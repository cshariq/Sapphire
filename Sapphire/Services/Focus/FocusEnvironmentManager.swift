//
//  FocusEnvironmentManager.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-25
//

import Foundation
import AppKit
import SwiftUI
import Combine

@MainActor
final class FocusEnvironmentManager {
    static let shared = FocusEnvironmentManager()

    private(set) var isActive = false

    private var dimInactive = false
    private var dimOpacity = 0.45
    private var disableDimInMissionControl = false
    private var hideWallpaper = false
    private var appLimitEnabled = false
    private var appLimit = 2

    private let cid = CGSMainConnectionID()
    private var refreshTimer: Timer?
    private var activeAppCancellables = Set<AnyCancellable>()
    private var dimWindows: [NSWindow] = []
    private var appliedScreenFrames: [NSRect] = []
    private var appliedDimOpacity: Double = 0.45
    private var wallpaperWindows: [NSWindow] = []

    private var recentApps: [String] = []
    private var hiddenWindows: Set<CGWindowID> = []
    private var hiddenBundleIDs: Set<String> = []

    static let essentials: Set<String> = [
        "com.apple.finder",
        "com.apple.systempreferences",
        "com.apple.SystemSettings",
        "com.apple.dock",
        "com.apple.controlcenter",
    ]

    private init() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.restoreHiddenWindows()
        }
    }

    // MARK: - Public API

    func configure(
        dimInactive: Bool,
        dimOpacity: Double,
        disableDimInMissionControl: Bool = false,
        hideWallpaper: Bool,
        appLimitEnabled: Bool,
        appLimit: Int
    ) {
        self.dimInactive = dimInactive
        self.dimOpacity = min(1.0, max(0.1, dimOpacity))
        self.disableDimInMissionControl = disableDimInMissionControl
        self.hideWallpaper = hideWallpaper
        self.appLimitEnabled = appLimitEnabled
        self.appLimit = max(1, appLimit)
        if isActive { refresh() }
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled != isActive else { return }
        isActive = enabled
        if enabled {
            recentApps.removeAll()
            appliedDimOpacity = dimOpacity
            start()
        } else {
            stop()
        }
    }

    // MARK: - Lifecycle

    private func start() {
        guard activeAppCancellables.isEmpty else { return }
        let monitor = ActiveAppMonitor.shared

        monitor.$activeAppBundleID
            .receive(on: DispatchQueue.main)
            .sink { [weak self] bundleID in
                guard let self, let bundleID else { return }
                self.handleFrontAppChange(bundleID: bundleID)
            }
            .store(in: &activeAppCancellables)

        refreshTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        refresh()
    }

    private func stop() {
        activeAppCancellables.removeAll()
        refreshTimer?.invalidate()
        refreshTimer = nil

        removeAllDimOverlays()

        for window in wallpaperWindows { window.orderOut(nil) }
        wallpaperWindows.removeAll()

        restoreHiddenWindows()
        recentApps.removeAll()
    }

    // MARK: - Refresh

    private func refresh() {
        guard isActive else { return }
        updateWallpaperWindows()
        if dimInactive {
            if disableDimInMissionControl && missionControlIsActive() {
                removeAllDimOverlays()
            } else {
                refreshDimOverlays()
            }
        } else {
            removeAllDimOverlays()
        }
        if appLimitEnabled { reapplyHiddenWindows() }
    }

    // MARK: - Wallpaper hiding

    private var appliedWallpaperFrames: [NSRect] = []

    private func updateWallpaperWindows() {
        guard hideWallpaper else {
            if !wallpaperWindows.isEmpty {
                for window in wallpaperWindows { window.orderOut(nil) }
                wallpaperWindows.removeAll()
                appliedWallpaperFrames.removeAll()
            }
            return
        }

        let currentFrames = NSScreen.screens.map(\.frame)
        guard currentFrames != appliedWallpaperFrames else {
            for window in wallpaperWindows { window.orderFrontRegardless() }
            return
        }
        for window in wallpaperWindows { window.orderOut(nil) }
        wallpaperWindows.removeAll()
        appliedWallpaperFrames = currentFrames

        for screen in NSScreen.screens {
            let window = NSWindow(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)))
            window.isOpaque = true
            window.backgroundColor = .black
            window.ignoresMouseEvents = true
            window.isReleasedWhenClosed = false
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
            window.orderFrontRegardless()
            wallpaperWindows.append(window)
        }
    }

    // MARK: - Dimming

    private func refreshDimOverlays() {
        let frontmost = NSWorkspace.shared.frontmostApplication
        let ownPID = ProcessInfo.processInfo.processIdentifier

        guard let frontmost, frontmost.processIdentifier != ownPID else {
            removeAllDimOverlays()
            return
        }
        let frontPID = frontmost.processIdentifier
        let frontBundleID = frontmost.bundleIdentifier

        if appliedDimOpacity != dimOpacity {
            appliedDimOpacity = dimOpacity
            removeAllDimOverlays()
        }

        let screens = NSScreen.screens
        let frames = screens.map(\.frame)
        if appliedScreenFrames != frames {
            appliedScreenFrames = frames
            removeAllDimOverlays()
        }

        guard !screens.isEmpty else { return }
        var layersBuiltThisPass = false
        if dimWindows.count != screens.count {
            removeAllDimOverlays()
            for screen in screens { makeDimWindow(for: screen) }
            layersBuiltThisPass = true
        }

        let windows = windowList()
        guard !windows.isEmpty else { return }

        guard windows.contains(where: { belongs(to: $0.pid, bundleID: frontBundleID, fallbackPID: frontPID) }) else {
            removeAllDimOverlays()
            return
        }

        for (index, screen) in screens.enumerated() {
            guard index < dimWindows.count else { continue }
            let dimNumber = CGWindowID(dimWindows[index].windowNumber)
            let onScreen = windows.filter { screen.frame.intersects($0.frame) }
            guard let first = onScreen.first else { continue }
            if let deepest = onScreen.last(where: { belongs(to: $0.pid, bundleID: frontBundleID, fallbackPID: frontPID) }) {
                _ = CGSOrderWindow(cid, dimNumber, -1, deepest.windowNumber)
            } else {
                _ = CGSOrderWindow(cid, dimNumber, 1, first.windowNumber)
            }
        }

        if layersBuiltThisPass {
            frontmost.activate(options: [.activateIgnoringOtherApps])
        }
    }

    private func belongs(to pid: pid_t, bundleID: String?, fallbackPID: pid_t) -> Bool {
        if pid == fallbackPID { return true }
        guard let bundleID,
              let app = NSRunningApplication(processIdentifier: pid),
              let appBundleID = app.bundleIdentifier else { return false }
        return appBundleID == bundleID
    }

    private func makeDimWindow(for screen: NSScreen) {
        let window = NSWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.level = .normal
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]
        window.contentView = NSHostingView(
            rootView: Rectangle()
                .fill(Color.black.opacity(dimOpacity))
                .ignoresSafeArea()
        )
        window.orderFrontRegardless()
        dimWindows.append(window)
    }

    private func removeAllDimOverlays() {
        for window in dimWindows { window.orderOut(nil) }
        dimWindows.removeAll()
    }

    // MARK: - App limiting

    private func handleFrontAppChange(bundleID: String) {
        if isActive, dimInactive { refreshDimOverlays() }
        guard isActive, appLimitEnabled else { return }
        if bundleID == Bundle.main.bundleIdentifier || Self.essentials.contains(bundleID) { return }

        recentApps.removeAll { $0 == bundleID }
        recentApps.insert(bundleID, at: 0)

        while recentApps.count > appLimit {
            let gone = recentApps.removeLast()
            hideWindows(of: gone)
        }
    }

    private func hideWindows(of bundleID: String) {
        hiddenBundleIDs.insert(bundleID)
        for windowNumber in windows(of: bundleID) {
            guard !hiddenWindows.contains(windowNumber) else { continue }
            _ = CGSOrderWindow(cid, windowNumber, 0, 0)
            hiddenWindows.insert(windowNumber)
        }
    }

    private func reapplyHiddenWindows() {
        guard !hiddenBundleIDs.isEmpty else { return }
        for bundleID in hiddenBundleIDs {
            for windowNumber in windows(of: bundleID) {
                guard !hiddenWindows.contains(windowNumber) else { continue }
                _ = CGSOrderWindow(cid, windowNumber, 0, 0)
                hiddenWindows.insert(windowNumber)
            }
        }
    }

    private func restoreHiddenWindows() {
        for windowNumber in hiddenWindows {
            _ = CGSOrderWindow(cid, windowNumber, 1, 0)
        }
        hiddenWindows.removeAll()
        hiddenBundleIDs.removeAll()
    }

    // MARK: - Mission Control detection

    private func missionControlIsActive() -> Bool {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return false
        }
        for info in list {
            guard let owner = info[kCGWindowOwnerName as String] as? String, owner == "Dock" else { continue }
            guard let name = info[kCGWindowName as String] as? String, name == "Dock - (null)" else { continue }
            return true
        }
        return false
    }

    // MARK: - Window enumeration (CGWindowList)

    private func windowList() -> [(windowNumber: CGWindowID, pid: pid_t, frame: NSRect)] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let topEdge = NSScreen.screens.map { $0.frame.maxY }.max() ?? NSScreen.main?.frame.maxY ?? 0
        var result: [(windowNumber: CGWindowID, pid: pid_t, frame: NSRect)] = []
        for info in list {
            if let layer = info[kCGWindowLayer as String] as? Int, layer > 1 { continue }
            guard let pidValue = info[kCGWindowOwnerPID as String] as? Int, pid_t(pidValue) != ownPID else { continue }
            guard let bounds = info[kCGWindowBounds as String] as? [String: CGFloat],
                  let width = bounds["Width"], let height = bounds["Height"],
                  width > 0, height > 0 else { continue }
            guard let windowNumber = info[kCGWindowNumber as String] as? CGWindowID else { continue }
            let x = bounds["X"] ?? 0
            let yTop = bounds["Y"] ?? 0
            let yBottom = topEdge - yTop - height
            result.append((windowNumber, pid_t(pidValue), NSRect(x: x, y: yBottom, width: width, height: height)))
        }
        return result
    }

    private func windows(of bundleID: String) -> Set<CGWindowID> {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        var result = Set<CGWindowID>()
        for info in list {
            guard let pidValue = info[kCGWindowOwnerPID as String] as? Int,
                  let app = NSRunningApplication(processIdentifier: pid_t(pidValue)),
                  app.bundleIdentifier == bundleID else { continue }
            if let layer = info[kCGWindowLayer as String] as? Int, layer != 0 { continue }
            guard let windowNumber = info[kCGWindowNumber as String] as? CGWindowID else { continue }
            result.insert(windowNumber)
        }
        return result
    }
}