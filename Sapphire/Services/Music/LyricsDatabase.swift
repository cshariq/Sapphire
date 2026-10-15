//
//  LyricsDatabase.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-14

import Compression
import FirebaseFirestore
import Foundation

enum LyricsDatabaseResult: Equatable {
    case lyrics([LyricLine])
    case timing(LyricsTimingOverlay, samples: Int, confidence: Double)
    case notFound
    case failed

    var overlay: LyricsTimingOverlay? {
        if case .timing(let overlay, _, _) = self { return overlay }
        return nil
    }
}

@MainActor
final class LyricsDatabase {
    static let shared = LyricsDatabase()
    nonisolated static let collection = "tracks"

    private init() {}

    nonisolated static func key(title: String, artist: String) -> String? {
        LyricsDatabaseKeys.metadataKey(title: title, artist: artist)
    }

    func lookup(title: String, artist: String, spotifyTrackID: String? = nil, duration: TimeInterval?) async -> LyricsDatabaseResult {
        let label = "'\(title)' / '\(artist)'"
        let primary = Self.key(title: title, artist: artist)
        if let primary {
            let result = await lookup(key: primary, duration: duration, label: label)
            guard result == .notFound, let spotifyTrackID, !spotifyTrackID.isEmpty else { return result }
        }
        guard let spotifyTrackID, !spotifyTrackID.isEmpty else { return .notFound }
        return await lookup(key: LyricsDatabaseKeys.spotifyKey(spotifyTrackID), duration: duration, label: "\(label) by Spotify ID")
    }

    func lookup(key: String, duration: TimeInterval?, label: String? = nil) async -> LyricsDatabaseResult {
        let durationMs = duration.flatMap { $0 > 0 ? Int($0 * 1000) : nil }
        let started = Date()

        let (result, source) = await Self.resolve(key: key, durationMs: durationMs)
        let elapsed = Self.milliseconds(since: started)
        switch result {
        case .lyrics(let lines):
            LyricsLog.info("Lyrics database: curated lyrics (\(source), \(elapsed)ms), \(lines.count) lines")
        case .timing(let overlay, let samples, let confidence):
            LyricsLog.info(
                "Lyrics database: timing for \(overlay.lines.count) lines (\(source), \(elapsed)ms), \(samples) listen(s), confidence \(Int(confidence * 100))%"
            )
        case .notFound:
            LyricsLog.info("Lyrics database: nothing for \(label ?? key) (\(source), \(elapsed)ms)")
        case .failed:
            LyricsLog.error("Lyrics database lookup failed for \(label ?? key): \(source)")
        }
        return result
    }

    private nonisolated static func resolve(key: String, durationMs: Int?) async -> (LyricsDatabaseResult, String) {
        switch LyricsDatabaseDiskCache.entry(for: key) {
        case .document(let data):
            return (LyricsDatabaseDocument.result(from: data, playingMs: durationMs), "cached")
        case .missing:
            return (.notFound, "cached")
        case nil:
            break
        }

        guard let database = await MainActor.run(body: { FirebaseBootstrap.firestoreDatabase() }) else {
            return (.failed, "Firestore is unavailable")
        }
        do {
            let data = try await database.collection(collection).document(key).getDocument().data()
            LyricsDatabaseDiskCache.store(data, for: key)
            guard let data else { return (.notFound, "server") }
            return (LyricsDatabaseDocument.result(from: data, playingMs: durationMs), "server")
        } catch {
            return (.failed, error.localizedDescription)
        }
    }

    private nonisolated static func milliseconds(since date: Date) -> Int {
        Int(Date().timeIntervalSince(date) * 1000)
    }
}

enum LyricsDatabaseDiskCache {
    enum Entry {
        case document([String: Any])
        case missing
    }

    static let hitLifetime: TimeInterval = 30 * 24 * 60 * 60
    static let missLifetime: TimeInterval = 7 * 24 * 60 * 60
    static let capacity = 4000
    static let trimTarget = 3000
    private static let storedFields: Set<String> = ["v", "z", "x", "o", "c", "n", "d", "i", "r"]

    private static let directory: URL = {
        let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "com.sapphire.app", isDirectory: true)
            .appendingPathComponent("LyricsDatabase", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    private static let trimLock = NSLock()
    private nonisolated(unsafe) static var hasTrimmed = false

    static func entry(for key: String, now: Date = Date()) -> Entry? {
        guard let raw = try? Data(contentsOf: fileURL(for: key)),
              let plist = try? PropertyListSerialization.propertyList(from: raw, format: nil) as? [String: Any],
              let storedAt = plist["at"] as? Date else {
            return nil
        }
        let document = plist["doc"] as? [String: Any]
        let lifetime = document == nil ? missLifetime : hitLifetime
        guard now.timeIntervalSince(storedAt) < lifetime else { return nil }
        return document.map(Entry.document) ?? .missing
    }

    static func store(_ document: [String: Any]?, for key: String, now: Date = Date()) {
        var plist: [String: Any] = ["at": now]
        if let document {
            plist["doc"] = document.filter { storedFields.contains($0.key) }
        }
        guard let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0) else { return }
        try? data.write(to: fileURL(for: key), options: .atomic)
        trimOncePerLaunch()
    }

    private static func fileURL(for key: String) -> URL {
        directory.appendingPathComponent(key.replacingOccurrences(of: ":", with: "_") + ".plist")
    }

    private static func trimOncePerLaunch() {
        let shouldTrim = trimLock.withLock {
            defer { hasTrimmed = true }
            return !hasTrimmed
        }
        guard shouldTrim else { return }
        Task.detached(priority: .utility) {
            let files = (try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.contentModificationDateKey]
            )) ?? []
            guard files.count > capacity else { return }
            let oldestFirst = files.sorted {
                let lhs = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let rhs = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return lhs < rhs
            }
            for file in oldestFirst.prefix(files.count - trimTarget) {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }
}

enum LyricsDatabaseDocument {
    static let curatedVersion = 2
    static let timingVersion = 3
    static let durationToleranceMs = 3000
    static let maximumPackedBytes = 98_304
    static let maximumOverlayBytes = 32_768
    static let maximumUnpackedBytes = 1_048_576

    static func result(from data: [String: Any], playingMs: Int?) -> LyricsDatabaseResult {
        switch integer(data["v"]) {
        case curatedVersion:
            return lines(from: data).map(LyricsDatabaseResult.lyrics) ?? .notFound
        case timingVersion:
            guard durationMatches(stored: data["d"], playingMs: playingMs), let overlay = overlay(from: data) else { return .notFound }
            return .timing(overlay, samples: max(integer(data["n"]) ?? 1, 1), confidence: number(data["c"]) ?? 0.7)
        default:
            return .notFound
        }
    }

    static func durationMatches(stored: Any?, playingMs: Int?) -> Bool {
        guard let storedMs = integer(stored), storedMs > 0, let playingMs, playingMs > 0 else { return true }
        return abs(storedMs - playingMs) <= durationToleranceMs
    }

    static func timing(
        _ overlay: LyricsTimingOverlay,
        confidence: Double,
        samples: Int,
        durationMs: Int?,
        engine: String
    ) -> [String: Any]? {
        guard let encoded = overlay.encoded(), let packed = deflate(encoded), packed.count <= maximumOverlayBytes else { return nil }
        var data: [String: Any] = [
            "v": timingVersion,
            "o": packed,
            "c": min(max(confidence, 0.7), 1),
            "n": min(max(samples, 1), LyricsTimingOverlay.maximumSamples),
            "e": engine,
        ]
        if let durationMs, (1000...3_600_000).contains(durationMs) { data["d"] = durationMs }
        return data
    }

    static func overlay(from data: [String: Any]) -> LyricsTimingOverlay? {
        guard let packed = data["o"] as? Data, packed.count <= maximumOverlayBytes else { return nil }
        return inflate(packed).flatMap(LyricsTimingOverlay.init(encoded:))
    }

    static func lines(from data: [String: Any]) -> [LyricLine]? {
        guard integer(data["v"]) == curatedVersion,
              let packed = data["z"] as? Data,
              let lyricsfile = inflate(packed).flatMap({ String(data: $0, encoding: .utf8) }),
              let parsed = LyricsParser.parseLyricsfile(lyricsfile),
              !parsed.isEmpty else {
            return nil
        }

        let extrasObject = (data["x"] as? Data)
            .flatMap(inflate)
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        let extras = (extrasObject?["lines"] as? [Any]) ?? []
        guard extras.count == parsed.count else { return parsed }

        return zip(parsed, extras).map { line, rawExtra in
            guard let extra = rawExtra as? [String: Any] else { return line }
            return LyricLine(
                id: line.id,
                text: line.text,
                timestamp: line.timestamp,
                endTimestamp: line.endTimestamp,
                words: line.words,
                translatedText: line.translatedText,
                background: words(extra["background"]),
                agent: extra["agent"] as? String,
                songPart: extra["songPart"] as? String,
                romanization: (extra["romanization"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            )
        }
    }

    // MARK: - Raw DEFLATE (zlib.deflateRawSync / inflateRawSync in the importer)

    static func deflate(_ data: Data) -> Data? {
        guard !data.isEmpty else { return nil }
        let capacity = data.count + 1024
        var output = Data(count: capacity)
        let written = output.withUnsafeMutableBytes { destination in
            data.withUnsafeBytes { source in
                compression_encode_buffer(
                    destination.bindMemory(to: UInt8.self).baseAddress!, capacity,
                    source.bindMemory(to: UInt8.self).baseAddress!, data.count,
                    nil, COMPRESSION_ZLIB
                )
            }
        }
        guard written > 0 else { return nil }
        return output.prefix(written)
    }

    static func inflate(_ data: Data) -> Data? {
        guard !data.isEmpty, data.count <= maximumPackedBytes else { return nil }
        let capacity = maximumUnpackedBytes + 1
        var output = Data(count: capacity)
        let written = output.withUnsafeMutableBytes { destination in
            data.withUnsafeBytes { source in
                compression_decode_buffer(
                    destination.bindMemory(to: UInt8.self).baseAddress!, capacity,
                    source.bindMemory(to: UInt8.self).baseAddress!, data.count,
                    nil, COMPRESSION_ZLIB
                )
            }
        }
        guard written > 0, written < capacity else { return nil }
        return output.prefix(written)
    }

    // MARK: - Fields

    private static func words(_ value: Any?) -> [LyricWord] {
        guard let items = value as? [[String: Any]] else { return [] }
        return items.compactMap { item in
            guard let text = item["text"] as? String,
                  let start = integer(item["startMs"]), start >= 0 else {
                return nil
            }
            let end = integer(item["endMs"]).flatMap { $0 >= start ? $0 : nil }
            return LyricWord(
                text: text,
                timestamp: TimeInterval(start) / 1000,
                endTimestamp: end.map { TimeInterval($0) / 1000 }
            )
        }
    }

    private static func integer(_ value: Any?) -> Int? {
        switch value {
        case let number as Int: return number
        case let number as NSNumber: return number.intValue
        default: return nil
        }
    }

    private static func number(_ value: Any?) -> Double? {
        switch value {
        case let number as Double: return number
        case let number as NSNumber: return number.doubleValue
        default: return nil
        }
    }
}