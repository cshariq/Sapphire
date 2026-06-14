//
//  WebSocketManager.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-08-18.
//

import Foundation
import Combine

class WebSocketManager: NSObject, URLSessionWebSocketDelegate, URLSessionDelegate {
    private var webSocketTask: URLSessionWebSocketTask?
    private let accessToken: String
    private var isConnected = false
    private(set) var isConnecting = false

    public let controllerDeviceID: String

    private var session: URLSession!
    private let delegateQueue = OperationQueue()
    private var shouldReconnect = true

    private weak var privateAPIManager: SpotifyPrivateAPIManager?

    private let playerStateSubject = PassthroughSubject<PlayerState, Never>()
    var playerStatePublisher: AnyPublisher<PlayerState, Never> {
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

    private func createWebSocketTask() -> URLSessionWebSocketTask {
        let url = URL(string: "wss://dealer.spotify.com/?access_token=\(accessToken)")!
        var request = URLRequest(url: url)
        request.setValue("https://open.spotify.com", forHTTPHeaderField: "Origin")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
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

    // MARK: - URLSessionWebSocketDelegate Methods

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        self.isConnected = true
        self.isConnecting = false
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
            if let playerState = webSocketMessage.payloads?.first?.cluster?.playerState ?? webSocketMessage.payloads?.first?.state {
                let signature = PlayerStateSignature(playerState)
                guard signature != lastPublishedPlayerStateSignature else { return }
                lastPublishedPlayerStateSignature = signature
                playerStateSubject.send(playerState)
            }
        } catch {
            return
        }
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
        latestConnectionID = nil
        lastPublishedPlayerStateSignature = nil
        isConnected = false
        isConnecting = false
    }

    private var reconnectTimer: Timer?

    private func handleConnectionFailure() {
        guard shouldReconnect else { return }
        reconnect(delay: 5.0)
    }

    private func reconnect(delay: TimeInterval) {
        guard shouldReconnect, !isConnecting, reconnectTimer == nil else { return }
        disconnect(shouldReconnect: true)
        DispatchQueue.main.async {
            self.reconnectTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
                guard let self else { return }
                self.reconnectTimer = nil
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.privateAPIManager?.requestSessionReestablishment(from: self)
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

// MARK: - Decoding Structs
struct WebSocketMessage: Decodable { let payloads: [Payload]? }
struct Payload: Decodable { let cluster: Cluster?; let state: PlayerState? }
struct Cluster: Decodable { let playerState: PlayerState?; enum CodingKeys: String, CodingKey { case playerState = "player_state" } }
