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
    private var pollTimer: Timer?
    private var accessibilityObserver: NSObjectProtocol?
    private var isStarted = false
    private(set) var isTrusted: Bool = AXIsProcessTrusted()

    private init() {}

    func start() {
        guard !isStarted else { return }
        isStarted = true

        accessibilityObserver = DistributedNotificationCenter.default().addObserver(
            forName: Self.accessibilityAPIDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshTrust() }
        }

        refreshTrust()

        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshTrust() }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(refreshTrustOnActivation),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
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

    @objc private func refreshTrustOnActivation() {
        refreshTrust()
    }

    private func refreshTrust() {
        let trusted = AXIsProcessTrusted()
        guard trusted != isTrusted else { return }
        isTrusted = trusted

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