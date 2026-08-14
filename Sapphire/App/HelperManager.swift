//
//  HelperManager.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-11-08.
//

import Foundation
import ServiceManagement
import AppKit
import SwiftUI
import OSLog

private let helperLogger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Sapphire", category: "HelperManager")

// MARK: - Error codes
//
// SAP-H1  Permission granted, helper still will not spawn (launchd EX_CONFIG)
// SAP-H2  macOS is waiting for Login Items approval (status 2)
// SAP-H3  Helper record missing (status 3 / notFound) — relaunch required

enum HelperIssue: Equatable {
    case spawnFailed
    case needsApproval
    case notFound

    var code: String {
        switch self {
        case .spawnFailed: return "SAP-H1"
        case .needsApproval: return "SAP-H2"
        case .notFound: return "SAP-H3"
        }
    }

    var title: String {
        switch self {
        case .spawnFailed: return "Helper cannot start"
        case .needsApproval: return "Login Items approval required"
        case .notFound: return "Helper registration missing"
        }
    }

    var shortSummary: String {
        switch self {
        case .spawnFailed:
            return "Permission is granted, but macOS still will not launch the helper."
        case .needsApproval:
            return "Turn on Sapphire and Sapphire Helper in Login Items."
        case .notFound:
            return "macOS lost the helper (status 3). Quit and reopen Sapphire."
        }
    }

    var instructions: String {
        switch self {
        case .notFound:
            return """
            Error code: SAP-H3

            macOS reports the helper as “Not Found” (SMAppService status 3). The Login Items database no longer has a record for this copy of Sapphire, so the helper cannot start until the app is relaunched.

            Do this:
            1. Click “Relaunch Sapphire” below (or quit Sapphire completely and open it again).
            2. When Sapphire opens, click Install if asked.
            3. In System Settings → General → Login Items, enable both:
               • Sapphire
               • Sapphire Helper

            If SAP-H3 appears again right after relaunch, use SAP-H1 recovery (reset background items).
            """
        case .needsApproval:
            return """
            Error code: SAP-H2

            macOS registered the helper but is waiting for your permission (SMAppService status 2).

            Do this:
            1. Click “Open Login Items” below.
            2. Under Allow in the Background, turn on:
               • Sapphire
               • Sapphire Helper
            3. Authenticate if macOS asks for your password.
            4. Return to Sapphire and click Install / Activate.

            Both items must be on. Enabling only the helper is not enough.
            """
        case .spawnFailed:
            return """
            Error code: SAP-H1

            Login Items permission is already granted (status 1), but macOS still will not spawn the helper. This usually means a stuck background-item database (launchd error 78 / EX_CONFIG).

            Do this:
            1. Quit Sapphire.
            2. Open Terminal.
            3. Paste and run this command (enter your Mac password when asked):

               sudo sfltool resetbtm

            4. Restart your Mac. macOS requires a reboot after that command.
            5. Open Sapphire.
            6. In System Settings → General → Login Items, enable both Sapphire and Sapphire Helper.
            7. Click Activate if the helper still shows as inactive.

            Note: resetbtm clears ALL login items and background apps, not only Sapphire. You will need to re-enable other apps’ background items afterward.
            """
        }
    }

    static let resetBTMCommand = "sudo sfltool resetbtm"
}

struct HelperStatusBanner: View {
    @ObservedObject var helperManager: HelperManager

    var body: some View {
        HStack(alignment: .top, spacing: 15) {
            Image(systemName: helperManager.bannerSymbol)
                .font(.title2)
                .foregroundColor(helperManager.bannerColor)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(helperManager.bannerTitle)
                        .font(.headline)
                    if let issue = helperManager.lastIssue {
                        Text(issue.code)
                            .font(.caption.weight(.semibold).monospaced())
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(helperManager.bannerColor.opacity(0.18))
                            .clipShape(Capsule())
                    }
                }
                Text(helperManager.bannerSubtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            HStack(spacing: 8) {
                if let issue = helperManager.lastIssue {
                    Button("Instructions") {
                        HelperAlertPresenter.present(issue)
                    }
                    .buttonStyle(.bordered)
                }

                if helperManager.status == .enabled && !helperManager.isRunning {
                    Button("Activate") {
                        helperManager.reactivateHelper()
                    }
                    .buttonStyle(.bordered)
                    .tint(.orange)
                } else if helperManager.status == .notFound {
                    Button("Relaunch") {
                        HelperManager.relaunchApp()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                } else if helperManager.status == .requiresApproval {
                    Button("Open Login Items") {
                        SMAppService.openSystemSettingsLoginItems()
                        helperManager.beginInstallation()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                } else if helperManager.status != .enabled {
                    Button("Install") {
                        helperManager.beginInstallation()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.accentColor)
                }
            }
        }
    }
}

@MainActor
class HelperManager: ObservableObject {
    static let shared = HelperManager()

    let helperToolIdentifier = "com.shariq.sapphireHelper"

    @Published var status: SMAppService.Status = .notRegistered
    @Published var isRunning: Bool = false
    @Published var lastIssue: HelperIssue?

    private var healthCheckTimer: Timer?
    private var isRegistering = false
    private var lastRegisterAttempt: Date?
    private var consecutiveMissedPings = 0
    private var presentedIssuesThisSession = Set<String>()
    private let registerCooldown: TimeInterval = 8

    private var daemonService: SMAppService {
        SMAppService.daemon(plistName: "\(helperToolIdentifier).plist")
    }

    var bannerTitle: String {
        if isRunning, status == .enabled { return "Helper Active" }
        return lastIssue?.title ?? "Helper Not Installed"
    }

    var bannerSubtitle: String {
        if isRunning, status == .enabled {
            return "Privileged helper is running."
        }
        return lastIssue?.shortSummary ?? "Install the helper to enable battery management and system integrations."
    }

    var bannerSymbol: String {
        if isRunning, status == .enabled { return "checkmark.circle.fill" }
        switch lastIssue {
        case .spawnFailed: return "exclamationmark.octagon.fill"
        case .needsApproval: return "exclamationmark.triangle.fill"
        case .notFound: return "arrow.triangle.2.circlepath.circle.fill"
        case nil: return "xmark.circle.fill"
        }
    }

    var bannerColor: Color {
        if isRunning, status == .enabled { return .green }
        switch lastIssue {
        case .spawnFailed: return .red
        case .needsApproval: return .yellow
        case .notFound: return .orange
        case nil: return .red
        }
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

    nonisolated static func relaunchApp() {
        let path = Bundle.main.bundlePath.replacingOccurrences(of: "\"", with: "\\\"")
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/zsh")
        task.arguments = ["-c", "sleep 0.7; /usr/bin/open -n \"\(path)\""]
        try? task.run()
        DispatchQueue.main.async {
            NSApplication.shared.terminate(nil)
        }
    }

    @objc func updateStatus() {
        let newStatus = daemonService.status
        if status != newStatus {
            helperLogger.info("[HelperManager] Status changed: \(String(describing: self.status)) -> \(String(describing: newStatus))")
            status = newStatus
        }
        refreshIssue()
        checkIfRunning()
    }

    func checkIfRunning() {
        if isRegistering { return }
        Task.detached(priority: .utility) {
            let running = await XPCClient.shared.ping(timeout: 2)
            await MainActor.run {
                helperLogger.info("[HelperManager] Ping result: \(running ? "running" : "NOT running"), current status: \(String(describing: self.status))")
                self.applyPingResult(running)
            }
        }
    }

    /// Settings "Activate". Forces unregister + register so launchd rebuilds LWCR.
    func reactivateHelper() {
        Task { await registerHelper(userInitiated: true, forceReinstall: true) }
    }

    /// Onboarding / Install button. Always user-initiated so Login Items opens and SAP-H2/H3 popups appear.
    func beginInstallation() {
        updateStatusLocked()
        helperLogger.info("[HelperManager] beginInstallation status=\(String(describing: self.status))")
        Task { await registerHelper(userInitiated: true, forceReinstall: false) }
    }

    func installIfNeeded() {
        updateStatusLocked()
        let appStatus = SMAppService.mainApp.status
        helperLogger.info("[HelperManager] installIfNeeded daemon=\(String(describing: self.status)) mainApp=\(String(describing: appStatus)) issue=\(self.lastIssue?.code ?? "none")")

        switch status {
        case .notFound:
            Task { await registerHelper(userInitiated: true, forceReinstall: false) }
        case .notRegistered:
            // Quiet auto-install at app launch. Still creates the Login Items entry.
            Task { await registerHelper(userInitiated: false, forceReinstall: false) }
        case .enabled:
            Task {
                if await XPCClient.shared.ping(timeout: 2) {
                    applyPingResult(true)
                    return
                }
                await registerHelper(userInitiated: false, forceReinstall: false)
            }
        case .requiresApproval:
            Task { await registerHelper(userInitiated: true, forceReinstall: false) }
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
        refreshIssue()
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

    @discardableResult
    private func registerHelper(userInitiated: Bool, forceReinstall: Bool) async -> Bool {
        if isRegistering { return false }
        if let last = lastRegisterAttempt, Date().timeIntervalSince(last) < registerCooldown, !userInitiated, !forceReinstall {
            return false
        }

        isRegistering = true
        lastRegisterAttempt = Date()
        defer { isRegistering = false }

        let service = daemonService
        helperLogger.info("[HelperManager] register() on main actor, status=\(String(describing: service.status)), bundle=\(Bundle.main.bundlePath), forceReinstall=\(forceReinstall)")

        if forceReinstall {
            _ = await reinstallHelper()
        } else {
            _ = await submitRegistration(service: service)
        }

        updateStatusLocked()
        refreshIssue()

        if status == .notFound {
            presentIssue(.notFound, force: userInitiated)
            return false
        }

        if status == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
            presentIssue(.needsApproval, force: true)
            return false
        }

        if await pingUntilRunning() {
            return true
        }

        refreshIssue()
        if let issue = lastIssue {
            presentIssue(issue, force: userInitiated || issue == .notFound)
        }
        return isRunning
    }

    private func submitRegistration(service: SMAppService) async -> Bool {
        do {
            try service.register()
            helperLogger.info("[HelperManager] register() returned success")
            return true
        } catch {
            let nsError = error as NSError
            helperLogger.error("[HelperManager] register() failed: \(error.localizedDescription) domain=\(nsError.domain) code=\(nsError.code)")
            updateStatusLocked()
            refreshIssue()
            return service.status == .enabled
        }
    }

    @discardableResult
    private func reinstallHelper() async -> Bool {
        let service = daemonService
        helperLogger.info("[HelperManager] unregister() to rebuild LWCR, current status=\(String(describing: service.status))")
        do {
            try await service.unregister()
            helperLogger.info("[HelperManager] unregister() succeeded")
        } catch {
            helperLogger.error("[HelperManager] unregister() failed: \(error.localizedDescription)")
        }

        XPCClient.shared.stop()
        try? await Task.sleep(for: .milliseconds(1000))
        updateStatusLocked()
        return await submitRegistration(service: service)
    }

    private func pingUntilRunning() async -> Bool {
        XPCClient.shared.start(force: false)
        try? await Task.sleep(for: .milliseconds(800))

        for attempt in 1...8 {
            let running = await XPCClient.shared.ping(timeout: 1.5)
            helperLogger.info("[HelperManager] Post-register ping \(attempt)/8: \(running ? "running" : "not running")")
            if running {
                applyPingResult(true)
                BatteryManager.shared.reconnectHelper()
                return true
            }
            try? await Task.sleep(for: .milliseconds(400))
        }
        applyPingResult(false)
        return false
    }

    private func applyPingResult(_ running: Bool) {
        if running {
            consecutiveMissedPings = 0
            isRunning = true
        } else if isRunning {
            consecutiveMissedPings += 1
            if consecutiveMissedPings >= 3 {
                isRunning = false
            }
        } else {
            consecutiveMissedPings += 1
            isRunning = false
        }
        refreshIssue()
    }

    private func refreshIssue() {
        if isRunning, status == .enabled {
            lastIssue = nil
            return
        }
        switch status {
        case .notFound:
            lastIssue = .notFound
        case .requiresApproval:
            lastIssue = .needsApproval
        case .enabled:
            lastIssue = .spawnFailed
        case .notRegistered:
            lastIssue = nil
        @unknown default:
            lastIssue = .notFound
        }
    }

    private func presentIssue(_ issue: HelperIssue, force: Bool) {
        if !force, presentedIssuesThisSession.contains(issue.code) { return }
        presentedIssuesThisSession.insert(issue.code)
        HelperAlertPresenter.present(issue)
    }

    private func updateStatusLocked() {
        let newStatus = daemonService.status
        if status != newStatus {
            helperLogger.info("[HelperManager] Status changed: \(String(describing: self.status)) -> \(String(describing: newStatus))")
            status = newStatus
        }
        refreshIssue()
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
