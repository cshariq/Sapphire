//
//  AccessibilityTrustMonitor.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-17.
//

import AppKit
import ApplicationServices

// MARK: - Runtime Accessibility Revocation Watchdog

@MainActor
final class AccessibilityTrustMonitor {
    static let shared = AccessibilityTrustMonitor()

    static let trustDidChange = Notification.Name("AccessibilityTrustMonitor.trustDidChange")

    private static let accessibilityAPIDidChange = NSNotification.Name("com.apple.accessibility.api")

    struct Registration {
        let name: String
        let teardown: () -> Void
        let reinstall: () -> Void
    }

    private let registryLock = NSLock()
    nonisolated(unsafe) private var registrations: [String: Registration] = [:]
    private var accessibilityObserver: NSObjectProtocol?
    private var activationObserver: NSObjectProtocol?
    private var isStarted = false
    nonisolated(unsafe) private static var _isTrustedAtomic: Bool = false
    var isTrusted: Bool { Self._isTrustedAtomic }
    private var debounceTask: Task<Void, Never>?

    private init() {
        let initial = AXIsProcessTrusted()
        Self._isTrustedAtomic = initial
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true

        accessibilityObserver = DistributedNotificationCenter.default().addObserver(
            forName: Self.accessibilityAPIDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleDebouncedRefresh() }
        }

        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleDebouncedRefresh() }
        }

        refreshTrust()
    }

    nonisolated func register(name: String, teardown: @escaping () -> Void, reinstall: @escaping () -> Void) {
        registryLock.lock()
        registrations[name] = Registration(name: name, teardown: teardown, reinstall: reinstall)
        registryLock.unlock()
    }

    nonisolated func unregister(name: String) {
        registryLock.lock()
        registrations.removeValue(forKey: name)
        registryLock.unlock()
    }

    nonisolated static func isCurrentlyTrusted() -> Bool {
        _isTrustedAtomic
    }

    private func scheduleDebouncedRefresh() {
        let current = AXIsProcessTrusted()
        if current != Self._isTrustedAtomic {
            if !current {
                debounceTask?.cancel()
                refreshTrust()
                return
            }
        }
        debounceTask?.cancel()
        debounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            self?.refreshTrust()
            self?.debounceTask = nil
        }
    }

    private func refreshTrust() {
        let trusted = AXIsProcessTrusted()
        guard trusted != Self._isTrustedAtomic else { return }
        Self._isTrustedAtomic = trusted

        registryLock.lock()
        let snapshot = Array(registrations.values)
        registryLock.unlock()

        if trusted {
            print("[AccessibilityTrustMonitor] Accessibility permission granted — reinstalling event taps.")
            for registration in snapshot {
                registration.reinstall()
            }
        } else {
            print("[AccessibilityTrustMonitor] Accessibility permission revoked — disabling all event taps so input is not swallowed.")
            for registration in snapshot {
                registration.teardown()
            }
        }

        NotificationCenter.default.post(
            name: Self.trustDidChange,
            object: nil,
            userInfo: ["trusted": trusted]
        )
    }
}