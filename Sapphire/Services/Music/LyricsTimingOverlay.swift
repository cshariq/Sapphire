//
//  LyricsTimingOverlay.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-10-12

import CryptoKit
import Foundation

struct LyricsTimingOverlay: Equatable, Sendable {
    struct Word: Equatable, Sendable {
        var start: Int
        var end: Int
        var syllables: [Syllable] = []
    }

    struct Syllable: Equatable, Sendable {
        let letterOffset: Int
        var start: Int
    }

    struct Line: Equatable, Sendable {
        let hash: String
        var words: [Word]
    }

    static let minimumLineCoverage = 0.6
    static let consensusTolerance = 300
    static let consensusTarget = 5
    static let maximumSamples = 100

    var lines: [Line]

    init(lines: [Line]) {
        self.lines = lines
    }

    // MARK: - Fingerprints

    static func countableTokens(of text: String) -> [(token: String, key: String)] {
        LyricsWordAligner.tokenize(text)
            .map { ($0, LyricsWordAligner.matchKey($0)) }
            .filter { !$0.key.isEmpty }
    }

    static func hash(ofLine text: String) -> String? {
        let keys = countableTokens(of: text).map(\.key)
        guard !keys.isEmpty else { return nil }
        let digest = SHA256.hash(data: Data(keys.joined(separator: " ").utf8))
        return digest.prefix(4).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Applying

    func apply(to target: [LyricLine], minimumCoverage: Double = minimumLineCoverage) -> [LyricLine]? {
        var cursor = 0
        var matched = 0
        var lyricLines = 0
        var output: [LyricLine] = []
        output.reserveCapacity(target.count)

        for line in target {
            guard let hash = Self.hash(ofLine: line.text) else {
                output.append(line)
                continue
            }
            lyricLines += 1
            let window = cursor..<min(cursor + 6, lines.count)
            guard let found = window.first(where: { lines[$0].hash == hash }),
                  let words = Self.words(for: line.text, timing: lines[found].words) else {
                output.append(line)
                continue
            }
            cursor = found + 1
            matched += 1
            let firstStart = words.first?.timestamp ?? line.timestamp
            let lastEnd = words.last?.endTimestamp ?? line.endTimestamp ?? line.timestamp
            output.append(line.replacing(
                timestamp: min(line.timestamp, firstStart),
                endTimestamp: .some(max(line.endTimestamp ?? lastEnd, lastEnd)),
                words: words
            ))
        }

        guard lyricLines > 0, matched > 0, Double(matched) / Double(lyricLines) >= minimumCoverage else { return nil }
        return output
    }

    private static func words(for text: String, timing: [Word]) -> [LyricWord]? {
        let tokens = LyricsWordAligner.tokenize(text)
        let countable = tokens.indices.filter { !LyricsWordAligner.matchKey(tokens[$0]).isEmpty }
        guard countable.count == timing.count, !countable.isEmpty else { return nil }

        var pieces: [(text: String, start: Int, end: Int)] = []
        var pendingPrefix = ""
        var wordIndex = 0
        for (index, token) in tokens.enumerated() {
            guard countable.contains(index) else {
                if pieces.isEmpty {
                    pendingPrefix += token
                } else {
                    pieces[pieces.count - 1].text += token
                }
                continue
            }
            let word = timing[wordIndex]
            wordIndex += 1
            let splits = syllableSplits(of: token, word: word)
            for (offset, split) in splits.enumerated() {
                var piece = split.text
                if offset == 0 {
                    piece = pendingPrefix + piece
                    pendingPrefix = ""
                }
                pieces.append((piece, split.start, split.end))
            }
        }

        var previousEnd = 0
        return pieces.map { piece in
            let start = max(piece.start, previousEnd)
            let end = max(piece.end, start)
            previousEnd = end
            return LyricWord(text: piece.text, timestamp: Double(start) / 1000, endTimestamp: Double(end) / 1000)
        }
    }

    private static func syllableSplits(of token: String, word: Word) -> [(text: String, start: Int, end: Int)] {
        guard !word.syllables.isEmpty else { return [(token, word.start, word.end)] }
        var cuts: [(index: String.Index, start: Int)] = []
        var letters = 0
        var pending = word.syllables.sorted { $0.letterOffset < $1.letterOffset }[...]
        for index in token.indices {
            if let next = pending.first, letters == next.letterOffset, letters > 0 {
                cuts.append((index, next.start))
                pending = pending.dropFirst()
            }
            if token[index].unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) }) { letters += 1 }
        }
        guard !cuts.isEmpty else { return [(token, word.start, word.end)] }

        var result: [(String, Int, Int)] = []
        var lower = token.startIndex
        var start = word.start
        for cut in cuts {
            let cutStart = min(max(cut.start, start), word.end)
            result.append((String(token[lower..<cut.index]), start, cutStart))
            lower = cut.index
            start = cutStart
        }
        result.append((String(token[lower...]), start, word.end))
        return result
    }

    // MARK: - Consensus

    func fit(to target: [LyricLine]) -> (found: Double, coverage: Double) {
        let targetHashes = target.compactMap { Self.hash(ofLine: $0.text) }
        guard !lines.isEmpty, !targetHashes.isEmpty else { return (0, 0) }
        let available = Set(targetHashes)
        let found = lines.filter { available.contains($0.hash) }.count
        return (Double(found) / Double(lines.count), Double(min(found, targetHashes.count)) / Double(targetHashes.count))
    }

    func merged(with newer: LyricsTimingOverlay, samples: Int) -> LyricsTimingOverlay {
        let weight = Double(max(samples, 1))
        var result = lines
        var cursor = 0
        var added: [Line] = []
        for line in newer.lines {
            let window = cursor..<min(cursor + 6, result.count)
            guard let found = window.first(where: { result[$0].hash == line.hash }),
                  result[found].words.count == line.words.count else {
                if !result.contains(where: { $0.hash == line.hash }) { added.append(line) }
                continue
            }
            cursor = found + 1
            for index in line.words.indices {
                result[found].words[index] = Self.average(result[found].words[index], line.words[index], weight: weight)
            }
        }
        result += added
        result.sort { ($0.words.first?.start ?? 0) < ($1.words.first?.start ?? 0) }
        return LyricsTimingOverlay(lines: result)
    }

    private static func average(_ old: Word, _ new: Word, weight: Double) -> Word {
        guard abs(old.start - new.start) <= consensusTolerance else { return old }
        func mix(_ a: Int, _ b: Int) -> Int { Int(((Double(a) * weight + Double(b)) / (weight + 1)).rounded()) }
        var word = Word(start: mix(old.start, new.start), end: 0, syllables: old.syllables)
        word.end = max(word.start, abs(old.end - new.end) <= consensusTolerance ? mix(old.end, new.end) : old.end)
        if old.syllables.map(\.letterOffset) == new.syllables.map(\.letterOffset) {
            word.syllables = zip(old.syllables, new.syllables).map { Syllable(letterOffset: $0.letterOffset, start: mix($0.start, $1.start)) }
        } else if old.syllables.isEmpty {
            word.syllables = new.syllables
        }
        return word
    }

    // MARK: - Encoding

    func encoded() -> Data? {
        let payload: [String: Any] = [
            "l": lines.map { line -> [String: Any] in
                var object: [String: Any] = ["h": line.hash, "w": line.words.map { [$0.start, $0.end] }]
                let syllables = line.words.enumerated().flatMap { index, word in
                    word.syllables.map { [index, $0.letterOffset, $0.start] }
                }
                if !syllables.isEmpty { object["y"] = syllables }
                return object
            },
        ]
        return try? JSONSerialization.data(withJSONObject: payload)
    }

    init?(encoded data: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawLines = object["l"] as? [[String: Any]] else {
            return nil
        }
        var lines: [Line] = []
        lines.reserveCapacity(rawLines.count)
        for raw in rawLines {
            guard let hash = raw["h"] as? String, hash.count == 8,
                  let rawWords = raw["w"] as? [[Int]],
                  rawWords.allSatisfy({ $0.count == 2 && $0[0] >= 0 && $0[1] >= $0[0] }) else {
                return nil
            }
            var words = rawWords.map { Word(start: $0[0], end: $0[1]) }
            for entry in (raw["y"] as? [[Int]]) ?? [] where entry.count == 3 && words.indices.contains(entry[0]) && entry[1] > 0 {
                words[entry[0]].syllables.append(Syllable(letterOffset: entry[1], start: entry[2]))
            }
            lines.append(Line(hash: hash, words: words))
        }
        guard !lines.isEmpty else { return nil }
        self.lines = lines
    }
}