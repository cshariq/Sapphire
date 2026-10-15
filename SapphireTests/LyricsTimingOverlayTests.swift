//
//  LyricsTimingOverlayTests.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-10-12

import Foundation
import Testing
@testable import Sapphire

@Suite("Lyrics timing overlays")
struct LyricsTimingOverlayTests {
    private static func line(_ text: String, at start: TimeInterval) -> LyricLine {
        LyricLine(id: UUID(), text: text, timestamp: start, endTimestamp: nil, words: [], translatedText: nil, background: [], agent: nil, songPart: nil)
    }

    private static let overlay = LyricsTimingOverlay(lines: [
        .init(hash: LyricsTimingOverlay.hash(ofLine: "I love you so")!, words: [
            .init(start: 10_000, end: 10_300),
            .init(start: 10_300, end: 12_200, syllables: [.init(letterOffset: 2, start: 10_900)]),
            .init(start: 12_200, end: 12_600),
            .init(start: 12_600, end: 13_000),
        ]),
        .init(hash: LyricsTimingOverlay.hash(ofLine: "Never let go")!, words: [
            .init(start: 14_000, end: 14_400), .init(start: 14_400, end: 14_700), .init(start: 14_700, end: 15_500),
        ]),
    ])

    @Test("Fingerprints ignore case and punctuation, so any provider's text matches")
    func fingerprints() {
        #expect(LyricsTimingOverlay.hash(ofLine: "I love you so") == LyricsTimingOverlay.hash(ofLine: "i LOVE you, so!"))
        #expect(LyricsTimingOverlay.hash(ofLine: "I love you so") != LyricsTimingOverlay.hash(ofLine: "I love you too"))
        #expect(LyricsTimingOverlay.hash(ofLine: " — ") == nil)
    }

    @Test("Lays timing over another provider's text, keeping its exact characters")
    func appliesToProviderText() throws {
        let target = [Self.line("I LOVE you, so!", at: 9.8), Self.line("", at: 13.2), Self.line("Never let go...", at: 13.9)]
        let timed = try #require(Self.overlay.apply(to: target))
        #expect(timed.map(\.text) == target.map(\.text))
        #expect(timed.allSatisfy { $0.text.isEmpty || $0.hasReconstructibleWordTiming })
        #expect(timed[0].words.map(\.text) == ["I ", "LO", "VE ", "you, ", "so!"])
        #expect(timed[0].words[2].timestamp == 10.9)
        #expect(timed[0].words[2].endTimestamp == 12.2)
        #expect(timed[0].timestamp == 9.8)
        #expect(timed[1].words.isEmpty)
        #expect(timed[2].words.last?.text == "go...")
        #expect(timed[0].id == target[0].id)
    }

    @Test("Refuses lyrics that don't match")
    func rejectsOtherLyrics() {
        let target = [Self.line("Completely different words", at: 1), Self.line("Never let go", at: 14)]
        #expect(Self.overlay.apply(to: target) == nil)
    }

    @Test("Round-trips through the compact encoding")
    func encoding() throws {
        let data = try #require(Self.overlay.encoded())
        #expect(LyricsTimingOverlay(encoded: data) == Self.overlay)
        #expect(LyricsTimingOverlay(encoded: Data("{\"l\":[{\"h\":\"short\",\"w\":[[1,2]]}]}".utf8)) == nil)
        #expect(LyricsTimingOverlay(encoded: Data("{\"l\":[{\"h\":\"1a2b3c4d\",\"w\":[[5,2]]}]}".utf8)) == nil)
        #expect(!String(decoding: data, as: UTF8.self).contains("love"))
    }

    @Test("Consensus averages agreeing listens and ignores outliers")
    func consensus() throws {
        var newer = Self.overlay
        newer.lines[0].words[0].start = 10_100
        newer.lines[0].words[2].start = 13_500
        let merged = Self.overlay.merged(with: newer, samples: 3)
        #expect(merged.lines[0].words[0].start == 10_025)
        #expect(merged.lines[0].words[2].start == 12_200)
        #expect(merged.lines[1] == Self.overlay.lines[1])
    }

    @Test("Partial listens add the lines they heard until the song is covered")
    func partialListens() throws {
        let first = LyricsTimingOverlay(lines: [Self.overlay.lines[0]])
        let second = LyricsTimingOverlay(lines: [Self.overlay.lines[1]])
        let target = [Self.line("I love you so", at: 9.8), Self.line("Never let go", at: 13.9)]
        #expect(first.fit(to: target) == (1, 0.5))
        #expect(first.apply(to: target) == nil)
        let combined = first.merged(with: second, samples: 1)
        #expect(combined.lines.map(\.hash) == Self.overlay.lines.map(\.hash))
        #expect(combined.apply(to: target) != nil)
        let unrelated = LyricsTimingOverlay(lines: [.init(hash: "00000000", words: [.init(start: 1, end: 2)])])
        #expect(unrelated.fit(to: target).found == 0)
    }
}

@Suite("Lyrics timing refinement")
struct LyricsTimingRefinerTests {
    private static func envelope(onsetsAt times: [TimeInterval]) -> LyricsOnsetEnvelope {
        var strength = [Float](repeating: 0.2, count: 3000)
        for time in times { strength[Int((time * 100).rounded())] = 6 }
        return LyricsOnsetEnvelope(start: 0, strength: strength)
    }

    @Test("Snaps word starts to nearby vocal onsets and keeps words in order")
    func snapsToOnsets() {
        let onsets = Self.envelope(onsetsAt: [1.05, 1.52, 3.0])
        var starts: [TimeInterval] = [1.0, 1.6, 2.0]
        var ends: [TimeInterval] = [1.6, 2.0, 2.4]
        LyricsTimingRefiner.snap(starts: &starts, ends: &ends, to: onsets)
        #expect(abs(starts[0] - 1.05) < 0.001)
        #expect(abs(starts[1] - 1.52) < 0.001)
        #expect(starts[2] == 2.0)
        #expect(abs(ends[0] - starts[1]) < 0.001)
        #expect(ends[1] == starts[2])
    }

    @Test("Finds no onset where nothing stands out")
    func ignoresFlatAudio() {
        let flat = LyricsOnsetEnvelope(start: 0, strength: [Float](repeating: 0.3, count: 500))
        #expect(flat.onset(near: 2, within: 0.12) == nil)
    }

    @Test("Splits sustained words at hyphenation points")
    func syllables() {
        let english = Locale(identifier: "en_US")
        #expect(LyricsTimingRefiner.hyphenationOffsets("forever", locale: english).isEmpty == false)
        let pieces = LyricsTimingRefiner.syllables(of: "forever ", start: 5, end: 6.5, onsets: nil, locale: english)
        #expect(!pieces.isEmpty)
        #expect(pieces.allSatisfy { $0.start > 5000 && $0.start < 6500 })
        #expect(LyricsTimingRefiner.syllables(of: "forever", start: 5, end: 5.2, onsets: nil, locale: english).isEmpty)
    }

    @Test("Builds an overlay that lays back over the source lyrics")
    func buildsOverlay() throws {
        let line = LyricLine(
            id: UUID(), text: "Hold on, forever", timestamp: 1, endTimestamp: 4,
            words: [
                LyricWord(text: "Hold ", timestamp: 1.0, endTimestamp: 1.4),
                LyricWord(text: "on, ", timestamp: 1.4, endTimestamp: 1.9),
                LyricWord(text: "forever", timestamp: 1.9, endTimestamp: 3.6),
            ],
            translatedText: nil, background: [], agent: nil, songPart: nil
        )
        let overlay = LyricsTimingRefiner.overlay(from: [line], onsets: nil, locale: Locale(identifier: "en_US"))
        #expect(overlay.lines.count == 1)
        let plain = LyricLine(id: line.id, text: line.text, timestamp: 1, endTimestamp: 4, words: [], translatedText: nil, background: [], agent: nil, songPart: nil)
        let timed = try #require(overlay.apply(to: [plain]))
        #expect(timed[0].hasReconstructibleWordTiming)
        #expect(timed[0].words.count > 3)
    }
}

@Suite("Lyrics timing score")
struct LyricsTimingScoreTests {
    @Test("Scores word starts against hand-timed syllables")
    func scores() throws {
        let truth = LyricLine(
            id: UUID(), text: "Hello forever", timestamp: 1, endTimestamp: 3,
            words: [
                LyricWord(text: "Hel", timestamp: 1.0, endTimestamp: 1.2),
                LyricWord(text: "lo ", timestamp: 1.2, endTimestamp: 1.5),
                LyricWord(text: "for", timestamp: 1.5, endTimestamp: 2.0),
                LyricWord(text: "ever", timestamp: 2.0, endTimestamp: 3.0),
            ],
            translatedText: nil, background: [], agent: nil, songPart: nil
        )
        #expect(LyricsTimingScore.wordStarts(of: truth) == [1.0, 1.5])
        let overlay = LyricsTimingOverlay(lines: [
            .init(hash: LyricsTimingOverlay.hash(ofLine: "hello, forever!")!, words: [.init(start: 1_040, end: 1_500), .init(start: 1_650, end: 3_000)]),
        ])
        let score = LyricsTimingScore.compare(overlay, groundTruth: [truth])
        #expect(score.words == 2)
        #expect(score.timedWords == 2)
        #expect(score.within50 == 0.5)
        #expect(score.within200 == 1)
        #expect(score.p90ErrorMs == 150)
        #expect(LyricsTimingScore.compare(LyricsTimingOverlay(lines: []), groundTruth: [truth]).timedWords == 0)
    }
}

@Suite("Lyrics language handling")
struct LyricsLanguageTests {
    private static let supported = ["en_CA", "en_SG", "en_US", "es_CL", "es_US", "ja_JP", "ko_KR", "zh_CN", "zh_HK", "zh_TW", "fr_FR", "fr_CA"]
        .map(Locale.init(identifier:))

    @Test("Picks the listener's regional model, else a widely used one, and pairs Mandarin with Cantonese")
    @available(macOS 26.0, *)
    func speechLocales() {
        func pick(_ language: String, _ current: String) -> [String] {
            LyricsWordTimingGenerator.preferredSpeechLocales(language: language, supported: Self.supported, current: Locale(identifier: current)).map(\.identifier)
        }
        #expect(pick("en", "en_CA") == ["en_CA"])
        #expect(pick("en", "de_DE") == ["en_US"])
        #expect(pick("es", "en_CA") == ["es_US"])
        #expect(pick("fr", "en_CA") == ["fr_CA"])
        #expect(pick("zh-Hans", "en_CA") == ["zh_CN", "zh_HK"])
        #expect(pick("zh-Hant", "en_CA") == ["zh_HK", "zh_TW"])
        #expect(pick("ru", "en_CA").isEmpty)
    }

    @Test("Traditional and Simplified Chinese compare equal")
    func chineseScripts() {
        #expect(LyricsWordAligner.matchKey("愛") == LyricsWordAligner.matchKey("爱"))
        #expect(LyricsTimingOverlay.hash(ofLine: "我愛你") == LyricsTimingOverlay.hash(ofLine: "我爱你"))
        #expect(LyricsWordAligner.matchKey("Café!") == "cafe")
    }
}

@Suite("Word timing from line timing")
struct LyricsLineTimingTests {
    private static func line(_ text: String, at start: TimeInterval) -> LyricLine {
        LyricLine(id: UUID(), text: text, timestamp: start, endTimestamp: nil, words: [], translatedText: nil, background: [], agent: nil, songPart: nil)
    }

    @Test("Estimates word-by-word timing inside each provider line, keeping line starts")
    func estimates() throws {
        let lines = [Self.line("Hello beautiful world", at: 10), Self.line("Again", at: 30), Self.line("", at: 40)]
        let timed = LyricsTimingRefiner.estimatedWords(for: lines)
        #expect(timed[0].hasReconstructibleWordTiming)
        #expect(timed[0].words.first?.timestamp == 10)
        #expect(timed[0].words.map(\.text) == ["Hello ", "beautiful ", "world"])
        let end = try #require(timed[0].words.last?.endTimestamp)
        #expect(end < 13)
        let hello = timed[0].words[1].timestamp - timed[0].words[0].timestamp
        let beautiful = timed[0].words[2].timestamp - timed[0].words[1].timestamp
        #expect(beautiful > hello)
        #expect(timed[2].words.isEmpty)
        #expect(LyricsTimingRefiner.syllableEstimate("beautiful") == 3)
        #expect(LyricsTimingRefiner.syllableEstimate("愛してる") == 4)
    }

    @Test("Anchors recognized words to the provider's line start and keeps them inside the line")
    func anchors() {
        let plain = [Self.line("one two three", at: 10), Self.line("four", at: 11)]
        let heard = [
            RecognizedWord(text: "one", start: 10.25, end: 10.45),
            RecognizedWord(text: "two", start: 10.55, end: 10.8),
            RecognizedWord(text: "three", start: 10.9, end: 11.6),
        ]
        let alignment = LyricsWordAligner.align(lines: plain, recognized: heard)
        let anchored = LyricsTimingRefiner.anchored(alignment, to: plain, bias: 0.05)
        #expect(anchored[0].words.first?.timestamp == 10)
        #expect((anchored[0].words.last?.endTimestamp ?? 99) <= 11.0001)
        #expect(anchored[0].words[1].timestamp > 10.2)
    }
}

@Suite("Apple Music lyric features")
struct LyricsAppleFeatureTests {
    private static func line(_ text: String, at start: TimeInterval, agent: String? = nil) -> LyricLine {
        LyricLine(id: UUID(), text: text, timestamp: start, agent: agent)
    }

    @Test("Parenthesized backing parts become timed background vocals")
    func backgroundVocals() throws {
        let lines = LyricsVocalParts.split([
            Self.line("I'm on my way (on my way)", at: 10),
            Self.line("(Ooh, ooh)", at: 14),
            Self.line("Nothing here", at: 20),
        ])
        #expect(lines[0].text == "I'm on my way")
        #expect(lines[0].background.map(\.text).joined() == "on my way")
        #expect(lines[1].text == "(Ooh, ooh)")
        #expect(lines[1].background.isEmpty)
        #expect(lines[2].background.isEmpty)

        let timed = LyricsVocalParts.timedBackground(LyricsTimingRefiner.estimatedWords(for: lines))
        let background = try #require(LyricsVocalParts.backgroundLine(of: timed[0]))
        #expect(background.hasReconstructibleWordTiming)
        let leadEnd = try #require(timed[0].words.last?.endTimestamp)
        #expect(background.timestamp >= leadEnd - 0.001)
        #expect((background.words.last?.endTimestamp ?? 99) <= 14)
        #expect(LyricsTimingOverlay.hash(ofLine: timed[0].text) == LyricsTimingOverlay.hash(ofLine: "I'm on my way"))
    }

    @Test("Duets put the second singer on the right")
    func duets() {
        let lines = [Self.line("a", at: 1, agent: "v1"), Self.line("b", at: 2, agent: "v2"), Self.line("c", at: 3, agent: "v1")]
        let sides = LyricsLayout.duetSides(lines)
        #expect(sides[lines[0].id] == .leading)
        #expect(sides[lines[1].id] == .trailing)
        #expect(LyricsLayout.duetSides([Self.line("solo", at: 1, agent: "v1")]).isEmpty)
    }

    @Test("Instrumental breaks of four seconds or more show the interlude dots")
    func interludes() throws {
        let lines = LyricsTimingRefiner.estimatedWords(for: [Self.line("Intro words here", at: 6), Self.line("Second line", at: 8), Self.line("After the solo", at: 30)])
        let intro = try #require(LyricsLayout.interlude(in: lines, at: 2))
        #expect(intro.nextIndex == 0)
        #expect(intro.end == 6)
        #expect(LyricsLayout.interlude(in: lines, at: 7) == nil)
        let solo = try #require(LyricsLayout.interlude(in: lines, at: 20))
        #expect(solo.nextIndex == 2)
        #expect(solo.start < 12)
    }
}

@Suite("Apple Music TTML")
struct AppleMusicTTMLTests {
    private static let ttml = """
    <tt xmlns="http://www.w3.org/ns/ttml" xmlns:itunes="http://music.apple.com/lyric-ttml-internal" xmlns:ttm="http://www.w3.org/ns/ttml#metadata" itunes:timing="Word" xml:lang="en"><head><metadata><ttm:agent type="person" xml:id="v1"/><ttm:agent type="person" xml:id="v2"/><iTunesMetadata xmlns="http://music.apple.com/lyric-ttml-internal"><transliterations><transliteration xml:lang="ja-Latn"><text for="L3"><span>ki</span><span>mi</span></text></transliteration></transliterations></iTunesMetadata></metadata></head><body dur="20.000"><div begin="1.000" end="9.000" itunes:songPart="Verse"><p begin="1.000" end="3.500" itunes:key="L1" ttm:agent="v1"><span begin="1.000" end="1.400">Hel</span><span begin="1.400" end="1.900">lo</span> <span begin="2.000" end="3.000">world</span><span ttm:role="x-bg"><span begin="3.000" end="3.300">(echo</span> <span begin="3.300" end="3.500">echo)</span></span></p><p begin="4.000" end="6.000" itunes:key="L2" ttm:agent="v2"><span begin="4.000" end="5.000">Second</span> <span begin="5.000" end="6.000">voice</span></p><p begin="0:07.000" end="0:09.000" itunes:key="L3" ttm:agent="v1"><span begin="7.000" end="9.000">君</span></p></div></body></tt>
    """

    @Test("Parses syllables, background vocals, singers, song parts and pronunciation")
    func parses() throws {
        let lines = try #require(AppleMusicTTMLParser.lines(from: Self.ttml))
        #expect(lines.count == 3)
        #expect(lines[0].text == "Hello world")
        #expect(lines[0].words.map(\.text) == ["Hel", "lo ", "world"])
        #expect(lines[0].hasReconstructibleWordTiming)
        #expect(lines[0].words[1].timestamp == 1.4)
        #expect(lines[0].background.map(\.text) == ["(echo ", "echo)"])
        #expect(lines[0].agent == "v1")
        #expect(lines[1].agent == "v2")
        #expect(lines[0].songPart == "Verse")
        #expect(lines[2].timestamp == 7)
        #expect(lines[2].romanization == "kimi")
        #expect(LyricsLayout.duetSides(lines)[lines[1].id] == .trailing)
    }

    @Test("Reads Apple's time formats")
    func times() {
        #expect(AppleMusicTTMLParser.seconds("12.5") == 12.5)
        #expect(AppleMusicTTMLParser.seconds("1:02.5") == 62.5)
        #expect(AppleMusicTTMLParser.seconds("01:01:02.5") == 3662.5)
        #expect(AppleMusicTTMLParser.seconds("3.25s") == 3.25)
        #expect(AppleMusicTTMLParser.seconds("x") == nil)
    }
}