//
//  PowerModeManager.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-08-17.
//
//

import Foundation
import AppKit

@MainActor
class PowerModeManager {
    static let shared = PowerModeManager()

    private init() {}

    func isLowPowerModeEnabled() -> Bool {
        let output = runPMSetCommand(args: ["-g"])
        return output?.contains("lowpowermode         1") ?? false
    }

    func enableLowPowerMode() {
        print("[PowerModeManager] Attempting to enable Low Power Mode via AppleScript.")
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
                print("[PowerModeManager] Successfully enabled Low Power Mode.")
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