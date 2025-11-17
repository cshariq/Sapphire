//
//  MenuBarSpacingManager.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-11-08
//

import Foundation
import Combine
import os.log
import AppKit

@MainActor
class MenuBarSpacingManager {
    @Published var spacing: Double = 1.0
    @Published var selectionPadding: Double = 1.0
    @Published var hasUnsavedChanges: Bool = false

    private var cancellables = Set<AnyCancellable>()
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Sapphire", category: "MenuBarSpacingManager")

    private let forceTerminateDelay: TimeInterval = 1.0

    init() {
        loadCurrentSettings()

        $spacing.dropFirst().sink { _ in self.hasUnsavedChanges = true }.store(in: &cancellables)
        $selectionPadding.dropFirst().sink { _ in self.hasUnsavedChanges = true }.store(in: &cancellables)
    }

    func applyChanges() {
        let settings = SettingsModel.shared.settings
        let spacingValue = settings.menuBarSpacing
        let paddingValue = settings.menuBarSelectionPadding

        Task {
            logger.info("Applying spacing: \(spacingValue), padding: \(paddingValue)")
            do {
                try await write(value: spacingValue, forKey: "NSStatusItemSpacing")
                try await write(value: paddingValue, forKey: "NSStatusItemSelectionPadding")
                try await refreshMenuBar()

                self.hasUnsavedChanges = false
            } catch {
                logger.error("Failed to apply changes: \(error.localizedDescription)")
            }
        }
    }

    func restoreDefaults() {
        Task {
            logger.info("Restoring default spacing.")
            do {
                try await delete(key: "NSStatusItemSpacing")
                try await delete(key: "NSStatusItemSelectionPadding")
                try await refreshMenuBar()

                SettingsModel.shared.settings.menuBarSpacing = 1
                SettingsModel.shared.settings.menuBarSelectionPadding = 1
                self.spacing = 1
                self.selectionPadding = 1
                self.hasUnsavedChanges = false
            } catch {
                logger.error("Failed to restore defaults: \(error.localizedDescription)")
            }
        }
    }

    private func loadCurrentSettings() {
        Task {
            let spacingValue = (try? await readDefaultsInt("NSStatusItemSpacing")) ?? 1
            let paddingValue = (try? await readDefaultsInt("NSStatusItemSelectionPadding")) ?? 1

            logger.info("Loaded existing settings - spacing: \(spacingValue), padding: \(paddingValue)")

            self.spacing = Double(spacingValue)
            self.selectionPadding = Double(paddingValue)
            self.hasUnsavedChanges = false
        }
    }

    // MARK: - Core Logic

    private func refreshMenuBar() async throws {
        try? await Task.sleep(for: .milliseconds(100))

        let pids = Set(MenuBarItemDetector.detectItemsWithInfo().map(\.ownerPID))
        var failedApps = [String]()

        logger.info("Found \(pids.count) apps with menu bar items to relaunch.")

        for pid in pids {
            guard let app = NSRunningApplication(processIdentifier: pid),
                  app.bundleIdentifier != "com.apple.controlcenter",
                  app.bundleIdentifier != Bundle.main.bundleIdentifier
            else {
                continue
            }

            do {
                logger.debug("Attempting to relaunch '\(app.localizedName ?? "Unknown App")'")
                try await relaunch(app)
            } catch {
                let appName = app.localizedName ?? app.bundleIdentifier ?? "PID \(pid)"
                logger.warning("Failed to relaunch '\(appName)': \(error.localizedDescription)")
                failedApps.append(appName)
            }
        }

        if let controlCenter = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.controlcenter").first {
            logger.debug("Attempting to restart ControlCenter.")
            do {
                try await signalAppToQuit(controlCenter)
            } catch {
                let appName = controlCenter.localizedName ?? "ControlCenter"
                logger.warning("Failed to quit '\(appName)': \(error.localizedDescription)")
                failedApps.append(appName)
            }
        }

        if !failedApps.isEmpty {
            logger.error("Could not relaunch the following apps: \(failedApps.joined(separator: ", "))")
        }
    }

    private func relaunch(_ app: NSRunningApplication) async throws {
        struct RelaunchError: LocalizedError {
            let message: String
            var errorDescription: String? { message }
        }

        guard let url = app.bundleURL, let bundleIdentifier = app.bundleIdentifier else {
            throw RelaunchError(message: "Could not get bundle info for app.")
        }

        try await signalAppToQuit(app)

        if !app.isTerminated {
            throw RelaunchError(message: "Application did not terminate.")
        }

        try await launch(url: url, bundleIdentifier: bundleIdentifier)
    }

    private func signalAppToQuit(_ app: NSRunningApplication) async throws {
        if app.isTerminated {
            logger.debug("'\(app.localizedName ?? "")' is already terminated.")
            return
        }

        app.terminate()

        let timeout = Date().addingTimeInterval(forceTerminateDelay)
        while !app.isTerminated && Date() < timeout {
            try? await Task.sleep(for: .milliseconds(100))
        }

        if !app.isTerminated {
            logger.warning("'\(app.localizedName ?? "")' did not quit gracefully. Force terminating.")
            app.forceTerminate()
        }
    }

    private func launch(url: URL, bundleIdentifier: String) async throws {
        if NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty {
            let configuration = NSWorkspace.OpenConfiguration()
            try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
            logger.debug("Successfully launched '\(url.lastPathComponent)'.")
        } else {
            logger.debug("'\(url.lastPathComponent)' is already running again.")
        }
    }

    // MARK: - Defaults Commands

    private func write(value: Int, forKey key: String) async throws {
        try await run("/usr/bin/defaults", ["write", "-globalDomain", key, "-int", "\(value)"])
    }

    private func delete(key: String) async throws {
        try await run("/usr/bin/defaults", ["delete", "-globalDomain", key])
    }

    private func readDefaultsInt(_ key: String) async throws -> Int? {
        let (output, status) = try await runWithOutput("/usr/bin/defaults", ["read", "-globalDomain", key])
        if status == 0, let value = Int(output.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return value
        }
        return nil
    }

    @discardableResult
    private func run(_ path: String, _ args: [String]) async throws -> Bool {
        logger.debug("Executing: \(path) \(args.joined(separator: " "))")
        let process = Process()
        process.launchPath = path
        process.arguments = args
        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { task in
                continuation.resume(returning: task.terminationStatus == 0)
            }
            do { try process.run() } catch { continuation.resume(throwing: error) }
        }
    }

    private func runWithOutput(_ path: String, _ args: [String]) async throws -> (String, Int32) {
        logger.debug("Executing: \(path) \(args.joined(separator: " "))")
        let process = Process()
        process.launchPath = path
        process.arguments = args
        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { task in
                let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                continuation.resume(returning: (output, task.terminationStatus))
            }
            do { try process.run() } catch { continuation.resume(throwing: error) }
        }
    }
}