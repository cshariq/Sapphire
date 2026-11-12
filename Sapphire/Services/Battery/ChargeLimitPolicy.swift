//
//  ChargeLimitPolicy.swift
//  Sapphire
//
//  Charge-limit decisions for the awake and sleep policies, kept pure so they can be tested.
//  A 100% limit means no limit: holding the battery for it would cut AC power in .adapter mode.
//

import Foundation

enum ChargeLimitPolicy {
    /// What the limit and Sailing Mode want while awake (manual pause and heat protection are applied separately).
    static func awakeDecision(charge: Int, limit: Int, sailingEnabled: Bool, sailingLowerLimit: Int, isCharging: Bool) -> (shouldCharge: Bool, state: ManagementState) {
        guard limit < 100 else { return (true, .charging) }
        if charge >= limit { return (false, .inhibited) }
        if sailingEnabled && charge >= limit - sailingLowerLimit && !isCharging { return (false, .sailing) }
        return (true, .charging)
    }

    /// Whether to stop charging as the Mac goes to sleep. Matches the helper's SleepBatteryMonitor.
    static func shouldInhibitForSleep(charge: Int, limit: Int, isCharging: Bool, stopChargingWhenSleeping: Bool) -> Bool {
        stopChargingWhenSleeping || (limit < 100 && (charge >= limit || isCharging))
    }

    /// At 100% there is nothing to enforce. Unless Sapphire must release a hold it sent itself, the firmware/legacy
    /// charge keys are left alone, because writing them can switch off macOS's own Charge Limit. Adapter mode
    /// always re-enables AC power.
    static func leavesChargingToMacOS(mode: ChargeControlMode, limit: Int, shouldCharge: Bool, holdApplied: Bool) -> Bool {
        mode != .adapter && limit >= 100 && shouldCharge && !holdApplied
    }
}
