//
//  BatteryStatus.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-10-23
//

import Foundation

struct BatterySystemState {
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
        if let managementState { self.currentState.managementState = managementState }
        if let ledColor { self.currentState.ledColor = ledColor }
        if let isSleeping { self.currentState.isSleeping = isSleeping }
    }
}