//
//  LyricsTimingRefiner.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-10-12

import Accelerate
import AVFoundation
import Foundation

struct LyricsOnsetEnvelope: Sendable {
    static let hop: TimeInterval = 0.01

    let start: TimeInterval
    let strength: [Float]
    let threshold: Float

    init(start: TimeInterval, strength: [Float]) {
        self.start = start
        self.strength = strength
        let sorted = strength.sorted()
        threshold = sorted.isEmpty ? .infinity : max(sorted[Int(Double(sorted.count - 1) * 0.8)], 0.5)
    }

    func onset(near time: TimeInterval, within window: TimeInterval, minimum: Float? = nil) -> TimeInterval? {
        let floor = minimum ?? threshold
        let lower = max(Int(((time - window - start) / Self.hop).rounded(.down)), 1)
        let upper = min(Int(((time + window - start) / Self.hop).rounded(.up)), strength.count - 2)
        guard lower <= upper else { return nil }
        var best: (score: Float, index: Int)?
        for index in lower...upper {
            let value = strength[index]
            guard value >= floor, value >= strength[index - 1], value >= strength[index + 1] else { continue }
            let distance = abs(start + Double(index) * Self.hop - time)
            let score = value * Float(1 - distance / (window * 1.5))
            if score > (best?.score ?? 0) { best = (score, index) }
        }
        return best.map { start + Double($0.index) * Self.hop }
    }
}

final class LyricsOnsetDetector {
    private let sampleRate: Double
    private let hopSamples: Int
    private var setup: vDSP_biquad_Setup?
    private var delay = [Float](repeating: 0, count: 4)
    private var mono: [Float] = []
    private var filtered: [Float] = []
    private var energySum: Float = 0
    private var energyCount = 0
    private var recent: [Float] = []
    private(set) var strength: [Float] = []

    init(sampleRate: Double) {
        self.sampleRate = sampleRate
        hopSamples = max(Int(sampleRate * LyricsOnsetEnvelope.hop), 1)
        let w0 = 2 * Double.pi * 1000 / sampleRate
        let alpha = sin(w0) / (2 * 0.6)
        let a0 = 1 + alpha
        let coefficients = [alpha / a0, 0, -alpha / a0, -2 * cos(w0) / a0, (1 - alpha) / a0]
        setup = vDSP_biquad_CreateSetup(coefficients, 1)
        strength.reserveCapacity(36_000)
    }

    deinit {
        if let setup { vDSP_biquad_DestroySetup(setup) }
    }

    func process(_ buffer: AVAudioPCMBuffer) {
        guard let channels = buffer.floatChannelData, let setup else { return }
        let count = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        guard count > 0, channelCount > 0 else { return }
        if mono.count < count {
            mono = [Float](repeating: 0, count: count)
            filtered = [Float](repeating: 0, count: count)
        }

        let interleaved = buffer.format.isInterleaved
        mono.withUnsafeMutableBufferPointer { output in
            let sum = output.baseAddress!
            vDSP_vclr(sum, 1, vDSP_Length(count))
            for channel in 0..<channelCount {
                let source = interleaved ? channels[0] + channel : channels[channel]
                vDSP_vadd(source, interleaved ? vDSP_Stride(channelCount) : 1, sum, 1, sum, 1, vDSP_Length(count))
            }
        }
        vDSP_biquad(setup, &delay, mono, 1, &filtered, 1, vDSP_Length(count))

        var offset = 0
        while offset < count {
            let take = min(hopSamples - energyCount, count - offset)
            var sum: Float = 0
            filtered.withUnsafeBufferPointer { pointer in
                vDSP_svesq(pointer.baseAddress! + offset, 1, &sum, vDSP_Length(take))
            }
            energySum += sum
            energyCount += take
            offset += take
            guard energyCount == hopSamples else { continue }

            let level = 10 * log10(energySum / Float(hopSamples) + 1e-10)
            let baseline = recent.isEmpty ? level : recent.reduce(0, +) / Float(recent.count)
            strength.append(max(0, level - baseline))
            recent.append(level)
            if recent.count > 3 { recent.removeFirst() }
            energySum = 0
            energyCount = 0
        }
    }
}

enum LyricsTimingRefiner {
    static func pieceTimes(_ pieces: [String], start: TimeInterval, duration: TimeInterval) -> [(start: TimeInterval, end: TimeInterval)] {
        let weights = pieces.map { Double(syllableEstimate($0)) }
        let total = max(weights.reduce(0, +), 1)
        var cursor = start
        return weights.map { weight in
            let length = duration * weight / total
            defer { cursor += length }
            return (cursor, cursor + length)
        }
    }

    // MARK: - Word timing from line timing

    static let estimatedSyllableDuration: TimeInterval = 0.3
    static let estimatedLineLead: TimeInterval = 0.3
    static let estimatedFinalHold = 1.5

    static func estimatedWords(for lines: [LyricLine]) -> [LyricLine] {
        lines.enumerated().map { index, line in
            guard line.words.isEmpty else { return line }
            let tokens = LyricsWordAligner.tokenize(line.text)
            guard !tokens.isEmpty, !LyricsTimingOverlay.countableTokens(of: line.text).isEmpty else { return line }
            let nextStart = lines.dropFirst(index + 1).first { $0.timestamp > line.timestamp }?.timestamp
            let windowEnd = line.endTimestamp ?? nextStart ?? line.timestamp + LyricsWordAligner.fallbackLineDuration
            let lastCountable = tokens.lastIndex { !LyricsWordAligner.matchKey($0).isEmpty }
            let weights = tokens.enumerated().map { position, token -> Double in
                guard !LyricsWordAligner.matchKey(token).isEmpty else { return 0 }
                let syllables = Double(syllableEstimate(token))
                return position == lastCountable ? syllables * estimatedFinalHold : syllables
            }
            let syllables = tokens.reduce(0) { $0 + (LyricsWordAligner.matchKey($1).isEmpty ? 0 : syllableEstimate($1)) }
            let end = max(line.timestamp + 0.2, min(windowEnd, line.timestamp + Double(syllables) * estimatedSyllableDuration + estimatedLineLead))
            let total = max(weights.reduce(0, +), 1)
            var cursor = line.timestamp
            let words = zip(tokens, weights).map { token, weight -> LyricWord in
                let start = cursor
                cursor += (end - line.timestamp) * weight / total
                return LyricWord(text: token, timestamp: start, endTimestamp: cursor)
            }
            return line.replacing(words: words)
        }
    }

    static func anchored(
        _ alignment: LyricsWordAligner.Alignment,
        to source: [LyricLine],
        bias: TimeInterval,
        measureOffset: Bool = false
    ) -> [LyricLine] {
        var offsets: [TimeInterval] = []
        for line in alignment.lines where line.hasWordTiming {
            let firstCountable = line.words.firstIndex { !LyricsWordAligner.matchKey($0.text).isEmpty }
            guard let firstCountable, alignment.matchedTokens[line.id]?.contains(firstCountable) == true else { continue }
            offsets.append(line.words[firstCountable].timestamp - bias - line.timestamp)
        }
        let sorted = offsets.sorted()
        let songOffset = measureOffset && sorted.count >= 5 && abs(sorted[sorted.count / 2]) < 1 ? sorted[sorted.count / 2] : 0

        return alignment.lines.enumerated().map { index, line in
            guard line.hasWordTiming, let first = line.words.first else { return line }
            let anchor = line.timestamp + songOffset
            let nextStart = source.dropFirst(index + 1).first { $0.timestamp > line.timestamp }?.timestamp
            let limit = (line.endTimestamp ?? nextStart).map { $0 + songOffset } ?? .infinity
            let span = max((line.words.last?.endTimestamp ?? line.words.last!.timestamp) - first.timestamp, 0.001)
            let scale = min(1, (limit - anchor) / span)
            let words = line.words.map { word in
                LyricWord(
                    text: word.text,
                    timestamp: anchor + (word.timestamp - first.timestamp) * scale,
                    endTimestamp: word.endTimestamp.map { anchor + ($0 - first.timestamp) * scale }
                )
            }
            return line.replacing(
                timestamp: line.timestamp + songOffset,
                endTimestamp: .some(line.endTimestamp.map { $0 + songOffset }),
                words: words
            )
        }
    }

    static func syllableEstimate(_ word: String) -> Int {
        var count = 0
        var previousWasVowel = false
        for character in word.lowercased() {
            guard character.isLetter || character.isNumber else { previousWasVowel = false; continue }
            if !character.isASCII, !"àáâãäåèéêëìíîïòóôõöùúûüýÿæœøаеёиоуыэюя".contains(character) {
                count += 1
                previousWasVowel = false
                continue
            }
            let isVowel = "aeiouyàáâãäåèéêëìíîïòóôõöùúûüýÿæœøаеёиоуыэюя".contains(character)
            if isVowel, !previousWasVowel { count += 1 }
            previousWasVowel = isVowel
        }
        if word.lowercased().hasSuffix("e"), count > 1, !word.lowercased().hasSuffix("le") { count -= 1 }
        return max(count, 1)
    }

    static let snapWindow: TimeInterval = 0.12
    static let syllableMinimumDuration: TimeInterval = 0.45
    static let minimumPieceDuration: TimeInterval = 0.06

    static func overlay(
        from lines: [LyricLine],
        matched: [UUID: Set<Int>] = [:],
        onsets: LyricsOnsetEnvelope?,
        locale: Locale,
        startBias: TimeInterval = 0
    ) -> LyricsTimingOverlay {
        var overlayLines: [LyricsTimingOverlay.Line] = []
        for line in lines where line.hasWordTiming {
            guard let hash = LyricsTimingOverlay.hash(ofLine: line.text) else { continue }
            let countable = line.words.indices.filter { !LyricsWordAligner.matchKey(line.words[$0].text).isEmpty }
            let timed = countable.map { line.words[$0] }
            guard timed.count == LyricsTimingOverlay.countableTokens(of: line.text).count else { continue }
            let heard = matched[line.id] ?? []
            let fixed = countable.map { heard.contains($0) }

            var starts = timed.map { $0.timestamp - startBias }
            var ends = timed.map { ($0.endTimestamp ?? $0.timestamp) - startBias }
            if let onsets { snap(starts: &starts, ends: &ends, to: onsets, fixed: fixed) }

            let words = timed.indices.map { index -> LyricsTimingOverlay.Word in
                let start = starts[index]
                let end = max(ends[index], start)
                return LyricsTimingOverlay.Word(
                    start: milliseconds(start),
                    end: milliseconds(end),
                    syllables: syllables(of: timed[index].text, start: start, end: end, onsets: onsets, locale: locale)
                )
            }
            overlayLines.append(LyricsTimingOverlay.Line(hash: hash, words: words))
        }
        return LyricsTimingOverlay(lines: overlayLines)
    }

    static func snap(
        starts: inout [TimeInterval],
        ends: inout [TimeInterval],
        to onsets: LyricsOnsetEnvelope,
        fixed: [Bool] = []
    ) {
        let original = starts
        let originalEnds = ends
        for index in starts.indices {
            let floor = index > 0 ? starts[index - 1] + minimumPieceDuration : -Double.infinity
            if fixed.indices.contains(index), fixed[index] {
                starts[index] = max(starts[index], floor)
            } else if let onset = onsets.onset(near: starts[index], within: snapWindow), onset >= floor {
                starts[index] = onset
            } else {
                starts[index] = max(starts[index], floor)
            }
        }
        for index in ends.indices {
            let next = index + 1 < starts.count ? starts[index + 1] : nil
            let wasContiguous = next != nil && originalEnds[index] >= original[index + 1] - 0.05
            var end = originalEnds[index]
            if let next {
                end = wasContiguous ? next : min(end, next)
            }
            ends[index] = max(end, starts[index] + minimumPieceDuration)
        }
    }

    static func syllables(
        of token: String,
        start: TimeInterval,
        end: TimeInterval,
        onsets: LyricsOnsetEnvelope?,
        locale: Locale
    ) -> [LyricsTimingOverlay.Syllable] {
        let duration = end - start
        guard duration >= syllableMinimumDuration else { return [] }
        let letters = String(token.filter { $0.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) } })
        guard letters.count >= 4 else { return [] }
        let offsets = hyphenationOffsets(letters, locale: locale)
        guard !offsets.isEmpty else { return [] }

        var result: [LyricsTimingOverlay.Syllable] = []
        var previous = start
        for offset in offsets {
            let proportional = start + duration * Double(offset) / Double(letters.count)
            var time = proportional
            if let onsets,
               let onset = onsets.onset(
                   near: proportional,
                   within: min(0.1, duration / Double(offsets.count + 1) / 2),
                   minimum: onsets.threshold * 0.7
               ) {
                time = onset
            }
            guard time >= previous + minimumPieceDuration, time <= end - minimumPieceDuration else { continue }
            result.append(LyricsTimingOverlay.Syllable(letterOffset: offset, start: milliseconds(time)))
            previous = time
        }
        return result
    }

    static func hyphenationOffsets(_ word: String, locale: Locale) -> [Int] {
        let cfLocale = locale as CFLocale
        guard CFStringIsHyphenationAvailableForLocale(cfLocale) else { return [] }
        let string = word as CFString
        let length = CFStringGetLength(string)
        var utf16Offsets: [Int] = []
        var index = length
        while index > 1 {
            let location = CFStringGetHyphenationLocationBeforeIndex(string, index, CFRange(location: 0, length: length), 0, cfLocale, nil)
            guard location != kCFNotFound, location > 0, location < index else { break }
            utf16Offsets.append(location)
            index = location
        }
        return utf16Offsets.reversed().compactMap { offset in
            guard let position = String.Index(utf16Offset: offset, in: word).samePosition(in: word) else { return nil }
            return word.distance(from: word.startIndex, to: position)
        }
    }

    private static func milliseconds(_ seconds: TimeInterval) -> Int {
        max(0, Int((seconds * 1000).rounded()))
    }
}