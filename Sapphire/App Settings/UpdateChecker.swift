//
//  UpdateChecker.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-07-10.
//

import SwiftUI
import AppKit

let currentAppVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0"

struct GitHubReleaseAsset: Codable, Equatable {
    let name: String
    let browserDownloadUrl: URL
    enum CodingKeys: String, CodingKey {
        case name, browserDownloadUrl = "browser_download_url"
    }
}

struct GitHubRelease: Codable {
    let name: String
    let tagName: String
    let prerelease: Bool
    let assets: [GitHubReleaseAsset]
    enum CodingKeys: String, CodingKey {
        case name, tagName = "tag_name", prerelease, assets
    }
}

enum UpdateStatus: Equatable {
    case checking
    case upToDate
    case available(version: String, asset: GitHubReleaseAsset)
    case downloading(progress: Double)
    case downloaded(path: URL)
    case installing
    case error(String)

    var isUpdateAvailable: Bool {
        if case .available = self { return true }
        return false
    }
}

private struct PersistedAvailableUpdate: Codable {
    let version: String
    let asset: GitHubReleaseAsset
}

@MainActor
class UpdateChecker: NSObject, ObservableObject, URLSessionDownloadDelegate {
    static let shared = UpdateChecker()

    @Published var status: UpdateStatus = .upToDate
    private var downloadTask: URLSessionDownloadTask?
    private var downloadedAssetPath: URL?
    private var timer: Timer?
    private var wakeObserver: NSObjectProtocol?
    private var initialCheckWorkItem: DispatchWorkItem?
    private var lastBackgroundCheck: Date = .distantPast
    private let minimumBackgroundCheckGap: TimeInterval = 30 * 60
    private let persistedAvailableUpdateKey = "SapphirePersistedAvailableUpdate"

    private override init() {
        super.init()
        restorePersistedAvailableUpdateIfNeeded()
    }

    private func applyStatus(_ newStatus: UpdateStatus) {
        let wasAvailable = status.isUpdateAvailable
        guard status != newStatus else { return }
        status = newStatus

        switch newStatus {
        case .available(let version, let asset):
            persistAvailableUpdate(version: version, asset: asset)
            if !wasAvailable {
                NotificationCenter.default.post(name: .sapphireUpdateAvailable, object: version)
            }
        case .upToDate:
            clearPersistedAvailableUpdate()
        default:
            break
        }
    }

    private func persistAvailableUpdate(version: String, asset: GitHubReleaseAsset) {
        let persisted = PersistedAvailableUpdate(version: version, asset: asset)
        guard let data = try? JSONEncoder().encode(persisted) else { return }
        UserDefaults.standard.set(data, forKey: persistedAvailableUpdateKey)
    }

    private func clearPersistedAvailableUpdate() {
        UserDefaults.standard.removeObject(forKey: persistedAvailableUpdateKey)
    }

    private func restorePersistedAvailableUpdateIfNeeded() {
        guard let data = UserDefaults.standard.data(forKey: persistedAvailableUpdateKey),
              let persisted = try? JSONDecoder().decode(PersistedAvailableUpdate.self, from: data),
              persisted.version.compare(currentAppVersion, options: .numeric) == .orderedDescending else {
            clearPersistedAvailableUpdate()
            return
        }
        status = .available(version: persisted.version, asset: persisted.asset)
    }

    func checkForUpdates() {
        if case .checking = status { return }
        if case .downloading = status { return }
        if case .installing = status { return }

        applyStatus(.checking)
        guard let url = URL(string: "https://api.github.com/repos/cshariq/Sapphire/releases/latest") else {
            applyStatus(.error("Invalid update URL")); return
        }

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 15
        URLSession(configuration: config).dataTask(with: url) { data, response, error in
            DispatchQueue.main.async {
                if let error = error { self.applyStatus(.error(error.localizedDescription)); return }
                guard let data = data else { self.applyStatus(.error("No data received.")); return }
                do {
                    let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
                    let latestVersion = release.name.replacingOccurrences(of: "v", with: "")

                    if latestVersion.compare(currentAppVersion, options: .numeric) == .orderedDescending {
                        if let asset = release.assets.first(where: { $0.name.hasSuffix(".zip") }) {
                            self.applyStatus(.available(version: latestVersion, asset: asset))
                        } else {
                            self.applyStatus(.error("No zip download found for this release."))
                        }
                    } else {
                        self.applyStatus(.upToDate)
                    }
                } catch {
                    self.applyStatus(.error("Failed to parse update information."))
                }
            }
        }.resume()
    }

    func checkForBetaUpdates() {
        if case .checking = status { return }
        if case .downloading = status { return }
        if case .installing = status { return }

        applyStatus(.checking)
        guard let url = URL(string: "https://api.github.com/repos/cshariq/Sapphire/releases?per_page=5") else {
            applyStatus(.error("Invalid beta update URL")); return
        }

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 15
        URLSession(configuration: config).dataTask(with: url) { data, response, error in
            DispatchQueue.main.async {
                if let error = error { self.applyStatus(.error(error.localizedDescription)); return }
                guard let data = data else { self.applyStatus(.error("No data received.")); return }
                do {
                    let releases = try JSONDecoder().decode([GitHubRelease].self, from: data)
                    guard let betaRelease = releases.first(where: { $0.prerelease }) else {
                        self.applyStatus(.upToDate)
                        return
                    }
                    let latestVersion = betaRelease.name.replacingOccurrences(of: "v", with: "")
                    if latestVersion.compare(currentAppVersion, options: .numeric) == .orderedDescending {
                        if let asset = betaRelease.assets.first(where: { $0.name.hasSuffix(".zip") }) {
                            self.applyStatus(.available(version: latestVersion, asset: asset))
                        } else {
                            self.applyStatus(.error("No zip beta download found for this release."))
                        }
                    } else {
                        self.applyStatus(.upToDate)
                    }
                } catch {
                    self.applyStatus(.error("Failed to parse beta update information."))
                }
            }
        }.resume()
    }

    func checkForUpdatesMatchingCurrentChannel() {
        let channel = ReleaseChannelPolicy.displayedChannel(for: SettingsModel.shared.settings)
        if channel == .beta {
            checkForBetaUpdates()
        } else {
            checkForUpdates()
        }
    }

    func checkInBackgroundIfNeeded(force: Bool = false) {
        switch status {
        case .checking, .downloading, .installing:
            return
        case .available:
            if !force { return }
        default:
            break
        }
        if !force, Date().timeIntervalSince(lastBackgroundCheck) < minimumBackgroundCheckGap {
            return
        }
        lastBackgroundCheck = Date()
        checkForUpdatesMatchingCurrentChannel()
    }

    func startPeriodicChecks(interval: TimeInterval) {
        stopPeriodicChecks()

        let work = DispatchWorkItem { [weak self] in
            self?.checkInBackgroundIfNeeded(force: true)
        }
        initialCheckWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 20, execute: work)

        let safeInterval = max(interval, 60 * 60)
        timer = Timer.scheduledTimer(withTimeInterval: safeInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkInBackgroundIfNeeded()
            }
        }
        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 8_000_000_000)
                self?.checkInBackgroundIfNeeded()
            }
        }
    }

    func stopPeriodicChecks() {
        initialCheckWorkItem?.cancel()
        initialCheckWorkItem = nil
        timer?.invalidate()
        timer = nil
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
            self.wakeObserver = nil
        }
    }

    func downloadUpdate(asset: GitHubReleaseAsset) {
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        downloadTask = session.downloadTask(with: asset.browserDownloadUrl)
        downloadTask?.resume()

        applyStatus(.downloading(progress: 0.0))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory
        let destinationURL = tempDir.appendingPathComponent(downloadTask.originalRequest!.url!.lastPathComponent)

        try? fileManager.removeItem(at: destinationURL)

        do {
            try fileManager.copyItem(at: location, to: destinationURL)
            DispatchQueue.main.async {
                self.downloadedAssetPath = destinationURL
                self.applyStatus(.downloaded(path: destinationURL))
            }
        } catch {
            DispatchQueue.main.async { self.applyStatus(.error("Failed to move update to temp folder.")) }
        }
    }

    private func isInstallPathUserWritable() -> Bool {
        let appURL = URL(fileURLWithPath: Bundle.main.bundlePath)
        let parentPath = appURL.deletingLastPathComponent().path
        return FileManager.default.isWritableFile(atPath: parentPath)
    }

    private func copyInstallerToTemporaryDirectory(scriptPath: String) throws -> String {
        let tempScript = FileManager.default.temporaryDirectory
            .appendingPathComponent("sapphire_install_update_\(ProcessInfo.processInfo.processIdentifier).sh")
        try? FileManager.default.removeItem(at: tempScript)
        try FileManager.default.copyItem(atPath: scriptPath, toPath: tempScript.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tempScript.path)
        return tempScript.path
    }

    private func launchInstallerScript(
        scriptPath: String,
        processID: String,
        newAppPath: String,
        currentAppPath: String
    ) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [scriptPath, processID, newAppPath, currentAppPath]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
    }

    /// Presents the system admin-password dialog, then starts the installer as root.
    private func launchInstallerWithAdministratorPrivileges(
        scriptPath: String,
        processID: String,
        newAppPath: String,
        currentAppPath: String
    ) throws {
        func shQuote(_ value: String) -> String {
            "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
        }
        let command = "nohup /bin/sh \(shQuote(scriptPath)) \(processID) \(shQuote(newAppPath)) \(shQuote(currentAppPath)) >/dev/null 2>&1 &"
        let escaped = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let source = "do shell script \"\(escaped)\" with administrator privileges"
        var error: NSDictionary?
        guard let appleScript = NSAppleScript(source: source) else {
            throw NSError(
                domain: "UpdateError",
                code: 6,
                userInfo: [NSLocalizedDescriptionKey: "Could not build the administrator prompt."]
            )
        }
        if appleScript.executeAndReturnError(&error) == nil {
            let code = error?[NSAppleScript.errorNumber] as? Int ?? 0
            if code == -128 {
                throw NSError(
                    domain: "UpdateError",
                    code: 7,
                    userInfo: [NSLocalizedDescriptionKey: "Update cancelled. Administrator access is required to replace Sapphire in this location."]
                )
            }
            let message = error?[NSAppleScript.errorMessage] as? String ?? "Administrator authentication failed."
            throw NSError(domain: "UpdateError", code: 8, userInfo: [NSLocalizedDescriptionKey: message])
        }
    }

    func installAndRelaunch() {
        guard let downloadedZipPath = downloadedAssetPath else {
            applyStatus(.error("Downloaded file path not found.")); return
        }

        applyStatus(.installing)

        Task.detached(priority: .userInitiated) {
            do {
                guard let scriptPath = Bundle.main.path(forResource: "install_update", ofType: "sh") else {
                    throw NSError(domain: "UpdateError", code: 1, userInfo: [NSLocalizedDescriptionKey: "install_update.sh not found in app bundle."])
                }

                let fileManager = FileManager.default
                let tempUnzipDirectory = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                try fileManager.createDirectory(at: tempUnzipDirectory, withIntermediateDirectories: true, attributes: nil)

                let unzipProcess = Process()
                unzipProcess.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
                unzipProcess.arguments = ["-o", downloadedZipPath.path, "-d", tempUnzipDirectory.path]
                try unzipProcess.run()
                unzipProcess.waitUntilExit()

                if unzipProcess.terminationStatus != 0 {
                    throw NSError(domain: "UpdateError", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to unzip the update file."])
                }

                guard let newAppPath = try fileManager.contentsOfDirectory(atPath: tempUnzipDirectory.path).first(where: { $0.hasSuffix(".app") }) else {
                    throw NSError(domain: "UpdateError", code: 3, userInfo: [NSLocalizedDescriptionKey: "No .app bundle found in the unzipped file."])
                }
                let fullNewAppPath = tempUnzipDirectory.appendingPathComponent(newAppPath).path

                let currentAppPath = Bundle.main.bundlePath
                let processID = String(ProcessInfo.processInfo.processIdentifier)
                let userWritable = await MainActor.run { self.isInstallPathUserWritable() }
                let tempScriptPath = try await MainActor.run {
                    try self.copyInstallerToTemporaryDirectory(scriptPath: scriptPath)
                }

                if userWritable {
                    try await self.launchInstallerScript(
                        scriptPath: tempScriptPath,
                        processID: processID,
                        newAppPath: fullNewAppPath,
                        currentAppPath: currentAppPath
                    )
                } else {
                    try await MainActor.run {
                        try self.launchInstallerWithAdministratorPrivileges(
                            scriptPath: tempScriptPath,
                            processID: processID,
                            newAppPath: fullNewAppPath,
                            currentAppPath: currentAppPath
                        )
                    }
                }

                await MainActor.run {
                    NSApp.terminate(nil)
                }

            } catch {
                await MainActor.run {
                    self.applyStatus(.error(error.localizedDescription))
                }
            }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error, (error as NSError).code != NSURLErrorCancelled {
            DispatchQueue.main.async { self.applyStatus(.error("Download failed: \(error.localizedDescription)")) }
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        DispatchQueue.main.async {
            if case .downloading = self.status {
                self.applyStatus(.downloading(progress: progress))
            }
        }
    }

    func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
    }
}
