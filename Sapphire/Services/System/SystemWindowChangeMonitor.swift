//
//  SystemWindowChangeMonitor.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-16

import AppKit
import ApplicationServices

@MainActor
final class SystemWindowChangeMonitor {
    struct Token: Hashable {
        fileprivate let id = UUID()
    }

    static let shared = SystemWindowChangeMonitor()

    private var handlers: [Token: () -> Void] = [:]
    private var accessibilityObservers: [pid_t: AXObserverHandle] = [:]
    private var workspaceObservers: [NSObjectProtocol] = []
    private var applicationObservers: [NSObjectProtocol] = []
    private var fallbackTimer: Timer?
    private var pendingDelivery: DispatchWorkItem?

    private init() {}

    func subscribe(_ handler: @escaping () -> Void) -> Token {
        let token = Token()
        handlers[token] = handler
        if handlers.count == 1 {
            start()
        }
        return token
    }

    func unsubscribe(_ token: Token) {
        handlers.removeValue(forKey: token)
        if handlers.isEmpty {
            stop()
        }
    }

    private func start() {
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        let workspaceNames: [Notification.Name] = [
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.didHideApplicationNotification,
            NSWorkspace.didUnhideApplicationNotification,
            NSWorkspace.activeSpaceDidChangeNotification,
        ]

        workspaceObservers = workspaceNames.map { name in
            workspaceCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                MainActor.assumeIsolated {
                    self?.handleWorkspaceChange(notification)
                }
            }
        }

        let center = NotificationCenter.default
        applicationObservers = [
            center.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.scheduleDelivery() }
            },
            center.addObserver(
                forName: AccessibilityTrustMonitor.trustDidChange,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.rebuildAccessibilityObservers() }
            },
        ]

        rebuildAccessibilityObservers()
    }

    private func stop() {
        pendingDelivery?.cancel()
        pendingDelivery = nil
        fallbackTimer?.invalidate()
        fallbackTimer = nil

        accessibilityObservers.values.forEach { $0.detach() }
        accessibilityObservers.removeAll()

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        workspaceObservers.forEach(workspaceCenter.removeObserver)
        workspaceObservers.removeAll()

        let center = NotificationCenter.default
        applicationObservers.forEach(center.removeObserver)
        applicationObservers.removeAll()
    }

    private func handleWorkspaceChange(_ notification: Notification) {
        if let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
            if notification.name == NSWorkspace.didTerminateApplicationNotification {
                accessibilityObservers.removeValue(forKey: application.processIdentifier)?.detach()
            } else if notification.name == NSWorkspace.didLaunchApplicationNotification {
                observe(application)
            }
        }
        synchronizeFallbackTimer()
        scheduleDelivery()
    }

    private func rebuildAccessibilityObservers() {
        accessibilityObservers.values.forEach { $0.detach() }
        accessibilityObservers.removeAll()

        if AccessibilityPermission.isProcessTrusted {
            for application in NSWorkspace.shared.runningApplications where !application.isTerminated {
                observe(application)
            }
        }

        synchronizeFallbackTimer()
        scheduleDelivery()
    }

    private func observe(_ application: NSRunningApplication) {
        let pid = application.processIdentifier
        guard pid > 0,
              pid != ProcessInfo.processInfo.processIdentifier,
              accessibilityObservers[pid] == nil,
              AccessibilityPermission.isProcessTrusted else { return }

        let applicationElement = AX.application(pid: pid)
        guard let observer = AXObserverHandle(pid: pid, handler: { [weak self] element, notification in
            MainActor.assumeIsolated {
                self?.handleAccessibilityChange(pid: pid, element: element, notification: notification)
            }
        }) else { return }

        var observationCount = observer.observe(
            [
                kAXWindowCreatedNotification as String,
                kAXFocusedWindowChangedNotification as String,
            ],
            on: applicationElement
        )

        for window in AX.elements(kAXWindowsAttribute as String, of: applicationElement, limit: 128) {
            observationCount += observeWindow(window, with: observer)
        }

        guard observationCount > 0 else { return }
        observer.attach()
        accessibilityObservers[pid] = observer
    }

    private func observeWindow(_ window: AXUIElement, with observer: AXObserverHandle) -> Int {
        observer.observe(
            [
                kAXMovedNotification as String,
                kAXResizedNotification as String,
                kAXWindowMovedNotification as String,
                kAXWindowResizedNotification as String,
                kAXWindowMiniaturizedNotification as String,
                kAXWindowDeminiaturizedNotification as String,
                kAXUIElementDestroyedNotification as String,
            ],
            on: window
        )
    }

    private func handleAccessibilityChange(pid: pid_t, element _: AXUIElement, notification: String) {
        if notification == (kAXWindowCreatedNotification as String)
            || notification == (kAXFocusedWindowChangedNotification as String),
           let observer = accessibilityObservers[pid] {
            let applicationElement = AX.application(pid: pid)
            for window in AX.elements(kAXWindowsAttribute as String, of: applicationElement, limit: 128) {
                _ = observeWindow(window, with: observer)
            }
        }
        scheduleDelivery()
    }

    private func synchronizeFallbackTimer() {
        let needsFallback = requiresFallbackPolling
        guard needsFallback else {
            fallbackTimer?.invalidate()
            fallbackTimer = nil
            return
        }
        guard fallbackTimer == nil else { return }

        fallbackTimer = Timer.scheduledCoalescing(
            withTimeInterval: 5,
            repeats: true,
            toleranceFraction: 0.3
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleDelivery() }
        }
    }

    private var requiresFallbackPolling: Bool {
        guard AccessibilityPermission.isProcessTrusted else { return true }

        let ownPID = ProcessInfo.processInfo.processIdentifier
        return NSWorkspace.shared.runningApplications.contains { application in
            let pid = application.processIdentifier
            return application.activationPolicy == .regular
                && !application.isTerminated
                && pid > 0
                && pid != ownPID
                && accessibilityObservers[pid] == nil
        }
    }

    private func scheduleDelivery() {
        guard pendingDelivery == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.pendingDelivery = nil
                let handlers = Array(self.handlers.values)
                handlers.forEach { $0() }
            }
        }
        pendingDelivery = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: work)
    }
}