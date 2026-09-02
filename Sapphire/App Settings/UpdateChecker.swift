//
//  UpdateChecker.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-07-10.
//

import SwiftUI
import AppKit

let currentAppVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0"

enum AppVersionOrdering {
    static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let a = normalize(lhs)
        let b = normalize(rhs)
        if a == b { return .orderedSame }

        let aParts = a.split(separator: ".").map(String.init)
        let bParts = b.split(separator: ".").map(String.init)

        if aParts.count <= 2, bParts.count <= 2,
           let aVal = Double(a), let bVal = Double(b) {
            if aVal > bVal { return .orderedDescending }
            if aVal < bVal { return .orderedAscending }
            return .orderedSame
        }

        let count = max(aParts.count, bParts.count)
        for i in 0..<count {
            let ai = i < aParts.count ? (Int(aParts[i].filter(\.isNumber)) ?? 0) : 0
            let bi = i < bParts.count ? (Int(bParts[i].filter(\.isNumber)) ?? 0) : 0
            if ai != bi { return ai > bi ? .orderedDescending : .orderedAscending }
        }
        return .orderedSame
    }

    static func isNewer(_ candidate: String, than current: String) -> Bool {
        compare(candidate, current) == .orderedDescending
    }

    private static func normalize(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "v", with: "", options: .caseInsensitive)
    }
}

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
    let body: String?
    let htmlUrl: String?
    let prerelease: Bool
    let assets: [GitHubReleaseAsset]
    enum CodingKeys: String, CodingKey {
        case name, tagName = "tag_name", body, htmlUrl = "html_url", prerelease, assets
    }

    var marketingVersion: String {
        let cleanTag = tagName.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "v", with: "", options: .caseInsensitive)
        if cleanTag.contains(where: \.isNumber) {
            return cleanTag
        }
        let fromName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "v", with: "", options: .caseInsensitive)
        if !fromName.isEmpty { return fromName }
        return cleanTag
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
    @Published var releaseNotes: String?
    @Published var releaseNotesVersion: String?
    @Published var releaseNotesURL: URL?
    private var downloadTask: URLSessionDownloadTask?
    private var downloadedAssetPath: URL?
    private var timer: Timer?
    private var wakeObserver: NSObjectProtocol?
    private var initialCheckWorkItem: DispatchWorkItem?
    private var lastBackgroundCheck: Date = .distantPast
    private let minimumBackgroundCheckGap: TimeInterval = 30 * 60
    private let persistedAvailableUpdateKey = "SapphirePersistedAvailableUpdate"

    private let embeddedInstallUpdateScript = """
#!/bin/bash

# Replaces the running Sapphire app bundle with a freshly downloaded one.
# Runs as the current user when the install location is writable (no password).
# Falls back to root only when launched with administrator privileges.
#
# Optional 4th argument: SYNC_MODE=1 tells the script the app is still alive and
# waiting for this script's result, so it can detect failures and fall back. In
# sync mode the script skips waiting for the app to quit and skips relaunching
# it — the app relaunches itself once the script has finished.

PID=$1
NEW_APP_PATH=$2
OLD_APP_PATH=$3
SYNC_MODE=$4

LOG_FILE="${HOME}/Library/Logs/SapphireUpdate.log"
if [ "$(id -u)" -eq 0 ]; then
    CONSOLE_USER=$(stat -f "%Su" /dev/console)
    LOG_FILE=$(eval echo "~$CONSOLE_USER/Library/Logs/SapphireUpdate.log")
fi

echo "---------------------------------" >> "$LOG_FILE"
echo "Update script started at $(date) (uid=$(id -u))" >> "$LOG_FILE"
echo "PID to wait for: $PID" >> "$LOG_FILE"
echo "New app path: $NEW_APP_PATH" >> "$LOG_FILE"
echo "Old app path: $OLD_APP_PATH" >> "$LOG_FILE"
echo "Sync mode: $SYNC_MODE" >> "$LOG_FILE"

if [ -z "$OLD_APP_PATH" ] || [ "$OLD_APP_PATH" == "/" ] || [ ! -d "$OLD_APP_PATH" ]; then
    echo "ERROR: Invalid old application path provided. Aborting update." >> "$LOG_FILE"
    exit 1
fi

if [ "$SYNC_MODE" != "1" ]; then
    echo "Waiting for application (PID: $PID) to quit..." >> "$LOG_FILE"
    while ps -p "$PID" > /dev/null; do
        sleep 1
    done
    echo "Application has quit." >> "$LOG_FILE"
fi

echo "Removing old application at $OLD_APP_PATH..." >> "$LOG_FILE"
rm -rf "$OLD_APP_PATH"
if [ $? -ne 0 ]; then
    echo "ERROR: Failed to remove old application." >> "$LOG_FILE"
    exit 1
fi
echo "Old application removed." >> "$LOG_FILE"

echo "Moving new application into place..." >> "$LOG_FILE"
mv "$NEW_APP_PATH" "$OLD_APP_PATH"
if [ $? -ne 0 ]; then
    echo "ERROR: Failed to move new application into place." >> "$LOG_FILE"
    exit 1
fi
echo "New application moved." >> "$LOG_FILE"

if [ "$SYNC_MODE" != "1" ]; then
    if [ "$(id -u)" -eq 0 ]; then
        CURRENT_USER=$(stat -f "%Su" /dev/console)
        su - "$CURRENT_USER" -c "open \"$OLD_APP_PATH\""
    else
        open "$OLD_APP_PATH"
    fi
else
    echo "Sync mode: relaunch is handled by the app." >> "$LOG_FILE"
fi

echo "Update script finished." >> "$LOG_FILE"
echo "---------------------------------" >> "$LOG_FILE"

exit 0
"""

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
              let persisted = try? JSONDecoder().decode(PersistedAvailableUpdate.self, from: data) else {
            clearPersistedAvailableUpdate()
            return
        }
        let offerStableDowngrade = ReleaseChannelPolicy.shouldOfferStableDowngrade(
            for: SettingsModel.shared.settings
        )
        let stillRelevant = AppVersionOrdering.isNewer(persisted.version, than: currentAppVersion)
            || (offerStableDowngrade
                && AppVersionOrdering.compare(persisted.version, currentAppVersion) != .orderedSame)
        guard stillRelevant else {
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
        guard let url = URL(string: "https://api.github.com/repos/cshariq/Sapphire/releases?per_page=30") else {
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
                    let releases = try JSONDecoder().decode([GitHubRelease].self, from: data)
                    let stable = releases.filter { !$0.prerelease }
                    guard let release = stable.max(by: {
                        AppVersionOrdering.compare($0.marketingVersion, $1.marketingVersion) == .orderedAscending
                    }) else {
                        self.applyReleaseNotes(from: releases, offeredVersion: nil)
                        self.applyStatus(.upToDate)
                        return
                    }
                    let latestVersion = release.marketingVersion
                    let offerStableDowngrade = ReleaseChannelPolicy.shouldOfferStableDowngrade(
                        for: SettingsModel.shared.settings
                    )
                    let shouldOffer = AppVersionOrdering.isNewer(latestVersion, than: currentAppVersion)
                        || (offerStableDowngrade
                            && AppVersionOrdering.compare(latestVersion, currentAppVersion) != .orderedSame)

                    if shouldOffer {
                        if let asset = release.assets.first(where: { $0.name.hasSuffix(".zip") }) {
                            self.applyReleaseNotes(from: releases, offeredVersion: latestVersion)
                            self.applyStatus(.available(version: latestVersion, asset: asset))
                        } else {
                            self.applyStatus(.error("No zip download found for this release."))
                        }
                    } else {
                        self.applyReleaseNotes(from: releases, offeredVersion: nil)
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
        guard let url = URL(string: "https://api.github.com/repos/cshariq/Sapphire/releases?per_page=30") else {
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
                    guard let candidateRelease = releases.max(by: {
                        AppVersionOrdering.compare($0.marketingVersion, $1.marketingVersion) == .orderedAscending
                    }) else {
                        self.applyReleaseNotes(from: releases, offeredVersion: nil)
                        self.applyStatus(.upToDate)
                        return
                    }
                    let latestVersion = candidateRelease.marketingVersion
                    if AppVersionOrdering.isNewer(latestVersion, than: currentAppVersion) {
                        if let asset = candidateRelease.assets.first(where: { $0.name.hasSuffix(".zip") }) {
                            self.applyReleaseNotes(from: releases, offeredVersion: latestVersion)
                            self.applyStatus(.available(version: latestVersion, asset: asset))
                        } else {
                            self.applyStatus(.error("No zip download found for this release."))
                        }
                    } else {
                        self.applyReleaseNotes(from: releases, offeredVersion: nil)
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

    private func applyReleaseNotes(from releases: [GitHubRelease], offeredVersion: String?) {
        let targetVersion = offeredVersion ?? currentAppVersion
        if let match = Self.findRelease(version: targetVersion, in: releases) {
            releaseNotesVersion = match.marketingVersion
            releaseNotes = Self.normalizedNotes(match.body)
            releaseNotesURL = match.htmlUrl.flatMap { URL(string: $0) }
            return
        }
        releaseNotesVersion = targetVersion
        releaseNotes = nil
        releaseNotesURL = URL(string: "https://github.com/cshariq/Sapphire/releases")
    }

    private static func normalizedNotes(_ body: String?) -> String? {
        guard let body = body?.trimmingCharacters(in: .whitespacesAndNewlines), !body.isEmpty else {
            return nil
        }
        return body
    }

    private static func findRelease(version: String, in releases: [GitHubRelease]) -> GitHubRelease? {
        releases.first { release in
            AppVersionOrdering.compare(release.marketingVersion, version) == .orderedSame
                || AppVersionOrdering.compare(
                    release.tagName
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .replacingOccurrences(of: "v", with: "", options: .caseInsensitive),
                    version
                ) == .orderedSame
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

    // MARK: - Current update method (privileged helper → admin prompt → user-writable fallback)

    private func prepareInstallerScript() throws -> String {
        let tempScript = FileManager.default.temporaryDirectory
            .appendingPathComponent("sapphire_install_update_\(ProcessInfo.processInfo.processIdentifier).sh")
        try? FileManager.default.removeItem(at: tempScript)

        let scriptData: Data
        if let scriptPath = Bundle.main.path(forResource: "install_update_sync", ofType: "sh"),
           let data = try? Data(contentsOf: URL(fileURLWithPath: scriptPath)) {
            scriptData = data
        } else if let embedded = embeddedInstallUpdateScript.data(using: .utf8) {
            scriptData = embedded
        } else {
            throw NSError(domain: "UpdateError", code: 1, userInfo: [NSLocalizedDescriptionKey: "install_update_sync.sh is unavailable."])
        }

        try scriptData.write(to: tempScript)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tempScript.path)
        return tempScript.path
    }

    nonisolated private static func runInstallerAsCurrentUser(
        scriptPath: String,
        processID: String,
        newAppPath: String,
        currentAppPath: String
    ) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [scriptPath, processID, newAppPath, currentAppPath, "1"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }

    nonisolated private static func runInstallerWithAdministratorPrivileges(
        scriptPath: String,
        processID: String,
        newAppPath: String,
        currentAppPath: String
    ) throws -> Bool {
        func shQuote(_ value: String) -> String {
            "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
        }
        let command = "/bin/sh \(shQuote(scriptPath)) \(processID) \(shQuote(newAppPath)) \(shQuote(currentAppPath)) 1"
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
            return true
        }
        let code = error?[NSAppleScript.errorNumber] as? Int ?? 0
        if code == -128 {
            throw NSError(
                domain: "UpdateError",
                code: 7,
                userInfo: [NSLocalizedDescriptionKey: "Update cancelled. Administrator access is required to replace Sapphire in this location."]
            )
        }
        if code == 1 {
            return false
        }
        let message = error?[NSAppleScript.errorMessage] as? String ?? "Administrator authentication failed."
        throw NSError(domain: "UpdateError", code: 8, userInfo: [NSLocalizedDescriptionKey: message])
    }

    nonisolated private static func installViaPrivilegedHelper(
        newAppPath: String,
        currentAppPath: String
    ) async -> Bool {
        guard let version = await XPCClient.shared.helperProtocolVersion(timeout: 3),
              version >= 6 else {
            return false
        }

        return await withCheckedContinuation { continuation in
            var resumed = false
            func resumeOnce(_ value: Bool) {
                guard !resumed else { return }
                resumed = true
                continuation.resume(returning: value)
            }

            guard let helper = XPCClient.shared.helper else {
                resumeOnce(false)
                return
            }

            helper.installUpdate(newAppPath: newAppPath, currentAppPath: currentAppPath) { success, _ in
                resumeOnce(success)
            }

            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 15) {
                resumeOnce(false)
            }
        }
    }

    enum UpdateInstallStrategy {
        case standard
        case withoutPassword
    }

    func installAndRelaunchCurrentMethod() {
        installAndRelaunch(strategy: .standard)
    }

    func installAndRelaunchWithoutPassword() {
        installAndRelaunch(strategy: .withoutPassword)
    }

    private func installAndRelaunch(strategy: UpdateInstallStrategy) {
        guard let downloadedZipPath = downloadedAssetPath else {
            applyStatus(.error("Downloaded file path not found.")); return
        }

        applyStatus(.installing)

        Task.detached(priority: .userInitiated) {
            do {

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
                    try self.prepareInstallerScript()
                }

                var installSucceeded = false
                var installCancelled = false

                switch strategy {
                case .standard:
                    if await Self.installViaPrivilegedHelper(newAppPath: fullNewAppPath, currentAppPath: currentAppPath) {
                        installSucceeded = true
                    } else {
                        var adminError: Error?
                        do {
                            installSucceeded = try Self.runInstallerWithAdministratorPrivileges(
                                scriptPath: tempScriptPath,
                                processID: processID,
                                newAppPath: fullNewAppPath,
                                currentAppPath: currentAppPath
                            )
                        } catch {
                            if Self.isInstallCancellation(error) {
                                installCancelled = true
                            } else {
                                adminError = error
                            }
                        }

                        if !installSucceeded, !installCancelled, userWritable {
                            let exitCode = (try? Self.runInstallerAsCurrentUser(
                                scriptPath: tempScriptPath,
                                processID: processID,
                                newAppPath: fullNewAppPath,
                                currentAppPath: currentAppPath
                            )) ?? -1
                            installSucceeded = exitCode == 0
                        }

                        if !installSucceeded, !installCancelled, let adminError {
                            throw adminError
                        }
                    }

                case .withoutPassword:
                    guard userWritable else {
                        throw NSError(
                            domain: "UpdateError",
                            code: 9,
                            userInfo: [NSLocalizedDescriptionKey: "Sapphire isn't in a user-writable location, so the no-password update method can't replace it. Use the standard install method instead."]
                        )
                    }
                    let exitCode = try Self.runInstallerAsCurrentUser(
                        scriptPath: tempScriptPath,
                        processID: processID,
                        newAppPath: fullNewAppPath,
                        currentAppPath: currentAppPath
                    )
                    installSucceeded = exitCode == 0
                }

                if installSucceeded {
                    Self.scheduleRelaunch(of: currentAppPath)
                    await MainActor.run {
                        NSApp.terminate(nil)
                    }
                } else if installCancelled {
                    await MainActor.run {
                        self.applyStatus(.downloaded(path: downloadedZipPath))
                    }
                } else {
                    await MainActor.run {
                        self.applyStatus(.error("The installer script failed to replace Sapphire. The update was not installed."))
                    }
                }

            } catch {
                await MainActor.run {
                    self.applyStatus(.error(error.localizedDescription))
                }
            }
        }
    }

    nonisolated private static func isInstallCancellation(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == "UpdateError" && nsError.code == 7
    }

    nonisolated private static func scheduleRelaunch(of appPath: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "sleep 3; open \"$1\"", "sapphire-relaunch", appPath]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
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