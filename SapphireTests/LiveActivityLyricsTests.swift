//
//  LiveActivityLyricsTests.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-14

import Foundation
import SwiftUI
import Testing
@testable import Sapphire

@Suite("Live activity lyrics")
struct LiveActivityLyricsTests {
    private static let wordSyncedLine = LyricLine(
        text: "Hello world",
        timestamp: 1,
        endTimestamp: 2,
        words: [
            LyricWord(text: "Hello ", timestamp: 1, endTimestamp: 1.5),
            LyricWord(text: "world", timestamp: 1.5, endTimestamp: 2),
        ]
    )

    private func decide(
        isPlaying: Bool = true,
        setting: Bool = true,
        appAllowed: Bool = true,
        hiddenByFullScreenApp: Bool = false,
        currentLyric: LyricLine?
    ) -> LiveActivityLyricsPolicy.Decision {
        LiveActivityLyricsPolicy.decide(
            isPlaying: isPlaying,
            showLyricsInLiveActivity: setting,
            lyricsAllowedForActiveApp: appAllowed,
            isHiddenByFullScreenApp: hiddenByFullScreenApp,
            currentLyric: currentLyric
        )
    }

    // MARK: Bottom-content decision

    @Test("Shows the current line while playing when lyrics are allowed")
    func showsCurrentLine() {
        #expect(decide(currentLyric: Self.wordSyncedLine) == .show(Self.wordSyncedLine))
    }

    @Test("Reports why lyrics are hidden")
    func reportsHideReasons() {
        #expect(decide(isPlaying: false, currentLyric: Self.wordSyncedLine) == .hide(.notPlaying))
        #expect(decide(setting: false, currentLyric: Self.wordSyncedLine) == .hide(.settingOff))
        #expect(decide(appAllowed: false, currentLyric: Self.wordSyncedLine) == .hide(.disallowedForActiveApp))
        #expect(decide(currentLyric: nil) == .hide(.noCurrentLine))
        #expect(decide(currentLyric: LyricLine(text: "  ", timestamp: 0)) == .hide(.blankLine))
    }

    @Test("Hides the lyrics section when a full-screen app covers the notch display")
    func fullScreenAppHidesLyricsSection() {
        #expect(decide(hiddenByFullScreenApp: true, currentLyric: Self.wordSyncedLine) == .hide(.hiddenByFullScreenApp))
    }

    @Test("A translation makes an otherwise blank line displayable")
    func translationIsDisplayable() {
        let line = LyricLine(text: " ", timestamp: 0, translatedText: "Hola")
        #expect(decide(currentLyric: line) == .show(line))
    }

    @Test("A short pause between lines keeps the line before it; a long one does not")
    func shortPausesKeepThePreviousLine() {
        let first = LyricLine(text: "One", timestamp: 1, endTimestamp: 2)
        let second = LyricLine(text: "Two", timestamp: 3, endTimestamp: 4)
        let third = LyricLine(text: "Three", timestamp: 8, endTimestamp: 9)
        let lyrics = [first, second, third]
        func bridged(_ time: TimeInterval) -> LyricLine? {
            LiveActivityLyricsPolicy.lineBridgingGap(in: lyrics, at: time)
        }

        #expect(bridged(0.5) == nil)
        #expect(bridged(2.5) == first)
        #expect(bridged(4.5) == nil)
        #expect(bridged(9.5) == nil)
        #expect(bridged(1.999) == first)
        #expect(bridged(3.001) == second)
    }

    // MARK: Playback tick

    private static let liveActivityWithLyrics = MusicPlaybackTickPolicy.Inputs(
        isPlaying: true,
        isDetailPlayerOpen: false,
        isLyricsDetailOpen: false,
        isDetachedLyricsOpen: false,
        isMusicLiveActivityActive: true,
        musicLiveActivityEnabled: true,
        showLyricsInLiveActivity: true,
        lyricsAllowedForActiveApp: true,
        hasLyrics: true,
        showNextSong: false,
        upNextSourceSupported: false
    )

    @Test("The tick that advances the current line runs once lyrics are loaded")
    func tickRunsWithLyrics() {
        #expect(MusicPlaybackTickPolicy.interval(for: Self.liveActivityWithLyrics) == 0.5)

        var withoutLyrics = Self.liveActivityWithLyrics
        withoutLyrics.hasLyrics = false
        #expect(MusicPlaybackTickPolicy.interval(for: withoutLyrics) == nil)
    }

    @Test("The tick stops when paused, disabled, hidden, or handled by an anchored timeline")
    func tickGates() {
        var paused = Self.liveActivityWithLyrics
        paused.isPlaying = false
        #expect(MusicPlaybackTickPolicy.interval(for: paused) == nil)

        var inactive = Self.liveActivityWithLyrics
        inactive.isMusicLiveActivityActive = false
        #expect(MusicPlaybackTickPolicy.interval(for: inactive) == nil)

        var disallowed = Self.liveActivityWithLyrics
        disallowed.lyricsAllowedForActiveApp = false
        #expect(MusicPlaybackTickPolicy.interval(for: disallowed) == nil)

        var detail = Self.liveActivityWithLyrics
        detail.hasLyrics = false
        detail.isLyricsDetailOpen = true
        #expect(MusicPlaybackTickPolicy.interval(for: detail) == nil)

        var detached = detail
        detached.isLyricsDetailOpen = false
        detached.isDetachedLyricsOpen = true
        #expect(MusicPlaybackTickPolicy.interval(for: detached) == 0.2)
    }

    @Test("Live activity ticks are scheduled at content boundaries")
    func eventDrivenTick() throws {
        let lyrics = [
            LyricLine(text: "First", timestamp: 1, endTimestamp: 2),
            LyricLine(text: "Second", timestamp: 3, endTimestamp: 4),
        ]
        let delay = MusicPlaybackTickPolicy.nextLiveActivityEventDelay(
            for: Self.liveActivityWithLyrics,
            elapsed: 1.25,
            lyricsElapsed: 1.25,
            lyrics: lyrics,
            duration: 100
        )
        #expect(abs(try #require(delay) - 0.75) < 1e-9)
    }

    // MARK: Word fill

    @Test("A word fills over its own duration")
    func wordFillWindows() {
        let line = LyricLine(
            text: "a b c",
            timestamp: 1,
            endTimestamp: 4,
            words: [
                LyricWord(text: "a ", timestamp: 1, endTimestamp: 1.5),
                LyricWord(text: "b ", timestamp: 2),
                LyricWord(text: "c", timestamp: 3),
            ]
        )
        #expect(KaraokeTickerTimeline(line: line).fills == [
            .init(start: 1, end: 1.5),
            .init(start: 2, end: 3),
            .init(start: 3, end: 4),
        ])

        let unended = LyricLine(text: "a", timestamp: 1, words: [LyricWord(text: "a", timestamp: 1)])
        #expect(KaraokeTickerTimeline(line: unended).fills == [.init(start: 1, end: 1)])
    }

    @Test("The ticker centres a word once it and every word before it have started")
    func tickerSteps() {
        let line = LyricLine(
            text: "a b c d e",
            timestamp: 1,
            words: [
                LyricWord(text: "a ", timestamp: 1),
                LyricWord(text: "b ", timestamp: 2),
                LyricWord(text: "c ", timestamp: 2),
                LyricWord(text: "d ", timestamp: 1.5),
                LyricWord(text: "e", timestamp: 3),
            ]
        )
        #expect(KaraokeTickerTimeline(line: line).steps == [
            .init(time: 2, word: 3),
            .init(time: 3, word: 4),
        ])
    }

    @Test("Missing word ends fall back to the next word's start, then the line end")
    func wordFillEnds() {
        let line = LyricLine(
            text: "a b",
            timestamp: 1,
            endTimestamp: 3,
            words: [LyricWord(text: "a ", timestamp: 1), LyricWord(text: "b", timestamp: 2)]
        )
        #expect(line.wordFillEndTimestamp(at: 0) == 2)
        #expect(line.wordFillEndTimestamp(at: 1) == 3)
        #expect(line.wordFillEndTimestamp(at: 2) == nil)
    }

    @Test("The fill schedule advances only at word boundaries")
    func fillScheduleCadence() throws {
        let reference = Date(timeIntervalSinceReferenceDate: 0)
        let schedule = KaraokeFillSchedule(
            referenceDate: reference,
            referenceElapsed: 1.0,
            windows: [1.0...1.5, 3.0...4.0]
        )
        var entries = schedule.entries(from: reference, mode: .normal)
        var dates: [Date] = []
        for _ in 0..<6 {
            let next = entries.next()
            dates.append(try #require(next))
        }

        let gaps = zip(dates, dates.dropFirst()).map { $1.timeIntervalSince($0) }
        #expect(gaps.allSatisfy { $0 > 0 })
        let landing = KaraokeFillSchedule.landingDelay
        let expected = [
            0, landing, 0.5 + landing, 2 + landing, 3 + landing,
            3 + landing + KaraokeFillSchedule.idleInterval
        ]
        let offsets = dates.map { $0.timeIntervalSince(reference) }
        #expect(zip(offsets, expected).allSatisfy { abs($0 - $1) < 1e-9 })
    }

    @Test("Fill schedule entries read back at or just after their boundary")
    func fillScheduleLandsAfterBoundaries() throws {
        let anchor = PlaybackTimingAnchor(
            elapsedAtSample: 37.218934,
            sampleEpochTime: 1_792_000_000.123457,
            rate: 1
        )
        let referenceDate = Date(timeIntervalSince1970: anchor.sampleEpochTime + 0.734)
        let boundaries = (1...400).map { Double(38_000 + $0 * 137) / 1000 }
        let schedule = KaraokeFillSchedule(
            referenceDate: referenceDate,
            referenceElapsed: anchor.elapsed(at: referenceDate),
            windows: boundaries.map { $0...$0 }
        )
        var entries = schedule.entries(from: referenceDate, mode: .normal)
        _ = entries.next()
        for boundary in boundaries {
            let next = entries.next()
            let elapsed = anchor.elapsed(at: try #require(next))
            #expect(elapsed >= boundary && elapsed < boundary + 0.002)
        }
    }

    // MARK: LRCLIB format

    @Test("Parses the Lyricsfile shape LRCLIB currently serves")
    func parsesLRCLibShape() throws {
        let lyricsfile = """
        version: '1.0'
        metadata:
          title: Placeholder Song
          artist: Placeholder Artist
          album: Placeholder Album
          duration_ms: 200000
          instrumental: false
        lines:
        - text: First placeholder line
          start_ms: 13130
          end_ms: 16560
        - text: Second placeholder line
          start_ms: 16560
          end_ms: 27160
        plain: |-
          First placeholder line
          Second placeholder line
        """
        let payload: [String: Any] = [
            "id": 1,
            "trackName": "Placeholder Song",
            "artistName": "Placeholder Artist",
            "albumName": "Placeholder Album",
            "duration": 200.0,
            "instrumental": false,
            "plainLyrics": "First placeholder line\nSecond placeholder line",
            "syncedLyrics": "[00:13.13] First placeholder line\n[00:16.56] Second placeholder line",
            "lyricsfile": lyricsfile,
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)

        let lyrics = try #require(LyricsParser.parseLRCLibResponse(data))
        #expect(lyrics.map(\.text) == ["First placeholder line", "Second placeholder line"])
        #expect(abs(lyrics[0].timestamp - 13.13) < 1e-9)
        #expect(abs(try #require(lyrics[0].endTimestamp) - 16.56) < 1e-9)
        #expect(lyrics.allSatisfy { !$0.hasWordTiming })
    }
}