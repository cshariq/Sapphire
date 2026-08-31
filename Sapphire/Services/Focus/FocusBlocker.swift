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
            return AnyView(AppShieldView(
                appName: resolvedAppName,
                mode: .focus(
                    intensity: self.intensity,
                    onUnblockNow: { [weak self] in self?.temporarilyUnblock(bundleID: bundleID) },
                    onSnooze: { [weak self] minutes in self?.snooze(bundleID: bundleID, minutes: minutes) },
                    onRequestUnblock: { [weak self] in self?.requestUnblock(bundleID: bundleID) },
                    remainingUnblockTime: { [weak self] in self?.remainingUnblockTime(bundleID: bundleID) },
                    onHide: { [weak self] in self?.hideBlockedApp(bundleID: bundleID) }
                )
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

    func hideBlockedApp(bundleID: String) {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first,
              !app.isTerminated else { return }
        app.hide()
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