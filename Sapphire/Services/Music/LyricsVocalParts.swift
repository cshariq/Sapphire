//
//  LyricsVocalParts.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-10-13

import Foundation

enum LyricsVocalParts {
    private static let parenthetical = try! NSRegularExpression(pattern: #"\s*[(（]([^()（）]+)[)）]"#)
    static let untimed: TimeInterval = -1

    static func split(_ lines: [LyricLine]) -> [LyricLine] {
        lines.map { line in
            guard line.words.isEmpty, line.background.isEmpty else { return line }
            let range = NSRange(line.text.startIndex..., in: line.text)
            let matches = parenthetical.matches(in: line.text, range: range)
            guard !matches.isEmpty else { return line }

            let backing = matches.compactMap { Range($0.range(at: 1), in: line.text).map { String(line.text[$0]) } }
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            let lead = parenthetical.stringByReplacingMatches(in: line.text, range: range, withTemplate: "")
                .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
            guard !backing.isEmpty, !LyricsTimingOverlay.countableTokens(of: lead).isEmpty else { return line }

            let tokens = LyricsWordAligner.tokenize(backing.joined(separator: " "))
            return line.replacing(
                words: [],
                background: tokens.map { LyricWord(text: $0, timestamp: untimed, endTimestamp: nil) },
                text: lead
            )
        }
    }

    static func timedBackground(_ lines: [LyricLine]) -> [LyricLine] {
        lines.enumerated().map { index, line in
            guard let first = line.background.first, first.timestamp == untimed else { return line }
            let leadStart = line.words.first?.timestamp ?? line.timestamp
            let leadEnd = line.words.last.map { $0.endTimestamp ?? $0.timestamp } ?? line.timestamp + 1
            let nextStart = lines.dropFirst(index + 1).first { $0.timestamp > line.timestamp }?.timestamp
                ?? leadEnd + LyricsWordAligner.fallbackLineDuration
            let syllables = line.background.reduce(0) { $0 + (LyricsWordAligner.matchKey($1.text).isEmpty ? 0 : LyricsTimingRefiner.syllableEstimate($1.text)) }
            let length = Double(max(syllables, 1)) * LyricsTimingRefiner.estimatedSyllableDuration
            let start = nextStart - leadEnd >= min(length, 1.2) ? leadEnd : leadStart + (leadEnd - leadStart) * 0.5
            let end = min(start + length, max(nextStart - 0.05, start + 0.2))

            let weights = line.background.map { LyricsWordAligner.matchKey($0.text).isEmpty ? 0 : Double(LyricsTimingRefiner.syllableEstimate($0.text)) }
            let total = max(weights.reduce(0, +), 1)
            var cursor = start
            let words = zip(line.background, weights).map { word, weight -> LyricWord in
                let wordStart = cursor
                cursor += (end - start) * weight / total
                return LyricWord(id: word.id, text: word.text, timestamp: wordStart, endTimestamp: cursor)
            }
            return line.replacing(background: words)
        }
    }

    static func backgroundLine(of line: LyricLine) -> LyricLine? {
        guard let first = line.background.first, first.timestamp >= 0 else { return nil }
        return LyricLine(
            id: line.id,
            text: line.background.map(\.text).joined(),
            timestamp: first.timestamp,
            endTimestamp: line.background.last?.endTimestamp,
            words: line.background
        )
    }
}