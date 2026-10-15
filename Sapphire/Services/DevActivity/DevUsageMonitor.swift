//
//  DevUsageMonitor.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-10-15
//

import Combine
import Foundation
import SQLite3
import SwiftUI

struct DevUsageMeter: Identifiable, Equatable {
    let label: String
    let usedFraction: Double
    let caption: String?

    var id: String { label }
}

struct DevUsageStat: Identifiable, Equatable {
    let label: String
    let value: String

    var id: String { label }
}

struct DevUsageCard: Identifiable, Equatable {
    let id: String
    let title: String
    let symbol: String
    let tint: Color
    var headline: String
    var subtitle: String?
    var meters: [DevUsageMeter] = []
    var stats: [DevUsageStat] = []
    var daily: [Double] = []
    var footnote: String?
    var compactValue: String
}

@MainActor
final class DevUsageMonitor: ObservableObject {
    static let shared = DevUsageMonitor()

    @Published private(set) var cards: [DevUsageCard] = []
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastRefresh: Date?

    private let collector = DevUsageCollector()
    private let queue = DispatchQueue(label: "com.shariq.sapphire.devusage", qos: .utility)
    private var observers = 0
    private var timer: Timer?

    private static let refreshInterval: TimeInterval = 60

    private init() {}

    func beginObserving() {
        observers += 1
        refreshIfStale()
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        timer?.tolerance = 10
    }

    func endObserving() {
        observers = max(0, observers - 1)
        guard observers == 0 else { return }
        timer?.invalidate()
        timer = nil
    }

    func refreshIfStale(maxAge: TimeInterval = 45) {
        if let lastRefresh, Date().timeIntervalSince(lastRefresh) < maxAge { return }
        refresh()
    }

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        let collector = collector
        queue.async { [weak self] in
            let cards = collector.collect(now: Date())
            Task { @MainActor in
                guard let self else { return }
                self.isRefreshing = false
                self.lastRefresh = Date()
                if cards != self.cards { self.cards = cards }
            }
        }
    }
}

// MARK: - Collection

nonisolated final class DevUsageCollector: @unchecked Sendable {

    private let claude = ClaudeUsageReader()
    private let codex = CodexUsageReader()
    private let gemini = GeminiCLIUsageReader()

    func collect(now: Date) -> [DevUsageCard] {
        let window = UsageWindow(now: now)
        var cards: [DevUsageCard] = []
        if let card = claude.card(window: window) { cards.append(card) }
        if let card = codex.card(window: window) { cards.append(card) }
        if let card = AntigravityUsageReader.card(window: window) { cards.append(card) }
        if let card = CursorUsageReader.card(window: window) { cards.append(card) }
        if let card = gemini.card(window: window) { cards.append(card) }
        return cards
    }
}

nonisolated struct UsageWindow {
    let now: Date
    let startOfToday: Date
    let fiveHoursAgo: Date
    let dayStarts: [Date]

    init(now: Date) {
        self.now = now
        let calendar = Calendar.current
        startOfToday = calendar.startOfDay(for: now)
        fiveHoursAgo = now.addingTimeInterval(-5 * 3600)
        dayStarts = (0..<7).reversed().compactMap { calendar.date(byAdding: .day, value: -$0, to: calendar.startOfDay(for: now)) }
    }

    var weekStart: Date { dayStarts.first ?? startOfToday }

    func dayIndex(of date: Date) -> Int? {
        guard date >= weekStart, date <= now else { return nil }
        return dayStarts.lastIndex { $0 <= date }
    }
}

nonisolated enum UsageFormat {
    static func tokens(_ value: Int) -> String {
        let double = Double(value)
        switch double {
        case 1_000_000_000...: return String(format: "%.1fB", double / 1_000_000_000)
        case 1_000_000...: return String(format: "%.1fM", double / 1_000_000)
        case 10_000...: return String(format: "%.0fK", double / 1_000)
        case 1_000...: return String(format: "%.1fK", double / 1_000)
        default: return "\(value)"
        }
    }

    static func dollars(_ value: Double) -> String {
        value >= 100 ? String(format: "$%.0f", value) : String(format: "$%.2f", value)
    }

    static func countdown(to date: Date, from now: Date) -> String {
        let seconds = Int(date.timeIntervalSince(now))
        guard seconds > 0 else { return "resetting" }
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3600
        let minutes = (seconds % 3600) / 60
        if days > 0 { return "resets in \(days)d \(hours)h" }
        if hours > 0 { return "resets in \(hours)h \(minutes)m" }
        return "resets in \(max(1, minutes))m"
    }
}

// MARK: - Incremental JSONL

nonisolated struct AppendedLines {
    var offset: UInt64 = 0
    var modified: Date = .distantPast

    mutating func read(path: String, modified newModified: Date, size: UInt64) -> (lines: [Data], restarted: Bool)? {
        guard newModified != modified || size != offset else { return nil }
        var restarted = false
        if size < offset {
            offset = 0
            restarted = true
        }
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        try? handle.seek(toOffset: offset)
        guard let data = try? handle.readToEnd(), !data.isEmpty else {
            modified = newModified
            return ([], restarted)
        }
        guard let lastNewline = data.lastIndex(of: UInt8(ascii: "\n")) else { return ([], restarted) }
        let complete = data[data.startIndex...lastNewline]
        offset += UInt64(complete.count)
        modified = newModified
        return (Self.lines(in: complete), restarted)
    }

    static func lines(in data: Data) -> [Data] {
        data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) -> [Data] in
            guard let base = buffer.baseAddress else { return [] }
            var lines: [Data] = []
            var start = 0
            let count = buffer.count
            while start < count {
                let remaining = count - start
                let end: Int
                if let hit = memchr(base + start, Int32(UInt8(ascii: "\n")), remaining) {
                    end = base.distance(to: UnsafeRawPointer(hit))
                } else {
                    end = count
                }
                if end > start { lines.append(Data(bytes: base + start, count: end - start)) }
                start = end + 1
            }
            return lines
        }
    }
}

extension Data {
    nonisolated func containsBytes(_ needle: Data) -> Bool {
        guard !needle.isEmpty else { return true }
        return withUnsafeBytes { (haystack: UnsafeRawBufferPointer) in
            needle.withUnsafeBytes { (pattern: UnsafeRawBufferPointer) in
                guard let h = haystack.baseAddress, let p = pattern.baseAddress else { return false }
                return memmem(h, haystack.count, p, pattern.count) != nil
            }
        }
    }
}

nonisolated enum UsageFiles {
    struct Entry {
        let path: String
        let modified: Date
        let size: UInt64
    }

    static func files(under root: URL, extension ext: String, since: Date, depth: Int) -> [Entry] {
        var result: [Entry] = []
        walk(root, ext: ext, since: since, depth: depth, into: &result)
        return result
    }

    private static func walk(_ directory: URL, ext: String, since: Date, depth: Int, into result: inout [Entry]) {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isDirectoryKey, .fileSizeKey]
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]
        ) else { return }
        for entry in entries {
            guard let values = try? entry.resourceValues(forKeys: Set(keys)) else { continue }
            if values.isDirectory == true {
                if depth > 0 { walk(entry, ext: ext, since: since, depth: depth - 1, into: &result) }
            } else if entry.pathExtension == ext,
                      let modified = values.contentModificationDate, modified >= since {
                result.append(Entry(path: entry.path, modified: modified, size: UInt64(values.fileSize ?? 0)))
            }
        }
    }
}

// MARK: - Claude Code

nonisolated final class ClaudeUsageReader {

    private struct Record {
        let date: Date
        let model: String
        let input: Int
        let output: Int
        let cacheRead: Int
        let cacheWrite5m: Int
        let cacheWrite1h: Int
        let session: String

        var totalTokens: Int { input + output + cacheRead + cacheWrite5m + cacheWrite1h }

        var cost: Double {
            let price = ClaudePricing.price(for: model)
            let millions = 1_000_000.0
            return Double(input) / millions * price.input
                + Double(output) / millions * price.output
                + Double(cacheRead) / millions * price.cacheRead
                + Double(cacheWrite5m) / millions * price.input * 1.25
                + Double(cacheWrite1h) / millions * price.input * 2
        }
    }

    private var readers: [String: AppendedLines] = [:]
    private var recordsByFile: [String: [String: Record]] = [:]

    private static let usageMarker = Data("\"usage\"".utf8)
    private static let assistantMarker = Data("\"assistant\"".utf8)

    func card(window: UsageWindow) -> DevUsageCard? {
        let roots = DevAgentSessionActivity.claudeConfigRoots
            .map { $0.appending(path: "projects", directoryHint: .isDirectory) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !roots.isEmpty else { return nil }

        let since = window.weekStart.addingTimeInterval(-3600)
        var live = Set<String>()
        for root in roots {
            for file in UsageFiles.files(under: root, extension: "jsonl", since: since, depth: 3) {
                live.insert(file.path)
                ingest(file)
            }
        }
        recordsByFile = recordsByFile.filter { live.contains($0.key) }
        readers = readers.filter { live.contains($0.key) }

        var unique: [String: Record] = [:]
        for records in recordsByFile.values {
            for (id, record) in records where record.date >= window.weekStart {
                unique[id] = record
            }
        }
        let records = Array(unique.values)

        let today = records.filter { $0.date >= window.startOfToday }
        let recent = records.filter { $0.date >= window.fiveHoursAgo }
        let todayCost = today.reduce(0) { $0 + $1.cost }
        let todayTokens = today.reduce(0) { $0 + $1.totalTokens }
        let weekCost = records.reduce(0) { $0 + $1.cost }
        let recentCost = recent.reduce(0) { $0 + $1.cost }
        let sessions = Set(today.map(\.session)).count

        var daily = Array(repeating: 0.0, count: 7)
        for record in records {
            if let index = window.dayIndex(of: record.date) { daily[index] += record.cost }
        }

        var byModel: [String: Double] = [:]
        for record in today { byModel[ClaudePricing.displayName(for: record.model), default: 0] += record.cost }
        let topModel = byModel.max { $0.value < $1.value }?.key

        var stats = [
            DevUsageStat(label: "Last 5 hours", value: "\(UsageFormat.dollars(recentCost)) · \(UsageFormat.tokens(recent.reduce(0) { $0 + $1.totalTokens }))"),
            DevUsageStat(label: "7 days", value: UsageFormat.dollars(weekCost)),
            DevUsageStat(label: "Output today", value: UsageFormat.tokens(today.reduce(0) { $0 + $1.output })),
        ]
        if let topModel { stats.append(DevUsageStat(label: "Top model", value: topModel)) }

        return DevUsageCard(
            id: "claude",
            title: "Claude Code",
            symbol: DevToolCatalog.claude.symbol,
            tint: DevToolCatalog.claude.tint,
            headline: "\(UsageFormat.tokens(todayTokens)) tokens today",
            subtitle: "≈ \(UsageFormat.dollars(todayCost)) API value · \(sessions) session\(sessions == 1 ? "" : "s")",
            stats: stats,
            daily: daily,
            footnote: "From local transcripts. Cost is the API-price equivalent, not your plan's bill.",
            compactValue: UsageFormat.tokens(todayTokens)
        )
    }

    private func ingest(_ file: UsageFiles.Entry) {
        var reader = readers[file.path] ?? AppendedLines()
        guard let (lines, restarted) = reader.read(path: file.path, modified: file.modified, size: file.size) else { return }
        readers[file.path] = reader
        var records = restarted ? [:] : (recordsByFile[file.path] ?? [:])
        let session = ((file.path as NSString).lastPathComponent as NSString).deletingPathExtension

        for line in lines {
            guard line.containsBytes(Self.usageMarker), line.containsBytes(Self.assistantMarker),
                  let json = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any],
                  json["type"] as? String == "assistant",
                  let message = json["message"] as? [String: Any],
                  let usage = message["usage"] as? [String: Any],
                  let timestamp = (json["timestamp"] as? String).flatMap(DevAgentTranscript.parseISODate) else { continue }
            let model = message["model"] as? String ?? ""
            guard model != "<synthetic>" else { continue }
            let id = (message["id"] as? String) ?? (json["requestId"] as? String) ?? (json["uuid"] as? String) ?? UUID().uuidString

            let cacheWrite = DevAgentTranscript.intValue(usage["cache_creation_input_tokens"])
            var write1h = 0
            var write5m = cacheWrite
            if let split = usage["cache_creation"] as? [String: Any] {
                write1h = DevAgentTranscript.intValue(split["ephemeral_1h_input_tokens"])
                write5m = DevAgentTranscript.intValue(split["ephemeral_5m_input_tokens"])
                if write1h + write5m == 0 { write5m = cacheWrite }
            }
            records[id] = Record(
                date: timestamp,
                model: model,
                input: DevAgentTranscript.intValue(usage["input_tokens"]),
                output: DevAgentTranscript.intValue(usage["output_tokens"]),
                cacheRead: DevAgentTranscript.intValue(usage["cache_read_input_tokens"]),
                cacheWrite5m: write5m,
                cacheWrite1h: write1h,
                session: (json["sessionId"] as? String) ?? session
            )
        }
        recordsByFile[file.path] = records
    }
}

nonisolated enum ClaudePricing {
    struct Price {
        let input: Double
        let output: Double
        let cacheRead: Double
    }

    private static let table: [(prefix: String, price: Price, name: String)] = [
        ("claude-fable-5-1", Price(input: 10, output: 50, cacheRead: 0.25), "Fable 5.1"),
        ("claude-mythos-5-1", Price(input: 10, output: 50, cacheRead: 0.25), "Mythos 5.1"),
        ("claude-fable-5", Price(input: 10, output: 50, cacheRead: 1.0), "Fable 5"),
        ("claude-opus-5-5", Price(input: 4, output: 20, cacheRead: 0.20), "Opus 5.5"),
        ("claude-opus-5", Price(input: 5, output: 25, cacheRead: 0.50), "Opus 5"),
        ("claude-opus-4-8", Price(input: 5, output: 25, cacheRead: 0.50), "Opus 4.8"),
        ("claude-opus-4-7", Price(input: 5, output: 25, cacheRead: 0.50), "Opus 4.7"),
        ("claude-opus-4-6", Price(input: 5, output: 25, cacheRead: 0.50), "Opus 4.6"),
        ("claude-opus-4-5", Price(input: 5, output: 25, cacheRead: 0.50), "Opus 4.5"),
        ("claude-opus-4", Price(input: 15, output: 75, cacheRead: 1.50), "Opus 4"),
        ("claude-sonnet-5-5", Price(input: 2, output: 10, cacheRead: 0.20), "Sonnet 5.5"),
        ("claude-sonnet-5", Price(input: 2, output: 10, cacheRead: 0.20), "Sonnet 5"),
        ("claude-sonnet-4", Price(input: 3, output: 15, cacheRead: 0.30), "Sonnet 4"),
        ("claude-haiku-5-5", Price(input: 0.10, output: 0.50, cacheRead: 0.01), "Haiku 5.5"),
        ("claude-haiku-4-5", Price(input: 1, output: 5, cacheRead: 0.10), "Haiku 4.5"),
        ("claude-3-5-haiku", Price(input: 0.8, output: 4, cacheRead: 0.08), "Haiku 3.5"),
    ]

    private static let fallback = Price(input: 3, output: 15, cacheRead: 0.30)

    static func price(for model: String) -> Price {
        table.first { model.hasPrefix($0.prefix) }?.price ?? fallback
    }

    static func displayName(for model: String) -> String {
        if let known = table.first(where: { model.hasPrefix($0.prefix) }) { return known.name }
        return model.replacingOccurrences(of: "claude-", with: "")
    }
}

// MARK: - Codex

nonisolated final class CodexUsageReader {

    private struct Event {
        let date: Date
        let input: Int
        let cached: Int
        let output: Int
    }

    private struct Limits {
        var date: Date
        var primary: [String: Any]?
        var secondary: [String: Any]?
    }

    private var readers: [String: AppendedLines] = [:]
    private var eventsByFile: [String: [Event]] = [:]
    private var limitsByFile: [String: Limits] = [:]

    private static let marker = Data("token_count".utf8)

    func card(window: UsageWindow) -> DevUsageCard? {
        guard FileManager.default.fileExists(atPath: DevAgentSessionActivity.codexSessionsRoot.path) else { return nil }
        let files = DevAgentSessionActivity.recentCodexRollouts()
        let live = Set(files)
        for path in files {
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
                  let modified = attributes[.modificationDate] as? Date else { continue }
            let size = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
            ingest(path: path, modified: modified, size: size)
        }
        readers = readers.filter { live.contains($0.key) }
        eventsByFile = eventsByFile.filter { live.contains($0.key) }
        limitsByFile = limitsByFile.filter { live.contains($0.key) }

        let events = eventsByFile.values.flatMap { $0 }
        let today = events.filter { $0.date >= window.startOfToday }
        let recent = events.filter { $0.date >= window.fiveHoursAgo }
        let todayTokens = today.reduce(0) { $0 + $1.input + $1.output }

        var meters: [DevUsageMeter] = []
        if let latest = limitsByFile.values.max(by: { $0.date < $1.date }) {
            if let primary = latest.primary, let meter = Self.meter(primary, fallbackName: "5-hour limit", at: latest.date, now: window.now) {
                meters.append(meter)
            }
            if let secondary = latest.secondary, let meter = Self.meter(secondary, fallbackName: "Weekly limit", at: latest.date, now: window.now) {
                meters.append(meter)
            }
        }

        var daily = Array(repeating: 0.0, count: 7)
        for event in events {
            if let index = window.dayIndex(of: event.date) { daily[index] += Double(event.input + event.output) }
        }

        let sessions = files.filter { path in
            (eventsByFile[path] ?? []).contains { $0.date >= window.startOfToday }
        }.count

        return DevUsageCard(
            id: "codex",
            title: "Codex",
            symbol: DevToolCatalog.codex.symbol,
            tint: DevToolCatalog.codex.tint,
            headline: "\(UsageFormat.tokens(todayTokens)) tokens today",
            subtitle: "\(sessions) session\(sessions == 1 ? "" : "s") today",
            meters: meters,
            stats: [
                DevUsageStat(label: "Last 5 hours", value: UsageFormat.tokens(recent.reduce(0) { $0 + $1.input + $1.output })),
                DevUsageStat(label: "Cached input today", value: UsageFormat.tokens(today.reduce(0) { $0 + $1.cached })),
            ],
            daily: daily,
            footnote: "Limits are as of Codex's last reply.",
            compactValue: meters.first.map { "\(Int(($0.usedFraction * 100).rounded()))%" } ?? UsageFormat.tokens(todayTokens)
        )
    }

    private static func meter(_ limit: [String: Any], fallbackName: String, at date: Date, now: Date) -> DevUsageMeter? {
        guard let used = (limit["used_percent"] as? NSNumber)?.doubleValue else { return nil }
        var name = fallbackName
        if let minutes = (limit["window_minutes"] as? NSNumber)?.intValue {
            name = minutes >= 7 * 24 * 60 - 60 ? "Weekly limit" : minutes >= 60 ? "\(minutes / 60)-hour limit" : "\(minutes)-minute limit"
        }
        var reset: Date?
        if let at = (limit["resets_at"] as? NSNumber)?.doubleValue {
            reset = Date(timeIntervalSince1970: at)
        } else if let seconds = (limit["resets_in_seconds"] as? NSNumber)?.doubleValue {
            reset = date.addingTimeInterval(seconds)
        }
        if let reset, reset < now { return DevUsageMeter(label: name, usedFraction: 0, caption: "reset") }
        return DevUsageMeter(
            label: name,
            usedFraction: min(1, max(0, used / 100)),
            caption: reset.map { UsageFormat.countdown(to: $0, from: now) }
        )
    }

    private func ingest(path: String, modified: Date, size: UInt64) {
        var reader = readers[path] ?? AppendedLines()
        guard let (lines, restarted) = reader.read(path: path, modified: modified, size: size) else { return }
        readers[path] = reader
        var events = restarted ? [] : (eventsByFile[path] ?? [])

        for line in lines where line.containsBytes(Self.marker) {
            guard let json = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any],
                  let payload = json["payload"] as? [String: Any],
                  payload["type"] as? String == "token_count",
                  let date = (json["timestamp"] as? String).flatMap(DevAgentTranscript.parseISODate) else { continue }
            if let info = payload["info"] as? [String: Any], let last = info["last_token_usage"] as? [String: Any] {
                events.append(Event(
                    date: date,
                    input: DevAgentTranscript.intValue(last["input_tokens"]),
                    cached: DevAgentTranscript.intValue(last["cached_input_tokens"]),
                    output: DevAgentTranscript.intValue(last["output_tokens"])
                ))
            }
            if let limits = payload["rate_limits"] as? [String: Any] {
                limitsByFile[path] = Limits(
                    date: date,
                    primary: limits["primary"] as? [String: Any],
                    secondary: limits["secondary"] as? [String: Any]
                )
            }
        }
        eventsByFile[path] = events
    }
}

// MARK: - Gemini CLI

nonisolated final class GeminiCLIUsageReader {

    private struct Turn {
        let date: Date
        let tokens: Int
    }

    private var turnsByFile: [String: (modified: Date, turns: [Turn])] = [:]

    func card(window: UsageWindow) -> DevUsageCard? {
        let root = URL(fileURLWithPath: NSHomeDirectory()).appending(path: ".gemini/tmp", directoryHint: .isDirectory)
        guard FileManager.default.fileExists(atPath: root.path) else { return nil }

        let files = UsageFiles.files(under: root, extension: "json", since: window.weekStart, depth: 3)
            .filter { $0.path.contains("/chats/") }
        let live = Set(files.map(\.path))
        for file in files where turnsByFile[file.path]?.modified != file.modified {
            turnsByFile[file.path] = (file.modified, Self.turns(atPath: file.path))
        }
        turnsByFile = turnsByFile.filter { live.contains($0.key) }

        let turns = turnsByFile.values.flatMap(\.turns)
        guard !turns.isEmpty else { return nil }
        let today = turns.filter { $0.date >= window.startOfToday }
        let todayTokens = today.reduce(0) { $0 + $1.tokens }
        var daily = Array(repeating: 0.0, count: 7)
        for turn in turns {
            if let index = window.dayIndex(of: turn.date) { daily[index] += Double(turn.tokens) }
        }

        return DevUsageCard(
            id: "gemini",
            title: "Gemini CLI",
            symbol: DevToolCatalog.gemini.symbol,
            tint: DevToolCatalog.gemini.tint,
            headline: "\(UsageFormat.tokens(todayTokens)) tokens today",
            subtitle: "\(today.count) repl\(today.count == 1 ? "y" : "ies") today",
            stats: [DevUsageStat(label: "7 days", value: UsageFormat.tokens(turns.reduce(0) { $0 + $1.tokens }))],
            daily: daily,
            compactValue: UsageFormat.tokens(todayTokens)
        )
    }

    private static func turns(atPath path: String) -> [Turn] {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)), data.count < 64 << 20,
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let messages = json["messages"] as? [[String: Any]] else { return [] }
        return messages.compactMap { message in
            guard let tokens = message["tokens"] as? [String: Any],
                  let date = (message["timestamp"] as? String).flatMap(DevAgentTranscript.parseISODate) else { return nil }
            var total = DevAgentTranscript.intValue(tokens["total"])
            if total == 0 {
                total = DevAgentTranscript.intValue(tokens["input"]) + DevAgentTranscript.intValue(tokens["output"])
            }
            return Turn(date: date, tokens: total)
        }
    }
}

// MARK: - Antigravity

nonisolated enum AntigravityUsageReader {

    struct ModelQuota {
        let name: String
        let remaining: Double
        let resetAt: Date?
    }

    static var stateDatabase: String {
        NSHomeDirectory() + "/Library/Application Support/Antigravity IDE/User/globalStorage/state.vscdb"
    }

    private static let finishedPrefix = "antigravity.notification.agent-finished-"

    static func card(window: UsageWindow) -> DevUsageCard? {
        let path = FileManager.default.fileExists(atPath: stateDatabase)
            ? stateDatabase
            : NSHomeDirectory() + "/Library/Application Support/Antigravity/User/globalStorage/state.vscdb"
        guard FileManager.default.fileExists(atPath: path) else { return nil }

        let rows = SQLiteReader.rows(
            path: path,
            sql: "SELECT key, value FROM ItemTable WHERE key = 'antigravityUnifiedStateSync.userStatus' OR key LIKE 'antigravity.notification.agent-finished-%'"
        )

        var runDates: [Date] = []
        var quotas: [ModelQuota] = []
        for row in rows {
            guard let key = row.first ?? nil else { continue }
            if key.hasPrefix(finishedPrefix) {
                if let millis = key.split(separator: "-").last.flatMap({ Double($0) }) {
                    runDates.append(Date(timeIntervalSince1970: millis / 1000))
                }
            } else if let value = row.last ?? nil, let data = Data(base64Encoded: value) {
                quotas = modelQuotas(in: data)
            }
        }

        let today = runDates.filter { $0 >= window.startOfToday }.count
        var daily = Array(repeating: 0.0, count: 7)
        for date in runDates {
            if let index = window.dayIndex(of: date) { daily[index] += 1 }
        }

        var seen = Set<String>()
        let meters = quotas
            .sorted { $0.remaining < $1.remaining }
            .filter { seen.insert(family(of: $0.name)).inserted }
            .prefix(4)
            .map { quota in
                let caption: String?
                if let reset = quota.resetAt, reset > window.now {
                    caption = UsageFormat.countdown(to: reset, from: window.now)
                } else {
                    caption = quota.resetAt == nil ? nil : "refreshes when Antigravity syncs"
                }
                return DevUsageMeter(label: family(of: quota.name), usedFraction: 1 - quota.remaining, caption: caption)
            }

        return DevUsageCard(
            id: "antigravity",
            title: "Antigravity",
            symbol: DevToolCatalog.antigravity.symbol,
            tint: DevToolCatalog.antigravity.tint,
            headline: "\(today) agent run\(today == 1 ? "" : "s") today",
            subtitle: quotas.isEmpty ? nil : "\(quotas.count) models in your plan",
            meters: Array(meters),
            stats: [DevUsageStat(label: "7 days", value: "\(runDates.filter { $0 >= window.weekStart }.count) runs")],
            daily: daily,
            footnote: "Model quotas as Antigravity last cached them.",
            compactValue: meters.first.map { "\(Int(((1 - $0.usedFraction) * 100).rounded()))% left" } ?? "\(today) runs"
        )
    }

    private static func family(of name: String) -> String {
        guard let paren = name.range(of: " (") else { return name }
        return String(name[..<paren.lowerBound])
    }

    static func modelQuotas(in data: Data) -> [ModelQuota] {
        var found: [String: ModelQuota] = [:]
        search(data, depth: 0, into: &found)
        return Array(found.values)
    }

    private static func search(_ data: Data, depth: Int, into found: inout [String: ModelQuota]) {
        guard depth < 10, let fields = Protobuf.parse(data) else { return }
        if let quota = quota(from: fields) {
            found[quota.name] = quota
            return
        }
        for field in fields {
            guard case .bytes(let bytes) = field.value, bytes.count > 2 else { continue }
            search(bytes, depth: depth + 1, into: &found)
            if bytes.count > 16, let text = String(data: bytes, encoding: .ascii),
               text.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "+" || $0 == "/" || $0 == "=" || $0 == "-" || $0 == "_" }),
               let decoded = Data(base64Encoded: text) ?? Data(base64Encoded: padded(text)) {
                search(decoded, depth: depth + 1, into: &found)
            }
        }
    }

    private static func padded(_ text: String) -> String {
        let remainder = text.count % 4
        return remainder == 0 ? text : text + String(repeating: "=", count: 4 - remainder)
    }

    private static func quota(from fields: [Protobuf.Field]) -> ModelQuota? {
        guard let nameField = fields.first(where: { $0.number == 1 }),
              case .bytes(let nameData) = nameField.value,
              let name = String(data: nameData, encoding: .utf8),
              !name.isEmpty, name.count < 80, name.allSatisfy({ !$0.isNewline && $0.isASCII }),
              name.contains(where: \.isLetter),
              let quotaField = fields.first(where: { $0.number == 15 }),
              case .bytes(let quotaData) = quotaField.value,
              let quotaFields = Protobuf.parse(quotaData) else { return nil }

        var remaining = 0.0
        var resetAt: Date?
        for field in quotaFields {
            switch (field.number, field.value) {
            case (1, .fixed32(let bits)):
                remaining = Double(Float(bitPattern: bits))
            case (2, .bytes(let timestamp)):
                if let seconds = Protobuf.parse(timestamp)?.first(where: { $0.number == 1 }),
                   case .varint(let value) = seconds.value, value > 0 {
                    resetAt = Date(timeIntervalSince1970: TimeInterval(value))
                }
            default:
                continue
            }
        }
        guard remaining.isFinite, (0...1.0001).contains(remaining) else { return nil }
        return ModelQuota(name: name, remaining: min(1, remaining), resetAt: resetAt)
    }
}

nonisolated enum Protobuf {
    enum Value {
        case varint(UInt64)
        case fixed64(UInt64)
        case bytes(Data)
        case fixed32(UInt32)
    }

    struct Field {
        let number: Int
        let value: Value
    }

    static func parse(_ data: Data) -> [Field]? {
        let bytes = [UInt8](data)
        var index = 0
        var fields: [Field] = []

        func varint() -> UInt64? {
            var result: UInt64 = 0
            var shift: UInt64 = 0
            while index < bytes.count, shift < 64 {
                let byte = bytes[index]
                index += 1
                result |= UInt64(byte & 0x7F) << shift
                if byte < 0x80 { return result }
                shift += 7
            }
            return nil
        }

        while index < bytes.count {
            guard let key = varint() else { return nil }
            let number = Int(key >> 3)
            guard number > 0, number < 1 << 20 else { return nil }
            switch key & 7 {
            case 0:
                guard let value = varint() else { return nil }
                fields.append(Field(number: number, value: .varint(value)))
            case 1:
                guard index + 8 <= bytes.count else { return nil }
                var value: UInt64 = 0
                for offset in 0..<8 { value |= UInt64(bytes[index + offset]) << (8 * UInt64(offset)) }
                index += 8
                fields.append(Field(number: number, value: .fixed64(value)))
            case 2:
                guard let length = varint(), length <= UInt64(bytes.count - index) else { return nil }
                let end = index + Int(length)
                fields.append(Field(number: number, value: .bytes(Data(bytes[index..<end]))))
                index = end
            case 5:
                guard index + 4 <= bytes.count else { return nil }
                var value: UInt32 = 0
                for offset in 0..<4 { value |= UInt32(bytes[index + offset]) << (8 * UInt32(offset)) }
                index += 4
                fields.append(Field(number: number, value: .fixed32(value)))
            default:
                return nil
            }
        }
        return fields
    }
}

// MARK: - Cursor

nonisolated enum CursorUsageReader {

    static func card(window: UsageWindow) -> DevUsageCard? {
        let home = NSHomeDirectory()
        let tracking = home + "/.cursor/ai-tracking/ai-code-tracking.db"
        let state = home + "/Library/Application Support/Cursor/User/globalStorage/state.vscdb"
        let hasTracking = FileManager.default.fileExists(atPath: tracking)
        guard hasTracking || FileManager.default.fileExists(atPath: state) else { return nil }

        let weekStartMillis = Int64(window.weekStart.timeIntervalSince1970 * 1000)
        let todayMillis = Int64(window.startOfToday.timeIntervalSince1970 * 1000)

        var daily = Array(repeating: 0.0, count: 7)
        var bySource: [String: Int] = [:]
        var todayLines = 0
        var models: [String: Int] = [:]
        if hasTracking {
            let rows = SQLiteReader.rows(
                path: tracking,
                sql: "SELECT source, IFNULL(model, ''), createdAt FROM ai_code_hashes WHERE createdAt >= \(weekStartMillis) AND source != 'human'"
            )
            for row in rows {
                guard row.count == 3, let millis = row[2].flatMap({ Double($0) }) else { continue }
                let date = Date(timeIntervalSince1970: millis / 1000)
                if let index = window.dayIndex(of: date) { daily[index] += 1 }
                if Int64(millis) >= todayMillis {
                    todayLines += 1
                    bySource[row[0] ?? "agent", default: 0] += 1
                    if let model = row[1], !model.isEmpty, model != "default" { models[model, default: 0] += 1 }
                }
            }
        }

        let plan = SQLiteReader.rows(
            path: state,
            sql: "SELECT value FROM ItemTable WHERE key = 'cursorAuth/stripeMembershipType'"
        ).first?.first??.trimmingCharacters(in: CharacterSet(charactersIn: "\" "))

        var stats = [DevUsageStat(label: "7 days", value: "\(Int(daily.reduce(0, +))) lines")]
        if let agent = bySource["composer"] { stats.append(DevUsageStat(label: "Agent today", value: "\(agent) lines")) }
        if let tab = bySource["tab"] { stats.append(DevUsageStat(label: "Tab today", value: "\(tab) lines")) }
        if let model = models.max(by: { $0.value < $1.value })?.key {
            stats.append(DevUsageStat(label: "Top model", value: model))
        }

        return DevUsageCard(
            id: "cursor",
            title: "Cursor",
            symbol: DevToolCatalog.cursor.symbol,
            tint: DevToolCatalog.cursor.tint,
            headline: "\(todayLines) AI lines today",
            subtitle: plan.map { "\($0.capitalized) plan" },
            stats: stats,
            daily: daily,
            footnote: "Lines Cursor's AI wrote, from its local tracking database.",
            compactValue: "\(todayLines) lines"
        )
    }
}

nonisolated enum SQLiteReader {
    static func rows(path: String, sql: String) -> [[String?]] {
        var handle: OpaquePointer?
        guard sqlite3_open_v2(path, &handle, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK else {
            sqlite3_close(handle)
            return []
        }
        defer { sqlite3_close(handle) }
        sqlite3_busy_timeout(handle, 200)

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }

        var result: [[String?]] = []
        let columns = sqlite3_column_count(statement)
        while sqlite3_step(statement) == SQLITE_ROW, result.count < 200_000 {
            var row: [String?] = []
            for column in 0..<columns {
                if let text = sqlite3_column_text(statement, column) {
                    row.append(String(cString: text))
                } else {
                    row.append(nil)
                }
            }
            result.append(row)
        }
        return result
    }
}