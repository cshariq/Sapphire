//
//  CursorPosition.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-10

import AppKit
import SwiftUI

enum CursorPosition {
    static var visibleNotchWindow: NSWindow? {
        NSApplication.shared.windows.first { window in
            window is DynamicFocusWindow && window.isVisible
        }
    }

    static var visibleNotchWindows: [NSWindow] {
        NSApplication.shared.windows.filter { window in
            window is DynamicFocusWindow && window.isVisible
        }
    }

    static func swiftUIGlobalPoint(in window: NSWindow?) -> CGPoint? {
        guard let window, let contentView = window.contentView else { return nil }
        let mouseInWindow = window.mouseLocationOutsideOfEventStream
        return CGPoint(
            x: mouseInWindow.x,
            y: contentView.bounds.height - mouseInWindow.y
        )
    }

    static func swiftUIGlobalPointForNotch() -> CGPoint? {
        swiftUIGlobalPoint(in: visibleNotchWindow)
    }

    static func targetNotchScreen() -> NSScreen? {
        let settings = SettingsModel.shared.settings
        switch settings.notchDisplayTarget {
        case .macbookDisplay:
            return NSScreen.screens.first { screen in
                if let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID {
                    return CGDisplayIsBuiltin(displayID) != 0
                }
                return false
            }
        case .mainDisplay, .allDisplays:
            return NSScreen.main
        }
    }

    static func screen(containing point: NSPoint) -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(point) }
    }

    static func notchActivationRect(extraWidth: CGFloat = 40, extraHeight: CGFloat = 12) -> CGRect? {
        if let window = visibleNotchWindow {
            let frame = window.frame
            let width = min(frame.width + extraWidth, frame.width + 120)
            let height = min(56, frame.height * 0.35) + extraHeight
            return CGRect(
                x: frame.midX - width / 2,
                y: frame.maxY - height,
                width: width,
                height: height
            )
        }

        guard let screen = targetNotchScreen() else { return nil }
        let screenFrame = screen.frame
        let width: CGFloat = 320
        let height: CGFloat = 48
        return CGRect(
            x: screenFrame.midX - width / 2,
            y: screenFrame.maxY - height,
            width: width,
            height: height
        )
    }

    static func screenForSnapping() -> NSScreen {
        if let screen = screenForFrontmostAppWindow() {
            return screen
        }
        if let notch = visibleNotchWindow, let screen = screen(for: notch) {
            return screen
        }
        return targetNotchScreen() ?? NSScreen.main ?? NSScreen.screens[0]
    }

    static func screen(for window: NSWindow) -> NSScreen? {
        screen(containing: NSPoint(x: window.frame.midX, y: window.frame.midY))
    }

    private static func screenForFrontmostAppWindow() -> NSScreen? {
        guard let frontApp = NSWorkspace.shared.frontmostApplication,
              frontApp.bundleIdentifier != Bundle.main.bundleIdentifier else {
            return nil
        }

        let appElement = AXUIElementCreateApplication(frontApp.processIdentifier)
        var windowRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &windowRef) == .success,
              let windowElement = windowRef else {
            return nil
        }

        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(windowElement as! AXUIElement, kAXPositionAttribute as CFString, &positionRef) == .success,
              AXUIElementCopyAttributeValue(windowElement as! AXUIElement, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let positionValue = positionRef,
              let sizeValue = sizeRef else {
            return nil
        }

        var origin = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &origin),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else {
            return nil
        }

        let center = NSPoint(x: origin.x + size.width / 2, y: origin.y + size.height / 2)
        return screen(containing: center)
    }
}

extension NSWindow {
    var swiftUIGlobalMouseLocation: CGPoint? {
        CursorPosition.swiftUIGlobalPoint(in: self)
    }

    static var visibleNotchWindow: NSWindow? {
        CursorPosition.visibleNotchWindow
    }
}