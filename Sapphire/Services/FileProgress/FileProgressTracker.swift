//
//  FileProgressTracker.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-28
//

import AppKit
import Combine
import SQLite3
import os

private let fileProgressLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Sapphire", category: "FileProgress")

struct TrackedTransfer: Identifiable, Equatable {
    enum Operation: Equatable { case download, copy, move, airDrop, other }

    let id: String
    var fileURL: URL
    var fileName: String
    var app: FileProgressApp
    var operation: Operation
    var completedBytes: Int64 = 0
    var totalBytes: Int64?
    var throughput: Double?
    var timeRemaining: TimeInterval?
    var startedAt = Date()
    var isFinished = false
    var isFailed = false
    var isPaused = false
    var canPause = false
    var canCancel = false

    var fraction: Double? {
        guard let totalBytes, totalBytes > 0 else { return isFinished ? 1 : nil }
        return min(1, Double(completedBytes) / Double(totalBytes))
    }
}

@MainActor
final class FileProgressTracker: ObservableObject {
    static let shared = FileProgressTracker()

    @Published private(set) var transfers: [TrackedTransfer] = []
    @Published private(set) var watchedFolders: [URL] = []

    private var subscribers: [URL: Any] = [:]
    private var folderWatchers: [URL: DispatchSourceFileSystemObject] = [:]
    private var published: [String: Progress] = [:]
    private var publishedSourceURLs: [String: URL] = [:]
    private var observations: [String: [NSKeyValueObservation]] = [:]
    private var partial: [String: PartialState] = [:]
    private var lingerTasks: [String: Task<Void, Never>] = [:]
    private var completionGraceTasks: [String: Task<Void, Never>] = [:]
    private var lastAdvance: [String: (completed: Int64, total: Int64, at: Date)] = [:]
    private var staleSizes: [String: Int64] = [:]
    private var vanishedStrikes: [String: Int] = [:]
    private var housekeepingTask: Task<Void, Never>?
    private var publishScheduled = false
    private var cancellables = Set<AnyCancellable>()
    private var isRunning = false

    private struct PartialState {
        var url: URL
        var watcher: DispatchSourceFileSystemObject?
        var lastBytes: Int64 = 0
        var lastSample = Date()
        var lastTotalProbe = Date.distantPast
        var totalProbes = 0
    }

    private var store: [String: TrackedTransfer] = [:]

    private init() {}

    // MARK: - Lifecycle

    func start() {
        guard !isRunning else { return }
        isRunning = true
        let current = SettingsModel.shared.current
        disabledApps = Set(current.fileProgressDisabledApps)
        rebuildWatches(extraFolders: current.fileProgressExtraFolders)
        SettingsModel.shared.$settings
            .map { ($0.fileProgressExtraFolders, $0.fileProgressDisabledApps) }
            .removeDuplicates { $0 == $1 }
            .dropFirst()
            .sink { [weak self] extraFolders, disabled in
                self?.disabledApps = Set(disabled)
                self?.rebuildWatches(extraFolders: extraFolders)
            }
            .store(in: &cancellables)
        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.didLaunchApplicationNotification)
            .debounce(for: .seconds(2), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.rebuildWatches(extraFolders: SettingsModel.shared.current.fileProgressExtraFolders)
            }
            .store(in: &cancellables)
    }

    func stop() {
        isRunning = false
        cancellables.removeAll()
        subscribers.values.forEach { Progress.removeSubscriber($0) }
        subscribers.removeAll()
        folderWatchers.values.forEach { $0.cancel() }
        folderWatchers.removeAll()
        partial.values.forEach { $0.watcher?.cancel() }
        partial.removeAll()
        observations.removeAll()
        published.removeAll()
        publishedSourceURLs.removeAll()
        tokenToID.removeAll()
        lingerTasks.values.forEach { $0.cancel() }
        lingerTasks.removeAll()
        completionGraceTasks.values.forEach { $0.cancel() }
        completionGraceTasks.removeAll()
        lastAdvance.removeAll()
        staleSizes.removeAll()
        vanishedStrikes.removeAll()
        housekeepingTask?.cancel()
        housekeepingTask = nil
        store.removeAll()
        scanScheduled.removeAll()
        rescanRequested.removeAll()
        samplesInFlight.removeAll()
        resampleRequested.removeAll()
        transfers = []
        watchedFolders = []
    }

    private var disabledApps: Set<String> = []

    private func isEnabled(_ app: FileProgressApp) -> Bool {
        !disabledApps.contains(app.rawValue)
    }

    nonisolated private static func foldersToWatch(enabledApps: [FileProgressApp], extraFolders: [String]) -> [URL] {
        let fm = FileManager.default
        var folders: [URL] = [FileManager.SearchPathDirectory.downloadsDirectory, .desktopDirectory, .documentDirectory]
            .compactMap { fm.urls(for: $0, in: .userDomainMask).first }
        for app in enabledApps {
            folders.append(contentsOf: app.configuredDownloadDirectories)
        }
        folders.append(contentsOf: extraFolders.map {
            URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath, isDirectory: true)
        })
        var seen = Set<String>()
        return folders.filter { url in
            let path = url.standardizedFileURL.path
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else { return false }
            return seen.insert(path).inserted
        }
    }

    private static let maxObservedFiles = 48
    private var rebuildGeneration = 0

    private func rebuildWatches(extraFolders: [String]) {
        guard isRunning else { return }
        rebuildGeneration += 1
        let generation = rebuildGeneration
        let enabledApps = FileProgressApp.allCases.filter(isEnabled)
        DispatchQueue.global(qos: .utility).async {
            let folders = Self.foldersToWatch(enabledApps: enabledApps, extraFolders: extraFolders)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    let tracker = FileProgressTracker.shared
                    guard tracker.isRunning, tracker.rebuildGeneration == generation else { return }
                    tracker.applyWatches(folders)
                }
            }
        }
    }

    private func applyWatches(_ folders: [URL]) {
        guard folders != watchedFolders else { return }
        let next = Set(folders)
        let previous = Set(watchedFolders)
        watchedFolders = folders

        for folder in previous.subtracting(next) {
            if let subscriber = subscribers.removeValue(forKey: folder) { Progress.removeSubscriber(subscriber) }
            folderWatchers.removeValue(forKey: folder)?.cancel()
            scanScheduled.remove(folder)
            rescanRequested.remove(folder)
            settleTransfers(in: folder)
        }

        for folder in folders where subscribers[folder] == nil {
            let subscriber = Progress.addSubscriber(forFileURL: folder) { [weak self] progress in
                let id = UUID().uuidString
                DispatchQueue.main.async { self?.attach(progress, token: id) }
                return { DispatchQueue.main.async { self?.detach(token: id) } }
            }
            subscribers[folder] = subscriber
            watchFolder(folder)
        }
    }

    private func settleTransfers(in folder: URL) {
        let folderPath = folder.standardizedFileURL.path
        for (id, transfer) in store where !transfer.isFinished && !transfer.isFailed
            && transfer.fileURL.deletingLastPathComponent().standardizedFileURL.path == folderPath {
            if let state = partial.removeValue(forKey: id) { state.watcher?.cancel() }
            let done = FileManager.default.fileExists(atPath: transfer.fileURL.path)
            completeTransfer(id: id, succeeded: done)
        }
    }

    // MARK: - Published progress

    private var tokenToID: [String: String] = [:]

    private func attach(_ progress: Progress, token: String) {
        guard let url = progress.fileURL ?? progress.userInfo[.fileURLKey] as? URL else { return }
        let kind = progress.fileOperationKind
        let app: FileProgressApp
        let operation: TrackedTransfer.Operation
        switch kind {
        case .some(.receiving):
            app = .airDrop; operation = .airDrop
        case .some(.copying):
            app = .finder; operation = .copy
        default:
            if let owner = FileProgressApp.owner(ofPartialFile: url) {
                app = owner
            } else if url.pathExtension.lowercased() == "download" {
                app = .safari
            } else {
                app = kind == .downloading ? .other : .finder
            }
            operation = (kind == .downloading || kind == .decompressingAfterDownloading || app != .finder) ? .download : .other
        }
        guard isEnabled(app) else { return }

        let id = Self.finalURL(for: url).standardizedFileURL.path
        guard published[id] != nil || published.count < Self.maxObservedFiles else { return }
        tokenToID[token] = id
        published[id] = progress
        publishedSourceURLs[id] = url
        if let state = partial.removeValue(forKey: id) { state.watcher?.cancel() }
        lingerTasks.removeValue(forKey: id)?.cancel()
        completionGraceTasks.removeValue(forKey: id)?.cancel()
        lastAdvance.removeValue(forKey: id)

        var transfer = store[id] ?? TrackedTransfer(
            id: id, fileURL: Self.finalURL(for: url), fileName: Self.displayName(for: url),
            app: app, operation: operation)
        transfer.app = app
        transfer.operation = operation
        transfer.isFinished = false
        transfer.isFailed = false
        store[id] = transfer
        refresh(id: id, from: progress)
        guard published[id] === progress else { return }

        observations[id] = [
            progress.observe(\.completedUnitCount) { [weak self] p, _ in self?.progressChanged(id: id, p) },
            progress.observe(\.totalUnitCount) { [weak self] p, _ in self?.progressChanged(id: id, p) },
            progress.observe(\.isPaused) { [weak self] p, _ in self?.progressChanged(id: id, p) },
            progress.observe(\.isFinished) { [weak self] p, _ in self?.progressChanged(id: id, p) },
            progress.observe(\.isCancelled) { [weak self] p, _ in self?.progressChanged(id: id, p) },
        ]
        scheduleHousekeeping()
    }

    private nonisolated let dirtyProgress = OSAllocatedUnfairLock(initialState: (ids: Set<String>(), scheduled: false))

    nonisolated private func progressChanged(id: String, _ progress: Progress) {
        let shouldSchedule = dirtyProgress.withLock { state -> Bool in
            state.ids.insert(id)
            guard !state.scheduled else { return false }
            state.scheduled = true
            return true
        }
        guard shouldSchedule else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            MainActor.assumeIsolated { self?.flushDirtyProgress() }
        }
    }

    private func flushDirtyProgress() {
        let ids = dirtyProgress.withLock { state -> Set<String> in
            let ids = state.ids
            state.ids.removeAll()
            state.scheduled = false
            return ids
        }
        for id in ids {
            if let progress = published[id] { refresh(id: id, from: progress) }
        }
    }

    private func refresh(id: String, from progress: Progress) {
        guard var transfer = store[id] else { return }
        let previousBytes = transfer.completedBytes
        let now = Date()
        transfer.completedBytes = max(0, progress.completedUnitCount)
        transfer.totalBytes = progress.totalUnitCount > 0 ? progress.totalUnitCount : nil
        transfer.isPaused = progress.isPaused
        transfer.canPause = progress.isPausable
        transfer.canCancel = progress.isCancellable
        if let rate = progress.throughput, rate > 0 {
            transfer.throughput = Double(rate)
        } else if transfer.completedBytes > previousBytes {
            let elapsed = max(now.timeIntervalSince(transfer.startedAt), 0.001)
            transfer.throughput = Double(transfer.completedBytes) / elapsed
        }
        if let eta = progress.estimatedTimeRemaining, eta > 0 {
            transfer.timeRemaining = eta
        } else if let total = transfer.totalBytes, let rate = transfer.throughput, rate > 0 {
            transfer.timeRemaining = Double(total - transfer.completedBytes) / rate
        }
        store[id] = transfer
        schedulePublish()

        let completed = progress.completedUnitCount, total = progress.totalUnitCount
        if let mark = lastAdvance[id], mark.completed == completed, mark.total == total {
        } else {
            lastAdvance[id] = (completed, total, now)
            staleSizes.removeValue(forKey: id)
            vanishedStrikes.removeValue(forKey: id)
        }

        if progress.isCancelled {
            completePublished(id: id, succeeded: false)
        } else if Self.hasReachedEnd(progress), completionGraceTasks[id] == nil {
            completionGraceTasks[id] = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(Self.completionGrace))
                guard !Task.isCancelled, let self else { return }
                self.completionGraceTasks.removeValue(forKey: id)
                guard let current = self.published[id], current === progress else { return }
                self.completePublished(id: id, succeeded: !current.isCancelled)
            }
        }
    }

    private static let completionGrace: TimeInterval = 3
    private static let staleProgressTimeout: TimeInterval = 45

    nonisolated private static func hasReachedEnd(_ progress: Progress) -> Bool {
        let total = progress.totalUnitCount
        guard total > 0 else { return false }
        return progress.completedUnitCount >= total
    }

    private func detach(token: String) {
        guard let id = tokenToID.removeValue(forKey: token) else { return }
        let progress = published[id]
        guard let transfer = store[id] else {
            forgetPublished(id: id)
            return
        }
        let cancelled = progress?.isCancelled ?? false
        let done = !cancelled && ((progress?.fractionCompleted ?? 0) >= 0.99
            || FileManager.default.fileExists(atPath: transfer.fileURL.path))
        completePublished(id: id, succeeded: done)
    }

    private func completePublished(id: String, succeeded: Bool) {
        forgetPublished(id: id)
        completeTransfer(id: id, succeeded: succeeded)
    }

    private func forgetPublished(id: String) {
        observations.removeValue(forKey: id)
        published.removeValue(forKey: id)
        publishedSourceURLs.removeValue(forKey: id)
        completionGraceTasks.removeValue(forKey: id)?.cancel()
        lastAdvance.removeValue(forKey: id)
        staleSizes.removeValue(forKey: id)
        vanishedStrikes.removeValue(forKey: id)
        tokenToID = tokenToID.filter { $0.value != id }
    }

    private func completeTransfer(id: String, succeeded: Bool) {
        guard var transfer = store[id], !transfer.isFinished, !transfer.isFailed else { return }
        transfer.isFinished = succeeded
        transfer.isFailed = !succeeded
        if succeeded, let total = transfer.totalBytes { transfer.completedBytes = total }
        store[id] = transfer
        finish(id: id, succeeded: succeeded)
    }

    // MARK: - Partial files (apps that don't publish progress)

    private let ioQueue = DispatchQueue(label: "com.sapphire.file-progress.io", qos: .utility)
    private var scanScheduled: Set<URL> = []
    private var rescanRequested: Set<URL> = []
    private var samplesInFlight: Set<String> = []
    private var resampleRequested: Set<String> = []

    private struct FolderScan {
        let folder: URL
        let partials: [(url: URL, id: String, owner: FileProgressApp?)]
        let presentPaths: Set<String>
    }

    private func watchFolder(_ folder: URL) {
        let fd = Darwin.open(folder.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.requestScan(of: folder) }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        folderWatchers[folder] = source
        requestScan(of: folder)
    }

    private func requestScan(of folder: URL) {
        guard isRunning else { return }
        guard scanScheduled.insert(folder).inserted else {
            rescanRequested.insert(folder)
            return
        }
        let known = Set(published.keys).union(partial.keys)
        ioQueue.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            let scan = Self.scan(folder, skippingOwnerLookupFor: known)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.scanScheduled.remove(folder)
                    guard self.isRunning, self.folderWatchers[folder] != nil else { return }
                    self.applyScan(scan)
                    if self.rescanRequested.remove(folder) != nil {
                        self.requestScan(of: folder)
                    }
                }
            }
        }
    }

    nonisolated private static func scan(_ folder: URL, skippingOwnerLookupFor known: Set<String>) -> FolderScan {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles)) ?? []
        let presentPaths = Set(contents.map { $0.standardizedFileURL.path })
        let partials = contents
            .filter { FileProgressApp.partialExtensions.contains($0.pathExtension.lowercased()) }
            .map { url -> (url: URL, id: String, owner: FileProgressApp?) in
                let id = finalURL(for: url).standardizedFileURL.path
                return (url, id, known.contains(id) ? nil : FileProgressApp.owner(ofPartialFile: url))
            }
        return FolderScan(folder: folder, partials: partials, presentPaths: presentPaths)
    }

    private func applyScan(_ scan: FolderScan) {
        let folder = scan.folder
        let present = Set(scan.partials.map(\.id))

        for (id, state) in partial where state.url.deletingLastPathComponent().standardizedFileURL == folder.standardizedFileURL
            && !present.contains(id) {
            state.watcher?.cancel()
            partial.removeValue(forKey: id)
            guard var transfer = store[id] else { continue }
            let done = scan.presentPaths.contains(transfer.fileURL.standardizedFileURL.path)
            transfer.isFinished = done
            transfer.isFailed = !done
            if done, let total = transfer.totalBytes { transfer.completedBytes = total }
            store[id] = transfer
            finish(id: id, succeeded: done)
        }

        for entry in scan.partials {
            guard published[entry.id] == nil, partial[entry.id] == nil,
                  let app = entry.owner, isEnabled(app) else { continue }
            let url = entry.url, id = entry.id
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                MainActor.assumeIsolated { self?.beginPartial(url: url, id: id, app: app) }
            }
        }
    }

    private func beginPartial(url: URL, id: String, app: FileProgressApp) {
        guard isRunning, published[id] == nil, partial[id] == nil else { return }
        ioQueue.async { [weak self] in
            guard FileManager.default.fileExists(atPath: url.path) else { return }
            let target = Self.growingFile(for: url)
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.startFollowing(url: url, target: target, id: id, app: app) }
            }
        }
    }

    private func startFollowing(url: URL, target: URL, id: String, app: FileProgressApp) {
        guard isRunning, published[id] == nil, partial[id] == nil else { return }
        guard lingerTasks[id] == nil else { return }
        store[id] = TrackedTransfer(id: id, fileURL: Self.finalURL(for: url), fileName: Self.displayName(for: url),
                                    app: app, operation: .download)
        var state = PartialState(url: url)
        let fd = Darwin.open(target.path, O_EVTONLY)
        if fd >= 0 {
            let folder = url.deletingLastPathComponent()
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd, eventMask: [.write, .extend, .attrib, .rename, .delete], queue: .main)
            source.setEventHandler { [weak self, weak source] in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    let events = source?.data ?? []
                    if events.contains(.rename) || events.contains(.delete) {
                        self.requestScan(of: folder)
                    } else {
                        self.samplePartial(id: id)
                    }
                }
            }
            source.setCancelHandler { close(fd) }
            source.resume()
            state.watcher = source
        }
        partial[id] = state
        samplePartial(id: id)
        scheduleHousekeeping()
    }

    // MARK: - Housekeeping

    private func scheduleHousekeeping() {
        guard housekeepingTask == nil else { return }
        housekeepingTask = Task { @MainActor [weak self] in
            defer { self?.housekeepingTask = nil }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(4))
                guard !Task.isCancelled, let self, self.isRunning else { return }
                guard !self.published.isEmpty || !self.partial.isEmpty else { return }
                await self.sweepLiveTransfers()
            }
        }
    }

    private func sweepLiveTransfers() async {
        for (id, progress) in published {
            if progress.isCancelled {
                completePublished(id: id, succeeded: false)
            } else if Self.hasReachedEnd(progress), completionGraceTasks[id] == nil, let tracked = store[id], !tracked.isFinished {
                refresh(id: id, from: progress)
            }
        }

        struct Probe { let id: String; let partialPath: String; let finalPath: String; let isStale: Bool }
        struct ProbeResult { let id: String; let partialExists: Bool; let finalExists: Bool; let finalSize: Int64? }
        let now = Date()
        var probes: [Probe] = []
        for (id, source) in publishedSourceURLs {
            guard let transfer = store[id], !transfer.isFinished, !transfer.isFailed else { continue }
            let isStale = published[id].map { !$0.isPaused } ?? false
                && lastAdvance[id].map { now.timeIntervalSince($0.at) >= Self.staleProgressTimeout } ?? false
            probes.append(Probe(id: id, partialPath: source.standardizedFileURL.path,
                                finalPath: transfer.fileURL.standardizedFileURL.path, isStale: isStale))
        }
        var partialProbes: [(id: String, path: String, folder: URL)] = []
        for (id, state) in partial {
            partialProbes.append((id, state.url.path, state.url.deletingLastPathComponent()))
        }
        guard !probes.isEmpty || !partialProbes.isEmpty else { return }

        let (results, missingPartialFolders) = await Task.detached(priority: .utility) { () -> ([ProbeResult], [URL]) in
            let fm = FileManager.default
            let results = probes.map { probe -> ProbeResult in
                let finalExists = fm.fileExists(atPath: probe.finalPath)
                let partialExists = probe.partialPath == probe.finalPath ? finalExists : fm.fileExists(atPath: probe.partialPath)
                let size = probe.isStale && finalExists
                    ? (try? fm.attributesOfItem(atPath: probe.finalPath)[.size] as? NSNumber)?.int64Value : nil
                return ProbeResult(id: probe.id, partialExists: partialExists, finalExists: finalExists, finalSize: size)
            }
            let folders = partialProbes.filter { !fm.fileExists(atPath: $0.path) }.map(\.folder)
            return (results, folders)
        }.value
        guard isRunning else { return }

        let probesByID = Dictionary(uniqueKeysWithValues: probes.map { ($0.id, $0) })
        for result in results where published[result.id] != nil {
            guard let probe = probesByID[result.id] else { continue }
            let hasPartial = probe.partialPath != probe.finalPath

            if hasPartial, !result.partialExists, result.finalExists {
                fileProgressLog.info("sweep: \(result.id, privacy: .private) finished on disk without an unpublish")
                completePublished(id: result.id, succeeded: true)
                continue
            }

            if !result.partialExists, !result.finalExists {
                let strikes = (vanishedStrikes[result.id] ?? 0) + 1
                vanishedStrikes[result.id] = strikes
                if strikes >= 2 {
                    fileProgressLog.info("sweep: \(result.id, privacy: .private) vanished from disk; ending it")
                    completePublished(id: result.id, succeeded: false)
                }
                continue
            }
            vanishedStrikes.removeValue(forKey: result.id)

            if probe.isStale, !hasPartial, let size = result.finalSize {
                if let previous = staleSizes[result.id], previous == size {
                    fileProgressLog.info("sweep: \(result.id, privacy: .private) stalled with its file complete; ending it")
                    completePublished(id: result.id, succeeded: true)
                } else {
                    staleSizes[result.id] = size
                }
            }
        }
        for folder in Set(missingPartialFolders) {
            requestScan(of: folder)
        }
    }

    private func samplePartial(id: String) {
        guard let state = partial[id], let transfer = store[id] else { return }
        guard samplesInFlight.insert(id).inserted else {
            resampleRequested.insert(id)
            return
        }
        let now = Date()
        let backoff = 5 * pow(3, Double(state.totalProbes))
        let probeTotal = transfer.totalBytes == nil && state.totalProbes < 3
            && now.timeIntervalSince(state.lastTotalProbe) > backoff
        if probeTotal {
            partial[id]?.lastTotalProbe = now
            partial[id]?.totalProbes += 1
        }
        let url = state.url
        let app = transfer.app
        ioQueue.async { [weak self] in
            let target = Self.growingFile(for: url)
            let bytes = (try? FileManager.default.attributesOfItem(atPath: target.path)[.size] as? NSNumber)?.int64Value ?? 0
            let total = probeTotal ? Self.partialTotal(for: url, app: app) : nil
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.samplesInFlight.remove(id)
                    self.applySample(id: id, bytes: bytes, total: total)
                    if self.resampleRequested.remove(id) != nil {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                            MainActor.assumeIsolated { self?.samplePartial(id: id) }
                        }
                    }
                }
            }
        }
    }

    private func applySample(id: String, bytes: Int64, total: Int64?) {
        guard var state = partial[id], var transfer = store[id] else { return }
        let now = Date()
        let dt = now.timeIntervalSince(state.lastSample)
        if dt >= 0.5, bytes > state.lastBytes {
            let rate = Double(bytes - state.lastBytes) / dt
            transfer.throughput = transfer.throughput.map { $0 * 0.6 + rate * 0.4 } ?? rate
            state.lastBytes = bytes
            state.lastSample = now
        }
        transfer.completedBytes = bytes
        if transfer.totalBytes == nil, let total { transfer.totalBytes = total }
        if let total = transfer.totalBytes, let rate = transfer.throughput, rate > 0 {
            transfer.timeRemaining = Double(max(0, total - bytes)) / rate
        }
        partial[id] = state
        store[id] = transfer
        schedulePublish()
    }

    // MARK: - Finishing

    private func finish(id: String, succeeded: Bool) {
        schedulePublish()
        let settings = SettingsModel.shared.settings
        if succeeded, settings.fileProgressAddFinishedToShelf, let url = store[id]?.fileURL,
           FileManager.default.fileExists(atPath: url.path) {
            FileShelfManager.shared.addFiles(from: [url])
        }
        let linger = max(1, settings.fileProgressKeepFinishedSeconds)
        completionGraceTasks.removeValue(forKey: id)?.cancel()
        lingerTasks[id]?.cancel()
        lingerTasks[id] = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(linger))
            guard !Task.isCancelled, let self else { return }
            self.store.removeValue(forKey: id)
            self.lingerTasks.removeValue(forKey: id)
            self.schedulePublish()
        }
    }

    private func schedulePublish() {
        guard !publishScheduled else { return }
        publishScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.publishScheduled = false
                let next = self.store.values.sorted { $0.startedAt > $1.startedAt }
                if next != self.transfers { self.transfers = next }
            }
        }
    }

    // MARK: - Actions

    func cancel(_ id: String) { published[id]?.cancel() }
    func pause(_ id: String) { published[id]?.pause() }
    func resume(_ id: String) { published[id]?.resume() }

    func reveal(_ id: String) {
        guard let transfer = store[id] else { return }
        let fm = FileManager.default
        let target = fm.fileExists(atPath: transfer.fileURL.path)
            ? transfer.fileURL
            : partial[id]?.url ?? transfer.fileURL.deletingLastPathComponent()
        NSWorkspace.shared.activateFileViewerSelecting([target])
    }

    func open(_ id: String) {
        guard let transfer = store[id], transfer.isFinished else { return reveal(id) }
        NSWorkspace.shared.open(transfer.fileURL)
    }

    // MARK: - Helpers

    nonisolated static func finalURL(for url: URL) -> URL {
        FileProgressApp.partialExtensions.contains(url.pathExtension.lowercased())
            ? url.deletingPathExtension() : url
    }

    nonisolated static func displayName(for url: URL) -> String {
        var name = finalURL(for: url).lastPathComponent
        if name.hasPrefix("Unconfirmed ") { name = "Downloading…" }
        return name
    }

    nonisolated private static func growingFile(for url: URL) -> URL {
        guard url.pathExtension.lowercased() == "download",
              let inner = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.fileSizeKey]))?
                .filter({ $0.lastPathComponent != "Info.plist" })
                .max(by: { ($0.fileSizeBytes ?? 0) < ($1.fileSizeBytes ?? 0) }) else { return url }
        return inner
    }

    nonisolated private static func partialTotal(for url: URL, app: FileProgressApp) -> Int64? {
        if app == .safari,
           let data = try? Data(contentsOf: url.appendingPathComponent("Info.plist")),
           let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
            let entry = (plist["DownloadEntry"] as? [String: Any]) ?? plist
            if let total = (entry["DownloadEntryProgressTotalToLoad"] ?? entry["DownloadEntryTotalBytes"]) as? NSNumber,
               total.int64Value > 0 { return total.int64Value }
        }
        if app.isChromium { return ChromiumHistory.totalBytes(for: url, app: app) }
        return nil
    }
}

private extension URL {
    var fileSizeBytes: Int? { (try? resourceValues(forKeys: [.fileSizeKey]))?.fileSize }
}

private enum ChromiumHistory {
    static func totalBytes(for partialURL: URL, app: FileProgressApp) -> Int64? {
        let roots: [String]
        switch app {
        case .chrome: roots = ["Google/Chrome"]
        case .edge: roots = ["Microsoft Edge"]
        case .brave: roots = ["BraveSoftware/Brave-Browser"]
        case .arc: roots = ["Arc/User Data"]
        case .vivaldi: roots = ["Vivaldi"]
        case .chromium: roots = ["Chromium"]
        default: return nil
        }
        let support = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        let fm = FileManager.default
        for root in roots {
            let base = support.appendingPathComponent(root)
            let profiles = ((try? fm.contentsOfDirectory(at: base, includingPropertiesForKeys: nil)) ?? [])
                .filter { $0.lastPathComponent == "Default" || $0.lastPathComponent.hasPrefix("Profile ") }
            for profile in profiles {
                let db = profile.appendingPathComponent("History")
                guard fm.fileExists(atPath: db.path) else { continue }
                if let total = query(db, partialURL: partialURL) { return total }
            }
        }
        return nil
    }

    private static func query(_ db: URL, partialURL: URL) -> Int64? {
        var handle: OpaquePointer?
        var components = URLComponents()
        components.scheme = "file"
        components.path = db.path
        components.queryItems = [URLQueryItem(name: "immutable", value: "1")]
        guard let uri = components.string,
              sqlite3_open_v2(uri, &handle, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK else {
            sqlite3_close(handle); return nil
        }
        defer { sqlite3_close(handle) }
        let sql = "SELECT total_bytes FROM downloads WHERE current_path = ? OR target_path = ? ORDER BY start_time DESC LIMIT 1"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(statement, 1, partialURL.path, -1, transient)
        sqlite3_bind_text(statement, 2, partialURL.deletingPathExtension().path, -1, transient)
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        let total = sqlite3_column_int64(statement, 0)
        return total > 0 ? total : nil
    }
}