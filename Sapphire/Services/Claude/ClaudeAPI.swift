//
//  ClaudeAPI.swift
//  Sapphire
//
//  Anthropic Messages API client backing the in-notch Claude chat panel.
//

import Foundation

struct ClaudeChatMessage: Identifiable, Equatable {
    enum Role: String {
        case user
        case assistant
    }

    let id: UUID
    let role: Role
    var content: String

    init(id: UUID = UUID(), role: Role, content: String) {
        self.id = id
        self.role = role
        self.content = content
    }
}

enum ClaudeAPIError: LocalizedError {
    case missingAPIKey
    case invalidResponse
    case server(status: Int, message: String)
    case decoding

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "No Anthropic API key configured."
        case .invalidResponse:
            return "Received an unexpected response from Claude."
        case .server(let status, let message):
            return "Claude API error (\(status)): \(message)"
        case .decoding:
            return "Couldn't parse Claude's response."
        }
    }
}

/// Minimal streaming client for the Anthropic Messages API (https://api.anthropic.com/v1/messages).
/// Swift has no official first-party Anthropic SDK, so this talks to the REST/SSE API directly.
final class ClaudeAPI {
    static let shared = ClaudeAPI()
    private init() {}

    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private static let apiVersion = "2023-06-01"
    private static let model = "claude-opus-5"
    private static let maxTokens = 4096
    private static let systemPrompt = "You are Claude, integrated directly into Sapphire, a macOS notch utility app. Keep answers concise and conversational, formatted as plain text (no markdown headers) since this renders in a small chat panel."

    /// Streams an assistant reply for the given conversation. `onDelta` is called on the main
    /// actor with each incremental text chunk as it arrives.
    func streamReply(
        for history: [ClaudeChatMessage],
        onDelta: @escaping @MainActor (String) -> Void
    ) async throws {
        let apiKey = APIKeyManager.shared.anthropicAPIKey
        guard !apiKey.isEmpty else { throw ClaudeAPIError.missingAPIKey }

        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(Self.apiVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")

        let payload: [String: Any] = [
            "model": Self.model,
            "max_tokens": Self.maxTokens,
            "system": Self.systemPrompt,
            "stream": true,
            "messages": history.suffix(40).map { ["role": $0.role.rawValue, "content": $0.content] },
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw ClaudeAPIError.invalidResponse }

        guard httpResponse.statusCode == 200 else {
            var body = ""
            for try await line in bytes.lines { body += line }
            throw ClaudeAPIError.server(status: httpResponse.statusCode, message: Self.extractErrorMessage(from: body) ?? "HTTP \(httpResponse.statusCode)")
        }

        for try await line in bytes.lines {
            guard line.hasPrefix("data: ") else { continue }
            let jsonString = String(line.dropFirst("data: ".count))
            guard let data = jsonString.data(using: .utf8),
                  let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = event["type"] as? String else { continue }

            switch type {
            case "content_block_delta":
                guard let delta = event["delta"] as? [String: Any],
                      delta["type"] as? String == "text_delta",
                      let text = delta["text"] as? String else { continue }
                await onDelta(text)

            case "error":
                let message = (event["error"] as? [String: Any])?["message"] as? String ?? "Unknown error"
                throw ClaudeAPIError.server(status: httpResponse.statusCode, message: message)

            case "message_stop":
                return

            default:
                continue
            }
        }
    }

    private static func extractErrorMessage(from body: String) -> String? {
        guard let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = json["error"] as? [String: Any] else { return nil }
        return error["message"] as? String
    }
}
