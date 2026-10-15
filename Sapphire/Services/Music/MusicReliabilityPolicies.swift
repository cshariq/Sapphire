//
//  MusicReliabilityPolicies.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-10-07
//

import CryptoKit
import Foundation

// MARK: - Now-playing stream restarts

struct StreamRestartPolicy: Equatable {
    var baseDelay: TimeInterval = 1
    var maxDelay: TimeInterval = 32
    var maxAttempts = 6
    var stableLifetime: TimeInterval = 60

    private(set) var attempts = 0

    var isExhausted: Bool { attempts >= maxAttempts }

    mutating func delayAfterExit(lifetime: TimeInterval) -> TimeInterval? {
        if lifetime >= stableLifetime { attempts = 0 }
        guard attempts < maxAttempts else { return nil }
        let delay = min(maxDelay, baseDelay * pow(2, Double(attempts)))
        attempts += 1
        return delay
    }

    mutating func reset() { attempts = 0 }
}

// MARK: - Line framing

struct NewlineFramer {
    let limit: Int
    private var pending = Data()
    private var discarding = false
    private(set) var droppedLines = 0

    init(limit: Int) {
        self.limit = limit
    }

    mutating func append(_ data: Data) -> [Data] {
        var lines: [Data] = []
        var start = data.startIndex
        while start < data.endIndex {
            guard let newline = data[start...].firstIndex(of: 0x0A) else {
                if !discarding {
                    pending.append(data[start...])
                    if pending.count > limit {
                        pending = Data()
                        discarding = true
                        droppedLines += 1
                    }
                }
                break
            }
            if discarding {
                discarding = false
            } else {
                pending.append(data[start..<newline])
                if pending.count > limit {
                    droppedLines += 1
                } else if !pending.isEmpty {
                    lines.append(pending)
                }
                pending = Data()
            }
            start = data.index(after: newline)
        }
        return lines
    }

    mutating func reset() {
        pending = Data()
        discarding = false
    }
}

// MARK: - Artwork identity

enum ArtworkDigest {
    static func of(base64 string: String) -> String {
        var hasher = SHA256()
        var copy = string
        copy.withUTF8 { hasher.update(bufferPointer: UnsafeRawBufferPointer($0)) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func of(base64Bytes data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

enum ArtworkGracePolicy {
    static let interval: TimeInterval = 2.0

    static func isArtworkKnownAbsent(trackChangedAt: Date?, now: Date, hasArtwork: Bool) -> Bool {
        guard !hasArtwork else { return false }
        guard let trackChangedAt else { return true }
        return now.timeIntervalSince(trackChangedAt) >= interval
    }
}

// MARK: - Adapter commands

enum AdapterCommand: Equatable {
    case send(Int)
    case seek(micros: Int64)

    var isSeek: Bool {
        if case .seek = self { return true }
        return false
    }

    var serveLine: String {
        switch self {
        case .send(let id): return "send \(id)"
        case .seek(let micros): return "seek \(micros)"
        }
    }

    var oneShotArguments: [String] {
        switch self {
        case .send(let id): return ["send", String(id)]
        case .seek(let micros): return ["seek", String(micros)]
        }
    }
}

struct AdapterCommandQueue: Equatable {
    private(set) var items: [AdapterCommand] = []
    let capacity: Int

    init(capacity: Int = 16) {
        self.capacity = capacity
    }

    var isEmpty: Bool { items.isEmpty }

    mutating func enqueue(_ command: AdapterCommand) {
        if command.isSeek, items.last?.isSeek == true {
            items[items.count - 1] = command
            return
        }
        if items.count >= capacity { items.removeFirst() }
        items.append(command)
    }

    mutating func dequeue() -> AdapterCommand? {
        items.isEmpty ? nil : items.removeFirst()
    }

    mutating func removeAll() { items.removeAll() }
}

struct CommandServerHealth: Equatable {
    var window: TimeInterval = 60
    var maxCrashes = 3
    private(set) var crashTimes: [Date] = []

    mutating func recordCrash(at now: Date) {
        crashTimes = crashTimes.filter { now.timeIntervalSince($0) < window }
        crashTimes.append(now)
    }

    func prefersOneShot(at now: Date) -> Bool {
        crashTimes.filter { now.timeIntervalSince($0) < window }.count >= maxCrashes
    }
}

// MARK: - Player modes from MediaRemote

struct PlayerModeCalibration: Equatable {
    enum Numbering: CaseIterable, Equatable {
        case zeroBased
        case oneBased

        func modes(shuffle: Int, repeat repeatValue: Int) -> (shuffle: Bool, repeat: RepeatMode)? {
            switch self {
            case .zeroBased:
                guard (0...2).contains(shuffle) else { return nil }
                let mode: RepeatMode
                switch repeatValue {
                case 0: mode = .off
                case 1: mode = .track
                case 2: mode = .context
                default: return nil
                }
                return (shuffle != 0, mode)
            case .oneBased:
                guard (1...3).contains(shuffle) else { return nil }
                let mode: RepeatMode
                switch repeatValue {
                case 1: mode = .off
                case 2: mode = .track
                case 3: mode = .context
                default: return nil
                }
                return (shuffle != 1, mode)
            }
        }
    }

    static let requiredAgreements = 2

    private(set) var candidates: [Numbering] = Numbering.allCases
    private(set) var agreements = 0

    var trusted: Numbering? {
        candidates.count == 1 && agreements >= Self.requiredAgreements ? candidates[0] : nil
    }

    var isRejected: Bool { candidates.isEmpty }

    mutating func observe(shuffle: Int, repeat repeatValue: Int, actualShuffle: Bool, actualRepeat: RepeatMode) {
        guard !candidates.isEmpty else { return }
        candidates = candidates.filter { numbering in
            guard let mapped = numbering.modes(shuffle: shuffle, repeat: repeatValue) else { return false }
            return mapped.shuffle == actualShuffle && mapped.repeat == actualRepeat
        }
        agreements = candidates.isEmpty ? 0 : agreements + 1
    }

    func modes(shuffle: Int?, repeat repeatValue: Int?) -> (shuffle: Bool, repeat: RepeatMode)? {
        guard let numbering = trusted, let shuffle, let repeatValue else { return nil }
        return numbering.modes(shuffle: shuffle, repeat: repeatValue)
    }
}

// MARK: - Lyrics

enum LyricsDurationMatch {
    static let tolerance: TimeInterval = 2

    static func requestDuration(_ duration: TimeInterval?) -> Int? {
        guard let duration, duration.isFinite, duration >= 1, duration <= 7_200 else { return nil }
        return Int(duration.rounded())
    }

    static func accepts(expected: TimeInterval?, actual: Double?) -> Bool {
        guard let expected, expected.isFinite, expected > 0,
              let actual, actual.isFinite, actual > 0 else { return true }
        return abs(expected - actual) <= tolerance
    }
}

enum LyricsFetchOutcome: Equatable {
    case found([LyricLine])
    case notFound
    case failed
}

struct LyricsRetryPolicy: Equatable {
    var baseDelay: TimeInterval = 15
    var maxDelay: TimeInterval = 30 * 60
    var capacity = 32

    private struct Entry: Equatable {
        var failures: Int
        var retryAt: Date
        var stamp: UInt64
    }

    private var entries: [String: Entry] = [:]
    private var clock: UInt64 = 0

    func isDue(_ key: String, now: Date) -> Bool {
        guard let entry = entries[key] else { return true }
        return now >= entry.retryAt
    }

    func retryDate(for key: String) -> Date? {
        entries[key]?.retryAt
    }

    @discardableResult
    mutating func recordFailure(_ key: String, now: Date) -> Date {
        clock &+= 1
        let failures = (entries[key]?.failures ?? 0) + 1
        let delay = min(maxDelay, baseDelay * pow(2, Double(failures - 1)))
        let retryAt = now.addingTimeInterval(delay)
        entries[key] = Entry(failures: failures, retryAt: retryAt, stamp: clock)
        if entries.count > capacity,
           let oldest = entries.min(by: { $0.value.stamp < $1.value.stamp })?.key {
            entries.removeValue(forKey: oldest)
        }
        return retryAt
    }

    mutating func recordSuccess(_ key: String) {
        entries.removeValue(forKey: key)
    }

    mutating func makeAllDue(now: Date) {
        for key in entries.keys { entries[key]?.retryAt = now }
    }
}

struct BoundedLRUCache<Key: Hashable, Value> {
    let capacity: Int
    private var storage: [Key: (value: Value, stamp: UInt64)] = [:]
    private var clock: UInt64 = 0

    init(capacity: Int) {
        self.capacity = max(1, capacity)
    }

    var count: Int { storage.count }
    var keys: [Key] { Array(storage.keys) }

    mutating func value(for key: Key) -> Value? {
        guard let entry = storage[key] else { return nil }
        clock &+= 1
        storage[key] = (entry.value, clock)
        return entry.value
    }

    func peek(_ key: Key) -> Value? {
        storage[key]?.value
    }

    mutating func set(_ value: Value, for key: Key) {
        clock &+= 1
        storage[key] = (value, clock)
        evict(downTo: capacity, keeping: key)
    }

    mutating func removeValue(for key: Key) {
        storage.removeValue(forKey: key)
    }

    mutating func removeAll() {
        storage.removeAll()
    }

    mutating func trim(to limit: Int, keeping key: Key?) {
        evict(downTo: max(0, limit), keeping: key)
    }

    private mutating func evict(downTo limit: Int, keeping key: Key?) {
        guard storage.count > limit else { return }
        let victims = storage
            .filter { $0.key != key }
            .sorted { $0.value.stamp < $1.value.stamp }
            .prefix(storage.count - limit)
        for victim in victims { storage.removeValue(forKey: victim.key) }
    }
}

struct LyricsTranslation: Equatable {
    let sourceLanguage: String
    let byOriginal: [String: String]

    static func cacheKey(trackKey: String, targetLanguage: String) -> String {
        "\(trackKey)|\(targetLanguage)"
    }

    init(sourceLanguage: String, byOriginal: [String: String]) {
        self.sourceLanguage = sourceLanguage
        self.byOriginal = byOriginal
    }

    init(sourceLanguage: String, translatedLines lines: [LyricLine]) {
        var map: [String: String] = [:]
        for line in lines {
            let original = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !original.isEmpty, let translated = line.translatedText else { continue }
            map[original] = translated
        }
        self.init(sourceLanguage: sourceLanguage, byOriginal: map)
    }

    func applied(to lines: [LyricLine]) -> [LyricLine]? {
        var result = lines
        for index in result.indices {
            let original = result[index].text.trimmingCharacters(in: .whitespacesAndNewlines)
            if original.isEmpty {
                result[index].translatedText = ""
                continue
            }
            guard let translated = byOriginal[original] else { return nil }
            result[index].translatedText = translated
        }
        return result
    }
}