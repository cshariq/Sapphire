//
//  LyricsfileTests.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-12

import Foundation
import Testing
@testable import Sapphire

@Suite("Lyricsfile 1.0")
struct LyricsfileTests {
    @Test("Parses word-synced lyrics and preserves significant whitespace")
    func parsesWordSyncedLyrics() throws {
        let lyrics = try #require(LyricsParser.parseLyricsfile(Self.wordSyncedFixture))
        let line = try #require(lyrics.first)

        #expect(lyrics.count == 1)
        #expect(line.text == "Hello world!")
        #expect(isApproximatelyEqual(line.timestamp, 1.2))
        #expect(isApproximatelyEqual(try #require(line.endTimestamp), 2.8))
        #expect(line.hasWordTiming)
        #expect(line.words.map(\.text) == ["Hello ", "world", "!"])
        #expect(line.words.map(\.text).joined() == line.text)

        let firstWord = try #require(line.words.first)
        let lastWord = try #require(line.words.last)
        #expect(isApproximatelyEqual(firstWord.timestamp, 1.2))
        #expect(isApproximatelyEqual(try #require(firstWord.endTimestamp), 1.9))
        #expect(isApproximatelyEqual(lastWord.timestamp, 2.7))
        #expect(isApproximatelyEqual(try #require(lastWord.endTimestamp), 2.8))
    }

    @Test("Preserves millisecond precision and missing end times")
    func preservesMillisecondPrecisionAndMissingEnds() throws {
        let lyrics = try #require(LyricsParser.parseLyricsfile(Self.precisionFixture))

        #expect(lyrics.count == 2)
        let firstLine = lyrics[0]
        let secondLine = lyrics[1]
        let firstWord = try #require(firstLine.words.first)

        #expect(isApproximatelyEqual(firstLine.timestamp, 0.001))
        #expect(firstLine.endTimestamp == nil)
        #expect(isApproximatelyEqual(firstWord.timestamp, 0.001))
        #expect(firstWord.endTimestamp == nil)

        #expect(isApproximatelyEqual(secondLine.timestamp, 1.234))
        #expect(isApproximatelyEqual(try #require(secondLine.endTimestamp), 1.235))
    }

    @Test("Uses complete line text when word timing is absent")
    func supportsLineSyncedFallback() throws {
        let lyrics = try #require(LyricsParser.parseLyricsfile(Self.lineSyncedFixture))

        #expect(lyrics.map(\.text) == ["Words omitted", "Words empty"])
        #expect(lyrics.allSatisfy { $0.words.isEmpty })
        #expect(lyrics.allSatisfy { !$0.hasWordTiming })
    }

    @Test("Preserves word timing when a writer's segments do not reconstruct the line")
    func preservesSemanticallyMismatchedWords() throws {
        let lyrics = try #require(LyricsParser.parseLyricsfile(Self.mismatchedWordsFixture))
        let line = try #require(lyrics.first)

        #expect(line.text == "Authoritative line")
        #expect(line.words.map(\.text) == ["Different segment"])
        #expect(line.hasWordTiming)
    }

    @Test("Preserves CJK segmentation and punctuation without adding spaces")
    func preservesCJKAndPunctuation() throws {
        let lyrics = try #require(LyricsParser.parseLyricsfile(Self.cjkFixture))
        let line = try #require(lyrics.first)

        #expect(line.words.map(\.text) == ["你", "好", "，", "world", "!"])
        #expect(line.words.map(\.text).joined() == "你好，world!")
        #expect(line.words.map(\.text).joined() == line.text)
        #expect(line.hasWordTiming)
    }

    @Test("Treats YAML 1.1 boolean and timestamp spellings as lyric strings")
    func parsesAmbiguousPlainScalarsAsStrings() throws {
        let lyrics = try #require(LyricsParser.parseLyricsfile(Self.ambiguousStringFixture))

        #expect(lyrics.map(\.text) == ["No", "2026-09-12"])
        #expect(lyrics[0].words.map(\.text) == ["No"])
    }

    @Test("Rejects invalid Lyricsfile documents and falls back to LRC")
    func rejectsInvalidDocumentsAndFallsBackToLRC() throws {
        for fixture in Self.invalidFixtures {
            #expect(
                LyricsParser.parseLyricsfile(fixture.yaml) == nil,
                "Expected \(fixture.name) to be rejected"
            )

            let response = try Self.lrclibResponse(
                lyricsfile: fixture.yaml,
                syncedLyrics: "[00:01.25] Fallback lyric"
            )
            let fallback = try #require(LyricsParser.parseLRCLibResponse(response))

            #expect(fallback.map(\.text) == ["Fallback lyric"], "Failed fallback for \(fixture.name)")
            #expect(isApproximatelyEqual(fallback[0].timestamp, 1.25))
            #expect(!fallback[0].hasWordTiming)
        }
    }

    @Test("Prefers Lyricsfile over conflicting legacy LRC")
    func responsePrefersLyricsfile() throws {
        let response = try Self.lrclibResponse(
            lyricsfile: Self.wordSyncedFixture,
            syncedLyrics: "[00:00.50] Legacy lyric"
        )
        let lyrics = try #require(LyricsParser.parseLRCLibResponse(response))

        #expect(lyrics.count == 1)
        #expect(lyrics[0].text == "Hello world!")
        #expect(isApproximatelyEqual(lyrics[0].timestamp, 1.2))
        #expect(lyrics[0].hasWordTiming)
    }

    @Test("Keeps a valid empty instrumental Lyricsfile authoritative")
    func responsePrefersValidEmptyLyricsfile() throws {
        let response = try Self.lrclibResponse(
            lyricsfile: Self.instrumentalFixture,
            syncedLyrics: "[00:00.50] Stale legacy lyric"
        )
        let lyrics = try #require(LyricsParser.parseLRCLibResponse(response))

        #expect(lyrics.isEmpty)
    }

    @Test("Falls back to LRC when Lyricsfile is absent or blank")
    func responseFallsBackWhenLyricsfileIsUnavailable() throws {
        let unavailableLyricsfiles: [String?] = [nil, "", "  \n\t"]

        for lyricsfile in unavailableLyricsfiles {
            let response = try Self.lrclibResponse(
                lyricsfile: lyricsfile,
                syncedLyrics: "[00:02.50] First line\n[00:03.125] Second line"
            )
            let lyrics = try #require(LyricsParser.parseLRCLibResponse(response))

            #expect(lyrics.map(\.text) == ["First line", "Second line"])
            #expect(isApproximatelyEqual(lyrics[0].timestamp, 2.5))
            #expect(isApproximatelyEqual(lyrics[1].timestamp, 3.125))
        }
    }

    @Test("Keeps overlapping lines active and selects the latest line as primary")
    func supportsOverlappingLines() throws {
        let lyrics = try #require(LyricsParser.parseLyricsfile(Self.overlapFixture))

        #expect(LyricsTimeline.activeIndices(in: lyrics, at: 0.999, trackDuration: 5) == [])
        #expect(LyricsTimeline.activeIndices(in: lyrics, at: 1.0, trackDuration: 5) == [0])
        #expect(LyricsTimeline.activeIndices(in: lyrics, at: 2.5, trackDuration: 5) == [0, 1])
        #expect(LyricsTimeline.primaryIndex(in: lyrics, at: 2.5, trackDuration: 5) == 1)
        #expect(LyricsTimeline.activeIndices(in: lyrics, at: 3.0, trackDuration: 5) == [1])
        #expect(LyricsTimeline.activeIndices(in: lyrics, at: 4.0, trackDuration: 5) == [])
    }

    @Test("Infers display bounds for lines without end times")
    func handlesMissingLineEndsOnTimeline() throws {
        let lyrics = try #require(LyricsParser.parseLyricsfile(Self.missingLineEndsFixture))

        #expect(LyricsTimeline.activeIndices(in: lyrics, at: 1.5, trackDuration: 5) == [0])
        #expect(LyricsTimeline.primaryIndex(in: lyrics, at: 1.5, trackDuration: 5) == 0)
        #expect(LyricsTimeline.activeIndices(in: lyrics, at: 2.0, trackDuration: 5) == [1])
        #expect(LyricsTimeline.primaryIndex(in: lyrics, at: 4.999, trackDuration: 5) == 1)
        #expect(LyricsTimeline.activeIndices(in: lyrics, at: 5.0, trackDuration: 5) == [])
    }

    @Test("Infers one shared end for simultaneous lines")
    func handlesSimultaneousLinesWithoutEnds() {
        let lyrics = [
            LyricLine(text: "First voice", timestamp: 1),
            LyricLine(text: "Second voice", timestamp: 1),
            LyricLine(text: "Next line", timestamp: 2),
        ]

        #expect(LyricsTimeline.activeIndices(in: lyrics, at: 1.5, trackDuration: 5) == [0, 1])
        #expect(LyricsTimeline.primaryIndex(in: lyrics, at: 1.5, trackDuration: 5) == 1)
        #expect(LyricsTimeline.activeIndices(in: lyrics, at: 2, trackDuration: 5) == [2])
    }

    private static let wordSyncedFixture = """
    version: '1.0'
    metadata:
      title: 'Example Song'
      artist: 'Example Artist'
      language: 'en'
      instrumental: false
    lines:
      - text: 'Hello world!'
        start_ms: 1200
        end_ms: 2800
        words:
          - text: 'Hello '
            start_ms: 1200
            end_ms: 1900
          - text: 'world'
            start_ms: 1900
            end_ms: 2700
          - text: '!'
            start_ms: 2700
            end_ms: 2800
    plain: |
      Hello world!
    """

    private static let precisionFixture = """
    version: '1.0'
    metadata:
      title: 'Precision'
      artist: 'Test Artist'
    lines:
      - text: 'A'
        start_ms: 1
        words:
          - text: 'A'
            start_ms: 1
      - text: 'B'
        start_ms: 1234
        end_ms: 1235
    """

    private static let lineSyncedFixture = """
    version: '1.0'
    metadata:
      title: 'Line Sync'
      artist: 'Test Artist'
    lines:
      - text: 'Words omitted'
        start_ms: 1000
        end_ms: 1900
      - text: 'Words empty'
        start_ms: 2000
        end_ms: 2900
        words: []
    """

    private static let mismatchedWordsFixture = """
    version: '1.0'
    metadata:
      title: 'Mismatched Segments'
      artist: 'Test Artist'
    lines:
      - text: 'Authoritative line'
        start_ms: 1000
        words:
          - text: 'Different segment'
            start_ms: 1000
    """

    private static let cjkFixture = """
    version: '1.0'
    metadata:
      title: 'Segments'
      artist: 'Test Artist'
    lines:
      - text: '你好，world!'
        start_ms: 1000
        end_ms: 2000
        words:
          - text: '你'
            start_ms: 1000
            end_ms: 1150
          - text: '好'
            start_ms: 1150
            end_ms: 1300
          - text: '，'
            start_ms: 1300
            end_ms: 1400
          - text: 'world'
            start_ms: 1400
            end_ms: 1900
          - text: '!'
            start_ms: 1900
            end_ms: 2000
    """

    private static let ambiguousStringFixture = """
    version: '1.0'
    metadata:
      title: NO
      artist: yes
      instrumental: false
    lines:
      - text: No
        start_ms: 0
        words:
          - text: No
            start_ms: 0
      - text: 2026-09-12
        start_ms: 1000
    """

    private static let instrumentalFixture = """
    version: '1.0'
    metadata:
      title: 'Instrumental'
      artist: 'Test Artist'
      instrumental: true
    lines: []
    plain: ''
    """

    private static let overlapFixture = """
    version: '1.0'
    metadata:
      title: 'Overlap'
      artist: 'Test Artist'
    lines:
      - text: 'First voice'
        start_ms: 1000
        end_ms: 3000
      - text: 'Second voice'
        start_ms: 2000
        end_ms: 4000
    """

    private static let missingLineEndsFixture = """
    version: '1.0'
    metadata:
      title: 'Open Ends'
      artist: 'Test Artist'
    lines:
      - text: 'First line'
        start_ms: 1000
      - text: 'Last line'
        start_ms: 2000
    """

    private static let invalidFixtures: [(name: String, yaml: String)] = [
        (
            "malformed YAML",
            """
            version: '1.0'
            metadata: [
            """
        ),
        (
            "unknown version",
            """
            version: '2.0'
            metadata:
              title: 'Future'
              artist: 'Test Artist'
            lines:
              - text: 'Do not interpret as 1.0'
                start_ms: 1000
            """
        ),
        (
            "negative line start",
            """
            version: '1.0'
            metadata:
              title: 'Negative'
              artist: 'Test Artist'
            lines:
              - text: 'Invalid'
                start_ms: -1
            """
        ),
        (
            "line end before start",
            """
            version: '1.0'
            metadata:
              title: 'Backwards'
              artist: 'Test Artist'
            lines:
              - text: 'Invalid'
                start_ms: 1000
                end_ms: 999
            """
        ),
        (
            "negative word start",
            """
            version: '1.0'
            metadata:
              title: 'Negative Word'
              artist: 'Test Artist'
            lines:
              - text: 'Invalid'
                start_ms: 0
                words:
                  - text: 'Invalid'
                    start_ms: -1
            """
        ),
        (
            "word end before start",
            """
            version: '1.0'
            metadata:
              title: 'Backwards Word'
              artist: 'Test Artist'
            lines:
              - text: 'Invalid'
                start_ms: 1000
                words:
                  - text: 'Invalid'
                    start_ms: 1000
                    end_ms: 999
            """
        ),
        (
            "duplicate keys",
            """
            version: '1.0'
            version: '1.0'
            metadata:
              title: 'Duplicate'
              artist: 'Test Artist'
            lines:
              - text: 'Invalid'
                start_ms: 1000
            """
        ),
    ]

    private static func lrclibResponse(
        lyricsfile: String?,
        syncedLyrics: String?
    ) throws -> Data {
        var payload: [String: Any] = [
            "id": 1,
            "name": "Fixture",
            "trackName": "Fixture",
            "artistName": "Test Artist",
            "albumName": "Test Album",
            "duration": 5,
            "instrumental": false,
            "plainLyrics": NSNull(),
        ]
        payload["lyricsfile"] = lyricsfile.map { $0 as Any } ?? NSNull()
        payload["syncedLyrics"] = syncedLyrics.map { $0 as Any } ?? NSNull()
        return try JSONSerialization.data(withJSONObject: payload)
    }
}

private func isApproximatelyEqual(
    _ lhs: TimeInterval,
    _ rhs: TimeInterval,
    tolerance: TimeInterval = 0.000_000_1
) -> Bool {
    abs(lhs - rhs) <= tolerance
}