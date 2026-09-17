//
//  UniversalDownloadManager.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-08-17.
//

import Foundation
import Combine
import Darwin

@MainActor
class UniversalDownloadManager {
    static let shared = UniversalDownloadManager()

    let tasksPublisher = PassthroughSubject<[DownloadTask], Never>()

    private var directoryMonitor: DirectoryMonitor?
    private var fileWatchers: [URL: DispatchSourceFileSystemObject] = [:]
    private var activeTasks: [URL: DownloadTask] = [:]
    private var cancellables = Set<AnyCancellable>()

    private let temporaryExtensions = ["crdownload", "download", "part"]

    private init() {}

    func startMonitoring() {
        guard directoryMonitor == nil,
              let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first,
              FileManager.default.fileExists(atPath: downloadsURL.path) else { return }

        directoryMonitor = DirectoryMonitor(url: downloadsURL)
        directoryMonitor?.fileDidChangePublisher
            .debounce(for: .seconds(0.5), scheduler: DispatchQueue.main)
            .sink { [weak self] in
                self?.scanForDownloads()
            }
            .store(in: &cancellables)

        directoryMonitor?.start()

        scanForDownloads()
    }

    func stopMonitoring() {
        directoryMonitor?.stop()
        directoryMonitor = nil
        fileWatchers.values.forEach { $0.cancel() }
        fileWatchers.removeAll()
        cancellables.removeAll()
    }

    private func scanForDownloads() {
        guard let downloadsURL = directoryMonitor?.url else { return }

        do {
            let fileURLs = try FileManager.default.contentsOfDirectory(at: downloadsURL, includingPropertiesForKeys: nil)
            var foundTempFiles = Set<URL>()

            for url in fileURLs {
                let extensionName = url.pathExtension.lowercased()
                let isSafariBundle = extensionName == "download" &&
                    (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
                if extensionName == "crdownload" || extensionName == "part" || isSafariBundle {
                    foundTempFiles.insert(url)
                    if activeTasks[url] == nil {
                        let finalName = url.deletingPathExtension().lastPathComponent
                        let newTask = DownloadTask(fileURL: url, fileName: finalName)
                        activeTasks[url] = newTask
                    }
                }
            }

            let removedURLs = Set(activeTasks.keys).subtracting(foundTempFiles)
            for url in removedURLs {
                activeTasks.removeValue(forKey: url)
                fileWatchers.removeValue(forKey: url)?.cancel()
            }

            for url in foundTempFiles where fileWatchers[url] == nil {
                installFileWatcher(for: url)
            }

            publishTasks()

        } catch {
            print("[UniversalDownloadManager] Error scanning downloads directory: \(error)")
        }
    }

    private func installFileWatcher(for url: URL) {
        let fileDescriptor = open(url.path, O_EVTONLY)
        guard fileDescriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .extend, .attrib, .delete, .rename, .revoke],
            queue: .main
        )
        source.setEventHandler { [weak self, weak source] in
            guard let self, let source else { return }
            self.updateProgress(for: url)
            if !source.data.isDisjoint(with: [.delete, .rename, .revoke]) {
                self.scanForDownloads()
            }
        }
        source.setCancelHandler { close(fileDescriptor) }
        source.resume()
        fileWatchers[url] = source
        updateProgress(for: url)
    }

    private func updateProgress(for url: URL) {
        guard let task = activeTasks[url] else { return }
        let newProgress = getProgress(for: task)
        guard task.progress != newProgress else { return }
        activeTasks[url]?.progress = newProgress
        publishTasks()
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
               let propertyList = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
               let plist = propertyList as? [String: Any] {
                let downloadEntry = (plist["DownloadEntry"] as? [String: Any]) ?? plist
                if let bytesSoFar = numericValue(downloadEntry["DownloadEntryProgressBytesSoFar"]),
                   let bytesTotal = numericValue(downloadEntry["DownloadEntryProgressTotalToLoad"] ?? downloadEntry["DownloadEntryTotalBytes"]),
                   bytesTotal > 0 {
                    return min(1.0, bytesSoFar / bytesTotal)
                }
            }
        }

        return task.progress
    }

    private func numericValue(_ value: Any?) -> Double? {
        switch value {
        case let number as NSNumber: return number.doubleValue
        case let value as Double: return value
        case let value as Int64: return Double(value)
        case let value as Int: return Double(value)
        case let value as String: return Double(value)
        default: return nil
        }
    }

    private func publishTasks() {
        tasksPublisher.send(Array(activeTasks.values))
    }
}