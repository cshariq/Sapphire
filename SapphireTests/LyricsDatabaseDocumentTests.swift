//
//  LyricsDatabaseDocumentTests.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-14

import Foundation
import Testing
@testable import Sapphire

@Suite("Lyrics database documents")
struct LyricsDatabaseDocumentTests {
    private static let lyricsfile = """
    version: '1.0'
    metadata:
      title: 'Placeholder Song'
      artist: 'Placeholder Artist'
      instrumental: false
    lines:
      - text: 'Alpha beta'
        start_ms: 1000
        end_ms: 2000
        words:
          - text: 'Alpha '
            start_ms: 1000
            end_ms: 1500
          - text: 'beta'
            start_ms: 1500
            end_ms: 2000
      - text: 'Gamma'
        start_ms: 3000
        end_ms: 4000
        words:
          - text: 'Gamma'
            start_ms: 3000
            end_ms: 4000
    """

    private static func document(extras: [[String: Any]]?) -> [String: Any] {
        var data: [String: Any] = ["v": 2, "z": LyricsDatabaseDocument.deflate(Data(lyricsfile.utf8))!, "c": 2]
        if let extras {
            data["x"] = LyricsDatabaseDocument.deflate(try! JSONSerialization.data(withJSONObject: ["lines": extras]))!
        }
        return data
    }

    @Test("Applies Apple Music-style extras to the matching lines")
    func appliesExtras() throws {
        let data = Self.document(extras: [
            [
                "agent": "v1",
                "songPart": "Verse",
                "background": [
                    ["text": "(echo ", "startMs": 1200, "endMs": 1400],
                    ["text": "echo)", "startMs": NSNumber(value: 1400), "endMs": 1300],
                ],
            ],
            ["agent": "v2", "songPart": "Chorus", "background": []],
        ])

        let lines = try #require(LyricsDatabaseDocument.lines(from: data))
        #expect(lines.map(\.text) == ["Alpha beta", "Gamma"])
        #expect(lines[0].words.map(\.text) == ["Alpha ", "beta"])
        #expect(lines[0].agent == "v1")
        #expect(lines[0].songPart == "Verse")
        #expect(lines[0].background.map(\.text) == ["(echo ", "echo)"])
        #expect(lines[0].background[0].endTimestamp == 1.4)
        #expect(lines[0].background[1].endTimestamp == nil)
        #expect(lines[1].agent == "v2")
        #expect(lines[1].background.isEmpty)
    }

    @Test("Keeps the core lyrics when extras are missing or out of step")
    func toleratesMissingExtras() throws {
        let withoutExtras = try #require(LyricsDatabaseDocument.lines(from: Self.document(extras: nil)))
        #expect(withoutExtras.count == 2)
        #expect(withoutExtras.allSatisfy { $0.agent == nil && $0.background.isEmpty })

        let mismatched = try #require(LyricsDatabaseDocument.lines(from: Self.document(extras: [["agent": "v1"]])))
        #expect(mismatched.count == 2)
        #expect(mismatched[0].agent == nil)
    }

    @Test("Rejects unknown schema versions and invalid Lyricsfiles")
    func rejectsInvalidDocuments() {
        var future = Self.document(extras: nil)
        future["v"] = 3
        #expect(LyricsDatabaseDocument.lines(from: future) == nil)

        var broken = Self.document(extras: nil)
        broken["z"] = LyricsDatabaseDocument.deflate(Data("version: '9.9'".utf8))!
        #expect(LyricsDatabaseDocument.lines(from: broken) == nil)

        var garbage = Self.document(extras: nil)
        garbage["z"] = Data([0xFF, 0x00, 0x13, 0x37])
        #expect(LyricsDatabaseDocument.lines(from: garbage) == nil)
    }

    @Test("Reads documents compressed by the importer (Node zlib.deflateRawSync)")
    func readsImporterCompression() throws {
        let z = try #require(Data(base64Encoded: "bY5LDsIwDET3PYV3WYFSpG6y6w2QOAAyxNBIToIS8zk+SQQFVfXyjeZ5HpSyi8GA6rdadZ4ELQqaDkCcMJVgz3imKbKlBIcYrqpkmMRlWYRjgzV2IUu6ewqCbOCCnKljFyhX7waEXrU78m1COJWXtQOQpWiPPhvotdYNUbAN7L7gGZNtlnoLk/rgVdO/rR9mOCt+MxaCYUXQ5rwB"))
        let x = try #require(Data(base64Encoded: "q1bKycxLLVayiq5WSkxPzStRslIqM1TSUSrOz0sPSCwC8cNSi4pTgUJJicnZ6UX5pXkpQOWxtbG1AA=="))
        let lines = try #require(LyricsDatabaseDocument.lines(from: ["v": NSNumber(value: 2), "z": z, "x": x, "c": 2]))
        #expect(lines.map(\.text) == ["Alpha beta"])
        #expect(lines[0].words.map(\.text) == ["Alpha ", "beta"])
        #expect(lines[0].agent == "v1")
        #expect(lines[0].songPart == "Verse")
    }

    @Test("Refuses to inflate past the Lyricsfile size limit")
    func boundsDecompression() throws {
        let bomb = try #require(LyricsDatabaseDocument.deflate(Data(repeating: 0x61, count: LyricsDatabaseDocument.maximumUnpackedBytes + 10)))
        #expect(bomb.count < LyricsDatabaseDocument.maximumPackedBytes)
        #expect(LyricsDatabaseDocument.inflate(bomb) == nil)
    }

    @Test("Builds timing documents the rules accept and reads them back")
    func timingDocument() throws {
        let overlay = LyricsTimingOverlay(lines: [
            .init(hash: "1a2b3c4d", words: [.init(start: 1000, end: 1400), .init(start: 1400, end: 2100)]),
        ])
        let data = try #require(LyricsDatabaseDocument.timing(overlay, confidence: 0.83, samples: 2, durationMs: 213_000, engine: "speechtranscriber-v2"))
        #expect(Set(data.keys) == ["v", "o", "c", "n", "d", "e"])
        #expect(data["n"] as? Int == 2)
        #expect(LyricsDatabaseDocument.result(from: data, playingMs: 214_000) == .timing(overlay, samples: 2, confidence: 0.83))
        #expect(LyricsDatabaseDocument.result(from: data, playingMs: 250_000) == .notFound)
        #expect(LyricsDatabaseDocument.timing(overlay, confidence: 0.9, samples: 9, durationMs: 50, engine: "e")?["d"] == nil)
        #expect(LyricsDatabaseDocument.timing(overlay, confidence: 0.9, samples: 900, durationMs: nil, engine: "e")?["n"] as? Int == LyricsTimingOverlay.maximumSamples)
        guard case .lyrics(let lines) = LyricsDatabaseDocument.result(from: Self.document(extras: nil), playingMs: nil) else {
            Issue.record("expected curated lyrics"); return
        }
        #expect(lines.count == 2)
    }

    @Test("Disk cache remembers hits and misses until they expire")
    func diskCache() throws {
        let key = "meta:test\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        let now = Date()
        #expect(LyricsDatabaseDiskCache.entry(for: key) == nil)

        LyricsDatabaseDiskCache.store(nil, for: key, now: now)
        guard case .missing = LyricsDatabaseDiskCache.entry(for: key, now: now.addingTimeInterval(60)) else {
            Issue.record("expected a cached miss"); return
        }
        #expect(LyricsDatabaseDiskCache.entry(for: key, now: now.addingTimeInterval(LyricsDatabaseDiskCache.missLifetime + 1)) == nil)

        LyricsDatabaseDiskCache.store(Self.document(extras: nil).merging(["t": "server only"]) { $1 }, for: key, now: now)
        guard case .document(let cached) = LyricsDatabaseDiskCache.entry(for: key, now: now.addingTimeInterval(60)) else {
            Issue.record("expected a cached document"); return
        }
        #expect(cached["t"] == nil)
        #expect(LyricsDatabaseDocument.lines(from: cached)?.count == 2)
    }

    @Test("Rejects generated timings recorded on a different-length version")
    func durationGuard() {
        #expect(LyricsDatabaseDocument.durationMatches(stored: 213_000, playingMs: 214_500))
        #expect(LyricsDatabaseDocument.durationMatches(stored: NSNumber(value: 213_000), playingMs: 210_000))
        #expect(!LyricsDatabaseDocument.durationMatches(stored: 213_000, playingMs: 245_000))
        #expect(LyricsDatabaseDocument.durationMatches(stored: nil, playingMs: 245_000))
        #expect(LyricsDatabaseDocument.durationMatches(stored: 213_000, playingMs: nil))
    }
}