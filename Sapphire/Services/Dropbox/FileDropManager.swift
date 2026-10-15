//
//  FileDropManager.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-08-12.
//

import Foundation
import Combine
import NearbyShare
import AppKit

enum FileTask: Identifiable, Equatable {
    case incomingTransfer(TransferProgressInfo)
    case fileConversion(ConversionTask)
    case universalTransfer(FileTransferTask)
    case airDrop(AirDropTask)
    case local(ShelfItem)

    var id: String {
        switch self {
        case .incomingTransfer(let transfer): return "transfer-\(transfer.id)"
        case .fileConversion(let task): return "conversion-\(task.id.uuidString)"
        case .universalTransfer(let task): return "universal-\(task.id)"
        case .airDrop(let task): return "airdrop-\(task.id.uuidString)"
        case .local(let item): return "local-\(item.id.uuidString)"
        }
    }
}

struct AirDropTask: Identifiable, Equatable {
    var id = UUID()
    var fileName: String
    var progress: Double = 0.5
    var isComplete: Bool = false
}

struct ConversionTask: Identifiable, Equatable {
    var id = UUID()
    var sourceURL: URL
    var targetFormat: ConversionFormat
    var status: Status = .inProgress
    var progress: Double = 0.0
    var outputURL: URL?
    var errorMessage: String?

    enum Status {
        case inProgress, done, failed
    }

    var fileName: String {
        sourceURL.deletingPathExtension().lastPathComponent
    }

    var sourceIcon: String {
        let fileExtension = sourceURL.pathExtension.lowercased()
        switch fileExtension {
        case "png", "jpg", "jpeg", "heic": return "photo"
        case "mov", "mp4": return "video.fill"
        case "pdf": return "doc.richtext.fill"
        default: return "doc.fill"
        }
    }
}

@MainActor
class FileDropManager: ObservableObject {
    static let shared = FileDropManager()
    @Published var tasks: [FileTask] = []

    private var cancellables = Set<AnyCancellable>()
    private var taskDismissalTimers: [String: Timer] = [:]
    private var nearbyDownloadObserver: NSObjectProtocol?

    private init() {
        FileConversionManager.shared.progressPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] (taskID, progress) in
                self?.updateConversionProgress(taskID: taskID, progress: progress)
            }
            .store(in: &cancellables)

        FileConversionManager.shared.completionPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] (taskID, result) in
                self?.finishConversion(taskID: taskID, result: result)
            }
            .store(in: &cancellables)

        FileProgressTracker.shared.$transfers
            .receive(on: DispatchQueue.main)
            .sink { [weak self] transfers in
                self?.updateTrackedTransfers(transfers)
            }
            .store(in: &cancellables)

        NearbyConnectionManager.shared.$transfers
            .receive(on: DispatchQueue.main)
            .sink { [weak self] allTransfers in
                self?.updateNearbyShareTransfers(newTasks: allTransfers)
            }
            .store(in: &cancellables)

        SettingsModel.shared.changes(of: \.fileProgressLiveActivityEnabled)
            .sink { isEnabled in
                if isEnabled {
                    FileProgressTracker.shared.start()
                } else {
                    FileProgressTracker.shared.stop()
                }
            }
            .store(in: &cancellables)

        nearbyDownloadObserver = NotificationCenter.default.addObserver(
            forName: .sapphireNearbyFileDownloaded,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let url = notification.userInfo?["url"] as? URL else { return }
            Task { @MainActor in self?.addDownloadedFileToShelf(url) }
        }

        if SettingsModel.shared.current.fileProgressLiveActivityEnabled {
            FileProgressTracker.shared.start()
        }
    }

    deinit {
        if let nearbyDownloadObserver {
            NotificationCenter.default.removeObserver(nearbyDownloadObserver)
        }
    }

    private func addDownloadedFileToShelf(_ url: URL) {
        FileShelfManager.shared.addFiles(from: [url])
    }

    private func scheduleTaskDismissal(for taskID: String, after delay: TimeInterval) {
        taskDismissalTimers[taskID]?.invalidate()
        let timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                print("[FDM] Dismissal timer fired for task \(taskID). Removing.")
                self?.removeTask(withID: taskID)
                self?.taskDismissalTimers.removeValue(forKey: taskID)
            }
        }
        taskDismissalTimers[taskID] = timer
    }

    private func updateNearbyShareTransfers(newTasks: [TransferProgressInfo]) {
        var activeIDs = Set<String>()
        var updatedTasks = tasks

        for taskData in newTasks {
            let taskID = "transfer-\(taskData.id)"
            activeIDs.insert(taskID)

            if let index = updatedTasks.firstIndex(where: { $0.id == taskID }) {
                updatedTasks[index] = .incomingTransfer(taskData)
            } else {
                updatedTasks.insert(.incomingTransfer(taskData), at: 0)
            }

            switch taskData.state {
            case .finished, .failed, .canceled:
                scheduleTaskDismissal(for: taskID, after: 300.0)
            default:
                taskDismissalTimers[taskID]?.invalidate()
                taskDismissalTimers.removeValue(forKey: taskID)
            }
        }

        updatedTasks.removeAll { task in
            if case .incomingTransfer = task {
                return !activeIDs.contains(task.id) && taskDismissalTimers[task.id] == nil
            }
            return false
        }

        if updatedTasks != tasks {
            tasks = updatedTasks
        }
    }

    private func updateTrackedTransfers(_ transfers: [TrackedTransfer]) {
        func task(_ t: TrackedTransfer, _ source: FileTransferTask.FileTransferSource) -> FileTransferTask {
            FileTransferTask(
                fileURL: t.fileURL,
                fileName: t.fileName,
                destinationURL: t.fileURL,
                currentSize: t.completedBytes,
                totalSize: t.totalBytes,
                speed: t.throughput ?? 0,
                lastChangeDate: t.startedAt,
                isComplete: t.isFinished || t.isFailed,
                status: t.isFinished ? .finished : .inProgress,
                sourceType: source,
                app: t.app,
                timeRemaining: t.timeRemaining
            )
        }
        let copies = transfers.filter { $0.operation == .copy || $0.operation == .move }
        let downloads = transfers.filter { $0.operation != .copy && $0.operation != .move }
        syncUniversalTasks(newTasks: downloads.map { task($0, .browserDownload) }, sourceType: .browserDownload, keepDuration: 0.5)
        syncUniversalTasks(newTasks: copies.map { task($0, .finder) }, sourceType: .finder, keepDuration: 0.5)
    }

    func updateExternalTask(_ task: FileTransferTask?, sourceType: FileTransferTask.FileTransferSource) {
        syncUniversalTasks(newTasks: task.map { [$0] } ?? [], sourceType: sourceType, keepDuration: 5.0)
    }

    private func syncUniversalTasks(newTasks: [FileTransferTask], sourceType: FileTransferTask.FileTransferSource, keepDuration: TimeInterval) {
        var updatedTasks = tasks
        let activeTaskIDs = Set(newTasks.map { "universal-\($0.id)" })

        let previousTaskIDs = Set(updatedTasks.compactMap { task -> String? in
            guard case .universalTransfer(let t) = task, t.sourceType == sourceType else { return nil }
            return "universal-\(t.id)"
        })

        let completedTaskIDs = previousTaskIDs.subtracting(activeTaskIDs)

        for taskID in completedTaskIDs {
            if let index = updatedTasks.firstIndex(where: { $0.id == taskID }) {
                if case .universalTransfer(var task) = updatedTasks[index], taskDismissalTimers[taskID] == nil {
                    task.isComplete = true
                    updatedTasks[index] = .universalTransfer(task)
                    scheduleTaskDismissal(for: taskID, after: keepDuration)
                }
            }
        }

        for taskData in newTasks {
            let taskID = "universal-\(taskData.id)"
            if let timer = taskDismissalTimers.removeValue(forKey: taskID) { timer.invalidate() }
            if let index = updatedTasks.firstIndex(where: { $0.id == taskID }) {
                updatedTasks[index] = .universalTransfer(taskData)
            } else {
                updatedTasks.insert(.universalTransfer(taskData), at: 0)
            }
        }

        if updatedTasks != tasks {
            tasks = updatedTasks
        }
    }

    func addAirDropTask(fileName: String) {
        let task = AirDropTask(fileName: fileName)
        tasks.insert(.airDrop(task), at: 0)
    }

    private func completeAirDropTask(fileName: String) {
        guard let index = tasks.firstIndex(where: {
            if case .airDrop(let task) = $0, task.fileName == fileName { return true }
            return false
        }) else { return }

        if case .airDrop(var task) = tasks[index] {
            task.isComplete = true
            task.progress = 1.0
            tasks[index] = .airDrop(task)
        }
    }

    func addConversion(sourceURL: URL, targetFormat: ConversionFormat) {
        let task = ConversionTask(sourceURL: sourceURL, targetFormat: targetFormat)
        tasks.insert(.fileConversion(task), at: 0)
        FileConversionManager.shared.convert(taskID: task.id, from: sourceURL, to: targetFormat)
    }

    func updateConversionProgress(taskID: UUID, progress: Double) {
        guard let index = tasks.firstIndex(where: {
            if case .fileConversion(let task) = $0, task.id == taskID { return true }
            return false
        }) else { return }

        if case .fileConversion(var task) = tasks[index], task.status == .inProgress {
            task.progress = progress
            tasks[index] = .fileConversion(task)
        }
    }

    private func finishConversion(taskID: UUID, result: Result<URL, Error>) {
        guard let index = tasks.firstIndex(where: {
            if case .fileConversion(let task) = $0, task.id == taskID { return true }
            return false
        }), case .fileConversion(var task) = tasks[index] else { return }
        switch result {
        case .success(let url):
            task.status = .done
            task.progress = 1
            task.outputURL = url
        case .failure(let error):
            task.status = .failed
            task.errorMessage = error.localizedDescription
        }
        tasks[index] = .fileConversion(task)
        scheduleTaskDismissal(for: tasks[index].id, after: task.status == .failed ? 10 : 6)
    }

    func addTransfer(_ transferInfo: TransferProgressInfo) {
        if !tasks.contains(where: { $0.id == "transfer-\(transferInfo.id)" }) {
            tasks.insert(.incomingTransfer(transferInfo), at: 0)
        }
    }

    func removeTask(withID id: String) {
        taskDismissalTimers[id]?.invalidate()
        taskDismissalTimers.removeValue(forKey: id)
        tasks.removeAll { $0.id == id }
    }
}