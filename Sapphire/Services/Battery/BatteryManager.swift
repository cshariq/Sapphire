//
//  BatteryManager.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-07-19.
//

import Foundation
import IOKit.ps
import Combine
import ServiceManagement
import AppKit
import OSLog

private let helperLogger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Sapphire", category: "BatteryManager")

public struct PowerAdapterInfo: Equatable {
    var name: String = "N/A"
    var manufacturer: String = "N/A"
    var serialNumber: String = "N/A"
    var current: Int = 0
    var maxCurrent: Int = 0
    var voltage: Int = 0
    var maxVoltage: Int = 0
    var power: Int = 0
    var maxPower: Int = 0
}

@MainActor
class PowerStateController: ObservableObject {
    static let shared = PowerStateController()

    private let settings = SettingsModel.shared
    private let batteryMonitor = BatteryMonitor.shared
    private let batteryManager = BatteryManager.shared
    private let caffeineManager = CaffeineManager.shared
    private let statusManager = BatteryStatusManager.shared
    private let calibrationManager = CalibrationManager.shared
    private let powerModeManager = PowerModeManager.shared
    private var cancellables = Set<AnyCancellable>()
    private var heatProtectionHysteresisTimer: Timer?
    private var isInHeatProtection = false

    private lazy var isAppleSilicon: Bool = {
        var sysinfo = utsname()
        uname(&sysinfo)
        let machine = withUnsafePointer(to: &sysinfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) { ptr in String(cString: ptr) }
        }
        return machine.starts(with: "arm64")
    }()

    private init() {
        Publishers.Merge3(
            settings.objectWillChange.map { _ in "Settings Change" },
            batteryMonitor.$currentState.map { _ in "Battery State Change" },
            calibrationManager.$state.map { _ in "Calibration State Change" }
        )
        .debounce(for: .milliseconds(350), scheduler: DispatchQueue.main)
        .sink { [weak self] _ in
            self?.evaluateState()
            self?.reconcileSleepMonitoring()
        }
        .store(in: &cancellables)

        let workspaceNC = NSWorkspace.shared.notificationCenter
        workspaceNC.addObserver(self, selector: #selector(systemWillSleep), name: NSWorkspace.willSleepNotification, object: nil)
        workspaceNC.addObserver(self, selector: #selector(systemDidWake), name: NSWorkspace.didWakeNotification, object: nil)

        reconcileSleepMonitoring()
        evaluateState()
    }

    @objc private func systemWillSleep() {
        statusManager.updateState(isSleeping: true)
        applyChargePolicyForSleep()
    }

    @objc private func systemDidWake() {
        statusManager.updateState(isSleeping: false)
        evaluateState()
        reconcileSleepMonitoring()
    }

    private func reconcileSleepMonitoring() {
        let current = settings.settings
        if current.logBatteryDuringSleep {
            batteryManager.startSleepBatteryLogging(
                intervalMinutes: max(15, current.sleepLoggingIntervalMinutes),
                chargeLimit: current.batteryChargeLimit,
                stopChargingWhileAsleep: current.stopChargingWhenSleeping
            )
        } else {
            batteryManager.stopSleepBatteryLogging()
        }
    }

    private func applyChargePolicyForSleep() {
        let currentSettings = settings.settings
        guard let batteryState = batteryMonitor.currentState else {
            if currentSettings.stopChargingWhenSleeping {
                batteryManager.enableCharging(false)
            }
            return
        }

        Task {
            let currentCharge = currentSettings.useHardwareBatteryPercentage
                ? await batteryManager.getHardwareBatteryPercentage()
                : batteryState.level
            let atOrAboveLimit = currentCharge >= currentSettings.batteryChargeLimit
            let shouldInhibit =
                currentSettings.stopChargingWhenSleeping
                || atOrAboveLimit
                || (currentSettings.batteryChargeLimit < 100 && batteryState.isCharging)

            if shouldInhibit {
                if isAppleSilicon {
                    let mode = await batteryManager.currentChargeControlMode()
                    if mode == .firmware {
                        if currentSettings.batteryChargeLimit < 100 {
                            batteryManager.setChargeLimit(currentSettings.batteryChargeLimit)
                        }
                    } else {
                        batteryManager.enableCharging(false)
                    }
                } else {
                    batteryManager.setChargeLimit(currentSettings.batteryChargeLimit)
                }
            }
        }
    }

    private func evaluateState() {
        Task {
            if calibrationManager.isActive {
                switch calibrationManager.state {
                case .chargingToFull, .holdingAtFull, .dischargingToLow, .finalChargeToLimit:
                    statusManager.updateState(managementState: .calibrating)
                case .done:
                    statusManager.updateState(managementState: .calibrationDone)
                case .error:
                    statusManager.updateState(managementState: .calibrationFailed)
                default:
                    break
                }
                return
            }

            guard let batteryState = batteryMonitor.currentState else { return }
            let currentSettings = self.settings.settings
            let currentCharge = currentSettings.useHardwareBatteryPercentage ? await batteryManager.getHardwareBatteryPercentage() : batteryState.level

            if currentSettings.oneTimeDischargeEnabled {
                if currentCharge <= currentSettings.oneTimeDischargeTarget {
                    self.settings.settings.oneTimeDischargeEnabled = false
                } else {
                    statusManager.updateState(managementState: .discharging)
                    batteryManager.setDischarge(discharging: true)
                    let ledColor = calculateMagSafeLEDColor(chargeState: batteryState, inhibited: true)
                    batteryManager.setMagSafeLED(color: ledColor)
                    return
                }
            }

            if currentSettings.dischargeToLimitEnabled && currentCharge <= currentSettings.batteryChargeLimit {
                self.settings.settings.dischargeToLimitEnabled = false
                batteryManager.setDischarge(discharging: false)
                caffeineManager.stopIfAutoStartedByBatteryDischarge()
            }

            if currentSettings.dischargeToLimitEnabled && currentCharge > currentSettings.batteryChargeLimit {
                statusManager.updateState(managementState: .discharging)
                batteryManager.setDischarge(discharging: true)
                if currentSettings.preventSleepDuringDischarge && !caffeineManager.isActive { caffeineManager.start(forcePreventSleepInClamshell: true) }
                let ledColor = calculateMagSafeLEDColor(chargeState: batteryState, inhibited: true)
                batteryManager.setMagSafeLED(color: ledColor)
                return
            }

            batteryManager.setDischarge(discharging: false)

            var shouldCharge = true
            var currentManagementState: ManagementState = .charging

            if currentSettings.sailingModeEnabled {
                let sailingLowerBound = currentSettings.batteryChargeLimit - currentSettings.sailingModeLowerLimit
                if currentCharge >= currentSettings.batteryChargeLimit { shouldCharge = false; currentManagementState = .inhibited }
                else if currentCharge < sailingLowerBound { shouldCharge = true }
                else { shouldCharge = batteryState.isCharging; if !shouldCharge { currentManagementState = .sailing } }
            } else {
                if currentCharge >= currentSettings.batteryChargeLimit { shouldCharge = false; currentManagementState = .inhibited }
            }

            if currentSettings.heatProtectionEnabled && shouldCharge && batteryState.isCharging {
                let temp = await batteryManager.getBatteryTemperature()
                let threshold = currentSettings.heatProtectionThreshold
                if temp >= threshold {
                    shouldCharge = false
                    currentManagementState = .heatProtection
                    isInHeatProtection = true
                    heatProtectionHysteresisTimer?.invalidate()
                    heatProtectionHysteresisTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: false) { [weak self] _ in
                        self?.evaluateState()
                    }
                } else if isInHeatProtection, temp <= threshold - 3 {
                    isInHeatProtection = false
                    heatProtectionHysteresisTimer?.invalidate()
                    heatProtectionHysteresisTimer = nil
                } else if isInHeatProtection {
                    shouldCharge = false
                    currentManagementState = .heatProtection
                }
            } else if !currentSettings.heatProtectionEnabled {
                isInHeatProtection = false
            }

            applyLowPowerModePolicy(batteryState: batteryState, settings: currentSettings)
            applySleepUntilChargeLimitPolicy(
                batteryState: batteryState,
                currentCharge: currentCharge,
                settings: currentSettings
            )

            if isAppleSilicon {
                let mode = await batteryManager.currentChargeControlMode()
                if mode == .firmware {
                    batteryManager.setChargeLimit(shouldCharge ? 100 : currentSettings.batteryChargeLimit)
                } else {
                    batteryManager.enableCharging(shouldCharge)
                }
            } else {
                batteryManager.setChargeLimit(shouldCharge ? 100 : currentSettings.batteryChargeLimit)
            }

            let ledColor = calculateMagSafeLEDColor(chargeState: batteryState, inhibited: !shouldCharge)
            batteryManager.setMagSafeLED(color: ledColor)
            statusManager.updateState(managementState: currentManagementState, ledColor: ledColor)
        }
    }

    private func applyLowPowerModePolicy(batteryState: BatteryState, settings: Settings) {
        switch settings.lowPowerMode {
        case .alwaysOn:
            if !powerModeManager.isLowPowerModeActive {
                powerModeManager.enableLowPowerMode()
            }
        case .onBattery:
            if !batteryState.isPluggedIn, batteryState.level <= 25, !powerModeManager.isLowPowerModeActive {
                powerModeManager.enableLowPowerMode()
            } else if batteryState.isPluggedIn, powerModeManager.isLowPowerModeActive {
                powerModeManager.disableLowPowerMode()
            }
        case .never:
            break
        }
    }

    private func applySleepUntilChargeLimitPolicy(
        batteryState: BatteryState,
        currentCharge: Int,
        settings: Settings
    ) {
        guard settings.disableSleepUntilChargeLimit else {
            if caffeineManager.isActive, !settings.dischargeToLimitEnabled, !settings.oneTimeDischargeEnabled {
                caffeineManager.stopIfAutoStartedByBatteryDischarge()
            }
            return
        }

        let needsStayAwake = batteryState.isPluggedIn
            && currentCharge < settings.batteryChargeLimit
            && !calibrationManager.isActive

        if needsStayAwake, !caffeineManager.isActive {
            caffeineManager.start(forcePreventSleepInClamshell: true)
        } else if !needsStayAwake {
            caffeineManager.stopIfAutoStartedByBatteryDischarge()
        }
    }

    private func calculateMagSafeLEDColor(chargeState: BatteryState, inhibited: Bool) -> Int {
        let settings = self.settings.settings
        guard settings.controlMagSafeLEDEnabled else { return -1 }
        let ledOff = 1, ledGreen = 3, ledAmber = 4

        if settings.magSafeLEDSetting == .off, (!settings.magSafeGreenAtLimit || (settings.magSafeGreenAtLimit && chargeState.level < settings.batteryChargeLimit)) {
            return ledOff
        }
        if chargeState.level >= settings.batteryChargeLimit && settings.magSafeGreenAtLimit {
            return ledGreen
        }
        if inhibited {
            let isDischarging = settings.dischargeToLimitEnabled || settings.oneTimeDischargeEnabled
            return settings.magSafeLEDBlinkOnDischarge && isDischarging ? ledAmber : ledGreen
        } else if chargeState.isCharging {
            return ledAmber
        } else {
            return ledGreen
        }
    }
}

class BatteryManager {
    static let shared = BatteryManager()
    private let connectionLock = NSLock()
    private var batteryService: io_connect_t = 0

    private var consecutiveFailures = 0
    private var lastFailureTime: Date?
    private let maxConsecutiveFailures = 3
    private let circuitBreakerCooldownInterval: TimeInterval = 60
    private var isCircuitOpen = false
    private var helperConnectionObserver: NSObjectProtocol?

    private lazy var isARM: Bool = {
        var sysinfo = utsname()
        uname(&sysinfo)
        let machine = withUnsafePointer(to: &sysinfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) { ptr in String(cString: ptr) }
        }
        return machine.starts(with: "arm64")
    }()

    var isAppleSilicon: Bool { isARM }

    private init() {
        self.batteryService = IOServiceGetMatchingService(kIOMasterPortDefault, IOServiceMatching("AppleSmartBattery"))
        helperConnectionObserver = NotificationCenter.default.addObserver(
            forName: .sapphireHelperConnectionLost,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.activeSleepMonitoringConfig = nil
            self?.resetCommandState()
        }
    }

    deinit {
        if let helperConnectionObserver {
            NotificationCenter.default.removeObserver(helperConnectionObserver)
        }
        if self.batteryService != 0 {
            IOObjectRelease(self.batteryService)
        }
    }

    private func recordFailure() {
        var opened = false

        connectionLock.lock()
        consecutiveFailures += 1
        if !isCircuitOpen {
            lastFailureTime = Date()
        }
        if consecutiveFailures >= maxConsecutiveFailures && !isCircuitOpen {
            isCircuitOpen = true
            opened = true
        }
        connectionLock.unlock()

        if opened {
            helperLogger.warning("[BatteryManager] Circuit breaker OPEN - helper unreachable, will retry in \(self.circuitBreakerCooldownInterval)s")
        }
    }

    private func recordSuccess() {
        var restored = false

        connectionLock.lock()
        if consecutiveFailures > 0 || isCircuitOpen {
            consecutiveFailures = 0
            isCircuitOpen = false
            lastFailureTime = nil
            restored = true
        }
        connectionLock.unlock()

        if restored {
            helperLogger.info("[BatteryManager] Circuit breaker CLOSED - helper connection restored")
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .sapphireHelperConnectionRestored, object: nil)
            }
        }
    }

    private func handleRemoteError(_ error: Error) {
        _ = error
        recordFailure()
    }

    func getHelper() -> HelperProtocol? {
        var shouldReconnect = false
        var circuitOpen = false
        connectionLock.lock()
        if isCircuitOpen,
           let lastFailure = lastFailureTime,
           Date().timeIntervalSince(lastFailure) >= circuitBreakerCooldownInterval {
            isCircuitOpen = false
            consecutiveFailures = 0
            lastFailureTime = nil
            shouldReconnect = true
        }
        circuitOpen = isCircuitOpen
        connectionLock.unlock()

        if shouldReconnect {
            XPCClient.shared.start(force: true)
            resetCommandState()
        }
        guard !circuitOpen else { return nil }

        guard let helper = XPCClient.shared.proxy(onError: { [weak self] error in
            self?.handleRemoteError(error)
        }) else {
            recordFailure()
            return nil
        }
        return helper
    }

    func helperDidBecomeReachable() {
        var restored = false
        connectionLock.lock()
        if consecutiveFailures > 0 || isCircuitOpen {
            restored = true
        }
        consecutiveFailures = 0
        isCircuitOpen = false
        lastFailureTime = nil
        connectionLock.unlock()
        activeSleepMonitoringConfig = nil
        resetCommandState()

        if restored {
            helperLogger.info("[BatteryManager] Helper connection restored")
        }
        NotificationCenter.default.post(name: .sapphireHelperConnectionRestored, object: nil)
    }

    func reconnectHelper() {
        XPCClient.shared.stop()

        connectionLock.lock()
        consecutiveFailures = 0
        isCircuitOpen = false
        lastFailureTime = nil
        connectionLock.unlock()
        resetCommandState()

        activeSleepMonitoringConfig = nil
        XPCClient.shared.start()
    }

    // MARK: - Sleep Battery Monitoring

    private var activeSleepMonitoringConfig: (intervalMinutes: Int, chargeLimit: Int, stopChargingWhileAsleep: Bool)?

    private let commandStateLock = NSLock()
    private var lastChargeLimitCommand: Int?
    private var lastChargingCommand: Bool?
    private var lastDischargeCommand: Bool?
    private var lastLEDCommand: Int?

    private func claimChargeLimit(_ value: Int) -> Bool {
        commandStateLock.lock(); defer { commandStateLock.unlock() }
        guard lastChargeLimitCommand != value else { return false }
        lastChargeLimitCommand = value
        return true
    }

    private func claimCharging(_ value: Bool) -> Bool {
        commandStateLock.lock(); defer { commandStateLock.unlock() }
        guard lastChargingCommand != value else { return false }
        lastChargingCommand = value
        return true
    }

    private func claimDischarge(_ value: Bool) -> Bool {
        commandStateLock.lock(); defer { commandStateLock.unlock() }
        guard lastDischargeCommand != value else { return false }
        lastDischargeCommand = value
        return true
    }

    private func claimLED(_ value: Int) -> Bool {
        commandStateLock.lock(); defer { commandStateLock.unlock() }
        guard lastLEDCommand != value else { return false }
        lastLEDCommand = value
        return true
    }

    private func clearChargeLimitCommand(if value: Int) {
        commandStateLock.lock(); if lastChargeLimitCommand == value { lastChargeLimitCommand = nil }; commandStateLock.unlock()
    }

    private func clearChargingCommand(if value: Bool) {
        commandStateLock.lock(); if lastChargingCommand == value { lastChargingCommand = nil }; commandStateLock.unlock()
    }

    private func clearDischargeCommand(if value: Bool) {
        commandStateLock.lock(); if lastDischargeCommand == value { lastDischargeCommand = nil }; commandStateLock.unlock()
    }

    private func clearLEDCommand(if value: Int) {
        commandStateLock.lock(); if lastLEDCommand == value { lastLEDCommand = nil }; commandStateLock.unlock()
    }

    private func resetCommandState() {
        commandStateLock.lock()
        lastChargeLimitCommand = nil
        lastChargingCommand = nil
        lastDischargeCommand = nil
        lastLEDCommand = nil
        commandStateLock.unlock()
    }

    func startSleepBatteryLogging(intervalMinutes: Int, chargeLimit: Int, stopChargingWhileAsleep: Bool) {
        let config = (intervalMinutes, chargeLimit, stopChargingWhileAsleep)
        if let active = activeSleepMonitoringConfig, active == config { return }

        guard let helper = getHelper() else {
            activeSleepMonitoringConfig = nil
            return
        }

        let logPath = sleepLogFileURL().path
        helper.startSleepBatteryMonitoring(
            intervalMinutes: intervalMinutes,
            chargeLimit: chargeLimit,
            stopChargingWhileAsleep: stopChargingWhileAsleep,
            logPath: logPath
        ) { error in
            if let error {
                helperLogger.error("[BatteryManager] startSleepBatteryMonitoring failed: \(error.localizedDescription)")
            }
        }
        activeSleepMonitoringConfig = config
    }

    func stopSleepBatteryLogging() {
        guard activeSleepMonitoringConfig != nil else { return }
        activeSleepMonitoringConfig = nil
        getHelper()?.stopSleepBatteryMonitoring { error in
            if let error {
                helperLogger.error("[BatteryManager] stopSleepBatteryMonitoring failed: \(error.localizedDescription)")
            }
        }
    }

    private func sleepLogFileURL() -> URL {
        let fileManager = FileManager.default
        let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return appSupportURL
            .appendingPathComponent("Sapphire/BatteryLogs")
            .appendingPathComponent("battery_sleep_log.jsonl")
    }

    private func withHelperCallback<T>(
        fallback: T,
        timeout: TimeInterval = 5,
        _ work: (HelperProtocol, @escaping (T) -> Void) -> Void
    ) async -> T {
        let recordFailure = self.recordFailure
        let recordSuccess = self.recordSuccess

        return await withCheckedContinuation { (continuation: CheckedContinuation<T, Never>) in
            let lock = NSLock()
            var resumed = false

            func finish(_ value: T, success: Bool) {
                lock.lock()
                guard !resumed else {
                    lock.unlock()
                    return
                }
                resumed = true
                lock.unlock()

                if success {
                    recordSuccess()
                } else {
                    recordFailure()
                }
                continuation.resume(returning: value)
            }

            guard let helper = getHelper() else {
                finish(fallback, success: false)
                return
            }

            work(helper) { value in
                finish(value, success: true)
            }

            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                finish(fallback, success: false)
            }
        }
    }

    // MARK: - Public API to Helper

    func setChargeLimit(_ limit: Int) {
        guard claimChargeLimit(limit) else { return }
        guard let helper = getHelper() else {
            clearChargeLimitCommand(if: limit)
            return
        }
        let recordFailure = self.recordFailure
        let recordSuccess = self.recordSuccess
        helper.setChargeLimit(limit) { [weak self] error in
            if let error = error {
                self?.clearChargeLimitCommand(if: limit)
                recordFailure()
                print("[BatteryManager] Error setting charge limit: \(error.localizedDescription)")
            } else {
                recordSuccess()
            }
        }
    }

    func enableCharging(_ enabled: Bool) {
        guard claimCharging(enabled) else { return }
        guard let helper = getHelper() else {
            clearChargingCommand(if: enabled)
            return
        }
        let recordFailure = self.recordFailure
        let recordSuccess = self.recordSuccess
        helper.enableCharging(enabled) { [weak self] error in
            if let error = error {
                self?.clearChargingCommand(if: enabled)
                recordFailure()
                print("[BatteryManager] Error setting charging enabled (\(enabled)): \(error.localizedDescription)")
            } else {
                recordSuccess()
            }
        }
    }

    func setDischarge(discharging: Bool) {
        guard claimDischarge(discharging) else { return }
        guard let helper = getHelper() else {
            clearDischargeCommand(if: discharging)
            return
        }
        let recordFailure = self.recordFailure
        let recordSuccess = self.recordSuccess
        helper.setDischarge(discharging) { [weak self] error in
            if let error = error {
                self?.clearDischargeCommand(if: discharging)
                recordFailure()
                print("[BatteryManager] Error setting discharge (\(discharging)): \(error.localizedDescription)")
            } else {
                recordSuccess()
            }
        }
    }

    func setMagSafeLED(color: Int) {
        guard claimLED(color) else { return }
        guard let helper = getHelper() else {
            clearLEDCommand(if: color)
            return
        }
        let recordFailure = self.recordFailure
        let recordSuccess = self.recordSuccess
        helper.setMagSafeLED(color: color) { [weak self] error in
            if let error = error {
                self?.clearLEDCommand(if: color)
                recordFailure()
                print("[BatteryManager] Error setting MagSafe LED: \(error.localizedDescription)")
            } else {
                recordSuccess()
            }
        }
    }

    @MainActor
    func startCalibration() {
        CalibrationManager.shared.start()
    }

    func beginCalibrationCycle(reply: @escaping (Error?) -> Void) {
        print("[BatteryManager] Sending command to helper to begin calibration hardware setup.")
        let recordFailure = self.recordFailure
        let recordSuccess = self.recordSuccess
        guard let helper = getHelper() else {
            let error = NSError(
                domain: "SapphireBattery",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "The privileged helper is not reachable. Install or reset it (Settings → Battery → Helper) before calibrating."]
            )
            print("[BatteryManager] beginCalibrationCycle failed: helper unreachable.")
            recordFailure()
            reply(error)
            return
        }
        helper.startCalibration { error in
            if error != nil {
                recordFailure()
            } else {
                recordSuccess()
            }
            reply(error)
        }
    }

    // MARK: - Data Fetching from IOKit

    private func getIntValue(for key: CFString) -> Int? {
        guard self.batteryService != 0 else { return nil }
        guard let value = IORegistryEntryCreateCFProperty(self.batteryService, key, kCFAllocatorDefault, 0) else { return nil }
        return value.takeRetainedValue() as? Int
    }

    private func getIOPSDictionary() async -> [String: AnyObject]? {
        await withCheckedContinuation { continuation in
            guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
                  let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef],
                  let powerSource = sources.first else {
                continuation.resume(returning: nil)
                return
            }
            let info = IOPSGetPowerSourceDescription(snapshot, powerSource)?.takeUnretainedValue() as? [String: AnyObject]
            continuation.resume(returning: info)
        }
    }

    func getPowerAdapterInfo() async -> PowerAdapterInfo? {
        await withCheckedContinuation { (continuation: CheckedContinuation<PowerAdapterInfo?, Never>) in
            guard let details = IOPSCopyExternalPowerAdapterDetails(),
                  let dict = details.takeRetainedValue() as? [String: Any] else {
                continuation.resume(returning: nil)
                return
            }

            let name = dict["Name"] as? String ?? "Power Adapter"
            let manufacturer = dict["Manufacturer"] as? String ?? "Apple Inc."
            let serialNumber = dict["SerialString"] as? String ?? "N/A"
            let current = dict["Current"] as? Int ?? 0
            let voltage = dict["AdapterVoltage"] as? Int ?? 0
            let maxCurrent = dict["PMUConfiguration"] as? Int ?? current
            let maxVoltage = dict["AdapterVoltage"] as? Int ?? 0
            let power = (voltage * current) / 1_000_000
            let maxPower = dict["Watts"] as? Int ?? 0

            let info = PowerAdapterInfo(
                name: name, manufacturer: manufacturer, serialNumber: serialNumber,
                current: current, maxCurrent: maxCurrent, voltage: voltage,
                maxVoltage: maxVoltage, power: power, maxPower: maxPower
            )
            continuation.resume(returning: info)
        }
    }

    func getBatteryHealth() async -> String {
        guard let info = await getIOPSDictionary() else { return "Unknown" }
        return info[kIOPSBatteryHealthKey] as? String ?? "Normal"
    }

    func getDesignCapacity() async -> Int {
        return getIntValue(for: "DesignCapacity" as CFString) ?? 0
    }

    func getMaxCapacity() async -> Int {
        let key = isARM ? "AppleRawMaxCapacity" : "MaxCapacity"
        return getIntValue(for: key as CFString) ?? 0
    }

    func getAppleMaxCapacity() async -> Int {
        guard let info = await getIOPSDictionary() else { return 0 }
        return info[kIOPSMaxCapacityKey] as? Int ?? 0
    }

    func getCycleCount() async -> Int {
        return getIntValue(for: "CycleCount" as CFString) ?? 0
    }

    func getHardwareBatteryPercentage() async -> Int {
        guard let info = await getIOPSDictionary() else { return 80 }
        guard let currentCapacity = info[kIOPSCurrentCapacityKey] as? Int else { return 80 }
        let rawCurrentCapacity = info["AppleRawCurrentCapacity"] as? Double ?? Double(currentCapacity)
        let rawMaxCapacity = info["AppleRawMaxCapacity"] as? Double ?? 100.0

        if rawMaxCapacity == 0 { return currentCapacity }

        let percentage = (rawCurrentCapacity / rawMaxCapacity) * 100.0
        return Int(round(max(0.0, min(100.0, percentage))))
    }

    @MainActor
    func getBatteryTemperature() async -> Double {
        await withHelperCallback(fallback: 0) { helper, reply in
            helper.getBatteryTemperature(reply: reply)
        }
    }

    private let helperPingTimeoutSentinel = "__sapphire_helper_timeout__"

    func verifyHelperResponds() async -> Bool {
        let version = await withHelperCallback(fallback: helperPingTimeoutSentinel) { helper, reply in
            helper.getVersion(reply: reply)
        }
        return version != helperPingTimeoutSentinel
    }

    private var cachedChargeControlMode: ChargeControlMode?

    func currentChargeControlMode() async -> ChargeControlMode {
        if let cached = cachedChargeControlMode { return cached }
        let raw = await withHelperCallback(fallback: -1) { helper, reply in
            helper.getChargeControlMode(reply: reply)
        }
        let mode = ChargeControlMode(rawValue: raw) ?? .legacy
        cachedChargeControlMode = mode
        return mode
    }
}