//
//  AccessibilityPermissionService.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-21

import AppKit
import ApplicationServices
import os

@MainActor
protocol AccessibilityTrustProviding: AnyObject {
    var isTrusted: Bool { get }
    func refresh()
}

@Observable
@MainActor
final class AccessibilityPermissionService: AccessibilityTrustProviding {
    private(set) var isTrustedCached: Bool

    var onTrustChanged: ((Bool) -> Void)?

    private var trustObserver: NSObjectProtocol?
    private var debounceTask: Task<Void, Never>?

    private let logger = Logger(subsystem: "com.finetuneapp.FineTune", category: "AccessibilityPermissionService")

    var refreshDidFinish: (() -> Void)?

    init() {
        self.isTrustedCached = AXIsProcessTrusted()
    }

    var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    func refresh() {
        let current = AXIsProcessTrusted()
        guard current != isTrustedCached else {
            refreshDidFinish?()
            return
        }
        isTrustedCached = current
        logger.info("Accessibility trust refreshed synchronously: \(current ? "granted" : "revoked")")
        onTrustChanged?(current)
        refreshDidFinish?()
    }

    func start() {
        guard trustObserver == nil else { return }
        trustObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.accessibility.api"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.scheduleDebouncedRefresh()
            }
        }
    }

    func stop() {
        debounceTask?.cancel()
        debounceTask = nil
        if let observer = trustObserver {
            DistributedNotificationCenter.default().removeObserver(observer)
            trustObserver = nil
        }
    }

    private func scheduleDebouncedRefresh() {
        debounceTask?.cancel()
        debounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, let self else { return }
            self.refresh()
            self.debounceTask = nil
        }
    }

    @discardableResult
    func promptForTrust() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    func requestAccess() {
        let trusted = promptForTrust()
        if !trusted {
            openSystemSettings()
        }
    }
}