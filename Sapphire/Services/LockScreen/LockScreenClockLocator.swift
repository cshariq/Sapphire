//
//  LockScreenClockLocator.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-11-16.
//

import AppKit
import ApplicationServices

/// Finds where the system lock screen draws its clock, so widgets can sit right under it.
///
/// loginwindow exposes the lock screen through Accessibility: a static text with identifier
/// `LargeDate` for the date, and a SwiftUI hosting group holding the time as a static text. The
/// time's frame is its text line box, so the digits end above the box's bottom by the font's
/// descent (measured at ~19% of the box height on macOS 27; digits have no descenders).
/// Needs Accessibility permission, which Sapphire already uses to type the unlock password.
enum LockScreenClockLocator {
    /// Share of the time element's height below the digits' baseline.
    private static let timeDescentFraction: CGFloat = 0.18
    private static let dateIdentifier = "LargeDate"

    /// Bottom edge of the visible clock digits in Cocoa screen coordinates, keyed by screen frame.
    /// Kept across locks so the next lock lays out correctly from the first frame.
    private(set) static var cachedClockBottom: [String: CGFloat] = [:]

    private static let queue = DispatchQueue(label: "lockscreen.clock-locator", qos: .userInitiated)

    static func clockBottom(on screen: NSScreen) -> CGFloat? {
        cachedClockBottom[key(screen.frame)]
    }

    /// `CGRect` is only `Hashable` from macOS 15, so screens are keyed by their frame's description.
    private static func key(_ frame: NSRect) -> String { NSStringFromRect(frame) }

    /// Reads the clock from loginwindow off the main thread. Calls back on main with true when the
    /// cached position for some screen changed.
    static func refresh(completion: @escaping (Bool) -> Void) {
        guard AXIsProcessTrusted(),
              let loginwindow = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.loginwindow").first
        else {
            completion(false)
            return
        }
        let pid = loginwindow.processIdentifier
        // Read the screen layout on main; AppKit screen objects aren't for background threads.
        let screens = NSScreen.screens.map(\.frame)
        let primaryMaxY = screens.first?.maxY ?? 0

        queue.async {
            let found = locate(pid: pid, screens: screens, primaryMaxY: primaryMaxY)
            DispatchQueue.main.async {
                var changed = false
                for (frame, bottom) in found where abs((cachedClockBottom[key(frame)] ?? -.infinity) - bottom) > 0.5 {
                    cachedClockBottom[key(frame)] = bottom
                    changed = true
                }
                completion(changed)
            }
        }
    }

    private static func locate(pid: pid_t, screens: [NSRect], primaryMaxY: CGFloat) -> [(NSRect, CGFloat)] {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.3)
        var result: [(NSRect, CGFloat)] = []

        for window in children(of: app, attribute: kAXWindowsAttribute) {
            let elements = flatten(window, depth: 3)
            guard let date = elements.first(where: { string(of: $0, kAXIdentifierAttribute) == dateIdentifier }),
                  let dateFrame = frame(of: date) else { continue }

            // The time is the tallest static text starting at or below the date's top, overlapping it horizontally.
            let time = elements
                .filter { string(of: $0, kAXRoleAttribute) == kAXStaticTextRole as String && $0 != date }
                .compactMap { element in frame(of: element).map { (element, $0) } }
                .filter { $0.1.minY >= dateFrame.minY - 4 && $0.1.minX < dateFrame.maxX && $0.1.maxX > dateFrame.minX }
                .max { $0.1.height < $1.1.height }

            // AX frames are top-left based from the primary screen's top edge.
            let digitsBottomAX: CGFloat
            if let (_, timeFrame) = time {
                digitsBottomAX = timeFrame.maxY - timeFrame.height * timeDescentFraction
            } else {
                digitsBottomAX = dateFrame.maxY
            }
            let cocoaY = primaryMaxY - digitsBottomAX
            let cocoaPoint = NSPoint(x: dateFrame.midX, y: cocoaY)
            if let screen = screens.first(where: { $0.contains(cocoaPoint) }) {
                result.append((screen, cocoaY))
            }
        }
        return result
    }

    // MARK: - AX helpers

    private static func value(of element: AXUIElement, _ attribute: String) -> AnyObject? {
        var value: AnyObject?
        return AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success ? value : nil
    }

    private static func string(of element: AXUIElement, _ attribute: String) -> String? {
        value(of: element, attribute) as? String
    }

    private static func children(of element: AXUIElement, attribute: String = kAXChildrenAttribute) -> [AXUIElement] {
        value(of: element, attribute) as? [AXUIElement] ?? []
    }

    private static func flatten(_ element: AXUIElement, depth: Int) -> [AXUIElement] {
        guard depth > 0 else { return [] }
        return children(of: element).flatMap { [$0] + flatten($0, depth: depth - 1) }
    }

    private static func frame(of element: AXUIElement) -> CGRect? {
        guard let positionValue = value(of: element, kAXPositionAttribute),
              let sizeValue = value(of: element, kAXSizeAttribute),
              CFGetTypeID(positionValue) == AXValueGetTypeID(),
              CFGetTypeID(sizeValue) == AXValueGetTypeID() else { return nil }
        var origin = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(positionValue as! AXValue, .cgPoint, &origin)
        AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        guard size.height > 1 else { return nil }
        return CGRect(origin: origin, size: size)
    }
}
