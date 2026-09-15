//
//  DownloadMonitor.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-08-17.
//

import Foundation
import Combine
import Darwin
import SQLite3

struct DownloadTask: Identifiable, Equatable {
    var id: URL { fileURL }
    let fileURL: URL
    let fileName: String
    var progress: Double = 0.0
    var isComplete: Bool = false
    var totalBytes: Int64 = 0

    var progressFraction: Double? {
        totalBytes > 0 ? min(1.0, Double(currentBytes) / Double(totalBytes)) : nil
    }
    var currentBytes: Int64 = 0
    var startTime: Date = Date()
    var estimatedTimeRemaining: TimeInterval?
    var downloadSpeed: Double?
    var source: DownloadSource = .browser
    var status: String = "Downloading..."
}

enum DownloadSource {
    case browser
    case rsync
    case generic
}

enum DownloadType {
    case safari
    case chrome
    case firefox
    case generic

    var partialExtension: String? {
        switch self {
        case .safari: return "download"
        case .chrome: return "crdownload"
        case .firefox: return "part"
        case .generic: return nil
        }
    }
}

class DownloadProgressExtractor {

    struct ProgressInfo {
        var currentBytes: Int64
        var totalBytes: Int64?
        var progress: Double?

        init(currentBytes: Int64, totalBytes: Int64? = nil) {
            self.currentBytes = currentBytes
            self.totalBytes = totalBytes

            if let total = totalBytes, total > 0 {
                self.progress = min(1.0, Double(currentBytes) / Double(total))
            } else {
                self.progress = nil
            }
        }
    }

    static func extractProgress(
        for url: URL,
        knownTotalBytes: Int64? = nil,
        shouldResolveTotal: Bool = true
    ) -> ProgressInfo? {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            guard let fileSize = attributes[.size] as? Int64 else {
                return nil
            }

            var progressInfo = ProgressInfo(currentBytes: fileSize)
            let downloadType = DownloadMonitor.determineDownloadType(from: url)

            switch downloadType {
            case .safari:
                if let safariInfo = extractSafariProgress(for: url) {
                    progressInfo = safariInfo
                }
            case .chrome:
                if let knownTotalBytes, knownTotalBytes > 0 {
                    progressInfo = ProgressInfo(currentBytes: fileSize, totalBytes: knownTotalBytes)
                } else if shouldResolveTotal,
                          let chromeInfo = extractChromeProgress(for: url, currentSize: fileSize) {
                    progressInfo = chromeInfo
                }
            case .firefox:
                if let knownTotalBytes, knownTotalBytes > 0 {
                    progressInfo = ProgressInfo(currentBytes: fileSize, totalBytes: knownTotalBytes)
                } else if shouldResolveTotal,
                          let firefoxInfo = extractFirefoxProgress(for: url, currentSize: fileSize) {
                    progressInfo = firefoxInfo
                }
            case .generic:
                break
            }

            return progressInfo

        } catch {
            print("[DPE] ERROR getting file attributes for \(url.lastPathComponent): \(error)")
            return nil
        }
    }

    private static func extractSafariProgress(for url: URL) -> ProgressInfo? {
        let infoURL = url.appendingPathComponent("Info.plist")
        guard let data = try? Data(contentsOf: infoURL) else {
            return nil
        }

        guard let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
            return nil
        }

        let entry = (plist["DownloadEntry"] as? [String: Any]) ?? plist
        if let bytesSoFar = integerValue(entry["DownloadEntryProgressBytesSoFar"]),
           let bytesTotal = integerValue(entry["DownloadEntryProgressTotalToLoad"] ?? entry["DownloadEntryTotalBytes"]),
           bytesTotal > 0 {
            return ProgressInfo(currentBytes: bytesSoFar, totalBytes: bytesTotal)
        }

        return nil
    }

    private static func integerValue(_ value: Any?) -> Int64? {
        switch value {
        case let number as NSNumber: return number.int64Value
        case let value as Int64: return value
        case let value as Int: return Int64(value)
        case let value as Double: return Int64(value)
        case let value as String: return Int64(value)
        default: return nil
        }
    }

    private static func extractChromeProgress(for url: URL, currentSize: Int64) -> ProgressInfo? {
        if let totalBytes = ChromiumDownloadDatabase.totalBytes(for: url) {
            return ProgressInfo(currentBytes: currentSize, totalBytes: totalBytes)
        }

        let attributeName = "com.apple.metadata:kMDItemTotalBytes"
        var totalSize: Int64 = 0

        let attrResult = url.withUnsafeFileSystemRepresentation {
            getxattr($0, attributeName, &totalSize, MemoryLayout<Int64>.size, 0, 0)
        }

        if attrResult > 0 && totalSize > 0 {
            return ProgressInfo(currentBytes: currentSize, totalBytes: totalSize)
        }
        return nil
    }

    private static func extractFirefoxProgress(for url: URL, currentSize: Int64) -> ProgressInfo? {
        let attributeName = "com.apple.metadata:kMDItemTotalBytes"
        var totalSize: Int64 = 0

        let attrResult = url.withUnsafeFileSystemRepresentation {
            getxattr($0, attributeName, &totalSize, MemoryLayout<Int64>.size, 0, 0)
        }

        if attrResult > 0 && totalSize > 0 {
            return ProgressInfo(currentBytes: currentSize, totalBytes: totalSize)
        }
        return nil
    }
}

private enum ChromiumDownloadDatabase {
    private static let databasePaths = [
        "Google/Chrome/Default/History",
        "Microsoft Edge/Default/History",
        "BraveSoftware/Brave-Browser/Default/History",
        "Arc/User Data/Default/History"
    ]

    static func totalBytes(for partialURL: URL) -> Int64? {
        let fullPath = partialURL.path
        let basePath = partialURL.deletingPathExtension().path
        let fullName = partialURL.lastPathComponent
        let baseName = partialURL.deletingPathExtension().lastPathComponent
        let likeFull = "%/" + fullName
        let likeBase = "%/" + baseName

        let home = FileManager.default.homeDirectoryForCurrentUser

        for relativePath in databasePaths {
            let databaseURL = home.appendingPathComponent("Library/Application Support").appendingPathComponent(relativePath)
            guard FileManager.default.fileExists(atPath: databaseURL.path) else { continue }

            var database: OpaquePointer?
            guard sqlite3_open_v2(databaseURL.path, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
                sqlite3_close(database)
                continue
            }
            defer { sqlite3_close(database) }

            let query = """
                SELECT total_bytes FROM downloads
                WHERE target_path IN (?, ?, ?, ?)
                   OR current_path IN (?, ?, ?, ?)
                   OR target_path LIKE ? OR target_path LIKE ?
                   OR current_path LIKE ? OR current_path LIKE ?
                ORDER BY start_time DESC LIMIT 1
                """
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK else { continue }
            defer { sqlite3_finalize(statement) }

            let bindValues = [
                fullPath, basePath, fullName, baseName,
                fullPath, basePath, fullName, baseName,
                likeBase, likeBase, likeFull, likeFull
            ]
            var index = 1
            for value in bindValues {
                _ = value.withCString { path in
                    sqlite3_bind_text(statement, Int32(index), path, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                }
                index += 1
            }

            guard sqlite3_step(statement) == SQLITE_ROW else { continue }
            let totalBytes = sqlite3_column_int64(statement, 0)
            if totalBytes > 0 {
                return totalBytes
            }
        }
        return nil
    }
}

@MainActor
class DownloadMonitor: ObservableObject {
    static let shared = DownloadMonitor()

    @Published private(set) var tasks: [DownloadTask] = []
    let tasksPublisher = PassthroughSubject<[DownloadTask], Never>()

    private let queue = DispatchQueue(label: "com.sapphire.downloadmonitor", qos: .utility)
    private let fileManager = FileManager.default
    private var downloadDirectory: URL?
    private var fileWatcher: DispatchSourceFileSystemObject?
    private var updateTimer: Timer?
    private var currentTasks: [URL: DownloadTask] = [:]
    private var taskLastSizes: [URL: Int64] = [:]
    private var taskLastUpdateTimes: [URL: Date] = [:]
    private var taskLastMetadataProbeTimes: [URL: Date] = [:]
    private var lastPublishedTasks: [DownloadTask] = []

    private init() {
        downloadDirectory = fileManager.urls(for: .downloadsDirectory, in: .userDomainMask).first
    }

    func startMonitoring() {
        guard fileWatcher == nil,
              let downloadDirectory = downloadDirectory,
              fileManager.fileExists(atPath: downloadDirectory.path) else {
            print("[DM] ERROR: Could not get downloads directory URL.")
            return
        }
        print("[DM] Starting monitoring on directory: \(downloadDirectory.path)")

        setupDirectoryMonitoring(for: downloadDirectory)
    }

    func stopMonitoring() {
        print("[DM] Stopping monitoring.")
        updateTimer?.invalidate()
        updateTimer = nil
        fileWatcher?.cancel()
        fileWatcher = nil
        currentTasks.removeAll()
        taskLastSizes.removeAll()
        taskLastUpdateTimes.removeAll()
        taskLastMetadataProbeTimes.removeAll()
        tasks = []
        lastPublishedTasks = []
        tasksPublisher.send([])
    }

    private func setupDirectoryMonitoring(for directory: URL) {
        let fileDescriptor = open(directory.path, O_EVTONLY)
        guard fileDescriptor >= 0 else {
            print("[DM] ERROR: Could not open directory for monitoring: \(directory.path)")
            return
        }

        fileWatcher = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fileDescriptor, eventMask: .write, queue: queue)
        fileWatcher?.setEventHandler { [weak self] in
            Task { @MainActor in
                print("[DM] File system event detected. Scanning downloads directory.")
                self?.scanDownloadsDirectory()
            }
        }
        fileWatcher?.setCancelHandler { close(fileDescriptor) }
        fileWatcher?.resume()
        scanDownloadsDirectory()
    }

    private func scanDownloadsDirectory() {
        guard let downloadDirectory = downloadDirectory else { return }

        do {
            let contents = try fileManager.contentsOfDirectory(
                at: downloadDirectory,
                includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
                options: .skipsHiddenFiles
            )
            let partialDownloads = contents.filter { url in
                let ext = url.pathExtension.lowercased()
                return ext == "crdownload" || ext == "part" ||
                    (ext == "download" && (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true)
            }

            let foundURLs = Set(partialDownloads)
            let knownURLs = Set(currentTasks.keys)
            let removedURLs = knownURLs.subtracting(foundURLs)
            let addedURLs = foundURLs.subtracting(knownURLs)

            for url in removedURLs {
                print("[DM] Partial download file removed: \(url.lastPathComponent). Removing task.")
                currentTasks.removeValue(forKey: url)
                removeSamplingState(for: url)
            }

            for url in addedURLs {
                print("[DM] New partial download detected: \(url.lastPathComponent). Creating task.")
                let fileName = getOriginalFileName(from: url)
                let task = DownloadTask(
                    fileURL: url,
                    fileName: fileName,
                    startTime: Date()
                )
                currentTasks[url] = task
                taskLastUpdateTimes[url] = Date()
            }

            if !removedURLs.isEmpty || !addedURLs.isEmpty {
                updateTasksList()
            }
            syncProgressTimer()
            checkDownloads()

        } catch {
            print("[DM] ERROR scanning downloads directory: \(error)")
        }
    }

    private func getOriginalFileName(from url: URL) -> String {
        if url.pathExtension.lowercased() == "download" &&
            (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            let infoURL = url.appendingPathComponent("Info.plist")
            if let data = try? Data(contentsOf: infoURL),
               let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] {
                for key in ["DownloadEntryFilename", "DownloadEntryFileName", "DownloadEntryPath"] {
                    if let value = plist[key] as? String, !value.isEmpty {
                        return URL(fileURLWithPath: value).lastPathComponent
                    }
                }
            }
        }

        let fileNameWithExt = url.lastPathComponent
        let ext = "." + url.pathExtension
        if let range = fileNameWithExt.range(of: ext, options: [.caseInsensitive, .backwards]) {
            return String(fileNameWithExt[..<range.lowerBound])
        }
        return fileNameWithExt
    }

    private func checkDownloads() {
        guard !currentTasks.isEmpty else {
            syncProgressTimer()
            return
        }

        var tasksHaveChanged = false

        for (url, var task) in currentTasks {
            guard fileManager.fileExists(atPath: url.path) else {
                print("[DM] File for task \(task.fileName) no longer exists. Assuming completed or deleted.")
                currentTasks.removeValue(forKey: url)
                removeSamplingState(for: url)
                tasksHaveChanged = true
                continue
            }

            let now = Date()
            let lastMetadataProbe = taskLastMetadataProbeTimes[url] ?? .distantPast
            let shouldResolveTotal = task.totalBytes <= 0 && now.timeIntervalSince(lastMetadataProbe) >= 10
            if shouldResolveTotal {
                taskLastMetadataProbeTimes[url] = now
            }

            if let progressInfo = DownloadProgressExtractor.extractProgress(
                for: url,
                knownTotalBytes: task.totalBytes > 0 ? task.totalBytes : nil,
                shouldResolveTotal: shouldResolveTotal
            ) {
                let oldProgress = task.progress
                let oldCurrentBytes = task.currentBytes
                let oldTotalBytes = task.totalBytes

                task.currentBytes = progressInfo.currentBytes
                if let total = progressInfo.totalBytes {
                    task.totalBytes = total
                }
                if let progress = progressInfo.progress {
                    task.progress = progress
                }

                let lastSize = taskLastSizes[url] ?? 0
                let lastUpdateTime = taskLastUpdateTimes[url] ?? task.startTime
                let timeDiff = now.timeIntervalSince(lastUpdateTime)

                if timeDiff > 0.1 && task.currentBytes > lastSize {
                    let bytesPerSecond = Double(task.currentBytes - lastSize) / timeDiff
                    task.downloadSpeed = bytesPerSecond

                    if task.totalBytes > 0 && bytesPerSecond > 0 {
                        let remainingBytes = Double(task.totalBytes - task.currentBytes)
                        task.estimatedTimeRemaining = remainingBytes / bytesPerSecond
                    }
                    taskLastSizes[url] = task.currentBytes
                    taskLastUpdateTimes[url] = now
                }

                if abs(task.progress - oldProgress) > 0.001 ||
                    task.currentBytes != oldCurrentBytes || task.totalBytes != oldTotalBytes {
                    tasksHaveChanged = true
                }
                currentTasks[url] = task
            }
        }

        let completedTasks = currentTasks.filter { $0.value.progress >= 0.999 }
        for (url, _) in completedTasks {
            print("[DM] Task for \(url.lastPathComponent) is complete. Removing.")
            currentTasks.removeValue(forKey: url)
            removeSamplingState(for: url)
            tasksHaveChanged = true
        }

        syncProgressTimer()
        if tasksHaveChanged || tasks.count != currentTasks.count {
            print("[DM] Download tasks changed. Publishing update.")
            updateTasksList()
        }
    }

    nonisolated static func determineDownloadType(from url: URL) -> DownloadType {
        switch url.pathExtension.lowercased() {
        case "download": return .safari
        case "crdownload": return .chrome
        case "part": return .firefox
        default: return .generic
        }
    }

    private func syncProgressTimer() {
        if currentTasks.isEmpty {
            updateTimer?.invalidate()
            updateTimer = nil
            return
        }

        guard updateTimer == nil else { return }
        let timer = Timer.scheduledCoalescing(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkDownloads() }
        }
        updateTimer = timer
    }

    private func removeSamplingState(for url: URL) {
        taskLastSizes.removeValue(forKey: url)
        taskLastUpdateTimes.removeValue(forKey: url)
        taskLastMetadataProbeTimes.removeValue(forKey: url)
    }

    private func updateTasksList() {
        let updatedTasks = Array(currentTasks.values).sorted { $0.startTime < $1.startTime }
        guard updatedTasks != lastPublishedTasks else { return }
        lastPublishedTasks = updatedTasks
        self.tasks = updatedTasks

        tasksPublisher.send(updatedTasks)
    }
}