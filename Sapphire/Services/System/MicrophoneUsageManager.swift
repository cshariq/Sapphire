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

@MainActor
final class MicrophoneUsageManager: ObservableObject {
    static let shared = MicrophoneUsageManager()

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Sapphire", category: "MicrophoneUsageManager")
    private let gainDefaultsKey = "SapphireMicrophoneAmplifierGain"
    private let amplifierEnabledDefaultsKey = "SapphireMicrophoneAmplifierEnabled"

    @Published private(set) var isMicInUse: Bool = false
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
    private var processListListener: AudioObjectPropertyListenerBlock?
    private var currentDefaultInputDeviceID: AudioDeviceID = kAudioObjectUnknown
    private var meteringTap: MicrophoneMeteringTap?
    private var meterResetTask: Task<Void, Never>?

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
        meteringTap?.stop()
        meterResetTask?.cancel()
        NotificationCenter.default.removeObserver(self)
    }

    private func setup() {
        refreshMonitoredInputDevices()
        observeDefaultInputDeviceChanges()
        NotificationCenter.default.addObserver(forName: .multiAudioActiveBundlesDidChange, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.updateMicUsageState() }
        }
    }

    private func observeDefaultInputDeviceChanges() {
        var defaultAddr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        defaultInputListener = { [weak self] _, _ in Task { @MainActor in self?.refreshMonitoredInputDevices() } }
        if let block = defaultInputListener { AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &defaultAddr, .main, block) }

        var listAddr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessObjectList, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        processListListener = { [weak self] _, _ in Task { @MainActor in self?.updateMicUsageState() } }
        if let block = processListListener { AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &listAddr, .main, block) }
    }

    private func refreshMonitoredInputDevices() {
        refreshDefaultInputDevice()
        let inputDevices = Self.allInputDeviceIDs()
        let monitored = Set(inputDevices)
        for deviceID in deviceRunningListeners.keys where !monitored.contains(deviceID) { removeRunningListener(for: deviceID) }
        for deviceID in inputDevices where deviceRunningListeners[deviceID] == nil { addRunningListener(for: deviceID) }
        updateMicUsageState()
        updateMeteringTap()
    }

    private func refreshDefaultInputDevice() {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var deviceID: AudioDeviceID = kAudioObjectUnknown
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        if AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &deviceID) == noErr { currentDefaultInputDeviceID = deviceID }
    }

    private func addRunningListener(for deviceID: AudioDeviceID) {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in Task { @MainActor in self?.updateMicUsageState() } }
        deviceRunningListeners[deviceID] = block
        AudioObjectAddPropertyListenerBlock(deviceID, &addr, .main, block)
    }

    private func removeRunningListener(for deviceID: AudioDeviceID) {
        guard let block = deviceRunningListeners.removeValue(forKey: deviceID) else { return }
        var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        _ = AudioObjectRemovePropertyListenerBlock(deviceID, &addr, .main, block)
    }

    private func updateMicUsageState() {
        isMicInUse = Self.anyProcessUsingMicrophone()
        let muteDeviceID = MultiAudioManager.shared.currentInputDeviceID ?? currentDefaultInputDeviceID
        let muted = MultiAudioManager.shared.areAllInputsMuted || (muteDeviceID != kAudioObjectUnknown && Self.readInputMuteState(of: muteDeviceID))
        isMuted = muted
        if !isMicInUse {
            audioLevel = 0
            peakLevel = 0
            isClipping = false
        }
    }

    private func updateMeteringTap() {
        meteringTap?.stop()
        meteringTap = nil
        guard amplifierEnabled || isMicInUse, currentDefaultInputDeviceID != kAudioObjectUnknown else { return }
        let tap = MicrophoneMeteringTap(deviceID: currentDefaultInputDeviceID, gain: amplifierEnabled ? amplifierGain : 1.0) { [weak self] level, peak, clipping in
            Task { @MainActor in self?.publishMeter(level: level, peak: peak, clipping: clipping) }
        }
        guard tap.start() else { return }
        meteringTap = tap
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
    func applyExternalMuteState(_ muted: Bool) { isMuted = muted }

    private static func anyProcessUsingMicrophone() -> Bool {
        let ourBundleID = Bundle.main.bundleIdentifier
        for objectID in allProcessObjectIDs() where processIsRunningInput(objectID) {
            if let bundleID = readProcessBundleID(objectID), (bundleID == ourBundleID || isIgnoredMicProcess(bundleID: bundleID)) { continue }
            return true
        }
        return false
    }

    private static func allProcessObjectIDs() -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessObjectList, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    private static func processIsRunningInput(_ objectID: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyIsRunningInput, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var running: UInt32 = 0; var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, &running) == noErr && running != 0
    }

    private static func readProcessBundleID(_ objectID: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyBundleID, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var bundleID: CFString = "" as CFString; var size = UInt32(MemoryLayout<CFString>.size)
        guard AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, &bundleID) == noErr else { return nil }
        let id = bundleID as String
        return id.isEmpty ? nil : id
    }

    private static func isIgnoredMicProcess(bundleID: String) -> Bool {
        ["com.apple.siri", "com.apple.Siri", "com.apple.assistant", "com.apple.audio", "com.apple.coreaudio", "com.apple.mediaremote", "com.apple.accessibility.heard", "com.apple.hearingd", "com.apple.voicebankingd", "com.apple.systemsound", "com.apple.speech", "com.apple.dictation", "com.apple.corespeech", "com.apple.CoreSpeech", "com.apple.VoiceControl", "com.apple.voicecontrol"].contains { bundleID.hasPrefix($0) }
    }

    private static func allInputDeviceIDs() -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.filter(hasInputChannels)
    }

    private static func hasInputChannels(_ deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamConfiguration, mScope: kAudioObjectPropertyScopeInput, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size) == noErr, size > 0 else { return false }
        let ptr = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: Int(size)); defer { ptr.deallocate() }
        var mutableSize = size
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &mutableSize, ptr) == noErr else { return false }
        return UnsafeMutableAudioBufferListPointer(ptr).contains { $0.mNumberChannels > 0 }
    }

    private static func readInputMuteState(of deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute, mScope: kAudioObjectPropertyScopeInput, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectHasProperty(deviceID, &address) else { return false }
        var muted: UInt32 = 0; var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &muted) == noErr && muted != 0
    }
}

private final class MicrophoneMeteringTap {
    private let deviceID: AudioDeviceID
    private let gain: Float
    private let callback: (Float, Float, Bool) -> Void
    private var ioProcID: AudioDeviceIOProcID?
    private var isRunning = false
    private let queue = DispatchQueue(label: "com.sapphire.microphone-meter", qos: .userInteractive)

    init(deviceID: AudioDeviceID, gain: Float, callback: @escaping (Float, Float, Bool) -> Void) {
        self.deviceID = deviceID; self.gain = gain; self.callback = callback
    }

    func start() -> Bool {
        var proc: AudioDeviceIOProcID?
        let status = AudioDeviceCreateIOProcIDWithBlock(&proc, deviceID, queue) { [weak self] _, _, _, outData, _ in
            self?.measure(outData)
        }
        guard status == noErr, let proc else { return false }
        guard AudioDeviceStart(deviceID, proc) == noErr else {
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

    private func measure(_ data: UnsafeMutablePointer<AudioBufferList>) {
        let buffers = UnsafeMutableAudioBufferListPointer(data)
        var sum: Float = 0
        var peak: Float = 0
        var count = 0
        for buffer in buffers {
            guard let bytes = buffer.mData else { continue }
            let samples = bytes.assumingMemoryBound(to: Float.self)
            let sampleCount = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
            for index in 0..<sampleCount {
                let amplified = samples[index] * gain
                let magnitude = abs(amplified)
                sum += magnitude * magnitude
                peak = max(peak, magnitude)
            }
            count += sampleCount
        }
        guard count > 0 else { return }
        let rms = min(sqrt(sum / Float(count)) * 2.2, 1.0)
        callback(rms, min(peak, 1.0), peak >= 0.98)
    }
}