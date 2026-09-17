//
//  CaffeinateManager.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-08-17.
//

import AppKit
import Combine
import Foundation
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

private struct CaffeinateTaskSettings: Equatable {
    let isEnabled: Bool
    let taskKinds: Set<String>
    let gracePeriod: Double

    init(_ settings: Settings) {
        isEnabled = settings.caffeinateAutoDuringTasks
        taskKinds = settings.caffeinateAutoTaskKinds
        gracePeriod = settings.caffeinateAutoTaskGrace
    }
}

@MainActor
class CaffeineManager: ObservableObject {
    static let shared = CaffeineManager()

    private let settings = SettingsModel.shared
    private let lidAngleSensor = LidAngleSensor.shared
    @Published private(set) var isActive = false

    private var caffeineTask: Process?
    private var rootDomainClamshellActive = false
    private var helperSleepDisabledActive = false
    private var forceClamshellGuard = false
    private var cancellables = Set<AnyCancellable>()
    private var dimmedScreenForLidAngle = false
    private var savedBrightnessBeforeScreenOff: Float?
    private var shouldRemainActive = false
    private var autoStartedByBatteryDischarge = false
    private var autoStartedByDevTask = false
    private var devTaskAutoSuppressed = false
    private var devTaskReleaseTask: Task<Void, Never>?
    private var lastKnownClamshellClosed = false
    private var clamshellReleaseDebounceTask: Task<Void, Never>?
    private var powerGuardRefreshDebounceTask: Task<Void, Never>?
    private var screenParameterDebounceTask: Task<Void, Never>?
    private var pendingClamshellOpen = false

    private var usingPolledClamshellFallback = false
    private var timeoutTask: Task<Void, Never>?
    @Published private(set) var timeoutEndsAt: Date?

    private init() {
        lidAngleSensor.$angle
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, self.shouldRemainActive else { return }
                self.evaluateLidAngleScreenOff()
                guard self.usingPolledClamshellFallback else { return }
                self.handleClamshellStateChanged(ClamshellDetector.isClosed)
            }
            .store(in: &cancellables)

        lidAngleSensor.$isAvailable
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, self.shouldRemainActive else { return }
                self.evaluateLidAngleScreenOff()
            }
            .store(in: &cancellables)

        if !ClamshellDetector.startObservingNativeEvents({ [weak self] isClosed in
            self?.handleClamshellStateChanged(isClosed)
        }) {
            os_log("CaffeineManager: Native clamshell notifications unavailable, falling back to polling.")
            usingPolledClamshellFallback = true
        }

        settings.changes(of: CaffeinateBehaviorSettings.init)
            .prepend(CaffeinateBehaviorSettings(settings.settings))
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateLidAngleSensorRequirement()
                self?.evaluateLidAngleScreenOff()
                self?.schedulePowerGuardRefresh()
                self?.rescheduleTimeoutIfNeeded()
            }
            .store(in: &cancellables)

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        workspaceCenter.publisher(for: NSWorkspace.didWakeNotification)
            .merge(with: workspaceCenter.publisher(for: NSWorkspace.screensDidWakeNotification))
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.restoreCaffeinateIfNeeded()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.scheduleClamshellReevaluation()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .sapphireHelperConnectionRestored)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.schedulePowerGuardRefresh()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .sapphireHelperConnectionLost)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.helperSleepDisabledActive = false
                self.updateActiveState()
            }
            .store(in: &cancellables)

        settings.changes(of: CaffeinateTaskSettings.init)
            .prepend(CaffeinateTaskSettings(settings.settings))
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.evaluateDevTaskCaffeinate()
            }
            .store(in: &cancellables)

        DevActivityMonitor.shared.$tasks
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.evaluateDevTaskCaffeinate()
            }
            .store(in: &cancellables)

        updateLidAngleSensorRequirement()
    }

    func toggle() {
        if isActive {
            stop()
        } else {
            start()
        }
    }

    func start(forcePreventSleepInClamshell: Bool = false) {
        let wasActive = isActive
        shouldRemainActive = true
        if forcePreventSleepInClamshell {
            self.forceClamshellGuard = true
            if !wasActive {
                autoStartedByBatteryDischarge = true
            }
        }

        if isActive {
            refreshAllPowerGuards()
            evaluateLidAngleScreenOff()
            scheduleTimeout()
            return
        }

        refreshAllPowerGuards()
        evaluateLidAngleScreenOff()
        scheduleTimeout()
    }

    func stop() {
        if hasQualifyingDevTask() { devTaskAutoSuppressed = true }

        shouldRemainActive = false
        forceClamshellGuard = false
        autoStartedByBatteryDischarge = false
        autoStartedByDevTask = false
        devTaskReleaseTask?.cancel()
        devTaskReleaseTask = nil
        cancelTimeout()
        clamshellReleaseDebounceTask?.cancel()
        powerGuardRefreshDebounceTask?.cancel()
        screenParameterDebounceTask?.cancel()
        pendingClamshellOpen = false

        releaseIOPMAssertions()
        terminateCaffeinateProcess()
        releaseClamshellGuardIfNeeded()
        ClamshellDetector.resetStickyState()

        isActive = false
        updateLidAngleSensorRequirement()
        restoreBrightnessIfNeeded()
    }

    private func scheduleTimeout() {
        cancelTimeout()
        let minutes = settings.settings.caffeinateTimeoutMinutes
        guard shouldRemainActive, minutes > 0 else { return }
        guard !autoStartedByDevTask else { return }

        let endsAt = Date().addingTimeInterval(minutes * 60)
        timeoutEndsAt = endsAt
        timeoutTask = Task { @MainActor [weak self] in
            let nanos = UInt64(max(0, minutes) * 60 * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanos)
            guard !Task.isCancelled, let self, self.shouldRemainActive else { return }
            self.stop()
        }
    }

    private func rescheduleTimeoutIfNeeded() {
        guard shouldRemainActive else {
            cancelTimeout()
            return
        }
        scheduleTimeout()
    }

    private func cancelTimeout() {
        timeoutTask?.cancel()
        timeoutTask = nil
        timeoutEndsAt = nil
    }

    // MARK: - Task-driven caffeinate

    private func hasQualifyingDevTask() -> Bool {
        guard settings.settings.caffeinateAutoDuringTasks else { return false }
        let kinds = settings.settings.caffeinateAutoTaskKinds
        guard !kinds.isEmpty else { return false }
        return DevActivityMonitor.shared.tasks.contains { kinds.contains($0.kind.rawValue) }
    }

    private func evaluateDevTaskCaffeinate() {
        guard settings.settings.caffeinateAutoDuringTasks else {
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

        guard !devTaskAutoSuppressed else { return }
        guard !isActive else { return }

        autoStartedByDevTask = true
        start()
        os_log("CaffeineManager: Auto-started for a running task.")
    }

    private func scheduleDevTaskRelease() {
        guard autoStartedByDevTask else { return }
        guard devTaskReleaseTask == nil else { return }

        let grace = max(0, settings.settings.caffeinateAutoTaskGrace)
        devTaskReleaseTask = Task { @MainActor [weak self] in
            if grace > 0 {
                try? await Task.sleep(nanoseconds: UInt64(grace * 1_000_000_000))
            }
            guard !Task.isCancelled, let self else { return }
            guard !self.hasQualifyingDevTask() else {
                self.devTaskReleaseTask = nil
                return
            }
            self.releaseDevTaskCaffeinateNow()
        }
    }

    private func releaseDevTaskCaffeinateNow() {
        devTaskReleaseTask?.cancel()
        devTaskReleaseTask = nil
        guard autoStartedByDevTask else { return }
        autoStartedByDevTask = false
        stop()
        os_log("CaffeineManager: Auto-stopped - no tasks running.")
    }

    func stopIfAutoStartedByBatteryDischarge() {
        guard autoStartedByBatteryDischarge else { return }
        stop()
    }

    // MARK: - Layered Power Guards

    private func refreshAllPowerGuards() {
        os_log("CaffeineManager: refreshAllPowerGuards - shouldAcquireClamshellGuard: %{public}@",
               shouldAcquireClamshellGuard() ? "true" : "false")
        let assertionOK = acquireIOPMAssertions()
        let caffeinateOK = ensureCaffeinateProcessRunning()

        if shouldAcquireClamshellGuard() {
            pendingClamshellOpen = false
            clamshellReleaseDebounceTask?.cancel()
            acquireClamshellGuardIfNeeded()
        }

        updateActiveState(assertionOK: assertionOK, caffeinateOK: caffeinateOK)
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
        forceClamshellGuard
            || settings.settings.sleepInClamshell
            || settings.settings.persistentCaffeinateAfterClamshell
            || ClamshellDetector.isClosed
    }

    private func shouldKeepClamshellGuardForSession() -> Bool {
        forceClamshellGuard
            || settings.settings.sleepInClamshell
            || settings.settings.persistentCaffeinateAfterClamshell
    }

    private func scheduleClamshellReleaseIfNeeded() {
        guard shouldRemainActive else { return }
        guard !shouldKeepClamshellGuardForSession() else {
            os_log("CaffeineManager: Skipping clamshell release - session guard required.")
            return
        }
        guard rootDomainClamshellActive || helperSleepDisabledActive else {
            os_log("CaffeineManager: Skipping clamshell release - no active guard.")
            return
        }

        os_log("CaffeineManager: Scheduling clamshell release (guard active, session guard not required).")
        clamshellReleaseDebounceTask?.cancel()
        pendingClamshellOpen = true
        clamshellReleaseDebounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, let self, self.shouldRemainActive else { return }
            guard !self.shouldKeepClamshellGuardForSession() else {
                os_log("CaffeineManager: Cancelled clamshell release - session guard now required.")
                return
            }
            guard !ClamshellDetector.isClosed else {
                os_log("CaffeineManager: Cancelled clamshell release - clamshell closed.")
                self.pendingClamshellOpen = false
                return
            }
            os_log("CaffeineManager: Executing clamshell release.")
            self.releaseClamshellGuardIfNeeded()
            self.pendingClamshellOpen = false
            self.refreshAllPowerGuards()
        }
    }

    private func restoreCaffeinateIfNeeded() {
        guard shouldRemainActive else { return }

        let reassertClamshellGuard =
            shouldKeepClamshellGuardForSession()
            || ClamshellDetector.isClosed

        if !isActive {
            refreshAllPowerGuards()
            evaluateLidAngleScreenOff()
            return
        }

        if reassertClamshellGuard {
            acquireClamshellGuardIfNeeded()
        }

        refreshAllPowerGuards()
        evaluateLidAngleScreenOff()
    }

    private func handleClamshellStateChanged(_ isClosed: Bool) {
        guard shouldRemainActive else { return }
        guard isClosed != lastKnownClamshellClosed else { return }

        os_log("CaffeineManager: Clamshell state transition - lastKnown: %{public}@, current: %{public}@",
               lastKnownClamshellClosed ? "true" : "false", isClosed ? "true" : "false")
        lastKnownClamshellClosed = isClosed

        if isClosed {
            pendingClamshellOpen = false
            clamshellReleaseDebounceTask?.cancel()
            os_log("CaffeineManager: Clamshell closed - refreshing power guards.")
            refreshAllPowerGuards()
            return
        }

        scheduleClamshellReleaseIfNeeded()
    }

    private func shouldUseClamshellGuard() -> Bool {
        shouldAcquireClamshellGuard()
    }

    private func acquireClamshellGuardIfNeeded() {
        os_log("CaffeineManager: acquireClamshellGuardIfNeeded called - rootDomainClamshellActive: %{public}@, helperSleepDisabledActive: %{public}@, shouldKeepClamshellGuardForSession: %{public}@",
               rootDomainClamshellActive ? "true" : "false",
               helperSleepDisabledActive ? "true" : "false",
               shouldKeepClamshellGuardForSession() ? "true" : "false")

        if rootDomainClamshellActive {
            os_log("CaffeineManager: Clamshell guard already active, skipping re-acquire.")
            updateActiveState()
            return
        }

        if helperSleepDisabledActive {
            os_log("CaffeineManager: Helper sleep disabled already active.")
            updateActiveState()
            return
        }

        if setClamshellSleepDisabled(true) {
            rootDomainClamshellActive = true
            releaseHelperSleepDisabledIfNeeded()
            print("[CaffeineManager] Clamshell sleep disabled via IOPMrootDomain.")
            updateActiveState()
            return
        }

        os_log("CaffeineManager: IOPMrootDomain clamshell guard unavailable, falling back to helper.")
        requestHelperSleepDisabled(true)
    }

    private func releaseClamshellGuardIfNeeded() {
        os_log("CaffeineManager: releaseClamshellGuardIfNeeded called - rootDomainClamshellActive: %{public}@, helperSleepDisabledActive: %{public}@, shouldKeepClamshellGuardForSession: %{public}@",
               rootDomainClamshellActive ? "true" : "false",
               helperSleepDisabledActive ? "true" : "false",
               shouldKeepClamshellGuardForSession() ? "true" : "false")

        if rootDomainClamshellActive {
            os_log("CaffeineManager: Releasing clamshell guard (rootDomainClamshellActive=true).")
            if setClamshellSleepDisabled(false) {
                print("[CaffeineManager] Clamshell sleep restored via IOPMrootDomain.")
            } else {
                os_log("CaffeineManager: Failed to restore clamshell sleep via IOPMrootDomain.")
            }
            rootDomainClamshellActive = false
        } else {
            os_log("CaffeineManager: Releasing clamshell guard (rootDomainClamshellActive=false).")
        }

        releaseHelperSleepDisabledIfNeeded()
    }

    private func acquireIOPMAssertions() -> Bool {
        if autoStartedByBatteryDischarge {
            acquirePreventSystemSleepOnlyAssertion()
        } else {
            acquirePreventSleepAssertions()
        }
    }

    private func releaseIOPMAssertions() {
        releasePreventSleepAssertions()
    }

    @discardableResult
    private func ensureCaffeinateProcessRunning() -> Bool {
        if let task = caffeineTask, task.isRunning {
            return true
        }

        caffeineTask = nil
        return startCaffeinateProcess()
    }

    @discardableResult
    private func startCaffeinateProcess() -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
        if autoStartedByBatteryDischarge {
            task.arguments = ["-i", "-m", "-s"]
        } else {
            task.arguments = ["-d", "-i", "-m", "-s"]
        }
        task.terminationHandler = { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.shouldRemainActive else { return }
                self.caffeineTask = nil
                if self.ensureCaffeinateProcessRunning() {
                    self.updateActiveState()
                }
            }
        }

        do {
            try task.run()
            caffeineTask = task
            return true
        } catch {
            os_log("CaffeineManager: Failed to start caffeinate process: %{public}@", error.localizedDescription)
            caffeineTask = nil
            return false
        }
    }

    private func terminateCaffeinateProcess() {
        guard let task = caffeineTask else { return }
        task.terminationHandler = nil
        if task.isRunning {
            task.terminate()
        }
        caffeineTask = nil
    }

    private func requestHelperSleepDisabled(_ disabled: Bool) {
        guard disabled else {
            releaseHelperSleepDisabledIfNeeded()
            return
        }

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
                    os_log(
                        "CaffeineManager: Helper failed to prevent sleep: %{public}@",
                        error.localizedDescription
                    )
                    self.helperSleepDisabledActive = false
                } else {
                    self.helperSleepDisabledActive = true
                    print("[CaffeineManager] System sleep disabled via helper.")
                }

                self.updateActiveState()
            }
        }
    }

    private func releaseHelperSleepDisabledIfNeeded() {
        guard helperSleepDisabledActive else { return }

        guard let helper = BatteryManager.shared.getHelper() else {
            helperSleepDisabledActive = false
            os_log("CaffeineManager: Helper unavailable while restoring sleep settings.")
            return
        }

        helper.allowSystemSleep { [weak self] error in
            Task { @MainActor [weak self] in
                guard let self else { return }

                if let error {
                    os_log(
                        "CaffeineManager: Helper failed to restore sleep: %{public}@",
                        error.localizedDescription
                    )
                } else {
                    print("[CaffeineManager] System sleep restored via helper.")
                }

                self.helperSleepDisabledActive = false
            }
        }
    }

    private func updateActiveState(
        assertionOK: Bool? = nil,
        caffeinateOK: Bool? = nil
    ) {
        let assertionsActive = assertionOK ?? preventSleepAssertionsAreActive()
        let caffeinateRunning = caffeinateOK ?? (caffeineTask?.isRunning == true)
        let clamshellGuardActive = rootDomainClamshellActive || helperSleepDisabledActive
        let needsClamshellGuard = shouldUseClamshellGuard()

        if needsClamshellGuard {
            isActive = assertionsActive || caffeinateRunning || clamshellGuardActive
        } else {
            isActive = assertionsActive || caffeinateRunning
        }

        updateLidAngleSensorRequirement()
    }

    // MARK: - Lid Angle Screen Dimming

    private func evaluateLidAngleScreenOff() {
        let shouldTurnScreenOff =
            isActive &&
            settings.settings.caffeinateTurnOffScreenUsingLidAngle &&
            lidAngleSensor.isAvailable &&
            lidAngleSensor.angle <= settings.settings.caffeinateLidAngleTrigger

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
        let needsSensor =
            isActive &&
            settings.settings.caffeinateTurnOffScreenUsingLidAngle

        if needsSensor {
            lidAngleSensor.acquire(.caffeineManager)
        } else {
            lidAngleSensor.release(.caffeineManager)
        }
    }

    private func restoreBrightnessIfNeeded() {
        guard dimmedScreenForLidAngle else { return }

        let targetBrightness = savedBrightnessBeforeScreenOff ?? max(0.2, settings.brightness)
        savedBrightnessBeforeScreenOff = nil
        dimmedScreenForLidAngle = false
        SystemControl.setBrightnessSmoothly(to: targetBrightness, duration: 0.15)
    }
}