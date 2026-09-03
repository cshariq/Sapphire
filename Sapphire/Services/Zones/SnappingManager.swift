//
//  SnappingManager.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-08-11.
//

import AppKit
import ApplicationServices

@MainActor
final class SnappingManager {
    static func snap(layoutID: UUID, zoneID: UUID) {
        let layouts = LayoutTemplate.allTemplates + SettingsModel.shared.settings.customSnapLayouts
        guard let layout = layouts.first(where: { $0.id == layoutID }),
              let zone = layout.zones.first(where: { $0.id == zoneID }) else {
            print("[SnappingManager] Could not find layout/zone for shortcut.")
            return
        }

        snap(zone: zone)
    }

    static func snap(zone: SnapZone) {
        guard let app = frontmostApplication() else {
            print("[SnappingManager] Could not identify a frontmost application to snap.")
            return
        }
        snap(app: app, to: zone)
    }

    static func snap(app: NSRunningApplication, to zone: SnapZone) {
        guard app.bundleIdentifier != Bundle.main.bundleIdentifier,
              let windowElement = getMostLikelyMainWindow(for: app),
              let accessibilityFrame = accessibilityFrame(of: windowElement),
              let screen = screen(for: accessibilityFrame) else {
            print("[SnappingManager] Could not find a usable window or display for \(app.bundleIdentifier ?? "unknown app")")
            return
        }

        let visibleFrame = screen.visibleFrame
        let normalizedX = max(0, min(1, zone.x))
        let normalizedY = max(0, min(1, zone.y))
        let normalizedWidth = max(0, min(1 - normalizedX, zone.width))
        let normalizedHeight = max(0, min(1 - normalizedY, zone.height))
        guard normalizedWidth > 0, normalizedHeight > 0 else {
            print("[SnappingManager] Ignoring an empty snap zone.")
            return
        }

        let targetFrame = CGRect(
            x: visibleFrame.origin.x + visibleFrame.width * normalizedX,
            y: visibleFrame.origin.y + visibleFrame.height * (1 - normalizedY - normalizedHeight),
            width: visibleFrame.width * normalizedWidth,
            height: visibleFrame.height * normalizedHeight
        )

        let mainDisplayMaxY = mainDisplayFrame?.maxY ?? screen.frame.maxY
        let targetPosition = CGPoint(
            x: targetFrame.minX,
            y: mainDisplayMaxY - targetFrame.maxY
        )

        var targetSize = targetFrame.size
        let sizeResult = AXValueCreate(AXValueType.cgSize, &targetSize)
            .map { AXUIElementSetAttributeValue(windowElement, kAXSizeAttribute as CFString, $0) }

        var position = targetPosition
        let positionResult = AXValueCreate(AXValueType.cgPoint, &position)
            .map { AXUIElementSetAttributeValue(windowElement, kAXPositionAttribute as CFString, $0) }

        guard sizeResult == .success, positionResult == .success else {
            print("[SnappingManager] Failed to move/resize \(app.bundleIdentifier ?? "unknown app"): size=\(String(describing: sizeResult)), position=\(String(describing: positionResult))")
            return
        }
    }

    private static func frontmostApplication() -> NSRunningApplication? {
        let ownBundleID = Bundle.main.bundleIdentifier
        if let frontmost = NSWorkspace.shared.frontmostApplication,
           frontmost.bundleIdentifier != ownBundleID {
            return frontmost
        }

        if let activeApp = NSWorkspace.shared.runningApplications.first(where: {
            $0.isActive && $0.bundleIdentifier != ownBundleID
        }) {
            return activeApp
        }

        if let bundleID = ActiveAppMonitor.shared.activeAppBundleID,
           let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleID }) {
            return app
        }

        return nil
    }

    private static func getMostLikelyMainWindow(for app: NSRunningApplication) -> AXUIElement? {
        let appElement = AXUIElementCreateApplication(app.processIdentifier)

        var focusedWindowRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focusedWindowRef) == .success,
           let focusedWindowRef,
           !isMinimized(focusedWindowRef as! AXUIElement) {
            return focusedWindowRef as! AXUIElement
        }

        var mainWindowRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(appElement, kAXMainWindowAttribute as CFString, &mainWindowRef) == .success,
           let mainWindowRef,
           !isMinimized(mainWindowRef as! AXUIElement) {
            return mainWindowRef as! AXUIElement
        }

        var windowListRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowListRef) == .success,
              let windowList = windowListRef as? [AXUIElement] else {
            return nil
        }

        var fallbackWindow: AXUIElement?
        for window in windowList where !isMinimized(window) {
            if fallbackWindow == nil {
                fallbackWindow = window
            }

            var subroleRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(window, kAXSubroleAttribute as CFString, &subroleRef) == .success,
               let subrole = subroleRef as? String,
               subrole == kAXStandardWindowSubrole as String {
                return window
            }
        }

        return fallbackWindow
    }

    private static func isMinimized(_ window: AXUIElement) -> Bool {
        var minimizedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &minimizedRef) == .success else {
            return false
        }
        return (minimizedRef as? NSNumber)?.boolValue == true
    }

    private static func accessibilityFrame(of window: AXUIElement) -> CGRect? {
        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionRef) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let positionRef,
              let sizeRef else {
            return nil
        }

        var origin = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionRef as! AXValue, .cgPoint, &origin),
              AXValueGetValue(sizeRef as! AXValue, .cgSize, &size),
              size.width > 0,
              size.height > 0 else {
            return nil
        }

        let mainDisplayMaxY = mainDisplayFrame?.maxY ?? 0
        return CGRect(
            x: origin.x,
            y: mainDisplayMaxY - origin.y - size.height,
            width: size.width,
            height: size.height
        )
    }

    private static func screen(for accessibilityFrame: CGRect) -> NSScreen? {
        let center = CGPoint(x: accessibilityFrame.midX, y: accessibilityFrame.midY)
        return NSScreen.screens.first(where: { $0.frame.contains(center) })
            ?? NSScreen.screens.first(where: { $0.frame.intersects(accessibilityFrame) })
            ?? NSScreen.main
    }

    private static var mainDisplayFrame: CGRect? {
        let mainDisplayID = CGMainDisplayID()
        return NSScreen.screens.first { screen in
            let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
            return displayID == mainDisplayID
        }?.frame
    }
}