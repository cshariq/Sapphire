//
//  MusicKitAppleMusicManager.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-30
//

import Foundation
import Combine
import AppKit
import MusicKit
import os

enum AppleMusicPlaybackIdentity {
    private static let state = OSAllocatedUnfairLock(initialState: false)

    static var isInAppPlaybackActive: Bool {
        state.withLock { $0 }
    }

    static func setInAppPlaybackActive(_ active: Bool) {
        state.withLock { $0 = active }
    }

    static let hostBundleID = Bundle.main.bundleIdentifier
}

@MainActor
@Observable
final class MusicKitAppleMusicManager {
    static let shared = MusicKitAppleMusicManager()

    // MARK: - Published state
    private(set) var account = AppleMusicAccountState()
    private(set) var isInAppPlaybackActive = false
    private(set) var inAppQueueRevision = 0

    @ObservationIgnored weak var transport: NativeMediaController?

    @ObservationIgnored private var subscriptionTask: Task<Void, Never>?
    @ObservationIgnored private var playerStateCancellable: AnyCancellable?
    @ObservationIgnored private var queueCancellable: AnyCancellable?
    @ObservationIgnored private var hasSetQueue = false
    @ObservationIgnored private var inAppStartedAt: Date = .distantPast

    @ObservationIgnored private var libraryPlaylistCache: [String: Playlist] = [:]
    @ObservationIgnored private var libraryPlaylistTracksCache: [String: MusicItemCollection<Track>] = [:]
    @ObservationIgnored private var nowPlayingCache: (key: String, details: AppleMusicNowPlayingDetails)?

    private let log = Logger(subsystem: "com.cshariq.sapphire", category: "AppleMusic")

    private init() {
        account.authorization = MusicAuthorization.currentStatus
        if account.isAuthorized { startSubscriptionUpdates() }
    }

    var isAuthorized: Bool { account.isAuthorized }

    private var player: ApplicationMusicPlayer { .shared }

    // MARK: - Authorization & subscription

    func requestAuthorization() async {
        let status = await MusicAuthorization.request()
        account.authorization = status
        if status == .authorized {
            startSubscriptionUpdates()
        } else {
            account.lastError = status == .denied
                ? "Apple Music access is off for Sapphire. Turn it on in System Settings → Privacy & Security → Media & Apple Music."
                : nil
        }
    }

    func refreshAuthorizationStatus() {
        let current = MusicAuthorization.currentStatus
        guard current != account.authorization else { return }
        account.authorization = current
        if current == .authorized { startSubscriptionUpdates() }
    }

    @discardableResult
    func ensureAuthorized() async -> Bool {
        if account.isAuthorized { return true }
        let current = MusicAuthorization.currentStatus
        if current == .authorized {
            account.authorization = current
            startSubscriptionUpdates()
            return true
        }
        guard current == .notDetermined else {
            account.authorization = current
            return false
        }
        await requestAuthorization()
        return account.isAuthorized
    }

    private func startSubscriptionUpdates() {
        guard subscriptionTask == nil else { return }
        subscriptionTask = Task { @MainActor [weak self] in
            if let current = try? await MusicSubscription.current {
                self?.apply(current)
            }
            self?.account.countryCode = try? await MusicDataRequest.currentCountryCode
            for await subscription in MusicSubscription.subscriptionUpdates {
                guard let self else { return }
                self.apply(subscription)
            }
        }
    }

    private func apply(_ subscription: MusicSubscription) {
        account.canPlayCatalogContent = subscription.canPlayCatalogContent
        account.canBecomeSubscriber = subscription.canBecomeSubscriber
        account.hasCloudLibraryEnabled = subscription.hasCloudLibraryEnabled
    }

    var diagnosticsSummary: String {
        var lines: [String] = []
        switch account.authorization {
        case .authorized: lines.append("Access: granted")
        case .notDetermined: lines.append("Access: not requested yet")
        case .denied: lines.append("Access: denied — enable Sapphire under Privacy & Security → Media & Apple Music")
        case .restricted: lines.append("Access: restricted on this Mac")
        @unknown default: lines.append("Access: \(account.authorization.rawValue)")
        }
        if account.isAuthorized {
            lines.append(account.canPlayCatalogContent
                ? "Subscription: active\(account.countryCode.map { " (\($0.uppercased()))" } ?? "")"
                : "Subscription: none — catalog playback unavailable")
            lines.append("iCloud Music Library: \(account.hasCloudLibraryEnabled ? "on" : "off")")
        }
        if let error = account.lastError { lines.append(error) }
        return lines.joined(separator: "\n")
    }

    private func record(_ error: Error, context: String) {
        log.error("\(context, privacy: .public) failed: \(String(describing: error), privacy: .public)")
        if let tokenError = error as? MusicTokenRequestError {
            switch tokenError {
            case .developerTokenRequestFailed:
                account.lastError = "MusicKit couldn't get a developer token. Enable the MusicKit App Service for com.cshariq.sapphire in the Apple Developer portal and re-sign."
            case .userNotSignedIn:
                account.lastError = "Sign in to Apple Music in the Music app."
            case .privacyAcknowledgementRequired:
                account.lastError = "Open the Music app once and accept Apple Music's privacy notice."
            case .permissionDenied:
                account.lastError = "Apple Music access is off for Sapphire."
            default:
                account.lastError = tokenError.localizedDescription
            }
        } else if let dataError = error as? MusicDataRequest.Error {
            account.lastError = "\(dataError.title) (\(dataError.status))"
        }
    }

    private func clearError() {
        if account.lastError != nil { account.lastError = nil }
    }

    // MARK: - Catalog search

    func search(_ term: String, limit: Int = 15) async -> AppleMusicSearchResults {
        let term = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty, await ensureAuthorized() else { return AppleMusicSearchResults() }

        var results = AppleMusicSearchResults()
        do {
            var request = MusicCatalogSearchRequest(
                term: term,
                types: [Song.self, Album.self, Artist.self, Playlist.self, Station.self, MusicVideo.self]
            )
            request.limit = limit
            request.includeTopResults = true
            let response = try await request.response()
            results.songs = response.songs.map(AppleMusicMapper.song)
            results.albums = response.albums.map(AppleMusicMapper.album)
            results.artists = response.artists.map(AppleMusicMapper.artist)
            results.playlists = response.playlists.map { AppleMusicMapper.playlist($0) }
            results.stations = response.stations.map(AppleMusicMapper.station)
            results.musicVideos = response.musicVideos.map(AppleMusicMapper.musicVideo)
            results.topResults = response.topResults.compactMap { top in
                switch top {
                case .song(let song): return .song(AppleMusicMapper.song(song))
                case .album(let album): return .album(AppleMusicMapper.album(album))
                case .artist(let artist): return .artist(AppleMusicMapper.artist(artist))
                case .playlist(let playlist): return .playlist(AppleMusicMapper.playlist(playlist))
                case .station(let station): return .station(AppleMusicMapper.station(station))
                default: return nil
                }
            }
            clearError()
        } catch {
            record(error, context: "Catalog search")
        }

        do {
            var libraryRequest = MusicLibrarySearchRequest(term: term, types: [Song.self])
            libraryRequest.limit = 5
            let libraryResponse = try await libraryRequest.response()
            results.librarySongs = libraryResponse.songs.map(AppleMusicMapper.song)
        } catch {
            log.debug("Library search failed: \(String(describing: error), privacy: .public)")
        }
        return results
    }

    func searchSuggestions(_ term: String, limit: Int = 8) async -> [String] {
        let term = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard term.count >= 2, await ensureAuthorized() else { return [] }
        do {
            var request = MusicCatalogSearchSuggestionsRequest(term: term)
            request.limit = limit
            let response = try await request.response()
            return response.suggestions.map(\.displayTerm)
        } catch {
            return []
        }
    }

    // MARK: - Charts & genres

    func charts(genreID: String? = nil, limit: Int = 25) async -> AppleMusicChartSet {
        guard await ensureAuthorized() else { return AppleMusicChartSet() }
        var genre: Genre?
        if let genreID {
            genre = try? await MusicCatalogResourceRequest<Genre>(matching: \.id, equalTo: MusicItemID(genreID))
                .response().items.first
        }
        var set = AppleMusicChartSet()
        do {
            var request = MusicCatalogChartsRequest(
                genre: genre,
                kinds: [.mostPlayed, .dailyGlobalTop, .cityTop],
                types: [Song.self, Album.self, Playlist.self, MusicVideo.self]
            )
            request.limit = limit
            let response = try await request.response()
            set.songs = response.songCharts.first { $0.kind == .mostPlayed }?.items.map(AppleMusicMapper.song) ?? []
            set.albums = response.albumCharts.first { $0.kind == .mostPlayed }?.items.map(AppleMusicMapper.album) ?? []
            set.musicVideos = response.musicVideoCharts.first { $0.kind == .mostPlayed }?.items.map(AppleMusicMapper.musicVideo) ?? []
            set.playlists = response.playlistCharts.first { $0.kind == .mostPlayed }?.items.map { AppleMusicMapper.playlist($0) } ?? []
            set.dailyGlobalTop = response.playlistCharts.first { $0.kind == .dailyGlobalTop }?.items.map { AppleMusicMapper.playlist($0) } ?? []
            set.cityTop = response.playlistCharts.first { $0.kind == .cityTop }?.items.map { AppleMusicMapper.playlist($0) } ?? []
            clearError()
        } catch {
            record(error, context: "Charts")
        }
        return set
    }

    func topGenres() async -> [AppleMusicGenre] {
        guard await ensureAuthorized() else { return [] }
        do {
            let response = try await MusicCatalogResourceRequest<Genre>().response()
            return response.items
                .filter { $0.parent != nil || $0.name != "Music" }
                .map { AppleMusicGenre(id: $0.id.rawValue, name: $0.name) }
        } catch {
            return []
        }
    }

    // MARK: - Catalog resources

    private func catalogSongs(_ ids: [String], properties: [PartialMusicAsyncProperty<Song>] = []) async -> [Song] {
        let ids = ids.filter { !$0.isEmpty }
        guard !ids.isEmpty else { return [] }
        var collected: [Song] = []
        for chunk in stride(from: 0, to: ids.count, by: 100).map({ Array(ids[$0..<min($0 + 100, ids.count)]) }) {
            var request = MusicCatalogResourceRequest<Song>(matching: \.id, memberOf: chunk.map { MusicItemID($0) })
            request.properties = properties
            if let items = try? await request.response().items {
                collected.append(contentsOf: items)
            }
        }
        let order = Dictionary(ids.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        return collected.sorted { (order[$0.id.rawValue] ?? .max) < (order[$1.id.rawValue] ?? .max) }
    }

    private func librarySongs(_ ids: [String]) async -> [Song] {
        guard !ids.isEmpty else { return [] }
        var request = MusicLibraryRequest<Song>()
        request.filter(matching: \.id, memberOf: ids.map { MusicItemID($0) })
        guard let items = try? await request.response().items else { return [] }
        let order = Dictionary(ids.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        return items.sorted { (order[$0.id.rawValue] ?? .max) < (order[$1.id.rawValue] ?? .max) }
    }

    private func playableSongs(_ ids: [String]) async -> [Song] {
        let catalog = await catalogSongs(ids)
        let found = Set(catalog.map(\.id.rawValue))
        let missing = ids.filter { !found.contains($0) }
        guard !missing.isEmpty else { return catalog }
        let library = await librarySongs(missing)
        let all = catalog + library
        let order = Dictionary(ids.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        return all.sorted { (order[$0.id.rawValue] ?? .max) < (order[$1.id.rawValue] ?? .max) }
    }

    func catalogSongs(ids: [String]) async -> [AppleMusicSong] {
        guard await ensureAuthorized() else { return [] }
        return await catalogSongs(ids).map(AppleMusicMapper.song)
    }

    private func catalogAlbum(_ id: String, properties: [PartialMusicAsyncProperty<Album>] = []) async -> Album? {
        var request = MusicCatalogResourceRequest<Album>(matching: \.id, equalTo: MusicItemID(id))
        request.properties = properties
        do {
            return try await request.response().items.first
        } catch {
            record(error, context: "Album \(id)")
            return nil
        }
    }

    private func catalogArtist(_ id: String, properties: [PartialMusicAsyncProperty<Artist>] = []) async -> Artist? {
        var request = MusicCatalogResourceRequest<Artist>(matching: \.id, equalTo: MusicItemID(id))
        request.properties = properties
        do {
            return try await request.response().items.first
        } catch {
            record(error, context: "Artist \(id)")
            return nil
        }
    }

    private func catalogPlaylist(_ id: String, properties: [PartialMusicAsyncProperty<Playlist>] = []) async -> Playlist? {
        var request = MusicCatalogResourceRequest<Playlist>(matching: \.id, equalTo: MusicItemID(id))
        request.properties = properties
        return try? await request.response().items.first
    }

    private func catalogStation(_ id: String) async -> Station? {
        try? await MusicCatalogResourceRequest<Station>(matching: \.id, equalTo: MusicItemID(id)).response().items.first
    }

    // MARK: - Artist / album / playlist pages

    func artistDetail(id: String) async -> AppleMusicArtistDetail? {
        guard await ensureAuthorized() else { return nil }
        guard let artist = await catalogArtist(id, properties: [
            .topSongs, .latestRelease, .fullAlbums, .singles, .liveAlbums, .compilationAlbums,
            .appearsOnAlbums, .featuredPlaylists, .similarArtists, .topMusicVideos, .station
        ]) else { return nil }

        var detail = AppleMusicArtistDetail(artist: AppleMusicMapper.artist(artist))
        detail.bio = artist.editorialNotes?.standard ?? artist.editorialNotes?.short
        detail.topSongs = artist.topSongs?.map(AppleMusicMapper.song) ?? []
        detail.latestRelease = artist.latestRelease.map(AppleMusicMapper.album)
        detail.albums = artist.fullAlbums?.map(AppleMusicMapper.album) ?? []
        detail.singles = artist.singles?.map(AppleMusicMapper.album) ?? []
        detail.liveAlbums = artist.liveAlbums?.map(AppleMusicMapper.album) ?? []
        detail.compilations = artist.compilationAlbums?.map(AppleMusicMapper.album) ?? []
        detail.appearsOn = artist.appearsOnAlbums?.map(AppleMusicMapper.album) ?? []
        detail.featuredPlaylists = artist.featuredPlaylists?.map { AppleMusicMapper.playlist($0) } ?? []
        detail.similarArtists = artist.similarArtists?.map(AppleMusicMapper.artist) ?? []
        detail.topMusicVideos = artist.topMusicVideos?.map(AppleMusicMapper.musicVideo) ?? []
        detail.station = artist.station.map(AppleMusicMapper.station)
        clearError()
        return detail
    }

    func albumDetail(id: String) async -> AppleMusicAlbumDetail? {
        guard await ensureAuthorized() else { return nil }
        guard let album = await catalogAlbum(id, properties: [
            .tracks, .relatedAlbums, .otherVersions, .appearsOn, .audioVariants
        ]) else { return nil }

        var detail = AppleMusicAlbumDetail(album: AppleMusicMapper.album(album))
        detail.notes = album.editorialNotes?.standard ?? album.editorialNotes?.short
        detail.copyright = album.copyright
        detail.recordLabel = album.recordLabelName
        detail.genreNames = album.genreNames.filter { $0 != "Music" }
        detail.audioBadges = AppleMusicMapper.badges(variants: album.audioVariants, isDigitalMaster: album.isAppleDigitalMaster)
        detail.tracks = album.tracks?.compactMap(AppleMusicMapper.song) ?? []
        detail.relatedAlbums = album.relatedAlbums?.map(AppleMusicMapper.album) ?? []
        detail.otherVersions = album.otherVersions?.map(AppleMusicMapper.album) ?? []
        detail.appearsOn = album.appearsOn?.map { AppleMusicMapper.playlist($0) } ?? []
        return detail
    }

    func playlistDetail(id: String, isLibrary: Bool) async -> AppleMusicPlaylistDetail? {
        guard await ensureAuthorized() else { return nil }
        if isLibrary {
            guard let playlist = await libraryPlaylist(id: id) else { return nil }
            var detail = AppleMusicPlaylistDetail(playlist: AppleMusicMapper.playlist(playlist, isLibrary: true))
            detail.tracks = await libraryPlaylistTracks(id: id)
            return detail
        }
        guard let playlist = await catalogPlaylist(id, properties: [.tracks, .featuredArtists, .moreByCurator]) else { return nil }
        var detail = AppleMusicPlaylistDetail(playlist: AppleMusicMapper.playlist(playlist))
        detail.tracks = playlist.tracks?.compactMap(AppleMusicMapper.song) ?? []
        detail.featuredArtists = playlist.featuredArtists?.map(AppleMusicMapper.artist) ?? []
        detail.moreByCurator = playlist.moreByCurator?.map { AppleMusicMapper.playlist($0) } ?? []
        return detail
    }

    func artistTopSongs(artistID: String) async -> [AppleMusicSong] {
        guard await ensureAuthorized() else { return [] }
        return await catalogArtist(artistID, properties: [.topSongs])?.topSongs?.map(AppleMusicMapper.song) ?? []
    }

    func artistAlbums(artistID: String) async -> [AppleMusicAlbum] {
        guard await ensureAuthorized() else { return [] }
        return await catalogArtist(artistID, properties: [.fullAlbums])?.fullAlbums?.map(AppleMusicMapper.album) ?? []
    }

    func albumTracks(albumID: String) async -> [AppleMusicSong] {
        guard await ensureAuthorized() else { return [] }
        return await catalogAlbum(albumID, properties: [.tracks])?.tracks?.compactMap(AppleMusicMapper.song) ?? []
    }

    func songsByArtist(named name: String, limit: Int = 10) async -> [AppleMusicSong] {
        guard await ensureAuthorized(), let artist = await resolveArtist(named: name) else { return [] }
        return artist.topSongs.map { Array($0.prefix(limit)).map(AppleMusicMapper.song) } ?? []
    }

    func findArtist(named name: String) async -> AppleMusicArtist? {
        guard await ensureAuthorized() else { return nil }
        var request = MusicCatalogSearchRequest(term: name, types: [Artist.self])
        request.limit = 5
        guard let artists = try? await request.response().artists, !artists.isEmpty else { return nil }
        let key = AppleMusicMapper.matchKey(name)
        return AppleMusicMapper.artist(artists.first { AppleMusicMapper.matchKey($0.name) == key } ?? artists.first!)
    }

    func findAlbum(title: String, artist: String) async -> AppleMusicAlbum? {
        guard await ensureAuthorized() else { return nil }
        var request = MusicCatalogSearchRequest(term: "\(title) \(artist)", types: [Album.self])
        request.limit = 8
        guard let albums = try? await request.response().albums, !albums.isEmpty else { return nil }
        let titleKey = AppleMusicMapper.matchKey(title)
        let artistKey = AppleMusicMapper.matchKey(artist)
        let match = albums.first {
            AppleMusicMapper.matchKey($0.title) == titleKey && AppleMusicMapper.matchKey($0.artistName).contains(artistKey)
        } ?? albums.first { AppleMusicMapper.matchKey($0.title) == titleKey }
        return match.map(AppleMusicMapper.album)
    }

    private func resolveArtist(named name: String) async -> Artist? {
        var request = MusicCatalogSearchRequest(term: name, types: [Artist.self])
        request.limit = 5
        guard let artists = try? await request.response().artists, !artists.isEmpty else { return nil }
        let key = AppleMusicMapper.matchKey(name)
        let match = artists.first { AppleMusicMapper.matchKey($0.name) == key } ?? artists.first!
        return try? await match.with([.topSongs, .similarArtists])
    }

    // MARK: - Library

    private func libraryPlaylist(id: String) async -> Playlist? {
        if let cached = libraryPlaylistCache[id] { return cached }
        var request = MusicLibraryRequest<Playlist>()
        request.filter(matching: \.id, equalTo: MusicItemID(id))
        request.limit = 1
        guard let playlist = try? await request.response().items.first else { return nil }
        libraryPlaylistCache[id] = playlist
        return playlist
    }

    func libraryPlaylists() async -> [AppleMusicPlaylist] {
        guard await ensureAuthorized() else { return [] }
        do {
            let items = try await MusicLibraryRequest<Playlist>().response().items
            for playlist in items { libraryPlaylistCache[playlist.id.rawValue] = playlist }
            clearError()
            return items
                .sorted { ($0.lastPlayedDate ?? .distantPast) > ($1.lastPlayedDate ?? .distantPast) }
                .map { AppleMusicMapper.playlist($0, isLibrary: true) }
        } catch {
            record(error, context: "Library playlists")
            return []
        }
    }

    private func libraryPlaylistTrackItems(id: String) async -> MusicItemCollection<Track>? {
        if let cached = libraryPlaylistTracksCache[id] { return cached }
        guard let playlist = await libraryPlaylist(id: id),
              let tracks = try? await playlist.with([.tracks]).tracks else { return nil }
        libraryPlaylistTracksCache[id] = tracks
        return tracks
    }

    func libraryPlaylistTracks(id: String, refresh: Bool = false) async -> [AppleMusicSong] {
        guard await ensureAuthorized() else { return [] }
        if refresh { libraryPlaylistTracksCache[id] = nil }
        return await libraryPlaylistTrackItems(id: id)?.compactMap(AppleMusicMapper.song) ?? []
    }

    private static let librarySnapshotLimit = 20_000
    private static let librarySnapshotTTL: TimeInterval = 600
    @ObservationIgnored private var songSnapshot: (date: Date, items: [Song])?
    @ObservationIgnored private var albumSnapshot: (date: Date, items: [Album])?
    @ObservationIgnored private var songSnapshotTask: Task<[Song], Never>?
    @ObservationIgnored private var albumSnapshotTask: Task<[Album], Never>?

    private func librarySongSnapshot() async -> [Song] {
        if let snapshot = songSnapshot, Date().timeIntervalSince(snapshot.date) < Self.librarySnapshotTTL {
            return snapshot.items
        }
        if let task = songSnapshotTask { return await task.value }
        let task = Task<[Song], Never> {
            var request = MusicLibraryRequest<Song>()
            request.limit = Self.librarySnapshotLimit
            return (try? await request.response().items).map(Array.init) ?? []
        }
        songSnapshotTask = task
        let items = await task.value
        songSnapshotTask = nil
        songSnapshot = (Date(), items)
        return items
    }

    private func libraryAlbumSnapshot() async -> [Album] {
        if let snapshot = albumSnapshot, Date().timeIntervalSince(snapshot.date) < Self.librarySnapshotTTL {
            return snapshot.items
        }
        if let task = albumSnapshotTask { return await task.value }
        let task = Task<[Album], Never> {
            var request = MusicLibraryRequest<Album>()
            request.limit = Self.librarySnapshotLimit
            return (try? await request.response().items).map(Array.init) ?? []
        }
        albumSnapshotTask = task
        let items = await task.value
        albumSnapshotTask = nil
        albumSnapshot = (Date(), items)
        return items
    }

    func librarySongs(limit: Int = 500) async -> [AppleMusicSong] {
        guard await ensureAuthorized() else { return [] }
        return await librarySongSnapshot()
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            .prefix(limit)
            .map(AppleMusicMapper.song)
    }

    func recentlyAdded(limit: Int = 25) async -> [AppleMusicSong] {
        guard await ensureAuthorized() else { return [] }
        return await librarySongSnapshot()
            .filter { $0.libraryAddedDate != nil }
            .sorted { $0.libraryAddedDate! > $1.libraryAddedDate! }
            .prefix(limit)
            .map(AppleMusicMapper.song)
    }

    func mostPlayed(limit: Int = 25) async -> [AppleMusicSong] {
        guard await ensureAuthorized() else { return [] }
        return await librarySongSnapshot()
            .filter { ($0.playCount ?? 0) > 0 }
            .sorted { ($0.playCount ?? 0) > ($1.playCount ?? 0) }
            .prefix(limit)
            .map(AppleMusicMapper.song)
    }

    func libraryAlbums(limit: Int = 100) async -> [AppleMusicAlbum] {
        guard await ensureAuthorized() else { return [] }
        return await libraryAlbumSnapshot()
            .sorted { ($0.libraryAddedDate ?? .distantPast) > ($1.libraryAddedDate ?? .distantPast) }
            .prefix(limit)
            .map(AppleMusicMapper.album)
    }

    func libraryArtists(limit: Int = 100) async -> [AppleMusicArtist] {
        guard await ensureAuthorized() else { return [] }
        var request = MusicLibraryRequest<Artist>()
        request.limit = Self.librarySnapshotLimit
        let artists = (try? await request.response().items).map(Array.init) ?? []
        return artists
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            .prefix(limit)
            .map(AppleMusicMapper.artist)
    }

    func heavyRotation(limit: Int = 15) async -> [AppleMusicAlbum] {
        guard await ensureAuthorized() else { return [] }
        async let albumItems = libraryAlbumSnapshot()
        async let songItems = librarySongSnapshot()
        let (allAlbums, songs) = await (albumItems, songItems)
        let albums = allAlbums
            .filter { $0.lastPlayedDate != nil }
            .sorted { $0.lastPlayedDate! > $1.lastPlayedDate! }
            .prefix(60)
        guard !albums.isEmpty else { return [] }
        var plays: [String: Int] = [:]
        for song in songs {
            guard let title = song.albumTitle, let count = song.playCount, count > 0 else { continue }
            plays[AppleMusicMapper.matchKey(title), default: 0] += count
        }
        let ranked = albums.enumerated().sorted { lhs, rhs in
            let l = plays[AppleMusicMapper.matchKey(lhs.element.title)] ?? 0
            let r = plays[AppleMusicMapper.matchKey(rhs.element.title)] ?? 0
            return l == r ? lhs.offset < rhs.offset : l > r
        }
        return ranked.prefix(limit).map { AppleMusicMapper.album($0.element) }
    }

    // MARK: - Personalization

    func recommendations(limit: Int = 10) async -> [AppleMusicRecommendationShelf] {
        guard await ensureAuthorized() else { return [] }
        do {
            var request = MusicPersonalRecommendationsRequest()
            request.limit = limit
            let response = try await request.response()
            clearError()
            return response.recommendations.compactMap { recommendation in
                let items = recommendation.items.compactMap(AppleMusicMapper.shelfItem)
                guard !items.isEmpty else { return nil }
                return AppleMusicRecommendationShelf(
                    id: recommendation.id.rawValue,
                    title: recommendation.title ?? "For You",
                    reason: recommendation.reason,
                    items: items
                )
            }
        } catch {
            record(error, context: "Recommendations")
            return []
        }
    }

    func recentlyPlayedSongs(limit: Int = 25) async -> [AppleMusicSong] {
        guard await ensureAuthorized() else { return [] }
        var request = MusicRecentlyPlayedRequest<Song>()
        request.limit = limit
        return (try? await request.response().items.map(AppleMusicMapper.song)) ?? []
    }

    func recentlyPlayedContainers(limit: Int = 15) async -> [AppleMusicShelfItem] {
        guard await ensureAuthorized() else { return [] }
        var request = MusicRecentlyPlayedContainerRequest()
        request.limit = limit
        return (try? await request.response().items.compactMap(AppleMusicMapper.shelfItem)) ?? []
    }

    func replay() async -> AppleMusicReplaySummary {
        guard await ensureAuthorized() else { return AppleMusicReplaySummary() }
        var request = MusicLibraryRequest<Playlist>()
        request.limit = 200
        let playlists = (try? await request.response().items) ?? []
        guard let replay = playlists
            .filter({ $0.kind == .replay || $0.name.localizedCaseInsensitiveContains("Replay") })
            .max(by: { $0.name < $1.name }),
            let tracks = try? await replay.with([.tracks]).tracks else {
            return AppleMusicReplaySummary()
        }

        var summary = AppleMusicReplaySummary(playlistName: replay.name)
        summary.topSongs = tracks.compactMap(AppleMusicMapper.song)

        var artistOrder: [String] = []
        var albumOrder: [String] = []
        var albumsByKey: [String: AppleMusicSong] = [:]
        for song in summary.topSongs {
            if !artistOrder.contains(song.artistName) { artistOrder.append(song.artistName) }
            if let album = song.albumTitle, !albumOrder.contains(album) {
                albumOrder.append(album)
                albumsByKey[album] = song
            }
        }
        summary.topArtists = artistOrder.prefix(10).map {
            AppleMusicArtist(id: "name:\($0)", name: $0, artworkURL: nil, url: nil)
        }
        summary.topAlbums = albumOrder.prefix(10).compactMap { title in
            guard let song = albumsByKey[title] else { return nil }
            return AppleMusicAlbum(id: "name:\(title)", title: title, artistName: song.artistName, artworkURL: song.artworkURL, url: nil)
        }
        return summary
    }

    // MARK: - Now playing enrichment

    func nowPlayingDetails(title: String, artist: String, album: String?, includeRelated: Bool) async -> AppleMusicNowPlayingDetails {
        guard await ensureAuthorized() else { return AppleMusicNowPlayingDetails() }
        let key = "\(title)|\(artist)|\(album ?? "")|\(includeRelated)".lowercased()
        if let cached = nowPlayingCache, cached.key == key { return cached.details }

        var details = AppleMusicNowPlayingDetails()

        var libraryRequest = MusicLibraryRequest<Song>()
        libraryRequest.filter(matching: \.title, equalTo: title)
        libraryRequest.limit = 10
        if let rows = try? await libraryRequest.response().items {
            let artistKey = AppleMusicMapper.matchKey(artist)
            if let row = rows.first(where: { AppleMusicMapper.matchKey($0.artistName).contains(artistKey) || artistKey.contains(AppleMusicMapper.matchKey($0.artistName)) }) {
                details.isInLibrary = true
                details.playCount = row.playCount
                details.lastPlayedDate = row.lastPlayedDate
                details.libraryAddedDate = row.libraryAddedDate
            }
        }

        var catalogSong: Song?
        if isInAppPlaybackActive, case .song(let song)? = player.queue.currentEntry?.item,
           AppleMusicMapper.matchKey(song.title) == AppleMusicMapper.matchKey(title) {
            catalogSong = song
        }
        if catalogSong == nil {
            catalogSong = await matchCatalogSong(title: title, artist: artist, album: album)
        }

        if let found = catalogSong,
           let song = try? await found.with([.artists, .albums, .station, .audioVariants]) {
            details.song = AppleMusicMapper.song(song)
            details.composer = song.composerName
            details.genreNames = song.genreNames.filter { $0 != "Music" }
            details.releaseDate = song.releaseDate
            details.hasLyrics = song.hasLyrics
            details.hasStation = song.station != nil
            details.audioBadges = AppleMusicMapper.badges(variants: song.audioVariants, isDigitalMaster: song.isAppleDigitalMaster)
            if let catalogArtist = song.artists?.first {
                details.artist = AppleMusicMapper.artist(catalogArtist)
                if includeRelated, let expanded = try? await catalogArtist.with([.topSongs, .similarArtists]) {
                    details.moreByArtist = (expanded.topSongs ?? [])
                        .filter { $0.id != song.id }
                        .prefix(10)
                        .map(AppleMusicMapper.song)
                    details.similarArtists = expanded.similarArtists?.prefix(10).map(AppleMusicMapper.artist) ?? []
                }
            }
            if let catalogAlbum = song.albums?.first {
                details.album = AppleMusicMapper.album(catalogAlbum)
                if includeRelated, let expanded = try? await catalogAlbum.with([.relatedAlbums]) {
                    details.relatedAlbums = expanded.relatedAlbums?.prefix(10).map(AppleMusicMapper.album) ?? []
                }
            }
        }

        nowPlayingCache = (key, details)
        return details
    }

    private func matchCatalogSong(title: String, artist: String, album: String?) async -> Song? {
        var request = MusicCatalogSearchRequest(term: "\(title) \(artist)", types: [Song.self])
        request.limit = 10
        guard let songs = try? await request.response().songs, !songs.isEmpty else { return nil }
        let titleKey = AppleMusicMapper.matchKey(title)
        let artistKey = AppleMusicMapper.matchKey(artist)
        let albumKey = album.map(AppleMusicMapper.matchKey)
        func score(_ song: Song) -> Int {
            var value = 0
            let songTitle = AppleMusicMapper.matchKey(song.title)
            if songTitle == titleKey { value += 4 } else if songTitle.contains(titleKey) || titleKey.contains(songTitle) { value += 2 }
            let songArtist = AppleMusicMapper.matchKey(song.artistName)
            if songArtist == artistKey { value += 3 } else if songArtist.contains(artistKey) || artistKey.contains(songArtist) { value += 2 }
            if let albumKey, let songAlbum = song.albumTitle, AppleMusicMapper.matchKey(songAlbum) == albumKey { value += 2 }
            return value
        }
        let best = songs.max { score($0) < score($1) }
        guard let best, score(best) >= 5 else { return nil }
        return best
    }

    // MARK: - In-app playback (ApplicationMusicPlayer)

    private func start(_ queue: ApplicationMusicPlayer.Queue) async -> Bool {
        guard await ensureAuthorized() else { return false }
        await AppleMusicAppBridge.shared.pauseIfPlaying()
        if playerStateCancellable == nil { observePlayerState() }
        player.queue = queue
        hasSetQueue = true
        inAppStartedAt = Date()
        observeQueue()
        setInAppActive(true)
        do {
            try await player.play()
            clearError()
            return true
        } catch {
            record(error, context: "Playback")
            return false
        }
    }

    func play(songIDs: [String], startingAt startID: String? = nil) async -> Bool {
        guard await ensureAuthorized() else { return false }
        let songs = await playableSongs(Array(songIDs.prefix(200)))
        guard !songs.isEmpty else { return false }
        let start = startID.flatMap { id in songs.first { $0.id.rawValue == id } }
        return await self.start(ApplicationMusicPlayer.Queue(for: songs, startingAt: start))
    }

    func playAlbum(albumID: String, startingAt songID: String? = nil) async -> Bool {
        guard await ensureAuthorized(), let album = await catalogAlbum(albumID, properties: [.tracks]) else { return false }
        if let songID, let track = album.tracks?.first(where: { $0.id.rawValue == songID }) {
            return await start(ApplicationMusicPlayer.Queue(album: album, startingAt: track))
        }
        return await start(ApplicationMusicPlayer.Queue(for: [album]))
    }

    func playPlaylist(id: String, isLibrary: Bool, startingAt songID: String? = nil, shuffled: Bool = false) async -> Bool {
        guard await ensureAuthorized() else { return false }
        let ok: Bool
        if isLibrary {
            guard let tracks = await libraryPlaylistTrackItems(id: id), !tracks.isEmpty else { return false }
            let start = songID.flatMap { id in tracks.first { $0.id.rawValue == id } }
            ok = await self.start(ApplicationMusicPlayer.Queue(for: tracks, startingAt: start))
        } else {
            guard let playlist = await catalogPlaylist(id, properties: [.tracks]) else { return false }
            if let songID, let tracks = playlist.tracks, let track = tracks.first(where: { $0.id.rawValue == songID }) {
                ok = await start(ApplicationMusicPlayer.Queue(for: tracks, startingAt: track))
            } else {
                ok = await start(ApplicationMusicPlayer.Queue(for: [playlist]))
            }
        }
        if ok, shuffled { player.state.shuffleMode = .songs }
        return ok
    }

    func playStation(id: String) async -> Bool {
        guard await ensureAuthorized(), let station = await catalogStation(id) else { return false }
        return await start(ApplicationMusicPlayer.Queue(for: [station]))
    }

    func playSongStation(songID: String) async -> Bool {
        guard await ensureAuthorized(),
              let song = await catalogSongs([songID], properties: [.station]).first,
              let station = song.station else { return false }
        return await start(ApplicationMusicPlayer.Queue(for: [station]))
    }

    func playArtistStation(artistID: String) async -> Bool {
        guard await ensureAuthorized(),
              let station = await catalogArtist(artistID, properties: [.station])?.station else { return false }
        return await start(ApplicationMusicPlayer.Queue(for: [station]))
    }

    func playArtistTopSongs(artistID: String) async -> Bool {
        guard await ensureAuthorized(),
              let songs = await catalogArtist(artistID, properties: [.topSongs])?.topSongs,
              !songs.isEmpty else { return false }
        return await start(ApplicationMusicPlayer.Queue(for: songs))
    }

    func playBySearch(term: String) async -> Bool {
        let results = await search(term, limit: 5)
        guard let first = results.songs.first else {
            let escaped = term.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            AppleMusicAppBridge.shared.open(url: URL(string: "https://music.apple.com/search?term=\(escaped)"))
            return false
        }
        return await play(songIDs: [first.id])
    }

    enum QueuePosition { case next, last }

    func enqueue(songIDs: [String], position: QueuePosition) async -> Bool {
        guard await ensureAuthorized() else { return false }
        let songs = await playableSongs(songIDs)
        guard !songs.isEmpty else { return false }
        guard isInAppPlaybackActive, hasSetQueue else {
            return await start(ApplicationMusicPlayer.Queue(for: songs))
        }
        do {
            try await player.queue.insert(songs, position: position == .next ? .afterCurrentEntry : .tail)
            inAppQueueRevision &+= 1
            return true
        } catch {
            record(error, context: "Queue insert")
            return false
        }
    }

    func inAppPlay() {
        Task { try? await player.play() }
    }

    func inAppPause() {
        player.pause()
    }

    func inAppNext() {
        Task { try? await player.skipToNextEntry() }
    }

    func inAppPrevious() {
        if player.playbackTime > 3 {
            player.restartCurrentEntry()
        } else {
            Task { try? await player.skipToPreviousEntry() }
        }
    }

    func inAppSeek(to seconds: TimeInterval) {
        player.playbackTime = max(0, seconds)
    }

    var inAppShuffle: Bool { player.state.shuffleMode == .songs }

    var inAppRepeat: RepeatMode {
        switch player.state.repeatMode {
        case .one: .track
        case .all: .context
        default: .off
        }
    }

    func setInAppShuffle(_ enabled: Bool) {
        player.state.shuffleMode = enabled ? .songs : .off
    }

    func setInAppRepeat(_ mode: RepeatMode) {
        switch mode {
        case .off: player.state.repeatMode = MusicPlayer.RepeatMode.none
        case .context: player.state.repeatMode = .all
        case .track: player.state.repeatMode = .one
        }
    }

    struct UpNextEntry {
        let id: String
        let songID: String?
        let title: String
        let artist: String
        let artworkURL: URL?
    }

    func inAppUpNext(limit: Int = 50) -> [UpNextEntry] {
        guard isInAppPlaybackActive, hasSetQueue else { return [] }
        let entries = Array(player.queue.entries)
        let startIndex: Int = {
            guard let currentID = player.queue.currentEntry?.id,
                  let index = entries.firstIndex(where: { $0.id == currentID }) else { return 0 }
            return index + 1
        }()
        guard startIndex < entries.count else { return [] }
        return entries[startIndex...].prefix(limit).map { entry in
            let songID: String? = {
                if case .song(let song)? = entry.item { return song.id.rawValue }
                return nil
            }()
            return UpNextEntry(
                id: entry.id,
                songID: songID,
                title: entry.title,
                artist: entry.subtitle ?? "",
                artworkURL: AppleMusicMapper.artworkURL(entry.artwork, size: 120)
            )
        }
    }

    func jumpToQueueEntry(id: String) async -> Bool {
        guard isInAppPlaybackActive,
              let entry = player.queue.entries.first(where: { $0.id == id }) else { return false }
        player.queue.currentEntry = entry
        try? await player.play()
        return true
    }

    var inAppCurrentSongURL: URL? {
        guard isInAppPlaybackActive, case .song(let song)? = player.queue.currentEntry?.item else { return nil }
        return song.url
    }

    func relinquishInAppPlaybackNow() {
        guard isInAppPlaybackActive else { return }
        player.pause()
        setInAppActive(false)
    }

    func relinquishInAppPlayback() {
        guard isInAppPlaybackActive, Date().timeIntervalSince(inAppStartedAt) > 3 else { return }
        player.pause()
        setInAppActive(false)
    }

    private func setInAppActive(_ active: Bool) {
        guard isInAppPlaybackActive != active else { return }
        isInAppPlaybackActive = active
        AppleMusicPlaybackIdentity.setInAppPlaybackActive(active)
    }

    private func observePlayerState() {
        playerStateCancellable = player.state.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, self.hasSetQueue else { return }
                switch self.player.state.playbackStatus {
                case .stopped:
                    if self.player.queue.currentEntry == nil { self.setInAppActive(false) }
                case .playing:
                    self.setInAppActive(true)
                default:
                    break
                }
            }
    }

    private func observeQueue() {
        queueCancellable = player.queue.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.inAppQueueRevision &+= 1
            }
    }
}