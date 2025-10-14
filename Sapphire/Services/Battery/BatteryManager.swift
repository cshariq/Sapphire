//
//  BatteryManager.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-07-19.
//

import Foundation
import IOKit
import IOKit.ps
import Combine

@MainActor
class PowerStateController: ObservableObject {
    private let settings = SettingsModel.shared
    private let batteryMonitor = BatteryMonitor.shared
    private let batteryManager = BatteryManager.shared

    private var cancellables = Set<AnyCancellable>()
    private var heatProtectionHysteresisTimer: Timer?

    init() {
        let settingsPublisher = settings.objectWillChange.map { _ in () }
        let batteryPublisher = batteryMonitor.$currentState.map { _ in () }

        Publishers.Merge(settingsPublisher, batteryPublisher)
            .debounce(for: .seconds(1), scheduler: DispatchQueue.main)
            .sink { [weak self] in self?.evaluateState() }
            .store(in: &cancellables)

        Timer.publish(every: 15.0, on: .main, in: .common).autoconnect()
            .sink { [weak self] _ in self?.evaluateState() }
            .store(in: &cancellables)
    }

    private func evaluateState() {
        guard let batteryState = batteryMonitor.currentState else { return }

        let settings = self.settings.settings
        let chargeLimit = settings.batteryChargeLimit
        let currentCharge = settings.useHardwareBatteryPercentage ?
            batteryManager.getHardwareBatteryPercentage() : batteryState.level

        var isChargingInhibited = false

        if settings.heatProtectionEnabled && batteryState.isCharging {
            Task {
                let temp = await batteryManager.getBatteryTemperature()
                if temp >= settings.heatProtectionThreshold {
                    isChargingInhibited = true

                    heatProtectionHysteresisTimer?.invalidate()
                    heatProtectionHysteresisTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: false) { [weak self] _ in
                        self?.evaluateState()
                    }
                }
            }
        }

        if settings.automaticDischargeEnabled && batteryState.isPluggedIn && currentCharge > chargeLimit {
            isChargingInhibited = true
        }

        else if settings.sailingModeEnabled && batteryState.isPluggedIn {
             let sailingLowerBound = chargeLimit - settings.sailingModeLowerLimit
             if currentCharge >= chargeLimit {
                 isChargingInhibited = true
             } else if currentCharge < sailingLowerBound {
                 isChargingInhibited = false
             }
        }

        batteryManager.setDischarge(isChargingInhibited)
        batteryManager.setChargeLimit(chargeLimit)
        updateMagSafeLED(chargeState: batteryState, inhibited: isChargingInhibited)
    }

    private func updateMagSafeLED(chargeState: BatteryState, inhibited: Bool) {
        guard settings.settings.controlMagSafeLEDEnabled else { return }

        if settings.settings.magSafeLEDSetting == .off && !settings.settings.magSafeGreenAtLimit {
            batteryManager.setMagSafeLED(color: 0)
            return
        }

        let limitReached = chargeState.level >= settings.settings.batteryChargeLimit

        if limitReached && settings.settings.magSafeGreenAtLimit {
            batteryManager.setMagSafeLED(color: 1)
            return
        }

        if chargeState.isCharging && !inhibited {
            batteryManager.setMagSafeLED(color: 2)
        } else if inhibited {
            batteryManager.setMagSafeLED(color: settings.settings.magSafeLEDBlinkOnDischarge ? 2 : 0)
        } else {
            batteryManager.setMagSafeLED(color: 0)
        }
    }
}

class BatteryManager {
    static let shared = BatteryManager()

    private lazy var isAppleSilicon: Bool = {
        var sysinfo = utsname()
        uname(&sysinfo)
        let machine = withUnsafePointer(to: &sysinfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(cString: $0)
            }
        }
        return machine.starts(with: "arm64")
    }()

    private func executeSMC(args: [String]) -> String? {
        print("[BatteryManager] STUB: executeSMC called with args \(args). Returning nil.")
        return nil
    }

    func setChargeLimit(_ limit: Int) {
        let hexLimit = String(max(20, min(100, limit)), radix: 16)
        print("[BatteryManager] STUB: Setting charge limit to \(limit)% (Hex: \(hexLimit))")
    }

    func setDischarge(_ discharging: Bool) {
        print("[BatteryManager] STUB: Setting discharge mode to: \(discharging)")
    }

    @MainActor
    func getBatteryTemperature() async -> Double {
        let temperatureFromSMC = getSMCBatteryTemperature()
        if temperatureFromSMC > 0 {
            return temperatureFromSMC
        }
        return getSimulatedTemperature()
    }

    private func getSMCBatteryTemperature() -> Double {
        let temperatureKey = "TB0T"

        let conn = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard conn != IO_OBJECT_NULL else {
            print("[BatteryManager] Failed to connect to SMC. This is expected on some systems.")
            return -1
        }
        defer { IOServiceClose(conn) }

        var input = SMCKeyData_t()
        var output = SMCKeyData_t()

        let key = stringToKey(temperatureKey)
        input.key = key
        input.data8 = UInt8(kSMCGetKeyInfo)

        var inputSize = MemoryLayout<SMCKeyData_t>.size
        var outputSize = MemoryLayout<SMCKeyData_t>.size
        guard IOConnectCallStructMethod(conn, UInt32(kSMCHandleYPCEvent), &input, inputSize, &output, &outputSize) == kIOReturnSuccess else {
            print("[BatteryManager] Error getting SMC key info")
            return -1
        }

        input.key = key
        input.data8 = UInt8(kSMCReadKey)
        input.keyInfo.dataSize = output.keyInfo.dataSize

        guard IOConnectCallStructMethod(conn, UInt32(kSMCHandleYPCEvent), &input, inputSize, &output, &outputSize) == kIOReturnSuccess else {
            print("[BatteryManager] Error reading SMC key")
            return -1
        }

        let integerPart = Double(output.bytes[0])
        let fractionalPart = Double(output.bytes[1]) / 256.0
        let temperatureC = integerPart + fractionalPart

        print("[BatteryManager] Battery temperature: \(temperatureC)°C")
        return temperatureC
    }

    @MainActor
    private func getSimulatedTemperature() -> Double {
        if let state = BatteryMonitor.shared.currentState {
            let baseTemp = 25.0
            let chargingFactor = state.isCharging ? 5.0 : 0.0
            let loadFactor = state.level < 20 ? 2.0 : 0.0

            return baseTemp + chargingFactor + loadFactor + Double.random(in: -1.0...1.0)
        }
        return 30.0
    }

    private func stringToKey(_ key: String) -> UInt32 {
        var ans: UInt32 = 0
        for (i, byte) in key.utf8.enumerated() where i < 4 {
            ans += UInt32(byte) << (8 * (3 - i))
        }
        return ans
    }

    private struct SMCKeyData_t {
        var key: UInt32 = 0
        var versCode: UInt8 = 0
        var reserved1: UInt8 = 0
        var dataSize: UInt16 = 0
        var dataType: UInt32 = 0
        var bytes: [UInt8] = Array(repeating: 0, count: 32)

        var data8: UInt8 {
            get { bytes[0] }
            set { bytes[0] = newValue }
        }

        var keyInfo: KeyInfo {
            get { KeyInfo(dataSize: dataSize, dataType: dataType) }
            set {
                dataSize = newValue.dataSize
                dataType = newValue.dataType
            }
        }

        struct KeyInfo {
            var dataSize: UInt16 = 0
            var dataType: UInt32 = 0
        }
    }

    private let kSMCGetKeyInfo: UInt8 = 9
    private let kSMCReadKey: UInt8 = 5
    private let kIOReturnSuccess: kern_return_t = 0
    private let kSMCHandleYPCEvent: UInt32 = 2

    func setMagSafeLED(color: Int) {
        let hexColor = String(color, radix: 16, uppercase: true)
        print("[BatteryManager] STUB: Setting MagSafe LED color to \(hexColor)")
    }

    func startCalibration() {
        print("[BatteryManager] STUB: Starting calibration cycle.")
    }

    func getHardwareBatteryPercentage() -> Int {
        print("[BatteryManager] STUB: getHardwareBatteryPercentage called. Returning 80.")
        return 80
    }
}