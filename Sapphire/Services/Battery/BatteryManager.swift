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
    private let settings = SettingsModel.shared
    private let batteryMonitor = BatteryMonitor.shared
    private let batteryManager = BatteryManager.shared
    private let caffeineManager = CaffeineManager.shared
    private let statusManager = BatteryStatusManager.shared
    private let calibrationManager = CalibrationManager.shared
    private var cancellables = Set<AnyCancellable>()
    private var heatProtectionHysteresisTimer: Timer?

    private var isAppleSilicon: Bool {
        var sysinfo = utsname()
        uname(&sysinfo)
        let machine = withUnsafePointer(to: &sysinfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) { ptr in String(cString: ptr) }
        }
        return machine.starts(with: "arm64")
    }

    init() {
        Publishers.Merge3(
            settings.objectWillChange.map { _ in "Settings Change" },
            batteryMonitor.$currentState.map { _ in "Battery State Change" },
            calibrationManager.$state.map { _ in "Calibration State Change" }
        )
        .debounce(for: .seconds(1), scheduler: DispatchQueue.main)
        .sink { [weak self] _ in self?.evaluateState() }
        .store(in: &cancellables)

        Timer.publish(every: 15.0, on: .main, in: .common).autoconnect()
            .sink { [weak self] _ in self?.evaluateState() }
            .store(in: &cancellables)

        let workspaceNC = NSWorkspace.shared.notificationCenter
        workspaceNC.addObserver(self, selector: #selector(systemWillSleep), name: NSWorkspace.willSleepNotification, object: nil)
        workspaceNC.addObserver(self, selector: #selector(systemDidWake), name: NSWorkspace.didWakeNotification, object: nil)
    }

    @objc private func systemWillSleep() {
        statusManager.updateState(isSleeping: true)
        if settings.settings.stopChargingWhenSleeping {
            batteryManager.enableCharging(false)
        }
    }

    @objc private func systemDidWake() {
        statusManager.updateState(isSleeping: false)
        evaluateState()
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
                if temp >= currentSettings.heatProtectionThreshold {
                    shouldCharge = false
                    currentManagementState = .heatProtection
                    heatProtectionHysteresisTimer?.invalidate()
                    heatProtectionHysteresisTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: false) { [weak self] _ in self?.evaluateState() }
                }
            }

            if isAppleSilicon { batteryManager.enableCharging(shouldCharge) }
            else { batteryManager.setChargeLimit(shouldCharge ? 100 : currentSettings.batteryChargeLimit) }

            if caffeineManager.isActive && currentSettings.preventSleepDuringDischarge { caffeineManager.stop() }
            let ledColor = calculateMagSafeLEDColor(chargeState: batteryState, inhibited: !shouldCharge)
            batteryManager.setMagSafeLED(color: ledColor)
            statusManager.updateState(managementState: currentManagementState, ledColor: ledColor)
        }
    }

    private func calculateMagSafeLEDColor(chargeState: BatteryState, inhibited: Bool) -> Int {
        let settings = self.settings.settings
        guard settings.controlMagSafeLEDEnabled else { return -1 }
        let ledOff = 0, ledGreen = 3, ledAmber = 4

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
    private var helperConnection: NSXPCConnection?
    private let connectionLock = NSLock()
    private var batteryService: io_connect_t = 0

    private var isARM: Bool {
        var sysinfo = utsname()
        uname(&sysinfo)
        let machine = withUnsafePointer(to: &sysinfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) { ptr in String(cString: ptr) }
        }
        return machine.starts(with: "arm64")
    }

    private init() {
        setupHelperConnection()
        self.batteryService = IOServiceGetMatchingService(kIOMasterPortDefault, IOServiceMatching("AppleSmartBattery"))
    }

    deinit {
        if self.batteryService != 0 {
            IOObjectRelease(self.batteryService)
        }
    }

    private func setupHelperConnection() {
        connectionLock.lock()
        defer { connectionLock.unlock() }

        guard self.helperConnection == nil else { return }

        let connection = NSXPCConnection(machServiceName: "com.shariq.sapphireHelper", options: .privileged)
        connection.remoteObjectInterface = NSXPCInterface(with: HelperProtocol.self)

        connection.invalidationHandler = { [weak self] in
            print("[BatteryManager] XPC connection invalidated.")
            self?.connectionLock.withLock { self?.helperConnection = nil }
        }

        connection.interruptionHandler = { [weak self] in
            print("[BatteryManager] XPC connection interrupted.")
            self?.connectionLock.withLock { self?.helperConnection = nil }
        }

        connection.resume()
        self.helperConnection = connection
    }

    func getHelper() -> HelperProtocol? {
        connectionLock.lock()
        defer { connectionLock.unlock() }

        if self.helperConnection == nil {
            setupHelperConnection()
        }

        let proxy = self.helperConnection?.remoteObjectProxyWithErrorHandler { [weak self] error in
            print("[BatteryManager] XPC remote object error: \(error.localizedDescription)")
            DispatchQueue.main.async {
                self?.connectionLock.withLock {
                    self?.helperConnection?.invalidate()
                    self?.helperConnection = nil
                }
            }
        } as? HelperProtocol

        return proxy
    }

    // MARK: - Public API to Helper

    func setChargeLimit(_ limit: Int) {
        getHelper()?.setChargeLimit(limit) { error in
            if let error = error { print("[BatteryManager] Error setting charge limit: \(error.localizedDescription)") }
        }
    }

    func enableCharging(_ enabled: Bool) {
        getHelper()?.enableCharging(enabled) { error in
            if let error = error { print("[BatteryManager] Error setting charging enabled (\(enabled)): \(error.localizedDescription)") }
        }
    }

    func setDischarge(discharging: Bool) {
        getHelper()?.setDischarge(discharging) { error in
            if let error = error { print("[BatteryManager] Error setting discharge (\(discharging)): \(error.localizedDescription)") }
        }
    }

    func setMagSafeLED(color: Int) {
        getHelper()?.setMagSafeLED(color: color) { error in
            if let error = error { print("[BatteryManager] Error setting MagSafe LED: \(error.localizedDescription)") }
        }
    }

    @MainActor
    func startCalibration() {
        CalibrationManager.shared.start()
    }

    func beginCalibrationCycle(reply: @escaping (Error?) -> Void) {
        print("[BatteryManager] Sending command to helper to begin calibration hardware setup.")
        getHelper()?.startCalibration(reply: reply)
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
        await withCheckedContinuation { continuation in
            getHelper()?.getBatteryTemperature { temperature in
                continuation.resume(returning: temperature)
            }
        }
    }
}