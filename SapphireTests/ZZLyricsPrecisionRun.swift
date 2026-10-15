//
//  ZZLyricsPrecisionRun.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-10-13

import Foundation
import Testing
@testable import Sapphire

@MainActor
@Suite("Lyrics precision run", .serialized)
struct ZZLyricsPrecisionRun {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["SAPPHIRE_LYRICS_EVAL"] != nil))
    func run() async throws {
        guard #available(macOS 26.0, *),
              let path = ProcessInfo.processInfo.environment["SAPPHIRE_LYRICS_EVAL"] else { return }
        let output = URL(fileURLWithPath: path).deletingLastPathComponent().appendingPathComponent("eval-results", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        try await Task.sleep(for: .seconds(8))

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        for line in try String(contentsOfFile: path, encoding: .utf8).split(separator: "\n") {
            let fields = line.split(separator: " ", maxSplits: 4).map(String.init)
            guard fields.count >= 4, let duration = Double(fields[3]) else { continue }
            let report = await LyricsEvaluationHarness.shared.evaluate(spotifyTrackID: fields[1], key: fields[2], duration: duration)
            try encoder.encode(report).write(to: output.appendingPathComponent("\(fields[0])-\(fields[1]).json"))
            if report.failure?.contains("not interrupting") == true {
                print("PRECISION stopped: something else is playing")
                return
            }
            print("PRECISION \(fields[0]) \(fields.count > 4 ? fields[4] : fields[1]): \(report.refined.map { "median \($0.medianErrorMs)ms bias \($0.medianBiasMs)ms p90 \($0.p90ErrorMs)ms <100ms \(Int($0.within100 * 100))%" } ?? report.failure ?? "no result")")
        }
    }
}