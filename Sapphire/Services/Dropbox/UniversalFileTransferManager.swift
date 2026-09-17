//
//  UniversalFileTransferManager.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-08-17.
//

import Foundation
import Combine
import CoreServices

struct FileTransferTask: Identifiable, Equatable {
    var id: String { fileURL.absoluteString }
    let fileURL: URL
    let fileName: String
    var destinationURL: URL
    var currentSize: Int64 = 0
    var totalSize: Int64?
    var speed: Double = 0
    var lastChangeDate: Date = Date()
    var isComplete: Bool = false
    var status: Status = .inProgress
    var sourceType: FileTransferSource = .manual

    enum Status { case inProgress, finished }

    enum FileTransferSource {
        case manual
        case browserDownload
        case finder
        case archiveExtraction
        case dmgInstall
    }

    var progress: Double? {
        guard let total = totalSize, total > 0 else { return nil }
        return min(1.0, Double(currentSize) / Double(total))
    }
}

@MainActor
class UniversalFileTransferManager {
    static let shared = UniversalFileTransferManager()

    let tasksPublisher = PassthroughSubject<[FileTransferTask], Never>()

    private var directoryMonitors: [DirectoryMonitor] = []
    private var fileWatchers: [URL: DispatchSourceFileSystemObject] = [:]
    private var completionTasks: [URL: Task<Void, Never>] = [:]
    private var activeTasks: [URL: FileTransferTask] = [:]
    private var cancellables = Set<AnyCancellable>()

    private let temporaryExtensions = ["crdownload", "download", "part"]
    private let completionDelay: TimeInterval = 5.0
    private var lastPublishedTasks: [FileTransferTask] = []

    private init() {}

    func startMonitoring() {
        guard directoryMonitors.isEmpty,
              let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first,
              let desktopURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
        else {
            print("[UFTM] ERROR: Could not get URLs for Downloads or Desktop directories.")
            return
        }

        let urlsToMonitor = [downloadsURL, desktopURL]
        for url in urlsToMonitor {
            let monitor = DirectoryMonitor(url: url)
            monitor.fileDidChangePublisher
                .debounce(for: .seconds(0.2), scheduler: DispatchQueue.main)
                .sink { [weak self] in
                    self?.scanForFileChanges()
                    self?.updateTasks()
                }
                .store(in: &cancellables)
            monitor.start()
            directoryMonitors.append(monitor)
        }

        scanForFileChanges()
    }

    func stopMonitoring() {
        directoryMonitors.forEach { $0.stop() }
        directoryMonitors.removeAll()
        fileWatchers.values.forEach { $0.cancel() }
        fileWatchers.removeAll()
        completionTasks.values.forEach { $0.cancel() }
        completionTasks.removeAll()
        cancellables.removeAll()
    }

    private func scanForFileChanges() {
        var allFileURLs: Set<URL> = []
        for monitor in directoryMonitors {
            if let urls = try? FileManager.default.contentsOfDirectory(at: monitor.url, includingPropertiesForKeys: [.creationDateKey, .contentModificationDateKey]) {
                allFileURLs.formUnion(urls)
            }
        }

        var hasChanges = false
        for url in allFileURLs {
            guard !url.lastPathComponent.starts(with: ".") else {
                continue
            }

            if activeTasks[url] == nil {
                if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
                   let modDate = attributes[.modificationDate] as? Date,
                   Date().timeIntervalSince(modDate) < 5.0 {

                    let isTempDownload = temporaryExtensions.contains(url.pathExtension.lowercased())

                    if !isTempDownload {
                        var newTask = FileTransferTask(
                            fileURL: url,
                            fileName: url.lastPathComponent,
                            destinationURL: url,
                            sourceType: .finder
                        )
                        updateMetadata(for: &newTask)
                        activeTasks[url] = newTask
                        installFileWatcher(for: url)
                        scheduleCompletionCheck(for: url, expectedSize: newTask.currentSize)
                        hasChanges = true
                    } else {
                    }
                }
            }
        }

        if hasChanges {
            publishTasks()
        }
    }

    private func updateTasks() {
        guard !activeTasks.isEmpty else { return }
        var hasChanges = false
        var tasksToRemove: [URL] = []

        for (url, task) in activeTasks where task.status == .inProgress {
            var updatedTask = task

            do {
                let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
                if let fileSize = attributes[.size] as? Int64 {
                    let oldSize = updatedTask.currentSize
                    updatedTask.currentSize = fileSize

                    if fileSize > oldSize {
                        let now = Date()
                        let timeDiff = now.timeIntervalSince(updatedTask.lastChangeDate)

                        if timeDiff > 0 {
                            updatedTask.speed = Double(fileSize - oldSize) / timeDiff
                        }
                        updatedTask.lastChangeDate = now
                        scheduleCompletionCheck(for: url, expectedSize: fileSize)
                        hasChanges = true
                    } else {
                        if completionTasks[url] == nil {
                            scheduleCompletionCheck(for: url, expectedSize: fileSize)
                        }
                    }
                }
            } catch {
                tasksToRemove.append(url)
                hasChanges = true
            }

            activeTasks[url] = updatedTask
        }

        for url in tasksToRemove {
            removeTask(for: url)
        }

        if hasChanges {
            publishTasks()
        }
    }

    private func installFileWatcher(for url: URL) {
        guard fileWatchers[url] == nil else { return }
        let fileDescriptor = open(url.path, O_EVTONLY)
        guard fileDescriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .extend, .attrib, .delete, .rename, .revoke],
            queue: .main
        )
        source.setEventHandler { [weak self, weak source] in
            guard let source else { return }
            let wasReplaced = !source.data.isDisjoint(with: [.delete, .rename, .revoke])
            self?.updateTasks()
            if wasReplaced { self?.scanForFileChanges() }
        }
        source.setCancelHandler { close(fileDescriptor) }
        source.resume()
        fileWatchers[url] = source
    }

    private func scheduleCompletionCheck(for url: URL, expectedSize: Int64) {
        completionTasks[url]?.cancel()
        completionTasks[url] = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(self?.completionDelay ?? 5))
            guard !Task.isCancelled, let self,
                  let task = self.activeTasks[url], task.status == .inProgress else { return }
            self.completionTasks[url] = nil
            let size = ((try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? NSNumber)?.int64Value
            guard size == expectedSize else {
                self.updateTasks()
                return
            }
            self.removeTask(for: url)
            self.publishTasks()
        }
    }

    private func removeTask(for url: URL) {
        activeTasks.removeValue(forKey: url)
        completionTasks.removeValue(forKey: url)?.cancel()
        fileWatchers.removeValue(forKey: url)?.cancel()
    }

    private func updateMetadata(for task: inout FileTransferTask) {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: task.fileURL.path)
            task.currentSize = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        } catch {
            print("[UFTM] ERROR: Could not get initial metadata for \(task.fileName).")
            activeTasks.removeValue(forKey: task.fileURL)
        }
    }

    private func publishTasks() {
        let tasksToPublish = Array(activeTasks.values.filter { $0.status == .inProgress })
            .sorted { $0.lastChangeDate < $1.lastChangeDate }
        guard tasksToPublish != lastPublishedTasks else { return }
        lastPublishedTasks = tasksToPublish
        tasksPublisher.send(tasksToPublish)
    }
}