//
//  HiddenNotchRevealMonitor.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-21

import AppKit
import os.log

private let hiddenNotchRevealLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Sapphire", category: "HiddenNotchReveal")

extension Notification.Name {
    static let sapphireRevealHiddenNotch = Notification.Name("sapphireRevealHiddenNotch")
}

@MainActor
final class HiddenNotchRevealMonitor {
    static let shared = HiddenNotchRevealMonitor()

    private var hiddenDisplayIDs = Set<CGDirectDisplayID>()
    private var scrollMonitorToken: UUID?
    private var hasProcessedCurrentGesture = false
    private var lastGestureTime: TimeInterval = 0
    private let debounce: TimeInterval = 0.55

    private init() {}

    func start(displayID: CGDirectDisplayID) {
        guard hiddenDisplayIDs.insert(displayID).inserted else { return }
        hiddenNotchRevealLog.info("Listening for reveal swipe on displayID=\(displayID, privacy: .public) hidden=[\(Self.describe(self.hiddenDisplayIDs), privacy: .public)]")
        guard scrollMonitorToken == nil else { return }
        installScrollMonitor()
        hasProcessedCurrentGesture = true
    }

    func stop(displayID: CGDirectDisplayID) {
        guard hiddenDisplayIDs.remove(displayID) != nil else { return }
        hiddenNotchRevealLog.info("Stopped listening on displayID=\(displayID, privacy: .public) hidden=[\(Self.describe(self.hiddenDisplayIDs), privacy: .public)]")
        guard hiddenDisplayIDs.isEmpty else { return }
        if let scrollMonitorToken {
            EventMonitorHub.shared.unregister(token: scrollMonitorToken, for: .scrollWheel)
            self.scrollMonitorToken = nil
        }
        hasProcessedCurrentGesture = false
        lastGestureTime = 0
    }

    private func installScrollMonitor() {
        guard scrollMonitorToken == nil else { return }
        scrollMonitorToken = EventMonitorHub.shared.register(for: .scrollWheel) { [weak self] event in
            self?.handleScroll(event)
        }
    }

    private func handleScroll(_ event: NSEvent) {
        let now = Date().timeIntervalSinceReferenceDate
        let mouse = NSEvent.mouseLocation
        guard let screen = CursorPosition.screen(containing: mouse),
              hiddenDisplayIDs.contains(screen.displayID),
              isInRevealZone(mouse, on: screen) else {
            hasProcessedCurrentGesture = false
            return
        }

        if event.phase == .began || event.momentumPhase == .began {
            hasProcessedCurrentGesture = false
        } else if event.phase.isEmpty, event.momentumPhase.isEmpty,
                  now - lastGestureTime > debounce {
            hasProcessedCurrentGesture = false
        }

        guard event.scrollingDeltaY > 6,
              abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX) else { return }

        guard !hasProcessedCurrentGesture, now - lastGestureTime > debounce else { return }
        hasProcessedCurrentGesture = true
        lastGestureTime = now

        let displayID = screen.displayID
        hiddenNotchRevealLog.info("Reveal swipe on displayID=\(displayID, privacy: .public)")
        NotificationCenter.default.post(name: .sapphireRevealHiddenNotch, object: NSNumber(value: displayID))
    }

    private func isInRevealZone(_ mouse: CGPoint, on screen: NSScreen) -> Bool {
        let menuBarHeight = max(24, screen.frame.height - screen.visibleFrame.height)
        let zoneWidth = min(screen.frame.width, max(640, screen.frame.width * 0.45))
        let zoneHeight = max(menuBarHeight + 28, 56)
        let zone = CGRect(
            x: screen.frame.midX - zoneWidth / 2,
            y: screen.frame.maxY - zoneHeight,
            width: zoneWidth,
            height: zoneHeight
        )
        return zone.insetBy(dx: -20, dy: -8).contains(mouse)
    }

    private static func describe(_ displayIDs: Set<CGDirectDisplayID>) -> String {
        displayIDs.sorted().map(String.init).joined(separator: ",")
    }
}