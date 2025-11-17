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

    private init() {
        FileConversionManager.shared.progressPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] (taskID, progress) in
                self?.updateConversionProgress(taskID: taskID, progress: progress)
            }
            .store(in: &cancellables)

        UniversalFileTransferManager.shared.tasksPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] transferTasks in
                self?.updateUniversalTransfers(newTasks: transferTasks)
            }
            .store(in: &cancellables)

        NearbyConnectionManager.shared.$transfers
            .receive(on: DispatchQueue.main)
            .sink { [weak self] allTransfers in
                self?.updateNearbyShareTransfers(newTasks: allTransfers)
            }
            .store(in: &cancellables)

        UniversalFileTransferManager.shared.startMonitoring()
    }

    private func scheduleTaskDismissal(for taskID: String, after delay: TimeInterval) {
        taskDismissalTimers[taskID]?.invalidate()
        let timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            print("[FDM] Dismissal timer fired for task \(taskID). Removing.")
            self?.removeTask(withID: taskID)
            self?.taskDismissalTimers.removeValue(forKey: taskID)
        }
        taskDismissalTimers[taskID] = timer
    }

    private func updateNearbyShareTransfers(newTasks: [TransferProgressInfo]) {
        var activeIDs = Set<String>()

        for taskData in newTasks {
            let taskID = "transfer-\(taskData.id)"
            activeIDs.insert(taskID)

            if let index = tasks.firstIndex(where: { $0.id == taskID }) {
                tasks[index] = .incomingTransfer(taskData)
            } else {
                tasks.insert(.incomingTransfer(taskData), at: 0)
            }

            switch taskData.state {
            case .finished, .failed, .canceled:
                scheduleTaskDismissal(for: taskID, after: 300.0)
            default:
                taskDismissalTimers[taskID]?.invalidate()
                taskDismissalTimers.removeValue(forKey: taskID)
            }
        }

        tasks.removeAll { task in
            if case .incomingTransfer = task {
                return !activeIDs.contains(task.id) && taskDismissalTimers[task.id] == nil
            }
            return false
        }

        objectWillChange.send()
    }

    func updateBrowserDownloads(_ downloads: [FileTransferTask]) {
        print("[FDM] Received updateBrowserDownloads with \(downloads.count) tasks from DownloadMonitor.")
        syncUniversalTasks(newTasks: downloads, sourceType: .browserDownload, keepDuration: 30.0)
    }

    private func updateUniversalTransfers(newTasks: [FileTransferTask]) {
        let finderTasks = newTasks.filter { $0.sourceType == .finder }
        print("[FDM] Processing \(finderTasks.count) Finder transfers from UFTM.")
        syncUniversalTasks(newTasks: finderTasks, sourceType: .finder, keepDuration: 30.0)
    }

    private func syncUniversalTasks(newTasks: [FileTransferTask], sourceType: FileTransferTask.FileTransferSource, keepDuration: TimeInterval) {
        let activeTaskIDs = Set(newTasks.map { "universal-\($0.id)" })

        let previousTaskIDs = Set(tasks.compactMap { task -> String? in
            guard case .universalTransfer(let t) = task, t.sourceType == sourceType else { return nil }
            return "universal-\(t.id)"
        })

        let completedTaskIDs = previousTaskIDs.subtracting(activeTaskIDs)

        for taskID in completedTaskIDs {
            if let index = tasks.firstIndex(where: { $0.id == taskID }) {
                if case .universalTransfer(var task) = tasks[index], taskDismissalTimers[taskID] == nil {
                    task.isComplete = true
                    tasks[index] = .universalTransfer(task)
                    scheduleTaskDismissal(for: taskID, after: keepDuration)
                }
            }
        }

        for taskData in newTasks {
            let taskID = "universal-\(taskData.id)"
            if let index = tasks.firstIndex(where: { $0.id == taskID }) {
                tasks[index] = .universalTransfer(taskData)
            } else {
                tasks.insert(.universalTransfer(taskData), at: 0)
            }
        }

        objectWillChange.send()
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

        if case .fileConversion(var task) = tasks[index] {
            task.progress = progress
            if progress >= 1.0 {
                task.status = .done
            }
            tasks[index] = .fileConversion(task)
        }
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