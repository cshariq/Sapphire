//
//  MicrophoneUsageManager.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-10

import Foundation
import Combine
import AudioToolbox
import OSLog

@MainActor
final class MicrophoneUsageManager: ObservableObject {
    static let shared = MicrophoneUsageManager()

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Sapphire", category: "MicrophoneUsageManager")

    @Published private(set) var isMicInUse: Bool = false
    @Published private(set) var isMuted: Bool = false
    @Published private(set) var audioLevel: Float = 0.0

    private var defaultInputListener: AudioObjectPropertyListenerBlock?
    private var deviceRunningListeners: [AudioDeviceID: AudioObjectPropertyListenerBlock] = [:]
    private var processListListener: AudioObjectPropertyListenerBlock?
    private var currentDefaultInputDeviceID: AudioDeviceID = kAudioObjectUnknown

    deinit {
        var defaultAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        if let block = defaultInputListener {
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &defaultAddr, .main, block)
        }
        var listAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        if let block = processListListener {
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &listAddr, .main, block)
        }
        for (deviceID, block) in deviceRunningListeners {
            var addr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            _ = AudioObjectRemovePropertyListenerBlock(deviceID, &addr, .main, block)
        }
        NotificationCenter.default.removeObserver(self)
    }

    private init() {
        DispatchQueue.main.async {
            self.setup()
        }
    }

    private func setup() {
        refreshMonitoredInputDevices()
        observeDefaultInputDeviceChanges()

        NotificationCenter.default.addObserver(forName: .multiAudioActiveBundlesDidChange, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.updateMicUsageState()
            }
        }
    }

    private func observeDefaultInputDeviceChanges() {
        var defaultAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        defaultInputListener = { [weak self] _, _ in
            Task { @MainActor in
                self?.refreshMonitoredInputDevices()
            }
        }

        if let block = defaultInputListener {
            AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &defaultAddr, .main, block)
        }

        var listAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        processListListener = { [weak self] _, _ in
            Task { @MainActor in
                self?.updateMicUsageState()
            }
        }
        if let pblock = processListListener {
            AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &listAddr, .main, pblock)
        }
    }

    private func refreshMonitoredInputDevices() {
        refreshDefaultInputDevice()
        let inputDevices = Self.allInputDeviceIDs()
        let monitored = Set(inputDevices)

        for deviceID in deviceRunningListeners.keys where !monitored.contains(deviceID) {
            removeRunningListener(for: deviceID)
        }

        for deviceID in inputDevices where deviceRunningListeners[deviceID] == nil {
            addRunningListener(for: deviceID)
        }

        updateMicUsageState()
    }

    private func refreshDefaultInputDevice() {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID: AudioDeviceID = kAudioObjectUnknown
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &deviceID) == noErr else {
            return
        }
        currentDefaultInputDeviceID = deviceID
    }

    private func addRunningListener(for deviceID: AudioDeviceID) {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor in
                self?.updateMicUsageState()
            }
        }

        deviceRunningListeners[deviceID] = block
        AudioObjectAddPropertyListenerBlock(deviceID, &addr, .main, block)
    }

    private func removeRunningListener(for deviceID: AudioDeviceID) {
        guard let block = deviceRunningListeners.removeValue(forKey: deviceID) else { return }
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        _ = AudioObjectRemovePropertyListenerBlock(deviceID, &addr, .main, block)
    }

    private func updateMicUsageState() {
        let anyRunning = Self.anyProcessUsingMicrophone()
        if anyRunning != isMicInUse {
            isMicInUse = anyRunning
        }

        let muted = MultiAudioManager.shared.areAllInputsMuted
            || {
                let muteDeviceID = MultiAudioManager.shared.currentInputDeviceID ?? currentDefaultInputDeviceID
                guard muteDeviceID != kAudioObjectUnknown else { return false }
                if MultiAudioManager.shared.availableInputDevices.contains(where: { $0.id == muteDeviceID }) {
                    return MultiAudioManager.shared.isInputMuted(for: muteDeviceID)
                }
                return Self.readInputMuteState(of: muteDeviceID)
            }()

        if muted != isMuted {
            isMuted = muted
        }
    }

    func toggleMute() {
        setMuted(!isMuted)
    }

    func setMuted(_ muted: Bool) {
        MultiAudioManager.shared.setAllInputMutes(muted)
        isMuted = muted
    }

    func applyExternalMuteState(_ muted: Bool) {
        if isMuted != muted {
            isMuted = muted
        }
    }

    // MARK: - CoreAudio helpers

    private static func anyProcessUsingMicrophone() -> Bool {
        let ourBundleID = Bundle.main.bundleIdentifier
        for objectID in allProcessObjectIDs() {
            guard processIsRunningInput(objectID) else { continue }
            let bundleID = readProcessBundleID(objectID)
            if let bundleID {
                if bundleID == ourBundleID { continue }
                if isIgnoredMicProcess(bundleID: bundleID) { continue }
            }
            return true
        }
        return false
    }

    private static func allProcessObjectIDs() -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize
        ) == noErr, dataSize > 0 else {
            return []
        }

        let count = Int(dataSize) / MemoryLayout<AudioObjectID>.size
        var objectIDs = [AudioObjectID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize,
            &objectIDs
        ) == noErr else {
            return []
        }
        return objectIDs
    }

    private static func processIsRunningInput(_ objectID: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyIsRunningInput,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var running: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, &running) == noErr else {
            return false
        }
        return running != 0
    }

    private static func readProcessBundleID(_ objectID: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyBundleID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var bundleID: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        guard AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, &bundleID) == noErr else {
            return nil
        }
        let id = bundleID as String
        return id.isEmpty ? nil : id
    }

    private static func isIgnoredMicProcess(bundleID: String) -> Bool {
        let ignoredPrefixes = [
            "com.apple.siri",
            "com.apple.Siri",
            "com.apple.assistant",
            "com.apple.audio",
            "com.apple.coreaudio",
            "com.apple.mediaremote",
            "com.apple.accessibility.heard",
            "com.apple.hearingd",
            "com.apple.voicebankingd",
            "com.apple.systemsound",
            "com.apple.speech",
            "com.apple.dictation",
            "com.apple.corespeech",
            "com.apple.CoreSpeech",
            "com.apple.VoiceControl",
            "com.apple.voicecontrol",
        ]
        return ignoredPrefixes.contains { bundleID.hasPrefix($0) }
    }

    private static func allInputDeviceIDs() -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize) == noErr,
              dataSize > 0 else {
            return []
        }

        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize,
            &deviceIDs
        ) == noErr else {
            return []
        }

        return deviceIDs.filter(hasInputChannels)
    }

    private static func hasInputChannels(_ deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &dataSize) == noErr,
              dataSize > 0 else {
            return false
        }

        let bufferListPointer = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: Int(dataSize))
        defer { bufferListPointer.deallocate() }

        var mutableSize = dataSize
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &mutableSize, bufferListPointer) == noErr else {
            return false
        }

        let buffers = UnsafeMutableAudioBufferListPointer(bufferListPointer)
        return buffers.contains { $0.mNumberChannels > 0 }
    }

    private static func readInputMuteState(of deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )

        guard AudioObjectHasProperty(deviceID, &address) else { return false }

        var muted: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let err = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &muted)
        return err == noErr && muted != 0
    }

    private static func setInputMuteState(_ muted: Bool, for deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )

        guard AudioObjectHasProperty(deviceID, &address) else { return false }

        var value: UInt32 = muted ? 1 : 0
        let size = UInt32(MemoryLayout<UInt32>.size)
        let err = AudioObjectSetPropertyData(deviceID, &address, 0, nil, size, &value)
        return err == noErr
    }
}