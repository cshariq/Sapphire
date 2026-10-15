//
//  MomentumLyricTimingTests.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-10-12

import Foundation
import Testing
@testable import Sapphire

@Suite("Momentum lyric timing")
struct MomentumLyricTimingTests {
    private static func line(_ words: [(String, TimeInterval, TimeInterval)]) -> LyricLine {
        LyricLine(
            id: UUID(),
            text: words.map(\.0).joined(),
            timestamp: words.first?.1 ?? 0,
            endTimestamp: words.last?.2,
            words: words.map { LyricWord(text: $0.0, timestamp: $0.1, endTimestamp: $0.2) },
            translatedText: nil,
            background: [],
            agent: nil,
            songPart: nil
        )
    }

    @Test("Joins syllables into words and marks only long held words for emphasis")
    func groupsAndEmphasis() throws {
        let timing = try #require(MomentumLineTiming(line: Self.line([
            ("I ", 10.0, 10.3),
            ("lo", 10.3, 10.8),
            ("ve ", 10.8, 12.2),
            ("you", 12.2, 12.6),
        ])))
        #expect(timing.groups.count == 3)
        #expect(timing.tokens.map(\.group) == [0, 1, 1, 2])
        #expect(timing.tokens[2].glyphOffset == 2)
        #expect(timing.groups[0].emphasis == 0)
        #expect(timing.groups[1].emphasis > 0)
        #expect(timing.groups[1].glyphCount == 4)
        #expect(timing.groups[2].emphasis == 0)
        #expect(abs(timing.animationEnd - (12.6 + MomentumLineTiming.settleDuration)) < 0.0001)
    }

    @Test("Fill progress runs from 0 to 1 across each token")
    func progress() throws {
        let timing = try #require(MomentumLineTiming(line: Self.line([("Hello ", 1, 2), ("world", 2, 2)])))
        #expect(timing.progress(ofToken: 0, at: 0.5) == 0)
        #expect(timing.progress(ofToken: 0, at: 1.5) == 0.5)
        #expect(timing.progress(ofToken: 0, at: 3) == 1)
        #expect(timing.progress(ofToken: 1, at: 2.01) == 1)
    }

    @Test("A held word swells in a wave and relaxes after the note")
    func swell() throws {
        let timing = try #require(MomentumLineTiming(line: Self.line([("Ohhh", 0, 2)])))
        #expect(timing.swell(ofGroup: 0, glyph: 0, at: 0) == 0)
        #expect(timing.swell(ofGroup: 0, glyph: 0, at: 1) > timing.swell(ofGroup: 0, glyph: 3, at: 1))
        #expect(timing.swell(ofGroup: 0, glyph: 3, at: 2) > 0.5)
        #expect(timing.swell(ofGroup: 0, glyph: 3, at: 2 + MomentumLineTiming.settleDuration) == 0)
        for t in stride(from: 0.0, through: 3.0, by: 0.05) {
            #expect((0...1).contains(timing.swell(ofGroup: 0, glyph: 2, at: t)))
        }
    }

    @Test("Lines whose words don't rebuild the text fall back to plain rendering")
    func rejectsUnreconstructibleLines() {
        let line = LyricLine(
            id: UUID(), text: "Different text", timestamp: 0, endTimestamp: 1,
            words: [LyricWord(text: "Other", timestamp: 0, endTimestamp: 1)],
            translatedText: nil, background: [], agent: nil, songPart: nil
        )
        #expect(MomentumLineTiming(line: line) == nil)
    }
}