//
//  BrowserAppleScriptManager.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-11-15
//

import Foundation
import AppKit

@MainActor
class BrowserAppleScriptManager {
    static let shared = BrowserAppleScriptManager()

    private init() {}

    private func escapeStringForAppleScript(_ input: String) -> String {
        return input.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    func focusTab(for bundleID: String, with trackTitle: String) {
        print("[BrowserAppleScriptManager] LOG: Received request to focus tab for bundleID: '\(bundleID)' with track title: '\(trackTitle)'")

        let appName: String
        let script: String
        let escapedTitle = escapeStringForAppleScript(trackTitle)

        switch bundleID {
        case "com.apple.Safari":
            appName = "Safari"
            script = """
            tell application "\(appName)"
                activate
                repeat with w in windows
                    repeat with t in tabs of w
                        if name of t contains "\(escapedTitle)" then
                            set current tab of w to t
                            set index of w to 1
                            return "FOUND"
                        end if
                    end repeat
                end repeat
                return "NOT_FOUND"
            end tell
            """

        case "com.google.Chrome", "com.microsoft.edgemac":
            appName = bundleID == "com.google.Chrome" ? "Google Chrome" : "Microsoft Edge"
            script = """
            tell application "\(appName)"
                activate
                repeat with w in windows
                    set i to 0
                    repeat with t in tabs of w
                        set i to i + 1
                        if title of t contains "\(escapedTitle)" then
                            set active tab index of w to i
                            set index of w to 1
                            return "FOUND"
                        end if
                    end repeat
                end repeat
                return "NOT_FOUND"
            end tell
            """

        case "company.thebrowser.Browser":
            appName = "Arc"
            script = """
            tell application "\(appName)"
                activate
                repeat with w in windows
                    repeat with t in tabs of w
                        if title of t contains "\(escapedTitle)" then
                            select t
                            set index of w to 1
                            return "FOUND"
                        end if
                    end repeat
                end repeat
                return "NOT_FOUND"
            end tell
            """

        default:
            print("[BrowserAppleScriptManager] LOG: BundleID '\(bundleID)' is not a supported browser. Aborting.")
            return
        }

        print("[BrowserAppleScriptManager] LOG: Determined app name: '\(appName)'.")
        print("[BrowserAppleScriptManager] LOG: Preparing to execute the following AppleScript:\n---\n\(script)\n---")

        Task {
            let result = await runAppleScriptInBackground(script)
            if result == "NOT_FOUND" {
                print("[BrowserAppleScriptManager] LOG: Tab not found. Activating app as a fallback.")
                if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                    NSWorkspace.shared.open(appURL)
                }
            }
        }
    }

    private func runAppleScriptInBackground(_ script: String) async -> String {
        print("[BrowserAppleScriptManager] LOG: Executing AppleScript on a background thread...")
        var error: NSDictionary?
        guard let scriptObject = NSAppleScript(source: script) else {
            print("[BrowserAppleScriptManager] ERROR: Failed to create NSAppleScript object.")
            return "ERROR"
        }

        let resultDescriptor = await Task.detached {
            return scriptObject.executeAndReturnError(&error)
        }.value

        if let error = error {
            print("[BrowserAppleScriptManager] ERROR: AppleScript execution failed.")
            print("--- ERROR DETAILS ---")
            for (key, value) in error {
                print("\(key): \(value)")
            }
            print("-----------------------")
            return "ERROR"
        } else {
            let resultString = resultDescriptor.stringValue ?? "No result string"
            print("[BrowserAppleScriptManager] LOG: AppleScript execution SUCCEEDED. Result: \(resultString)")
            return resultString
        }
    }
}