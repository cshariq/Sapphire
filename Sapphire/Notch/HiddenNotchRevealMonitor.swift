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

    private var catcherPanel: NSPanel?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var hasProcessedCurrentGesture = false
    private var lastGestureTime: TimeInterval = 0
    private let debounce: TimeInterval = 0.55

    private init() {}

    func start(screen: NSScreen?) {
        stop()
        let targetScreen = screen ?? NSScreen.main
        guard let targetScreen else { return }

        installCatcher(on: targetScreen)
        installMonitors()

        hasProcessedCurrentGesture = true
    }

    func stop() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        catcherPanel?.orderOut(nil)
        catcherPanel = nil
        hasProcessedCurrentGesture = false
        lastGestureTime = 0
    }

    private func installCatcher(on screen: NSScreen) {
        let menuBarHeight = max(24, screen.frame.height - screen.visibleFrame.height)
        let zoneWidth = min(screen.frame.width, max(640, screen.frame.width * 0.45))
        let zoneHeight = max(menuBarHeight + 28, 56)
        let frame = CGRect(
            x: screen.frame.midX - zoneWidth / 2,
            y: screen.frame.maxY - zoneHeight,
            width: zoneWidth,
            height: zoneHeight
        )

        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = NSWindow.Level(Int(CGWindowLevelForKey(.statusWindow)) + 2)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.contentView = PassThroughScrollCatcherView(frame: CGRect(origin: .zero, size: frame.size))
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
        catcherPanel = panel
    }

    private func installMonitors() {
        let handler: (NSEvent) -> Void = { [weak self] event in
            Task { @MainActor in
                self?.handleScroll(event)
            }
        }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.scrollWheel], handler: handler)
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel]) { event in
            handler(event)
            return event
        }
    }

    private func handleScroll(_ event: NSEvent) {
        let now = Date().timeIntervalSinceReferenceDate

        if event.phase == .began || event.momentumPhase == .began {
            hasProcessedCurrentGesture = false
        }

        guard event.scrollingDeltaY > 6,
              abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX) else { return }

        let mouse = NSEvent.mouseLocation
        guard isInRevealZone(mouse) else { return }

        guard !hasProcessedCurrentGesture, now - lastGestureTime > debounce else { return }
        hasProcessedCurrentGesture = true
        lastGestureTime = now

        NotificationCenter.default.post(name: .sapphireRevealHiddenNotch, object: nil)
    }

    private func isInRevealZone(_ mouse: CGPoint) -> Bool {
        if let panel = catcherPanel, panel.frame.insetBy(dx: -20, dy: -8).contains(mouse) {
            return true
        }
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

private final class PassThroughScrollCatcherView: NSView {
    override var acceptsFirstResponder: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}