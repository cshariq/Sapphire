//
//  FocusBlocker.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-25

import Foundation
import AppKit
import SwiftUI

@MainActor
final class FocusBlocker {
    var appBlockedBundleIDs: [String] = []
    var webBlockedDomains: [String] = []
    var isBlocking: Bool { blocker.isBlocking }

    private let blocker = AppBlocker()

    private var intensity: FocusIntensity = .standard
    private var strictCooldown: TimeInterval = 10 * 60
    private var temporarilyUnblocked: Set<String> = []
    private var unblockRequests: [String: Date] = [:]
    private var unblockCooldowns: [String: TimeInterval] = [:]
    private var snoozedUntil: [String: Date] = [:]
    private var blockingMode: FocusBlockingMode = .blocklist
    private var allowedApps: Set<String> = []

    private static let allowlistEssentials: Set<String> = [
        "com.apple.finder",
        "com.apple.systempreferences",
        "com.apple.SystemSettings",
        "com.apple.dock",
    ]

    init() {
        blocker.isBlocked = { [weak self] bundleID in
            self?.isBlocked(bundleID: bundleID) ?? false
        }
        blocker.makeShieldContent = { [weak self] (appName: String, bundleID: String) in
            guard let self else { return AnyView(EmptyView()) }
            let resolvedAppName = AppShieldManager.displayName(for: bundleID)
            return AnyView(FocusShieldView(
                appName: resolvedAppName,
                intensity: self.intensity,
                onUnblockNow: { [weak self] in self?.temporarilyUnblock(bundleID: bundleID) },
                onSnooze: { [weak self] minutes in self?.snooze(bundleID: bundleID, minutes: minutes) },
                onRequestUnblock: { [weak self] in self?.requestUnblock(bundleID: bundleID) },
                remainingUnblockTime: { [weak self] in self?.remainingUnblockTime(bundleID: bundleID) }
            ))
        }
        blocker.forceClosesOnActivation = intensity.forceClosesBlockedApps
        blocker.onAppActivated = { [weak self] (appName: String, bundleID: String, _: NSRunningApplication) in
            guard let self, self.isBlocking, self.isBlocked(bundleID: bundleID) else { return }
            let resolvedAppName = AppShieldManager.displayName(for: bundleID)
            self.announceRestrictedApp(appName: resolvedAppName, bundleID: bundleID)
        }
    }

    // MARK: - Public API

    func setBlocking(enabled: Bool, apps: [String]? = nil, websites: [String]? = nil, intensity: FocusIntensity? = nil, strictCooldown: TimeInterval? = nil, mode: FocusBlockingMode? = nil, allowedApps: [String]? = nil) {
        let intensityChanged = (intensity != nil && intensity != self.intensity)
            || (strictCooldown != nil && strictCooldown != self.strictCooldown)
        if let apps { appBlockedBundleIDs = apps }
        if let websites { webBlockedDomains = websites }
        if let intensity { self.intensity = intensity }
        if let strictCooldown { self.strictCooldown = strictCooldown }
        if let mode { blockingMode = mode }
        if let allowedApps { self.allowedApps = Set(allowedApps) }

        blocker.forceClosesOnActivation = self.intensity.forceClosesBlockedApps

        if enabled == isBlocking {
            if isBlocking {
                if intensityChanged {
                    blocker.removeAllShields()
                }
                blocker.refresh()
            }
            return
        }

        if enabled {
            temporarilyUnblocked.removeAll()
            unblockRequests.removeAll()
            snoozedUntil.removeAll()
            closeRunningBlockedApps()
            blocker.setBlocking(true)
        } else {
            blocker.setBlocking(false)
        }
    }

    func isBlocked(bundleID: String) -> Bool {
        guard isBlocking else { return false }
        if temporarilyUnblocked.contains(bundleID) { return false }
        if let until = snoozedUntil[bundleID] {
            if until > Date() { return false }
            snoozedUntil[bundleID] = nil
        }
        if let requestDate = unblockRequests[bundleID] {
            let remaining = unblockCooldowns[bundleID] ?? (strictCooldown - Date().timeIntervalSince(requestDate))
            if remaining > 0 { return true }
            unblockRequests[bundleID] = nil
            unblockCooldowns[bundleID] = nil
            return false
        }
        if blockingMode == .allowlist {
            if allowedApps.contains(bundleID) || Self.allowlistEssentials.contains(bundleID) {
                return false
            }
            return true
        }
        return appBlockedBundleIDs.contains(bundleID)
    }

    func snooze(bundleID: String, minutes: Int) {
        snoozedUntil[bundleID] = Date().addingTimeInterval(TimeInterval(minutes * 60))
        blocker.unshield(bundleID: bundleID)
    }

    func hasPendingUnblockRequest(bundleID: String) -> Bool {
        unblockRequests[bundleID] != nil
    }

    func remainingUnblockTime(bundleID: String) -> TimeInterval? {
        guard let requestDate = unblockRequests[bundleID] else { return nil }
        return max(0, (unblockCooldowns[bundleID] ?? strictCooldown) - Date().timeIntervalSince(requestDate))
    }

    func temporarilyUnblock(bundleID: String) {
        temporarilyUnblocked.insert(bundleID)
        blocker.unshield(bundleID: bundleID)
    }

    func requestUnblock(bundleID: String, cooldown: TimeInterval? = nil) {
        unblockRequests[bundleID] = Date()
        if let cooldown {
            unblockCooldowns[bundleID] = cooldown
        }
        blocker.refresh()
    }

    func requestProductiveWebsiteAccess(domain: String) -> Bool {
        guard SubscriptionAccess.hasAccess(to: .focusProductiveAccess),
              isBlocking,
              webBlockedDomains.contains(FocusWebsiteBlocker.normalize([domain]).first ?? "") else {
            return false
        }
        return true
    }

    // MARK: - Internals

    private func closeRunningBlockedApps() {
        guard intensity.forceClosesBlockedApps else { return }
        for app in NSWorkspace.shared.runningApplications {
            guard let bundleID = app.bundleIdentifier,
                  bundleID != Bundle.main.bundleIdentifier,
                  isBlocked(bundleID: bundleID) else { continue }
            announceRestrictedApp(
                appName: AppShieldManager.displayName(for: bundleID),
                bundleID: bundleID
            )
            AppShieldManager.forceClose(app, guard: self.isBlocking)
        }
    }

    // MARK: - Force-close announcements

    private func announceRestrictedApp(appName: String, bundleID: String) {
        NotificationCenter.default.post(
            name: .focusRestrictedAppOpened,
            object: nil,
            userInfo: ["appName": appName, "bundleID": bundleID]
        )
    }
}

// MARK: - Shield content view

struct FocusShieldView: View {
    let appName: String
    let intensity: FocusIntensity
    let onUnblockNow: () -> Void
    let onSnooze: (Int) -> Void
    let onRequestUnblock: () -> Void
    let remainingUnblockTime: () -> TimeInterval?

    @State private var requested = false

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
            Rectangle()
                .fill(Color.black.opacity(0.35))

            VStack(spacing: 14) {
                Image(systemName: iconName)
                    .font(.system(size: 46, weight: .semibold))
                    .foregroundStyle(.white)

                Text("\(appName) is blocked")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)

                Text(message)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center)

                actionButton
            }
            .padding(24)
            .frame(maxWidth: 420)
        }
        .ignoresSafeArea()
    }

    private var iconName: String {
        switch intensity {
        case .minimal: return "hand.raised.fill"
        case .gentle: return "hand.raised.fill"
        case .standard: return "lock.shield.fill"
        case .strict: return "shield.lefthalf.filled"
        }
    }

    private var message: String {
        switch intensity {
        case .minimal:
            return "Focus session in progress — stay on task! You can use this app for a moment if you really need it."
        case .gentle:
            return "Focus session in progress — this app is blocked until the session ends. "
        case .standard:
            return "Focus session in progress — this app is restricted. It was closed and will reopen once the session ends."
        case .strict:
            return "Focus session in progress — this app is restricted. Unblocking takes 10 minutes and the session can't be stopped early."
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        switch intensity {
        case .minimal, .gentle, .standard:
            VStack(spacing: 10) {
                if intensity == .minimal {
                    Button(action: { onUnblockNow() }) {
                        Label("Use Anyway", systemImage: "arrow.uturn.forward")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 10)
                            .background(Color.white.opacity(0.22), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                snoozeRow
            }
        case .strict:
            if requested || remainingUnblockTime() != nil {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    if let remaining = remainingUnblockTime() {
                        VStack(spacing: 4) {
                            Image(systemName: "hourglass")
                                .font(.system(size: 14, weight: .semibold))
                            Text("Unblocked in \(Self.formatCountdown(remaining))")
                                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                        }
                        .foregroundColor(.white.opacity(0.9))
                    }
                }
            } else {
                Button(action: {
                    requested = true
                    onRequestUnblock()
                }) {
                    Label("Request Unblock", systemImage: "clock.badge.questionmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(Color.orange.opacity(0.65), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var snoozeRow: some View {
        VStack(spacing: 5) {
            Text("Need it briefly? Snooze blocking for")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.75))
            HStack(spacing: 8) {
                snoozeButton(minutes: 5)
                snoozeButton(minutes: 15)
                snoozeButton(minutes: 60)
            }
        }
    }

    private func snoozeButton(minutes: Int) -> some View {
        Button(action: { onSnooze(minutes) }) {
            Text("\(minutes)m")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.18), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private static func formatCountdown(_ time: TimeInterval) -> String {
        let total = Int(time.rounded())
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}