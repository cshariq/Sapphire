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
        currentLyric: LyricLine?
    ) -> LiveActivityLyricsPolicy.Decision {
        LiveActivityLyricsPolicy.decide(
            isPlaying: isPlaying,
            showLyricsInLiveActivity: setting,
            lyricsAllowedForActiveApp: appAllowed,
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

    @Test("A translation makes an otherwise blank line displayable")
    func translationIsDisplayable() {
        let line = LyricLine(text: " ", timestamp: 0, translatedText: "Hola")
        #expect(decide(currentLyric: line) == .show(line))
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

    @Test("The tick stops when paused, disabled, or hidden, and speeds up for detail views")
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
        #expect(MusicPlaybackTickPolicy.interval(for: detail) == 0.2)
    }

    // MARK: Word fill

    @Test("A word fills over its own duration")
    func wordFillFraction() {
        #expect(KaraokeWordView.fillFraction(elapsed: 0.9, start: 1, fillEnd: 2) == 0)
        #expect(abs(KaraokeWordView.fillFraction(elapsed: 1.25, start: 1, fillEnd: 2) - 0.25) < 1e-9)
        #expect(KaraokeWordView.fillFraction(elapsed: 2.5, start: 1, fillEnd: 2) == 1)
        #expect(KaraokeWordView.fillFraction(elapsed: 1.1, start: 1, fillEnd: nil) == 1)
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

    @Test("The fill schedule always advances, at 30 fps inside a word and 0.25s between words")
    func fillScheduleCadence() throws {
        let reference = Date(timeIntervalSinceReferenceDate: 0)
        let schedule = KaraokeFillSchedule(
            referenceDate: reference,
            referenceElapsed: 1.0,
            windows: [1.0...1.5, 3.0...4.0]
        )
        var entries = schedule.entries(from: reference, mode: .normal)
        var dates: [Date] = []
        for _ in 0..<200 {
            let next = entries.next()
            dates.append(try #require(next))
        }

        let gaps = zip(dates, dates.dropFirst()).map { $1.timeIntervalSince($0) }
        #expect(gaps.allSatisfy { $0 > 0 })
        #expect(gaps.allSatisfy { $0 <= KaraokeFillSchedule.fallbackInterval + 1e-9 })
        #expect(abs(gaps[0] - KaraokeFillSchedule.frameInterval) < 1e-9)
        #expect(dates.contains { abs($0.timeIntervalSince(reference) - 2.0) < 1e-9 })
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