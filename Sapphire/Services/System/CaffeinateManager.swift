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
    private var watchdogTimer: Timer?
    private var lastKnownClamshellClosed = false
    private var clamshellReleaseDebounceTask: Task<Void, Never>?
    private var powerGuardRefreshDebounceTask: Task<Void, Never>?
    private var screenParameterDebounceTask: Task<Void, Never>?
    private var pendingClamshellOpen = false

    /// Hysteresis: require consecutive "open" readings before releasing detector-only guards.
    private var consecutiveClamshellOpenReadings = 0
    private let clamshellOpenReadingsRequired = 10

    private init() {
        lidAngleSensor.$angle
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.handleClamshellOrLidChange()
            }
            .store(in: &cancellables)

        lidAngleSensor.$isAvailable
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.handleClamshellOrLidChange()
            }
            .store(in: &cancellables)

        settings.$settings
            .map {
                (
                    $0.sleepInClamshell,
                    $0.persistentCaffeinateAfterClamshell,
                    $0.caffeinateTurnOffScreenUsingLidAngle,
                    $0.caffeinateLidAngleTrigger
                )
            }
            .removeDuplicates { $0 == $1 }
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateLidAngleSensorRequirement()
                self?.evaluateLidAngleScreenOff()
                self?.schedulePowerGuardRefresh()
            }
            .store(in: &cancellables)

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        workspaceCenter.publisher(for: NSWorkspace.willSleepNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshPowerGuardsIfNeeded()
            }
            .store(in: &cancellables)

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
        shouldRemainActive = true
        if forcePreventSleepInClamshell {
            self.forceClamshellGuard = true
        }

        if isActive {
            refreshAllPowerGuards()
            evaluateLidAngleScreenOff()
            return
        }

        refreshAllPowerGuards()
        startWatchdogIfNeeded()
        evaluateLidAngleScreenOff()
    }

    func stop() {
        shouldRemainActive = false
        forceClamshellGuard = false
        stopWatchdog()
        clamshellReleaseDebounceTask?.cancel()
        powerGuardRefreshDebounceTask?.cancel()
        screenParameterDebounceTask?.cancel()
        pendingClamshellOpen = false
        consecutiveClamshellOpenReadings = 0

        releaseIOPMAssertions()
        terminateCaffeinateProcess()
        releaseClamshellGuardIfNeeded()
        ClamshellDetector.resetStickyState()

        isActive = false
        updateLidAngleSensorRequirement()
        restoreBrightnessIfNeeded()
    }

    // MARK: - Layered Power Guards

    private func refreshAllPowerGuards() {
        os_log("CaffeineManager: refreshAllPowerGuards - shouldAcquireClamshellGuard: %{public}@", 
               shouldAcquireClamshellGuard() ? "true" : "false")
        let assertionOK = acquireIOPMAssertions()
        let caffeinateOK = ensureCaffeinateProcessRunning()

        if shouldAcquireClamshellGuard() {
            pendingClamshellOpen = false
            consecutiveClamshellOpenReadings = 0
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
            self.handleClamshellOrLidChange()
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

    /// Keep clamshell sleep disabled for the whole caffeinate session when any sticky setting is on.
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

    private func refreshPowerGuardsIfNeeded() {
        guard shouldRemainActive else { return }
        refreshAllPowerGuards()
    }

    private func restoreCaffeinateIfNeeded() {
        guard shouldRemainActive else { return }

        let reassertClamshellGuard =
            shouldKeepClamshellGuardForSession()
            || ClamshellDetector.isClosed

        if !isActive {
            refreshAllPowerGuards()
            startWatchdogIfNeeded()
            evaluateLidAngleScreenOff()
            return
        }

        if reassertClamshellGuard {
            acquireClamshellGuardIfNeeded()
        }

        refreshAllPowerGuards()
        evaluateLidAngleScreenOff()
    }

    private func handleClamshellOrLidChange() {
        os_log("CaffeineManager: handleClamshellOrLidChange called - shouldRemainActive: %{public}@", 
               shouldRemainActive ? "true" : "false")
        evaluateLidAngleScreenOff()
        guard shouldRemainActive else { return }

        let clamshellClosed = ClamshellDetector.isClosed
        os_log("CaffeineManager: ClamshellDetector.isClosed = %{public}@, lastKnownClamshellClosed = %{public}@", 
               clamshellClosed ? "true" : "false", lastKnownClamshellClosed ? "true" : "false")
        os_log("CaffeineManager: Clamshell state changed - closed: %{public}@, consecutiveOpen: %{public}d", 
               clamshellClosed ? "true" : "false", consecutiveClamshellOpenReadings)

        if clamshellClosed {
            consecutiveClamshellOpenReadings = 0
            pendingClamshellOpen = false
            clamshellReleaseDebounceTask?.cancel()
        } else {
            consecutiveClamshellOpenReadings += 1
        }

        guard clamshellClosed != lastKnownClamshellClosed else { return }
        os_log("CaffeineManager: Clamshell state transition - lastKnown: %{public}@, current: %{public}@", 
               lastKnownClamshellClosed ? "true" : "false", clamshellClosed ? "true" : "false")
        lastKnownClamshellClosed = clamshellClosed

        if clamshellClosed {
            os_log("CaffeineManager: Clamshell closed - refreshing power guards.")
            refreshAllPowerGuards()
            return
        }

        guard consecutiveClamshellOpenReadings >= clamshellOpenReadingsRequired else { 
            os_log("CaffeineManager: Not enough consecutive open readings (%{public}d/%{public}d)", 
                   consecutiveClamshellOpenReadings, clamshellOpenReadingsRequired)
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
        acquirePreventSleepAssertions()
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
        task.arguments = ["-d", "-i", "-m", "-s"]
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

    // MARK: - Watchdog

    private func startWatchdogIfNeeded() {
        guard watchdogTimer == nil else { return }

        watchdogTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.runWatchdog()
            }
        }
    }

    private func stopWatchdog() {
        watchdogTimer?.invalidate()
        watchdogTimer = nil
    }

    private func runWatchdog() {
        guard shouldRemainActive else {
            stopWatchdog()
            return
        }

        refreshAllPowerGuards()
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

        let targetBrightness = savedBrightnessBeforeScreenOff ?? max(0.2, settings.settings.brightness)
        savedBrightnessBeforeScreenOff = nil
        dimmedScreenForLidAngle = false
        SystemControl.setBrightnessSmoothly(to: targetBrightness, duration: 0.15)
    }
}
