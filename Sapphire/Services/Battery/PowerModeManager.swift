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

    private var refreshTimer: Timer?

    private init() {
        Task {
            self.isLowPowerModeActive = self.isLowPowerModeEnabled()
        }

        refreshTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                self.isLowPowerModeActive = self.isLowPowerModeEnabled()
            }
        }
    }

    func isLowPowerModeEnabled() -> Bool {
        let output = runPMSetCommand(args: ["-g"])
        let enabled = output?.contains("lowpowermode         1") ?? false
        isLowPowerModeActive = enabled
        return enabled
    }

    func enableLowPowerMode() {
        print("[PowerModeManager] Attempting to enable Low Power Mode via helper...")

        guard let helper = BatteryManager.shared.getHelper() else {
            print("[PowerModeManager] ERROR: Could not get helper connection.")
            fallbackToAppleScript()
            return
        }

        helper.enableLowPowerMode { [weak self] error in
            if let error = error {
                print("[PowerModeManager] Helper failed to enable Low Power Mode: \(error.localizedDescription)")
                self?.fallbackToAppleScript()
            } else {
                print("[PowerModeManager] Successfully enabled Low Power Mode via helper.")
                Task { @MainActor in
                    self?.isLowPowerModeActive = true
                }
            }
        }
    }

    func disableLowPowerMode() {
        print("[PowerModeManager] Attempting to disable Low Power Mode via helper...")

        guard let helper = BatteryManager.shared.getHelper() else {
            print("[PowerModeManager] ERROR: Could not get helper connection.")
            return
        }

        helper.disableLowPowerMode { [weak self] error in
            if let error = error {
                print("[PowerModeManager] Helper failed to disable Low Power Mode: \(error.localizedDescription)")
            } else {
                print("[PowerModeManager] Successfully disabled Low Power Mode via helper.")
                Task { @MainActor in
                    self?.isLowPowerModeActive = false
                }
            }
        }
    }

    private func fallbackToAppleScript() {
        print("[PowerModeManager] Falling back to AppleScript authentication method.")
        let scriptSource = "do shell script \"pmset -a lowpowermode 1\" with administrator privileges"

        var error: NSDictionary?
        if let script = NSAppleScript(source: scriptSource) {
            if script.executeAndReturnError(&error) == nil {
                if let err = error {
                    if (err[NSAppleScript.errorNumber] as? Int) != -128 {
                        print("[PowerModeManager] AppleScript execution error: \(err)")
                    } else {
                        print("[PowerModeManager] User cancelled the administrator password prompt.")
                    }
                }
            } else {
                print("[PowerModeManager] Successfully enabled Low Power Mode via AppleScript.")
                isLowPowerModeActive = true
            }
        }
    }

    private func runPMSetCommand(args: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = args

        let pipe = Pipe()
        process.standardOutput = pipe

        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                return String(data: data, encoding: .utf8)
            } else {
                print("[PowerModeManager] pmset command failed with status: \(process.terminationStatus)")
                return nil
            }
        } catch {
            print("[PowerModeManager] Failed to run pmset process: \(error)")
            return nil
        }
    }
}