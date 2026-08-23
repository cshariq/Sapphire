//
//  SpotifyPrivateAPI.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-10-05
//

import Foundation
import Combine
import Network
import CryptoKit
import SwiftUI
import AppKit
import WebKit

enum SpotAPIError: Error, LocalizedError {
    case authenticationFailed(String)
    case invalidResponse
    case decodingError(Error)
    case missingData(String)
    case urlConstructionFailed(String)
    case loginCancelled
    case connectionClosedUnexpectedly
    case apiError(String)
    case rateLimited(String)

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
        case .rateLimited(let message): return "Spotify is rate limiting requests: \(message)"
        }
    }
}

enum CachePolicy {
    case returnCacheDataElseFetch
    case fetchIgnoringCacheData
    case fetchAndReturnCacheData
}

private actor FileAPICache {
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

    func get(forKey key: String) async -> (data: Data, timestamp: Date)? {
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

    func set(_ value: Data, forKey key: String) async {
        guard let url = cacheUrl(forKey: key) else { return }
        try? value.write(to: url)
    }

    func clear() async {
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
    @Published var profileFollowerCount: Int?
    @Published var playerState: PlayerState?
    @Published var devices: [SpotifyNativeDevice] = []
    @Published public private(set) var activePlayerDeviceID: String?
    @Published var nativeQueue: [PlayerState.Track] = []
    @Published var nativePlaylists: [SpotifyPlaylist] = []
    @Published var librarySortOrders: [UserLibraryResponse.SortOrder] = []
    @Published var selectedLibrarySortOrderId: String = "Recents"
    @Published var selectedPlaylist: SpotifyPlaylistDetailsResponse.PlaylistV2?
    @Published var playlistTrackViewModels: [TrackViewModel] = []
    @Published var isPlaylistLoading: Bool = false
    @Published var isPlaylistLoadingMore: Bool = false
    @Published var playlistHasMore: Bool = false
    @Published var playlistTotalCount: Int = 0
    @Published private(set) var playlistTrackIndexByUID: [String: Int] = [:]
    private var playlistNextOffset: Int = 0
    private var playlistLoadedURI: String?

    @Published var accountInfo: SpotifyAccountInfo?
    @Published var currentCanvas: SpotifyCanvasInfo?
    @Published var artistConcerts: [SpotifyArtistConcert] = []
    @Published var playlistRecommendations: [SpotifyRecommendedTrack] = []
    @Published var recentlyPlayedItems: [SpotifyRecentlyPlayedItem] = []
    @Published var homeSections: [SpotifyHomeSection] = []
    @Published var homeGreeting: String?
    @Published var deviceTransferNotice: String?
    @Published var smartShuffleAvailable: Bool = false
    @Published var hasUnreadNotifications: Bool = false
    @Published var currentPlaylistPermissions: SpotifyPlaylistPermissions?
    @Published var jamSessionActive: Bool = false
    @Published var libraryImportEligible: Bool = false
    @Published var popularReleases: [SpotifyPopularRelease] = []
    @Published var nowPlayingArtist: SpotifyArtistProfile?
    @Published var similarAlbums: [SpotifySimilarAlbum] = []
    @Published var relatedTracks: [SpotifyRecommendedTrack] = []
    @Published var trackArtistCredits: [SpotifyTrackArtistCredit] = []
    @Published var isEnhanceLoading: Bool = false
    @Published var isConnectStreamingSession: Bool = false
    @Published var isSmartShuffleActive: Bool = false
    private var deviceTransferNoticeClearTask: Task<Void, Never>?

    var isControllingConnectPlayback: Bool {
        guard isConnectStreamingSession,
              let active = activePlayerDeviceID,
              let selfId = controllerDeviceID else { return false }
        return active != selfId
    }

    var isActivelyStreaming: Bool { isControllingConnectPlayback }

    var currentTrackURI: String? { playerState?.track?.uri }
    var currentContextURI: String? { playerState?.contextUri }

    func scheduleDeviceTransferNoticeClear(after seconds: TimeInterval = 4) {
        deviceTransferNoticeClearTask?.cancel()
        deviceTransferNoticeClearTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self.deviceTransferNotice = nil
        }
    }

    private let cookieManager = CookieManager()
    var webSocketManager: WebSocketManager?
    private var stateCancellables = Set<AnyCancellable>()
    private var sessionCancellables = Set<AnyCancellable>()

    internal var openSpotifyClient: CustomTLSClient?
    internal var spclientClient: CustomTLSClient?
    internal var apiPartnerClient: CustomTLSClient?
    internal var clientTokenClient: CustomTLSClient?
    internal var wwwSpotifyClient: CustomTLSClient?
    internal var wgSpclientClient: CustomTLSClient?

    private var accessToken: String?
    private var accessTokenExpiresAt: Date?
    private var clientToken: String?
    private var clientTokenRefreshAt: Date?
    private var webPlayerClientID: String?
    private var tokenRefreshTask: Task<Void, Never>?
    private var softReconnectObserver: AnyCancellable?

    func currentAccessToken() -> String? { accessToken }
    internal var clientVersion: String?

    var sessionDeviceID: String?
    var controllerDeviceID: String?

    private var jsPackURL: String?
    private var operationHashes: [String: String] = [:]
    private var playlistTrackUIDByNormalizedURI: [String: String] = [:]
    private let commonUserAgent = SpotifyWebPlayerIdentity.userAgent

    private static let webPlayerClientID = "d8a5ed958d274c2e8ee717e6a4b0971d"

    private let sessionUserDefaultsKey = "spotAPISessionCookies"
    private let controllerDeviceIDKey = "spotAPIControllerDeviceID"
    private let externalRefreshTokenKey = "spotAPIExternalRefreshToken"
    private let externalClientIDKey = "spotAPIExternalClientID"
    private let externalClientSecretKey = "spotAPIExternalClientSecret"
    private let preferredSpclientHostKey = "spotAPIPreferredSpclientHost"

    private var queueHydrationTask: Task<Void, Never>?
    private var queueRefreshTask: Task<Void, Never>?
    private var libraryFetchTask: Task<Void, Never>?
    private var reestablishTask: Task<Void, Never>?
    private var activeSessionAttemptID = UUID()
    private var lastPlayerStateSignature: PrivatePlayerStateSignature?
    private var lastQueueHydrationIDs: [String] = []
    private var nowPlayingHydrationTrackURI: String?
    private var lastAdSkipAttemptAt: Date?
    private var isSkippingAd = false
    private let adSkipCooldown: TimeInterval = 18

    private var bootstrapTask: Task<Void, Never>?
    private var hasRequestedSessionBootstrap = false

    enum SessionBootstrapPolicy {
        case automatic
        case onDemand
        case reconnect
    }

    private lazy var apiCache = FileAPICache()

    private init() {
        setupSubscribers()
    }

    func hasPersistedSession() -> Bool {
        guard let savedCookiesData = UserDefaults.standard.array(forKey: sessionUserDefaultsKey) as? [[String: Any]] else {
            return false
        }
        return !savedCookiesData.isEmpty
    }

    private func shouldAutoBootstrapAtLaunch() -> Bool {
        guard hasPersistedSession() else { return false }
        return SettingsModel.shared.settings.defaultMusicPlayer == .spotify
    }

    func bootstrapIfNeeded(
        policy: SessionBootstrapPolicy = .automatic,
        delay: TimeInterval = 0
    ) {
        guard !isLoggedIn, loginChallenge == nil else { return }

        switch policy {
        case .automatic:
            guard shouldAutoBootstrapAtLaunch() else { return }
        case .onDemand:
            guard hasPersistedSession() else { return }
        case .reconnect:
            guard hasRequestedSessionBootstrap || shouldAutoBootstrapAtLaunch() else { return }
        }

        guard bootstrapTask == nil, reestablishTask == nil else { return }

        hasRequestedSessionBootstrap = true
        bootstrapTask = Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            guard !Task.isCancelled else { return }
            await self.loadSession()
            await MainActor.run {
                self.bootstrapTask = nil
            }
        }
    }

    private func setupSubscribers() {
        $playerState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] playerState in
                guard let self = self, let playerState = playerState else { return }

                Task { await self.hydrateNowPlayingIfNeeded(for: playerState) }
                self.hydrateQueue(from: playerState)

                if self.isAdvertisement(playerState) {
                    Task { await self.skipAd() }
                }
            }
            .store(in: &stateCancellables)
    }

    private func isAdvertisement(_ playerState: PlayerState) -> Bool {
        if playerState.track?.uri.hasPrefix("spotify:ad:") == true { return true }
        if playerState.track?.metadata?.hidden == "true" { return true }
        return false
    }

    private var isLocalSpotifyActivePlayer: Bool {
        guard SpotifyAppleScriptManager.shared.isAppRunning() else { return false }
        guard let active = activePlayerDeviceID else {
            return true
        }
        if active == controllerDeviceID { return false }
        guard let device = devices.first(where: { $0.deviceId == active }) else { return true }
        let name = device.name.lowercased()
        let type = device.deviceType.lowercased()
        if name.contains("sapphire") { return false }
        return type == "computer" || name.contains("mac") || name == "spotify" || type.contains("computer")
    }

    private func initializeClients() async {
        let spclientHost = await resolveSpclientHost()
        openSpotifyClient = CustomTLSClient(host: "open.spotify.com", userAgent: commonUserAgent, cookieManager: cookieManager)
        spclientClient = CustomTLSClient(host: spclientHost, userAgent: commonUserAgent, cookieManager: cookieManager)
        apiPartnerClient = CustomTLSClient(host: "api-partner.spotify.com", userAgent: commonUserAgent, cookieManager: cookieManager)
        clientTokenClient = CustomTLSClient(host: "clienttoken.spotify.com", userAgent: commonUserAgent, cookieManager: cookieManager)
        wwwSpotifyClient = CustomTLSClient(host: "www.spotify.com", userAgent: commonUserAgent, cookieManager: cookieManager)
        wgSpclientClient = CustomTLSClient(host: "spclient.wg.spotify.com", userAgent: commonUserAgent, cookieManager: cookieManager)

        let clients: [CustomTLSClient?] = [
            openSpotifyClient,
            spclientClient,
            apiPartnerClient,
            clientTokenClient,
            wwwSpotifyClient,
            wgSpclientClient
        ]
        for client in clients {
            client?.onUnauthorized = { [weak self] in
                guard let self else { return false }
                return await self.refreshTokensIfNeeded(force: true)
            }
        }
    }

    private func resolveSpclientHost() async -> String {
        if let cached = UserDefaults.standard.string(forKey: preferredSpclientHostKey), !cached.isEmpty {
            Task.detached(priority: .utility) { [weak self] in
                await self?.refreshSpclientHostPreference()
            }
            return cached
        }
        return await refreshSpclientHostPreference() ?? "gue1-spclient.spotify.com"
    }

    @discardableResult
    private func refreshSpclientHostPreference() async -> String? {
        let fallbacks = [
            "gue1-spclient.spotify.com",
            "gew1-spclient.spotify.com",
            "guc3-spclient.spotify.com",
            "spclient.wg.spotify.com"
        ]
        guard let url = URL(string: "https://apresolve.spotify.com/?type=spclient") else {
            return fallbacks.first
        }
        do {
            var request = URLRequest(url: url)
            request.setValue(commonUserAgent, forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let hosts = json["spclient"] as? [String],
                  let first = hosts.first else {
                return fallbacks.first
            }
            let host = first.components(separatedBy: ":").first ?? first
            UserDefaults.standard.set(host, forKey: preferredSpclientHostKey)
            print("[SpotifyPrivateAPIManager] Resolved spclient host: \(host)")
            return host
        } catch {
            print("[SpotifyPrivateAPIManager] apresolve failed: \(error.localizedDescription)")
            return fallbacks.first
        }
    }

    func login() {
        hasRequestedSessionBootstrap = true
        Task { @MainActor in
            await self.prepareFreshLogin()
            self.loginChallenge = LoginChallengeDetails()
        }
    }

    private func prepareFreshLogin() async {
        reestablishTask?.cancel()
        reestablishTask = nil
        _internalLogout()
        await cookieManager.clear()
        UserDefaults.standard.removeObject(forKey: sessionUserDefaultsKey)
        await clearSpotifyBrowserData()
        print("[SpotifyPrivateAPIManager] Prepared fresh login — cleared cookies and browser data.")
    }

    func completeLoginAfterWebViewSuccess(with cookieProperties: [[String: Any]]) {
        hasRequestedSessionBootstrap = true
        let cookies = cookieProperties.compactMap { HTTPCookie(properties: $0.toStringKeys()) }
        Task {
            await cookieManager.clear()
            await cookieManager.setCookies(cookies)
            await saveSession()
            reestablishSession()
        }
    }

    func adoptExternalTokens(accessToken: String, refreshToken: String?, clientID: String, clientSecret: String?) {
        self.accessToken = accessToken
        if let refreshToken {
            UserDefaults.standard.set(refreshToken, forKey: externalRefreshTokenKey)
            UserDefaults.standard.set(clientID, forKey: externalClientIDKey)
            UserDefaults.standard.set(clientSecret, forKey: externalClientSecretKey)
        } else {
            UserDefaults.standard.removeObject(forKey: externalRefreshTokenKey)
            UserDefaults.standard.removeObject(forKey: externalClientIDKey)
            UserDefaults.standard.removeObject(forKey: externalClientSecretKey)
        }
        updateAllClientTokens()
        isLoggedIn = true
    }

    func logout() {
        _internalLogout()
        Task { await SpotifyRateLimitTracker.shared.reset() }

        Task { @MainActor in
            await apiCache.clear()
            await cookieManager.clear()
            await clearSpotifyBrowserData()
        }
        UserDefaults.standard.removeObject(forKey: sessionUserDefaultsKey)
    }

    @MainActor
    private func clearSpotifyBrowserData() async {
        let dataStore = WKWebsiteDataStore.default()
        let allCookies = await withCheckedContinuation { (continuation: CheckedContinuation<[HTTPCookie], Never>) in
            dataStore.httpCookieStore.getAllCookies { continuation.resume(returning: $0) }
        }
        for cookie in allCookies where cookie.domain.lowercased().contains("spotify") {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                dataStore.httpCookieStore.delete(cookie) { continuation.resume() }
            }
        }
        let records = await dataStore.dataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes())
        let spotifyRecords = records.filter {
            $0.displayName.localizedCaseInsensitiveContains("spotify")
        }
        guard !spotifyRecords.isEmpty else { return }
        await dataStore.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), for: spotifyRecords)
        print("[SpotifyPrivateAPIManager] Cleared Spotify browser data.")
    }

    private func invalidateStoredSession(reason: String, clearWebViewData: Bool = false) async {
        await cookieManager.clear()
        UserDefaults.standard.removeObject(forKey: sessionUserDefaultsKey)
        if clearWebViewData {
            await clearSpotifyBrowserData()
        }
        print("[SpotifyPrivateAPIManager] Invalidated stored session: \(reason)")
    }

    private func _internalLogout() {
        softReconnectRetryTask?.cancel()
        softReconnectRetryTask = nil
        resetActiveSession()
        reestablishTask?.cancel()
        reestablishTask = nil
        cancelTokenRefreshSchedule()
        softReconnectObserver?.cancel()
        softReconnectObserver = nil

        openSpotifyClient = nil; spclientClient = nil; apiPartnerClient = nil; clientTokenClient = nil; wwwSpotifyClient = nil; wgSpclientClient = nil
        accessToken = nil; clientToken = nil; activePlayerDeviceID = nil; controllerDeviceID = nil; sessionDeviceID = nil
        accessTokenExpiresAt = nil; clientTokenRefreshAt = nil; webPlayerClientID = nil; inFlightTokenRefresh = nil
        jsPackURL = nil; clientVersion = nil; operationHashes = [:]; playlistTrackUIDByNormalizedURI = [:]; playlistTrackIndexByUID = [:]
        Task { await SpotifyOperationHashRegistry.shared.invalidate() }

        self.isLoggedIn = false; self.userProfile = nil; self.profileFollowerCount = nil; self.playerState = nil; self.devices = []
        self.nativeQueue = []
        self.nativePlaylists = []
        self.selectedPlaylist = nil
        self.playlistTrackViewModels = []
        self.isPlaylistLoading = false
        self.accountInfo = nil; self.currentCanvas = nil; self.artistConcerts = []
        self.playlistRecommendations = []; self.recentlyPlayedItems = []; self.homeSections = []; self.homeGreeting = nil
        self.smartShuffleAvailable = false; self.hasUnreadNotifications = false
        self.currentPlaylistPermissions = nil
        self.jamSessionActive = false; self.libraryImportEligible = false
        self.popularReleases = []
        self.nowPlayingArtist = nil; self.similarAlbums = []; self.relatedTracks = []
        self.trackArtistCredits = []
        self.isEnhanceLoading = false
        self.isConnectStreamingSession = false
        self.isSmartShuffleActive = false
        self.lastPlayerStateSignature = nil
        self.lastQueueHydrationIDs = []
        self.nowPlayingHydrationTrackURI = nil
        self.deviceTransferNotice = nil
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
        guard reestablishTask == nil else { return }

        let attemptID = UUID()
        activeSessionAttemptID = attemptID
        resetActiveSession(preserveLogin: true)

        reestablishTask = Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            await self.runReestablishSession(attemptID: attemptID)
        }
    }

    @MainActor
    private func runReestablishSession(attemptID: UUID) async {
        defer {
            reestablishTask = nil
        }

        do {
            await initializeClients()

            try await verifySessionAndFetchUserInfo()

            if let sessionCookie = await cookieManager.allCookies()["sp_t"] {
                sessionDeviceID = sessionCookie.value
            } else {
                throw SpotAPIError.missingData("sp_t cookie not found in saved session.")
            }

            try await fetchApiTokensAndClientVersion()

            guard let token = accessToken else {
                throw SpotAPIError.authenticationFailed("Could not obtain access token before initializing WebSocket.")
            }

            let persistentDeviceID = getOrSetControllerDeviceID()
            controllerDeviceID = persistentDeviceID

            let wsManager = WebSocketManager(accessToken: token, client: self, controllerDeviceID: persistentDeviceID)
            webSocketManager = wsManager

            wsManager.playerStatePublisher
                .receive(on: DispatchQueue.main)
                .sink { [weak self, weak wsManager] update in
                    guard let self, let wsManager, self.webSocketManager === wsManager, self.activeSessionAttemptID == attemptID else { return }
                    if let activeId = update.activeDeviceId {
                        self.activePlayerDeviceID = activeId
                        if activeId == self.controllerDeviceID {
                            self.isConnectStreamingSession = false
                        } else {
                            self.lastLocalActivationKey = nil
                        }
                    }
                    if !update.devices.isEmpty {
                        self.devices = Array(update.devices.values)
                    }
                    self.applyPlayerStateIfNeeded(update.playerState)
                    self.handleLocalPlayerActivationIfNeeded(playerState: update.playerState)
                }
                .store(in: &sessionCancellables)

            wsManager.connectionIdPublisher
                .first()
                .receive(on: DispatchQueue.main)
                .sink { [weak self, weak wsManager] connectionId in
                    guard let self, let wsManager, self.webSocketManager === wsManager, self.activeSessionAttemptID == attemptID else { return }
                    Task {
                        await self.finishInitializationFlow(connectionId: connectionId, attemptID: attemptID)
                    }
                }
                .store(in: &sessionCancellables)

            wsManager.connect()

        } catch let error {
            guard activeSessionAttemptID == attemptID else { return }
            let message = error.localizedDescription
            let isHardCookieDeath: Bool = {
                if case SpotAPIError.authenticationFailed(let detail) = error {
                    let d = detail.lowercased()
                    return d.contains("missing sp_dc")
                        || d.contains("missing sp_key")
                        || d.contains("could not fetch user profile")
                        || d.contains("session verification failed")
                }
                return false
            }()

            if isHardCookieDeath {
                resetActiveSession()
                openSpotifyClient = nil; spclientClient = nil; apiPartnerClient = nil
                clientTokenClient = nil; wwwSpotifyClient = nil; wgSpclientClient = nil
                accessToken = nil; clientToken = nil; clientVersion = nil
                accessTokenExpiresAt = nil; clientTokenRefreshAt = nil; inFlightTokenRefresh = nil
                isLoggedIn = false
                cancelTokenRefreshSchedule()
                await invalidateStoredSession(reason: message)
                print("[SpotifyPrivateAPIManager] Failed to re-establish session: \(message). Stored cookies cleared — sign in again.")
            } else {
                webSocketManager?.disconnect()
                webSocketManager = nil
                sessionCancellables.removeAll()
                print("[SpotifyPrivateAPIManager] Failed to re-establish session: \(message). Keeping login; scheduling retry.")
                scheduleSoftReconnectRetry()
            }
        }
    }

    func requestSessionReestablishment(from webSocketManager: WebSocketManager) {
        guard self.webSocketManager === webSocketManager else { return }
        reestablishSession()
    }

    func observeSoftReconnectConnection(from webSocketManager: WebSocketManager) {
        guard self.webSocketManager === webSocketManager else { return }
        softReconnectObserver?.cancel()
        softReconnectObserver = webSocketManager.connectionIdPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak webSocketManager] connectionId in
                guard let self, let webSocketManager, self.webSocketManager === webSocketManager else { return }
                Task {
                    do {
                        try await self.performDeviceRegistration(connectionId: connectionId)
                        try? await self.refreshPlayerAndDeviceState()
                        print("[SpotifyPrivateAPIManager] Soft reconnect rebound connection_id=\(connectionId.prefix(8))…")
                    } catch {
                        print("[SpotifyPrivateAPIManager] Soft reconnect rebind failed: \(error.localizedDescription)")
                    }
                }
            }
    }

    private func finishInitializationFlow(connectionId: String, attemptID: UUID) async {
        do {
            try await performDeviceRegistration(connectionId: connectionId)

            do {
                let playerStateResponse = try await fetchInitialPlayerState()
                self.applyPlayerStateIfNeeded(playerStateResponse.playerState)
                self.devices = Array(playerStateResponse.devices.values)
                self.activePlayerDeviceID = playerStateResponse.activeDeviceId

                if let previouslyActiveDevice = playerStateResponse.activeDeviceId,
                   let newControllerID = self.controllerDeviceID,
                   previouslyActiveDevice != newControllerID {
                    self.activePlayerDeviceID = previouslyActiveDevice
                } else if let active = playerStateResponse.activeDeviceId {
                    self.activePlayerDeviceID = active
                }
            } catch {
                print("[SpotifyPrivateAPIManager] Initial player state unavailable (continuing login): \(error.localizedDescription)")
            }

            await performUserVerification()
            await sendGaboSessionEvent()
            self.isLoggedIn = true
            await saveSession()

            do {
                try await self.refreshPlayerAndDeviceState()
            } catch {
                print("[SpotifyPrivateAPIManager] Player state refresh failed after login (session kept): \(error.localizedDescription)")
            }

            await self.refreshExtendedSessionData()

            guard self.activeSessionAttemptID == attemptID else { return }
        } catch {
            guard self.activeSessionAttemptID == attemptID else { return }
            print("[SpotifyPrivateAPIManager] Error in final initialization flow: \(error.localizedDescription)")
            scheduleSoftReconnectRetry()
        }
    }

    private var softReconnectRetryTask: Task<Void, Never>?

    private func scheduleSoftReconnectRetry(after delay: TimeInterval = 3.0) {
        softReconnectRetryTask?.cancel()
        softReconnectRetryTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            guard self.loginChallenge == nil else { return }
            if self.webSocketManager?.hasActiveConnection == true { return }
            if self.isLoggedIn {
                self.reestablishSession()
            } else {
                self.bootstrapIfNeeded(policy: .reconnect)
            }
        }
    }

    private func resetActiveSession(preserveLogin: Bool = false) {
        queueHydrationTask?.cancel()
        queueHydrationTask = nil
        queueRefreshTask?.cancel()
        queueRefreshTask = nil
        libraryFetchTask?.cancel()
        libraryFetchTask = nil
        if !preserveLogin {
            isLoggedIn = false
        }
        activePlayerDeviceID = nil
        webSocketManager?.disconnect()
        webSocketManager = nil
        sessionCancellables.removeAll()
    }

    func skipAd() async {
        guard SettingsModel.shared.settings.skipSpotifyAd else { return }
        guard !isSkippingAd else { return }

        if let last = lastAdSkipAttemptAt, Date().timeIntervalSince(last) < adSkipCooldown {
            return
        }

        guard isLocalSpotifyActivePlayer else { return }

        isSkippingAd = true
        lastAdSkipAttemptAt = Date()
        defer { isSkippingAd = false }

        let contextURI = playerState?.contextUri
        let nextContent = playerState?.nextTracks?.first { track in
            !track.uri.hasPrefix("spotify:ad:")
                && !track.uri.contains("spotify:delimiter")
                && track.metadata?.hidden != "true"
        }
        let preferredDeviceID = activePlayerDeviceID

        print("[SpotifyPrivateAPIManager] Local ad detected — relaunching Spotify in the background, then Connect resume.")
        let ok = await SpotifyAppleScriptManager.shared.relaunchWithoutActivating()
        guard ok else {
            print("[SpotifyPrivateAPIManager] Background Spotify relaunch failed.")
            return
        }

        await resumePlaybackAfterAdRelaunch(
            preferredDeviceID: preferredDeviceID,
            trackURI: nextContent?.uri,
            trackUID: nextContent?.uid,
            contextURI: contextURI
        )
    }

    private func resumePlaybackAfterAdRelaunch(
        preferredDeviceID: String?,
        trackURI: String?,
        trackUID: String?,
        contextURI: String?
    ) async {
        guard isLoggedIn, controllerDeviceID != nil else {
            print("[SpotifyPrivateAPIManager] Cannot Connect-resume after ad — not logged in.")
            return
        }

        for attempt in 0..<24 {
            try? await Task.sleep(nanoseconds: 500_000_000)
            if await SpotifyRateLimitTracker.shared.isThrottled(host: "spclient.spotify.com") {
                print("[SpotifyPrivateAPIManager] Spotify is rate limiting — aborting ad-skip polling.")
                return
            }
            guard SpotifyAppleScriptManager.shared.isAppRunning() else { continue }

            try? await refreshPlayerAndDeviceState()

            if let currentURI = playerState?.track?.uri,
               currentURI.hasPrefix("spotify:ad:") || currentURI.contains(":ad:") {
                print("[SpotifyPrivateAPIManager] Ad still playing after relaunch — skipping track (attempt \(attempt + 1)).")
                try? await skipNext()
                try? await Task.sleep(nanoseconds: 400_000_000)
                try? await refreshPlayerAndDeviceState()
                if let uri = playerState?.track?.uri,
                   !uri.hasPrefix("spotify:ad:"),
                   !uri.contains(":ad:") {
                    print("[SpotifyPrivateAPIManager] Skip cleared ad on attempt \(attempt + 1).")
                    return
                }
            }

            let localID = devices.first(where: { $0.deviceId == preferredDeviceID })?.deviceId
                ?? localSpotifyDesktopDeviceID()
            guard let localID else { continue }

            if let trackURI, !trackURI.isEmpty {
                let result = await connectPlay(
                    trackUri: trackURI,
                    contextUri: contextURI,
                    trackUid: trackUID,
                    trackIndex: nil
                )
                if case .success = result {
                    print("[SpotifyPrivateAPIManager] Post-ad Connect play succeeded on attempt \(attempt + 1).")
                    return
                }
            }

            do {
                let from = activePlayerDeviceID ?? controllerDeviceID!
                if from != localID {
                    try await transferDevice(from: from, to: localID)
                }
                activePlayerDeviceID = localID
                if await sendConnectCommandReturning(endpoint: "resume") {
                    print("[SpotifyPrivateAPIManager] Post-ad Connect resume succeeded on attempt \(attempt + 1).")
                    return
                }
            } catch {
                print("[SpotifyPrivateAPIManager] Post-ad transfer/resume attempt \(attempt + 1) failed: \(error.localizedDescription)")
            }
        }

        print("[SpotifyPrivateAPIManager] Timed out waiting to Connect-resume after ad relaunch.")
    }

    private func localSpotifyDesktopDeviceID() -> String? {
        devices.first { device in
            let name = device.name.lowercased()
            let type = device.deviceType.lowercased()
            guard !name.contains("sapphire") else { return false }
            return type == "computer" || type.contains("computer") || name.contains("mac") || name == "spotify"
        }?.deviceId
    }

    func skipAdIfNeededFromMediaRemote(isAdvertisement: Bool) async {
        guard isAdvertisement else { return }
        await skipAd()
    }

    func searchForTrack(title: String, artist: String) async -> SpotifyTrack? {
        await searchForTrackResilient(title: title, artist: artist)
    }

    func fetchTrackDetails(trackId: String) async -> SpotifyTrackDetailsResponse.TrackUnion? {
        await fetchTrackMetadataResilient(trackID: trackId)
    }

    func loadPlaylist(playlistId: String) async {
        guard !playlistId.contains(":collection") && playlistId != "tracks" else { return }
        isPlaylistLoading = true
        defer { isPlaylistLoading = false }

        do {
            resetLoadedPlaylistState()
            let playlistURI = "spotify:playlist:\(playlistId)"
            playlistLoadedURI = playlistURI
            playlistNextOffset = 0
            playlistHasMore = false
            playlistTotalCount = 0

            let page = try await fetchPlaylistContentsPage(uri: playlistURI, offset: 0, limit: 50)
            guard var freshPlaylistData = page else {
                throw SpotAPIError.missingData("Initial PlaylistV2 data was missing.")
            }
            if Task.isCancelled { return }

            var playlistName = freshPlaylistData.name
            if playlistName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || playlistName == "Playlist" {
                if let meta: SpotifyPlaylistDetailsResponse = try? await pathfinderQuery(
                    operationName: "fetchPlaylist",
                    variables: [
                        "uri": playlistURI,
                        "offset": 0,
                        "limit": 25,
                        "enableWatchFeedEntrypoint": true,
                        "includeEpisodeContentRatingsV2": true
                    ],
                    sendAsBody: true,
                    cachePolicy: .fetchIgnoringCacheData,
                    useV2Endpoint: true
                ), let named = meta.data?.playlistV2?.name, !named.isEmpty {
                    playlistName = named
                }
            }

            freshPlaylistData.uri = playlistURI
            self.selectedPlaylist = SpotifyPlaylistDetailsResponse.PlaylistV2(
                name: playlistName,
                uri: playlistURI,
                content: .init(totalCount: freshPlaylistData.content.totalCount, items: [])
            )
            self.playlistTotalCount = freshPlaylistData.content.totalCount
            self.playlistTrackViewModels = registerPlaylistItems(freshPlaylistData.content.items, startingAt: 0)
            self.playlistNextOffset = freshPlaylistData.content.items.count
            self.playlistHasMore = playlistNextOffset < playlistTotalCount

            await hydrateSparsePlaylistTracksIfNeeded()

            async let permissions = fetchPlaylistPermissions(uri: playlistURI)
            async let recommendations = extendPlaylist(uri: playlistURI)
            async let smartShuffle = checkSmartShuffleAvailable(uri: playlistURI)
            self.currentPlaylistPermissions = await permissions
            _ = await recommendations
            _ = await smartShuffle
        } catch {
            if !(error is CancellationError) {
                print("[SpotifyPrivateAPIManager] Error loading playlist via pathfinder: \(error.localizedDescription). Trying playlist/v2 fallback.")
                let fallbackLoaded = await loadPlaylistUsingSignals(playlistId: playlistId)
                if fallbackLoaded {
                    await hydrateSparsePlaylistTracksIfNeeded()
                    playlistHasMore = false
                } else {
                    self.selectedPlaylist = nil
                }
            }
        }
    }

    func loadMorePlaylistTracks() async {
        guard !isPlaylistLoadingMore,
              playlistHasMore,
              let uri = playlistLoadedURI ?? selectedPlaylist?.uri,
              !uri.isEmpty else { return }

        isPlaylistLoadingMore = true
        defer { isPlaylistLoadingMore = false }

        do {
            guard let page = try await fetchPlaylistContentsPage(uri: uri, offset: playlistNextOffset, limit: 50) else { return }
            let newItems = page.content.items
            guard !newItems.isEmpty else {
                playlistHasMore = false
                return
            }
            let start = playlistNextOffset
            playlistTrackViewModels.append(contentsOf: registerPlaylistItems(newItems, startingAt: start))
            playlistNextOffset += newItems.count
            playlistTotalCount = max(playlistTotalCount, page.content.totalCount)
            playlistHasMore = playlistNextOffset < playlistTotalCount
            await hydrateSparsePlaylistTracksIfNeeded()
        } catch {
            print("[SpotifyPrivateAPIManager] loadMorePlaylistTracks failed: \(error.localizedDescription)")
        }
    }

    private func fetchPlaylistContentsPage(uri: String, offset: Int, limit: Int) async throws -> SpotifyPlaylistDetailsResponse.PlaylistV2? {
        let variables: [String: Any] = [
            "uri": uri,
            "offset": offset,
            "limit": limit,
            "includeEpisodeContentRatingsV2": true
        ]
        let response: SpotifyPlaylistDetailsResponse = try await pathfinderQuery(
            operationName: "fetchPlaylistContents",
            variables: variables,
            sendAsBody: true,
            cachePolicy: .fetchIgnoringCacheData,
            useV2Endpoint: true
        )
        return response.data?.playlistV2
    }

    func loadLikedSongs(for playlist: SpotifyPlaylist) async {
        isPlaylistLoading = true
        defer { isPlaylistLoading = false }

        do {
            resetLoadedPlaylistState()
            var allLikedItems: [LikedSongItem] = []
            var offset = 0
            let limit = 500
            var totalCount = 0

            repeat {
                let variables: [String: Any] = ["offset": offset, "limit": limit]
                let response: LikedSongsResponse = try await pathfinderQuery(
                    operationName: "fetchLibraryTracks",
                    variables: variables,
                    sendAsBody: true,
                    cachePolicy: .fetchIgnoringCacheData
                )
                if Task.isCancelled { return }

                let pageItems = response.data.me.library.tracks.items
                if pageItems.isEmpty { break }

                allLikedItems.append(contentsOf: pageItems)
                totalCount = response.data.me.library.tracks.totalCount
                offset += pageItems.count

                if offset == pageItems.count || offset >= totalCount {
                    let playlistItems = allLikedItems.map { likedItem -> SpotifyPlaylistDetailsResponse.PlaylistItem in
                        var mutableItemData = likedItem.track.data
                        mutableItemData.uri = likedItem.track.uri
                        return SpotifyPlaylistDetailsResponse.PlaylistItem(
                            uid: likedItem.track.uri,
                            itemV2: .init(data: mutableItemData),
                            addedAtInfo: likedItem.addedAtInfo,
                            addedBy: nil
                        )
                    }
                    self.selectedPlaylist = SpotifyPlaylistDetailsResponse.PlaylistV2(
                        name: playlist.name,
                        uri: playlist.uri,
                        content: .init(totalCount: totalCount, items: [])
                    )
                    self.playlistTotalCount = totalCount
                    self.playlistTrackViewModels = registerPlaylistItems(playlistItems, startingAt: 0)
                    self.playlistLoadedURI = playlist.uri
                }
            } while offset < totalCount && !Task.isCancelled

            let finalPlaylistItems = allLikedItems.map { likedItem -> SpotifyPlaylistDetailsResponse.PlaylistItem in
                var mutableItemData = likedItem.track.data
                mutableItemData.uri = likedItem.track.uri
                return SpotifyPlaylistDetailsResponse.PlaylistItem(
                    uid: likedItem.track.uri,
                    itemV2: .init(data: mutableItemData),
                    addedAtInfo: likedItem.addedAtInfo,
                    addedBy: nil
                )
            }

            self.selectedPlaylist = SpotifyPlaylistDetailsResponse.PlaylistV2(
                name: playlist.name,
                uri: playlist.uri,
                content: .init(totalCount: totalCount, items: [])
            )
            self.playlistTotalCount = totalCount
            self.playlistTrackViewModels = registerPlaylistItems(finalPlaylistItems, startingAt: 0)
            self.playlistHasMore = false
            self.playlistNextOffset = finalPlaylistItems.count
            self.playlistLoadedURI = playlist.uri
        } catch {
            if !(error is CancellationError) {
                print("[SpotifyPrivateAPIManager] Error loading liked songs: \(error.localizedDescription)")
                self.selectedPlaylist = nil
            }
        }
    }

    func fetchUserLibrary(order: String? = nil) async {
        guard isLoggedIn else { return }

        if let existing = libraryFetchTask {
            await existing.value
            if order == nil || order == selectedLibrarySortOrderId {
                return
            }
        }

        let requestedOrder = order
        libraryFetchTask = Task {
            defer { self.libraryFetchTask = nil }
            do {
                let sortId = requestedOrder ?? self.selectedLibrarySortOrderId
                let library = try await self.fetchLibrary(order: sortId)
                if let orders = library.availableSortOrders, !orders.isEmpty {
                    self.librarySortOrders = orders
                }
                if let selected = library.selectedSortOrder?.id {
                    self.selectedLibrarySortOrderId = selected
                } else if let requestedOrder {
                    self.selectedLibrarySortOrderId = requestedOrder
                }
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
                if playlists.isEmpty {
                    let rootlist = await self.fetchPlaylistRootlist()
                    if !rootlist.isEmpty { self.nativePlaylists = rootlist }
                }
            } catch {
                if error is CancellationError { return }
                print("[SpotifyPrivateAPIManager] Error fetching user library: \(error.localizedDescription)")
                let rootlist = await self.fetchPlaylistRootlist()
                self.nativePlaylists = rootlist
            }
        }

        await libraryFetchTask?.value
    }

    func loadPlaylistUsingSignals(playlistId: String) async -> Bool {
        guard let client = wgSpclientClient else { return false }
        let path = "/playlist/v2/playlist/\(playlistId)/signals"
        let payload: [String: Any] = [
            "emittedSignals": [
                ["identifier": "reset", "data": "CgdlbmhhbmNl"]
            ]
        ]

        do {
            let response = try await client.post(
                path: path,
                queryItems: [URLQueryItem(name: "spotify-apply-lenses", value: "enhance")],
                jsonBody: payload
            )

            guard let json = try JSONSerialization.jsonObject(with: response.body) as? [String: Any] else {
                return false
            }

            let attrs = json["attributes"] as? [String: Any]
            let playlistName = (attrs?["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let items = ((json["contents"] as? [String: Any])?["items"] as? [[String: Any]]) ?? []

            let playlistItems: [SpotifyPlaylistDetailsResponse.PlaylistItem] = items.compactMap { item in
                guard let uri = item["uri"] as? String, uri.hasPrefix("spotify:track:") else { return nil }
                let title = (item["attributes"] as? [String: Any])?["name"] as? String
                let data = SpotifyPlaylistDetailsResponse.ItemData(
                    uri: uri,
                    name: title ?? uri.components(separatedBy: ":").last,
                    albumOfTrack: nil,
                    artists: nil,
                    playcount: nil
                )
                return SpotifyPlaylistDetailsResponse.PlaylistItem(
                    uid: uri,
                    itemV2: .init(data: data),
                    addedAtInfo: nil
                )
            }

            self.selectedPlaylist = SpotifyPlaylistDetailsResponse.PlaylistV2(
                name: (playlistName?.isEmpty == false ? playlistName! : "Playlist"),
                uri: "spotify:playlist:\(playlistId)",
                content: .init(totalCount: playlistItems.count, items: [])
            )
            self.playlistTrackViewModels = registerPlaylistItems(playlistItems, startingAt: 0)
            return !playlistItems.isEmpty
        } catch {
            print("[SpotifyPrivateAPIManager] playlist/v2 fallback failed: \(error.localizedDescription)")
            return false
        }
    }

    private func hydrateSparsePlaylistTracksIfNeeded() async {
        let sparseIndexes = playlistTrackViewModels.enumerated().compactMap { index, model -> Int? in
            let looksLikeID = model.name.count == 22 || model.artists == "Unknown Artist" || model.albumName == "Unknown Album"
            return looksLikeID ? index : nil
        }
        guard !sparseIndexes.isEmpty else { return }

        let uris = sparseIndexes.map { playlistTrackViewModels[$0].uri }.filter { !$0.isEmpty }
        guard !uris.isEmpty else { return }

        let decorated = await decorateContextTracks(uris: uris)
        let byURI = Dictionary(uniqueKeysWithValues: decorated.map { ($0.uri, $0) })

        for index in sparseIndexes {
            let uri = playlistTrackViewModels[index].uri
            guard let details = byURI[uri] else { continue }
            let existing = playlistTrackViewModels[index]
            let preservedAddedAt = existing.dateAdded.map { timestamp -> SpotifyPlaylistDetailsResponse.AddedAt in
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime]
                return SpotifyPlaylistDetailsResponse.AddedAt(
                    isoString: formatter.string(from: Date(timeIntervalSince1970: timestamp))
                )
            }
            let hydratedItem = SpotifyPlaylistDetailsResponse.PlaylistItem(
                uid: existing.uid ?? uri,
                itemV2: .init(data: .init(
                    uri: details.uri,
                    name: details.name,
                    albumOfTrack: .init(
                        name: details.albumOfTrack.name,
                        coverArt: .init(
                            items: nil,
                            sources: details.albumOfTrack.coverArt?.sources.map {
                                ImageSource(url: $0.url)
                            }
                        ),
                        publishDate: nil
                    ),
                    artists: .init(items: details.artists.items.compactMap { artist in
                        guard let artistURI = artist.uri else { return nil }
                        return ArtistItem(uri: artistURI, profile: .init(name: artist.profile.name))
                    }),
                    playcount: nil
                )),
                addedAtInfo: preservedAddedAt,
                addedBy: existing.addedByName.map {
                    .init(data: .init(name: $0, username: nil, uri: nil))
                }
            )
            playlistTrackViewModels[index] = TrackViewModel(playlistItem: hydratedItem)
        }
    }

    func likeTrack(trackURI: String) async -> Bool {
        if await applyCuration(trackURI: trackURI, curationType: "CURATE") {
            return true
        }
        if await addToLikedSongsPlaylist(trackURI: trackURI) {
            return true
        }
        do {
            let _: EmptyResponse = try await pathfinderQuery(
                operationName: "addToLibrary",
                variables: ["uris": [trackURI]],
                sendAsBody: true,
                useV2Endpoint: true
            )
            return true
        } catch {
            print("[SpotifyPrivateAPIManager] Error liking track: \(error.localizedDescription)")
            return false
        }
    }

    func unlikeTrack(trackURI: String) async -> Bool {
        if await applyCuration(trackURI: trackURI, curationType: "UNCURATE") {
            return true
        }
        if await removeFromLikedSongsPlaylist(trackURI: trackURI) {
            return true
        }
        do {
            let _: EmptyResponse = try await pathfinderQuery(
                operationName: "removeFromLibrary",
                variables: ["uris": [trackURI]],
                sendAsBody: true,
                useV2Endpoint: true
            )
            return true
        } catch {
            print("[SpotifyPrivateAPIManager] Error unliking track: \(error.localizedDescription)")
            return false
        }
    }

    private func applyCuration(trackURI: String, curationType: String) async -> Bool {
        guard trackURI.contains("spotify:track:") else { return false }
        struct ApplyCurationsResponse: Decodable {
            let data: DataNode?
            struct DataNode: Decodable {
                let applyCurations: [CurationItem]?
            }
            struct CurationItem: Decodable {
                let data: CuratedData?
            }
            struct CuratedData: Decodable {
                let isCurated: Bool?
            }
        }

        do {
            let response: ApplyCurationsResponse = try await pathfinderQuery(
                operationName: "applyCurations",
                variables: [
                    "input": [
                        "curations": [[
                            "contextUri": "spotify:collection:tracks",
                            "curationType": curationType
                        ]],
                        "itemUris": [trackURI]
                    ]
                ],
                sendAsBody: true,
                cachePolicy: .fetchIgnoringCacheData,
                useV2Endpoint: true
            )
            guard let items = response.data?.applyCurations, !items.isEmpty else {
                return true
            }
            if let curated = items.first?.data?.isCurated {
                return curationType == "CURATE" ? curated : !curated
            }
            return true
        } catch {
            print("[SpotifyPrivateAPIManager] applyCurations(\(curationType)) failed: \(error.localizedDescription)")
            return false
        }
    }

    func addToLikedSongsPlaylist(trackURI: String) async -> Bool {
        if await collectionMutate(path: "/collection/v2/add", set: "tracks", uris: [trackURI]) {
            return true
        }
        return await addTracksToPlaylist(playlistURI: likedSongsPlaylistURI(), trackURIs: [trackURI])
    }

    func removeFromLikedSongsPlaylist(trackURI: String) async -> Bool {
        if await collectionMutate(path: "/collection/v2/remove", set: "tracks", uris: [trackURI]) {
            return true
        }
        return await removeTracksFromPlaylist(playlistURI: likedSongsPlaylistURI(), trackURIs: [trackURI])
    }

    private func likedSongsPlaylistURI() -> String? {
        guard let username = userProfile?.profile.username, !username.isEmpty else { return nil }
        return "spotify:user:\(username):collection"
    }

    func addTracksToPlaylist(playlistURI: String?, trackURIs: [String]) async -> Bool {
        guard let playlistURI, !playlistURI.isEmpty, !trackURIs.isEmpty else { return false }
        guard let client = wgSpclientClient ?? spclientClient else { return false }

        if playlistURI.contains(":collection"),
           let username = userProfile?.profile.username {
            let path = "/playlist/v2/playlist/user/\(username)/collection/tracks"
            let payload: [String: Any] = [
                "uris": trackURIs,
                "operation": "add"
            ]
            do {
                let response = try await client.post(path: path, jsonBody: payload)
                if (200...299).contains(response.statusCode) { return true }
            } catch {
                print("[SpotifyPrivateAPIManager] collection playlist add failed: \(error.localizedDescription)")
            }
        }

        let encoded = playlistURI
            .replacingOccurrences(of: "spotify:playlist:", with: "")
            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? playlistURI
        let path = "/playlist/v2/playlist/\(encoded)/items/add"
        let payload: [String: Any] = [
            "uris": trackURIs,
            "duplicates": "add_as_new_item"
        ]
        do {
            let response = try await client.post(path: path, jsonBody: payload)
            return (200...299).contains(response.statusCode)
        } catch {
            print("[SpotifyPrivateAPIManager] addTracksToPlaylist failed: \(error.localizedDescription)")
            return false
        }
    }

    func removeTracksFromPlaylist(playlistURI: String?, trackURIs: [String]) async -> Bool {
        guard let playlistURI, !playlistURI.isEmpty, !trackURIs.isEmpty else { return false }
        guard let client = wgSpclientClient ?? spclientClient else { return false }

        if playlistURI.contains(":collection"),
           let username = userProfile?.profile.username {
            let path = "/playlist/v2/playlist/user/\(username)/collection/tracks"
            let payload: [String: Any] = [
                "uris": trackURIs,
                "operation": "remove"
            ]
            do {
                let response = try await client.post(path: path, jsonBody: payload)
                if (200...299).contains(response.statusCode) { return true }
            } catch {
                print("[SpotifyPrivateAPIManager] collection playlist remove failed: \(error.localizedDescription)")
            }
        }
        return false
    }

    func checkTrackInPlaylist(trackURI: String, playlist: SpotifyPlaylist) async -> Bool {
        if playlist.uri.contains(":collection"), let username = userProfile?.profile.username {
            return false
        }
        let normalizedTrack = normalizeSpotifyUri(trackURI)
        guard !normalizedTrack.isEmpty else { return false }
        do {
            if let playlistDetails = try await fetchPlaylistContentsPage(uri: playlist.uri, offset: 0, limit: 100) {
                let contains = playlistDetails.content.items.contains { item in
                    let itemURI = normalizeSpotifyUri(item.itemV2.data.uri ?? "")
                    return itemURI == normalizedTrack
                }
                return contains
            }
        } catch {
        }
        return false
    }

    func checkTrackMembership(trackURI: String, playlists: [SpotifyPlaylist]) async -> Set<String> {
        await withTaskGroup(of: (String, Bool).self, returning: Set<String>.self) { group in
            for playlist in playlists {
                group.addTask { [weak self] in
                    guard let self else { return (playlist.uri, false) }
                    let contained = await self.checkTrackInPlaylist(trackURI: trackURI, playlist: playlist)
                    return (playlist.uri, contained)
                }
            }
            var containedURIs = Set<String>()
            for await (uri, contained) in group {
                if contained { containedURIs.insert(uri) }
            }
            return containedURIs
        }
    }

    private func collectionMutate(path: String, set: String, uris: [String]) async -> Bool {
        guard !uris.isEmpty else { return false }
        guard let client = wgSpclientClient ?? spclientClient else { return false }

        var username = userProfile?.profile.username
        if username == nil || username?.isEmpty == true {
            _ = await fetchProfileAttributes()
            username = userProfile?.profile.username
        }
        guard let username, !username.isEmpty else {
            print("[SpotifyPrivateAPIManager] \(path) skipped — missing username")
            return false
        }

        let payload: [String: Any] = [
            "username": username,
            "set": set,
            "items": uris.map { ["uri": $0] }
        ]
        let fullPath = path.contains("?") ? path : "\(path)?market=from_token"
        do {
            let response = try await client.post(path: fullPath, jsonBody: payload)
            let ok = (200...299).contains(response.statusCode)
            if !ok {
                print("[SpotifyPrivateAPIManager] \(fullPath) HTTP \(response.statusCode)")
            }
            return ok
        } catch {
            print("[SpotifyPrivateAPIManager] \(fullPath) failed: \(error.localizedDescription)")
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
        if toDeviceId == controllerDeviceID {
            await MainActor.run {
                self.deviceTransferNotice = "Sapphire is not a Spotify speaker. Choose the desktop app or another device."
                self.scheduleDeviceTransferNoticeClear()
            }
            return false
        }

        guard let fromDeviceId = activePlayerDeviceID ?? controllerDeviceID else { return false }
        do {
            try await transferDevice(from: fromDeviceId, to: toDeviceId)
            await MainActor.run {
                self.deviceTransferNotice = nil
                self.isConnectStreamingSession = true
            }
            return true
        } catch {
            print("[SpotifyPrivateAPIManager] Error transferring playback: \(error.localizedDescription)")
            await MainActor.run {
                self.deviceTransferNotice = "Couldn’t switch device: \(error.localizedDescription)"
                self.scheduleDeviceTransferNoticeClear()
            }
            return false
        }
    }

    private func fetchApiTokensAndClientVersion() async throws {
        let scrape = await SpotifyOperationHashRegistry.shared.refreshHashesFromCDN(force: operationHashes.isEmpty)
        if let discovered = scrape?.hashes, !discovered.isEmpty {
            self.operationHashes = discovered
            self.jsPackURL = scrape?.jsPackURL
            self.clientVersion = scrape?.clientVersion
            await SpotifyOperationHashRegistry.shared.seed(
                discovered,
                clientVersion: self.clientVersion,
                jsPackURL: self.jsPackURL,
                replaceAll: true
            )
            print("[SpotifyPrivateAPIManager] Using \(discovered.count) live Pathfinder APQ hashes.")
        } else if operationHashes.isEmpty {
            guard let openSpotifyClient = openSpotifyClient else {
                throw SpotAPIError.missingData("Open Spotify client not initialized.")
            }
            let openSpotifyResponse = try await openSpotifyClient.get(path: "/")
            guard let openSpotifyHtml = String(data: openSpotifyResponse.body, encoding: .utf8) else {
                throw SpotAPIError.missingData("Could not parse open.spotify.com HTML.")
            }
            let jsPackPatterns = [
                #"https:\/\/open\.spotifycdn\.com\/cdn\/build\/web-player\/web-player\.[0-9a-f]+\.js"#,
                #"https:\/\/open-exp\.spotifycdn\.com\/cdn\/build\/web-player\/web-player\.[0-9a-f]+\.js"#
            ]
            for pattern in jsPackPatterns {
                if let range = openSpotifyHtml.range(of: pattern, options: .regularExpression) {
                    self.jsPackURL = String(openSpotifyHtml[range])
                    break
                }
            }
            if self.clientVersion == nil {
                self.clientVersion = await SpotifyOperationHashRegistry.shared.cachedClientVersion()
            }
            print("[SpotifyPrivateAPIManager] CDN hash scrape empty — will resolve ops lazily with fallbacks.")
        }

        if self.jsPackURL == nil, let cached = await SpotifyOperationHashRegistry.shared.cachedJsPackURL() {
            self.jsPackURL = cached
        }

        try await refreshAccessAndClientTokens(reason: "init")
    }

    private var inFlightTokenRefresh: Task<Bool, Never>?

    @discardableResult
    func refreshTokensIfNeeded(force: Bool = false) async -> Bool {
        let accessStale = force
            || accessToken == nil
            || accessTokenExpiresAt.map { Date().addingTimeInterval(60) >= $0 } ?? true
        let clientStale = force
            || clientToken == nil
            || clientTokenRefreshAt.map { Date() >= $0 } ?? true

        guard accessStale || clientStale else { return true }

        if let existing = inFlightTokenRefresh {
            return await existing.value
        }
        let task = Task { [weak self] () -> Bool in
            guard let self else { return false }
            do {
                try await self.refreshAccessAndClientTokens(reason: "transport")
                return true
            } catch {
                print("[SpotifyPrivateAPIManager] Token refresh failed (cookies kept): \(error.localizedDescription)")
                return false
            }
        }
        inFlightTokenRefresh = task
        let success = await task.value
        inFlightTokenRefresh = nil
        return success
    }

    private func refreshAccessAndClientTokens(reason: String) async throws {
        let accessTokenResponse = try await getAccessToken(reason: reason)
        guard let token = accessTokenResponse.accessToken, let clientID = accessTokenResponse.clientId else {
            throw SpotAPIError.missingData("Access token or client ID was nil in response.")
        }
        if accessTokenResponse.isAnonymous == true {
            throw SpotAPIError.authenticationFailed("Session verification failed. Anonymous token — cookies revoked.")
        }
        self.accessToken = token
        self.webPlayerClientID = clientID
        if let expiryMs = accessTokenResponse.accessTokenExpirationTimestampMs {
            self.accessTokenExpiresAt = Date(timeIntervalSince1970: Double(expiryMs) / 1000.0)
        } else {
            self.accessTokenExpiresAt = Date().addingTimeInterval(3600)
        }
        updateAllClientTokens()
        webSocketManager?.updateAccessToken(token)

        let clientTokenResponse = try await getClientToken(clientID: Self.webPlayerClientID)
        self.clientToken = clientTokenResponse.grantedToken.token
        let refreshAfter = TimeInterval(clientTokenResponse.grantedToken.refreshAfterSeconds)
        self.clientTokenRefreshAt = Date().addingTimeInterval(max(60, refreshAfter))
        updateAllClientTokens()
        scheduleTokenRefresh()
    }

    private func scheduleTokenRefresh() {
        cancelTokenRefreshSchedule()
        guard let accessExpiry = accessTokenExpiresAt else { return }
        let clientRefresh = clientTokenRefreshAt ?? accessExpiry
        let fireAt = min(accessExpiry.addingTimeInterval(-60), clientRefresh)
        let delay = max(30, fireAt.timeIntervalSinceNow)
        tokenRefreshTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self?.refreshTokensIfNeeded(force: true)
        }
    }

    private func cancelTokenRefreshSchedule() {
        tokenRefreshTask?.cancel()
        tokenRefreshTask = nil
    }

    private func getAccessToken(reason: String) async throws -> AccessTokenResponse {
        guard let openSpotifyClient = openSpotifyClient else {
            throw SpotAPIError.missingData("Open Spotify client not initialized.")
        }
        let candidates = await TotpGenerator.generateTotpCandidates()
        guard !candidates.isEmpty else {
            throw SpotAPIError.missingData("TOTP unavailable — could not generate codes.")
        }

        var lastError: Error?
        for (totp, totpVer) in candidates {
            var components = URLComponents()
            components.path = "/api/token"
            components.queryItems = [
                URLQueryItem(name: "reason", value: reason),
                URLQueryItem(name: "productType", value: "web-player"),
                URLQueryItem(name: "totp", value: totp),
                URLQueryItem(name: "totpVer", value: String(totpVer)),
                URLQueryItem(name: "totpServer", value: totp)
            ]
            do {
                let response = try await openSpotifyClient.get(
                    path: components.url!.relativeString,
                    authenticate: false
                )
                guard (200...299).contains(response.statusCode), !response.body.isEmpty else {
                    let snippet = String(data: response.body.prefix(120), encoding: .utf8) ?? "<empty>"
                    lastError = SpotAPIError.apiError("token HTTP \(response.statusCode): \(snippet)")
                    continue
                }
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                return try decoder.decode(AccessTokenResponse.self, from: response.body)
            } catch {
                lastError = error
            }
        }
        throw lastError ?? SpotAPIError.apiError("All TOTP token attempts failed.")
    }

    private func getClientToken(clientID: String) async throws -> ClientTokenResponse {
        guard let clientTokenClient = self.clientTokenClient else {
            throw SpotAPIError.missingData("ClientTokenClient not initialized.")
        }
        guard let deviceId = self.sessionDeviceID else {
            throw SpotAPIError.missingData("Session Device ID is missing for getClientToken.")
        }
        let path = "/v1/clienttoken"
        let body: [String: Any] = [
            "client_data": [
                "client_version": self.clientVersion ?? "1.2.98.87.g59eaf1b0-development",
                "client_id": clientID,
                "js_sdk_data": [
                    "device_brand": "Apple",
                    "device_model": "unknown",
                    "os": "macos",
                    "os_version": "10.15.7",
                    "device_id": deviceId,
                    "device_type": "computer"
                ]
            ]
        ]
        let headers: [String: String] = ["Accept": "application/json"]
        let response = try await clientTokenClient.post(path: path, jsonBody: body, additionalHeaders: headers, authenticate: false)
        guard (200...299).contains(response.statusCode), !response.body.isEmpty else {
            let snippet = String(data: response.body.prefix(200), encoding: .utf8)
                .flatMap { $0.isEmpty ? nil : $0 } ?? "<empty \(response.body.count) bytes>"
            throw SpotAPIError.apiError("clienttoken HTTP \(response.statusCode): \(snippet)")
        }
        let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(ClientTokenResponse.self, from: response.body)
    }

    private func performDeviceRegistration(connectionId: String) async throws {
        guard let spclient = spclientClient else { throw SpotAPIError.authenticationFailed("SPClient not ready.") }
        guard let controllerDeviceID = self.controllerDeviceID else { throw SpotAPIError.missingData("Controller Device ID is not set.") }

        let deletePath = "/track-playback/v1/devices/\(controllerDeviceID)"; do { _ = try await spclient.delete(path: deletePath) } catch { }

        let registerPayload: [String: Any] = [
            "device": [
                "brand": "spotify",
                "capabilities": [
                    "change_volume": true,
                    "enable_play_token": true,
                    "supports_file_media_type": true,
                    "play_token_lost_behavior": "pause",
                    "disable_connect": false,
                    "audio_podcasts": true,
                    "video_playback": true,
                    "supports_preferred_media_type": true,
                    "supports_playback_offsets": true,
                    "supports_playback_speed": true,
                    "manifest_formats": [
                        "file_ids_mp3", "file_urls_mp3", "manifest_urls_audio_ad",
                        "manifest_ids_video", "file_urls_external", "file_ids_mp4",
                        "file_ids_mp4_dual", "manifest_urls_audio_ad"
                    ]
                ],
                "device_id": controllerDeviceID,
                "device_type": "computer",
                "metadata": [:],
                "model": "web_player",
                "name": "Sapphire",
                "platform_identifier": "osx",
                "is_group": false,
                "is_public": false
            ],
            "connection_id": connectionId,
            "client_version": self.clientVersion ?? "harmony:4.43.2-a61ecaf5",
            "volume": 65535,
            "outro_endcontent_snooping": false
        ]
        let registerDevicePath = "/track-playback/v1/devices"
        _ = try await spclient.post(path: registerDevicePath, jsonBody: registerPayload)

        let connectDevicePath = "/connect-state/v1/devices/hobs_\(controllerDeviceID)"
        let connectPayload: [String: Any] = [
            "member_type": "CONNECT_STATE",
            "device": ["device_info": ["capabilities": Self.connectStateCapabilities()]]
        ]
        var connectHeaders = ["x-spotify-connection-id": connectionId]
        connectHeaders["Content-Type"] = "application/json"
        _ = try await spclient.put(path: connectDevicePath, jsonBody: connectPayload, additionalHeaders: connectHeaders)
        print("[SpotifyPrivateAPIManager] Registered hidden controller \(controllerDeviceID)")
    }

    private func fetchInitialPlayerState() async throws -> SpotifyNativePlayerStateResponse {
        guard let spclient = spclientClient, let controllerDeviceID = self.controllerDeviceID else { throw SpotAPIError.authenticationFailed("Cannot fetch initial state before controller is initialized.") }
        guard let connectionId = webSocketManager?.latestConnectionID else {
            throw SpotAPIError.missingData("WebSocket connection ID is not available for initial state fetch.")
        }
        let connectDevicePath = "/connect-state/v1/devices/hobs_\(controllerDeviceID)"
        let connectPayload: [String: Any] = [
            "member_type": "CONNECT_STATE",
            "device": ["device_info": ["capabilities": Self.connectStateCapabilities()]]
        ]
        var connectHeaders = ["x-spotify-connection-id": connectionId]
        connectHeaders["Content-Type"] = "application/json"
        let connectResponse = try await spclient.put(path: connectDevicePath, jsonBody: connectPayload, additionalHeaders: connectHeaders)
        if connectResponse.body.isEmpty {
            return SpotifyNativePlayerStateResponse(activeDeviceId: nil, playerState: PlayerState(), devices: [:])
        }
        return try SpotifyPrivateAPIManager.decodeResponseBody(connectResponse.body, for: "initial-connect-state") as SpotifyNativePlayerStateResponse
    }

    private static func connectStateCapabilities() -> [String: Any] {
        [
            "can_be_player": false,
            "hidden": true,
            "needs_full_player_state": true,
            "volume_steps": 64,
            "gaia_eq_connect_id": true,
            "supports_logout": true,
            "is_observable": true,
            "command_acks": true,
            "supports_rename": false,
            "supports_playlist_v2": true,
            "is_controllable": true,
            "supports_command_request": true,
            "supports_external_episodes": true,
            "supports_set_options_command": true,
            "supported_types": [] as [String]
        ]
    }

    private func performUserVerification() async {
        guard let client = wgSpclientClient else { return }
        let path = "/user-verification-service/v0/verifications/"
        let queryItems = [URLQueryItem(name: "market", value: "from_token")]
        let headers: [String: String] = [ "spotify-app-version": self.clientVersion ?? "1.2.74.57.g078ed0e9", "Accept": "application/json" ]
        do { _ = try await client.get(path: path, queryItems: queryItems, additionalHeaders: headers) } catch { print("[SpotifyPrivateAPIManager] Error during user verification: \(error.localizedDescription)") }
    }

    func logSortTelemetry() async {
        guard let spclient = spclientClient else { return }
        let event: [String: Any] = [
            "name": "hit_sort",
            "data": [
                "actionName": "sort",
                "actionVersion": 1,
                "app": "music",
                "interactionType": "hit",
                "specificationMode": "default"
            ]
        ]
        do {
            _ = try await spclient.post(
                path: "/gabo-receiver-service/v3/events",
                jsonBody: ["events": [event]]
            )
        } catch {
        }
    }

    private func sendGaboSessionEvent() async {
        guard let spclient = spclientClient else { return }
        let event = [ "name": "session_start", "data": [ "client_version": self.clientVersion ?? "harmony:4.43.2-a61ecaf5", "platform": "web_player" ] ] as [String : Any]
        let payload: [String: Any] = ["events": [event]]
        let path = "/gabo-receiver-service/v3/events"
        do { _ = try await spclient.post(path: path, jsonBody: payload) } catch { print("[SpotifyPrivateAPIManager] Error sending Gabo session event: \(error.localizedDescription)") }
    }

    func pythonCompatiblePlay(trackUri: String, contextUri: String, trackUid: String?, trackIndex: Int?, targetDeviceID: String) async throws {
        guard let fromDeviceID = self.controllerDeviceID, self.isLoggedIn else {
            throw SpotAPIError.authenticationFailed("Spotify private API is not logged in.")
        }
        guard let spclient = spclientClient else {
            throw SpotAPIError.authenticationFailed("SPClient not ready.")
        }
        let path = "/connect-state/v1/player/command/from/\(fromDeviceID)/to/\(targetDeviceID)"
        var optionsPayload: [String: Any] = [
            "license": "premium",
            "player_options_override": [:] as [String: Any]
        ]
        if !trackUri.isEmpty {
            var skipTo: [String: Any] = ["track_uri": trackUri]
            if let trackUid, !trackUid.isEmpty {
                skipTo["track_uid"] = trackUid
            }
            if let trackIndex {
                skipTo["track_index"] = trackIndex
            }
            optionsPayload["skip_to"] = skipTo
        }
        let commandPayload: [String: Any] = [
            "context": [
                "uri": contextUri,
                "url": "context://\(contextUri)",
                "metadata": [:] as [String: Any]
            ],
            "play_origin": [
                "feature_identifier": "harmony",
                "feature_version": "open-server_2025-09-20_1758397650501_078ed0e",
                "referrer_identifier": "deeplink"
            ],
            "options": optionsPayload,
            "logging_params": [
                "page_instance_ids": [UUID().uuidString],
                "interaction_ids": [UUID().uuidString],
                "command_id": generateRandomHexString(length: 32)
            ],
            "endpoint": "play"
        ]
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
        return playlistTrackUIDByNormalizedURI[normalizeSpotifyUri(trackUri)]
    }

    private func normalizeSpotifyUri(_ uri: String) -> String { if uri.starts(with: "spotify:track:") { return String(uri.dropFirst("spotify:track:".count)) }; if let url = URL(string: uri), url.host?.contains("spotify.com") == true { return url.lastPathComponent }; return uri }

    private func _setVolume(percent: Int) async throws { guard let from = self.controllerDeviceID, let to = self.activePlayerDeviceID, self.isLoggedIn else { throw SpotAPIError.authenticationFailed("Device IDs missing.") }; guard let spclient = spclientClient else { throw SpotAPIError.authenticationFailed("SPClient not ready.") }; let clampedPercent = max(0.0, min(1.0, Double(percent) / 100.0)); let sixteenBitRep = Int(clampedPercent * 65535); let path = "/connect-state/v1/connect/volume/from/\(from)/to/\(to)"; let payload: [String: Any] = ["volume": sixteenBitRep]; _ = try await spclient.put(path: path, jsonBody: payload) }

    private static let knownPathfinderHashes: [String: String] = [
        "fetchLibraryTracks": "087278b20b743578a6262c2b0b4bcd20d879c503cc359a2285baf083ef944240",
        "fetchPlaylist": "e4b2953f160e58e38ac025d79b5a9b3aceee5c4c716598e9830bfceb69faff5f",
        "fetchPlaylistContents": "e4b2953f160e58e38ac025d79b5a9b3aceee5c4c716598e9830bfceb69faff5f",
        "fetchPlaylistMetadata": "e4b2953f160e58e38ac025d79b5a9b3aceee5c4c716598e9830bfceb69faff5f",
        "decorateContextTracks": "383de00240775c39a6afe0b1055dc562b2a3930894201f9762f3fc32a74971c7",
        "getTrack": "1a2f0cce77c90a4a5b1730beecc4da7e34290d684324c16663bf09a268ebce48",
        "libraryV3": "390c78e5b951029bad359785e69b07b536a509c581cbcd0aded5e5067f187455",
        "areEntitiesInLibrary": "134337999233cc6fdd6b1e6dbf94841409f04a946c5c7b744b09ba0dfe5a85ed",
        "canvas": "575138ab27cd5c1b3e54da54d0a7cc8d85485402de26340c2145f0f6bb5e7a9f",
        "playlistPermissions": "e43d1d35f231cf289c23c9d9c489f4a4f502e4eda09839c530608f107b6556b8",
        "smartShuffle": "3384085be84fbf2f855b024f99bc06cded1c0fd71af3a8fb8abb84e9656faba2",
        "fetchEntitiesForRecentlyPlayed": "cf5d2e94ffd82788470788ae1f6090cc3e9e774fb8fd383580634c6e6f50f7be",
        "accountAttributes": "24aaa3057b69fa91492de26841ad199bd0b330ca95817b7a4d6715150de01827",
        "queryNpvArtist": "b2cedf7ed0f29c713567d97ed69b848c8387294edfe58a0e439a3a5669cc27bb",
        "queryArtistOverview": "ae0e2958a4ab645b35ca19ac04d0495ae12d9c5d7b7286217674801a9aab281a",
        "queryTrackArtists": "ee2b038198f5e62c679c3996584d9249bbee55fe69fc212271c56492a022c798",
        "lookupChildEntities": "91ce02e32b19123de231dc8de91fe4b9ab84eca087d4c015549308d77fbb6d10",
        "isCurated": "e4ed1f91a2cc5415befedb85acf8671dc1a4bf3ca1a5b945a6386101a22e28a6",
        "internalLinkRecommenderTrack": "c77098ee9d6ee8ad3eb844938722db60570d040b49f41f5ec6e7be9160a7c86b",
        "similarAlbumsBasedOnThisTrack": "1d1f93a737498adca2c892c73af87fc0b052afe4e1a33c989540c32413dfae17",
        "ArtistConcerts": "ef53c43b865496b9890b7167eab1dc614a8949ef9451b3c41184ea888de8bd2b",
        "ArtistConcertsPageLocation": "320698465a352f0d0247ec8ed02471244106d4199820f99de4d0a785561c2b03",
        "userLocation": "079939378ca79b67c6d047be9152ea940d21f10bbfa2f5d4cf4d8320d87774c2",
        "searchDesktop": "db61238974d27839a136c9dc02bfdbe3fab7635f21cf85976ebff9a1ee281345",
        "addToLibrary": "1ad0d40b3c09660d818b9e770eb1e84745dfbe941df159a64f8772b6fa2bfc3a",
        "removeFromLibrary": "1ad0d40b3c09660d818b9e770eb1e84745dfbe941df159a64f8772b6fa2bfc3a",
        "queryAlbumTracks": "b9bfabef66ed756e5e13f68a942deb60bd4125ec1f1be8cc42769dc0259b4b10",
        "editablePlaylists": "d5c4b8096437dcc2ac9528c91dfcd299e35b747cda2f8f75d28f41f49c5092ba",
        "applyCurations": "05b739a3a73091c213385233b9d3ed8a857c2ca29d2eebadb3d04ed12e288697",
        "centralisedStatePlayerOptions": "e2dcfcab470854d4d1c7cb1a851438f14fe0a94d57db7f0b9dde492559d5395d",
        "feedBaselineLookup": "a950fb7c4ecdcaf2aad2f3ca9ee9c3aa4b9c43c97e1d07d05148c4d355bea7fc"
    ]

    internal func pathfinderQuery<T: Decodable>(
        operationName: String,
        variables: [String: Any],
        extensions: [String: Any]? = nil,
        sendAsBody: Bool = true,
        cachePolicy: CachePolicy = .returnCacheDataElseFetch,
        useV2Endpoint: Bool = true
    ) async throws -> T {
        try await pathfinderQueryInternal(
            operationName: operationName,
            variables: variables,
            extensions: extensions,
            sendAsBody: sendAsBody,
            cachePolicy: cachePolicy,
            useV2Endpoint: useV2Endpoint,
            allowHashRefreshRetry: true
        )
    }

    private func pathfinderQueryInternal<T: Decodable>(
        operationName: String,
        variables: [String: Any],
        extensions: [String: Any]?,
        sendAsBody: Bool,
        cachePolicy: CachePolicy,
        useV2Endpoint: Bool,
        allowHashRefreshRetry: Bool,
        allowAuthRetry: Bool = true
    ) async throws -> T {
        guard let apiPartnerClient = apiPartnerClient, isLoggedIn else {
            throw SpotAPIError.authenticationFailed("Not logged in.")
        }

        guard await refreshTokensIfNeeded(force: false) else {
            throw SpotAPIError.authenticationFailed("Access token refresh failed; refusing authenticated Pathfinder request.")
        }

        let variablesData = try? JSONSerialization.data(withJSONObject: variables, options: .sortedKeys)
        let variablesString = variablesData?.base64EncodedString() ?? ""
        let cacheKey = "\(operationName)_\(variablesString)"

        if cachePolicy == .returnCacheDataElseFetch || cachePolicy == .fetchAndReturnCacheData {
            if let cachedEntry = await apiCache.get(forKey: cacheKey) {
                let cachedData = cachedEntry.data
                return try await Task.detached(priority: .utility) {
                    try Self.decodePathfinderResponse(cachedData, for: operationName)
                }.value
            }
        }

        let suppliedHash = (extensions?["persistedQuery"] as? [String: Any])?["sha256Hash"] as? String
        let hardcoded = Self.knownPathfinderHashes[operationName]
        let localLive = operationHashes[operationName]
        let resolvedHash: String?
        if let suppliedHash {
            resolvedHash = suppliedHash
        } else {
            resolvedHash = await SpotifyOperationHashRegistry.shared.getHash(
                for: operationName,
                fallback: localLive ?? hardcoded,
                forceRefresh: false,
                allowFallback: true
            )
        }
        guard let sha256Hash = resolvedHash else {
            throw SpotAPIError.missingData("SHA256 hash for operation '\(operationName)' not found.")
        }
        operationHashes[operationName] = sha256Hash

        let finalExtensions = extensions ?? ["persistedQuery": ["version": 1, "sha256Hash": sha256Hash]]

        let response: HTTPResponse
        let path = useV2Endpoint ? "/pathfinder/v2/query" : "/pathfinder/v1/query"

        if sendAsBody {
            let payload: [String: Any] = [
                "operationName": operationName,
                "variables": variables,
                "extensions": finalExtensions
            ]
            response = try await apiPartnerClient.post(path: path, jsonBody: payload)
        } else {
            var components = URLComponents(); components.path = path
            guard let variablesJSONData = try? JSONSerialization.data(withJSONObject: variables),
                  let extensionsJSONData = try? JSONSerialization.data(withJSONObject: finalExtensions),
                  let variablesJSONString = String(data: variablesJSONData, encoding: .utf8),
                  let extensionsJSONString = String(data: extensionsJSONData, encoding: .utf8) else {
                throw SpotAPIError.urlConstructionFailed("Could not serialize pathfinder variables/extensions to JSON string.")
            }
            components.queryItems = [
                URLQueryItem(name: "operationName", value: operationName),
                URLQueryItem(name: "variables", value: variablesJSONString),
                URLQueryItem(name: "extensions", value: extensionsJSONString)
            ]
            guard let pathWithParams = components.url?.relativeString else {
                throw SpotAPIError.urlConstructionFailed("Could not create path with query parameters.")
            }
            response = try await apiPartnerClient.get(path: pathWithParams)
        }

        if allowAuthRetry, response.statusCode == 401 || response.statusCode == 403 {
            print("[SpotifyPrivateAPIManager] Pathfinder \(operationName) HTTP \(response.statusCode) — refreshing tokens.")
            guard await refreshTokensIfNeeded(force: true) else {
                throw SpotAPIError.authenticationFailed("Access token refresh failed after Pathfinder HTTP \(response.statusCode).")
            }
            return try await pathfinderQueryInternal(
                operationName: operationName,
                variables: variables,
                extensions: nil,
                sendAsBody: sendAsBody,
                cachePolicy: .fetchIgnoringCacheData,
                useV2Endpoint: useV2Endpoint,
                allowHashRefreshRetry: allowHashRefreshRetry,
                allowAuthRetry: false
            )
        }

        let wrongShape = allowHashRefreshRetry && !Self.responseMatchesOperation(response.body, operationName: operationName)
        let apqMiss = allowHashRefreshRetry && Self.isPersistedQueryHashError(response: response)

        if wrongShape || apqMiss {
            print("[SpotifyPrivateAPIManager] APQ mismatch for \(operationName) (wrongShape=\(wrongShape)) — dropping hash and re-scraping.")
            operationHashes.removeValue(forKey: operationName)
            await SpotifyOperationHashRegistry.shared.invalidate(operation: operationName)
            await SpotifyOperationHashRegistry.shared.invalidate()
            if let scrape = await SpotifyOperationHashRegistry.shared.refreshHashesFromCDN(force: true) {
                operationHashes.merge(scrape.hashes) { _, live in live }
                if let version = scrape.clientVersion { self.clientVersion = version }
                await SpotifyOperationHashRegistry.shared.seed(
                    scrape.hashes,
                    clientVersion: scrape.clientVersion,
                    jsPackURL: scrape.jsPackURL
                )
            }
            if let live = await SpotifyOperationHashRegistry.shared.getHash(
                for: operationName,
                fallback: nil,
                forceRefresh: false,
                allowFallback: false
            ) {
                operationHashes[operationName] = live
                return try await pathfinderQueryInternal(
                    operationName: operationName,
                    variables: variables,
                    extensions: ["persistedQuery": ["version": 1, "sha256Hash": live]],
                    sendAsBody: sendAsBody,
                    cachePolicy: .fetchIgnoringCacheData,
                    useV2Endpoint: useV2Endpoint,
                    allowHashRefreshRetry: false,
                    allowAuthRetry: allowAuthRetry
                )
            }
        }

        if (200...299).contains(response.statusCode) && !response.body.isEmpty {
            let bodyToCache = response.body
            Task(priority: .utility) { await self.apiCache.set(bodyToCache, forKey: cacheKey) }
        }
        let responseBody = response.body
        do {
            return try await Task.detached(priority: .utility) {
                try Self.decodePathfinderResponse(responseBody, for: operationName)
            }.value
        } catch SpotAPIError.authenticationFailed(_) where allowAuthRetry {
            print("[SpotifyPrivateAPIManager] Pathfinder \(operationName) auth error — refreshing tokens and retrying once.")
            guard await refreshTokensIfNeeded(force: true) else {
                throw SpotAPIError.authenticationFailed("Access token refresh failed after Pathfinder authentication error.")
            }
            return try await pathfinderQueryInternal(
                operationName: operationName,
                variables: variables,
                extensions: nil,
                sendAsBody: sendAsBody,
                cachePolicy: .fetchIgnoringCacheData,
                useV2Endpoint: useV2Endpoint,
                allowHashRefreshRetry: false,
                allowAuthRetry: false
            )
        } catch {
            guard allowHashRefreshRetry else { throw error }
            print("[SpotifyPrivateAPIManager] Decode failed for \(operationName) — treating as APQ drift and retrying once.")
            operationHashes.removeValue(forKey: operationName)
            await SpotifyOperationHashRegistry.shared.invalidate(operation: operationName)
            await SpotifyOperationHashRegistry.shared.invalidate()
            _ = await SpotifyOperationHashRegistry.shared.refreshHashesFromCDN(force: true)
            return try await pathfinderQueryInternal(
                operationName: operationName,
                variables: variables,
                extensions: nil,
                sendAsBody: sendAsBody,
                cachePolicy: .fetchIgnoringCacheData,
                useV2Endpoint: useV2Endpoint,
                allowHashRefreshRetry: false,
                allowAuthRetry: allowAuthRetry
            )
        }
    }

    private nonisolated static func responseMatchesOperation(_ data: Data, operationName: String) -> Bool {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return true
        }
        if json["errors"] != nil, json["data"] == nil { return true }
        guard let dataNode = json["data"] as? [String: Any] else {
            return true
        }

        switch operationName {
        case "profileAttributes":
            return (dataNode["me"] as? [String: Any])?["profile"] != nil
        case "accountAttributes":
            return (dataNode["me"] as? [String: Any])?["account"] != nil
        case "fetchExtractedColors":
            return dataNode["extractedColors"] != nil
        case "getDynamicColorsByUris", "getDynamicColors":
            return dataNode["dynamicColors"] != nil || dataNode["extractedColors"] != nil
        case "home":
            return dataNode["home"] != nil
        case "getTrack":
            return dataNode["trackUnion"] != nil
        case "decorateContextTracks":
            return dataNode["tracks"] != nil
        case "searchDesktop":
            return dataNode["searchV2"] != nil
        case "libraryV3":
            return (dataNode["me"] as? [String: Any])?["libraryV3"] != nil
        case "canvas":
            return dataNode["canvas"] != nil || dataNode["canvasForTracks"] != nil || !dataNode.isEmpty
        default:
            return true
        }
    }

    private nonisolated static func isPersistedQueryHashError(response: HTTPResponse) -> Bool {
        guard let body = String(data: response.body.prefix(2_000), encoding: .utf8)?.lowercased() else {
            return false
        }
        return body.contains("persistedquery")
            || body.contains("persisted query")
            || body.contains("persistedquerynotfound")
    }

    private nonisolated static func decodePathfinderResponse<T: Decodable>(_ data: Data, for operationName: String) throws -> T {
        try decodeResponseBody(data, for: operationName)
    }

    private nonisolated static func decodeResponseBody<T: Decodable>(_ data: Data, for operationName: String) throws -> T {
        if let apiError = try? JSONDecoder().decode(SpotifyPathfinderErrorEnvelope.self, from: data),
           let error = apiError.error {
            let message = error.message ?? "Spotify API error"
            if error.status == 401 {
                throw SpotAPIError.authenticationFailed(message)
            }
            throw SpotAPIError.missingData(message)
        }

        do {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            return try decoder.decode(T.self, from: data)
        } catch {
            let snippet = String(data: data.prefix(400), encoding: .utf8) ?? "<non-utf8 \(data.count) bytes>"
            print("[SpotifyPrivateAPIManager] Decode failed for \(operationName): \(error)\nBody snippet: \(snippet)")
            throw SpotAPIError.decodingError(error)
        }
    }

    func skipNext() async throws {
        guard let from = self.controllerDeviceID, let to = self.activePlayerDeviceID, self.isLoggedIn, let spclient = spclientClient else { return }
        let path = "/connect-state/v1/player/command/from/\(from)/to/\(to)"
        let payload: [String: Any] = ["command": ["endpoint": "skip_next"]]
        _ = try await spclient.post(path: path, jsonBody: payload)
    }

    private var playerStateRefreshTask: Task<Void, Error>?

    func refreshPlayerAndDeviceState() async throws {
        if let existing = playerStateRefreshTask {
            try await existing.value
            return
        }
        let task = Task { [weak self] in
            guard let self else { throw SpotAPIError.authenticationFailed("Spotify manager deallocated.") }
            defer { self.playerStateRefreshTask = nil }
            try await self.performPlayerAndDeviceStateRefresh()
        }
        playerStateRefreshTask = task
        try await task.value
    }

    private func performPlayerAndDeviceStateRefresh() async throws {
        if let cluster = await fetchConnectCluster() {
            applyPlayerStateIfNeeded(cluster.playerState)
            devices = Array(cluster.devices.values)
            activePlayerDeviceID = cluster.activeDeviceId
            if cluster.activeDeviceId == controllerDeviceID {
                isConnectStreamingSession = false
            }
            return
        }

        guard let spclient = spclientClient, let controllerDeviceID = self.controllerDeviceID else { throw SpotAPIError.authenticationFailed("SPClient not ready or controllerDeviceID is missing.") }
        guard let connectionId = webSocketManager?.latestConnectionID else {
            throw SpotAPIError.missingData("WebSocket connection ID is not available for player state refresh.")
        }
        let connectDevicePath = "/connect-state/v1/devices/hobs_\(controllerDeviceID)"
        let connectPayload: [String: Any] = [
            "member_type": "CONNECT_STATE",
            "device": ["device_info": ["capabilities": Self.connectStateCapabilities()]]
        ]
        var connectHeaders = ["x-spotify-connection-id": connectionId]; connectHeaders["Content-Type"] = "application/json"
        let connectResponse = try await spclient.put(path: connectDevicePath, jsonBody: connectPayload, additionalHeaders: connectHeaders)
        if connectResponse.body.isEmpty {
            print("[SpotifyPrivateAPIManager] Empty connect-state body on refresh; keeping existing player state.")
            return
        }
        do {
            let responseBody = connectResponse.body
            let playerStateResponse = try await Task.detached(priority: .utility) {
                try SpotifyPrivateAPIManager.decodeResponseBody(responseBody, for: "connect-state") as SpotifyNativePlayerStateResponse
            }.value
            self.applyPlayerStateIfNeeded(playerStateResponse.playerState)
            self.devices = Array(playerStateResponse.devices.values)
            self.activePlayerDeviceID = playerStateResponse.activeDeviceId
        } catch let error {
            print("[SpotifyPrivateAPIManager] Error refreshing player state (session kept): \(error.localizedDescription)")
            throw error
        }
    }

    func fetchConnectCluster() async -> SpotifyNativePlayerStateResponse? {
        guard let spclient = spclientClient, isLoggedIn else { return nil }
        do {
            var headers: [String: String] = [:]
            if let connectionId = webSocketManager?.latestConnectionID {
                headers["x-spotify-connection-id"] = connectionId
            }
            let response = try await spclient.get(
                path: "/connect-state/v1/cluster",
                additionalHeaders: headers.isEmpty ? nil : headers
            )
            guard !response.body.isEmpty else { return nil }
            let responseBody = response.body
            return try await Task.detached(priority: .utility) {
                try SpotifyPrivateAPIManager.decodeResponseBody(responseBody, for: "connect-state-cluster") as SpotifyNativePlayerStateResponse
            }.value
        } catch {
            print("[SpotifyPrivateAPIManager] GET cluster unavailable: \(error.localizedDescription)")
            return nil
        }
    }

    private func fetchLibrary(order: String? = nil) async throws -> UserLibraryResponse.Library {
        var variables: [String: Any] = [
            "textFilter": "",
            "features": ["LIKED_SONGS", "YOUR_EPISODES_V2", "PRERELEASES", "PRERELEASES_V2", "CLIPS", "EVENTS"],
            "limit": 50,
            "offset": 0,
            "flatten": false,
            "expandedFolders": [] as [String],
            "folderUri": NSNull(),
            "includeFoldersWhenFlattening": true
        ]
        if let order, !order.isEmpty {
            variables["order"] = order
        } else {
            variables["order"] = NSNull()
        }
        let response: UserLibraryResponse = try await pathfinderQuery(
            operationName: "libraryV3",
            variables: variables,
            sendAsBody: true,
            useV2Endpoint: true
        )
        guard let library = response.data?.me?.libraryV3 else {
            throw SpotAPIError.missingData("Library data was missing in the response.")
        }
        return library
    }
    private func verifySessionAndFetchUserInfo() async throws {
        guard let wwwSpotifyClient = self.wwwSpotifyClient else {
            throw SpotAPIError.authenticationFailed("wwwSpotifyClient not initialized for verification.")
        }

        let cookies = await cookieManager.allCookies()
        guard cookies["sp_dc"] != nil, cookies["sp_key"] != nil else {
            throw SpotAPIError.authenticationFailed("Session verification failed. Missing sp_dc/sp_key cookies.")
        }

        let response = try await wwwSpotifyClient.get(
            path: "/api/account-settings/v1/profile",
            authenticate: false
        )
        if response.statusCode == 401 || response.statusCode == 403 {
            throw SpotAPIError.authenticationFailed("Session verification failed. Could not fetch user profile.")
        }
        guard response.statusCode == 200, !response.body.isEmpty else {
            let snippet = String(data: response.body.prefix(160), encoding: .utf8) ?? "<empty>"
            print("[SpotifyPrivateAPIManager] Profile verify HTTP \(response.statusCode): \(snippet)")
            throw SpotAPIError.apiError("Profile verify HTTP \(response.statusCode) — keeping cookies.")
        }
        do {
            let userProfileResponse = try SpotifyPrivateAPIManager.decodeResponseBody(response.body, for: "user-profile") as SpotifyNativeUserProfile
            self.userProfile = userProfileResponse
        } catch {
            print("[SpotifyPrivateAPIManager] Error verifying session/fetching user info: \(error.localizedDescription)")
            throw error
        }
    }
    private func getPartHash(operationName: String) throws -> String { guard let hash = self.operationHashes[operationName] else { throw SpotAPIError.missingData("SHA256 hash for operation '\(operationName)' not found.") }; return hash }
    private func updateAllClientTokens() { let clients: [String: CustomTLSClient?] = [ "openSpotifyClient": openSpotifyClient, "spclientClient": spclientClient, "apiPartnerClient": apiPartnerClient, "clientTokenClient": clientTokenClient, "wwwSpotifyClient": wwwSpotifyClient, "wgSpclientClient": wgSpclientClient ]; for (_, client) in clients { client?.accessToken = self.accessToken; client?.clientToken = self.clientToken; client?.clientVersion = self.clientVersion }; }
    internal func generateRandomHexString(length: Int) -> String { let characters = Array("0123456789abcdef"); var result = ""; for _ in 0..<length { result.append(characters.randomElement()!) }; return result }
    private struct EmptyResponse: Decodable {}

    private func resetLoadedPlaylistState() {
        selectedPlaylist = nil
        playlistTrackViewModels = []
        playlistTrackIndexByUID = [:]
        playlistTrackUIDByNormalizedURI = [:]
        playlistNextOffset = 0
        playlistHasMore = false
        playlistTotalCount = 0
        playlistLoadedURI = nil
    }

    private func registerPlaylistItems(_ items: [SpotifyPlaylistDetailsResponse.PlaylistItem], startingAt startIndex: Int) -> [TrackViewModel] {
        var viewModels: [TrackViewModel] = []
        viewModels.reserveCapacity(items.count)

        for (offset, item) in items.enumerated() {
            let absoluteIndex = startIndex + offset
            let uid = item.uid
            playlistTrackIndexByUID[uid] = absoluteIndex

            let normalizedURI = normalizeSpotifyUri(item.itemV2.data.uri ?? "")
            if !normalizedURI.isEmpty {
                playlistTrackUIDByNormalizedURI[normalizedURI] = uid
            }

            viewModels.append(TrackViewModel(playlistItem: item))
        }

        return viewModels
    }

    private func hydrateNowPlayingIfNeeded(for state: PlayerState) async {
        guard let sparseTrack = state.track, sparseTrack.metadata?.artistName == nil, !sparseTrack.uri.isEmpty else {
            nowPlayingHydrationTrackURI = nil
            return
        }

        guard nowPlayingHydrationTrackURI != sparseTrack.uri else { return }
        nowPlayingHydrationTrackURI = sparseTrack.uri

        let expectedTrackURI = sparseTrack.uri
        if let trackUnion = await fetchTrackMetadataResilient(trackID: sparseTrack.uri) {
            var hydratedState = state
            let hydratedTrack = PlayerState.Track(hydrating: sparseTrack, withDetails: trackUnion)

            guard self.playerState?.track?.uri == expectedTrackURI else { return }
            hydratedState.track = hydratedTrack
            self.applyPlayerStateIfNeeded(hydratedState)
            self.nowPlayingHydrationTrackURI = nil
        } else {
            nowPlayingHydrationTrackURI = nil
            print("[SpotifyPrivateAPIManager] Error hydrating now playing track via resilient metadata.")
        }
    }

    private func hydrateQueue(from playerState: PlayerState) {
        let sparseQueue = playerState.nextTracks?.filter {
            !($0.uri.contains("spotify:delimiter") || ($0.metadata?.hidden == "true"))
        } ?? []
        let expectedQueueIDs = sparseQueue.map(\.uid)
        let currentQueueIDs = nativeQueue.map(\.uid)

        let needsMetadata = sparseQueue.contains {
            ($0.metadata?.title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
                || $0.metadata?.artistName == nil
        }

        if expectedQueueIDs == currentQueueIDs,
           !expectedQueueIDs.isEmpty,
           !needsMetadata,
           !nativeQueue.contains(where: {
               ($0.metadata?.title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
                   && $0.metadata?.artistName == nil
           }) {
            return
        }

        if expectedQueueIDs == lastQueueHydrationIDs,
           currentQueueIDs == expectedQueueIDs,
           queueHydrationTask != nil,
           !needsMetadata {
            return
        }

        queueHydrationTask?.cancel()
        lastQueueHydrationIDs = expectedQueueIDs

        if currentQueueIDs != expectedQueueIDs || nativeQueue.isEmpty {
            nativeQueue = sparseQueue
        }

        queueHydrationTask = Task(priority: .utility) {
            defer { self.queueHydrationTask = nil }
            await self.hydrateQueueMetadataProgressively(
                sparseQueue: sparseQueue,
                expectedQueueIDs: expectedQueueIDs
            )
        }
    }

    private func hydrateQueueMetadataProgressively(
        sparseQueue: [PlayerState.Track],
        expectedQueueIDs: [String]
    ) async {
        var finalQueue = sparseQueue
        let batchSize = 20
        var start = 0

        while start < finalQueue.count {
            if Task.isCancelled { return }

            let end = min(start + batchSize, finalQueue.count)
            let indicesNeedingHydration = (start..<end).filter { index in
                let track = finalQueue[index]
                let title = track.metadata?.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return title.isEmpty || track.metadata?.artistName == nil
            }

            if !indicesNeedingHydration.isEmpty {
                let batch = indicesNeedingHydration.map { finalQueue[$0] }
                let hydratedBatch = await hydrateTracksBatch(batch)
                for (offset, hydratedTrack) in hydratedBatch.enumerated() {
                    let index = indicesNeedingHydration[offset]
                    if index < finalQueue.count {
                        finalQueue[index] = hydratedTrack
                    }
                }

                if !Task.isCancelled {
                    let liveQueueIDs = self.playerState?.nextTracks?
                        .filter { !($0.uri.contains("spotify:delimiter") || ($0.metadata?.hidden == "true")) }
                        .map(\.uid) ?? []
                    guard liveQueueIDs == expectedQueueIDs else { return }
                    self.nativeQueue = finalQueue
                }
            }

            start = end
        }
    }

    func hydrateQueueItemIfNeeded(uid: String) async {
        guard let index = nativeQueue.firstIndex(where: { $0.uid == uid }) else { return }
        let track = nativeQueue[index]
        let title = track.metadata?.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard title.isEmpty || track.metadata?.artistName == nil else { return }

        let lo = max(0, index - 2)
        let hi = min(nativeQueue.count, index + 8)
        let sliceIndices = Array(lo..<hi)
        let sparse = sliceIndices.map { nativeQueue[$0] }
        let hydrated = await hydrateTracksBatch(sparse)
        await MainActor.run {
            var updated = self.nativeQueue
            for (offset, track) in hydrated.enumerated() {
                let i = sliceIndices[offset]
                guard i < updated.count, updated[i].uid == track.uid else { continue }
                updated[i] = track
            }
            self.nativeQueue = updated
        }
    }

    func refreshQueueForUI() async {
        if let existing = queueRefreshTask {
            await existing.value
            return
        }

        queueRefreshTask = Task(priority: .userInitiated) {
            defer { self.queueRefreshTask = nil }

            await MainActor.run {
                self.lastQueueHydrationIDs = []
            }

            let hasSparseQueue = self.playerState?.nextTracks?.contains(where: {
                !$0.uri.contains("spotify:delimiter") && $0.metadata?.hidden != "true"
            }) == true
            let wsIsLive = self.webSocketManager?.hasActiveConnection == true

            if !hasSparseQueue || !wsIsLive {
                do {
                    try await self.refreshPlayerAndDeviceState()
                } catch {
                    print("[SpotifyPrivateAPIManager] refreshQueueForUI cluster failed: \(error.localizedDescription)")
                }
            }

            await MainActor.run {
                if let state = self.playerState {
                    self.lastQueueHydrationIDs = []
                    self.hydrateQueue(from: state)
                }
            }
        }

        await queueRefreshTask?.value
    }

    private func applyPlayerStateIfNeeded(_ playerState: PlayerState) {
        let signature = PrivatePlayerStateSignature(playerState)
        guard signature != lastPlayerStateSignature else { return }
        lastPlayerStateSignature = signature
        self.playerState = playerState
    }

    private var lastLocalActivationKey: String?
    private var lastLocalActivationAt: Date = .distantPast

    private func handleLocalPlayerActivationIfNeeded(playerState: PlayerState) {
        guard let selfId = controllerDeviceID else { return }

        let activeId = activePlayerDeviceID
        let isSelfActive = activeId == selfId
            || (activeId?.hasSuffix(selfId) == true)
            || (activeId != nil && selfId.hasSuffix(activeId!))

        guard isSelfActive,
              let trackURI = playerState.track?.uri,
              !trackURI.isEmpty,
              !trackURI.hasPrefix("spotify:ad:")
        else {
            return
        }

        if playerState.isPaused == true { return }

        let activationKey = "\(selfId)|\(trackURI)|bounce"
        let now = Date()
        if activationKey == lastLocalActivationKey, now.timeIntervalSince(lastLocalActivationAt) < 2.5 {
            return
        }
        lastLocalActivationKey = activationKey
        lastLocalActivationAt = now

        Task {
            guard let external = preferredExternalPlaybackDeviceID(excluding: selfId) else {
                await MainActor.run {
                    self.deviceTransferNotice = "Open the Spotify app or another speaker to play audio."
                    self.scheduleDeviceTransferNoticeClear()
                }
                return
            }
            do {
                try await transferDevice(from: selfId, to: external)
                await MainActor.run {
                    self.isConnectStreamingSession = true
                    self.deviceTransferNotice =
                        "Playback moved to \(self.devices.first(where: { $0.deviceId == external })?.name ?? "your speaker")."
                    self.scheduleDeviceTransferNoticeClear()
                }
            } catch {
                print("[SpotifyPrivateAPIManager] Bounce to external speaker failed: \(error.localizedDescription)")
            }
        }
    }

    func checkAndReconnectIfNeeded() {
        guard loginChallenge == nil, webSocketManager?.isConnecting != true else {
            return
        }
        if isLoggedIn {
            if webSocketManager?.hasActiveConnection == true { return }
            print("[SpotifyPrivateAPIManager] Logged in but dealer disconnected after wake — re-establishing.")
            reestablishSession()
            return
        }

        print("[SpotifyPrivateAPIManager] Proactively checking connection and re-establishing session after wake/network change.")
        bootstrapIfNeeded(policy: .reconnect)
    }
}

private struct PrivatePlayerStateSignature: Equatable {
    let trackURI: String?
    let trackUID: String?
    let trackTitle: String?
    let trackArtist: String?
    let trackAlbum: String?
    let trackImage: String?
    let hiddenFlag: String?
    let isPlaying: Bool?
    let isPaused: Bool?
    let contextURI: String?
    let shuffle: Bool?
    let repeatingContext: Bool?
    let repeatingTrack: Bool?
    let previousTrackUIDs: [String]
    let nextTrackUIDs: [String]
    let positionBucket: Int?

    init(_ state: PlayerState) {
        trackURI = state.track?.uri
        trackUID = state.track?.uid
        trackTitle = state.track?.metadata?.title
        trackArtist = state.track?.metadata?.artistName
        trackAlbum = state.track?.metadata?.albumTitle
        trackImage = state.track?.metadata?.imageUrl ?? state.track?.metadata?.imageLargeUrl ?? state.track?.metadata?.imageSmallUrl ?? state.track?.metadata?.imageXlargeUrl
        hiddenFlag = state.track?.metadata?.hidden
        isPlaying = state.isPlaying
        isPaused = state.isPaused
        contextURI = state.contextUri
        shuffle = state.options?.shufflingContext
        repeatingContext = state.options?.repeatingContext
        repeatingTrack = state.options?.repeatingTrack
        previousTrackUIDs = state.prevTracks?.map(\.uid) ?? []
        nextTrackUIDs = state.nextTracks?.map(\.uid) ?? []
        if let ms = state.positionAsOfTimestamp {
            positionBucket = ms / 2000
        } else {
            positionBucket = nil
        }
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

private struct SpotifyPathfinderErrorEnvelope: Decodable {
    struct ErrorBody: Decodable {
        let status: Int?
        let message: String?
    }
    let error: ErrorBody?
}

extension SpotifyTrack {
    init(from nativeTrack: NativeTrackData) {
        self.id = nativeTrack.uri.components(separatedBy: ":").last ?? ""
        self.name = nativeTrack.name ?? "Unknown Track"
        self.uri = nativeTrack.uri
        self.album = SpotifyAlbum(
            name: nativeTrack.albumOfTrack?.name ?? "Unknown Album",
            images: nativeTrack.albumOfTrack?.coverArt.sources.map { SpotifyImage(url: $0.url) } ?? []
        )
        self.artists = nativeTrack.artists?.items.map { SpotifyArtist(name: $0.profile.name) } ?? [SpotifyArtist(name: "Unknown Artist")]
        self.durationMs = nativeTrack.duration?.totalMilliseconds ?? 0
        self.popularity = nil
    }
}

// MARK: - Consolidated from SpotifyConnectCommands.swift

struct SpotifyColorLyrics: Decodable {
    let lyrics: LyricsBlock?

    struct LyricsBlock: Decodable {
        let syncType: String?
        let lines: [Line]

        struct Line: Decodable {
            let startTimeMs: String
            let words: String
            let endTimeMs: String?

            enum CodingKeys: String, CodingKey {
                case startTimeMs, words, endTimeMs
            }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                if let stringValue = try? container.decode(String.self, forKey: .startTimeMs) {
                    startTimeMs = stringValue
                } else if let intValue = try? container.decode(Int.self, forKey: .startTimeMs) {
                    startTimeMs = String(intValue)
                } else if let doubleValue = try? container.decode(Double.self, forKey: .startTimeMs) {
                    startTimeMs = String(Int(doubleValue))
                } else {
                    startTimeMs = "0"
                }
                words = try container.decodeIfPresent(String.self, forKey: .words) ?? ""
                if let endString = try? container.decode(String.self, forKey: .endTimeMs) {
                    endTimeMs = endString
                } else if let endInt = try? container.decode(Int.self, forKey: .endTimeMs) {
                    endTimeMs = String(endInt)
                } else {
                    endTimeMs = nil
                }
            }
        }
    }
}

struct SpotifyClipTranscript: Decodable {
    let words: [TranscriptWord]?
    let speakers: [TranscriptSpeaker]?

    struct TranscriptWord: Decodable {
        let text: String?
        let startTimeMs: Int?
        let endTimeMs: Int?
    }

    struct TranscriptSpeaker: Decodable {
        let id: String?
        let name: String?
    }
}

struct SpotifyJamSession: Decodable {
    let session: SessionInfo?

    struct SessionInfo: Decodable {
        let id: String?
        let isActive: Bool?
    }
}

struct SpotifyPopularRelease: Identifiable, Hashable {
    let id: String
    let name: String
    let uri: String
    let imageURL: URL?
}

extension SpotifyPrivateAPIManager {

    // MARK: Connect Playback

    @discardableResult
    func connectPlay(
        trackUri: String,
        contextUri: String?,
        trackUid: String? = nil,
        trackIndex: Int? = nil
    ) async -> PlaybackResult {
        guard isLoggedIn, let deviceId = controllerDeviceID else {
            return .failure(reason: "Spotify private API is not logged in.")
        }

        do {
            let resolvedTrackURI = trackUri.isEmpty ? (playerState?.track?.uri ?? trackUri) : trackUri
            if devices.isEmpty || activePlayerDeviceID == nil {
                try? await refreshPlayerAndDeviceState()
            }
            guard let playbackDevice = preferredExternalPlaybackDeviceID(excluding: deviceId) else {
                let reason = "Open the Spotify desktop app or another speaker to play audio."
                await MainActor.run {
                    self.isConnectStreamingSession = false
                    self.deviceTransferNotice = reason
                }
                return .failure(reason: reason)
            }

            let fromDevice = activePlayerDeviceID ?? deviceId
            if fromDevice != playbackDevice {
                try await transferDevice(from: fromDevice, to: playbackDevice)
            }

            let playTrackURI = trackUri.isEmpty ? resolvedTrackURI : trackUri
            let resolvedContext = await resolvePlayContextURI(
                trackUri: playTrackURI,
                preferredContextURI: contextUri
            )
            try await pythonCompatiblePlay(
                trackUri: playTrackURI,
                contextUri: resolvedContext,
                trackUid: trackUid,
                trackIndex: trackIndex,
                targetDeviceID: playbackDevice
            )
            let deviceName = devices.first(where: { $0.deviceId == playbackDevice })?.name ?? "another device"
            await MainActor.run {
                self.isConnectStreamingSession = true
                self.deviceTransferNotice = "Playing on \(deviceName)."
                self.scheduleDeviceTransferNoticeClear()
            }
            print("[SpotifyConnect] Playback on \(deviceName) (\(playbackDevice.prefix(8))…)")
            return .success
        } catch {
            print("[SpotifyConnect] play failed: \(error.localizedDescription)")
            await MainActor.run {
                self.isConnectStreamingSession = false
                self.deviceTransferNotice = "Couldn’t start playback: \(error.localizedDescription)"
                self.scheduleDeviceTransferNoticeClear()
            }
            return .failure(reason: error.localizedDescription)
        }
    }

    func preferredExternalPlaybackDeviceID(excluding deviceId: String) -> String? {
        if let active = activePlayerDeviceID,
           active != deviceId,
           active != controllerDeviceID,
           devices.contains(where: { $0.deviceId == active }) {
            return active
        }

        let ranked = devices.filter { $0.deviceId != deviceId && $0.deviceId != controllerDeviceID }
        if let desktop = ranked.first(where: { device in
            let name = device.name.lowercased()
            let type = device.deviceType.lowercased()
            guard !name.contains("sapphire") else { return false }
            return type == "computer" || name.contains("mac") || name == "spotify"
        }) {
            return desktop.deviceId
        }
        if let phone = ranked.first(where: { device in
            let name = device.name.lowercased()
            let type = device.deviceType.lowercased()
            return !name.contains("sapphire") && (type.contains("smartphone") || type.contains("tablet") || name.contains("iphone"))
        }) {
            return phone.deviceId
        }
        return ranked.first(where: { !$0.name.lowercased().contains("sapphire") })?.deviceId
            ?? ranked.first?.deviceId
    }

    private func resolvePlayContextURI(trackUri: String, preferredContextURI: String?) async -> String {
        if let preferred = preferredContextURI?.trimmingCharacters(in: .whitespacesAndNewlines),
           !preferred.isEmpty,
           !preferred.contains(":track:") {
            return preferred
        }
        if let preferred = preferredContextURI, preferred.contains(":album:") || preferred.contains(":playlist:") {
            return preferred
        }

        if !trackUri.isEmpty {
            let decorated = await decorateContextTracks(uris: [trackUri])
            if let albumURI = decorated.first?.albumOfTrack.uri, !albumURI.isEmpty {
                return albumURI
            }
        }

        return preferredContextURI ?? trackUri
    }

    func connectSeek(to seconds: TimeInterval) async -> Bool {
        let clamped = max(0, seconds)
        let ms = clamped * 1000.0
        return await sendWebPlayerStyleSkip(endpoint: "seek_to", extra: ["value": ms])
    }

    @discardableResult
    func connectSkipNext() async -> Bool {
        await sendWebPlayerStyleSkip(endpoint: "skip_next")
    }

    @discardableResult
    func connectSkipPrevious() async -> Bool {
        let elapsedMs = playerState?.realtimePositionMilliseconds() ?? 0
        if elapsedMs > 3_000 {
            return await sendWebPlayerStyleSkip(endpoint: "seek_to", extra: ["value": 0])
        }
        return await sendWebPlayerStyleSkip(endpoint: "skip_prev")
    }

    @discardableResult
    private func sendWebPlayerStyleSkip(endpoint: String, extra: [String: Any] = [:]) async -> Bool {
        guard let from = controllerDeviceID, let spclient = spclientClient, isLoggedIn else {
            print("[SpotifyConnect] \(endpoint) skipped — not ready")
            return false
        }

        let to = await resolvePlaybackDeviceIDForCommand()
        guard let to, to != from else {
            print("[SpotifyConnect] \(endpoint) skipped — no external playback device (from=\(from.prefix(8))…)")
            return false
        }

        await refreshTokensIfNeeded(force: false)
        let path = "/connect-state/v1/player/command/from/\(from)/to/\(to)"
        var command: [String: Any] = [
            "logging_params": [
                "command_id": generateRandomHexString(length: 32)
            ],
            "endpoint": endpoint
        ]
        for (key, value) in extra { command[key] = value }
        let payload: [String: Any] = ["command": command]

        do {
            var headers: [String: String] = [:]
            if let connectionId = webSocketManager?.latestConnectionID {
                headers["x-spotify-connection-id"] = connectionId
            }
            var response = try await spclient.post(
                path: path,
                jsonBody: payload,
                additionalHeaders: headers.isEmpty ? nil : headers
            )
            if response.statusCode == 401 || response.statusCode == 403 {
                await refreshTokensIfNeeded(force: true)
                response = try await spclient.post(
                    path: path,
                    jsonBody: payload,
                    additionalHeaders: headers.isEmpty ? nil : headers
                )
            }
            let ok = (200...299).contains(response.statusCode)
            if !ok {
                let snippet = String(data: response.body.prefix(200), encoding: .utf8) ?? ""
                print("[SpotifyConnect] \(endpoint) HTTP \(response.statusCode): \(snippet)")
                return false
            }
            if !response.body.isEmpty {
                let body = String(data: response.body, encoding: .utf8) ?? ""
                if !body.contains("ack_id") {
                    print("[SpotifyConnect] \(endpoint) unexpected body: \(body.prefix(120))")
                }
            }
            activePlayerDeviceID = to
            return true
        } catch {
            print("[SpotifyConnect] \(endpoint) failed: \(error.localizedDescription)")
            return false
        }
    }

    @discardableResult
    private func wakePlaybackDeviceIfNeeded(_ deviceID: String) async -> Bool {
        guard let from = controllerDeviceID, from != deviceID else { return false }
        do {
            try await transferDevice(from: from, to: deviceID)
            try? await Task.sleep(nanoseconds: 250_000_000)
            return true
        } catch {
            print("[SpotifyConnect] wake/transfer to \(deviceID.prefix(8))… failed: \(error.localizedDescription)")
            return false
        }
    }

    @discardableResult
    func connectResume() async -> Bool {
        guard isLoggedIn, controllerDeviceID != nil else { return false }
        try? await refreshPlayerAndDeviceState()

        guard let to = await resolvePlaybackDeviceIDForCommand() else {
            print("[SpotifyConnect] resume skipped — no playback device")
            return false
        }

        if await sendWebPlayerStyleSkip(endpoint: "resume") {
            return true
        }

        _ = await wakePlaybackDeviceIfNeeded(to)
        if await sendWebPlayerStyleSkip(endpoint: "resume") {
            return true
        }

        if let active = activePlayerDeviceID, active != to, active != controllerDeviceID {
            do {
                try await transferDevice(from: active, to: to)
                try? await Task.sleep(nanoseconds: 250_000_000)
                return await sendWebPlayerStyleSkip(endpoint: "resume")
            } catch {
                print("[SpotifyConnect] secondary transfer/resume failed: \(error.localizedDescription)")
            }
        }
        return false
    }

    @discardableResult
    func connectPause() async -> Bool {
        guard isLoggedIn, controllerDeviceID != nil else { return false }

        if await sendWebPlayerStyleSkip(endpoint: "pause") {
            return true
        }

        try? await refreshPlayerAndDeviceState()
        guard let to = await resolvePlaybackDeviceIDForCommand() else { return false }
        _ = await wakePlaybackDeviceIfNeeded(to)
        return await sendWebPlayerStyleSkip(endpoint: "pause")
    }

    private func resolvePlaybackDeviceIDForCommand() async -> String? {
        if let active = activePlayerDeviceID,
           active != controllerDeviceID {
            return active
        }
        if devices.isEmpty || activePlayerDeviceID == nil || activePlayerDeviceID == controllerDeviceID {
            try? await refreshPlayerAndDeviceState()
        }
        if let active = activePlayerDeviceID,
           active != controllerDeviceID {
            return active
        }
        if let external = preferredExternalPlaybackDeviceID(excluding: controllerDeviceID ?? "") {
            return external
        }
        return localSpotifyDesktopDeviceID()
    }

    func addToQueue(uri: String, uid: String? = nil, metadata: [String: String] = [:]) async -> Bool {
        var meta = metadata
        if meta["title"] == nil { meta["title"] = "Queued Track" }
        let trackUID = uid ?? UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        var extra: [String: Any] = [
            "track": [
                "uri": uri,
                "uid": trackUID,
                "metadata": meta,
                "provider": "queue"
            ] as [String: Any]
        ]
        if let revision = playerState?.queueRevision {
            extra["queue_revision"] = revision
        }
        let ok = await sendConnectCommandReturning(endpoint: "add_to_queue", extra: extra)
        if ok {
            let optimistic = PlayerState.Track(
                uri: uri,
                uid: trackUID,
                metadata: .init(
                    title: meta["title"],
                    albumTitle: meta["album_title"],
                    artistName: meta["artist_name"],
                    artistUri: nil,
                    imageUrl: meta["image_url"],
                    imageSmallUrl: nil,
                    imageLargeUrl: meta["image_url"],
                    imageXlargeUrl: nil,
                    contextUri: meta["context_uri"],
                    hidden: nil
                )
            )
            await MainActor.run {
                if !self.nativeQueue.contains(where: { $0.uid == trackUID }) {
                    self.nativeQueue.append(optimistic)
                }
            }
            try? await refreshPlayerAndDeviceState()
        }
        return ok
    }

    func removeFromQueue(uid: String) async -> Bool {
        let sourceQueue = await MainActor.run { self.nativeQueue }
        let remaining = sourceQueue.filter { $0.uid != uid }
        guard remaining.count != sourceQueue.count else { return false }

        let next = connectQueueTrackPayloads(from: remaining)
        let prev = connectQueueTrackPayloads(from: playerState?.prevTracks ?? [])
        var extra: [String: Any] = [
            "next_tracks": next,
            "prev_tracks": prev
        ]
        if let revision = playerState?.queueRevision {
            extra["queue_revision"] = revision
        }

        await MainActor.run { self.nativeQueue = remaining }

        let ok = await sendConnectCommandReturning(endpoint: "set_queue", extra: extra)
        try? await refreshPlayerAndDeviceState()
        if !ok {
            await MainActor.run { self.nativeQueue = sourceQueue }
        }
        return ok
    }

    private func connectQueueTrackPayloads(from tracks: [PlayerState.Track]) -> [[String: Any]] {
        tracks.map { track in
            var metadata: [String: String] = [:]
            if let title = track.metadata?.title { metadata["title"] = title }
            if let artist = track.metadata?.artistName { metadata["artist_name"] = artist }
            if let album = track.metadata?.albumTitle { metadata["album_title"] = album }
            if let image = track.metadata?.imageUrl ?? track.metadata?.imageLargeUrl {
                metadata["image_url"] = image
            }
            if let context = track.metadata?.contextUri ?? playerState?.contextUri {
                metadata["context_uri"] = context
            }
            return [
                "uri": track.uri,
                "uid": track.uid,
                "metadata": metadata,
                "provider": "queue"
            ] as [String: Any]
        }
    }

    @discardableResult
    func sendConnectCommandReturning(endpoint: String, extra: [String: Any] = [:]) async -> Bool {
        if endpoint == "resume", extra.isEmpty {
            return await connectResume()
        }
        if endpoint == "pause", extra.isEmpty {
            return await connectPause()
        }

        guard let from = controllerDeviceID,
              let spclient = spclientClient else {
            print("[SpotifyConnect] connect command \(endpoint) skipped — missing device/spclient")
            return false
        }

        let to = await resolvePlaybackDeviceIDForCommand() ?? activePlayerDeviceID
        guard let to, to != from else {
            print("[SpotifyConnect] connect command \(endpoint) skipped — no playback device")
            return false
        }

        await refreshTokensIfNeeded(force: false)
        let path = "/connect-state/v1/player/command/from/\(from)/to/\(to)"
        var command: [String: Any] = [
            "endpoint": endpoint,
            "logging_params": [
                "command_id": generateRandomHexString(length: 32)
            ]
        ]
        for (key, value) in extra { command[key] = value }
        let payload: [String: Any] = ["command": command]
        do {
            var headers: [String: String] = [:]
            if let connectionId = webSocketManager?.latestConnectionID {
                headers["x-spotify-connection-id"] = connectionId
            }
            let response = try await spclient.post(
                path: path,
                jsonBody: payload,
                additionalHeaders: headers.isEmpty ? nil : headers
            )
            if response.statusCode == 401 || response.statusCode == 403 {
                await refreshTokensIfNeeded(force: true)
                let retry = try await spclient.post(path: path, jsonBody: payload, additionalHeaders: headers.isEmpty ? nil : headers)
                let ok = (200...299).contains(retry.statusCode)
                if ok { activePlayerDeviceID = to }
                return ok
            }
            let ok = (200...299).contains(response.statusCode)
            if ok { activePlayerDeviceID = to }
            return ok
        } catch {
            print("[SpotifyConnect] connect command \(endpoint) failed: \(error.localizedDescription)")
            return false
        }
    }

    private func applyQueueRevision(nextTracks: [[String: Any]]) async -> Bool {
        var extra: [String: Any] = [
            "next_tracks": nextTracks,
            "prev_tracks": connectQueueTrackPayloads(from: playerState?.prevTracks ?? [])
        ]
        if let revision = playerState?.queueRevision {
            extra["queue_revision"] = revision
        }
        let ok = await sendConnectCommandReturning(endpoint: "set_queue", extra: extra)
        try? await refreshPlayerAndDeviceState()
        return ok
    }

    func clearConnectControlSession() {
        Task { @MainActor in self.isConnectStreamingSession = false }
    }

    // MARK: Connect Commands (self-targeted)

    func sendConnectCommand(endpoint: String, extra: [String: Any] = [:]) async {
        _ = await sendConnectCommandReturning(endpoint: endpoint, extra: extra)
    }

    // MARK: Additional API Features

    func fetchColorLyrics(trackId: String, imageURL: String) async -> [LyricLine] {
        guard let client = wgSpclientClient else { return [] }
        let rawId = SpotifyIDConverter.rawID(from: trackId)
        let normalizedImage = Self.normalizedLyricsImageURL(imageURL)

        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-_.!~*'()")

        let query = [
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "vocalRemoval", value: "false"),
            URLQueryItem(name: "market", value: "from_token")
        ]

        var candidates: [(path: String, query: [URLQueryItem])] = []
        if !normalizedImage.isEmpty,
           let encodedImage = normalizedImage.addingPercentEncoding(withAllowedCharacters: allowed) {
            candidates.append(("/color-lyrics/v2/track/\(rawId)/image/\(encodedImage)", query))
        }
        candidates.append(("/color-lyrics/v2/track/\(rawId)", query))

        let headers = [
            "Accept": "application/json",
            "app-platform": "WebPlayer",
            "spotify-app-version": clientVersion ?? "1.2.95.452.g5c9bdf32"
        ]

        for candidate in candidates {
            do {
                let response = try await client.get(
                    path: candidate.path,
                    queryItems: candidate.query,
                    additionalHeaders: headers
                )
                guard (200...299).contains(response.statusCode), !response.body.isEmpty else {
                    let snippet = String(data: response.body.prefix(120), encoding: .utf8) ?? ""
                    print("[SpotifyConnect] color-lyrics HTTP \(response.statusCode) for \(candidate.path.prefix(80)): \(snippet)")
                    continue
                }
                if let lines = decodeColorLyrics(response.body) {
                    return lines
                }
            } catch {
                print("[SpotifyConnect] color-lyrics \(candidate.path.prefix(80)) failed: \(error.localizedDescription)")
            }
        }
        return []
    }

    private static func normalizedLyricsImageURL(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if trimmed.hasPrefix("spotify:image:") {
            let id = trimmed.replacingOccurrences(of: "spotify:image:", with: "")
            return "https://i.scdn.co/image/\(id)"
        }
        if trimmed.hasPrefix("//") { return "https:\(trimmed)" }
        return trimmed
    }

    private func decodeColorLyrics(_ data: Data) -> [LyricLine]? {
        do {
            let decoded = try JSONDecoder().decode(SpotifyColorLyrics.self, from: data)
            let lines = decoded.lyrics?.lines.compactMap { line -> LyricLine? in
                let ms: Int
                if let asInt = Int(line.startTimeMs) {
                    ms = asInt
                } else if let asDouble = Double(line.startTimeMs) {
                    ms = Int(asDouble)
                } else {
                    return nil
                }
                let text = line.words.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty, text != "" else {
                    return LyricLine(text: text.isEmpty ? "" : text, timestamp: TimeInterval(ms) / 1000.0, translatedText: nil)
                }
                return LyricLine(text: text, timestamp: TimeInterval(ms) / 1000.0, translatedText: nil)
            } ?? []
            return lines.isEmpty ? nil : lines
        } catch {
            let snippet = String(data: data.prefix(240), encoding: .utf8) ?? "<non-utf8 \(data.count) bytes>"
            print("[SpotifyConnect] color-lyrics decode failed: \(error.localizedDescription)\nSnippet: \(snippet)")
            return nil
        }
    }

    func fetchClipTranscript(episodeURI: String, startSeconds: Double = 0, endSeconds: Double = 60) async -> SpotifyClipTranscript? {
        guard let client = wgSpclientClient else { return nil }
        let encoded = SpotifyIDConverter.pathEncodedURI(episodeURI)
        let path = "/clip-transcript/v1/transcripts/\(encoded)"
        let query = [
            URLQueryItem(name: "offsets.start", value: String(format: "%.3fs", startSeconds)),
            URLQueryItem(name: "offsets.end", value: String(format: "%.3fs", endSeconds))
        ]
        do {
            let response = try await client.get(path: path, queryItems: query)
            return try JSONDecoder().decode(SpotifyClipTranscript.self, from: response.body)
        } catch {
            return nil
        }
    }

    func fetchJamSession() async -> Bool {
        guard let client = wgSpclientClient else { return false }
        do {
            let response = try await client.get(path: "/social-connect/v2/sessions/current")
            let decoded = try JSONDecoder().decode(SpotifyJamSession.self, from: response.body)
            let active = decoded.session?.isActive ?? false
            publishExtendedState(jamSessionActive: active)
            return active
        } catch {
            return false
        }
    }

    func fetchLibraryImportEligible() async -> Bool {
        guard let client = wgSpclientClient else { return false }
        do {
            let response = try await client.get(path: "/library-import/v1/eligible")
            if let json = try? JSONSerialization.jsonObject(with: response.body) as? [String: Any],
               let eligible = json["eligible"] as? Bool {
                publishExtendedState(libraryImportEligible: eligible)
                return eligible
            }
        } catch { }
        return false
    }

    func fetchPopularReleases(artistId: String) async -> [SpotifyPopularRelease] {
        guard let client = wgSpclientClient else { return [] }
        let path = "/playlist/v2/list/popular-release-segments-main-roles/artist_\(artistId)"
        do {
            let response = try await client.get(path: path)
            guard let json = try JSONSerialization.jsonObject(with: response.body) as? [String: Any],
                  let items = json["items"] as? [[String: Any]] else { return [] }
            let releases = items.compactMap { item -> SpotifyPopularRelease? in
                guard let uri = item["uri"] as? String, let name = item["name"] as? String else { return nil }
                let imageURL = (item["image"] as? [String: Any])?["url"] as? String
                return SpotifyPopularRelease(
                    id: uri,
                    name: name,
                    uri: uri,
                    imageURL: imageURL.flatMap { URL(string: $0) }
                )
            }
            publishExtendedState(popularReleases: releases)
            return releases
        } catch {
            return []
        }
    }

    func lookupChildEntities(uris: [String]) async -> [URL] {
        guard !uris.isEmpty else { return [] }
        do {
            let response: LookupChildResponse = try await pathfinderQuery(
                operationName: "lookupChildEntities",
                variables: ["uris": uris],
                sendAsBody: true,
                useV2Endpoint: true
            )
            return response.data.lookupEntities.compactMap { entity in
                entity.visualIdentityTrait?.squareCoverImage?.image?.data?.sources?.first?.url.flatMap { URL(string: $0) }
            }
        } catch {
            return []
        }
    }

    func checkIsCurated(uris: [String]) async -> [Bool] {
        guard !uris.isEmpty else { return [] }
        do {
            let response: IsCuratedResponse = try await pathfinderQuery(
                operationName: "isCurated",
                variables: ["uris": uris],
                sendAsBody: true,
                useV2Endpoint: true
            )
            return response.data.lookup.map { $0.data?.isCurated ?? false }
        } catch {
            return []
        }
    }

    func fetchExtendedMetadata(trackURI: String) async -> [String: Any]? {
        guard let client = wgSpclientClient else { return nil }
        let payload: [String: Any] = [
            "entityRequest": [[
                "entityUri": trackURI,
                "query": [["extensionKind": 249, "etag": ""]]
            ]]
        ]
        do {
            let response = try await client.post(path: "/extended-metadata/v0/extended-metadata", jsonBody: payload)
            return try JSONSerialization.jsonObject(with: response.body) as? [String: Any]
        } catch {
            return nil
        }
    }

    func collectionContains(set: String, uris: [String]) async -> [Bool] {
        guard let client = wgSpclientClient, let username = userProfile?.profile.username else { return [] }
        let payload: [String: Any] = [
            "username": username,
            "set": set,
            "items": uris.map { ["uri": $0] }
        ]
        do {
            let response = try await client.post(path: "/collection/v2/contains?market=from_token", jsonBody: payload)
            let decoded = try JSONDecoder().decode(CollectionContainsResponse.self, from: response.body)
            return decoded.found
        } catch {
            return []
        }
    }
}

// MARK: - Response Wrappers

private struct LookupChildResponse: Decodable {
    let data: DataNode
    struct DataNode: Decodable {
        let lookupEntities: [EntityNode]
    }
    struct EntityNode: Decodable {
        let visualIdentityTrait: VisualTrait?
    }
    struct VisualTrait: Decodable {
        let squareCoverImage: CoverImage?
    }
    struct CoverImage: Decodable {
        let image: ImageData?
    }
    struct ImageData: Decodable {
        let data: ImageSources?
    }
    struct ImageSources: Decodable {
        let sources: [Source]?
    }
    struct Source: Decodable {
        let url: String?
    }
}

private struct IsCuratedResponse: Decodable {
    let data: DataNode
    struct DataNode: Decodable {
        let lookup: [LookupItem]
    }
    struct LookupItem: Decodable {
        let data: CuratedData?
    }
    struct CuratedData: Decodable {
        let isCurated: Bool?
    }
}

private struct CollectionContainsResponse: Decodable {
    let found: [Bool]
}

// MARK: - Consolidated from SpotifyResilientAPI.swift

// MARK: - Official Web API DTOs (api.spotify.com/v1)

private struct OfficialWebAPITrack: Decodable {
    let id: String
    let name: String
    let uri: String
    let album: Album
    let artists: [Artist]
    let durationMs: Int?

    enum CodingKeys: String, CodingKey {
        case id, name, uri, album, artists
        case durationMs = "duration_ms"
    }

    struct Album: Decodable {
        let name: String
        let images: [Image]
    }

    struct Artist: Decodable {
        let id: String
        let name: String
        let uri: String
    }

    struct Image: Decodable {
        let url: String
        let width: Int?
        let height: Int?
    }

    func toTrackUnion() -> SpotifyTrackDetailsResponse.TrackUnion {
        .init(
            uri: uri,
            name: name,
            playcount: nil,
            albumOfTrack: .init(
                name: album.name,
                coverArt: .init(sources: album.images.map {
                    .init(url: $0.url, width: $0.width, height: $0.height)
                }),
                publishDate: nil
            ),
            artists: .init(items: artists.map {
                .init(uri: $0.uri, profile: .init(name: $0.name))
            }),
            otherArtists: .init(items: [])
        )
    }

    func toSpotifyTrack() -> SpotifyTrack {
        SpotifyTrack(
            id: id,
            name: name,
            uri: uri,
            album: SpotifyAlbum(
                name: album.name,
                images: album.images.map { SpotifyImage(url: $0.url) }
            ),
            artists: artists.map { SpotifyArtist(name: $0.name) },
            durationMs: durationMs ?? 0,
            popularity: nil
        )
    }
}

private struct OfficialWebAPISearchResponse: Decodable {
    struct Tracks: Decodable {
        let items: [OfficialWebAPITrack]
    }
    let tracks: Tracks?
}

extension SpotifyPrivateAPIManager {

    func fetchTrackMetadataResilient(trackID: String) async -> SpotifyTrackDetailsResponse.TrackUnion? {
        let rawID = SpotifyIDConverter.rawID(from: trackID)

        if let official = await fetchOfficialTrack(rawID: rawID) {
            return official.toTrackUnion()
        }

        if let pathfinder = await fetchTrackViaPathfinder(rawID: rawID) {
            return pathfinder
        }

        let uri = "spotify:track:\(rawID)"
        if let decorated = await decorateContextTracks(uris: [uri]).first {
            let sources = decorated.albumOfTrack.coverArt?.sources.map {
                SpotifyTrackDetailsResponse.ImageSource(url: $0.url, width: $0.width, height: $0.height)
            } ?? []
            let artists = ArtistCollection(items: decorated.artists.items.compactMap { item in
                guard let uri = item.uri else { return nil }
                return ArtistItem(uri: uri, profile: .init(name: item.profile.name))
            })
            return SpotifyTrackDetailsResponse.TrackUnion(
                uri: decorated.uri,
                name: decorated.name,
                playcount: nil,
                albumOfTrack: .init(
                    name: decorated.albumOfTrack.name,
                    coverArt: .init(sources: sources),
                    publishDate: nil
                ),
                artists: artists,
                otherArtists: .init(items: [])
            )
        }

        guard let metadata = await fetchTrackMetadata(trackId: rawID) else { return nil }
        let coverSources: [SpotifyTrackDetailsResponse.ImageSource] = {
            guard let url = metadata.album?.bestImageURL?.absoluteString else { return [] }
            return [.init(url: url, width: nil, height: nil)]
        }()
        let artists = ArtistCollection(items: (metadata.artist ?? []).map {
            ArtistItem(uri: $0.gid.map { "spotify:artist:\($0)" } ?? "", profile: .init(name: $0.name))
        })
        return SpotifyTrackDetailsResponse.TrackUnion(
            uri: metadata.canonicalUri ?? uri,
            name: metadata.name,
            playcount: nil,
            albumOfTrack: .init(
                name: metadata.album?.name ?? "Unknown Album",
                coverArt: .init(sources: coverSources),
                publishDate: nil
            ),
            artists: artists,
            otherArtists: .init(items: [])
        )
    }

    func searchForTrackResilient(title: String, artist: String) async -> SpotifyTrack? {
        if let official = await searchOfficialWebAPI(title: title, artist: artist) {
            return official
        }
        return await searchForTrackViaPathfinder(title: title, artist: artist)
    }

    // MARK: - Official Web API helpers

    private func fetchOfficialTrack(rawID: String) async -> OfficialWebAPITrack? {
        guard let token = currentAccessToken() else { return nil }
        guard let url = URL(string: "https://api.spotify.com/v1/tracks/\(rawID)") else { return nil }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            return try JSONDecoder().decode(OfficialWebAPITrack.self, from: data)
        } catch {
            print("[SpotifyAPI] Official /v1/tracks failed: \(error.localizedDescription)")
            return nil
        }
    }

    private func searchOfficialWebAPI(title: String, artist: String) async -> SpotifyTrack? {
        guard let token = currentAccessToken() else { return nil }
        var components = URLComponents(string: "https://api.spotify.com/v1/search")!
        let query = "track:\"\(title.trimmingCharacters(in: .whitespacesAndNewlines))\" artist:\"\(artist.trimmingCharacters(in: .whitespacesAndNewlines))\""
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "type", value: "track"),
            URLQueryItem(name: "limit", value: "1")
        ]
        guard let url = components.url else { return nil }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            let decoded = try JSONDecoder().decode(OfficialWebAPISearchResponse.self, from: data)
            guard let first = decoded.tracks?.items.first else { return nil }
            return first.toSpotifyTrack()
        } catch {
            print("[SpotifyAPI] Official /v1/search failed: \(error.localizedDescription)")
            return nil
        }
    }

    private func fetchTrackViaPathfinder(rawID: String) async -> SpotifyTrackDetailsResponse.TrackUnion? {
        do {
            let response: SpotifyTrackDetailsResponse = try await pathfinderQuery(
                operationName: "getTrack",
                variables: [
                    "uri": "spotify:track:\(rawID)",
                    "includeVideoAssociationItems": false
                ],
                sendAsBody: true,
                useV2Endpoint: true
            )
            return response.data.trackUnion
        } catch {
            print("[SpotifyAPI] Pathfinder getTrack failed, falling back to spclient: \(error.localizedDescription)")
            return nil
        }
    }

    private func searchForTrackViaPathfinder(title: String, artist: String) async -> SpotifyTrack? {
        let query = "\(title) \(artist)"
        let variables: [String: Any] = [
            "searchTerm": query,
            "offset": 0,
            "limit": 5,
            "numberOfTopResults": 1,
            "includeAudiobooks": false
        ]
        do {
            let response: NativeSearchResponse = try await pathfinderQuery(
                operationName: "searchDesktop",
                variables: variables
            )
            if let bestMatch = response.data?.searchV2?.tracksV2?.items?.first?.itemV2.data {
                return SpotifyTrack(from: bestMatch)
            }
            return nil
        } catch {
            print("[SpotifyPrivateAPIManager] Error searching for track: \(error.localizedDescription)")
            return nil
        }
    }
}

// MARK: - Consolidated from SpotifyExtendedAPI.swift

import SwiftUI

// MARK: - Extended Models

struct SpotifyAccountInfo: Decodable, Equatable {
    let product: String
    let country: String
    let onDemand: Bool
    let catalogue: String
    let ads: Bool

    var isPremium: Bool { product.uppercased() == "PREMIUM" }
    var displayProduct: String { isPremium ? "Premium" : "Free" }

    enum CodingKeys: String, CodingKey {
        case product, country
        case onDemand = "onDemand"
        case catalogue, ads
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        product = try container.decodeIfPresent(String.self, forKey: .product) ?? "FREE"
        country = try container.decodeIfPresent(String.self, forKey: .country) ?? ""
        onDemand = try container.decodeIfPresent(Bool.self, forKey: .onDemand) ?? false
        catalogue = try container.decodeIfPresent(String.self, forKey: .catalogue) ?? "free"
        ads = try container.decodeIfPresent(Bool.self, forKey: .ads) ?? true
    }
}

struct SpotifyExtractedColor: Decodable, Equatable {
    let hex: String
    let isFallback: Bool

    var swiftUIColor: Color {
        Color(hex: hex) ?? .white
    }
}

struct SpotifyDecoratedTrack: Decodable {
    let uri: String
    let name: String
    let albumOfTrack: Album
    let artists: ArtistItems
    let duration: Duration?

    struct Album: Decodable {
        let name: String
        let uri: String?
        let coverArt: CoverArt?

        enum CodingKeys: String, CodingKey { case name, uri, coverArt }

        init(name: String, uri: String?, coverArt: CoverArt?) {
            self.name = name
            self.uri = uri
            self.coverArt = coverArt
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Unknown Album"
            uri = try container.decodeIfPresent(String.self, forKey: .uri)
            coverArt = try container.decodeIfPresent(CoverArt.self, forKey: .coverArt)
        }
    }

    struct CoverArt: Decodable {
        let sources: [ImageSource]
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            sources = try container.decodeIfPresent([ImageSource].self, forKey: .sources) ?? []
        }
        enum CodingKeys: String, CodingKey { case sources }
    }

    struct ImageSource: Decodable {
        let url: String
        let width: Int?
        let height: Int?

        enum CodingKeys: String, CodingKey { case url, width, height }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            url = try container.decodeIfPresent(String.self, forKey: .url) ?? ""
            width = try container.decodeIfPresent(Int.self, forKey: .width)
                ?? container.decodeIfPresent(Int.self, forKey: .height)
            height = try container.decodeIfPresent(Int.self, forKey: .height)
                ?? width
        }
    }

    struct ArtistItems: Decodable {
        let items: [ArtistItem]
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            items = try container.decodeIfPresent([ArtistItem].self, forKey: .items) ?? []
        }
        enum CodingKeys: String, CodingKey { case items }
    }

    struct ArtistItem: Decodable {
        let uri: String?
        let profile: Profile
        struct Profile: Decodable {
            let name: String
            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Unknown Artist"
            }
            enum CodingKeys: String, CodingKey { case name }
        }
    }

    struct Duration: Decodable {
        let totalMilliseconds: Int
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            totalMilliseconds = try container.decodeIfPresent(Int.self, forKey: .totalMilliseconds) ?? 0
        }
        enum CodingKeys: String, CodingKey { case totalMilliseconds }
    }

    var imageURL: URL? {
        guard let url = albumOfTrack.coverArt?.sources.max(by: { ($0.width ?? 0) < ($1.width ?? 0) })?.url,
              !url.isEmpty else { return nil }
        return URL(string: url)
    }

    var artistName: String {
        let names = artists.items.map(\.profile.name)
        return names.isEmpty ? "Unknown Artist" : names.joined(separator: ", ")
    }
}

struct SpotifyRecommendedTrack: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let uri: String
    let duration: Int
    let popularity: Int?
    let artists: [Artist]
    let album: Album

    struct Artist: Decodable, Hashable {
        let id: String
        let name: String
        init(id: String, name: String) {
            self.id = id
            self.name = name
        }
    }

    struct Album: Decodable, Hashable {
        let id: String
        let name: String
        let imageUrl: String?

        enum CodingKeys: String, CodingKey {
            case id, name
            case imageUrl = "largeImageUrl"
        }

        init(id: String, name: String, imageUrl: String?) {
            self.id = id
            self.name = name
            self.imageUrl = imageUrl
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decodeIfPresent(String.self, forKey: .id) ?? ""
            name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
            imageUrl = try container.decodeIfPresent(String.self, forKey: .imageUrl)
        }
    }

    init(id: String, name: String, uri: String, duration: Int, popularity: Int?, artists: [Artist], album: Album) {
        self.id = id
        self.name = name
        self.uri = uri
        self.duration = duration
        self.popularity = popularity
        self.artists = artists
        self.album = album
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        duration = try container.decode(Int.self, forKey: .duration)
        popularity = try container.decodeIfPresent(Int.self, forKey: .popularity)
        artists = try container.decode([Artist].self, forKey: .artists)
        album = try container.decode(Album.self, forKey: .album)
        let originalId = try container.decodeIfPresent(String.self, forKey: .originalId)
        uri = originalId ?? "spotify:track:\(id)"
    }

    enum CodingKeys: String, CodingKey {
        case id, originalId, name, duration, popularity, artists, album
    }

    var imageURL: URL? {
        guard let imageUrl = album.imageUrl else { return nil }
        return URL(string: imageUrl)
    }

    var albumURI: String? {
        if album.id.hasPrefix("spotify:album:") { return album.id }
        if album.id.hasPrefix("spotify:") { return album.id }
        if !album.id.isEmpty { return "spotify:album:\(album.id)" }
        return nil
    }
}

struct SpotifyPlaylistPermissions: Decodable {
    let canEditItems: Bool
    let canEditMetadata: Bool
    let canView: Bool
    let basePermission: String

    enum CodingKeys: String, CodingKey {
        case basePermission
        case currentUserCapabilities
    }

    enum CapKeys: String, CodingKey {
        case canEditItems, canEditMetadata, canView
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        basePermission = try container.decodeIfPresent(String.self, forKey: .basePermission) ?? "BLOCKED"
        let caps = try container.nestedContainer(keyedBy: CapKeys.self, forKey: .currentUserCapabilities)
        canEditItems = try caps.decodeIfPresent(Bool.self, forKey: .canEditItems) ?? false
        canEditMetadata = try caps.decodeIfPresent(Bool.self, forKey: .canEditMetadata) ?? false
        canView = try caps.decodeIfPresent(Bool.self, forKey: .canView) ?? true
    }
}

struct SpotifyCanvasInfo: Decodable, Equatable {
    let url: String
    let type: String?

    var videoURL: URL? { URL(string: url) }

    var isPlayableVideo: Bool {
        let lower = url.lowercased()
        if lower.contains(".cnvs.") || lower.hasSuffix(".mp4") || lower.hasSuffix(".webm") {
            return true
        }
        if let type, type.uppercased().contains("VIDEO") {
            return !lower.contains(".thmb.") && !lower.hasSuffix(".jpg") && !lower.hasSuffix(".jpeg") && !lower.hasSuffix(".png")
        }
        return false
    }
}

struct SpotifyArtistConcert: Decodable, Identifiable, Hashable {
    let uri: String
    let title: String
    let startDateIsoString: String
    let city: String
    let venue: String

    var id: String { uri }

    init(uri: String, title: String, startDateIsoString: String, city: String, venue: String) {
        self.uri = uri
        self.title = title
        self.startDateIsoString = startDateIsoString
        self.city = city
        self.venue = venue
    }

    enum CodingKeys: String, CodingKey {
        case uri, title, startDateIsoString, location
    }

    enum LocationKeys: String, CodingKey {
        case city, name
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        uri = try container.decode(String.self, forKey: .uri)
        title = try container.decode(String.self, forKey: .title)
        startDateIsoString = try container.decode(String.self, forKey: .startDateIsoString)
        let location = try container.nestedContainer(keyedBy: LocationKeys.self, forKey: .location)
        city = try location.decodeIfPresent(String.self, forKey: .city) ?? ""
        venue = try location.decodeIfPresent(String.self, forKey: .name) ?? ""
    }
}

struct SpotifyRecentlyPlayedItem: Identifiable, Hashable {
    let id: String
    let name: String
    let uri: String
    let imageURL: URL?
    let ownerName: String
}

struct SpotifyHomeItem: Identifiable, Hashable {
    let id: String
    let name: String
    let uri: String
    let imageURL: URL?
    let subtitle: String?
}

struct SpotifyHomeSection: Identifiable, Hashable {
    let id: String
    let title: String?
    let items: [SpotifyHomeItem]

    init?(from section: SpotifyHomeResponse.SectionItem) {
        let uri = section.uri ?? section.data?.uri ?? UUID().uuidString
        let rawItems = section.sectionItems?.items ?? []
        let mapped: [SpotifyHomeItem] = rawItems.compactMap { item in
            let content = item.content?.data
            let entityURI = content?.uri ?? item.uri
            guard let entityURI, !entityURI.isEmpty else { return nil }
            let name = content?.name ?? "Untitled"
            let owner = content?.ownerV2?.data?.name
            let imageURL = content?.resolvedImageURL
            return SpotifyHomeItem(
                id: entityURI,
                name: name,
                uri: entityURI,
                imageURL: imageURL,
                subtitle: owner
            )
        }
        guard !mapped.isEmpty else { return nil }
        self.id = uri
        self.title = section.data?.titleString ?? section.data?.headerEntity?.data?.profile?.name
        self.items = mapped
    }
}

// MARK: - Home Pathfinder response

struct SpotifyHomeResponse: Decodable {
    let data: DataNode?

    struct DataNode: Decodable {
        let home: HomeNode?
    }

    struct HomeNode: Decodable {
        let greeting: Greeting?
        let sectionContainer: SectionContainer?
    }

    struct Greeting: Decodable {
        let transformedLabel: String?
        let translatedBaseText: String?
    }

    struct SectionContainer: Decodable {
        let sections: Sections?
    }

    struct Sections: Decodable {
        let items: [SectionItem]?
        let totalCount: Int?
    }

    struct SectionItem: Decodable {
        let uri: String?
        let sectionItems: SectionItems?
        let data: SectionData?
    }

    struct SectionData: Decodable {
        let uri: String?
        let title: FlexibleLocalizedText?
        let headerEntity: HeaderEntity?

        var titleString: String? { title?.value }
    }

    struct FlexibleLocalizedText: Decodable {
        let value: String?

        init(from decoder: Decoder) throws {
            if let single = try? decoder.singleValueContainer() {
                if let string = try? single.decode(String.self) {
                    value = string
                    return
                }
            }
            struct Box: Decodable {
                let transformedLabel: String?
                let translatedBaseText: String?
                let text: String?
                let title: String?
                let name: String?
            }
            let box = try Box(from: decoder)
            value = box.transformedLabel ?? box.translatedBaseText ?? box.text ?? box.title ?? box.name
        }
    }

    struct HeaderEntity: Decodable {
        let data: HeaderEntityData?
    }

    struct HeaderEntityData: Decodable {
        let profile: ProfileName?
    }

    struct ProfileName: Decodable {
        let name: String?
    }

    struct SectionItems: Decodable {
        let items: [ContentWrapper]?
        let totalCount: Int?
    }

    struct ContentWrapper: Decodable {
        let uri: String?
        let content: ContentNode?
    }

    struct ContentNode: Decodable {
        let data: ContentData?
    }

    struct ContentData: Decodable {
        let uri: String?
        let name: String?
        let description: String?
        let images: FlexibleHomeImage?
        let ownerV2: OwnerWrapper?

        var resolvedImageURL: URL? {
            images?.url
        }
    }

    struct OwnerWrapper: Decodable {
        let data: OwnerData?
    }

    struct OwnerData: Decodable {
        let name: String?
        let uri: String?
    }

    enum FlexibleHomeImage: Decodable {
        case urlString(String)
        case nested(NestedImages)

        struct NestedImages: Decodable {
            let items: [ImageItem]?
            let sources: [ImageSource]?

            struct ImageItem: Decodable {
                let sources: [ImageSource]?
            }

            struct ImageSource: Decodable {
                let url: String?
            }
        }

        init(from decoder: Decoder) throws {
            if let single = try? decoder.singleValueContainer(), let string = try? single.decode(String.self) {
                self = .urlString(string)
                return
            }
            self = .nested(try NestedImages(from: decoder))
        }

        var url: URL? {
            switch self {
            case .urlString(let string):
                return URL(string: string)
            case .nested(let nested):
                if let direct = nested.sources?.compactMap(\.url).first {
                    return URL(string: direct)
                }
                if let nestedURL = nested.items?.compactMap({ $0.sources?.compactMap(\.url).first }).first {
                    return URL(string: nestedURL)
                }
                return nil
            }
        }
    }
}

struct SpotifyArtistMerch: Identifiable, Hashable {
    let id: String
    let name: String
    let uri: String
    let imageURL: URL?
    let price: String?
}

struct SpotifyTrackArtistCredit: Identifiable, Hashable {
    let id: String
    let uri: String
    let name: String
    let role: String?
}

struct SpotifyArtistProfile: Equatable {
    let uri: String
    let name: String
    let biography: String
    let monthlyListeners: Int?
    let followers: Int?
    let headerImageURL: URL?
    let avatarURL: URL?
    let isVerified: Bool
    let topCities: [String]
    let merch: [SpotifyArtistMerch]

    init(
        uri: String,
        name: String,
        biography: String,
        monthlyListeners: Int?,
        followers: Int?,
        headerImageURL: URL?,
        avatarURL: URL?,
        isVerified: Bool,
        topCities: [String],
        merch: [SpotifyArtistMerch] = []
    ) {
        self.uri = uri
        self.name = name
        self.biography = biography
        self.monthlyListeners = monthlyListeners
        self.followers = followers
        self.headerImageURL = headerImageURL
        self.avatarURL = avatarURL
        self.isVerified = isVerified
        self.topCities = topCities
        self.merch = merch
    }
}

struct SpotifySimilarAlbum: Identifiable, Hashable {
    let id: String
    let name: String
    let uri: String
    let artistName: String
    let imageURL: URL?
    let year: Int?
}

enum SpotifyGeohash {
    static func encode(latitude: Double, longitude: Double, precision: Int = 8) -> String {
        let base32 = Array("0123456789bcdefghjkmnpqrstuvwxyz")
        var latRange = (-90.0, 90.0)
        var lonRange = (-180.0, 180.0)
        var hash = ""
        var bit = 0
        var ch = 0
        var isLon = true
        while hash.count < precision {
            if isLon {
                let mid = (lonRange.0 + lonRange.1) / 2
                if longitude >= mid { ch = (ch << 1) | 1; lonRange.0 = mid }
                else { ch <<= 1; lonRange.1 = mid }
            } else {
                let mid = (latRange.0 + latRange.1) / 2
                if latitude >= mid { ch = (ch << 1) | 1; latRange.0 = mid }
                else { ch <<= 1; latRange.1 = mid }
            }
            isLon.toggle()
            bit += 1
            if bit == 5 {
                hash.append(base32[ch])
                bit = 0
                ch = 0
            }
        }
        return hash
    }
}

// MARK: - Color Hex Helper

private extension Color {
    init?(hex: String) {
        var cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("#") { cleaned.removeFirst() }
        guard cleaned.count == 6, let value = UInt64(cleaned, radix: 16) else { return nil }
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

// MARK: - Extended API

extension SpotifyPrivateAPIManager {

    @MainActor
    func publishExtendedState(
        accountInfo: SpotifyAccountInfo? = nil,
        canvas: SpotifyCanvasInfo? = nil,
        concerts: [SpotifyArtistConcert]? = nil,
        recommendations: [SpotifyRecommendedTrack]? = nil,
        recentlyPlayed: [SpotifyRecentlyPlayedItem]? = nil,
        smartShuffleAvailable: Bool? = nil,
        hasUnreadNotifications: Bool? = nil,
        jamSessionActive: Bool? = nil,
        libraryImportEligible: Bool? = nil,
        popularReleases: [SpotifyPopularRelease]? = nil,
        nowPlayingArtist: SpotifyArtistProfile? = nil,
        similarAlbums: [SpotifySimilarAlbum]? = nil,
        relatedTracks: [SpotifyRecommendedTrack]? = nil,
        trackArtistCredits: [SpotifyTrackArtistCredit]? = nil
    ) {
        if let accountInfo { self.accountInfo = accountInfo }
        if let canvas { self.currentCanvas = canvas }
        if let concerts { self.artistConcerts = concerts }
        if let recommendations { self.playlistRecommendations = recommendations }
        if let recentlyPlayed { self.recentlyPlayedItems = recentlyPlayed }
        if let smartShuffleAvailable { self.smartShuffleAvailable = smartShuffleAvailable }
        if let hasUnreadNotifications { self.hasUnreadNotifications = hasUnreadNotifications }
        if let jamSessionActive { self.jamSessionActive = jamSessionActive }
        if let libraryImportEligible { self.libraryImportEligible = libraryImportEligible }
        if let popularReleases { self.popularReleases = popularReleases }
        if let nowPlayingArtist { self.nowPlayingArtist = nowPlayingArtist }
        if let similarAlbums { self.similarAlbums = similarAlbums }
        if let relatedTracks { self.relatedTracks = relatedTracks }
        if let trackArtistCredits { self.trackArtistCredits = trackArtistCredits }
    }

    func refreshExtendedSessionData() async {
        guard isLoggedIn else { return }
        async let account = fetchAccountAttributes()
        async let profile = fetchProfileAttributes()
        async let notifications = fetchUnreadNotificationStatus()
        _ = await (account, profile, notifications)
    }

    func fetchAccountAttributes() async -> SpotifyAccountInfo? {
        let knownHashes = [
            await SpotifyOperationHashRegistry.shared.liveHash(for: "accountAttributes"),
            "24aaa3057b69fa91492de26841ad199bd0b330ca95817b7a4d6715150de01827"
        ].compactMap { $0 }

        for hash in knownHashes {
            do {
                let response: AccountAttributesResponse = try await pathfinderQuery(
                    operationName: "accountAttributes",
                    variables: [:],
                    extensions: ["persistedQuery": ["version": 1, "sha256Hash": hash]],
                    sendAsBody: true,
                    cachePolicy: .fetchIgnoringCacheData,
                    useV2Endpoint: true
                )
                if let attrs = response.data.me?.account {
                    let info = SpotifyAccountInfo(
                        product: attrs.product ?? "unknown",
                        country: attrs.country ?? "",
                        onDemand: attrs.attributes?.onDemand ?? false,
                        catalogue: attrs.attributes?.catalogue ?? "free",
                        ads: attrs.attributes?.ads ?? true
                    )
                    publishExtendedState(accountInfo: info)
                    operationHashes["accountAttributes"] = hash
                    await SpotifyOperationHashRegistry.shared.seed(["accountAttributes": hash])
                    return info
                }
            } catch {
                continue
            }
        }

        if let info = await fetchAccountAttributesViaWebAPI() {
            publishExtendedState(accountInfo: info)
            return info
        }

        print("[SpotifyExtendedAPI] accountAttributes unavailable via Pathfinder and /v1/me")
        return nil
    }

    private func fetchAccountAttributesViaWebAPI() async -> SpotifyAccountInfo? {
        guard let token = currentAccessToken() else { return nil }
        guard let url = URL(string: "https://api.spotify.com/v1/me") else { return nil }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            struct MeResponse: Decodable {
                let product: String?
                let country: String?
            }
            let me = try JSONDecoder().decode(MeResponse.self, from: data)
            let product = (me.product ?? "free").uppercased()
            let isPremium = product == "PREMIUM"
            return SpotifyAccountInfo(
                product: product,
                country: me.country ?? "",
                onDemand: isPremium,
                catalogue: isPremium ? "premium" : "free",
                ads: !isPremium
            )
        } catch {
            print("[SpotifyExtendedAPI] /v1/me account fallback failed: \(error.localizedDescription)")
            return nil
        }
    }

    func fetchDynamicColors(for imageURIs: [String]) async -> [String] {
        guard !imageURIs.isEmpty else { return [] }
        do {
            let response: DynamicColorsResponse = try await pathfinderQuery(
                operationName: "getDynamicColorsByUris",
                variables: ["imageUris": imageURIs]
            )
            return response.data.dynamicColors.compactMap { swatch in
                swatch.dark?.textBase?.hex ?? swatch.light?.textBase?.hex ?? swatch.dark?.backgroundBase?.hex
            }
        } catch {
            print("[SpotifyExtendedAPI] getDynamicColorsByUris failed: \(error.localizedDescription)")
            return []
        }
    }

    func fetchProfileAttributes() async -> String? {
        do {
            let response: ProfileAttributesResponse = try await pathfinderQuery(
                operationName: "profileAttributes",
                variables: [:]
            )
            let profileNode = response.data.me?.profile
            let name = profileNode?.name?.trimmingCharacters(in: .whitespacesAndNewlines)
            let username = profileNode?.username
            await MainActor.run {
                if var profile = self.userProfile {
                    if let name, !name.isEmpty {
                        let existing = profile.profile.displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        if existing.isEmpty {
                            profile.profile.displayName = name
                            self.userProfile = profile
                        }
                    }
                } else if let username, !username.isEmpty {
                    self.userProfile = SpotifyNativeUserProfile(profile: .init(
                        email: nil,
                        gender: nil,
                        birthdate: nil,
                        country: nil,
                        username: username,
                        displayName: name
                    ))
                }
            }
            if let username, !username.isEmpty {
                await fetchProfileFollowerCount(username: username)
            } else if let username = userProfile?.profile.username, !username.isEmpty {
                await fetchProfileFollowerCount(username: username)
            }
            return profileNode?.uri ?? profileNode?.username
        } catch {
            print("[SpotifyExtendedAPI] profileAttributes failed: \(error.localizedDescription)")
            if let username = userProfile?.profile.username, !username.isEmpty {
                await fetchProfileFollowerCount(username: username)
            }
            return nil
        }
    }

    func fetchProfileFollowerCount(username: String) async {
        guard let client = wgSpclientClient ?? spclientClient else { return }
        let encoded = username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? username
        let path = "/user-profile-view/v3/profile/\(encoded)?playlist_limit=0&artist_limit=0&episode_limit=0&market=from_token"
        do {
            let response = try await client.get(path: path)
            guard response.statusCode == 200,
                  let json = try JSONSerialization.jsonObject(with: response.body) as? [String: Any] else { return }

            let count: Int? = {
                if let n = json["followers_count"] as? Int { return n }
                if let n = json["followersCount"] as? Int { return n }
                if let n = (json["followers_count"] as? NSNumber)?.intValue { return n }
                if let followers = json["followers"] as? [String: Any] {
                    if let n = followers["total"] as? Int { return n }
                    if let n = followers["count"] as? Int { return n }
                    if let n = (followers["total"] as? NSNumber)?.intValue { return n }
                }
                if let n = json["total_public_playlists_count"] as? Int, json["followers_count"] == nil {
                    return nil
                }
                return nil
            }()

            await MainActor.run {
                if let count {
                    self.profileFollowerCount = count
                }
            }
        } catch {
            print("[SpotifyExtendedAPI] profile follower fetch failed: \(error.localizedDescription)")
        }
    }

    func fetchRelatedTracks(for trackURI: String, limit: Int = 8) async -> [SpotifyRecommendedTrack] {
        do {
            let response: InternalLinkRecommenderResponse = try await pathfinderQuery(
                operationName: "internalLinkRecommenderTrack",
                variables: ["uri": trackURI, "limit": limit]
            )
            let tracks = response.data.seoRecommendedTrack.items.compactMap { item -> SpotifyRecommendedTrack? in
                guard let data = item.data else { return nil }
                return SpotifyRecommendedTrack(
                    id: data.id ?? SpotifyIDConverter.rawID(from: data.uri),
                    name: data.name,
                    uri: data.uri,
                    duration: data.duration?.totalMilliseconds ?? 0,
                    popularity: nil,
                    artists: data.artists?.items.map {
                        .init(id: $0.id ?? SpotifyIDConverter.rawID(from: $0.uri), name: $0.profile.name)
                    } ?? [],
                    album: .init(
                        id: data.albumOfTrack?.uri
                            ?? data.albumOfTrack?.id.map { $0.hasPrefix("spotify:") ? $0 : "spotify:album:\($0)" }
                            ?? "",
                        name: data.name,
                        imageUrl: data.albumOfTrack?.coverArt?.sources.first?.url
                    )
                )
            }
            await MainActor.run {
                guard self.playerState?.track?.uri == trackURI else { return }
                self.publishExtendedState(relatedTracks: tracks)
            }
            return tracks
        } catch {
            print("[SpotifyExtendedAPI] internalLinkRecommenderTrack failed: \(error.localizedDescription)")
            return []
        }
    }

    func fetchSimilarAlbums(for trackURI: String, limit: Int = 20) async -> [SpotifySimilarAlbum] {
        do {
            let response: SimilarAlbumsResponse = try await pathfinderQuery(
                operationName: "similarAlbumsBasedOnThisTrack",
                variables: ["uri": trackURI, "limit": limit, "albumsOnly": true]
            )
            let albums = response.data.seoRecommendedTrackAlbum.items.compactMap { item -> SpotifySimilarAlbum? in
                guard let data = item.data else { return nil }
                let image = data.coverArt?.sources.max(by: { ($0.width ?? 0) < ($1.width ?? 0) })?.url
                return SpotifySimilarAlbum(
                    id: data.uri,
                    name: data.name,
                    uri: data.uri,
                    artistName: data.artists?.items.first?.profile.name ?? "Unknown",
                    imageURL: image.flatMap(URL.init(string:)),
                    year: data.date?.year
                )
            }
            await MainActor.run {
                guard self.playerState?.track?.uri == trackURI else { return }
                self.publishExtendedState(similarAlbums: albums)
            }
            return albums
        } catch {
            print("[SpotifyExtendedAPI] similarAlbumsBasedOnThisTrack failed: \(error.localizedDescription)")
            return []
        }
    }

    func fetchAlbumTracks(albumURI: String, limit: Int = 50) async -> [SpotifyRecommendedTrack] {
        do {
            let response: AlbumTracksResponse = try await pathfinderQuery(
                operationName: "queryAlbumTracks",
                variables: [
                    "uri": albumURI,
                    "offset": 0,
                    "limit": limit
                ]
            )
            return response.data.albumUnion?.tracksV2?.items.compactMap { item -> SpotifyRecommendedTrack? in
                guard let track = item.track ?? item.data else { return nil }
                let uri = track.uri ?? ""
                guard !uri.isEmpty else { return nil }
                return SpotifyRecommendedTrack(
                    id: SpotifyIDConverter.rawID(from: uri),
                    name: track.name ?? "Track",
                    uri: uri,
                    duration: track.duration?.totalMilliseconds ?? 0,
                    popularity: nil,
                    artists: track.artists?.items.map {
                        .init(id: SpotifyIDConverter.rawID(from: $0.uri ?? ""), name: $0.profile?.name ?? $0.profileName ?? "Artist")
                    } ?? [],
                    album: .init(id: SpotifyIDConverter.rawID(from: albumURI), name: "Album", imageUrl: nil)
                )
            } ?? []
        } catch {
            print("[SpotifyExtendedAPI] queryAlbumTracks failed: \(error.localizedDescription)")
            return []
        }
    }

    func fetchTrackArtists(for trackURI: String) async -> [SpotifyTrackArtistCredit] {
        do {
            let response: TrackArtistsResponse = try await pathfinderQuery(
                operationName: "queryTrackArtists",
                variables: ["trackUri": trackURI]
            )
            let credits = response.data.trackUnion?.artists?.items.compactMap { item -> SpotifyTrackArtistCredit? in
                guard let uri = item.uri ?? item.data?.uri else { return nil }
                let name = item.profile?.name ?? item.data?.profile?.name ?? "Artist"
                return SpotifyTrackArtistCredit(
                    id: uri,
                    uri: uri,
                    name: name,
                    role: item.role ?? item.data?.role
                )
            } ?? []
            publishExtendedState(trackArtistCredits: credits)
            return credits
        } catch {
            print("[SpotifyExtendedAPI] queryTrackArtists failed: \(error.localizedDescription)")
            return []
        }
    }

    func isArtistBanned(_ artistURI: String) async -> Bool {
        let results = await collectionContains(set: "artistban", uris: [artistURI])
        return results.first ?? false
    }

    func fetchExtractedColors(for imageURIs: [String]) async -> [SpotifyExtractedColor] {
        guard !imageURIs.isEmpty else { return [] }
        let dynamic = await fetchDynamicColors(for: imageURIs)
        if !dynamic.isEmpty {
            return dynamic.map { SpotifyExtractedColor(hex: $0, isFallback: false) }
        }
        do {
            let response: ExtractedColorsResponse = try await pathfinderQuery(
                operationName: "fetchExtractedColors",
                variables: ["imageUris": imageURIs],
                sendAsBody: true,
                useV2Endpoint: true
            )
            return response.data.extractedColors.map { $0.colorRaw }
        } catch {
            print("[SpotifyExtendedAPI] fetchExtractedColors failed: \(error.localizedDescription)")
            return []
        }
    }

    func areEntitiesInLibrary(uris: [String]) async -> [Bool] {
        guard !uris.isEmpty else { return [] }
        do {
            let response: LibraryLookupResponse = try await pathfinderQuery(
                operationName: "areEntitiesInLibrary",
                variables: ["uris": uris],
                sendAsBody: true,
                useV2Endpoint: true
            )
            return response.data.lookup.map { $0.data?.saved ?? false }
        } catch {
            print("[SpotifyExtendedAPI] areEntitiesInLibrary failed: \(error.localizedDescription)")
            return Array(repeating: false, count: uris.count)
        }
    }

    func isTrackLiked(uri: String) async -> Bool {
        let contains = await collectionContains(set: "tracks", uris: [uri])
        if let value = contains.first { return value }
        return false
    }

    func searchSuggestions(query: String) async -> [SpotifySearchSuggestion] {
        let variables: [String: Any] = [
            "query": query,
            "limit": 30,
            "numberOfTopResults": 30,
            "offset": 0,
            "includeAuthors": true,
            "includeAlbumPreReleases": true,
            "includeEpisodeContentRatingsV2": true
        ]
        do {
            let response: SpotifySearchSuggestionsResponse = try await pathfinderQuery(
                operationName: "searchSuggestions",
                variables: variables,
                sendAsBody: true,
                cachePolicy: .fetchIgnoringCacheData,
                useV2Endpoint: true
            )
            return response.suggestions
        } catch {
            print("[SpotifyExtendedAPI] searchSuggestions failed: \(error.localizedDescription)")
            return []
        }
    }

    func searchTopResults(query: String) async -> SpotifySearchTopResults {
        let variables: [String: Any] = [
            "query": query,
            "limit": 50,
            "offset": 0,
            "numberOfTopResults": 50,
            "includeArtistHasConcertsField": false,
            "includeAudiobooks": true,
            "includeAuthors": true,
            "includePreReleases": true,
            "includeAlbumPreReleases": true,
            "includeEpisodeContentRatingsV2": true,
            "sectionFilters": ["GENERIC", "VIDEO_CONTENT"]
        ]
        do {
            let response: SpotifySearchTopResultsResponse = try await pathfinderQuery(
                operationName: "searchTopResultsList",
                variables: variables,
                sendAsBody: true,
                cachePolicy: .fetchIgnoringCacheData,
                useV2Endpoint: true
            )
            return response.parsed
        } catch {
            print("[SpotifyExtendedAPI] searchTopResultsList failed: \(error.localizedDescription)")
            if let track = await searchForTrack(title: query, artist: "") {
                return SpotifySearchTopResults(
                    tracks: [
                        SpotifySearchTrack(
                            id: track.id,
                            name: track.name,
                            uri: track.uri,
                            artists: track.artists.map(\.name).joined(separator: ", "),
                            imageURL: track.imageURL
                        )
                    ],
                    artists: [],
                    albums: [],
                    playlists: []
                )
            }
            return .empty
        }
    }

    func fetchArtistOverview(uri: String) async -> SpotifyArtistOverview? {
        do {
            let response: ArtistOverviewResponse = try await pathfinderQuery(
                operationName: "queryArtistOverview",
                variables: [
                    "uri": uri,
                    "locale": "",
                    "preReleaseV2": true
                ],
                sendAsBody: true,
                cachePolicy: .fetchIgnoringCacheData,
                useV2Endpoint: true
            )
            return response.overview
        } catch {
            print("[SpotifyExtendedAPI] queryArtistOverview failed: \(error.localizedDescription)")
            return nil
        }
    }

    func trackHasLyrics(trackId: String) async -> Bool? {
        guard let meta = await fetchTrackMetadata(trackId: trackId) else { return nil }
        return meta.hasLyrics
    }

    func fetchHomeSections() async -> [SpotifyHomeSection] {
        let timeZone = TimeZone.current.identifier
        let variables: [String: Any] = [
            "homeEndUserIntegration": "INTEGRATION_WEB_PLAYER",
            "timeZone": timeZone,
            "sp_t": UUID().uuidString,
            "facet": "",
            "sectionItemsLimit": 20,
            "includeEpisodeContentRatingsV2": true
        ]
        do {
            let response: SpotifyHomeResponse = try await pathfinderQuery(
                operationName: "home",
                variables: variables,
                sendAsBody: true,
                cachePolicy: .fetchIgnoringCacheData,
                useV2Endpoint: true
            )
            let greeting = response.data?.home?.greeting?.transformedLabel
                ?? response.data?.home?.greeting?.translatedBaseText
            let sections = response.data?.home?.sectionContainer?.sections?.items ?? []
            let mapped = sections.compactMap { SpotifyHomeSection(from: $0) }
            await MainActor.run {
                self.homeGreeting = greeting
                self.homeSections = mapped
                if let first = mapped.first, !first.items.isEmpty {
                    self.recentlyPlayedItems = first.items.map {
                        SpotifyRecentlyPlayedItem(
                            id: $0.id,
                            name: $0.name,
                            uri: $0.uri,
                            imageURL: $0.imageURL,
                            ownerName: $0.subtitle ?? ""
                        )
                    }
                }
            }
            return mapped
        } catch {
            print("[SpotifyExtendedAPI] home fetch failed: \(error.localizedDescription)")
            return []
        }
    }

    func decorateContextTracks(uris: [String]) async -> [SpotifyDecoratedTrack] {
        guard !uris.isEmpty else { return [] }
        do {
            let response: DecorateTracksResponse = try await pathfinderQuery(
                operationName: "decorateContextTracks",
                variables: ["uris": uris],
                sendAsBody: true,
                useV2Endpoint: true
            )
            return response.data.tracks
        } catch {
            print("[SpotifyExtendedAPI] decorateContextTracks failed: \(error.localizedDescription)")
            return []
        }
    }

    func fetchPlaylistPermissions(uri: String) async -> SpotifyPlaylistPermissions? {
        do {
            let response: PlaylistPermissionsResponse = try await pathfinderQuery(
                operationName: "playlistPermissions",
                variables: ["uri": uri],
                sendAsBody: true,
                useV2Endpoint: true
            )
            return response.data.playlistV2
        } catch {
            print("[SpotifyExtendedAPI] playlistPermissions failed: \(error.localizedDescription)")
            return nil
        }
    }

    func checkSmartShuffleAvailable(uri: String) async -> Bool {
        do {
            let response: SmartShuffleResponse = try await pathfinderQuery(
                operationName: "smartShuffle",
                variables: ["uris": [uri]],
                sendAsBody: true,
                useV2Endpoint: true
            )
            let available = response.data.lookup.first?.data?.smartShuffle?.available ?? false
            publishExtendedState(smartShuffleAvailable: available)
            return available
        } catch {
            print("[SpotifyExtendedAPI] smartShuffle failed: \(error.localizedDescription)")
            return false
        }
    }

    func fetchRecentlyPlayedEntities(uris: [String]) async -> [SpotifyRecentlyPlayedItem] {
        guard !uris.isEmpty else { return [] }
        do {
            let response: RecentlyPlayedResponse = try await pathfinderQuery(
                operationName: "fetchEntitiesForRecentlyPlayed",
                variables: ["uris": uris],
                sendAsBody: true,
                useV2Endpoint: true
            )
            let items = response.data.lookup.compactMap { wrapper -> SpotifyRecentlyPlayedItem? in
                guard let playlist = wrapper.data, let uri = playlist.uri else { return nil }
                let imageURL = playlist.images?.items.first?.sources.first.flatMap { URL(string: $0.url) }
                return SpotifyRecentlyPlayedItem(
                    id: uri,
                    name: playlist.name ?? "Playlist",
                    uri: uri,
                    imageURL: imageURL,
                    ownerName: playlist.ownerV2?.data?.name ?? "Spotify"
                )
            }
            publishExtendedState(recentlyPlayed: items)
            return items
        } catch {
            print("[SpotifyExtendedAPI] fetchEntitiesForRecentlyPlayed failed: \(error.localizedDescription)")
            return []
        }
    }

    func fetchCanvas(for trackURI: String) async -> SpotifyCanvasInfo? {
        do {
            let response: CanvasResponse = try await pathfinderQuery(
                operationName: "canvas",
                variables: ["trackUri": trackURI],
                sendAsBody: true,
                useV2Endpoint: true
            )
            guard let canvas = response.data.trackUnion.canvas else {
                await MainActor.run {
                    if self.playerState?.track?.uri == trackURI {
                        self.currentCanvas = nil
                    }
                }
                return nil
            }
            let info = SpotifyCanvasInfo(url: canvas.url, type: canvas.type)
            guard info.isPlayableVideo else {
                print("[SpotifyExtendedAPI] canvas returned non-video URL, ignoring: \(canvas.url)")
                await MainActor.run {
                    if self.playerState?.track?.uri == trackURI {
                        self.currentCanvas = nil
                    }
                }
                return nil
            }
            await MainActor.run {
                guard self.playerState?.track?.uri == trackURI else { return }
                self.publishExtendedState(canvas: info)
            }
            return info
        } catch {
            print("[SpotifyExtendedAPI] canvas failed: \(error.localizedDescription)")
            return nil
        }
    }

    func fetchArtistConcerts(artistURI: String, trackURI: String) async -> [SpotifyArtistConcert] {
        async let npvTask: (SpotifyArtistProfile?, [SpotifyArtistConcert]) = fetchNpvArtist(artistURI: artistURI, trackURI: trackURI)
        async let geoTask = fetchGeoConcerts(artistURI: artistURI)

        let (profile, npvConcerts) = await npvTask
        let geoConcerts = await geoTask
        let concerts = geoConcerts.isEmpty ? npvConcerts : geoConcerts
        if let profile {
            publishExtendedState(concerts: concerts, nowPlayingArtist: profile)
        } else {
            publishExtendedState(concerts: concerts)
        }
        return concerts
    }

    private func fetchNpvArtist(artistURI: String, trackURI: String) async -> (SpotifyArtistProfile?, [SpotifyArtistConcert]) {
        let variables: [String: Any] = [
            "artistUri": artistURI,
            "trackUri": trackURI,
            "contributorsLimit": 10,
            "contributorsOffset": 0,
            "enableRelatedVideos": true,
            "enableRelatedAudioTracks": false
        ]
        do {
            let response: NpvArtistResponse = try await pathfinderQuery(
                operationName: "queryNpvArtist",
                variables: variables
            )
            let union = response.data.artistUnion
            let header = union.headerImage?.data?.sources.max(by: { ($0.maxWidth ?? 0) < ($1.maxWidth ?? 0) })?.url
            let avatar = union.visuals?.avatarImage?.sources?.first?.url
            let profile = SpotifyArtistProfile(
                uri: union.uri ?? artistURI,
                name: union.profile?.name ?? "Artist",
                biography: union.profile?.biography?.text ?? "",
                monthlyListeners: union.stats?.monthlyListeners,
                followers: union.stats?.followers,
                headerImageURL: header.flatMap(URL.init(string:)),
                avatarURL: avatar.flatMap(URL.init(string:)),
                isVerified: union.onPlatformReputationTrait?.verification?.isVerified ?? false,
                topCities: union.stats?.topCities?.items.prefix(3).map(\.city) ?? [],
                merch: union.goods?.merch?.items?.compactMap { item -> SpotifyArtistMerch? in
                    guard let name = item.name, let uri = item.uri else { return nil }
                    return SpotifyArtistMerch(
                        id: uri,
                        name: name,
                        uri: uri,
                        imageURL: item.imageURL.flatMap(URL.init(string:)),
                        price: item.price
                    )
                } ?? []
            )
            let concerts = union.goods?.concerts?.items.compactMap { item -> SpotifyArtistConcert? in
                guard let data = item.data else { return nil }
                return SpotifyArtistConcert(
                    uri: data.uri,
                    title: data.title,
                    startDateIsoString: data.startDateIsoString,
                    city: data.location.city ?? "",
                    venue: data.location.name ?? ""
                )
            } ?? []
            return (profile, concerts)
        } catch {
            print("[SpotifyExtendedAPI] queryNpvArtist failed: \(error.localizedDescription)")
            return (nil, [])
        }
    }

    private func fetchGeoConcerts(artistURI: String) async -> [SpotifyArtistConcert] {
        let geoHash: String
        if let resolved = await fetchUserGeoHash() {
            geoHash = resolved
        } else {
            geoHash = "dr5reg"
        }
        do {
            let response: ArtistConcertsResponse = try await pathfinderQuery(
                operationName: "ArtistConcerts",
                variables: [
                    "artistUri": artistURI,
                    "geoHash": geoHash,
                    "includeNearby": true
                ]
            )
            return response.data.artistUnion?.nearby?.concerts?.items.compactMap { item -> SpotifyArtistConcert? in
                guard let data = item.data ?? item.concert else { return nil }
                return SpotifyArtistConcert(
                    uri: data.uri ?? UUID().uuidString,
                    title: data.title ?? data.name ?? "Concert",
                    startDateIsoString: data.startDateIsoString ?? data.date ?? "",
                    city: data.location?.city ?? data.venue?.city ?? "",
                    venue: data.location?.name ?? data.venue?.name ?? ""
                )
            } ?? []
        } catch {
            print("[SpotifyExtendedAPI] ArtistConcerts failed: \(error.localizedDescription)")
            return []
        }
    }

    private func fetchUserGeoHash() async -> String? {
        do {
            let response: UserLocationResponse = try await pathfinderQuery(
                operationName: "userLocation",
                variables: [:]
            )
            if let hash = response.data.me?.userLocation?.geoHash, !hash.isEmpty {
                return hash
            }
            if let lat = response.data.me?.userLocation?.latitude,
               let lon = response.data.me?.userLocation?.longitude {
                return SpotifyGeohash.encode(latitude: lat, longitude: lon)
            }
        } catch {
            print("[SpotifyExtendedAPI] userLocation failed: \(error.localizedDescription)")
        }
        return nil
    }

    @discardableResult
    func applyPlaylistEnhance(playlistId: String) async -> Bool {
        await MainActor.run { isEnhanceLoading = true }
        defer { Task { @MainActor in self.isEnhanceLoading = false } }
        return await loadPlaylistUsingSignals(playlistId: playlistId)
    }

    func playSmartShuffle(playlistURI: String) async -> PlaybackResult {
        let playlistId = SpotifyIDConverter.rawID(from: playlistURI)
        _ = await applyPlaylistEnhance(playlistId: playlistId)
        let result = await connectPlay(
            trackUri: "",
            contextUri: playlistURI,
            trackUid: nil,
            trackIndex: 0
        )
        guard case .success = result else { return result }
        await sendConnectCommand(endpoint: "set_options", extra: ["shuffling_context": true])
        await MainActor.run { self.isSmartShuffleActive = true }
        return .success
    }

    func extendPlaylist(uri: String, skipTrackIDs: [String] = [], numResults: Int = 20) async -> [SpotifyRecommendedTrack] {
        guard let client = wgSpclientClient else { return [] }
        let normalizedSkipIDs = skipTrackIDs.map { SpotifyIDConverter.rawID(from: $0) }
        let payload: [String: Any] = [
            "playlistURI": uri.hasPrefix("spotify:") ? uri : "spotify:playlist:\(uri)",
            "trackSkipIDs": normalizedSkipIDs,
            "numResults": numResults
        ]
        do {
            let response = try await client.post(path: "/playlistextender/extendp/", jsonBody: payload)
            let decoded = try JSONDecoder().decode(PlaylistExtenderResponse.self, from: response.body)
            publishExtendedState(recommendations: decoded.recommendedTracks)
            return decoded.recommendedTracks
        } catch {
            print("[SpotifyExtendedAPI] playlistextender failed: \(error.localizedDescription)")
            return []
        }
    }

    func fetchUnreadNotificationStatus() async -> Bool {
        guard let client = wgSpclientClient else { return false }
        do {
            let response = try await client.get(
                path: "/gander/v2/GetUserHasUnreadNotification",
                queryItems: [URLQueryItem(name: "postFix", value: "a")]
            )
            let decoded = try JSONDecoder().decode(NotificationResponse.self, from: response.body)
            publishExtendedState(hasUnreadNotifications: decoded.userHasUnreadNotification)
            return decoded.userHasUnreadNotification
        } catch {
            return false
        }
    }

    func fetchTrackMetadata(trackId: String) async -> SpotifyTrackMetadata? {
        let rawId = SpotifyIDConverter.rawID(from: trackId)
        let extended = await fetchTrackMetadataViaExtended(trackId: rawId)
        if let extended, !extended.allAudioFiles.isEmpty {
            return extended
        }

        guard let client = wgSpclientClient else { return extended }
        let gid = SpotifyIDConverter.gid(fromBase62: rawId) ?? rawId
        do {
            let response = try await client.get(
                path: "/metadata/4/track/\(gid)",
                queryItems: [URLQueryItem(name: "market", value: "from_token")],
                additionalHeaders: [
                    "Accept": "application/json",
                    "App-Platform": "WebPlayer"
                ]
            )
            guard !response.body.isEmpty else {
                print("[SpotifyExtendedAPI] track metadata empty for \(rawId)")
                return extended
            }
            if response.body.first != UInt8(ascii: "{") {
                let snippet = String(data: response.body.prefix(80), encoding: .utf8)
                    ?? "binary(\(response.body.count))"
                print("[SpotifyExtendedAPI] track metadata not JSON for \(rawId): \(snippet)")
                return extended
            }
            let decoder = JSONDecoder()
            do {
                let legacy = try decoder.decode(SpotifyTrackMetadata.self, from: response.body)
                if legacy.allAudioFiles.isEmpty {
                    print("[SpotifyExtendedAPI] legacy metadata has 0 files for \(rawId); extended files=\(extended?.allAudioFiles.count ?? -1)")
                    return extended ?? legacy
                }
                return legacy
            } catch {
                let snippet = String(data: response.body.prefix(240), encoding: .utf8)
                    ?? "<binary \(response.body.count) bytes>"
                print("[SpotifyExtendedAPI] track metadata decode failed for \(rawId) (gid=\(gid)): \(error)\nSnippet: \(snippet)")
                return extended
            }
        } catch {
            print("[SpotifyExtendedAPI] track metadata failed for \(rawId) (gid=\(gid)): \(error.localizedDescription)")
            return extended
        }
    }

    private func fetchTrackMetadataViaExtended(trackId: String) async -> SpotifyTrackMetadata? {
        guard let client = wgSpclientClient else { return nil }
        let uri = SpotifyIDConverter.uri(type: "track", from: trackId)

        var query = Data()
        query.append(SpotifyProtoWire.writeVarintField(field: 1, 10))

        var entity = Data()
        entity.append(SpotifyProtoWire.writeString(field: 1, uri))
        entity.append(SpotifyProtoWire.writeMessage(field: 2, query))

        var header = Data()
        if let country = accountInfo?.country, !country.isEmpty {
            header.append(SpotifyProtoWire.writeString(field: 1, country))
        }
        if let catalogue = accountInfo?.catalogue, !catalogue.isEmpty {
            header.append(SpotifyProtoWire.writeString(field: 2, catalogue))
        }

        var request = Data()
        if !header.isEmpty {
            request.append(SpotifyProtoWire.writeMessage(field: 1, header))
        }
        request.append(SpotifyProtoWire.writeMessage(field: 2, entity))

        var headers: [String: String] = [
            "Content-Type": "application/x-protobuf",
            "Accept": "application/x-protobuf",
            "app-platform": "Desktop"
        ]

        do {
            let response = try await client.post(
                path: "/extended-metadata/v0/extended-metadata",
                bodyData: request,
                additionalHeaders: headers
            )
            guard response.statusCode == 200, !response.body.isEmpty else {
                print("[SpotifyExtendedAPI] extended-metadata HTTP \(response.statusCode) for \(uri) (\(response.body.count) bytes)")
                return nil
            }
            guard let parsed = SpotifyExtendedMetadataParser.parseTrack(fromBatchedResponse: response.body) else {
                print("[SpotifyExtendedAPI] extended-metadata parse yielded no track for \(uri)")
                return nil
            }
            print("[SpotifyExtendedAPI] extended-metadata files=\(parsed.allAudioFiles.count) for \(uri)")
            return parsed
        } catch {
            print("[SpotifyExtendedAPI] extended-metadata failed for \(uri): \(error.localizedDescription)")
            return nil
        }
    }

    func fetchPlaylistRootlist() async -> [SpotifyPlaylist] {
        guard let client = wgSpclientClient,
              let username = userProfile?.profile.username else { return [] }
        do {
            let response = try await client.get(
                path: "/playlist/v2/user/\(username)/rootlist",
                queryItems: [
                    URLQueryItem(name: "decorate", value: "revision,length,attributes,timestamp,owner,capabilities"),
                    URLQueryItem(name: "bustCache", value: String(Int(Date().timeIntervalSince1970 * 1000)))
                ]
            )
            let decoded = try JSONDecoder().decode(PlaylistRootlistResponse.self, from: response.body)
            return decoded.contents.items.compactMap { item in
                guard let uri = item.uri else { return nil }
                let id = uri.components(separatedBy: ":").last ?? uri
                let imageURL = item.attributes?.picture ?? ""
                let fallbackName = uri.components(separatedBy: ":").last?.uppercased() ?? "Playlist"
                return SpotifyPlaylist(
                    id: id,
                    name: item.name ?? fallbackName,
                    uri: uri,
                    images: [SpotifyImage(url: imageURL)],
                    owner: SpotifyUserSimple(id: username, displayName: userProfile?.profile.displayName ?? username, images: nil),
                    collaborators: nil
                )
            }
        } catch {
            print("[SpotifyExtendedAPI] rootlist failed: \(error.localizedDescription)")
            return []
        }
    }

    func hydrateTracksBatch(_ sparseTracks: [PlayerState.Track]) async -> [PlayerState.Track] {
        guard !sparseTracks.isEmpty else { return sparseTracks }
        var result = sparseTracks
        let uris = sparseTracks.map(\.uri)
        let chunks = uris.chunked(into: 50)

        for (chunkIndex, chunk) in chunks.enumerated() {
            let decorated = await decorateContextTracks(uris: chunk)
            let startIndex = chunkIndex * 50
            for (offset, decoratedTrack) in decorated.enumerated() {
                let index = startIndex + offset
                guard index < result.count else { break }
                result[index] = PlayerState.Track(hydrating: result[index], withDecorated: decoratedTrack)
            }
        }
        return result
    }
}

// MARK: - Response Wrappers

private struct AccountAttributesResponse: Decodable {
    let data: DataNode
    struct DataNode: Decodable {
        let me: MeNode?
    }
    struct MeNode: Decodable {
        let account: AccountNode?
        let profile: ProfileAttributesResponse.ProfileNode?
    }
    struct AccountNode: Decodable {
        let product: String?
        let country: String?
        let attributes: AttrNode?
    }
    struct AttrNode: Decodable {
        let onDemand: Bool?
        let catalogue: String?
        let ads: Bool?
    }
}

private struct ExtractedColorsResponse: Decodable {
    let data: DataNode
    struct DataNode: Decodable {
        let extractedColors: [ColorNode]
    }
    struct ColorNode: Decodable {
        let colorRaw: SpotifyExtractedColor
    }
}

private struct LibraryLookupResponse: Decodable {
    let data: DataNode
    struct DataNode: Decodable {
        let lookup: [LookupItem]
    }
    struct LookupItem: Decodable {
        let data: SavedNode?
    }
    struct SavedNode: Decodable {
        let saved: Bool?
    }
}

private struct DecorateTracksResponse: Decodable {
    let data: DataNode
    struct DataNode: Decodable {
        let tracks: [SpotifyDecoratedTrack]
    }
}

private struct PlaylistPermissionsResponse: Decodable {
    let data: DataNode
    struct DataNode: Decodable {
        let playlistV2: SpotifyPlaylistPermissions
    }
}

private struct SmartShuffleResponse: Decodable {
    let data: DataNode
    struct DataNode: Decodable {
        let lookup: [LookupItem]
    }
    struct LookupItem: Decodable {
        let data: PlaylistData?
    }
    struct PlaylistData: Decodable {
        let smartShuffle: SmartShuffleNode?
    }
    struct SmartShuffleNode: Decodable {
        let available: Bool?
    }
}

private struct RecentlyPlayedResponse: Decodable {
    let data: DataNode
    struct DataNode: Decodable {
        let lookup: [LookupWrapper]
    }
    struct LookupWrapper: Decodable {
        let data: PlaylistData?
    }
    struct PlaylistData: Decodable {
        let name: String?
        let uri: String?
        let images: ImageCollection?
        let ownerV2: OwnerWrapper?
    }
    struct ImageCollection: Decodable {
        let items: [ImageItem]
    }
    struct ImageItem: Decodable {
        let sources: [ImageSource]
    }
    struct ImageSource: Decodable {
        let url: String
    }
    struct OwnerWrapper: Decodable {
        let data: OwnerData?
    }
    struct OwnerData: Decodable {
        let name: String?
    }
}

private struct CanvasResponse: Decodable {
    let data: DataNode
    struct DataNode: Decodable {
        let trackUnion: TrackNode
    }
    struct TrackNode: Decodable {
        let canvas: CanvasNode?
    }
    struct CanvasNode: Decodable {
        let url: String
        let type: String?
    }
}

private struct NpvArtistResponse: Decodable {
    let data: DataNode
    struct DataNode: Decodable { let artistUnion: ArtistNode }
    struct ArtistNode: Decodable {
        let uri: String?
        let profile: ProfileNode?
        let stats: StatsNode?
        let goods: GoodsNode?
        let headerImage: HeaderImage?
        let visuals: VisualsNode?
        let onPlatformReputationTrait: ReputationNode?
    }
    struct ProfileNode: Decodable {
        let name: String?
        let biography: BiographyNode?
    }
    struct BiographyNode: Decodable { let text: String? }
    struct StatsNode: Decodable {
        let followers: Int?
        let monthlyListeners: Int?
        let topCities: TopCities?
    }
    struct TopCities: Decodable { let items: [TopCity] }
    struct TopCity: Decodable { let city: String }
    struct GoodsNode: Decodable {
        let concerts: ConcertCollection?
        let merch: MerchCollection?
    }
    struct ConcertCollection: Decodable { let items: [ConcertItem] }
    struct ConcertItem: Decodable { let data: ConcertData? }
    struct ConcertData: Decodable {
        let uri: String
        let title: String
        let startDateIsoString: String
        let location: LocationNode
    }
    struct LocationNode: Decodable {
        let city: String?
        let name: String?
    }
    struct MerchCollection: Decodable { let items: [MerchItem]? }
    struct MerchItem: Decodable {
        let name: String?
        let uri: String?
        let price: String?
        let imageURL: String?

        enum CodingKeys: String, CodingKey {
            case name, uri, price
            case imageURL = "imageUrl"
            case image
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            name = try container.decodeIfPresent(String.self, forKey: .name)
            uri = try container.decodeIfPresent(String.self, forKey: .uri)
            price = try container.decodeIfPresent(String.self, forKey: .price)
            if let direct = try container.decodeIfPresent(String.self, forKey: .imageURL) {
                imageURL = direct
            } else if let nested = try? container.decodeIfPresent(MerchImage.self, forKey: .image) {
                imageURL = nested.url ?? nested.sources?.first?.url
            } else {
                imageURL = nil
            }
        }

        struct MerchImage: Decodable {
            let url: String?
            let sources: [SimpleSource]?
        }
    }
    struct HeaderImage: Decodable { let data: ImageData? }
    struct ImageData: Decodable { let sources: [ImageSource] }
    struct ImageSource: Decodable {
        let url: String
        let maxWidth: Int?
        let maxHeight: Int?
    }
    struct VisualsNode: Decodable { let avatarImage: AvatarImage? }
    struct AvatarImage: Decodable { let sources: [SimpleSource]? }
    struct SimpleSource: Decodable { let url: String }
    struct ReputationNode: Decodable { let verification: Verification? }
    struct Verification: Decodable {
        let isRegistered: Bool?
        let isVerified: Bool?
    }
}

private struct ArtistConcertsResponse: Decodable {
    let data: DataNode
    struct DataNode: Decodable { let artistUnion: ArtistNode? }
    struct ArtistNode: Decodable { let nearby: NearbyNode? }
    struct NearbyNode: Decodable { let concerts: ConcertCollection? }
    struct ConcertCollection: Decodable { let items: [ConcertItem] }
    struct ConcertItem: Decodable {
        let data: ConcertData?
        let concert: ConcertData?
    }
    struct ConcertData: Decodable {
        let uri: String?
        let title: String?
        let name: String?
        let startDateIsoString: String?
        let date: String?
        let location: LocationNode?
        let venue: LocationNode?
    }
    struct LocationNode: Decodable {
        let city: String?
        let name: String?
    }
}

private struct UserLocationResponse: Decodable {
    let data: DataNode
    struct DataNode: Decodable { let me: MeNode? }
    struct MeNode: Decodable { let userLocation: LocationNode? }
    struct LocationNode: Decodable {
        let geoHash: String?
        let latitude: Double?
        let longitude: Double?
    }
}

private struct DynamicColorsResponse: Decodable {
    let data: DataNode
    struct DataNode: Decodable { let dynamicColors: [Swatch] }
    struct Swatch: Decodable {
        let bestFit: String?
        let dark: Palette?
        let light: Palette?
    }
    struct Palette: Decodable {
        let textBase: HexColor?
        let backgroundBase: HexColor?
    }
    struct HexColor: Decodable { let hex: String? }
}

private struct ProfileAttributesResponse: Decodable {
    let data: DataNode
    struct DataNode: Decodable {
        let me: MeNode?
        let extractedColors: [ExtractedColorsResponse.ColorNode]?
    }
    struct MeNode: Decodable { let profile: ProfileNode? }
    struct ProfileNode: Decodable {
        let uri: String?
        let username: String?
        let name: String?
    }
}

private struct InternalLinkRecommenderResponse: Decodable {
    let data: DataNode
    struct DataNode: Decodable { let seoRecommendedTrack: TrackCollection }
    struct TrackCollection: Decodable { let items: [Item] }
    struct Item: Decodable { let data: TrackData? }
    struct TrackData: Decodable {
        let id: String?
        let uri: String
        let name: String
        let duration: DurationNode?
        let artists: ArtistItems?
        let albumOfTrack: AlbumNode?
    }
    struct DurationNode: Decodable { let totalMilliseconds: Int? }
    struct ArtistItems: Decodable { let items: [ArtistItem] }
    struct ArtistItem: Decodable {
        let id: String?
        let uri: String
        let profile: Profile
        struct Profile: Decodable { let name: String }
    }
    struct AlbumNode: Decodable {
        let id: String?
        let uri: String?
        let coverArt: CoverArt?
    }
    struct CoverArt: Decodable { let sources: [Source] }
    struct Source: Decodable {
        let url: String
        let width: Int?
        let height: Int?
    }
}

private struct SimilarAlbumsResponse: Decodable {
    let data: DataNode
    struct DataNode: Decodable { let seoRecommendedTrackAlbum: AlbumCollection }
    struct AlbumCollection: Decodable { let items: [Item] }
    struct Item: Decodable { let data: AlbumData? }
    struct AlbumData: Decodable {
        let name: String
        let uri: String
        let artists: ArtistItems?
        let coverArt: CoverArt?
        let date: DateNode?
    }
    struct ArtistItems: Decodable { let items: [ArtistItem] }
    struct ArtistItem: Decodable {
        let uri: String?
        let profile: Profile
        struct Profile: Decodable { let name: String }
    }
    struct CoverArt: Decodable { let sources: [Source] }
    struct Source: Decodable {
        let url: String
        let width: Int?
        let height: Int?
    }
    struct DateNode: Decodable { let year: Int? }
}

private struct TrackArtistsResponse: Decodable {
    let data: DataNode
    struct DataNode: Decodable { let trackUnion: TrackNode? }
    struct TrackNode: Decodable { let artists: ArtistCollection? }
    struct ArtistCollection: Decodable { let items: [ArtistItem] }
    struct ArtistItem: Decodable {
        let uri: String?
        let role: String?
        let profile: Profile?
        let data: NestedArtist?

        struct Profile: Decodable { let name: String? }
        struct NestedArtist: Decodable {
            let uri: String?
            let role: String?
            let profile: Profile?
        }
    }
}

private struct AlbumTracksResponse: Decodable {
    let data: DataNode
    struct DataNode: Decodable { let albumUnion: AlbumNode? }
    struct AlbumNode: Decodable { let tracksV2: TracksNode? }
    struct TracksNode: Decodable { let items: [Item] }
    struct Item: Decodable {
        let track: TrackData?
        let data: TrackData?
    }
    struct TrackData: Decodable {
        let uri: String?
        let name: String?
        let duration: Duration?
        let artists: Artists?
        struct Duration: Decodable { let totalMilliseconds: Int? }
        struct Artists: Decodable { let items: [Artist] }
        struct Artist: Decodable {
            let uri: String?
            let profile: Profile?
            let profileName: String?
            struct Profile: Decodable { let name: String? }
        }
    }
}

private struct PlaylistExtenderResponse: Decodable {
    let recommendedTracks: [SpotifyRecommendedTrack]
}

private struct NotificationResponse: Decodable {
    let userHasUnreadNotification: Bool
}

struct SpotifyTrackMetadata: Decodable {
    let gid: String?
    let name: String
    let popularity: Int?
    let duration: Int?
    let canonicalUri: String?
    let hasLyrics: Bool?
    let album: AlbumNode?
    let artist: [ArtistNode]?
    let file: [AudioFile]?
    let alternative: [AlternativeNode]?

    enum CodingKeys: String, CodingKey {
        case gid, name, popularity, duration, album, artist, file, alternative
        case canonicalUri = "canonical_uri"
        case hasLyrics = "has_lyrics"
    }

    init(
        gid: String? = nil,
        name: String,
        popularity: Int? = nil,
        duration: Int? = nil,
        canonicalUri: String? = nil,
        hasLyrics: Bool? = nil,
        album: AlbumNode? = nil,
        artist: [ArtistNode]? = nil,
        file: [AudioFile]? = nil,
        alternative: [AlternativeNode]? = nil
    ) {
        self.gid = gid
        self.name = name
        self.popularity = popularity
        self.duration = duration
        self.canonicalUri = canonicalUri
        self.hasLyrics = hasLyrics
        self.album = album
        self.artist = artist
        self.file = file
        self.alternative = alternative
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        gid = try container.decodeIfPresent(String.self, forKey: .gid)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Unknown"
        popularity = Self.decodeFlexibleInt(container, forKey: .popularity)
        duration = Self.decodeFlexibleInt(container, forKey: .duration)
        canonicalUri = try container.decodeIfPresent(String.self, forKey: .canonicalUri)
        hasLyrics = try container.decodeIfPresent(Bool.self, forKey: .hasLyrics)
        album = try container.decodeIfPresent(AlbumNode.self, forKey: .album)
        artist = try container.decodeIfPresent([ArtistNode].self, forKey: .artist)
        file = try container.decodeIfPresent([AudioFile].self, forKey: .file)
        alternative = try container.decodeIfPresent([AlternativeNode].self, forKey: .alternative)
    }

    private static func decodeFlexibleInt(_ container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) -> Int? {
        if let v = try? container.decodeIfPresent(Int.self, forKey: key) { return v }
        if let s = try? container.decodeIfPresent(String.self, forKey: key), let v = Int(s) { return v }
        if let d = try? container.decodeIfPresent(Double.self, forKey: key) { return Int(d) }
        return nil
    }

    struct AudioFile: Decodable {
        let fileId: String?
        let format: Int?

        enum CodingKeys: String, CodingKey {
            case fileId = "file_id"
            case format
        }

        init(fileId: String?, format: Int?) {
            self.fileId = fileId
            self.format = format
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            fileId = try container.decodeIfPresent(String.self, forKey: .fileId)
            if let intFormat = try container.decodeIfPresent(Int.self, forKey: .format) {
                format = intFormat
            } else if let stringFormat = try container.decodeIfPresent(String.self, forKey: .format) {
                format = Self.parseFormat(stringFormat)
            } else {
                format = nil
            }
        }

        static func parseFormatPublic(_ raw: String) -> Int? { parseFormat(raw) }

        private static func parseFormat(_ raw: String) -> Int? {
            if let n = Int(raw) { return n }
            switch raw.uppercased() {
            case "OGG_VORBIS_96": return 0
            case "OGG_VORBIS_160": return 1
            case "OGG_VORBIS_320": return 2
            case "MP3_256": return 3
            case "MP3_320": return 4
            case "MP3_160": return 5
            case "MP3_96": return 6
            case "MP3_160_ENC": return 7
            case "AAC_24", "MP4_128": return 10
            case "AAC_48", "MP4_128_DUAL": return 12
            case "AAC_160", "MP4_256": return 11
            case "AAC_320", "MP4_256_DUAL": return 13
            default: return nil
            }
        }

        var file_id: String? { fileId }
        var formatCode: Int? { format }
    }

    struct AlternativeNode: Decodable {
        let gid: String?
        let file: [AudioFile]?
        init(gid: String? = nil, file: [AudioFile]?) {
            self.gid = gid
            self.file = file
        }
    }

    struct AlbumNode: Decodable {
        let gid: String?
        let name: String
        let coverGroup: CoverGroup?

        enum CodingKeys: String, CodingKey {
            case gid, name
            case coverGroup = "cover_group"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            gid = try container.decodeIfPresent(String.self, forKey: .gid)
            name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Album"
            coverGroup = try container.decodeIfPresent(CoverGroup.self, forKey: .coverGroup)
        }

        struct CoverGroup: Decodable {
            let image: [CoverImage]?
        }

        struct CoverImage: Decodable {
            let fileId: String?
            let size: String?
            let width: Int?
            let height: Int?

            enum CodingKeys: String, CodingKey {
                case size, width, height
                case fileId = "file_id"
            }

            var imageURL: URL? {
                guard let fileId else { return nil }
                return URL(string: "https://i.scdn.co/image/\(fileId)")
            }
        }

        var bestImageURL: URL? {
            let images = coverGroup?.image ?? []
            return images.max(by: { ($0.width ?? 0) < ($1.width ?? 0) })?.imageURL ?? images.first?.imageURL
        }
    }

    struct ArtistNode: Decodable {
        let gid: String?
        let name: String

        init(gid: String?, name: String) {
            self.gid = gid
            self.name = name
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            gid = try container.decodeIfPresent(String.self, forKey: .gid)
            name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Artist"
        }

        enum CodingKeys: String, CodingKey { case gid, name }
    }

    var artistNames: String {
        (artist ?? []).map(\.name).joined(separator: ", ")
    }

    var allAudioFiles: [AudioFile] {
        var files = file ?? []
        for alt in alternative ?? [] {
            files.append(contentsOf: alt.file ?? [])
        }
        return files
    }
}

private struct PlaylistRootlistResponse: Decodable {
    let contents: ContentsNode
    struct ContentsNode: Decodable {
        let items: [RootItem]
    }
    struct RootItem: Decodable {
        let uri: String?
        let name: String?
        let attributes: AttributesNode?
    }
    struct AttributesNode: Decodable {
        let picture: String?
    }
}

// MARK: - Track Hydration from Decorated Data

extension PlayerState.Track {
    init(hydrating sparseTrack: PlayerState.Track, withDecorated details: SpotifyDecoratedTrack) {
        self.uri = sparseTrack.uri
        self.uid = sparseTrack.uid
        var updatedMetadata = sparseTrack.metadata ?? Metadata(
            title: nil, albumTitle: nil, artistName: nil, artistUri: nil,
            imageUrl: nil, imageSmallUrl: nil, imageLargeUrl: nil, imageXlargeUrl: nil,
            contextUri: nil, hidden: nil
        )
        updatedMetadata.title = details.name
        updatedMetadata.albumTitle = details.albumOfTrack.name
        updatedMetadata.artistName = details.artistName
        updatedMetadata.artistUri = details.artists.items.first?.uri
        updatedMetadata.imageUrl = details.imageURL?.absoluteString
        self.metadata = updatedMetadata
    }
}

private extension SpotifyAccountInfo {
    init(product: String, country: String, onDemand: Bool, catalogue: String, ads: Bool) {
        self.product = product
        self.country = country
        self.onDemand = onDemand
        self.catalogue = catalogue
        self.ads = ads
    }
}

// MARK: - Search models

struct SpotifySearchSuggestion: Identifiable, Hashable {
    var id: String { uri ?? text }
    let text: String
    let uri: String?
}

struct SpotifySearchTrack: Identifiable, Hashable {
    let id: String
    let name: String
    let uri: String
    let artists: String
    let imageURL: URL?
}

struct SpotifySearchArtist: Identifiable, Hashable {
    let id: String
    let name: String
    let uri: String
    let imageURL: URL?
}

struct SpotifySearchAlbum: Identifiable, Hashable {
    let id: String
    let name: String
    let uri: String
    let artistName: String
    let imageURL: URL?
}

struct SpotifySearchPlaylistHit: Identifiable, Hashable {
    let id: String
    let name: String
    let uri: String
    let ownerName: String?
    let imageURL: URL?
}

struct SpotifySearchTopResults: Hashable {
    var tracks: [SpotifySearchTrack]
    var artists: [SpotifySearchArtist]
    var albums: [SpotifySearchAlbum]
    var playlists: [SpotifySearchPlaylistHit]

    var isEmpty: Bool { tracks.isEmpty && artists.isEmpty && albums.isEmpty && playlists.isEmpty }
    static let empty = SpotifySearchTopResults(tracks: [], artists: [], albums: [], playlists: [])
}

struct SpotifySearchSuggestionsResponse: Decodable {
    let data: DataNode?

    struct DataNode: Decodable {
        let searchV2: SearchV2?
    }
    struct SearchV2: Decodable {
        let topResultsV2: TopResults?
    }
    struct TopResults: Decodable {
        let itemsV2: [Item]?
    }
    struct Item: Decodable {
        let item: Wrapper?
    }
    struct Wrapper: Decodable {
        let data: SuggestionData?
    }
    struct SuggestionData: Decodable {
        let text: String?
        let uri: String?
    }

    var suggestions: [SpotifySearchSuggestion] {
        (data?.searchV2?.topResultsV2?.itemsV2 ?? []).compactMap { row in
            guard let text = row.item?.data?.text, !text.isEmpty else { return nil }
            return SpotifySearchSuggestion(text: text, uri: row.item?.data?.uri)
        }
    }
}

struct SpotifySearchTopResultsResponse: Decodable {
    let data: DataNode?

    struct DataNode: Decodable { let searchV2: SearchV2? }
    struct SearchV2: Decodable {
        let tracksV2: PagedTracks?
        let artists: PagedArtists?
        let albumsV2: PagedAlbums?
        let playlists: PagedPlaylists?
        let topResultsV2: TopBucket?
    }
    struct PagedTracks: Decodable { let items: [TrackItem]? }
    struct TrackItem: Decodable { let item: TrackWrapper? }
    struct TrackWrapper: Decodable { let data: TrackData? }
    struct TrackData: Decodable {
        let uri: String?
        let name: String?
        let artists: ArtistBag?
        let albumOfTrack: AlbumOf?
    }
    struct ArtistBag: Decodable { let items: [ArtistRow]? }
    struct ArtistRow: Decodable { let profile: NameOnly?; let uri: String? }
    struct NameOnly: Decodable { let name: String? }
    struct AlbumOf: Decodable { let coverArt: Cover?; let name: String? }
    struct Cover: Decodable { let sources: [Src]? }
    struct Src: Decodable { let url: String? }

    struct PagedArtists: Decodable { let items: [ArtistItem]? }
    struct ArtistItem: Decodable { let data: ArtistData? }
    struct ArtistData: Decodable {
        let uri: String?
        let profile: NameOnly?
        let visuals: Visuals?
    }
    struct Visuals: Decodable { let avatarImage: Cover? }

    struct PagedAlbums: Decodable { let items: [AlbumItem]? }
    struct AlbumItem: Decodable { let data: AlbumData? }
    struct AlbumData: Decodable {
        let uri: String?
        let name: String?
        let artists: ArtistBag?
        let coverArt: Cover?
    }

    struct PagedPlaylists: Decodable { let items: [PlaylistItem]? }
    struct PlaylistItem: Decodable { let data: PlaylistData? }
    struct PlaylistData: Decodable {
        let uri: String?
        let name: String?
        let ownerV2: Owner?
        let images: SpotifyHomeResponse.FlexibleHomeImage?
    }
    struct Owner: Decodable { let data: NameOnly? }

    struct TopBucket: Decodable { let itemsV2: [TopItem]? }
    struct TopItem: Decodable { let item: TopWrapper? }
    struct TopWrapper: Decodable {
        let data: FlexibleEntity?
    }
    struct FlexibleEntity: Decodable {
        let __typename: String?
        let uri: String?
        let name: String?
        let profile: NameOnly?
        let artists: ArtistBag?
        let coverArt: Cover?
        let visuals: Visuals?
        let ownerV2: Owner?
        let images: SpotifyHomeResponse.FlexibleHomeImage?
        let albumOfTrack: AlbumOf?
    }

    var parsed: SpotifySearchTopResults {
        let search = data?.searchV2
        var tracks: [SpotifySearchTrack] = (search?.tracksV2?.items ?? []).compactMap { item in
            guard let d = item.item?.data, let uri = d.uri, let name = d.name else { return nil }
            return SpotifySearchTrack(
                id: uri,
                name: name,
                uri: uri,
                artists: (d.artists?.items ?? []).compactMap { $0.profile?.name }.joined(separator: ", "),
                imageURL: URL(string: d.albumOfTrack?.coverArt?.sources?.first?.url ?? "")
            )
        }
        var artists: [SpotifySearchArtist] = (search?.artists?.items ?? []).compactMap { item in
            guard let d = item.data, let uri = d.uri, let name = d.profile?.name else { return nil }
            return SpotifySearchArtist(
                id: uri,
                name: name,
                uri: uri,
                imageURL: URL(string: d.visuals?.avatarImage?.sources?.first?.url ?? "")
            )
        }
        var albums: [SpotifySearchAlbum] = (search?.albumsV2?.items ?? []).compactMap { item in
            guard let d = item.data, let uri = d.uri, let name = d.name else { return nil }
            return SpotifySearchAlbum(
                id: uri,
                name: name,
                uri: uri,
                artistName: (d.artists?.items ?? []).compactMap { $0.profile?.name }.joined(separator: ", "),
                imageURL: URL(string: d.coverArt?.sources?.first?.url ?? "")
            )
        }
        var playlists: [SpotifySearchPlaylistHit] = (search?.playlists?.items ?? []).compactMap { item in
            guard let d = item.data, let uri = d.uri, let name = d.name else { return nil }
            return SpotifySearchPlaylistHit(
                id: uri,
                name: name,
                uri: uri,
                ownerName: d.ownerV2?.data?.name,
                imageURL: d.images?.url
            )
        }

        for top in search?.topResultsV2?.itemsV2 ?? [] {
            guard let d = top.item?.data, let uri = d.uri else { continue }
            let typename = (d.__typename ?? "").lowercased()
            if typename.contains("track"), !tracks.contains(where: { $0.uri == uri }) {
                tracks.append(
                    SpotifySearchTrack(
                        id: uri,
                        name: d.name ?? "Track",
                        uri: uri,
                        artists: (d.artists?.items ?? []).compactMap { $0.profile?.name }.joined(separator: ", "),
                        imageURL: URL(string: d.albumOfTrack?.coverArt?.sources?.first?.url ?? d.coverArt?.sources?.first?.url ?? "")
                    )
                )
            } else if typename.contains("artist"), !artists.contains(where: { $0.uri == uri }) {
                artists.append(
                    SpotifySearchArtist(
                        id: uri,
                        name: d.profile?.name ?? d.name ?? "Artist",
                        uri: uri,
                        imageURL: URL(string: d.visuals?.avatarImage?.sources?.first?.url ?? "")
                    )
                )
            } else if typename.contains("album"), !albums.contains(where: { $0.uri == uri }) {
                albums.append(
                    SpotifySearchAlbum(
                        id: uri,
                        name: d.name ?? "Album",
                        uri: uri,
                        artistName: (d.artists?.items ?? []).compactMap { $0.profile?.name }.joined(separator: ", "),
                        imageURL: URL(string: d.coverArt?.sources?.first?.url ?? "")
                    )
                )
            } else if typename.contains("playlist"), !playlists.contains(where: { $0.uri == uri }) {
                playlists.append(
                    SpotifySearchPlaylistHit(
                        id: uri,
                        name: d.name ?? "Playlist",
                        uri: uri,
                        ownerName: d.ownerV2?.data?.name,
                        imageURL: d.images?.url
                    )
                )
            }
        }

        return SpotifySearchTopResults(tracks: tracks, artists: artists, albums: albums, playlists: playlists)
    }
}

// MARK: - Artist overview

struct SpotifyArtistOverview {
    let profile: SpotifyArtistProfile
    let topTracks: [SpotifySearchTrack]
    let albums: [SpotifySearchAlbum]
    let singles: [SpotifySearchAlbum]
    let featuringPlaylists: [SpotifySearchPlaylistHit]
    let relatedArtists: [SpotifySearchArtist]
    let concerts: [SpotifyArtistConcert]
}

struct ArtistOverviewResponse: Decodable {
    let data: DataNode?
    struct DataNode: Decodable { let artistUnion: ArtistUnion? }

    struct ArtistUnion: Decodable {
        let uri: String?
        let profile: Profile?
        let visuals: Visuals?
        let stats: Stats?
        let discography: Discography?
        let relatedContent: Related?
        let goods: Goods?
        let onPlatformReputationTrait: Reputation?

        struct Profile: Decodable {
            let name: String?
            let biography: Bio?
            struct Bio: Decodable { let text: String? }
        }
        struct Visuals: Decodable {
            let avatarImage: Img?
            let headerImage: Img?
            struct Img: Decodable { let sources: [Src]?; let extractedColors: Extracted? }
            struct Src: Decodable { let url: String? }
            struct Extracted: Decodable { let colorDark: Hex?; struct Hex: Decodable { let hex: String? } }
        }
        struct Stats: Decodable {
            let monthlyListeners: Int?
            let followers: Int?
            let topCities: TopCities?
            struct TopCities: Decodable { let items: [City]? }
            struct City: Decodable { let city: String? }
        }
        struct Reputation: Decodable {
            let verification: Verification?
            struct Verification: Decodable { let isVerified: Bool? }
        }

        struct Discography: Decodable {
            let topTracks: TopTracks?
            let albums: Releases?
            let singles: Releases?
            struct TopTracks: Decodable { let items: [TopItem]? }
            struct TopItem: Decodable { let track: TrackWrap?; let uid: String? }
            struct TrackWrap: Decodable { let uri: String?; let name: String?; let playcount: String?; let album: AlbumWrap?; let artists: Artists? }
            struct AlbumWrap: Decodable { let name: String?; let coverArt: Cover? }
            struct Cover: Decodable { let sources: [Src]?; struct Src: Decodable { let url: String? } }
            struct Artists: Decodable { let items: [AItem]?; struct AItem: Decodable { let profile: P?; struct P: Decodable { let name: String? } } }
            struct Releases: Decodable { let items: [ReleaseItem]? }
            struct ReleaseItem: Decodable {
                let uri: String?
                let name: String?
                let coverArt: Cover?
                let releases: Nested?
                struct Nested: Decodable { let items: [Release]? }
            }
            struct Release: Decodable { let uri: String?; let name: String?; let coverArt: Cover? }
        }

        struct Related: Decodable {
            let featuringV2: Featuring?
            let relatedArtists: RelatedArtists?
            struct Featuring: Decodable { let items: [FeatItem]? }
            struct FeatItem: Decodable {
                let playlist: PlaylistData?
                struct PlaylistData: Decodable {
                    let uri: String?
                    let name: String?
                    let images: SpotifyHomeResponse.FlexibleHomeImage?
                    let ownerV2: Owner?
                }
                struct Owner: Decodable {
                    let data: Name?
                    struct Name: Decodable { let name: String? }
                }
            }
            struct RelatedArtists: Decodable { let items: [RelArtist]? }
            struct RelArtist: Decodable {
                let uri: String?
                let profile: Name?
                let visuals: Visuals?
                struct Name: Decodable { let name: String? }
            }
        }

        struct Goods: Decodable {
            let merch: MerchList?
            let concerts: ConcertList?
            struct MerchList: Decodable { let items: [MerchItem]? }
            struct MerchItem: Decodable {
                let name: String?
                let uri: String?
                let imageURL: String?
                let price: String?

                enum CodingKeys: String, CodingKey {
                    case name, uri, price
                    case imageURL = "imageUrl"
                }

                init(from decoder: Decoder) throws {
                    let container = try decoder.container(keyedBy: CodingKeys.self)
                    name = try container.decodeIfPresent(String.self, forKey: .name)
                    uri = try container.decodeIfPresent(String.self, forKey: .uri)
                    price = try container.decodeIfPresent(String.self, forKey: .price)
                    if let direct = try container.decodeIfPresent(String.self, forKey: .imageURL) {
                        imageURL = direct
                    } else {
                        imageURL = nil
                    }
                }
            }
            struct ConcertList: Decodable { let items: [ConcertItem]? }
            struct ConcertItem: Decodable { let data: ConcertData? }
            struct ConcertData: Decodable {
                let uri: String?
                let title: String?
                let startDateIsoString: String?
                let location: Loc?
                struct Loc: Decodable { let city: String?; let name: String? }
            }
        }
    }

    var overview: SpotifyArtistOverview? {
        guard let union = data?.artistUnion else { return nil }
        let uri = union.uri ?? ""
        let name = union.profile?.name ?? "Artist"
        let bio = union.profile?.biography?.text ?? ""
        let avatar = union.visuals?.avatarImage?.sources?.first?.url.flatMap(URL.init(string:))
        let header = union.visuals?.headerImage?.sources?.first?.url.flatMap(URL.init(string:))
        let cities = (union.stats?.topCities?.items ?? []).compactMap(\.city)
        let merch: [SpotifyArtistMerch] = (union.goods?.merch?.items ?? []).compactMap { item in
            guard let mName = item.name, let mURI = item.uri else { return nil }
            return SpotifyArtistMerch(
                id: mURI,
                name: mName,
                uri: mURI,
                imageURL: item.imageURL.flatMap(URL.init(string:)),
                price: item.price
            )
        }
        let profile = SpotifyArtistProfile(
            uri: uri,
            name: name,
            biography: bio,
            monthlyListeners: union.stats?.monthlyListeners,
            followers: union.stats?.followers,
            headerImageURL: header,
            avatarURL: avatar,
            isVerified: union.onPlatformReputationTrait?.verification?.isVerified ?? false,
            topCities: cities,
            merch: merch
        )
        let topTracks: [SpotifySearchTrack] = (union.discography?.topTracks?.items ?? []).compactMap { item in
            guard let t = item.track, let tURI = t.uri, let tName = t.name else { return nil }
            return SpotifySearchTrack(
                id: tURI,
                name: tName,
                uri: tURI,
                artists: (t.artists?.items ?? []).compactMap { $0.profile?.name }.joined(separator: ", "),
                imageURL: t.album?.coverArt?.sources?.first?.url.flatMap(URL.init(string:))
            )
        }
        func releases(from block: ArtistUnion.Discography.Releases?) -> [SpotifySearchAlbum] {
            (block?.items ?? []).flatMap { item -> [ArtistUnion.Discography.Release] in
                if let nested = item.releases?.items, !nested.isEmpty { return nested }
                if let uri = item.uri, let name = item.name {
                    return [ArtistUnion.Discography.Release(uri: uri, name: name, coverArt: item.coverArt)]
                }
                return []
            }.compactMap { rel in
                guard let rURI = rel.uri, let rName = rel.name else { return nil }
                return SpotifySearchAlbum(
                    id: rURI,
                    name: rName,
                    uri: rURI,
                    artistName: name,
                    imageURL: rel.coverArt?.sources?.first?.url.flatMap(URL.init(string:))
                )
            }
        }
        let featuring: [SpotifySearchPlaylistHit] = (union.relatedContent?.featuringV2?.items ?? []).compactMap { item in
            guard let p = item.playlist, let pURI = p.uri, let pName = p.name else { return nil }
            return SpotifySearchPlaylistHit(
                id: pURI,
                name: pName,
                uri: pURI,
                ownerName: p.ownerV2?.data?.name,
                imageURL: p.images?.url
            )
        }
        let related: [SpotifySearchArtist] = (union.relatedContent?.relatedArtists?.items ?? []).compactMap { item in
            guard let aURI = item.uri, let aName = item.profile?.name else { return nil }
            return SpotifySearchArtist(
                id: aURI,
                name: aName,
                uri: aURI,
                imageURL: item.visuals?.avatarImage?.sources?.first?.url.flatMap(URL.init(string:))
            )
        }
        let concerts: [SpotifyArtistConcert] = (union.goods?.concerts?.items ?? []).compactMap { item in
            guard let data = item.data else { return nil }
            return SpotifyArtistConcert(
                uri: data.uri ?? UUID().uuidString,
                title: data.title ?? "Concert",
                startDateIsoString: data.startDateIsoString ?? "",
                city: data.location?.city ?? "",
                venue: data.location?.name ?? ""
            )
        }
        return SpotifyArtistOverview(
            profile: profile,
            topTracks: topTracks,
            albums: releases(from: union.discography?.albums),
            singles: releases(from: union.discography?.singles),
            featuringPlaylists: featuring,
            relatedArtists: related,
            concerts: concerts
        )
    }
}

// MARK: - Consolidated from SpotifyLoginChallenge.swift

struct LoginChallengeDetails: Identifiable {
    let id = UUID()
}