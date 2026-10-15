//
//  AppleMusic.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-21
//

import Foundation
import AppKit
import MusicKit

// MARK: - Apple Music (MusicKit + Music.app scripting + MediaRemote)

@MainActor
final class AppleMusicManager {
    static let shared = AppleMusicManager()

    let musicKit = MusicKitAppleMusicManager.shared
    let musicApp = AppleMusicAppBridge.shared

    private var cachedPlaylists: [SpotifyPlaylist] = []
    private var cachedPlaylistTracks: [String: [SpotifyTrack]] = [:]
    private var cachedIsLiked = false
    private var modeCalibration = PlayerModeCalibration()

    private init() {}

    func attach(mediaController: NativeMediaController) {
        musicKit.transport = mediaController
    }

    // MARK: - Authorization

    var isMusicKitConfigured: Bool {
        let status = MusicAuthorization.currentStatus
        return status != .denied && status != .restricted
    }

    var isMusicKitAuthorized: Bool { musicKit.isAuthorized }

    func requestAuthorization() async {
        await musicKit.requestAuthorization()
    }

    func ensureAuthorized() async {
        await musicKit.ensureAuthorized()
    }

    func refreshMusicKitState() async {
        guard await musicKit.ensureAuthorized() else { return }
        await refreshPlaylists()
    }

    var diagnosticsSummary: String { musicKit.diagnosticsSummary }

    // MARK: - Source state

    var isInAppPlaybackActive: Bool { musicKit.isInAppPlaybackActive }

    func isAppRunning() -> Bool {
        musicApp.isRunning || musicKit.isInAppPlaybackActive
    }

    func isPlaying() -> Bool {
        musicKit.transport?.activeClients.values.first?.payload.isPlaying ?? false
    }

    func isTrackLiked() -> Bool {
        cachedIsLiked
    }

    func playerModes() async -> (shuffle: Bool, repeat: RepeatMode) {
        if musicKit.isInAppPlaybackActive {
            return (musicKit.inAppShuffle, musicKit.inAppRepeat)
        }
        let payload = musicKit.transport?.activeClients.values.first?.payload
        let payloadShuffle = payload?.shuffleMode
        let payloadRepeat = payload?.repeatMode
        if let modes = modeCalibration.modes(shuffle: payloadShuffle, repeat: payloadRepeat) {
            return modes
        }

        async let shuffle = musicApp.shuffleEnabled()
        async let repeatMode = musicApp.repeatMode()
        let scriptShuffle = await shuffle
        let scriptRepeat = await repeatMode
        if let scriptShuffle, let scriptRepeat, let payloadShuffle, let payloadRepeat {
            modeCalibration.observe(
                shuffle: payloadShuffle,
                repeat: payloadRepeat,
                actualShuffle: scriptShuffle,
                actualRepeat: scriptRepeat
            )
        }
        let fallbackRepeat: RepeatMode = {
            switch payloadRepeat {
            case 1: return .track
            case 2: return .context
            default: return .off
            }
        }()
        return (scriptShuffle ?? (payloadShuffle == 1), scriptRepeat ?? fallbackRepeat)
    }

    // MARK: - Transport (in-app player only; Music.app goes through MediaRemote)

    func play() { musicKit.inAppPlay() }
    func pause() { musicKit.inAppPause() }
    func nextTrack() { musicKit.inAppNext() }
    func previousTrack() { musicKit.inAppPrevious() }
    func seek(to seconds: TimeInterval) { musicKit.inAppSeek(to: seconds) }

    func setShuffle(enabled: Bool) {
        if musicKit.isInAppPlaybackActive {
            musicKit.setInAppShuffle(enabled)
            return
        }
        Task { _ = await musicApp.setShuffle(enabled) }
    }

    func setRepeat(mode: RepeatMode) {
        if musicKit.isInAppPlaybackActive {
            musicKit.setInAppRepeat(mode)
            return
        }
        Task { _ = await musicApp.setRepeat(mode) }
    }

    // MARK: - Favourite (love) / dislike

    func setLiked(isLiked: Bool) {
        cachedIsLiked = isLiked
    }

    func setFavorite(_ favorited: Bool, title: String?, artist: String?) async -> Bool {
        let ok = await musicApp.setFavorited(favorited, title: title, artist: artist)
        if ok { cachedIsLiked = favorited }
        return ok
    }

    func setDisliked(_ disliked: Bool) async -> Bool {
        await musicApp.setDisliked(disliked)
    }

    // MARK: - Now playing enrichment

    func nowPlayingDetails(title: String, artist: String, album: String?, includeRelated: Bool) async -> AppleMusicNowPlayingDetails {
        let readsMusicApp = !musicKit.isInAppPlaybackActive
        async let catalog = musicKit.nowPlayingDetails(title: title, artist: artist, album: album, includeRelated: includeRelated)
        async let appTrack = readsMusicApp ? musicApp.currentTrack() : nil
        var details = await catalog
        if let track = await appTrack, track.title == title {
            details.isFavorited = track.favorited
            details.isDisliked = track.disliked
            if track.playedCount > 0 { details.playCount = track.playedCount }
            if track.isLibraryTrack { details.isInLibrary = true }
        }
        cachedIsLiked = details.isFavorited ?? false
        return details
    }

    func suggestedTracks(artistName: String) async -> [AppleMusicSong] {
        await musicKit.songsByArtist(named: artistName)
    }

    // MARK: - Library

    func fetchPlaylists() -> [SpotifyPlaylist] {
        cachedPlaylists
    }

    func refreshPlaylists() async {
        let playlists = await musicKit.libraryPlaylists()
        cachedPlaylists = playlists.map { playlist in
            SpotifyPlaylist(
                id: playlist.id,
                name: playlist.name,
                uri: playlist.id,
                images: playlist.artworkURL.map { [SpotifyImage(url: $0.absoluteString)] } ?? [],
                owner: SpotifyUserSimple(id: "apple_music", displayName: playlist.curatorName ?? "Me", images: nil),
                collaborators: nil
            )
        }
    }

    func fetchPlaylistTracks(playlistID: String) -> [SpotifyTrack] {
        cachedPlaylistTracks[playlistID] ?? []
    }

    func refreshPlaylistTracks(playlistID: String) async {
        let songs = await musicKit.libraryPlaylistTracks(id: playlistID, refresh: true)
        for song in songs {
            if let catalogID = song.catalogID { catalogIDs[song.id] = catalogID }
        }
        cachedPlaylistTracks[playlistID] = songs.map(spotifyTrack)
    }

    private var catalogIDs: [String: String] = [:]

    private func resolvedCatalogIDs(_ ids: [String]) -> [String] {
        ids.map { catalogIDs[$0] ?? $0 }
    }

    private func spotifyTrack(_ song: AppleMusicSong) -> SpotifyTrack {
        SpotifyTrack(
            id: song.id,
            name: song.title,
            uri: song.id,
            album: SpotifyAlbum(name: song.albumTitle ?? "", images: song.artworkURL.map { [SpotifyImage(url: $0.absoluteString)] } ?? []),
            artists: song.artistName.isEmpty ? [] : [SpotifyArtist(name: song.artistName)],
            durationMs: song.duration.map { Int($0 * 1000) } ?? 0,
            popularity: nil
        )
    }

    func librarySongs(limit: Int = 500) async -> [AppleMusicSong] {
        await musicKit.librarySongs(limit: limit)
    }

    func recentlyAdded(limit: Int = 20) async -> [AppleMusicSong] {
        await musicKit.recentlyAdded(limit: limit)
    }

    func mostPlayed(limit: Int = 25) async -> [AppleMusicSong] {
        await musicKit.mostPlayed(limit: limit)
    }

    func libraryAlbums(limit: Int = 100) async -> [AppleMusicAlbum] {
        await musicKit.libraryAlbums(limit: limit)
    }

    func libraryArtists(limit: Int = 100) async -> [AppleMusicArtist] {
        await musicKit.libraryArtists(limit: limit)
    }

    @discardableResult
    func addToLibrary(song: AppleMusicSong) async -> Bool {
        if !musicKit.isInAppPlaybackActive,
           let current = await musicApp.currentTrack(),
           AppleMusicMapper.matchKey(current.title) == AppleMusicMapper.matchKey(song.title) {
            return await musicApp.addCurrentTrackToLibrary()
        }
        musicApp.open(url: song.url)
        return false
    }

    @discardableResult
    func addCurrentTrackToLibrary() async -> Bool {
        await musicApp.addCurrentTrackToLibrary()
    }

    func userPlaylistNames() async -> [String] {
        await musicApp.userPlaylistNames()
    }

    @discardableResult
    func addCurrentTrack(toPlaylistNamed name: String) async -> Bool {
        await musicApp.addCurrentTrack(toPlaylistNamed: name)
    }

    @discardableResult
    func createPlaylist(name: String, addingCurrentTrack: Bool) async -> Bool {
        let ok = await musicApp.createPlaylist(named: name, addingCurrentTrack: addingCurrentTrack)
        if ok { await refreshPlaylists() }
        return ok
    }

    // MARK: - Catalog

    func search(_ term: String) async -> AppleMusicSearchResults {
        await musicKit.search(term)
    }

    func searchSuggestions(_ term: String) async -> [String] {
        await musicKit.searchSuggestions(term)
    }

    func catalogSongs(ids: [String]) async -> [AppleMusicSong] {
        await musicKit.catalogSongs(ids: ids)
    }

    func charts(genreID: String? = nil) async -> AppleMusicChartSet {
        await musicKit.charts(genreID: genreID)
    }

    func topGenres() async -> [AppleMusicGenre] {
        await musicKit.topGenres()
    }

    func artistDetail(id: String) async -> AppleMusicArtistDetail? {
        await musicKit.artistDetail(id: id)
    }

    func albumDetail(id: String) async -> AppleMusicAlbumDetail? {
        await musicKit.albumDetail(id: id)
    }

    func playlistDetail(id: String, isLibrary: Bool) async -> AppleMusicPlaylistDetail? {
        await musicKit.playlistDetail(id: id, isLibrary: isLibrary)
    }

    func findArtist(named name: String) async -> AppleMusicArtist? {
        await musicKit.findArtist(named: name)
    }

    func findAlbum(title: String, artist: String) async -> AppleMusicAlbum? {
        await musicKit.findAlbum(title: title, artist: artist)
    }

    func artistTopTracks(artistID: String) async -> [AppleMusicSong] {
        await musicKit.artistTopSongs(artistID: artistID)
    }

    func artistAlbums(artistID: String) async -> [AppleMusicAlbum] {
        await musicKit.artistAlbums(artistID: artistID)
    }

    func albumTracks(albumID: String) async -> [AppleMusicSong] {
        await musicKit.albumTracks(albumID: albumID)
    }

    // MARK: - Personalization

    func recommendations() async -> [AppleMusicRecommendationShelf] {
        await musicKit.recommendations()
    }

    func recentlyPlayed(limit: Int = 25) async -> [AppleMusicSong] {
        await musicKit.recentlyPlayedSongs(limit: limit)
    }

    func recentlyPlayedContainers(limit: Int = 15) async -> [AppleMusicShelfItem] {
        await musicKit.recentlyPlayedContainers(limit: limit)
    }

    func heavyRotationAlbums(limit: Int = 15) async -> [AppleMusicAlbum] {
        await musicKit.heavyRotation(limit: limit)
    }

    func latestReplay() async -> AppleMusicReplaySummary {
        await musicKit.replay()
    }

    // MARK: - Playback

    let systemQueue = AppleMusicSystemQueue.shared

    private static let maxQueuedSongs = 60

    private func playInMusicApp(_ ids: [String]) async -> Bool {
        let catalogIDs = Array(ids.filter(AppleMusicSystemQueue.isCatalogID).prefix(Self.maxQueuedSongs))
        guard !catalogIDs.isEmpty, systemQueue.isAvailable, await ensureMusicAppRunning() else { return false }
        musicKit.relinquishInAppPlaybackNow()
        return await systemQueue.playNow(storeIDs: catalogIDs)
    }

    private func play(songIDs rawIDs: [String], startingAt rawStartID: String? = nil, shuffled: Bool = false) async -> Bool {
        var ordered = resolvedCatalogIDs(rawIDs)
        let startID = rawStartID.map { catalogIDs[$0] ?? $0 }
        if let startID, let index = ordered.firstIndex(of: startID) {
            ordered = Array(ordered[index...])
        }
        if shuffled { ordered.shuffle() }
        if await playInMusicApp(ordered) { return true }
        return await musicKit.play(songIDs: ordered, startingAt: shuffled ? nil : startID)
    }

    private func ensureMusicAppRunning() async -> Bool {
        if musicApp.isRunning { return true }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: AppleMusicAppBridge.bundleID) else { return false }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.hides = true
        _ = try? await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        for _ in 0..<20 {
            if musicApp.isRunning {
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                return true
            }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        return false
    }

    @discardableResult
    func playTrack(persistentID: String) -> Bool {
        Task { _ = await play(songIDs: [persistentID]) }
        return true
    }

    func play(song: AppleMusicSong, within songs: [AppleMusicSong] = []) async -> Bool {
        let list = songs.contains(song) ? songs : [song]
        return await play(songIDs: list.map { $0.catalogID ?? $0.id }, startingAt: song.catalogID ?? song.id)
    }

    func playAlbum(albumID: String, startingAt songID: String? = nil, shuffled: Bool = false) async -> Bool {
        let tracks = await musicKit.albumTracks(albumID: albumID)
        if !tracks.isEmpty, await play(songIDs: tracks.map(\.id), startingAt: songID, shuffled: shuffled) {
            return true
        }
        let ok = await musicKit.playAlbum(albumID: albumID, startingAt: songID)
        if ok, shuffled { musicKit.setInAppShuffle(true) }
        return ok
    }

    func playArtistTopTracks(artistID: String) async -> Bool {
        let tracks = await musicKit.artistTopSongs(artistID: artistID)
        if !tracks.isEmpty, await playInMusicApp(tracks.map(\.id)) { return true }
        return await musicKit.playArtistTopSongs(artistID: artistID)
    }

    func playCatalogPlaylist(playlistID: String, shuffled: Bool = false) async -> Bool {
        if let detail = await musicKit.playlistDetail(id: playlistID, isLibrary: false), !detail.tracks.isEmpty,
           await play(songIDs: detail.tracks.map(\.id), shuffled: shuffled) {
            return true
        }
        return await musicKit.playPlaylist(id: playlistID, isLibrary: false, shuffled: shuffled)
    }

    func playPlaylist(_ playlist: AppleMusicPlaylist, startingAt songID: String? = nil, shuffled: Bool = false) async -> Bool {
        guard playlist.isLibrary else {
            if let songID, let detail = await musicKit.playlistDetail(id: playlist.id, isLibrary: false),
               await play(songIDs: detail.tracks.map(\.id), startingAt: songID) {
                return true
            }
            if songID == nil, await playCatalogPlaylist(playlistID: playlist.id, shuffled: shuffled) { return true }
            return await musicKit.playPlaylist(id: playlist.id, isLibrary: false, startingAt: songID, shuffled: shuffled)
        }
        return await playLibraryPlaylist(id: playlist.id, name: playlist.name, startingAt: songID, shuffled: shuffled)
    }

    private func playLibraryPlaylist(id: String, name: String?, startingAt songID: String?, shuffled: Bool) async -> Bool {
        let startTitle: String? = songID.flatMap { songID in
            cachedPlaylistTracks[id]?.first { $0.id == songID }?.name
        }
        if let name, !name.isEmpty {
            musicKit.relinquishInAppPlaybackNow()
            if await musicApp.playUserPlaylist(named: name, startingAtTitle: startTitle, shuffled: shuffled) { return true }
        }
        return await musicKit.playPlaylist(id: id, isLibrary: true, startingAt: songID, shuffled: shuffled)
    }

    func playStation(stationID: String) async -> Bool {
        await musicKit.playStation(id: stationID)
    }

    func playSongStation(songID: String) async -> Bool {
        await musicKit.playSongStation(songID: songID)
    }

    func playArtistStation(artistID: String) async -> Bool {
        await musicKit.playArtistStation(artistID: artistID)
    }

    func play(shelfItem: AppleMusicShelfItem) async -> Bool {
        switch shelfItem {
        case .album(let album): return await playAlbum(albumID: album.id)
        case .playlist(let playlist): return await playPlaylist(playlist)
        case .station(let station): return await playStation(stationID: station.id)
        }
    }

    func playNext(songIDs: [String]) async -> Bool {
        await enqueue(songIDs, position: .next)
    }

    func playLater(songIDs: [String]) async -> Bool {
        await enqueue(songIDs, position: .later)
    }

    private func enqueue(_ rawIDs: [String], position: AppleMusicSystemQueue.Position) async -> Bool {
        let ids = resolvedCatalogIDs(rawIDs)
        if musicKit.isInAppPlaybackActive {
            return await musicKit.enqueue(songIDs: ids, position: position == .next ? .next : .last)
        }
        if systemQueue.isAvailable, musicApp.isRunning,
           await systemQueue.insert(storeIDs: ids, position: position) {
            return true
        }
        return await play(songIDs: ids)
    }

    @discardableResult
    func playTrack(persistentID: String, inPlaylistPersistentID playlistID: String) -> Bool {
        let name = cachedPlaylists.first { $0.id == playlistID }?.name
        Task { _ = await playLibraryPlaylist(id: playlistID, name: name, startingAt: persistentID, shuffled: false) }
        return true
    }

    @discardableResult
    func playPlaylist(persistentID: String, shuffled: Bool = false) -> Bool {
        let name = cachedPlaylists.first { $0.id == persistentID }?.name
        Task { _ = await playLibraryPlaylist(id: persistentID, name: name, startingAt: nil, shuffled: shuffled) }
        return true
    }

    func play(contextUri: String) async -> PlaybackResult {
        if let songID = parseAppleMusicSongURL(contextUri) {
            return await play(songIDs: [songID]) ? .success : .failure(reason: "Could not play in Apple Music.")
        }
        let results = await musicKit.search(contextUri, limit: 5)
        if let first = results.songs.first, await play(songIDs: [first.id]) { return .success }
        return .failure(reason: "Could not play in Apple Music.")
    }

    func parseAppleMusicSongURL(_ urlString: String) -> String? {
        guard let url = URL(string: urlString), let host = url.host else { return nil }
        guard host == "music.apple.com" || host == "itunes.apple.com" else { return nil }
        if let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
           let songID = items.first(where: { $0.name == "i" })?.value {
            return songID
        }
        return url.pathComponents.last(where: { Int($0) != nil })
    }

    // MARK: - Up Next

    struct QueueTrack: Identifiable, Equatable {
        enum Source: Equatable {
            case inAppQueue(entryID: String)
            case musicAppQueue(contentItemID: String)
            case musicAppPlaylist(persistentID: String)
        }

        let id: String
        let title: String
        let artist: String
        var artworkURL: URL? = nil
        var catalogID: String? = nil
        let source: Source
    }

    private var queueArtworkCache: [String: URL] = [:]

    func fetchUpNextTracks() async -> [QueueTrack] {
        if musicKit.isInAppPlaybackActive {
            return musicKit.inAppUpNext().map {
                QueueTrack(id: $0.id, title: $0.title, artist: $0.artist, artworkURL: $0.artworkURL,
                           catalogID: $0.songID, source: .inAppQueue(entryID: $0.id))
            }
        }
        guard musicApp.isRunning else { return [] }
        if systemQueue.isAvailable, let snapshot = await systemQueue.snapshot() {
            let entries = snapshot.upNext
            await loadQueueArtwork(for: entries.map(\.storeID))
            return entries.map { entry in
                QueueTrack(
                    id: entry.id,
                    title: entry.title,
                    artist: entry.artist,
                    artworkURL: queueArtworkCache[entry.storeID],
                    catalogID: entry.storeID.isEmpty ? nil : entry.storeID,
                    source: .musicAppQueue(contentItemID: entry.id)
                )
            }
        }
        return await musicApp.upcomingTracks().map {
            QueueTrack(id: $0.persistentID, title: $0.title, artist: $0.artist, source: .musicAppPlaylist(persistentID: $0.persistentID))
        }
    }

    private func loadQueueArtwork(for storeIDs: [String]) async {
        let missing = Array(Set(storeIDs.filter { !$0.isEmpty && queueArtworkCache[$0] == nil }))
        guard !missing.isEmpty, musicKit.isAuthorized else { return }
        for song in await musicKit.catalogSongs(ids: missing) {
            if let url = song.artworkURL { queueArtworkCache[song.id] = url }
        }
        if queueArtworkCache.count > 800 { queueArtworkCache.removeAll() }
    }

    @discardableResult
    func playQueueTrack(_ track: QueueTrack) async -> Bool {
        switch track.source {
        case .inAppQueue(let entryID): return await musicKit.jumpToQueueEntry(id: entryID)
        case .musicAppQueue(let itemID): return await systemQueue.playItem(id: itemID)
        case .musicAppPlaylist(let persistentID): return await musicApp.playTrackInCurrentPlaylist(persistentID: persistentID)
        }
    }

    var canEditQueue: Bool {
        !musicKit.isInAppPlaybackActive && systemQueue.isAvailable
    }

    func canRemove(_ track: QueueTrack) -> Bool {
        if case .musicAppQueue = track.source { return true }
        return false
    }

    @discardableResult
    func removeFromQueue(_ track: QueueTrack) async -> Bool {
        guard case .musicAppQueue(let itemID) = track.source else { return false }
        return await systemQueue.removeItem(id: itemID)
    }

    @discardableResult
    func clearUpNext() async -> Bool {
        guard canEditQueue else { return false }
        return await systemQueue.clearUpNext()
    }

    func currentPlaylistName() -> String? {
        nil
    }

    // MARK: - Reveal

    func revealCurrentTrack() {
        if musicKit.isInAppPlaybackActive {
            musicApp.open(url: musicKit.inAppCurrentSongURL)
            return
        }
        Task { await musicApp.revealCurrentTrack() }
    }

    func open(url: URL?) {
        musicApp.open(url: url)
    }
}