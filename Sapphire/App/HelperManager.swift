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
    private var isRegistering = false
    private var lastRegisterAttempt: Date?
    private let registerCooldown: TimeInterval = 8

    private var daemonService: SMAppService {
        SMAppService.daemon(plistName: "\(helperToolIdentifier).plist")
    }

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
        let newStatus = daemonService.status
        if status != newStatus {
            helperLogger.info("[HelperManager] Status changed: \(String(describing: self.status)) -> \(String(describing: newStatus))")
            status = newStatus
        }
        checkIfRunning()
    }

    func checkIfRunning() {
        Task.detached(priority: .utility) {
            let running = await XPCClient.shared.ping(timeout: 2)
            await MainActor.run {
                helperLogger.info("[HelperManager] Ping result: \(running ? "running" : "NOT running"), current status: \(String(describing: self.status))")
                if self.isRunning != running {
                    self.isRunning = running
                }
                if running {
                    BatteryManager.shared.reconnectHelper()
                }
            }
        }
    }

    /// Settings "Activate" and launch recovery. Never unregisters — that drops Login Items approval.
    func reactivateHelper() {
        Task { await registerHelper(userInitiated: true) }
    }

    func installIfNeeded() {
        updateStatusLocked()
        switch status {
        case .notRegistered, .notFound:
            Task { await registerHelper(userInitiated: false) }
        case .requiresApproval:
            SMAppService.openSystemSettingsLoginItems()
            Task { await registerHelper(userInitiated: false) }
        case .enabled:
            XPCClient.shared.start(force: true)
            checkIfRunning()
        @unknown default:
            break
        }
    }

    func uninstall() {
        do {
            try daemonService.unregister()
            NSLog("[HelperManager] Helper unregistration successful.")
            XPCClient.shared.stop()
        } catch {
            NSLog("[HelperManager] Helper unregistration failed with error: \(error.localizedDescription)")
        }
        updateStatusLocked()
    }

    func startHealthCheckTimer(interval: TimeInterval = 1800) {
        healthCheckTimer?.invalidate()
        healthCheckTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkIfRunning()
            }
        }
        if let timer = healthCheckTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
        helperLogger.info("[HelperManager] Starting health check timer (interval: \(interval)s)")
        checkIfRunning()
    }

    // MARK: - Register (main actor only)

    /// `SMAppService.register()` must run on the main thread so macOS can show the
    /// Login Items prompt. Calling it from a detached task returns "Operation not permitted".
    @discardableResult
    private func registerHelper(userInitiated: Bool) async -> Bool {
        if isRegistering { return false }
        if let last = lastRegisterAttempt, Date().timeIntervalSince(last) < registerCooldown, !userInitiated {
            return false
        }

        isRegistering = true
        lastRegisterAttempt = Date()
        defer { isRegistering = false }

        let service = daemonService
        helperLogger.info("[HelperManager] register() on main actor, current status: \(String(describing: service.status))")

        do {
            try service.register()
            helperLogger.info("[HelperManager] register() succeeded")
        } catch {
            let nsError = error as NSError
            helperLogger.error("[HelperManager] register() failed: \(error.localizedDescription) domain=\(nsError.domain) code=\(nsError.code)")

            updateStatusLocked()

            // Already registered / already enabled is success.
            if service.status == .enabled {
                helperLogger.info("[HelperManager] Service is enabled after register() error — continuing")
            } else if service.status == .requiresApproval || isPermissionError(nsError) {
                SMAppService.openSystemSettingsLoginItems()
                if userInitiated {
                    AlertHelper.showAlert(
                        title: "Enable Sapphire Helper",
                        message: "macOS needs Sapphire Helper turned on in System Settings → General → Login Items. Enable it, then return to Sapphire."
                    )
                }
                return false
            } else if userInitiated {
                AlertHelper.showAlert(
                    title: "Installation Failed",
                    message: "Failed to install the helper service. \(error.localizedDescription)"
                )
                return false
            } else {
                return false
            }
        }

        updateStatusLocked()

        if status == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
            return false
        }

        XPCClient.shared.start(force: true)
        BatteryManager.shared.reconnectHelper()

        for attempt in 1...6 {
            let running = await XPCClient.shared.ping(timeout: 1.5)
            isRunning = running
            helperLogger.info("[HelperManager] Post-register ping \(attempt)/6: \(running ? "running" : "not running")")
            if running {
                BatteryManager.shared.reconnectHelper()
                return true
            }
            try? await Task.sleep(for: .milliseconds(400))
            XPCClient.shared.start(force: true)
        }

        if userInitiated, status != .enabled {
            SMAppService.openSystemSettingsLoginItems()
        }
        return isRunning
    }

    private func isPermissionError(_ error: NSError) -> Bool {
        if error.domain == NSPOSIXErrorDomain && error.code == 1 { return true }
        if error.localizedDescription.lowercased().contains("not permitted") { return true }
        if error.localizedDescription.lowercased().contains("denied") { return true }
        return false
    }

    private func updateStatusLocked() {
        let newStatus = daemonService.status
        if status != newStatus {
            helperLogger.info("[HelperManager] Status changed: \(String(describing: self.status)) -> \(String(describing: newStatus))")
            status = newStatus
        }
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
