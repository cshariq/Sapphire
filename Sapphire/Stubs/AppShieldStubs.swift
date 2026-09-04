// Minimal stubs to satisfy Focus-related compile references when not building full app
// These are lightweight implementations intended for the non-full build / stubs scenario.

#if !SAPPHIRE_FULL_BUILD
import Foundation
import AppKit
import SwiftUI

// Simple blocking controller used by FocusBlocker in stubs build
final class AppBlocker {
    var isBlocked: ((String) -> Bool)?
    var makeShieldContent: ((String, String) -> AnyView)?
    var forceClosesOnActivation: Bool = false
    var onAppActivated: ((String, String, NSRunningApplication) -> Void)?

    private(set) var isBlocking: Bool = false

    func setBlocking(_ enabled: Bool) {
        isBlocking = enabled
    }

    func removeAllShields() {}
    func refresh() {}
    func unshield(bundleID: String) {}
}

// Manager helpers used by FocusBlocker
enum AppShieldManager {
    static func displayName(for bundleID: String) -> String {
        // Try to resolve a user-friendly name, fall back to bundle identifier
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first,
           let name = app.localizedName {
            return name
        }
        return bundleID
    }

    static func forceClose(_ app: NSRunningApplication, guard: Bool) {
        // Best-effort attempt to terminate the app in stub builds
        if `guard` {
            app.terminate()
        }
    }
}

// Mode for the shield view; only the focus case is required here
enum AppShieldMode {
    case focus(intensity: FocusIntensity,
               onUnblockNow: () -> Void,
               onSnooze: (Int) -> Void,
               onRequestUnblock: () -> Void,
               remainingUnblockTime: () -> TimeInterval?,
               onHide: () -> Void)
}

// Minimal view shown when an app is blocked. EmptyView is sufficient for stubs.
struct AppShieldView: View {
    let appName: String
    let mode: AppShieldMode

    init(appName: String, mode: AppShieldMode) {
        self.appName = appName
        self.mode = mode
    }

    var body: some View { EmptyView() }
}

#endif
