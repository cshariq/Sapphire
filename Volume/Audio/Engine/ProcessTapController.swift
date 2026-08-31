//
//  ProcessTapController.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-21

import AudioToolbox
import Foundation
import os

// MARK: - Threading Model

final class ProcessTapController: ProcessTapControlling {
    let app: AudioApp
    private let logger: Logger
    private let queue = DispatchQueue(label: "ProcessTapController", qos: .userInitiated)

    private weak var deviceMonitor: AudioDeviceMonitor?
    private var preferredTapSourceDeviceUID: String?

    var tapSourceDeviceUID: String? { preferredTapSourceDeviceUID }

    // MARK: - RT-Safe State (nonisolated(unsafe) for lock-free audio thread access)

    private nonisolated(unsafe) var _volume: Float = 1.0
    private nonisolated(unsafe) var _primaryCurrentVolume: Float = 1.0
    private nonisolated(unsafe) var _secondaryCurrentVolume: Float = 1.0
    private nonisolated(unsafe) var _forceSilence: Bool = false
    private nonisolated(unsafe) var _isMuted: Bool = false
    private nonisolated(unsafe) var _peakLevel: Float = 0.0
    private nonisolated(unsafe) var _secondaryPeakLevel: Float = 0.0
    private nonisolated(unsafe) var _currentDeviceVolume: Float = 1.0
    private nonisolated(unsafe) var _isDeviceMuted: Bool = false
    private nonisolated(unsafe) var _primaryPreferredStereoLeftChannel: Int = 0
    private nonisolated(unsafe) var _primaryPreferredStereoRightChannel: Int = 1
    private nonisolated(unsafe) var _secondaryPreferredStereoLeftChannel: Int = 0
    private nonisolated(unsafe) var _secondaryPreferredStereoRightChannel: Int = 1
    private nonisolated(unsafe) var _lastRenderHostTime: UInt64 = 0
    private nonisolated(unsafe) var _activationHostTime: UInt64 = 0
    private nonisolated(unsafe) var _hasRenderedAudio: Bool = false

    private nonisolated(unsafe) var _primaryCallbackID: UInt32 = 0
    private nonisolated(unsafe) var _secondaryCallbackID: UInt32 = 0
    private var nextCallbackID: UInt32 = 0

    private nonisolated(unsafe) var crossfadeState = CrossfadeState()

    // MARK: - Non-RT State (modified only from main thread)

    private let levelSmoothingFactor: Float = 0.3
    private nonisolated(unsafe) var rampCoefficient: Float = 0.0007
    private nonisolated(unsafe) var secondaryRampCoefficient: Float = 0.0007
    private nonisolated(unsafe) var eqProcessor: EQProcessor?
    private nonisolated(unsafe) var autoEQProcessor: AutoEQProcessor?
    private nonisolated(unsafe) var loudnessCompensator: LoudnessCompensator?
    private nonisolated(unsafe) var loudnessEqualizerProcessor: LoudnessEqualizer?
    private var _lastLoudnessVolume: Float = 1.0
    private nonisolated(unsafe) var secondaryEQProcessor: EQProcessor?
    private nonisolated(unsafe) var secondaryAutoEQProcessor: AutoEQProcessor?
    private nonisolated(unsafe) var secondaryLoudnessCompensator: LoudnessCompensator?
    private nonisolated(unsafe) var secondaryLoudnessEqualizerProcessor: LoudnessEqualizer?

    private var targetDeviceUIDs: [String]
    private(set) var currentDeviceUIDs: [String] = []

    var currentDeviceUID: String? { currentDeviceUIDs.first }

    private var primaryResources = TapResources()
    private var activated = false

    private var secondaryResources = TapResources()

    private var isSwitching = false
    private var crossfadeTask: Task<Void, Error>?
    private var didLogEQBypassForMultichannel = false

    // MARK: - Public Properties

    var audioLevel: Float { crossfadeState.isActive ? max(_peakLevel, _secondaryPeakLevel) : _peakLevel }

    private static let hostTimeNanosScale: Double = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        guard info.denom != 0 else { return 1.0 }
        return Double(info.numer) / Double(info.denom)
    }()

    func hasRecentAudioCallback(within seconds: Double) -> Bool {
        let last = _lastRenderHostTime
        guard last != 0 else { return false }
        let now = mach_absolute_time()
        let deltaNanos = Double(now &- last) * Self.hostTimeNanosScale
        return deltaNanos <= (seconds * 1_000_000_000.0)
    }

    func isHealthCheckEligible(minActiveSeconds: Double) -> Bool {
        guard _hasRenderedAudio else { return false }
        let started = _activationHostTime
        guard started != 0 else { return false }
        let deltaNanos = Double(mach_absolute_time() &- started) * Self.hostTimeNanosScale
        return deltaNanos >= (minActiveSeconds * 1_000_000_000.0)
    }

    var currentDeviceVolume: Float {
        get { _currentDeviceVolume }
        set { _currentDeviceVolume = newValue }
    }

    var isDeviceMuted: Bool {
        get { _isDeviceMuted }
        set { _isDeviceMuted = newValue }
    }

    var volume: Float {
        get { _volume }
        set { _volume = newValue }
    }

    var isMuted: Bool {
        get { _isMuted }
        set { _isMuted = newValue }
    }

    // MARK: - Initialization

    init(
        app: AudioApp,
        targetDeviceUIDs: [String],
        deviceMonitor: AudioDeviceMonitor? = nil,
        preferredTapSourceDeviceUID: String? = nil
    ) {
        precondition(!targetDeviceUIDs.isEmpty, "Must have at least one target device")
        self.app = app
        self.targetDeviceUIDs = targetDeviceUIDs
        self.deviceMonitor = deviceMonitor
        self.preferredTapSourceDeviceUID = preferredTapSourceDeviceUID
        self.logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.cshariq.sapphire", category: "ProcessTapController(\(app.name))")
    }

    convenience init(
        app: AudioApp,
        targetDeviceUID: String,
        deviceMonitor: AudioDeviceMonitor? = nil,
        preferredTapSourceDeviceUID: String? = nil
    ) {
        self.init(
            app: app,
            targetDeviceUIDs: [targetDeviceUID],
            deviceMonitor: deviceMonitor,
            preferredTapSourceDeviceUID: preferredTapSourceDeviceUID
        )
    }

    // MARK: - Public Methods

    func updateEQSettings(_ settings: EQSettings) {
        eqProcessor?.updateSettings(settings)
        secondaryEQProcessor?.updateSettings(settings)
    }

    func updateAutoEQProfile(_ profile: AutoEQProfile?) {
        autoEQProcessor?.updateProfile(profile)
        secondaryAutoEQProcessor?.updateProfile(profile)
    }

    func setAutoEQPreampEnabled(_ enabled: Bool) {
        autoEQProcessor?.setPreampEnabled(enabled)
        secondaryAutoEQProcessor?.setPreampEnabled(enabled)
    }

    func updateLoudnessCompensation(volume: Float, enabled: Bool) {
        _lastLoudnessVolume = volume
        if enabled {
            loudnessCompensator?.updateForVolume(volume)
            secondaryLoudnessCompensator?.updateForVolume(volume)
        } else {
            loudnessCompensator?.setEnabled(false)
            secondaryLoudnessCompensator?.setEnabled(false)
        }
    }

    func updateLoudnessEqualization(_ settings: LoudnessEqualizerSettings) {
        if let sampleRate = try? primaryResources.aggregateDeviceID.readNominalSampleRate() {
            let newProcessor = LoudnessEqualizer(settings: settings, sampleRate: Float(sampleRate))
            let old = loudnessEqualizerProcessor
            loudnessEqualizerProcessor = newProcessor
            if let old {
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.5) { _ = old }
            }
        }
        if let secondary = secondaryLoudnessEqualizerProcessor,
           let sampleRate = try? secondaryResources.aggregateDeviceID.readNominalSampleRate() {
            let newSecondary = LoudnessEqualizer(settings: settings, sampleRate: Float(sampleRate))
            secondaryLoudnessEqualizerProcessor = newSecondary
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.5) { _ = secondary }
        }
    }

    // MARK: - Multi-Device Aggregate Configuration

    private func buildAggregateDescription(outputUIDs: [String], tapUUID: UUID, name: String) -> [String: Any] {
        precondition(!outputUIDs.isEmpty, "Must have at least one output device")

        var subDevices: [[String: Any]] = []
        for (index, deviceUID) in outputUIDs.enumerated() {
            subDevices.append([
                kAudioSubDeviceUIDKey: deviceUID,
                kAudioSubDeviceDriftCompensationKey: index > 0
            ])
        }

        let clockDeviceUID = outputUIDs[0]

        return [
            kAudioAggregateDeviceNameKey: name,
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: clockDeviceUID,
            kAudioAggregateDeviceClockDeviceKey: clockDeviceUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: true,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: subDevices,
            kAudioAggregateDeviceTapListKey: [
                [
                    kAudioSubTapDriftCompensationKey: true,
                    kAudioSubTapUIDKey: tapUUID.uuidString
                ]
            ]
        ]
    }

    private func preferredStereoChannels(for deviceUID: String?) -> (left: Int, right: Int) {
        guard let deviceUID, let deviceID = audioDeviceID(for: deviceUID) else {
            return (0, 1)
        }
        return deviceID.preferredStereoChannelIndices()
    }

    private func outputStreamIndex(for deviceUID: String?) -> UInt? {
        guard let deviceUID, let deviceID = audioDeviceID(for: deviceUID) else {
            return nil
        }
        return try? deviceID.firstOutputStreamIndex()
    }

    private func audioDeviceID(for deviceUID: String) -> AudioDeviceID? {
        if let monitored = deviceMonitor?.device(for: deviceUID)?.id {
            return monitored
        }

        guard let deviceIDs = try? AudioObjectID.readDeviceList() else { return nil }
        for id in deviceIDs {
            if (try? id.readDeviceUID()) == deviceUID {
                return id
            }
        }
        return nil
    }

    private func maybeLogEQBypass(for tapID: AudioObjectID) {
        guard !didLogEQBypassForMultichannel else { return }
        guard let asbd = try? tapID.readAudioTapStreamBasicDescription() else { return }
        guard asbd.mChannelsPerFrame != 2 else { return }

        didLogEQBypassForMultichannel = true
        logger.info("EQ processing is stereo-only and will be bypassed for tap format with \(asbd.mChannelsPerFrame) channels.")
    }

    private func createProcessTap(preferredDeviceUID: String?) throws -> (description: CATapDescription, tapID: AudioObjectID) {
        var lastError: OSStatus = noErr

        if let deviceUID = preferredDeviceUID {
            if let outputStream = outputStreamIndex(for: deviceUID) {
                let streamTap = CATapDescription(processes: app.processObjectIDs, deviceUID: deviceUID, stream: outputStream)
                streamTap.uuid = UUID()
                streamTap.muteBehavior = .mutedWhenTapped
                streamTap.isPrivate = true

                var tapID: AudioObjectID = .unknown
                let err = AudioHardwareCreateProcessTap(streamTap, &tapID)
                if err == noErr {
                    logger.info("Created stream-specific tap for device \(deviceUID, privacy: .public) (stream \(outputStream))")
                    maybeLogEQBypass(for: tapID)
                    return (streamTap, tapID)
                }

                lastError = err
                logger.warning("Stream-specific tap creation failed for device \(deviceUID, privacy: .public) stream \(outputStream): \(err). Falling back to stereo mixdown.")
            } else {
                logger.warning("Could not resolve an output stream index for device \(deviceUID, privacy: .public). Falling back to stereo mixdown.")
            }
        }

        let mixdownTap = CATapDescription(stereoMixdownOfProcesses: app.processObjectIDs)
        mixdownTap.uuid = UUID()
        mixdownTap.muteBehavior = .mutedWhenTapped
        mixdownTap.isPrivate = true

        var mixdownTapID: AudioObjectID = .unknown
        let mixdownErr = AudioHardwareCreateProcessTap(mixdownTap, &mixdownTapID)
        guard mixdownErr == noErr else {
            throw NSError(
                domain: NSOSStatusErrorDomain,
                code: Int(mixdownErr),
                userInfo: [
                    NSLocalizedDescriptionKey: "Failed to create process tap (stream-specific err: \(lastError), mixdown err: \(mixdownErr))"
                ]
            )
        }

        if preferredDeviceUID != nil {
            logger.info("Using stereo mixdown tap fallback")
        }
        maybeLogEQBypass(for: mixdownTapID)
        return (mixdownTap, mixdownTapID)
    }

    func activate() throws {
        guard !activated else { return }

        logger.debug("Activating tap for \(self.app.name)")

        _lastRenderHostTime = 0
        _activationHostTime = mach_absolute_time()
        _hasRenderedAudio = false

        let (tapDesc, tapID) = try createProcessTap(preferredDeviceUID: preferredTapSourceDeviceUID)
        primaryResources.tapDescription = tapDesc
        let preferred = preferredStereoChannels(for: targetDeviceUIDs.first)
        _primaryPreferredStereoLeftChannel = preferred.left
        _primaryPreferredStereoRightChannel = preferred.right

        primaryResources.tapID = tapID
        logger.debug("Created process tap #\(tapID)")

        let description = buildAggregateDescription(
            outputUIDs: targetDeviceUIDs,
            tapUUID: tapDesc.uuid,
            name: "Sapphire-\(app.id)"
        )

        var err: OSStatus
        var aggID: AudioObjectID = .unknown
        err = AudioHardwareCreateAggregateDevice(description as CFDictionary, &aggID)
        guard err == noErr else {
            cleanupPartialActivation()
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(err), userInfo: [NSLocalizedDescriptionKey: "Failed to create aggregate device: \(err)"])
        }
        primaryResources.aggregateDeviceID = aggID
        CrashGuard.trackDevice(aggID)

        guard primaryResources.aggregateDeviceID.waitUntilReady(timeout: 2.0) else {
            cleanupPartialActivation()
            throw NSError(domain: "ProcessTapController", code: -1, userInfo: [NSLocalizedDescriptionKey: "Aggregate device not ready within timeout"])
        }

        logger.debug("Created aggregate device #\(self.primaryResources.aggregateDeviceID)")

        let sampleRate: Float64
        if let deviceSampleRate = try? primaryResources.aggregateDeviceID.readNominalSampleRate() {
            sampleRate = deviceSampleRate
            logger.info("Device sample rate: \(sampleRate) Hz")
        } else {
            sampleRate = 48000
            logger.warning("Failed to read sample rate, using default: \(sampleRate) Hz")
        }
        let rampTimeSeconds: Float = 0.030
        rampCoefficient = 1 - exp(-1 / (Float(sampleRate) * rampTimeSeconds))
        logger.debug("Ramp coefficient: \(self.rampCoefficient)")

        eqProcessor = EQProcessor(sampleRate: sampleRate)
        autoEQProcessor = AutoEQProcessor(sampleRate: sampleRate)
        loudnessEqualizerProcessor = LoudnessEqualizer(settings: LoudnessEqualizerSettings(), sampleRate: Float(sampleRate))
        loudnessCompensator = LoudnessCompensator(sampleRate: sampleRate)

        nextCallbackID += 1
        _primaryCallbackID = nextCallbackID
        let activateCallbackID = nextCallbackID
        err = AudioDeviceCreateIOProcIDWithBlock(&primaryResources.deviceProcID, primaryResources.aggregateDeviceID, queue) { [weak self] _, inInputData, _, outOutputData, _ in
            guard let self else {
                let outputs = UnsafeMutableAudioBufferListPointer(outOutputData)
                for buf in outputs {
                    if let data = buf.mData { memset(data, 0, Int(buf.mDataByteSize)) }
                }
                return
            }
            self.processAudioCallback(inInputData, to: outOutputData, callbackID: activateCallbackID)
        }
        guard err == noErr else {
            cleanupPartialActivation()
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(err), userInfo: [NSLocalizedDescriptionKey: "Failed to create IO proc: \(err)"])
        }

        err = AudioDeviceStart(primaryResources.aggregateDeviceID, primaryResources.deviceProcID)
        guard err == noErr else {
            cleanupPartialActivation()
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(err), userInfo: [NSLocalizedDescriptionKey: "Failed to start device: \(err)"])
        }

        _primaryCurrentVolume = _volume

        currentDeviceUIDs = targetDeviceUIDs

        activated = true
        logger.info("Tap activated for \(self.app.name) on \(self.targetDeviceUIDs.count) device(s)")
    }

    func switchDevice(to newDeviceUID: String, preferredTapSourceDeviceUID: String? = nil, sourceDeviceDead: Bool = false) async throws {
        try await updateDevices(to: [newDeviceUID], preferredTapSourceDeviceUID: preferredTapSourceDeviceUID, sourceDeviceDead: sourceDeviceDead)
    }

    func updateDevices(to newDeviceUIDs: [String], preferredTapSourceDeviceUID: String? = nil, sourceDeviceDead: Bool = false) async throws {
        precondition(!newDeviceUIDs.isEmpty, "Must have at least one target device")
        self.preferredTapSourceDeviceUID = preferredTapSourceDeviceUID

        guard activated else {
            targetDeviceUIDs = newDeviceUIDs
            return
        }

        guard newDeviceUIDs != currentDeviceUIDs else { return }

        let startTime = CFAbsoluteTimeGetCurrent()
        logger.info("[UPDATE] Switching \(self.app.name) to \(newDeviceUIDs.count) device(s)\(sourceDeviceDead ? " (source dead)" : "")")

        let primaryDeviceUID = newDeviceUIDs[0]

        if sourceDeviceDead {
            guard primaryResources.tapDescription != nil else {
                throw CrossfadeError.noTapDescription
            }
            try await performDestructiveDeviceSwitch(to: primaryDeviceUID, allDeviceUIDs: newDeviceUIDs, sourceAlreadySilent: true)
        } else {
            crossfadeTask?.cancel()
            crossfadeTask = Task {
                try await performCrossfadeSwitch(to: primaryDeviceUID, allDeviceUIDs: newDeviceUIDs)
            }
            do {
                try await crossfadeTask!.value
            } catch is CancellationError {
                logger.info("[UPDATE] Crossfade cancelled by invalidate()")
                return
            } catch {
                logger.warning("[UPDATE] Crossfade failed: \(error.localizedDescription), using fallback")
                guard primaryResources.tapDescription != nil else {
                    throw CrossfadeError.noTapDescription
                }
                try await performDestructiveDeviceSwitch(to: primaryDeviceUID, allDeviceUIDs: newDeviceUIDs)
            }
            crossfadeTask = nil
        }

        targetDeviceUIDs = newDeviceUIDs
        currentDeviceUIDs = newDeviceUIDs

        let endTime = CFAbsoluteTimeGetCurrent()
        logger.info("[UPDATE] === END === Total time: \((endTime - startTime) * 1000)ms")
    }

    func refreshTapSource(_ preferredDeviceUID: String?) async throws {
        let oldPreferred = self.preferredTapSourceDeviceUID
        self.preferredTapSourceDeviceUID = preferredDeviceUID
        guard activated, let primaryUID = currentDeviceUIDs.first else { return }
        guard oldPreferred != preferredDeviceUID else { return }

        let allUIDs = currentDeviceUIDs
        logger.info("[REFRESH] Tap source changing for \(self.app.name): \(oldPreferred ?? "mixdown") → \(preferredDeviceUID ?? "mixdown")")

        crossfadeTask?.cancel()
        crossfadeTask = Task {
            try await performCrossfadeSwitch(to: primaryUID, allDeviceUIDs: allUIDs)
        }
        do {
            try await crossfadeTask!.value
        } catch is CancellationError {
            logger.info("[REFRESH] Tap source refresh cancelled")
            return
        } catch {
            logger.warning("[REFRESH] Crossfade failed, using destructive switch: \(error.localizedDescription)")
            guard primaryResources.tapDescription != nil else {
                throw CrossfadeError.noTapDescription
            }
            try await performDestructiveDeviceSwitch(to: primaryUID, allDeviceUIDs: allUIDs)
        }
        crossfadeTask = nil

        logger.info("[REFRESH] Tap source refresh complete for \(self.app.name)")
    }

    private var _invalidating = false
    func invalidate() {
        guard beginInvalidation() else { return }
        defer { endInvalidation() }

        secondaryResources.destroyAsync()
        primaryResources.destroyAsync()

        logger.info("Tap invalidated for \(self.app.name)")
    }

    func invalidateAsync() async {
        guard beginInvalidation() else { return }
        defer { endInvalidation() }

        await withCheckedContinuation { continuation in
            secondaryResources.destroyAsync(on: .global(qos: .userInitiated)) {
                continuation.resume()
            }
        }
        await withCheckedContinuation { continuation in
            primaryResources.destroyAsync(on: .global(qos: .userInitiated)) {
                continuation.resume()
            }
        }

        logger.info("Tap invalidated (async) for \(self.app.name)")
    }

    // MARK: - Invalidation Helpers

    private func beginInvalidation() -> Bool {
        guard activated, !_invalidating else { return false }
        _invalidating = true
        activated = false

        _lastRenderHostTime = 0
        _activationHostTime = 0
        _hasRenderedAudio = false

        crossfadeTask?.cancel()
        crossfadeTask = nil

        logger.debug("Invalidating tap for \(self.app.name)")

        crossfadeState.complete()
        _primaryCallbackID = 0
        _secondaryCallbackID = 0

        return true
    }

    private func endInvalidation() {
        secondaryEQProcessor = nil
        secondaryAutoEQProcessor = nil
        secondaryLoudnessCompensator = nil
        secondaryLoudnessEqualizerProcessor = nil
        _invalidating = false
    }

    deinit {
        invalidate()
    }

    // MARK: - Crossfade Operations

    private func performCrossfadeSwitch(to primaryDeviceUID: String, allDeviceUIDs: [String]? = nil) async throws {
        let deviceUIDs = allDeviceUIDs ?? [primaryDeviceUID]

        if isSwitching {
            logger.warning("[CROSSFADE] Re-entrant switch detected — tearing down in-progress secondary")
            cleanupSecondaryTap()
            crossfadeState.complete()
        }
        isSwitching = true
        defer { isSwitching = false }

        logger.info("[CROSSFADE] Step 1: Reading device volumes for compensation")

        var isBluetoothDestination = false
        if let destDevice = deviceMonitor?.device(for: primaryDeviceUID) {
            let transport = destDevice.id.readTransportType()
            isBluetoothDestination = (transport == .bluetooth || transport == .bluetoothLE)
            logger.debug("[CROSSFADE] Destination device: BT=\(isBluetoothDestination)")
        }

        logger.info("[CROSSFADE] Step 2: Preparing crossfade state")

        crossfadeState.beginWarmup()

        logger.info("[CROSSFADE] Step 3: Creating secondary tap for \(deviceUIDs.count) device(s)")
        try createSecondaryTap(for: deviceUIDs)

        var crossfadeCompleted = false
        defer {
            if !crossfadeCompleted {
                logger.warning("[CROSSFADE] Cleaning up secondary tap after failure/cancellation")
                cleanupSecondaryTap()
                crossfadeState.complete()
            }
        }

        if isBluetoothDestination {
            logger.info("[CROSSFADE] Destination is Bluetooth - using extended warmup")
        }

        let warmupMs = isBluetoothDestination ? 300 : 50
        logger.info("[CROSSFADE] Step 4: Waiting for secondary tap warmup (\(warmupMs)ms)...")
        try await Task.sleep(for: .milliseconds(UInt64(warmupMs)))

        crossfadeState.beginCrossfading()
        logger.info("[CROSSFADE] Step 5: Crossfade in progress (\(CrossfadeConfig.duration * 1000)ms)")

        let timeoutMs = Int(CrossfadeConfig.duration * 1000) + (isBluetoothDestination ? 400 : 100)
        let pollIntervalMs: UInt64 = 5
        var elapsedMs: Int = 0

        while (!crossfadeState.isCrossfadeComplete || !crossfadeState.isWarmupComplete) && elapsedMs < timeoutMs {
            try await Task.sleep(for: .milliseconds(pollIntervalMs))
            elapsedMs += Int(pollIntervalMs)
        }

        let progressAtTimeout = crossfadeState.progress
        if progressAtTimeout < 1.0 {
            logger.warning("[CROSSFADE] Timeout at \(progressAtTimeout * 100)% - forcing completion")
            crossfadeState.progress = 1.0
        }

        guard secondaryResources.aggregateDeviceID.isValid, secondaryResources.deviceProcID != nil else {
            logger.error("[CROSSFADE] Secondary tap invalid after timeout")
            throw CrossfadeError.secondaryTapFailed
        }

        try await Task.sleep(for: .milliseconds(10))

        logger.info("[CROSSFADE] Crossfade complete, promoting secondary")

        destroyPrimaryTap()
        promoteSecondaryToPrimary()

        crossfadeState.complete()
        crossfadeCompleted = true

        logger.info("[CROSSFADE] Complete")
    }

    private func createSecondaryTap(for outputUIDs: [String]) throws {
        precondition(!outputUIDs.isEmpty, "Must have at least one output device")

        let (tapDesc, tapID) = try createProcessTap(preferredDeviceUID: preferredTapSourceDeviceUID)
        secondaryResources.tapDescription = tapDesc
        let preferred = preferredStereoChannels(for: outputUIDs.first)
        _secondaryPreferredStereoLeftChannel = preferred.left
        _secondaryPreferredStereoRightChannel = preferred.right

        secondaryResources.tapID = tapID
        logger.debug("[CROSSFADE] Created secondary tap #\(tapID)")

        let description = buildAggregateDescription(
            outputUIDs: outputUIDs,
            tapUUID: tapDesc.uuid,
            name: "Sapphire-\(app.id)-secondary"
        )

        var err: OSStatus
        var aggID: AudioObjectID = .unknown
        err = AudioHardwareCreateAggregateDevice(description as CFDictionary, &aggID)
        guard err == noErr else {
            secondaryResources.destroy()
            throw CrossfadeError.aggregateCreationFailed(err)
        }
        secondaryResources.aggregateDeviceID = aggID
        CrashGuard.trackDevice(aggID)

        guard secondaryResources.aggregateDeviceID.waitUntilReady(timeout: 2.0) else {
            secondaryResources.destroy()
            throw CrossfadeError.deviceNotReady
        }

        logger.debug("[CROSSFADE] Created secondary aggregate #\(self.secondaryResources.aggregateDeviceID)")

        let sampleRate: Double
        if let deviceSampleRate = try? secondaryResources.aggregateDeviceID.readNominalSampleRate() {
            sampleRate = deviceSampleRate
        } else {
            sampleRate = 48000
        }
        crossfadeState.totalSamples = CrossfadeConfig.totalSamples(at: sampleRate)

        let rampTimeSeconds: Float = 0.030
        secondaryRampCoefficient = 1 - exp(-1 / (Float(sampleRate) * rampTimeSeconds))

        _secondaryCurrentVolume = _primaryCurrentVolume

        let secEQ = EQProcessor(sampleRate: sampleRate)
        if let settings = eqProcessor?.currentSettings {
            secEQ.updateSettings(settings)
        }
        secondaryEQProcessor = secEQ

        let secAutoEQ = AutoEQProcessor(sampleRate: sampleRate)
        if let profile = autoEQProcessor?.currentProfile {
            secAutoEQ.updateProfile(profile)
        }
        secondaryAutoEQProcessor = secAutoEQ

        let secLoudnessEqualizer = LoudnessEqualizer(settings: loudnessEqualizerProcessor?.currentSettings ?? LoudnessEqualizerSettings(), sampleRate: Float(sampleRate))
        secondaryLoudnessEqualizerProcessor = secLoudnessEqualizer

        let secLoudness = LoudnessCompensator(sampleRate: sampleRate)
        secLoudness.updateForVolume(_lastLoudnessVolume)
        if !(loudnessCompensator?.isEnabled ?? false) { secLoudness.setEnabled(false) }
        secondaryLoudnessCompensator = secLoudness

        nextCallbackID += 1
        _secondaryCallbackID = nextCallbackID
        let secondaryCallbackID = nextCallbackID
        err = AudioDeviceCreateIOProcIDWithBlock(&secondaryResources.deviceProcID, secondaryResources.aggregateDeviceID, queue) { [weak self] _, inInputData, _, outOutputData, _ in
            guard let self else {
                let outputs = UnsafeMutableAudioBufferListPointer(outOutputData)
                for buf in outputs {
                    if let data = buf.mData { memset(data, 0, Int(buf.mDataByteSize)) }
                }
                return
            }
            self.processAudioCallback(inInputData, to: outOutputData, callbackID: secondaryCallbackID)
        }
        guard err == noErr else {
            secondaryResources.destroy()
            throw CrossfadeError.tapCreationFailed(err)
        }

        err = AudioDeviceStart(secondaryResources.aggregateDeviceID, secondaryResources.deviceProcID)
        guard err == noErr else {
            secondaryResources.destroy()
            throw CrossfadeError.tapCreationFailed(err)
        }

        logger.debug("[CROSSFADE] Secondary tap started")
    }

    private func destroyPrimaryTap() {
        primaryResources.destroyAsync()
    }

    private func cleanupSecondaryTap() {
        guard secondaryResources.isActive else { return }
        _secondaryCallbackID = 0
        secondaryResources.destroy()
        secondaryEQProcessor = nil
        secondaryAutoEQProcessor = nil
        secondaryLoudnessCompensator = nil
        secondaryLoudnessEqualizerProcessor = nil
    }

    private func promoteSecondaryToPrimary() {
        primaryResources = secondaryResources
        secondaryResources = TapResources()

        if let deviceSampleRate = try? primaryResources.aggregateDeviceID.readNominalSampleRate() {
            let rampTimeSeconds: Float = 0.030
            rampCoefficient = 1 - exp(-1 / (Float(deviceSampleRate) * rampTimeSeconds))
        }

        let oldEQ = eqProcessor
        let oldAutoEQ = autoEQProcessor
        let oldLoudness = loudnessCompensator
        let oldLoudnessEqualizer = loudnessEqualizerProcessor
        eqProcessor = secondaryEQProcessor
        autoEQProcessor = secondaryAutoEQProcessor
        loudnessCompensator = secondaryLoudnessCompensator
        loudnessEqualizerProcessor = secondaryLoudnessEqualizerProcessor
        secondaryEQProcessor = nil
        secondaryAutoEQProcessor = nil
        secondaryLoudnessCompensator = nil
        secondaryLoudnessEqualizerProcessor = nil

        if oldEQ != nil || oldAutoEQ != nil || oldLoudness != nil || oldLoudnessEqualizer != nil {
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
                _ = oldEQ
                _ = oldAutoEQ
                _ = oldLoudness
                _ = oldLoudnessEqualizer
            }
        }

        _primaryCurrentVolume = _secondaryCurrentVolume
        _secondaryCurrentVolume = 0
        _primaryPreferredStereoLeftChannel = _secondaryPreferredStereoLeftChannel
        _primaryPreferredStereoRightChannel = _secondaryPreferredStereoRightChannel

        OSMemoryBarrier()
        _primaryCallbackID = _secondaryCallbackID
        _secondaryCallbackID = 0

    }

    private func performDestructiveDeviceSwitch(to primaryDeviceUID: String, allDeviceUIDs: [String]? = nil, sourceAlreadySilent: Bool = false) async throws {
        let deviceUIDs = allDeviceUIDs ?? [primaryDeviceUID]
        let originalVolume = _volume

        _forceSilence = true
        OSMemoryBarrier()
        defer { _forceSilence = false; OSMemoryBarrier() }
        logger.info("[SWITCH-DESTROY] Enabled _forceSilence=true (sourceAlreadySilent=\(sourceAlreadySilent))")

        if !sourceAlreadySilent {
            try await Task.sleep(for: .milliseconds(100))
        }

        try performDeviceSwitch(to: deviceUIDs)

        _primaryCurrentVolume = 0
        _volume = 0

        let settleMs = sourceAlreadySilent ? 80 : 150
        try await Task.sleep(for: .milliseconds(settleMs))

        _forceSilence = false

        for i in 1...10 {
            _volume = originalVolume * Float(i) / 10.0
            try await Task.sleep(for: .milliseconds(20))
        }

        logger.info("[SWITCH-DESTROY] Complete")
    }

    private func performDeviceSwitch(to outputUIDs: [String]) throws {
        precondition(!outputUIDs.isEmpty, "Must have at least one output device")

        var newResources = TapResources()

        let (newTapDesc, tapID) = try createProcessTap(preferredDeviceUID: preferredTapSourceDeviceUID)
        newResources.tapDescription = newTapDesc
        let preferred = preferredStereoChannels(for: outputUIDs.first)
        _primaryPreferredStereoLeftChannel = preferred.left
        _primaryPreferredStereoRightChannel = preferred.right

        newResources.tapID = tapID

        let description = buildAggregateDescription(
            outputUIDs: outputUIDs,
            tapUUID: newTapDesc.uuid,
            name: "Sapphire-\(app.id)"
        )

        var err: OSStatus
        var aggID: AudioObjectID = .unknown
        err = AudioHardwareCreateAggregateDevice(description as CFDictionary, &aggID)
        guard err == noErr else {
            newResources.destroy()
            throw CrossfadeError.aggregateCreationFailed(err)
        }
        newResources.aggregateDeviceID = aggID
        CrashGuard.trackDevice(aggID)

        guard newResources.aggregateDeviceID.waitUntilReady(timeout: 2.0) else {
            newResources.destroy()
            throw CrossfadeError.deviceNotReady
        }

        nextCallbackID += 1
        _primaryCallbackID = nextCallbackID
        let switchCallbackID = nextCallbackID
        err = AudioDeviceCreateIOProcIDWithBlock(&newResources.deviceProcID, newResources.aggregateDeviceID, queue) { [weak self] _, inInputData, _, outOutputData, _ in
            guard let self else {
                let outputs = UnsafeMutableAudioBufferListPointer(outOutputData)
                for buf in outputs {
                    if let data = buf.mData { memset(data, 0, Int(buf.mDataByteSize)) }
                }
                return
            }
            self.processAudioCallback(inInputData, to: outOutputData, callbackID: switchCallbackID)
        }
        guard err == noErr else {
            newResources.destroy()
            throw CrossfadeError.tapCreationFailed(err)
        }

        err = AudioDeviceStart(newResources.aggregateDeviceID, newResources.deviceProcID)
        guard err == noErr else {
            newResources.destroy()
            throw CrossfadeError.tapCreationFailed(err)
        }

        primaryResources.destroy()
        primaryResources = newResources
        targetDeviceUIDs = outputUIDs
        currentDeviceUIDs = outputUIDs

        if let deviceSampleRate = try? primaryResources.aggregateDeviceID.readNominalSampleRate() {
            rampCoefficient = 1 - exp(-1 / (Float(deviceSampleRate) * 0.030))
            eqProcessor?.updateSampleRate(deviceSampleRate)
            autoEQProcessor?.updateSampleRate(deviceSampleRate)
            loudnessCompensator?.updateSampleRate(deviceSampleRate)

            if let oldLE = loudnessEqualizerProcessor {
                let newLE = LoudnessEqualizer(
                    settings: oldLE.currentSettings,
                    sampleRate: Float(deviceSampleRate)
                )
                loudnessEqualizerProcessor = newLE
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.5) { _ = oldLE }
            }
        }
    }

    private func cleanupPartialActivation() {
        primaryResources.destroy()
    }

    @inline(__always)
    static func processMappedBuffers(
        inputBuffers: UnsafeMutableAudioBufferListPointer,
        outputBuffers: UnsafeMutableAudioBufferListPointer,
        targetVol: Float,
        crossfadeMultiplier: Float,
        rampCoefficient: Float,
        preferredStereoLeft: Int,
        preferredStereoRight: Int,
        currentVol: inout Float,
        eqProc: EQProcessor?,
        autoEQProc: AutoEQProcessor?,
        loudnessEqualizerProc: LoudnessEqualizer?,
        loudnessCompensatorProc: LoudnessCompensator?
    ) {
        let inputBufferCount = inputBuffers.count
        let outputBufferCount = outputBuffers.count

        for outputIndex in 0..<outputBufferCount {
            let outputBuffer = outputBuffers[outputIndex]
            guard let outputData = outputBuffer.mData else { continue }

            let inputIndex: Int
            if inputBufferCount > outputBufferCount {
                inputIndex = inputBufferCount - outputBufferCount + outputIndex
            } else {
                inputIndex = outputIndex
            }

            guard inputIndex < inputBufferCount else {
                memset(outputData, 0, Int(outputBuffer.mDataByteSize))
                continue
            }

            let inputBuffer = inputBuffers[inputIndex]
            guard let inputData = inputBuffer.mData else {
                memset(outputData, 0, Int(outputBuffer.mDataByteSize))
                continue
            }

            let inputSamples = inputData.assumingMemoryBound(to: Float.self)
            let outputSamples = outputData.assumingMemoryBound(to: Float.self)
            let inputChannels = max(1, Int(inputBuffer.mNumberChannels))
            let outputChannels = max(1, Int(outputBuffer.mNumberChannels))
            let inputSampleCount = Int(inputBuffer.mDataByteSize) / MemoryLayout<Float>.size
            let outputSampleCount = Int(outputBuffer.mDataByteSize) / MemoryLayout<Float>.size
            let inputFrameCount = inputSampleCount / inputChannels
            let outputFrameCount = outputSampleCount / outputChannels
            let frameCount = min(inputFrameCount, outputFrameCount)

            guard frameCount > 0 else {
                memset(outputData, 0, Int(outputBuffer.mDataByteSize))
                continue
            }

            let safeLeft = min(max(preferredStereoLeft, 0), max(outputChannels - 1, 0))
            let safeRight = min(max(preferredStereoRight, 0), max(outputChannels - 1, 0))

            let eq = eqProc
            let eqCanProcessStereoInterleaved = (inputChannels == 2 && outputChannels == 2)

            if inputChannels == outputChannels {
                let sampleCount = frameCount * inputChannels
                for frame in 0..<frameCount {
                    currentVol += (targetVol - currentVol) * rampCoefficient
                    let gain = currentVol * crossfadeMultiplier
                    let base = frame * inputChannels
                    for ch in 0..<inputChannels {
                        outputSamples[base + ch] = inputSamples[base + ch] * gain
                    }
                }
                if sampleCount < outputSampleCount {
                    memset(outputSamples.advanced(by: sampleCount), 0, (outputSampleCount - sampleCount) * MemoryLayout<Float>.size)
                }
            } else if inputChannels == 2 && outputChannels > 2 {
                for frame in 0..<frameCount {
                    currentVol += (targetVol - currentVol) * rampCoefficient
                    let gain = currentVol * crossfadeMultiplier
                    let inBase = frame * 2
                    let outBase = frame * outputChannels
                    let left = inputSamples[inBase] * gain
                    let right = inputSamples[inBase + 1] * gain

                    for ch in 0..<outputChannels {
                        outputSamples[outBase + ch] = 0
                    }
                    outputSamples[outBase + safeLeft] = left
                    outputSamples[outBase + safeRight] = right
                }
                let writtenSamples = frameCount * outputChannels
                if writtenSamples < outputSampleCount {
                    memset(outputSamples.advanced(by: writtenSamples), 0, (outputSampleCount - writtenSamples) * MemoryLayout<Float>.size)
                }
            } else if inputChannels == 1 && outputChannels > 1 {
                for frame in 0..<frameCount {
                    currentVol += (targetVol - currentVol) * rampCoefficient
                    let gain = currentVol * crossfadeMultiplier
                    let sample = inputSamples[frame] * gain
                    let outBase = frame * outputChannels

                    for ch in 0..<outputChannels {
                        outputSamples[outBase + ch] = 0
                    }
                    outputSamples[outBase + safeLeft] = sample
                    outputSamples[outBase + safeRight] = sample
                }
                let writtenSamples = frameCount * outputChannels
                if writtenSamples < outputSampleCount {
                    memset(outputSamples.advanced(by: writtenSamples), 0, (outputSampleCount - writtenSamples) * MemoryLayout<Float>.size)
                }
            } else {
                for frame in 0..<frameCount {
                    currentVol += (targetVol - currentVol) * rampCoefficient
                    let gain = currentVol * crossfadeMultiplier
                    let inBase = frame * inputChannels
                    let outBase = frame * outputChannels
                    let copiedChannels = min(inputChannels, outputChannels)
                    for ch in 0..<copiedChannels {
                        outputSamples[outBase + ch] = inputSamples[inBase + ch] * gain
                    }
                    if copiedChannels < outputChannels {
                        for ch in copiedChannels..<outputChannels {
                            outputSamples[outBase + ch] = 0
                        }
                    }
                }
                let writtenSamples = frameCount * outputChannels
                if writtenSamples < outputSampleCount {
                    memset(outputSamples.advanced(by: writtenSamples), 0, (outputSampleCount - writtenSamples) * MemoryLayout<Float>.size)
                }
            }

            if let eq = eq, eq.isEnabled, eqCanProcessStereoInterleaved {
                eq.process(input: outputSamples, output: outputSamples, frameCount: frameCount)
            }

            if let autoEQProc, autoEQProc.isEnabled, eqCanProcessStereoInterleaved {
                autoEQProc.process(input: outputSamples, output: outputSamples, frameCount: frameCount)
            }

            if let loudnessEqualizerProc, loudnessEqualizerProc.isEnabled, eqCanProcessStereoInterleaved {
                loudnessEqualizerProc.process(input: UnsafePointer(outputSamples), output: outputSamples, frameCount: frameCount, channelCount: outputChannels)
            }

            if let loudnessCompensatorProc, loudnessCompensatorProc.isEnabled, eqCanProcessStereoInterleaved {
                loudnessCompensatorProc.process(input: outputSamples, output: outputSamples, frameCount: frameCount)
            }

            let writtenSampleCount = frameCount * outputChannels
            SoftLimiter.processBuffer(outputSamples, sampleCount: writtenSampleCount)
        }
    }

    // MARK: - RT-Safe Audio Callback (DO NOT MODIFY WITHOUT RT-SAFETY REVIEW)

    private func processAudioCallback(
        _ inputBufferList: UnsafePointer<AudioBufferList>,
        to outputBufferList: UnsafeMutablePointer<AudioBufferList>,
        callbackID: UInt32
    ) {
        _lastRenderHostTime = mach_absolute_time()
        _hasRenderedAudio = true

        let isPrimary = (callbackID == _primaryCallbackID)
        let isSecondary = !isPrimary && (callbackID == _secondaryCallbackID)

        let outputBuffers = UnsafeMutableAudioBufferListPointer(outputBufferList)

        guard isPrimary || isSecondary else {
            for buf in outputBuffers {
                if let data = buf.mData { memset(data, 0, Int(buf.mDataByteSize)) }
            }
            return
        }

        let inputBuffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inputBufferList))

        if isPrimary && _forceSilence {
            for buf in outputBuffers {
                if let data = buf.mData { memset(data, 0, Int(buf.mDataByteSize)) }
            }
            return
        }

        var maxPeak: Float = 0.0
        var totalSamplesThisBuffer: Int = 0
        for inputBuffer in inputBuffers {
            guard let inputData = inputBuffer.mData else { continue }
            let inputSamples = inputData.assumingMemoryBound(to: Float.self)
            let channels = max(1, Int(inputBuffer.mNumberChannels))
            let sampleCount = Int(inputBuffer.mDataByteSize) / MemoryLayout<Float>.size
            if totalSamplesThisBuffer == 0 {
                totalSamplesThisBuffer = sampleCount / channels
            }
            for i in stride(from: 0, to: sampleCount, by: channels) {
                let absSample = abs(inputSamples[i])
                if absSample > maxPeak { maxPeak = absSample }
            }
        }
        let rawPeak = min(maxPeak, 1.0)

        if isPrimary {
            _peakLevel = _peakLevel + levelSmoothingFactor * (rawPeak - _peakLevel)
        } else {
            _secondaryPeakLevel = _secondaryPeakLevel + levelSmoothingFactor * (rawPeak - _secondaryPeakLevel)
            _ = crossfadeState.updateProgress(samples: totalSamplesThisBuffer)
        }

        if _isMuted {
            for buf in outputBuffers {
                if let data = buf.mData { memset(data, 0, Int(buf.mDataByteSize)) }
            }
            return
        }

        let targetVol = _volume
        var currentVol: Float
        let crossfadeMultiplier: Float
        let rampCoeff: Float
        let stereoLeft: Int
        let stereoRight: Int
        let eqProc: EQProcessor?
        let autoEQProc: AutoEQProcessor?
        let loudnessEqualizerProc: LoudnessEqualizer?
        let loudnessCompensatorProc: LoudnessCompensator?

        if isPrimary {
            currentVol = _primaryCurrentVolume
            crossfadeMultiplier = crossfadeState.primaryMultiplier
            rampCoeff = rampCoefficient
            stereoLeft = _primaryPreferredStereoLeftChannel
            stereoRight = _primaryPreferredStereoRightChannel
            eqProc = eqProcessor
            autoEQProc = autoEQProcessor
            loudnessEqualizerProc = loudnessEqualizerProcessor
            loudnessCompensatorProc = loudnessCompensator
        } else {
            currentVol = _secondaryCurrentVolume
            crossfadeMultiplier = crossfadeState.secondaryMultiplier
            rampCoeff = secondaryRampCoefficient
            stereoLeft = _secondaryPreferredStereoLeftChannel
            stereoRight = _secondaryPreferredStereoRightChannel
            eqProc = secondaryEQProcessor
            autoEQProc = secondaryAutoEQProcessor
            loudnessEqualizerProc = secondaryLoudnessEqualizerProcessor
            loudnessCompensatorProc = secondaryLoudnessCompensator
        }

        Self.processMappedBuffers(
            inputBuffers: inputBuffers,
            outputBuffers: outputBuffers,
            targetVol: targetVol,
            crossfadeMultiplier: crossfadeMultiplier,
            rampCoefficient: rampCoeff,
            preferredStereoLeft: stereoLeft,
            preferredStereoRight: stereoRight,
            currentVol: &currentVol,
            eqProc: eqProc,
            autoEQProc: autoEQProc,
            loudnessEqualizerProc: loudnessEqualizerProc,
            loudnessCompensatorProc: loudnessCompensatorProc
        )

        if isPrimary {
            _primaryCurrentVolume = currentVol
        } else {
            _secondaryCurrentVolume = currentVol
        }
    }
}