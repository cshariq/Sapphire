//
//  BatteryStatus.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-10-23
//

import Foundation

struct BatterySystemState: Equatable {
    var managementState: ManagementState = .charging
    var ledColor: Int = 0
    var isSleeping: Bool = false
}

enum ManagementState: String, Codable {
    case charging = "Charging"
    case inhibited = "Charge Limit"
    case sailing = "Sailing"
    case heatProtection = "Heat Protection"
    case discharging = "Discharging"
    case calibrating = "Calibrating"
    case calibrationStarted = "Calibration Started"
    case calibrationDone = "Calibration Complete"
    case calibrationFailed = "Calibration Failed"
    case dischargeStarted = "Discharge Started"
    case dischargeStopped = "Discharge Stopped"
    case heatProtectionOn = "Heat Protection Enabled"
    case heatProtectionOff = "Heat Protection Disabled"

    var displayName: String {
        switch self {
        case .charging: return String(localized: "Charging")
        case .inhibited: return String(localized: "Charge Limit")
        case .sailing: return String(localized: "Sailing")
        case .heatProtection: return String(localized: "Heat Protection")
        case .discharging: return String(localized: "Discharging")
        case .calibrating: return String(localized: "Calibrating")
        case .calibrationStarted: return String(localized: "Calibration Started")
        case .calibrationDone: return String(localized: "Calibration Complete")
        case .calibrationFailed: return String(localized: "Calibration Failed")
        case .dischargeStarted: return String(localized: "Discharge Started")
        case .dischargeStopped: return String(localized: "Discharge Stopped")
        case .heatProtectionOn: return String(localized: "Heat Protection Enabled")
        case .heatProtectionOff: return String(localized: "Heat Protection Disabled")
        }
    }
}

@MainActor
class BatteryStatusManager: ObservableObject {
    static let shared = BatteryStatusManager()

    @Published private(set) var currentState = BatterySystemState()

    private init() {}

    func updateState(
        managementState: ManagementState? = nil,
        ledColor: Int? = nil,
        isSleeping: Bool? = nil
    ) {
        var state = currentState
        if let managementState { state.managementState = managementState }
        if let ledColor { state.ledColor = ledColor }
        if let isSleeping { state.isSleeping = isSleeping }
        if state != currentState { currentState = state }
    }
}