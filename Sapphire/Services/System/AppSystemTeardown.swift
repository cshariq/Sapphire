//
//  AppSystemTeardown.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-10

import Foundation

@MainActor
enum AppSystemTeardown {
    static func restoreManagedSystemState(reason: String) {
        print("[AppSystemTeardown] Restoring session-scoped system state (\(reason))")

        if CalibrationManager.shared.isActive {
            CalibrationManager.shared.cancel()
        }

        LockScreenWallpaperManager.shared.restore()

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