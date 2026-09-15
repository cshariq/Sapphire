//
//  SnappingManager.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-08-11.
//

import AppKit
import ApplicationServices
import QuartzCore

enum SnapZoneHitTesting {
    static let tolerance: CGFloat = 18

    static func distance(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return hypot(dx, dy)
    }

    static func nearest<Region>(
        _ regions: [Region],
        to point: CGPoint,
        frame: (Region) -> CGRect
    ) -> Region? {
        var best: (region: Region, distance: CGFloat)?
        for region in regions {
            let distance = distance(from: point, to: frame(region))
            if distance == 0 { return region }
            if distance <= tolerance, distance < (best?.distance ?? .infinity) {
                best = (region, distance)
            }
        }
        return best?.region
    }
}

@MainActor
final class SnappingManager {
    private struct Display: Sendable {
        let frame: CGRect
        let visibleFrame: CGRect
    }

    private nonisolated static let queue = DispatchQueue(label: "com.sapphire.snapping", qos: .userInteractive)

    private nonisolated static let generationLock = NSLock()
    private nonisolated(unsafe) static var generations: [pid_t: UInt64] = [:]

    private nonisolated static let smoothDuration: CFTimeInterval = 0.25
    private nonisolated static let smoothFrameInterval: CFTimeInterval = 1.0 / 60.0

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
        guard app.bundleIdentifier != Bundle.main.bundleIdentifier else { return }

        let normalizedX = max(0, min(1, zone.x))
        let normalizedY = max(0, min(1, zone.y))
        let normalizedWidth = max(0, min(1 - normalizedX, zone.width))
        let normalizedHeight = max(0, min(1 - normalizedY, zone.height))
        guard normalizedWidth > 0, normalizedHeight > 0 else {
            print("[SnappingManager] Ignoring an empty snap zone.")
            return
        }

        let displays = NSScreen.screens.map { Display(frame: $0.frame, visibleFrame: $0.visibleFrame) }
        let fallbackDisplay = NSScreen.main.map { Display(frame: $0.frame, visibleFrame: $0.visibleFrame) }
        let mainDisplayFrame = self.mainDisplayFrame
        let animation = SettingsModel.shared.settings.snapWindowAnimation
        let pid = app.processIdentifier
        let appName = app.bundleIdentifier ?? "unknown app"
        let generation = nextGeneration(for: pid)

        queue.async {
            guard isCurrent(generation, for: pid) else { return }
            guard let windowElement = mostLikelyMainWindow(pid: pid),
                  let axFrame = AX.windowFrame(of: windowElement),
                  axFrame.width > 0, axFrame.height > 0 else {
                print("[SnappingManager] Could not find a usable window for \(appName)")
                return
            }

            let cocoaFrame = CGRect(
                x: axFrame.minX,
                y: (mainDisplayFrame?.maxY ?? 0) - axFrame.minY - axFrame.height,
                width: axFrame.width,
                height: axFrame.height
            )
            guard let display = display(for: cocoaFrame, in: displays) ?? fallbackDisplay else {
                print("[SnappingManager] Could not find a display for \(appName)")
                return
            }

            let visibleFrame = display.visibleFrame
            let targetFrame = CGRect(
                x: visibleFrame.origin.x + visibleFrame.width * normalizedX,
                y: visibleFrame.origin.y + visibleFrame.height * (1 - normalizedY - normalizedHeight),
                width: visibleFrame.width * normalizedWidth,
                height: visibleFrame.height * normalizedHeight
            )
            let mainDisplayMaxY = mainDisplayFrame?.maxY ?? display.frame.maxY
            let targetAXFrame = CGRect(
                x: targetFrame.minX,
                y: mainDisplayMaxY - targetFrame.maxY,
                width: targetFrame.width,
                height: targetFrame.height
            )

            if animation == .smooth {
                animate(windowElement, from: axFrame, to: targetAXFrame, pid: pid, generation: generation)
                guard isCurrent(generation, for: pid) else { return }
            }

            if !applyFrame(targetAXFrame, to: windowElement) {
                print("[SnappingManager] Failed to move/resize \(appName)")
            }
        }
    }

    // MARK: - Moving the window (snapping queue)

    @discardableResult
    private nonisolated static func applyFrame(_ frame: CGRect, to window: AXUIElement) -> Bool {
        let sized = AX.set(kAXSizeAttribute as String, toSize: frame.size, on: window)
        let positioned = AX.set(kAXPositionAttribute as String, toPoint: frame.origin, on: window)
        if positioned {
            AX.set(kAXSizeAttribute as String, toSize: frame.size, on: window)
        }
        return sized && positioned
    }

    private nonisolated static func animate(
        _ window: AXUIElement,
        from start: CGRect,
        to end: CGRect,
        pid: pid_t,
        generation: UInt64
    ) {
        let startTime = CACurrentMediaTime()
        while isCurrent(generation, for: pid) {
            let elapsed = CACurrentMediaTime() - startTime
            let progress = elapsed / smoothDuration
            guard progress < 1 else { return }

            let eased = 1 - pow(1 - progress, 3)
            let frame = CGRect(
                x: (start.minX + (end.minX - start.minX) * eased).rounded(),
                y: (start.minY + (end.minY - start.minY) * eased).rounded(),
                width: (start.width + (end.width - start.width) * eased).rounded(),
                height: (start.height + (end.height - start.height) * eased).rounded()
            )
            let sized = AX.set(kAXSizeAttribute as String, toSize: frame.size, on: window)
            let positioned = AX.set(kAXPositionAttribute as String, toPoint: frame.origin, on: window)
            guard sized || positioned else { return }

            let nextFrameTime = startTime + (floor(elapsed / smoothFrameInterval) + 1) * smoothFrameInterval
            let wait = nextFrameTime - CACurrentMediaTime()
            if wait > 0 { Thread.sleep(forTimeInterval: wait) }
        }
    }

    private nonisolated static func nextGeneration(for pid: pid_t) -> UInt64 {
        generationLock.lock()
        defer { generationLock.unlock() }
        let generation = (generations[pid] ?? 0) &+ 1
        generations[pid] = generation
        return generation
    }

    private nonisolated static func isCurrent(_ generation: UInt64, for pid: pid_t) -> Bool {
        generationLock.lock()
        defer { generationLock.unlock() }
        return generations[pid] == generation
    }

    // MARK: - Lookup

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

    private nonisolated static func mostLikelyMainWindow(pid: pid_t) -> AXUIElement? {
        let appElement = AX.application(pid: pid)

        if let focused = AX.focusedWindow(ofApplication: appElement), !isMinimized(focused) {
            return focused
        }

        if let main = AX.mainWindow(ofApplication: appElement), !isMinimized(main) {
            return main
        }

        var fallbackWindow: AXUIElement?
        for window in AX.elements(kAXWindowsAttribute as String, of: appElement) where !isMinimized(window) {
            if fallbackWindow == nil {
                fallbackWindow = window
            }

            if AX.subrole(of: window) == kAXStandardWindowSubrole as String {
                return window
            }
        }

        return fallbackWindow
    }

    private nonisolated static func isMinimized(_ window: AXUIElement) -> Bool {
        AX.bool(kAXMinimizedAttribute as String, of: window) == true
    }

    private nonisolated static func display(for cocoaFrame: CGRect, in displays: [Display]) -> Display? {
        let center = CGPoint(x: cocoaFrame.midX, y: cocoaFrame.midY)
        return displays.first(where: { $0.frame.contains(center) })
            ?? displays.first(where: { $0.frame.intersects(cocoaFrame) })
    }

    private static var mainDisplayFrame: CGRect? {
        let mainDisplayID = CGMainDisplayID()
        return NSScreen.screens.first { screen in
            let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
            return displayID == mainDisplayID
        }?.frame
    }
}