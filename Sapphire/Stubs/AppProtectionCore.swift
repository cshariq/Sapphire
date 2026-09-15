//
//  AppProtectionCore.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-15

#if !SAPPHIRE_FULL_BUILD
import AppKit
import SwiftUI

@MainActor
final class AppBlocker {
    var isBlocked: (String) -> Bool = { _ in false }
    var makeShieldContent: (String, String) -> AnyView = { _, _ in AnyView(EmptyView()) }
    var shieldsAreKeyable = false
    var forceClosesOnActivation = false
    var shieldsOnlyWhenFrontmost = false
    var keepsShieldWhenNotFrontmost: (String) -> Bool = { _ in false }
    var onAppActivated: ((_ appName: String, _ bundleID: String, _ app: NSRunningApplication) -> Void)?
    private(set) var isBlocking = false

    func setBlocking(_ enabled: Bool) { isBlocking = enabled }
    func refresh() {}
    func shield(bundleID: String) {}
    func isShielded(_ bundleID: String) -> Bool { false }
    func unshield(bundleID: String) {}
    func removeAllShields() {}
}

@MainActor
enum AppShieldManager {
    static func displayName(for bundleID: String) -> String { bundleID }

    @discardableResult
    static func forceClose(
        _ app: NSRunningApplication,
        guard isValid: @autoclosure @escaping () -> Bool = true,
        immediate: Bool = false
    ) -> Bool { false }
}

enum AppShieldMode {
    case focus(
        intensity: FocusIntensity,
        onUnblockNow: () -> Void,
        onSnooze: (Int) -> Void,
        onRequestUnblock: () -> Void,
        remainingUnblockTime: () -> TimeInterval?,
        onHide: () -> Void
    )
}

struct AppShieldView: View {
    let appName: String
    let mode: AppShieldMode
    var body: some View { Color.clear }
}
#endif