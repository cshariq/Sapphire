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

    private weak var privateAPIManager: SpotifyPrivateAPIManager?

    private let playerStateSubject = PassthroughSubject<PlayerState, Never>()
    var playerStatePublisher: AnyPublisher<PlayerState, Never> {
        return playerStateSubject.eraseToAnyPublisher()
    }

    private let connectionIdSubject = PassthroughSubject<String, Never>()
    var connectionIdPublisher: AnyPublisher<String, Never> {
        return connectionIdSubject.eraseToAnyPublisher()
    }

    init(accessToken: String, client: SpotifyPrivateAPIManager, controllerDeviceID: String) {
        self.accessToken = accessToken
        self.privateAPIManager = client
        self.controllerDeviceID = controllerDeviceID

        super.init()
        self.session = URLSession(configuration: .default, delegate: self, delegateQueue: delegateQueue)
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

        webSocketTask = createWebSocketTask()
        isConnecting = true
        print("[WebSocketManager] Starting connection attempt with Controller ID: \(self.controllerDeviceID)")
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
            print("[WebSocketManager] WebSocket Task COMPLETED WITH ERROR: \(error)")
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
                print("[WebSocketManager] Receive loop failed with error: \(error.localizedDescription)")
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

                print("[WebSocketManager] Received Connection ID: \(connId). Publishing...")
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
                playerStateSubject.send(playerState)
            }
        } catch {
            print("[WebSocketManager] FAILED to decode WebSocketMessage JSON: \(error)")
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
                        print("[WebSocketManager] Ping failed: \(error)")
                        self.handleConnectionFailure()
                    }
                }
            }
        }
    }

    func disconnect() {
        pingTimer?.invalidate(); pingTimer = nil
        reconnectTimer?.invalidate(); reconnectTimer = nil
        if isConnected || isConnecting {
            webSocketTask?.cancel(with: .goingAway, reason: nil)
            isConnected = false; isConnecting = false
            print("[WebSocketManager] Disconnected.")
        }
    }

    private var reconnectTimer: Timer?

    private func handleConnectionFailure() {
        reconnect(delay: 5.0)
    }

    private func reconnect(delay: TimeInterval) {
        guard !isConnecting else { return }
        disconnect()
        print("[WebSocketManager] Attempting to reconnect in \(delay) seconds...")
        DispatchQueue.main.async {
            self.reconnectTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
                self?.privateAPIManager?.reestablishSession()
            }
        }
    }
}

// MARK: - Decoding Structs
struct WebSocketMessage: Decodable { let payloads: [Payload]? }
struct Payload: Decodable { let cluster: Cluster?; let state: PlayerState? }
struct Cluster: Decodable { let playerState: PlayerState?; enum CodingKeys: String, CodingKey { case playerState = "player_state" } }