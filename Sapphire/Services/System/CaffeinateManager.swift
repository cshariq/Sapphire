//
//  CaffeinateManager.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-08-17.
//

import AppKit
import Combine
import Foundation
import IOKit.pwr_mgt
import os.log

private struct CaffeinateBehaviorSettings: Equatable {
    let sleepInClamshell: Bool
    let persistAfterClamshell: Bool
    let turnOffScreenUsingLidAngle: Bool
    let lidAngleTrigger: Double
    let timeoutMinutes: Double

    init(_ settings: Settings) {
        sleepInClamshell = settings.sleepInClamshell
        persistAfterClamshell = settings.persistentCaffeinateAfterClamshell
        turnOffScreenUsingLidAngle = settings.caffeinateTurnOffScreenUsingLidAngle
        lidAngleTrigger = settings.caffeinateLidAngleTrigger
        timeoutMinutes = settings.caffeinateTimeoutMinutes
    }
}

private struct KeepAwakeAutomationSettings: Equatable {
    let featureEnabled: Bool
    let autoDuringTasks: Bool
    let taskKinds: Set<String>
    let taskGrace: Double
    let triggers: KeepAwakeTriggerConfiguration

    init(_ settings: Settings) {
        featureEnabled = settings.caffeinateEnabled
        autoDuringTasks = settings.caffeinateAutoDuringTasks
        taskKinds = settings.caffeinateAutoTaskKinds
        taskGrace = settings.caffeinateAutoTaskGrace
        triggers = KeepAwakeTriggerConfiguration(settings)
    }

    var watchesTasks: Bool { featureEnabled && autoDuringTasks && !taskKinds.isEmpty }
    var watchesTriggers: Bool { featureEnabled && triggers.hasAnyTrigger }
}

private final class KeepAwakeAssertions {
    private enum Kind: String, CaseIterable {
        case idleSystemSleep = "PreventUserIdleSystemSleep"
        case idleDisplaySleep = "PreventUserIdleDisplaySleep"
        case systemSleep = "PreventSystemSleep"
        case diskIdle = "PreventDiskIdle"
    }

    private var held: [Kind: IOPMAssertionID] = [:]

    var isHoldingAny: Bool { !held.isEmpty }

    @discardableResult
    func update(preventDisplaySleep: Bool) -> Bool {
        for kind in Kind.allCases {
            let wanted = kind != .idleDisplaySleep || preventDisplaySleep
            if wanted {
                acquire(kind)
            } else {
                release(kind)
            }
        }
        return held[.idleSystemSleep] != nil
    }

    func releaseAll() {
        Kind.allCases.forEach(release)
    }

    private func acquire(_ kind: Kind) {
        guard held[kind] == nil else { return }
        var id = IOPMAssertionID(0)
        let result = IOPMAssertionCreateWithName(
            kind.rawValue as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "Sapphire Keep Awake" as CFString,
            &id
        )
        if result == kIOReturnSuccess {
            held[kind] = id
        } else {
            os_log("CaffeineManager: Couldn't create %{public}@ assertion (%d)", kind.rawValue, result)
        }
    }

    private func release(_ kind: Kind) {
        guard let id = held.removeValue(forKey: kind) else { return }
        IOPMAssertionRelease(id)
    }
}

@MainActor
class CaffeineManager: ObservableObject {
    static let shared = CaffeineManager()

    enum Reason: Hashable {
        case manual
        case battery
        case devTask
        case trigger
    }

    private static let sleepGuardMarkerKey = "keepAwake.sleepGuardEngaged"

    private let settings = SettingsModel.shared
    @Published private(set) var isActive = false
    @Published private(set) var timeoutEndsAt: Date?

    private var reasons: Set<Reason> = []
    private let assertions = KeepAwakeAssertions()

    private var rootDomainClamshellActive = false
    private var helperSleepDisabledActive = false {
        didSet { updateSleepGuardMarker() }
    }
    private var dimmedScreenForLidAngle = false
    private var savedBrightnessBeforeScreenOff: Float?
    private var lastKnownClamshellClosed = false
    private var clamshellReleaseDebounceTask: Task<Void, Never>?
    private var powerGuardRefreshDebounceTask: Task<Void, Never>?
    private var screenParameterDebounceTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var scheduledTimeoutMinutes: Double = 0
    private var oneShotTimeoutMinutes: Double?
    private var usingPolledClamshellFallback = false
    private var isObservingClamshell = false

    private var activeCancellables = Set<AnyCancellable>()
    private var automationCancellable: AnyCancellable?
    private var automation: KeepAwakeAutomationSettings

    private var devTaskCancellable: AnyCancellable?
    private var devTaskReleaseTask: Task<Void, Never>?
    private var devTaskAutoSuppressed = false

    private var triggerMonitor: KeepAwakeTriggerMonitor?
    private var triggerSuppressed = false

    private var forceClamshellGuard: Bool { reasons.contains(.battery) }
    private var shouldRemainActive: Bool { !reasons.isEmpty }

    private init() {
        automation = KeepAwakeAutomationSettings(settings.current)
        recoverStaleSleepGuardIfNeeded()
        automationCancellable = settings.changes(of: KeepAwakeAutomationSettings.init)
            .sink { [weak self] newValue in
                MainActor.assumeIsolated { self?.applyAutomation(newValue) }
            }
        applyAutomation(automation, isInitial: true)
    }

    func bootstrap() {}

    func toggle() {
        if isActive {
            stop()
        } else {
            start()
        }
    }

    func start(forcePreventSleepInClamshell: Bool = false) {
        if !forcePreventSleepInClamshell { oneShotTimeoutMinutes = nil }
        addReason(forcePreventSleepInClamshell ? .battery : .manual)
    }

    func start(forMinutes minutes: Double) {
        oneShotTimeoutMinutes = max(1, minutes)
        addReason(.manual)
    }

    func startIndefinitely() {
        oneShotTimeoutMinutes = 0
        addReason(.manual)
    }

    func stop() {
        if hasQualifyingDevTask() { devTaskAutoSuppressed = true }
        if triggerMonitor?.shouldKeepAwake == true { triggerSuppressed = true }
        devTaskReleaseTask?.cancel()
        devTaskReleaseTask = nil
        reasons.removeAll()
        deactivate()
    }

    func stopIfAutoStartedByBatteryDischarge() {
        removeReason(.battery)
    }

    private func addReason(_ reason: Reason) {
        let wasEmpty = reasons.isEmpty
        let inserted = reasons.insert(reason).inserted
        if wasEmpty { installActiveObservers() }
        if reason == .manual { scheduleTimeout() }
        guard inserted || wasEmpty || !isActive else { return }
        refreshAllPowerGuards()
        evaluateLidAngleScreenOff()
    }

    private func removeReason(_ reason: Reason) {
        guard reasons.remove(reason) != nil else { return }
        if reason == .manual {
            cancelTimeout()
            oneShotTimeoutMinutes = nil
        }
        if reasons.isEmpty {
            deactivate()
        } else {
            if !shouldKeepClamshellGuardForSession() && !ClamshellDetector.isClosed {
                releaseClamshellGuardIfNeeded()
            }
            refreshAllPowerGuards()
        }
    }

    private func deactivate() {
        cancelTimeout()
        oneShotTimeoutMinutes = nil
        clamshellReleaseDebounceTask?.cancel()
        powerGuardRefreshDebounceTask?.cancel()
        screenParameterDebounceTask?.cancel()

        assertions.releaseAll()
        releaseClamshellGuardIfNeeded()
        if isObservingClamshell { ClamshellDetector.resetStickyState() }

        isActive = false
        removeActiveObservers()
        updateLidAngleSensorRequirement()
        restoreBrightnessIfNeeded()
    }

    // MARK: - Observers while active

    private func installActiveObservers() {
        guard activeCancellables.isEmpty else { return }

        if !isObservingClamshell {
            isObservingClamshell = true
            if !ClamshellDetector.startObservingNativeEvents({ [weak self] isClosed in
                self?.handleClamshellStateChanged(isClosed)
            }) {
                os_log("CaffeineManager: Native clamshell notifications unavailable, falling back to polling.")
                usingPolledClamshellFallback = true
            }
        }

        let lidAngleSensor = LidAngleSensor.shared
        lidAngleSensor.$angle
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, self.shouldRemainActive else { return }
                self.evaluateLidAngleScreenOff()
                guard self.usingPolledClamshellFallback else { return }
                self.handleClamshellStateChanged(ClamshellDetector.isClosed)
            }
            .store(in: &activeCancellables)

        lidAngleSensor.$isAvailable
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, self.shouldRemainActive else { return }
                self.evaluateLidAngleScreenOff()
            }
            .store(in: &activeCancellables)

        settings.changes(of: CaffeinateBehaviorSettings.init)
            .sink { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.updateLidAngleSensorRequirement()
                    self.evaluateLidAngleScreenOff()
                    self.schedulePowerGuardRefresh()
                    self.rescheduleTimeoutIfNeeded()
                }
            }
            .store(in: &activeCancellables)

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        workspaceCenter.publisher(for: NSWorkspace.didWakeNotification)
            .merge(with: workspaceCenter.publisher(for: NSWorkspace.screensDidWakeNotification))
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.restoreCaffeinateIfNeeded()
            }
            .store(in: &activeCancellables)

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.scheduleClamshellReevaluation()
            }
            .store(in: &activeCancellables)

        NotificationCenter.default.publisher(for: .sapphireHelperConnectionRestored)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.schedulePowerGuardRefresh()
            }
            .store(in: &activeCancellables)

        NotificationCenter.default.publisher(for: .sapphireHelperConnectionLost)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.helperSleepDisabledActive = false
                self.updateActiveState()
            }
            .store(in: &activeCancellables)
    }

    private func removeActiveObservers() {
        activeCancellables.removeAll()
    }

    // MARK: - Timeout

    private func scheduleTimeout() {
        cancelTimeout()
        let minutes = oneShotTimeoutMinutes ?? settings.current.caffeinateTimeoutMinutes
        guard reasons.contains(.manual), minutes > 0 else { return }

        scheduledTimeoutMinutes = minutes
        timeoutEndsAt = Date().addingTimeInterval(minutes * 60)
        timeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(minutes * 60 * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            self.timeoutTask = nil
            self.removeReason(.manual)
        }
    }

    private func rescheduleTimeoutIfNeeded() {
        guard reasons.contains(.manual) else {
            cancelTimeout()
            return
        }
        guard oneShotTimeoutMinutes == nil,
              settings.current.caffeinateTimeoutMinutes != scheduledTimeoutMinutes else { return }
        scheduleTimeout()
    }

    private func cancelTimeout() {
        timeoutTask?.cancel()
        timeoutTask = nil
        timeoutEndsAt = nil
        scheduledTimeoutMinutes = 0
    }

    // MARK: - Automation (tasks and triggers)

    private func applyAutomation(_ newValue: KeepAwakeAutomationSettings, isInitial: Bool = false) {
        guard isInitial || newValue != automation else { return }
        automation = newValue

        if newValue.watchesTasks {
            if devTaskCancellable == nil {
                devTaskCancellable = DevActivityMonitor.shared.$tasks
                    .receive(on: RunLoop.main)
                    .sink { [weak self] _ in self?.evaluateDevTaskCaffeinate() }
            }
            evaluateDevTaskCaffeinate()
        } else {
            devTaskCancellable = nil
            devTaskAutoSuppressed = false
            releaseDevTaskCaffeinateNow()
        }

        if newValue.watchesTriggers {
            let monitor = triggerMonitor ?? KeepAwakeTriggerMonitor { [weak self] shouldKeepAwake in
                self?.handleTriggerDecision(shouldKeepAwake)
            }
            triggerMonitor = monitor
            monitor.update(newValue.triggers)
        } else if let monitor = triggerMonitor {
            monitor.stop()
            triggerMonitor = nil
            triggerSuppressed = false
            removeReason(.trigger)
        }
    }

    private func handleTriggerDecision(_ shouldKeepAwake: Bool) {
        guard shouldKeepAwake else {
            triggerSuppressed = false
            removeReason(.trigger)
            return
        }
        guard automation.watchesTriggers, !triggerSuppressed else { return }
        addReason(.trigger)
        os_log("CaffeineManager: Kept awake by a trigger.")
    }

    private func hasQualifyingDevTask() -> Bool {
        guard automation.watchesTasks else { return false }
        let kinds = automation.taskKinds
        return DevActivityMonitor.shared.tasks.contains { kinds.contains($0.kind.rawValue) }
    }

    private func evaluateDevTaskCaffeinate() {
        guard automation.watchesTasks else {
            devTaskAutoSuppressed = false
            releaseDevTaskCaffeinateNow()
            return
        }

        guard hasQualifyingDevTask() else {
            devTaskAutoSuppressed = false
            scheduleDevTaskRelease()
            return
        }

        devTaskReleaseTask?.cancel()
        devTaskReleaseTask = nil

        guard !devTaskAutoSuppressed, !reasons.contains(.devTask) else { return }
        addReason(.devTask)
        os_log("CaffeineManager: Auto-started for a running task.")
    }

    private func scheduleDevTaskRelease() {
        guard reasons.contains(.devTask), devTaskReleaseTask == nil else { return }

        let grace = max(0, automation.taskGrace)
        devTaskReleaseTask = Task { @MainActor [weak self] in
            if grace > 0 {
                try? await Task.sleep(nanoseconds: UInt64(grace * 1_000_000_000))
            }
            guard !Task.isCancelled, let self else { return }
            self.devTaskReleaseTask = nil
            guard !self.hasQualifyingDevTask() else { return }
            self.releaseDevTaskCaffeinateNow()
        }
    }

    private func releaseDevTaskCaffeinateNow() {
        devTaskReleaseTask?.cancel()
        devTaskReleaseTask = nil
        guard reasons.contains(.devTask) else { return }
        removeReason(.devTask)
        os_log("CaffeineManager: Auto-stopped - no tasks running.")
    }

    // MARK: - Layered Power Guards

    private func refreshAllPowerGuards() {
        guard shouldRemainActive else { return }
        let assertionOK = assertions.update(preventDisplaySleep: reasons != [.battery])

        if shouldAcquireClamshellGuard() {
            clamshellReleaseDebounceTask?.cancel()
            acquireClamshellGuardIfNeeded()
        }

        updateActiveState(assertionOK: assertionOK)
        lastKnownClamshellClosed = ClamshellDetector.isClosed
    }

    private func scheduleClamshellReevaluation() {
        guard shouldRemainActive else { return }
        screenParameterDebounceTask?.cancel()
        screenParameterDebounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled, let self, self.shouldRemainActive else { return }
            self.handleClamshellStateChanged(ClamshellDetector.isClosed)
        }
    }

    private func schedulePowerGuardRefresh() {
        guard shouldRemainActive else { return }
        powerGuardRefreshDebounceTask?.cancel()
        powerGuardRefreshDebounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled, let self, self.shouldRemainActive else { return }
            self.refreshAllPowerGuards()
        }
    }

    private func shouldAcquireClamshellGuard() -> Bool {
        shouldKeepClamshellGuardForSession() || ClamshellDetector.isClosed
    }

    private func shouldKeepClamshellGuardForSession() -> Bool {
        let current = settings.current
        return forceClamshellGuard
            || current.sleepInClamshell
            || current.persistentCaffeinateAfterClamshell
    }

    private func scheduleClamshellReleaseIfNeeded() {
        guard shouldRemainActive else { return }
        guard !shouldKeepClamshellGuardForSession() else { return }
        guard rootDomainClamshellActive || helperSleepDisabledActive else { return }

        clamshellReleaseDebounceTask?.cancel()
        clamshellReleaseDebounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, let self, self.shouldRemainActive else { return }
            guard !self.shouldKeepClamshellGuardForSession() else { return }
            guard !ClamshellDetector.isClosed else { return }
            os_log("CaffeineManager: Lid opened, releasing the clamshell guard.")
            self.releaseClamshellGuardIfNeeded()
            self.refreshAllPowerGuards()
        }
    }

    private func restoreCaffeinateIfNeeded() {
        guard shouldRemainActive else { return }
        if isActive, shouldKeepClamshellGuardForSession() || ClamshellDetector.isClosed {
            acquireClamshellGuardIfNeeded()
        }
        refreshAllPowerGuards()
        evaluateLidAngleScreenOff()
    }

    private func handleClamshellStateChanged(_ isClosed: Bool) {
        guard shouldRemainActive else { return }
        guard isClosed != lastKnownClamshellClosed else { return }
        lastKnownClamshellClosed = isClosed

        if isClosed {
            clamshellReleaseDebounceTask?.cancel()
            os_log("CaffeineManager: Clamshell closed - refreshing power guards.")
            refreshAllPowerGuards()
            return
        }

        scheduleClamshellReleaseIfNeeded()
    }

    private func acquireClamshellGuardIfNeeded() {
        if rootDomainClamshellActive || helperSleepDisabledActive {
            updateActiveState()
            return
        }

        if setClamshellSleepDisabled(true) {
            rootDomainClamshellActive = true
            updateSleepGuardMarker()
            os_log("CaffeineManager: Clamshell sleep disabled via IOPMrootDomain.")
            updateActiveState()
            return
        }

        os_log("CaffeineManager: IOPMrootDomain clamshell guard unavailable, falling back to helper.")
        requestHelperSleepDisabled()
    }

    private func releaseClamshellGuardIfNeeded() {
        if rootDomainClamshellActive {
            if !setClamshellSleepDisabled(false) {
                os_log("CaffeineManager: Failed to restore clamshell sleep via IOPMrootDomain.")
            }
            rootDomainClamshellActive = false
            updateSleepGuardMarker()
        }
        releaseHelperSleepDisabledIfNeeded()
    }

    private func requestHelperSleepDisabled() {
        guard !helperSleepDisabledActive else { return }

        guard let helper = BatteryManager.shared.getHelper() else {
            os_log("CaffeineManager: Helper unavailable for clamshell sleep prevention.")
            updateActiveState()
            return
        }

        helper.preventSystemSleep { [weak self] error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let error {
                    os_log("CaffeineManager: Helper failed to prevent sleep: %{public}@", error.localizedDescription)
                    self.helperSleepDisabledActive = false
                } else if self.shouldRemainActive {
                    self.helperSleepDisabledActive = true
                } else {
                    self.helperSleepDisabledActive = true
                    self.releaseHelperSleepDisabledIfNeeded()
                }
                self.updateActiveState()
            }
        }
    }

    private func releaseHelperSleepDisabledIfNeeded() {
        guard helperSleepDisabledActive else { return }

        guard let helper = BatteryManager.shared.getHelper() else {
            helperSleepDisabledActive = false
            UserDefaults.standard.set(true, forKey: Self.sleepGuardMarkerKey)
            os_log("CaffeineManager: Helper unavailable while restoring sleep settings.")
            return
        }

        helperSleepDisabledActive = false
        helper.allowSystemSleep { error in
            if let error {
                os_log("CaffeineManager: Helper failed to restore sleep: %{public}@", error.localizedDescription)
                Task { @MainActor in
                    UserDefaults.standard.set(true, forKey: CaffeineManager.sleepGuardMarkerKey)
                }
            }
        }
    }

    private func updateSleepGuardMarker() {
        let engaged = rootDomainClamshellActive || helperSleepDisabledActive
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: Self.sleepGuardMarkerKey) != engaged {
            defaults.set(engaged, forKey: Self.sleepGuardMarkerKey)
        }
    }

    private func recoverStaleSleepGuardIfNeeded() {
        guard UserDefaults.standard.bool(forKey: Self.sleepGuardMarkerKey) else { return }
        os_log("CaffeineManager: Restoring sleep left disabled by a previous session.")
        _ = setClamshellSleepDisabled(false)
        UserDefaults.standard.set(false, forKey: Self.sleepGuardMarkerKey)
        guard let helper = BatteryManager.shared.getHelper() else { return }
        helper.allowSystemSleep { error in
            guard error != nil else { return }
            Task { @MainActor in
                UserDefaults.standard.set(true, forKey: CaffeineManager.sleepGuardMarkerKey)
            }
        }
    }

    private func updateActiveState(assertionOK: Bool? = nil) {
        guard shouldRemainActive else {
            isActive = false
            updateLidAngleSensorRequirement()
            return
        }
        let assertionsActive = assertionOK ?? assertions.isHoldingAny
        let clamshellGuardActive = rootDomainClamshellActive || helperSleepDisabledActive
        let newValue = shouldAcquireClamshellGuard()
            ? assertionsActive || clamshellGuardActive
            : assertionsActive
        if isActive != newValue { isActive = newValue }
        updateLidAngleSensorRequirement()
    }

    // MARK: - Lid Angle Screen Dimming

    private func evaluateLidAngleScreenOff() {
        let current = settings.current
        guard isActive, current.caffeinateTurnOffScreenUsingLidAngle else {
            restoreBrightnessIfNeeded()
            return
        }
        let lidAngleSensor = LidAngleSensor.shared
        let shouldTurnScreenOff = lidAngleSensor.isAvailable && lidAngleSensor.angle <= current.caffeinateLidAngleTrigger

        if shouldTurnScreenOff {
            guard !dimmedScreenForLidAngle else { return }
            savedBrightnessBeforeScreenOff = SystemControl.getBrightness()
            SystemControl.setBrightnessSmoothly(to: 0, duration: 0.12)
            dimmedScreenForLidAngle = true
            return
        }

        restoreBrightnessIfNeeded()
    }

    private func updateLidAngleSensorRequirement() {
        let needsSensor = isActive && settings.current.caffeinateTurnOffScreenUsingLidAngle
        guard needsSensor || hasClaimedLidSensor else { return }
        hasClaimedLidSensor = needsSensor
        if needsSensor {
            LidAngleSensor.shared.acquire(.caffeineManager)
        } else {
            LidAngleSensor.shared.release(.caffeineManager)
        }
    }

    private var hasClaimedLidSensor = false

    private func restoreBrightnessIfNeeded() {
        guard dimmedScreenForLidAngle else { return }

        let targetBrightness = savedBrightnessBeforeScreenOff ?? max(0.2, settings.brightness)
        savedBrightnessBeforeScreenOff = nil
        dimmedScreenForLidAngle = false
        SystemControl.setBrightnessSmoothly(to: targetBrightness, duration: 0.15)
    }
}