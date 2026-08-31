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

struct AppleMusicSearchResults {
    var songs: [AppleMusicSong] = []
    var albums: [AppleMusicAlbum] = []
    var artists: [AppleMusicArtist] = []
    var playlists: [AppleMusicPlaylist] = []

    var isEmpty: Bool { songs.isEmpty && albums.isEmpty && artists.isEmpty && playlists.isEmpty }
}

struct AppleMusicSong: Identifiable, Hashable {
    let id: String
    let title: String
    let artistName: String
    let albumTitle: String?
    let artworkURL: URL?
    let duration: TimeInterval?
    let url: URL?
}

struct AppleMusicAlbum: Identifiable, Hashable {
    let id: String
    let title: String
    let artistName: String
    let artworkURL: URL?
    let url: URL?
}

struct AppleMusicArtist: Identifiable, Hashable {
    let id: String
    let name: String
    let artworkURL: URL?
    let url: URL?
}

struct AppleMusicPlaylist: Identifiable, Hashable {
    let id: String
    let name: String
    let curatorName: String?
    let artworkURL: URL?
    let url: URL?
}

struct AppleMusicMusicVideo: Identifiable, Hashable {
    let id: String
    let title: String
    let artistName: String
    let albumTitle: String?
    let artworkURL: URL?
    let duration: TimeInterval?
    let url: URL?
}

struct AppleMusicStation: Identifiable, Hashable {
    let id: String
    let name: String
    let tagline: String?
    let artworkURL: URL?
    let url: URL?
}

struct AppleMusicRating: Equatable, Hashable {
    let id: String
    let type: String
    let value: Int
}

struct AppleMusicReplaySummary: Equatable {
    var topSongs: [AppleMusicSong] = []
    var topAlbums: [AppleMusicAlbum] = []
    var topArtists: [AppleMusicArtist] = []
}

@MainActor
final class MusicKitAppleMusicManager: ObservableObject {
    static let shared = MusicKitAppleMusicManager()

    // MARK: - Published state
    @Published private(set) var developerTokenPresent: Bool
    @Published private(set) var authorizationStatus: MusicAuthorization.Status = .notDetermined
    @Published private(set) var isAuthorized: Bool = false
    @Published private(set) var didBootstrap: Bool = false

    weak var transport: NativeMediaController?

    private var hasSetQueue = false

    private init() {
        developerTokenPresent = MusicKitTokenStore.hasDeveloperToken
    }

    var isConfigured: Bool {
        developerTokenPresent
    }

    var isConfiguredAndAuthorized: Bool {
        developerTokenPresent && isAuthorized
    }

    private var applicationPlayer: ApplicationMusicPlayer {
        .shared
    }

    // MARK: - Token provider

    var currentTokenProvider: SapphireMusicTokenProvider? {
        let token = MusicKitTokenStore.developerToken
        guard !token.isEmpty else { return nil }
        return SapphireMusicTokenProvider(developerToken: token)
    }

    // MARK: - Artwork

    private func loadableArtworkURL(_ artwork: Artwork?, size: Int = 300) -> URL? {
        guard let url = artwork?.url(width: size, height: size) else { return nil }
        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else { return nil }
        return url
    }

    // MARK: - Authorization

    func requestAuthorization() async {
        let status = await MusicAuthorization.request()
        authorizationStatus = status
        isAuthorized = (status == .authorized)
        if isAuthorized, isConfigured {
            configureTokenProviderIfNeeded()
            AppleMusicPrivateAPIManager.shared.bootstrapIfNeeded(policy: .automatic, delay: 0.5)
        }
        didBootstrap = true
        MusicManager.shared.objectWillChange.send()
    }

    func ensureAuthorized() async {
        guard !isAuthorized, isConfigured else { return }
        await requestAuthorization()
    }

    private func configureTokenProviderIfNeeded() {
        guard MusicKitTokenStore.canObtainUserToken,
              let provider = currentTokenProvider else { return }
        MusicDataRequest.tokenProvider = provider
    }

    // MARK: - App detection

    func isAppRunning() -> Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == "com.apple.Music" }
    }

    func activateMusicApp() {
        NSWorkspace.shared.runningApplications
            .first { $0.bundleIdentifier == "com.apple.Music" }?
            .activate()
    }

    // MARK: - Player state (reads, token-free via MediaRemote where possible)

    func currentShuffleState() -> Bool {
        if isAuthorized, isConfigured,
           applicationPlayer.state.playbackStatus == .playing || applicationPlayer.state.playbackStatus == .paused {
            return applicationPlayer.state.shuffleMode == .songs
        }
        return transport?.activeClients.values.first?.payload.shuffleMode == 1
    }

    func currentRepeatState() -> RepeatMode {
        if isAuthorized, isConfigured,
           applicationPlayer.state.playbackStatus == .playing || applicationPlayer.state.playbackStatus == .paused {
            switch applicationPlayer.state.repeatMode {
            case .one: return .track
            case .all: return .context
            case .none: return .off
            @unknown default: return .off
            }
        }
        let raw = transport?.activeClients.values.first?.payload.repeatMode
        switch raw {
        case 1: return .track
        case 2: return .context
        default: return .off
        }
    }

    func currentTrackIsLiked() -> Bool {
        transport?.activeClients.values.first?.payload.isLiked ?? false
    }

    // MARK: - Transport controls (token-free)

    func play() -> Bool {
        guard let transport else { return false }
        transport.play()
        return true
    }

    func pause() -> Bool {
        guard let transport else { return false }
        transport.pause()
        return true
    }

    func nextTrack() -> Bool {
        guard let transport else { return false }
        transport.nextTrack()
        return true
    }

    func previousTrack() -> Bool {
        guard let transport else { return false }
        transport.previousTrack()
        return true
    }

    func seek(to seconds: Double) -> Bool {
        guard let transport else { return false }
        transport.setTime(seconds: max(0, seconds))
        return true
    }

    func seek(by delta: TimeInterval) -> Bool {
        guard let transport,
              let track = transport.activeClients.values.first?.payload else { return false }
        let current = track.calculatedElapsedTime
        transport.setTime(seconds: max(0, current + delta))
        return true
    }

    // MARK: - Real Up Next (Music-app queue)

    struct UpNextEntry {
        let id: String
        let songID: String?
        let title: String
        let artist: String
    }

    func liveUpNext() -> [UpNextEntry] {
        guard isAuthorized, isConfigured, hasSetQueue else { return [] }
        return Array(applicationPlayer.queue.entries).map { entry in
            let songID: String? = {
                if case .song(let song)? = entry.item { return song.id.rawValue }
                return nil
            }()
            return UpNextEntry(
                id: entry.id,
                songID: songID,
                title: entry.title,
                artist: entry.subtitle ?? ""
            )
        }
    }

    func currentLiveUpNextEntryID() -> String? {
        guard isAuthorized, isConfigured, hasSetQueue else { return nil }
        return applicationPlayer.queue.currentEntry?.id
    }

    // MARK: - Shuffle / repeat setters

    func setShuffle(enabled: Bool) {
        if isAuthorized, isConfigured {
            applicationPlayer.state.shuffleMode = enabled ? .songs : .off
            return
        }
        let currentlyOn = currentShuffleState()
        guard currentlyOn != enabled, let transport else { return }
        transport.toggleShuffle()
    }

    func setRepeat(mode: RepeatMode) {
        if isAuthorized, isConfigured {
            switch mode {
            case .off: applicationPlayer.state.repeatMode = .none
            case .context: applicationPlayer.state.repeatMode = .all
            case .track: applicationPlayer.state.repeatMode = .one
            }
            return
        }
        var cycles = 0
        while currentRepeatState() != mode, cycles < 2, let transport {
            transport.toggleRepeat()
            cycles += 1
        }
    }

    // MARK: - Library

    func fetchLibraryPlaylists() async -> [SpotifyPlaylist] {
        guard isConfiguredAndAuthorized else { return [] }
        do {
            let request = MusicLibraryRequest<Playlist>()
            let response = try await request.response()
            return response.items.map { playlist in
                SpotifyPlaylist(
                    id: playlist.id.rawValue,
                    name: playlist.name,
                    uri: playlist.id.rawValue,
                    images: playlist.artwork.map { [SpotifyImage(url: loadableArtworkURL($0)?.absoluteString ?? "")] } ?? [],
                    owner: SpotifyUserSimple(id: "apple_music", displayName: "Me", images: nil),
                    collaborators: nil
                )
            }
        } catch {
            return []
        }
    }

    func fetchPlaylistTracks(playlistID: String) async -> [SpotifyTrack] {
        guard isConfiguredAndAuthorized else { return [] }
        do {
            var request = MusicLibraryRequest<Playlist>()
            request.filter(matching: \.id, equalTo: MusicItemID(playlistID))
            request.limit = 1
            let response = try await request.response()
            guard let firstPlaylist = response.items.first else { return [] }
            var playlist = try await firstPlaylist.with([.tracks])
            let tracks = playlist.tracks ?? []
            return tracks.compactMap(mapLibraryTrack)
        } catch {
            return []
        }
    }

    func fetchLibrarySongs() async -> [SpotifyTrack] {
        guard isConfiguredAndAuthorized else { return [] }
        do {
            let request = MusicLibraryRequest<Song>()
            let response = try await request.response()
            return response.items.compactMap(mapLibrarySong)
        } catch {
            return []
        }
    }

    private func mapLibraryTrack(_ track: Track) -> SpotifyTrack? {
        switch track {
        case .song(let song): return mapLibrarySong(song)
        case .musicVideo: return nil
        @unknown default: return nil
        }
    }

    private func mapLibrarySong(_ song: Song) -> SpotifyTrack? {
        let artwork = song.artwork.map { [SpotifyImage(url: loadableArtworkURL($0)?.absoluteString ?? "")] } ?? []
        return SpotifyTrack(
            id: song.id.rawValue,
            name: song.title,
            uri: song.id.rawValue,
            album: SpotifyAlbum(name: song.albumTitle ?? "", images: artwork),
            artists: song.artistName.isEmpty ? [] : [SpotifyArtist(name: song.artistName)],
            durationMs: song.duration.map { Int($0 * 1000) } ?? 0,
            popularity: nil
        )
    }

    // MARK: - Catalog search

    func search(_ term: String) async -> AppleMusicSearchResults {
        guard isConfiguredAndAuthorized, !term.isEmpty else { return AppleMusicSearchResults() }
        do {
            let request = MusicCatalogSearchRequest(
                term: term,
                types: [Song.self, Album.self, Artist.self, Playlist.self]
            )
            let response = try await request.response()

            var results = AppleMusicSearchResults()
            results.songs = response.songs.map(mapCatalogSong)
            results.albums = response.albums.map(mapCatalogAlbum)
            results.artists = response.artists.map(mapCatalogArtist)
            results.playlists = response.playlists.map(mapCatalogPlaylist)
            return results
        } catch {
            return AppleMusicSearchResults()
        }
    }

    private func mapCatalogSong(_ song: Song) -> AppleMusicSong {
        AppleMusicSong(
            id: song.id.rawValue,
            title: song.title,
            artistName: song.artistName,
            albumTitle: song.albumTitle,
            artworkURL: loadableArtworkURL(song.artwork),
            duration: song.duration,
            url: song.url
        )
    }

    private func mapCatalogAlbum(_ album: Album) -> AppleMusicAlbum {
        AppleMusicAlbum(
            id: album.id.rawValue,
            title: album.title,
            artistName: album.artistName,
            artworkURL: loadableArtworkURL(album.artwork),
            url: album.url
        )
    }

    private func mapCatalogArtist(_ artist: Artist) -> AppleMusicArtist {
        AppleMusicArtist(
            id: artist.id.rawValue,
            name: artist.name,
            artworkURL: loadableArtworkURL(artist.artwork),
            url: artist.url
        )
    }

    private func mapCatalogPlaylist(_ playlist: Playlist) -> AppleMusicPlaylist {
        AppleMusicPlaylist(
            id: playlist.id.rawValue,
            name: playlist.name,
            curatorName: playlist.curatorName,
            artworkURL: loadableArtworkURL(playlist.artwork),
            url: playlist.url
        )
    }

    // MARK: - Play (needs authorization; falls back to opening the Music app)

    func play(songs: [Song]) async -> Bool {
        guard isConfiguredAndAuthorized, !songs.isEmpty else { return false }
        applicationPlayer.queue = ApplicationMusicPlayer.Queue(for: songs)
        hasSetQueue = true
        do {
            try await applicationPlayer.play()
            return true
        } catch {
            return false
        }
    }

    func play(song: AppleMusicSong) async -> Bool {
        await ensureAuthorized()
        guard isConfiguredAndAuthorized else {
            activateMusicApp()
            return false
        }
        let request = MusicCatalogResourceRequest<Song>(matching: \.id, equalTo: MusicItemID(song.id))
        do {
            let response = try await request.response()
            guard let song = response.items.first else { return false }
            return await play(songs: [song])
        } catch {
            activateMusicApp()
            return false
        }
    }

    func playBySearch(term: String) async -> Bool {
        await ensureAuthorized()
        let results = await search(term)
        guard let first = results.songs.first else {
            openAppleMusicSearchURL(term)
            return false
        }
        return await play(song: first)
    }

    private func openAppleMusicSearchURL(_ term: String) {
        let escaped = term.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: "music://music.apple.com/search?term=\(escaped)") {
            NSWorkspace.shared.open(url)
        }
    }
}

final class SapphireMusicTokenProvider: MusicUserTokenProvider, MusicDeveloperTokenProvider {
    let developerToken: String

    init(developerToken: String) {
        self.developerToken = developerToken
        super.init()
    }

    func developerToken(options: MusicTokenRequestOptions) async throws -> String {
        developerToken
    }
}