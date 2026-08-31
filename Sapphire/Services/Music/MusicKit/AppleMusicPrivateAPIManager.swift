//
//  AppleMusicPrivateAPIManager.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-30
//

import Foundation
import Combine
import AppKit
import MusicKit

enum AppleMusicPrivateBootstrapPolicy {
    case onDemand
    case automatic
}

@MainActor
final class AppleMusicPrivateAPIManager: ObservableObject {
    static let shared = AppleMusicPrivateAPIManager()

    // MARK: - Published state
    @Published private(set) var isLoggedIn: Bool = false
    @Published private(set) var currentPlayCount: Int?
    @Published private(set) var currentPopularity: Int?
    @Published private(set) var currentFavorite: Bool?

    // MARK: - Auth internals
    private var developerToken: String = ""
    private var userToken: String = ""
    private var storefront: String = "us"
    private var storefrontFetchedAt: Date = .distantPast
    private var bootstrapTask: Task<Void, Never>?
    private var lastBootstrapAt: Date = .distantPast
    private var refreshInFlight: Task<Bool, Never>?
    private var lastResolvedSongID: String?
    private var lastResolvedKey: String?

    private let baseURL = URL(string: "https://api.music.apple.com")!

    private init() {}

    // MARK: - Auth

    var isConfigured: Bool {
        MusicKitTokenStore.hasDeveloperToken
            && MusicKitAppleMusicManager.shared.isAuthorized
    }

    var canAccessCatalog: Bool {
        if developerToken.isEmpty {
            developerToken = MusicKitTokenStore.developerToken
        }
        return !developerToken.isEmpty
    }

    // MARK: - Diagnostics

    var diagnosticsSummary: String {
        var lines: [String] = []
        if MusicKitTokenStore.hasDeveloperToken {
            if let expiry = MusicKitTokenStore.developerTokenExpiry {
                let remaining = Int(expiry.timeIntervalSinceNow)
                if remaining > 0 {
                    lines.append("Developer token: valid (expires in \(Self.daysString(remaining)))")
                } else {
                    lines.append("Developer token: EXPIRED \(expiry.formatted())")
                }
            } else {
                lines.append("Developer token: present (unparseable JWT)")
            }
        } else {
            lines.append("Developer token: missing — set MUSICKIT_DEVELOPER_TOKEN or mint one")
        }
        if isLoggedIn {
            lines.append("User token: connected (source: \(MusicKitTokenStore.userTokenSource))")
        } else if MusicKitTokenStore.userTokenOverride != nil {
            lines.append("User token: override present but not yet validated")
        } else {
            lines.append("User token: none — personalized features (love, play counts, recently played, library) need MUSICKIT_USER_TOKEN or the MusicKit entitlement")
        }
        return lines.joined(separator: "\n")
    }

    private static func daysString(_ seconds: Int) -> String {
        let days = max(1, seconds / 86400)
        return days < 30 ? "\(days) day(s)" : "\(days / 30) month(s)"
    }

    func testDeveloperToken() async -> Bool {
        guard canAccessCatalog else { return false }
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/test"))
        request.httpMethod = "GET"
        request.setValue("Bearer \(developerToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }
            let ok = (200...299).contains(http.statusCode)
            print("[AppleMusic] testDeveloperToken -> HTTP \(http.statusCode)")
            return ok
        } catch {
            print("[AppleMusic] testDeveloperToken failed: \(error.localizedDescription)")
            return false
        }
    }

    func bootstrapIfNeeded(policy: AppleMusicPrivateBootstrapPolicy = .automatic, delay: TimeInterval = 2.0) {
        guard isConfigured, !isLoggedIn else { return }
        guard Date().timeIntervalSince(lastBootstrapAt) > 15 else { return }
        lastBootstrapAt = Date()
        bootstrapTask?.cancel()
        bootstrapTask = Task { @MainActor [weak self] in
            switch policy {
            case .onDemand:
                break
            case .automatic:
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            guard !Task.isCancelled else { return }
            _ = await self?.refreshAuthIfNeeded(force: true)
        }
    }

    @discardableResult
    func refreshAuthIfNeeded(force: Bool = false) async -> Bool {
        if isLoggedIn, !force { return true }
        guard isConfigured else {
            isLoggedIn = false
            return false
        }

        if let inFlight = refreshInFlight, !force {
            return await inFlight.value
        }

        let task = Task<Bool, Never> { @MainActor [weak self] in
            guard let self else { return false }
            self.developerToken = MusicKitTokenStore.developerToken
            guard !self.developerToken.isEmpty else { return false }

            do {
                let token = try await MusicKitTokenStore.userToken(developerToken: self.developerToken)
                guard !token.isEmpty else { return false }
                self.userToken = token

                if let code = await self.fetchStorefront() {
                    self.storefront = code
                }

                self.isLoggedIn = true
                return true
            } catch {
                self.isLoggedIn = false
                return false
            }
        }
        refreshInFlight = task
        defer { refreshInFlight = nil }
        return await task.value
    }

    private func fetchStorefront() async -> String? {
        if Date().timeIntervalSince(storefrontFetchedAt) < 3600, storefront != "us" {
            return storefront
        }
        let path = "/v1/me/storefront"
        guard let data = await performGET(path: path, needsUserToken: true) else { return nil }
        struct StorefrontResponse: Decodable {
            struct Item: Decodable { let id: String }
            let data: [Item]
        }
        guard let response = try? Self.decoder.decode(StorefrontResponse.self, from: data) else { return nil }
        storefrontFetchedAt = Date()
        return response.data.first?.id.lowercased()
    }

    // MARK: - Request plumbing

    private func makeURL(path: String, query: [URLQueryItem] = []) -> URL? {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        if !query.isEmpty {
            components?.queryItems = query
        }
        return components?.url
    }

    private func performGET(path: String, query: [URLQueryItem] = [], needsUserToken: Bool = true) async -> Data? {
        guard let url = makeURL(path: path, query: query) else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(developerToken)", forHTTPHeaderField: "Authorization")
        if needsUserToken, !userToken.isEmpty {
            request.setValue(userToken, forHTTPHeaderField: "Music-User-Token")
            request.setValue(userToken, forHTTPHeaderField: "media-user-token")
            request.setValue("https://music.apple.com", forHTTPHeaderField: "Origin")
            request.setValue("https://music.apple.com/", forHTTPHeaderField: "Referer")
        }
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, status) = await send(request, logPath: "GET \(path)")
        guard (200...299).contains(status) else {
            if status > 0 { print("[AppleMusic] GET \(path) -> HTTP \(status)") }
            return nil
        }
        return data
    }

    private func send(_ request: URLRequest, logPath: String) async -> (data: Data?, status: Int) {
        var attempts = 0
        while true {
            attempts += 1
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                let status = (response as? HTTPURLResponse)?.statusCode ?? -1
                if status == 429, attempts < 2 {
                    print("[AppleMusic] \(logPath) -> HTTP 429 (rate limited), retrying…")
                    try? await Task.sleep(nanoseconds: 1_200_000_000)
                    continue
                }
                return (data, status)
            } catch {
                return (nil, -1)
            }
        }
    }

    @discardableResult
    private func performMutation(path: String, method: String, body: [String: Any]? = nil) async -> Bool {
        guard let url = makeURL(path: path) else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(developerToken)", forHTTPHeaderField: "Authorization")
        if !userToken.isEmpty {
            request.setValue(userToken, forHTTPHeaderField: "Music-User-Token")
            request.setValue(userToken, forHTTPHeaderField: "media-user-token")
            request.setValue("https://music.apple.com", forHTTPHeaderField: "Origin")
            request.setValue("https://music.apple.com/", forHTTPHeaderField: "Referer")
        }
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }

        let (_, status) = await send(request, logPath: "\(method) \(path)")
        let ok = (200...299).contains(status)
        if !ok, status > 0 { print("[AppleMusic] \(method) \(path) -> HTTP \(status)") }
        return ok
    }

    private func performMutationData(path: String, method: String, body: [String: Any]? = nil) async -> Data? {
        guard let url = makeURL(path: path) else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(developerToken)", forHTTPHeaderField: "Authorization")
        if !userToken.isEmpty {
            request.setValue(userToken, forHTTPHeaderField: "Music-User-Token")
            request.setValue(userToken, forHTTPHeaderField: "media-user-token")
            request.setValue("https://music.apple.com", forHTTPHeaderField: "Origin")
            request.setValue("https://music.apple.com/", forHTTPHeaderField: "Referer")
        }
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }

        let (data, status) = await send(request, logPath: "\(method) \(path)")
        guard (200...299).contains(status) else { return nil }
        return data
    }

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .useDefaultKeys
        return decoder
    }()

    // MARK: - Current track identity

    func currentTrackSongID() async -> String? {
        let payload = MusicKitAppleMusicManager.shared.transport?.activeClients.values.first?.payload
        let title = payload?.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let artist = payload?.artist?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let key = "\(title)|\(artist)".lowercased()
        if key == lastResolvedKey, let cached = lastResolvedSongID {
            return cached
        }

        if let raw = payload?.uniqueIdentifier ?? payload?.contentItemIdentifier,
           Int(raw) != nil {
            lastResolvedKey = key
            lastResolvedSongID = raw
            return raw
        }

        guard !title.isEmpty else { return nil }
        let id = await findLibrarySongID(title: title, artist: artist)
        lastResolvedKey = key
        lastResolvedSongID = id
        return id
    }

    private func findLibrarySongID(title: String, artist: String) async -> String? {
        guard await refreshAuthIfNeeded() else { return nil }
        let term = "\(title) \(artist)".trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return nil }

        let data = await performGET(
            path: "/v1/me/library/search",
            query: [
                URLQueryItem(name: "term", value: term),
                URLQueryItem(name: "types", value: "songs"),
                URLQueryItem(name: "limit", value: "5"),
            ]
        )
        guard let data else { return nil }

        struct LibrarySearchResponse: Decodable {
            struct Results: Decodable {
                struct Collection: Decodable {
                    struct Item: Decodable {
                        let id: String
                        let attributes: Attributes?
                        struct Attributes: Decodable {
                            let name: String?
                            let artistName: String?
                        }
                    }
                    let data: [Item]
                }
                let songs: Collection?
            }
            let results: Results
        }

        guard let response = try? Self.decoder.decode(LibrarySearchResponse.self, from: data) else { return nil }
        let wantTitle = title.lowercased()
        let wantArtist = artist.lowercased()
        return response.results.songs?.data.first { item in
            guard let name = item.attributes?.name?.lowercased(),
                  let itemArtist = item.attributes?.artistName?.lowercased() else { return false }
            return name == wantTitle && (wantArtist.isEmpty || itemArtist.contains(wantArtist) || wantArtist.contains(itemArtist))
        }?.id
    }

    // MARK: - Love / unlike

    func setFavorite(songID: String, favorite: Bool) async -> Bool {
        guard await refreshAuthIfNeeded() else { return false }

        let method = favorite ? "POST" : "DELETE"
        guard let url = makeURL(path: "/v1/me/favorites", query: [URLQueryItem(name: "ids[songs]", value: songID)]) else {
            return false
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(developerToken)", forHTTPHeaderField: "Authorization")
        request.setValue(userToken, forHTTPHeaderField: "Music-User-Token")
        request.setValue(userToken, forHTTPHeaderField: "media-user-token")
        request.setValue("https://music.apple.com", forHTTPHeaderField: "Origin")
        request.setValue("https://music.apple.com/", forHTTPHeaderField: "Referer")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse,
               (200...299).contains(http.statusCode) || http.statusCode == 202 {
                currentFavorite = favorite
                return true
            }
        } catch {
        }

        let ratingsPath = "/v1/me/ratings/library-songs/\(songID)"
        if favorite {
            let ok = await performMutation(path: ratingsPath, method: "PUT", body: ["attributes": ["value": 1]])
            if ok { currentFavorite = true }
            return ok
        } else {
            let ok = await performMutation(path: ratingsPath, method: "DELETE")
            if ok { currentFavorite = false }
            return ok
        }
    }

    // MARK: - Play count / popularity

    func fetchTrackStats(songID: String) async -> (playCount: Int?, popularity: Int?) {
        guard await refreshAuthIfNeeded() else { return (nil, nil) }
        let data = await performGET(path: "/v1/me/library/songs/\(songID)")
        guard let data else { return (nil, nil) }

        struct SongResponse: Decodable {
            struct Item: Decodable {
                let attributes: Attributes?
                struct Attributes: Decodable {
                    let playCount: FlexibleInt?
                    let popularity: FlexibleInt?
                }
            }
            let data: [Item]
        }

        guard let response = try? Self.decoder.decode(SongResponse.self, from: data),
              let attributes = response.data.first?.attributes else { return (nil, nil) }
        return (attributes.playCount?.intValue, attributes.popularity?.intValue)
    }

    // MARK: - Enrichment for the now-playing track

    func resetCurrentTrackStats() {
        currentPlayCount = nil
        currentPopularity = nil
        currentFavorite = nil
        lastResolvedSongID = nil
        lastResolvedKey = nil
    }

    func enrichCurrentTrack() async {
        guard await refreshAuthIfNeeded() else { return }
        guard let songID = await currentTrackSongID() else { return }
        let (playCount, popularity) = await fetchTrackStats(songID: songID)
        if playCount != nil { currentPlayCount = playCount }
        if popularity != nil { currentPopularity = popularity }
    }

    // MARK: - Catalog search (richer attributes than MusicKit's public search)

    func search(_ term: String) async -> AppleMusicSearchResults {
        guard canAccessCatalog, !term.isEmpty else { return AppleMusicSearchResults() }
        let data = await performGET(
            path: "/v1/catalog/\(storefront)/search",
            query: [
                URLQueryItem(name: "term", value: term),
                URLQueryItem(name: "types", value: "songs,albums,artists,playlists"),
                URLQueryItem(name: "limit", value: "25"),
            ],
            needsUserToken: false
        )
        guard let data else { return AppleMusicSearchResults() }

        struct SearchResponse: Decodable {
            struct Results: Decodable {
                struct Collection: Decodable {
                    struct Item: Decodable {
                        let id: String
                        let attributes: Attributes?
                        struct Attributes: Decodable {
                            let name: String?
                            let artistName: String?
                            let albumName: String?
                            let durationInMillis: Int?
                            let url: String?
                            let curatorName: String?
                            let artwork: Artwork?
                            struct Artwork: Decodable {
                                let url: String?
                                let width: Int?
                                let height: Int?
                            }
                        }
                    }
                    let data: [Item]
                }
                let songs: Collection?
                let albums: Collection?
                let artists: Collection?
                let playlists: Collection?
            }
            let results: Results
        }

        guard let response = try? Self.decoder.decode(SearchResponse.self, from: data) else {
            return AppleMusicSearchResults()
        }

        func artworkURL(_ urlString: String?, width: Int?) -> URL? {
            guard let urlString else { return nil }
            let size = width.map { "\($0)x\($0)bb" } ?? "300x300bb"
            let replaced = urlString
                .replacingOccurrences(of: "{w}x{h}bb", with: size)
                .replacingOccurrences(of: "{w}x{h}", with: size)
            return URL(string: replaced)
        }

        var results = AppleMusicSearchResults()
        results.songs = (response.results.songs?.data ?? []).map { item in
            let a = item.attributes
            return AppleMusicSong(
                id: item.id,
                title: a?.name ?? "",
                artistName: a?.artistName ?? "",
                albumTitle: a?.albumName,
                artworkURL: artworkURL(a?.artwork?.url, width: a?.artwork?.width),
                duration: a?.durationInMillis.map { TimeInterval($0) / 1000.0 },
                url: a?.url.flatMap(URL.init)
            )
        }
        results.albums = (response.results.albums?.data ?? []).map { item in
            let a = item.attributes
            return AppleMusicAlbum(
                id: item.id,
                title: a?.name ?? "",
                artistName: a?.artistName ?? "",
                artworkURL: artworkURL(a?.artwork?.url, width: a?.artwork?.width),
                url: a?.url.flatMap(URL.init)
            )
        }
        results.artists = (response.results.artists?.data ?? []).map { item in
            let a = item.attributes
            return AppleMusicArtist(
                id: item.id,
                name: a?.name ?? "",
                artworkURL: artworkURL(a?.artwork?.url, width: a?.artwork?.width),
                url: a?.url.flatMap(URL.init)
            )
        }
        results.playlists = (response.results.playlists?.data ?? []).map { item in
            let a = item.attributes
            return AppleMusicPlaylist(
                id: item.id,
                name: a?.name ?? "",
                curatorName: a?.curatorName,
                artworkURL: artworkURL(a?.artwork?.url, width: a?.artwork?.width),
                url: a?.url.flatMap(URL.init)
            )
        }
        return results
    }

    // MARK: - Search depth (music videos / stations / suggestions)

    func searchMusicVideos(_ term: String, limit: Int = 12) async -> [AppleMusicMusicVideo] {
        guard canAccessCatalog, !term.isEmpty else { return [] }
        let data = await performGET(
            path: "/v1/catalog/\(storefront)/search",
            query: [
                URLQueryItem(name: "term", value: term),
                URLQueryItem(name: "types", value: "music-videos"),
                URLQueryItem(name: "limit", value: String(limit)),
            ],
            needsUserToken: false
        )
        guard let data else { return [] }
        struct Response: Decodable {
            struct Results: Decodable {
                struct Collection: Decodable {
                    struct Item: Decodable {
                        let id: String
                        let attributes: Attributes?
                        struct Attributes: Decodable {
                            let name: String?
                            let artistName: String?
                            let albumName: String?
                            let durationInMillis: Int?
                            let url: String?
                            let artwork: Artwork?
                            struct Artwork: Decodable {
                                let url: String?
                                let width: Int?
                                let height: Int?
                            }
                        }
                    }
                    let data: [Item]
                }
                let musicVideos: Collection?
            }
            let results: Results
        }
        guard let response = try? Self.decoder.decode(Response.self, from: data) else { return [] }
        return (response.results.musicVideos?.data ?? []).compactMap { item in
            guard let a = item.attributes, let name = a.name else { return nil }
            return AppleMusicMusicVideo(
                id: item.id,
                title: name,
                artistName: a.artistName ?? "",
                albumTitle: a.albumName,
                artworkURL: a.artwork.flatMap { URL(string: Self.fixedArtworkURL($0.url ?? "", width: $0.width)) },
                duration: a.durationInMillis.map { TimeInterval($0) / 1000.0 },
                url: a.url.flatMap(URL.init)
            )
        }
    }

    func searchStations(_ term: String, limit: Int = 12) async -> [AppleMusicStation] {
        guard canAccessCatalog, !term.isEmpty else { return [] }
        let data = await performGET(
            path: "/v1/catalog/\(storefront)/search",
            query: [
                URLQueryItem(name: "term", value: term),
                URLQueryItem(name: "types", value: "stations"),
                URLQueryItem(name: "limit", value: String(limit)),
            ],
            needsUserToken: false
        )
        guard let data else { return [] }
        struct Response: Decodable {
            struct Results: Decodable {
                struct Collection: Decodable {
                    struct Item: Decodable {
                        let id: String
                        let attributes: Attributes?
                        struct Attributes: Decodable {
                            let name: String?
                            let tagline: String?
                            let url: String?
                            let artwork: Artwork?
                            struct Artwork: Decodable {
                                let url: String?
                                let width: Int?
                                let height: Int?
                            }
                        }
                    }
                    let data: [Item]
                }
                let stations: Collection?
            }
            let results: Results
        }
        guard let response = try? Self.decoder.decode(Response.self, from: data) else { return [] }
        return (response.results.stations?.data ?? []).compactMap { item in
            guard let a = item.attributes, let name = a.name else { return nil }
            return AppleMusicStation(
                id: item.id,
                name: name,
                tagline: a.tagline,
                artworkURL: a.artwork.flatMap { URL(string: Self.fixedArtworkURL($0.url ?? "", width: $0.width)) },
                url: a.url.flatMap(URL.init)
            )
        }
    }

    func searchSuggestions(_ term: String, limit: Int = 10) async -> [String] {
        guard canAccessCatalog, !term.isEmpty else { return [] }
        let data = await performGET(
            path: "/v1/catalog/\(storefront)/search/suggestions",
            query: [
                URLQueryItem(name: "term", value: term),
                URLQueryItem(name: "kinds", value: "terms"),
                URLQueryItem(name: "limit", value: String(limit)),
            ],
            needsUserToken: false
        )
        guard let data else { return [] }
        struct Response: Decodable {
            struct Results: Decodable {
                struct Suggestions: Decodable {
                    struct Term: Decodable { let term: String }
                    let terms: [Term]?
                }
                let suggestions: [Suggestions]
            }
            let results: Results
        }
        guard let response = try? Self.decoder.decode(Response.self, from: data) else { return [] }
        return response.results.suggestions.flatMap { $0.terms ?? [] }.map { $0.term }
    }

    // MARK: - Catalog reads (single + multiple resources)

    private func fetchCatalogResources(songs: [String] = [], albums: [String] = [], playlists: [String] = []) async -> Data? {
        guard canAccessCatalog else { return nil }
        var query: [URLQueryItem] = []
        if !songs.isEmpty {
            query.append(URLQueryItem(name: "ids[songs]", value: songs.joined(separator: ",")))
        }
        if !albums.isEmpty {
            query.append(URLQueryItem(name: "ids[albums]", value: albums.joined(separator: ",")))
        }
        if !playlists.isEmpty {
            query.append(URLQueryItem(name: "ids[playlists]", value: playlists.joined(separator: ",")))
        }
        guard !query.isEmpty else { return nil }
        return await performGET(path: "/v1/catalog/\(storefront)", query: query, needsUserToken: false)
    }

    func fetchCatalogSongs(ids: [String]) async -> [AppleMusicSong] {
        guard !ids.isEmpty else { return [] }
        let chunkSize = 300
        var songs: [AppleMusicSong] = []
        for chunk in stride(from: 0, to: ids.count, by: chunkSize) {
            let slice = Array(ids[chunk..<min(chunk + chunkSize, ids.count)])
            guard let data = await fetchCatalogResources(songs: slice) else { continue }
            songs += Self.mapCatalogSongItems(from: data)
        }
        return songs
    }

    func fetchCatalogAlbums(ids: [String]) async -> [AppleMusicAlbum] {
        guard !ids.isEmpty else { return [] }
        guard let data = await fetchCatalogResources(albums: Array(ids.prefix(300))) else { return [] }
        struct Response: Decodable {
            struct Item: Decodable {
                let id: String
                let attributes: Attributes?
                struct Attributes: Decodable {
                    let name: String?
                    let artistName: String?
                    let artwork: Artwork?
                    struct Artwork: Decodable {
                        let url: String?
                        let width: Int?
                        let height: Int?
                    }
                }
            }
            let data: [Item]
        }
        guard let response = try? Self.decoder.decode(Response.self, from: data) else { return [] }
        return response.data.compactMap { item in
            guard let a = item.attributes, let name = a.name else { return nil }
            return AppleMusicAlbum(
                id: item.id,
                title: name,
                artistName: a.artistName ?? "",
                artworkURL: a.artwork.flatMap { URL(string: Self.fixedArtworkURL($0.url ?? "", width: $0.width)) },
                url: nil
            )
        }
    }

    func fetchCatalogSongDetail(id: String) async -> AppleMusicSong? {
        await fetchCatalogSongs(ids: [id]).first
    }

    func fetchCatalogSongsForPlayback(ids: [String]) async -> [Song] {
        guard !ids.isEmpty else { return [] }
        var songs: [Song] = []
        let chunkSize = 300
        for chunk in stride(from: 0, to: ids.count, by: chunkSize) {
            let slice = Array(ids[chunk..<min(chunk + chunkSize, ids.count)])
            guard let data = await fetchCatalogResources(songs: slice) else { continue }
            if let decoded = try? Self.decoder.decode(MusicItemCollection<Song>.self, from: data) {
                songs += decoded
            }
        }
        return songs
    }

    func fetchAlbumCharts(limit: Int = 12) async -> [AppleMusicAlbum] {
        guard canAccessCatalog else { return [] }
        let data = await performGET(path: "/v1/catalog/\(storefront)/charts", query: [
            URLQueryItem(name: "types", value: "albums"),
            URLQueryItem(name: "limit", value: String(limit)),
        ], needsUserToken: false)
        guard let data else { return [] }
        struct ChartsResponse: Decodable {
            struct Results: Decodable {
                struct Album: Decodable {
                    let id: String
                    let attributes: Attributes?
                    struct Attributes: Decodable {
                        let name: String?
                        let artistName: String?
                        let artwork: Artwork?
                        struct Artwork: Decodable {
                            let url: String?
                            let width: Int?
                            let height: Int?
                        }
                    }
                }
                let albums: [Album]?
            }
            let results: Results
        }
        guard let response = try? Self.decoder.decode(ChartsResponse.self, from: data) else { return [] }
        return (response.results.albums ?? []).compactMap { item in
            guard let a = item.attributes, let name = a.name else { return nil }
            return AppleMusicAlbum(
                id: item.id,
                title: name,
                artistName: a.artistName ?? "",
                artworkURL: a.artwork.flatMap { URL(string: Self.fixedArtworkURL($0.url ?? "", width: $0.width)) },
                url: nil
            )
        }
    }

    // MARK: - Library reads (parity with MusadoraKit `MLibrary`)

    func fetchRecentlyAdded(limit: Int = 20) async -> [AppleMusicSong] {
        guard await refreshAuthIfNeeded() else { return [] }
        let data = await performGET(path: "/v1/me/library/recently-added", query: [
            URLQueryItem(name: "limit", value: String(limit)),
        ])
        guard let data else { return [] }
        return Self.mapCatalogSongItems(from: data)
    }

    func fetchLibraryAlbums(limit: Int = 100) async -> [AppleMusicAlbum] {
        guard await refreshAuthIfNeeded() else { return [] }
        let data = await performGET(path: "/v1/me/library/albums", query: [
            URLQueryItem(name: "limit", value: String(limit)),
        ])
        guard let data else { return [] }
        struct Response: Decodable {
            struct Item: Decodable {
                let id: String
                let attributes: Attributes?
                struct Attributes: Decodable {
                    let name: String?
                    let artistName: String?
                    let artwork: Artwork?
                    struct Artwork: Decodable {
                        let url: String?
                        let width: Int?
                        let height: Int?
                    }
                }
            }
            let data: [Item]
        }
        guard let response = try? Self.decoder.decode(Response.self, from: data) else { return [] }
        return response.data.compactMap { item in
            guard let a = item.attributes, let name = a.name else { return nil }
            return AppleMusicAlbum(
                id: item.id,
                title: name,
                artistName: a.artistName ?? "",
                artworkURL: a.artwork.flatMap { URL(string: Self.fixedArtworkURL($0.url ?? "", width: $0.width)) },
                url: nil
            )
        }
    }

    func fetchLibraryArtists(limit: Int = 100) async -> [AppleMusicArtist] {
        guard await refreshAuthIfNeeded() else { return [] }
        let data = await performGET(path: "/v1/me/library/artists", query: [
            URLQueryItem(name: "limit", value: String(limit)),
        ])
        guard let data else { return [] }
        struct Response: Decodable {
            struct Item: Decodable {
                let id: String
                let attributes: Attributes?
                struct Attributes: Decodable {
                    let name: String?
                    let artwork: Artwork?
                    struct Artwork: Decodable {
                        let url: String?
                        let width: Int?
                        let height: Int?
                    }
                }
            }
            let data: [Item]
        }
        guard let response = try? Self.decoder.decode(Response.self, from: data) else { return [] }
        return response.data.compactMap { item in
            guard let a = item.attributes, let name = a.name else { return nil }
            return AppleMusicArtist(
                id: item.id,
                name: name,
                artworkURL: a.artwork.flatMap { URL(string: Self.fixedArtworkURL($0.url ?? "", width: $0.width)) },
                url: nil
            )
        }
    }

    func isInLibrary(songID: String) async -> Bool {
        guard await refreshAuthIfNeeded() else { return false }
        let data = await performGET(path: "/v1/me/library", query: [
            URLQueryItem(name: "ids[songs]", value: songID),
        ])
        guard let data else { return false }
        struct Response: Decodable { let data: [Item]; struct Item: Decodable { let id: String } }
        guard let response = try? Self.decoder.decode(Response.self, from: data) else { return false }
        return !response.data.isEmpty
    }

    // MARK: - Library mutations (add / remove / playlists)

    @discardableResult
    func addToLibrary(songIDs: [String] = [], albumIDs: [String] = [], playlistIDs: [String] = []) async -> Bool {
        guard await refreshAuthIfNeeded() else { return false }
        var query: [URLQueryItem] = []
        if !songIDs.isEmpty {
            query.append(URLQueryItem(name: "ids[songs]", value: songIDs.joined(separator: ",")))
        }
        if !albumIDs.isEmpty {
            query.append(URLQueryItem(name: "ids[albums]", value: albumIDs.joined(separator: ",")))
        }
        if !playlistIDs.isEmpty {
            query.append(URLQueryItem(name: "ids[playlists]", value: playlistIDs.joined(separator: ",")))
        }
        guard !query.isEmpty else { return false }
        guard let url = makeURL(path: "/v1/me/library", query: query) else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(developerToken)", forHTTPHeaderField: "Authorization")
        request.setValue(userToken, forHTTPHeaderField: "Music-User-Token")
        request.setValue(userToken, forHTTPHeaderField: "media-user-token")
        request.setValue("https://music.apple.com", forHTTPHeaderField: "Origin")
        request.setValue("https://music.apple.com/", forHTTPHeaderField: "Referer")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }
            return http.statusCode == 202 || (200...299).contains(http.statusCode)
        } catch {
            return false
        }
    }

    @discardableResult
    func removeFromLibrary(songIDs: [String] = [], albumIDs: [String] = [], playlistIDs: [String] = []) async -> Bool {
        guard await refreshAuthIfNeeded() else { return false }
        var query: [URLQueryItem] = []
        if !songIDs.isEmpty {
            query.append(URLQueryItem(name: "ids[songs]", value: songIDs.joined(separator: ",")))
        }
        if !albumIDs.isEmpty {
            query.append(URLQueryItem(name: "ids[albums]", value: albumIDs.joined(separator: ",")))
        }
        if !playlistIDs.isEmpty {
            query.append(URLQueryItem(name: "ids[playlists]", value: playlistIDs.joined(separator: ",")))
        }
        guard !query.isEmpty else { return false }
        guard let url = makeURL(path: "/v1/me/library", query: query) else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(developerToken)", forHTTPHeaderField: "Authorization")
        request.setValue(userToken, forHTTPHeaderField: "Music-User-Token")
        request.setValue(userToken, forHTTPHeaderField: "media-user-token")
        request.setValue("https://music.apple.com", forHTTPHeaderField: "Origin")
        request.setValue("https://music.apple.com/", forHTTPHeaderField: "Referer")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }
            return (200...299).contains(http.statusCode)
        } catch {
            return false
        }
    }

    func createPlaylist(name: String, description: String? = nil, songIDs: [String] = []) async -> String? {
        guard await refreshAuthIfNeeded() else { return nil }
        var attributes: [String: Any] = ["name": name]
        if let description, !description.isEmpty {
            attributes["description"] = description
        }
        var body: [String: Any] = ["attributes": attributes]
        if !songIDs.isEmpty {
            let tracksData = songIDs.map { ["id": $0, "type": "songs"] as [String: Any] }
            body["relationships"] = ["tracks": ["data": tracksData]]
        }
        let data = await performMutationData(path: "/v1/me/library/playlists", method: "POST", body: body)
        guard let data else { return nil }
        struct Response: Decodable {
            struct Item: Decodable { let id: String }
            let data: [Item]
        }
        guard let response = try? Self.decoder.decode(Response.self, from: data) else { return nil }
        return response.data.first?.id
    }

    @discardableResult
    func addTracksToPlaylist(songIDs: [String], playlistID: String) async -> Bool {
        guard await refreshAuthIfNeeded(), !songIDs.isEmpty else { return false }
        let tracksData = songIDs.map { ["id": $0, "type": "songs"] as [String: Any] }
        let body: [String: Any] = ["data": tracksData]
        let ok = await performMutation(
            path: "/v1/me/library/playlists/\(playlistID)/tracks",
            method: "POST",
            body: body
        )
        return ok
    }

    @discardableResult
    func deletePlaylist(playlistID: String) async -> Bool {
        guard await refreshAuthIfNeeded() else { return false }
        return await performMutation(path: "/v1/me/library/playlists/\(playlistID)", method: "DELETE")
    }

    // MARK: - Ratings (library + catalog)

    private enum RatingResource: String {
        case librarySongs = "library-songs"
        case libraryAlbums = "library-albums"
        case libraryPlaylists = "library-playlists"
        case libraryMusicVideos = "library-music-videos"
        case songs = "songs"
        case albums = "albums"
        case playlists = "playlists"
    }

    private func ratingsPath(resource: RatingResource, ids: [String]) -> String {
        let base = resource.rawValue.hasPrefix("library-") ? "/v1/me/ratings" : "/v1/catalog/\(storefront)/ratings"
        return "\(base)/\(resource.rawValue)?ids=\(ids.joined(separator: ","))"
    }

    func fetchRatings(songIDs: [String] = [], albumIDs: [String] = [], playlistIDs: [String] = []) async -> [AppleMusicRating] {
        guard await refreshAuthIfNeeded() else { return [] }
        var results: [AppleMusicRating] = []
        if !songIDs.isEmpty, let data = await performGET(path: ratingsPath(resource: .librarySongs, ids: songIDs)) {
            results += Self.decodeRatings(from: data)
        }
        if !albumIDs.isEmpty, let data = await performGET(path: ratingsPath(resource: .libraryAlbums, ids: albumIDs)) {
            results += Self.decodeRatings(from: data)
        }
        if !playlistIDs.isEmpty, let data = await performGET(path: ratingsPath(resource: .libraryPlaylists, ids: playlistIDs)) {
            results += Self.decodeRatings(from: data)
        }
        return results
    }

    func fetchCatalogRating(resource: String, id: String) async -> AppleMusicRating? {
        guard canAccessCatalog else { return nil }
        let path = "/v1/catalog/\(storefront)/\(resource)/\(id)/rating"
        guard let data = await performGET(path: path, needsUserToken: false) else { return nil }
        return Self.decodeRatings(from: data).first
    }

    @discardableResult
    func setRating(value: Int, songID: String, resource: String = "library-songs") async -> Bool {
        guard await refreshAuthIfNeeded() else { return false }
        let base = resource.hasPrefix("library-") ? "/v1/me/ratings" : "/v1/catalog/\(storefront)/ratings"
        let ok = await performMutation(
            path: "\(base)/\(resource)/\(songID)",
            method: "PUT",
            body: ["attributes": ["value": value]]
        )
        return ok
    }

    @discardableResult
    func deleteRating(songID: String, resource: String = "library-songs") async -> Bool {
        guard await refreshAuthIfNeeded() else { return false }
        let base = resource.hasPrefix("library-") ? "/v1/me/ratings" : "/v1/catalog/\(storefront)/ratings"
        return await performMutation(path: "\(base)/\(resource)/\(songID)", method: "DELETE")
    }

    private static func decodeRatings(from data: Data) -> [AppleMusicRating] {
        struct Response: Decodable {
            struct Item: Decodable {
                let id: String
                let type: String?
                let attributes: Attributes?
                struct Attributes: Decodable {
                    let value: FlexibleInt?
                }
            }
            let data: [Item]
        }
        guard let response = try? decoder.decode(Response.self, from: data) else { return [] }
        return response.data.compactMap { item in
            guard let value = item.attributes?.value?.intValue else { return nil }
            return AppleMusicRating(id: item.id, type: item.type ?? "", value: value)
        }
    }

    // MARK: - Replay (music summaries)

    func fetchLatestReplay(limit: Int = 50) async -> AppleMusicReplaySummary {
        guard await refreshAuthIfNeeded() else { return AppleMusicReplaySummary() }
        let data = await performGET(path: "/v1/me/music-summaries", query: [
            URLQueryItem(name: "filter[year]", value: "latest"),
            URLQueryItem(name: "views", value: "top-artists,top-albums,top-songs"),
            URLQueryItem(name: "include", value: "artist,album,song"),
            URLQueryItem(name: "limit", value: String(limit)),
        ])
        guard let data else { return AppleMusicReplaySummary() }
        return Self.decodeReplaySummary(from: data)
    }

    private static func decodeReplaySummary(from data: Data) -> AppleMusicReplaySummary {
        struct Response: Decodable {
            struct Item: Decodable {
                struct Views: Decodable {
                    struct View: Decodable {
                        struct DataItem: Decodable {
                            let id: String
                            let attributes: Attributes?
                            struct Attributes: Decodable {
                                let name: String?
                                let artistName: String?
                                let albumName: String?
                                let artwork: Artwork?
                                struct Artwork: Decodable {
                                    let url: String?
                                    let width: Int?
                                    let height: Int?
                                }
                            }
                        }
                        let data: [DataItem]?
                    }
                    let topSongs: View?
                    let topAlbums: View?
                    let topArtists: View?
                }
                let views: Views?
            }
            let data: [Item]
        }

        guard let response = try? decoder.decode(Response.self, from: data),
              let views = response.data.first?.views else { return AppleMusicReplaySummary() }

        func mapSongs(_ view: Response.Item.Views.View?) -> [AppleMusicSong] {
            (view?.data ?? []).compactMap { item in
                guard let a = item.attributes, let name = a.name else { return nil }
                return AppleMusicSong(
                    id: item.id,
                    title: name,
                    artistName: a.artistName ?? "",
                    albumTitle: a.albumName,
                    artworkURL: a.artwork.flatMap { URL(string: fixedArtworkURL($0.url ?? "", width: $0.width)) },
                    duration: nil,
                    url: nil
                )
            }
        }
        func mapAlbums(_ view: Response.Item.Views.View?) -> [AppleMusicAlbum] {
            (view?.data ?? []).compactMap { item in
                guard let a = item.attributes, let name = a.name else { return nil }
                return AppleMusicAlbum(
                    id: item.id,
                    title: name,
                    artistName: a.artistName ?? "",
                    artworkURL: a.artwork.flatMap { URL(string: fixedArtworkURL($0.url ?? "", width: $0.width)) },
                    url: nil
                )
            }
        }
        func mapArtists(_ view: Response.Item.Views.View?) -> [AppleMusicArtist] {
            (view?.data ?? []).compactMap { item in
                guard let a = item.attributes, let name = a.name else { return nil }
                return AppleMusicArtist(
                    id: item.id,
                    name: name,
                    artworkURL: a.artwork.flatMap { URL(string: fixedArtworkURL($0.url ?? "", width: $0.width)) },
                    url: nil
                )
            }
        }

        return AppleMusicReplaySummary(
            topSongs: mapSongs(views.topSongs),
            topAlbums: mapAlbums(views.topAlbums),
            topArtists: mapArtists(views.topArtists)
        )
    }

    // MARK: - Related / suggested tracks

    func fetchArtistCatalogTracks(artistName: String) async -> [AppleMusicSong] {
        let query = artistName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        let results = await search(query)
        let wanted = query.lowercased()
        return results.songs.filter {
            let name = $0.artistName.lowercased()
            return !name.isEmpty && (name.contains(wanted) || wanted.contains(name))
        }
    }

    // MARK: - Personalization, charts & catalog depth (feature parity)

    private static func mapCatalogSongItems(from data: Data) -> [AppleMusicSong] {
        struct Response: Decodable {
            struct Item: Decodable {
                let id: String
                let attributes: Attributes?
                struct Attributes: Decodable {
                    let name: String?
                    let artistName: String?
                    let albumName: String?
                    let durationInMillis: Int?
                    let artwork: Artwork?
                    struct Artwork: Decodable {
                        let url: String?
                        let width: Int?
                        let height: Int?
                    }
                }
            }
            let data: [Item]
        }
        guard let response = try? Self.decoder.decode(Response.self, from: data) else { return [] }
        return response.data.compactMap { item in
            guard let a = item.attributes, let name = a.name else { return nil }
            return AppleMusicSong(
                id: item.id,
                title: name,
                artistName: a.artistName ?? "",
                albumTitle: a.albumName,
                artworkURL: a.artwork.flatMap { URL(string: Self.fixedArtworkURL($0.url ?? "", width: $0.width)) },
                duration: a.durationInMillis.map { TimeInterval($0) / 1000.0 },
                url: nil
            )
        }
    }

    func fetchRecentlyPlayed(limit: Int = 25) async -> [AppleMusicSong] {
        guard await refreshAuthIfNeeded() else { return [] }
        let data = await performGET(path: "/v1/me/recent/played/tracks", query: [
            URLQueryItem(name: "limit", value: String(limit)),
        ])
        guard let data else { return [] }
        return Self.mapCatalogSongItems(from: data)
    }

    func fetchCharts(limit: Int = 25) async -> [AppleMusicSong] {
        guard canAccessCatalog else { return [] }
        let data = await performGET(path: "/v1/catalog/\(storefront)/charts", query: [
            URLQueryItem(name: "types", value: "songs"),
            URLQueryItem(name: "limit", value: String(limit)),
        ], needsUserToken: false)
        guard let data else { return [] }

        struct ChartsResponse: Decodable {
            struct Results: Decodable {
                struct Song: Decodable {
                    let id: String
                    let attributes: Attributes?
                    struct Attributes: Decodable {
                        let name: String?
                        let artistName: String?
                        let albumName: String?
                        let artwork: Artwork?
                        struct Artwork: Decodable {
                            let url: String?
                            let width: Int?
                            let height: Int?
                        }
                    }
                }
                let songs: [Song]?
            }
            let results: Results
        }

        guard let response = try? Self.decoder.decode(ChartsResponse.self, from: data) else { return [] }
        return (response.results.songs ?? []).compactMap { item in
            guard let a = item.attributes, let name = a.name else { return nil }
            return AppleMusicSong(
                id: item.id,
                title: name,
                artistName: a.artistName ?? "",
                albumTitle: a.albumName,
                artworkURL: a.artwork.flatMap { URL(string: Self.fixedArtworkURL($0.url ?? "", width: $0.width)) },
                duration: nil,
                url: nil
            )
        }
    }

    func fetchArtistTopTracks(artistID: String, limit: Int = 25) async -> [AppleMusicSong] {
        guard canAccessCatalog else { return [] }
        if let data = await performGET(path: "/v1/catalog/\(storefront)/artists/\(artistID)/top-tracks", query: [
            URLQueryItem(name: "limit", value: String(limit)),
        ], needsUserToken: false) {
            let songs = Self.mapCatalogSongItems(from: data)
            if !songs.isEmpty { return songs }
        }
        guard let artist = await fetchCatalogArtist(id: artistID) else { return [] }
        return await fetchArtistCatalogTracks(artistName: artist.name)
    }

    private func fetchCatalogArtist(id: String) async -> AppleMusicArtist? {
        guard canAccessCatalog else { return nil }
        let data = await performGET(path: "/v1/catalog/\(storefront)/artists/\(id)", needsUserToken: false)
        guard let data else { return nil }
        struct Response: Decodable {
            struct Item: Decodable {
                let id: String
                let attributes: Attributes?
                struct Attributes: Decodable {
                    let name: String?
                    let artwork: Artwork?
                    struct Artwork: Decodable {
                        let url: String?
                        let width: Int?
                        let height: Int?
                    }
                }
            }
            let data: [Item]
        }
        guard let response = try? Self.decoder.decode(Response.self, from: data),
              let item = response.data.first,
              let name = item.attributes?.name else { return nil }
        return AppleMusicArtist(
            id: item.id,
            name: name,
            artworkURL: item.attributes?.artwork.flatMap { URL(string: Self.fixedArtworkURL($0.url ?? "", width: $0.width)) },
            url: nil
        )
    }

    func fetchArtistAlbums(artistID: String, limit: Int = 25) async -> [AppleMusicAlbum] {
        guard canAccessCatalog else { return [] }
        let data = await performGET(path: "/v1/catalog/\(storefront)/artists/\(artistID)/albums", query: [
            URLQueryItem(name: "limit", value: String(limit)),
        ], needsUserToken: false)
        guard let data else { return [] }

        struct Response: Decodable {
            struct Item: Decodable {
                let id: String
                let attributes: Attributes?
                struct Attributes: Decodable {
                    let name: String?
                    let artistName: String?
                    let artwork: Artwork?
                    struct Artwork: Decodable {
                        let url: String?
                        let width: Int?
                        let height: Int?
                    }
                }
            }
            let data: [Item]
        }

        guard let response = try? Self.decoder.decode(Response.self, from: data) else { return [] }
        return response.data.compactMap { item in
            guard let a = item.attributes, let name = a.name else { return nil }
            return AppleMusicAlbum(
                id: item.id,
                title: name,
                artistName: a.artistName ?? "",
                artworkURL: a.artwork.flatMap { URL(string: Self.fixedArtworkURL($0.url ?? "", width: $0.width)) },
                url: nil
            )
        }
    }

    func fetchAlbumTracks(albumID: String, limit: Int = 100) async -> [AppleMusicSong] {
        guard canAccessCatalog else { return [] }
        let data = await performGET(path: "/v1/catalog/\(storefront)/albums/\(albumID)/tracks", query: [
            URLQueryItem(name: "limit", value: String(limit)),
        ], needsUserToken: false)
        guard let data else { return [] }
        return Self.mapCatalogSongItems(from: data)
    }

    func fetchCatalogPlaylistTracks(playlistID: String, limit: Int = 200) async -> [AppleMusicSong] {
        guard canAccessCatalog else { return [] }
        let data = await performGET(path: "/v1/catalog/\(storefront)/playlists/\(playlistID)/tracks", query: [
            URLQueryItem(name: "limit", value: String(limit)),
        ], needsUserToken: false)
        guard let data else { return [] }
        return Self.mapCatalogSongItems(from: data)
    }

    func fetchHeavyRotation(limit: Int = 15) async -> [AppleMusicAlbum] {
        guard await refreshAuthIfNeeded() else { return [] }
        let data = await performGET(path: "/v1/me/history/heavy-rotation", query: [
            URLQueryItem(name: "limit", value: String(limit)),
        ])
        guard let data else { return [] }

        struct Response: Decodable {
            struct Item: Decodable {
                let id: String
                let type: String?
                let attributes: Attributes?
                struct Attributes: Decodable {
                    let name: String?
                    let artistName: String?
                    let artwork: Artwork?
                    struct Artwork: Decodable {
                        let url: String?
                        let width: Int?
                        let height: Int?
                    }
                }
            }
            let data: [Item]
        }

        guard let response = try? Self.decoder.decode(Response.self, from: data) else { return [] }
        return response.data.compactMap { item in
            guard let a = item.attributes, let name = a.name else { return nil }
            guard item.type == "albums" || item.type == "artists" else { return nil }
            return AppleMusicAlbum(
                id: item.id,
                title: name,
                artistName: a.artistName ?? "",
                artworkURL: a.artwork.flatMap { URL(string: Self.fixedArtworkURL($0.url ?? "", width: $0.width)) },
                url: nil
            )
        }
    }

    func fetchForYouPlaylists(limit: Int = 10) async -> [AppleMusicPlaylist] {
        guard await refreshAuthIfNeeded() else { return [] }
        let data = await performGET(path: "/v1/me/recommendations", query: [
            URLQueryItem(name: "limit", value: String(limit)),
        ])
        guard let data else { return [] }

        struct Response: Decodable {
            struct Item: Decodable {
                let id: String
                let type: String?
                let attributes: Attributes?
                struct Attributes: Decodable {
                    let name: String?
                    let artwork: Artwork?
                    struct Artwork: Decodable {
                        let url: String?
                        let width: Int?
                        let height: Int?
                    }
                }
            }
            let data: [Item]
        }

        guard let response = try? Self.decoder.decode(Response.self, from: data) else { return [] }
        return response.data.compactMap { item in
            guard let a = item.attributes, let name = a.name else { return nil }
            guard item.type == "playlists" || item.type == "library-playlists" else { return nil }
            return AppleMusicPlaylist(
                id: item.id,
                name: name,
                curatorName: item.type == "playlists" ? "Apple Music" : "Your Library",
                artworkURL: a.artwork.flatMap { URL(string: Self.fixedArtworkURL($0.url ?? "", width: $0.width)) },
                url: nil
            )
        }
    }

    // MARK: - Library (private API, mirrors MusicKit library reads with richer data)

    func fetchLibraryPlaylists() async -> [SpotifyPlaylist] {
        guard await refreshAuthIfNeeded() else { return [] }
        let data = await performGET(path: "/v1/me/library/playlists", query: [URLQueryItem(name: "limit", value: "100")])
        guard let data else { return [] }

        struct PlaylistsResponse: Decodable {
            struct Item: Decodable {
                let id: String
                let attributes: Attributes?
                struct Attributes: Decodable {
                    let name: String?
                    let curatorName: String?
                    let artwork: Artwork?
                    let url: String?
                    struct Artwork: Decodable {
                        let url: String?
                        let width: Int?
                        let height: Int?
                    }
                }
            }
            let data: [Item]
        }

        guard let response = try? Self.decoder.decode(PlaylistsResponse.self, from: data) else { return [] }
        return response.data.map { item in
            let a = item.attributes
            return SpotifyPlaylist(
                id: item.id,
                name: a?.name ?? "Untitled Playlist",
                uri: item.id,
                images: a?.artwork?.url.map { [SpotifyImage(url: Self.fixedArtworkURL($0, width: a?.artwork?.width))] } ?? [],
                owner: SpotifyUserSimple(id: "apple_music", displayName: "Me", images: nil),
                collaborators: nil
            )
        }
    }

    func fetchPlaylistTracks(playlistID: String) async -> [SpotifyTrack] {
        guard await refreshAuthIfNeeded() else { return [] }
        let data = await performGET(
            path: "/v1/me/library/playlists/\(playlistID)/tracks",
            query: [URLQueryItem(name: "limit", value: "200")]
        )
        guard let data else { return [] }
        return Self.mapLibrarySongItems(from: data)
    }

    func fetchLibrarySongs() async -> [SpotifyTrack] {
        guard await refreshAuthIfNeeded() else { return [] }
        let data = await performGET(
            path: "/v1/me/library/songs",
            query: [URLQueryItem(name: "limit", value: "100"), URLQueryItem(name: "include", value: "playCount")]
        )
        guard let data else { return [] }
        return Self.mapLibrarySongItems(from: data)
    }

    private static func mapLibrarySongItems(from data: Data) -> [SpotifyTrack] {
        struct SongsResponse: Decodable {
            struct Item: Decodable {
                let id: String
                let attributes: Attributes?
                struct Attributes: Decodable {
                    let name: String?
                    let artistName: String?
                    let albumName: String?
                    let durationInMillis: Int?
                    let artwork: Artwork?
                    struct Artwork: Decodable {
                        let url: String?
                        let width: Int?
                        let height: Int?
                    }
                }
            }
            let data: [Item]
        }

        guard let response = try? Self.decoder.decode(SongsResponse.self, from: data) else { return [] }
        return response.data.compactMap { item in
            guard let a = item.attributes, let name = a.name else { return nil }
            return SpotifyTrack(
                id: item.id,
                name: name,
                uri: item.id,
                album: SpotifyAlbum(
                    name: a.albumName ?? "",
                    images: a.artwork?.url.map { [SpotifyImage(url: Self.fixedArtworkURL($0, width: a.artwork?.width))] } ?? []
                ),
                artists: a.artistName.map { [$0].map { SpotifyArtist(name: $0) } } ?? [],
                durationMs: a.durationInMillis ?? 0,
                popularity: nil
            )
        }
    }

    private static func fixedArtworkURL(_ urlString: String, width: Int?) -> String {
        let size = width.map { "\($0)x\($0)bb" } ?? "300x300bb"
        return urlString
            .replacingOccurrences(of: "{w}x{h}bb", with: size)
            .replacingOccurrences(of: "{w}x{h}", with: size)
    }
}

struct FlexibleInt: Decodable {
    let intValue: Int

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let int = try? container.decode(Int.self) {
            intValue = int
        } else if let string = try? container.decode(String.self), let parsed = Int(string) {
            intValue = parsed
        } else {
            throw DecodingError.typeMismatch(
                Int.self,
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Expected Int or numeric String.")
            )
        }
    }
}