//
//  SnappingManager.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-08-11.
//

import AppKit
import SwiftUI

@MainActor
class SnappingManager {
    @_silgen_name("_AXUIElementGetWindow") private static func _AXUIElementGetWindow(_ element: AXUIElement, _ wid: UnsafeMutablePointer<CGWindowID>) -> CGError

    static func snap(app: NSRunningApplication, to zone: SnapZone) {
        guard let windowElement = getMostLikelyMainWindow(for: app),
              let screen = NSScreen.main else {
            print("[SnappingManager] Could not find main window or screen for \(app.bundleIdentifier ?? "unknown app")")
            return
        }

        let visibleFrame = screen.visibleFrame
        let fullFrame = screen.frame

        let targetSize = CGSize(
            width: visibleFrame.width * zone.width,
            height: visibleFrame.height * zone.height
        )

        let targetOriginBottomLeft = CGPoint(
            x: visibleFrame.origin.x + (visibleFrame.width * zone.x),
            y: visibleFrame.origin.y + (visibleFrame.height * (1.0 - zone.y - zone.height))
        )

        let targetOriginTopLeft = CGPoint(
            x: targetOriginBottomLeft.x,
            y: fullFrame.height - (targetOriginBottomLeft.y + targetSize.height)
        )

        var position = targetOriginTopLeft
        if let positionValue = AXValueCreate(AXValueType.cgPoint, &position) {
            AXUIElementSetAttributeValue(windowElement, kAXPositionAttribute as CFString, positionValue)
        }

        var size = targetSize
        if let sizeValue = AXValueCreate(AXValueType.cgSize, &size) {
            AXUIElementSetAttributeValue(windowElement, kAXSizeAttribute as CFString, sizeValue)
        }
    }

    static func snap(zone: SnapZone) {
        guard let bundleID = ActiveAppMonitor.shared.activeAppBundleID,
              let appToSnap = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleID }) else {
            print("[SnappingManager] Error: Could not identify the application to snap from ActiveAppMonitor.")
            guard let frontmostApp = NSWorkspace.shared.runningApplications.first(where: { $0.isActive && $0.bundleIdentifier != Bundle.main.bundleIdentifier }) else {
                print("[SnappingManager] Fallback failed: Could not find any frontmost application.")
                return
            }
            print("[SnappingManager] Warning: Using fallback to identify frontmost app.")
            snap(app: frontmostApp, to: zone)
            return
        }

        print("[SnappingManager] Snapping app '\(bundleID)' identified by ActiveAppMonitor.")
        snap(app: appToSnap, to: zone)
    }

    private static func getMostLikelyMainWindow(for app: NSRunningApplication) -> AXUIElement? {
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var windowListRef: CFTypeRef?

        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowListRef) == .success,
              let windowList = windowListRef as? [AXUIElement],
              !windowList.isEmpty else {
            var mainWindowRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(appElement, kAXMainWindowAttribute as CFString, &mainWindowRef) == .success {
                return mainWindowRef as! AXUIElement?
            }
            return nil
        }

        var bestCandidate: AXUIElement? = nil

        for window in windowList {
            var isMinimizedRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &isMinimizedRef) == .success,
               (isMinimizedRef as? NSNumber)?.boolValue == true {
                continue
            }

            var subroleRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(window, kAXSubroleAttribute as CFString, &subroleRef) == .success,
               let subrole = subroleRef as? String,
               subrole == kAXStandardWindowSubrole as String {
                return window
            }

            if bestCandidate == nil {
                bestCandidate = window
            }
        }

        return bestCandidate
    }
}