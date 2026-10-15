//
//  MicrophoneUsageManager.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-10

import Foundation
import Combine
import AudioToolbox
import CoreAudio
import OSLog
import Accelerate

@MainActor
final class MicrophoneUsageManager: ObservableObject {
    static let shared = MicrophoneUsageManager()

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Sapphire", category: "MicrophoneUsageManager")
    private let gainDefaultsKey = "SapphireMicrophoneAmplifierGain"
    private let amplifierEnabledDefaultsKey = "SapphireMicrophoneAmplifierEnabled"

    @Published private(set) var isMicInUse: Bool = false
    @Published private(set) var inputBundleIDs: Set<String> = []
    @Published private(set) var isMuted: Bool = false
    @Published private(set) var audioLevel: Float = 0.0
    @Published private(set) var peakLevel: Float = 0.0
    @Published private(set) var isClipping: Bool = false
    @Published var amplifierEnabled: Bool {
        didSet {
            UserDefaults.standard.set(amplifierEnabled, forKey: amplifierEnabledDefaultsKey)
            updateMeteringTap()
        }
    }
    @Published var amplifierGain: Float {
        didSet {

            amplifierGain = min(max(amplifierGain, 1.0), 4.0)
            UserDefaults.standard.set(amplifierGain, forKey: gainDefaultsKey)
            updateMeteringTap()
        }
    }

    private var defaultInputListener: AudioObjectPropertyListenerBlock?
    private var deviceRunningListeners: [AudioDeviceID: AudioObjectPropertyListenerBlock] = [:]
    private var micUsageUpdateTask: Task<Void, Never>?
    private var processListListener: AudioObjectPropertyListenerBlock?
    private var currentDefaultInputDeviceID: AudioDeviceID = kAudioObjectUnknown
    private var meteringTap: MicrophoneMeteringTap?
    private var meteringClientCount = 0
    private var meterResetTask: Task<Void, Never>?
    private var activeBundlesObserver: NSObjectProtocol?
    private let halQueue = DispatchQueue(label: "com.sapphire.microphone-usage", qos: .utility)
    private var usageGeneration = 0
    private var deviceScanGeneration = 0

    private init() {
        amplifierEnabled = UserDefaults.standard.object(forKey: amplifierEnabledDefaultsKey) as? Bool ?? false
        amplifierGain = min(max(UserDefaults.standard.object(forKey: gainDefaultsKey) as? Float ?? 1.5, 1.0), 4.0)
        DispatchQueue.main.async { self.setup() }
    }

    deinit {
        var defaultAddr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        if let block = defaultInputListener { AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &defaultAddr, .main, block) }
        var listAddr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessObjectList, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        if let block = processListListener { AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &listAddr, .main, block) }
        for (deviceID, block) in deviceRunningListeners {
            var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            _ = AudioObjectRemovePropertyListenerBlock(deviceID, &addr, .main, block)
        }
        if let meteringTap { halQueue.async { meteringTap.stop() } }
        meterResetTask?.cancel()
        if let activeBundlesObserver {
            NotificationCenter.default.removeObserver(activeBundlesObserver)
        }
    }

    private func setup() {
        refreshMonitoredInputDevices()
        observeDefaultInputDeviceChanges()
        activeBundlesObserver = NotificationCenter.default.addObserver(forName: .multiAudioActiveBundlesDidChange, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.updateMicUsageState() }
        }
    }

    private func observeDefaultInputDeviceChanges() {
        var defaultAddr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        defaultInputListener = { [weak self] _, _ in Task { @MainActor in self?.refreshMonitoredInputDevices() } }
        if let block = defaultInputListener { AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &defaultAddr, .main, block) }

        var listAddr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessObjectList, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        processListListener = { [weak self] _, _ in Task { @MainActor in self?.scheduleMicUsageUpdate() } }
        if let block = processListListener { AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &listAddr, .main, block) }
    }

    func inputDevicesDidChange() {
        refreshMonitoredInputDevices()
    }

    private func refreshMonitoredInputDevices() {
        deviceScanGeneration += 1
        let generation = deviceScanGeneration
        halQueue.async { [weak self] in
            let defaultInput = Self.readDefaultInputDevice()
            let inputDevices = Self.allInputDeviceIDs()
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, generation == self.deviceScanGeneration else { return }
                    self.applyInputDevices(defaultInput: defaultInput, inputDevices: inputDevices)
                }
            }
        }
    }

    private func applyInputDevices(defaultInput: AudioDeviceID?, inputDevices: [AudioDeviceID]) {
        if let defaultInput { currentDefaultInputDeviceID = defaultInput }
        let monitored = Set(inputDevices)
        for deviceID in deviceRunningListeners.keys where !monitored.contains(deviceID) { removeRunningListener(for: deviceID) }
        for deviceID in inputDevices where deviceRunningListeners[deviceID] == nil { addRunningListener(for: deviceID) }
        updateMicUsageState()
    }

    private nonisolated static func readDefaultInputDevice() -> AudioDeviceID? {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var deviceID: AudioDeviceID = kAudioObjectUnknown
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &deviceID) == noErr else { return nil }
        return deviceID
    }

    private func addRunningListener(for deviceID: AudioDeviceID) {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in Task { @MainActor in self?.scheduleMicUsageUpdate() } }
        deviceRunningListeners[deviceID] = block
        AudioObjectAddPropertyListenerBlock(deviceID, &addr, .main, block)
    }

    private func removeRunningListener(for deviceID: AudioDeviceID) {
        guard let block = deviceRunningListeners.removeValue(forKey: deviceID) else { return }
        var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        _ = AudioObjectRemovePropertyListenerBlock(deviceID, &addr, .main, block)
    }

    private func scheduleMicUsageUpdate() {
        micUsageUpdateTask?.cancel()
        micUsageUpdateTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled, let self else { return }
            self.micUsageUpdateTask = nil
            self.updateMicUsageState()
        }
    }

    private func updateMicUsageState() {
        usageGeneration += 1
        let generation = usageGeneration
        halQueue.async { [weak self] in
            let users = Self.processesUsingMicrophone()
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, generation == self.usageGeneration else { return }
                    self.applyMicUsage(users)
                }
            }
        }
    }

    private func applyMicUsage(_ users: [String?]) {
        let inUse = !users.isEmpty
        if isMicInUse != inUse { isMicInUse = inUse }
        let bundles = Set(users.compactMap { $0 })
        if bundles != inputBundleIDs { inputBundleIDs = bundles }
        let audio = MultiAudioManager.shared
        let muteDeviceID = audio.currentInputDeviceID ?? currentDefaultInputDeviceID
        let muted = audio.areAllInputsMuted || (muteDeviceID != kAudioObjectUnknown && audio.isInputMuted(for: muteDeviceID))
        if isMuted != muted { isMuted = muted }
        if !isMicInUse {
            audioLevel = 0
            peakLevel = 0
            isClipping = false
        }
        updateMeteringTap()
    }

    func beginMetering() {
        meteringClientCount += 1
        updateMeteringTap()
    }

    func endMetering() {
        meteringClientCount = max(0, meteringClientCount - 1)
        updateMeteringTap()
    }

    private func updateMeteringTap() {
        let desiredGain = amplifierEnabled ? amplifierGain : 1.0
        let shouldRun = meteringClientCount > 0 && currentDefaultInputDeviceID != kAudioObjectUnknown
        if shouldRun,
           meteringTap?.deviceID == currentDefaultInputDeviceID,
           meteringTap?.gain == desiredGain {
            return
        }
        if let previous = meteringTap { halQueue.async { previous.stop() } }
        meteringTap = nil
        guard shouldRun else {
            audioLevel = 0
            peakLevel = 0
            isClipping = false
            return
        }
        let tap = MicrophoneMeteringTap(deviceID: currentDefaultInputDeviceID, gain: desiredGain) { [weak self] level, peak, clipping in
            Task { @MainActor in self?.publishMeter(level: level, peak: peak, clipping: clipping) }
        }
        meteringTap = tap
        halQueue.async { [weak self] in
            guard !tap.start() else { return }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    if self?.meteringTap === tap { self?.meteringTap = nil }
                }
            }
        }
    }

    private func publishMeter(level: Float, peak: Float, clipping: Bool) {
        audioLevel = min(max(level, 0), 1)
        peakLevel = min(max(peak, 0), 1)
        if clipping {
            isClipping = true
            meterResetTask?.cancel()
            meterResetTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(0.8))
                guard !Task.isCancelled else { return }
                self.isClipping = false
            }
        }
    }

    func toggleMute() { setMuted(!isMuted) }
    func setMuted(_ muted: Bool) { MultiAudioManager.shared.setAllInputMutes(muted); isMuted = muted }
    func applyExternalMuteState(_ muted: Bool) {
        usageGeneration += 1
        isMuted = muted
    }

    private nonisolated static func processesUsingMicrophone() -> [String?] {
        let ourBundleID = Bundle.main.bundleIdentifier
        let ourProcessID = ProcessInfo.processInfo.processIdentifier
        var users: [String?] = []
        for objectID in allProcessObjectIDs() where processIsRunningInput(objectID) {
            let processID = readProcessID(objectID)
            let bundleID = readProcessBundleID(objectID)
            let inputDeviceNames = processInputDeviceIDs(objectID).map { CoreAudioDevices.name(of: $0) }
            guard MicrophoneUsageFilter.shouldCount(
                processID: processID,
                bundleID: bundleID,
                inputDeviceNames: inputDeviceNames,
                ownProcessID: ourProcessID,
                ownBundleID: ourBundleID
            ) else { continue }
            users.append(bundleID)
        }
        return users
    }

    private nonisolated static func allProcessObjectIDs() -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessObjectList, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    private nonisolated static func processIsRunningInput(_ objectID: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyIsRunningInput, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var running: UInt32 = 0; var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, &running) == noErr && running != 0
    }

    private nonisolated static func processInputDeviceIDs(_ objectID: AudioObjectID) -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyDevices, mScope: kAudioObjectPropertyScopeInput, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(objectID, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioDeviceID](repeating: kAudioObjectUnknown, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard !ids.isEmpty,
              AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    private nonisolated static func readProcessID(_ objectID: AudioObjectID) -> pid_t? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyPID, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var processID: pid_t = 0
        var size = UInt32(MemoryLayout<pid_t>.size)
        guard AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, &processID) == noErr else { return nil }
        return processID
    }

    private nonisolated static func readProcessBundleID(_ objectID: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyBundleID, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var bundleID: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, &bundleID) == noErr,
              let bundleID else { return nil }
        let id = bundleID.takeRetainedValue() as String
        return id.isEmpty ? nil : id
    }

    private nonisolated static func allInputDeviceIDs() -> [AudioDeviceID] {
        (CoreAudioDevices.all() ?? []).filter {
            CoreAudioDevices.hasChannels($0, scope: kAudioObjectPropertyScopeInput)
                && MicrophoneUsageFilter.isMicrophoneInputDevice(name: CoreAudioDevices.name(of: $0))
        }
    }
}

enum MicrophoneUsageFilter {
    private static let ignoredBundleIDPrefixes = [
        "com.apple.siri", "com.apple.Siri", "com.apple.assistant", "com.apple.audio",
        "com.apple.coreaudio", "com.apple.mediaremote", "com.apple.accessibility.heard",
        "com.apple.hearingd", "com.apple.voicebankingd", "com.apple.systemsound",
        "com.apple.speech", "com.apple.dictation", "com.apple.corespeech",
        "com.apple.CoreSpeech", "com.apple.VoiceControl", "com.apple.voicecontrol",
        "com.apple.controlcenter", "com.apple.cmio", "com.apple.mediaanalysisd",
        "com.apple.universalcontrol", "com.apple.donotdisturb", "com.apple.Focus"
    ]

    private static let appleUserFacingMicPrefixes = [
        "com.apple.FaceTime", "com.apple.VoiceMemos", "com.apple.QuickTimePlayerX",
        "com.apple.PhotoBooth", "com.apple.garageband", "com.apple.musicmemos",
        "com.apple.MobileSMS", "com.apple.iChat", "com.apple.Safari", "com.apple.WebKit"
    ]

    static func shouldCount(
        processID: pid_t?,
        bundleID: String?,
        inputDeviceNames: [String?],
        ownProcessID: pid_t,
        ownBundleID: String?
    ) -> Bool {
        if processID == ownProcessID { return false }
        guard let bundleID, !bundleID.isEmpty else { return false }
        if bundleID == ownBundleID { return false }
        if ignoredBundleIDPrefixes.contains(where: bundleID.hasPrefix) { return false }
        if bundleID.hasPrefix("com.apple."),
           !appleUserFacingMicPrefixes.contains(where: bundleID.hasPrefix) {
            return false
        }
        return inputDeviceNames.contains(where: { isMicrophoneInputDevice(name: $0) })
    }

    static func isMicrophoneInputDevice(name: String?) -> Bool {
        guard let name, !name.isEmpty else { return false }
        return !name.hasPrefix("Sapphire-")
    }
}

private final class MicrophoneMeteringTap: @unchecked Sendable {
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Sapphire", category: "MicrophoneMeteringTap")
    let deviceID: AudioDeviceID
    let gain: Float
    private let callback: (Float, Float, Bool) -> Void
    private var ioProcID: AudioDeviceIOProcID?
    private var isRunning = false
    private let queue = DispatchQueue(label: "com.sapphire.microphone-meter", qos: .userInteractive)
    private var accumulator = MeterAccumulator(sampleRate: 48000)

    init(deviceID: AudioDeviceID, gain: Float, callback: @escaping (Float, Float, Bool) -> Void) {
        self.deviceID = deviceID; self.gain = gain; self.callback = callback
    }

    func start() -> Bool {
        let sampleRate = MixerEngine.nominalSampleRate(deviceID)
        queue.sync { accumulator = MeterAccumulator(sampleRate: sampleRate) }
        var proc: AudioDeviceIOProcID?
        let status = AudioDeviceCreateIOProcIDWithBlock(&proc, deviceID, queue) { [weak self] _, inputData, _, _, _ in
            self?.measure(inputData)
        }
        guard status == noErr, let proc else {
            logger.error("Could not create microphone IO proc for device \(self.deviceID): \(status)")
            return false
        }
        let startStatus = AudioDeviceStart(deviceID, proc)
        guard startStatus == noErr else {
            logger.error("Could not start microphone IO proc for device \(self.deviceID): \(startStatus)")
            AudioDeviceDestroyIOProcID(deviceID, proc)
            return false
        }
        ioProcID = proc; isRunning = true
        return true
    }

    func stop() {
        guard isRunning, let proc = ioProcID else { return }
        AudioDeviceStop(deviceID, proc)
        AudioDeviceDestroyIOProcID(deviceID, proc)
        ioProcID = nil; isRunning = false
    }

    private func measure(_ data: UnsafePointer<AudioBufferList>) {
        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: data))
        var sumOfSquares: Float = 0
        var peak: Float = 0
        var sampleCount = 0
        var frameCount = 0
        for buffer in buffers {
            guard let bytes = buffer.mData else { continue }
            let samples = bytes.assumingMemoryBound(to: Float.self)
            let count = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
            guard count > 0 else { continue }
            var bufferSum: Float = 0
            var bufferPeak: Float = 0
            vDSP_svesq(samples, 1, &bufferSum, vDSP_Length(count))
            vDSP_maxmgv(samples, 1, &bufferPeak, vDSP_Length(count))
            sumOfSquares += bufferSum
            peak = max(peak, bufferPeak)
            sampleCount += count
            frameCount = max(frameCount, count / max(1, Int(buffer.mNumberChannels)))
        }
        guard let reading = accumulator.add(
            sumOfSquares: sumOfSquares * gain * gain,
            peak: peak * gain,
            sampleCount: sampleCount,
            frameCount: frameCount
        ) else { return }
        let rms = min(reading.rms * 2.2, 1.0)
        callback(rms, min(reading.peak, 1.0), reading.peak >= 0.98)
    }
}