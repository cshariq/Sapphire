//
//  AppShieldManager.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-30

import AppKit
import SwiftUI
import OSLog

@MainActor
final class AppShieldManager {
    static let shared = AppShieldManager()

    private let cid = CGSMainConnectionID()

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Sapphire", category: "AppShield")

    // MARK: - Window enumeration

    static func onScreenWindowsByBundleID(
        only bundleID: String? = nil
    ) -> [String: [CGWindowID: NSRect]] {
        guard let list = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return [:]
        }

        var pidCache: [Int: String] = [:]
        func lookupBundleID(forPID pid: Int) -> String? {
            if let cached = pidCache[pid] { return cached }
            guard let app = NSRunningApplication(processIdentifier: pid_t(pid)),
                  let bid = app.bundleIdentifier else { return nil }
            pidCache[pid] = bid
            return bid
        }

        let topEdge = NSScreen.screens.first { $0.frame.origin == .zero }?.frame.maxY
            ?? NSScreen.screens.map { $0.frame.maxY }.max()
            ?? 0
        let ownPID = Bundle.main.bundleIdentifier
        var result: [String: [CGWindowID: NSRect]] = [:]

        for info in list {
            guard let pidValue = info[kCGWindowOwnerPID as String] as? Int,
                  let bid = lookupBundleID(forPID: pidValue),
                  bid != ownPID else { continue }
            if let bundleID, bid != bundleID { continue }
            if let layer = info[kCGWindowLayer as String] as? Int, layer != 0 { continue }
            guard let bounds = info[kCGWindowBounds as String] as? [String: CGFloat],
                  let width = bounds["Width"], let height = bounds["Height"],
                  width >= 120, height >= 80 else { continue }
            guard let windowNumber = info[kCGWindowNumber as String] as? CGWindowID else { continue }
            let x = bounds["X"] ?? 0
            let yTop = bounds["Y"] ?? 0
            let yBottom = topEdge - yTop - height
            result[bid, default: [:]][windowNumber] = NSRect(
                x: x, y: yBottom, width: width, height: height
            )
        }
        return result
    }

    // MARK: - Window snapshot cache

    private static var snapshotCache: [String: [CGWindowID: NSRect]]?
    private static var snapshotDate: Date?
    private static let snapshotTTL: TimeInterval = 1.0

    static func cachedOnScreenWindowsByBundleID() -> [String: [CGWindowID: NSRect]] {
        let now = Date()
        if let cache = snapshotCache, let date = snapshotDate,
           now.timeIntervalSince(date) < snapshotTTL {
            return cache
        }
        let map = onScreenWindowsByBundleID()
        snapshotCache = map
        snapshotDate = now
        return map
    }

    static func invalidateSnapshot() {
        snapshotCache = nil
        snapshotDate = nil
    }

    static func windowFrames(forBundleID bundleID: String) -> [CGWindowID: NSRect] {
        cachedOnScreenWindowsByBundleID()[bundleID] ?? [:]
    }

    static func windowFillsScreen(_ frame: NSRect) -> Bool {
        for screen in NSScreen.screens {
            let sf = screen.frame
            if abs(sf.width - frame.width) < 2 && abs(sf.height - frame.height) < 2 {
                return true
            }
        }
        return false
    }

    static func shieldFrame(for parentFrame: NSRect) -> NSRect {
        let titleBarInset: CGFloat = windowFillsScreen(parentFrame) ? 0 : 28
        return NSRect(
            x: parentFrame.minX,
            y: parentFrame.minY,
            width: parentFrame.width,
            height: max(0, parentFrame.height - titleBarInset)
        )
    }

    // MARK: - Shield lifecycle

    @discardableResult
    static func makeShield(
        parentWindowNumber: CGWindowID,
        frame: NSRect,
        contentView: some View,
        keyable: Bool = false
    ) -> NSWindow {
        let shieldFrame = shieldFrame(for: frame)

        let window: NSWindow = {
            if keyable {
                return _KeyableShieldWindow(
                    contentRect: shieldFrame,
                    styleMask: [.borderless],
                    backing: .buffered,
                    defer: false
                )
            }
            return NSWindow(
                contentRect: shieldFrame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
        }()

        window.level = .floating
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = false
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.collectionBehavior = windowFillsScreen(frame)
            ? [.fullScreenAuxiliary] : []

        window.contentView = NSHostingView(rootView: contentView)
        window.orderFrontRegardless()

        let cid = CGSMainConnectionID()
        let childNumber = CGWindowID(window.windowNumber)
        _ = CGSAddWindowToWindowOrderingGroup(cid, childNumber, parentWindowNumber)
        _ = CGSAddWindowToWindowMovementGroup(cid, childNumber, parentWindowNumber)
        _ = CGSOrderWindow(cid, childNumber, 1, parentWindowNumber)

        return window
    }

    static func removeShield(_ window: NSWindow) {
        let cid = CGSMainConnectionID()
        let childNumber = CGWindowID(window.windowNumber)
        _ = CGSRemoveFromOrderingGroup(cid, childNumber)
        _ = CGSRemoveWindowFromWindowMovementGroup(cid, childNumber)
        window.orderOut(nil)
    }

    // MARK: - App lifecycle

    static func forceClose(_ app: NSRunningApplication, guard isValid: @autoclosure @escaping () -> Bool = true) {
        app.terminate()
        let pid = app.processIdentifier
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            guard isValid(),
                  let still = NSRunningApplication(processIdentifier: pid),
                  !still.isTerminated else { return }
            still.forceTerminate()
        }
    }

    private static var resolvedNameCache: [String: String] = [:]
    private static let emptyBundleID = "(unknown bundle)"

    static func displayName(for bundleID: String) -> String {
        if let cached = resolvedNameCache[bundleID], !isPlaceholder(cached) {
            return cached
        }

        var name: String?
        var source = "none"

        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
            if let localized = running.localizedName, !isPlaceholder(localized) {
                name = localized
                source = "running"
            }
        }

        if name == nil,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
           let bundle = Bundle(url: url) {
            let candidates = [
                bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String,
                bundle.object(forInfoDictionaryKey: "CFBundleName") as? String,
                url.deletingPathExtension().lastPathComponent,
            ].compactMap { $0 }
            if let resolvedCandidate = candidates.first(where: { !isPlaceholder($0) }) {
                name = resolvedCandidate
                source = "bundle"
            }
        }

        let resolved: String
        if let name, !isPlaceholder(name) {
            resolved = name
        } else if bundleID.isEmpty {
            resolved = emptyBundleID
        } else {
            resolved = bundleID
        }
        resolvedNameCache[bundleID] = resolved

        if resolved != bundleID, !bundleID.isEmpty {
            logger.info("displayName(\(bundleID, privacy: .public)) -> \(resolved, privacy: .public) (source: \(source, privacy: .public))")
        } else {
            logger.warning("displayName(\(bundleID, privacy: .public)) could not be resolved (source: \(source, privacy: .public)); falling back to bundle id")
        }
        return resolved
    }

    private static func isPlaceholder(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        let lower = trimmed.lowercased()
        return lower == "(app name)" || lower == "app name" || lower.hasSuffix("(app name)")
    }
}

// MARK: - Keyable shield window

private final class _KeyableShieldWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}