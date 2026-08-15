//
//  WindowArrangementManager.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-08-11.
//

import AppKit
import SwiftUI

@MainActor
class WindowArrangementManager {
    static let shared = WindowArrangementManager()
    private let settings = SettingsModel.shared

    func activate(plane: Plane) {
        guard let layout = (LayoutTemplate.allTemplates + settings.settings.customSnapLayouts).first(where: { $0.id == plane.layoutID }) else {
            print("[WindowArrangementManager] Error: Could not find layout with ID \(plane.layoutID) for plane '\(plane.name)'.")
            return
        }

        print("[WindowArrangementManager] Activating plane '\(plane.name)'...")

        Task {
            var runningAppsToSnap: [(app: NSRunningApplication, zone: SnapZone)] = []
            var appsToLaunch: [(bundleID: String, zone: SnapZone)] = []

            for (zoneID, bundleID) in plane.assignments {
                guard let zone = layout.zones.first(where: { $0.id == zoneID }) else { continue }

                if let runningApp = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleID }) {
                    runningAppsToSnap.append((app: runningApp, zone: zone))
                } else {
                    appsToLaunch.append((bundleID: bundleID, zone: zone))
                }
            }

            print("[WindowArrangementManager] Found \(runningAppsToSnap.count) app(s) already running. Attempting to launch \(appsToLaunch.count) app(s).")

            var allAppsToSnap = runningAppsToSnap
            if !appsToLaunch.isEmpty {
                let successfullyLaunched = await launchAndPrepareApps(appsToLaunch)
                allAppsToSnap.append(contentsOf: successfullyLaunched)
            }

            print("[WindowArrangementManager] All apps ready. Proceeding to snap \(allAppsToSnap.count) windows.")
            for item in allAppsToSnap {
                SnappingManager.snap(app: item.app, to: item.zone)
            }
        }
    }

    private func launchAndPrepareApps(_ apps: [(bundleID: String, zone: SnapZone)]) async -> [(app: NSRunningApplication, zone: SnapZone)] {
        var preparedApps: [(app: NSRunningApplication, zone: SnapZone)] = []

        await withTaskGroup(of: (NSRunningApplication, SnapZone)?.self) { group in
            for appInfo in apps {
                group.addTask {
                    guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: appInfo.bundleID) else {
                        print("[WindowArrangementManager] Error: Could not find URL for \(appInfo.bundleID)")
                        return nil
                    }

                    do {
                        print("[WindowArrangementManager] Launching \(appInfo.bundleID)...")
                        let app = try await NSWorkspace.shared.launchApplication(at: url, options: .async, configuration: [:])

                        if await self.waitForWindow(for: app, timeout: 5.0) {
                            print("[WindowArrangementManager] Window for \(appInfo.bundleID) is ready.")
                            return (app, appInfo.zone)
                        } else {
                            print("[WindowArrangementManager] Error: Timed out waiting for window of \(appInfo.bundleID)")
                            return nil
                        }
                    } catch {
                        print("[WindowArrangementManager] Error: Failed to launch \(appInfo.bundleID): \(error)")
                        return nil
                    }
                }
            }

            for await result in group {
                if let preparedApp = result {
                    preparedApps.append(preparedApp)
                }
            }
        }

        return preparedApps
    }

    private func waitForWindow(for app: NSRunningApplication, timeout: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let appElement = AXUIElementCreateApplication(app.processIdentifier)
            var windowListRef: CFTypeRef?

            if AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowListRef) == .success {
                if let windowList = windowListRef as? [AXUIElement], !windowList.isEmpty {
                    try? await Task.sleep(for: .milliseconds(150))
                    return true
                }
            }

            try? await Task.sleep(for: .milliseconds(200))
        }
        return false
    }
}