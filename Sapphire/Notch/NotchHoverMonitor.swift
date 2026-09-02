//
//  NotchHoverMonitor.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-02

import Cocoa

// MARK: - Tracking View

final class HoverTrackingView: NSView {
    var onPointerEvent: (() -> Void)?

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override var acceptsFirstResponder: Bool { false }
    override var mouseDownCanMoveWindow: Bool { false }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(
            NSTrackingArea(
                rect: .zero,
                options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
        )
    }

    override func mouseEntered(with event: NSEvent) { onPointerEvent?() }
    override func mouseExited(with event: NSEvent) { onPointerEvent?() }
}

// MARK: - Probe Window

final class HoverProbeWindow: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    convenience init(level: NSWindow.Level, collectionBehavior: NSWindow.CollectionBehavior) {
        self.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isReleasedWhenClosed = false
        self.level = level
        self.collectionBehavior = collectionBehavior
        ignoresMouseEvents = true
        isMovable = false
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        sharingType = .none
    }
}

// MARK: - Monitor

@MainActor
final class NotchHoverMonitor {
    private weak var notchWindow: NSWindow?
    private var probeWindow: HoverProbeWindow?
    private var tracker: HoverTrackingView?
    private var onPointerEvent: (() -> Void)?

    private var currentRect: CGRect = .null
    private var isParked = true
    private var pointerIsInside = false
    private var stuckHoverWatchdog: Timer?

    var isRunning: Bool { notchWindow != nil }

    // MARK: Lifecycle

    func start(window: NSWindow, onPointerEvent: @escaping () -> Void) {
        if notchWindow === window, probeWindow != nil {
            self.onPointerEvent = onPointerEvent
            return
        }
        stop()

        notchWindow = window
        self.onPointerEvent = onPointerEvent

        let probe = HoverProbeWindow(level: window.level, collectionBehavior: window.collectionBehavior)
        let tracker = HoverTrackingView(frame: .zero)
        tracker.autoresizingMask = [.width, .height]
        tracker.onPointerEvent = { [weak self] in self?.onPointerEvent?() }
        probe.contentView = tracker

        self.tracker = tracker
        self.probeWindow = probe

        (NSApp.delegate as? AppDelegate)?.attachAuxiliaryNotchWindow(probe)
    }

    func stop() {
        stuckHoverWatchdog?.invalidate()
        stuckHoverWatchdog = nil

        tracker?.onPointerEvent = nil
        tracker = nil

        if let probeWindow {
            (NSApp.delegate as? AppDelegate)?.detachAuxiliaryNotchWindow(probeWindow)
            probeWindow.orderOut(nil)
            probeWindow.contentView = nil
            probeWindow.close()
        }
        probeWindow = nil

        notchWindow = nil
        onPointerEvent = nil
        currentRect = .null
        isParked = true
        pointerIsInside = false
    }

    // MARK: Geometry

    func update(hoverRect rect: CGRect, pointerIsInside: Bool) {
        guard let window = notchWindow, let probeWindow else { return }

        self.pointerIsInside = pointerIsInside
        syncStuckHoverWatchdog()

        guard !rect.isNull, !rect.isEmpty else {
            park()
            return
        }

        let changed = movedMeaningfully(from: currentRect, to: rect)
        if changed {
            currentRect = rect
            probeWindow.setFrame(window.convertToScreen(rect), display: false)
        }

        if isParked {
            isParked = false
            probeWindow.order(.above, relativeTo: window.windowNumber)
        }
    }

    private func park() {
        guard !isParked else { return }
        isParked = true
        currentRect = .null
        probeWindow?.orderOut(nil)
    }

    private func movedMeaningfully(from old: CGRect, to new: CGRect) -> Bool {
        if old.isNull { return true }
        return abs(new.minX - old.minX) > 1
            || abs(new.minY - old.minY) > 1
            || abs(new.width - old.width) > 1
            || abs(new.height - old.height) > 1
    }

    private func syncStuckHoverWatchdog() {
        if pointerIsInside {
            guard stuckHoverWatchdog == nil else { return }
            let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.onPointerEvent?() }
            }
            timer.tolerance = 0.5
            RunLoop.main.add(timer, forMode: .common)
            stuckHoverWatchdog = timer
        } else {
            stuckHoverWatchdog?.invalidate()
            stuckHoverWatchdog = nil
        }
    }
}