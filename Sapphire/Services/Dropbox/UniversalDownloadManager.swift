//
//  UniversalDownloadManager.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-08-17.
//

import Foundation
import Combine

@MainActor
class UniversalDownloadManager {
    static let shared = UniversalDownloadManager()

    let tasksPublisher = PassthroughSubject<[DownloadTask], Never>()

    private var directoryMonitor: DirectoryMonitor?
    private var progressUpdateTimer: Timer?
    private var activeTasks: [URL: DownloadTask] = [:]
    private var cancellables = Set<AnyCancellable>()

    private let temporaryExtensions = ["crdownload", "download", "part"]

    private init() {}

    func startMonitoring() {
        guard directoryMonitor == nil,
              let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else { return }

        directoryMonitor = DirectoryMonitor(url: downloadsURL)
        directoryMonitor?.fileDidChangePublisher
            .debounce(for: .seconds(0.5), scheduler: DispatchQueue.main)
            .sink { [weak self] in
                self?.scanForDownloads()
            }
            .store(in: &cancellables)

        directoryMonitor?.start()

        progressUpdateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateAllProgress()
        }

        scanForDownloads()
    }

    func stopMonitoring() {
        directoryMonitor?.stop()
        directoryMonitor = nil
        progressUpdateTimer?.invalidate()
        progressUpdateTimer = nil
        cancellables.removeAll()
    }

    private func scanForDownloads() {
        guard let downloadsURL = directoryMonitor?.url else { return }

        do {
            let fileURLs = try FileManager.default.contentsOfDirectory(at: downloadsURL, includingPropertiesForKeys: nil)
            var foundTempFiles = Set<URL>()

            for url in fileURLs {
                if temporaryExtensions.contains(url.pathExtension) {
                    foundTempFiles.insert(url)
                    if activeTasks[url] == nil {
                        let finalName = url.deletingPathExtension().lastPathComponent
                        let newTask = DownloadTask(fileURL: url, fileName: finalName)
                        activeTasks[url] = newTask
                    }
                }
            }

            activeTasks = activeTasks.filter { foundTempFiles.contains($0.key) }

            publishTasks()

        } catch {
            print("[UniversalDownloadManager] Error scanning downloads directory: \(error)")
        }
    }

    private func updateAllProgress() {
        guard !activeTasks.isEmpty else { return }
        var hasChanges = false

        for (url, task) in activeTasks {
            let newProgress = getProgress(for: task)
            if activeTasks[url]?.progress != newProgress {
                activeTasks[url]?.progress = newProgress
                hasChanges = true
            }
        }

        if hasChanges {
            publishTasks()
        }
    }

    private func getProgress(for task: DownloadTask) -> Double {
        do {
            let fileAttributes = try FileManager.default.attributesOfItem(atPath: task.fileURL.path)
            guard let currentSize = fileAttributes[.size] as? NSNumber else { return task.progress }

            let attributeName = "com.apple.metadata:kMDItemTotalBytes"
            var totalSize: Int64 = 0
            let attributeValue = try task.fileURL.withUnsafeFileSystemRepresentation {
                getxattr($0, attributeName, &totalSize, MemoryLayout<Int64>.size, 0, 0)
            }

            if attributeValue > 0 && totalSize > 0 {
                return min(1.0, Double(currentSize.int64Value) / Double(totalSize))
            }

        } catch {
        }

        if task.fileURL.pathExtension == "download" {
            let plistURL = task.fileURL.appendingPathComponent("Info.plist")
            if let data = try? Data(contentsOf: plistURL),
               let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
               let downloadEntry = plist["DownloadEntry"] as? [String: Any],
               let bytesSoFar = downloadEntry["DownloadEntryProgressBytesSoFar"] as? Double,
               let bytesTotal = downloadEntry["DownloadEntryProgressTotalToLoad"] as? Double,
               bytesTotal > 0 {
                return min(1.0, bytesSoFar / bytesTotal)
            }
        }

        return task.progress
    }

    private func publishTasks() {
        tasksPublisher.send(Array(activeTasks.values))
    }
}