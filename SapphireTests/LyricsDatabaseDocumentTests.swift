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
        var data: [String: Any] = ["schemaVersion": 1, "lyricsfile": lyricsfile]
        if let extras { data["extras"] = ["lines": extras] }
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
        future["schemaVersion"] = 2
        #expect(LyricsDatabaseDocument.lines(from: future) == nil)

        var broken = Self.document(extras: nil)
        broken["lyricsfile"] = "version: '9.9'"
        #expect(LyricsDatabaseDocument.lines(from: broken) == nil)
    }
}