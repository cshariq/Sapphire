//
//  ZZLyricsPrecisionReplay.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-10-13

import Foundation
import Testing
@testable import Sapphire

@MainActor
@Suite("Lyrics precision replay")
struct ZZLyricsPrecisionReplay {
    private struct Recorded: Decodable {
        let key: String
        let locale: String?
        let heard: [[String]]?
        let onsetStart: Double?
        let onsetStrength: [Float]?
    }

    static func syllableWeighted(_ words: [RecognizedWord]) -> [RecognizedWord] {
        var result: [RecognizedWord] = []
        var index = 0
        while index < words.count {
            var end = index + 1
            let step = words[index].end - words[index].start
            while end < words.count,
                  abs(words[end].start - words[end - 1].end) < 0.002,
                  abs((words[end].end - words[end].start) - step) < 0.002 { end += 1 }
            let run = Array(words[index..<end])
            let times = LyricsTimingRefiner.pieceTimes(run.map(\.text), start: run[0].start, duration: run.last!.end - run[0].start)
            result += zip(run, times).map { RecognizedWord(text: $0.text, start: $1.start, end: $1.end) }
            index = end
        }
        return result
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["SAPPHIRE_LYRICS_REPLAY"] != nil))
    func replay() async throws {
        guard let path = ProcessInfo.processInfo.environment["SAPPHIRE_LYRICS_REPLAY"] else { return }
        let folder = URL(fileURLWithPath: path)
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        let strategies: [(String, (LyricsWordAligner.Alignment, LyricsOnsetEnvelope?, Locale) -> LyricsTimingOverlay)] = [
            ("recognized", { a, _, l in LyricsTimingRefiner.overlay(from: a.lines, onsets: nil, locale: l) }),
            ("bias 40ms", { a, _, l in LyricsTimingRefiner.overlay(from: a.lines, onsets: nil, locale: l, startBias: 0.04) }),
            ("bias 80ms", { a, _, l in LyricsTimingRefiner.overlay(from: a.lines, onsets: nil, locale: l, startBias: 0.08) }),
            ("snap all", { a, o, l in LyricsTimingRefiner.overlay(from: a.lines, onsets: o, locale: l) }),
            ("bias+snap gaps", { a, o, l in LyricsTimingRefiner.overlay(from: a.lines, matched: a.matchedTokens, onsets: o, locale: l, startBias: 0.04) }),
        ]
        var lineStrategies: [(String, ([LyricLine], LyricsWordAligner.Alignment, Locale) -> LyricsTimingOverlay)] = []
        lineStrategies.append(("line timing only (estimate)", { plain, _, l in
            LyricsTimingRefiner.overlay(from: LyricsTimingRefiner.estimatedWords(for: plain), onsets: nil, locale: l) }))
        lineStrategies.append(("anchored, offset measured", { plain, a, l in
            LyricsTimingRefiner.overlay(from: LyricsTimingRefiner.anchored(a, to: plain, bias: 0.05, measureOffset: true), onsets: nil, locale: l) }))
        lineStrategies.append(("anchored to line start", { plain, a, l in
            LyricsTimingRefiner.overlay(from: LyricsTimingRefiner.anchored(a, to: plain, bias: 0.05), onsets: nil, locale: l) }))

        var report: [String] = []
        func print(_ line: String) { report.append(line) }
        defer { try? report.joined(separator: "\n").write(to: folder.appendingPathComponent("replay.txt"), atomically: true, encoding: .utf8) }
        var pooled: [String: [Int]] = [:]
        for file in files {
            let recorded = try JSONDecoder().decode(Recorded.self, from: Data(contentsOf: file))
            guard let heardRows = recorded.heard,
                  case .lyrics(let truth) = await LyricsDatabase.shared.lookup(key: recorded.key, duration: nil) else {
                print("REPLAY \(file.lastPathComponent): skipped (no recorded words or hand timing)")
                continue
            }
            let heard = heardRows.compactMap { row -> RecognizedWord? in
                guard row.count == 3, let start = Double(row[1]), let end = Double(row[2]) else { return nil }
                return RecognizedWord(text: row[0], start: start, end: end)
            }
            let plain = truth.map {
                LyricLine(id: $0.id, text: $0.text, timestamp: $0.timestamp, endTimestamp: $0.endTimestamp, words: [],
                          translatedText: nil, background: [], agent: nil, songPart: nil)
            }
            let onsets = recorded.onsetStrength.map { LyricsOnsetEnvelope(start: recorded.onsetStart ?? 0, strength: $0) }
            let locale = Locale(identifier: recorded.locale ?? "en_US")
            let evenAlignment = LyricsWordAligner.align(lines: plain, recognized: heard)
            let alignment = LyricsWordAligner.align(lines: plain, recognized: Self.syllableWeighted(heard))
            let evenScore = LyricsTimingScore.compare(LyricsTimingRefiner.overlay(from: evenAlignment.lines, onsets: nil, locale: locale), groundTruth: truth)
            print("  even split (as recorded): med \(evenScore.medianErrorMs) bias \(evenScore.medianBiasMs) p90 \(evenScore.p90ErrorMs) <100 \(Int(evenScore.within100 * 100))%")

            var line = "REPLAY \(file.deletingPathExtension().lastPathComponent) matched \(alignment.matchedWords)/\(alignment.totalWords):"
            for (name, strategy) in strategies {
                let score = LyricsTimingScore.compare(strategy(alignment, onsets, locale), groundTruth: truth)
                line += " | \(name): med \(score.medianErrorMs) bias \(score.medianBiasMs) p90 \(score.p90ErrorMs) <100 \(Int(score.within100 * 100))%"
                pooled[name, default: []].append(contentsOf: [score.medianErrorMs, Int(score.within100 * 1000), score.timedWords])
            }
            for (name, strategy) in lineStrategies {
                let score = LyricsTimingScore.compare(strategy(plain, alignment, locale), groundTruth: truth)
                line += " | \(name): med \(score.medianErrorMs) bias \(score.medianBiasMs) p90 \(score.p90ErrorMs) <100 \(Int(score.within100 * 100))% <200 \(Int(score.within200 * 100))%"
            }
            print(line)

            var heardErrors: [Int] = []
            var interpolatedErrors: [Int] = []
            for truthLine in truth {
                guard let starts = LyricsTimingScore.wordStarts(of: truthLine),
                      let aligned = alignment.lines.first(where: { $0.id == truthLine.id }), aligned.hasWordTiming else { continue }
                let matched = alignment.matchedTokens[truthLine.id] ?? []
                let countable = aligned.words.indices.filter { !LyricsWordAligner.matchKey(aligned.words[$0].text).isEmpty }
                guard countable.count == starts.count else { continue }
                for (position, tokenIndex) in countable.enumerated() {
                    let error = Int(abs(aligned.words[tokenIndex].timestamp - starts[position]) * 1000)
                    if matched.contains(tokenIndex) { heardErrors.append(error) } else { interpolatedErrors.append(error) }
                }
            }
            func summary(_ values: [Int]) -> String {
                guard !values.isEmpty else { return "none" }
                let sorted = values.sorted()
                return "\(values.count) words, median \(sorted[sorted.count / 2])ms, p90 \(sorted[Int(Double(sorted.count - 1) * 0.9)])ms, <100ms \(sorted.filter { $0 <= 100 }.count * 100 / sorted.count)%"
            }
            print("  heard: \(summary(heardErrors))")
            print("  interpolated: \(summary(interpolatedErrors))")
        }
        for (name, _) in strategies {
            let values = pooled[name] ?? []
            let songs = values.count / 3
            guard songs > 0 else { continue }
            let medians = stride(from: 0, to: values.count, by: 3).map { values[$0] }
            let within = stride(from: 1, to: values.count, by: 3).map { values[$0] }
            print("REPLAY TOTAL \(name): mean of medians \(medians.reduce(0, +) / songs)ms, mean <100ms \(within.reduce(0, +) / songs / 10)% over \(songs) songs")
        }
    }
}