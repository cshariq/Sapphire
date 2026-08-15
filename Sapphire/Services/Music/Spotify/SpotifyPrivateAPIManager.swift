//
//  SpotifyPrivateAPIManager.swift
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
    /// Follower count for the signed-in Spotify user (hub profile pill).
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

    // Extended API state (pathfinder + spclient)
    @Published var accountInfo: SpotifyAccountInfo?
    @Published var currentCanvas: SpotifyCanvasInfo?
    @Published var artistConcerts: [SpotifyArtistConcert] = []
    @Published var playlistRecommendations: [SpotifyRecommendedTrack] = []
    @Published var recentlyPlayedItems: [SpotifyRecentlyPlayedItem] = []
    @Published var homeSections: [SpotifyHomeSection] = []
    @Published var homeGreeting: String?
    /// Shown when the user tries to play on Sapphire or Connect bounces off it.
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
    /// True when Sapphire started Connect playback on an external speaker.
    @Published var isConnectStreamingSession: Bool = false
    @Published var isSmartShuffleActive: Bool = false
    private var deviceTransferNoticeClearTask: Task<Void, Never>?

    /// Sapphire is actively driving playback on another Connect device (not itself).
    var isControllingConnectPlayback: Bool {
        guard isConnectStreamingSession,
              let active = activePlayerDeviceID,
              let selfId = controllerDeviceID else { return false }
        return active != selfId
    }

    /// Legacy alias for Connect-control badge callers.
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

    func currentAccessToken() -> String? { accessToken }
    private var clientToken: String?
    internal var clientVersion: String?

    var sessionDeviceID: String?
    var controllerDeviceID: String?

    private var jsPackURL: String?
    private var operationHashes: [String: String] = [:]
    private var playlistTrackUIDByNormalizedURI: [String: String] = [:]
    private let commonUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
    private let sessionUserDefaultsKey = "spotAPISessionCookies"
    private let controllerDeviceIDKey = "spotAPIControllerDeviceID"
    private let externalRefreshTokenKey = "spotAPIExternalRefreshToken"
    private let externalClientIDKey = "spotAPIExternalClientID"
    private let externalClientSecretKey = "spotAPIExternalClientSecret"

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
        /// Only when Spotify is the default player (or music widget) and a saved session exists.
        case automatic
        /// User opened music UI, settings, or Spotify became active.
        case onDemand
        /// Wake / network reconnect after a prior bootstrap.
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

    /// Restores a saved Spotify session without blocking app launch.
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

    /// True when local desktop Spotify is the active Connect player (same Mac).
    private var isLocalSpotifyActivePlayer: Bool {
        guard SpotifyAppleScriptManager.shared.isAppRunning() else { return false }
        guard let active = activePlayerDeviceID else {
            // No Connect device yet — still treat local app as eligible if it's running.
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
        openSpotifyClient = CustomTLSClient(host: "open.spotify.com", userAgent: commonUserAgent, cookieManager: cookieManager)
        spclientClient = CustomTLSClient(host: "gue1-spclient.spotify.com", userAgent: commonUserAgent, cookieManager: cookieManager)
        apiPartnerClient = CustomTLSClient(host: "api-partner.spotify.com", userAgent: commonUserAgent, cookieManager: cookieManager)
        clientTokenClient = CustomTLSClient(host: "clienttoken.spotify.com", userAgent: commonUserAgent, cookieManager: cookieManager)
        wwwSpotifyClient = CustomTLSClient(host: "www.spotify.com", userAgent: commonUserAgent, cookieManager: cookieManager)
        wgSpclientClient = CustomTLSClient(host: "spclient.wg.spotify.com", userAgent: commonUserAgent, cookieManager: cookieManager)
    }

    func login() {
        hasRequestedSessionBootstrap = true
        // Always start from a clean slate so revoked cookies (e.g. after "Sign out everywhere")
        // cannot make the webview think we're already signed in.
        Task { @MainActor in
            await self.prepareFreshLogin()
            self.loginChallenge = LoginChallengeDetails()
        }
    }

    /// Wipes CookieManager, persisted session, and WKWebView Spotify data before presenting login.
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
            // Replace any residual cookies rather than merging with a dead session.
            await cookieManager.clear()
            await cookieManager.setCookies(cookies)
            await saveSession()
            reestablishSession()
        }
    }

    /// Adopts access / refresh tokens obtained through an external OAuth flow (Connected Accounts)
    /// so the private API manager can use them without a cookie-based web login.
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

        Task { @MainActor in
            await apiCache.clear()
            await cookieManager.clear()
            await clearSpotifyBrowserData()
        }
        UserDefaults.standard.removeObject(forKey: sessionUserDefaultsKey)
    }

    /// Clears WKWebView Spotify cookies/cache. Called on sign-out and before fresh login.
    /// MUST run on MainActor — WKWebsiteDataStore.default() is not thread-safe.
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

    /// Drops persisted cookies after an auth failure so the next attempt requires a real login.
    /// - Parameter clearWebViewData: Pass false during background session restoration to avoid
    ///   initialising WKWebsiteDataStore off the main thread, which triggers FSFindFolder and hangs.
    private func invalidateStoredSession(reason: String, clearWebViewData: Bool = false) async {
        await cookieManager.clear()
        UserDefaults.standard.removeObject(forKey: sessionUserDefaultsKey)
        if clearWebViewData {
            await clearSpotifyBrowserData()
        }
        print("[SpotifyPrivateAPIManager] Invalidated stored session: \(reason)")
    }

    private func _internalLogout() {
        resetActiveSession()
        reestablishTask?.cancel()
        reestablishTask = nil

        openSpotifyClient = nil; spclientClient = nil; apiPartnerClient = nil; clientTokenClient = nil; wwwSpotifyClient = nil; wgSpclientClient = nil
        accessToken = nil; clientToken = nil; activePlayerDeviceID = nil; controllerDeviceID = nil; sessionDeviceID = nil
        jsPackURL = nil; clientVersion = nil; operationHashes = [:]; playlistTrackUIDByNormalizedURI = [:]; playlistTrackIndexByUID = [:]

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
        resetActiveSession()

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
            let isAuthFailure =
                message.localizedCaseInsensitiveContains("authentication")
                || message.localizedCaseInsensitiveContains("session verification")
                || message.localizedCaseInsensitiveContains("sp_t cookie")
                || message.localizedCaseInsensitiveContains("access token")

            resetActiveSession()
            openSpotifyClient = nil; spclientClient = nil; apiPartnerClient = nil
            clientTokenClient = nil; wwwSpotifyClient = nil; wgSpclientClient = nil
            accessToken = nil; clientToken = nil; clientVersion = nil
            isLoggedIn = false

            if isAuthFailure {
                await invalidateStoredSession(reason: message)
                print("[SpotifyPrivateAPIManager] Failed to re-establish session: \(message). Stored cookies cleared — sign in again.")
            } else {
                print("[SpotifyPrivateAPIManager] Failed to re-establish session: \(message). In-memory state cleared; cookies kept for retry.")
            }
        }
    }

    func requestSessionReestablishment(from webSocketManager: WebSocketManager) {
        guard self.webSocketManager === webSocketManager else { return }
        reestablishSession()
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
                    // Keep playback on the existing speaker. Sapphire is a controller only —
                    // transferring onto ourselves breaks Connect (no local Widevine decode).
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

            // Library, home, and extended profile data load lazily when the music hub opens.
            guard self.activeSessionAttemptID == attemptID else { return }
        } catch {
            guard self.activeSessionAttemptID == attemptID else { return }
            print("[SpotifyPrivateAPIManager] Error in final initialization flow: \(error.localizedDescription)")
            // Keep cookies / browser data so the next reconnect can succeed without re-login.
            self.isLoggedIn = false
        }
    }

    private func resetActiveSession() {
        queueHydrationTask?.cancel()
        queueHydrationTask = nil
        queueRefreshTask?.cancel()
        queueRefreshTask = nil
        libraryFetchTask?.cancel()
        libraryFetchTask = nil
        isLoggedIn = false
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

        // Only soft-relaunch when Spotify desktop is playing on this Mac.
        guard isLocalSpotifyActivePlayer else { return }

        isSkippingAd = true
        lastAdSkipAttemptAt = Date()
        defer { isSkippingAd = false }

        // Capture the next real track + context before we kill the desktop app.
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

    /// Wait for the local Spotify Connect device after relaunch, then start playback via API (not AppleScript play).
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
            guard SpotifyAppleScriptManager.shared.isAppRunning() else { continue }

            try? await refreshPlayerAndDeviceState()

            let localID = devices.first(where: { $0.deviceId == preferredDeviceID })?.deviceId
                ?? localSpotifyDesktopDeviceID()
            guard let localID else { continue }

            // Prefer explicit Connect play of the upcoming content track.
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

            // Fallback: transfer to local desktop + Connect resume (no system/AppleScript play).
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

    /// Entry point for MediaRemote advertisement flags (local Spotify only).
    func skipAdIfNeededFromMediaRemote(isAdvertisement: Bool) async {
        guard isAdvertisement else { return }
        await skipAd()
    }

    func searchForTrack(title: String, artist: String) async -> SpotifyTrack? {
        let query = "\(title) \(artist)"
        let variables: [String: Any] = ["searchTerm": query, "offset": 0, "limit": 5, "numberOfTopResults": 1, "includeAudiobooks": false]
        do {
            let response: NativeSearchResponse = try await pathfinderQuery(operationName: "searchDesktop", variables: variables)
            if let bestMatch = response.data?.searchV2?.tracksV2?.items?.first?.itemV2.data { return SpotifyTrack(from: bestMatch) }
            return nil
        } catch {
            print("[SpotifyPrivateAPIManager] Error searching for track: \(error.localizedDescription)")
            return nil
        }
    }

    func fetchTrackDetails(trackId: String) async -> SpotifyTrackDetailsResponse.TrackUnion? {
        let normalizedTrackId: String = {
            if trackId.hasPrefix("spotify:track:") { return String(trackId.dropFirst("spotify:track:".count)) }
            return trackId
        }()
        do {
            let response: SpotifyTrackDetailsResponse = try await pathfinderQuery(
                operationName: "getTrack",
                variables: [
                    "uri": "spotify:track:\(normalizedTrackId)",
                    "includeVideoAssociationItems": false
                ],
                sendAsBody: true,
                useV2Endpoint: true
            )
            return response.data.trackUnion
        } catch {
            print("[SpotifyPrivateAPIManager] Pathfinder getTrack failed, trying decorate/metadata: \(error.localizedDescription)")
            let uri = "spotify:track:\(normalizedTrackId)"
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

            guard let metadata = await fetchTrackMetadata(trackId: normalizedTrackId) else { return nil }
            let coverSources: [SpotifyTrackDetailsResponse.ImageSource] = {
                guard let url = metadata.album?.bestImageURL?.absoluteString else { return [] }
                return [.init(url: url, width: nil, height: nil)]
            }()
            let artists = ArtistCollection(items: (metadata.artist ?? []).map {
                ArtistItem(uri: $0.gid.map { "spotify:artist:\($0)" } ?? "", profile: .init(name: $0.name))
            })
            return SpotifyTrackDetailsResponse.TrackUnion(
                uri: metadata.canonicalUri ?? "spotify:track:\(normalizedTrackId)",
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

            // Hydrate only the first page — further pages hydrate as they load.
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

    /// Loads the next page of playlist tracks (on-demand). Preserves Spotify's native playlist order.
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

                // Publish initial batch immediately so UI starts populating instantly
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

    /// Fills title/artist/album/artwork for sparse playlist rows (signals fallback or partial GraphQL).
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
        // Prefer Collection REST (Liked Songs set) — matches Web Player /collection/v2/add.
        if await collectionMutate(path: "/collection/v2/add", set: "tracks", uris: [trackURI]) {
            return true
        }
        do {
            let _: EmptyResponse = try await pathfinderQuery(operationName: "addToLibrary", variables: ["uris": [trackURI]], sendAsBody: true)
            return true
        } catch {
            print("[SpotifyPrivateAPIManager] Error liking track: \(error.localizedDescription)")
            return false
        }
    }

    func unlikeTrack(trackURI: String) async -> Bool {
        if await collectionMutate(path: "/collection/v2/remove", set: "tracks", uris: [trackURI]) {
            return true
        }
        do {
            let _: EmptyResponse = try await pathfinderQuery(operationName: "removeFromLibrary", variables: ["uris": [trackURI]], sendAsBody: true)
            return true
        } catch {
            print("[SpotifyPrivateAPIManager] Error unliking track: \(error.localizedDescription)")
            return false
        }
    }

    /// Liked Songs / collection mutation via spclient Collection service.
    private func collectionMutate(path: String, set: String, uris: [String]) async -> Bool {
        guard let client = wgSpclientClient, let username = userProfile?.profile.username, !uris.isEmpty else { return false }
        let payload: [String: Any] = [
            "username": username,
            "set": set,
            "items": uris.map { ["uri": $0] }
        ]
        do {
            _ = try await client.post(path: path, jsonBody: payload)
            return true
        } catch {
            print("[SpotifyPrivateAPIManager] \(path) failed: \(error.localizedDescription)")
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
        // Sapphire is a hidden controller only — never accept transfers onto ourselves.
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
        guard let openSpotifyClient = openSpotifyClient else { throw SpotAPIError.authenticationFailed("Open Spotify client not initialized.") }
        let openSpotifyResponse = try await openSpotifyClient.get(path: "/")
        guard let openSpotifyHtml = String(data: openSpotifyResponse.body, encoding: .utf8) else { throw SpotAPIError.authenticationFailed("Could not parse open.spotify.com HTML.") }
        let jsPackPatterns = [ #"https:\/\/open\.spotifycdn\.com\/cdn\/build\/web-player\/web-player\.[0-9a-f]+\.js"#, #"https:\/\/open-exp\.spotifycdn\.com\/cdn\/build\/web-player\/web-player\.[0-9a-f]+\.js"# ]
        for pattern in jsPackPatterns { if let range = openSpotifyHtml.range(of: pattern, options: .regularExpression) { self.jsPackURL = String(openSpotifyHtml[range]); break } }
        guard let jsPackURL = self.jsPackURL else { throw SpotAPIError.missingData("jsPackURL not found.") }

        guard let mainJsUrl = URL(string: jsPackURL) else { throw SpotAPIError.urlConstructionFailed(jsPackURL) }

        let (mainJsData, _) = try await URLSession.shared.data(from: mainJsUrl)

        let (processedHashes, clientVersion) = try await Task.detached(priority: .userInitiated) { () -> ([String: String], String?) in
            guard let mainJsContent = String(data: mainJsData, encoding: .utf8) else {
                throw SpotAPIError.authenticationFailed("Could not parse main js_pack content.")
            }

            func extractOperationHashes(from content: String) throws -> [String: String] {
                let regex = try NSRegularExpression(pattern: #"\"([A-Za-z0-9_]+)\",\"(?:query|mutation)\",\"([a-f0-9]{64})\""#)
                let range = NSRange(location: 0, length: content.utf16.count)
                var hashes: [String: String] = [:]

                for match in regex.matches(in: content, options: [], range: range) {
                    guard
                        let operationRange = Range(match.range(at: 1), in: content),
                        let hashRange = Range(match.range(at: 2), in: content)
                    else {
                        continue
                    }

                    hashes[String(content[operationRange])] = String(content[hashRange])
                }

                return hashes
            }

            func fetchAndAppendExtraJs(content: String, xpuiName: String) async throws -> String {
                let searchString = ":\"\(xpuiName)\""; guard let range = content.range(of: searchString) else { return "" }
                let prefix = String(content[..<range.lowerBound]); guard let routeNum = prefix.components(separatedBy: ",").last else { return "" }
                let hashPattern = try Regex("\(routeNum):\"([a-f0-9]+)\""); guard let match = content.firstMatch(of: hashPattern) else { return "" }
                let routeHash = String(match.output[1].substring!)
                let extraJsUrlString = "https://open.spotifycdn.com/cdn/build/web-player/\(xpuiName).\(routeHash).js"; guard let extraJsUrl = URL(string: extraJsUrlString) else { return "" }
                let (extraJsData, _) = try await URLSession.shared.data(from: extraJsUrl)
                return String(data: extraJsData, encoding: .utf8) ?? ""
            }

            var discoveredHashes = try extractOperationHashes(from: mainJsContent)

            for xpuiName in ["xpui-routes-search", "xpui-routes-track-v2", "xpui-routes-collection"] {
                let extraContent = try await fetchAndAppendExtraJs(content: mainJsContent, xpuiName: xpuiName)
                guard !extraContent.isEmpty else { continue }
                let extraHashes = try extractOperationHashes(from: extraContent)
                discoveredHashes.merge(extraHashes) { current, _ in current }
            }

            var version: String? = nil
            let components = mainJsContent.components(separatedBy: "clientVersion:\""); if components.count > 1, let versionPart = components.last, let foundVersion = versionPart.components(separatedBy: "\"").first { version = foundVersion }

            return (discoveredHashes, version)
        }.value

        var mergedHashes = Self.knownPathfinderHashes
        mergedHashes.merge(processedHashes) { _, discovered in discovered }
        self.operationHashes = mergedHashes
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
        let path = "/v1/clienttoken"
        let body: [String: Any] = [
            "client_data": [
                "client_version": self.clientVersion ?? "1.2.95.452.g5c9bdf32",
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
            let snippet = String(data: response.body.prefix(200), encoding: .utf8) ?? "<empty \(response.body.count) bytes>"
            throw SpotAPIError.apiError("clienttoken HTTP \(response.statusCode): \(snippet)")
        }
        let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(ClientTokenResponse.self, from: response.body)
     }

    private func performDeviceRegistration(connectionId: String) async throws {
        guard let spclient = spclientClient else { throw SpotAPIError.authenticationFailed("SPClient not ready.") }
        guard let controllerDeviceID = self.controllerDeviceID else { throw SpotAPIError.missingData("Controller Device ID is not set.") }

        let deletePath = "/track-playback/v1/devices/\(controllerDeviceID)"; do { _ = try await spclient.delete(path: deletePath) } catch { }

        // Hidden Connect controller — Sapphire never plays catalog audio itself.
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
            // Empty supported_types prevents other Spotify apps from transferring onto us.
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
            // Telemetry is best-effort.
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

    /// Known Automatic Persisted Query hashes captured from the Web Player (api-partner pathfinder).
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
        "fetchExtractedColors": "36e90fcaea00d47c695fce31874efeb2519b97d4cd0ee1abfb4f8dc9348596ea",
        "getDynamicColorsByUris": "f0f112945d6d745bd8ff790317bbf8d310036da75df33130490e9d6dc96c59d9",
        "getDynamicColors": "f0f112945d6d745bd8ff790317bbf8d310036da75df33130490e9d6dc96c59d9",
        "accountAttributes": "8ea75f2a2e357219328570ef35ec2d9c4db6089076908f59c6eb62348b225b55",
        "profileAttributes": "08ffb4730af3746e04a8301396f20875dbbce10c75243803091a9274eacc8ac0",
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
        "home": "76243c78b0e20ecdbe41b794dec8cbe73f75e585b0a7201b8d2e84578412847a",
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
        guard let apiPartnerClient = apiPartnerClient, isLoggedIn else { throw SpotAPIError.authenticationFailed("Not logged in.") }
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

        let sha256Hash: String
        if let known = Self.knownPathfinderHashes[operationName] {
            sha256Hash = known
        } else if let discovered = operationHashes[operationName] {
            sha256Hash = discovered
        } else {
            throw SpotAPIError.missingData("SHA256 hash for operation '\(operationName)' not found.")
        }

        let finalExtensions = extensions ?? ["persistedQuery": ["version": 1, "sha256Hash": sha256Hash]]

        let response: HTTPResponse
        let path = useV2Endpoint ? "/pathfinder/v2/query" : "/pathfinder/v1/query"

        if sendAsBody {
            // Web Player APQ POST: { operationName, variables, extensions.persistedQuery }
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

        if (200...299).contains(response.statusCode) && !response.body.isEmpty {
            let bodyToCache = response.body
            Task(priority: .utility) { await self.apiCache.set(bodyToCache, forKey: cacheKey) }
        }
        let responseBody = response.body
        return try await Task.detached(priority: .utility) {
            try Self.decodePathfinderResponse(responseBody, for: operationName)
        }.value
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

    func refreshPlayerAndDeviceState() async throws {
        // Prefer an explicit cluster read when available; fall back to device PUT registration.
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
            // Never wipe cookies/session on a transient decode issue — only explicit logout should.
            print("[SpotifyPrivateAPIManager] Error refreshing player state (session kept): \(error.localizedDescription)")
            throw error
        }
    }

    /// GET /connect-state/v1/cluster — source of truth for cross-device timestamp + position_as_of_timestamp.
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
        // Backend libraryV3 sort: Recents / Recently Added / Alphabetical / Creator
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

        // Prefer cookie-only auth for the profile endpoint (no bearer yet).
        let response = try await wwwSpotifyClient.get(
            path: "/api/account-settings/v1/profile",
            authenticate: false
        )
        guard response.statusCode == 200, !response.body.isEmpty else {
            let snippet = String(data: response.body.prefix(160), encoding: .utf8) ?? "<empty>"
            print("[SpotifyPrivateAPIManager] Profile verify HTTP \(response.statusCode): \(snippet)")
            throw SpotAPIError.authenticationFailed("Session verification failed. Could not fetch user profile.")
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
        do {
            let trackDetailsResponse: SpotifyTrackDetailsResponse = try await pathfinderQuery(
                operationName: "getTrack",
                variables: [
                    "uri": sparseTrack.uri,
                    "includeVideoAssociationItems": false
                ]
            )

            var hydratedState = state
            let hydratedTrack = PlayerState.Track(hydrating: sparseTrack, withDetails: trackDetailsResponse.data.trackUnion)

            guard self.playerState?.track?.uri == expectedTrackURI else { return }
            hydratedState.track = hydratedTrack
            self.applyPlayerStateIfNeeded(hydratedState)
            self.nowPlayingHydrationTrackURI = nil

        } catch {
            nowPlayingHydrationTrackURI = nil
            print("[SpotifyPrivateAPIManager] Error hydrating now playing track: \(error.localizedDescription)")
        }
    }

    private func hydrateQueue(from playerState: PlayerState) {
        let sparseQueue = playerState.nextTracks?.filter {
            !($0.uri.contains("spotify:delimiter") || ($0.metadata?.hidden == "true"))
        } ?? []
        let expectedQueueIDs = sparseQueue.map(\.uid)
        let currentQueueIDs = nativeQueue.map(\.uid)

        if expectedQueueIDs == currentQueueIDs,
           !expectedQueueIDs.isEmpty,
           !nativeQueue.contains(where: { ($0.metadata?.title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) && $0.metadata?.artistName == nil }) {
            return
        }

        if expectedQueueIDs == lastQueueHydrationIDs,
           currentQueueIDs == expectedQueueIDs,
           queueHydrationTask != nil {
            return
        }

        queueHydrationTask?.cancel()
        lastQueueHydrationIDs = expectedQueueIDs

        // Publish sparse up-next immediately so the media player pill updates on song change
        // without waiting for Pathfinder metadata hydration.
        if currentQueueIDs != expectedQueueIDs || nativeQueue.isEmpty {
            nativeQueue = sparseQueue
        }

        queueHydrationTask = Task(priority: .utility) {
            defer { self.queueHydrationTask = nil }
            var finalQueue = sparseQueue
            let tracksToHydrateIndices = finalQueue.indices.filter { finalQueue[$0].metadata?.artistName == nil }

            guard !tracksToHydrateIndices.isEmpty else {
                if self.nativeQueue.map(\.uid) != finalQueue.map(\.uid) { self.nativeQueue = finalQueue }
                return
            }

            let tracksNeedingHydration = tracksToHydrateIndices.prefix(5).map { finalQueue[$0] }
            let hydrateIndices = Array(tracksToHydrateIndices.prefix(5))
            let hydratedBatch = await hydrateTracksBatch(tracksNeedingHydration)
            for (batchOffset, hydratedTrack) in hydratedBatch.enumerated() {
                let index = hydrateIndices[batchOffset]
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
    }

    /// Force a Connect cluster refresh + queue hydrate (used when music player opens with no up-next).
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

    /// If Sapphire somehow becomes the active Connect player, bounce to a real speaker.
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
        guard !isLoggedIn, loginChallenge == nil, webSocketManager?.isConnecting != true else {
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
    /// Coarse position bucket so seeks / track-edge resets still republish without per-ms churn.
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
