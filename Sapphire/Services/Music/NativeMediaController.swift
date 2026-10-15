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
        var artworkKnownAbsent: Bool = false

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
    var onActiveClientsChanged: (([String: TrackInfo]) -> Void)?
    var onListenerTerminated: (() -> Void)?
    var onDecodingError: ((String, String?) -> Void)?
    var onTrackInfoReceived: ((TrackInfo?) -> Void)?

    @Published var activeClients: [String: TrackInfo] = [:]

    private enum SuspendReason: Hashable {
        case systemSleep
    }

    private struct StreamLaunch {
        let token: UInt64
        let process: Process
        let stdin: Pipe
        let stdout: Pipe
        let startedAt: Date
    }

    private var isListening = false
    private var suspendReasons = Set<SuspendReason>()
    nonisolated(unsafe) private var stream: StreamLaunch?
    private var launchToken: UInt64 = 0
    private var restartPolicy = StreamRestartPolicy()
    private var restartTask: Task<Void, Never>?
    private var powerObservers: [NSObjectProtocol] = []
    private let commands = AdapterCommandChannel()

    private var lastActiveClientKey: String?
    private var lastTrackIdentity: String?
    private var lastMediaFingerprint: String?
    private var currentMergedMetadata: [String: Any] = [:]
    private var currentArtwork: NSImage?
    private var currentArtworkDigest: String?
    private var lastTrackChangeAt: Date?
    private var artworkGraceTask: Task<Void, Never>?

    nonisolated static let cachedPaths: (script: String, adapter: String, testClient: String?)? = {
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

    // MARK: - Lifecycle

    func startListening() {
        guard !isListening else { return }
        isListening = true
        restartPolicy.reset()
        installPowerObservers()
        launchStream()
    }

    func restartListeningIfNeeded() {
        guard isListening else {
            startListening()
            return
        }
        restartPolicy.reset()
        terminateStream()
        launchStream()
    }

    func stop() {
        guard isListening else { return }
        isListening = false
        removePowerObservers()
        terminateStream()
        commands.shutdown()
    }

    deinit {
        stream?.process.terminate()
    }

    // MARK: - Native Media Remote Transport Commands
    func play() { commands.submit(.send(0)) }
    func pause() { commands.submit(.send(1)) }
    func togglePlayPause() { commands.submit(.send(2)) }
    func stopPlayback() { commands.submit(.send(3)) }
    func nextTrack() { commands.submit(.send(4)) }
    func previousTrack() { commands.submit(.send(5)) }
    func toggleShuffle() { commands.submit(.send(6)) }
    func toggleRepeat() { commands.submit(.send(7)) }
    func beginForwardSeek() { commands.submit(.send(8)) }
    func endForwardSeek() { commands.submit(.send(9)) }
    func beginBackwardSeek() { commands.submit(.send(10)) }
    func endBackwardSeek() { commands.submit(.send(11)) }
    func skipBack15Seconds() { commands.submit(.send(12)) }
    func skipForward15Seconds() { commands.submit(.send(13)) }
    func setTime(seconds: Double) {
        commands.submit(.seek(micros: Self.micros(fromSeconds: max(0, seconds)) ?? 0))
    }

    // MARK: - Stream process

    private func launchStream() {
        guard isListening, suspendReasons.isEmpty, stream == nil else { return }
        restartTask?.cancel()
        restartTask = nil
        guard let paths = Self.cachedPaths else {
            print("[NativeMediaController] mediaremote-adapter resources are missing; now playing is unavailable.")
            return
        }
        Self.reapOrphanedStreamsOnce()

        launchToken &+= 1
        let token = launchToken
        print("[NativeMediaController] Starting mediaremote-adapter.pl stream (launch \(token))...")

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        task.arguments = [paths.script, paths.adapter, "stream", "--debounce=100", "--micros"]

        var env = ProcessInfo.processInfo.environment
        env["PERLIO"] = ":unix"
        env["SAPPHIRE_WATCH_PARENT_STDIN"] = "1"
        task.environment = env
        let stdin = Pipe()
        task.standardInput = stdin
        let stdout = Pipe()
        task.standardOutput = stdout
        task.standardError = FileHandle.nullDevice

        currentMergedMetadata.removeAll()

        let parser = NowPlayingStreamParser()
        let parseQueue = DispatchQueue(label: "com.sapphire.mediaremote.stream-parse", qos: .userInitiated)
        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            parseQueue.async {
                let events = parser.consume(data)
                guard !events.isEmpty else { return }
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        guard let self else { return }
                        for event in events { self.handleStreamEvent(event, token: token) }
                    }
                }
            }
        }

        task.terminationHandler = { [weak self] process in
            let status = process.terminationStatus
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.streamDidExit(token: token, status: status)
                }
            }
        }

        let launch = StreamLaunch(token: token, process: task, stdin: stdin, stdout: stdout, startedAt: Date())
        stream = launch
        do {
            try task.run()
        } catch {
            print("[NativeMediaController] Could not start the now playing stream: \(error.localizedDescription)")
            stream = nil
            Self.closePipes(of: launch)
            scheduleRestartAfterExit(lifetime: 0)
        }
    }

    private func terminateStream() {
        restartTask?.cancel()
        restartTask = nil
        guard let launch = stream else { return }
        stream = nil
        if launch.process.isRunning { launch.process.terminate() }
        Self.closePipes(of: launch)
    }

    private static func closePipes(of launch: StreamLaunch) {
        launch.stdout.fileHandleForReading.readabilityHandler = nil
        try? launch.stdin.fileHandleForWriting.close()
    }

    private func streamDidExit(token: UInt64, status: Int32) {
        guard let launch = stream, launch.token == token else { return }
        stream = nil
        Self.closePipes(of: launch)
        print("[NativeMediaController] Stream process exited (status \(status)).")
        onListenerTerminated?()
        scheduleRestartAfterExit(lifetime: Date().timeIntervalSince(launch.startedAt))
    }

    private func scheduleRestartAfterExit(lifetime: TimeInterval) {
        guard isListening, suspendReasons.isEmpty else { return }
        guard let delay = restartPolicy.delayAfterExit(lifetime: lifetime) else {
            print("[NativeMediaController] Now playing stream keeps dying; giving up until wake or an explicit restart.")
            return
        }
        restartTask?.cancel()
        restartTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            self.restartTask = nil
            self.launchStream()
        }
    }

    // MARK: - Sleep

    private func installPowerObservers() {
        guard powerObservers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        powerObservers = [
            center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.suspend(.systemSleep) }
            },
            center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.resume(.systemSleep) }
            },
        ]
    }

    private func removePowerObservers() {
        let center = NSWorkspace.shared.notificationCenter
        powerObservers.forEach(center.removeObserver)
        powerObservers.removeAll()
        suspendReasons.removeAll()
    }

    private func suspend(_ reason: SuspendReason) {
        guard isListening, suspendReasons.insert(reason).inserted else { return }
        terminateStream()
    }

    private func resume(_ reason: SuspendReason) {
        guard suspendReasons.remove(reason) != nil else { return }
        restartPolicy.reset()
        launchStream()
    }

    // MARK: - Payload handling

    private func clearActiveSystemMedia(notify: Bool = true) {
        print("[NativeMediaController] Clearing active system media source.")
        activeClients.removeAll()
        currentMergedMetadata.removeAll()
        lastActiveClientKey = nil
        lastTrackIdentity = nil
        lastMediaFingerprint = nil
        resetArtwork()
        if notify {
            onActiveClientsChanged?([:])
            onTrackInfoReceived?(nil)
        }
    }

    private func resetArtwork() {
        currentArtwork = nil
        currentArtworkDigest = nil
        lastTrackChangeAt = nil
        artworkGraceTask?.cancel()
        artworkGraceTask = nil
    }

    private func handleStreamEvent(_ event: NowPlayingStreamParser.Event, token: UInt64) {
        guard stream?.token == token else { return }
        handleTrackUpdate(event.metadata, artwork: event.artwork)
    }

    private func handleTrackUpdate(_ metadata: [String: Any], artwork artworkUpdate: NowPlayingStreamParser.ArtworkUpdate) {
        if metadata.isEmpty, case .unchanged = artworkUpdate {
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
            print("[NativeMediaController] Switching active system source: '\(last)' -> '\(targetKey)'")
            currentMergedMetadata.removeAll()
            lastTrackIdentity = nil
            lastMediaFingerprint = nil
            resetArtwork()
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
        let transportOnly = Self.isTransportOnlyMetadata(metadata) && artworkUpdate.isUnchanged

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

        let now = Date()
        if trackChanged {
            print("[NativeMediaController] System track changed: [\(targetKey)] -> \(title)")
            lastTrackIdentity = mergedIdentity
            if !fingerprint.isEmpty {
                lastMediaFingerprint = fingerprint
            }
            lastTrackChangeAt = now
        }

        var artworkChanged = false
        switch artworkUpdate {
        case .unchanged:
            break
        case .removed:
            if currentArtwork != nil || currentArtworkDigest != nil {
                currentArtwork = nil
                currentArtworkDigest = nil
                artworkChanged = true
            }
        case .image(let digest, let image):
            if digest != currentArtworkDigest {
                currentArtworkDigest = digest
                currentArtwork = image
                artworkChanged = true
            }
        }

        let artworkKnownAbsent = ArtworkGracePolicy.isArtworkKnownAbsent(
            trackChangedAt: lastTrackChangeAt,
            now: now,
            hasArtwork: currentArtwork != nil
        )
        if currentArtwork == nil, !artworkKnownAbsent {
            scheduleArtworkGraceCheck()
        } else {
            artworkGraceTask?.cancel()
            artworkGraceTask = nil
        }

        guard let track = buildTrackInfo(
            from: currentMergedMetadata,
            artwork: currentArtwork,
            artworkKnownAbsent: artworkKnownAbsent
        ) else {
            clearActiveSystemMedia(notify: true)
            return
        }

        let existingClient = activeClients[targetKey]
        let playStateChanged = existingClient?.payload.isPlaying != track.payload.isPlaying
            || existingClient?.payload.playbackRate != track.payload.playbackRate
        let positionChanged = playbackPositionChanged(from: existingClient?.payload, to: track.payload)
        let artworkArrived = track.payload.artwork != nil && existingClient?.payload.artwork == nil
        let absenceSettled = artworkKnownAbsent && existingClient?.payload.artworkKnownAbsent != true

        let shouldNotify = trackChanged || playStateChanged || positionChanged || artworkChanged
            || artworkArrived || absenceSettled

        activeClients = [targetKey: track]

        if shouldNotify {
            onActiveClientsChanged?(activeClients)
            onTrackInfoReceived?(track)
        }
    }

    private func scheduleArtworkGraceCheck() {
        guard artworkGraceTask == nil, let changedAt = lastTrackChangeAt else { return }
        let remaining = max(0, ArtworkGracePolicy.interval - Date().timeIntervalSince(changedAt))
        let identity = lastTrackIdentity
        artworkGraceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(remaining + 0.05))
            guard !Task.isCancelled, let self else { return }
            self.artworkGraceTask = nil
            guard self.isListening, self.lastTrackIdentity == identity,
                  self.currentArtwork == nil, !self.currentMergedMetadata.isEmpty else { return }
            self.handleTrackUpdate([:], artwork: .removed)
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

    nonisolated private func buildTrackInfo(
        from metadata: [String: Any],
        artwork: NSImage?,
        artworkKnownAbsent: Bool
    ) -> TrackInfo? {
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
            artworkMimeType: metadata["artworkMimeType"] as? String,
            artworkKnownAbsent: artworkKnownAbsent
        )
        return TrackInfo(payload: payload)
    }
}