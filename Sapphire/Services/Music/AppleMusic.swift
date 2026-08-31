//
//  AppleMusic.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-21
//

import Foundation
import AppKit
import MusicKit

// MARK: - Apple Music via MusicKit + MediaRemote

@MainActor
class AppleMusicManager {
    static let shared = AppleMusicManager()

    let musicKit = MusicKitAppleMusicManager.shared
    let privateAPI = AppleMusicPrivateAPIManager.shared

    private var cachedPlaylists: [SpotifyPlaylist] = []
    private var cachedPlaylistTracks: [String: [SpotifyTrack]] = [:]
    private var cachedUpNext: [QueueTrack] = []
    private var cachedIsLiked = false

    private init() {}

    func attach(mediaController: NativeMediaController) {
        musicKit.transport = mediaController
    }

    // MARK: - Authorization (delegated to MusicKit)

    var isMusicKitConfigured: Bool { musicKit.isConfigured }
    var isMusicKitAuthorized: Bool { musicKit.isAuthorized }
    var developerTokenPresent: Bool { musicKit.developerTokenPresent }

    func requestAuthorization() async {
        await musicKit.requestAuthorization()
    }

    func refreshMusicKitState() async {
        await musicKit.requestAuthorization()
        guard musicKit.isAuthorized else { return }
        await refreshPlaylists()
    }

    // MARK: - App state

    func isAppRunning() -> Bool {
        musicKit.isAppRunning()
    }

    func isPlaying() -> Bool {
        musicKit.transport?.activeClients.values.first?.payload.isPlaying ?? false
    }

    func getShuffleState() -> Bool {
        musicKit.currentShuffleState()
    }

    func getRepeatState() -> RepeatMode {
        musicKit.currentRepeatState()
    }

    func isTrackLiked() -> Bool {
        musicKit.currentTrackIsLiked()
    }

    // MARK: - Mode / rating actions

    func setShuffle(enabled: Bool) {
        musicKit.setShuffle(enabled: enabled)
    }

    func setRepeat(mode: RepeatMode) {
        musicKit.setRepeat(mode: mode)
    }

    func setLiked(isLiked: Bool) {
        cachedIsLiked = isLiked
    }

    // MARK: - Library

    func fetchPlaylists() -> [SpotifyPlaylist] {
        cachedPlaylists
    }

    func refreshPlaylists() async {
        cachedPlaylists = await musicKit.fetchLibraryPlaylists()
    }

    func fetchPlaylistTracks(playlistID: String) -> [SpotifyTrack] {
        cachedPlaylistTracks[playlistID] ?? []
    }

    func refreshPlaylistTracks(playlistID: String) async {
        cachedPlaylistTracks[playlistID] = await musicKit.fetchPlaylistTracks(playlistID: playlistID)
    }

    var librarySongs: [SpotifyTrack] = []

    func refreshLibrarySongs() async {
        librarySongs = await musicKit.fetchLibrarySongs()
    }

    func suggestedTracks(artistName: String) async -> [AppleMusicSong] {
        await privateAPI.fetchArtistCatalogTracks(artistName: artistName)
    }

    // MARK: - Search depth (music videos / stations / suggestions)

    func search(_ term: String) async -> AppleMusicSearchResults {
        await privateAPI.search(term)
    }

    func searchMusicVideos(_ term: String) async -> [AppleMusicMusicVideo] {
        await privateAPI.searchMusicVideos(term)
    }

    func searchStations(_ term: String) async -> [AppleMusicStation] {
        await privateAPI.searchStations(term)
    }

    func searchSuggestions(_ term: String) async -> [String] {
        await privateAPI.searchSuggestions(term)
    }

    // MARK: - Catalog reads

    func catalogSongs(ids: [String]) async -> [AppleMusicSong] {
        await privateAPI.fetchCatalogSongs(ids: ids)
    }

    func albumCharts(limit: Int = 12) async -> [AppleMusicAlbum] {
        await privateAPI.fetchAlbumCharts(limit: limit)
    }

    // MARK: - Library reads

    func recentlyAdded(limit: Int = 20) async -> [AppleMusicSong] {
        await privateAPI.fetchRecentlyAdded(limit: limit)
    }

    func libraryAlbums(limit: Int = 100) async -> [AppleMusicAlbum] {
        await privateAPI.fetchLibraryAlbums(limit: limit)
    }

    func libraryArtists(limit: Int = 100) async -> [AppleMusicArtist] {
        await privateAPI.fetchLibraryArtists(limit: limit)
    }

    func isInLibrary(songID: String) async -> Bool {
        await privateAPI.isInLibrary(songID: songID)
    }

    // MARK: - Library mutations

    @discardableResult
    func addToLibrary(songIDs: [String] = [], albumIDs: [String] = [], playlistIDs: [String] = []) async -> Bool {
        let ok = await privateAPI.addToLibrary(songIDs: songIDs, albumIDs: albumIDs, playlistIDs: playlistIDs)
        if ok { await refreshPlaylists() }
        return ok
    }

    @discardableResult
    func removeFromLibrary(songIDs: [String] = [], albumIDs: [String] = [], playlistIDs: [String] = []) async -> Bool {
        let ok = await privateAPI.removeFromLibrary(songIDs: songIDs, albumIDs: albumIDs, playlistIDs: playlistIDs)
        if ok { await refreshPlaylists() }
        return ok
    }

    func createPlaylist(name: String, description: String? = nil, songIDs: [String] = []) async -> String? {
        let id = await privateAPI.createPlaylist(name: name, description: description, songIDs: songIDs)
        if id != nil { await refreshPlaylists() }
        return id
    }

    @discardableResult
    func addTracksToPlaylist(songIDs: [String], playlistID: String) async -> Bool {
        await privateAPI.addTracksToPlaylist(songIDs: songIDs, playlistID: playlistID)
    }

    @discardableResult
    func deletePlaylist(playlistID: String) async -> Bool {
        let ok = await privateAPI.deletePlaylist(playlistID: playlistID)
        if ok { await refreshPlaylists() }
        return ok
    }

    // MARK: - Ratings

    func fetchRatings(songIDs: [String] = [], albumIDs: [String] = [], playlistIDs: [String] = []) async -> [AppleMusicRating] {
        await privateAPI.fetchRatings(songIDs: songIDs, albumIDs: albumIDs, playlistIDs: playlistIDs)
    }

    @discardableResult
    func setRating(value: Int, songID: String) async -> Bool {
        await privateAPI.setRating(value: value, songID: songID)
    }

    @discardableResult
    func deleteRating(songID: String) async -> Bool {
        await privateAPI.deleteRating(songID: songID)
    }

    // MARK: - Replay

    func latestReplay() async -> AppleMusicReplaySummary {
        await privateAPI.fetchLatestReplay()
    }

    // MARK: - Personalization & charts (feature parity)

    func recentlyPlayed(limit: Int = 25) async -> [AppleMusicSong] {
        await privateAPI.fetchRecentlyPlayed(limit: limit)
    }

    func charts(limit: Int = 25) async -> [AppleMusicSong] {
        await privateAPI.fetchCharts(limit: limit)
    }

    func forYouPlaylists(limit: Int = 10) async -> [AppleMusicPlaylist] {
        await privateAPI.fetchForYouPlaylists(limit: limit)
    }

    func heavyRotationAlbums(limit: Int = 15) async -> [AppleMusicAlbum] {
        await privateAPI.fetchHeavyRotation(limit: limit)
    }

    func artistTopTracks(artistID: String, limit: Int = 25) async -> [AppleMusicSong] {
        await privateAPI.fetchArtistTopTracks(artistID: artistID, limit: limit)
    }

    func artistAlbums(artistID: String, limit: Int = 25) async -> [AppleMusicAlbum] {
        await privateAPI.fetchArtistAlbums(artistID: artistID, limit: limit)
    }

    func albumTracks(albumID: String, limit: Int = 100) async -> [AppleMusicSong] {
        await privateAPI.fetchAlbumTracks(albumID: albumID, limit: limit)
    }

    // MARK: - Playback (specific item)

    @discardableResult
    func playTrack(persistentID: String) -> Bool {
        Task {
            await ensureAuthorized()
            _ = await musicKit.play(songIDs: [persistentID])
        }
        return true
    }

    func ensureAuthorized() async {
        await musicKit.ensureAuthorized()
    }

    func playAlbum(albumID: String) async -> Bool {
        await ensureAuthorized()
        let tracks = await privateAPI.fetchAlbumTracks(albumID: albumID)
        guard !tracks.isEmpty else { return false }
        setUpNext(for: tracks)
        return await musicKit.play(songIDs: tracks.map(\.id))
    }

    func playArtistTopTracks(artistID: String) async -> Bool {
        await ensureAuthorized()
        let tracks = await privateAPI.fetchArtistTopTracks(artistID: artistID)
        guard !tracks.isEmpty else { return false }
        setUpNext(for: tracks)
        return await musicKit.play(songIDs: tracks.map(\.id))
    }

    func playCatalogPlaylist(playlistID: String) async -> Bool {
        await ensureAuthorized()
        let tracks = await privateAPI.fetchCatalogPlaylistTracks(playlistID: playlistID)
        guard !tracks.isEmpty else { return false }
        setUpNext(for: tracks)
        return await musicKit.play(songIDs: tracks.map(\.id))
    }

    private func setUpNext(for songs: [AppleMusicSong]) {
        setCachedUpNext(
            songs.map { QueueTrack(id: $0.id, title: $0.title, artist: $0.artistName) }
        )
    }

    @discardableResult
    func playTrack(persistentID: String, inPlaylistPersistentID playlistID: String) -> Bool {
        guard let tracks = cachedPlaylistTracks[playlistID], !tracks.isEmpty else {
            return playTrack(persistentID: persistentID)
        }
        let id = persistentID
        Task {
            await ensureAuthorized()
            let ordered = tracks.contains { $0.id == id }
                ? reorder(tracks, startingAt: id)
                : tracks
            setUpNext(for: ordered, startingAt: id)
            _ = await musicKit.play(songIDs: ordered.map(\.id))
        }
        return true
    }

    private func reorder(_ tracks: [SpotifyTrack], startingAt id: String) -> [SpotifyTrack] {
        guard let index = tracks.firstIndex(where: { $0.id == id }), index > 0 else { return tracks }
        return Array(tracks[index...]) + Array(tracks[..<index])
    }

    @discardableResult
    func playPlaylist(persistentID: String) -> Bool {
        Task {
            await ensureAuthorized()
            await refreshPlaylistTracks(playlistID: persistentID)
            if let tracks = cachedPlaylistTracks[persistentID], !tracks.isEmpty {
                setUpNext(for: tracks)
                _ = await musicKit.play(songIDs: tracks.map(\.id))
            }
        }
        return true
    }

    func play(contextUri: String) async -> PlaybackResult {
        await ensureAuthorized()
        if let session = parseAppleMusicSongURL(contextUri) {
            return await musicKit.play(songIDs: [session]) ? .success : .failure(reason: "Could not play in Apple Music.")
        }
        let ok = await musicKit.playBySearch(term: contextUri)
        return ok ? .success : .failure(reason: "Could not play in Apple Music.")
    }

    func parseAppleMusicSongURL(_ urlString: String) -> String? {
        guard let url = URL(string: urlString),
              let host = url.host else { return nil }
        guard host == "music.apple.com" || host == "itunes.apple.com" else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" && $0 != "song" }
        if let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
           let songID = items.first(where: { $0.name == "i" })?.value {
            return songID
        }
        if let last = parts.last(where: { Int($0) != nil }) {
            return last
        }
        return nil
    }

    // MARK: - Up Next

    struct QueueTrack: Identifiable, Equatable {
        let id: String
        let title: String
        let artist: String
    }

    func fetchUpNextTracks() async -> [QueueTrack] {
        let live = musicKit.liveUpNext()
        if !live.isEmpty {
            let currentID = musicKit.currentLiveUpNextEntryID()
            let upcoming = live.filter { $0.id != currentID }
            let list = upcoming.isEmpty ? live : upcoming
            return list.map { QueueTrack(id: $0.songID ?? $0.id, title: $0.title, artist: $0.artist) }
        }
        return cachedUpNext
    }

    func setCachedUpNext(_ tracks: [QueueTrack]) {
        cachedUpNext = tracks
    }

    func setUpNext(for tracks: [SpotifyTrack], startingAt id: String? = nil) {
        var ordered = tracks
        if let id,
           let index = ordered.firstIndex(where: { $0.id == id }),
           index > 0 {
            ordered = Array(ordered[index...]) + Array(ordered[..<index])
        }
        setCachedUpNext(
            ordered.map {
                QueueTrack(id: $0.id, title: $0.name, artist: $0.artists.map(\.name).joined(separator: ", "))
            }
        )
    }

    func setUpNextFromSearch(_ songs: [AppleMusicSong]) {
        guard !songs.isEmpty else { return }
        setCachedUpNext(
            songs.map { QueueTrack(id: $0.id, title: $0.title, artist: $0.artistName) }
        )
    }

    func currentPlaylistName() -> String? {
        nil
    }

    // MARK: - Reveal

    func revealCurrentTrack() {
        musicKit.activateMusicApp()
    }
}

// MARK: - MusicKit song playback by catalog IDs

extension MusicKitAppleMusicManager {
    @discardableResult
    func play(songIDs: [String]) async -> Bool {
        await ensureAuthorized()
        guard isConfiguredAndAuthorized, !songIDs.isEmpty else {
            activateMusicApp()
            return false
        }

        var songs = await AppleMusicPrivateAPIManager.shared.fetchCatalogSongsForPlayback(ids: songIDs)
        if songs.isEmpty {
            for id in songIDs {
                if let song = await fetchCatalogSong(id: id) {
                    songs.append(song)
                }
                if songs.count >= 100 { break }
            }
        }

        guard !songs.isEmpty else {
            activateMusicApp()
            return false
        }
        return await play(songs: Array(songs.prefix(100)))
    }

    func fetchCatalogSong(id: String) async -> Song? {
        do {
            let request = MusicCatalogResourceRequest<Song>(matching: \.id, equalTo: MusicItemID(id))
            let response = try await request.response()
            return response.items.first
        } catch {
            return nil
        }
    }
}