//
//  FocusNotificationSuppressor.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-25
//

import Foundation
import AppKit

@MainActor
final class FocusNotificationSuppressor {
    static let shared = FocusNotificationSuppressor()

    private let prefsDomain = "com.apple.ncprefs"

    private static let allowNotifications = 1 << 25
    private static let banners = 1 << 3
    private static let alerts = 1 << 4
    private static let showInNotificationCenter = 1 << 0
    private static let showOnLockScreen = 1 << 12

    private static let suppressMask = banners | alerts | showInNotificationCenter | showOnLockScreen

    private var originalFlags: [String: Int] = [:]

    var isActive: Bool { !originalFlags.isEmpty }

    func suppress(_ bundleIDs: [String]) {
        let targets = Set(bundleIDs)
        guard !targets.isEmpty else { return }
        guard var apps = readAppsArray() else { return }

        var changed = false
        for i in apps.indices {
            var entry = apps[i]
            guard let bundleID = entry["bundle-id"] as? String, targets.contains(bundleID) else { continue }
            guard let raw = entry["flags"] as? NSNumber else { continue }
            let flags = raw.intValue
            guard flags & Self.allowNotifications != 0 else { continue }

            if originalFlags[bundleID] == nil {
                originalFlags[bundleID] = flags
            }
            let newFlags = flags & ~Self.suppressMask
            if newFlags != flags {
                entry["flags"] = NSNumber(value: newFlags)
                apps[i] = entry
                changed = true
            }
        }

        guard changed else { return }
        writeAppsArray(apps)
        reloadNotificationCenter()
        print("[FocusNotificationSuppressor] Suppressed notifications for \(changed) app(s)")
    }

    func restoreAll() {
        guard !originalFlags.isEmpty else { return }
        guard var apps = readAppsArray() else { return }

        var changed = false
        for i in apps.indices {
            var entry = apps[i]
            guard let bundleID = entry["bundle-id"] as? String,
                  let original = originalFlags[bundleID] else { continue }
            entry["flags"] = NSNumber(value: original)
            apps[i] = entry
            changed = true
        }

        originalFlags.removeAll()
        guard changed else { return }
        writeAppsArray(apps)
        reloadNotificationCenter()
        print("[FocusNotificationSuppressor] Restored notification settings")
    }

    // MARK: - ncprefs plumbing

    private func readAppsArray() -> [[String: Any]]? {
        guard let apps = CFPreferencesCopyAppValue("apps" as CFString, prefsDomain as CFString) as? [[String: Any]] else {
            print("[FocusNotificationSuppressor] Could not read ncprefs apps array")
            return nil
        }
        return apps
    }

    private func writeAppsArray(_ apps: [[String: Any]]) {
        CFPreferencesSetAppValue("apps" as CFString, apps as CFArray, prefsDomain as CFString)
        CFPreferencesAppSynchronize(prefsDomain as CFString)
    }

    private func reloadNotificationCenter() {
        ProcessRunner.runDetached(executablePath: "/usr/bin/killall", arguments: ["usernoted"])
    }
}