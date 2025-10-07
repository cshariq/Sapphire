//
//  LaunchpadManager.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-09-16.
//
//

import Cocoa
import SwiftUI

// MARK: - Gesture Monitor

class LaunchpadGestureMonitor {
    static let shared = LaunchpadGestureMonitor()

    private var monitor: Any?
    private var isMonitoring = false
    private var hasProcessedGesture = false

    var onShowLaunchpad: (() -> Void)?
    var onHideLaunchpad: (() -> Void)?

    private init() {}

    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true

        monitor = NSEvent.addGlobalMonitorForEvents(matching: .magnify) { [weak self] event in
            self?.handleMagnifyEvent(event)
        }
    }

    func stopMonitoring() {
        if let monitor = monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        isMonitoring = false
    }

    private func handleMagnifyEvent(_ event: NSEvent) {
        if event.phase == .began {
            hasProcessedGesture = false
        }

        if !hasProcessedGesture && (event.phase == .changed) {
            let magnification = event.magnification
            if magnification > 0.08 {
                onShowLaunchpad?()
                hasProcessedGesture = true
            }
            else if magnification < -0.08 {
                onHideLaunchpad?()
                hasProcessedGesture = true
            }
        }

        if event.phase == .ended || event.phase == .cancelled {
            hasProcessedGesture = false
        }
    }
}

// MARK: - Window Controller

class LaunchpadWindowController: NSWindowController {

    private var isVisible: Bool = false {
        didSet {
            guard oldValue != isVisible else { return }

            let notificationName = "com.apple.expose.front.awake" as CFString

            LaunchInterceptor.shared.interceptNextMissionControlLaunch = true

            CoreDockSendNotification(notificationName, 0)

            if isVisible {
                window?.setFrame(NSScreen.main?.frame ?? .zero, display: true)
                showWindow(self)
                window?.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            } else {
                window?.orderOut(nil)
            }
        }
    }

    convenience init() {
        LaunchInterceptor.shared.startObserving()

        let screenFrame = NSScreen.main?.frame ?? .zero
        let window = NSWindow(
            contentRect: screenFrame,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.isOpaque = false
        window.backgroundColor = .clear

        self.init(window: window)

        let launchpadView = LaunchpadView(isVisible: Binding(get: { self.isVisible }, set: { self.isVisible = $0 }))
        window.contentView = NSHostingView(rootView: launchpadView)
    }

    deinit {
        LaunchInterceptor.shared.stopObserving()

        if isVisible {
            let notificationName = "com.apple.expose.awake" as CFString
            CoreDockSendNotification(notificationName, 0)
        }
    }

    func showLaunchpad() {
        guard !isVisible else { return }
        isVisible = true
    }

    func hideLaunchpad() {
        guard isVisible else { return }
        isVisible = false
    }
}