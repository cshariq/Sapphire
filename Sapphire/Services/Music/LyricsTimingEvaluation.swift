//
//  LyricsTimingEvaluation.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-10-13

import AppKit
import Foundation

struct LyricsTimingScore: Codable, Equatable {
    let words: Int
    let timedWords: Int
    let medianErrorMs: Int
    let meanErrorMs: Int
    let p90ErrorMs: Int
    let medianBiasMs: Int
    let within50: Double
    let within100: Double
    let within200: Double

    var wordCoverage: Double { words == 0 ? 0 : Double(timedWords) / Double(words) }

    static func compare(_ overlay: LyricsTimingOverlay, groundTruth: [LyricLine]) -> LyricsTimingScore {
        var errors: [Int] = []
        var signed: [Int] = []
        var words = 0
        var cursor = 0
        for line in groundTruth {
            guard let hash = LyricsTimingOverlay.hash(ofLine: line.text), let truth = wordStarts(of: line) else { continue }
            words += truth.count
            let window = cursor..<min(cursor + 6, overlay.lines.count)
            guard let found = window.first(where: { overlay.lines[$0].hash == hash }),
                  overlay.lines[found].words.count == truth.count else {
                continue
            }
            cursor = found + 1
            for (word, start) in zip(overlay.lines[found].words, truth) {
                let difference = word.start - Int((start * 1000).rounded())
                errors.append(abs(difference))
                signed.append(difference)
            }
        }

        let sorted = errors.sorted()
        func share(_ limit: Int) -> Double {
            sorted.isEmpty ? 0 : Double(sorted.filter { $0 <= limit }.count) / Double(sorted.count)
        }
        return LyricsTimingScore(
            words: words,
            timedWords: sorted.count,
            medianErrorMs: sorted.isEmpty ? 0 : sorted[sorted.count / 2],
            meanErrorMs: sorted.isEmpty ? 0 : sorted.reduce(0, +) / sorted.count,
            p90ErrorMs: sorted.isEmpty ? 0 : sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.9))],
            medianBiasMs: signed.isEmpty ? 0 : signed.sorted()[signed.count / 2],
            within50: share(50),
            within100: share(100),
            within200: share(200)
        )
    }

    static func wordStarts(of line: LyricLine) -> [TimeInterval]? {
        guard line.hasReconstructibleWordTiming else { return nil }
        var pieceStarts: [(offset: Int, start: TimeInterval)] = []
        var offset = 0
        for piece in line.words {
            pieceStarts.append((offset, piece.timestamp))
            offset += piece.text.count
        }

        var starts: [TimeInterval] = []
        var position = 0
        for token in LyricsWordAligner.tokenize(line.text) {
            defer { position += token.count }
            guard !LyricsWordAligner.matchKey(token).isEmpty else { continue }
            let leading = token.prefix { $0.isWhitespace }.count
            let first = position + leading
            guard let piece = pieceStarts.last(where: { $0.offset <= first }) else { return nil }
            starts.append(piece.start)
        }
        return starts.isEmpty ? nil : starts
    }
}

#if DEBUG
@available(macOS 26.0, *)
@MainActor
final class LyricsEvaluationHarness {
    static let shared = LyricsEvaluationHarness()

    struct Report: Codable {
        let spotifyTrackID: String
        let key: String
        var playingTitle: String?
        var locale: String?
        var heardWords: Int?
        var secondsHeard: Double?
        var endReason: String?
        var matchedWords: Int?
        var totalWords: Int?
        var alignedLines: Int?
        var lyricLines: Int?
        var recognized: LyricsTimingScore?
        var refined: LyricsTimingScore?
        var failure: String?
        var heard: [[String]]?
        var onsetStart: Double?
        var onsetStrength: [Float]?
        var audioStart: Double?
        var audioFile: String?
    }

    private let generator = LyricsWordTimingGenerator()
    private var observer: NSObjectProtocol?
    private var timeout: Task<Void, Never>?

    private static let directory: URL = {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("sapphire-lyrics-eval", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    func install() {
        guard observer == nil else { return }
        observer = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.cshariq.sapphire.debug.lyrics"),
            object: nil,
            queue: .main
        ) { notification in
            let command = notification.object as? String
            MainActor.assumeIsolated { LyricsEvaluationHarness.shared.handle(command) }
        }
    }

    private func handle(_ command: String?) {
        let parts = command?.split(separator: " ").map(String.init) ?? []
        if parts.first == "study" {
            if parts.count == 2, let minutes = Double(parts[1]) {
                studyUntil = Date().addingTimeInterval(minutes * 60)
                studiedTitle = nil
                LyricsLog.info("Lyrics study: following playback for \(Int(minutes)) minutes")
            } else {
                studyUntil = nil
                studyGenerator.stop()
                LyricsLog.info("Lyrics study: stopped")
            }
            return
        }
        guard parts.count == 4, parts[0] == "evaluate", let duration = Double(parts[3]) else {
            LyricsLog.error("Lyrics evaluation: unrecognized command '\(command ?? "")'")
            return
        }
        Task { _ = await evaluate(spotifyTrackID: parts[1], key: parts[2], duration: duration) }
    }

    func evaluate(spotifyTrackID: String, key: String, duration: TimeInterval) async -> Report {
        await withCheckedContinuation { continuation in
            pending = continuation
            Task { await start(spotifyTrackID: spotifyTrackID, key: key, duration: duration) }
        }
    }

    private var pending: CheckedContinuation<Report, Never>?

    // MARK: - Study mode: follow normal playback

    struct StudyLine: Codable {
        let text: String
        let start: Double
        let words: [[String]]?
    }

    struct StudyReport: Codable {
        let title: String
        let artist: String
        let referenceSource: String?
        let reference: [StudyLine]?
        let lines: [StudyLine]
        var locale: String?
        var endReason: String?
        var secondsHeard: Double?
        var matchedWords: Int?
        var totalWords: Int?
        var recognized: LyricsTimingScore?
        var refined: LyricsTimingScore?
        var heard: [[String]]?
        var audioStart: Double?
        var audioFile: String?
    }

    private var studyUntil: Date?
    private var studiedTitle: String?
    private let studyGenerator = LyricsWordTimingGenerator()

    var isStudying: Bool { (studyUntil ?? .distantPast) > Date() }

    private static func studyLines(_ lines: [LyricLine], withWords: Bool) -> [StudyLine] {
        lines.map { line in
            StudyLine(
                text: line.text,
                start: line.timestamp,
                words: withWords && line.hasWordTiming ? line.words.map { [$0.text, String(format: "%.3f", $0.timestamp)] } : nil
            )
        }
    }

    func study(title: String, artist: String, duration: TimeInterval?, reference: [LyricLine]?, referenceSource: String?, lines: [LyricLine]?, processID: pid_t) {
        guard isStudying, studiedTitle != title, processID > 0,
              let source = lines ?? reference, !source.isEmpty else { return }
        studiedTitle = title
        let plain = source.map { LyricLine(id: $0.id, text: $0.text, timestamp: $0.timestamp, endTimestamp: $0.endTimestamp) }
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "")
        let slug = title.lowercased().replacingOccurrences(of: #"[^a-z0-9]+"#, with: "-", options: .regularExpression).prefix(40)
        let name = "study-\(stamp)-\(slug)"
        var report = StudyReport(
            title: title,
            artist: artist,
            referenceSource: reference == nil ? nil : referenceSource,
            reference: reference.map { Self.studyLines($0, withWords: true) },
            lines: Self.studyLines(plain, withWords: false)
        )
        LyricsLog.info("Lyrics study: timing '\(title)' (reference: \(report.referenceSource ?? "none"))")
        studyGenerator.start(
            request: .init(
                trackIdentity: name,
                title: title,
                artist: artist,
                album: nil,
                consensus: nil,
                durationMs: duration.map { Int($0 * 1000) },
                lines: plain,
                processID: processID
            ),
            currentSongTime: { MusicManager.shared.elapsedTime() },
            isCurrentTrack: { MusicManager.shared.isPlaying && MusicManager.shared.title == title },
            onGenerated: { _ in },
            evaluate: { [weak self] result in
                report.locale = result.locale
                report.endReason = result.endReason
                report.secondsHeard = result.secondsHeard
                report.matchedWords = result.matchedWords
                report.totalWords = result.totalWords
                if let reference {
                    report.recognized = LyricsTimingScore.compare(result.recognized, groundTruth: reference)
                    report.refined = LyricsTimingScore.compare(result.refined, groundTruth: reference)
                }
                report.heard = result.heard.map { [$0.text, String(format: "%.3f", $0.start), String(format: "%.3f", $0.end)] }
                report.audioStart = result.audioStart
                report.audioFile = result.audioFile?.path
                self?.writeStudy(report, name: name)
            }
        )
    }

    private func writeStudy(_ report: StudyReport, name: String) {
        studiedTitle = nil
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(report) else { return }
        try? data.write(to: Self.directory.appendingPathComponent("\(name).json"), options: .atomic)
        let score = report.refined.map { "median \($0.medianErrorMs) ms, \(Int($0.within100 * 100))% within 100 ms" } ?? "no reference"
        LyricsLog.info("Lyrics study: '\(report.title)' done (\(report.endReason ?? "?"), \(score))")
    }
    private var lastEvaluatedTitle: String?

    private func start(spotifyTrackID: String, key: String, duration: TimeInterval) async {
        var report = Report(spotifyTrackID: spotifyTrackID, key: key)
        generator.stop()
        timeout?.cancel()

        if MusicManager.shared.isPlaying, lastEvaluatedTitle == nil || MusicManager.shared.title != lastEvaluatedTitle {
            report.failure = "something else is playing; not interrupting it"
            return write(report)
        }
        guard case .lyrics(let truth) = await LyricsDatabase.shared.lookup(key: key, duration: nil) else {
            report.failure = "no hand-timed lyrics under \(key)"
            return write(report)
        }
        guard case .success = await MusicManager.shared.spotifyAppleScript.play(uri: "spotify:track:\(spotifyTrackID)") else {
            report.failure = "Spotify did not start the track"
            return write(report)
        }
        try? await Task.sleep(for: .seconds(2.5))
        guard let pid = NSRunningApplication.runningApplications(withBundleIdentifier: "com.spotify.client").first?.processIdentifier else {
            report.failure = "Spotify is not running"
            return write(report)
        }
        report.playingTitle = MusicManager.shared.title
        lastEvaluatedTitle = MusicManager.shared.title

        let plain = truth.map {
            LyricLine(
                id: $0.id, text: $0.text, timestamp: $0.timestamp, endTimestamp: $0.endTimestamp, words: [],
                translatedText: nil, background: [], agent: $0.agent, songPart: $0.songPart
            )
        }
        let deadline = Date().addingTimeInterval(duration + 15)
        timeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration + 45))
            guard !Task.isCancelled, let self else { return }
            self.generator.stop()
            var late = report
            late.failure = "no result from the generator (speech model unavailable for this language, or capture failed)"
            self.write(late)
        }

        generator.start(
            request: .init(
                trackIdentity: "eval:\(spotifyTrackID)",
                title: key,
                artist: "",
                album: nil,
                consensus: nil,
                durationMs: Int(duration * 1000),
                lines: plain,
                processID: pid,
                muteCapture: true
            ),
            currentSongTime: { MusicManager.shared.elapsedTime() },
            isCurrentTrack: { MusicManager.shared.isPlaying && Date() < deadline },
            onGenerated: { _ in },
            evaluate: { [weak self] result in
                guard let self else { return }
                self.timeout?.cancel()
                report.locale = result.locale
                report.heardWords = result.heardWords
                report.secondsHeard = result.secondsHeard
                report.endReason = result.endReason
                report.matchedWords = result.matchedWords
                report.totalWords = result.totalWords
                report.alignedLines = result.alignedLines
                report.lyricLines = result.lyricLines
                report.recognized = LyricsTimingScore.compare(result.recognized, groundTruth: truth)
                report.refined = LyricsTimingScore.compare(result.refined, groundTruth: truth)
                report.heard = result.heard.map { [$0.text, String(format: "%.3f", $0.start), String(format: "%.3f", $0.end)] }
                report.onsetStart = result.onsets?.start
                report.onsetStrength = result.onsets?.strength
                report.audioStart = result.audioStart
                report.audioFile = result.audioFile?.path
                self.write(report)
                Task { await MusicManager.shared.spotifyAppleScript.pause() }
            }
        )
    }

    private func write(_ report: Report) {
        pending?.resume(returning: report)
        pending = nil
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(report) else { return }
        try? data.write(to: Self.directory.appendingPathComponent("\(report.spotifyTrackID).json"), options: .atomic)
        LyricsLog.info("Lyrics evaluation for \(report.spotifyTrackID): \(String(decoding: data, as: UTF8.self))")
    }
}
#endif