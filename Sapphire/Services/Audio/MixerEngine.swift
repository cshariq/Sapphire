//
//  MixerEngine.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-10-07
//

import Foundation
import CoreAudio
import AudioToolbox
import Darwin
import OSLog

// MARK: - Value types shared with the main actor

struct AppTapParameters: Equatable {
    var volume: Float = 1
    var muted = false
    var eqGains: [Double] = AudioEQ.flat
    var eqBass: Double = 0
    var eqDeviceScope: Set<String>?
    var eightD = EightDAudioSettings()
    var surround = SurroundAudioSettings()

    func appliesEQ(toDeviceUID uid: String) -> Bool { eqDeviceScope?.contains(uid) ?? true }
}

struct DeviceTapParameters: Equatable {
    var volume: Float = 1
    var balance: Float = 0.5
    var delay: Float = 0
    var eqGains: [Double] = AudioEQ.flat
    var bass: Double = 0

    init() {}

    init(_ settings: AudioDeviceSettings) {
        volume = Float(settings.volume)
        balance = Float(settings.balance)
        delay = Float(settings.delay)
        eqGains = settings.customEQGains
        bass = settings.bassGain
    }
}

struct MixerPlan: Equatable {
    var globalOutputUIDs: [String] = []
    var tapAllAudibleApps = false
    var adjustedBundleIDs: Set<String> = []
    var routes: [String: String] = [:]
}

struct MixerDeviceSnapshot: Equatable {
    var outputs: [AudioDevice] = []
    var inputs: [AudioDevice] = []
    var defaultOutputID: AudioDeviceID?
    var defaultOutputUID: String?
    var defaultInputID: AudioDeviceID?
    var defaultInputUID: String?
    var inputVolumes: [AudioDeviceID: Float] = [:]
    var inputMutes: [AudioDeviceID: Bool] = [:]
}

struct MixerTapKey: Hashable, Comparable {
    let bundleID: String
    let deviceUID: String

    static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.bundleID, lhs.deviceUID) < (rhs.bundleID, rhs.deviceUID)
    }
}

// MARK: - Tap registry + live parameters

final class MixerSharedState: @unchecked Sendable {
    private let lock = NSLock()
    private var taps: [String: [String: AppTapController]] = [:]
    private var appParameters: [String: AppTapParameters] = [:]
    private var deviceParameters: [String: DeviceTapParameters] = [:]

    func setAppParameters(_ parameters: AppTapParameters, for bundleID: String) {
        lock.lock(); defer { lock.unlock() }
        guard appParameters[bundleID] != parameters else { return }
        appParameters[bundleID] = parameters
        taps[bundleID]?.values.forEach { Self.apply(parameters, to: $0) }
    }

    func setDeviceParameters(_ parameters: DeviceTapParameters, forUID uid: String) {
        lock.lock(); defer { lock.unlock() }
        guard deviceParameters[uid] != parameters else { return }
        deviceParameters[uid] = parameters
        for tapMap in taps.values {
            if let tap = tapMap[uid] { Self.apply(parameters, to: tap) }
        }
    }

    func install(_ tap: AppTapController) {
        lock.lock(); defer { lock.unlock() }
        taps[tap.bundleID, default: [:]][tap.targetDeviceUID] = tap
        Self.apply(appParameters[tap.bundleID] ?? AppTapParameters(), to: tap)
        Self.apply(deviceParameters[tap.targetDeviceUID] ?? DeviceTapParameters(), to: tap)
    }

    @discardableResult
    func remove(_ key: MixerTapKey) -> AppTapController? {
        lock.lock(); defer { lock.unlock() }
        let tap = taps[key.bundleID]?.removeValue(forKey: key.deviceUID)
        if taps[key.bundleID]?.isEmpty == true { taps.removeValue(forKey: key.bundleID) }
        return tap
    }

    func removeAll() -> [AppTapController] {
        lock.lock(); defer { lock.unlock() }
        let all = taps.values.flatMap(\.values)
        taps.removeAll()
        return all
    }

    func tap(for key: MixerTapKey) -> AppTapController? {
        lock.lock(); defer { lock.unlock() }
        return taps[key.bundleID]?[key.deviceUID]
    }

    func allTaps() -> [AppTapController] {
        lock.lock(); defer { lock.unlock() }
        return taps.values.flatMap(\.values)
    }

    func snapshot() -> [String: [String: AppTapController]] {
        lock.lock(); defer { lock.unlock() }
        return taps
    }

    func hasTap(for bundleID: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return !(taps[bundleID]?.isEmpty ?? true)
    }

    private static func apply(_ parameters: AppTapParameters, to tap: AppTapController) {
        tap.updateAppVolume(parameters.volume)
        tap.updateAppMute(parameters.muted)
        tap.updateEightDAudio(settings: parameters.eightD)
        tap.updateSurroundAudio(settings: parameters.surround)
        let applies = parameters.appliesEQ(toDeviceUID: tap.targetDeviceUID)
        tap.updateAppEQ(gains: applies ? parameters.eqGains : AudioEQ.flat, bassGain: applies ? parameters.eqBass : 0)
    }

    private static func apply(_ parameters: DeviceTapParameters, to tap: AppTapController) {
        tap.updateDeviceControls(volume: parameters.volume, balance: parameters.balance, delay: parameters.delay)
        tap.updateDeviceEQ(gains: parameters.eqGains, bassGain: parameters.bass)
    }
}

// MARK: - Engine

final class MixerEngine: @unchecked Sendable {
    let state = MixerSharedState()

    var onDevices: (@Sendable (MixerDeviceSnapshot) -> Void)?
    var onActiveBundles: (@Sendable (Set<String>) -> Void)?
    var onProcessListChanged: (@Sendable () -> Void)?

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Sapphire", category: "MixerEngine")
    private let queue = DispatchQueue(label: "com.sapphire.mixer.hal", qos: .userInitiated)
    private let queueKey = DispatchSpecificKey<Void>()

    private let mailboxLock = NSLock()
    private var mailbox = LatestOnlyMailbox<MixerPlan>()

    private let frontmostLock = NSLock()
    private var frontmostBundleID: String?

    private struct ListenerRegistration {
        let objectID: AudioObjectID
        var address: AudioObjectPropertyAddress
        let block: AudioObjectPropertyListenerBlock
    }

    private var isStarted = false
    private var systemListeners: [ListenerRegistration] = []
    private var processListListener: ListenerRegistration?
    private var processRunningListeners: [AudioObjectID: ListenerRegistration] = [:]
    private var inputDeviceListeners: [AudioDeviceID: [ListenerRegistration]] = [:]
    private var pidByObject: [AudioObjectID: pid_t] = [:]
    private var bundleByObject: [AudioObjectID: String] = [:]
    private var deviceIDByUID: [String: AudioDeviceID] = [:]
    private var availableOutputUIDs: Set<String> = []
    private var staleUIDs: Set<String> = []
    private var failedOpen: Set<MixerTapKey> = []
    private var watchdog: [MixerTapKey: TapWatchdogState] = [:]
    private var watchdogTimer: DispatchSourceTimer?
    private var lastPlan: MixerPlan?
    private var processListDirty = true
    private var isSleeping = false
    private var isRescanScheduled = false

    private static let watchdogInterval: DispatchTimeInterval = .seconds(2)

    init() {
        queue.setSpecific(key: queueKey, value: ())
    }

    deinit {
        let registrations = systemListeners + Array(processRunningListeners.values)
            + inputDeviceListeners.values.flatMap { $0 } + [processListListener].compactMap { $0 }
        for registration in registrations {
            var address = registration.address
            AudioObjectRemovePropertyListenerBlock(registration.objectID, &address, queue, registration.block)
        }
        watchdogTimer?.cancel()
        state.removeAll().forEach { $0.invalidate() }
    }

    // MARK: Public API (any thread)

    func start() {
        queue.async { [self] in
            guard !isStarted else { return }
            isStarted = true
            installSystemListeners()
            rescanDevices()
        }
    }

    func startProcessMonitoring() {
        queue.async { [self] in
            guard processListListener == nil else { return }
            var address = Self.address(kAudioHardwarePropertyProcessObjectList)
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.processListDidChange() }
            if AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, queue, block) == noErr {
                processListListener = ListenerRegistration(objectID: AudioObjectID(kAudioObjectSystemObject), address: address, block: block)
            }
            processListDirty = true
        }
    }

    func setFrontmostBundleID(_ bundleID: String?) {
        frontmostLock.lock(); frontmostBundleID = bundleID; frontmostLock.unlock()
    }

    func submit(_ plan: MixerPlan, force: Bool = false) {
        mailboxLock.lock()
        let mustSchedule = mailbox.post(plan, force: force)
        mailboxLock.unlock()
        if mustSchedule { queue.async { [self] in drain() } }
    }

    private func resubmitForRebuild() {
        dispatchPrecondition(condition: .onQueue(queue))
        mailboxLock.lock()
        let mustSchedule = mailbox.forceRebuild(fallback: lastPlan)
        mailboxLock.unlock()
        if mustSchedule { queue.async { [self] in drain() } }
    }

    func rebuildAll() {
        queue.async { [self] in
            state.removeAll().forEach { $0.invalidate() }
            watchdog.removeAll()
            failedOpen.removeAll()
            processListDirty = true
            resubmitForRebuild()
        }
    }

    func handleWillSleep() {
        queue.async { [self] in
            isSleeping = true
            updateWatchdogTimer()
        }
    }

    func handleDidWake() {
        queue.async { [self] in
            isSleeping = false
            state.removeAll().forEach { $0.invalidate() }
            watchdog.removeAll()
            failedOpen.removeAll()
            processListDirty = true
            rescanDevices()
            resubmitForRebuild()
        }
    }

    func setInputMute(_ muted: Bool, deviceIDs: [AudioDeviceID]) {
        queue.async { [self] in
            deviceIDs.forEach { Self.writeInputMute(muted, to: $0) }
            scheduleRescan()
        }
    }

    func setInputVolume(_ volume: Float, deviceID: AudioDeviceID) {
        queue.async {
            var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar, mScope: kAudioObjectPropertyScopeInput, mElement: kAudioObjectPropertyElementMain)
            if !AudioObjectHasProperty(deviceID, &address) { address.mElement = 1 }
            guard AudioObjectHasProperty(deviceID, &address) else { return }
            var value = min(max(volume, 0), 1)
            AudioObjectSetPropertyData(deviceID, &address, 0, nil, UInt32(MemoryLayout<Float>.size), &value)
        }
    }

    func setDefaultDevice(uid: String, input: Bool, completion: (@Sendable (Bool) -> Void)? = nil) {
        queue.async {
            let ok = Self.setDefaultDevice(uid: uid, input: input)
            if let completion { DispatchQueue.main.async { completion(ok) } }
        }
    }

    func setNominalSampleRate(_ rate: Double, deviceID: AudioDeviceID) {
        queue.async {
            var address = Self.address(kAudioDevicePropertyNominalSampleRate)
            var value = rate
            AudioObjectSetPropertyData(deviceID, &address, 0, nil, UInt32(MemoryLayout<Double>.size), &value)
        }
    }

    struct DeviceFormatInfo: Sendable {
        var sampleRate: Double
        var availableRates: [Double]
        var streamFormat: String
    }

    func readFormatInfo(deviceID: AudioDeviceID, completion: @escaping @Sendable (DeviceFormatInfo) -> Void) {
        queue.async {
            let info = DeviceFormatInfo(
                sampleRate: Self.nominalSampleRate(deviceID),
                availableRates: Self.availableSampleRates(deviceID),
                streamFormat: Self.streamFormat(deviceID)
            )
            DispatchQueue.main.async { completion(info) }
        }
    }

    // MARK: Build

    private func drain() {
        dispatchPrecondition(condition: .onQueue(queue))
        while true {
            mailboxLock.lock()
            let next = mailbox.take()
            mailboxLock.unlock()
            guard let plan = next ?? (processListDirty ? lastPlan : nil) else { return }
            if build(plan) {
                mailboxLock.lock(); mailbox.markApplied(plan); mailboxLock.unlock()
            }
            if next == nil { return }
        }
    }

    private var hasNewerPlan: Bool {
        mailboxLock.lock(); defer { mailboxLock.unlock() }
        return mailbox.hasNewer
    }

    private func build(_ plan: MixerPlan) -> Bool {
        if plan != lastPlan { failedOpen.removeAll() }
        lastPlan = plan

        let groups = readAudibleProcessGroups()
        processListDirty = false
        onActiveBundles?(Set(groups.keys))

        var desired: [MixerTapKey: [AudioObjectID]] = [:]
        for (bundleID, objectIDs) in groups {
            let route = plan.routes[bundleID]
            let needsTap = plan.tapAllAudibleApps
                || plan.adjustedBundleIDs.contains(bundleID)
                || MixerRouting.routeRequiresTap(route: route, availableUIDs: availableOutputUIDs, globalOutputUIDs: plan.globalOutputUIDs)
            guard needsTap else { continue }
            let targets = MixerRouting.targetUIDs(route: route, availableUIDs: availableOutputUIDs, globalOutputUIDs: plan.globalOutputUIDs)
            for uid in targets where deviceIDByUID[uid] != nil {
                let key = MixerTapKey(bundleID: bundleID, deviceUID: uid)
                guard !failedOpen.contains(key) else { continue }
                desired[key] = objectIDs
            }
        }

        for tap in state.allTaps() {
            let key = MixerTapKey(bundleID: tap.bundleID, deviceUID: tap.targetDeviceUID)
            guard desired[key] == nil || staleUIDs.contains(key.deviceUID) else { continue }
            state.remove(key)
            tap.invalidate()
            if desired[key] == nil { watchdog.removeValue(forKey: key) }
        }
        staleUIDs.removeAll()

        defer { updateWatchdogTimer() }
        for (key, objectIDs) in desired.sorted(by: { $0.key < $1.key }) {
            if hasNewerPlan { return false }
            if let existing = state.tap(for: key) {
                if existing.processObjectIDs == objectIDs { continue }
                if existing.updateProcesses(objectIDs) { continue }
                state.remove(key)
                existing.invalidate()
            }
            createTap(key, processObjectIDs: objectIDs)
        }
        return true
    }

    @discardableResult
    private func createTap(_ key: MixerTapKey, processObjectIDs: [AudioObjectID]) -> Bool {
        guard let deviceID = deviceIDByUID[key.deviceUID] else { return false }
        let sampleRate = Self.nominalSampleRate(deviceID)
        let tap: AppTapController
        do {
            tap = try AppTapController(bundleID: key.bundleID, processObjectIDs: processObjectIDs, targetDeviceUID: key.deviceUID, sampleRate: sampleRate)
        } catch {
            logger.error("Could not tap \(key.bundleID, privacy: .public) → \(key.deviceUID, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return false
        }
        state.install(tap)
        do {
            try tap.activate()
        } catch {
            state.remove(key)
            tap.invalidate()
            logger.error("Could not start tap for \(key.bundleID, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return false
        }
        var health = watchdog[key] ?? TapWatchdogState()
        health.lastRenderCount = 0
        health.stalledChecks = 0
        health.healthyChecks = 0
        watchdog[key] = health
        return true
    }

    // MARK: Watchdog

    private func updateWatchdogTimer() {
        let shouldRun = !isSleeping && !state.allTaps().isEmpty
        if shouldRun, watchdogTimer == nil {
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now() + Self.watchdogInterval, repeating: Self.watchdogInterval, leeway: .milliseconds(500))
            timer.setEventHandler { [weak self] in self?.runWatchdog() }
            timer.resume()
            watchdogTimer = timer
        } else if !shouldRun, let timer = watchdogTimer {
            timer.cancel()
            watchdogTimer = nil
        }
    }

    private func runWatchdog() {
        guard !isSleeping else { return }
        for tap in state.allTaps() {
            let key = MixerTapKey(bundleID: tap.bundleID, deviceUID: tap.targetDeviceUID)
            var health = watchdog[key] ?? TapWatchdogState(lastRenderCount: tap.renderCount)
            let verdict = health.observe(renderCount: tap.renderCount)
            watchdog[key] = health
            switch verdict {
            case .healthy, .waiting:
                continue
            case .rebuild:
                logger.notice("Tap for \(key.bundleID, privacy: .public) stopped rendering; rebuilding once")
                let objectIDs = tap.processObjectIDs
                state.remove(key)
                tap.invalidate()
                if !createTap(key, processObjectIDs: objectIDs) { watchdog.removeValue(forKey: key) }
            case .failOpen:
                logger.error("Tap for \(key.bundleID, privacy: .public) died again; leaving the app unprocessed")
                state.remove(key)
                tap.invalidate()
                failedOpen.insert(key)
                watchdog.removeValue(forKey: key)
            }
        }
        updateWatchdogTimer()
    }

    // MARK: Listeners

    private func installSystemListeners() {
        let system = AudioObjectID(kAudioObjectSystemObject)
        for selector in [kAudioHardwarePropertyDevices, kAudioHardwarePropertyDefaultOutputDevice, kAudioHardwarePropertyDefaultInputDevice] {
            var address = Self.address(selector)
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.scheduleRescan() }
            if AudioObjectAddPropertyListenerBlock(system, &address, queue, block) == noErr {
                systemListeners.append(ListenerRegistration(objectID: system, address: address, block: block))
            }
        }
    }

    private func processListDidChange() {
        processListDirty = true
        onProcessListChanged?()
    }

    private func updateProcessRunningListeners(_ objectIDs: [AudioObjectID]) {
        let current = Set(objectIDs)
        for (objectID, registration) in processRunningListeners where !current.contains(objectID) {
            var address = registration.address
            AudioObjectRemovePropertyListenerBlock(objectID, &address, queue, registration.block)
            processRunningListeners.removeValue(forKey: objectID)
            pidByObject.removeValue(forKey: objectID)
            bundleByObject.removeValue(forKey: objectID)
        }
        for objectID in current where processRunningListeners[objectID] == nil {
            var address = Self.address(kAudioProcessPropertyIsRunning)
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.processListDidChange() }
            if AudioObjectAddPropertyListenerBlock(objectID, &address, queue, block) == noErr {
                processRunningListeners[objectID] = ListenerRegistration(objectID: objectID, address: address, block: block)
            }
        }
    }

    private func updateInputDeviceListeners(_ deviceIDs: [AudioDeviceID]) {
        let current = Set(deviceIDs)
        for (deviceID, registrations) in inputDeviceListeners where !current.contains(deviceID) {
            for registration in registrations {
                var address = registration.address
                AudioObjectRemovePropertyListenerBlock(deviceID, &address, queue, registration.block)
            }
            inputDeviceListeners.removeValue(forKey: deviceID)
        }
        for deviceID in current where inputDeviceListeners[deviceID] == nil {
            var registrations: [ListenerRegistration] = []
            for selector in [kAudioDevicePropertyVolumeScalar, kAudioDevicePropertyMute] {
                for element in [kAudioObjectPropertyElementMain, AudioObjectPropertyElement(1)] {
                    var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeInput, mElement: element)
                    guard AudioObjectHasProperty(deviceID, &address) else { continue }
                    let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.scheduleRescan() }
                    if AudioObjectAddPropertyListenerBlock(deviceID, &address, queue, block) == noErr {
                        registrations.append(ListenerRegistration(objectID: deviceID, address: address, block: block))
                    }
                    break
                }
            }
            inputDeviceListeners[deviceID] = registrations
        }
    }

    // MARK: Device scan

    private func scheduleRescan() {
        guard !isRescanScheduled else { return }
        isRescanScheduled = true
        queue.asyncAfter(deadline: .now() + .milliseconds(60)) { [weak self] in
            guard let self else { return }
            self.isRescanScheduled = false
            self.rescanDevices()
        }
    }

    private func rescanDevices() {
        dispatchPrecondition(condition: .onQueue(queue))
        guard let deviceIDs = CoreAudioDevices.all() else { return }
        var snapshot = MixerDeviceSnapshot()
        var uidMap: [String: AudioDeviceID] = [:]
        var inputIDs: [AudioDeviceID] = []

        snapshot.defaultOutputID = Self.defaultDevice(kAudioHardwarePropertyDefaultOutputDevice)
        snapshot.defaultInputID = Self.defaultDevice(kAudioHardwarePropertyDefaultInputDevice)

        for deviceID in deviceIDs {
            guard let name = CoreAudioDevices.name(of: deviceID), let uid = CoreAudioDevices.uid(of: deviceID) else { continue }
            if deviceID == snapshot.defaultOutputID { snapshot.defaultOutputUID = uid; uidMap[uid] = deviceID }
            if deviceID == snapshot.defaultInputID { snapshot.defaultInputUID = uid }
            guard !name.hasPrefix("Sapphire-"), !Self.isHiddenVirtualDevice(name: name, uid: uid) else { continue }

            let isInput = CoreAudioDevices.hasStreams(deviceID, scope: kAudioObjectPropertyScopeInput)
            let isOutput = CoreAudioDevices.hasStreams(deviceID, scope: kAudioObjectPropertyScopeOutput)
            let device = AudioDevice(id: deviceID, uid: uid, name: name, isInput: isInput, isOutput: isOutput)
            if isOutput {
                snapshot.outputs.append(device)
                uidMap[uid] = deviceID
            }
            if isInput {
                snapshot.inputs.append(device)
                inputIDs.append(deviceID)
                snapshot.inputVolumes[deviceID] = Self.readInputVolume(deviceID)
                if let muted = Self.readInputMute(deviceID) { snapshot.inputMutes[deviceID] = muted }
            }
        }
        snapshot.outputs.sort { $0.name < $1.name }
        snapshot.inputs.sort { $0.name < $1.name }

        for (uid, oldID) in deviceIDByUID where uidMap[uid] != oldID { staleUIDs.insert(uid) }
        let changedAvailability = Set(uidMap.keys) != availableOutputUIDs || !staleUIDs.isEmpty
        deviceIDByUID = uidMap
        availableOutputUIDs = Set(uidMap.keys)
        updateInputDeviceListeners(inputIDs)
        if changedAvailability { processListDirty = true }
        onDevices?(snapshot)
    }

    // MARK: Process groups

    private func readAudibleProcessGroups() -> [String: [AudioObjectID]] {
        let objectIDs = Self.processObjectList()
        updateProcessRunningListeners(objectIDs)
        let runningApps = RunningApps.shared.infoByPID()
        frontmostLock.lock(); let frontmost = frontmostBundleID; frontmostLock.unlock()
        let ownBundleID = Bundle.main.bundleIdentifier

        var groups: [String: [AudioObjectID]] = [:]
        for objectID in objectIDs {
            var isRunning: UInt32 = 0
            var size = UInt32(MemoryLayout<UInt32>.size)
            var runningAddress = Self.address(kAudioProcessPropertyIsRunning)
            if AudioObjectGetPropertyData(objectID, &runningAddress, 0, nil, &size, &isRunning) == noErr, isRunning == 0 { continue }

            let pid: pid_t
            if let cached = pidByObject[objectID] {
                pid = cached
            } else {
                var readPID: pid_t = 0
                var pidSize = UInt32(MemoryLayout<pid_t>.size)
                var pidAddress = Self.address(kAudioProcessPropertyPID)
                guard AudioObjectGetPropertyData(objectID, &pidAddress, 0, nil, &pidSize, &readPID) == noErr else { continue }
                pid = readPID
                pidByObject[objectID] = readPID
            }

            var bundleID = bundleByObject[objectID]
                ?? runningApps[pid]?.bundleID
                ?? Self.responsibleAppBundleID(for: pid, runningApps: runningApps)
            if let bundleID {
                bundleByObject[objectID] = bundleID
            } else {
                bundleID = CallAudioAttribution.callingApp(
                    forDaemonBundleID: Self.readProcessBundleID(objectID),
                    frontmostBundleID: frontmost,
                    isRunning: RunningApps.shared.isRunning
                )
            }
            if let bundleID, !bundleID.hasPrefix("com.apple.audio"), bundleID != ownBundleID {
                groups[bundleID, default: []].append(objectID)
            }
        }
        return groups.mapValues { Array(Set($0)).sorted() }
    }

    private static func responsibleAppBundleID(for pid: pid_t, runningApps: [pid_t: RunningApps.AppInfo]) -> String? {
        if let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -1), "responsibility_get_pid_responsible_for_pid") {
            let responsiblePID = unsafeBitCast(symbol, to: (@convention(c) (pid_t) -> pid_t).self)(pid)
            if responsiblePID > 0, responsiblePID != pid, let app = runningApps[responsiblePID] { return app.bundleID }
        }
        var currentPID = pid
        while currentPID > 1 {
            if let app = runningApps[currentPID], app.isAppBundle { return app.bundleID }
            var info = kinfo_proc()
            var size = MemoryLayout<kinfo_proc>.size
            var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, currentPID]
            guard sysctl(&mib, 4, &info, &size, nil, 0) == 0 else { break }
            let parentPID = info.kp_eproc.e_ppid
            if parentPID == currentPID { break }
            currentPID = parentPID
        }
        return nil
    }

    // MARK: HAL helpers (call on `queue`)

    private static func address(_ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private static func processObjectList() -> [AudioObjectID] {
        var address = Self.address(kAudioHardwarePropertyProcessObjectList)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == noErr else { return [] }
        return Array(ids.prefix(Int(size) / MemoryLayout<AudioObjectID>.size))
    }

    private static func readProcessBundleID(_ objectID: AudioObjectID) -> String? {
        var address = Self.address(kAudioProcessPropertyBundleID)
        var bundleID: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, &bundleID) == noErr, let bundleID else { return nil }
        let id = bundleID.takeRetainedValue() as String
        return id.isEmpty ? nil : id
    }

    static func defaultDevice(_ selector: AudioObjectPropertySelector) -> AudioDeviceID? {
        var id: AudioDeviceID = kAudioObjectUnknown
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = Self.address(selector)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id) == noErr,
              id != kAudioObjectUnknown else { return nil }
        return id
    }

    static func deviceID(forUID uid: String) -> AudioDeviceID? {
        var address = Self.address(kAudioHardwarePropertyTranslateUIDToDevice)
        var cfUID = uid as CFString
        var deviceID: AudioDeviceID = kAudioObjectUnknown
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = withUnsafeMutablePointer(to: &cfUID) { uidPointer in
            AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address,
                                       UInt32(MemoryLayout<CFString>.size), uidPointer, &size, &deviceID)
        }
        guard status == noErr, deviceID != kAudioObjectUnknown else { return nil }
        return deviceID
    }

    static func setDefaultDevice(uid: String, input: Bool) -> Bool {
        guard let deviceID = deviceID(forUID: uid) else { return false }
        var address = Self.address(input ? kAudioHardwarePropertyDefaultInputDevice : kAudioHardwarePropertyDefaultOutputDevice)
        var value = deviceID
        let status = AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, UInt32(MemoryLayout<AudioDeviceID>.size), &value)
        if status == noErr, !input {
            var systemAddress = Self.address(kAudioHardwarePropertyDefaultSystemOutputDevice)
            AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &systemAddress, 0, nil, UInt32(MemoryLayout<AudioDeviceID>.size), &value)
        }
        return status == noErr
    }

    static func nominalSampleRate(_ deviceID: AudioDeviceID) -> Double {
        var address = Self.address(kAudioDevicePropertyNominalSampleRate)
        var rate: Double = 0
        var size = UInt32(MemoryLayout<Double>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &rate)
        return (status == noErr && rate > 8000) ? rate : 48000
    }

    private static func availableSampleRates(_ deviceID: AudioDeviceID) -> [Double] {
        var address = Self.address(kAudioDevicePropertyAvailableNominalSampleRates)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ranges = [AudioValueRange](repeating: AudioValueRange(), count: Int(size) / MemoryLayout<AudioValueRange>.size)
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &ranges) == noErr else { return [] }
        return Array(Set(ranges.map(\.mMinimum))).sorted()
    }

    private static func streamFormat(_ deviceID: AudioDeviceID) -> String {
        var address = Self.address(kAudioDevicePropertyStreamFormat, scope: kAudioObjectPropertyScopeInput)
        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &format) == noErr else { return String(localized: "Unknown") }
        return String(localized: "\(format.mChannelsPerFrame) Ch / \(format.mBitsPerChannel)-bit")
    }

    private static func inputAddress(_ selector: AudioObjectPropertySelector, deviceID: AudioDeviceID) -> AudioObjectPropertyAddress? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeInput, mElement: kAudioObjectPropertyElementMain)
        if AudioObjectHasProperty(deviceID, &address) { return address }
        address.mElement = 1
        return AudioObjectHasProperty(deviceID, &address) ? address : nil
    }

    private static func readInputVolume(_ deviceID: AudioDeviceID) -> Float {
        guard var address = inputAddress(kAudioDevicePropertyVolumeScalar, deviceID: deviceID) else { return 1 }
        var volume: Float = 1
        var size = UInt32(MemoryLayout<Float>.size)
        return AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &volume) == noErr ? volume : 1
    }

    private static func readInputMute(_ deviceID: AudioDeviceID) -> Bool? {
        guard var address = inputAddress(kAudioDevicePropertyMute, deviceID: deviceID) else { return nil }
        var muted: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &muted) == noErr else { return nil }
        return muted != 0
    }

    private static func writeInputMute(_ muted: Bool, to deviceID: AudioDeviceID) {
        guard var address = inputAddress(kAudioDevicePropertyMute, deviceID: deviceID) else { return }
        var settable: DarwinBoolean = false
        if AudioObjectIsPropertySettable(deviceID, &address, &settable) == noErr, !settable.boolValue { return }
        var value: UInt32 = muted ? 1 : 0
        AudioObjectSetPropertyData(deviceID, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
    }

    static func isHiddenVirtualDevice(name: String, uid: String) -> Bool {
        let loweredName = name.lowercased()
        let loweredUID = uid.lowercased()
        let markers = ["blackhole", "loopback", "aggregate", "multi-output", "soundflower", "background music", "airfoil", "vb-cable", "virtual"]
        return markers.contains { loweredName.contains($0) || loweredUID.contains($0) }
    }
}