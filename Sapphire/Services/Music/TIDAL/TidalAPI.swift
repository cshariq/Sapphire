//
//  TidalAPI.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-05.
//

import Foundation
import AppKit
import Combine
import CryptoKit

// MARK: - JSON:API Envelope Models

struct TidalJSONAPIDocument<T: Decodable>: Decodable {
    let data: T?
    let included: [TidalResource]?
    let links: TidalLinks?
}

struct TidalLinks: Decodable {
    let selfLink: String?
    let next: String?
    let nextCursor: String?

    enum CodingKeys: String, CodingKey {
        case selfLink = "self"
        case next
    }

    private struct LinksMeta: Decodable { let nextCursor: String? }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        selfLink = try? container.decode(String.self, forKey: .selfLink)
        next = try? container.decode(String.self, forKey: .next)
        nextCursor = ((try? container.decode(LinksMeta.self, forKey: .next))?.nextCursor) ?? nil
    }
}

struct TidalResource: Decodable {
    let id: String
    let type: String
    let attributes: TidalAttributesPayload?
    let relationships: [String: TidalRelationship]?

    enum CodingKeys: String, CodingKey {
        case id, type, attributes, relationships
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        type = try container.decode(String.self, forKey: .type)
        attributes = try? container.decode(TidalAttributesPayload.self, forKey: .attributes)
        relationships = try? container.decode([String: TidalRelationship].self, forKey: .relationships)
    }
}

struct TidalAttributesPayload: Decodable {
    let raw: [String: AnyDecodableValue]

    init(from decoder: Decoder) throws {
        raw = try [String: AnyDecodableValue](from: decoder)
    }

    func string(_ key: String) -> String? {
        (raw[key]?.value as? String)?.isEmpty == false ? raw[key]?.value as? String : nil
    }

    func bool(_ key: String) -> Bool? {
        raw[key]?.value as? Bool
    }

    func int(_ key: String) -> Int? {
        if let i = raw[key]?.value as? Int { return i }
        if let d = raw[key]?.value as? Double { return Int(d) }
        return nil
    }

    func double(_ key: String) -> Double? {
        if let d = raw[key]?.value as? Double { return d }
        if let i = raw[key]?.value as? Int { return Double(i) }
        return nil
    }
}

enum AnyDecodableValue: Decodable {
    case string(String)
    case bool(Bool)
    case int(Int)
    case double(Double)
    case array([AnyDecodableValue])
    case dictionary([String: AnyDecodableValue])
    case null

    var value: Any? {
        switch self {
        case .string(let v): return v
        case .bool(let v): return v
        case .int(let v): return v
        case .double(let v): return v
        case .array(let v): return v.map { $0.value }
        case .dictionary(let v): return v.mapValues { $0.value }
        case .null: return nil
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null; return }
        if let v = try? container.decode(Bool.self) { self = .bool(v); return }
        if let v = try? container.decode(Int.self) { self = .int(v); return }
        if let v = try? container.decode(Double.self) { self = .double(v); return }
        if let v = try? container.decode(String.self) { self = .string(v); return }
        if let v = try? container.decode([AnyDecodableValue].self) { self = .array(v); return }
        if let v = try? container.decode([String: AnyDecodableValue].self) { self = .dictionary(v); return }
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON:API value")
    }
}

struct TidalRelationship: Decodable {
    let ids: [String]

    struct TidalRelationshipData: Decodable {
        let id: String?
        let type: String?
    }

    enum DataKey: String, CodingKey { case data }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DataKey.self)
        if let single = try? container.decode(TidalRelationshipData.self, forKey: .data) {
            ids = single.id.map { [$0] } ?? []
        } else if let many = try? container.decode([TidalRelationshipData].self, forKey: .data) {
            ids = many.compactMap { $0.id }
        } else {
            ids = []
        }
    }
}

// MARK: - Domain Models

struct TidalUser {
    let id: String
    let username: String?
    let country: String?
    let developerAccessTier: String?
}

struct TidalSearchHit {
    let track: SpotifyTrack?
    let trackID: String?
}

// MARK: - Manager

@MainActor
class TidalAPIManager: ObservableObject {
    static let shared = TidalAPIManager()

    @Published var isAuthenticated = false
    @Published var hasApiKeys = false
    @Published var userProfile: TidalUser?

    private var accessToken: String?
    private var refreshToken: String?
    private var accessTokenExpiresAt: Date?
    private var clientId = ""
    private var clientSecret = ""
    private let redirectURI = "sapphire://callback"
    private let baseURL = "https://openapi.tidal.com/v2"
    private let tokenURL = "https://auth.tidal.com/v1/oauth2/token"
    private let authorizeURL = "https://login.tidal.com/authorize"

    static let authorizationScopes = [
        "user.read", "search.read",
        "collection.read", "collection.write", "playlists.read", "playlists.write"
    ]

    private var refreshTask: Task<Bool, Never>?
    private var pkceCodeVerifier: String?

    private init() {
        updateCredentials()
        NotificationCenter.default.addObserver(
            forName: .apiKeyManagerTidalCredentialsChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.updateCredentials() }
        }

        self.accessToken = UserDefaults.standard.string(forKey: "tidalAccessToken")
        self.refreshToken = UserDefaults.standard.string(forKey: "tidalRefreshToken")
        self.accessTokenExpiresAt = UserDefaults.standard.object(forKey: "tidalAccessTokenExpiresAt") as? Date
        self.isAuthenticated = self.accessToken != nil

        if self.refreshToken != nil {
            Task { await self.refreshTokenIfNeeded() }
        }
    }

    private func updateCredentials() {
        let clientId = APIKeyManager.shared.tidalClientId
        let clientSecret = APIKeyManager.shared.tidalClientSecret
        self.clientId = clientId
        self.clientSecret = clientSecret
        let nowHasKeys = !clientId.isEmpty && !clientSecret.isEmpty
        if self.hasApiKeys != nowHasKeys {
            self.hasApiKeys = nowHasKeys
        }
    }

    // MARK: - Authentication (Authorization Code + PKCE)

    private static func generateCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 48)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncodedString()
    }

    private static func codeChallenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).base64URLEncodedString()
    }

    func makeAuthorizeURL() -> URL? {
        updateCredentials()
        guard !clientId.isEmpty, !clientSecret.isEmpty else {
            print("[TidalAPIManager] Log in failed: Client ID or Client Secret is missing.")
            return nil
        }

        let verifier = Self.generateCodeVerifier()
        self.pkceCodeVerifier = verifier

        var components = URLComponents(string: authorizeURL)!
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: Self.authorizationScopes.joined(separator: " ")),
            URLQueryItem(name: "code_challenge", value: Self.codeChallenge(for: verifier)),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
        ]
        return components.url
    }

    func login() {
        guard let url = makeAuthorizeURL() else { return }
        NSWorkspace.shared.open(url)
    }

    func cancelLogin() {
        pkceCodeVerifier = nil
    }

    func handleRedirect(url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
            return
        }
        Task { await self.exchangeCodeForToken(code: code) }
    }

    private struct TokenResponse: Decodable {
        let accessToken: String
        let refreshToken: String?
        let expiresIn: Int
        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case expiresIn = "expires_in"
        }
    }

    private struct TokenErrorResponse: Decodable {
        let error: String?
        let errorDescription: String?
        enum CodingKeys: String, CodingKey {
            case error
            case errorDescription = "error_description"
        }
    }

    private func exchangeCodeForToken(code: String) async {
        guard let verifier = pkceCodeVerifier else {
            print("[TidalAPIManager] Token exchange failed: missing PKCE verifier.")
            return
        }
        var request = URLRequest(url: URL(string: tokenURL)!)
        request.httpMethod = "POST"
        var body = URLComponents()
        body.queryItems = [
            URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "code_verifier", value: verifier),
        ]
        request.httpBody = body.query?.data(using: .utf8)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        await consumeTokenResponse(from: request, storingRefreshToken: true)
        self.pkceCodeVerifier = nil
    }

    private var isAccessTokenValid: Bool {
        guard accessToken != nil, let expiresAt = accessTokenExpiresAt else { return false }
        return Date().addingTimeInterval(60) < expiresAt
    }

    @discardableResult
    func refreshTokenIfNeeded(force: Bool = false) async -> Bool {
        guard let refreshToken = self.refreshToken else {
            self.isAuthenticated = false
            return false
        }
        guard force || !isAccessTokenValid else { return true }

        if let existing = refreshTask {
            return await existing.value
        }

        let task = Task { [weak self] in
            guard let self else { return false }
            return await self.performTokenRefresh(refreshToken: refreshToken)
        }
        refreshTask = task
        let success = await task.value
        refreshTask = nil

        if success {
            await fetchUserProfile()
        }
        return success
    }

    private func performTokenRefresh(refreshToken: String) async -> Bool {
        var request = URLRequest(url: URL(string: tokenURL)!)
        request.httpMethod = "POST"
        var body = URLComponents()
        body.queryItems = [
            URLQueryItem(name: "grant_type", value: "refresh_token"),
            URLQueryItem(name: "refresh_token", value: refreshToken),
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "client_secret", value: clientSecret),
        ]
        request.httpBody = body.query?.data(using: .utf8)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        return await consumeTokenResponse(from: request, storingRefreshToken: true)
    }

    @discardableResult
    private func consumeTokenResponse(from request: URLRequest, storingRefreshToken: Bool) async -> Bool {
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                let errorBody = String(data: data, encoding: .utf8) ?? "No response body"
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                print("[TidalAPIManager] Token request failed (\(statusCode)): \(errorBody)")
                if let errorResponse = try? JSONDecoder().decode(TokenErrorResponse.self, from: data),
                   errorResponse.error == "invalid_grant" {
                    logout()
                }
                return false
            }

            let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
            self.accessToken = tokenResponse.accessToken
            self.accessTokenExpiresAt = Date().addingTimeInterval(TimeInterval(tokenResponse.expiresIn))
            UserDefaults.standard.set(tokenResponse.accessToken, forKey: "tidalAccessToken")
            UserDefaults.standard.set(self.accessTokenExpiresAt, forKey: "tidalAccessTokenExpiresAt")
            if storingRefreshToken, let newRefresh = tokenResponse.refreshToken {
                self.refreshToken = newRefresh
                UserDefaults.standard.set(newRefresh, forKey: "tidalRefreshToken")
            }
            self.isAuthenticated = true
            await fetchUserProfile()
            return true
        } catch {
            print("[TidalAPIManager] Token request failed: \(error)")
            return false
        }
    }

    func logout() {
        refreshTask?.cancel()
        refreshTask = nil
        self.accessToken = nil
        self.refreshToken = nil
        self.accessTokenExpiresAt = nil
        self.userProfile = nil
        self.isAuthenticated = false
        UserDefaults.standard.removeObject(forKey: "tidalAccessToken")
        UserDefaults.standard.removeObject(forKey: "tidalRefreshToken")
        UserDefaults.standard.removeObject(forKey: "tidalAccessTokenExpiresAt")
    }

    // MARK: - User

    func fetchUserProfile() async {
        guard isAuthenticated else { return }

        if userProfile == nil, let userID = Self.userIDFromToken(accessToken) {
            await fetchUser(id: userID)
        }
    }

    private static func userIDFromToken(_ token: String?) -> String? {
        guard let token else { return nil }
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { return nil }
        var segment = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while segment.count % 4 != 0 { segment += "=" }
        guard let payloadData = Data(base64Encoded: segment) else { return nil }
        guard let payload = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any] else { return nil }
        return payload["sub"] as? String
    }

    func fetchUser(id: String) async {
        let document: TidalJSONAPIDocument<TidalResource>? = await get("/users/\(id)")
        guard let resource = document?.data else { return }
        self.userProfile = TidalUser(
            id: resource.id,
            username: resource.attributes?.string("username"),
            country: resource.attributes?.string("country"),
            developerAccessTier: resource.attributes?.string("developerAccessTier")
        )
    }

    // MARK: - Search

    func searchForTrack(title: String, artist: String) async -> SpotifyTrack? {
        let query = "\(title) \(artist)".trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return nil }

        guard let resource = await searchFirstTrack(query: query) else { return nil }
        return Self.spotifyTrack(from: resource, included: nil)
    }

    private func searchFirstTrack(query: String) async -> TidalResource? {
        var components = URLComponents(string: "\(baseURL)/searchResults")!
        components.queryItems = [
            URLQueryItem(name: "filter[query]", value: query),
            URLQueryItem(name: "include", value: "tracks"),
            URLQueryItem(name: "countryCode", value: Locale.current.regionCode ?? "US"),
        ]
        guard let url = components.url else { return nil }
        let document: TidalJSONAPIDocument<TidalResource>? = await requestData(url: url)
        guard let firstID = document?.data?.relationships?["tracks"]?.ids.first else { return nil }
        let included = document?.included ?? []
        return included.first(where: { $0.type == "tracks" && $0.id == firstID })
    }

    // MARK: - Likes (My Collection)

    private func userCollectionTracksID() async -> String? {
        if let id = userProfile?.id { return id }
        await fetchUserProfile()
        return userProfile?.id
    }

    func checkIfTrackIsLiked(trackID: String) async -> Bool? {
        guard let collectionID = await userCollectionTracksID() else { return nil }

        var nextURL: URL? = URL(string: "\(baseURL)/userCollectionTracks/\(collectionID)/relationships/items?include=items&page%5Bcursor%5D=")

        while let url = nextURL {
            let document: TidalJSONAPIDocument<TidalResource>? = await requestData(url: url)
            guard let collection = document?.data else { return nil }
            if collection.relationships?["items"]?.ids.contains(trackID) == true {
                return true
            }
            nextURL = Self.nextPageURL(from: document?.links, fallbackPath: url.path)
        }
        return false
    }

    func likeTrack(trackID: String) async -> Bool {
        guard let collectionID = await userCollectionTracksID() else { return false }
        let payload: [String: Any] = [
            "data": ["id": trackID, "type": "tracks"]
        ]
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return false }
        let result: Bool? = await writeRequest(
            path: "/userCollectionTracks/\(collectionID)/relationships/items",
            method: "POST",
            body: body
        )
        return result == true
    }

    func unlikeTrack(trackID: String) async -> Bool {
        guard let collectionID = await userCollectionTracksID() else { return false }
        let payload: [String: Any] = [
            "data": ["id": trackID, "type": "tracks"]
        ]
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return false }
        let result: Bool? = await writeRequest(
            path: "/userCollectionTracks/\(collectionID)/relationships/items",
            method: "DELETE",
            body: body
        )
        return result == true
    }

    // MARK: - Playlists

    func fetchPlaylists() async -> [SpotifyPlaylist] {
        guard let userID = await userCollectionTracksID() else { return [] }
        var nextURL: URL? = URL(string: "\(baseURL)/userCollectionPlaylists/\(userID)/relationships/items?include=items&page%5Bcursor%5D=")

        var playlists: [SpotifyPlaylist] = []
        while let url = nextURL {
            let document: TidalJSONAPIDocument<TidalResource>? = await requestData(url: url)
            guard let collection = document?.data else { break }
            let included = document?.included ?? []
            for id in collection.relationships?["items"]?.ids ?? [] {
                if let playlist = included.first(where: { $0.type == "playlists" && $0.id == id }),
                   let mapped = Self.spotifyPlaylist(from: playlist, included: included) {
                    playlists.append(mapped)
                }
            }
            nextURL = Self.nextPageURL(from: document?.links, fallbackPath: url.path)
        }
        return playlists
    }

    func fetchPlaylistTracks(playlistID: String) async -> [SpotifyTrack]? {
        var nextURL: URL? = URL(string: "\(baseURL)/playlists/\(playlistID)/relationships/items?include=items&page%5Bcursor%5D=")

        var tracks: [SpotifyTrack] = []
        while let url = nextURL {
            let document: TidalJSONAPIDocument<TidalResource>? = await requestData(url: url)
            guard let playlist = document?.data else { break }
            let included = document?.included ?? []
            for id in playlist.relationships?["items"]?.ids ?? [] {
                if let track = included.first(where: { $0.type == "tracks" && $0.id == id }),
                   let mapped = Self.spotifyTrack(from: track, included: included) {
                    tracks.append(mapped)
                }
            }
            nextURL = Self.nextPageURL(from: document?.links, fallbackPath: url.path)
        }
        return tracks
    }

    private static func nextPageURL(from links: TidalLinks?, fallbackPath: String) -> URL? {
        if let next = links?.next, let url = URL(string: next) { return url }
        guard let cursor = links?.nextCursor, !cursor.isEmpty,
              var components = URLComponents(string: fallbackPath) else { return nil }
        components.queryItems = (components.queryItems ?? []) + [
            URLQueryItem(name: "page[cursor]", value: cursor)
        ]
        return components.url
    }

    // MARK: - JSON:API → Spotify Model Mapping

    private static func artworkURL(for resource: TidalResource, included: [TidalResource]?) -> URL? {
        let relationshipKeys = ["coverArt", "profileArt", "thumbnailArt"]
        for key in relationshipKeys {
            guard let included else { continue }
            for artworkID in resource.relationships?[key]?.ids ?? [] {
                if let artwork = included.first(where: { $0.type == "artworks" && $0.id == artworkID }) {
                    if let url = artworkURL(fromArtwork: artwork) { return url }
                }
            }
        }
        return nil
    }

    private static func artworkURL(fromArtwork artwork: TidalResource) -> URL? {
        guard let files = artwork.attributes?.raw["files"]?.value as? [[String: Any]] else { return nil }
        let sorted = files.sorted { lhs, rhs in
            let lhsMeta = lhs["meta"] as? [String: Any]
            let rhsMeta = rhs["meta"] as? [String: Any]
            let lhsW = (lhsMeta?["width"] as? Int) ?? 0
            let rhsW = (rhsMeta?["width"] as? Int) ?? 0
            return lhsW < rhsW
        }
        let chosen = sorted.last ?? sorted.first
        if let href = chosen?["href"] as? String, let url = URL(string: href) {
            return url
        }
        return nil
    }

    private static func artistNames(for track: TidalResource, included: [TidalResource]?) -> [SpotifyArtist] {
        guard let included else { return [] }
        let names = track.relationships?["artists"]?.ids.compactMap { id -> String? in
            guard let artist = included.first(where: { $0.type == "artists" && $0.id == id }) else { return nil }
            return artist.attributes?.string("name")
        } ?? []
        return names.map { SpotifyArtist(name: $0) }
    }

    static func spotifyTrack(from resource: TidalResource, included: [TidalResource]?) -> SpotifyTrack? {
        guard let attributes = resource.attributes else { return nil }
        let name = attributes.string("title") ?? ""
        guard !name.isEmpty else { return nil }

        let artwork = artworkURL(for: resource, included: included).map { [SpotifyImage(url: $0.absoluteString)] } ?? []
        let albumName = albumTitle(for: resource, included: included)
        let durationMs = durationMilliseconds(from: attributes.string("duration") ?? "")

        return SpotifyTrack(
            id: resource.id,
            name: name,
            uri: "tidal:track:\(resource.id)",
            album: SpotifyAlbum(name: albumName, images: artwork),
            artists: artistNames(for: resource, included: included),
            durationMs: durationMs,
            popularity: attributes.int("popularity")
        )
    }

    private static func albumTitle(for track: TidalResource, included: [TidalResource]?) -> String {
        guard let included else { return "" }
        for id in track.relationships?["albums"]?.ids ?? [] {
            if let album = included.first(where: { $0.type == "albums" && $0.id == id }) {
                return album.attributes?.string("title") ?? ""
            }
        }
        return ""
    }

    private static func durationMilliseconds(from iso8601Duration: String) -> Int {
        guard !iso8601Duration.isEmpty else { return 0 }
        let pattern = "PT(?:(\\d+(?:\\.\\d+)?)H)?(?:(\\d+(?:\\.\\d+)?)M)?(?:(\\d+(?:\\.\\d+)?)S)?"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return 0 }
        let range = NSRange(iso8601Duration.startIndex..<iso8601Duration.endIndex, in: iso8601Duration)
        guard let match = regex.firstMatch(in: iso8601Duration, range: range) else { return 0 }

        func component(_ index: Int) -> Double {
            guard index < match.numberOfRanges, let r = Range(match.range(at: index), in: iso8601Duration) else { return 0 }
            return Double(iso8601Duration[r]) ?? 0
        }
        let hours = component(1), minutes = component(2), seconds = component(3)
        return Int((hours * 3600 + minutes * 60 + seconds) * 1000)
    }

    static func spotifyPlaylist(from resource: TidalResource, included: [TidalResource]?) -> SpotifyPlaylist? {
        guard let attributes = resource.attributes else { return nil }
        let name = attributes.string("name") ?? ""
        guard !name.isEmpty else { return nil }
        let artwork = artworkURL(for: resource, included: included).map { [SpotifyImage(url: $0.absoluteString)] } ?? []
        return SpotifyPlaylist(
            id: resource.id,
            name: name,
            uri: "tidal:playlist:\(resource.id)",
            images: artwork,
            owner: SpotifyUserSimple(id: "tidal", displayName: "TIDAL", images: nil),
            collaborators: nil
        )
    }

    // MARK: - Networking

    private func get<T: Decodable>(_ path: String) async -> T? {
        guard let url = URL(string: "\(baseURL)\(path)") else { return nil }
        return await requestData(url: url)
    }

    private func requestData<T: Decodable>(url: URL) async -> T? {
        guard await ensureValidToken() else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken!)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.api+json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { return nil }
            if httpResponse.statusCode == 401 {
                guard await refreshTokenIfNeeded(force: true) else { return nil }
                return await requestData(url: url)
            }
            guard (200...299).contains(httpResponse.statusCode) else {
                let errorBody = String(data: data, encoding: .utf8) ?? "No response body"
                print("[TidalAPIManager] GET \(url.path) failed (\(httpResponse.statusCode)): \(errorBody)")
                return nil
            }
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            print("[TidalAPIManager] GET \(url.path) failed: \(error)")
            return nil
        }
    }

    private func writeRequest(path: String, method: String, body: Data?) async -> Bool? {
        guard await ensureValidToken(), let url = URL(string: "\(baseURL)\(path)") else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(accessToken!)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.api+json", forHTTPHeaderField: "Accept")
        request.setValue("application/vnd.api+json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { return nil }
            if httpResponse.statusCode == 401 {
                guard await refreshTokenIfNeeded(force: true) else { return nil }
                return await writeRequest(path: path, method: method, body: body)
            }
            guard (200...299).contains(httpResponse.statusCode) else {
                let errorBody = String(data: data, encoding: .utf8) ?? "No response body"
                print("[TidalAPIManager] \(method) \(path) failed (\(httpResponse.statusCode)): \(errorBody)")
                return nil
            }
            return true
        } catch {
            print("[TidalAPIManager] \(method) \(path) failed: \(error)")
            return nil
        }
    }

    private func ensureValidToken() async -> Bool {
        if isAccessTokenValid { return true }
        return await refreshTokenIfNeeded(force: true)
    }
}

// MARK: - Base64 Helpers

extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}