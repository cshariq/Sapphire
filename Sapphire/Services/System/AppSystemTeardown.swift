//
//  AppSystemTeardown.swift
//  Sapphire
//

import Foundation

/// Restores session-scoped system state when Sapphire stops managing the Mac.
///
/// Battery charge limits and fan curves are intentionally **not** reset here — the
/// privileged helper daemon keeps running after the app exits and continues to own
/// those SMC settings until Sapphire reconnects or the user changes them.
@MainActor
enum AppSystemTeardown {
    static func restoreManagedSystemState(reason: String) {
        print("[AppSystemTeardown] Restoring session-scoped system state (\(reason))")

        if CalibrationManager.shared.isActive {
            CalibrationManager.shared.cancel()
        }

        CaffeineManager.shared.stop()
        LidAngleAutomationManager.shared.releaseForcedSystemChanges()
        restoreHelperSleepIfNeeded()
    }

    private static func restoreHelperSleepIfNeeded() {
        guard let helper = BatteryManager.shared.getHelper() else { return }

        let group = DispatchGroup()
        group.enter()
        helper.allowSystemSleep { _ in group.leave() }
        _ = group.wait(timeout: .now() + 1.0)
    }
}
