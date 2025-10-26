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

@MainActor
class PowerStateController: ObservableObject {
    private let settings = SettingsModel.shared
    private let batteryMonitor = BatteryMonitor.shared
    private let batteryManager = BatteryManager.shared
    private let caffeineManager = CaffeineManager.shared
    private let statusManager = BatteryStatusManager.shared
    private let fanManager = FanManager.shared

    private var cancellables = Set<AnyCancellable>()
    private var heatProtectionHysteresisTimer: Timer?

    @Published var isDischargingForAutomation = false

    private var isAppleSilicon: Bool {
        var sysinfo = utsname()
        uname(&sysinfo)
        return withUnsafePointer(to: &sysinfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) { ptr in
                String(cString: ptr).starts(with: "arm64")
            }
        }
    }

    init() {
        Publishers.Merge3(
            settings.objectWillChange.map { _ in "Settings Change" },
            batteryMonitor.$currentState.map { _ in "Battery State Change" },
            $isDischargingForAutomation.map { _ in "Discharge Toggle Change" }
        )
        .debounce(for: .seconds(1), scheduler: DispatchQueue.main)
        .sink { [weak self] source in
            self?.evaluateState()
        }
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

    public func setAutomatedDischarge(to limit: Int) {
        settings.settings.batteryChargeLimit = limit
        self.isDischargingForAutomation = true
    }

    private func evaluateState() {
        if CalibrationManager.shared.isActive {
            statusManager.updateState(managementState: .calibrating)
            return
        }

        guard let batteryState = batteryMonitor.currentState else { return }

        let settings = self.settings.settings
        let chargeLimit = settings.batteryChargeLimit
        let currentCharge = settings.useHardwareBatteryPercentage ? batteryManager.getHardwareBatteryPercentage() : batteryState.level

        var shouldCharge = true
        var shouldDischarge = self.isDischargingForAutomation
        var currentManagementState: ManagementState = .charging

        if shouldDischarge {
            currentManagementState = .discharging
            shouldCharge = false
            if settings.preventSleepDuringDischarge && !caffeineManager.isActive { caffeineManager.start() }
            if currentCharge <= chargeLimit {
                self.isDischargingForAutomation = false
                if settings.preventSleepDuringDischarge { caffeineManager.stop() }
            }
        } else {
            if caffeineManager.isActive && settings.preventSleepDuringDischarge { caffeineManager.stop() }
            if settings.sailingModeEnabled {
                let sailingLowerBound = chargeLimit - settings.sailingModeLowerLimit
                if currentCharge >= chargeLimit {
                    shouldCharge = false
                    currentManagementState = .inhibited
                } else if currentCharge < sailingLowerBound {
                    shouldCharge = true
                } else {
                    shouldCharge = batteryState.isCharging
                    if !shouldCharge { currentManagementState = .sailing }
                }
            } else {
                if currentCharge >= chargeLimit {
                    shouldCharge = false
                    currentManagementState = .inhibited
                }
            }
        }

        if settings.heatProtectionEnabled && batteryState.isCharging && shouldCharge {
            Task {
                let temp = await batteryManager.getBatteryTemperature()
                if temp >= settings.heatProtectionThreshold {
                    shouldCharge = false
                    currentManagementState = .heatProtection
                    heatProtectionHysteresisTimer?.invalidate()
                    heatProtectionHysteresisTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: false) { [weak self] _ in self?.evaluateState() }
                }
            }
        }

        if isAppleSilicon { batteryManager.enableCharging(shouldCharge) }
        else { batteryManager.setChargeLimit(shouldCharge ? 100 : chargeLimit) }

        batteryManager.setDischarge(shouldDischarge)

        let inhibited = !shouldCharge || shouldDischarge
        let ledColor = calculateMagSafeLEDColor(chargeState: batteryState, inhibited: inhibited)
        batteryManager.setMagSafeLED(color: ledColor)

        statusManager.updateState(managementState: currentManagementState, ledColor: ledColor)
    }

    private func calculateMagSafeLEDColor(chargeState: BatteryState, inhibited: Bool) -> Int {
        let settings = self.settings.settings
        guard settings.controlMagSafeLEDEnabled else { return -1 }

        let ledOff = 0, ledGreen = 3, ledAmber = 4

        switch settings.magSafeLEDSetting {
        case .off:
            if !settings.magSafeGreenAtLimit || (settings.magSafeGreenAtLimit && chargeState.level < settings.batteryChargeLimit) {
                return ledOff
            }
        case .alwaysOn:
            break
        }

        if chargeState.level >= settings.batteryChargeLimit && settings.magSafeGreenAtLimit {
            return ledGreen
        }
        if inhibited {
            return settings.magSafeLEDBlinkOnDischarge && self.isDischargingForAutomation ? ledAmber : ledGreen
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

    private init() {
        setupHelperConnection()
    }

    private func setupHelperConnection() {
        connectionLock.lock()
        defer { connectionLock.unlock() }

        guard self.helperConnection == nil else {
            return
        }

        let connection = NSXPCConnection(machServiceName: Constant.helperMachLabel, options: .privileged)
        connection.remoteObjectInterface = NSXPCInterface(with: HelperProtocol.self)

        connection.invalidationHandler = { [weak self] in
            print("[BatteryManager] Helper connection invalidated.")
            self?.connectionLock.withLock {
                self?.helperConnection = nil
            }
        }

        connection.interruptionHandler = { [weak self] in
            print("[BatteryManager] Helper connection interrupted.")
            self?.connectionLock.withLock {
                self?.helperConnection = nil
            }
        }

        connection.resume()
        self.helperConnection = connection
        print("[BatteryManager] New helper connection established.")
    }

    func getHelper() -> HelperProtocol? {
        connectionLock.lock()
        if self.helperConnection == nil {
            connectionLock.unlock()
            setupHelperConnection()
            connectionLock.lock()
        }

        let proxy = self.helperConnection?.remoteObjectProxyWithErrorHandler { [weak self] error in
            print("[BatteryManager] Helper connection proxy error: \(error.localizedDescription)")
            DispatchQueue.main.async {
                self?.connectionLock.withLock {
                    self?.helperConnection?.invalidate()
                    self?.helperConnection = nil
                }
            }
        } as? HelperProtocol

        connectionLock.unlock()
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
            if let error = error { print("[BatteryManager] Error setting charging state: \(error.localizedDescription)") }
        }
    }

    func setDischarge(_ discharging: Bool) {
        getHelper()?.setDischarge(discharging) { error in
            if let error = error { print("[BatteryManager] Error setting discharge mode: \(error.localizedDescription)") }
        }
    }

    func setMagSafeLED(color: Int) {
        getHelper()?.setMagSafeLED(color: color) { error in
            if let error = error { print("[BatteryManager] Error setting MagSafe LED: \(error.localizedDescription)") }
        }
    }

    @MainActor func startCalibration() {
        print("[BatteryManager] Starting calibration process via CalibrationManager.")
        CalibrationManager.shared.start()
    }

    // MARK: - Data Fetching

    func getHardwareBatteryPercentage() -> Int {
        let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue()
        let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef]

        guard let sources = sources, let powerSource = sources.first else {
            print("[BatteryManager] Failed to get power sources for hardware percentage.")
            return 80
        }

        let info = IOPSGetPowerSourceDescription(snapshot, powerSource)?.takeUnretainedValue() as? [String: AnyObject]

        guard let currentCapacity = info?[kIOPSCurrentCapacityKey] as? Int else {
            print("[BatteryManager] Could not read current capacity key.")
            return 80
        }

        let rawCurrentCapacity = info?["AppleRawCurrentCapacity"] as? Double ?? Double(currentCapacity)
        let rawMaxCapacity = info?["AppleRawMaxCapacity"] as? Double ?? 100.0

        if rawMaxCapacity == 0 {
            print("[BatteryManager] Raw max capacity is zero, cannot calculate percentage.")
            return currentCapacity
        }

        let percentage = (rawCurrentCapacity / rawMaxCapacity) * 100.0

        let finalPercentage = Int(round(max(0.0, min(100.0, percentage))))

        return finalPercentage
    }

    @MainActor
    func getBatteryTemperature() async -> Double {
        return await withCheckedContinuation { continuation in
            getHelper()?.getBatteryTemperature { temperature in
                continuation.resume(returning: temperature)
            }
        }
    }
}