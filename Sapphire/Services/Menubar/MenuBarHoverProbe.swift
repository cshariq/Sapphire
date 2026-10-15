//
//  MenuBarHoverProbe.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-02

import AppKit

@MainActor
final class MenuBarHoverProbe {
    private var windows: [HoverProbeWindow] = []
    private var enteredTrackers: Set<ObjectIdentifier> = []
    private var screenObserver: NSObjectProtocol?
    private var onHoverChange: ((Bool) -> Void)?

    var isHovering: Bool { !enteredTrackers.isEmpty || exitPoll != nil }

    private var exitPoll: Timer?
    private static let exitPollInterval: TimeInterval = 0.1

    func start(onHoverChange: @escaping (Bool) -> Void) {
        guard windows.isEmpty else {
            self.onHoverChange = onHoverChange
            return
        }
        self.onHoverChange = onHoverChange
        rebuildWindows()

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.rebuildWindows() }
        }
    }

    func stop() {
        stopExitPoll()
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
            self.screenObserver = nil
        }
        teardownWindows()
        onHoverChange = nil
    }

    // MARK: - Windows

    private var builtRects: [CGRect] = []

    private func rebuildWindows() {
        let rects = NSScreen.screens.compactMap { menuBarRect(for: $0) }
        guard rects != builtRects || windows.count != rects.count else { return }
        if windows.count == rects.count {
            for (window, rect) in zip(windows, rects) where window.frame != rect {
                window.setFrame(rect, display: false)
            }
            builtRects = rects
            return
        }
        let wasHovering = isHovering
        teardownWindows()
        builtRects = rects

        for rect in rects {

            let probe = HoverProbeWindow(
                level: .statusBar,
                collectionBehavior: [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
            )
            let tracker = HoverTrackingView(frame: .zero)
            tracker.autoresizingMask = [.width, .height]
            tracker.onPointerEvent = { [weak self, weak tracker] _, _ in
                guard let self, let tracker else { return }
                self.handleCrossing(for: tracker)
            }
            probe.contentView = tracker
            probe.setFrame(rect, display: false)
            probe.orderFront(nil)
            windows.append(probe)
        }

        if exitPoll != nil {
            for window in windows { window.orderOut(nil) }
        }
        if wasHovering && !isHovering { onHoverChange?(false) }
    }

    private func teardownWindows() {
        for window in windows {
            (window.contentView as? HoverTrackingView)?.onPointerEvent = nil
            window.orderOut(nil)
            window.contentView = nil
            window.close()
        }
        windows.removeAll()
        builtRects = []
        enteredTrackers.removeAll()
    }

    private var knownMenuBarHeights: [CGDirectDisplayID: CGFloat] = [:]

    private func menuBarRect(for screen: NSScreen) -> CGRect? {
        let height = NotchDisplayMetrics.menuBarGap(frame: screen.frame, visibleFrame: screen.visibleFrame)
        let displayID = screen.displayID
        if height > 0 { knownMenuBarHeights[displayID] = min(height, 44) }
        let menuBarHeight = knownMenuBarHeights[displayID] ?? 24
        guard menuBarHeight > 0 else { return nil }
        return CGRect(
            x: screen.frame.minX,
            y: screen.frame.maxY - menuBarHeight,
            width: screen.frame.width,
            height: menuBarHeight
        )
    }

    // MARK: - Crossings

    private func handleCrossing(for tracker: HoverTrackingView) {
        guard exitPoll == nil else { return }
        let wasHovering = isHovering
        let identifier = ObjectIdentifier(tracker)

        if let window = tracker.window, window.frame.contains(NSEvent.mouseLocation) {
            enteredTrackers.insert(identifier)
        } else {
            enteredTrackers.remove(identifier)
        }

        if !enteredTrackers.isEmpty { startExitPoll() }
        guard wasHovering != isHovering else { return }
        onHoverChange?(isHovering)
    }

    // MARK: - Exit polling

    private func startExitPoll() {
        guard exitPoll == nil else { return }
        enteredTrackers.removeAll()
        for window in windows { window.orderOut(nil) }
        let timer = Timer(timeInterval: Self.exitPollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pollForExit() }
        }
        timer.tolerance = Self.exitPollInterval * 0.5
        RunLoop.main.add(timer, forMode: .common)
        exitPoll = timer
    }

    private func pollForExit() {
        let location = NSEvent.mouseLocation
        guard !builtRects.contains(where: { $0.contains(location) }) else { return }
        stopExitPoll()
        enteredTrackers.removeAll()
        for window in windows { window.orderFront(nil) }
        onHoverChange?(false)
    }

    private func stopExitPoll() {
        exitPoll?.invalidate()
        exitPoll = nil
    }
}