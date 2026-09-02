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

    var isHovering: Bool { !enteredTrackers.isEmpty }

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
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
            self.screenObserver = nil
        }
        teardownWindows()
        onHoverChange = nil
    }

    // MARK: - Windows

    private func rebuildWindows() {
        let wasHovering = isHovering
        teardownWindows()

        for screen in NSScreen.screens {
            guard let rect = menuBarRect(for: screen) else { continue }

            let probe = HoverProbeWindow(
                level: .statusBar,
                collectionBehavior: [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
            )
            let tracker = HoverTrackingView(frame: .zero)
            tracker.autoresizingMask = [.width, .height]
            tracker.onPointerEvent = { [weak self, weak tracker] in
                guard let self, let tracker else { return }
                self.handleCrossing(for: tracker)
            }
            probe.contentView = tracker
            probe.setFrame(rect, display: false)
            probe.orderFront(nil)
            windows.append(probe)
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
        enteredTrackers.removeAll()
    }

    private func menuBarRect(for screen: NSScreen) -> CGRect? {
        let height = screen.frame.height - screen.visibleFrame.height
        let menuBarHeight = height > 0 ? min(height, 44) : 24
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
        let wasHovering = isHovering
        let identifier = ObjectIdentifier(tracker)

        if let window = tracker.window, window.frame.contains(NSEvent.mouseLocation) {
            enteredTrackers.insert(identifier)
        } else {
            enteredTrackers.remove(identifier)
        }

        guard wasHovering != isHovering else { return }
        onHoverChange?(isHovering)
    }
}