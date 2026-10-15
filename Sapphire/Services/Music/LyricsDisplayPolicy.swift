//
//  LyricsDisplayPolicy.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-14

import Foundation

enum LiveActivityLyricsPolicy {
    enum Decision: Equatable {
        case show(LyricLine)
        case hide(Reason)
    }

    enum Reason: String, Equatable {
        case notPlaying = "not playing"
        case settingOff = "Show Lyrics in Live Activity is off"
        case disallowedForActiveApp = "lyrics are hidden for the active app"
        case hiddenByFullScreenApp = "lyrics overlap a full-screen app"
        case noCurrentLine = "no current line (lyrics not loaded, or before/between lines)"
        case blankLine = "current line is blank"
    }

    static func decide(
        isPlaying: Bool,
        showLyricsInLiveActivity: Bool,
        lyricsAllowedForActiveApp: Bool,
        isHiddenByFullScreenApp: Bool = false,
        currentLyric: LyricLine?
    ) -> Decision {
        guard isPlaying else { return .hide(.notPlaying) }
        guard showLyricsInLiveActivity else { return .hide(.settingOff) }
        guard lyricsAllowedForActiveApp else { return .hide(.disallowedForActiveApp) }
        guard !isHiddenByFullScreenApp else { return .hide(.hiddenByFullScreenApp) }
        guard let currentLyric else { return .hide(.noCurrentLine) }
        let text = currentLyric.translatedText ?? currentLyric.text
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .hide(.blankLine) }
        return .show(currentLyric)
    }

    static let bridgedGap: TimeInterval = 1.5

    static func lineBridgingGap(
        in lyrics: [LyricLine],
        at time: TimeInterval,
        maxGap: TimeInterval = bridgedGap
    ) -> LyricLine? {
        var previous: LyricLine?
        var nextStart: TimeInterval?
        for line in lyrics where line.timestamp.isFinite {
            if line.timestamp <= time {
                if previous.map({ line.timestamp >= $0.timestamp }) ?? true { previous = line }
            } else if nextStart.map({ line.timestamp < $0 }) ?? true {
                nextStart = line.timestamp
            }
        }
        guard let previous else { return nil }
        if let end = previous.endTimestamp, time < end { return previous }
        guard let nextStart else { return nil }
        let gap = nextStart - (previous.endTimestamp ?? nextStart)
        return gap <= maxGap ? previous : nil
    }
}

enum MusicPlaybackTickPolicy {
    struct Inputs: Equatable {
        var isPlaying: Bool
        var isDetailPlayerOpen: Bool
        var isLyricsDetailOpen: Bool
        var isDetachedLyricsOpen: Bool
        var isMusicLiveActivityActive: Bool
        var musicLiveActivityEnabled: Bool
        var showLyricsInLiveActivity: Bool
        var lyricsAllowedForActiveApp: Bool
        var hasLyrics: Bool
        var showNextSong: Bool
        var upNextSourceSupported: Bool
    }

    static func interval(for inputs: Inputs) -> TimeInterval? {
        let needsProgressUI = inputs.isDetachedLyricsOpen
        let needsLyricLiveActivity = inputs.isMusicLiveActivityActive
            && inputs.musicLiveActivityEnabled
            && inputs.showLyricsInLiveActivity
            && inputs.lyricsAllowedForActiveApp
            && inputs.hasLyrics
        let needsUpNextLiveActivity = inputs.isMusicLiveActivityActive
            && inputs.musicLiveActivityEnabled
            && inputs.showNextSong
            && inputs.upNextSourceSupported
        guard inputs.isPlaying, needsProgressUI || needsLyricLiveActivity || needsUpNextLiveActivity else { return nil }
        return needsProgressUI ? 0.2 : 0.5
    }

    static func nextLiveActivityEventDelay(
        for inputs: Inputs,
        elapsed: TimeInterval,
        lyricsElapsed: TimeInterval,
        lyrics: [LyricLine],
        duration: TimeInterval
    ) -> TimeInterval? {
        guard inputs.isPlaying, inputs.isMusicLiveActivityActive, inputs.musicLiveActivityEnabled else {
            return nil
        }

        let epsilon = 0.01
        var delays: [TimeInterval] = []

        if inputs.showLyricsInLiveActivity, inputs.lyricsAllowedForActiveApp, inputs.hasLyrics {
            for line in lyrics {
                if line.timestamp > lyricsElapsed + epsilon {
                    delays.append(line.timestamp - lyricsElapsed)
                }
                if let end = line.endTimestamp, end > lyricsElapsed + epsilon {
                    delays.append(end - lyricsElapsed)
                }
            }
        }

        if inputs.showNextSong, inputs.upNextSourceSupported, duration > 0 {
            let upNextStart = max(0, duration - 10)
            if upNextStart > elapsed + epsilon {
                delays.append(upNextStart - elapsed)
            }
        }

        if duration > elapsed + epsilon {
            delays.append(duration - elapsed)
        }

        return delays.min().map { max(0.02, $0) }
    }
}