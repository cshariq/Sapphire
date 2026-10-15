//
//  AudioOutputSwitcher.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-10-07
//

import AppKit
import Combine
import CoreAudio
import AudioToolbox
import OSLog

@MainActor
final class AudioOutputSwitcher: ObservableObject {
    static let shared = AudioOutputSwitcher()

    private enum Keys {
        static let cycleShortcut = "SapphireAudioOutputCycleShortcut"
        static let micMuteShortcut = "SapphireMicrophoneMuteShortcut"
        static let cycleDeviceUIDs = "SapphireAudioOutputCycleDeviceUIDs"
        static let lowerOnDisconnect = "SapphireLowerVolumeOnHeadphoneDisconnect"
        static let disconnectLevel = "SapphireHeadphoneDisconnectVolumeLevel"
    }

    @Published var cycleShortcut: KeyboardShortcut? {
        didSet { persistShortcut(cycleShortcut, forKey: Keys.cycleShortcut); updateHotkeys() }
    }
    @Published var micMuteShortcut: KeyboardShortcut? {
        didSet { persistShortcut(micMuteShortcut, forKey: Keys.micMuteShortcut); updateHotkeys() }
    }
    @Published var cycleDeviceUIDs: [String] {
        didSet { UserDefaults.standard.set(cycleDeviceUIDs, forKey: Keys.cycleDeviceUIDs) }
    }
    @Published var lowerVolumeOnHeadphoneDisconnect: Bool {
        didSet {
            UserDefaults.standard.set(lowerVolumeOnHeadphoneDisconnect, forKey: Keys.lowerOnDisconnect)
            updateHeadphoneMonitoring()
        }
    }
    @Published var headphoneDisconnectLevel: Double {
        didSet {
            let clamped = min(max(headphoneDisconnectLevel, 0.0), 0.8)
            if clamped != headphoneDisconnectLevel { headphoneDisconnectLevel = clamped }
            UserDefaults.standard.set(clamped, forKey: Keys.disconnectLevel)
            monitor.setTargetLevel(Float(clamped))
        }
    }

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Sapphire", category: "AudioOutputSwitcher")
    private let hotkeys = AudioHotkeyTable()
    private var tapToken: GlobalEventTap.Token?
    private var isShortcutRecording = false
    private var shortcutRecordingObserver: ShortcutRecordingObserver?
    private let monitor = HeadphoneDisconnectMonitor()
    private var lastSnapshot: MixerDeviceSnapshot?

    private init() {
        let defaults = UserDefaults.standard
        cycleShortcut = Self.loadShortcut(forKey: Keys.cycleShortcut)
        micMuteShortcut = Self.loadShortcut(forKey: Keys.micMuteShortcut)
        cycleDeviceUIDs = defaults.stringArray(forKey: Keys.cycleDeviceUIDs) ?? []
        lowerVolumeOnHeadphoneDisconnect = defaults.bool(forKey: Keys.lowerOnDisconnect)
        headphoneDisconnectLevel = min(max(defaults.object(forKey: Keys.disconnectLevel) as? Double ?? 0.25, 0.0), 0.8)
        monitor.setTargetLevel(Float(headphoneDisconnectLevel))

        shortcutRecordingObserver = ShortcutRecordingObserver { [weak self] isRecording in
            MainActor.assumeIsolated {
                self?.isShortcutRecording = isRecording
                self?.updateHotkeys()
            }
        }
        updateHotkeys()
    }

    func start() {
        updateHeadphoneMonitoring()
    }

    // MARK: - Device snapshots

    func devicesDidChange(_ snapshot: MixerDeviceSnapshot) {
        lastSnapshot = snapshot
        guard lowerVolumeOnHeadphoneDisconnect else { return }
        monitor.evaluate(snapshot)
    }

    private func updateHeadphoneMonitoring() {
        if lowerVolumeOnHeadphoneDisconnect {
            monitor.start()
            if let lastSnapshot { monitor.evaluate(lastSnapshot) }
        } else {
            monitor.stop()
        }
    }

    // MARK: - Actions

    func cycleOutput() {
        let audio = MultiAudioManager.shared
        let connected = audio.availableOutputDevices.map(\.uid)
        let chosen = cycleDeviceUIDs.isEmpty ? connected : cycleDeviceUIDs
        guard let next = OutputCycle.next(currentUID: audio.defaultOutputUID, chosenUIDs: chosen, availableUIDs: Set(connected)) else {
            NSSound.beep()
            return
        }
        let name = audio.availableOutputDevices.first { $0.uid == next }?.name ?? next
        audio.setSystemDefaultOutput(uid: next) { [logger] ok in
            if !ok { logger.error("Could not switch output to \(name, privacy: .public)") }
        }
    }

    func toggleMicrophoneMute() {
        MicrophoneUsageManager.shared.toggleMute()
    }

    // MARK: - Hotkeys

    private func updateHotkeys() {
        var triggers: [AudioHotkeyTable.Trigger: AudioHotkeyTable.Action] = [:]
        if let trigger = trigger(for: cycleShortcut) { triggers[trigger] = .cycleOutput }
        if let trigger = trigger(for: micMuteShortcut) { triggers[trigger] = .toggleMicMute }
        hotkeys.replace(with: triggers)

        let shouldListen = !triggers.isEmpty && !isShortcutRecording
        if shouldListen, tapToken == nil {
            tapToken = GlobalEventTap.shared.register(
                name: "AudioOutputSwitcher",
                mask: CGEventMask(1 << CGEventType.keyDown.rawValue),
                priority: EventTapPriority.shortcut
            ) { [hotkeys] type, event in
                guard type == .keyDown,
                      event.getIntegerValueField(.keyboardEventAutorepeat) == 0,
                      let action = hotkeys.action(keyCode: UInt16(event.getIntegerValueField(.keyboardEventKeycode)), flags: event.flags)
                else { return .pass }
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { AudioOutputSwitcher.shared.perform(action) }
                }
                return .swallow
            }
        } else if let tapToken {
            GlobalEventTap.shared.setEnabled(tapToken, shouldListen)
        }
    }

    private func perform(_ action: AudioHotkeyTable.Action) {
        switch action {
        case .cycleOutput: cycleOutput()
        case .toggleMicMute: toggleMicrophoneMute()
        }
    }

    private func trigger(for shortcut: KeyboardShortcut?) -> AudioHotkeyTable.Trigger? {
        guard let shortcut, !shortcut.key.isEmpty,
              let keyCode = KeyCodeTranslator.shared.keyCode(for: shortcut.key) else { return nil }
        return AudioHotkeyTable.Trigger(keyCode: keyCode, modifiers: AudioHotkeyTable.modifierMask(shortcut.significantModifiers))
    }

    private func persistShortcut(_ shortcut: KeyboardShortcut?, forKey key: String) {
        if let shortcut, let data = try? JSONEncoder().encode(shortcut) {
            UserDefaults.standard.set(data, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    private static func loadShortcut(forKey key: String) -> KeyboardShortcut? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(KeyboardShortcut.self, from: data)
    }
}

// MARK: - Hotkey table

final class AudioHotkeyTable: @unchecked Sendable {
    enum Action: Sendable { case cycleOutput, toggleMicMute }

    struct Trigger: Hashable, Sendable {
        let keyCode: UInt16
        let modifiers: UInt64
    }

    private let lock = NSLock()
    private var triggers: [Trigger: Action] = [:]

    func replace(with triggers: [Trigger: Action]) {
        lock.lock(); self.triggers = triggers; lock.unlock()
    }

    func action(keyCode: UInt16, flags: CGEventFlags) -> Action? {
        let trigger = Trigger(keyCode: keyCode, modifiers: Self.modifierMask(flags))
        lock.lock(); defer { lock.unlock() }
        return triggers[trigger]
    }

    static func modifierMask(_ flags: CGEventFlags) -> UInt64 {
        flags.rawValue & (CGEventFlags.maskCommand.rawValue | CGEventFlags.maskAlternate.rawValue
            | CGEventFlags.maskControl.rawValue | CGEventFlags.maskShift.rawValue)
    }

    static func modifierMask(_ flags: NSEvent.ModifierFlags) -> UInt64 {
        var result: UInt64 = 0
        if flags.contains(.command) { result |= CGEventFlags.maskCommand.rawValue }
        if flags.contains(.option) { result |= CGEventFlags.maskAlternate.rawValue }
        if flags.contains(.control) { result |= CGEventFlags.maskControl.rawValue }
        if flags.contains(.shift) { result |= CGEventFlags.maskShift.rawValue }
        return result
    }
}

// MARK: - Headphone disconnect

private final class HeadphoneDisconnectMonitor: @unchecked Sendable {
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Sapphire", category: "HeadphoneDisconnect")
    private let queue = DispatchQueue(label: "com.sapphire.audio.headphone-disconnect", qos: .utility)
    private static let savedVolumesKey = "SapphireSavedSpeakerVolumesByUID"

    private var isRunning = false
    private var targetLevel: Float = 0.25
    private var previousState: HeadphoneDisconnectPolicy.OutputState?
    private var lastSnapshot: MixerDeviceSnapshot?
    private var dataSourceListener: (deviceID: AudioDeviceID, block: AudioObjectPropertyListenerBlock)?

    func setTargetLevel(_ level: Float) {
        queue.async { self.targetLevel = level }
    }

    func start() {
        queue.async {
            guard !self.isRunning else { return }
            self.isRunning = true
            self.previousState = nil
        }
    }

    func stop() {
        queue.async {
            self.isRunning = false
            self.previousState = nil
            self.removeDataSourceListener()
        }
    }

    func evaluate(_ snapshot: MixerDeviceSnapshot) {
        queue.async { self.evaluateOnQueue(snapshot) }
    }

    private func evaluateOnQueue(_ snapshot: MixerDeviceSnapshot) {
        guard isRunning else { return }
        lastSnapshot = snapshot
        guard let deviceID = snapshot.defaultOutputID, let uid = snapshot.defaultOutputUID else { return }
        watchDataSource(of: deviceID)

        let current = Self.outputState(deviceID: deviceID, uid: uid)
        defer { previousState = current }
        guard let previous = previousState, previous != current else { return }

        let previousConnected = snapshot.outputs.contains { $0.uid == previous.uid }
        let saved = savedVolumes()
        let action = HeadphoneDisconnectPolicy.decide(
            previous: previous,
            current: current,
            previousStillConnected: previousConnected,
            speakerVolume: current.isBuiltInSpeaker ? Self.outputVolume(deviceID) : nil,
            targetLevel: targetLevel,
            hasSavedVolume: saved[previous.uid] != nil
        )
        switch action {
        case .none:
            break
        case .lower(let speakerUID, let level):
            if previous.uid != current.uid, let volume = Self.outputVolume(deviceID) {
                var updated = saved
                updated[speakerUID] = volume
                UserDefaults.standard.set(updated, forKey: Self.savedVolumesKey)
            }
            Self.setOutputVolume(level, deviceID: deviceID)
            logger.info("Headphones disconnected; speaker volume lowered")
        case .restore(let speakerUID):
            guard let volume = saved[speakerUID],
                  let speakerID = MixerEngine.deviceID(forUID: speakerUID) else { break }
            Self.setOutputVolume(volume, deviceID: speakerID)
            var updated = saved
            updated.removeValue(forKey: speakerUID)
            UserDefaults.standard.set(updated, forKey: Self.savedVolumesKey)
        }
    }

    private func savedVolumes() -> [String: Float] {
        (UserDefaults.standard.dictionary(forKey: Self.savedVolumesKey) ?? [:]).compactMapValues {
            ($0 as? NSNumber)?.floatValue
        }
    }

    private func watchDataSource(of deviceID: AudioDeviceID) {
        guard dataSourceListener?.deviceID != deviceID else { return }
        removeDataSourceListener()
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDataSource, mScope: kAudioObjectPropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectHasProperty(deviceID, &address) else { return }
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            guard let self, let snapshot = self.lastSnapshot else { return }
            self.evaluateOnQueue(snapshot)
        }
        if AudioObjectAddPropertyListenerBlock(deviceID, &address, queue, block) == noErr {
            dataSourceListener = (deviceID, block)
        }
    }

    private func removeDataSourceListener() {
        guard let listener = dataSourceListener else { return }
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDataSource, mScope: kAudioObjectPropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        AudioObjectRemovePropertyListenerBlock(listener.deviceID, &address, queue, listener.block)
        dataSourceListener = nil
    }

    // MARK: HAL reads

    private static func outputState(deviceID: AudioDeviceID, uid: String) -> HeadphoneDisconnectPolicy.OutputState {
        let name = CoreAudioDevices.name(of: deviceID) ?? ""
        let transport = uint32Property(kAudioDevicePropertyTransportType, scope: kAudioObjectPropertyScopeGlobal, deviceID: deviceID)
        let dataSource = uint32Property(kAudioDevicePropertyDataSource, scope: kAudioObjectPropertyScopeOutput, deviceID: deviceID)
        let isBluetooth = transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE
        let headphoneSource = dataSource == 0x6864_706E
        let isHeadphones = HeadphoneDisconnectPolicy.looksLikeHeadphones(name: name, transportIsBluetooth: isBluetooth, dataSourceIsHeadphones: headphoneSource)
        let isBuiltInSpeaker = transport == kAudioDeviceTransportTypeBuiltIn && !isHeadphones
        return .init(uid: uid, isHeadphones: isHeadphones, isBuiltInSpeaker: isBuiltInSpeaker)
    }

    private static func uint32Property(_ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope, deviceID: AudioDeviceID) -> UInt32? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectHasProperty(deviceID, &address) else { return nil }
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &value) == noErr ? value : nil
    }

    private static func outputVolume(_ deviceID: AudioDeviceID) -> Float? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume, mScope: kAudioObjectPropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectHasProperty(deviceID, &address) else { return nil }
        var volume: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        return AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &volume) == noErr ? volume : nil
    }

    private static func setOutputVolume(_ volume: Float, deviceID: AudioDeviceID) {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume, mScope: kAudioObjectPropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectHasProperty(deviceID, &address) else { return }
        var value = min(max(volume, 0), 1)
        AudioObjectSetPropertyData(deviceID, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &value)
    }
}