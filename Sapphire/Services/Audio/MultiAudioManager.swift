//
//  MultiAudioManager.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-08-13.
//

import Foundation
import AppKit
import Combine
import CoreAudio
import AudioToolbox
import Accelerate
import Darwin
import os.lock

struct AudioDevice: Identifiable, Hashable {
    let id: AudioDeviceID
    let uid: String
    let name: String
    let isInput: Bool
    let isOutput: Bool
}

struct AudioDeviceSettings: Equatable, Codable {
    var volume: Double = 1.0
    var balance: Double = 0.5
    var delay: TimeInterval = 0.0
    var customEQGains: [Double] = AudioEQ.flat
    var bassGain: Double = 0.0

    private enum CodingKeys: String, CodingKey {
        case volume, balance, delay, customEQGains, bassGain
    }

    init(volume: Double = 1.0, balance: Double = 0.5, delay: TimeInterval = 0.0,
         customEQGains: [Double] = AudioEQ.flat, bassGain: Double = 0.0) {
        self.volume = volume
        self.balance = balance
        self.delay = delay
        self.customEQGains = AudioEQ.normalize(customEQGains)
        self.bassGain = bassGain
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        volume = try values.decodeIfPresent(Double.self, forKey: .volume) ?? 1.0
        balance = try values.decodeIfPresent(Double.self, forKey: .balance) ?? 0.5
        delay = try values.decodeIfPresent(TimeInterval.self, forKey: .delay) ?? 0.0
        let storedGains = try values.decodeIfPresent([Double].self, forKey: .customEQGains) ?? AudioEQ.flat
        customEQGains = AudioEQ.normalize(storedGains)
        bassGain = try values.decodeIfPresent(Double.self, forKey: .bassGain) ?? 0.0
    }
}

struct EightDAudioSettings: Equatable, Codable {
    var enabled: Bool = false
    var rotationSpeed: Double = 0.12
    var depth: Double = 0.85
    var distance: Double = 0.15
    var elevationMotion: Double = 0.9
    var frontBackMotion: Double = 0.95
    var roomSize: Double = 0.82
    var roomSpread: Double = 0.88
    var bassBoost: Double = 0.0
    var intensity: Double = 0.9
    var centerFocus: Double = 0.35

    private enum CodingKeys: String, CodingKey {
        case enabled, rotationSpeed, depth, distance, elevationMotion, frontBackMotion, roomSize, roomSpread, bassBoost, intensity, centerFocus
    }

    init(enabled: Bool = false, rotationSpeed: Double = 0.10, depth: Double = 0.88, distance: Double = 0.18, elevationMotion: Double = 0.85, frontBackMotion: Double = 0.92, roomSize: Double = 0.78, roomSpread: Double = 0.85, bassBoost: Double = 0.0, intensity: Double = 0.9, centerFocus: Double = 0.35) {
        self.enabled = enabled
        self.rotationSpeed = rotationSpeed
        self.depth = depth
        self.distance = distance
        self.elevationMotion = elevationMotion
        self.frontBackMotion = frontBackMotion
        self.roomSize = roomSize
        self.roomSpread = roomSpread
        self.bassBoost = bassBoost
        self.intensity = intensity
        self.centerFocus = centerFocus
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try values.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        rotationSpeed = try values.decodeIfPresent(Double.self, forKey: .rotationSpeed) ?? 0.10
        depth = try values.decodeIfPresent(Double.self, forKey: .depth) ?? 0.88
        distance = try values.decodeIfPresent(Double.self, forKey: .distance) ?? 0.18
        elevationMotion = try values.decodeIfPresent(Double.self, forKey: .elevationMotion) ?? 0.85
        frontBackMotion = try values.decodeIfPresent(Double.self, forKey: .frontBackMotion) ?? 0.92
        roomSize = try values.decodeIfPresent(Double.self, forKey: .roomSize) ?? 0.78
        roomSpread = try values.decodeIfPresent(Double.self, forKey: .roomSpread) ?? 0.85
        bassBoost = try values.decodeIfPresent(Double.self, forKey: .bassBoost) ?? 0.0
        intensity = try values.decodeIfPresent(Double.self, forKey: .intensity) ?? 0.9
        centerFocus = try values.decodeIfPresent(Double.self, forKey: .centerFocus) ?? 0.35
    }
}

struct SurroundAudioSettings: Equatable, Codable {
    var enabled: Bool = false
    var width: Double = 1.7
    var crossfeed: Double = 0.12
    var ambience: Double = 0.4
    var depth: Double = 0.55
    var centerFocus: Double = 0.45

    private enum CodingKeys: String, CodingKey {
        case enabled, width, crossfeed, ambience, depth, centerFocus
    }

    init(enabled: Bool = false, width: Double = 1.7, crossfeed: Double = 0.12, ambience: Double = 0.4, depth: Double = 0.55, centerFocus: Double = 0.45) {
        self.enabled = enabled
        self.width = width
        self.crossfeed = crossfeed
        self.ambience = ambience
        self.depth = depth
        self.centerFocus = centerFocus
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try values.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        width = try values.decodeIfPresent(Double.self, forKey: .width) ?? 1.7
        crossfeed = try values.decodeIfPresent(Double.self, forKey: .crossfeed) ?? 0.12
        ambience = try values.decodeIfPresent(Double.self, forKey: .ambience) ?? 0.4
        depth = try values.decodeIfPresent(Double.self, forKey: .depth) ?? 0.55
        centerFocus = try values.decodeIfPresent(Double.self, forKey: .centerFocus) ?? 0.45
    }
}

@MainActor
class MultiAudioManager: ObservableObject {
    static let shared = MultiAudioManager()

    private let deviceSettingsDefaultsKey = "SapphireDeviceAudioSettingsByUID"
    private let selectedOutputUIDsDefaultsKey = "SapphireSelectedOutputDeviceUIDs"
    private let eightDAudioDefaultsKey = "SapphireEightDAudioSettingsByBundleID"
    private let surroundAudioDefaultsKey = "SapphireSurroundAudioSettingsByBundleID"

    @Published var availableOutputDevices: [AudioDevice] = []
    @Published var availableInputDevices: [AudioDevice] = []
    @Published var currentInputDeviceID: AudioDeviceID?
    @Published var defaultOutputDeviceID: AudioDeviceID?

    @Published var selectedOutputDeviceIDs: Set<AudioDeviceID> = [] {
        didSet {
            rebuildLiveDeviceSettingsFromArchive()
            if !isRestoringPersistedSelection {
                persistSelectedOutputUIDs()
                reTapAllApps()
            }
        }
    }

    @Published var deviceSettings: [AudioDeviceID: AudioDeviceSettings] = [:]

    private(set) var activeTaps: [String: [String: AppTapController]] = [:]
    private var isProcessMonitorStarted = false
    private var processListListenerBlock: AudioObjectPropertyListenerBlock?
    private var processRunningListenerBlocks: [AudioObjectID: AudioObjectPropertyListenerBlock] = [:]
    private var monitoredProcessObjectIDs: Set<AudioObjectID> = []
    private var processPIDByObjectID: [AudioObjectID: pid_t] = [:]
    private var processBundleIDByObjectID: [AudioObjectID: String] = [:]
    private var reconcileTask: Task<Void, Never>?
    private var settingsPersistenceTask: Task<Void, Never>?
    private var latestActiveBundleIDs: Set<String> = []
    private var lastAudioActivityByBundleID: [String: Date] = [:]
    private let recentAudioPriorityWindow: TimeInterval = 180
    private var isAuthorized = false
    private var settingsByUID: [String: AudioDeviceSettings] = [:]
    private var eightDAudioSettingsByBundleID: [String: EightDAudioSettings] = [:]
    private var surroundAudioSettingsByBundleID: [String: SurroundAudioSettings] = [:]
    private var isRestoringPersistedSelection = false

    private init() {
        CrashGuard.install()
        requestCapturePermissions()
        discoverDevices()
        loadPersistedDeviceState()
        setupDeviceListeners()
        configureProcessMonitor()
        if isAuthorized { startProcessMonitorIfNeeded() }

        premiumAccessCancellable = PremiumGate.accessChanges
            .sink { [weak self] in self?.applyPremiumDSPAccess() }

        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshAuthorization()
            }
        }
    }

    func refreshAuthorization() {
        guard !isAuthorized else { return }
        if CGPreflightScreenCaptureAccess() {
            isAuthorized = true
            startProcessMonitorIfNeeded()
        }
    }

    private func requestCapturePermissions() {
        if CGPreflightScreenCaptureAccess() {
            self.isAuthorized = true
        }
    }

    // MARK: - DSP Controls (UI to Engine Bridge)

    func notifyAdjustmentMade(for bundleID: String) {
        reconcileRunningApps()
    }

    func setAppVolume(bundleID: String, volume: Float) {
        guard let taps = activeTaps[bundleID]?.values else { return }
        for tap in taps {
            tap.updateAppVolume(volume)
        }
    }

    func setAppMute(bundleID: String, isMuted: Bool) {
        guard let taps = activeTaps[bundleID]?.values else { return }
        for tap in taps {
            tap.updateAppMute(isMuted)
        }
    }

    func setAppEQ(bundleID: String, gains: [Double], bassGain: Double = 0.0) {
        guard let taps = activeTaps[bundleID]?.values else { return }
        let normalized = AudioEQ.normalize(gains)
        for tap in taps {
            let shouldApply = PerAppAudioController.shared.appliesEQ(for: bundleID, toDeviceUID: tap.targetDeviceUID)
            tap.updateAppEQ(gains: shouldApply ? normalized : AudioEQ.flat,
                            bassGain: shouldApply ? bassGain : 0.0)
        }
    }

    private var premiumAccessCancellable: AnyCancellable?

    func eightDAudioSettings(for bundleID: String) -> EightDAudioSettings {
        guard PremiumGate.hasAccess(.audio8D) else { return EightDAudioSettings() }
        return eightDAudioSettingsByBundleID[bundleID] ?? EightDAudioSettings()
    }

    private func applyPremiumDSPAccess() {
        for (bundleID, taps) in activeTaps {
            let eightD = eightDAudioSettings(for: bundleID)
            let surround = surroundAudioSettings(for: bundleID)
            for tap in taps.values {
                tap.updateEightDAudio(settings: eightD)
                tap.updateSurroundAudio(settings: surround)
            }
        }
        objectWillChange.send()
        reconcileRunningApps()
    }

    func setEightDAudioSettings(_ settings: EightDAudioSettings, for bundleID: String) {
        guard SubscriptionAccess.hasAccess(to: .audio8D) else { return }
        var clamped = settings
        clamped.rotationSpeed = min(max(clamped.rotationSpeed, 0.01), 1.0)
        clamped.depth = min(max(clamped.depth, 0.0), 1.0)
        clamped.distance = min(max(clamped.distance, 0.0), 1.0)
        clamped.elevationMotion = min(max(clamped.elevationMotion, 0.0), 1.0)
        clamped.frontBackMotion = min(max(clamped.frontBackMotion, 0.0), 1.0)
        clamped.roomSize = min(max(clamped.roomSize, 0.0), 1.0)
        clamped.roomSpread = min(max(clamped.roomSpread, 0.0), 1.0)
        clamped.bassBoost = min(max(clamped.bassBoost, 0.0), 12.0)
        clamped.intensity = min(max(clamped.intensity, 0.0), 1.0)
        clamped.centerFocus = min(max(clamped.centerFocus, 0.0), 1.0)
        let previous = eightDAudioSettingsByBundleID[bundleID] ?? EightDAudioSettings()
        guard previous != clamped else { return }
        eightDAudioSettingsByBundleID[bundleID] = clamped
        scheduleSettingsPersistence()

        activeTaps[bundleID]?.values.forEach { $0.updateEightDAudio(settings: clamped) }
        if previous.enabled != clamped.enabled {
            objectWillChange.send()
            reconcileRunningApps()
        }
    }

    func surroundAudioSettings(for bundleID: String) -> SurroundAudioSettings {
        guard PremiumGate.hasAccess(.surroundSound) else { return SurroundAudioSettings() }
        return surroundAudioSettingsByBundleID[bundleID] ?? SurroundAudioSettings()
    }

    func setSurroundAudioSettings(_ settings: SurroundAudioSettings, for bundleID: String) {
        guard SubscriptionAccess.hasAccess(to: .surroundSound) else { return }
        var clamped = settings
        clamped.width = min(max(clamped.width, 1.0), 2.5)
        clamped.crossfeed = min(max(clamped.crossfeed, 0.0), 0.5)
        clamped.ambience = min(max(clamped.ambience, 0.0), 1.0)
        clamped.depth = min(max(clamped.depth, 0.0), 1.0)
        clamped.centerFocus = min(max(clamped.centerFocus, 0.0), 1.0)
        let previous = surroundAudioSettingsByBundleID[bundleID] ?? SurroundAudioSettings()
        guard previous != clamped else { return }
        surroundAudioSettingsByBundleID[bundleID] = clamped
        scheduleSettingsPersistence()

        activeTaps[bundleID]?.values.forEach { $0.updateSurroundAudio(settings: clamped) }
        if previous.enabled != clamped.enabled {
            objectWillChange.send()
            reconcileRunningApps()
        }
    }

    func resetEightDAudio(for bundleID: String) {
        eightDAudioSettingsByBundleID.removeValue(forKey: bundleID)
        persistEightDAudioSettings()
        activeTaps[bundleID]?.values.forEach { $0.updateEightDAudio(settings: EightDAudioSettings()) }
        objectWillChange.send()
        reconcileRunningApps()
    }

    func resetSurroundAudio(for bundleID: String) {
        surroundAudioSettingsByBundleID.removeValue(forKey: bundleID)
        persistSurroundAudioSettings()
        activeTaps[bundleID]?.values.forEach { $0.updateSurroundAudio(settings: SurroundAudioSettings()) }
        objectWillChange.send()
        reconcileRunningApps()
    }

    func clearAllEightDAudioSettings() {
        eightDAudioSettingsByBundleID.removeAll()
        surroundAudioSettingsByBundleID.removeAll()
        persistEightDAudioSettings()
        persistSurroundAudioSettings()
        activeTaps.values.flatMap(\.values).forEach {
            $0.updateEightDAudio(settings: EightDAudioSettings())
            $0.updateSurroundAudio(settings: SurroundAudioSettings())
        }
        objectWillChange.send()
        reconcileRunningApps()
    }

    func updateSettings(for deviceID: AudioDeviceID, settings: AudioDeviceSettings) {
        let previous = deviceSettings[deviceID] ?? AudioDeviceSettings()
        guard previous != settings else { return }
        self.deviceSettings[deviceID] = settings
        guard let uid = CoreAudioDevices.uid(of: deviceID) else { return }
        settingsByUID[uid] = settings
        scheduleSettingsPersistence()

        for tapMap in activeTaps.values {
            for tap in tapMap.values where tap.targetDeviceUID == uid {
                tap.updateDeviceControls(volume: Float(settings.volume), balance: Float(settings.balance), delay: Float(settings.delay))
                tap.updateDeviceEQ(gains: settings.customEQGains, bassGain: settings.bassGain)
            }
        }
        if Self.requiresProcessing(previous) != Self.requiresProcessing(settings) {
            reconcileRunningApps()
        }
    }

    func clearAllDeviceSettings() {
        settingsByUID.removeAll()
        deviceSettings.removeAll()
        UserDefaults.standard.removeObject(forKey: deviceSettingsDefaultsKey)
        notifyAdjustmentMade(for: "ResetAll")
    }

    // MARK: - Input Device Controls

    func setInputMute(_ mute: Bool, for deviceID: AudioDeviceID) {
        setAllInputMutes(mute)
    }

    func setAllInputMutes(_ mute: Bool) {
        let deviceIDs: [AudioDeviceID]
        if availableInputDevices.isEmpty {
            deviceIDs = Self.allHardwareInputDeviceIDs()
        } else {
            deviceIDs = Array(Set(availableInputDevices.map(\.id) + Self.allHardwareInputDeviceIDs()))
        }

        for id in deviceIDs {
            applyInputMute(mute, to: id)
        }
        objectWillChange.send()

        Task { @MainActor in
            MicrophoneUsageManager.shared.applyExternalMuteState(mute)
        }
    }

    func isInputMuted(for deviceID: AudioDeviceID) -> Bool {
        readInputMute(of: deviceID)
    }

    var areAllInputsMuted: Bool {
        let ids = availableInputDevices.isEmpty ? Self.allHardwareInputDeviceIDs() : availableInputDevices.map(\.id)
        let muteable = ids.filter { Self.hasInputMuteProperty($0) }
        guard !muteable.isEmpty else { return false }
        return muteable.allSatisfy { readInputMute(of: $0) }
    }

    private func applyInputMute(_ mute: Bool, to deviceID: AudioDeviceID) {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )

        if !AudioObjectHasProperty(deviceID, &address) {
            address.mElement = 1
        }
        guard AudioObjectHasProperty(deviceID, &address) else { return }

        var settable: DarwinBoolean = false
        if AudioObjectIsPropertySettable(deviceID, &address, &settable) == noErr, !settable.boolValue {
            return
        }

        var muteVal: UInt32 = mute ? 1 : 0
        AudioObjectSetPropertyData(deviceID, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &muteVal)
    }

    private func readInputMute(of deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        if !AudioObjectHasProperty(deviceID, &address) {
            address.mElement = 1
        }
        guard AudioObjectHasProperty(deviceID, &address) else { return false }

        var muteVal: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        if AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &muteVal) == noErr {
            return muteVal != 0
        }
        return false
    }

    private static func hasInputMuteProperty(_ deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        if AudioObjectHasProperty(deviceID, &address) { return true }
        address.mElement = 1
        return AudioObjectHasProperty(deviceID, &address)
    }

    private static func allHardwareInputDeviceIDs() -> [AudioDeviceID] {
        (CoreAudioDevices.all() ?? []).filter { CoreAudioDevices.hasChannels($0, scope: kAudioObjectPropertyScopeInput) }
    }

    func getInputVolume(for deviceID: AudioDeviceID) -> Float {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        if !AudioObjectHasProperty(deviceID, &address) {
            address.mElement = 1
            if !AudioObjectHasProperty(deviceID, &address) { return 1.0 }
        }
        var vol: Float = 0.0
        var size = UInt32(MemoryLayout<Float>.size)
        if AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &vol) == noErr {
            return vol
        }
        return 1.0
    }

    func setInputVolume(_ volume: Float, for deviceID: AudioDeviceID) {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        if !AudioObjectHasProperty(deviceID, &address) { address.mElement = 1 }

        var vol = volume
        let status = AudioObjectSetPropertyData(deviceID, &address, 0, nil, UInt32(MemoryLayout<Float>.size), &vol)

        if status == noErr {
            self.objectWillChange.send()
        }
    }

    // MARK: - Process Monitoring & Lazy Tapping
    private func configureProcessMonitor() { }

    private func startProcessMonitorIfNeeded() {
        guard !isProcessMonitorStarted else { return }
        isProcessMonitorStarted = true

        var listAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.scheduleReconcile()
            }
        }

        processListListenerBlock = block
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &listAddr, .main, block)
        reconcileRunningApps()
    }

    private func getResponsibleAppBundleID(for pid: pid_t, runningApps: [pid_t: RunningApps.AppInfo]) -> String? {
        if let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -1), "responsibility_get_pid_responsible_for_pid") {
            let responsiblePID = unsafeBitCast(sym, to: (@convention(c) (pid_t) -> pid_t).self)(pid)
            if responsiblePID > 0 && responsiblePID != pid, let app = runningApps[responsiblePID] { return app.bundleID }
        }
        var currentPID = pid
        while currentPID > 1 {
            if let app = runningApps[currentPID], app.isAppBundle { return app.bundleID }
            var info = kinfo_proc(); var size = MemoryLayout<kinfo_proc>.size; var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, currentPID]
            guard sysctl(&mib, 4, &info, &size, nil, 0) == 0 else { break }
            let parentPID = info.kp_eproc.e_ppid
            if parentPID == currentPID { break }; currentPID = parentPID
        }
        return nil
    }

    private func appNeedsTap(bundleID: String, outputDeviceIDs: [AudioDeviceID]) -> Bool {
        if PerAppAudioController.shared.hasAdjustments(for: bundleID) || eightDAudioSettings(for: bundleID).enabled || surroundAudioSettings(for: bundleID).enabled { return true }
        if selectedOutputDeviceIDs.count > 1 { return true }
        if selectedOutputDeviceIDs.count == 1 {
            if let selectedID = selectedOutputDeviceIDs.first,
               let defaultID = defaultOutputDeviceID,
               selectedID != defaultID {
                return true
            }
        }
        for deviceID in outputDeviceIDs {
            if let settings = deviceSettings[deviceID] {
                if settings.volume != 1.0 { return true }
                if settings.balance != 0.5 { return true }
                if settings.delay > 0.0 { return true }
                if settings.bassGain != 0.0 { return true }
                if !settings.customEQGains.allSatisfy({ $0 == 0.0 }) { return true }
            }
        }
        return false
    }

    private func scheduleReconcile() {
        reconcileTask?.cancel()
        reconcileTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled, let self else { return }
            self.reconcileTask = nil
            self.reconcileRunningApps()
        }
    }

    private func reconcileRunningApps() {
        if !isAuthorized {
            if CGPreflightScreenCaptureAccess() {
                isAuthorized = true
                startProcessMonitorIfNeeded()
            } else {
                return
            }
        }

        let outputDeviceIDs: [AudioDeviceID] = {
            if !selectedOutputDeviceIDs.isEmpty {
                return Array(selectedOutputDeviceIDs)
            }
            if let defaultID = defaultOutputDeviceID {
                return [defaultID]
            }
            return[]
        }()
        guard !outputDeviceIDs.isEmpty else { return }

        let outputUIDByDeviceID: [AudioDeviceID: String] = Dictionary(uniqueKeysWithValues: outputDeviceIDs.compactMap { deviceID -> (AudioDeviceID, String)? in
            guard let uid = CoreAudioDevices.uid(of: deviceID) else { return nil }
            return (deviceID, uid)
        })
        guard !outputUIDByDeviceID.isEmpty else { return }

        var listAddr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessObjectList, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &listAddr, 0, nil, &size) == noErr else { return }

        var objectIDs = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &listAddr, 0, nil, &size, &objectIDs)
        updateProcessRunningListeners(for: objectIDs)

        let runningAppsByPID = RunningApps.shared.infoByPID()
        var newBundleGroups: [String: [AudioObjectID]] = [:]

        for objID in objectIDs {
            var isRunning: UInt32 = 0
            var runSize = UInt32(MemoryLayout<UInt32>.size)
            var runAddr = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyIsRunning, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            if AudioObjectGetPropertyData(objID, &runAddr, 0, nil, &runSize, &isRunning) == noErr, isRunning == 0 { continue }

            let pid: pid_t
            if let cachedPID = processPIDByObjectID[objID] {
                pid = cachedPID
            } else {
                var readPID: pid_t = 0
                var pidSize = UInt32(MemoryLayout<pid_t>.size)
                var pidAddr = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyPID, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
                guard AudioObjectGetPropertyData(objID, &pidAddr, 0, nil, &pidSize, &readPID) == noErr else { continue }
                pid = readPID
                processPIDByObjectID[objID] = readPID
            }

            let bundleID = processBundleIDByObjectID[objID]
                ?? runningAppsByPID[pid]?.bundleID
                ?? getResponsibleAppBundleID(for: pid, runningApps: runningAppsByPID)
            if let bundleID { processBundleIDByObjectID[objID] = bundleID }
            if let bID = bundleID, !bID.hasPrefix("com.apple.audio") && bID != Bundle.main.bundleIdentifier {
                newBundleGroups[bID, default: []].append(objID)
            }
        }

        let currentBundles = Set(newBundleGroups.keys)
        let now = Date()
        for bundleID in currentBundles {
            lastAudioActivityByBundleID[bundleID] = now
        }
        lastAudioActivityByBundleID = lastAudioActivityByBundleID.filter {
            now.timeIntervalSince($0.value) <= recentAudioPriorityWindow * 4
        }

        if currentBundles != latestActiveBundleIDs {
            latestActiveBundleIDs = currentBundles
            NotificationCenter.default.post(name: .multiAudioActiveBundlesDidChange, object: self)
        }

        let trackedBundles = Set(activeTaps.keys)
        let activeOutputUIDs = Set(outputUIDByDeviceID.values)
        let perAppCtrl = PerAppAudioController.shared

        for bID in trackedBundles {
            guard currentBundles.contains(bID), appNeedsTap(bundleID: bID, outputDeviceIDs: outputDeviceIDs) else {
                activeTaps[bID]?.values.forEach { $0.invalidate() }
                activeTaps.removeValue(forKey: bID)
                continue
            }

            var tapMap = activeTaps[bID] ?? [:]
            for (uid, tap) in tapMap where !activeOutputUIDs.contains(uid) {
                tap.invalidate()
                tapMap.removeValue(forKey: uid)
            }
            activeTaps[bID] = tapMap.isEmpty ? nil : tapMap
        }

        for (bundleID, objIDs) in newBundleGroups {
            guard appNeedsTap(bundleID: bundleID, outputDeviceIDs: outputDeviceIDs) else { continue }
            let sortedIDs = Array(Set(objIDs)).sorted()
            var tapMap = activeTaps[bundleID] ?? [:]

            for (outputDeviceID, outputUID) in outputUIDByDeviceID {
                if let existingTap = tapMap[outputUID] {
                    if existingTap.processObjectIDs != sortedIDs {
                        existingTap.invalidate()
                        tapMap.removeValue(forKey: outputUID)
                    }
                }

                if tapMap[outputUID] == nil {
                    do {
                        let hwSampleRate = MultiAudioManager.getNominalSampleRate(for: outputDeviceID)

                        let tap = try AppTapController(bundleID: bundleID, processObjectIDs: sortedIDs, targetDeviceUID: outputUID, sampleRate: hwSampleRate)

                        tap.updateAppVolume(Float(perAppCtrl.volume(for: bundleID)))
                        tap.updateAppMute(perAppCtrl.mute(for: bundleID))

                        tap.updateEightDAudio(settings: eightDAudioSettings(for: bundleID))
                        tap.updateSurroundAudio(settings: surroundAudioSettings(for: bundleID))

                        let appEQGains = perAppCtrl.eqGains(for: bundleID)
                        let appEQBass = perAppCtrl.eqBass(for: bundleID)
                        let shouldApplyAppEQ = perAppCtrl.appliesEQ(for: bundleID, toDeviceUID: outputUID)

                        tap.updateAppEQ(gains: shouldApplyAppEQ ? appEQGains : AudioEQ.flat,
                                        bassGain: shouldApplyAppEQ ? appEQBass : 0.0)

                        if let devSettings = deviceSettings[outputDeviceID] {
                            tap.updateDeviceControls(volume: Float(devSettings.volume), balance: Float(devSettings.balance), delay: Float(devSettings.delay))
                            tap.updateDeviceEQ(gains: devSettings.customEQGains, bassGain: devSettings.bassGain)
                        }

                        try tap.activate()
                        tapMap[outputUID] = tap
                    } catch {
                        print("[Engine]  Failed to tap \(bundleID): \(error.localizedDescription)")
                    }
                }
            }
            activeTaps[bundleID] = tapMap.isEmpty ? nil : tapMap
        }
    }

    private func reTapAllApps() {
        activeTaps.values.forEach { tapMap in
            tapMap.values.forEach { $0.invalidate() }
        }
        activeTaps.removeAll()
        reconcileRunningApps()
    }

    // MARK: - Device Discovery & Helpers
    private func discoverDevices() {
        self.defaultOutputDeviceID = getDefaultDevice(for: kAudioHardwarePropertyDefaultOutputDevice)

        let previouslySelectedUIDs = Set(
            availableOutputDevices
                .filter { selectedOutputDeviceIDs.contains($0.id) }
                .map(\.uid)
            + (UserDefaults.standard.stringArray(forKey: selectedOutputUIDsDefaultsKey) ?? [])
        )

        var outputs: [AudioDevice] = []; var inputs: [AudioDevice] = []
        guard let deviceIDs = CoreAudioDevices.all() else { return }

        for deviceID in deviceIDs {
            guard let name = CoreAudioDevices.name(of: deviceID), let uid = CoreAudioDevices.uid(of: deviceID), !name.hasPrefix("Sapphire-") else { continue }
            if shouldHideVirtualDevice(name: name, uid: uid) { continue }

            let isInput = CoreAudioDevices.hasStreams(deviceID, scope: kAudioObjectPropertyScopeInput)
            let isOutput = CoreAudioDevices.hasStreams(deviceID, scope: kAudioObjectPropertyScopeOutput)

            if isOutput { outputs.append(AudioDevice(id: deviceID, uid: uid, name: name, isInput: isInput, isOutput: isOutput)) }
            if isInput { inputs.append(AudioDevice(id: deviceID, uid: uid, name: name, isInput: isInput, isOutput: isOutput)) }
        }
        self.availableOutputDevices = outputs.sorted { $0.name < $1.name }; self.availableInputDevices = inputs.sorted { $0.name < $1.name }
        rematchSelectedDevices(to: previouslySelectedUIDs)
    }

    // MARK: - Device Settings Persistence

    private func loadPersistedDeviceState() {
        if let data = UserDefaults.standard.data(forKey: deviceSettingsDefaultsKey),
           let decoded = try? JSONDecoder().decode([String: AudioDeviceSettings].self, from: data) {
            settingsByUID = decoded
        }
        if let data = UserDefaults.standard.data(forKey: eightDAudioDefaultsKey),
           let decoded = try? JSONDecoder().decode([String: EightDAudioSettings].self, from: data) {
            eightDAudioSettingsByBundleID = decoded
        }
        if let data = UserDefaults.standard.data(forKey: surroundAudioDefaultsKey),
           let decoded = try? JSONDecoder().decode([String: SurroundAudioSettings].self, from: data) {
            surroundAudioSettingsByBundleID = decoded
        }

        let savedUIDs = Set(UserDefaults.standard.stringArray(forKey: selectedOutputUIDsDefaultsKey) ?? [])
        rematchSelectedDevices(to: savedUIDs)
    }

    private func persistDeviceSettingsArchive() {
        if let data = try? JSONEncoder().encode(settingsByUID) {
            UserDefaults.standard.set(data, forKey: deviceSettingsDefaultsKey)
        }
    }

    private func persistEightDAudioSettings() {
        if let data = try? JSONEncoder().encode(eightDAudioSettingsByBundleID) {
            UserDefaults.standard.set(data, forKey: eightDAudioDefaultsKey)
        }
    }

    private func persistSurroundAudioSettings() {
        if let data = try? JSONEncoder().encode(surroundAudioSettingsByBundleID) {
            UserDefaults.standard.set(data, forKey: surroundAudioDefaultsKey)
        }
    }

    private func persistSelectedOutputUIDs() {
        let uids = availableOutputDevices
            .filter { selectedOutputDeviceIDs.contains($0.id) }
            .map(\.uid)
        UserDefaults.standard.set(uids, forKey: selectedOutputUIDsDefaultsKey)
    }

    private func scheduleSettingsPersistence() {
        settingsPersistenceTask?.cancel()
        settingsPersistenceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, let self else { return }
            self.settingsPersistenceTask = nil
            self.persistDeviceSettingsArchive()
            self.persistEightDAudioSettings()
            self.persistSurroundAudioSettings()
        }
    }

    private static func requiresProcessing(_ settings: AudioDeviceSettings) -> Bool {
        settings.volume != 1.0 ||
            settings.balance != 0.5 ||
            settings.delay > 0.0 ||
            settings.bassGain != 0.0 ||
            !settings.customEQGains.allSatisfy { $0 == 0.0 }
    }

    private func rebuildLiveDeviceSettingsFromArchive() {
        var live: [AudioDeviceID: AudioDeviceSettings] = [:]
        for device in availableOutputDevices {
            if let archived = settingsByUID[device.uid] {
                live[device.id] = archived
            }
        }
        deviceSettings = live
    }

    private func rematchSelectedDevices(to uids: Set<String>) {
        guard !uids.isEmpty else {
            rebuildLiveDeviceSettingsFromArchive()
            return
        }
        let matchedIDs = Set(availableOutputDevices.filter { uids.contains($0.uid) }.map(\.id))
        if matchedIDs == selectedOutputDeviceIDs {
            rebuildLiveDeviceSettingsFromArchive()
            return
        }
        isRestoringPersistedSelection = true
        selectedOutputDeviceIDs = matchedIDs
        isRestoringPersistedSelection = false
        rebuildLiveDeviceSettingsFromArchive()
        reTapAllApps()
    }

    private func setupDeviceListeners() {
        var devicesAddr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &devicesAddr, nil) { [weak self] _, _ in
            Task { @MainActor [weak self] in self?.discoverDevices() }
        }

        var defaultOutputAddr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &defaultOutputAddr, nil) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.defaultOutputDeviceID = self?.getDefaultDevice(for: kAudioHardwarePropertyDefaultOutputDevice)
                self?.scheduleReconcile()
            }
        }
    }

    private func shouldHideVirtualDevice(name: String, uid: String) -> Bool {
        let loweredName = name.lowercased()
        let loweredUID = uid.lowercased()
        let virtualMarkers = ["blackhole", "loopback", "aggregate", "multi-output", "soundflower", "background music", "airfoil", "vb-cable", "virtual"]
        return virtualMarkers.contains { loweredName.contains($0) || loweredUID.contains($0) }
    }

    private func getDefaultDevice(for selector: AudioObjectPropertySelector) -> AudioDeviceID? {
        var id: AudioDeviceID = 0; var size = UInt32(MemoryLayout<AudioDeviceID>.size); var addr = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        return AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id) == noErr ? id : nil
    }

    private func updateProcessRunningListeners(for processObjectIDs: [AudioObjectID]) {
        let newSet = Set(processObjectIDs)
        let removed = monitoredProcessObjectIDs.subtracting(newSet)
        for objectID in removed {
            processPIDByObjectID[objectID] = nil
            processBundleIDByObjectID[objectID] = nil
            guard let block = processRunningListenerBlocks.removeValue(forKey: objectID) else { continue }
            var address = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyIsRunning, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            _ = AudioObjectRemovePropertyListenerBlock(objectID, &address, .main, block)
        }
        let added = newSet.subtracting(monitoredProcessObjectIDs)
        for objectID in added {
            var address = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyIsRunning, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                Task { @MainActor [weak self] in self?.scheduleReconcile() }
            }
            if AudioObjectAddPropertyListenerBlock(objectID, &address, .main, block) == noErr { processRunningListenerBlocks[objectID] = block }
        }
        monitoredProcessObjectIDs = newSet
    }

    func activeAudioBundleIDs() -> Set<String> {
        if !isAuthorized {
            if CGPreflightScreenCaptureAccess() {
                isAuthorized = true
                startProcessMonitorIfNeeded()
            } else {
                return[]
            }
        }
        return latestActiveBundleIDs
    }

    func lastAudioActivityDate(for bundleID: String) -> Date? {
        lastAudioActivityByBundleID[bundleID]
    }

    func isRecentlyOutputtingAudio(_ bundleID: String, within window: TimeInterval = 180) -> Bool {
        guard let date = lastAudioActivityByBundleID[bundleID] else { return false }
        return Date().timeIntervalSince(date) <= window
    }

    // MARK: - Advanced Hardware Property Helpers

    nonisolated static func getNominalSampleRate(for deviceID: AudioDeviceID) -> Double {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyNominalSampleRate, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var rate: Double = 0; var size = UInt32(MemoryLayout<Double>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &rate)
        return (status == noErr && rate > 8000) ? rate : 48000.0
    }

    func getAvailableSampleRates(for deviceID: AudioDeviceID) -> [Double] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyAvailableNominalSampleRates,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size)
        let count = Int(size) / MemoryLayout<AudioValueRange>.size
        var ranges = [AudioValueRange](repeating: AudioValueRange(), count: count)
        AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &ranges)
        return ranges.map { $0.mMinimum }.sorted()
    }

    func setNominalSampleRate(_ rate: Double, for deviceID: AudioDeviceID) {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var newRate = rate
        AudioObjectSetPropertyData(deviceID, &address, 0, nil, UInt32(MemoryLayout<Double>.size), &newRate)
    }

    func getStreamFormat(for deviceID: AudioDeviceID) -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamFormat,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &format) == noErr else { return "Unknown" }

        let bitDepth = format.mBitsPerChannel
        let channels = format.mChannelsPerFrame
        return "\(channels) Ch / \(bitDepth)-bit"
    }
}

// MARK: - Sapphire Process Tap Controller
class AppTapController {
    let bundleID: String, processObjectIDs: [AudioObjectID], targetDeviceUID: String
    var tapID: AudioObjectID = 0, aggregateDeviceID: AudioObjectID = 0, procID: AudioDeviceIOProcID?

    nonisolated(unsafe) var appVolume: Float = 1.0, isAppMuted: Bool = false, appEqSetup: vDSP_biquad_Setup?
    nonisolated(unsafe) var deviceVolume: Float = 1.0, deviceBalance: Float = 0.5, deviceDelay: Float = 0.0, deviceEqSetup: vDSP_biquad_Setup?
    private var parameterLock = os_unfair_lock_s()
    private var pendingEightDSettings = EightDAudioSettings()
    private var pendingSurroundSettings = SurroundAudioSettings()
    private var renderAppVolume: Float = 1.0
    private var renderAppMuted = false
    private var renderDeviceVolume: Float = 1.0
    private var renderDeviceBalance: Float = 0.5
    private var renderDeviceDelay: Float = 0.0
    private var renderAppEQ: vDSP_biquad_Setup?
    private var renderDeviceEQ: vDSP_biquad_Setup?
    private var renderEightDSettings = EightDAudioSettings()
    private var renderSurroundSettings = SurroundAudioSettings()
    private var retiredEQSetups: [vDSP_biquad_Setup] = []

    private let appBufferL, appBufferR, devBufferL, devBufferR: UnsafeMutablePointer<Float>
    private let bufferSize = 2 * BiquadMath.sectionCount + 2
    private let maxDelaySamples = 96000
    private static let eightDDelaySamples = 4096
    private static let roomBufferSamples = 32768
    private static let surroundDelaySamples = 8192
    private var eightDDelayL, eightDDelayR: UnsafeMutablePointer<Float>
    private var eightDWriteIndex = 0
    private var eightDPhase = 0.0
    private var eightDReverbL, eightDReverbR: UnsafeMutablePointer<Float>
    private var eightDReverbIndex = 0
    private var surroundDelayL, surroundDelayR: UnsafeMutablePointer<Float>
    private var surroundWriteIndex = 0
    private var eightDLowpassL: Float = 0
    private var eightDLowpassR: Float = 0
    private var eightDShadowL: Float = 0
    private var eightDShadowR: Float = 0
    private var eightDBassL: Float = 0
    private var eightDBassR: Float = 0
    private var eightDRoomDampL: Float = 0
    private var eightDRoomDampR: Float = 0
    private var eightDPanLSm: Float = 0.707
    private var eightDPanRSm: Float = 0.707
    private var eightDDelayLSm: Float = 0
    private var eightDDelayRSm: Float = 0
    private var eightDShadowAmtLSm: Float = 0
    private var eightDShadowAmtRSm: Float = 0
    private var eightDDirectGainSm: Float = 1
    private var eightDAirGainSm: Float = 1
    private var eightDCrossfeedSm: Float = 0
    private var eightDWetSm: Float = 0
    private var surroundSideLowL: Float = 0
    private var surroundRearDampL: Float = 0
    private var surroundRearDampR: Float = 0
    private static let roomTapTimes: [Double] = [0.0111, 0.0193, 0.0331, 0.0518, 0.0773, 0.1129, 0.1663, 0.2411]
    private static let roomTapGains: [Float] = [0.32, 0.26, 0.21, 0.16, 0.12, 0.088, 0.06, 0.038]
    private var roomTapOffsets: [Int] = []
    private var delayBufferL, delayBufferR: UnsafeMutablePointer<Float>
    private var delayWriteIndex = 0
    private var fadeInSamplesRemaining = 2048
    private var isInvalidated = false
    private var currentSampleRate: Double

    init(bundleID: String, processObjectIDs: [AudioObjectID], targetDeviceUID: String, sampleRate: Double) throws {
        self.bundleID = bundleID; self.processObjectIDs = processObjectIDs; self.targetDeviceUID = targetDeviceUID
        self.currentSampleRate = sampleRate
        self.roomTapOffsets = Self.roomTapTimes.map { min(Int($0 * sampleRate), Self.roomBufferSamples - 1) }

        appBufferL = .allocate(capacity: bufferSize); appBufferR = .allocate(capacity: bufferSize)
        devBufferL = .allocate(capacity: bufferSize); devBufferR = .allocate(capacity: bufferSize)

        appBufferL.initialize(repeating: 0, count: bufferSize)
        appBufferR.initialize(repeating: 0, count: bufferSize)
        devBufferL.initialize(repeating: 0, count: bufferSize)
        devBufferR.initialize(repeating: 0, count: bufferSize)

        delayBufferL = .allocate(capacity: maxDelaySamples); delayBufferR = .allocate(capacity: maxDelaySamples)
        delayBufferL.initialize(repeating: 0, count: maxDelaySamples); delayBufferR.initialize(repeating: 0, count: maxDelaySamples)
        eightDDelayL = .allocate(capacity: Self.eightDDelaySamples); eightDDelayR = .allocate(capacity: Self.eightDDelaySamples)
        eightDDelayL.initialize(repeating: 0, count: Self.eightDDelaySamples); eightDDelayR.initialize(repeating: 0, count: Self.eightDDelaySamples)
        eightDReverbL = .allocate(capacity: Self.roomBufferSamples); eightDReverbR = .allocate(capacity: Self.roomBufferSamples)
        eightDReverbL.initialize(repeating: 0, count: Self.roomBufferSamples); eightDReverbR.initialize(repeating: 0, count: Self.roomBufferSamples)
        surroundDelayL = .allocate(capacity: Self.surroundDelaySamples); surroundDelayR = .allocate(capacity: Self.surroundDelaySamples)
        surroundDelayL.initialize(repeating: 0, count: Self.surroundDelaySamples); surroundDelayR.initialize(repeating: 0, count: Self.surroundDelaySamples)

        let objectIDNumbers = processObjectIDs.map { NSNumber(value: $0) }
        let tapDesc = CATapDescription(stereoMixdownOfProcesses: objectIDNumbers as! [AudioObjectID])
        tapDesc.uuid = UUID(); tapDesc.muteBehavior = .mutedWhenTapped; tapDesc.isPrivate = true

        var err = AudioHardwareCreateProcessTap(tapDesc, &tapID)
        guard err == noErr else { throw NSError(domain: "TapError", code: Int(err)) }

        let aggDesc: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Sapphire-\(bundleID.split(separator: ".").last ?? "App")",
            kAudioAggregateDeviceUIDKey: UUID().uuidString, kAudioAggregateDeviceMainSubDeviceKey: targetDeviceUID,
            kAudioAggregateDeviceClockDeviceKey: targetDeviceUID, kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: true, kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: targetDeviceUID]],
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapDriftCompensationKey: false, kAudioSubTapUIDKey: tapDesc.uuid.uuidString]]
        ]

        err = AudioHardwareCreateAggregateDevice(aggDesc as CFDictionary, &aggregateDeviceID)
        guard err == noErr else { invalidate(); throw NSError(domain: "AggregateError", code: Int(err)) }
        CrashGuard.trackDevice(aggregateDeviceID)
    }

    deinit { invalidate() }

    func activate() throws {
        let queue = DispatchQueue(label: "com.sapphire.audiotap.\(bundleID)", qos: .userInteractive)
        var err = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateDeviceID, queue) { [weak self] _, inData, _, outData, _ in self?.process(inData, outData) }
        guard err == noErr else { throw NSError(domain: "IOProcError", code: Int(err)) }
        err = AudioDeviceStart(aggregateDeviceID, procID!)
        guard err == noErr else { throw NSError(domain: "DeviceStartError", code: Int(err)) }
    }

    func invalidate() {
        guard !isInvalidated else { return }
        isInvalidated = true
        if let pID = procID { AudioDeviceStop(aggregateDeviceID, pID); AudioDeviceDestroyIOProcID(aggregateDeviceID, pID) }
        if aggregateDeviceID != 0 { CrashGuard.untrackDevice(aggregateDeviceID); AudioHardwareDestroyAggregateDevice(aggregateDeviceID) }
        if tapID != 0 { AudioHardwareDestroyProcessTap(tapID) }
        os_unfair_lock_lock(&parameterLock)
        if let setup = appEqSetup { vDSP_biquad_DestroySetup(setup) }
        if let setup = deviceEqSetup { vDSP_biquad_DestroySetup(setup) }
        retiredEQSetups.forEach { vDSP_biquad_DestroySetup($0) }
        retiredEQSetups.removeAll()
        appEqSetup = nil
        deviceEqSetup = nil
        os_unfair_lock_unlock(&parameterLock)
        appBufferL.deallocate(); appBufferR.deallocate(); devBufferL.deallocate(); devBufferR.deallocate()
        delayBufferL.deallocate(); delayBufferR.deallocate()
        eightDDelayL.deallocate(); eightDDelayR.deallocate()
        eightDReverbL.deallocate(); eightDReverbR.deallocate()
        surroundDelayL.deallocate(); surroundDelayR.deallocate()
    }

    func updateAppVolume(_ volume: Float) {
        os_unfair_lock_lock(&parameterLock)
        appVolume = volume
        os_unfair_lock_unlock(&parameterLock)
    }

    func updateAppMute(_ muted: Bool) {
        os_unfair_lock_lock(&parameterLock)
        isAppMuted = muted
        os_unfair_lock_unlock(&parameterLock)
    }

    func updateDeviceControls(volume: Float, balance: Float, delay: Float) {
        os_unfair_lock_lock(&parameterLock)
        deviceVolume = volume
        deviceBalance = balance
        deviceDelay = delay
        os_unfair_lock_unlock(&parameterLock)
    }

    func updateEightDAudio(settings: EightDAudioSettings) {
        os_unfair_lock_lock(&parameterLock)
        pendingEightDSettings = settings
        os_unfair_lock_unlock(&parameterLock)
    }

    func updateSurroundAudio(settings: SurroundAudioSettings) {
        os_unfair_lock_lock(&parameterLock)
        pendingSurroundSettings = settings
        os_unfair_lock_unlock(&parameterLock)
    }

    func updateAppEQ(gains: [Double], bassGain: Double = 0.0) {
        let newSetup = BiquadMath.createSetup(gains: gains, bassGain: bassGain, sampleRate: currentSampleRate, oldSetup: nil)
        os_unfair_lock_lock(&parameterLock)
        if let oldSetup = appEqSetup { retiredEQSetups.append(oldSetup) }
        appEqSetup = newSetup
        os_unfair_lock_unlock(&parameterLock)
    }

    func updateDeviceEQ(gains: [Double], bassGain: Double = 0.0) {
        let newSetup = BiquadMath.createSetup(gains: gains, bassGain: bassGain, sampleRate: currentSampleRate, oldSetup: nil)
        os_unfair_lock_lock(&parameterLock)
        if let oldSetup = deviceEqSetup { retiredEQSetups.append(oldSetup) }
        deviceEqSetup = newSetup
        os_unfair_lock_unlock(&parameterLock)
    }

    @_optimize(speed)
    private func process(_ inData: UnsafePointer<AudioBufferList>, _ outData: UnsafeMutablePointer<AudioBufferList>) {
        let inBuffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inData))
        let outBuffers = UnsafeMutableAudioBufferListPointer(outData)

        if os_unfair_lock_trylock(&parameterLock) {
            renderAppVolume = appVolume
            renderAppMuted = isAppMuted
            renderDeviceVolume = deviceVolume
            renderDeviceBalance = deviceBalance
            renderDeviceDelay = deviceDelay
            renderAppEQ = appEqSetup
            renderDeviceEQ = deviceEqSetup
            renderEightDSettings = pendingEightDSettings
            renderSurroundSettings = pendingSurroundSettings
            os_unfair_lock_unlock(&parameterLock)
        }
        let finalVol = renderAppMuted ? 0.0 : (renderAppVolume * renderDeviceVolume)
        let needs8D = renderEightDSettings.enabled
        let needsSurround = renderSurroundSettings.enabled
        let needsProcessing = finalVol != 1.0 || renderAppEQ != nil || renderDeviceEQ != nil || renderDeviceBalance != 0.5 || renderDeviceDelay > 0.0 || fadeInSamplesRemaining > 0 || needs8D || needsSurround

        for i in 0..<outBuffers.count {
            guard let outBytes = outBuffers[i].mData, let inBytes = inBuffers[i].mData else { continue }
            let totalSamples = Int(outBuffers[i].mDataByteSize) / MemoryLayout<Float>.size
            let channels = Int(outBuffers[i].mNumberChannels)
            let outPtr = outBytes.assumingMemoryBound(to: Float.self); let inPtr = inBytes.assumingMemoryBound(to: Float.self)

            if !needsProcessing {
                if inBytes != outBytes { memcpy(outBytes, inBytes, totalSamples * MemoryLayout<Float>.size) }
                continue
            }

            if finalVol == 0 { vDSP_vclr(outPtr, 1, vDSP_Length(totalSamples)) }
            else { var v = finalVol; vDSP_vsmul(inPtr, 1, &v, outPtr, 1, vDSP_Length(totalSamples)) }

            let frameCount = totalSamples / channels
            if let eq = renderAppEQ, channels == 2 { vDSP_biquad(eq, appBufferL, outPtr, 2, outPtr, 2, vDSP_Length(frameCount)); vDSP_biquad(eq, appBufferR, outPtr.advanced(by: 1), 2, outPtr.advanced(by: 1), 2, vDSP_Length(frameCount)) }
            if let eq = renderDeviceEQ, channels == 2 { vDSP_biquad(eq, devBufferL, outPtr, 2, outPtr, 2, vDSP_Length(frameCount)); vDSP_biquad(eq, devBufferR, outPtr.advanced(by: 1), 2, outPtr.advanced(by: 1), 2, vDSP_Length(frameCount)) }

            if needsSurround && channels == 2 {
                applySurround(outPtr, frameCount: frameCount, settings: renderSurroundSettings)
            }

            if needs8D && channels == 2 {
                applyEightD(outPtr, frameCount: frameCount, settings: renderEightDSettings)
            }

            if (renderDeviceBalance != 0.5 || renderDeviceDelay > 0.0) && channels == 2 {
                let leftG = min(1.0, (1.0 - renderDeviceBalance) * 2.0); let rightG = min(1.0, renderDeviceBalance * 2.0)
                let delayFrames = min(Int(renderDeviceDelay * Float(currentSampleRate)), maxDelaySamples - 1)
                var ptr = outPtr
                for _ in 0..<frameCount {
                    var l = ptr[0] * leftG, r = ptr[1] * rightG
                    if renderDeviceDelay > 0.0 {
                        delayBufferL[delayWriteIndex] = l; delayBufferR[delayWriteIndex] = r
                        let readIdx = (delayWriteIndex - delayFrames + maxDelaySamples) % maxDelaySamples
                        l = delayBufferL[readIdx]; r = delayBufferR[readIdx]
                        delayWriteIndex = (delayWriteIndex + 1) % maxDelaySamples
                    }
                    ptr[0] = l; ptr[1] = r; ptr += 2
                }
            }
            if fadeInSamplesRemaining > 0 {
                let fadeCount = min(totalSamples, fadeInSamplesRemaining)
                for s in 0..<fadeCount { outPtr[s] *= Float(2048 - fadeInSamplesRemaining + s) / 2048.0 }
                fadeInSamplesRemaining -= fadeCount
            }
            SoftLimiter.processBuffer(outPtr, sampleCount: totalSamples)
        }
    }

    @_optimize(speed)
    @inline(__always)
    private func fractionalRead(_ buffer: UnsafeMutablePointer<Float>, writeIndex: Int, delaySamples: Float, count: Int) -> Float {
        let clamped = min(max(delaySamples, 0), Float(count - 2))
        let whole = Int(clamped)
        let frac = clamped - Float(whole)
        var i0 = writeIndex - whole
        if i0 < 0 { i0 += count }
        var i1 = i0 - 1
        if i1 < 0 { i1 += count }
        return buffer[i0] * (1 - frac) + buffer[i1] * frac
    }

    @_optimize(speed)
    private func applySurround(_ samples: UnsafeMutablePointer<Float>, frameCount: Int, settings: SurroundAudioSettings) {
        let sampleRate = Float(max(currentSampleRate, 8000.0))
        let width = Float(settings.width)
        let crossfeed = Float(settings.crossfeed)
        let ambience = Float(settings.ambience)
        let depth = Float(settings.depth)
        let centerFocus = Float(settings.centerFocus)

        let lowAlpha = 1 - expf(-2 * .pi * 220 / sampleRate)

        let rearBase = 0.0085 + 0.017 * depth
        let leftRearDelay = min(sampleRate * rearBase, Float(Self.surroundDelaySamples - 2))
        let rightRearDelay = min(sampleRate * (rearBase * 1.63 + 0.0037), Float(Self.surroundDelaySamples - 2))
        let feedback = 0.22 + 0.3 * depth
        let dampAlpha: Float = 0.32
        let rearMix = ambience * 0.5
        let focus = centerFocus * 0.5
        let norm = 1 / (1 + (width - 1) * 0.32 + rearMix * 0.6)

        for frame in 0..<frameCount {
            let index = frame * 2
            let inputL = samples[index]
            let inputR = samples[index + 1]
            let mid = (inputL + inputR) * 0.5
            let sideRaw = (inputL - inputR) * 0.5

            surroundSideLowL += lowAlpha * (sideRaw - surroundSideLowL)
            let sideLow = surroundSideLowL
            let sideHigh = sideRaw - sideLow
            let side = sideLow + sideHigh * width

            var left = mid + side
            var right = mid - side

            let fedL = left * (1 - crossfeed) + right * crossfeed
            let fedR = right * (1 - crossfeed) + left * crossfeed
            left = fedL
            right = fedR

            surroundDelayL[surroundWriteIndex] = inputL + surroundRearDampL * feedback
            surroundDelayR[surroundWriteIndex] = inputR + surroundRearDampR * feedback
            let delayedL = fractionalRead(surroundDelayL, writeIndex: surroundWriteIndex, delaySamples: leftRearDelay, count: Self.surroundDelaySamples)
            let delayedR = fractionalRead(surroundDelayR, writeIndex: surroundWriteIndex, delaySamples: rightRearDelay, count: Self.surroundDelaySamples)
            surroundRearDampL += dampAlpha * (delayedL - surroundRearDampL)
            surroundRearDampR += dampAlpha * (delayedR - surroundRearDampR)

            left += delayedR * rearMix
            right += delayedL * rearMix

            left = left * (1 - focus) + mid * focus
            right = right * (1 - focus) + mid * focus

            samples[index] = left * norm
            samples[index + 1] = right * norm
            surroundWriteIndex += 1
            if surroundWriteIndex == Self.surroundDelaySamples { surroundWriteIndex = 0 }
        }
    }

    @_optimize(speed)
    private func applyEightD(_ samples: UnsafeMutablePointer<Float>, frameCount: Int, settings: EightDAudioSettings) {
        let speed = settings.rotationSpeed
        let depthF = Float(settings.depth)
        let distance = Float(settings.distance)
        let elevationMotion = Float(settings.elevationMotion)
        let frontBackMotion = Float(settings.frontBackMotion)
        let room = Float(settings.roomSize)
        let spread = Float(settings.roomSpread)
        let bassBoost = settings.bassBoost
        let bassGain = Float(pow(10.0, bassBoost / 20.0) - 1.0)
        let intensity = Float(min(max(settings.intensity, 0.0), 1.0))
        let centerFocus = Float(settings.centerFocus)
        let sampleRate = max(currentSampleRate, 8000.0)
        let sampleRateF = Float(sampleRate)
        let phaseStep = 2.0 * .pi * speed / sampleRate
        let stepSin = sin(phaseStep)
        let stepCos = cos(phaseStep)
        var sinPhase = sin(eightDPhase)
        var cosPhase = cos(eightDPhase)

        let shadowAlpha = 1 - expf(-2 * .pi * 2600 / sampleRateF)
        let airAlpha = 1 - expf(-2 * .pi * 1800 / sampleRateF)
        let bassAlpha = 1 - expf(-2 * .pi * 260 / sampleRateF)
        let slew: Float = 1 - expf(-1 / (0.008 * sampleRateF))

        var panLTarget: Float = 0.707
        var panRTarget: Float = 0.707
        var delayLTarget: Float = 0
        var delayRTarget: Float = 0
        var shadowLTarget: Float = 0
        var shadowRTarget: Float = 0
        var directGainTarget: Float = 1
        var airGainTarget: Float = 1
        var crossfeedTarget: Float = 0
        var wetTarget: Float = 0

        func refreshTargets() {
            let orbit = Float(sinPhase)
            let frontBack = Float(cosPhase) * frontBackMotion
            let elevation = Float(cosPhase * cosPhase - sinPhase * sinPhase) * elevationMotion
            let panPosition = (orbit * depthF + 1) * 0.5
            panLTarget = sqrtf(max(0, 1 - panPosition))
            panRTarget = sqrtf(max(0, panPosition))
            let rear = 1 - ((frontBack + 1) * 0.5)
            directGainTarget = (1 - distance * 0.3) * (1 - rear * 0.25)
            let itd = abs(orbit) * depthF * 0.00072 * sampleRateF
            delayLTarget = orbit > 0 ? itd : 0
            delayRTarget = orbit < 0 ? itd : 0
            let shadow = (0.5 + distance * 0.3)
            shadowLTarget = max(0, orbit) * shadow
            shadowRTarget = max(0, -orbit) * shadow
            airGainTarget = max(0.25, 0.82 + elevation * 0.32 - rear * 0.22)
            crossfeedTarget = 0.05 + rear * 0.28
            wetTarget = min(room * (0.55 + rear * 0.4 + abs(elevation) * 0.18), 1)
        }
        refreshTargets()

        for frame in 0..<frameCount {
            if frame & 31 == 0 { refreshTargets() }

            eightDPanLSm += slew * (panLTarget - eightDPanLSm)
            eightDPanRSm += slew * (panRTarget - eightDPanRSm)
            eightDDelayLSm += slew * (delayLTarget - eightDDelayLSm)
            eightDDelayRSm += slew * (delayRTarget - eightDDelayRSm)
            eightDShadowAmtLSm += slew * (shadowLTarget - eightDShadowAmtLSm)
            eightDShadowAmtRSm += slew * (shadowRTarget - eightDShadowAmtRSm)
            eightDDirectGainSm += slew * (directGainTarget - eightDDirectGainSm)
            eightDAirGainSm += slew * (airGainTarget - eightDAirGainSm)
            eightDCrossfeedSm += slew * (crossfeedTarget - eightDCrossfeedSm)
            eightDWetSm += slew * (wetTarget - eightDWetSm)

            let index = frame * 2
            let inputL = samples[index]
            let inputR = samples[index + 1]
            let mid = (inputL + inputR) * 0.5
            let sideRaw = (inputL - inputR) * 0.5
            let retainedSide = sideRaw * (1 - depthF * 0.55)

            let pannedL = mid * eightDPanLSm + retainedSide
            let pannedR = mid * eightDPanRSm - retainedSide
            eightDDelayL[eightDWriteIndex] = pannedL
            eightDDelayR[eightDWriteIndex] = pannedR

            var left = fractionalRead(eightDDelayL, writeIndex: eightDWriteIndex, delaySamples: eightDDelayLSm, count: Self.eightDDelaySamples) * eightDDirectGainSm
            var right = fractionalRead(eightDDelayR, writeIndex: eightDWriteIndex, delaySamples: eightDDelayRSm, count: Self.eightDDelaySamples) * eightDDirectGainSm

            eightDShadowL += shadowAlpha * (left - eightDShadowL)
            eightDShadowR += shadowAlpha * (right - eightDShadowR)
            left = left * (1 - eightDShadowAmtLSm) + eightDShadowL * eightDShadowAmtLSm * 0.88
            right = right * (1 - eightDShadowAmtRSm) + eightDShadowR * eightDShadowAmtRSm * 0.88

            if bassBoost > 0 {
                eightDBassL += bassAlpha * (left - eightDBassL)
                eightDBassR += bassAlpha * (right - eightDBassR)
                left += eightDBassL * bassGain
                right += eightDBassR * bassGain
            }

            eightDLowpassL += airAlpha * (left - eightDLowpassL)
            eightDLowpassR += airAlpha * (right - eightDLowpassR)
            left = eightDLowpassL + (left - eightDLowpassL) * eightDAirGainSm
            right = eightDLowpassR + (right - eightDLowpassR) * eightDAirGainSm

            let cf = eightDCrossfeedSm
            let crossedL = left * (1 - cf) + right * cf
            let crossedR = right * (1 - cf) + left * cf
            left = crossedL
            right = crossedR

            if room > 0 {
                let roomIndex = eightDReverbIndex
                var wetL: Float = 0
                var wetR: Float = 0
                for tap in 0..<self.roomTapOffsets.count {
                    var tapIndex = roomIndex - roomTapOffsets[tap]
                    if tapIndex < 0 { tapIndex += Self.roomBufferSamples }
                    wetL += eightDReverbL[tapIndex] * Self.roomTapGains[tap]
                    wetR += eightDReverbR[tapIndex] * Self.roomTapGains[tap]
                }
                let crossL = wetL * (1 - spread) + wetR * spread
                let crossR = wetR * (1 - spread) + wetL * spread
                eightDRoomDampL += 0.3 * (crossL - eightDRoomDampL)
                eightDRoomDampR += 0.3 * (crossR - eightDRoomDampR)
                let roomMix = eightDWetSm * 0.38
                let feedbackMix = eightDWetSm * 0.3
                eightDReverbL[roomIndex] = left + eightDRoomDampR * feedbackMix
                eightDReverbR[roomIndex] = right + eightDRoomDampL * feedbackMix
                left += crossL * roomMix
                right += crossR * roomMix
                eightDReverbIndex += 1
                if eightDReverbIndex == Self.roomBufferSamples { eightDReverbIndex = 0 }
            }

            left = inputL * (1 - intensity) + left * intensity
            right = inputR * (1 - intensity) + right * intensity
            let focus = centerFocus * 0.45
            left = left * (1 - focus) + mid * focus
            right = right * (1 - focus) + mid * focus

            samples[index] = left * 1.08
            samples[index + 1] = right * 1.08
            eightDWriteIndex += 1
            if eightDWriteIndex == Self.eightDDelaySamples { eightDWriteIndex = 0 }

            let nextSin = sinPhase * stepCos + cosPhase * stepSin
            cosPhase = cosPhase * stepCos - sinPhase * stepSin
            sinPhase = nextSin
        }
        eightDPhase += phaseStep * Double(frameCount)
        eightDPhase.formTruncatingRemainder(dividingBy: 2.0 * .pi)
        if eightDPhase < 0 { eightDPhase += 2.0 * .pi }
    }
}

// MARK: - Sharp DSP Utilities

enum BiquadMath {
    static let sectionCount = AudioEQ.bandCount + 2

    private static func rbjPeaking(freq: Double, gainDB: Double, q: Double, sampleRate: Double) -> [Double] {
        let A = pow(10.0, gainDB / 40.0)
        let w0 = 2.0 * .pi * freq / sampleRate
        let cs = cos(w0)
        let alpha = sin(w0) / (2.0 * q)
        let b0 = 1.0 + alpha * A
        let b1 = -2.0 * cs
        let b2 = 1.0 - alpha * A
        let a0 = 1.0 + alpha / A
        let a1 = -2.0 * cs
        let a2 = 1.0 - alpha / A
        return [b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0]
    }

    private static func rbjLowShelf(freq: Double, gainDB: Double, sampleRate: Double) -> [Double] {
        let A = pow(10.0, gainDB / 40.0)
        let w0 = 2.0 * .pi * freq / sampleRate
        let cs = cos(w0)
        let sn = sin(w0)
        let alpha = sn / 2.0 * sqrt((A + 1.0 / A) * (1.0 / 0.9 - 1.0) + 2.0)
        let twoSqrtAAlpha = 2.0 * sqrt(A) * alpha
        let b0 = A * ((A + 1.0) - (A - 1.0) * cs + twoSqrtAAlpha)
        let b1 = 2.0 * A * ((A - 1.0) - (A + 1.0) * cs)
        let b2 = A * ((A + 1.0) - (A - 1.0) * cs - twoSqrtAAlpha)
        let a0 = (A + 1.0) + (A - 1.0) * cs + twoSqrtAAlpha
        let a1 = -2.0 * ((A - 1.0) + (A + 1.0) * cs)
        let a2 = (A + 1.0) + (A - 1.0) * cs - twoSqrtAAlpha
        return [b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0]
    }

    private static func rbjHighShelf(freq: Double, gainDB: Double, sampleRate: Double) -> [Double] {
        let A = pow(10.0, gainDB / 40.0)
        let w0 = 2.0 * .pi * freq / sampleRate
        let cs = cos(w0)
        let sn = sin(w0)
        let alpha = sn / 2.0 * sqrt((A + 1.0 / A) * (1.0 / 0.9 - 1.0) + 2.0)
        let twoSqrtAAlpha = 2.0 * sqrt(A) * alpha
        let b0 = A * ((A + 1.0) + (A - 1.0) * cs + twoSqrtAAlpha)
        let b1 = -2.0 * A * ((A - 1.0) + (A + 1.0) * cs)
        let b2 = A * ((A + 1.0) + (A - 1.0) * cs - twoSqrtAAlpha)
        let a0 = (A + 1.0) - (A - 1.0) * cs + twoSqrtAAlpha
        let a1 = 2.0 * ((A - 1.0) - (A + 1.0) * cs)
        let a2 = (A + 1.0) - (A - 1.0) * cs - twoSqrtAAlpha
        return [b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0]
    }

    private static let passthrough: [Double] = [1, 0, 0, 0, 0]

    static func createSetup(gains rawGains: [Double], bassGain: Double, sampleRate: Double, oldSetup: vDSP_biquad_Setup?) -> vDSP_biquad_Setup? {
        if let old = oldSetup { DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) { vDSP_biquad_DestroySetup(old) } }

        let gains = AudioEQ.normalize(rawGains)
        if bassGain == 0.0 && gains.allSatisfy({ $0 == 0.0 }) { return nil }

        let bandQ = 4.318
        let sr = max(sampleRate, 8000.0)
        var coeffs: [Double] = []
        coeffs.reserveCapacity(sectionCount * 5)

        coeffs += bassGain == 0.0 ? passthrough
            : rbjLowShelf(freq: AudioEQ.bassShelfFrequency, gainDB: bassGain, sampleRate: sr)

        for i in 0..<AudioEQ.bandCount {
            let g = gains[i]
            let f = min(AudioEQ.frequencies[i], sr * 0.45)
            if g == 0.0 {
                coeffs += passthrough
            } else if i == 0 {
                coeffs += rbjLowShelf(freq: f, gainDB: g, sampleRate: sr)
            } else if i == AudioEQ.bandCount - 1 {
                coeffs += rbjHighShelf(freq: f, gainDB: g, sampleRate: sr)
            } else {
                coeffs += rbjPeaking(freq: f, gainDB: g, q: bandQ, sampleRate: sr)
            }
        }

        let positiveSum = gains.filter { $0 > 0 }.reduce(0, +) + max(0, bassGain)
        let peakBoost = (gains.max() ?? 0) + max(0, bassGain) * 0.5
        let makeupDB = -min(peakBoost * 0.5 + positiveSum * 0.06, 9.0)
        let makeup = pow(10.0, makeupDB / 20.0)
        coeffs += [makeup, 0, 0, 0, 0]

        return coeffs.withUnsafeBufferPointer { vDSP_biquad_CreateSetup($0.baseAddress!, vDSP_Length(sectionCount)) }
    }
}

enum SoftLimiter {
    @inline(__always) static func processBuffer(_ buffer: UnsafeMutablePointer<Float>, sampleCount: Int) {
        guard sampleCount > 0 else { return }

        let threshold: Float = 0.88
        let remainingHeadroom: Float = 1.0 - threshold
        for index in 0..<sampleCount {
            let sample = buffer[index]
            let magnitude = abs(sample)
            guard magnitude > threshold else { continue }

            let excess = magnitude - threshold
            let compressed = threshold + remainingHeadroom * excess / (remainingHeadroom + excess)
            buffer[index] = sample < 0 ? -compressed : compressed
        }
    }
}

extension Notification.Name {
    static let multiAudioActiveBundlesDidChange = Notification.Name("multiAudioActiveBundlesDidChange")
    static let perAppAudioSettingsDidChange = Notification.Name("perAppAudioSettingsDidChange")
}

enum CrashGuard {
    private static var devices: [AudioObjectID] = []
    private static let lock = NSLock()
    static func install() { signal(SIGABRT, { CrashGuard.handleSignal($0) }); signal(SIGSEGV, { CrashGuard.handleSignal($0) }) }
    static func handleSignal(_ sig: Int32) { devices.forEach { AudioHardwareDestroyAggregateDevice($0) }; signal(sig, SIG_DFL); raise(sig) }
    static func trackDevice(_ id: AudioObjectID) { lock.lock(); devices.append(id); lock.unlock() }
    static func untrackDevice(_ id: AudioObjectID) { lock.lock(); devices.removeAll { $0 == id }; lock.unlock() }
}