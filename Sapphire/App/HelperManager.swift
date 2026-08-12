//
//  HelperManager.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-11-08.
//

import Foundation
import ServiceManagement
import AppKit
import OSLog

class AlertHelper {
    static func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

private let helperLogger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Sapphire", category: "HelperManager")

@MainActor
class HelperManager: ObservableObject {
    static let shared = HelperManager()

    let helperToolIdentifier = "com.shariq.sapphireHelper"

    @Published var status: SMAppService.Status = .notRegistered
    @Published var isRunning: Bool = false

    private var healthCheckTimer: Timer?
    private var isReactivating = false
    private var reactivationFailureCount = 0
    private var alertShowing = false
    private var lastAlertTime: Date?
    private let maxReactivationFailuresBeforeAlert = 3
    private let alertCooldownInterval: TimeInterval = 3600 // 1 hour

    private init() {
        helperLogger.info("[HelperManager] Initialized")
        updateStatus()
        startHealthCheckTimer()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updateStatus),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    deinit {
        healthCheckTimer?.invalidate()
    }

    @objc func updateStatus() {
        let service = SMAppService.daemon(plistName: "\(helperToolIdentifier).plist")
        let newStatus = service.status
        if self.status != newStatus {
            helperLogger.info("[HelperManager] Status changed: \(String(describing: self.status)) -> \(String(describing: newStatus))")
            self.status = newStatus
        }
        checkIfRunning()
    }

    func checkIfRunning() {
        guard !isReactivating else {
            helperLogger.debug("[HelperManager] Skipping check - reactivation in progress")
            return
        }
        Task.detached(priority: .utility) {
            helperLogger.debug("[HelperManager] Pinging helper...")
            let running = await XPCClient.shared.ping()
            await MainActor.run {
                helperLogger.info("[HelperManager] Ping result: \(running ? "running" : "NOT running"), current status: \(String(describing: self.status))")
                if self.isRunning != running {
                    self.isRunning = running
                }
                // If helper is installed but not running, try to reactivate it
                if self.status == .enabled && !running && !self.isReactivating {
                    helperLogger.warning("[HelperManager] Helper installed but not running - triggering reactivation")
                    self.reactivateHelper()
                }
            }
        }
    }

    func reactivateHelper() {
        isReactivating = true
        helperLogger.info("[HelperManager] Starting reactivation...")
        Task.detached(priority: .utility) {
            do {
                let service = SMAppService.daemon(plistName: "\(self.helperToolIdentifier).plist")
                helperLogger.info("[HelperManager] Calling register() on service...")
                try service.register()
                helperLogger.info("[HelperManager] register() succeeded, waiting for helper to start...")
                await MainActor.run { self.checkIfRunning() }
            } catch {
                helperLogger.error("[HelperManager] Helper reactivation failed: \(error.localizedDescription)")
                await MainActor.run { self.handleReactivationFailure() }
            }
            await MainActor.run { self.isReactivating = false }
        }
    }

    private func handleReactivationFailure() {
        reactivationFailureCount += 1
        helperLogger.warning("[HelperManager] Reactivation failure count: \(self.reactivationFailureCount)")

        if reactivationFailureCount >= maxReactivationFailuresBeforeAlert {
            showHelperAlertIfNeeded()
            // Switch to slower check interval (every minute) after showing alert
            startHealthCheckTimer(interval: 60)
        }
    }

    private func showHelperAlertIfNeeded() {
        let now = Date()
        if let lastAlert = lastAlertTime, now.timeIntervalSince(lastAlert) < alertCooldownInterval {
            return
        }
        if alertShowing { return }

        alertShowing = true
        lastAlertTime = now
        helperLogger.error("[HelperManager] Showing helper failure alert")

        DispatchQueue.main.async {
            AlertHelper.showAlert(
                title: "Helper Service Unavailable",
                message: "Sapphire's helper service is not responding. Battery management features will be limited. Please check System Settings > General > Login Items and ensure 'Sapphire Helper' is enabled, then restart Sapphire."
            )
            self.alertShowing = false
        }
    }

    func startHealthCheckTimer(interval: TimeInterval = 30) {
        healthCheckTimer?.invalidate()
        healthCheckTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkIfRunning()
            }
        }
        if let timer = healthCheckTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
        // Initial check
        helperLogger.info("[HelperManager] Starting health check timer (interval: \(interval)s)")
        checkIfRunning()
    }

    func installIfNeeded() {
        guard status == .notRegistered || status == .notFound else {
            if status == .requiresApproval {
                DispatchQueue.main.async {
                    AlertHelper.showAlert(
                        title: "Helper Service Approval Required",
                        message: "Sapphire needs you to enable its helper service in System Settings for certain functions like battery management to work correctly. Please go to System Settings > General > Login Items and enable it."
                    )
                    SMAppService.openSystemSettingsLoginItems()
                }
            }
            return
        }

        Task.detached(priority: .utility) {
            do {
                try SMAppService.daemon(plistName: "\(self.helperToolIdentifier).plist").register()
                await MainActor.run {
                    AlertHelper.showAlert(
                        title: "Helper Service Installed",
                        message: "The helper service for Sapphire has been properly installed."
                    )
                }
            } catch {
                NSLog("[HelperManager] Helper registration failed with error: \(error.localizedDescription)")
                await MainActor.run {
                    AlertHelper.showAlert(
                        title: "Installation Failed",
                        message: "Failed to install the helper service. Please try again. Error: \(error.localizedDescription)"
                    )
                }
            }
            await MainActor.run { self.updateStatus() }
        }
    }

    func uninstall() {
        do {
            try SMAppService.daemon(plistName: "\(helperToolIdentifier).plist").unregister()
            NSLog("[HelperManager] Helper unregistration successful.")
            XPCClient.shared.stop()
        } catch {
            NSLog("[HelperManager] Helper unregistration failed with error: \(error.localizedDescription)")
        }
        updateStatus()
    }
}

extension SMAppService.Status: CustomStringConvertible {
    public var description: String {
        switch self {
        case .notRegistered: return "Not Registered"
        case .enabled: return "Enabled"
        case .requiresApproval: return "Requires Approval"
        case .notFound: return "Not Found"
        @unknown default: return "Unknown"
        }
    }
}
