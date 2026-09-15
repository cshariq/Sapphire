//
//  NativeMediaController.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-21

import Foundation
import Darwin
import AppKit
import Combine
import ImageIO

// MARK: - Precise Absolute Timing Anchor
struct PlaybackTimingAnchor: Equatable {
    let elapsedAtSample: TimeInterval
    let sampleEpochTime: TimeInterval
    let rate: Double

    func elapsed(at now: Date = Date()) -> TimeInterval {
        guard rate != 0 else { return elapsedAtSample }
        let delta = now.timeIntervalSince1970 - sampleEpochTime
        let clampedDelta = max(0, min(delta, 86400))
        return elapsedAtSample + (clampedDelta * rate)
    }
}

struct TrackInfo: Equatable {
    struct Payload: Equatable {
        var processIdentifier: Int? = nil
        var bundleIdentifier: String? = nil
        var parentApplicationBundleIdentifier: String? = nil
        var title: String? = nil
        var artist: String? = nil
        var album: String? = nil
        var albumArtist: String? = nil
        var composer: String? = nil
        var genre: String? = nil
        var chapterNumber: NSNumber? = nil
        var totalChapterCount: NSNumber? = nil
        var trackNumber: NSNumber? = nil
        var discNumber: NSNumber? = nil
        var totalTrackCount: NSNumber? = nil
        var queueIndex: NSNumber? = nil
        var totalQueueCount: NSNumber? = nil
        var isPlaying: Bool? = nil
        var durationMicros: Int64? = nil
        var currentElapsedTime: TimeInterval? = nil
        var elapsedTimeMicros: Int64? = nil
        var playbackRate: Float? = nil
        var startTime: NSNumber? = nil
        var timestamp: NSNumber? = nil
        var timestampEpochMicros: Int64? = nil
        var repeatMode: Int? = nil
        var shuffleMode: Int? = nil
        var isLiked: Bool? = nil
        var isBanned: Bool? = nil
        var isInWishList: Bool? = nil
        var isAdvertisement: Bool? = nil
        var isMusicApp: Bool? = nil
        var supportsIsLiked: Bool? = nil
        var supportsIsBanned: Bool? = nil
        var supportsFastForward15Seconds: Bool? = nil
        var supportsRewind15Seconds: Bool? = nil
        var prohibitsSkip: Bool? = nil
        var radioStationIdentifier: String? = nil
        var radioStationHash: String? = nil
        var contentItemIdentifier: String? = nil
        var uniqueIdentifier: String? = nil
        var mediaType: String? = nil
        var artwork: NSImage? = nil
        var artworkMimeType: String? = nil

        var calculatedElapsedTime: TimeInterval {
            interpolatedElapsedTime(at: Date())
        }

        func interpolatedElapsedTime(at now: Date) -> TimeInterval {
            guard let anchor = playbackTimingAnchor(isPlayingNow: isPlaying ?? false) else {
                return currentElapsedTime ?? 0
            }
            return anchor.elapsed(at: now)
        }

        func playbackTimingAnchor(isPlayingNow: Bool) -> PlaybackTimingAnchor? {
            guard let elapsed = currentElapsedTime else { return nil }

            let rate: Double
            if isPlayingNow {
                let reported = Double(playbackRate ?? 1.0)
                rate = reported > 0 ? reported : 1.0
            } else {
                rate = 0.0
            }
            let sampleEpoch: TimeInterval

            if let micros = timestampEpochMicros {
                sampleEpoch = Double(micros) / 1_000_000.0
            } else if let ts = timestamp?.doubleValue {
                sampleEpoch = ts + Date.timeIntervalBetween1970AndReferenceDate
            } else {
                sampleEpoch = Date().timeIntervalSince1970
            }

            return PlaybackTimingAnchor(
                elapsedAtSample: elapsed,
                sampleEpochTime: sampleEpoch,
                rate: rate
            )
        }
    }

    let payload: Payload
}

@MainActor
final class NativeMediaController: NSObject {
    private struct SendableMetadata: @unchecked Sendable {
        let value: [String: Any]
    }

    var onActiveClientsChanged: (([String: TrackInfo]) -> Void)?
    var onListenerTerminated: (() -> Void)?
    var onDecodingError: ((String, String?) -> Void)?
    var onTrackInfoReceived: ((TrackInfo?) -> Void)?

    @Published var activeClients: [String: TrackInfo] = [:]

    nonisolated private let pollQueue = DispatchQueue(label: "com.sapphire.mediaremote.adapter", qos: .userInitiated)
    private var isListening = false
    private var streamProcess: Process?
    nonisolated(unsafe) private var buffer = Data()
    private var lastActiveClientKey: String?
    private var lastTrackIdentity: String?
    private var lastMediaFingerprint: String?
    private var currentMergedMetadata: [String: Any] = [:]
    private var lastDecodedArtworkHash: Int?
    private var lastDecodedArtworkImage: NSImage?

    nonisolated private static let cachedPaths: (script: String, adapter: String, testClient: String?)? = {
        let fm = FileManager.default
        guard let resourcePath = Bundle.main.resourcePath else { return nil }

        let scriptPath = (resourcePath as NSString).appendingPathComponent("mediaremote-adapter.pl")
        let adapterPath = (resourcePath as NSString).appendingPathComponent("MediaRemoteAdapter.framework")

        if fm.fileExists(atPath: scriptPath) && fm.fileExists(atPath: adapterPath) {
            return (scriptPath, adapterPath, nil)
        }

        var size: UInt32 = 0
        _NSGetExecutablePath(nil, &size)
        let buffer = UnsafeMutablePointer<Int8>.allocate(capacity: Int(size))
        defer { buffer.deallocate() }

        if _NSGetExecutablePath(buffer, &size) == 0 {
            let exeDir = (String(cString: buffer) as NSString).deletingLastPathComponent
            let fbScript = (exeDir as NSString).appendingPathComponent("mediaremote-adapter.pl")
            let fbAdapter = (exeDir as NSString).appendingPathComponent("MediaRemoteAdapter.framework")

            if fm.fileExists(atPath: fbScript) && fm.fileExists(atPath: fbAdapter) {
                return (fbScript, fbAdapter, nil)
            }
        }
        return nil
    }()

    override init() {
        super.init()
    }

    private static var didReapOrphanedStreams = false

    private static func reapOrphanedStreamsOnce() {
        guard !didReapOrphanedStreams else { return }
        didReapOrphanedStreams = true
        DispatchQueue.global(qos: .utility).async {
            let ps = Process()
            ps.executableURL = URL(fileURLWithPath: "/bin/ps")
            ps.arguments = ["-axo", "pid=,ppid=,command="]
            let output = Pipe()
            ps.standardOutput = output
            ps.standardError = FileHandle.nullDevice
            guard (try? ps.run()) != nil else { return }
            let data = output.fileHandleForReading.readDataToEndOfFile()
            ps.waitUntilExit()
            guard let listing = String(data: data, encoding: .utf8) else { return }
            for line in listing.split(separator: "\n") {
                let fields = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
                guard fields.count == 3,
                      let pid = pid_t(fields[0]), fields[1] == "1",
                      fields[2].contains("Sapphire.app/Contents/Resources/mediaremote-adapter.pl"),
                      fields[2].contains(" stream") else { continue }
                kill(pid, SIGTERM)
            }
        }
    }

    func startListening() {
        guard !isListening else { return }
        isListening = true
        pollQueue.async { [weak self] in
            Task { @MainActor in self?.launchStream() }
        }
    }

    func restartListeningIfNeeded() {
        guard isListening else {
            startListening()
            return
        }
        pollQueue.async { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.streamProcess?.terminate()
                self.streamProcess = nil
                self.launchStream()
            }
        }
    }

    func stop() {
        guard isListening else { return }
        isListening = false
        pollQueue.async { [weak self] in
            Task { @MainActor in
                self?.streamProcess?.terminate()
                self?.streamProcess = nil
            }
        }
    }

    deinit { streamProcess?.terminate() }

    // MARK: - Native Media Remote Transport Commands
    func play() { runAdapterCommand(["send", "0"]) }
    func pause() { runAdapterCommand(["send", "1"]) }
    func togglePlayPause() { runAdapterCommand(["send", "2"]) }
    func stopPlayback() { runAdapterCommand(["send", "3"]) }
    func nextTrack() { runAdapterCommand(["send", "4"]) }
    func previousTrack() { runAdapterCommand(["send", "5"]) }
    func toggleShuffle() { runAdapterCommand(["send", "6"]) }
    func toggleRepeat() { runAdapterCommand(["send", "7"]) }
    func beginForwardSeek() { runAdapterCommand(["send", "8"]) }
    func endForwardSeek() { runAdapterCommand(["send", "8"]) }
    func beginBackwardSeek() { runAdapterCommand(["send", "10"]) }
    func endBackwardSeek() { runAdapterCommand(["send", "11"]) }
    func skipBack15Seconds() { runAdapterCommand(["send", "12"]) }
    func skipForward15Seconds() { runAdapterCommand(["send", "13"]) }
    func setTime(seconds: Double) {
        runAdapterCommand(["seek", String(Self.micros(fromSeconds: seconds) ?? 0)])
    }

    private func runAdapterCommand(_ args: [String]) {
        pollQueue.async {
            guard let paths = Self.cachedPaths else { return }
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
            var arguments = [paths.script, paths.adapter]
            arguments.append(contentsOf: args)
            task.arguments = arguments
            task.standardOutput = FileHandle.nullDevice
            task.standardError = FileHandle.nullDevice
            try? task.run()
        }
    }

    private func launchStream() {
        guard let paths = Self.cachedPaths else { return }

        print("[NativeMediaController]  Starting mediaremote-adapter.pl stream...")
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        task.arguments = [paths.script, paths.adapter, "stream", "--debounce=100", "--micros"]

        var env = ProcessInfo.processInfo.environment
        env["PERLIO"] = ":unix"
        env["SAPPHIRE_WATCH_PARENT_STDIN"] = "1"
        task.environment = env
        task.standardInput = Pipe()
        Self.reapOrphanedStreamsOnce()

        let stdout = Pipe()
        task.standardOutput = stdout
        task.standardError = FileHandle.nullDevice
        streamProcess = task
        pollQueue.async { [weak self] in
            self?.buffer.removeAll()
        }

        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            self?.pollQueue.async { [weak self] in
                self?.appendAndProcessBuffer(data)
            }
        }

        task.terminationHandler = { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                print("[NativeMediaController] ️ Stream process terminated.")
                self.onListenerTerminated?()
                if self.isListening {
                    try? await Task.sleep(for: .seconds(1.5))
                    guard self.isListening else { return }
                    self.launchStream()
                }
            }
        }

        try? task.run()
    }

    nonisolated private func appendAndProcessBuffer(_ data: Data) {
        buffer.append(data)
        while let range = buffer.range(of: Data("\n".utf8)) {
            let lineData = buffer.subdata(in: buffer.startIndex..<range.lowerBound)
            buffer.removeSubrange(buffer.startIndex..<range.upperBound)
            guard !lineData.isEmpty else { continue }

            guard let parsed = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else {
                continue
            }

            let payload: [String: Any]
            if let inner = parsed["payload"] as? [String: Any] {
                payload = inner
            } else {
                payload = parsed
            }

            let metadata = SendableMetadata(value: payload)
            Task { @MainActor [weak self] in
                self?.handleTrackUpdate(metadata.value)
            }
        }
    }

    private func clearActiveSystemMedia(notify: Bool = true) {
        print("[NativeMediaController]  Clearing active system media source.")
        activeClients.removeAll()
        currentMergedMetadata.removeAll()
        lastActiveClientKey = nil
        lastTrackIdentity = nil
        lastMediaFingerprint = nil
        lastDecodedArtworkHash = nil
        lastDecodedArtworkImage = nil
        if notify {
            onActiveClientsChanged?([:])
            onTrackInfoReceived?(nil)
        }
    }

    private func handleTrackUpdate(_ metadata: [String: Any]) {
        if metadata.isEmpty {
            clearActiveSystemMedia(notify: true)
            return
        }

        guard isListening else { return }

        let incomingBundle: String? = {
            if let raw = metadata["bundleIdentifier"] as? String {
                return MediaApplicationIdentity.canonicalBundleID(raw) ?? raw
            }
            return nil
        }()

        let targetKey: String
        if let incomingBundle, !incomingBundle.isEmpty {
            targetKey = incomingBundle
        } else if let last = lastActiveClientKey {
            targetKey = last
        } else {
            targetKey = "unknown"
        }

        if let last = lastActiveClientKey, last != targetKey {
            print("[NativeMediaController]  Switching active system source: '\(last)' -> '\(targetKey)'")
            currentMergedMetadata.removeAll()
            lastTrackIdentity = nil
            lastMediaFingerprint = nil
            lastDecodedArtworkHash = nil
            lastDecodedArtworkImage = nil
        }
        lastActiveClientKey = targetKey

        for (entryKey, value) in metadata {
            if entryKey == "_sapphireSnapshot" { continue }
            if value is NSNull || Self.isEmptyMergeValue(value) {
                currentMergedMetadata.removeValue(forKey: entryKey)
            } else {
                currentMergedMetadata[entryKey] = value
            }
        }

        let playbackState = currentMergedMetadata["playbackState"] as? Int
        let isStopped = playbackState == 3
        let title = (currentMergedMetadata["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if title.isEmpty || isStopped {
            clearActiveSystemMedia(notify: true)
            return
        }

        if let playing = Self.normalizedPlaying(from: metadata) {
            currentMergedMetadata["playing"] = playing
        } else if metadata["playbackRate"] != nil {
            let rate = (metadata["playbackRate"] as? NSNumber)?.floatValue ?? 0
            currentMergedMetadata["playing"] = rate != 0
        }

        let mergedIdentity = Self.trackIdentity(currentMergedMetadata)
        let fingerprint = Self.mediaFingerprint(currentMergedMetadata)
        let transportOnly = Self.isTransportOnlyMetadata(metadata)

        var trackChanged = false
        if !transportOnly {
            if !fingerprint.isEmpty {
                trackChanged = fingerprint != lastMediaFingerprint
            } else if let lastTrackIdentity, mergedIdentity != "unknown" {
                trackChanged = mergedIdentity != lastTrackIdentity
            } else if lastTrackIdentity == nil, mergedIdentity != "unknown" {
                trackChanged = true
            }
        }

        if trackChanged {
            print("[NativeMediaController]  System track changed: [\(targetKey)] -> \(title)")
            lastTrackIdentity = mergedIdentity
            if !fingerprint.isEmpty {
                lastMediaFingerprint = fingerprint
            }
            if metadata["artworkData"] == nil {
                lastDecodedArtworkHash = nil
                lastDecodedArtworkImage = nil
            }
        }

        var artworkImage = lastDecodedArtworkImage
        var artworkChanged = false
        let eventCarriesArtwork = metadata["artworkData"] != nil
        let hasNoArtworkRecord = lastDecodedArtworkImage == nil && lastDecodedArtworkHash == nil
        if eventCarriesArtwork || hasNoArtworkRecord,
           let base64 = currentMergedMetadata["artworkData"] as? String, !base64.isEmpty {
            let utf8 = base64.utf8
            let currentHash: Int = {
                var h = base64.count
                h &+= Int(utf8.first ?? 0)
                h &+= Int(utf8.last ?? 0) << 8
                let midIndex = utf8.index(utf8.startIndex, offsetBy: min(63, utf8.count - 1))
                h &+= Int(utf8[midIndex]) << 16
                return h
            }()
            if currentHash == lastDecodedArtworkHash, let cached = lastDecodedArtworkImage {
                artworkImage = cached
            } else if let data = Data(base64Encoded: base64, options: .ignoreUnknownCharacters),
                      let decoded = NSImage(data: data) {
                lastDecodedArtworkHash = currentHash
                lastDecodedArtworkImage = decoded
                artworkImage = decoded
                artworkChanged = true
            } else if lastDecodedArtworkHash != currentHash {
                lastDecodedArtworkHash = currentHash
                lastDecodedArtworkImage = nil
                artworkImage = nil
                artworkChanged = true
            }
        }

        guard let track = buildTrackInfo(from: currentMergedMetadata, artwork: artworkImage) else {
            clearActiveSystemMedia(notify: true)
            return
        }

        let existingClient = activeClients[targetKey]
        let playStateChanged = existingClient?.payload.isPlaying != track.payload.isPlaying
            || existingClient?.payload.playbackRate != track.payload.playbackRate
        let positionChanged = playbackPositionChanged(from: existingClient?.payload, to: track.payload)
        let artworkArrived = track.payload.artwork != nil && existingClient?.payload.artwork == nil

        let shouldNotify = trackChanged || playStateChanged || positionChanged || artworkChanged || artworkArrived

        activeClients = [targetKey: track]

        if shouldNotify {
            onActiveClientsChanged?(activeClients)
            onTrackInfoReceived?(track)
        }
    }

    private func playbackPositionChanged(from previous: TrackInfo.Payload?, to current: TrackInfo.Payload) -> Bool {
        guard let prev = previous, prev.currentElapsedTime != nil else {
            return previous?.currentElapsedTime != current.currentElapsedTime
        }
        guard let currElapsed = current.currentElapsedTime else { return true }

        let expectedElapsed = prev.interpolatedElapsedTime(at: Date())

        return abs(expectedElapsed - currElapsed) > 1.5
    }

    func trimArtworkCache(keeping identity: String?) {
        lastDecodedArtworkHash = nil
        lastDecodedArtworkImage = nil
    }

    nonisolated private static func micros(fromSeconds seconds: Double) -> Int64? {
        guard seconds.isFinite else { return nil }
        let micros = seconds * 1_000_000
        guard micros.isFinite, micros >= Double(Int64.min), micros < Double(Int64.max) else {
            return nil
        }
        return Int64(micros)
    }

    nonisolated private static func normalizedPlaying(from metadata: [String: Any]) -> Bool? {
        if let playing = metadata["playing"] as? Bool { return playing }
        if let playing = metadata["playing"] as? NSNumber { return playing.boolValue }
        if let rate = (metadata["playbackRate"] as? NSNumber)?.floatValue { return rate != 0 }
        return nil
    }

    nonisolated private static func isTransportOnlyMetadata(_ metadata: [String: Any]) -> Bool {
        let transportKeys: Set<String> = [
            "playing", "playbackRate", "playbackState",
            "elapsedTime", "elapsedTimeMicros",
            "elapsedTimeNow", "elapsedTimeNowMicros",
            "timestamp", "timestampEpochMicros",
            "startTime", "processIdentifier", "bundleIdentifier"
        ]
        let identityKeys: Set<String> = [
            "title", "artist", "album", "albumArtist",
            "contentItemIdentifier", "uniqueIdentifier",
            "duration", "durationMicros",
            "artworkData", "artworkMimeType"
        ]
        let keys = Set(metadata.keys)
        return !keys.isDisjoint(with: transportKeys) && keys.isDisjoint(with: identityKeys)
    }

    nonisolated private static func trackIdentity(_ m: [String: Any]) -> String {
        if let id = m["contentItemIdentifier"] as? String, !id.isEmpty { return "cid:\(id)" }
        if let id = m["uniqueIdentifier"] as? String, !id.isEmpty { return "uid:\(id)" }
        let fingerprint = mediaFingerprint(m)
        return fingerprint.isEmpty ? "unknown" : "fp:\(fingerprint)"
    }

    nonisolated private static func mediaFingerprint(_ m: [String: Any]) -> String {
        [m["title"] as? String, m["artist"] as? String]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "|")
            .lowercased()
    }

    nonisolated private static func isEmptyMergeValue(_ value: Any) -> Bool {
        if let string = value as? String {
            return string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return false
    }

    nonisolated private func buildTrackInfo(from metadata: [String: Any], artwork: NSImage?) -> TrackInfo? {
        let title = metadata["title"] as? String
        let artist = metadata["artist"] as? String
        let rawBundle = metadata["bundleIdentifier"] as? String
        let bundleId = MediaApplicationIdentity.canonicalBundleID(rawBundle) ?? rawBundle

        let hasIdentity = (title?.isEmpty == false) || (bundleId?.isEmpty == false)
        guard hasIdentity else { return nil }

        let durationMicros: Int64?
        if let micros = (metadata["durationMicros"] as? NSNumber)?.int64Value, micros > 0 {
            durationMicros = micros
        } else if let d = (metadata["duration"] as? NSNumber)?.doubleValue,
                  d > 0,
                  let micros = Self.micros(fromSeconds: d), micros > 0 {
            durationMicros = micros
        } else {
            durationMicros = nil
        }

        let elapsed: TimeInterval?
        if let micros = (metadata["elapsedTimeMicros"] as? NSNumber)?.int64Value {
            elapsed = TimeInterval(micros) / 1_000_000
        } else if let e = (metadata["elapsedTime"] as? NSNumber)?.doubleValue {
            elapsed = e
        } else if let micros = (metadata["elapsedTimeNowMicros"] as? NSNumber)?.int64Value {
            elapsed = TimeInterval(micros) / 1_000_000
        } else if let e = (metadata["elapsedTimeNow"] as? NSNumber)?.doubleValue {
            elapsed = e
        } else {
            elapsed = nil
        }

        let playbackRateNumber = metadata["playbackRate"] as? NSNumber
        let playbackRate = playbackRateNumber?.floatValue
        let isPlaying = Self.normalizedPlaying(from: metadata)

        let timestamp: NSNumber?
        let timestampEpochMicros: Int64?
        if let micros = (metadata["timestampEpochMicros"] as? NSNumber)?.int64Value {
            timestampEpochMicros = micros
            timestamp = NSNumber(value: Double(micros) / 1_000_000)
        } else if let ts = metadata["timestamp"] as? NSNumber {
            timestamp = ts
            timestampEpochMicros = nil
        } else {
            timestamp = nil
            timestampEpochMicros = nil
        }

        let processIdentifier: Int? = {
            if let value = metadata["processIdentifier"] as? Int { return value }
            if let value = metadata["processIdentifier"] as? NSNumber { return value.intValue }
            return nil
        }()

        let payload = TrackInfo.Payload(
            processIdentifier: processIdentifier,
            bundleIdentifier: bundleId,
            parentApplicationBundleIdentifier: metadata["parentApplicationBundleIdentifier"] as? String,
            title: title,
            artist: artist,
            album: metadata["album"] as? String,
            albumArtist: metadata["albumArtist"] as? String,
            composer: metadata["composer"] as? String,
            genre: metadata["genre"] as? String,
            chapterNumber: metadata["chapterNumber"] as? NSNumber,
            totalChapterCount: metadata["totalChapterCount"] as? NSNumber,
            trackNumber: metadata["trackNumber"] as? NSNumber,
            discNumber: metadata["discNumber"] as? NSNumber,
            totalTrackCount: metadata["totalTrackCount"] as? NSNumber,
            queueIndex: metadata["queueIndex"] as? NSNumber,
            totalQueueCount: metadata["totalQueueCount"] as? NSNumber,
            isPlaying: isPlaying,
            durationMicros: durationMicros,
            currentElapsedTime: elapsed,
            elapsedTimeMicros: elapsed.flatMap { Self.micros(fromSeconds: $0) },
            playbackRate: playbackRate,
            startTime: metadata["startTime"] as? NSNumber,
            timestamp: timestamp,
            timestampEpochMicros: timestampEpochMicros,
            repeatMode: (metadata["repeatMode"] as? NSNumber)?.intValue,
            shuffleMode: (metadata["shuffleMode"] as? NSNumber)?.intValue,
            isLiked: metadata["isLiked"] as? Bool,
            isBanned: metadata["isBanned"] as? Bool,
            isInWishList: metadata["isInWishList"] as? Bool,
            isAdvertisement: metadata["isAdvertisement"] as? Bool,
            isMusicApp: metadata["isMusicApp"] as? Bool,
            supportsIsLiked: metadata["supportsIsLiked"] as? Bool,
            supportsIsBanned: metadata["supportsIsBanned"] as? Bool,
            supportsFastForward15Seconds: metadata["supportsFastForward15Seconds"] as? Bool,
            supportsRewind15Seconds: metadata["supportsRewind15Seconds"] as? Bool,
            prohibitsSkip: metadata["prohibitsSkip"] as? Bool,
            radioStationIdentifier: metadata["radioStationIdentifier"] as? String,
            radioStationHash: metadata["radioStationHash"] as? String,
            contentItemIdentifier: metadata["contentItemIdentifier"] as? String,
            uniqueIdentifier: metadata["uniqueIdentifier"] as? String,
            mediaType: metadata["mediaType"] as? String,
            artwork: artwork,
            artworkMimeType: metadata["artworkMimeType"] as? String
        )
        return TrackInfo(payload: payload)
    }
}