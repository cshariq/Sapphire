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
    let assets: [GitHubReleaseAsset]
    enum CodingKeys: String, CodingKey {
        case name, tagName = "tag_name", assets
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
}

@MainActor
class UpdateChecker: NSObject, ObservableObject, URLSessionDownloadDelegate {
    static let shared = UpdateChecker()

    @Published var status: UpdateStatus = .upToDate
    private var downloadTask: URLSessionDownloadTask?
    private var downloadedAssetPath: URL?
    private var timer: Timer?

    private override init() {
        super.init()
    }

    func checkForUpdates() {
        if case .checking = status { return }
        if case .downloading = status { return }

        self.status = .checking
        guard let url = URL(string: "https://api.github.com/repos/cshariq/Sapphire/releases/latest") else {
            self.status = .error("Invalid update URL"); return
        }

        URLSession.shared.dataTask(with: url) { data, response, error in
            DispatchQueue.main.async {
                if let error = error { self.status = .error(error.localizedDescription); return }
                guard let data = data else { self.status = .error("No data received."); return }
                do {
                    let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
                    let latestVersion = release.name.replacingOccurrences(of: "v", with: "")

                    if latestVersion.compare(currentAppVersion, options: .numeric) == .orderedDescending {
                        if let asset = release.assets.first(where: { $0.name.hasSuffix(".zip") }) ?? release.assets.first(where: { $0.name.hasSuffix(".dmg") }) {
                            self.status = .available(version: latestVersion, asset: asset)
                        } else {
                            self.status = .error("No suitable download file found.")
                        }
                    } else {
                        self.status = .upToDate
                    }
                } catch {
                    self.status = .error("Failed to parse update information.")
                }
            }
        }.resume()
    }

    func startPeriodicChecks(interval: TimeInterval) {

    }

    func stopPeriodicChecks() {
        timer?.invalidate()
        timer = nil
    }

    func downloadUpdate(asset: GitHubReleaseAsset) {
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        downloadTask = session.downloadTask(with: asset.browserDownloadUrl)
        downloadTask?.resume()

        self.status = .downloading(progress: 0.0)
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
                self.status = .downloaded(path: destinationURL)
            }
        } catch {
            DispatchQueue.main.async { self.status = .error("Failed to move update to temp folder.") }
        }
    }

    func installAndRelaunch() {
        guard let downloadedZipPath = downloadedAssetPath else {
            self.status = .error("Downloaded file path not found."); return
        }

        self.status = .installing

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

                let quotedScriptPath = "'\(scriptPath)'"
                let quotedNewAppPath = "'\(fullNewAppPath)'"
                let quotedCurrentAppPath = "'\(currentAppPath)'"

                let shellCommand = "sh \(quotedScriptPath) \(processID) \(quotedNewAppPath) \(quotedCurrentAppPath) > /dev/null 2>&1 &"

                let appleScript = "do shell script \"\(shellCommand)\" with administrator privileges"

                var error: NSDictionary?
                guard let scriptObject = NSAppleScript(source: appleScript) else {
                    throw NSError(domain: "UpdateError", code: 4, userInfo: [NSLocalizedDescriptionKey: "Could not create AppleScript object."])
                }

                let success = await MainActor.run { () -> Bool in
                    if scriptObject.executeAndReturnError(&error) == nil {
                        if let err = error, let errNum = err[NSAppleScript.errorNumber] as? Int, errNum == -128 {
                            self.status = .downloaded(path: downloadedZipPath)
                        } else {
                            self.status = .error("Installer script failed: \(error?[NSAppleScript.errorMessage] ?? "Unknown error")")
                        }
                        return false
                    }
                    return true
                }

                if success {
                    await MainActor.run {
                        NSApp.terminate(nil)
                    }
                }

            } catch {
                await MainActor.run {
                    self.status = .error(error.localizedDescription)
                }
            }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error, (error as NSError).code != NSURLErrorCancelled {
            DispatchQueue.main.async { self.status = .error("Download failed: \(error.localizedDescription)") }
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        DispatchQueue.main.async {
            if case .downloading = self.status {
                self.status = .downloading(progress: progress)
            }
        }
    }

    func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
    }
}