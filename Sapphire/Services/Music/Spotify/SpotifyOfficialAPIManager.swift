//
//  SpotifyOfficialAPIManager.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-09-22.
//

import Foundation
import AppKit
import Combine

@MainActor
class SpotifyOfficialAPIManager: ObservableObject {
    static let shared = SpotifyOfficialAPIManager()

    @Published var isAuthenticated = false
    @Published var userProfile: UserProfile?
    @Published var isPremiumUser = false
    @Published var hasApiKeys = false

    private var accessToken: String?
    private var refreshToken: String?
    private var clientId = ""
    private var clientSecret = ""
    private let redirectURI = "sapphire://callback"

    private let settingsModel = SettingsModel.shared
    private var cancellables = Set<AnyCancellable>()

    private init() {
        updateCredentials(clientId: settingsModel.settings.spotifyClientId, clientSecret: settingsModel.settings.spotifyClientSecret)
        settingsModel.$settings.receive(on: DispatchQueue.main).sink { [weak self] newSettings in
            self?.updateCredentials(clientId: newSettings.spotifyClientId, clientSecret: newSettings.spotifyClientSecret)
        }.store(in: &cancellables)

        self.accessToken = UserDefaults.standard.string(forKey: "spotifyAccessToken")
        self.refreshToken = UserDefaults.standard.string(forKey: "spotifyRefreshToken")

        if self.refreshToken != nil {
            Task { await self.refreshTokenIfNeeded() }
        }
    }

    private func updateCredentials(clientId: String, clientSecret: String) {
        self.clientId = clientId
        self.clientSecret = clientSecret
        let nowHasKeys = !clientId.isEmpty && !clientSecret.isEmpty
        if self.hasApiKeys != nowHasKeys {
            self.hasApiKeys = nowHasKeys
        }
    }

    // MARK: - Authentication

    func login() {
        let scope = "user-read-playback-state user-modify-playback-state user-read-currently-playing playlist-read-private user-read-private user-library-modify user-library-read"
        var components = URLComponents(string: "https://accounts.spotify.com/authorize")!
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "scope", value: scope),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
        ]
        guard let url = components.url else { return }
        NSWorkspace.shared.open(url)
    }

    func handleRedirect(url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
            return
        }
        Task { await self.exchangeCodeForToken(code: code) }
    }

    private struct TokenResponse: Decodable {
        let accessToken: String, refreshToken: String?, expiresIn: Int
        enum CodingKeys: String, CodingKey { case accessToken = "access_token", refreshToken = "refresh_token", expiresIn = "expires_in" }
    }

    private func exchangeCodeForToken(code: String) async {
        guard let url = URL(string: "https://accounts.spotify.com/api/token") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
        ]
        request.httpBody = components.query?.data(using: .utf8)
        let authHeader = "\(clientId):\(clientSecret)".data(using: .utf8)!.base64EncodedString()
        request.setValue("Basic \(authHeader)", forHTTPHeaderField: "Authorization")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                let errorBody = String(data: data, encoding: .utf8) ?? "No response body"
                print("[SpotifyOfficialAPIManager] Token exchange failed with status code \((response as? HTTPURLResponse)?.statusCode ?? 0). Response: \(errorBody)")
                return
            }

            let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)

            self.accessToken = tokenResponse.accessToken
            self.refreshToken = tokenResponse.refreshToken
            UserDefaults.standard.set(tokenResponse.accessToken, forKey: "spotifyAccessToken")
            if let refreshToken = tokenResponse.refreshToken {
                UserDefaults.standard.set(refreshToken, forKey: "spotifyRefreshToken")
            }
            self.isAuthenticated = true
            await self.fetchUserProfile()
        } catch {
            print("[SpotifyOfficialAPIManager] Token exchange failed: \(error)")
        }
    }

    private struct TokenErrorResponse: Decodable {
        let error: String
        let error_description: String
    }

    func refreshTokenIfNeeded() async {
        guard let refreshToken = self.refreshToken else {
            self.isAuthenticated = false
            return
        }

        guard let url = URL(string: "https://accounts.spotify.com/api/token") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "grant_type", value: "refresh_token"),
            URLQueryItem(name: "refresh_token", value: refreshToken),
        ]
        request.httpBody = components.query?.data(using: .utf8)
        let authHeader = "\(clientId):\(clientSecret)".data(using: .utf8)!.base64EncodedString()
        request.setValue("Basic \(authHeader)", forHTTPHeaderField: "Authorization")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let decoder = JSONDecoder()
            if let tokenResponse = try? decoder.decode(TokenResponse.self, from: data) {
                self.accessToken = tokenResponse.accessToken
                UserDefaults.standard.set(tokenResponse.accessToken, forKey: "spotifyAccessToken")
                if let newRefreshToken = tokenResponse.refreshToken {
                    self.refreshToken = newRefreshToken
                    UserDefaults.standard.set(newRefreshToken, forKey: "spotifyRefreshToken")
                }
                self.isAuthenticated = true
                await self.fetchUserProfile()
            } else if let errorResponse = try? decoder.decode(TokenErrorResponse.self, from: data) {
                print("[SpotifyOfficialAPIManager] Refresh token error: \(errorResponse.error_description)")
                await logout()
            } else {
                throw URLError(.cannotDecodeContentData)
            }
        } catch {
            print("[SpotifyOfficialAPIManager] Refresh token request failed: \(error)")
            await logout()
        }
    }

    func logout() {
        self.accessToken = nil
        self.refreshToken = nil
        self.userProfile = nil
        self.isAuthenticated = false
        UserDefaults.standard.removeObject(forKey: "spotifyAccessToken")
        UserDefaults.standard.removeObject(forKey: "spotifyRefreshToken")
    }

    // MARK: - API Requests

    func fetchUserProfile() async {
        guard isAuthenticated, let url = URL(string: "https://api.spotify.com/v1/me") else { return }
        let profile: UserProfile? = await makeAPIRequest(url: url)
        self.userProfile = profile
        self.isPremiumUser = (profile?.product == "premium")
    }

    func fetchPlaybackState() async -> PlaybackState? {
        guard isAuthenticated, let url = URL(string: "https://api.spotify.com/v1/me/player") else { return nil }
        return await makeAPIRequest(url: url)
    }

    func searchForTrack(title: String, artist: String) async -> SpotifyTrack? {
        guard isAuthenticated else { return nil }
        var components = URLComponents(string: "https://api.spotify.com/v1/search")!
        let query = "track:\"\(title.trimmingCharacters(in: .whitespacesAndNewlines))\" artist:\"\(artist.trimmingCharacters(in: .whitespacesAndNewlines))\""
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "type", value: "track"),
            URLQueryItem(name: "limit", value: "1")
        ]
        guard let url = components.url else { return nil }
        let response: SearchResponse? = await makeAPIRequest(url: url)
        return response?.tracks.items.first
    }

    func likeTrack(id: String) async -> Bool {
        guard isAuthenticated, let url = URL(string: "https://api.spotify.com/v1/me/tracks?ids=\(id)") else { return false }
        let success: Bool? = await makeAPIRequest(url: url, method: "PUT", body: nil)
        return success == true
    }

    func unlikeTrack(id: String) async -> Bool {
        guard isAuthenticated, let url = URL(string: "https://api.spotify.com/v1/me/tracks?ids=\(id)") else { return false }
        let success: Bool? = await makeAPIRequest(url: url, method: "DELETE", body: nil)
        return success == true
    }

    func checkIfTrackIsLiked(id: String) async -> Bool? {
        guard isAuthenticated, let url = URL(string: "https://api.spotify.com/v1/me/tracks/contains?ids=\(id)") else { return nil }
        let response: [Bool]? = await makeAPIRequest(url: url)
        return response?.first
    }

    func setShuffle(state: Bool) async -> Bool {
        guard isPremiumUser, var components = URLComponents(string: "https://api.spotify.com/v1/me/player/shuffle") else { return false }
        components.queryItems = [URLQueryItem(name: "state", value: state ? "true" : "false")]
        guard let url = components.url else { return false }
        let success: Bool? = await makeAPIRequest(url: url, method: "PUT", body: nil)
        return success == true
    }

    func setRepeatMode(mode: String) async -> Bool {
        guard isPremiumUser, var components = URLComponents(string: "https://api.spotify.com/v1/me/player/repeat") else { return false }
        components.queryItems = [URLQueryItem(name: "state", value: mode)]
        guard let url = components.url else { return false }
        let success: Bool? = await makeAPIRequest(url: url, method: "PUT", body: nil)
        return success == true
    }

    func setVolume(percent: Int) async -> PlaybackResult {
        if isPremiumUser {
            guard var components = URLComponents(string: "https://api.spotify.com/v1/me/player/volume") else { return .failure(reason: "Invalid URL") }
            components.queryItems = [URLQueryItem(name: "volume_percent", value: "\(percent)")]
            guard let url = components.url else { return .failure(reason: "Invalid URL") }
            let success: Bool? = await makeAPIRequest(url: url, method: "PUT")
            return success == true ? .success : .failure(reason: "API request failed")
        }
        return .requiresPremium
    }

    func fetchDevices() async -> [SpotifyDevice] {
        guard isAuthenticated, let url = URL(string: "https://api.spotify.com/v1/me/player/devices") else { return [] }
        struct DevicesResponse: Decodable { let devices: [SpotifyDevice] }
        let response: DevicesResponse? = await makeAPIRequest(url: url)
        return response?.devices ?? []
    }

    func transferPlayback(to deviceId: String) async -> PlaybackResult {
        guard isPremiumUser else { return .requiresPremium }
        guard let url = URL(string: "https://api.spotify.com/v1/me/player") else { return .failure(reason: "Invalid URL") }
        struct TransferPlaybackBody: Encodable { let device_ids: [String]; let play: Bool }
        let body = TransferPlaybackBody(device_ids: [deviceId], play: true)
        guard let bodyData = try? JSONEncoder().encode(body) else { return .failure(reason: "Encoding failed") }
        let success: Bool? = await makeAPIRequest(url: url, method: "PUT", body: bodyData)
        return success == true ? .success : .failure(reason: "API request failed")
    }

    func playTrack(uri: String) async -> PlaybackResult {
        guard isPremiumUser else { return .requiresPremium }
        guard let url = URL(string: "https://api.spotify.com/v1/me/player/play") else { return .failure(reason: "Invalid URL") }
        struct PlayBody: Encodable { var uris: [String]? = nil }
        let body = PlayBody(uris: [uri])
        guard let bodyData = try? JSONEncoder().encode(body) else { return .failure(reason: "Encoding failed") }
        let success: Bool? = await makeAPIRequest(url: url, method: "PUT", body: bodyData)
        return success == true ? .success : .failure(reason: "API request failed")
    }

    func playPlaylist(contextUri: String) async -> PlaybackResult {
        guard isPremiumUser else { return .requiresPremium }
        guard let url = URL(string: "https://api.spotify.com/v1/me/player/play") else { return .failure(reason: "Invalid URL") }
        struct PlayBody: Encodable { var context_uri: String? = nil }
        let body = PlayBody(context_uri: contextUri)
        guard let bodyData = try? JSONEncoder().encode(body) else { return .failure(reason: "Encoding failed") }
        let success: Bool? = await makeAPIRequest(url: url, method: "PUT", body: bodyData)
        return success == true ? .success : .failure(reason: "API request failed")
    }

    func fetchQueue() async -> SpotifyQueue? {
        guard isPremiumUser, let url = URL(string: "https://api.spotify.com/v1/me/player/queue") else { return nil }
        return await makeAPIRequest(url: url)
    }

    func fetchPlaylists() async -> [SpotifyPlaylist] {
        guard isAuthenticated, let url = URL(string: "https://api.spotify.com/v1/me/playlists") else { return [] }
        struct PlaylistResponse: Decodable { let items: [SpotifyPlaylist] }
        let response: PlaylistResponse? = await makeAPIRequest(url: url)
        return response?.items ?? []
    }

    func fetchPlaylistTracks(playlistID: String) async -> [SpotifyTrack]? {
        guard isAuthenticated else { return nil }

        struct PlaylistTrackItem: Decodable { let track: SpotifyTrack? }
        struct PlaylistTracksResponse: Decodable {
            let items: [PlaylistTrackItem]
            let next: String?
        }

        var allTracks: [SpotifyTrack] = []
        var nextUrlString: String? = "https://api.spotify.com/v1/playlists/\(playlistID)/tracks"

        while let urlString = nextUrlString, let url = URL(string: urlString) {
            let response: PlaylistTracksResponse? = await makeAPIRequest(url: url)

            if let items = response?.items {
                allTracks.append(contentsOf: items.compactMap { $0.track })
            }

            nextUrlString = response?.next
        }

        return allTracks
    }

    // MARK: - Generic API Helper

    private func makeAPIRequest<T: Decodable>(url: URL, method: String = "GET", body: Data? = nil) async -> T? {
        guard isAuthenticated, let token = accessToken else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body = body {
            request.httpBody = body
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                print("[SpotifyOfficialAPIManager] Invalid response type.")
                return nil
            }

            if httpResponse.statusCode == 204 {
                return (true as? T)
            }

            if httpResponse.statusCode == 401 {
                print("[SpotifyOfficialAPIManager] Access token expired. Refreshing...")
                await refreshTokenIfNeeded()
                if self.isAuthenticated {
                    return await makeAPIRequest(url: url, method: method, body: body)
                } else {
                    return nil
                }
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                let errorBody = String(data: data, encoding: .utf8) ?? "No response body"
                print("[SpotifyOfficialAPIManager] API Request failed for URL \(url) with status code \(httpResponse.statusCode). Response: \(errorBody)")
                return nil
            }

            if data.isEmpty, T.self == Bool.self {
                return true as? T
            }

            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            print("[SpotifyOfficialAPIManager] Decoding failed for URL \(url): \(error)")
            return nil
        }
    }
}