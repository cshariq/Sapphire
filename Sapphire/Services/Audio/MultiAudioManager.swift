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
    private let appRoutesDefaultsKey = "SapphirePerAppOutputRouteUIDs"
    private let appOrderingDefaultsKey = "SapphireMixerAppOrdering"
    private let preferredInputDefaultsKey = "SapphirePreferredInputDeviceUID"

    @Published var availableOutputDevices: [AudioDevice] = []
    @Published var availableInputDevices: [AudioDevice] = []
    @Published private(set) var currentInputDeviceID: AudioDeviceID?
    @Published var defaultOutputDeviceID: AudioDeviceID?
    @Published private(set) var defaultOutputUID: String?
    @Published private(set) var inputVolumes: [AudioDeviceID: Float] = [:]
    @Published private(set) var inputMutes: [AudioDeviceID: Bool] = [:]
    @Published private(set) var appRoutes: [String: String] = [:]
    @Published private(set) var appOrdering = MixerAppOrdering()
    @Published private(set) var preferredInputUID: String?

    @Published var selectedOutputDeviceIDs: Set<AudioDeviceID> = [] {
        didSet {
            rebuildLiveDeviceSettingsFromArchive()
            if !isRestoringPersistedSelection {
                persistSelectedOutputUIDs()
                scheduleReconcile()
            }
        }
    }

    @Published var deviceSettings: [AudioDeviceID: AudioDeviceSettings] = [:]

    var activeTaps: [String: [String: AppTapController]] { engine.state.snapshot() }

    func hasActiveTap(for bundleID: String) -> Bool { engine.state.hasTap(for: bundleID) }

    private let engine = MixerEngine()
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
    private var preferredInputEnforcements: [Date] = []
    private var hasAppliedSnapshot = false
    private var premiumAccessCancellable: AnyCancellable?
    private var observers: [(center: NotificationCenter, token: NSObjectProtocol)] = []

    private init() {
        loadPersistedDeviceState()

        engine.onDevices = { [weak self] snapshot in
            Task { @MainActor in self?.apply(snapshot) }
        }
        engine.onActiveBundles = { [weak self] bundles in
            Task { @MainActor in self?.applyActiveBundles(bundles) }
        }
        engine.onProcessListChanged = { [weak self] in
            Task { @MainActor in self?.scheduleReconcile() }
        }
        pushAllParameters()
        engine.start()
        AudioOutputSwitcher.shared.start()

        if CGPreflightScreenCaptureAccess() {
            isAuthorized = true
            engine.startProcessMonitoring()
            scheduleReconcile()
        }

        premiumAccessCancellable = PremiumGate.accessChanges
            .sink { [weak self] in self?.applyPremiumDSPAccess() }

        let center = NotificationCenter.default
        observers.append((center, center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refreshAuthorization() }
        }))
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        observers.append((workspaceCenter, workspaceCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.engine.handleWillSleep() }
        }))
        observers.append((workspaceCenter, workspaceCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.engine.handleDidWake() }
        }))
    }

    func refreshAuthorization() {
        guard !isAuthorized else { return }
        if ensureAuthorized() { scheduleReconcile() }
    }

    private func ensureAuthorized() -> Bool {
        if !isAuthorized, CGPreflightScreenCaptureAccess() {
            isAuthorized = true
            engine.startProcessMonitoring()
        }
        return isAuthorized
    }

    // MARK: - DSP Controls (UI to Engine Bridge)

    func notifyAdjustmentMade(for bundleID: String) {
        scheduleReconcile()
    }

    func setAppVolume(bundleID: String, volume: Float) {
        pushAppParameters(for: bundleID)
    }

    func setAppMute(bundleID: String, isMuted: Bool) {
        pushAppParameters(for: bundleID)
    }

    func setAppEQ(bundleID: String, gains: [Double], bassGain: Double = 0.0) {
        pushAppParameters(for: bundleID)
    }

    func eightDAudioSettings(for bundleID: String) -> EightDAudioSettings {
        guard PremiumGate.hasAccess(.audio8D) else { return EightDAudioSettings() }
        return eightDAudioSettingsByBundleID[bundleID] ?? EightDAudioSettings()
    }

    private func applyPremiumDSPAccess() {
        pushAllParameters()
        objectWillChange.send()
        scheduleReconcile()
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

        pushAppParameters(for: bundleID)
        if previous.enabled != clamped.enabled {
            objectWillChange.send()
            scheduleReconcile()
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

        pushAppParameters(for: bundleID)
        if previous.enabled != clamped.enabled {
            objectWillChange.send()
            scheduleReconcile()
        }
    }

    func resetEightDAudio(for bundleID: String) {
        eightDAudioSettingsByBundleID.removeValue(forKey: bundleID)
        persistEightDAudioSettings()
        pushAppParameters(for: bundleID)
        objectWillChange.send()
        scheduleReconcile()
    }

    func resetSurroundAudio(for bundleID: String) {
        surroundAudioSettingsByBundleID.removeValue(forKey: bundleID)
        persistSurroundAudioSettings()
        pushAppParameters(for: bundleID)
        objectWillChange.send()
        scheduleReconcile()
    }

    func clearAllEightDAudioSettings() {
        let affected = Set(eightDAudioSettingsByBundleID.keys).union(surroundAudioSettingsByBundleID.keys)
        eightDAudioSettingsByBundleID.removeAll()
        surroundAudioSettingsByBundleID.removeAll()
        persistEightDAudioSettings()
        persistSurroundAudioSettings()
        affected.forEach { pushAppParameters(for: $0) }
        objectWillChange.send()
        scheduleReconcile()
    }

    func updateSettings(for deviceID: AudioDeviceID, settings: AudioDeviceSettings) {
        let previous = deviceSettings[deviceID] ?? AudioDeviceSettings()
        guard previous != settings else { return }
        self.deviceSettings[deviceID] = settings
        guard let uid = availableOutputDevices.first(where: { $0.id == deviceID })?.uid else { return }
        settingsByUID[uid] = settings
        scheduleSettingsPersistence()
        engine.state.setDeviceParameters(DeviceTapParameters(settings), forUID: uid)
        if Self.requiresProcessing(previous) != Self.requiresProcessing(settings) {
            scheduleReconcile()
        }
    }

    func clearAllDeviceSettings() {
        for uid in settingsByUID.keys {
            engine.state.setDeviceParameters(DeviceTapParameters(), forUID: uid)
        }
        settingsByUID.removeAll()
        deviceSettings.removeAll()
        UserDefaults.standard.removeObject(forKey: deviceSettingsDefaultsKey)
        notifyAdjustmentMade(for: "ResetAll")
    }

    func resetAllTaps() {
        engine.rebuildAll()
    }

    private func appParameters(for bundleID: String) -> AppTapParameters {
        let perApp = PerAppAudioController.shared
        return AppTapParameters(
            volume: Float(perApp.volume(for: bundleID)),
            muted: perApp.mute(for: bundleID),
            eqGains: perApp.eqGains(for: bundleID),
            eqBass: perApp.eqBass(for: bundleID),
            eqDeviceScope: perApp.targetDeviceUIDs(for: bundleID),
            eightD: eightDAudioSettings(for: bundleID),
            surround: surroundAudioSettings(for: bundleID)
        )
    }

    private func pushAppParameters(for bundleID: String) {
        engine.state.setAppParameters(appParameters(for: bundleID), for: bundleID)
    }

    private func pushAllParameters() {
        let bundles = PerAppAudioController.shared.adjustedBundleIDs()
            .union(eightDAudioSettingsByBundleID.keys)
            .union(surroundAudioSettingsByBundleID.keys)
            .union(engine.state.snapshot().keys)
        bundles.forEach { pushAppParameters(for: $0) }
        for (uid, settings) in settingsByUID {
            engine.state.setDeviceParameters(DeviceTapParameters(settings), forUID: uid)
        }
    }

    // MARK: - Per-app routing, order and visibility

    func route(for bundleID: String) -> String? { appRoutes[bundleID] }

    func setRoute(_ uid: String?, for bundleID: String) {
        guard appRoutes[bundleID] != uid else { return }
        if let uid { appRoutes[bundleID] = uid } else { appRoutes.removeValue(forKey: bundleID) }
        UserDefaults.standard.set(appRoutes, forKey: appRoutesDefaultsKey)
        scheduleReconcile()
    }

    func togglePin(_ bundleID: String) {
        appOrdering.togglePin(bundleID)
        persistAppOrdering()
    }

    func move(_ bundleID: String, offset: Int, visible: [String]) {
        appOrdering.move(bundleID, offset: offset, visible: visible)
        persistAppOrdering()
    }

    func hideApp(_ bundleID: String) {
        appOrdering.hide(bundleID)
        persistAppOrdering()
    }

    func unhideApp(_ bundleID: String) {
        appOrdering.unhide(bundleID)
        persistAppOrdering()
    }

    func unhideAllApps() {
        appOrdering.unhideAll()
        persistAppOrdering()
    }

    private func persistAppOrdering() {
        if let data = try? JSONEncoder().encode(appOrdering) {
            UserDefaults.standard.set(data, forKey: appOrderingDefaultsKey)
        }
    }

    // MARK: - Output devices

    func setSystemDefaultOutput(uid: String, completion: (@Sendable (Bool) -> Void)? = nil) {
        engine.setDefaultDevice(uid: uid, input: false, completion: completion)
    }

    // MARK: - Input Device Controls

    func selectInputDevice(_ device: AudioDevice) {
        preferredInputUID = device.uid
        UserDefaults.standard.set(device.uid, forKey: preferredInputDefaultsKey)
        currentInputDeviceID = device.id
        engine.setDefaultDevice(uid: device.uid, input: true)
    }

    func clearPreferredInput() {
        preferredInputUID = nil
        UserDefaults.standard.removeObject(forKey: preferredInputDefaultsKey)
    }

    func setInputMute(_ mute: Bool, for deviceID: AudioDeviceID) {
        setAllInputMutes(mute)
    }

    func setAllInputMutes(_ mute: Bool) {
        let deviceIDs = Array(Set(availableInputDevices.map(\.id)).union(inputMutes.keys))
        var updated = inputMutes
        for id in inputMutes.keys { updated[id] = mute }
        inputMutes = updated
        engine.setInputMute(mute, deviceIDs: deviceIDs)
        MicrophoneUsageManager.shared.applyExternalMuteState(mute)
    }

    func isInputMuted(for deviceID: AudioDeviceID) -> Bool {
        inputMutes[deviceID] ?? false
    }

    var areAllInputsMuted: Bool {
        !inputMutes.isEmpty && inputMutes.values.allSatisfy { $0 }
    }

    func getInputVolume(for deviceID: AudioDeviceID) -> Float {
        inputVolumes[deviceID] ?? 1.0
    }

    func setInputVolume(_ volume: Float, for deviceID: AudioDeviceID) {
        let clamped = min(max(volume, 0), 1)
        guard inputVolumes[deviceID] != clamped else { return }
        inputVolumes[deviceID] = clamped
        engine.setInputVolume(clamped, deviceID: deviceID)
    }

    // MARK: - Reconcile

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
        guard ensureAuthorized() else { return }
        engine.setFrontmostBundleID(ActiveAppMonitor.shared.activeAppBundleID)
        engine.submit(makePlan())
    }

    private func makePlan() -> MixerPlan {
        var available = Set(availableOutputDevices.map(\.uid))
        if let defaultOutputUID { available.insert(defaultOutputUID) }
        let selectedUIDs = availableOutputDevices
            .filter { selectedOutputDeviceIDs.contains($0.id) }
            .map(\.uid)
            .sorted()
        let globalOutputs = MixerRouting.globalOutputUIDs(selectedUIDs: selectedUIDs, availableUIDs: available, defaultUID: defaultOutputUID)

        var tapAll = selectedOutputDeviceIDs.count > 1
        if selectedOutputDeviceIDs.count == 1, let selected = selectedOutputDeviceIDs.first,
           let defaultOutputDeviceID, selected != defaultOutputDeviceID {
            tapAll = true
        }
        if !tapAll {
            tapAll = globalOutputs.contains { uid in settingsByUID[uid].map(Self.requiresProcessing) ?? false }
        }

        var adjusted = PerAppAudioController.shared.adjustedBundleIDs()
        for (bundleID, settings) in eightDAudioSettingsByBundleID where settings.enabled && PremiumGate.hasAccess(.audio8D) {
            adjusted.insert(bundleID)
        }
        for (bundleID, settings) in surroundAudioSettingsByBundleID where settings.enabled && PremiumGate.hasAccess(.surroundSound) {
            adjusted.insert(bundleID)
        }
        return MixerPlan(globalOutputUIDs: globalOutputs, tapAllAudibleApps: tapAll, adjustedBundleIDs: adjusted, routes: appRoutes)
    }

    private func applyActiveBundles(_ bundles: Set<String>) {
        let now = Date()
        for bundleID in bundles { lastAudioActivityByBundleID[bundleID] = now }
        lastAudioActivityByBundleID = lastAudioActivityByBundleID.filter {
            now.timeIntervalSince($0.value) <= recentAudioPriorityWindow * 4
        }
        if bundles != latestActiveBundleIDs {
            latestActiveBundleIDs = bundles
            NotificationCenter.default.post(name: .multiAudioActiveBundlesDidChange, object: self)
        }
    }

    // MARK: - Device snapshots

    private func apply(_ snapshot: MixerDeviceSnapshot) {
        let previouslySelectedUIDs = Set(
            availableOutputDevices
                .filter { selectedOutputDeviceIDs.contains($0.id) }
                .map(\.uid)
            + (UserDefaults.standard.stringArray(forKey: selectedOutputUIDsDefaultsKey) ?? [])
        )
        let outputsChanged = availableOutputDevices != snapshot.outputs
            || defaultOutputDeviceID != snapshot.defaultOutputID
            || defaultOutputUID != snapshot.defaultOutputUID
        let inputsChanged = availableInputDevices != snapshot.inputs || currentInputDeviceID != snapshot.defaultInputID
            || inputMutes != snapshot.inputMutes
        if availableOutputDevices != snapshot.outputs { availableOutputDevices = snapshot.outputs }
        if availableInputDevices != snapshot.inputs { availableInputDevices = snapshot.inputs }
        if defaultOutputDeviceID != snapshot.defaultOutputID { defaultOutputDeviceID = snapshot.defaultOutputID }
        if defaultOutputUID != snapshot.defaultOutputUID { defaultOutputUID = snapshot.defaultOutputUID }
        if currentInputDeviceID != snapshot.defaultInputID { currentInputDeviceID = snapshot.defaultInputID }
        if inputVolumes != snapshot.inputVolumes { inputVolumes = snapshot.inputVolumes }
        if inputMutes != snapshot.inputMutes { inputMutes = snapshot.inputMutes }
        if inputsChanged {
            enforcePreferredInput(snapshot)
            MicrophoneUsageManager.shared.inputDevicesDidChange()
        }
        if outputsChanged || !hasAppliedSnapshot {
            hasAppliedSnapshot = true
            rematchSelectedDevices(to: previouslySelectedUIDs)
            AudioOutputSwitcher.shared.devicesDidChange(snapshot)
            scheduleReconcile()
        }
    }

    private func enforcePreferredInput(_ snapshot: MixerDeviceSnapshot) {
        guard let target = PreferredInputPolicy.deviceToSelect(
            preferredUID: preferredInputUID,
            currentDefaultUID: snapshot.defaultInputUID,
            availableUIDs: Set(snapshot.inputs.map(\.uid))
        ) else { return }
        let now = Date()
        preferredInputEnforcements.removeAll { now.timeIntervalSince($0) > 10 }
        guard preferredInputEnforcements.count < 3 else { return }
        preferredInputEnforcements.append(now)
        engine.setDefaultDevice(uid: target, input: true)
    }

    // MARK: - Device Settings Persistence

    private func loadPersistedDeviceState() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: deviceSettingsDefaultsKey),
           let decoded = try? JSONDecoder().decode([String: AudioDeviceSettings].self, from: data) {
            settingsByUID = decoded
        }
        if let data = defaults.data(forKey: eightDAudioDefaultsKey),
           let decoded = try? JSONDecoder().decode([String: EightDAudioSettings].self, from: data) {
            eightDAudioSettingsByBundleID = decoded
        }
        if let data = defaults.data(forKey: surroundAudioDefaultsKey),
           let decoded = try? JSONDecoder().decode([String: SurroundAudioSettings].self, from: data) {
            surroundAudioSettingsByBundleID = decoded
        }
        if let routes = defaults.dictionary(forKey: appRoutesDefaultsKey) as? [String: String] {
            appRoutes = routes.filter { !$0.key.isEmpty && !$0.value.isEmpty }
        }
        if let data = defaults.data(forKey: appOrderingDefaultsKey),
           let decoded = try? JSONDecoder().decode(MixerAppOrdering.self, from: data) {
            appOrdering = decoded
        }
        preferredInputUID = defaults.string(forKey: preferredInputDefaultsKey)
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
        if live != deviceSettings { deviceSettings = live }
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
    }

    func activeAudioBundleIDs() -> Set<String> {
        guard ensureAuthorized() else { return [] }
        return latestActiveBundleIDs
    }

    func lastAudioActivityDate(for bundleID: String) -> Date? {
        lastAudioActivityByBundleID[bundleID]
    }

    func isRecentlyOutputtingAudio(_ bundleID: String, within window: TimeInterval = 180) -> Bool {
        guard let date = lastAudioActivityByBundleID[bundleID] else { return false }
        return Date().timeIntervalSince(date) <= window
    }

    // MARK: - Device format (read on the HAL queue)

    func loadFormatInfo(for deviceID: AudioDeviceID, completion: @escaping @Sendable (MixerEngine.DeviceFormatInfo) -> Void) {
        engine.readFormatInfo(deviceID: deviceID, completion: completion)
    }

    func setNominalSampleRate(_ rate: Double, for deviceID: AudioDeviceID) {
        engine.setNominalSampleRate(rate, deviceID: deviceID)
    }
}

// MARK: - Call Audio Attribution
enum CallAudioAttribution {
    static let callAudioDaemonBundleIDs: Set<String> = [
        "com.apple.avconferenced",
        "com.apple.TelephonyUtilities"
    ]
    static let callingAppBundleIDs = ["com.apple.FaceTime", "com.apple.mobilephone"]

    static func callingApp(
        forDaemonBundleID daemonBundleID: String?,
        frontmostBundleID: String?,
        isRunning: (String) -> Bool
    ) -> String? {
        guard let daemonBundleID, callAudioDaemonBundleIDs.contains(daemonBundleID) else { return nil }
        if let frontmostBundleID, callingAppBundleIDs.contains(frontmostBundleID) { return frontmostBundleID }
        return callingAppBundleIDs.first(where: isRunning)
    }
}

// MARK: - Sapphire Process Tap Controller
final class AppTapController {
    let bundleID: String
    let targetDeviceUID: String
    private(set) var processObjectIDs: [AudioObjectID]
    private(set) var tapID: AudioObjectID = 0
    private(set) var aggregateDeviceID: AudioObjectID = 0
    private var procID: AudioDeviceIOProcID?
    private let tapDescription: CATapDescription
    private let ioQueue: DispatchQueue
    private let ioQueueToken = UUID()
    private static let ioQueueKey = DispatchSpecificKey<UUID>()

    private struct EQKey: Equatable {
        var gains: [Double]
        var bass: Double
    }

    private let parameterLock: UnsafeMutablePointer<os_unfair_lock_s>
    private var appVolume: Float = 1.0
    private var isAppMuted = false
    private var appEqKey = EQKey(gains: AudioEQ.flat, bass: 0)
    private var deviceVolume: Float = 1.0
    private var deviceBalance: Float = 0.5
    private var deviceDelay: Float = 0.0
    private var deviceEqKey = EQKey(gains: AudioEQ.flat, bass: 0)
    private var eqSampleRate: Double
    private var installedEQ: (app: EQKey, device: EQKey, sampleRate: Double)?
    private var pendingEightDSettings = EightDAudioSettings()
    private var pendingSurroundSettings = SurroundAudioSettings()
    private var isInvalidated = false

    private var renderAppVolume: Float = 1.0
    private var renderAppMuted = false
    private var renderDeviceVolume: Float = 1.0
    private var renderDeviceBalance: Float = 0.5
    private var renderDeviceDelay: Float = 0.0
    private var renderEightDSettings = EightDAudioSettings()
    private var renderSurroundSettings = SurroundAudioSettings()
    private var renderGain: Float = 0
    private let renderCounter: UnsafeMutablePointer<UInt64>
    private let primaryLimiter: LookaheadLimiter
    private let secondaryLimiter: LookaheadLimiter

    private let primaryEQ = GraphicEQProcessor()
    private let secondaryEQ = GraphicEQProcessor()
    private let designQueue = DispatchQueue(label: "com.sapphire.audiotap.eq-design", qos: .userInitiated)
    private var sampleRateListener: AudioObjectPropertyListenerBlock?
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
    private var currentSampleRate: Double

    var renderCount: UInt64 { renderCounter.pointee }

    init(bundleID: String, processObjectIDs: [AudioObjectID], targetDeviceUID: String, sampleRate: Double) throws {
        self.bundleID = bundleID
        self.processObjectIDs = processObjectIDs
        self.targetDeviceUID = targetDeviceUID
        self.currentSampleRate = sampleRate
        self.roomTapOffsets = Self.roomTapTimes.map { min(Int($0 * sampleRate), Self.roomBufferSamples - 1) }
        _ = Self.roomTapGains

        parameterLock = .allocate(capacity: 1)
        parameterLock.initialize(to: os_unfair_lock_s())
        renderCounter = .allocate(capacity: 1)
        renderCounter.initialize(to: 0)
        primaryLimiter = LookaheadLimiter(sampleRate: sampleRate, lookaheadSeconds: 0.002)
        secondaryLimiter = LookaheadLimiter(sampleRate: sampleRate, lookaheadSeconds: 0.002)

        eqSampleRate = sampleRate

        delayBufferL = .allocate(capacity: maxDelaySamples); delayBufferR = .allocate(capacity: maxDelaySamples)
        delayBufferL.initialize(repeating: 0, count: maxDelaySamples); delayBufferR.initialize(repeating: 0, count: maxDelaySamples)
        eightDDelayL = .allocate(capacity: Self.eightDDelaySamples); eightDDelayR = .allocate(capacity: Self.eightDDelaySamples)
        eightDDelayL.initialize(repeating: 0, count: Self.eightDDelaySamples); eightDDelayR.initialize(repeating: 0, count: Self.eightDDelaySamples)
        eightDReverbL = .allocate(capacity: Self.roomBufferSamples); eightDReverbR = .allocate(capacity: Self.roomBufferSamples)
        eightDReverbL.initialize(repeating: 0, count: Self.roomBufferSamples); eightDReverbR.initialize(repeating: 0, count: Self.roomBufferSamples)
        surroundDelayL = .allocate(capacity: Self.surroundDelaySamples); surroundDelayR = .allocate(capacity: Self.surroundDelaySamples)
        surroundDelayL.initialize(repeating: 0, count: Self.surroundDelaySamples); surroundDelayR.initialize(repeating: 0, count: Self.surroundDelaySamples)

        ioQueue = DispatchQueue(label: "com.sapphire.audiotap.\(bundleID)", qos: .userInteractive)
        ioQueue.setSpecific(key: Self.ioQueueKey, value: ioQueueToken)

        tapDescription = CATapDescription(stereoMixdownOfProcesses: processObjectIDs)
        tapDescription.uuid = UUID()
        tapDescription.muteBehavior = .mutedWhenTapped
        tapDescription.isPrivate = true

        guard #available(macOS 14.2, *) else {
            invalidate()
            throw NSError(domain: "TapError", code: Int(kAudioHardwareUnsupportedOperationError))
        }
        var err = AudioHardwareCreateProcessTap(tapDescription, &tapID)
        guard err == noErr else {
            invalidate()
            throw NSError(domain: "TapError", code: Int(err))
        }

        let aggregateDescription: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Sapphire-\(bundleID.split(separator: ".").last ?? "App")",
            kAudioAggregateDeviceUIDKey: UUID().uuidString, kAudioAggregateDeviceMainSubDeviceKey: targetDeviceUID,
            kAudioAggregateDeviceClockDeviceKey: targetDeviceUID, kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: true, kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: targetDeviceUID]],
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapDriftCompensationKey: false, kAudioSubTapUIDKey: tapDescription.uuid.uuidString]]
        ]

        err = AudioHardwareCreateAggregateDevice(aggregateDescription as CFDictionary, &aggregateDeviceID)
        guard err == noErr else {
            invalidate()
            throw NSError(domain: "AggregateError", code: Int(err))
        }
    }

    deinit {
        invalidate()
        parameterLock.deinitialize(count: 1)
        parameterLock.deallocate()
        renderCounter.deallocate()
    }

    func activate() throws {
        var err = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateDeviceID, ioQueue) { [weak self] _, inData, _, outData, _ in
            self?.process(inData, outData)
        }
        guard err == noErr, let procID else { throw NSError(domain: "IOProcError", code: Int(err)) }
        err = AudioDeviceStart(aggregateDeviceID, procID)
        guard err == noErr else { throw NSError(domain: "DeviceStartError", code: Int(err)) }
        observeSampleRate()
    }

    func updateProcesses(_ objectIDs: [AudioObjectID]) -> Bool {
        guard !objectIDs.isEmpty, tapID != 0 else { return false }
        let previous = tapDescription.processes
        tapDescription.processes = objectIDs
        var address = AudioObjectPropertyAddress(mSelector: kAudioTapPropertyDescription, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var description: CATapDescription = tapDescription
        let status = withUnsafeMutablePointer(to: &description) { pointer in
            AudioObjectSetPropertyData(tapID, &address, 0, nil, UInt32(MemoryLayout<CATapDescription>.size), pointer)
        }
        guard status == noErr else {
            tapDescription.processes = previous
            return false
        }
        processObjectIDs = objectIDs
        return true
    }

    func invalidate() {
        os_unfair_lock_lock(parameterLock)
        let alreadyInvalidated = isInvalidated
        isInvalidated = true
        os_unfair_lock_unlock(parameterLock)
        guard !alreadyInvalidated else { return }

        if let procID {
            AudioDeviceStop(aggregateDeviceID, procID)
            AudioDeviceDestroyIOProcID(aggregateDeviceID, procID)
            self.procID = nil
        }
        if DispatchQueue.getSpecific(key: Self.ioQueueKey) != ioQueueToken {
            ioQueue.sync {}
        }
        if let sampleRateListener {
            var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyNominalSampleRate, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            AudioObjectRemovePropertyListenerBlock(aggregateDeviceID, &address, designQueue, sampleRateListener)
            self.sampleRateListener = nil
        }
        if aggregateDeviceID != 0 {
            AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
            aggregateDeviceID = 0
        }
        if tapID != 0, #available(macOS 14.2, *) {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = 0
        }

        delayBufferL.deallocate(); delayBufferR.deallocate()
        eightDDelayL.deallocate(); eightDDelayR.deallocate()
        eightDReverbL.deallocate(); eightDReverbR.deallocate()
        surroundDelayL.deallocate(); surroundDelayR.deallocate()
    }

    func updateAppVolume(_ volume: Float) {
        os_unfair_lock_lock(parameterLock)
        appVolume = min(max(volume, 0), PerAppAudioController.maxVolume)
        os_unfair_lock_unlock(parameterLock)
    }

    func updateAppMute(_ muted: Bool) {
        os_unfair_lock_lock(parameterLock)
        isAppMuted = muted
        os_unfair_lock_unlock(parameterLock)
    }

    func updateDeviceControls(volume: Float, balance: Float, delay: Float) {
        os_unfair_lock_lock(parameterLock)
        deviceVolume = volume
        deviceBalance = balance
        deviceDelay = delay
        os_unfair_lock_unlock(parameterLock)
    }

    func updateEightDAudio(settings: EightDAudioSettings) {
        os_unfair_lock_lock(parameterLock)
        pendingEightDSettings = settings
        os_unfair_lock_unlock(parameterLock)
    }

    func updateSurroundAudio(settings: SurroundAudioSettings) {
        os_unfair_lock_lock(parameterLock)
        pendingSurroundSettings = settings
        os_unfair_lock_unlock(parameterLock)
    }

    func updateAppEQ(gains: [Double], bassGain: Double = 0.0) {
        installEQ(EQKey(gains: AudioEQ.normalize(gains), bass: bassGain), isApp: true)
    }

    func updateDeviceEQ(gains: [Double], bassGain: Double = 0.0) {
        installEQ(EQKey(gains: AudioEQ.normalize(gains), bass: bassGain), isApp: false)
    }

    private func installEQ(_ key: EQKey, isApp: Bool) {
        os_unfair_lock_lock(parameterLock)
        if isApp { appEqKey = key } else { deviceEqKey = key }
        os_unfair_lock_unlock(parameterLock)
        scheduleEQDesign()
    }

    private func scheduleEQDesign() {
        designQueue.async { [weak self] in
            guard let self else { return }
            os_unfair_lock_lock(self.parameterLock)
            let app = self.appEqKey, device = self.deviceEqKey, rate = self.eqSampleRate
            let invalidated = self.isInvalidated
            os_unfair_lock_unlock(self.parameterLock)
            guard !invalidated else { return }
            if let installed = self.installedEQ, installed.app == app, installed.device == device, installed.sampleRate == rate { return }
            self.installedEQ = (app, device, rate)

            let gains = zip(app.gains, device.gains).map { $0 + $1 }
            let design = GraphicEQDesigner.design(gains: gains, bass: app.bass + device.bass, sampleRate: rate)
            self.primaryEQ.post(design)
            self.secondaryEQ.post(design)
        }
    }

    private func observeSampleRate() {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyNominalSampleRate, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            guard let self else { return }
            var rate: Float64 = 0
            var size = UInt32(MemoryLayout<Float64>.size)
            var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyNominalSampleRate, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            guard AudioObjectGetPropertyData(self.aggregateDeviceID, &address, 0, nil, &size, &rate) == noErr, rate > 0 else { return }
            os_unfair_lock_lock(self.parameterLock)
            self.eqSampleRate = rate
            os_unfair_lock_unlock(self.parameterLock)
            self.scheduleEQDesign()
        }
        if AudioObjectAddPropertyListenerBlock(aggregateDeviceID, &address, designQueue, listener) == noErr {
            sampleRateListener = listener
        }
    }

    @_optimize(speed)
    private func process(_ inData: UnsafePointer<AudioBufferList>, _ outData: UnsafeMutablePointer<AudioBufferList>) {
        renderCounter.pointee &+= 1
        let inBuffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inData))
        let outBuffers = UnsafeMutableAudioBufferListPointer(outData)

        if os_unfair_lock_trylock(parameterLock) {
            renderAppVolume = appVolume
            renderAppMuted = isAppMuted
            renderDeviceVolume = deviceVolume
            renderDeviceBalance = deviceBalance
            renderDeviceDelay = deviceDelay
            renderEightDSettings = pendingEightDSettings
            renderSurroundSettings = pendingSurroundSettings
            os_unfair_lock_unlock(parameterLock)
        }
        let targetGain = renderAppMuted ? 0 : renderAppVolume * renderDeviceVolume
        let startGain = renderGain
        renderGain = targetGain
        let needs8D = renderEightDSettings.enabled
        let needsSurround = renderSurroundSettings.enabled

        for i in 0..<outBuffers.count {
            guard let outBytes = outBuffers[i].mData else { continue }
            let outSampleCount = Int(outBuffers[i].mDataByteSize) / MemoryLayout<Float>.size
            guard i < inBuffers.count, let inBytes = inBuffers[i].mData else {
                memset(outBytes, 0, Int(outBuffers[i].mDataByteSize))
                continue
            }
            let channels = max(1, Int(outBuffers[i].mNumberChannels))
            let inSampleCount = Int(inBuffers[i].mDataByteSize) / MemoryLayout<Float>.size
            let frameCount = min(outSampleCount, inSampleCount) / channels
            let outPtr = outBytes.assumingMemoryBound(to: Float.self)
            let inPtr = inBytes.assumingMemoryBound(to: Float.self)
            if frameCount * channels < outSampleCount {
                outPtr.advanced(by: frameCount * channels).update(repeating: 0, count: outSampleCount - frameCount * channels)
            }
            guard frameCount > 0 else { continue }

            GainRamp.apply(input: inPtr, output: outPtr, frames: frameCount, channels: channels, from: startGain, to: targetGain)

            if channels == 2, i < 2 {
                (i == 0 ? primaryEQ : secondaryEQ).process(outPtr, frames: frameCount)
            }

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

            switch i {
            case 0: primaryLimiter.process(outPtr, frames: frameCount, channels: channels)
            case 1: secondaryLimiter.process(outPtr, frames: frameCount, channels: channels)
            default:
                for index in 0..<(frameCount * channels) {
                    outPtr[index] = LookaheadLimiter.softKnee(outPtr[index], ceiling: primaryLimiter.ceiling)
                }
            }
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

extension Notification.Name {
    static let multiAudioActiveBundlesDidChange = Notification.Name("multiAudioActiveBundlesDidChange")
    static let perAppAudioSettingsDidChange = Notification.Name("perAppAudioSettingsDidChange")
}