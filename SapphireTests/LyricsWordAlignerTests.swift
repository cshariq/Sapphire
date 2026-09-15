//
//  LyricsWordAlignerTests.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-14

import Foundation
import Testing
@testable import Sapphire

@Suite("Lyrics word aligner")
struct LyricsWordAlignerTests {
    private static func heard(_ text: String, _ start: TimeInterval, _ end: TimeInterval) -> RecognizedWord {
        RecognizedWord(text: text, start: start, end: end)
    }

    @Test("Tokens concatenate back to the exact line text")
    func tokenizerPreservesText() {
        #expect(LyricsWordAligner.tokenize("Alpha beta  gamma") == ["Alpha ", "beta  ", "gamma"])
        #expect(LyricsWordAligner.tokenize(" lead") == [" lead"])
        #expect(LyricsWordAligner.tokenize("你好 world") == ["你", "好 ", "world"])
        for text in ["Alpha beta  gamma", " lead", "你好 world", "trailing "] {
            #expect(LyricsWordAligner.tokenize(text).joined() == text)
        }
    }

    @Test("Takes recognizer timing for every word it heard")
    func perfectRecognition() throws {
        let line = LyricLine(text: "Alpha beta gamma", timestamp: 10, endTimestamp: 13)
        let result = LyricsWordAligner.align(
            lines: [line],
            recognized: [Self.heard("alpha", 10.1, 10.8), Self.heard("Beta", 10.9, 11.6), Self.heard("gamma!", 11.7, 12.9)]
        )

        let words = try #require(result.lines.first?.words)
        #expect(words.map(\.text) == ["Alpha ", "beta ", "gamma"])
        #expect(words.map(\.timestamp) == [10.1, 10.9, 11.7])
        #expect(words.map(\.endTimestamp) == [10.8, 11.6, 12.9])
        #expect(result.confidence == 1)
        #expect(result.lineCoverage == 1)
        #expect(result.lines[0].hasReconstructibleWordTiming)
    }

    @Test("Accepts near misses and spreads unheard words between their neighbours")
    func nearMissesAndGaps() throws {
        let line = LyricLine(text: "Alpha beta gamma delta", timestamp: 0, endTimestamp: 4)
        let result = LyricsWordAligner.align(
            lines: [line],
            recognized: [Self.heard("alpha", 0.0, 1.0), Self.heard("gammer", 2.0, 3.0)]
        )

        let words = try #require(result.lines.first?.words)
        #expect(result.matchedWords == 2)
        #expect(result.totalWords == 4)
        #expect(words[1].timestamp == 1.0)
        #expect(words[1].endTimestamp == 2.0)
        #expect(words[2].timestamp == 2.0)
        #expect(words[3].timestamp == 3.0)
        #expect(words[3].endTimestamp == 4.0)
        #expect(zip(words, words.dropFirst()).allSatisfy { $0.timestamp <= $1.timestamp })
    }

    @Test("Ignores heard words outside a line's window and never reuses them")
    func windowsAndOrdering() {
        let lines = [
            LyricLine(text: "Echo echo", timestamp: 5, endTimestamp: 7),
            LyricLine(text: "Echo again", timestamp: 8, endTimestamp: 10),
            LyricLine(text: "Silent line", timestamp: 20, endTimestamp: 22),
        ]
        let result = LyricsWordAligner.align(
            lines: lines,
            recognized: [
                Self.heard("echo", 1.0, 1.5),
                Self.heard("echo", 5.1, 5.8),
                Self.heard("echo", 6.0, 6.8),
                Self.heard("echo", 8.1, 8.9),
                Self.heard("again", 9.0, 9.8),
            ]
        )

        #expect(result.lines[0].words.map(\.timestamp) == [5.1, 6.0])
        #expect(result.lines[1].words.map(\.timestamp) == [8.1, 9.0])
        #expect(result.lines[2].words.isEmpty)
        #expect(result.alignedLines == 2)
        #expect(result.lyricLines == 3)
        #expect(result.matchedWords == 4)
    }

    @Test("Blank lines pass through untouched and don't count")
    func blankLines() {
        let lines = [LyricLine(text: "", timestamp: 0), LyricLine(text: "Alpha", timestamp: 1, endTimestamp: 2)]
        let result = LyricsWordAligner.align(lines: lines, recognized: [Self.heard("alpha", 1.1, 1.9)])
        #expect(result.lines.count == 2)
        #expect(result.lines[0].words.isEmpty)
        #expect(result.lyricLines == 1)
        #expect(result.confidence == 1)
    }

    @Test("Similarity tolerates small recognition errors only")
    func similarity() {
        #expect(LyricsWordAligner.similarityScore("beta", "beta") == 1)
        #expect(LyricsWordAligner.similarityScore("gamma", "gammer") >= LyricsWordAligner.minimumSimilarity)
        #expect(LyricsWordAligner.similarityScore("alpha", "omega") < LyricsWordAligner.minimumSimilarity)
    }

    @Test("Generated timing round-trips through the Lyricsfile writer and parser")
    func lyricsfileRoundTrip() throws {
        let aligned = LyricsWordAligner.align(
            lines: [
                LyricLine(text: "It's No", timestamp: 1.5, endTimestamp: 3.25),
                LyricLine(text: "", timestamp: 4),
            ],
            recognized: [Self.heard("its", 1.5, 2.0), Self.heard("no", 2.1, 3.2)]
        )
        let yaml = LyricsfileWriter.document(title: "No", artist: "O'Brien", album: nil, lines: aligned.lines)

        let parsed = try #require(LyricsParser.parseLyricsfile(yaml))
        #expect(parsed.map(\.text) == ["It's No", ""])
        #expect(parsed[0].words.map(\.text) == ["It's ", "No"])
        #expect(parsed[0].words.map(\.timestamp) == [1.5, 2.1])
        #expect(parsed[0].endTimestamp == 3.25)
        #expect(parsed[0].hasReconstructibleWordTiming)
    }
}