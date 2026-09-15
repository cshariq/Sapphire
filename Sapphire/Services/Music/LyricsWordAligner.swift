//
//  LyricsWordAligner.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-14

import Foundation

struct RecognizedWord: Equatable, Sendable {
    let text: String
    let start: TimeInterval
    let end: TimeInterval
}

enum LyricsWordAligner {
    struct Alignment: Equatable {
        let lines: [LyricLine]
        let matchedWords: Int
        let totalWords: Int
        let alignedLines: Int
        let lyricLines: Int

        var confidence: Double {
            totalWords == 0 ? 0 : Double(matchedWords) / Double(totalWords)
        }

        var lineCoverage: Double {
            lyricLines == 0 ? 0 : Double(alignedLines) / Double(lyricLines)
        }
    }

    static let windowPadding: TimeInterval = 0.6
    static let minimumSimilarity = 0.6
    static let fallbackLineDuration: TimeInterval = 5

    static func align(lines: [LyricLine], recognized: [RecognizedWord]) -> Alignment {
        let heard = recognized
            .filter { !matchKey($0.text).isEmpty }
            .sorted { $0.start < $1.start }
        var cursor = 0
        var matchedWords = 0
        var totalWords = 0
        var alignedLines = 0
        var lyricLines = 0
        var output: [LyricLine] = []
        output.reserveCapacity(lines.count)

        for (index, line) in lines.enumerated() {
            let tokens = tokenize(line.text)
            let keys = tokens.map(matchKey)
            let countable = keys.filter { !$0.isEmpty }.count
            guard countable > 0 else {
                output.append(line)
                continue
            }
            lyricLines += 1
            totalWords += countable

            let lineStart = line.timestamp
            let nextStart = lines.dropFirst(index + 1).first { $0.timestamp > lineStart }?.timestamp
            let lineEnd = max(lineStart, line.endTimestamp ?? nextStart ?? lineStart + fallbackLineDuration)
            let windowStart = lineStart - windowPadding
            let windowEnd = lineEnd + windowPadding

            while cursor < heard.count, heard[cursor].start < windowStart { cursor += 1 }
            var candidateEnd = cursor
            while candidateEnd < heard.count, heard[candidateEnd].start <= windowEnd { candidateEnd += 1 }
            let candidates = Array(heard[cursor..<candidateEnd])

            let pairs = bestPairs(keys: keys, candidates: candidates)
            guard !pairs.isEmpty else {
                output.append(line)
                continue
            }

            alignedLines += 1
            matchedWords += pairs.count
            cursor += (pairs.map(\.candidate).max() ?? -1) + 1

            var matches: [Int: RecognizedWord] = [:]
            for pair in pairs { matches[pair.word] = candidates[pair.candidate] }
            let words = assignTimes(tokens: tokens, keys: keys, matches: matches, lineStart: lineStart, lineEnd: lineEnd)
            output.append(LyricLine(
                id: line.id,
                text: line.text,
                timestamp: line.timestamp,
                endTimestamp: line.endTimestamp,
                words: words,
                translatedText: line.translatedText,
                background: line.background,
                agent: line.agent,
                songPart: line.songPart
            ))
        }

        return Alignment(
            lines: output,
            matchedWords: matchedWords,
            totalWords: totalWords,
            alignedLines: alignedLines,
            lyricLines: lyricLines
        )
    }

    // MARK: - Tokens

    static func tokenize(_ text: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        for character in text {
            if character.isWhitespace {
                current.append(character)
                continue
            }
            let hasContent = current.contains { !$0.isWhitespace }
            let endsWithSpace = current.last?.isWhitespace == true
            let lastIsCJK = current.last.map(isCJK) ?? false
            if hasContent, endsWithSpace || lastIsCJK || isCJK(character) {
                tokens.append(current)
                current = ""
            }
            current.append(character)
        }
        if !current.isEmpty {
            if current.contains(where: { !$0.isWhitespace }) || tokens.isEmpty {
                tokens.append(current)
            } else {
                tokens[tokens.count - 1] += current
            }
        }
        return tokens
    }

    static func matchKey(_ text: String) -> String {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
        return String(String.UnicodeScalarView(folded.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }))
    }

    private static func isCJK(_ character: Character) -> Bool {
        character.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x4E00...0x9FFF, 0x3400...0x4DBF, 0xF900...0xFAFF, 0x3040...0x30FF, 0xAC00...0xD7AF:
                return true
            default:
                return false
            }
        }
    }

    // MARK: - Matching

    private struct Pair {
        let word: Int
        let candidate: Int
    }

    private static func bestPairs(keys: [String], candidates: [RecognizedWord]) -> [Pair] {
        let wordCount = keys.count
        let candidateCount = candidates.count
        guard wordCount > 0, candidateCount > 0 else { return [] }
        let candidateKeys = candidates.map { matchKey($0.text) }

        var similarity = Array(repeating: Array(repeating: 0.0, count: candidateCount), count: wordCount)
        for word in 0..<wordCount where !keys[word].isEmpty {
            for candidate in 0..<candidateCount {
                let score = similarityScore(keys[word], candidateKeys[candidate])
                similarity[word][candidate] = score >= minimumSimilarity ? score : 0
            }
        }

        var table = Array(repeating: Array(repeating: 0.0, count: candidateCount + 1), count: wordCount + 1)
        for word in 1...wordCount {
            for candidate in 1...candidateCount {
                let skipWord = table[word - 1][candidate]
                let skipCandidate = table[word][candidate - 1]
                let score = similarity[word - 1][candidate - 1]
                let take = score > 0 ? table[word - 1][candidate - 1] + score : 0
                table[word][candidate] = max(skipWord, skipCandidate, take)
            }
        }

        var pairs: [Pair] = []
        var word = wordCount
        var candidate = candidateCount
        while word > 0, candidate > 0 {
            let score = similarity[word - 1][candidate - 1]
            if score > 0, table[word][candidate] == table[word - 1][candidate - 1] + score {
                pairs.append(Pair(word: word - 1, candidate: candidate - 1))
                word -= 1
                candidate -= 1
            } else if table[word - 1][candidate] >= table[word][candidate - 1] {
                word -= 1
            } else {
                candidate -= 1
            }
        }
        return pairs.reversed()
    }

    static func similarityScore(_ lhs: String, _ rhs: String) -> Double {
        guard !lhs.isEmpty, !rhs.isEmpty else { return 0 }
        if lhs == rhs { return 1 }
        let a = Array(lhs)
        let b = Array(rhs)
        var previous = Array(0...b.count)
        var current = Array(repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            current[0] = i
            for j in 1...b.count {
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            swap(&previous, &current)
        }
        return 1 - Double(previous[b.count]) / Double(max(a.count, b.count))
    }

    // MARK: - Timing

    private static func assignTimes(
        tokens: [String],
        keys: [String],
        matches: [Int: RecognizedWord],
        lineStart: TimeInterval,
        lineEnd: TimeInterval
    ) -> [LyricWord] {
        var starts = Array(repeating: 0.0, count: tokens.count)
        var ends = Array(repeating: 0.0, count: tokens.count)
        var index = 0
        var leftTime = lineStart

        while index < tokens.count {
            if let match = matches[index] {
                let start = min(max(match.start, leftTime), lineEnd)
                starts[index] = start
                ends[index] = min(max(match.end, start), lineEnd)
                leftTime = ends[index]
                index += 1
                continue
            }

            var runEnd = index
            while runEnd < tokens.count, matches[runEnd] == nil { runEnd += 1 }
            let rightTime = max(leftTime, runEnd < tokens.count ? min(matches[runEnd]!.start, lineEnd) : lineEnd)
            let weights = (index..<runEnd).map { Double(max(keys[$0].count, 1)) }
            let totalWeight = weights.reduce(0, +)
            var cursor = leftTime
            for (offset, weight) in weights.enumerated() {
                let duration = (rightTime - leftTime) * weight / totalWeight
                starts[index + offset] = cursor
                cursor += duration
                ends[index + offset] = cursor
            }
            leftTime = rightTime
            index = runEnd
        }

        return tokens.indices.map { position in
            LyricWord(text: tokens[position], timestamp: starts[position], endTimestamp: ends[position])
        }
    }
}