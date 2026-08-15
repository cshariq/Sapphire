//
//  PowerModeManager.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-08-17.
//

import Foundation
import AppKit

@MainActor
class PowerModeManager: ObservableObject {
    static let shared = PowerModeManager()

    @Published var isLowPowerModeActive: Bool = false

    private init() {
        self.isLowPowerModeActive = ProcessInfo.processInfo.isLowPowerModeEnabled

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(powerStateChanged),
            name: NSNotification.Name.NSProcessInfoPowerStateDidChange,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func powerStateChanged() {
        self.isLowPowerModeActive = ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    func isLowPowerModeEnabled() -> Bool {
        return ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    func enableLowPowerMode() {
        setPowerMode(enabled: true)
    }

    func disableLowPowerMode() {
        setPowerMode(enabled: false)
    }

    private func setPowerMode(enabled: Bool) {
        print("[PowerModeManager] Setting Low Power Mode: \(enabled)")

        guard let helper = BatteryManager.shared.getHelper() else {
            print("[PowerModeManager] ERROR: Could not get helper connection.")
            fallbackToAppleScript(enabled: enabled)
            return
        }

        let completion: (Error?) -> Void = { [weak self] error in
            if let error = error {
                print("[PowerModeManager] Helper failed: \(error.localizedDescription)")
                self?.fallbackToAppleScript(enabled: enabled)
            } else {
                Task { @MainActor in
                    self?.isLowPowerModeActive = enabled
                }
            }
        }

        if enabled {
            helper.enableLowPowerMode(reply: completion)
        } else {
            helper.disableLowPowerMode(reply: completion)
        }
    }

    private func fallbackToAppleScript(enabled: Bool) {
        print("[PowerModeManager] Falling back to AppleScript.")
        let value = enabled ? "1" : "0"
        let scriptSource = "do shell script \"pmset -a lowpowermode \(value)\" with administrator privileges"

        DispatchQueue.global(qos: .userInitiated).async {
            var error: NSDictionary?
            if let script = NSAppleScript(source: scriptSource) {
                if script.executeAndReturnError(&error) == nil {
                    if let err = error {
                        print("[PowerModeManager] AppleScript error: \(err)")
                    }
                } else {
                    Task { @MainActor in
                        self.isLowPowerModeActive = enabled
                    }
                }
            }
        }
    }
}