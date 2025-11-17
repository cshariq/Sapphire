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
    private var progressUpdateTimer: Timer?
    private var activeTasks: [URL: FileTransferTask] = [:]
    private var cancellables = Set<AnyCancellable>()

    private let temporaryExtensions = ["crdownload", "download", "part"]
    private let completionDelay: TimeInterval = 5.0

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
                }
                .store(in: &cancellables)
            monitor.start()
            directoryMonitors.append(monitor)
        }

        progressUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.updateTasks()
        }

        scanForFileChanges()
    }

    func stopMonitoring() {
        directoryMonitors.forEach { $0.stop() }
        directoryMonitors.removeAll()
        progressUpdateTimer?.invalidate()
        progressUpdateTimer = nil
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

                    let isTempDownload = temporaryExtensions.contains(url.pathExtension)

                    if !isTempDownload {
                        var newTask = FileTransferTask(
                            fileURL: url,
                            fileName: url.lastPathComponent,
                            destinationURL: url,
                            sourceType: .finder
                        )
                        updateMetadata(for: &newTask)
                        activeTasks[url] = newTask
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
                        hasChanges = true
                    } else {
                        let timeSinceLastChange = Date().timeIntervalSince(updatedTask.lastChangeDate)

                        if timeSinceLastChange > completionDelay {
                            updatedTask.status = .finished
                            updatedTask.isComplete = true
                            tasksToRemove.append(url)
                            hasChanges = true
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
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
                self?.activeTasks.removeValue(forKey: url)
                self?.publishTasks()
            }
        }

        if hasChanges {
            publishTasks()
        }
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
        tasksPublisher.send(tasksToPublish)
    }
}