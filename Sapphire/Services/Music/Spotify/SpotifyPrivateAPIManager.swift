//
//  SpotifyPrivateAPIManager.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-10-05
//

import Foundation
import Combine
import CaptchaSolverInterface

enum SpotAPIError: Error, LocalizedError {
    case authenticationFailed(String)
    case invalidResponse
    case decodingError(Error)
    case missingData(String)
    case urlConstructionFailed(String)
    case loginCancelled
    case connectionClosedUnexpectedly
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .authenticationFailed(let message): return "Authentication Failed: \(message)"
        case .invalidResponse: return "Invalid response from Spotify server."
        case .decodingError(let error): return "Failed to decode data: \(error.localizedDescription)"
        case .missingData(let field): return "Missing required data: \(field)"
        case .urlConstructionFailed(let url): return "Failed to construct URL: \(url)"
        case .loginCancelled: return "Login was cancelled by the user."
        case .connectionClosedUnexpectedly: return "The server closed the connection unexpectedly."
        case .apiError(let message): return "Spotify API Error: \(message)"
        }
    }
}

enum CachePolicy {
    case returnCacheDataElseFetch
    case fetchIgnoringCacheData
    case fetchAndReturnCacheData
}

private class FileAPICache {
    private let fileManager = FileManager.default
    private let cacheDirectory: URL
    private let expirationInterval: TimeInterval = 7 * 24 * 60 * 60

    init() {
        let cacheBaseUrl = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        cacheDirectory = cacheBaseUrl.appendingPathComponent("APICache")
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true, attributes: nil)

        Task(priority: .background) {
            await cleanupOldFiles()
        }
    }

    private func cacheUrl(forKey key: String) -> URL? {
        guard let safeKey = key.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed) else {
            return nil
        }
        return cacheDirectory.appendingPathComponent(safeKey)
    }

    func get(forKey key: String) -> (data: Data, timestamp: Date)? {
        guard let url = cacheUrl(forKey: key) else { return nil }
        guard fileManager.fileExists(atPath: url.path) else { return nil }

        do {
            let modificationDate = try fileManager.attributesOfItem(atPath: url.path)[.modificationDate] as? Date ?? .distantPast

            if Date().timeIntervalSince(modificationDate) > expirationInterval {
                try? fileManager.removeItem(at: url)
                return nil
            }

            let data = try Data(contentsOf: url)
            return (data, modificationDate)
        } catch {
            return nil
        }
    }

    func set(_ value: Data, forKey key: String) {
        guard let url = cacheUrl(forKey: key) else { return }
        try? value.write(to: url)
    }

    func clear() {
        try? fileManager.removeItem(at: cacheDirectory)
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true, attributes: nil)
    }

    private func cleanupOldFiles() async {
        do {
            let files = try fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: [.contentModificationDateKey], options: .skipsHiddenFiles)
            for file in files {
                if let modificationDate = try file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                   Date().timeIntervalSince(modificationDate) > expirationInterval {
                    try fileManager.removeItem(at: file)
                }
            }
        } catch {
            print("Error cleaning up API cache: \(error)")
        }
    }
}

@MainActor
class SpotifyPrivateAPIManager: ObservableObject {
    static let shared = SpotifyPrivateAPIManager()

    @Published var isLoggedIn = false
    @Published var loginChallenge: LoginChallengeDetails?
    @Published var userProfile: SpotifyNativeUserProfile?
    @Published var playerState: PlayerState?
    @Published var devices: [SpotifyNativeDevice] = []
    @Published public private(set) var activePlayerDeviceID: String?
    @Published var nativeQueue: [PlayerState.Track] = []
    @Published var nativePlaylists: [SpotifyPlaylist] = []
    @Published var selectedPlaylist: SpotifyPlaylistDetailsResponse.PlaylistV2?
    @Published var playlistTrackViewModels: [TrackViewModel] = []
    @Published var isPlaylistLoading: Bool = false

    var currentTrackURI: String? { playerState?.track?.uri }
    var currentContextURI: String? { playerState?.contextUri }

    private let cookieManager = CookieManager()
    var webSocketManager: WebSocketManager?
    private var cancellables = Set<AnyCancellable>()

    internal var openSpotifyClient: CustomTLSClient?
    internal var spclientClient: CustomTLSClient?
    internal var apiPartnerClient: CustomTLSClient?
    internal var clientTokenClient: CustomTLSClient?
    internal var wwwSpotifyClient: CustomTLSClient?
    internal var wgSpclientClient: CustomTLSClient?

    private var accessToken: String?
    private var clientToken: String?
    internal var clientVersion: String?

    var sessionDeviceID: String?
    var controllerDeviceID: String?

    private var jsPackURL: String?
    private var rawHashes: String?
    private let commonUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
    private let sessionUserDefaultsKey = "spotAPISessionCookies"
    private let controllerDeviceIDKey = "spotAPIControllerDeviceID"

    private var queueHydrationTask: Task<Void, Never>?

    private let apiCache = FileAPICache()

    private init() {
        Task { await loadSession() }
        setupSubscribers()
    }

    private func setupSubscribers() {
        $playerState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] playerState in
                guard let self = self, let playerState = playerState else { return }

                Task { await self.hydrateNowPlayingIfNeeded(for: playerState) }
                self.hydrateQueue(from: playerState)

                let isAd = (playerState.track?.uri.starts(with: "spotify:ad:") ?? false) || (playerState.track?.metadata?.hidden == "true")
                if isAd {
                    print("[SpotifyPrivateAPIManager] Ad detected. Attempting to skip.")
                    Task { await self.skipAd() }
                }
            }
            .store(in: &cancellables)
    }

    private func initializeClients() async {
        openSpotifyClient = CustomTLSClient(host: "open.spotify.com", userAgent: commonUserAgent, cookieManager: cookieManager)
        spclientClient = CustomTLSClient(host: "gue1-spclient.spotify.com", userAgent: commonUserAgent, cookieManager: cookieManager)
        apiPartnerClient = CustomTLSClient(host: "api-partner.spotify.com", userAgent: commonUserAgent, cookieManager: cookieManager)
        clientTokenClient = CustomTLSClient(host: "clienttoken.spotify.com", userAgent: commonUserAgent, cookieManager: cookieManager)
        wwwSpotifyClient = CustomTLSClient(host: "www.spotify.com", userAgent: commonUserAgent, cookieManager: cookieManager)
        wgSpclientClient = CustomTLSClient(host: "spclient.wg.spotify.com", userAgent: commonUserAgent, cookieManager: cookieManager)
    }

    func login() { self.loginChallenge = LoginChallengeDetails() }

    func completeLoginAfterWebViewSuccess(with cookieProperties: [[String: Any]]) {
        let cookies = cookieProperties.compactMap { HTTPCookie(properties: $0.toStringKeys()) }
        Task {
            await cookieManager.setCookies(cookies)
            await saveSession()
            reestablishSession()
        }
    }

    func logout() {
        _internalLogout()

        apiCache.clear()
        Task { await cookieManager.clear() }
        UserDefaults.standard.removeObject(forKey: sessionUserDefaultsKey)
    }

    private func _internalLogout() {
        webSocketManager?.disconnect(); webSocketManager = nil
        cancellables.removeAll()

        openSpotifyClient = nil; spclientClient = nil; apiPartnerClient = nil; clientTokenClient = nil; wwwSpotifyClient = nil; wgSpclientClient = nil
        accessToken = nil; clientToken = nil; activePlayerDeviceID = nil; controllerDeviceID = nil; sessionDeviceID = nil
        jsPackURL = nil; clientVersion = nil

        self.isLoggedIn = false; self.userProfile = nil; self.playerState = nil; self.devices = []
        self.nativeQueue = []
        self.nativePlaylists = []
        self.selectedPlaylist = nil
        self.playlistTrackViewModels = []
        self.isPlaylistLoading = false

        setupSubscribers()
    }

    private func saveSession() async {
        let cookies = await cookieManager.allCookies().values.map { $0.encodeToDictionary() }
        UserDefaults.standard.set(cookies, forKey: sessionUserDefaultsKey)
    }

    private func loadSession() async {
        guard let savedCookiesData = UserDefaults.standard.array(forKey: sessionUserDefaultsKey) as? [[String: Any]] else { return }
        let cookies = savedCookiesData.compactMap { HTTPCookie(properties: $0.toStringKeys()) }
        if cookies.isEmpty {
            UserDefaults.standard.removeObject(forKey: sessionUserDefaultsKey)
            return
        }

        await cookieManager.setCookies(cookies)
        reestablishSession()
    }

    private func getOrSetControllerDeviceID() -> String {
        if let deviceID = UserDefaults.standard.string(forKey: controllerDeviceIDKey) { return deviceID }
        else { let newDeviceID = generateRandomHexString(length: 40); UserDefaults.standard.set(newDeviceID, forKey: controllerDeviceIDKey); return newDeviceID }
    }

    func reestablishSession() {
        Task(priority: .userInitiated) {
            do {
                await self.initializeClients()

                try await self.verifySessionAndFetchUserInfo()

                if let sessionCookie = await self.cookieManager.allCookies()["sp_t"] {
                    self.sessionDeviceID = sessionCookie.value
                } else {
                    throw SpotAPIError.missingData("sp_t cookie not found in saved session.")
                }

                try await self.fetchApiTokensAndClientVersion()

                guard let token = self.accessToken else {
                    throw SpotAPIError.authenticationFailed("Could not obtain access token before initializing WebSocket.")
                }

                let persistentDeviceID = self.getOrSetControllerDeviceID()
                self.controllerDeviceID = persistentDeviceID

                let wsManager = WebSocketManager(accessToken: token, client: self, controllerDeviceID: persistentDeviceID)
                self.webSocketManager = wsManager

                wsManager.playerStatePublisher
                    .receive(on: DispatchQueue.main)
                    .sink { [weak self] playerState in self?.playerState = playerState }
                    .store(in: &self.cancellables)

                wsManager.connectionIdPublisher
                    .first()
                    .receive(on: DispatchQueue.main)
                    .sink { [weak self] connectionId in
                        Task {
                            await self?.finishInitializationFlow(connectionId: connectionId)
                        }
                    }
                    .store(in: &self.cancellables)

                wsManager.connect()

            } catch let error {
                _internalLogout()
                print("[SpotifyPrivateAPIManager] Failed to re-establish session: \(error.localizedDescription). State has been cleared for next attempt.")
                self.isLoggedIn = false
            }
        }
    }

    private func finishInitializationFlow(connectionId: String) async {
        do {
            try await performDeviceRegistration(connectionId: connectionId)
            let playerStateResponse = try await fetchInitialPlayerState()
            if let previouslyActiveDevice = playerStateResponse.activeDeviceId, let newControllerID = self.controllerDeviceID {
                try await self.transferDevice(from: previouslyActiveDevice, to: newControllerID, isInitialHandshake: true)
            }
            await performUserVerification()
            await sendGaboSessionEvent()
            try await self.refreshPlayerAndDeviceState()
            self.isLoggedIn = true
        } catch {
            print("[SpotifyPrivateAPIManager] Error in final initialization flow: \(error.localizedDescription)")
            self.isLoggedIn = false
        }
    }

    func skipAd() async {
        do {
            try await forceReregisterAndTransferToSelf()
            try await Task.sleep(for: .seconds(1))

            guard let nextTrack = nativeQueue.first else {
                try await skipNext()
                return
            }

            _ = await MusicManager.shared.play(trackUri: nextTrack.uri, contextUri: nextTrack.metadata?.contextUri, trackUid: nextTrack.uid, trackIndex: nil)
        } catch { print("[SpotifyPrivateAPIManager] Error skipping ad: \(error.localizedDescription)") }
    }

    func searchForTrack(title: String, artist: String) async -> SpotifyTrack? {
        let query = "\(title) \(artist)"
        let variables: [String: Any] = ["searchTerm": query, "offset": 0, "limit": 5, "numberOfTopResults": 1, "includeAudiobooks": false]
        do {
            let response: NativeSearchResponse = try await pathfinderQuery(operationName: "searchDesktop", variables: variables, sendAsBody: false)
            if let bestMatch = response.data?.searchV2?.tracksV2?.items?.first?.itemV2.data { return SpotifyTrack(from: bestMatch) }
            return nil
        } catch {
            print("[SpotifyPrivateAPIManager] Error searching for track: \(error.localizedDescription)")
            return nil
        }
    }

    func fetchTrackDetails(trackId: String) async -> SpotifyTrackDetailsResponse.TrackUnion? {
        do {
            let response: SpotifyTrackDetailsResponse = try await pathfinderQuery(operationName: "getTrack", variables: ["uri": "spotify:track:\(trackId)"], sendAsBody: false)
            return response.data.trackUnion
        } catch {
            print("[SpotifyPrivateAPIManager] Error fetching track details: \(error.localizedDescription)")
            return nil
        }
    }

    func loadPlaylist(playlistId: String) async {
        guard !playlistId.contains(":collection") && playlistId != "tracks" else { return }
        isPlaylistLoading = true
        defer { isPlaylistLoading = false }

        do {
            let initialVariables: [String: Any] = ["uri": "spotify:playlist:\(playlistId)", "offset": 0, "limit": 100, "enableWatchFeedEntrypoint": false]
            let freshResponse: SpotifyPlaylistDetailsResponse = try await pathfinderQuery(operationName: "fetchPlaylist", variables: initialVariables, sendAsBody: true, cachePolicy: .fetchIgnoringCacheData, useV2Endpoint: true)

            guard var freshPlaylistData = freshResponse.data?.playlistV2 else { throw SpotAPIError.missingData("Initial PlaylistV2 data was missing.") }
            if Task.isCancelled { return }

            freshPlaylistData.uri = "spotify:playlist:\(playlistId)"
            self.selectedPlaylist = freshPlaylistData
            self.playlistTrackViewModels = freshPlaylistData.content.items.map { TrackViewModel(playlistItem: $0) }

            var currentOffset = freshPlaylistData.content.items.count
            let totalTracks = freshPlaylistData.content.totalCount

            while currentOffset < totalTracks {
                if Task.isCancelled { break }
                let pageVariables: [String: Any] = ["uri": "spotify:playlist:\(playlistId)", "offset": currentOffset, "limit": 200, "enableWatchFeedEntrypoint": false]
                let pageResponse: SpotifyPlaylistDetailsResponse = try await pathfinderQuery(operationName: "fetchPlaylist", variables: pageVariables, sendAsBody: true, cachePolicy: .fetchIgnoringCacheData, useV2Endpoint: true)

                if let newItems = pageResponse.data?.playlistV2?.content.items, !newItems.isEmpty {
                    self.selectedPlaylist?.content.items.append(contentsOf: newItems)
                    let newViewModels = newItems.map { TrackViewModel(playlistItem: $0) }
                    self.playlistTrackViewModels.append(contentsOf: newViewModels)
                    currentOffset += newItems.count
                } else {
                    break
                }
            }
        } catch {
            if !(error is CancellationError) {
                print("[SpotifyPrivateAPIManager] Error loading playlist: \(error.localizedDescription)")
                self.selectedPlaylist = nil
            }
        }
    }

    func loadLikedSongs(for playlist: SpotifyPlaylist) async {
        isPlaylistLoading = true
        defer { isPlaylistLoading = false }

        do {
            let variables: [String: Any] = ["offset": 0, "limit": 500]
            let response: LikedSongsResponse = try await pathfinderQuery(operationName: "fetchLibraryTracks", variables: variables, sendAsBody: true, cachePolicy: .fetchIgnoringCacheData)
            if Task.isCancelled { return }

            let likedItems = response.data.me.library.tracks.items
            let playlistItems = likedItems.map { likedItem -> SpotifyPlaylistDetailsResponse.PlaylistItem in
                var mutableItemData = likedItem.track.data
                mutableItemData.uri = likedItem.track.uri
                return SpotifyPlaylistDetailsResponse.PlaylistItem(uid: likedItem.track.uri, itemV2: .init(data: mutableItemData), addedAtInfo: likedItem.addedAtInfo)
            }

            self.selectedPlaylist = SpotifyPlaylistDetailsResponse.PlaylistV2(name: playlist.name, uri: playlist.uri, content: .init(totalCount: response.data.me.library.tracks.totalCount, items: playlistItems))
            self.playlistTrackViewModels = playlistItems.map { TrackViewModel(playlistItem: $0) }
        } catch {
            if !(error is CancellationError) {
                print("[SpotifyPrivateAPIManager] Error loading liked songs: \(error.localizedDescription)")
                self.selectedPlaylist = nil
            }
        }
    }

    func fetchUserLibrary() async {
        guard isLoggedIn else { return }
        do {
            let library = try await fetchLibrary()
            let playlists = library.items?.compactMap { item -> SpotifyPlaylist? in
                guard let itemData = item.item?.data else { return nil }
                switch itemData {
                case .playlist(let data):
                    return SpotifyPlaylist(id: data.uri?.components(separatedBy: ":").last ?? "", name: data.name ?? "Playlist", uri: data.uri ?? "", images: [SpotifyImage(url: data.images?.items?.first?.sources?.first?.url ?? "")], owner: SpotifyUserSimple(id: "", displayName: data.ownerV2?.data?.name ?? "Unknown", images: nil), collaborators: nil)
                case .pseudoPlaylist(let data):
                    return SpotifyPlaylist(id: data.uri?.components(separatedBy: ":").last ?? "", name: data.name ?? "Liked Songs", uri: data.uri ?? "", images: [SpotifyImage(url: data.image?.sources?.first?.url ?? "")], owner: SpotifyUserSimple(id: "spotify", displayName: "Spotify", images: nil), collaborators: nil)
                default: return nil
                }
            } ?? []
            self.nativePlaylists = playlists
        } catch {
            print("[SpotifyPrivateAPIManager] Error fetching user library: \(error.localizedDescription)")
            self.nativePlaylists = []
        }
    }

    func likeTrack(trackURI: String) async -> Bool {
        do {
            let _: EmptyResponse = try await pathfinderQuery(operationName: "addToLibrary", variables: ["uris": [trackURI]], sendAsBody: true)
            return true
        } catch {
            print("[SpotifyPrivateAPIManager] Error liking track: \(error.localizedDescription)")
            return false
        }
    }

    func unlikeTrack(trackURI: String) async -> Bool {
        do {
            let _: EmptyResponse = try await pathfinderQuery(operationName: "removeFromLibrary", variables: ["uris": [trackURI]], sendAsBody: true)
            return true
        } catch {
            print("[SpotifyPrivateAPIManager] Error unliking track: \(error.localizedDescription)")
            return false
        }
    }

    func setShuffle(state: Bool) async -> Bool {
        guard let from = self.controllerDeviceID, let to = self.activePlayerDeviceID, self.isLoggedIn, let spclient = spclientClient else { return false }
        do {
            let path = "/connect-state/v1/player/command/from/\(from)/to/\(to)"
            let payload: [String: Any] = ["command": ["value": state, "endpoint": "set_shuffling_context"]]
            _ = try await spclient.post(path: path, jsonBody: payload)
            return true
        } catch {
            print("[SpotifyPrivateAPIManager] Error setting shuffle: \(error.localizedDescription)")
            return false
        }
    }

    func setRepeatMode(mode: RepeatMode) async -> Bool {
        guard let from = self.controllerDeviceID, let to = self.activePlayerDeviceID, self.isLoggedIn, let spclient = spclientClient else { return false }
        do {
            let path = "/connect-state/v1/player/command/from/\(from)/to/\(to)"
            var payloadCommand: [String: Any] = ["endpoint": "set_options"]
            switch mode {
            case .off: payloadCommand["repeating_context"] = false; payloadCommand["repeating_track"] = false
            case .context: payloadCommand["repeating_context"] = true; payloadCommand["repeating_track"] = false
            case .track: payloadCommand["repeating_context"] = false; payloadCommand["repeating_track"] = true
            }
            let payload: [String: Any] = ["command": payloadCommand]
            _ = try await spclient.post(path: path, jsonBody: payload)
            return true
        } catch {
            print("[SpotifyPrivateAPIManager] Error setting repeat mode: \(error.localizedDescription)")
            return false
        }
    }

    func setVolume(percent: Int) async -> Bool {
        do {
            try await _setVolume(percent: percent)
            return true
        } catch {
            print("[SpotifyPrivateAPIManager] Error setting volume: \(error.localizedDescription)")
            return false
        }
    }

    func transferPlayback(to toDeviceId: String) async -> Bool {
        guard let fromDeviceId = activePlayerDeviceID ?? controllerDeviceID else { return false }
        do {
            try await transferDevice(from: fromDeviceId, to: toDeviceId)
            return true
        } catch {
            print("[SpotifyPrivateAPIManager] Error transferring playback: \(error.localizedDescription)")
            return false
        }
    }

    private func fetchApiTokensAndClientVersion() async throws {
        guard let openSpotifyClient = openSpotifyClient else { throw SpotAPIError.authenticationFailed("Open Spotify client not initialized.") }
        let openSpotifyResponse = try await openSpotifyClient.get(path: "/")
        guard let openSpotifyHtml = String(data: openSpotifyResponse.body, encoding: .utf8) else { throw SpotAPIError.authenticationFailed("Could not parse open.spotify.com HTML.") }
        let jsPackPatterns = [ #"https:\/\/open\.spotifycdn\.com\/cdn\/build\/web-player\/web-player\.[0-9a-f]+\.js"#, #"https:\/\/open-exp\.spotifycdn\.com\/cdn\/build\/web-player\/web-player\.[0-9a-f]+\.js"# ]
        for pattern in jsPackPatterns { if let range = openSpotifyHtml.range(of: pattern, options: .regularExpression) { self.jsPackURL = String(openSpotifyHtml[range]); break } }
        guard let jsPackURL = self.jsPackURL else { throw SpotAPIError.missingData("jsPackURL not found.") }

        guard let mainJsUrl = URL(string: jsPackURL) else { throw SpotAPIError.urlConstructionFailed(jsPackURL) }

        let (mainJsData, _) = try await URLSession.shared.data(from: mainJsUrl)

        let (processedHashes, clientVersion) = try await Task.detached(priority: .userInitiated) { () -> (String, String?) in
            guard let mainJsContent = String(data: mainJsData, encoding: .utf8) else {
                throw SpotAPIError.authenticationFailed("Could not parse main js_pack content.")
            }

            var combinedHashes = mainJsContent

            func fetchAndAppendExtraJs(content: String, xpuiName: String) async throws -> String {
                let searchString = ":\"\(xpuiName)\""; guard let range = content.range(of: searchString) else { return "" }
                let prefix = String(content[..<range.lowerBound]); guard let routeNum = prefix.components(separatedBy: ",").last else { return "" }
                let hashPattern = try Regex("\(routeNum):\"([a-f0-9]+)\""); guard let match = content.firstMatch(of: hashPattern) else { return "" }
                let routeHash = String(match.output[1].substring!)
                let extraJsUrlString = "https://open.spotifycdn.com/cdn/build/web-player/\(xpuiName).\(routeHash).js"; guard let extraJsUrl = URL(string: extraJsUrlString) else { return "" }
                let (extraJsData, _) = try await URLSession.shared.data(from: extraJsUrl)
                return String(data: extraJsData, encoding: .utf8) ?? ""
            }

            combinedHashes += try await fetchAndAppendExtraJs(content: mainJsContent, xpuiName: "xpui-routes-search")
            combinedHashes += try await fetchAndAppendExtraJs(content: mainJsContent, xpuiName: "xpui-routes-track-v2")
            combinedHashes += try await fetchAndAppendExtraJs(content: mainJsContent, xpuiName: "xpui-routes-collection")

            var version: String? = nil
            let components = mainJsContent.components(separatedBy: "clientVersion:\""); if components.count > 1, let versionPart = components.last, let foundVersion = versionPart.components(separatedBy: "\"").first { version = foundVersion }

            return (combinedHashes, version)
        }.value

        self.rawHashes = processedHashes
        self.clientVersion = clientVersion

        let (totp, totpVer) = await TotpGenerator.generateTotp()
        let accessTokenResponse = try await getAccessToken(totp: totp, totpVer: totpVer)
        guard let token = accessTokenResponse.accessToken, let clientID = accessTokenResponse.clientId else { throw SpotAPIError.authenticationFailed("Access token or client ID was nil in response.") }
        self.accessToken = token
        updateAllClientTokens()

        let clientTokenResponse = try await getClientToken(clientID: clientID)
        self.clientToken = clientTokenResponse.grantedToken.token
        updateAllClientTokens()
    }

    private func getAccessToken(totp: String, totpVer: Int) async throws -> AccessTokenResponse {
        guard let openSpotifyClient = openSpotifyClient else { throw SpotAPIError.authenticationFailed("Open Spotify client not initialized.") }
        var components = URLComponents(); components.path = "/api/token"; components.queryItems = [ URLQueryItem(name: "reason", value: "init"), URLQueryItem(name: "productType", value: "web-player"), URLQueryItem(name: "totp", value: totp), URLQueryItem(name: "totpVer", value: String(totpVer)), URLQueryItem(name: "totpServer", value: totp) ]
        let response = try await openSpotifyClient.get(path: components.url!.relativeString); let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase; return try decoder.decode(AccessTokenResponse.self, from: response.body)
    }

    private func getClientToken(clientID: String) async throws -> ClientTokenResponse {
        guard let clientTokenClient = self.clientTokenClient else { throw SpotAPIError.authenticationFailed("ClientTokenClient not initialized.") }
        guard let deviceId = self.sessionDeviceID else { throw SpotAPIError.missingData("Session Device ID is missing for getClientToken.") }
        let path = "/v1/clienttoken"; let body: [String: Any] = [ "client_data": [ "client_version": self.clientVersion ?? "harmony:4.43.2-a61ecaf5", "client_id": clientID, "js_sdk_data": ["device_brand": "unknown", "device_model": "unknown", "os": "mac", "os_version": "OS X 10.15.7", "device_id": deviceId, "device_type": "computer"] ] ]; let headers: [String: String] = [ "Accept": "application/json" ]
        let response = try await clientTokenClient.post(path: path, jsonBody: body, additionalHeaders: headers, authenticate: false)
        guard !response.body.isEmpty else { throw SpotAPIError.invalidResponse }
        let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase; return try decoder.decode(ClientTokenResponse.self, from: response.body)
     }

    private func performDeviceRegistration(connectionId: String) async throws {
        guard let spclient = spclientClient else { throw SpotAPIError.authenticationFailed("SPClient not ready.") }
        guard let controllerDeviceID = self.controllerDeviceID else { throw SpotAPIError.missingData("Controller Device ID is not set.") }

        let deletePath = "/track-playback/v1/devices/hobs_\(controllerDeviceID)"; do { _ = try await spclient.delete(path: deletePath) } catch { }

        let registerPayload: [String: Any] = [ "device": [ "brand": "spotify", "capabilities": [ "change_volume": true, "enable_play_token": true, "supports_file_media_type": true, "play_token_lost_behavior": "pause", "disable_connect": false, "audio_podcasts": true, "video_playback": true, "manifest_formats": [ "file_ids_mp3", "file_urls_mp3", "manifest_urls_audio_ad", "manifest_ids_video", "file_urls_external", "file_ids_mp4", "file_ids_mp4_dual", "manifest_urls_audio_ad", ], ], "device_id": controllerDeviceID, "device_type": "computer", "metadata": [:], "model": "web_player", "name": "Sapphire", "platform_identifier": "web_player windows 10;chrome 120.0.0.0;desktop", "is_group": false, ], "connection_id": connectionId, "client_version": self.clientVersion ?? "harmony:4.43.2-a61ecaf5", "volume": 65535, "outro_endcontent_snooping": false ]
        let registerDevicePath = "/track-playback/v1/devices"; _ = try await spclient.post(path: registerDevicePath, jsonBody: registerPayload)

        let connectDevicePath = "/connect-state/v1/devices/hobs_\(controllerDeviceID)"; let connectPayload: [String: Any] = ["member_type": "CONNECT_STATE", "device": ["device_info": [ "capabilities": [ "can_be_player": false, "hidden": true, "needs_full_player_state": true ] ]]]; var connectHeaders = ["x-spotify-connection-id": connectionId]; connectHeaders["Content-Type"] = "application/json"; _ = try await spclient.put(path: connectDevicePath, jsonBody: connectPayload, additionalHeaders: connectHeaders)
    }

    private func fetchInitialPlayerState() async throws -> SpotifyNativePlayerStateResponse {
        guard let spclient = spclientClient, let controllerDeviceID = self.controllerDeviceID else { throw SpotAPIError.authenticationFailed("Cannot fetch initial state before controller is initialized.") }
        let connectionId = generateRandomHexString(length: 32)
        let connectDevicePath = "/connect-state/v1/devices/hobs_\(controllerDeviceID)"; let connectPayload: [String: Any] = ["member_type": "CONNECT_STATE", "device": ["device_info": [ "capabilities": [ "can_be_player": false, "hidden": true, "needs_full_player_state": true ] ]]]; var connectHeaders = ["x-spotify-connection-id": connectionId]; connectHeaders["Content-Type"] = "application/json"
        let connectResponse = try await spclient.put(path: connectDevicePath, jsonBody: connectPayload, additionalHeaders: connectHeaders)
        return try decodeResponse(connectResponse.body, for: "initial-connect-state") as SpotifyNativePlayerStateResponse
    }

    private func performUserVerification() async {
        guard let client = wgSpclientClient else { return }
        let path = "/user-verification-service/v0/verifications/"
        let queryItems = [URLQueryItem(name: "market", value: "from_token")]
        let headers: [String: String] = [ "spotify-app-version": self.clientVersion ?? "1.2.74.57.g078ed0e9", "Accept": "application/json" ]
        do { _ = try await client.get(path: path, queryItems: queryItems, additionalHeaders: headers) } catch { print("[SpotifyPrivateAPIManager] Error during user verification: \(error.localizedDescription)") }
    }

    private func sendGaboSessionEvent() async {
        guard let spclient = spclientClient else { return }
        let event = [ "name": "session_start", "data": [ "client_version": self.clientVersion ?? "harmony:4.43.2-a61ecaf5", "platform": "web_player" ] ] as [String : Any]
        let payload: [String: Any] = ["events": [event]]
        let path = "/gabo-receiver-service/v1/events"
        do { _ = try await spclient.post(path: path, jsonBody: payload) } catch { print("[SpotifyPrivateAPIManager] Error sending Gabo session event: \(error.localizedDescription)") }
    }

    func pythonCompatiblePlay(trackUri: String, contextUri: String, trackUid: String?, trackIndex: Int?, targetDeviceID: String) async throws {
        guard let fromDeviceID = self.controllerDeviceID, self.isLoggedIn, let spclient = spclientClient else { return }
        let path = "/connect-state/v1/player/command/from/\(fromDeviceID)/to/\(targetDeviceID)"
        var optionsPayload: [String: Any] = [ "license": "tft", "player_options_override": [:] ]
        if !trackUri.isEmpty { optionsPayload["skip_to"] = [ "track_uid": trackUid ?? "", "track_index": trackIndex ?? 0, "track_uri": trackUri ] }
        let commandPayload: [String: Any] = [ "context": [ "uri": contextUri, "url": "context://\(contextUri)", "metadata": [:] ], "play_origin": [ "feature_identifier": "playlist", "feature_version": "open-server_2025-09-20_1758397650501_078ed0e", "referrer_identifier": "deeplink" ], "options": optionsPayload, "logging_params": [ "page_instance_ids": [UUID().uuidString], "interaction_ids": [UUID().uuidString], "command_id": generateRandomHexString(length: 32) ], "endpoint": "play" ]
        let finalPayload: [String: Any] = ["command": commandPayload]
        let response = try await spclient.post(path: path, jsonBody: finalPayload)

        if !response.body.isEmpty, let responseString = String(data: response.body, encoding: .utf8), responseString.contains("ack_id") {
            if let command = finalPayload["command"] as? [String: Any], let loggingParams = command["logging_params"] as? [String: Any], let commandId = loggingParams["command_id"] as? String {
                await sendMelodyConfirmation(commandId: commandId, targetDeviceId: targetDeviceID)
            }
        }
        self.activePlayerDeviceID = targetDeviceID
    }

    private func sendMelodyConfirmation(commandId: String, targetDeviceId: String) async {
        guard let spclient = spclientClient else { return }
        let playOrigin: [String: String] = [ "feature_identifier": "playlist", "feature_version": "open-server_2025-09-20_1758346958904_1b5fa34", "referrer_identifier": "deeplink" ]
        guard let playOriginData = try? JSONSerialization.data(withJSONObject: playOrigin), let playOriginString = String(data: playOriginData, encoding: .utf8) else { return }
        let messagePayload: [String: Any] = [ "command_id": commandId, "command_type": "play", "target_device_id": targetDeviceId, "result": "success", "http_status_code": 200, "play_origin": playOriginString, "interaction_ids": "", "ms_ack_duration": Int.random(in: 400...600), "ms_request_latency": Int.random(in: 150...250) ]
        let message: [String: Any] = [ "type": "jssdk_connect_command", "message": messagePayload ]
        let payload: [String: Any] = [ "messages": [message], "sdk_id": "harmony:4.58.0-a717498aa", "platform": "web_player osx 10.15.7;microsoft edge 140.0.0.0;desktop", "client_version": self.clientVersion ?? "harmony:4.43.2-a61ecaf5" ]
        guard let payloadData = try? JSONSerialization.data(withJSONObject: payload) else { return }
        let path = "/melody/v1/msg/batch"; let headers = ["Content-Type": "text/plain;charset=UTF-8"]
        do { _ = try await spclient.post(path: path, bodyData: payloadData, additionalHeaders: headers) } catch { print("[SpotifyPrivateAPIManager] Error sending Melody confirmation: \(error.localizedDescription)") }
    }

    internal func transferDevice(from fromDeviceId: String, to toDeviceId: String, isInitialHandshake: Bool = false) async throws {
        guard isLoggedIn || isInitialHandshake else { throw SpotAPIError.authenticationFailed("Not logged in.") }
        guard let spclient = spclientClient else { throw SpotAPIError.authenticationFailed("SPClient not ready.") }
        let path = "/connect-state/v1/connect/transfer/from/\(fromDeviceId)/to/\(toDeviceId)"
        let payload: [String: Any] = ["transfer_options": ["restore_paused": "restore"], "interaction_id": UUID().uuidString.lowercased(), "command_id": generateRandomHexString(length: 32)]
        _ = try await spclient.post(path: path, jsonBody: payload)
        self.activePlayerDeviceID = toDeviceId
    }

    func findUidForTrackInPlaylist(trackUri: String, playlistId: String) async throws -> String? {
        guard let playlistDetails = self.selectedPlaylist, playlistDetails.uri == "spotify:playlist:\(playlistId)" else {
            throw SpotAPIError.missingData("Playlist not loaded or mismatch.")
        }
        let normalizedTrackUri = normalizeSpotifyUri(trackUri)
        let targetItem = playlistDetails.content.items.first { item in
            let itemUri = normalizeSpotifyUri(item.itemV2.data.uri ?? "")
            return itemUri == normalizedTrackUri
        }
        return targetItem?.uid
    }

    private func normalizeSpotifyUri(_ uri: String) -> String { if uri.starts(with: "spotify:track:") { return String(uri.dropFirst("spotify:track:".count)) }; if let url = URL(string: uri), url.host?.contains("spotify.com") == true { return url.lastPathComponent }; return uri }

    private func _setVolume(percent: Int) async throws { guard let from = self.controllerDeviceID, let to = self.activePlayerDeviceID, self.isLoggedIn else { throw SpotAPIError.authenticationFailed("Device IDs missing.") }; guard let spclient = spclientClient else { throw SpotAPIError.authenticationFailed("SPClient not ready.") }; let clampedPercent = max(0.0, min(1.0, Double(percent) / 100.0)); let sixteenBitRep = Int(clampedPercent * 65535); let path = "/connect-state/v1/connect/volume/from/\(from)/to/\(to)"; let payload: [String: Any] = ["volume": sixteenBitRep]; _ = try await spclient.put(path: path, jsonBody: payload) }

    internal func pathfinderQuery<T: Decodable>(operationName: String, variables: [String: Any], extensions: [String: Any]? = nil, sendAsBody: Bool, cachePolicy: CachePolicy = .returnCacheDataElseFetch, useV2Endpoint: Bool = false) async throws -> T {
        guard let apiPartnerClient = apiPartnerClient, isLoggedIn else { throw SpotAPIError.authenticationFailed("Not logged in.") }
        let variablesData = try? JSONSerialization.data(withJSONObject: variables, options: .sortedKeys); let variablesString = variablesData?.base64EncodedString() ?? ""; let cacheKey = "\(operationName)_\(variablesString)"

        if cachePolicy == .returnCacheDataElseFetch || cachePolicy == .fetchAndReturnCacheData {
            if let cachedEntry = apiCache.get(forKey: cacheKey) {
                return try decodeResponse(cachedEntry.data, for: operationName) as T
            }
        }

        let sha256Hash: String
        switch operationName {
        case "fetchLibraryTracks":
            sha256Hash = "087278b20b743578a6262c2b0b4bcd20d879c503cc359a2285baf083ef944240"
        case "fetchPlaylist":
            sha256Hash = "837211ef46f604a73cd3d051f12ee63c81aca4ec6eb18e227b0629a7b36adad3"
        default:
            sha256Hash = try getPartHash(operationName: operationName)
        }

        let finalExtensions = try extensions ?? ["persistedQuery": ["version": 1, "sha256Hash": sha256Hash]]

        let response: HTTPResponse
        let path = useV2Endpoint ? "/pathfinder/v2/query" : "/pathfinder/v1/query"

        if sendAsBody {
            let payload: [String: Any] = [ "operationName": operationName, "variables": variables, "extensions": finalExtensions ]
            response = try await apiPartnerClient.post(path: path, jsonBody: payload)
        } else {
            var components = URLComponents(); components.path = path
            guard let variablesJSONData = try? JSONSerialization.data(withJSONObject: variables), let extensionsJSONData = try? JSONSerialization.data(withJSONObject: finalExtensions), let variablesJSONString = String(data: variablesJSONData, encoding: .utf8), let extensionsJSONString = String(data: extensionsJSONData, encoding: .utf8) else { throw SpotAPIError.urlConstructionFailed("Could not serialize pathfinder variables/extensions to JSON string.") }
            components.queryItems = [URLQueryItem(name: "operationName", value: operationName), URLQueryItem(name: "variables", value: variablesJSONString), URLQueryItem(name: "extensions", value: extensionsJSONString)]
            guard let pathWithParams = components.url?.relativeString else { throw SpotAPIError.urlConstructionFailed("Could not create path with query parameters.") }
            response = try await apiPartnerClient.get(path: pathWithParams)
        }

        if (200...299).contains(response.statusCode) && !response.body.isEmpty { apiCache.set(response.body, forKey: cacheKey) }
        return try decodeResponse(response.body, for: operationName)
    }
    private func decodeResponse<T: Decodable>(_ data: Data, for operationName: String) throws -> T {
        do { let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase; return try decoder.decode(T.self, from: data) }
        catch let error { throw SpotAPIError.decodingError(error) }
    }

    func skipNext() async throws {
        guard let from = self.controllerDeviceID, let to = self.activePlayerDeviceID, self.isLoggedIn, let spclient = spclientClient else { return }
        let path = "/connect-state/v1/player/command/from/\(from)/to/\(to)"
        let payload: [String: Any] = ["command": ["endpoint": "skip_next"]]
        _ = try await spclient.post(path: path, jsonBody: payload)
    }

    func forceReregisterAndTransferToSelf() async throws {
        guard let webSocketManager = self.webSocketManager, let controllerDeviceID = self.controllerDeviceID else { throw SpotAPIError.authenticationFailed("Player is not in a valid state to re-register.") }
        webSocketManager.connect()
        let connectionId = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            var cancellable: AnyCancellable?; cancellable = webSocketManager.connectionIdPublisher.first().sink { connId in continuation.resume(returning: connId); cancellable?.cancel() }
        }
        try await performDeviceRegistration(connectionId: connectionId)
        try await transferDevice(from: controllerDeviceID, to: controllerDeviceID, isInitialHandshake: true)
    }

    func refreshPlayerAndDeviceState() async throws {
        guard let spclient = spclientClient, let controllerDeviceID = self.controllerDeviceID else { throw SpotAPIError.authenticationFailed("SPClient not ready or controllerDeviceID is missing.") }
        let connectionId = generateRandomHexString(length: 32)
        let connectDevicePath = "/connect-state/v1/devices/hobs_\(controllerDeviceID)"
        let connectPayload: [String: Any] = ["member_type": "CONNECT_STATE", "device": ["device_info": [ "capabilities": [ "can_be_player": false, "hidden": true, "needs_full_player_state": true ] ]]]
        var connectHeaders = ["x-spotify-connection-id": connectionId]; connectHeaders["Content-Type"] = "application/json"
        let connectResponse = try await spclient.put(path: connectDevicePath, jsonBody: connectPayload, additionalHeaders: connectHeaders)
        do {
            let playerStateResponse = try decodeResponse(connectResponse.body, for: "connect-state") as SpotifyNativePlayerStateResponse
            self.playerState = playerStateResponse.playerState; self.devices = Array(playerStateResponse.devices.values); self.activePlayerDeviceID = playerStateResponse.activeDeviceId
        } catch let error {
            print("[SpotifyPrivateAPIManager] Error refreshing player state: \(error.localizedDescription)")

            if let spotError = error as? SpotAPIError, case .decodingError = spotError {
                print("[SpotifyPrivateAPIManager] Decoding error detected. Treating as a connection loss and resetting session.")
                _internalLogout()
                checkAndReconnectIfNeeded()
            }

            throw error
        }
    }

    private func fetchLibrary() async throws -> UserLibraryResponse.Library { let response: UserLibraryResponse = try await pathfinderQuery( operationName: "libraryV3", variables: [ "filters": [], "order": nil, "textFilter": "", "features": ["LIKED_SONGS", "YOUR_EPISODES"], "limit": 100, "offset": 0, "flatten": false, "expandedFolders": [], "folderUri": nil, "includeFoldersWhenFlattening": true ], sendAsBody: false ); guard let library = response.data?.me?.libraryV3 else { throw SpotAPIError.missingData("Library data was missing in the response.") }; return library }
    private func verifySessionAndFetchUserInfo() async throws { guard let wwwSpotifyClient = self.wwwSpotifyClient else { throw SpotAPIError.authenticationFailed("wwwSpotifyClient not initialized for verification.") }; let response = try await wwwSpotifyClient.get(path: "/api/account-settings/v1/profile"); guard response.statusCode == 200, !response.body.isEmpty else { throw SpotAPIError.authenticationFailed("Session verification failed. Could not fetch user profile.") }; do { let userProfileResponse = try decodeResponse(response.body, for: "user-profile") as SpotifyNativeUserProfile; self.userProfile = userProfileResponse } catch let error { print("[SpotifyPrivateAPIManager] Error verifying session/fetching user info: \(error.localizedDescription)"); throw error } }
    private func getPartHash(operationName: String) throws -> String { guard let rawHashes = self.rawHashes else { throw SpotAPIError.missingData("rawHashes not available.") }; let patterns = [ "\"\(operationName)\",\"query\",\"([^\"]*)\"", "\"\(operationName)\",\"mutation\",\"([^\"]*)\"" ]; for pattern in patterns { let regex = try NSRegularExpression(pattern: pattern); let range = NSRange(location: 0, length: rawHashes.utf16.count); if let match = regex.firstMatch(in: rawHashes, options: [], range: range) { if let hashRange = Range(match.range(at: 1), in: rawHashes) { return String(rawHashes[hashRange]) } } }; throw SpotAPIError.missingData("SHA256 hash for operation '\(operationName)' not found.") }
    private func updateAllClientTokens() { let clients: [String: CustomTLSClient?] = [ "openSpotifyClient": openSpotifyClient, "spclientClient": spclientClient, "apiPartnerClient": apiPartnerClient, "clientTokenClient": clientTokenClient, "wwwSpotifyClient": wwwSpotifyClient, "wgSpclientClient": wgSpclientClient ]; for (_, client) in clients { client?.accessToken = self.accessToken; client?.clientToken = self.clientToken; client?.clientVersion = self.clientVersion }; }
    internal func generateRandomHexString(length: Int) -> String { let characters = Array("0123456789abcdef"); var result = ""; for _ in 0..<length { result.append(characters.randomElement()!) }; return result }
    private struct EmptyResponse: Decodable {}

    private func hydrateNowPlayingIfNeeded(for state: PlayerState) async {
        guard let sparseTrack = state.track, sparseTrack.metadata?.artistName == nil, !sparseTrack.uri.isEmpty else {
            return
        }

        do {
            let trackDetailsResponse: SpotifyTrackDetailsResponse = try await pathfinderQuery(
                operationName: "getTrack",
                variables: ["uri": sparseTrack.uri],
                sendAsBody: false
            )

            var hydratedState = state
            let hydratedTrack = PlayerState.Track(hydrating: sparseTrack, withDetails: trackDetailsResponse.data.trackUnion)

            hydratedState.track = hydratedTrack
            self.playerState = hydratedState

        } catch {
            print("[SpotifyPrivateAPIManager] Error hydrating now playing track: \(error.localizedDescription)")
        }
    }

    private func hydrateQueue(from playerState: PlayerState) {
        queueHydrationTask?.cancel()

        let sparseQueue = playerState.nextTracks?.filter {
            !($0.uri.contains("spotify:delimiter") || ($0.metadata?.hidden == "true"))
        } ?? []

        queueHydrationTask = Task {
            var finalQueue = sparseQueue
            let tracksToHydrateIndices = finalQueue.indices.filter { finalQueue[$0].metadata?.artistName == nil }

            guard !tracksToHydrateIndices.isEmpty else {
                if self.nativeQueue.map({$0.uid}) != finalQueue.map({$0.uid}) { self.nativeQueue = finalQueue }
                return
            }

            await withTaskGroup(of: (Int, PlayerState.Track).self) { group in
                for index in tracksToHydrateIndices {
                    let track = finalQueue[index]
                    group.addTask {
                        var hydratedTrack = track
                        do {
                            let trackDetails: SpotifyTrackDetailsResponse = try await self.pathfinderQuery(operationName: "getTrack", variables: ["uri": track.uri], sendAsBody: false)
                            hydratedTrack = PlayerState.Track(hydrating: track, withDetails: trackDetails.data.trackUnion)
                        } catch {
                            print("[SpotifyPrivateAPIManager] Error hydrating queue track \(track.uri): \(error.localizedDescription)")
                        }
                        return (index, hydratedTrack)
                    }
                }

                for await (index, hydratedTrack) in group {
                    if index < finalQueue.count {
                        finalQueue[index] = hydratedTrack
                    }
                }
            }

            if !Task.isCancelled {
                self.nativeQueue = finalQueue
            }
        }
    }

    func checkAndReconnectIfNeeded() {
        guard !isLoggedIn, loginChallenge == nil, webSocketManager?.isConnecting == false else {
            return
        }

        print("[SpotifyPrivateAPIManager] Proactively checking connection and re-establishing session after wake/network change.")
        reestablishSession()
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }
}

extension HTTPCookie {
    func encodeToDictionary() -> [String: Any] { var properties = [String: Any](); if let cookieProperties = self.properties { for (key, value) in cookieProperties { properties[key.rawValue] = value } }; return properties }
}

extension Dictionary where Key == String, Value == Any {
    func toStringKeys() -> [HTTPCookiePropertyKey: Any] { var newDict = [HTTPCookiePropertyKey: Any](); for (key, value) in self { newDict[HTTPCookiePropertyKey(key)] = value }; return newDict }
}

extension Data {
    var prettyPrintedJSONString: String? {
        guard let object = try? JSONSerialization.jsonObject(with: self, options: []),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted]),
              let prettyPrintedString = String(data: data, encoding: .utf8) else { return String(data: self, encoding: .utf8) }
        return prettyPrintedString
    }
}

extension SpotifyTrack {
    init(from nativeTrack: NativeTrackData) {
        self.id = nativeTrack.uri.components(separatedBy: ":").last ?? ""
        self.name = nativeTrack.name
        self.uri = nativeTrack.uri
        self.album = SpotifyAlbum(
            name: nativeTrack.albumOfTrack.name,
            images: nativeTrack.albumOfTrack.coverArt.sources.map { SpotifyImage(url: $0.url) }
        )
        self.artists = nativeTrack.artists.items.map { SpotifyArtist(name: $0.profile.name) }
        self.durationMs = nativeTrack.duration.totalMilliseconds
        self.popularity = nil
    }
}