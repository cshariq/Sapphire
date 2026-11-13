//
//  DevAgentTranscript.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-10-15
//

import Foundation

struct DevAgentMessage: Identifiable, Equatable {
    enum Role: Equatable {
        case user
        case assistant
        case tool
        case toolResult(isError: Bool)
    }

    let id: String
    let role: Role
    let text: String
    let timestamp: Date?
}

struct DevAgentSnapshot: Equatable {
    var sessionID: String?
    var sessionName: String?
    var status: String?
    var model: String?
    var entrypoint: String?
    var version: String?
    var gitBranch: String?
    var contextTokens: Int?
    var sessionOutputTokens: Int = 0
    var messages: [DevAgentMessage] = []
    var transcriptPath: String?

    var isDesktopHosted: Bool {
        guard let entrypoint = entrypoint?.lowercased() else { return false }
        return entrypoint.contains("desktop") || entrypoint.contains("vscode") || entrypoint.contains("jetbrains")
    }
}

nonisolated enum DevAgentTranscript {

    static let tailBytes = 512 * 1024
    static let messageLimit = 60

    static func snapshot(toolID: String, pid: pid_t, workingDirectory: String?) -> DevAgentSnapshot? {
        switch toolID {
        case DevToolCatalog.claude.id:
            return claudeSnapshot(pid: pid, workingDirectory: workingDirectory)
        case DevToolCatalog.codex.id:
            guard let workingDirectory,
                  let path = DevAgentSessionActivity.newestCodexRollout(forWorkingDirectory: workingDirectory) else {
                return nil
            }
            return codexSnapshot(path: path)
        default:
            return nil
        }
    }

    // MARK: - Claude

    private static func claudeSnapshot(pid: pid_t, workingDirectory: String?) -> DevAgentSnapshot? {
        var snapshot = DevAgentSnapshot()
        var directory = workingDirectory

        for root in DevAgentSessionActivity.claudeConfigRoots {
            let registry = root.appending(path: "sessions/\(pid).json")
            guard let data = try? Data(contentsOf: registry), data.count < 1 << 16,
                  let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  (json["pid"] as? Int) == Int(pid) else { continue }
            snapshot.sessionID = nonEmpty(json["sessionId"])
            snapshot.sessionName = nonEmpty(json["name"])
            snapshot.status = nonEmpty(json["status"])
            snapshot.entrypoint = nonEmpty(json["entrypoint"])
            snapshot.version = nonEmpty(json["version"])
            directory = nonEmpty(json["cwd"]) ?? directory
            break
        }

        guard let directory, let slug = DevAgentSessionActivity.projectSlug(for: directory) else {
            return snapshot.sessionID == nil ? nil : snapshot
        }

        var transcript: String?
        for root in DevAgentSessionActivity.claudeConfigRoots {
            let folder = root.appending(path: "projects/\(slug)", directoryHint: .isDirectory)
            if let sessionID = snapshot.sessionID {
                let candidate = folder.appending(path: "\(sessionID).jsonl").path
                if FileManager.default.fileExists(atPath: candidate) { transcript = candidate; break }
            } else if let newest = newestJSONL(in: folder) {
                transcript = newest
                break
            }
        }
        guard let transcript else { return snapshot }
        snapshot.transcriptPath = transcript

        var messages: [DevAgentMessage] = []
        var seenUsage = Set<String>()
        for line in tailLines(ofFile: transcript) {
            guard let json = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any] else { continue }
            let type = json["type"] as? String
            let timestamp = (json["timestamp"] as? String).flatMap(parseISODate)
            let uuid = (json["uuid"] as? String) ?? UUID().uuidString

            switch type {
            case "custom-title":
                snapshot.sessionName = nonEmpty(json["customTitle"]) ?? snapshot.sessionName
            case "agent-name":
                if snapshot.sessionName == nil { snapshot.sessionName = nonEmpty(json["agentName"]) }
            case "user":
                if json["isSidechain"] as? Bool == true { continue }
                snapshot.gitBranch = nonEmpty(json["gitBranch"]) ?? snapshot.gitBranch
                let message = json["message"] as? [String: Any]
                if let text = message?["content"] as? String {
                    appendUser(text, id: uuid, timestamp: timestamp, to: &messages)
                } else if let blocks = message?["content"] as? [[String: Any]] {
                    for (index, block) in blocks.enumerated() {
                        let blockID = "\(uuid)-\(index)"
                        switch block["type"] as? String {
                        case "text":
                            if let text = block["text"] as? String {
                                appendUser(text, id: blockID, timestamp: timestamp, to: &messages)
                            }
                        case "tool_result":
                            let isError = block["is_error"] as? Bool ?? false
                            let text = toolResultText(block["content"])
                            guard !text.isEmpty else { continue }
                            messages.append(.init(id: blockID, role: .toolResult(isError: isError), text: clip(text, 220), timestamp: timestamp))
                        default:
                            continue
                        }
                    }
                }
            case "assistant":
                if json["isSidechain"] as? Bool == true { continue }
                guard let message = json["message"] as? [String: Any] else { continue }
                snapshot.model = nonEmpty(message["model"]) ?? snapshot.model
                if let usage = message["usage"] as? [String: Any] {
                    let input = intValue(usage["input_tokens"])
                    let cacheRead = intValue(usage["cache_read_input_tokens"])
                    let cacheWrite = intValue(usage["cache_creation_input_tokens"])
                    let context = input + cacheRead + cacheWrite
                    if context > 0 { snapshot.contextTokens = context }
                    let messageID = (message["id"] as? String) ?? uuid
                    if seenUsage.insert(messageID).inserted {
                        snapshot.sessionOutputTokens += intValue(usage["output_tokens"])
                    }
                }
                for (index, block) in ((message["content"] as? [[String: Any]]) ?? []).enumerated() {
                    let blockID = "\(uuid)-\(index)"
                    switch block["type"] as? String {
                    case "text":
                        let text = (block["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !text.isEmpty else { continue }
                        messages.append(.init(id: blockID, role: .assistant, text: clip(text, 1200), timestamp: timestamp))
                    case "tool_use":
                        let name = block["name"] as? String ?? String(localized: "Tool")
                        let summary = toolInputSummary(block["input"] as? [String: Any])
                        messages.append(.init(id: blockID, role: .tool, text: summary.isEmpty ? name : "\(name) · \(summary)", timestamp: timestamp))
                    default:
                        continue
                    }
                }
            default:
                continue
            }
        }

        snapshot.messages = Array(messages.suffix(messageLimit))
        return snapshot
    }

    private static func appendUser(_ raw: String, id: String, timestamp: Date?, to messages: inout [DevAgentMessage]) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !text.hasPrefix("<"), !text.hasPrefix("[Request interrupted") else { return }
        messages.append(.init(id: id, role: .user, text: clip(text, 600), timestamp: timestamp))
    }

    private static func toolResultText(_ content: Any?) -> String {
        if let text = content as? String { return text.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let blocks = content as? [[String: Any]] {
            return blocks.compactMap { $0["text"] as? String }
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return ""
    }

    private static let summaryKeys = ["command", "file_path", "path", "pattern", "url", "query", "description", "prompt", "skill"]

    private static func toolInputSummary(_ input: [String: Any]?) -> String {
        guard let input else { return "" }
        for key in summaryKeys {
            if let value = input[key] as? String, !value.isEmpty {
                let display = key == "file_path" || key == "path" ? (value as NSString).lastPathComponent : value
                return clip(display.replacingOccurrences(of: "\n", with: " "), 140)
            }
        }
        return ""
    }

    private static func newestJSONL(in folder: URL) -> String? {
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]
        ) else { return nil }
        return entries
            .filter { $0.pathExtension == "jsonl" }
            .max { lhs, rhs in
                let l = (try? lhs.resourceValues(forKeys: Set(keys)).contentModificationDate) ?? .distantPast
                let r = (try? rhs.resourceValues(forKeys: Set(keys)).contentModificationDate) ?? .distantPast
                return l < r
            }?.path
    }

    // MARK: - Codex

    private static func codexSnapshot(path: String) -> DevAgentSnapshot? {
        var snapshot = DevAgentSnapshot(transcriptPath: path)
        snapshot.sessionID = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        var messages: [DevAgentMessage] = []
        var index = 0

        for line in tailLines(ofFile: path) {
            index += 1
            guard let json = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any],
                  let payload = json["payload"] as? [String: Any] else { continue }
            let timestamp = (json["timestamp"] as? String).flatMap(parseISODate)
            let id = "codex-\(index)"

            switch (json["type"] as? String, payload["type"] as? String) {
            case ("turn_context", _):
                snapshot.model = nonEmpty(payload["model"]) ?? snapshot.model
            case ("response_item", "message"):
                let role = payload["role"] as? String
                let text = ((payload["content"] as? [[String: Any]]) ?? [])
                    .compactMap { $0["text"] as? String }
                    .joined(separator: "\n")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty, !text.hasPrefix("<") else { continue }
                if role == "user" {
                    messages.append(.init(id: id, role: .user, text: clip(text, 600), timestamp: timestamp))
                } else if role == "assistant" {
                    messages.append(.init(id: id, role: .assistant, text: clip(text, 1200), timestamp: timestamp))
                }
            case ("response_item", "function_call"), ("response_item", "custom_tool_call"), ("response_item", "local_shell_call"):
                let name = payload["name"] as? String ?? "shell"
                var summary = ""
                if let arguments = payload["arguments"] as? String,
                   let data = arguments.data(using: .utf8),
                   let parsed = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
                    if let command = parsed["command"] as? [String] {
                        summary = clip(command.joined(separator: " "), 140)
                    } else {
                        summary = toolInputSummary(parsed)
                    }
                } else if let input = payload["input"] as? String {
                    summary = clip(input.replacingOccurrences(of: "\n", with: " "), 140)
                }
                messages.append(.init(id: id, role: .tool, text: summary.isEmpty ? name : "\(name) · \(summary)", timestamp: timestamp))
            case ("response_item", "function_call_output"), ("response_item", "custom_tool_call_output"):
                var text = ""
                if let output = payload["output"] as? String {
                    if let data = output.data(using: .utf8),
                       let parsed = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                       let inner = parsed["output"] as? String {
                        text = inner
                    } else {
                        text = output
                    }
                }
                text = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }
                messages.append(.init(id: id, role: .toolResult(isError: false), text: clip(text, 220), timestamp: timestamp))
            case ("event_msg", "token_count"):
                if let info = payload["info"] as? [String: Any] {
                    if let last = info["last_token_usage"] as? [String: Any] {
                        let context = intValue(last["input_tokens"])
                        if context > 0 { snapshot.contextTokens = context }
                    }
                    if let total = info["total_token_usage"] as? [String: Any] {
                        snapshot.sessionOutputTokens = intValue(total["output_tokens"])
                    }
                }
            default:
                continue
            }
        }
        snapshot.messages = Array(messages.suffix(messageLimit))
        return snapshot
    }

    // MARK: - Helpers

    static func tailLines(ofFile path: String, bytes: Int = tailBytes) -> [Data] {
        guard let handle = FileHandle(forReadingAtPath: path) else { return [] }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        let start = size > UInt64(bytes) ? size - UInt64(bytes) : 0
        try? handle.seek(toOffset: start)
        guard let data = try? handle.readToEnd(), !data.isEmpty else { return [] }

        var lines = data.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true)
        if start > 0, !lines.isEmpty { lines.removeFirst() }
        return lines.map { Data($0) }
    }

    static func intValue(_ value: Any?) -> Int {
        if let number = value as? NSNumber { return number.intValue }
        if let int = value as? Int { return int }
        return 0
    }

    private static func nonEmpty(_ value: Any?) -> String? {
        guard let string = value as? String, !string.isEmpty else { return nil }
        return string
    }

    static func clip(_ text: String, _ limit: Int) -> String {
        text.count > limit ? String(text.prefix(limit)) + "…" : text
    }

    private static let isoWithFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let isoPlain = ISO8601DateFormatter()
    private static let formatterLock = NSLock()

    static func parseISODate(_ string: String) -> Date? {
        formatterLock.lock()
        defer { formatterLock.unlock() }
        return isoWithFraction.date(from: string) ?? isoPlain.date(from: string)
    }
}