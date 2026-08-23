//
//  SpotifyNetwork.swift
//  Sapphire
//
//  Consolidated Spotify networking, crypto, protobuf, and APQ hash registry.
//

import Foundation
import Combine
import AppKit
import CryptoKit
import CommonCrypto
import JavaScriptCore


struct HTTPResponse {
    let statusCode: Int
    let headers: [String: String]
    let body: Data
    let cookies: [HTTPCookie]
}

/// Tracks Spotify's HTTP 429 responses so the whole integration backs off instead of
/// hammering an endpoint that is actively throttling the account. Spotify rate limits
/// tend to hit the account/session broadly, so any 429 also pauses every host briefly.
actor SpotifyRateLimitTracker {
    static let shared = SpotifyRateLimitTracker()

    private struct HostEntry {
        var until: Date
        var strikeCount: Int
        var lastSeen: Date
    }

    private var perHost: [String: HostEntry] = [:]
    private var globalUntil: Date?
    private var globalStrikes = 0
    private var last429At: Date?

    private let baseCooldown: TimeInterval = 15
    private let maxCooldown: TimeInterval = 300
    private let strikeWindow: TimeInterval = 60

    /// Records a 429. `retryAfter` (seconds) comes from the Retry-After header when present.
    func record(host: String, retryAfter: TimeInterval?) {
        let now = Date()
        if let last = last429At, now.timeIntervalSince(last) > strikeWindow {
            globalStrikes = 0
        }

        // Per-host cooldown with exponential strike escalation within a short window.
        let base = retryAfter.map { max($0, 5) } ?? baseCooldown
        var strikes = 1
        if let entry = perHost[host], now.timeIntervalSince(entry.lastSeen) < strikeWindow {
            strikes = entry.strikeCount + 1
        }
        let cooldown = min(base * Double(strikes), maxCooldown)
        perHost[host] = HostEntry(until: now.addingTimeInterval(cooldown), strikeCount: strikes, lastSeen: now)

        // Any 429 pauses everything briefly — throttling usually covers the whole session.
        globalStrikes += 1
        let globalCooldown = min(20.0 * Double(globalStrikes), maxCooldown)
        let newGlobalUntil = now.addingTimeInterval(globalCooldown)
        if globalUntil == nil || newGlobalUntil > globalUntil! {
            globalUntil = newGlobalUntil
        }
        last429At = now
        print("[SpotifyRateLimit] 429 on \(host) — backing off \(Int(cooldown))s (host), \(Int(globalCooldown))s (global).")
    }

    /// True when we should NOT fire a request to `host` right now.
    func isThrottled(host: String) -> Bool {
        let now = Date()
        if let globalUntil, now < globalUntil { return true }
        if let entry = perHost[host], now < entry.until { return true }
        return false
    }

    func reset() {
        perHost.removeAll()
        globalUntil = nil
        globalStrikes = 0
        last429At = nil
    }
}

/// Domain-aware cookie jar matching browser Cookie storage for Spotify hosts.
actor CookieManager {
    private var cookiesByKey: [String: HTTPCookie] = [:]

    private func key(for cookie: HTTPCookie) -> String {
        "\(cookie.domain.lowercased())|\(cookie.path)|\(cookie.name)"
    }

    func setCookie(_ cookie: HTTPCookie) {
        cookiesByKey[key(for: cookie)] = cookie
    }

    func setCookies(_ newCookies: [HTTPCookie]) {
        for cookie in newCookies { setCookie(cookie) }
    }

    func clear() { cookiesByKey.removeAll() }

    /// Legacy name-keyed map (last write wins) for callers that look up `sp_dc` / `sp_t`.
    func allCookies() -> [String: HTTPCookie] {
        var byName: [String: HTTPCookie] = [:]
        for cookie in cookiesByKey.values {
            byName[cookie.name] = cookie
        }
        return byName
    }

    func cookies(for host: String) -> [HTTPCookie] {
        let hostLower = host.lowercased()
        let now = Date()
        return cookiesByKey.values.filter { cookie in
            if let expires = cookie.expiresDate, expires < now { return false }
            let domain = cookie.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
            return hostLower == domain || hostLower.hasSuffix("." + domain)
        }
    }

    func cookieHeader(for host: String) -> String? {
        let matching = cookies(for: host)
        guard !matching.isEmpty else { return nil }
        return matching.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
    }
}

/// Shared web-player identity — keep UA / Client Hints aligned with login WKWebView.
enum SpotifyWebPlayerIdentity {
    static let chromeMajor = "131"
    static let userAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/\(chromeMajor).0.0.0 Safari/537.36"
    static let secCHUA =
        "\"Not;A=Brand\";v=\"99\", \"Google Chrome\";v=\"\(chromeMajor)\", \"Chromium\";v=\"\(chromeMajor)\""
    static let origin = "https://open.spotify.com"
    static let referer = "https://open.spotify.com/"
    static let acceptLanguage = "en-US,en;q=0.9"
}

/// URLSession client that impersonates the Spotify Web Player request surface.
final class CustomTLSClient: @unchecked Sendable {
    private let hostName: String
    internal let userAgent: String
    private let cookieManager: CookieManager
    private let session: URLSession
    internal var accessToken: String?
    internal var clientToken: String?
    internal var clientVersion: String?
    internal var onUnauthorized: (() async -> Bool)?

    init(host: String, port: UInt16 = 443, userAgent: String, cookieManager: CookieManager) {
        self.hostName = host
        self.userAgent = userAgent
        self.cookieManager = cookieManager
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieAcceptPolicy = .never
        config.httpShouldSetCookies = false
        config.httpCookieStorage = nil
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        config.waitsForConnectivity = true
        self.session = URLSession(configuration: config)
    }

    private func baseURL(path: String) -> URL? {
        let normalized = path.hasPrefix("/") ? path : "/" + path
        return URL(string: "https://\(hostName)\(normalized)")
    }

    private func webPlayerHeaders(authenticate: Bool, contentType: String?, acceptType: String) async -> [String: String] {
        var headers: [String: String] = [
            "User-Agent": userAgent,
            "Accept": acceptType,
            "Accept-Language": SpotifyWebPlayerIdentity.acceptLanguage,
            "Referer": SpotifyWebPlayerIdentity.referer,
            "sec-ch-ua": SpotifyWebPlayerIdentity.secCHUA,
            "sec-ch-ua-mobile": "?0",
            "sec-ch-ua-platform": "\"macOS\"",
            "sec-fetch-dest": "empty",
            "sec-fetch-mode": "cors",
            "sec-fetch-site": hostName.contains("spotify.com") ? "same-site" : "cross-site"
        ]

        if !hostName.hasPrefix("clienttoken.") {
            headers["Origin"] = SpotifyWebPlayerIdentity.origin
            headers["app-platform"] = "WebPlayer"
        }

        if let contentType { headers["Content-Type"] = contentType }

        if authenticate {
            if let token = accessToken { headers["Authorization"] = "Bearer \(token)" }
            if let cToken = clientToken { headers["client-token"] = cToken }
            if let cVersion = clientVersion { headers["spotify-app-version"] = cVersion }
        }

        if let cookieHeader = await cookieManager.cookieHeader(for: hostName) {
            headers["Cookie"] = cookieHeader
        }
        return headers
    }

    private func ingestResponseCookies(_ response: HTTPURLResponse) async {
        guard let url = response.url,
              let headerFields = response.allHeaderFields as? [String: String] else { return }
        let parsed = HTTPCookie.cookies(withResponseHeaderFields: headerFields, for: url)
        if !parsed.isEmpty {
            await cookieManager.setCookies(parsed)
            return
        }
        // Fallback for Set-Cookie strings missing Domain.
        if let raw = response.value(forHTTPHeaderField: "Set-Cookie") {
            for part in raw.components(separatedBy: ", ") {
                if let cookie = HTTPCookie(string: part, defaultDomain: hostName) {
                    await cookieManager.setCookie(cookie)
                }
            }
        }
    }

    private func performRequest(
        method: String,
        path: String,
        queryItems: [URLQueryItem]? = nil,
        body: Data? = nil,
        contentType: String? = nil,
        acceptType: String = "*/*",
        additionalHeaders: [String: String]? = nil,
        authenticate: Bool = true,
        allowAuthRetry: Bool = true
    ) async throws -> HTTPResponse {
        // Fail fast while Spotify is throttling us — every request fired during a
        // rate-limit window deepens the block and extends the cooldown.
        if await SpotifyRateLimitTracker.shared.isThrottled(host: hostName) {
            throw SpotAPIError.rateLimited("Suppressing request to \(hostName) while rate-limited.")
        }

        guard var components = URLComponents(url: baseURL(path: path)!, resolvingAgainstBaseURL: false) else {
            throw URLError(.badURL)
        }
        if let queryItems, !queryItems.isEmpty {
            components.queryItems = (components.queryItems ?? []) + queryItems
        }
        guard let url = components.url else { throw URLError(.badURL) }

        var request = URLRequest(url: url)
        request.httpMethod = method.uppercased()
        request.httpBody = body
        request.cachePolicy = .reloadIgnoringLocalCacheData

        var headers = await webPlayerHeaders(authenticate: authenticate, contentType: contentType, acceptType: acceptType)
        additionalHeaders?.forEach { headers[$0.key] = $0.value }
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        await ingestResponseCookies(http)

        var responseHeaders: [String: String] = [:]
        for (key, value) in http.allHeaderFields {
            if let k = key as? String, let v = value as? String {
                responseHeaders[k] = v
            }
        }
        if http.statusCode == 429 {
            // Retry-After may arrive as "Retry-After" or lowercase — match case-insensitively.
            let retryAfter = responseHeaders.first(where: { $0.key.caseInsensitiveCompare("Retry-After") == .orderedSame })
                .flatMap { Double($0.value.trimmingCharacters(in: .whitespaces)) }
            await SpotifyRateLimitTracker.shared.record(host: hostName, retryAfter: retryAfter)
        }
        if allowAuthRetry,
           authenticate,
           (http.statusCode == 401 || http.statusCode == 403),
           let onUnauthorized,
           await onUnauthorized() {
            return try await performRequest(
                method: method,
                path: path,
                queryItems: queryItems,
                body: body,
                contentType: contentType,
                acceptType: acceptType,
                additionalHeaders: additionalHeaders,
                authenticate: authenticate,
                allowAuthRetry: false
            )
        }

        let cookies = await cookieManager.cookies(for: hostName)
        return HTTPResponse(statusCode: http.statusCode, headers: responseHeaders, body: data, cookies: cookies)
    }

    internal func get(path: String, queryItems: [URLQueryItem]? = nil, additionalHeaders: [String: String]? = nil, authenticate: Bool = true) async throws -> HTTPResponse {
        try await performRequest(method: "GET", path: path, queryItems: queryItems, additionalHeaders: additionalHeaders, authenticate: authenticate)
    }

    internal func post(path: String, bodyData: Data, additionalHeaders: [String: String]? = nil) async throws -> HTTPResponse {
        let contentType = additionalHeaders?["Content-Type"] ?? "application/octet-stream"
        return try await performRequest(method: "POST", path: path, body: bodyData, contentType: contentType, additionalHeaders: additionalHeaders)
    }

    internal func post(path: String, queryItems: [URLQueryItem]? = nil, jsonBody: [String: Any]? = nil, urlEncodedBody: [String: String]? = nil, additionalHeaders: [String: String]? = nil, authenticate: Bool = true) async throws -> HTTPResponse {
        var bodyData: Data?
        var contentType: String?
        var acceptType = "*/*"
        if let json = jsonBody {
            bodyData = try? JSONSerialization.data(withJSONObject: json)
            contentType = "application/json"
            acceptType = "application/json"
        } else if let urlEncoded = urlEncodedBody {
            var components = URLComponents()
            components.queryItems = urlEncoded.map { URLQueryItem(name: $0.key, value: $0.value) }
            bodyData = components.percentEncodedQuery?.data(using: .utf8)
            contentType = "application/x-www-form-urlencoded"
        }
        return try await performRequest(method: "POST", path: path, queryItems: queryItems, body: bodyData, contentType: contentType, acceptType: acceptType, additionalHeaders: additionalHeaders, authenticate: authenticate)
    }

    internal func put(path: String, queryItems: [URLQueryItem]? = nil, jsonBody: [String: Any]? = nil, additionalHeaders: [String: String]? = nil, authenticate: Bool = true) async throws -> HTTPResponse {
        var bodyData: Data?
        var contentType: String?
        var acceptType = "*/*"
        if let json = jsonBody {
            bodyData = try? JSONSerialization.data(withJSONObject: json)
            contentType = "application/json"
            acceptType = "application/json"
        }
        return try await performRequest(method: "PUT", path: path, queryItems: queryItems, body: bodyData, contentType: contentType, acceptType: acceptType, additionalHeaders: additionalHeaders, authenticate: authenticate)
    }

    internal func delete(path: String, additionalHeaders: [String: String]? = nil, authenticate: Bool = true) async throws -> HTTPResponse {
        try await performRequest(method: "DELETE", path: path, additionalHeaders: additionalHeaders, authenticate: authenticate)
    }
}

// MARK: - HTTPCookie Extension
extension HTTPCookie {
    convenience init?(string: String, defaultDomain: String? = nil) {
        let components = string.components(separatedBy: ";").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard let nameValue = components.first, nameValue.contains("=") else { return nil }

        let nameValueParts = nameValue.split(separator: "=", maxSplits: 1)
        let name = String(nameValueParts[0])
        let value = String(nameValueParts.count > 1 ? nameValueParts[1] : "")

        var properties: [HTTPCookiePropertyKey: Any] = [
            .name: name,
            .value: value,
            .path: "/"
        ]
        if let defaultDomain {
            properties[.domain] = defaultDomain
        }

        for component in components.dropFirst() {
            let parts = component.split(separator: "=", maxSplits: 1)
            let key = String(parts[0]).trimmingCharacters(in: .whitespaces).lowercased()
            let val = String(parts.count > 1 ? parts[1] : "").trimmingCharacters(in: .whitespaces)

            switch key {
            case "domain":
                properties[.domain] = val
            case "path":
                properties[.path] = val
            case "expires":
                let formatter = DateFormatter()
                let formats = ["EEE, dd MMM yyyy HH:mm:ss zzz", "EEEE, dd-MMM-yy HH:mm:ss zzz"]
                for format in formats {
                    formatter.dateFormat = format
                    formatter.locale = Locale(identifier: "en_US_POSIX")
                    if let date = formatter.date(from: val) {
                        properties[.expires] = date
                        break
                    }
                }
            case "max-age":
                if let maxAge = Int(val) { properties[.maximumAge] = maxAge }
            case "secure":
                properties[.secure] = "TRUE"
            case "httponly":
                break
            default:
                break
            }
        }

        if properties[.domain] == nil, let defaultDomain {
            properties[.domain] = defaultDomain
        }
        self.init(properties: properties)
    }
}


// MARK: - Consolidated from WebSocketManager.swift


class WebSocketManager: NSObject, URLSessionWebSocketDelegate, URLSessionDelegate {
    private var webSocketTask: URLSessionWebSocketTask?
    private var accessToken: String
    private var isConnected = false
    private(set) var isConnecting = false
    private(set) var lastPlayerStateReceivedAt: Date?

    var hasActiveConnection: Bool { isConnected }

    public let controllerDeviceID: String

    private var session: URLSession!
    private let delegateQueue = OperationQueue()
    private var shouldReconnect = true
    private var softReconnectAttempts = 0
    private let maxSoftReconnectAttempts = 3

    private weak var privateAPIManager: SpotifyPrivateAPIManager?

    private let playerStateSubject = PassthroughSubject<PlayerStateClusterUpdate, Never>()
    var playerStatePublisher: AnyPublisher<PlayerStateClusterUpdate, Never> {
        return playerStateSubject.eraseToAnyPublisher()
    }

    private let connectionIdSubject = PassthroughSubject<String, Never>()
    var connectionIdPublisher: AnyPublisher<String, Never> {
        return connectionIdSubject.eraseToAnyPublisher()
    }
    private(set) var latestConnectionID: String?
    private var lastPublishedPlayerStateSignature: PlayerStateSignature?

    init(accessToken: String, client: SpotifyPrivateAPIManager, controllerDeviceID: String) {
        self.accessToken = accessToken
        self.privateAPIManager = client
        self.controllerDeviceID = controllerDeviceID

        super.init()
        self.delegateQueue.maxConcurrentOperationCount = 1
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 60 * 60 * 24
        configuration.timeoutIntervalForResource = 60 * 60 * 24
        configuration.waitsForConnectivity = true
        self.session = URLSession(configuration: configuration, delegate: self, delegateQueue: delegateQueue)
    }

    deinit {
        disconnect()
    }

    func updateAccessToken(_ token: String) {
        accessToken = token
    }

    private func createWebSocketTask() -> URLSessionWebSocketTask {
        let url = URL(string: "wss://dealer.spotify.com/?access_token=\(accessToken)")!
        var request = URLRequest(url: url)
        request.setValue(SpotifyWebPlayerIdentity.origin, forHTTPHeaderField: "Origin")
        request.setValue(SpotifyWebPlayerIdentity.userAgent, forHTTPHeaderField: "User-Agent")
        return session.webSocketTask(with: request)
    }

    func connect() {
        if isConnected || isConnecting {
            return
        }

        reconnectTimer?.invalidate()
        reconnectTimer = nil
        shouldReconnect = true
        webSocketTask = createWebSocketTask()
        isConnecting = true
        webSocketTask?.resume()
        receiveMessages()
    }

    /// Soft reconnect: keep session cookies/tokens; only reopen dealer and emit a fresh connection_id.
    func softReconnect(withAccessToken token: String?) {
        if let token { accessToken = token }
        softReconnectAttempts = 0
        reconnectSoft(delay: 0.5)
    }

    // MARK: - URLSessionWebSocketDelegate Methods

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        self.isConnected = true
        self.isConnecting = false
        softReconnectAttempts = 0
        schedulePing()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        self.isConnected = false
        self.isConnecting = false
        if let error = error {
            guard !isTimeoutError(error) else { return }
            handleConnectionFailure()
        }
    }

    // MARK: - Message Handling

    private func receiveMessages() {
        webSocketTask?.receive { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let message):
                switch message {
                case .string(let text): self.handleMessage(text)
                case .data(let data):
                    if let string = String(data: data, encoding: .utf8) { self.handleMessage(string) }
                @unknown default: break
                }
                self.receiveMessages()
            case .failure(let error):
                if self.isTimeoutError(error), self.isConnected {
                    self.receiveMessages()
                    return
                }
                self.handleConnectionFailure()
            }
        }
    }

    private func handleMessage(_ message: String) {
        if message.contains("Spotify-Connection-Id") {
            if let data = message.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let headers = json["headers"] as? [String: String],
               let connId = headers["Spotify-Connection-Id"] {

                latestConnectionID = connId
                connectionIdSubject.send(connId)
            }
        }

        if message.contains("player_state") {
            processPlayerStateUpdate(message)
        }
    }

    private func processPlayerStateUpdate(_ message: String) {
        guard let data = message.data(using: .utf8) else { return }
        do {
            let webSocketMessage = try JSONDecoder().decode(WebSocketMessage.self, from: data)
            // Dealer device maps are snake_case; Cluster's nested Decodable often misses them
            // without convertFromSnakeCase — repair from the raw payload asynchronously-safe.
            let repairedDevices = Self.decodeClusterDevices(from: data) ?? [:]

            if let cluster = webSocketMessage.payloads?.first?.cluster,
               let playerState = cluster.playerState ?? webSocketMessage.payloads?.first?.state {
                let devices = !repairedDevices.isEmpty ? repairedDevices : (cluster.devices ?? [:])
                let signature = PlayerStateSignature(playerState)
                let playerChanged = signature != lastPublishedPlayerStateSignature
                // Device roster can change while the track signature stays identical — still publish.
                if !playerChanged && devices.isEmpty { return }
                if playerChanged {
                    lastPublishedPlayerStateSignature = signature
                }
                lastPlayerStateReceivedAt = Date()
                playerStateSubject.send(PlayerStateClusterUpdate(
                    playerState: playerState,
                    activeDeviceId: cluster.activeDeviceId,
                    devices: devices
                ))
            } else if let playerState = webSocketMessage.payloads?.first?.state {
                let signature = PlayerStateSignature(playerState)
                let playerChanged = signature != lastPublishedPlayerStateSignature
                if !playerChanged && repairedDevices.isEmpty { return }
                if playerChanged {
                    lastPublishedPlayerStateSignature = signature
                }
                lastPlayerStateReceivedAt = Date()
                playerStateSubject.send(PlayerStateClusterUpdate(
                    playerState: playerState,
                    activeDeviceId: nil,
                    devices: repairedDevices
                ))
            }
        } catch {
            return
        }
    }

    /// Decode `cluster.devices` with snake_case so Connect device IDs/names aren't dropped.
    private static func decodeClusterDevices(from data: Data) -> [String: SpotifyNativeDevice]? {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let payloads = root["payloads"] as? [[String: Any]]
        else { return nil }

        for payload in payloads {
            guard let cluster = payload["cluster"] as? [String: Any],
                  let devicesObj = cluster["devices"],
                  !(devicesObj is NSNull) else { continue }
            guard let devicesData = try? JSONSerialization.data(withJSONObject: devicesObj) else { continue }
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            if let decoded = try? decoder.decode([String: SpotifyNativeDevice].self, from: devicesData),
               !decoded.isEmpty {
                return decoded
            }
        }
        return nil
    }

    private var pingTimer: Timer?

    private func schedulePing() {
        pingTimer?.invalidate()
        DispatchQueue.main.async {
            self.pingTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
                guard let self = self, self.isConnected else { return }
                self.webSocketTask?.send(.string("{\"type\":\"ping\"}")) { error in
                    if let error = error {
                        guard !self.isTimeoutError(error) else { return }
                        self.handleConnectionFailure()
                    }
                }
            }
        }
    }

    func disconnect(shouldReconnect: Bool = false) {
        self.shouldReconnect = shouldReconnect
        pingTimer?.invalidate(); pingTimer = nil
        reconnectTimer?.invalidate(); reconnectTimer = nil
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        // Keep latestConnectionID until a replacement arrives so in-flight Connect calls can finish.
        lastPublishedPlayerStateSignature = nil
        isConnected = false
        isConnecting = false
    }

    private var reconnectTimer: Timer?

    private func handleConnectionFailure() {
        guard shouldReconnect else { return }
        reconnectSoft(delay: 2.0)
    }

    private func reconnectSoft(delay: TimeInterval) {
        guard shouldReconnect, reconnectTimer == nil else { return }
        softReconnectAttempts += 1
        if softReconnectAttempts > maxSoftReconnectAttempts {
            softReconnectAttempts = 0
            DispatchQueue.main.async {
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.privateAPIManager?.requestSessionReestablishment(from: self)
                }
            }
            return
        }

        pingTimer?.invalidate(); pingTimer = nil
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        isConnected = false
        isConnecting = false

        DispatchQueue.main.async {
            self.reconnectTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
                guard let self else { return }
                self.reconnectTimer = nil
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    // Refresh bearer first (web player does this before dealer reconnect).
                    await self.privateAPIManager?.refreshTokensIfNeeded(force: false)
                    if let token = self.privateAPIManager?.currentAccessToken() {
                        self.accessToken = token
                    }
                    self.connect()
                    // Rebind Connect device once we get a new connection_id.
                    self.privateAPIManager?.observeSoftReconnectConnection(from: self)
                }
            }
        }
    }

    private func isTimeoutError(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain && nsError.code == URLError.timedOut.rawValue {
            return true
        }
        return false
    }
}

private struct PlayerStateSignature: Equatable {
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
    }
}

struct PlayerStateClusterUpdate {
    let playerState: PlayerState
    let activeDeviceId: String?
    let devices: [String: SpotifyNativeDevice]
}

// MARK: - Decoding Structs
struct WebSocketMessage: Decodable { let payloads: [Payload]? }
struct Payload: Decodable { let cluster: Cluster?; let state: PlayerState? }
struct Cluster: Decodable {
    let playerState: PlayerState?
    let activeDeviceId: String?
    let devices: [String: SpotifyNativeDevice]?
    enum CodingKeys: String, CodingKey {
        case playerState = "player_state"
        case activeDeviceId = "active_device_id"
        case devices
    }
}


// MARK: - Consolidated from TotpGenerator.swift


func hmacSHA1(key: Data, message: Data) -> Data {
    var result = Data(count: Int(CC_SHA1_DIGEST_LENGTH))
    result.withUnsafeMutableBytes { resultBytes in
        key.withUnsafeBytes { keyBytes in
            message.withUnsafeBytes { messageBytes in
                CCHmac(CCHmacAlgorithm(kCCHmacAlgSHA1),
                       keyBytes.baseAddress, key.count,
                       messageBytes.baseAddress, message.count,
                       resultBytes.baseAddress)
            }
        }
    }
    return result
}

class TotpGenerator {
    private static var secretCache: (version: Int, secretBytes: Data)?
    private static var cacheExpiry: Date?
    private static let cacheTTL: TimeInterval = 15 * 60

    // `getLatestTotpSecret()` is invoked concurrently from multiple async auth flows
    // (token refreshes and in-flight requests). Guard the mutable cache so racing
    // tasks can't corrupt the ref-counted `Data` storage (which crashes in
    // `_swift_release_dealloc`).
    private static let cacheLock = NSLock()

    private static func cachedSecret() -> (version: Int, secretBytes: Data)? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        guard let cache = secretCache, let expiry = cacheExpiry, Date() < expiry else {
            return nil
        }
        return cache
    }

    private static func storeSecret(_ secret: (version: Int, secretBytes: Data)) {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        secretCache = secret
        cacheExpiry = Date().addingTimeInterval(cacheTTL)
    }

    private static let fallbackSecrets: [Int: Data] = [
        18: Data([70, 60, 33, 57, 92, 120, 90, 33, 32, 62, 62, 55, 126, 93, 66, 35, 108, 68]),
        12: Data([107, 81, 49, 57, 67, 93, 87, 81, 69, 67, 40, 93, 48, 50, 46, 91, 94, 113, 41, 108, 77, 107, 34]),
        11: Data([111, 45, 40, 73, 95, 74, 35, 85, 105, 107, 60, 110, 55, 72, 69, 70, 114, 83, 63, 88, 91]),
        10: Data([61, 110, 58, 98, 35, 79, 117, 69, 102, 72, 92, 102, 69, 93, 41, 101, 42, 75]),
    ]

    private static let secretURLs = [
        "https://raw.githubusercontent.com/xyloflake/spot-secrets-go/main/secrets/secretDict.json",
        "https://cdn.jsdelivr.net/gh/xyloflake/spot-secrets-go@main/secrets/secretDict.json"
    ]

    private static func getLatestFallbackSecret() -> (version: Int, secretBytes: Data) {
        guard let latestVersion = fallbackSecrets.keys.max(),
              let secretData = fallbackSecrets[latestVersion] else {
            fatalError("Fallback TOTP secrets dictionary is empty.")
        }
        return (latestVersion, secretData)
    }

    static func getLatestTotpSecret() async -> (version: Int, secretBytes: Data) {
        if let cache = cachedSecret() {
            return cache
        }

        for urlString in secretURLs {
            guard let url = URL(string: urlString) else { continue }
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                    continue
                }
                guard let secretsDict = try JSONSerialization.jsonObject(with: data) as? [String: [Int]] else {
                    continue
                }
                guard let latestVersionString = secretsDict.keys.max(),
                      let latestVersion = Int(latestVersionString),
                      let secretList = secretsDict[latestVersionString] else {
                    continue
                }
                let secretData = Data(secretList.compactMap { UInt8(exactly: $0) })
                storeSecret((latestVersion, secretData))
                print("[TotpGenerator] Successfully fetched and cached secret version: \(latestVersion)")
                return (latestVersion, secretData)
            } catch {
                continue
            }
        }

        print("[TotpGenerator] All secret sources failed, using fallback.")
        return getLatestFallbackSecret()
    }

    /// Generates TOTP codes for the current and adjacent 30s windows (web player retries around clock skew).
    static func generateTotpCandidates() async -> [(totp: String, version: Int)] {
        let (version, secretBytes) = await getLatestTotpSecret()
        guard let base32Secret = makeBase32Secret(from: secretBytes) else { return [] }
        let offsets: [TimeInterval] = [0, -30, 30]
        var results: [(String, Int)] = []
        var seen = Set<String>()
        for offset in offsets {
            let code = calculateTOTP(secret: base32Secret, timeInterval: 30, digits: 6, timeOffset: offset)
            if !code.isEmpty, seen.insert(code).inserted {
                results.append((code, version))
            }
        }
        return results
    }

    static func generateTotp() async -> (totp: String, version: Int) {
        let candidates = await generateTotpCandidates()
        return candidates.first ?? ("", 0)
    }

    private static func makeBase32Secret(from secretBytes: Data) -> String? {
        var transformedBytes: [UInt8] = []
        for (index, byte) in secretBytes.enumerated() {
            transformedBytes.append(byte ^ UInt8((index % 33) + 9))
        }
        let joinedString = transformedBytes.map { String($0) }.joined()
        guard let joinedData = joinedString.data(using: .utf8) else { return nil }
        let hexString = joinedData.map { String(format: "%02x", $0) }.joined()
        guard let keyData = Data(hex: hexString) else { return nil }
        return base32Encode(data: keyData).replacingOccurrences(of: "=", with: "")
    }

    private static func base32Encode(data: Data) -> String {
        let alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
        var result = ""
        var bits = 0
        var byteBuffer: UInt64 = 0

        for byte in data {
            byteBuffer = (byteBuffer << 8) | UInt64(byte)
            bits += 8

            while bits >= 5 {
                let index = Int((byteBuffer >> (bits - 5)) & 0x1F)
                result.append(alphabet[alphabet.index(alphabet.startIndex, offsetBy: index)])
                bits -= 5
            }
        }

        if bits > 0 {
            let index = Int((byteBuffer << (5 - bits)) & 0x1F)
            result.append(alphabet[alphabet.index(alphabet.startIndex, offsetBy: index)])
        }

        let paddingNeeded = result.count % 8
        if paddingNeeded != 0 {
            result.append(String(repeating: "=", count: 8 - paddingNeeded))
        }

        return result
    }

    private static func base32Decode(base32String: String) -> Data? {
        let alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
        let base32Mapping = alphabet.enumerated().reduce(into: [Character: UInt8]()) { map, entry in
            map[entry.element] = UInt8(entry.offset)
        }

        var result = Data()
        var bits = 0
        var byteBuffer: UInt32 = 0

        let strippedString = base32String.replacingOccurrences(of: "=", with: "").uppercased()

        for char in strippedString {
            guard let value = base32Mapping[char] else { return nil }
            byteBuffer = (byteBuffer << 5) | UInt32(value)
            bits += 5

            if bits >= 8 {
                let byte = UInt8((byteBuffer >> (bits - 8)) & 0xFF)
                result.append(byte)
                bits -= 8
            }
        }
        return result
    }

    private static func calculateTOTP(secret: String, timeInterval: TimeInterval, digits: Int, timeOffset: TimeInterval = 0) -> String {
        guard let keyData = base32Decode(base32String: secret) else {
            return ""
        }

        let currentUnixTime = Date().timeIntervalSince1970 + timeOffset
        let counter = UInt64(floor(currentUnixTime / timeInterval))

        var counterData = Data(count: 8)
        var bigEndianCounter = counter.bigEndian
        counterData.withUnsafeMutableBytes {
            $0.copyBytes(from: withUnsafeBytes(of: &bigEndianCounter) { $0 })
        }

        let authenticationCode = hmacSHA1(key: keyData, message: counterData)
        let hash = Data(authenticationCode)

        let offset = Int(hash.last! & 0x0F)
        let truncatedHash = hash[offset..<(offset + 4)]

        var code: UInt32 = 0
        _ = withUnsafeMutableBytes(of: &code) {
            truncatedHash.copyBytes(to: $0)
        }

        code = UInt32(bigEndian: code) & 0x7FFFFFFF

        let otp = code % UInt32(pow(10, Double(digits)))
        return String(format: "%0\(digits)d", otp)
    }
}

extension Data {
    init?(hex: String) {
        let len = hex.count / 2
        var data = Data(capacity: len)
        var i = hex.startIndex
        while i < hex.endIndex {
            let j = hex.index(i, offsetBy: 2)
            let bytes = hex[i..<j]
            if var num = UInt8(bytes, radix: 16) {
                data.append(&num, count: 1)
            } else {
                return nil
            }
            i = j
        }
        self = data
    }
}

// MARK: - Consolidated from SpotifyProtoWire.swift


// MARK: - Minimal protobuf2 writer / field reader

enum SpotifyProtoWire {
    static func writeVarint(_ value: UInt64) -> Data {
        var v = value
        var out = Data()
        while v > 0x7F {
            out.append(UInt8((v & 0x7F) | 0x80))
            v >>= 7
        }
        out.append(UInt8(v & 0x7F))
        return out
    }

    static func key(_ field: UInt64, _ wire: UInt64) -> Data {
        writeVarint((field << 3) | wire)
    }

    static func writeBytes(field: UInt64, _ data: Data) -> Data {
        key(field, 2) + writeVarint(UInt64(data.count)) + data
    }

    static func writeString(field: UInt64, _ string: String) -> Data {
        writeBytes(field: field, Data(string.utf8))
    }

    static func writeVarintField(field: UInt64, _ value: UInt64) -> Data {
        key(field, 0) + writeVarint(value)
    }

    static func writeUInt64(field: UInt64, _ value: UInt64) -> Data {
        writeVarintField(field: field, value)
    }

    static func writeMessage(field: UInt64, _ message: Data) -> Data {
        writeBytes(field: field, message)
    }

    /// Resilient reader that skips unrecognized field tags during Protobuf parsing.
    static func skipField(wireType: Int, in data: inout Data) -> Bool {
        switch wireType {
        case 0: // Varint
            return readVarint(from: &data) != nil
        case 1: // 64-bit
            guard data.count >= 8 else { return false }
            data.removeFirst(8)
            return true
        case 2: // Length-delimited
            guard let length = readVarint(from: &data), data.count >= length else { return false }
            data.removeFirst(Int(length))
            return true
        case 5: // 32-bit
            guard data.count >= 4 else { return false }
            data.removeFirst(4)
            return true
        default:
            return false
        }
    }

    static func readVarint(from data: inout Data) -> UInt64? {
        var value: UInt64 = 0
        var shift: UInt64 = 0
        while !data.isEmpty {
            let byte = data.removeFirst()
            value |= UInt64(byte & 0x7F) << shift
            if (byte & 0x80) == 0 { return value }
            shift += 7
            if shift >= 64 { return nil }
        }
        return nil
    }

    static func readFields(_ data: Data) -> [UInt64: [Data]] {
        var map: [UInt64: [Data]] = [:]
        var remaining = data
        while !remaining.isEmpty {
            guard let tag = readVarint(from: &remaining) else { break }
            let field = tag >> 3
            let wire = Int(tag & 0x7)
            switch wire {
            case 0:
                guard let value = readVarint(from: &remaining) else { return map }
                map[field, default: []].append(writeVarint(value))
            case 2:
                guard let len = readVarint(from: &remaining), remaining.count >= len else { return map }
                let chunk = remaining.prefix(Int(len))
                map[field, default: []].append(Data(chunk))
                remaining.removeFirst(Int(len))
            case 5:
                guard remaining.count >= 4 else { return map }
                map[field, default: []].append(Data(remaining.prefix(4)))
                remaining.removeFirst(4)
            case 1:
                guard remaining.count >= 8 else { return map }
                map[field, default: []].append(Data(remaining.prefix(8)))
                remaining.removeFirst(8)
            default:
                // Unknown wire type — stop rather than corrupt subsequent fields.
                // Known types above already skip unrecognized *field numbers*.
                if !skipField(wireType: wire, in: &remaining) {
                    return map
                }
            }
        }
        return map
    }

    static func readVarint(_ data: Data, at start: Data.Index) -> (UInt64, Data.Index)? {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        var i = start
        while i < data.endIndex {
            let b = data[i]
            i = data.index(after: i)
            result |= UInt64(b & 0x7F) << shift
            if b & 0x80 == 0 { return (result, i) }
            shift += 7
            if shift > 63 { return nil }
        }
        return nil
    }

    static func firstBytes(_ fields: [UInt64: [Data]], _ field: UInt64) -> Data? {
        fields[field]?.first.map { Data($0) }
    }

    static func firstVarint(_ fields: [UInt64: [Data]], _ field: UInt64) -> UInt64? {
        guard let raw = fields[field]?.first, let (v, _) = readVarint(Data(raw), at: 0) else { return nil }
        return v
    }
}


// MARK: - Consolidated from SpotifyExtendedMetadataParser.swift


enum SpotifyExtendedMetadataParser {

    /// BatchedExtensionResponse → TRACK_V4 Any.value → metadata.Track
    static func parseTrack(fromBatchedResponse data: Data) -> SpotifyTrackMetadata? {
        let root = SpotifyProtoWire.readFields(data)
        // field 2: repeated EntityExtensionDataArray extended_metadata
        guard let arrays = root[2], !arrays.isEmpty else { return nil }

        for arrayBytes in arrays {
            let array = SpotifyProtoWire.readFields(Data(arrayBytes))
            // field 3: repeated EntityExtensionData
            for extBytes in array[3] ?? [] {
                let ext = SpotifyProtoWire.readFields(Data(extBytes))
                // field 3: google.protobuf.Any extension_data
                guard let anyBytes = SpotifyProtoWire.firstBytes(ext, 3) else { continue }
                let anyFields = SpotifyProtoWire.readFields(anyBytes)
                // Any.value = field 2
                guard let trackBytes = SpotifyProtoWire.firstBytes(anyFields, 2) else { continue }
                if let track = parseTrackMessage(trackBytes) {
                    return track
                }
            }
        }
        return nil
    }

    /// metadata.Track protobuf (proto2)
    static func parseTrackMessage(_ data: Data) -> SpotifyTrackMetadata? {
        let fields = SpotifyProtoWire.readFields(data)

        let gidHex = SpotifyProtoWire.firstBytes(fields, 1).map(hexString)
        let name = SpotifyProtoWire.firstBytes(fields, 2).flatMap { String(data: $0, encoding: .utf8) } ?? "Unknown"
        let duration = SpotifyProtoWire.firstVarint(fields, 7).map(decodeSInt32)
        let popularity = SpotifyProtoWire.firstVarint(fields, 8).map(decodeSInt32)
        let hasLyrics: Bool? = {
            guard let v = SpotifyProtoWire.firstVarint(fields, 18) else { return nil }
            return v != 0
        }()
        let canonicalUri = SpotifyProtoWire.firstBytes(fields, 36).flatMap { String(data: $0, encoding: .utf8) }

        // field 12: repeated AudioFile file
        let files = (fields[12] ?? []).compactMap { parseAudioFile(Data($0)) }
        // field 13: repeated Track alternative — each may contain files at field 12
        let alternatives: [SpotifyTrackMetadata.AlternativeNode] = (fields[13] ?? []).compactMap { altData in
            let altFields = SpotifyProtoWire.readFields(Data(altData))
            let altGid = SpotifyProtoWire.firstBytes(altFields, 1).map(hexString)
            let altFiles = (altFields[12] ?? []).compactMap { parseAudioFile(Data($0)) }
            guard !altFiles.isEmpty || altGid != nil else { return nil }
            return SpotifyTrackMetadata.AlternativeNode(gid: altGid, file: altFiles.isEmpty ? nil : altFiles)
        }

        let artists: [SpotifyTrackMetadata.ArtistNode]? = {
            let list = (fields[4] ?? []).compactMap { artistData -> SpotifyTrackMetadata.ArtistNode? in
                let af = SpotifyProtoWire.readFields(Data(artistData))
                guard let n = SpotifyProtoWire.firstBytes(af, 2).flatMap({ String(data: $0, encoding: .utf8) }) else {
                    return nil
                }
                let agid = SpotifyProtoWire.firstBytes(af, 1).map(hexString)
                return SpotifyTrackMetadata.ArtistNode(gid: agid, name: n)
            }
            return list.isEmpty ? nil : list
        }()

        return SpotifyTrackMetadata(
            gid: gidHex,
            name: name,
            popularity: popularity,
            duration: duration,
            canonicalUri: canonicalUri,
            hasLyrics: hasLyrics,
            album: nil,
            artist: artists,
            file: files.isEmpty ? nil : files,
            alternative: alternatives.isEmpty ? nil : alternatives
        )
    }

    private static func parseAudioFile(_ data: Data) -> SpotifyTrackMetadata.AudioFile? {
        let fields = SpotifyProtoWire.readFields(data)
        guard let fileIdBytes = SpotifyProtoWire.firstBytes(fields, 1), !fileIdBytes.isEmpty else {
            return nil
        }
        let format = SpotifyProtoWire.firstVarint(fields, 2).map { Int($0) }
        return SpotifyTrackMetadata.AudioFile(fileId: hexString(fileIdBytes), format: format)
    }

    private static func hexString(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    /// Protobuf zigzag decode for sint32.
    private static func decodeSInt32(_ raw: UInt64) -> Int {
        let n = Int32(truncatingIfNeeded: raw)
        return Int((n >> 1) ^ (-(n & 1)))
    }
}


// MARK: - Consolidated from SpotifyOperationHashRegistry.swift


actor SpotifyOperationHashRegistry {
    static let shared = SpotifyOperationHashRegistry()

    struct ScrapeResult: Sendable {
        let hashes: [String: String]
        let clientVersion: String?
        let jsPackURL: String?
    }

    private var hashes: [String: String] = [:]
    private var lastFetchTime: Date?
    private var lastJsPackURL: String?
    private var lastClientVersion: String?
    private var inFlightRefresh: Task<ScrapeResult?, Never>?

    private let cacheTTL: TimeInterval = 86_400
    private let userAgent =
        SpotifyWebPlayerIdentity.userAgent

    /// Seeds / merges hashes discovered during session bootstrap.
    /// Only pass live CDN hashes here — never seed stale hardcoded values.
    func seed(_ discovered: [String: String], clientVersion: String? = nil, jsPackURL: String? = nil, replaceAll: Bool = false) {
        guard !discovered.isEmpty else { return }
        if replaceAll {
            hashes = discovered
        } else {
            hashes.merge(discovered) { _, new in new }
        }
        lastFetchTime = Date()
        if let clientVersion { lastClientVersion = clientVersion }
        if let jsPackURL { lastJsPackURL = jsPackURL }
    }

    func cachedClientVersion() -> String? { lastClientVersion }
    func cachedJsPackURL() -> String? { lastJsPackURL }
    func hashCount() -> Int { hashes.count }
    func liveHash(for operationName: String) -> String? { hashes[operationName] }

    /// Drop a single operation hash after a wrong-shape response (stale APQ).
    func invalidate(operation operationName: String) {
        hashes.removeValue(forKey: operationName)
    }

    /// Forces the next lookup to re-scrape CDN bundles.
    func invalidate() {
        lastFetchTime = nil
        inFlightRefresh?.cancel()
        inFlightRefresh = nil
    }

    /// Resolves an operation hash from live CDN scrape. `fallback` is last-resort only.
    func getHash(for operationName: String, fallback: String? = nil, forceRefresh: Bool = false, allowFallback: Bool = true) async -> String? {
        if !forceRefresh, let hash = hashes[operationName] {
            return hash
        }

        let needsRefresh = forceRefresh
            || hashes[operationName] == nil
            || lastFetchTime == nil
            || Date().timeIntervalSince(lastFetchTime!) > cacheTTL

        if needsRefresh {
            _ = await refreshHashesFromCDN(force: forceRefresh || hashes[operationName] == nil)
        }

        if let hash = hashes[operationName] {
            return hash
        }
        return allowFallback ? fallback : nil
    }

    /// Scrapes open.spotify.com JS bundles for GraphQL operationName → sha256Hash mappings.
    @discardableResult
    func refreshHashesFromCDN(force: Bool = false) async -> ScrapeResult? {
        if !force,
           let lastFetchTime,
           Date().timeIntervalSince(lastFetchTime) <= cacheTTL,
           !hashes.isEmpty {
            return ScrapeResult(hashes: hashes, clientVersion: lastClientVersion, jsPackURL: lastJsPackURL)
        }

        if let existing = inFlightRefresh {
            return await existing.value
        }

        let task = Task<ScrapeResult?, Never> {
            await Self.scrapeLiveHashes(userAgent: userAgent)
        }
        inFlightRefresh = task
        let result = await task.value
        inFlightRefresh = nil

        if let result, !result.hashes.isEmpty {
            hashes.merge(result.hashes) { _, new in new }
            lastFetchTime = Date()
            lastClientVersion = result.clientVersion ?? lastClientVersion
            lastJsPackURL = result.jsPackURL ?? lastJsPackURL
            print("[SpotifyAPQRegistry] Successfully updated \(result.hashes.count) operation hashes live.")
            return ScrapeResult(hashes: hashes, clientVersion: lastClientVersion, jsPackURL: lastJsPackURL)
        }

        print("[SpotifyAPQRegistry] Hash extraction returned no operations.")
        return nil
    }

    // MARK: - CDN scrape

    private static func scrapeLiveHashes(userAgent: String) async -> ScrapeResult? {
        guard let url = URL(string: "https://open.spotify.com/") else { return nil }
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let html = String(data: data, encoding: .utf8) else { return nil }

            let bundlePattern = #"https:\/\/open(?:-exp)?\.spotifycdn\.com\/cdn\/build\/web-player\/[a-zA-Z0-9\-_.]+\.js"#
            let regex = try NSRegularExpression(pattern: bundlePattern)
            let matches = regex.matches(in: html, range: NSRange(html.startIndex..., in: html))

            var bundleURLs: [String] = []
            var seen = Set<String>()
            for match in matches {
                guard let range = Range(match.range, in: html) else { continue }
                let jsURLString = String(html[range])
                if seen.insert(jsURLString).inserted {
                    bundleURLs.append(jsURLString)
                }
            }

            // Prefer the main web-player bundle first for clientVersion + xpui route discovery.
            if let mainIndex = bundleURLs.firstIndex(where: { $0.contains("/web-player.") }) {
                let main = bundleURLs.remove(at: mainIndex)
                bundleURLs.insert(main, at: 0)
            }

            var extractedHashes: [String: String] = [:]
            // The web player now serves its version inside the base64 "appServerConfig"
            // script tag; the old clientVersion:"…" literal is gone from the JS bundles.
            var clientVersion = extractClientVersion(fromServerConfig: html)
            var jsPackURL: String?
            var mainJsContent: String?

            for jsURLString in bundleURLs.prefix(8) {
                guard let jsURL = URL(string: jsURLString) else { continue }
                let (jsData, _) = try await URLSession.shared.data(from: jsURL)
                guard let jsContent = String(data: jsData, encoding: .utf8) else { continue }

                if jsPackURL == nil, jsURLString.contains("/web-player.") {
                    jsPackURL = jsURLString
                    mainJsContent = jsContent
                    if clientVersion == nil {
                        clientVersion = extractClientVersion(from: jsContent)
                    }
                }

                let hashes = try extractOperationHashes(from: jsContent)
                extractedHashes.merge(hashes) { _, new in new }
            }

            // Pull route chunks that historically hold search / track / collection ops.
            if let mainJsContent {
                for xpuiName in ["xpui-routes-search", "xpui-routes-track-v2", "xpui-routes-collection", "xpui-routes-home", "xpui-routes-profile"] {
                    if let extra = try await fetchXpuiChunk(content: mainJsContent, xpuiName: xpuiName) {
                        let hashes = try extractOperationHashes(from: extra)
                        extractedHashes.merge(hashes) { _, new in new }
                    }
                }
            }

            guard !extractedHashes.isEmpty else { return nil }
            return ScrapeResult(hashes: extractedHashes, clientVersion: clientVersion, jsPackURL: jsPackURL)
        } catch {
            print("[SpotifyAPQRegistry] Hash extraction failed: \(error.localizedDescription)")
            return nil
        }
    }

    private static func extractOperationHashes(from content: String) throws -> [String: String] {
        var hashes: [String: String] = [:]

        // Classic APQ tuple: "OperationName","query|mutation","<64-hex>"
        let classic = try NSRegularExpression(pattern: #"\"([A-Za-z][A-Za-z0-9_]*)\",\"(?:query|mutation)\",\"([a-f0-9]{64})\""#)
        let range = NSRange(location: 0, length: content.utf16.count)
        for match in classic.matches(in: content, options: [], range: range) {
            guard
                let operationRange = Range(match.range(at: 1), in: content),
                let hashRange = Range(match.range(at: 2), in: content)
            else { continue }
            let name = String(content[operationRange])
            // Skip obvious non-operation identifiers.
            guard name.count >= 3, name != "query", name != "mutation" else { continue }
            hashes[name] = String(content[hashRange])
        }

        // Newer object form: operationName:"getTrack" ... sha256Hash:"..."
        // Keep associations within a short window to reduce false pairing.
        let namedOps = try NSRegularExpression(pattern: #"operationName[\"']?\s*[:=]\s*[\"']([A-Za-z][A-Za-z0-9_]*)[\"']"#)
        let hashLiteral = try NSRegularExpression(pattern: #"(?:sha256Hash|hash)[\"']?\s*[:=]\s*[\"']([a-f0-9]{64})[\"']"#)
        let opMatches = namedOps.matches(in: content, options: [], range: range)
        let hashMatches = hashLiteral.matches(in: content, options: [], range: range)
        for opMatch in opMatches {
            guard let opRange = Range(opMatch.range(at: 1), in: content) else { continue }
            let opName = String(content[opRange])
            let opEnd = opMatch.range.location + opMatch.range.length
            // Nearest hash within ~400 chars after the operationName.
            let window = NSRange(location: opEnd, length: min(400, content.utf16.count - opEnd))
            guard window.length > 0 else { continue }
            if let nearest = hashMatches.first(where: { NSLocationInRange($0.range.location, window) }),
               let hashRange = Range(nearest.range(at: 1), in: content) {
                hashes[opName] = String(content[hashRange])
            }
        }

        return hashes
    }

    private static func extractClientVersion(from content: String) -> String? {
        let components = content.components(separatedBy: "clientVersion:\"")
        guard components.count > 1,
              let versionPart = components.last,
              let foundVersion = versionPart.components(separatedBy: "\"").first,
              !foundVersion.isEmpty
        else { return nil }
        return foundVersion
    }

    /// Reads the live web-player client version from the base64 `appServerConfig`
    /// script tag embedded in open.spotify.com's HTML (the current web player layout).
    private static func extractClientVersion(fromServerConfig html: String) -> String? {
        let pattern = #"<script id="appServerConfig" type="text/plain">([^<]+)</script>"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let range = Range(match.range(at: 1), in: html) else { return nil }
        let base64 = String(html[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = Data(base64Encoded: base64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let version = json["clientVersion"] as? String,
              !version.isEmpty else { return nil }
        return version
    }

    private static func fetchXpuiChunk(content: String, xpuiName: String) async throws -> String? {
        let searchString = ":\"\(xpuiName)\""
        guard let range = content.range(of: searchString) else { return nil }
        let prefix = String(content[..<range.lowerBound])
        guard let routeNum = prefix.components(separatedBy: ",").last else { return nil }
        let hashPattern = try Regex("\(routeNum):\"([a-f0-9]+)\"")
        guard let match = content.firstMatch(of: hashPattern) else { return nil }
        let routeHash = String(match.output[1].substring!)
        let extraJsUrlString = "https://open.spotifycdn.com/cdn/build/web-player/\(xpuiName).\(routeHash).js"
        guard let extraJsUrl = URL(string: extraJsUrlString) else { return nil }
        let (extraJsData, _) = try await URLSession.shared.data(from: extraJsUrl)
        return String(data: extraJsData, encoding: .utf8)
    }
}


// MARK: - Consolidated from LightweightSpotifyJSEngine.swift


final class LightweightSpotifyJSEngine: @unchecked Sendable {
    static let shared = LightweightSpotifyJSEngine()

    private let jsContext: JSContext
    private let lock = NSLock()

    private init() {
        jsContext = JSContext()!
        jsContext.exceptionHandler = { _, exception in
            print("[JSEngine Exception]: \(exception?.toString() ?? "Unknown error")")
        }

        // Minimal Web Crypto–style helpers used by some Spotify token scripts.
        jsContext.evaluateScript("""
        var globalThis = this;
        if (typeof console === 'undefined') {
          var console = { log: function(){}, warn: function(){}, error: function(){} };
        }
        """)
    }

    /// Evaluates a JS script and returns the result value.
    @discardableResult
    func evaluate(script: String) -> JSValue? {
        lock.lock()
        defer { lock.unlock() }
        return jsContext.evaluateScript(script)
    }

    /// Calls a named global function with JSON-serializable arguments.
    func call(functionName: String, arguments: [Any] = []) -> JSValue? {
        lock.lock()
        defer { lock.unlock() }
        guard let fn = jsContext.objectForKeyedSubscript(functionName), fn.isObject else {
            return nil
        }
        return fn.call(withArguments: arguments)
    }

    /// Loads a remote JS snippet (e.g. a small helper from CDN) and evaluates it.
    func loadRemoteScript(from url: URL) async throws -> JSValue? {
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        guard let script = String(data: data, encoding: .utf8) else {
            throw URLError(.cannotDecodeContentData)
        }
        return evaluate(script: script)
    }
}
