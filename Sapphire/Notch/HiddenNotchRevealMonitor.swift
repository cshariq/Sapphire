//
//  HiddenNotchRevealMonitor.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-21

import AppKit

extension Notification.Name {
    static let sapphireRevealHiddenNotch = Notification.Name("sapphireRevealHiddenNotch")
}

@MainActor
final class HiddenNotchRevealMonitor {
    static let shared = HiddenNotchRevealMonitor()

    private var scrollMonitorToken: UUID?
    private var hasProcessedCurrentGesture = false
    private var lastGestureTime: TimeInterval = 0
    private let debounce: TimeInterval = 0.55

    private init() {}

    func start(screen: NSScreen?) {
        stop()
        guard (screen ?? NSScreen.main) != nil else { return }
        installScrollMonitor()
        hasProcessedCurrentGesture = true
    }

    func stop() {
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
        guard isInRevealZone(NSEvent.mouseLocation) else {
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

        NotificationCenter.default.post(name: .sapphireRevealHiddenNotch, object: nil)
    }

    private func isInRevealZone(_ mouse: CGPoint) -> Bool {
        guard let screen = CursorPosition.screen(containing: mouse) ?? NSScreen.main else {
            return false
        }
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
}