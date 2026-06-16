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

struct TrackInfo {
    struct Payload: Equatable {
        let processIdentifier: Int?
        let bundleIdentifier: String?
        let parentApplicationBundleIdentifier: String?
        let title: String?
        let artist: String?
        let album: String?
        let albumArtist: String?
        let composer: String?
        let genre: String?
        let chapterNumber: NSNumber?
        let totalChapterCount: NSNumber?
        let trackNumber: NSNumber?
        let discNumber: NSNumber?
        let totalTrackCount: NSNumber?
        let queueIndex: NSNumber?
        let totalQueueCount: NSNumber?
        let isPlaying: Bool?
        let durationMicros: Int64?
        let currentElapsedTime: TimeInterval?
        let elapsedTimeMicros: Int64?
        let playbackRate: Float?
        let startTime: NSNumber?
        let timestamp: NSNumber?
        let timestampEpochMicros: Int64?
        let repeatMode: Int?
        let shuffleMode: Int?
        let isLiked: Bool?
        let isBanned: Bool?
        let isInWishList: Bool?
        let isAdvertisement: Bool?
        let isMusicApp: Bool?
        let supportsIsLiked: Bool?
        let supportsIsBanned: Bool?
        let supportsFastForward15Seconds: Bool?
        let supportsRewind15Seconds: Bool?
        let prohibitsSkip: Bool?
        let radioStationIdentifier: String?
        let radioStationHash: String?
        let contentItemIdentifier: String?
        let uniqueIdentifier: String?
        let mediaType: String?
        let artwork: NSImage?
        let artworkMimeType: String?
        
        var calculatedElapsedTime: TimeInterval {
            interpolatedElapsedTime(at: Date())
        }

        func interpolatedElapsedTime(at now: Date) -> TimeInterval {
            guard let anchor = playbackTimingAnchor(isPlayingNow: isPlaying ?? false) else {
                return currentElapsedTime ?? 0
            }
            return anchor.elapsed(at: now)
        }

        // Creates a highly precise timing anchor using absolute OS timestamps
        func playbackTimingAnchor(isPlayingNow: Bool) -> PlaybackTimingAnchor? {
            guard let elapsed = currentElapsedTime else { return nil }

            let rate = isPlayingNow ? Double(playbackRate ?? 1.0) : 0.0
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
    var onTrackInfoReceived: ((TrackInfo?) -> Void)?
    var onActiveClientsChanged: (([String: TrackInfo]) -> Void)?
    var onListenerTerminated: (() -> Void)?
    var onDecodingError: ((String, String?) -> Void)?

    @Published var activeClients: [String: TrackInfo] = [:]

    private let pollQueue = DispatchQueue(label: "com.sapphire.mediaremote.adapter", qos: .userInitiated)
    private var isListening = false
    private var streamProcess: Process?
    private var buffer = Data()
    private var lastKnownTrackInfo: TrackInfo?
    private var lastTrackIdentityByKey: [String: String] = [:]
    private var lastMediaFingerprintByKey: [String: String] = [:]
    private var artworkPrefetchTasks: [String: Task<Void, Never>] = [:]
    private var mergedMetadataByKey: [String: [String: Any]] = [:]
    private var snapshotRefreshTask: Task<Void, Never>?
    private var lastSnapshotRefreshInstant: TimeInterval = 0

    // Cached Paths (Avoids continuous disk hits)
    private static let cachedPaths: (script: String, adapter: String, testClient: String?)? = {
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

    func startListening() {
        guard !isListening else { return }
        isListening = true
        pollQueue.async { [weak self] in
            Task { @MainActor in self?.launchStream() }
        }
    }

    private static func runArtworkFetch(script: String, adapter: String) -> (NSImage?, String?) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        task.arguments = [script, adapter, "get"]
        task.standardError = FileHandle.nullDevice
        let stdout = Pipe()
        task.standardOutput = stdout
        try? task.run()

        let deadline = DispatchTime.now() + 0.35
        while task.isRunning && DispatchTime.now() < deadline {
            Thread.sleep(forTimeInterval: 0.02)
        }
        if task.isRunning { task.terminate() }

        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let base64 = json["artworkData"] as? String,
              let imageData = Data(base64Encoded: base64),
              let image = NSImage(data: imageData) else {
            return (nil, nil)
        }
        return (image, json["artworkMimeType"] as? String)
    }

    func fetchCurrentArtwork() async -> (NSImage?, String?) {
        guard let paths = resolveAdapterPaths() else { return (nil, nil) }
        return await withCheckedContinuation { continuation in
            pollQueue.async {
                let result = Self.runArtworkFetch(script: paths.script, adapter: paths.adapter)
                continuation.resume(returning: result)
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

    func play() { runAdapterCommand(["send", "0"]) }
    func pause() { runAdapterCommand(["send", "1"]) }
    func togglePlayPause() { runAdapterCommand(["send", "2"]) }
    func stopPlayback() { runAdapterCommand(["send", "3"]) }
    func nextTrack() { runAdapterCommand(["send", "4"]) }
    func previousTrack() { runAdapterCommand(["send", "5"]) }
    func toggleShuffle() { runAdapterCommand(["send", "6"]) }
    func toggleRepeat() { runAdapterCommand(["send", "7"]) }
    func beginForwardSeek() { runAdapterCommand(["send", "8"]) }
    func endForwardSeek() { runAdapterCommand(["send", "9"]) }
    func beginBackwardSeek() { runAdapterCommand(["send", "10"]) }
    func endBackwardSeek() { runAdapterCommand(["send", "11"]) }
    func skipBack15Seconds() { runAdapterCommand(["send", "12"]) }
    func skipForward15Seconds() { runAdapterCommand(["send", "13"]) }
    func setTime(seconds: Double) { runAdapterCommand(["seek", String(Int(seconds * 1_000_000))]) }
    func likeTrack(trackID: String?, stationID: String?, stationHash: String?) { runAdapterCommand(["send", "106"]) }

    private func runAdapterCommand(_ args: [String]) {
        pollQueue.async {
            guard let paths = self.resolveAdapterPaths() else { return }
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
        guard let paths = resolveAdapterPaths() else { return }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        // OPTIMIZATION: Passed "--micros" option to enforce microsecond epoch time formats natively
        task.arguments = [paths.script, paths.adapter, "stream", "--debounce=100", "--micros"]
        
        var env = ProcessInfo.processInfo.environment
        env["PERLIO"] = ":unix"
        task.environment = env

        let stdout = Pipe()
        task.standardOutput = stdout
        task.standardError = FileHandle.nullDevice
        streamProcess = task
        buffer.removeAll()

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
                guard let self = self else { return }
                self.onListenerTerminated?()
                if self.isListening {
                    try? await Task.sleep(for: .seconds(2))
                    guard self.isListening else { return }
                    self.launchStream()
                }
            }
        }

        try? task.run()
    }

    private func appendAndProcessBuffer(_ data: Data) {
        buffer.append(data)
        while let range = buffer.range(of: Data("\n".utf8)) {
            let lineData = buffer.subdata(in: buffer.startIndex..<range.lowerBound)
            buffer.removeSubrange(buffer.startIndex..<range.upperBound)
            guard !lineData.isEmpty else { continue }

            guard let parsed = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else { continue }
            let payload: [String: Any]
            if let type = parsed["type"] as? String, type == "data", let inner = parsed["payload"] as? [String: Any] {
                payload = inner
            } else if parsed["type"] == nil {
                payload = parsed
            } else {
                continue
            }

            Task { @MainActor in
                self.handleTrackUpdate(payload)
            }
        }
    }

    private func handleTrackUpdate(_ metadata: [String: Any]) {
        if metadata.isEmpty {
            mergedMetadataByKey.removeAll()
            activeClients.removeAll()
            onActiveClientsChanged?(activeClients)
            lastKnownTrackInfo = nil
            onTrackInfoReceived?(nil)
            return
        }

        guard isListening else { return }

        let key = metadataKey(for: metadata)
        var merged = mergedMetadataByKey[key] ?? [:]
        
        for (entryKey, value) in metadata {
            if entryKey == "artworkData" || entryKey == "artworkMimeType" || entryKey == "_sapphireSnapshot" { continue }
            
            // OPTIMIZATION: Safely prune keys that have been explicitly nullified (diff tracking)
            if value is NSNull {
                merged.removeValue(forKey: entryKey)
            } else if Self.shouldMergeField(key: entryKey, value: value) {
                merged[entryKey] = value
            }
        }
        
        if Self.shouldAcceptIncomingArtwork(from: metadata, for: merged) {
            if let artworkData = metadata["artworkData"] {
                merged["artworkData"] = artworkData
            }
            if let artworkMimeType = metadata["artworkMimeType"] {
                merged["artworkMimeType"] = artworkMimeType
            }
        } else {
            merged.removeValue(forKey: "artworkData")
            merged.removeValue(forKey: "artworkMimeType")
        }
        if let playing = Self.normalizedPlaying(from: metadata) {
            merged["playing"] = playing
        } else if metadata["playbackRate"] != nil {
            let rate = (metadata["playbackRate"] as? NSNumber)?.floatValue ?? 0
            merged["playing"] = rate != 0
        }
        mergedMetadataByKey[key] = merged

        let provisionalClientKey = clientKey(fromMerged: merged)
        let previousClient = activeClients[provisionalClientKey]

        let mergedIdentity = Self.trackIdentity(merged)
        let previousIdentity = lastTrackIdentityByKey[key]
        let fingerprint = Self.mediaFingerprint(merged)
        let previousFingerprint = lastMediaFingerprintByKey[key]
        let transportOnly = Self.isTransportOnlyMetadata(metadata)

        var trackChanged = false
        if !transportOnly {
            if !fingerprint.isEmpty, fingerprint != previousFingerprint {
                trackChanged = true
            } else if fingerprint.isEmpty, mergedIdentity != previousIdentity {
                trackChanged = true
            } else if Self.incomingMetadataDeclaresNewTrack(metadata, previous: previousClient?.payload) {
                trackChanged = true
            }
        }

        if trackChanged {
            lastTrackIdentityByKey[key] = mergedIdentity
            if !fingerprint.isEmpty {
                lastMediaFingerprintByKey[key] = fingerprint
            }
            merged.removeValue(forKey: "artworkData")
            merged.removeValue(forKey: "artworkMimeType")
            mergedMetadataByKey[key] = merged
            
            let streamHasCompleteData = merged["title"] != nil && merged["artist"] != nil && (merged["durationMicros"] != nil || merged["duration"] != nil)
            if !streamHasCompleteData {
                requestImmediateSnapshot(for: key, urgent: true)
            }
        }

        let transportChanged = Self.transportFieldsChanged(in: metadata)

        let previousArtwork = previousClient?.payload.artwork
        let previousTitle = previousClient?.payload.title

        guard let track = buildTrackInfo(
            from: merged,
            trackChanged: trackChanged,
            previousArtwork: previousArtwork,
            previousTitle: previousTitle,
            previousIsPlaying: previousClient?.payload.isPlaying
        ) else { return }

        let clientKey = clientKey(for: track)
        let existingClient = activeClients[clientKey]
        let trackIdentity = Self.trackIdentityFor(track.payload)

        if trackChanged,
           metadata["_sapphireSnapshot"] as? Bool == true,
           track.payload.artwork == nil {
            prefetchArtworkIfNeeded(identity: trackIdentity, clientKey: clientKey, payload: track.payload)
        }

        let playStateChanged = existingClient?.payload.isPlaying != track.payload.isPlaying
            || existingClient?.payload.playbackRate != track.payload.playbackRate
        let positionChanged = playbackPositionChanged(
            from: existingClient?.payload,
            to: track.payload
        )

        activeClients[clientKey] = track

        let activeKeys = activeClients.keys
        if activeKeys.count > 5 { activeClients.removeValue(forKey: activeKeys.first!) }

        let artworkUpdated = metadata["artworkData"] != nil
        let artworkArrived = track.payload.artwork != nil && existingClient?.payload.artwork == nil
        let shouldNotify = trackChanged || playStateChanged || positionChanged || transportChanged || artworkUpdated || artworkArrived
        lastKnownTrackInfo = track
        if shouldNotify {
            onActiveClientsChanged?(activeClients)
            onTrackInfoReceived?(track)
        }
    }

    private func metadataKey(for metadata: [String: Any]) -> String {
        let bundle = metadata["bundleIdentifier"] as? String ?? "unknown"
        let pid = (metadata["processIdentifier"] as? NSNumber)?.intValue
            ?? metadata["processIdentifier"] as? Int
            ?? 0
        return "\(bundle):\(pid)"
    }

    private func clientKey(fromMerged metadata: [String: Any]) -> String {
        let bundle = metadata["bundleIdentifier"] as? String ?? "unknown"
        let pid = (metadata["processIdentifier"] as? NSNumber)?.intValue
            ?? metadata["processIdentifier"] as? Int
            ?? 0
        return "\(bundle):\(pid)"
    }

    private func playbackPositionChanged(from previous: TrackInfo.Payload?, to current: TrackInfo.Payload) -> Bool {
        guard let previousElapsed = previous?.currentElapsedTime,
              let currentElapsed = current.currentElapsedTime else {
            return previous?.currentElapsedTime != current.currentElapsedTime
        }
        return abs(previousElapsed - currentElapsed) >= 0.5
    }

    func trimArtworkCache(keeping identity: String?) {
        artworkPrefetchTasks.values.forEach { $0.cancel() }
        artworkPrefetchTasks.removeAll()

        mergedMetadataByKey.removeAll(keepingCapacity: false)
        lastTrackIdentityByKey.removeAll(keepingCapacity: false)
        lastMediaFingerprintByKey.removeAll(keepingCapacity: false)

        activeClients = activeClients.mapValues { track in
            TrackInfo(payload: track.payload.updatingArtwork(nil, mimeType: nil))
        }
    }

    private func requestImmediateSnapshot(for metadataKey: String, urgent: Bool = false) {
        if !urgent {
            let now = Date().timeIntervalSinceReferenceDate
            guard now - lastSnapshotRefreshInstant > 0.08 else { return }
            lastSnapshotRefreshInstant = now
        }

        snapshotRefreshTask?.cancel()
        snapshotRefreshTask = Task { @MainActor in
            let snapshot = await self.fetchMetadataSnapshot()
            guard !Task.isCancelled, let snapshot = snapshot, !snapshot.isEmpty else { return }
            var tagged = snapshot
            tagged["_sapphireSnapshot"] = true
            self.handleTrackUpdate(tagged)
        }
    }

    private func fetchMetadataSnapshot() async -> [String: Any]? {
        await withCheckedContinuation { continuation in
            pollQueue.async {
                continuation.resume(returning: Self.fetchMetadataSnapshotSync(paths: self.resolveAdapterPaths()))
            }
        }
    }

    nonisolated private static func fetchMetadataSnapshotSync(paths: (script: String, adapter: String, testClient: String?)?) -> [String: Any]? {
        guard let paths = paths else { return nil }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        task.arguments = [paths.script, paths.adapter, "get", "--micros"]
        task.standardError = FileHandle.nullDevice
        let stdout = Pipe()
        task.standardOutput = stdout
        try? task.run()

        let deadline = DispatchTime.now() + 0.35
        while task.isRunning && DispatchTime.now() < deadline {
            Thread.sleep(forTimeInterval: 0.02)
        }
        if task.isRunning { task.terminate() }

        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        guard let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let type = parsed["type"] as? String, type == "data", let inner = parsed["payload"] as? [String: Any] {
            return inner
        }
        return parsed["type"] == nil ? parsed : nil
    }

    nonisolated private static func normalizedPlaying(from metadata: [String: Any]) -> Bool? {
        if let playing = metadata["playing"] as? Bool { return playing }
        if let playing = metadata["playing"] as? NSNumber { return playing.boolValue }
        if let rate = (metadata["playbackRate"] as? NSNumber)?.floatValue { return rate != 0 }
        return nil
    }

    nonisolated private static func transportFieldsChanged(in metadata: [String: Any]) -> Bool {
        metadata["playing"] != nil || metadata["playbackRate"] != nil
    }

    private func prefetchArtworkIfNeeded(identity: String, clientKey: String, payload: TrackInfo.Payload) {
        artworkPrefetchTasks[identity]?.cancel()
        artworkPrefetchTasks[identity] = Task { @MainActor in
            defer { self.artworkPrefetchTasks[identity] = nil }
            let (image, mimeType) = await self.fetchArtworkForTrack(
                expectedIdentity: identity,
                title: payload.title,
                artist: payload.artist,
                album: payload.album
            )
            guard !Task.isCancelled, let image = image else { return }

            guard let existing = self.activeClients[clientKey] else { return }
            guard Self.trackIdentityFor(existing.payload) == identity else { return }

            let updatedPayload = existing.payload.updatingArtwork(image, mimeType: mimeType)
            let updated = TrackInfo(payload: updatedPayload)
            self.activeClients[clientKey] = updated
            self.lastKnownTrackInfo = updated
            self.onActiveClientsChanged?(self.activeClients)
            self.onTrackInfoReceived?(updated)
        }
    }

    // Directly fetch artwork from the adapter with zero caching
    func fetchArtworkForTrack(
        expectedIdentity: String,
        title: String?,
        artist: String?,
        album: String?
    ) async -> (NSImage?, String?) {
        guard let paths = resolveAdapterPaths() else { return (nil, nil) }
        return await withCheckedContinuation { continuation in
            pollQueue.async {
                let result = Self.runValidatedArtworkFetch(
                    script: paths.script,
                    adapter: paths.adapter,
                    expectedIdentity: expectedIdentity,
                    expectedTitle: title,
                    expectedArtist: artist,
                    expectedAlbum: album
                )
                continuation.resume(returning: result)
            }
        }
    }

    nonisolated private static func runValidatedArtworkFetch(
        script: String,
        adapter: String,
        expectedIdentity: String,
        expectedTitle: String?,
        expectedArtist: String?,
        expectedAlbum: String?
    ) -> (NSImage?, String?) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        task.arguments = [script, adapter, "get"]
        task.standardError = FileHandle.nullDevice
        let stdout = Pipe()
        task.standardOutput = stdout
        try? task.run()

        let deadline = DispatchTime.now() + 0.35
        while task.isRunning && DispatchTime.now() < deadline {
            Thread.sleep(forTimeInterval: 0.02)
        }
        if task.isRunning { task.terminate() }

        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              artworkMatchesTrack(
                metadata: json,
                expectedIdentity: expectedIdentity,
                expectedTitle: expectedTitle,
                expectedArtist: expectedArtist,
                expectedAlbum: expectedAlbum
              ),
              let base64 = json["artworkData"] as? String,
              let imageData = Data(base64Encoded: base64),
              let image = NSImage(data: imageData) else {
            return (nil, nil)
        }
        return (image, json["artworkMimeType"] as? String)
    }

    nonisolated private static func shouldAcceptIncomingArtwork(from metadata: [String: Any], for merged: [String: Any]) -> Bool {
        guard metadata["artworkData"] != nil else { return false }
        return artworkMatchesTrack(
            metadata: metadata,
            expectedIdentity: trackIdentity(merged),
            expectedTitle: merged["title"] as? String,
            expectedArtist: merged["artist"] as? String,
            expectedAlbum: merged["album"] as? String
        )
    }

    nonisolated private static func artworkMatchesTrack(
        metadata: [String: Any],
        expectedIdentity: String,
        expectedTitle: String?,
        expectedArtist: String?,
        expectedAlbum: String?
    ) -> Bool {
        let responseIdentity = trackIdentity(metadata)
        if responseIdentity == expectedIdentity { return true }

        guard let title = metadata["title"] as? String, !title.isEmpty,
              title == (expectedTitle ?? "") else { return false }

        if let expectedArtist, !expectedArtist.isEmpty {
            let responseArtist = metadata["artist"] as? String ?? ""
            if responseArtist != expectedArtist { return false }
        }

        if let expectedAlbum, !expectedAlbum.isEmpty {
            let responseAlbum = metadata["album"] as? String ?? ""
            if responseAlbum != expectedAlbum { return false }
        }

        return true
    }

    nonisolated private static func trackIdentity(_ m: [String: Any]) -> String {
        if let id = m["contentItemIdentifier"] as? String, !id.isEmpty { return "cid:\(id)" }
        if let id = m["uniqueIdentifier"] as? String, !id.isEmpty { return "uid:\(id)" }
        let fingerprint = mediaFingerprint(m)
        return fingerprint.isEmpty ? "unknown" : "fp:\(fingerprint)"
    }

    nonisolated private static func mediaFingerprint(_ m: [String: Any]) -> String {
        [m["title"] as? String, m["artist"] as? String, m["album"] as? String]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "|")
            .lowercased()
    }

    nonisolated private static func isEmptyMergeValue(_ value: Any) -> Bool {
        if value is NSNull { return true }
        if let string = value as? String {
            return string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return false
    }

    nonisolated private static func shouldMergeField(key: String, value: Any) -> Bool {
        let identityFields: Set<String> = [
            "title", "artist", "album", "albumArtist",
            "contentItemIdentifier", "uniqueIdentifier"
        ]
        if identityFields.contains(key), isEmptyMergeValue(value) { return false }
        return true
    }

    nonisolated private static func isTransportOnlyMetadata(_ metadata: [String: Any]) -> Bool {
        let transportKeys: Set<String> = [
            "playing", "playbackRate",
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

    nonisolated private static func incomingMetadataDeclaresNewTrack(
        _ metadata: [String: Any],
        previous: TrackInfo.Payload?
    ) -> Bool {
        if let incomingID = metadata["contentItemIdentifier"] as? String, !incomingID.isEmpty,
           incomingID != previous?.contentItemIdentifier {
            return true
        }
        if let incomingID = metadata["uniqueIdentifier"] as? String, !incomingID.isEmpty,
           incomingID != previous?.uniqueIdentifier {
            return true
        }
        if let incomingTitle = metadata["title"] as? String, !incomingTitle.isEmpty,
           incomingTitle != previous?.title {
            return true
        }
        return false
    }

    private static func trackIdentityFor(_ payload: TrackInfo.Payload) -> String {
        if let id = payload.contentItemIdentifier, !id.isEmpty { return "cid:\(id)" }
        if let id = payload.uniqueIdentifier, !id.isEmpty { return "uid:\(id)" }
        let fingerprint = mediaFingerprint(payload)
        return fingerprint.isEmpty ? "unknown" : "fp:\(fingerprint)"
    }

    nonisolated private static func mediaFingerprint(_ payload: TrackInfo.Payload) -> String {
        [payload.title, payload.artist, payload.album]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "|")
            .lowercased()
    }

    nonisolated private func resolveAdapterPaths() -> (script: String, adapter: String, testClient: String?)? {
        return Self.cachedPaths
    }

    nonisolated private func clientKey(for track: TrackInfo) -> String {
        let bundle = track.payload.bundleIdentifier ?? "unknown"
        let pid = track.payload.processIdentifier.map(String.init) ?? "0"
        return "\(bundle):\(pid)"
    }

    nonisolated private func buildTrackInfo(
        from metadata: [String: Any],
        trackChanged: Bool,
        previousArtwork: NSImage?,
        previousTitle: String?,
        previousIsPlaying: Bool?
    ) -> TrackInfo? {
        let title = metadata["title"] as? String
        let artist = metadata["artist"] as? String
        let bundleId = metadata["bundleIdentifier"] as? String
        
        let hasIdentity = (title?.isEmpty == false) || (bundleId?.isEmpty == false)
        guard hasIdentity else { return nil }

        let durationMicros: Int64?
        if let micros = (metadata["durationMicros"] as? NSNumber)?.int64Value, micros > 0 {
            durationMicros = micros
        } else if let d = (metadata["duration"] as? NSNumber)?.doubleValue, d > 0 {
            durationMicros = Int64(d * 1_000_000)
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
        let isPlaying = Self.normalizedPlaying(from: metadata) ?? previousIsPlaying

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

        var artwork: NSImage?
        
        // Directly decode base64
        if let base64 = metadata["artworkData"] as? String,
           let data = Data(base64Encoded: base64) {
            artwork = NSImage(data: data)
        } else if !trackChanged, let previousArtwork, previousTitle == title {
            artwork = previousArtwork
        }

        let payload = TrackInfo.Payload(
            processIdentifier: metadata["processIdentifier"] as? Int,
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
            elapsedTimeMicros: elapsed.map { Int64($0 * 1_000_000) },
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

// MARK: - TrackInfo.Payload Extension
extension TrackInfo.Payload {
    func updatingArtwork(_ artwork: NSImage?, mimeType: String?) -> TrackInfo.Payload {
        TrackInfo.Payload(
            processIdentifier: processIdentifier,
            bundleIdentifier: bundleIdentifier,
            parentApplicationBundleIdentifier: parentApplicationBundleIdentifier,
            title: title,
            artist: artist,
            album: album,
            albumArtist: albumArtist,
            composer: composer,
            genre: genre,
            chapterNumber: chapterNumber,
            totalChapterCount: totalChapterCount,
            trackNumber: trackNumber,
            discNumber: discNumber,
            totalTrackCount: totalTrackCount,
            queueIndex: queueIndex,
            totalQueueCount: totalQueueCount,
            isPlaying: isPlaying,
            durationMicros: durationMicros,
            currentElapsedTime: currentElapsedTime,
            elapsedTimeMicros: elapsedTimeMicros,
            playbackRate: playbackRate,
            startTime: startTime,
            timestamp: timestamp,
            timestampEpochMicros: timestampEpochMicros,
            repeatMode: repeatMode,
            shuffleMode: shuffleMode,
            isLiked: isLiked,
            isBanned: isBanned,
            isInWishList: isLiked,
            isAdvertisement: isAdvertisement,
            isMusicApp: isMusicApp,
            supportsIsLiked: supportsIsLiked,
            supportsIsBanned: supportsIsBanned,
            supportsFastForward15Seconds: supportsFastForward15Seconds,
            supportsRewind15Seconds: supportsRewind15Seconds,
            prohibitsSkip: prohibitsSkip,
            radioStationIdentifier: radioStationIdentifier,
            radioStationHash: radioStationHash,
            contentItemIdentifier: contentItemIdentifier,
            uniqueIdentifier: uniqueIdentifier,
            mediaType: mediaType,
            artwork: artwork,
            artworkMimeType: mimeType
        )
    }
}
