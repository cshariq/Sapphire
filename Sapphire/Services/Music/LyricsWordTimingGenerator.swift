//
//  LyricsWordTimingGenerator.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-15

import Accelerate
import AVFoundation
import FirebaseFirestore
import Foundation
import NaturalLanguage
import Speech

@available(macOS 26.0, *)
@MainActor
final class LyricsWordTimingGenerator {
    struct Request: Sendable {
        let trackIdentity: String
        let title: String
        let artist: String
        let album: String?
        let consensus: (overlay: LyricsTimingOverlay, samples: Int, confidence: Double)?
        let durationMs: Int?
        let lines: [LyricLine]
        let processID: pid_t
        var muteCapture = false
    }

    static let shared = LyricsWordTimingGenerator()
    static let minimumConfidence = 0.7
    static let minimumLineCoverage = 0.85
    nonisolated static let engine = "speechtranscriber-v2"

    private var task: Task<Void, Never>?
    private var trackIdentity: String?
    private var activeTap: LyricsAudioTap?
    private var activeContinuation: AsyncStream<AnalyzerInput>.Continuation?

    struct Evaluation {
        let locale: String
        let heardWords: Int
        let secondsHeard: TimeInterval
        let endReason: String
        let matchedWords: Int
        let totalWords: Int
        let alignedLines: Int
        let lyricLines: Int
        let recognized: LyricsTimingOverlay
        let refined: LyricsTimingOverlay
        let heard: [RecognizedWord]
        let onsets: LyricsOnsetEnvelope?
        let audioStart: TimeInterval
        let audioFile: URL?
    }

    init() {}

    func start(
        request: Request,
        currentSongTime: @escaping @MainActor () -> TimeInterval?,
        isCurrentTrack: @escaping @MainActor () -> Bool,
        onGenerated: @escaping @MainActor ([LyricLine]) -> Void,
        evaluate: (@MainActor (Evaluation) -> Void)? = nil
    ) {
        guard trackIdentity != request.trackIdentity else { return }
        stop()
        trackIdentity = request.trackIdentity
        task = Task { [weak self] in
            await self?.run(
                request,
                currentSongTime: currentSongTime,
                isCurrentTrack: isCurrentTrack,
                onGenerated: onGenerated,
                evaluate: evaluate
            )
        }
    }

    func stop() {
        task?.cancel()
        activeTap?.stop()
        activeContinuation?.finish()
        activeTap = nil
        activeContinuation = nil
        task = nil
        trackIdentity = nil
    }

    private func run(
        _ request: Request,
        currentSongTime: @MainActor () -> TimeInterval?,
        isCurrentTrack: @MainActor () -> Bool,
        onGenerated: @MainActor ([LyricLine]) -> Void,
        evaluate: (@MainActor (Evaluation) -> Void)?
    ) async {
        let label = "'\(request.title)'"
        guard SpeechTranscriber.isAvailable else {
            LyricsLog.info("Word timing for \(label) skipped: speech transcription is unavailable on this Mac")
            return
        }

        let locales = await Self.speechLocales(for: request.lines)
        guard !locales.isEmpty else {
            LyricsLog.info("Word timing for \(label) skipped: no speech model for this song's language")
            return
        }

        let transcribers = locales.map {
            SpeechTranscriber(
                locale: $0,
                transcriptionOptions: [],
                reportingOptions: [.alternativeTranscriptions],
                attributeOptions: [.audioTimeRange]
            )
        }
        do {
            if let installation = try await AssetInventory.assetInstallationRequest(supporting: transcribers) {
                LyricsLog.info("Word timing: downloading speech models for \(locales.map(\.identifier).joined(separator: ", ")) (one time)")
                try await installation.downloadAndInstall()
            }
        } catch {
            LyricsLog.error("Word timing for \(label) skipped: speech model install failed: \(error.localizedDescription)")
            return
        }
        guard !Task.isCancelled, isCurrentTrack() else { return }

        guard let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: transcribers) else {
            LyricsLog.error("Word timing for \(label) skipped: speech model reported no audio format")
            return
        }
        let analyzer = SpeechAnalyzer(modules: transcribers)
        do {
            try await analyzer.prepareToAnalyze(in: analyzerFormat)
            let context = AnalysisContext()
            context.contextualStrings[.general] = Self.vocabulary(of: request.lines)
            try await analyzer.setContext(context)
        } catch {
            LyricsLog.error("Word timing for \(label) skipped: analyzer setup failed: \(error.localizedDescription)")
            return
        }

        let (inputs, continuation) = AsyncStream.makeStream(of: AnalyzerInput.self)
        let feeder = LyricsAudioFeeder(outputFormat: analyzerFormat, continuation: continuation)
        let audioFile = evaluate == nil ? nil : FileManager.default.temporaryDirectory
            .appendingPathComponent("sapphire-lyrics-eval", isDirectory: true)
            .appendingPathComponent("\(request.trackIdentity.replacingOccurrences(of: "eval:", with: "").replacingOccurrences(of: ":", with: "-")).caf")
        if let audioFile { feeder.record(to: audioFile) }
        let tap = LyricsAudioTap()
        guard let firstSongTime = currentSongTime() else { return }
        do {
            try tap.start(processID: request.processID, muted: request.muteCapture) { buffer in feeder.consume(buffer) }
        } catch {
            continuation.finish()
            LyricsLog.error("Word timing for \(label) skipped: audio tap on pid \(request.processID) failed: \(error.localizedDescription)")
            return
        }
        activeTap = tap
        activeContinuation = continuation
        defer {
            tap.stop()
            feeder.flush()
            continuation.finish()
            if activeTap === tap {
                activeTap = nil
                activeContinuation = nil
            }
        }
        LyricsLog.info(
            "Word timing started for \(label): \(locales.map(\.identifier).joined(separator: " + ")), pid \(request.processID), from \(Self.seconds(firstSongTime))"
        )

        let collectors = transcribers.map { transcriber in
            let results = transcriber.results
            return Task.detached { () -> [RecognizedWord] in
                var heard: [RecognizedWord] = []
                do {
                    for try await result in results {
                        heard.append(contentsOf: Self.words(in: result, offset: 0))
                    }
                } catch {
                    LyricsLog.error("Word timing: transcription stream ended with an error: \(error.localizedDescription)")
                }
                return heard
            }
        }
        let analysis = Task.detached { () -> String? in
            do {
                _ = try await analyzer.analyzeSequence(inputs)
                try await analyzer.finalizeAndFinishThroughEndOfInput()
                return nil
            } catch {
                return error.localizedDescription
            }
        }

        let lastLyricEnd = request.lines
            .last { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { $0.endTimestamp ?? $0.timestamp + LyricsWordAligner.fallbackLineDuration }
            ?? firstSongTime
        var anchors: [TimeInterval] = []
        var endReason = "reached the last lyric line"
        while true {
            try? await Task.sleep(for: .seconds(1))
            if Task.isCancelled {
                endReason = "stopped (track changed)"
                break
            }
            guard isCurrentTrack(), let now = currentSongTime() else {
                endReason = "paused or track changed"
                break
            }
            let anchor = now - feeder.secondsFed
            if anchors.count >= Self.anchorWarmup + 2,
               let settled = Self.median(anchors.dropFirst(Self.anchorWarmup)),
               abs(anchor - settled) > 1.5 {
                endReason = "playback position jumped by \(Self.seconds(anchor - settled))"
                break
            }
            anchors.append(anchor)
            if feeder.secondsFed > 8, !feeder.hasSignal {
                endReason = "the tapped app produced no audio (it may play through a helper process)"
                break
            }
            if now > lastLyricEnd + 1 { break }
        }

        tap.stop()
        feeder.flush()
        continuation.finish()
        if activeTap === tap {
            activeTap = nil
            activeContinuation = nil
        }
        if let failure = await analysis.value {
            LyricsLog.error("Word timing for \(label): analysis failed: \(failure)")
        }
        let songTimeAtStart = Self.median(anchors.count > Self.anchorWarmup ? Array(anchors.dropFirst(Self.anchorWarmup)) : anchors)
            ?? firstSongTime

        var best: (locale: Locale, heard: [RecognizedWord], alignment: LyricsWordAligner.Alignment)?
        for (index, collector) in collectors.enumerated() {
            let heard = (await collector.value).map {
                RecognizedWord(text: $0.text, start: $0.start + songTimeAtStart, end: $0.end + songTimeAtStart)
            }
            let alignment = LyricsWordAligner.align(lines: request.lines, recognized: heard)
            if best == nil || alignment.matchedWords > best!.alignment.matchedWords {
                best = (locales[index], heard, alignment)
            }
        }
        guard let (locale, heard, alignment) = best else { return }
        LyricsLog.info(
            "Word timing for \(label) ended (\(endReason)) after \(Self.seconds(feeder.secondsFed)) of audio [\(locale.identifier)]: heard \(heard.count) words, matched \(alignment.matchedWords)/\(alignment.totalWords) (\(Self.percent(alignment.confidence))), aligned \(alignment.alignedLines)/\(alignment.lyricLines) lines (\(Self.percent(alignment.lineCoverage)))"
        )
        if let evaluate {
            let onsets = feeder.onsetEnvelope(startingAt: songTimeAtStart)
            evaluate(Evaluation(
                locale: locale.identifier,
                heardWords: heard.count,
                secondsHeard: feeder.secondsFed,
                endReason: endReason,
                matchedWords: alignment.matchedWords,
                totalWords: alignment.totalWords,
                alignedLines: alignment.alignedLines,
                lyricLines: alignment.lyricLines,
                recognized: LyricsTimingRefiner.overlay(from: alignment.lines, onsets: nil, locale: locale),
                refined: LyricsTimingRefiner.overlay(
                    from: LyricsTimingRefiner.anchored(alignment, to: request.lines, bias: Self.startBias),
                    onsets: nil,
                    locale: locale
                ),
                heard: heard,
                onsets: onsets,
                audioStart: songTimeAtStart,
                audioFile: audioFile
            ))
            return
        }
        let heardWindow = songTimeAtStart...(songTimeAtStart + feeder.secondsFed)
        let window = Self.windowQuality(of: alignment, lines: request.lines, within: heardWindow)
        let wholeSong = alignment.confidence >= Self.minimumConfidence && alignment.lineCoverage >= Self.minimumLineCoverage
        let partial = window.lines >= Self.minimumPartialLines
            && window.confidence >= Self.minimumConfidence
            && window.lineCoverage >= Self.minimumLineCoverage
        guard wholeSong || partial else {
            LyricsLog.info(
                "Word timing for \(label) not used: \(window.lines) lyric lines heard, \(Self.percent(window.confidence)) of their words matched (needs \(Self.minimumPartialLines)+ lines, \(Self.percent(Self.minimumConfidence)) matched, \(Self.percent(Self.minimumLineCoverage)) aligned)"
            )
            return
        }
        let anchored = LyricsTimingRefiner.anchored(alignment, to: request.lines, bias: Self.startBias)
        let usedLines = wholeSong ? anchored : anchored.filter { window.ids.contains($0.id) }
        let fresh = LyricsTimingRefiner.overlay(from: usedLines, onsets: nil, locale: locale)
        var overlay = fresh
        var samples = 1
        var confidence = wholeSong ? alignment.confidence : window.confidence
        if let consensus = request.consensus {
            overlay = consensus.overlay.merged(with: fresh, samples: consensus.samples)
            samples = consensus.samples + 1
            confidence = (consensus.confidence * Double(consensus.samples) + confidence) / Double(samples)
        }
        if let applied = overlay.apply(to: request.lines, minimumCoverage: 0), isCurrentTrack() {
            onGenerated(applied)
        }

        guard let key = LyricsDatabase.key(title: request.title, artist: request.artist),
              let document = LyricsDatabaseDocument.timing(
                overlay,
                confidence: confidence,
                samples: samples,
                durationMs: request.durationMs,
                engine: Self.engine
              ) else {
            return
        }
        switch await Self.upload(document, key: key) {
        case .stored:
            LyricsLog.info("Word timing for \(label) uploaded (\(overlay.lines.count) lines, \(samples) listen(s) averaged)")
        case .keptExisting:
            LyricsLog.info("Word timing for \(label) not uploaded: the database already has an equal or better result")
        case .failed(let message):
            LyricsLog.error("Word timing for \(label): upload failed: \(message)")
        }
    }

    // MARK: - Helpers

    private enum UploadOutcome: Sendable {
        case stored
        case keptExisting
        case failed(String)
    }

    private nonisolated static func upload(_ document: [String: Any], key: String) async -> UploadOutcome {
        var data = document
        data["t"] = FieldValue.serverTimestamp()
        guard let database = await MainActor.run(body: { FirebaseBootstrap.firestoreDatabase() }) else {
            return .failed("Firestore is unavailable")
        }
        do {
            try await database.collection(LyricsDatabase.collection).document(key).setData(data)
            LyricsDatabaseDiskCache.store(document, for: key)
            return .stored
        } catch let error as NSError where error.domain == FirestoreErrorDomain && error.code == FirestoreErrorCode.permissionDenied.rawValue {
            return .keptExisting
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    static func vocabulary(of lines: [LyricLine]) -> [String] {
        var seen = Set<String>()
        var words: [String] = []
        for line in lines {
            for token in line.text.split(whereSeparator: \.isWhitespace) {
                let word = String(token.filter { $0.isLetter || $0 == "'" || $0 == "’" })
                    .trimmingCharacters(in: CharacterSet(charactersIn: "'’"))
                guard word.count >= 2, seen.insert(word.lowercased()).inserted else { continue }
                words.append(word)
            }
        }
        return Array(words.sorted { $0.count > $1.count }.prefix(100))
    }

    private nonisolated static func words(in result: SpeechTranscriber.Result, offset: TimeInterval) -> [RecognizedWord] {
        var words: [RecognizedWord] = []
        var seen = Set<String>()
        for transcript in [result.text] + result.alternatives {
            for run in transcript.runs {
                guard let range = run[AttributeScopes.SpeechAttributes.TimeRangeAttribute.self] else { continue }
                let pieces = String(transcript[run.range].characters)
                    .split(whereSeparator: \.isWhitespace)
                    .map(String.init)
                let start = range.start.seconds
                let duration = range.duration.seconds
                guard !pieces.isEmpty, start.isFinite, duration.isFinite, duration >= 0 else { continue }
                let times = LyricsTimingRefiner.pieceTimes(pieces, start: offset + start, duration: duration)
                for (piece, time) in zip(pieces, times) {
                    guard seen.insert("\(LyricsWordAligner.matchKey(piece))@\(Int(time.start * 50))").inserted else { continue }
                    words.append(RecognizedWord(text: piece, start: time.start, end: time.end))
                }
            }
        }
        return words
    }

    nonisolated static let anchorWarmup = 3
    nonisolated static let minimumPartialLines = 6

    nonisolated static func windowQuality(
        of alignment: LyricsWordAligner.Alignment,
        lines: [LyricLine],
        within heard: ClosedRange<TimeInterval>
    ) -> (lines: Int, confidence: Double, lineCoverage: Double, ids: Set<UUID>) {
        var ids = Set<UUID>()
        var words = 0
        var matched = 0
        var aligned = 0
        for line in lines where heard.contains(line.timestamp) {
            let countable = LyricsTimingOverlay.countableTokens(of: line.text).count
            guard countable > 0 else { continue }
            ids.insert(line.id)
            words += countable
            let hits = alignment.matchedTokens[line.id]?.count ?? 0
            matched += hits
            if hits > 0 { aligned += 1 }
        }
        guard !ids.isEmpty else { return (0, 0, 0, []) }
        return (ids.count, Double(matched) / Double(max(words, 1)), Double(aligned) / Double(ids.count), ids)
    }
    nonisolated static let startBias: TimeInterval = 0.05

    nonisolated static func median(_ values: some Collection<TimeInterval>) -> TimeInterval? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        return sorted[sorted.count / 2]
    }

    static func speechLocales(for lines: [LyricLine]) async -> [Locale] {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(lines.prefix(80).map(\.text).joined(separator: "\n"))
        guard let language = recognizer.dominantLanguage?.rawValue else { return [] }
        let supported = await SpeechTranscriber.supportedLocales
        return preferredSpeechLocales(language: language, supported: supported, current: Locale.current)
    }

    nonisolated static func preferredSpeechLocales(language: String, supported: [Locale], current: Locale) -> [Locale] {
        func pick(_ identifiers: [String]) -> [Locale] {
            identifiers.compactMap { identifier in supported.first { $0.identifier == identifier } }
        }
        switch language {
        case "zh-Hans": return pick(["zh_CN", "zh_HK"])
        case "zh-Hant": return pick(["zh_HK", "zh_TW"])
        default:
            let code = Locale(identifier: language).language.languageCode
            let matching = supported.filter { $0.language.languageCode == code }
            if let regional = matching.first(where: { $0.region == current.region }) { return [regional] }
            let defaults = ["en": "en_US", "es": "es_US", "fr": "fr_FR", "de": "de_DE", "it": "it_IT", "pt": "pt_BR", "ja": "ja_JP", "ko": "ko_KR", "hi": "hi_IN"]
            if let preferred = defaults[language].flatMap({ pick([$0]).first }) { return [preferred] }
            return matching.first.map { [$0] } ?? []
        }
    }

    private nonisolated static func seconds(_ value: TimeInterval) -> String {
        String(format: "%.1fs", value)
    }

    private nonisolated static func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }
}

@available(macOS 26.0, *)
final class LyricsAudioFeeder: @unchecked Sendable {
    private let outputFormat: AVAudioFormat
    private let continuation: AsyncStream<AnalyzerInput>.Continuation
    private let lock = NSLock()
    private var converter: AVAudioConverter?
    private var framesFed: AVAudioFramePosition = 0
    private var peak: Float = 0
    private var onsetDetector: LyricsOnsetDetector?
    private var recording: AVAudioFile?
    private var pending: AVAudioPCMBuffer?
    private var pendingStartFrame: AVAudioFramePosition = 0
    static let batchSeconds: Double = 0.2

    func record(to url: URL) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: url)
        lock.withLock {
            recording = try? AVAudioFile(
                forWriting: url,
                settings: outputFormat.settings,
                commonFormat: outputFormat.commonFormat,
                interleaved: outputFormat.isInterleaved
            )
        }
    }

    init(outputFormat: AVAudioFormat, continuation: AsyncStream<AnalyzerInput>.Continuation) {
        self.outputFormat = outputFormat
        self.continuation = continuation
    }

    var secondsFed: TimeInterval {
        lock.withLock { Double(framesFed) / outputFormat.sampleRate }
    }

    var hasSignal: Bool {
        lock.withLock { peak > 0.0005 }
    }

    func onsetEnvelope(startingAt songTime: TimeInterval) -> LyricsOnsetEnvelope? {
        lock.withLock {
            guard let strength = onsetDetector?.strength, !strength.isEmpty else { return nil }
            return LyricsOnsetEnvelope(start: songTime, strength: strength)
        }
    }

    func consume(_ input: AVAudioPCMBuffer) {
        if converter == nil || converter?.inputFormat != input.format {
            converter = AVAudioConverter(from: input.format, to: outputFormat)
        }
        guard let converter, input.frameLength > 0 else { return }

        let capacity = AVAudioFrameCount(Double(input.frameLength) * outputFormat.sampleRate / input.format.sampleRate) + 64
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else { return }
        var supplied = false
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) { _, inputStatus in
            if supplied {
                inputStatus.pointee = .noDataNow
                return nil
            }
            supplied = true
            inputStatus.pointee = .haveData
            return input
        }
        guard status != .error, output.frameLength > 0 else { return }

        let level = Self.peakLevel(of: input)
        let ready: [(AVAudioPCMBuffer, AVAudioFramePosition)] = lock.withLock {
            if onsetDetector == nil { onsetDetector = LyricsOnsetDetector(sampleRate: input.format.sampleRate) }
            onsetDetector?.process(input)
            if let recording, recording.processingFormat == output.format { try? recording.write(from: output) }
            let start = framesFed
            framesFed += AVAudioFramePosition(output.frameLength)
            peak = max(peak, level)
            return appendPendingLocked(output, startFrame: start)
        }
        for (batch, startFrame) in ready { yield(batch, startFrame: startFrame) }
    }

    func flush() {
        let remaining: (AVAudioPCMBuffer, AVAudioFramePosition)? = lock.withLock {
            defer { pending = nil }
            guard let pending, pending.frameLength > 0 else { return nil }
            return (pending, pendingStartFrame)
        }
        if let (batch, startFrame) = remaining { yield(batch, startFrame: startFrame) }
    }

    private func appendPendingLocked(_ output: AVAudioPCMBuffer, startFrame: AVAudioFramePosition) -> [(AVAudioPCMBuffer, AVAudioFramePosition)] {
        let batchFrames = AVAudioFrameCount(outputFormat.sampleRate * Self.batchSeconds)
        var ready: [(AVAudioPCMBuffer, AVAudioFramePosition)] = []
        if let batch = pending, batch.frameLength + output.frameLength > batch.frameCapacity {
            ready.append((batch, pendingStartFrame))
            pending = nil
        }
        if pending == nil {
            guard let fresh = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: max(batchFrames, output.frameLength)) else {
                ready.append((output, startFrame))
                return ready
            }
            pending = fresh
            pendingStartFrame = startFrame
        }
        guard let batch = pending, Self.append(output, to: batch) else {
            if let batch = pending, batch.frameLength > 0 { ready.append((batch, pendingStartFrame)) }
            pending = nil
            ready.append((output, startFrame))
            return ready
        }
        if batch.frameLength >= batchFrames {
            ready.append((batch, pendingStartFrame))
            pending = nil
        }
        return ready
    }

    private static func append(_ source: AVAudioPCMBuffer, to target: AVAudioPCMBuffer) -> Bool {
        let frames = Int(source.frameLength)
        let offset = Int(target.frameLength)
        let format = target.format
        guard source.format == format else { return false }
        let channels = Int(format.channelCount)
        let samplesPerFrame = format.isInterleaved ? channels : 1
        let planes = format.isInterleaved ? 1 : channels
        if let src = source.floatChannelData, let dst = target.floatChannelData {
            for plane in 0..<planes {
                (dst[plane] + offset * samplesPerFrame).update(from: src[plane], count: frames * samplesPerFrame)
            }
        } else if let src = source.int16ChannelData, let dst = target.int16ChannelData {
            for plane in 0..<planes {
                (dst[plane] + offset * samplesPerFrame).update(from: src[plane], count: frames * samplesPerFrame)
            }
        } else if let src = source.int32ChannelData, let dst = target.int32ChannelData {
            for plane in 0..<planes {
                (dst[plane] + offset * samplesPerFrame).update(from: src[plane], count: frames * samplesPerFrame)
            }
        } else {
            return false
        }
        target.frameLength = AVAudioFrameCount(offset + frames)
        return true
    }

    private func yield(_ buffer: AVAudioPCMBuffer, startFrame: AVAudioFramePosition) {
        continuation.yield(AnalyzerInput(
            buffer: buffer,
            bufferStartTime: CMTime(value: startFrame, timescale: CMTimeScale(outputFormat.sampleRate))
        ))
    }

    private static func peakLevel(of buffer: AVAudioPCMBuffer) -> Float {
        guard let channels = buffer.floatChannelData else { return 1 }
        let channelCount = Int(buffer.format.channelCount)
        let planes = buffer.format.isInterleaved ? 1 : channelCount
        let samplesPerPlane = Int(buffer.frameLength) * (buffer.format.isInterleaved ? channelCount : 1)
        var level: Float = 0
        for plane in 0..<planes {
            var planePeak: Float = 0
            vDSP_maxmgv(channels[plane], 1, &planePeak, vDSP_Length(samplesPerPlane))
            level = max(level, planePeak)
        }
        return level
    }
}