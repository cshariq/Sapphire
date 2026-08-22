//
//  GeminiAPI.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-10

import Foundation
import Combine

// MARK: - Live API Configuration

struct GeminiLiveConfiguration {
    var apiKey: String {
        APIKeyManager.shared.googleGeminiAPIKey
    }

    var model: String {
        "models/gemini-2.5-flash-native-audio-preview-12-2025"
    }

    var voiceName: String {
        "Aoede"
    }

    var systemInstruction: String? {
        "You are Sapphire, a concise voice assistant on macOS. You receive a live view of the user's screen as JPEG frames — look at those frames and talk about what is actually on screen. Speak naturally in short sentences. Never output markdown, headers, or internal reasoning — only speak aloud."
    }
}

// MARK: - WebSocket URL

extension GeminiAPI {
    static func liveWebSocketURL(apiKey: String) -> URL {
        URL(string: "wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent?key=\(apiKey)")!
    }
}

// MARK: - Message Types

enum GeminiLiveServerMessage {
    case setupComplete
    case serverContent(modelTurn: [String: Any]?, turnComplete: Bool, interrupted: Bool, speechState: String?)
    case inputTranscription(text: String, finished: Bool)
    case outputTranscription(text: String, finished: Bool)
    case toolCall(functionCalls: [[String: Any]])
    case toolCallCancellation(ids: [String])
    case error(message: String)
}

enum GeminiLiveError: LocalizedError {
    case websocketError(String)
    case apiError(String)
    case disconnected
    case invalidMessage
    case setupTimeout

    var errorDescription: String? {
        switch self {
        case .websocketError(let msg): return "WebSocket error: \(msg)"
        case .apiError(let msg): return "Gemini Live API error: \(msg)"
        case .disconnected: return "Disconnected from Gemini Live"
        case .invalidMessage: return "Invalid message from server"
        case .setupTimeout: return "Gemini Live setup timed out"
        }
    }
}

// MARK: - Gemini API

struct GeminiAPI {
    static let modelName = "models/gemini-2.0-flash-exp"
}

// MARK: - WebSocket Session (Official JSON Live API)

@MainActor
final class GeminiLiveSession: NSObject, ObservableObject, URLSessionWebSocketDelegate {
    @Published var isConnected = false
    @Published var isConnecting = false
    @Published private(set) var isSetupComplete = false

    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession!
    private var pendingSetup: [String: Any]?

    let serverMessagePublisher = PassthroughSubject<GeminiLiveServerMessage, Never>()
    let connectionErrorPublisher = PassthroughSubject<Error, Never>()

    override init() {
        super.init()
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 3600
        config.timeoutIntervalForResource = 3600
        config.waitsForConnectivity = true
        urlSession = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }

    func connect(
        apiKey: String,
        model: String,
        systemInstruction: String?,
        generationConfig: [String: Any]?,
        voiceName: String = "Aoede"
    ) {
        guard !isConnected && !isConnecting else { return }
        isConnecting = true
        isSetupComplete = false
        pendingSetup = Self.makeSetupMessage(
            model: model,
            systemInstruction: systemInstruction,
            generationConfig: generationConfig,
            voiceName: voiceName
        )

        let url = GeminiAPI.liveWebSocketURL(apiKey: apiKey)
        webSocketTask = urlSession.webSocketTask(with: url)
        webSocketTask?.resume()
        receiveMessages()
    }

    func disconnect() {
        isConnected = false
        isConnecting = false
        isSetupComplete = false
        pendingSetup = nil
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
    }

    func sendRealtimeAudio(_ audioData: Data) {
        guard isSetupComplete else { return }
        let message: [String: Any] = [
            "realtimeInput": [
                "audio": [
                    "mimeType": "audio/pcm;rate=16000",
                    "data": audioData.base64EncodedString()
                ]
            ]
        ]
        sendJSON(message)
    }

    func sendRealtimeVideo(_ jpegData: Data) {
        guard isSetupComplete, !jpegData.isEmpty else { return }
        let message: [String: Any] = [
            "realtimeInput": [
                "video": [
                    "mimeType": "image/jpeg",
                    "data": jpegData.base64EncodedString()
                ]
            ]
        ]
        sendJSON(message)
    }

    func sendClientContent(text: String? = nil, turnComplete: Bool = false) {
        guard isSetupComplete else { return }
        var clientContent: [String: Any] = [:]
        if let text, !text.isEmpty {
            clientContent["turns"] = [
                [
                    "role": "user",
                    "parts": [["text": text]]
                ]
            ]
        }
        if turnComplete {
            clientContent["turnComplete"] = true
        }
        sendJSON(["clientContent": clientContent])
    }

    func sendToolResponse(functionResponses: [[String: Any]]) {
        guard isSetupComplete else { return }
        sendJSON(["toolResponse": ["functionResponses": functionResponses]])
    }

    func sendAudioStreamEnd() {
        guard isSetupComplete else { return }
        sendJSON(["realtimeInput": ["audioStreamEnd": true]])
    }

    // MARK: - URLSessionWebSocketDelegate

    nonisolated func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocol: String?
    ) {
        Task { @MainActor in
            self.isConnecting = false
            self.isConnected = true
            if let setup = self.pendingSetup {
                self.sendJSON(setup)
                self.pendingSetup = nil
            }
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        Task { @MainActor in
            self.isConnected = false
            self.isConnecting = false
            self.isSetupComplete = false
        }
    }

    // MARK: - Private

    private static func makeSetupMessage(
        model: String,
        systemInstruction: String?,
        generationConfig: [String: Any]?,
        voiceName: String
    ) -> [String: Any] {
        var genCfg = generationConfig ?? [:]
        if genCfg["responseModalities"] == nil {
            genCfg["responseModalities"] = ["AUDIO"]
        }
        if genCfg["speechConfig"] == nil {
            genCfg["speechConfig"] = [
                "voiceConfig": [
                    "prebuiltVoiceConfig": [
                        "voiceName": voiceName
                    ]
                ]
            ]
        }

        var setup: [String: Any] = [
            "model": model,
            "generationConfig": genCfg,
            "inputAudioTranscription": [:],
            "outputAudioTranscription": [:]
        ]

        if let instruction = systemInstruction, !instruction.isEmpty {
            setup["systemInstruction"] = ["parts": [["text": instruction]]]
        }

        return ["setup": setup]
    }

    private func sendJSON(_ object: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: object),
              let text = String(data: data, encoding: .utf8) else { return }

        webSocketTask?.send(.string(text)) { [weak self] error in
            if let error {
                Task { @MainActor in
                    self?.connectionErrorPublisher.send(GeminiLiveError.websocketError(error.localizedDescription))
                }
            }
        }
    }

    private func receiveMessages() {
        webSocketTask?.receive { [weak self] result in
            guard let self else { return }

            switch result {
            case .success(let message):
                let payload: Data?
                switch message {
                case .string(let text):
                    payload = text.data(using: .utf8)
                case .data(let data):
                    payload = data
                @unknown default:
                    payload = nil
                }

                if let payload, let serverMsg = decodeLiveJSONMessage(payload) {
                    Task { @MainActor in
                        if case .setupComplete = serverMsg {
                            self.isSetupComplete = true
                        }
                        if case .error(let message) = serverMsg {
                            self.connectionErrorPublisher.send(GeminiLiveError.apiError(message))
                        }
                        self.serverMessagePublisher.send(serverMsg)
                    }
                }

                self.receiveMessages()

            case .failure(let error):
                Task { @MainActor in
                    self.isConnected = false
                    self.isConnecting = false
                    self.isSetupComplete = false
                    self.connectionErrorPublisher.send(error)
                }
            }
        }
    }
}

// MARK: - JSON Live API decoding

private func decodeLiveJSONMessage(_ data: Data) -> GeminiLiveServerMessage? {
    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        return nil
    }

    if json["setupComplete"] != nil {
        return .setupComplete
    }

    if let error = json["error"] as? [String: Any] {
        let message = error["message"] as? String ?? "Unknown Gemini Live error"
        return .error(message: message)
    }

    if let serverContent = json["serverContent"] as? [String: Any] {
        if let inputTx = serverContent["inputTranscription"] as? [String: Any],
           let text = inputTx["text"] as? String {
            let finished = inputTx["finished"] as? Bool ?? false
            return .inputTranscription(text: text, finished: finished)
        }

        if let outputTx = serverContent["outputTranscription"] as? [String: Any],
           let text = outputTx["text"] as? String {
            let finished = outputTx["finished"] as? Bool ?? false
            return .outputTranscription(text: text, finished: finished)
        }

        let turnComplete = serverContent["turnComplete"] as? Bool ?? false
        let interrupted = serverContent["interrupted"] as? Bool ?? false
        let speechState = serverContent["speechState"] as? String
        var modelTurn: [String: Any]?

        if let turn = serverContent["modelTurn"] as? [String: Any],
           let parts = turn["parts"] as? [[String: Any]] {
            var parsedParts: [[String: Any]] = []
            for part in parts {
                var parsed = part
                if let inlineData = part["inlineData"] as? [String: Any],
                   let mime = inlineData["mimeType"] as? String,
                   mime.contains("audio"),
                   let b64 = inlineData["data"] as? String,
                   let audioData = Data(base64Encoded: b64) {
                    parsed["audioData"] = audioData
                }
                parsedParts.append(parsed)
            }
            modelTurn = ["parts": parsedParts]
        }

        return .serverContent(
            modelTurn: modelTurn,
            turnComplete: turnComplete,
            interrupted: interrupted,
            speechState: speechState
        )
    }

    if let toolCall = json["toolCall"] as? [String: Any],
       let functionCalls = toolCall["functionCalls"] as? [[String: Any]] {
        return .toolCall(functionCalls: functionCalls)
    }

    if let cancellation = json["toolCallCancellation"] as? [String: Any],
       let ids = cancellation["ids"] as? [String] {
        return .toolCallCancellation(ids: ids)
    }

    return nil
}