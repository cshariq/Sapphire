//
//  AppStorageModels.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-02

import AppKit
import CryptoKit
import Darwin
import SwiftUI

private final class WeakReference<Value: AnyObject>: @unchecked Sendable {
    weak var value: Value?

    init(_ value: Value) {
        self.value = value
    }
}

private enum StorageOpaqueIdentifier: Hashable, Sendable {
    case data(Data)
    case text(String)

    var serialized: String {
        switch self {
        case let .data(data): return data.base64EncodedString()
        case let .text(text): return text
        }
    }

    static func read(_ value: Any?) -> StorageOpaqueIdentifier? {
        guard let value else { return nil }
        if let data = value as? Data { return .data(data) }
        if let data = value as? NSData { return .data(data as Data) }
        return .text(String(describing: value))
    }
}

private struct StorageFileIdentity: Hashable, Sendable {
    let volume: String
    let file: StorageOpaqueIdentifier

    var serialized: String { "\(volume):\(file.serialized)" }

    static func read(
        from values: URLResourceValues,
        assumingVolume assumedVolume: String? = nil
    ) -> StorageFileIdentity? {
        guard let volume = assumedVolume ?? identityVolume(from: values),
              let file = StorageOpaqueIdentifier.read(values.fileResourceIdentifier) else { return nil }
        return StorageFileIdentity(volume: volume, file: file)
    }

    static func volumeIdentifier(from values: URLResourceValues) -> String? {
        StorageOpaqueIdentifier.read(values.volumeIdentifier)?.serialized
    }

    static func identityVolume(from values: URLResourceValues) -> String? {
        volumeIdentifier(from: values) ?? fallbackVolumeIdentifier(from: values.volume)
    }

    static func fallbackVolumeIdentifier(from volumeURL: URL?) -> String? {
        volumeURL.map { "volume-url:\($0.standardizedFileURL.path)" }
    }

    static func read(at url: URL) -> StorageFileIdentity? {
        guard let values = try? url.resourceValues(forKeys: [
            .volumeIdentifierKey,
            .volumeURLKey,
            .fileResourceIdentifierKey
        ]) else { return nil }
        return read(from: values)
    }

}

fileprivate struct StoragePOSIXFileIdentity: Hashable, Sendable {
    private static let serializationPrefix = "posix-device-inode:"

    let device: UInt64
    let inode: UInt64

    var serialized: String { "\(Self.serializationPrefix)\(device):\(inode)" }

    init(_ metadata: stat) {
        device = UInt64(truncatingIfNeeded: metadata.st_dev)
        inode = UInt64(truncatingIfNeeded: metadata.st_ino)
    }

    static func read(at url: URL) -> StoragePOSIXFileIdentity? {
        url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return nil }
            var metadata = stat()
            guard lstat(path, &metadata) == 0 else { return nil }
            return StoragePOSIXFileIdentity(metadata)
        }
    }

    static func recognizes(_ serialized: String) -> Bool {
        serialized.hasPrefix(serializationPrefix)
    }
}

fileprivate final class StorageHardLinkRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var identities = Set<StoragePOSIXFileIdentity>()

    func shouldCount(_ identity: StoragePOSIXFileIdentity) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return identities.insert(identity).inserted
    }
}

private struct StorageCacheKey: Hashable, Sendable {
    let path: String
    let deepScan: Bool

    init(url: URL, deepScan: Bool) {
        self.path = url.standardizedFileURL.path
        self.deepScan = deepScan
    }
}

private struct StorageScanRequest: Sendable {
    let url: URL
    let deepScan: Bool
}

private struct StoragePathCategoryContext: Sendable {
    private var containsTrash = false
    private var containsDownloads = false
    private var containsCaches = false
    private var containsApplicationSupport = false

    init() {}

    init(url: URL) {
        self.init()
        for component in url.standardizedFileURL.pathComponents {
            append(component.lowercased())
        }
    }

    func appending(_ lowercasedComponent: String) -> StoragePathCategoryContext {
        var copy = self
        copy.append(lowercasedComponent)
        return copy
    }

    func category(itemName: String, isDirectory: Bool) -> StorageCategory {
        if containsTrash { return .trash }
        if containsDownloads { return .downloads }
        if containsCaches { return .caches }
        if isDirectory {
            if itemName == "languages" || itemName.hasSuffix(".lproj") { return .languagePacks }
            if containsApplicationSupport || itemName == "support" { return .appSupport }
        }
        return .other
    }

    private mutating func append(_ lowercasedComponent: String) {
        switch lowercasedComponent {
        case ".trash", ".trashes": containsTrash = true
        case "downloads": containsDownloads = true
        case "caches", "tmp": containsCaches = true
        case "application support": containsApplicationSupport = true
        default: break
        }
    }
}

private struct StorageTraversalContext: Sendable {
    let pathCategory: StoragePathCategoryContext
    let packageCategory: StorageCategory?
}

private struct StorageInsightAccumulator: Sendable {
    static let notableCategories: Set<StorageCategory> = [
        .largeFiles, .oldFiles, .downloads, .caches, .trash
    ]

    private var buckets: [StorageCategory: [StorageEntry]] = [:]

    static func shouldIndex(category: StorageCategory, isLargeFile: Bool, isOldFile: Bool) -> Bool {
        notableCategories.contains(category) || isLargeFile || isOldFile
    }

    func wouldAdmit(
        category: StorageCategory,
        size: Int64,
        lastModified: Date?,
        isLargeFile: Bool,
        isOldFile: Bool,
        limitPerCategory: Int
    ) -> Bool {
        guard limitPerCategory > 0 else { return false }
        if Self.notableCategories.contains(category),
           wouldAdmit(size: size, lastModified: lastModified, to: category, limit: limitPerCategory) {
            return true
        }
        if isLargeFile, category != .largeFiles,
           wouldAdmit(size: size, lastModified: lastModified, to: .largeFiles, limit: limitPerCategory) {
            return true
        }
        if isOldFile, category != .oldFiles,
           wouldAdmit(size: size, lastModified: lastModified, to: .oldFiles, limit: limitPerCategory) {
            return true
        }
        return false
    }

    private func wouldAdmit(
        size: Int64,
        lastModified: Date?,
        to bucketKey: StorageCategory,
        limit: Int
    ) -> Bool {
        guard let bucket = buckets[bucketKey], bucket.count >= limit, let leastUseful = bucket.first else {
            return true
        }
        if size != leastUseful.size { return size > leastUseful.size }
        let candidateDate = lastModified ?? .distantPast
        let existingDate = leastUseful.lastModified ?? .distantPast
        if candidateDate != existingDate { return candidateDate < existingDate }
        return true
    }

    mutating func consider(_ entry: StorageEntry, limitPerCategory: Int) {
        guard limitPerCategory > 0,
              !entry.isDirectory,
              !entry.isPackage,
              !entry.isSymbolicLink else { return }

        var bucketKeys: [StorageCategory] = []
        if Self.notableCategories.contains(entry.category) { bucketKeys.append(entry.category) }
        if entry.isLargeFile, !bucketKeys.contains(.largeFiles) { bucketKeys.append(.largeFiles) }
        if entry.isOldFile, !bucketKeys.contains(.oldFiles) { bucketKeys.append(.oldFiles) }
        for bucketKey in bucketKeys {
            consider(entry, in: bucketKey, limit: limitPerCategory)
        }
    }

    private mutating func consider(_ entry: StorageEntry, in bucketKey: StorageCategory, limit: Int) {
        var bucket = buckets.removeValue(forKey: bucketKey) ?? []
        if bucket.count < limit {
            bucket.append(entry)
            siftUp(&bucket, from: bucket.count - 1)
            buckets[bucketKey] = bucket
            return
        }

        guard !bucket.isEmpty else { return }
        if Self.isMoreUseful(entry, than: bucket[0]) {
            bucket[0] = entry
            siftDown(&bucket, from: 0)
        }
        buckets[bucketKey] = bucket
    }

    private func siftUp(_ heap: inout [StorageEntry], from startIndex: Int) {
        var child = startIndex
        while child > 0 {
            let parent = (child - 1) / 2
            guard Self.isLessUseful(heap[child], than: heap[parent]) else { break }
            heap.swapAt(child, parent)
            child = parent
        }
    }

    private func siftDown(_ heap: inout [StorageEntry], from startIndex: Int) {
        var parent = startIndex
        while true {
            let left = parent * 2 + 1
            guard left < heap.count else { return }
            let right = left + 1
            var leastUseful = left
            if right < heap.count, Self.isLessUseful(heap[right], than: heap[left]) {
                leastUseful = right
            }
            guard Self.isLessUseful(heap[leastUseful], than: heap[parent]) else { return }
            heap.swapAt(parent, leastUseful)
            parent = leastUseful
        }
    }

    mutating func merge(_ entries: [StorageEntry], limitPerCategory: Int) {
        for entry in entries { consider(entry, limitPerCategory: limitPerCategory) }
    }

    var entries: [StorageEntry] {
        let unique = Dictionary(
            buckets.values.flatMap { $0 }.map { ($0.url.standardizedFileURL, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        return unique.values.sorted {
            if $0.category != $1.category { return $0.category.rawValue < $1.category.rawValue }
            return Self.isMoreUseful($0, than: $1)
        }
    }

    private static func isMoreUseful(_ lhs: StorageEntry, than rhs: StorageEntry) -> Bool {
        if lhs.size != rhs.size { return lhs.size > rhs.size }
        if lhs.lastModified != rhs.lastModified {
            return (lhs.lastModified ?? .distantPast) < (rhs.lastModified ?? .distantPast)
        }
        return lhs.url.path.localizedStandardCompare(rhs.url.path) == .orderedAscending
    }

    private static func isLessUseful(_ lhs: StorageEntry, than rhs: StorageEntry) -> Bool {
        isMoreUseful(rhs, than: lhs)
    }
}

private struct StorageScanProgress: Sendable {
    let state: StorageScanState
    let fraction: Double
    let label: String
}

private struct StorageDirectorySnapshot: Sendable {
    let url: URL
    var entries: [StorageEntry]
    let insightEntries: [StorageEntry]
    let recommendations: [CleanupRecommendation]
    let duplicateGroups: [StorageDuplicateGroup]
    let categorySizes: [StorageCategory: Int64]
    let reclaimableBytes: Int64
    let issues: [StorageScanIssue]
    var metrics: StorageScanMetrics
}

private actor StorageSnapshotCache {
    static let shared = StorageSnapshotCache()

    private struct CachedValue: Sendable {
        var snapshot: StorageDirectorySnapshot
        var storedAt: Date
        var lastAccess: Date
        let cost: Int
    }

    private var values: [StorageCacheKey: CachedValue] = [:]
    private let maximumEntries = 16
    private let maximumCost = 50_000

    func value(for key: StorageCacheKey, maxAge: TimeInterval) -> StorageDirectorySnapshot? {
        guard var cached = values[key],
              Date().timeIntervalSince(cached.storedAt) >= 0,
              Date().timeIntervalSince(cached.storedAt) < maxAge else {
            values.removeValue(forKey: key)
            return nil
        }
        cached.lastAccess = Date()
        values[key] = cached
        return cached.snapshot
    }

    func store(_ snapshot: StorageDirectorySnapshot, for key: StorageCacheKey) {
        let now = Date()
        let cost = snapshot.entries.count
            + snapshot.insightEntries.count
            + snapshot.recommendations.reduce(0) { $0 + $1.entries.count }
            + snapshot.duplicateGroups.reduce(0) { $0 + $1.entries.count }
            + snapshot.issues.count
        guard cost <= maximumCost else {
            values.removeValue(forKey: key)
            return
        }
        values[key] = CachedValue(snapshot: snapshot, storedAt: now, lastAccess: now, cost: cost)
        while (values.count > maximumEntries
                || (values.count > 1 && values.values.reduce(0, { $0 + $1.cost }) > maximumCost)),
              let leastRecentlyUsed = values.min(by: { $0.value.lastAccess < $1.value.lastAccess })?.key {
            values.removeValue(forKey: leastRecentlyUsed)
        }
    }

    func invalidate(affectedBy urls: [URL]) {
        guard !urls.isEmpty else { return }
        values = values.filter { key, _ in
            let cachedRoot = URL(fileURLWithPath: key.path, isDirectory: true)
            return !urls.contains { removed in
                StorageDeletionPolicy.contains(cachedRoot, removed)
                    || StorageDeletionPolicy.contains(removed, cachedRoot)
            }
        }
    }
}

private struct StorageChildScanResult: Sendable {
    let index: Int
    let entry: StorageEntry?
    let candidates: [StorageFileCandidate]
    let categorySizes: [StorageCategory: Int64]
    let insightEntries: [StorageEntry]
    let failures: [DirectoryScanFailure]
    let filesVisited: Int
    let directoriesVisited: Int
    let logicalBytesVisited: Int64
    let allocatedBytesVisited: Int64
    let wasCancelled: Bool

    func droppingTransientCollections() -> StorageChildScanResult {
        StorageChildScanResult(
            index: index,
            entry: entry,
            candidates: [],
            categorySizes: categorySizes,
            insightEntries: [],
            failures: [],
            filesVisited: filesVisited,
            directoriesVisited: directoriesVisited,
            logicalBytesVisited: logicalBytesVisited,
            allocatedBytesVisited: allocatedBytesVisited,
            wasCancelled: wasCancelled
        )
    }
}

private struct StorageIndexedURL: Sendable {
    let index: Int
    let url: URL
    let metadata: StorageChildMetadata?
}

private struct StorageChildMetadata: Sendable {
    let isDirectory: Bool
    let isSymbolicLink: Bool
    let isPackage: Bool
    let identity: StorageFileIdentity?
    let logicalSize: Int64
    let allocatedSize: Int64
    let lastModified: Date?
    let linkCount: Int
    let volumeIdentifier: String?
    let volumeURL: URL?

    init(values: URLResourceValues, assumingVolume: String?) {
        isDirectory = values.isDirectory == true
        isSymbolicLink = values.isSymbolicLink == true
        isPackage = values.isPackage == true
        identity = StorageFileIdentity.read(from: values, assumingVolume: assumingVolume)
        logicalSize = Int64(max(0, values.fileSize ?? 0))
        allocatedSize = Int64(max(0, values.totalFileAllocatedSize ?? values.fileSize ?? 0))
        lastModified = values.contentModificationDate
        linkCount = max(1, values.linkCount ?? 1)
        volumeIdentifier = StorageFileIdentity.volumeIdentifier(from: values)
        volumeURL = values.volume?.standardizedFileURL
    }
}

private struct StorageScanUnit: Sendable {
    let items: [StorageIndexedURL]
}

private struct StorageScanUnitProducer {
    private let children: [URL]
    private let resourceKeys: Set<URLResourceKey>
    private let assumedVolume: String?
    private let fileBatchSize: Int
    private var nextIndex = 0
    private var pendingFiles: [StorageIndexedURL] = []
    private var pendingDirectory: StorageIndexedURL?

    init(
        children: [URL],
        resourceKeys: Set<URLResourceKey>,
        assumedVolume: String?,
        fileBatchSize: Int
    ) {
        self.children = children
        self.resourceKeys = resourceKeys
        self.assumedVolume = assumedVolume
        self.fileBatchSize = max(1, fileBatchSize)
        pendingFiles.reserveCapacity(self.fileBatchSize)
    }

    mutating func next() -> StorageScanUnit? {
        if let pendingDirectory {
            self.pendingDirectory = nil
            return StorageScanUnit(items: [pendingDirectory])
        }
        while nextIndex < children.count {
            if Task.isCancelled { return nil }
            let index = nextIndex
            let child = children[index]
            nextIndex += 1
            let metadata = (try? child.resourceValues(forKeys: resourceKeys)).map {
                StorageChildMetadata(values: $0, assumingVolume: assumedVolume)
            }
            let indexedURL = StorageIndexedURL(index: index, url: child, metadata: metadata)
            if metadata?.isDirectory == false {
                pendingFiles.append(indexedURL)
                if pendingFiles.count == fileBatchSize { return takePendingFiles() }
            } else {
                if !pendingFiles.isEmpty {
                    pendingDirectory = indexedURL
                    return takePendingFiles()
                }
                return StorageScanUnit(items: [indexedURL])
            }
        }
        return takePendingFiles()
    }

    private mutating func takePendingFiles() -> StorageScanUnit? {
        guard !pendingFiles.isEmpty else { return nil }
        let unit = StorageScanUnit(items: pendingFiles)
        pendingFiles.removeAll(keepingCapacity: true)
        return unit
    }
}

private struct StorageFingerprint: Hashable, Sendable {
    let size: Int64
    let digest: Data

    var serialized: String { "\(size):\(digest.base64EncodedString())" }
}

private enum StorageHashMode: Equatable, Sendable {
    case sample
    case full
}

private struct StorageHashOutcome: Sendable {
    let candidate: StorageFileCandidate
    let digest: Data?
    let issue: StorageScanIssue?
}

private struct StorageHashBatchResult: Sendable {
    var groups: [StorageFingerprint: [StorageFileCandidate]] = [:]
    var issues: [StorageScanIssue] = []
}

private enum StorageScannerError: LocalizedError {
    case cannotRead(URL, String)

    var errorDescription: String? {
        switch self {
        case let .cannotRead(url, message): return "Could not scan \(url.path): \(message)"
        }
    }
}

private enum StorageScanner {
    private static let maximumConcurrentDirectories = 2
    private static let maximumConcurrentHashes = 2
    private static let directFileBatchSize = 128
    private static let hashSampleSize = 128 * 1_024
    private static let minimumDuplicateFileSize: Int64 = 1_048_576
    private static let progressUpdateInterval: TimeInterval = 0.1
    private static let maximumInsightsPerCategoryPerChild = 32
    private static let maximumInsightsPerCategory = 200
    private static let maximumIssues = 100
    private static let basicResourceKeys: Set<URLResourceKey> = [
        .isDirectoryKey,
        .isSymbolicLinkKey,
        .isPackageKey,
        .fileSizeKey,
        .totalFileAllocatedSizeKey,
        .contentModificationDateKey,
        .fileResourceIdentifierKey,
        .linkCountKey
    ]
    private static let volumeResourceKeys: Set<URLResourceKey> = [
        .volumeIdentifierKey,
        .volumeURLKey
    ]

    private static var childResourceKeys: Set<URLResourceKey> {
        basicResourceKeys.union(volumeResourceKeys)
    }

    static func scan(
        request: StorageScanRequest,
        progress: @escaping @Sendable (StorageScanProgress) async -> Void
    ) async throws -> StorageDirectorySnapshot {
        try Task.checkCancellation()
        let startedAt = ProcessInfo.processInfo.systemUptime
        let oldFileCutoff = Calendar.current.date(byAdding: .year, value: -1, to: Date()) ?? .distantPast
        let fileManager = FileManager.default
        let root = request.url.standardizedFileURL
        let rootValues: URLResourceValues
        do {
            rootValues = try root.resourceValues(forKeys: childResourceKeys)
        } catch {
            throw StorageScannerError.cannotRead(root, error.localizedDescription)
        }
        guard rootValues.isDirectory == true else {
            throw StorageScannerError.cannotRead(root, "The selected location is not a folder.")
        }

        let children: [URL]
        do {
            children = try fileManager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: Array(childResourceKeys),
                options: []
            )
        } catch {
            throw StorageScannerError.cannotRead(root, error.localizedDescription)
        }

        let rootVolume = StorageFileIdentity.volumeIdentifier(from: rootValues)
        let rootVolumeURL = rootValues.volume?.standardizedFileURL
        let rootIdentityVolume = StorageFileIdentity.identityVolume(from: rootValues)
        let rootIdentity = StorageFileIdentity.read(
            from: rootValues,
            assumingVolume: rootIdentityVolume
        )
        let ancestorIdentities = Set([rootIdentity].compactMap { $0 })
        let nestedMountPaths = DirectorySize.nestedMountPaths(inside: root)
        let hardLinkRegistry = StorageHardLinkRegistry()
        var results = Array<StorageChildScanResult?>(repeating: nil, count: children.count)
        var insightAccumulator = StorageInsightAccumulator()
        var recursiveCategorySizes: [StorageCategory: Int64] = [:]
        var singletonCandidates: [Int64: StorageFileCandidate] = [:]
        var candidateBuckets: [Int64: [StorageFileCandidate]] = [:]
        var seenCandidateIdentities = Set<StoragePOSIXFileIdentity>()
        var scanIssues: [StorageScanIssue] = []
        scanIssues.reserveCapacity(maximumIssues)
        var cancelled = false

        await progress(StorageScanProgress(
            state: .scanning,
            fraction: children.isEmpty ? 0.78 : 0,
            label: children.isEmpty
                ? "No items to inspect"
                : (request.deepScan
                    ? "Deep scanning \(children.count) items…"
                    : "Surface scanning \(children.count) items…")
        ))

        let targetFileUnitCount = min(maximumConcurrentDirectories, max(1, children.count))
        let fileBatchSize = min(
            directFileBatchSize,
            max(1, (children.count + targetFileUnitCount - 1) / targetFileUnitCount)
        )
        var unitProducer = StorageScanUnitProducer(
            children: children,
            resourceKeys: childResourceKeys,
            assumedVolume: rootIdentityVolume,
            fileBatchSize: fileBatchSize
        )
        await withTaskGroup(of: [StorageChildScanResult].self) { group in
            for _ in 0..<maximumConcurrentDirectories {
                guard let unit = unitProducer.next() else { break }
                group.addTask {
                    scanUnit(
                        unit,
                        rootVolume: rootVolume,
                        rootVolumeURL: rootVolumeURL,
                        rootIdentityVolume: rootIdentityVolume,
                        ancestorIdentities: ancestorIdentities,
                        nestedMountPaths: nestedMountPaths,
                        oldFileCutoff: oldFileCutoff,
                        hardLinkRegistry: hardLinkRegistry,
                        recursive: request.deepScan,
                        collectCandidates: request.deepScan
                    )
                }
            }

            var completed = 0
            var lastProgressAt = ProcessInfo.processInfo.systemUptime
            while let unitResults = await group.next() {
                if Task.isCancelled || unitResults.contains(where: \.wasCancelled) {
                    cancelled = true
                    group.cancelAll()
                    break
                }

                if let unit = unitProducer.next() {
                    group.addTask {
                        scanUnit(
                            unit,
                            rootVolume: rootVolume,
                            rootVolumeURL: rootVolumeURL,
                            rootIdentityVolume: rootIdentityVolume,
                            ancestorIdentities: ancestorIdentities,
                            nestedMountPaths: nestedMountPaths,
                            oldFileCutoff: oldFileCutoff,
                            hardLinkRegistry: hardLinkRegistry,
                            recursive: request.deepScan,
                            collectCandidates: request.deepScan
                        )
                    }
                }

                for result in unitResults {
                    for failure in result.failures.prefix(maximumIssues - scanIssues.count) {
                        scanIssues.append(StorageScanIssue(url: failure.url, message: failure.message))
                    }
                    insightAccumulator.merge(
                        result.insightEntries,
                        limitPerCategory: maximumInsightsPerCategory
                    )
                    for (category, bytes) in result.categorySizes {
                        recursiveCategorySizes[category] = saturatingAdd(
                            recursiveCategorySizes[category, default: 0],
                            bytes
                        )
                    }
                    if request.deepScan {
                        for candidate in result.candidates {
                            if !seenCandidateIdentities.insert(candidate.identity).inserted {
                                continue
                            }
                            if candidateBuckets[candidate.logicalSize] != nil {
                                candidateBuckets[candidate.logicalSize, default: []].append(candidate)
                            } else if let firstCandidate = singletonCandidates.removeValue(
                                forKey: candidate.logicalSize
                            ) {
                                candidateBuckets[candidate.logicalSize] = [firstCandidate, candidate]
                            } else {
                                singletonCandidates[candidate.logicalSize] = candidate
                            }
                        }
                    }
                    results[result.index] = result.droppingTransientCollections()
                }
                completed += unitResults.count
                let now = ProcessInfo.processInfo.systemUptime
                if completed == children.count || now - lastProgressAt >= progressUpdateInterval {
                    lastProgressAt = now
                    await progress(StorageScanProgress(
                        state: .scanning,
                        fraction: children.isEmpty ? 0.78 : 0.78 * Double(completed) / Double(children.count),
                        label: "\(request.deepScan ? "Deep scanned" : "Surface scanned") \(completed) of \(children.count) items"
                    ))
                }
            }
        }

        if cancelled { throw CancellationError() }
        try Task.checkCancellation()

        let completedResults = results.compactMap { $0 }
        var entries = completedResults.compactMap(\.entry)
        var issues = scanIssues
        let duplicateGroups: [StorageDuplicateGroup]
        if request.deepScan {
            singletonCandidates.removeAll(keepingCapacity: false)
            let duplicateResult = try await detectDuplicates(sizeBuckets: &candidateBuckets, progress: progress)
            duplicateGroups = duplicateResult.groups
            issues.append(contentsOf: duplicateResult.issues.prefix(maximumIssues - issues.count))
            let directEntryURLs = Set(entries.lazy
                .filter { !$0.isDirectory }
                .map { $0.url.standardizedFileURL })
            var duplicateMetadata: [URL: (fingerprint: String, groupID: String)] = [:]
            duplicateMetadata.reserveCapacity(directEntryURLs.count)
            for group in duplicateGroups {
                for entry in group.entries {
                    let entryURL = entry.url.standardizedFileURL
                    guard directEntryURLs.contains(entryURL) else { continue }
                    duplicateMetadata[entryURL] = (
                        group.fingerprint,
                        group.id
                    )
                }
            }
            for index in entries.indices where !entries[index].isDirectory {
                if let duplicate = duplicateMetadata[entries[index].url.standardizedFileURL] {
                    entries[index].isDuplicate = true
                    entries[index].contentHash = duplicate.0
                }
            }
        } else {
            duplicateGroups = []
        }

        entries.sort {
            if $0.size == $1.size {
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            return $0.size > $1.size
        }
        let insightEntries = insightAccumulator.entries.map { entry -> StorageEntry in
            var enriched = entry
            enriched.isSystemProtected = StorageDeletionPolicy.isProtectedDuringScan(entry.url)
            if enriched.resourceIdentifier == nil {
                enriched.resourceIdentifier = StorageFileIdentity.read(at: entry.url)?.serialized
            }
            return enriched
        }
        let categorySizes = recursiveCategorySizes
        let recommendations = StorageViewModel.generateRecommendations(
            from: insightEntries,
            duplicateGroups: duplicateGroups
        )
        let reclaimableBytes = reclaimableSpace(
            categorySizes: categorySizes,
            duplicateGroups: duplicateGroups
        )
        let duration = max(0, ProcessInfo.processInfo.systemUptime - startedAt)
        let metrics = StorageScanMetrics(
            childCount: children.count,
            filesVisited: completedResults.reduce(0) { $0 + $1.filesVisited },
            directoriesVisited: completedResults.reduce(0) { $0 + $1.directoriesVisited },
            logicalBytesVisited: completedResults.reduce(Int64(0)) { saturatingAdd($0, $1.logicalBytesVisited) },
            allocatedBytesVisited: completedResults.reduce(Int64(0)) { saturatingAdd($0, $1.allocatedBytesVisited) },
            duplicateFileCount: duplicateGroups.reduce(0) { $0 + $1.entries.count },
            duration: duration,
            cacheHit: false
        )
        return StorageDirectorySnapshot(
            url: root,
            entries: entries,
            insightEntries: insightEntries,
            recommendations: recommendations,
            duplicateGroups: duplicateGroups,
            categorySizes: categorySizes,
            reclaimableBytes: reclaimableBytes,
            issues: issues,
            metrics: metrics
        )
    }

    private static func scanUnit(
        _ unit: StorageScanUnit,
        rootVolume: String?,
        rootVolumeURL: URL?,
        rootIdentityVolume: String?,
        ancestorIdentities: Set<StorageFileIdentity>,
        nestedMountPaths: Set<String>,
        oldFileCutoff: Date,
        hardLinkRegistry: StorageHardLinkRegistry,
        recursive: Bool,
        collectCandidates: Bool
    ) -> [StorageChildScanResult] {
        var unitResults: [StorageChildScanResult] = []
        unitResults.reserveCapacity(unit.items.count)
        for item in unit.items {
            if Task.isCancelled {
                unitResults.append(cancelledResult(index: item.index))
                break
            }
            unitResults.append(scanChild(
                item.url,
                index: item.index,
                prefetchedMetadata: item.metadata,
                rootVolume: rootVolume,
                rootVolumeURL: rootVolumeURL,
                rootIdentityVolume: rootIdentityVolume,
                ancestorIdentities: ancestorIdentities,
                nestedMountPaths: nestedMountPaths,
                oldFileCutoff: oldFileCutoff,
                hardLinkRegistry: hardLinkRegistry,
                recursive: recursive,
                collectCandidates: collectCandidates
            ))
        }
        return unitResults
    }

    private static func scanChild(
        _ child: URL,
        index: Int,
        prefetchedMetadata: StorageChildMetadata?,
        rootVolume: String?,
        rootVolumeURL: URL?,
        rootIdentityVolume: String?,
        ancestorIdentities: Set<StorageFileIdentity>,
        nestedMountPaths: Set<String>,
        oldFileCutoff: Date,
        hardLinkRegistry: StorageHardLinkRegistry,
        recursive: Bool,
        collectCandidates: Bool
    ) -> StorageChildScanResult {
        if Task.isCancelled { return cancelledResult(index: index) }
        let fileManager = FileManager.default
        do {
            let metadata: StorageChildMetadata
            if let prefetchedMetadata {
                metadata = prefetchedMetadata
            } else {
                metadata = StorageChildMetadata(
                    values: try child.resourceValues(forKeys: childResourceKeys),
                    assumingVolume: rootIdentityVolume
                )
            }
            let isDirectory = metadata.isDirectory
            let isSymbolicLink = metadata.isSymbolicLink
            let identity = metadata.identity
            let logical = metadata.logicalSize
            let allocated = metadata.allocatedSize
            var failures: [DirectoryScanFailure] = []
            var candidates: [StorageFileCandidate] = []
            var categorySizes: [StorageCategory: Int64] = [:]
            var insightEntries: [StorageEntry] = []
            var size = allocated
            var logicalSize = logical
            var filesVisited = isDirectory ? 0 : 1
            var directoriesVisited = isDirectory ? 1 : 0

            let isOtherVolume = nestedMountPaths.contains(child.standardizedFileURL.path)
            let isRepeatedHardLink: Bool
            if !isDirectory,
               !isSymbolicLink,
               !isOtherVolume,
               metadata.linkCount > 1,
               let hardLinkIdentity = StoragePOSIXFileIdentity.read(at: child) {
                isRepeatedHardLink = !hardLinkRegistry.shouldCount(hardLinkIdentity)
            } else {
                isRepeatedHardLink = false
            }

            if isRepeatedHardLink {
                size = 0
                logicalSize = 0
                filesVisited = 0
            }
            if isDirectory, !isSymbolicLink, !isOtherVolume, recursive {
                let measurement = DirectorySize.measure(
                    child,
                    using: fileManager,
                    preferAllocated: true,
                    rootVolumeIdentifier: rootVolume,
                    rootVolumeURL: rootVolumeURL,
                    ancestorDirectoryIdentities: ancestorIdentities,
                    collectCandidates: collectCandidates,
                    minimumCandidateSize: minimumDuplicateFileSize,
                    insightLimitPerCategory: maximumInsightsPerCategoryPerChild,
                    hardLinkRegistry: hardLinkRegistry,
                    isCancelled: { Task.isCancelled }
                )
                if measurement.wasCancelled { return cancelledResult(index: index) }
                size = measurement.bytes
                logicalSize = measurement.logicalBytes
                filesVisited = measurement.filesVisited
                directoriesVisited = measurement.directoriesVisited + 1
                failures = measurement.failures
                candidates = measurement.candidates
                categorySizes = measurement.categorySizes
                insightEntries = measurement.insightEntries
            } else if isDirectory, !isSymbolicLink, !isOtherVolume {
                size = 0
                logicalSize = 0
            } else if isDirectory, isOtherVolume {
                size = 0
                logicalSize = 0
                failures.append(DirectoryScanFailure(
                    url: child,
                    message: "Skipped a mounted volume. Scan that volume directly to include it."
                ))
            } else if collectCandidates,
                      !isSymbolicLink,
                      metadata.linkCount <= 1,
                      logical >= minimumDuplicateFileSize,
                      let candidateIdentity = StoragePOSIXFileIdentity.read(at: child) {
                candidates = [StorageFileCandidate(
                    url: child,
                    logicalSize: logical,
                    allocatedSize: allocated,
                    lastModified: metadata.lastModified,
                    identity: candidateIdentity
                )]
            }

            var entry = StorageEntry(url: child, size: size, isDirectory: isDirectory)
            entry.logicalSize = logicalSize
            entry.isPackage = metadata.isPackage
            entry.isSymbolicLink = isSymbolicLink
            entry.lastModified = metadata.lastModified
            entry.fileType = child.pathExtension.isEmpty ? nil : child.pathExtension.lowercased()
            entry.resourceIdentifier = identity?.serialized
            entry.category = StorageViewModel.categorize(
                url: child,
                size: size,
                isDirectory: isDirectory,
                lastModified: metadata.lastModified
            )
            if !isDirectory, !isSymbolicLink {
                let facets = StorageViewModel.fileFacets(
                    size: size,
                    lastModified: metadata.lastModified,
                    oldFileCutoff: oldFileCutoff
                )
                entry.isLargeFile = facets.isLargeFile
                entry.isOldFile = facets.isOldFile
            }
            entry.isSystemProtected = StorageViewModel.isSystemProtected(url: child)
            if isOtherVolume { entry.scanWarning = "Mounted volume not included" }
            if isSymbolicLink { entry.scanWarning = "Symbolic link target not followed" }
            if isRepeatedHardLink { entry.scanWarning = "Hard-linked data already accounted elsewhere" }
            if isDirectory, !isSymbolicLink, !isOtherVolume, !recursive {
                entry.scanWarning = "Folder contents not measured in Surface Scan"
            }
            if let firstFailure = failures.first { entry.scanWarning = firstFailure.message }

            if !isDirectory {
                categorySizes[entry.category] = saturatingAdd(categorySizes[entry.category, default: 0], size)
                if !isRepeatedHardLink {
                    var directInsightAccumulator = StorageInsightAccumulator()
                    directInsightAccumulator.merge(insightEntries, limitPerCategory: maximumInsightsPerCategoryPerChild)
                    directInsightAccumulator.consider(entry, limitPerCategory: maximumInsightsPerCategoryPerChild)
                    insightEntries = directInsightAccumulator.entries
                }
            } else if isSymbolicLink {
                categorySizes[entry.category] = saturatingAdd(categorySizes[entry.category, default: 0], size)
            }

            return StorageChildScanResult(
                index: index,
                entry: entry,
                candidates: candidates,
                categorySizes: categorySizes,
                insightEntries: insightEntries,
                failures: failures,
                filesVisited: filesVisited,
                directoriesVisited: directoriesVisited,
                logicalBytesVisited: logicalSize,
                allocatedBytesVisited: size,
                wasCancelled: false
            )
        } catch {
            return StorageChildScanResult(
                index: index,
                entry: nil,
                candidates: [],
                categorySizes: [:],
                insightEntries: [],
                failures: [DirectoryScanFailure(url: child, message: error.localizedDescription)],
                filesVisited: 0,
                directoriesVisited: 0,
                logicalBytesVisited: 0,
                allocatedBytesVisited: 0,
                wasCancelled: Task.isCancelled
            )
        }
    }

    private static func cancelledResult(index: Int) -> StorageChildScanResult {
        StorageChildScanResult(
            index: index,
            entry: nil,
            candidates: [],
            categorySizes: [:],
            insightEntries: [],
            failures: [],
            filesVisited: 0,
            directoriesVisited: 0,
            logicalBytesVisited: 0,
            allocatedBytesVisited: 0,
            wasCancelled: true
        )
    }

    private static func detectDuplicates(
        sizeBuckets: inout [Int64: [StorageFileCandidate]],
        progress: @escaping @Sendable (StorageScanProgress) async -> Void
    ) async throws -> (groups: [StorageDuplicateGroup], issues: [StorageScanIssue]) {
        var sampleCandidates: [StorageFileCandidate] = []
        sampleCandidates.reserveCapacity(sizeBuckets.values.reduce(0) { partial, candidates in
            candidates.count > 1 ? partial + candidates.count : partial
        })
        for size in Array(sizeBuckets.keys) {
            guard let candidates = sizeBuckets.removeValue(forKey: size),
                  candidates.count > 1 else { continue }
            sampleCandidates.append(contentsOf: candidates)
        }
        sizeBuckets.removeAll(keepingCapacity: false)
        guard !sampleCandidates.isEmpty else {
            await progress(StorageScanProgress(state: .hashingDuplicates, fraction: 0.99, label: "No duplicate candidates"))
            return ([], [])
        }

        await progress(StorageScanProgress(
            state: .hashingDuplicates,
            fraction: 0.78,
            label: "Screening \(sampleCandidates.count) duplicate candidates…"
        ))

        var sampleBatch = try await hashCandidates(
            &sampleCandidates,
            mode: .sample,
            fractionStart: 0.78,
            fractionEnd: 0.86,
            progressVerb: "Screened",
            progress: progress
        )
        var issues = sampleBatch.issues

        var verifiedGroups: [StorageFingerprint: [StorageFileCandidate]] = [:]
        var fullHashCandidates: [StorageFileCandidate] = []
        for fingerprint in Array(sampleBatch.groups.keys) {
            guard let candidates = sampleBatch.groups.removeValue(forKey: fingerprint),
                  candidates.count > 1 else { continue }
            if fingerprint.size <= Int64(hashSampleSize * 2) {
                verifiedGroups[fingerprint] = candidates
            } else {
                fullHashCandidates.append(contentsOf: candidates)
            }
        }

        if !fullHashCandidates.isEmpty {
            var fullBatch = try await hashCandidates(
                &fullHashCandidates,
                mode: .full,
                fractionStart: 0.86,
                fractionEnd: 0.99,
                progressVerb: "Verified",
                progress: progress
            )
            issues.append(contentsOf: fullBatch.issues.prefix(maximumIssues - issues.count))
            for fingerprint in Array(fullBatch.groups.keys) {
                guard let candidates = fullBatch.groups.removeValue(forKey: fingerprint) else { continue }
                verifiedGroups[fingerprint] = candidates
            }
        } else {
            await progress(StorageScanProgress(
                state: .hashingDuplicates,
                fraction: 0.99,
                label: "Duplicate verification complete"
            ))
        }

        let oldFileCutoff = Calendar.current.date(byAdding: .year, value: -1, to: Date()) ?? .distantPast
        var duplicateGroups: [StorageDuplicateGroup] = []
        duplicateGroups.reserveCapacity(verifiedGroups.count)
        for fingerprint in Array(verifiedGroups.keys) {
            guard let candidates = verifiedGroups.removeValue(forKey: fingerprint),
                  candidates.count > 1 else { continue }
            let serializedFingerprint = fingerprint.serialized
            var entries = candidates.map { candidate -> StorageEntry in
                var entry = StorageEntry(url: candidate.url, size: candidate.allocatedSize, isDirectory: false)
                entry.logicalSize = candidate.logicalSize
                entry.lastModified = candidate.lastModified
                entry.fileType = candidate.url.pathExtension.isEmpty
                    ? nil
                    : candidate.url.pathExtension.lowercased()
                entry.category = .duplicates
                let facets = StorageViewModel.fileFacets(
                    size: candidate.allocatedSize,
                    lastModified: candidate.lastModified,
                    oldFileCutoff: oldFileCutoff
                )
                entry.isLargeFile = facets.isLargeFile
                entry.isOldFile = facets.isOldFile
                entry.isDuplicate = true
                entry.isSystemProtected = StorageDeletionPolicy.isProtectedDuringScan(candidate.url)
                entry.resourceIdentifier = candidate.identity.serialized
                entry.contentHash = serializedFingerprint
                return entry
            }
            entries.sort {
                if $0.isSystemProtected != $1.isSystemProtected {
                    return $0.isSystemProtected
                }
                return $0.url.path.localizedStandardCompare($1.url.path) == .orderedAscending
            }
            let reclaimable = entries.dropFirst()
                .filter { !$0.isSystemProtected }
                .reduce(Int64(0)) { saturatingAdd($0, $1.size) }
            duplicateGroups.append(StorageDuplicateGroup(
                id: serializedFingerprint,
                fingerprint: serializedFingerprint,
                logicalFileSize: fingerprint.size,
                entries: entries,
                reclaimableBytes: reclaimable
            ))
        }
        duplicateGroups.sort { $0.reclaimableBytes > $1.reclaimableBytes }
        return (duplicateGroups, issues)
    }

    private static func hashCandidates(
        _ candidates: inout [StorageFileCandidate],
        mode: StorageHashMode,
        fractionStart: Double,
        fractionEnd: Double,
        progressVerb: String,
        progress: @escaping @Sendable (StorageScanProgress) async -> Void
    ) async throws -> StorageHashBatchResult {
        guard !candidates.isEmpty else { return StorageHashBatchResult() }
        let totalCount = candidates.count
        var result = StorageHashBatchResult()
        result.issues.reserveCapacity(min(maximumIssues, totalCount))
        var singletonMatches: [StorageFingerprint: StorageFileCandidate] = [:]
        var cancelled = false
        await withTaskGroup(of: StorageHashOutcome.self) { group in
            let initialCount = min(maximumConcurrentHashes, totalCount)
            for _ in 0..<initialCount {
                guard let candidate = candidates.popLast() else { break }
                if candidates.isEmpty { candidates.removeAll(keepingCapacity: false) }
                group.addTask { hash(candidate: candidate, mode: mode) }
            }

            var completed = 0
            var lastProgressAt = ProcessInfo.processInfo.systemUptime
            while let outcome = await group.next() {
                if Task.isCancelled {
                    cancelled = true
                    group.cancelAll()
                    break
                }
                completed += 1
                if let digest = outcome.digest {
                    let fingerprint = StorageFingerprint(
                        size: outcome.candidate.logicalSize,
                        digest: digest
                    )
                    if result.groups[fingerprint] != nil {
                        result.groups[fingerprint, default: []].append(outcome.candidate)
                    } else if let firstCandidate = singletonMatches.removeValue(forKey: fingerprint) {
                        result.groups[fingerprint] = [firstCandidate, outcome.candidate]
                    } else {
                        singletonMatches[fingerprint] = outcome.candidate
                    }
                }
                if let issue = outcome.issue, result.issues.count < maximumIssues {
                    result.issues.append(issue)
                }
                if let candidate = candidates.popLast() {
                    if candidates.isEmpty { candidates.removeAll(keepingCapacity: false) }
                    group.addTask { hash(candidate: candidate, mode: mode) }
                }

                let now = ProcessInfo.processInfo.systemUptime
                if completed == totalCount || now - lastProgressAt >= progressUpdateInterval {
                    lastProgressAt = now
                    let fraction = fractionStart
                        + (fractionEnd - fractionStart) * Double(completed) / Double(totalCount)
                    await progress(StorageScanProgress(
                        state: .hashingDuplicates,
                        fraction: fraction,
                        label: "\(progressVerb) \(completed) of \(totalCount) files"
                    ))
                }
            }
        }
        if cancelled { throw CancellationError() }
        try Task.checkCancellation()
        candidates.removeAll(keepingCapacity: false)
        return result
    }

    private static func hash(candidate: StorageFileCandidate, mode: StorageHashMode) -> StorageHashOutcome {
        do {
            try Task.checkCancellation()
            let eligibilityValues = try candidate.url.resourceValues(forKeys: [
                .linkCountKey,
                .isUbiquitousItemKey,
                .ubiquitousItemDownloadingStatusKey
            ])
            let isPlaceholder = eligibilityValues.isUbiquitousItem == true
                && eligibilityValues.ubiquitousItemDownloadingStatus != .current
            guard (eligibilityValues.linkCount ?? 1) <= 1, !isPlaceholder else {
                return StorageHashOutcome(candidate: candidate, digest: nil, issue: nil)
            }

            let handle = try FileHandle(forReadingFrom: candidate.url)
            defer { try? handle.close() }
            var openedMetadata = stat()
            guard fstat(handle.fileDescriptor, &openedMetadata) == 0,
                  StoragePOSIXFileIdentity(openedMetadata) == candidate.identity else {
                throw fileChangedError("The file was replaced before it could be verified.")
            }
            var hasher = SHA256()
            let bytesRead: Int64
            switch mode {
            case .full:
                bytesRead = try update(&hasher, from: handle, byteLimit: nil)
            case .sample:
                if candidate.logicalSize <= Int64(hashSampleSize * 2) {
                    bytesRead = try update(&hasher, from: handle, byteLimit: nil)
                } else {
                    let prefixBytes = try update(
                        &hasher,
                        from: handle,
                        byteLimit: Int64(hashSampleSize)
                    )
                    try handle.seek(toOffset: UInt64(candidate.logicalSize - Int64(hashSampleSize)))
                    let suffixBytes = try update(
                        &hasher,
                        from: handle,
                        byteLimit: Int64(hashSampleSize)
                    )
                    bytesRead = prefixBytes + suffixBytes
                    guard bytesRead == Int64(hashSampleSize * 2) else {
                        throw CocoaError(.fileReadUnknown, userInfo: [
                            NSLocalizedDescriptionKey: "The file changed while it was being screened."
                        ])
                    }
                }
            }
            try Task.checkCancellation()
            if mode == .full || candidate.logicalSize <= Int64(hashSampleSize * 2),
               bytesRead != candidate.logicalSize {
                throw CocoaError(.fileReadUnknown, userInfo: [
                    NSLocalizedDescriptionKey: "The file changed while it was being verified."
                ])
            }
            let finalValues = try candidate.url.resourceValues(forKeys: [
                .isSymbolicLinkKey,
                .fileSizeKey,
                .contentModificationDateKey,
                .linkCountKey,
                .isUbiquitousItemKey,
                .ubiquitousItemDownloadingStatusKey
            ])
            let finalIsPlaceholder = finalValues.isUbiquitousItem == true
                && finalValues.ubiquitousItemDownloadingStatus != .current
            guard (finalValues.linkCount ?? 1) <= 1, !finalIsPlaceholder else {
                return StorageHashOutcome(candidate: candidate, digest: nil, issue: nil)
            }
            if StoragePOSIXFileIdentity.read(at: candidate.url) != candidate.identity {
                throw fileChangedError("The file was replaced while it was being verified.")
            }
            if finalValues.isSymbolicLink == true
                || Int64(finalValues.fileSize ?? -1) != candidate.logicalSize
                || (candidate.lastModified != nil && finalValues.contentModificationDate != candidate.lastModified) {
                throw CocoaError(.fileReadUnknown, userInfo: [
                    NSLocalizedDescriptionKey: "The file changed while it was being verified."
                ])
            }
            return StorageHashOutcome(candidate: candidate, digest: Data(hasher.finalize()), issue: nil)
        } catch is CancellationError {
            return StorageHashOutcome(candidate: candidate, digest: nil, issue: nil)
        } catch {
            return StorageHashOutcome(
                candidate: candidate,
                digest: nil,
                issue: StorageScanIssue(url: candidate.url, message: error.localizedDescription)
            )
        }
    }

    private static func update(
        _ hasher: inout SHA256,
        from handle: FileHandle,
        byteLimit: Int64?
    ) throws -> Int64 {
        var totalRead: Int64 = 0
        while byteLimit.map({ totalRead < $0 }) ?? true {
            try Task.checkCancellation()
            let remaining = byteLimit.map { max(0, $0 - totalRead) } ?? 1_048_576
            let requestSize = Int(min(1_048_576, remaining))
            guard requestSize > 0,
                  let data = try handle.read(upToCount: requestSize),
                  !data.isEmpty else { break }
            hasher.update(data: data)
            totalRead += Int64(data.count)
        }
        return totalRead
    }

    private static func fileChangedError(_ description: String) -> CocoaError {
        CocoaError(.fileReadUnknown, userInfo: [NSLocalizedDescriptionKey: description])
    }

    private static func reclaimableSpace(
        categorySizes: [StorageCategory: Int64],
        duplicateGroups: [StorageDuplicateGroup]
    ) -> Int64 {
        var total = saturatingAdd(
            categorySizes[.caches, default: 0],
            categorySizes[.trash, default: 0]
        )
        for group in duplicateGroups {
            for duplicate in group.entries.dropFirst() {
                guard !duplicate.isSystemProtected else { continue }
                let baseCategory = StorageViewModel.categorize(
                    url: duplicate.url,
                    size: duplicate.size,
                    isDirectory: false,
                    lastModified: duplicate.lastModified
                )
                if baseCategory != .caches, baseCategory != .trash {
                    total = saturatingAdd(total, duplicate.size)
                }
            }
        }
        return total
    }

    private static func saturatingAdd(_ lhs: Int64, _ rhs: Int64) -> Int64 {
        let (sum, overflow) = lhs.addingReportingOverflow(rhs)
        return overflow ? Int64.max : sum
    }
}

private actor StorageScanCoordinator {
    static let shared = StorageScanCoordinator()

    typealias ProgressHandler = @Sendable (StorageScanProgress) async -> Void

    struct Lease: Sendable {
        let key: StorageCacheKey
        let subscriberID: UUID
        let runID: UUID
        let task: Task<StorageDirectorySnapshot, Error>
        let isPrimary: Bool
    }

    private struct InFlight {
        let runID: UUID
        let task: Task<StorageDirectorySnapshot, Error>
        var subscribers: [UUID: ProgressHandler]
    }

    private var inFlight: [StorageCacheKey: InFlight] = [:]

    func acquire(
        request: StorageScanRequest,
        progress: @escaping ProgressHandler
    ) -> Lease {
        let key = StorageCacheKey(url: request.url, deepScan: request.deepScan)
        let subscriberID = UUID()
        if var existing = inFlight[key] {
            existing.subscribers[subscriberID] = progress
            inFlight[key] = existing
            return Lease(
                key: key,
                subscriberID: subscriberID,
                runID: existing.runID,
                task: existing.task,
                isPrimary: false
            )
        }

        let runID = UUID()
        let task = Task.detached(priority: .utility) {
            let snapshot = try await StorageScanner.scan(request: request) { update in
                await StorageScanCoordinator.shared.publish(update, for: key, runID: runID)
            }
            try Task.checkCancellation()
            await StorageSnapshotCache.shared.store(snapshot, for: key)
            return snapshot
        }
        inFlight[key] = InFlight(
            runID: runID,
            task: task,
            subscribers: [subscriberID: progress]
        )
        return Lease(
            key: key,
            subscriberID: subscriberID,
            runID: runID,
            task: task,
            isPrimary: true
        )
    }

    func release(_ lease: Lease) {
        guard var existing = inFlight[lease.key], existing.runID == lease.runID else { return }
        existing.subscribers.removeValue(forKey: lease.subscriberID)
        guard !existing.subscribers.isEmpty else {
            existing.task.cancel()
            inFlight.removeValue(forKey: lease.key)
            return
        }
        inFlight[lease.key] = existing
    }

    private func publish(
        _ progress: StorageScanProgress,
        for key: StorageCacheKey,
        runID: UUID
    ) async {
        guard let existing = inFlight[key], existing.runID == runID else { return }
        let subscribers = Array(existing.subscribers.values)
        for subscriber in subscribers {
            await subscriber(progress)
        }
    }
}

private enum StorageDeletionPolicy {
    private static let protectedHomeFolderNames: Set<String> = [
        "library", "desktop", "documents", "downloads", "movies",
        "music", "pictures", "public", "applications"
    ]

    static func rejectionReason(for entry: StorageEntry, within scope: URL) -> String? {
        if isTrashLocation(entry.url) {
            return "Sapphire does not permanently delete items that are already in Trash. Review or empty Trash in Finder."
        }
        if entry.isSystemProtected || isProtectedLocation(entry.url) {
            return "This is a protected location and can only be inspected."
        }
        let target = canonical(entry.url)
        let canonicalScope = canonical(scope)
        guard contains(canonicalScope, target) else {
            return "The item is outside the folder that was scanned."
        }
        guard FileManager.default.fileExists(atPath: target.path) else {
            return "The item no longer exists."
        }
        guard FileManager.default.isDeletableFile(atPath: target.path) else {
            return "macOS reports that this item cannot be moved to Trash."
        }
        return nil
    }

    static func revalidationReason(for entry: StorageEntry) -> String? {
        let keys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .isSymbolicLinkKey,
            .fileSizeKey,
            .totalFileAllocatedSizeKey,
            .contentModificationDateKey,
            .volumeIdentifierKey,
            .volumeURLKey,
            .fileResourceIdentifierKey
        ]
        let values: URLResourceValues
        do {
            values = try entry.url.resourceValues(forKeys: keys)
        } catch {
            return "The item could not be revalidated: \(error.localizedDescription)"
        }

        guard values.isDirectory == entry.isDirectory,
              values.isSymbolicLink == entry.isSymbolicLink else {
            return "The item type changed after the scan and it was not removed."
        }
        if let expectedIdentifier = entry.resourceIdentifier {
            let identityMatches: Bool
            if StoragePOSIXFileIdentity.recognizes(expectedIdentifier) {
                identityMatches = StoragePOSIXFileIdentity.read(at: entry.url)?.serialized
                    == expectedIdentifier
            } else {
                identityMatches = StorageFileIdentity.read(from: values)?.serialized
                    == expectedIdentifier
            }
            if !identityMatches {
                return "The item identity changed after the scan and it was not removed."
            }
        }
        guard let expectedModificationDate = entry.lastModified,
              values.contentModificationDate == expectedModificationDate else {
            return "The item was modified after the scan and it was not removed."
        }
        if entry.isDirectory, !entry.isSymbolicLink {
            let measurement = DirectorySize.measure(
                entry.url,
                using: FileManager.default,
                preferAllocated: true,
                rootVolumeIdentifier: StorageFileIdentity.volumeIdentifier(from: values),
                rootVolumeURL: values.volume?.standardizedFileURL,
                ancestorDirectoryIdentities: [],
                collectCandidates: false,
                insightLimitPerCategory: 0,
                isCancelled: { Task.isCancelled }
            )
            if measurement.wasCancelled { return "Removal was cancelled before the folder could be revalidated." }
            if let failure = measurement.failures.first {
                return "The folder could not be fully revalidated: \(failure.message)"
            }
            guard measurement.bytes == entry.size else {
                return "The folder contents changed after the scan and it was not removed."
            }
        } else {
            let logicalSize = Int64(max(0, values.fileSize ?? 0))
            let allocatedSize = Int64(max(0, values.totalFileAllocatedSize ?? values.fileSize ?? 0))
            guard logicalSize == entry.logicalSize, allocatedSize == entry.size else {
                return "The item size changed after the scan and it was not removed."
            }
        }
        return nil
    }

    static func isTrashLocation(_ url: URL) -> Bool {
        canonical(url).pathComponents.contains {
            let component = $0.lowercased()
            return component == ".trash" || component == ".trashes"
        }
    }

    static func isProtectedLocation(_ url: URL) -> Bool {
        let requested = url.standardizedFileURL
        let requestedHome = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL
        let target = canonical(url)
        let home = canonical(requestedHome)
        if target == home { return true }
        if isStandardHomeFolder(requested, home: requestedHome)
            || isStandardHomeFolder(target, home: home) {
            return true
        }
        if contains(home, target) { return false }

        let volumes = URL(fileURLWithPath: "/Volumes", isDirectory: true)
        if target == volumes { return true }
        if contains(volumes, target) {
            let volumeRoot = (try? target.resourceValues(forKeys: [.volumeURLKey]))?.volume.map(canonical)
            return volumeRoot == target
        }
        return true
    }

    static func isProtectedDuringScan(_ url: URL) -> Bool {
        let target = url.standardizedFileURL
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL
        if target == home || isStandardHomeFolder(target, home: home) { return true }
        if lexicallyContains(home, target) { return false }

        let volumes = URL(fileURLWithPath: "/Volumes", isDirectory: true).standardizedFileURL
        if target == volumes { return true }
        if lexicallyContains(volumes, target) {
            return target.pathComponents.count == volumes.pathComponents.count + 1
        }
        return true
    }

    private static func isStandardHomeFolder(_ candidate: URL, home: URL) -> Bool {
        let candidateComponents = candidate.standardizedFileURL.pathComponents.map { $0.lowercased() }
        let homeComponents = home.standardizedFileURL.pathComponents.map { $0.lowercased() }
        guard candidateComponents.count == homeComponents.count + 1,
              Array(candidateComponents.dropLast()) == homeComponents,
              let name = candidateComponents.last else { return false }
        return protectedHomeFolderNames.contains(name)
    }

    private static func lexicallyContains(_ parent: URL, _ child: URL) -> Bool {
        let parentComponents = parent.standardizedFileURL.pathComponents
        let childComponents = child.standardizedFileURL.pathComponents
        guard childComponents.count >= parentComponents.count else { return false }
        return childComponents.prefix(parentComponents.count).elementsEqual(parentComponents)
    }

    static func contains(_ parent: URL, _ child: URL) -> Bool {
        let parentComponents = canonical(parent).pathComponents
        let childComponents = canonical(child).pathComponents
        guard childComponents.count >= parentComponents.count else { return false }
        return Array(childComponents.prefix(parentComponents.count)) == parentComponents
    }

    private static func canonical(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath()
    }
}

private enum StorageDeletionWorker {
    static func moveToTrash(_ entries: [StorageEntry], within scope: URL) -> StorageRemovalResult {
        let fileManager = FileManager.default
        var removed: [URL] = []
        var failures: [StorageScanIssue] = []
        var bytesMoved: Int64 = 0

        for entry in entries {
            if Task.isCancelled { break }
            if let reason = StorageDeletionPolicy.rejectionReason(for: entry, within: scope) {
                failures.append(StorageScanIssue(url: entry.url, message: reason))
                continue
            }
            if let reason = StorageDeletionPolicy.revalidationReason(for: entry) {
                failures.append(StorageScanIssue(url: entry.url, message: reason))
                continue
            }
            do {
                try fileManager.trashItem(at: entry.url, resultingItemURL: nil)
                removed.append(entry.url)
                let (sum, overflow) = bytesMoved.addingReportingOverflow(entry.size)
                bytesMoved = overflow ? Int64.max : sum
            } catch {
                failures.append(StorageScanIssue(url: entry.url, message: error.localizedDescription))
            }
        }

        return StorageRemovalResult(
            removed: removed,
            failures: failures,
            bytesMovedToTrash: bytesMoved,
            completedAt: Date()
        )
    }
}

private struct StorageFileCandidate: Sendable {
    let url: URL
    let logicalSize: Int64
    let allocatedSize: Int64
    let lastModified: Date?
    let identity: StoragePOSIXFileIdentity
}

private struct DirectoryScanFailure: Sendable {
    let url: URL
    let message: String
}

enum DirectorySize {
    fileprivate struct Measurement: Sendable {
        var bytes: Int64 = 0
        var logicalBytes: Int64 = 0
        var categorySizes: [StorageCategory: Int64] = [:]
        var insightEntries: [StorageEntry] = []
        var filesVisited = 0
        var directoriesVisited = 0
        var candidates: [StorageFileCandidate] = []
        var failures: [DirectoryScanFailure] = []
        var wasCancelled = false
    }

    static func of(
        _ url: URL,
        using fileManager: FileManager = .default,
        preferAllocated: Bool,
        isCancelled: @escaping () -> Bool = { false }
    ) -> Int64 {
        let rootValues = try? url.resourceValues(forKeys: [.volumeIdentifierKey, .volumeURLKey])
        let measurement = measure(
            url,
            using: fileManager,
            preferAllocated: preferAllocated,
            rootVolumeIdentifier: rootValues.flatMap(StorageFileIdentity.volumeIdentifier(from:)),
            rootVolumeURL: rootValues?.volume?.standardizedFileURL,
            ancestorDirectoryIdentities: [],
            collectCandidates: false,
            insightLimitPerCategory: 0,
            isCancelled: isCancelled
        )
        return measurement.wasCancelled ? 0 : measurement.bytes
    }

    fileprivate static func measure(
        _ url: URL,
        using _: FileManager,
        preferAllocated: Bool,
        rootVolumeIdentifier _: String?,
        rootVolumeURL: URL?,
        ancestorDirectoryIdentities _: Set<StorageFileIdentity>,
        collectCandidates: Bool,
        minimumCandidateSize: Int64 = 1,
        insightLimitPerCategory: Int,
        hardLinkRegistry: StorageHardLinkRegistry? = nil,
        isCancelled: @escaping () -> Bool
    ) -> Measurement {
        let needsInsights = insightLimitPerCategory > 0
        let needsPackageMetadata = needsInsights || collectCandidates
        let needsAllocatedSize = preferAllocated || collectCandidates
        var measurement = Measurement()
        let hardLinkRegistry = hardLinkRegistry ?? StorageHardLinkRegistry()
        var insightAccumulator = StorageInsightAccumulator()
        let oldFileCutoff = Calendar.current.date(byAdding: .year, value: -1, to: Date()) ?? .distantPast
        let rootIsPackage = needsPackageMetadata
            && isPackageDirectory(at: url, name: url.lastPathComponent)
        let rootPathCategory = needsInsights ? StoragePathCategoryContext(url: url) : StoragePathCategoryContext()
        let rootPackageCategory: StorageCategory? = rootIsPackage
            ? (needsInsights
                ? rootPathCategory.category(itemName: url.lastPathComponent.lowercased(), isDirectory: true)
                : .other)
            : nil
        var traversalContexts = [StorageTraversalContext(
            pathCategory: rootPathCategory,
            packageCategory: rootPackageCategory
        )]

        guard let rootPath = url.withUnsafeFileSystemRepresentation({ path -> UnsafeMutablePointer<CChar>? in
            guard let path else { return nil }
            return strdup(path)
        }) else {
            measurement.failures.append(DirectoryScanFailure(
                url: url,
                message: "The folder path could not be represented by the file system."
            ))
            return measurement
        }
        defer { free(rootPath) }

        var rootMetadata = stat()
        guard lstat(rootPath, &rootMetadata) == 0 else {
            measurement.failures.append(DirectoryScanFailure(
                url: url,
                message: posixErrorMessage(errno)
            ))
            return measurement
        }

        let excludedMountPaths = sameDeviceMountPaths(
            inside: rootPath,
            fallbackRootVolumeURL: rootVolumeURL,
            rootDevice: rootMetadata.st_dev
        )

        var paths: [UnsafeMutablePointer<CChar>?] = [rootPath, nil]
        let stream = paths.withUnsafeMutableBufferPointer { buffer in
            fts_open(buffer.baseAddress, FTS_PHYSICAL | FTS_XDEV | FTS_NOCHDIR, nil)
        }
        guard let stream else {
            measurement.failures.append(DirectoryScanFailure(
                url: url,
                message: posixErrorMessage(errno)
            ))
            return measurement
        }
        defer { fts_close(stream) }

        while let item = fts_read(stream) {
            if isCancelled() {
                measurement.wasCancelled = true
                break
            }

            autoreleasepool {
                let info = item.pointee.fts_info
                if info == FTS_DP { return }

                if info == FTS_DNR || info == FTS_ERR || info == FTS_NS || info == FTS_DC {
                    if measurement.failures.count < 50 {
                        measurement.failures.append(DirectoryScanFailure(
                            url: fileURL(for: item, isDirectory: info == FTS_DNR || info == FTS_DC),
                            message: posixErrorMessage(item.pointee.fts_errno)
                        ))
                    }
                    if info == FTS_DC || info == FTS_DNR {
                        fts_set(stream, item, FTS_SKIP)
                    }
                    return
                }

                guard item.pointee.fts_level > 0,
                      let metadataPointer = item.pointee.fts_statp else { return }

                let metadata = metadataPointer.pointee
                let isDirectory = info == FTS_D
                let isSymbolicLink = info == FTS_SL || info == FTS_SLNONE
                let isRegularFile = info == FTS_F

                if isDirectory,
                   isExcludedMount(item.pointee.fts_path, paths: excludedMountPaths) {
                    fts_set(stream, item, FTS_SKIP)
                    return
                }

                if metadata.st_dev != rootMetadata.st_dev {
                    if isDirectory { fts_set(stream, item, FTS_SKIP) }
                    return
                }

                if !isDirectory, metadata.st_nlink > 1 {
                    let identity = StoragePOSIXFileIdentity(metadata)
                    guard hardLinkRegistry.shouldCount(identity) else { return }
                }

                let level = max(1, Int(item.pointee.fts_level))
                while traversalContexts.count > level { traversalContexts.removeLast() }
                let parentContext = traversalContexts.last ?? traversalContexts[0]
                let originalName = needsPackageMetadata ? itemName(for: item) : ""
                let lowercasedName = needsInsights ? originalName.lowercased() : ""
                let pathCategory = needsInsights
                    ? parentContext.pathCategory.appending(lowercasedName)
                    : parentContext.pathCategory
                var packageCategory = parentContext.packageCategory
                var isPackage = false

                if isDirectory {
                    measurement.directoriesVisited += 1
                    if packageCategory == nil,
                       needsPackageMetadata,
                       mayBePackage(name: originalName) {
                        let directoryURL = fileURL(for: item, isDirectory: true)
                        isPackage = isPackageDirectory(at: directoryURL, name: originalName)
                        if isPackage {
                            packageCategory = needsInsights
                                ? pathCategory.category(itemName: lowercasedName, isDirectory: true)
                                : .other
                        }
                    }
                    traversalContexts.append(StorageTraversalContext(
                        pathCategory: pathCategory,
                        packageCategory: packageCategory
                    ))
                } else {
                    measurement.filesVisited += 1
                }

                let logical = max(0, Int64(metadata.st_size))
                let allocated = needsAllocatedSize ? allocatedBytes(for: metadata) : logical
                let countedSize = preferAllocated ? allocated : logical
                measurement.logicalBytes = addingWithoutOverflow(measurement.logicalBytes, logical)
                measurement.bytes = addingWithoutOverflow(measurement.bytes, countedSize)
                let lastModified = needsInsights || collectCandidates
                    ? modificationDate(for: metadata)
                    : nil

                if needsInsights {
                    let isInspectableFile = packageCategory == nil && isRegularFile && !isSymbolicLink
                    let facets = isInspectableFile
                        ? StorageViewModel.fileFacets(
                            size: countedSize,
                            lastModified: lastModified,
                            oldFileCutoff: oldFileCutoff
                        )
                        : (isLargeFile: false, isOldFile: false)
                    let category = packageCategory
                        ?? pathCategory.category(itemName: lowercasedName, isDirectory: isDirectory)
                    measurement.categorySizes[category] = addingWithoutOverflow(
                        measurement.categorySizes[category, default: 0],
                        countedSize
                    )
                    if isInspectableFile,
                       StorageInsightAccumulator.shouldIndex(
                        category: category,
                        isLargeFile: facets.isLargeFile,
                        isOldFile: facets.isOldFile
                       ),
                       insightAccumulator.wouldAdmit(
                        category: category,
                        size: countedSize,
                        lastModified: lastModified,
                        isLargeFile: facets.isLargeFile,
                        isOldFile: facets.isOldFile,
                        limitPerCategory: insightLimitPerCategory
                       ) {
                        let itemURL = fileURL(for: item, isDirectory: false)
                        var insight = StorageEntry(url: itemURL, size: countedSize, isDirectory: false)
                        insight.logicalSize = logical
                        insight.isPackage = isPackage
                        insight.isSymbolicLink = isSymbolicLink
                        insight.category = category
                        insight.isLargeFile = facets.isLargeFile
                        insight.isOldFile = facets.isOldFile
                        insight.lastModified = lastModified
                        insight.fileType = pathExtension(of: originalName)
                        insightAccumulator.consider(insight, limitPerCategory: insightLimitPerCategory)
                    }
                }

                guard collectCandidates,
                      packageCategory == nil,
                      isRegularFile,
                      !isSymbolicLink,
                      metadata.st_nlink <= 1,
                      logical >= minimumCandidateSize else { return }
                measurement.candidates.append(StorageFileCandidate(
                    url: fileURL(for: item, isDirectory: false),
                    logicalSize: logical,
                    allocatedSize: allocated,
                    lastModified: lastModified,
                    identity: StoragePOSIXFileIdentity(metadata)
                ))
            }
        }

        if isCancelled() { measurement.wasCancelled = true }

        measurement.insightEntries = insightAccumulator.entries
        return measurement
    }

    fileprivate static func nestedMountPaths(inside rootURL: URL) -> Set<String> {
        let traversalRoot = rootURL.standardizedFileURL.path
        return Set(mountedFileSystemSnapshots().lazy.compactMap { fileSystem in
            let mountPath = mountPointPath(from: fileSystem)
            guard mountPath != traversalRoot,
                  isDescendantPath(mountPath, of: traversalRoot) else { return nil }
            return mountPath
        })
    }

    private static func sameDeviceMountPaths(
        inside rootPath: UnsafePointer<CChar>,
        fallbackRootVolumeURL: URL?,
        rootDevice: dev_t
    ) -> [String] {
        let traversalRoot = String(cString: rootPath)
        var rootFileSystem = statfs()
        let rootMountPath: String?
        if statfs(rootPath, &rootFileSystem) == 0 {
            rootMountPath = mountPointPath(from: rootFileSystem)
        } else {
            rootMountPath = fallbackRootVolumeURL?.standardizedFileURL.path
        }

        let mountedFileSystems = mountedFileSystemSnapshots()

        var paths: [String] = []
        for fileSystem in mountedFileSystems {
            let mountPath = mountPointPath(from: fileSystem)
            guard mountPath != rootMountPath,
                  mountPath != traversalRoot,
                  isDescendantPath(mountPath, of: traversalRoot) else { continue }

            var metadata = stat()
            let isSameDevice = mountPath.withCString { path in
                lstat(path, &metadata) == 0 && metadata.st_dev == rootDevice
            }
            if isSameDevice { paths.append(mountPath) }
        }
        return paths
    }

    private static func mountedFileSystemSnapshots() -> [statfs] {
        let mountCapacity = getfsstat(nil, 0, MNT_NOWAIT)
        guard mountCapacity > 0 else { return [] }
        let emptyFileSystem = statfs()
        var mountedFileSystems = Array(
            repeating: emptyFileSystem,
            count: Int(mountCapacity) + 4
        )
        let mountCount = mountedFileSystems.withUnsafeMutableBufferPointer { buffer in
            getfsstat(
                buffer.baseAddress,
                Int32(buffer.count * MemoryLayout.size(ofValue: emptyFileSystem)),
                MNT_NOWAIT
            )
        }
        guard mountCount > 0 else { return [] }
        return Array(mountedFileSystems.prefix(min(Int(mountCount), mountedFileSystems.count)))
    }

    private static func mountPointPath(from fileSystem: statfs) -> String {
        var mountName = fileSystem.f_mntonname
        return withUnsafePointer(to: &mountName) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: Int(MNAMELEN)) {
                String(cString: $0)
            }
        }
    }

    private static func isDescendantPath(_ candidate: String, of root: String) -> Bool {
        if root == "/" { return candidate.hasPrefix("/") && candidate != "/" }
        let prefix = root.hasSuffix("/") ? root : root + "/"
        return candidate.hasPrefix(prefix)
    }

    private static func isExcludedMount(
        _ candidate: UnsafePointer<CChar>,
        paths: [String]
    ) -> Bool {
        paths.contains { path in
            path.withCString { strcmp(candidate, $0) == 0 }
        }
    }

    private static func fileURL(
        for entry: UnsafeMutablePointer<FTSENT>,
        isDirectory: Bool
    ) -> URL {
        URL(
            fileURLWithFileSystemRepresentation: entry.pointee.fts_path,
            isDirectory: isDirectory,
            relativeTo: nil
        )
    }

    private static func itemName(for entry: UnsafeMutablePointer<FTSENT>) -> String {
        withUnsafePointer(to: &entry.pointee.fts_name) { pointer in
            pointer.withMemoryRebound(
                to: CChar.self,
                capacity: Int(entry.pointee.fts_namelen) + 1
            ) { String(cString: $0) }
        }
    }

    private static func mayBePackage(name: String) -> Bool {
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return false }
        return name.index(after: dot) < name.endIndex
    }

    private static func isPackageDirectory(at url: URL, name: String) -> Bool {
        guard mayBePackage(name: name) else { return false }
        return (try? url.resourceValues(forKeys: [.isPackageKey]))?.isPackage == true
    }

    private static func pathExtension(of name: String) -> String? {
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return nil }
        let start = name.index(after: dot)
        guard start < name.endIndex else { return nil }
        return String(name[start...]).lowercased()
    }

    private static func modificationDate(for metadata: stat) -> Date {
        let seconds = TimeInterval(metadata.st_mtimespec.tv_sec)
        let nanoseconds = TimeInterval(metadata.st_mtimespec.tv_nsec) / 1_000_000_000
        return Date(timeIntervalSince1970: seconds + nanoseconds)
    }

    private static func allocatedBytes(for metadata: stat) -> Int64 {
        let blocks = max(0, Int64(metadata.st_blocks))
        let (bytes, overflow) = blocks.multipliedReportingOverflow(by: 512)
        return overflow ? Int64.max : bytes
    }

    private static func posixErrorMessage(_ code: Int32) -> String {
        let resolvedCode = code == 0 ? errno : code
        guard let message = strerror(resolvedCode) else { return "The folder could not be read." }
        return String(cString: message)
    }

    private static func addingWithoutOverflow(_ lhs: Int64, _ rhs: Int64) -> Int64 {
        let (sum, overflow) = lhs.addingReportingOverflow(rhs)
        return overflow ? Int64.max : sum
    }
}

struct InstalledApp: Identifiable {
    let id: String
    let name: String
    let bundleIdentifier: String
    let url: URL
    let size: Int64
    let isSystem: Bool
    let icon: NSImage
    let resourceIdentifier: String?
    let version: String
    var sizeMeasuredAt: Date = .distantPast
    var formattedSize: String { size.formatted(.byteCount(style: .file)) }
}

private struct InstalledAppDescriptor: Sendable {
    let id: String
    let name: String
    let bundleIdentifier: String
    let url: URL
    let size: Int64
    let isSystem: Bool
    let resourceIdentifier: String?
    let version: String
    let sizeMeasuredAt: Date
}

private struct InstalledAppScanOutput: Sendable {
    var apps: [InstalledAppDescriptor] = []
    var errors: [String] = []
}

enum InstalledAppDiscoveryPolicy {
    static func applicationURL(
        for candidateURL: URL,
        isDirectory: Bool,
        isSymbolicLink: Bool,
        protectedSystemRoot: URL = URL(fileURLWithPath: "/System", isDirectory: true)
    ) -> URL? {
        guard candidateURL.pathExtension.caseInsensitiveCompare("app") == .orderedSame else { return nil }
        guard isSymbolicLink else { return isDirectory ? candidateURL : nil }

        let resolvedURL = candidateURL.resolvingSymlinksInPath().standardizedFileURL
        guard isDescendant(resolvedURL, of: protectedSystemRoot) else { return nil }
        return resolvedURL
    }

    private static func isDescendant(_ candidateURL: URL, of rootURL: URL) -> Bool {
        let candidateComponents = candidateURL.standardizedFileURL.pathComponents
        let rootComponents = rootURL.standardizedFileURL.pathComponents
        return candidateComponents.count > rootComponents.count
            && candidateComponents.prefix(rootComponents.count).elementsEqual(rootComponents)
    }
}

private enum InstalledAppScanner {
    private static let maximumConcurrentSizes = 2

    static func scan() async -> InstalledAppScanOutput {
        let fileManager = FileManager.default
        let roots = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)
        ]
        var discovered: [URL] = []
        var seenPaths = Set<String>()
        var scanErrors: [String] = []
        let discoveryKeys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .isSymbolicLinkKey,
            .isPackageKey,
            .volumeIdentifierKey,
            .volumeURLKey,
            .fileResourceIdentifierKey
        ]

        for root in roots where fileManager.fileExists(atPath: root.path) {
            if Task.isCancelled { return InstalledAppScanOutput() }
            let rootValues = try? root.resourceValues(forKeys: [.volumeIdentifierKey, .volumeURLKey])
            let rootVolume = rootValues.flatMap(StorageFileIdentity.volumeIdentifier(from:))
            let rootVolumeURL = rootValues?.volume?.standardizedFileURL
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: Array(discoveryKeys),
                options: [.skipsHiddenFiles, .skipsPackageDescendants],
                errorHandler: { url, error in
                    if scanErrors.count < 20 { scanErrors.append("\(url.path): \(error.localizedDescription)") }
                    return !Task.isCancelled
                }
            ) else {
                scanErrors.append("Could not scan \(root.path).")
                continue
            }

            while let url = enumerator.nextObject() as? URL {
                if Task.isCancelled { return InstalledAppScanOutput() }
                guard let values = try? url.resourceValues(forKeys: discoveryKeys) else {
                    enumerator.skipDescendants()
                    continue
                }
                let isDirectory = values.isDirectory == true
                if values.isSymbolicLink == true {
                    if let applicationURL = InstalledAppDiscoveryPolicy.applicationURL(
                        for: url,
                        isDirectory: isDirectory,
                        isSymbolicLink: true
                    ) {
                        let path = applicationURL.standardizedFileURL.path
                        if seenPaths.insert(path).inserted { discovered.append(applicationURL) }
                    }
                    if isDirectory { enumerator.skipDescendants() }
                    continue
                }
                if let rootVolume,
                   let itemVolume = StorageFileIdentity.volumeIdentifier(from: values),
                   itemVolume != rootVolume {
                    if isDirectory { enumerator.skipDescendants() }
                    continue
                }
                if let rootVolumeURL,
                   let itemVolumeURL = values.volume?.standardizedFileURL,
                   itemVolumeURL != rootVolumeURL {
                    if isDirectory { enumerator.skipDescendants() }
                    continue
                }

                if let applicationURL = InstalledAppDiscoveryPolicy.applicationURL(
                    for: url,
                    isDirectory: isDirectory,
                    isSymbolicLink: false
                ) {
                    let path = applicationURL.standardizedFileURL.path
                    if seenPaths.insert(path).inserted { discovered.append(applicationURL) }
                    enumerator.skipDescendants()
                } else if isDirectory, values.isPackage == true {
                    enumerator.skipDescendants()
                }
            }
        }

        var descriptors: [InstalledAppDescriptor] = []
        await withTaskGroup(of: InstalledAppDescriptor?.self) { group in
            var nextIndex = 0
            let initialCount = min(maximumConcurrentSizes, discovered.count)
            for _ in 0..<initialCount {
                let url = discovered[nextIndex]
                nextIndex += 1
                group.addTask { descriptor(at: url, fileManager: FileManager.default) }
            }

            while let completedDescriptor = await group.next() {
                if Task.isCancelled {
                    group.cancelAll()
                    break
                }
                if let completedDescriptor { descriptors.append(completedDescriptor) }
                if nextIndex < discovered.count {
                    let url = discovered[nextIndex]
                    nextIndex += 1
                    group.addTask { descriptor(at: url, fileManager: FileManager.default) }
                }
            }
        }

        return InstalledAppScanOutput(
            apps: descriptors.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending },
            errors: scanErrors
        )
    }

    private static func descriptor(at url: URL, fileManager: FileManager) -> InstalledAppDescriptor? {
        guard !Task.isCancelled,
              let bundle = Bundle(url: url),
              let bundleIdentifier = bundle.bundleIdentifier,
              AppSecurityValidator.isSafeIdentifier(bundleIdentifier) else { return nil }

        let standardizedURL = url.standardizedFileURL
        let system = standardizedURL.path.hasPrefix("/System/")
            || standardizedURL == Bundle.main.bundleURL.standardizedFileURL
        let rootIdentity = StorageFileIdentity.read(at: url)
        let name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? url.deletingPathExtension().lastPathComponent
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
            ?? "—"

        if system {
            return InstalledAppDescriptor(
                id: standardizedURL.path,
                name: name,
                bundleIdentifier: bundleIdentifier,
                url: standardizedURL,
                size: 0,
                isSystem: true,
                resourceIdentifier: rootIdentity?.serialized ?? AppUninstaller.currentResourceIdentifier(at: url),
                version: version,
                sizeMeasuredAt: Date()
            )
        }

        let volumeValues = try? url.resourceValues(forKeys: [.volumeIdentifierKey, .volumeURLKey])
        let measurement = DirectorySize.measure(
            url,
            using: fileManager,
            preferAllocated: false,
            rootVolumeIdentifier: volumeValues.flatMap(StorageFileIdentity.volumeIdentifier(from:)),
            rootVolumeURL: volumeValues?.volume?.standardizedFileURL,
            ancestorDirectoryIdentities: [],
            collectCandidates: false,
            insightLimitPerCategory: 0,
            isCancelled: { Task.isCancelled }
        )
        guard !Task.isCancelled, !measurement.wasCancelled else { return nil }

        return InstalledAppDescriptor(
            id: standardizedURL.path,
            name: name,
            bundleIdentifier: bundleIdentifier,
            url: standardizedURL,
            size: measurement.bytes,
            isSystem: false,
            resourceIdentifier: rootIdentity?.serialized ?? AppUninstaller.currentResourceIdentifier(at: url),
            version: version,
            sizeMeasuredAt: Date()
        )
    }
}

@MainActor final class InstalledAppsViewModel: ObservableObject {
    @Published private(set) var apps: [InstalledApp] = []
    @Published var confirmingRemoval = false
    @Published private(set) var isLoading = false
    @Published private(set) var isScanningArtifacts = false
    @Published private(set) var isRemoving = false
    @Published private(set) var selectedAppID: String?
    @Published private(set) var artifacts: [AppUninstallArtifact] = []
    @Published var selectedArtifactIDs: Set<String> = []
    @Published var uninstallResult: AppUninstallResult?
    @Published private(set) var scanError: String?
    private var pendingRemoval: InstalledApp?
    var removalMessage: String {
        guard let pendingRemoval else { return "" }
        return "\(selectedArtifacts.count) item\(selectedArtifacts.count == 1 ? "" : "s") for \(pendingRemoval.name) will be moved to the Trash, freeing approximately \(selectedSize.formatted(.byteCount(style: .file)))."
    }

    private var scanTask: Task<Void, Never>?
    private var artifactScanTask: Task<Void, Never>?
    private var scanGeneration: UInt64 = 0
    private static var cachedApps: [InstalledApp] = []
    private static var cacheDate: Date?
    private static let cacheLifetime: TimeInterval = 5 * 60

    private let identifierOwnership: AppIdentifierOwnership = .uncertain

    deinit {
        scanTask?.cancel()
        artifactScanTask?.cancel()
    }

    var selectedApp: InstalledApp? {
        guard let selectedAppID else { return nil }
        return apps.first { $0.id == selectedAppID }
    }

    var selectedArtifacts: [AppUninstallArtifact] {
        artifacts.filter { selectedArtifactIDs.contains($0.id) }
    }

    var selectedSize: Int64 {
        selectedArtifacts.reduce(0) { $0 + $1.size }
    }

    var relatedDataSize: Int64 {
        artifacts.filter { !$0.isApplication }.reduce(0) { $0 + $1.size }
    }

    func scan(force: Bool = false) {
        scanGeneration &+= 1
        let generation = scanGeneration
        scanTask?.cancel()
        if !force,
           let cacheDate = Self.cacheDate,
           Date().timeIntervalSince(cacheDate) < Self.cacheLifetime,
           !Self.cachedApps.isEmpty {
            apps = Self.cachedApps
            isLoading = false
            scanError = nil
            return
        }

        isLoading = true
        scanError = nil
        let owner = WeakReference(self)
        scanTask = Task.detached(priority: .utility) {
            let output = await InstalledAppScanner.scan()
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self = owner.value, self.scanGeneration == generation else { return }
                let installedApps = output.apps.map { descriptor in
                    InstalledApp(
                        id: descriptor.id,
                        name: descriptor.name,
                        bundleIdentifier: descriptor.bundleIdentifier,
                        url: descriptor.url,
                        size: descriptor.size,
                        isSystem: descriptor.isSystem,
                        icon: NSWorkspace.shared.icon(forFile: descriptor.url.path),
                        resourceIdentifier: descriptor.resourceIdentifier,
                        version: descriptor.version,
                        sizeMeasuredAt: descriptor.sizeMeasuredAt
                    )
                }
                self.apps = installedApps
                Self.cachedApps = installedApps
                Self.cacheDate = Date()
                self.isLoading = false
                self.scanError = output.errors.isEmpty ? nil : output.errors.joined(separator: "\n")
                if let selectedAppID = self.selectedAppID,
                   !installedApps.contains(where: { $0.id == selectedAppID }) {
                    self.selectedAppID = nil
                    self.artifacts = []
                    self.selectedArtifactIDs = []
                }
            }
        }
    }

    func rescan() { scan(force: true) }

    func cancelScan() {
        scanGeneration &+= 1
        scanTask?.cancel()
        scanTask = nil
        isLoading = false
    }

    func select(_ app: InstalledApp) {
        guard !app.isSystem else { return }
        uninstallResult = nil
        selectedAppID = app.id
        artifacts = []
        selectedArtifactIDs = []
        artifactScanTask?.cancel()
        isScanningArtifacts = true
        let ownership = identifierOwnership
        let owner = WeakReference(self)
        artifactScanTask = Task.detached(priority: .utility) {
            let found = AppArtifactScanner.scan(app: app, identifierOwnership: ownership)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self = owner.value, self.selectedAppID == app.id else { return }
                self.artifacts = found
                self.selectedArtifactIDs = Set(found.filter { $0.confidence == .exact }.map(\.id))
                self.isScanningArtifacts = false
            }
        }
    }

    func cancelArtifactScan() {
        artifactScanTask?.cancel()
        artifactScanTask = nil
        isScanningArtifacts = false
    }

    func setArtifact(_ artifact: AppUninstallArtifact, selected: Bool) {
        if artifact.isApplication {
            selectedArtifactIDs.insert(artifact.id)
            return
        }
        if selected {
            selectedArtifactIDs.insert(artifact.id)
        } else {
            selectedArtifactIDs.remove(artifact.id)
        }
    }

    func selectRecommendedArtifacts() {
        selectedArtifactIDs = Set(artifacts.filter { $0.confidence == .exact }.map(\.id))
    }

    func requestRemoval(_ app: InstalledApp) {
        guard !app.isSystem,
              !isRemoving,
              InstalledAppUpdatesChecker.shared.updatingBundleID != app.bundleIdentifier else { return }
        if selectedAppID != app.id { select(app) }
        pendingRemoval = app
        confirmingRemoval = true
    }

    func removeConfirmed() {
        confirmingRemoval = false
        guard let app = pendingRemoval, !isRemoving else { return }
        let confirmedArtifacts = selectedArtifacts
        guard confirmedArtifacts.contains(where: \.isApplication) else {
            pendingRemoval = nil
            return
        }
        isRemoving = true
        Task {
            let result = await AppUninstaller.uninstall(app: app, artifacts: confirmedArtifacts)
            uninstallResult = result
            isRemoving = false
            pendingRemoval = nil

            if result.applicationRemoved {
                apps.removeAll { $0.id == app.id }
                Self.cachedApps.removeAll { $0.id == app.id }
                Self.cacheDate = Date()
                artifacts = []
                selectedArtifactIDs = []
                selectedAppID = nil
                let hasAnotherInstalledCopy = apps.contains {
                    $0.bundleIdentifier == app.bundleIdentifier
                }
                let ownershipWasVerifiedExclusive = identifierOwnership.isVerifiedExclusive
                InstalledAppUpdatesChecker.shared.forgetApp(
                    bundleIdentifier: app.bundleIdentifier,
                    url: app.url,
                    preserveBundlePreferences: hasAnotherInstalledCopy || !ownershipWasVerifiedExclusive
                )
                if hasAnotherInstalledCopy {
                    if SettingsModel.shared.settings.installedAppUpdatesEnabled {
                        InstalledAppUpdatesChecker.shared.checkNow()
                    }
                } else if ownershipWasVerifiedExclusive {
                    SettingsModel.shared.removeReferences(toApplication: app.bundleIdentifier)
                }
            } else {
                select(app)
                uninstallResult = result
            }
        }
    }

}

enum StorageCategory: String, Codable, CaseIterable, Sendable {
    case caches = "Caches"
    case trash = "Trash"
    case downloads = "Downloads"
    case largeFiles = "Large Files"
    case oldFiles = "Old Files"
    case languagePacks = "Language Packs"
    case duplicates = "Duplicates"
    case appSupport = "App Support"
    case other = "Other"

    var icon: String {
        switch self {
        case .caches: return "trash.fill"
        case .trash: return "trash.circle.fill"
        case .downloads: return "arrow.down.circle.fill"
        case .largeFiles: return "externaldrive.fill"
        case .oldFiles: return "calendar"
        case .languagePacks: return "globe"
        case .duplicates: return "doc.badge"
        case .appSupport: return "app.fill"
        case .other: return "folder.fill"
        }
    }

    var color: Color {
        switch self {
        case .caches: return Color(hue: 0.0, saturation: 0.8, brightness: 0.9)
        case .trash: return Color(hue: 0.05, saturation: 0.8, brightness: 0.9)
        case .downloads: return Color(hue: 0.15, saturation: 0.8, brightness: 0.9)
        case .largeFiles: return Color(hue: 0.3, saturation: 0.8, brightness: 0.9)
        case .oldFiles: return Color(hue: 0.45, saturation: 0.8, brightness: 0.9)
        case .languagePacks: return Color(hue: 0.6, saturation: 0.8, brightness: 0.9)
        case .duplicates: return Color(hue: 0.75, saturation: 0.8, brightness: 0.9)
        case .appSupport: return Color(hue: 0.9, saturation: 0.8, brightness: 0.9)
        case .other: return Color(hue: 0.55, saturation: 0.72, brightness: 0.9)
        }
    }

    var safetyLevel: String {
        switch self {
        case .caches: return "Safe"
        case .trash, .duplicates, .largeFiles: return "Review"
        case .downloads, .oldFiles, .languagePacks: return "Caution"
        case .appSupport: return "Risky"
        case .other: return "Unknown"
        }
    }
}

struct StorageEntry: Identifiable, Equatable, Sendable {
    let id: URL
    let name: String
    let url: URL
    let size: Int64
    let isDirectory: Bool
    var logicalSize: Int64
    var isPackage = false
    var isSymbolicLink = false
    var category: StorageCategory = .other
    var isLargeFile = false
    var isOldFile = false
    var lastModified: Date?
    var fileType: String?
    var isDuplicate: Bool = false
    var isSystemProtected: Bool = false
    var resourceIdentifier: String?
    var contentHash: String?
    var scanWarning: String?

    init(url: URL, size: Int64, isDirectory: Bool) {
        self.id = url
        self.url = url
        self.name = url.lastPathComponent
        self.size = size
        self.isDirectory = isDirectory
        self.logicalSize = size
    }

    func matches(_ filter: StorageCategory) -> Bool {
        switch filter {
        case .largeFiles: return isLargeFile || category == .largeFiles
        case .oldFiles: return isOldFile || category == .oldFiles
        case .duplicates: return isDuplicate || category == .duplicates
        default: return category == filter
        }
    }
}

struct CleanupRecommendation: Identifiable, Sendable {
    let id = UUID()
    let category: StorageCategory
    let description: String
    let potentialSpaceFreed: Int64
    let actionDescription: String
    let isAutomatic: Bool
    let entries: [StorageEntry]
}

struct ScanResult: Codable, Sendable {
    let timestamp: Date
    let totalScanned: Int64
    let spaceFreed: Int64
    let duration: TimeInterval
    let categoryCounts: [String: Int64]
    let scopeIdentifier: String?
    let deepScanEnabled: Bool?
    let bytesMovedToTrash: Int64?

    init(
        timestamp: Date,
        totalScanned: Int64,
        spaceFreed: Int64,
        duration: TimeInterval,
        categoryCounts: [String: Int64],
        scopeIdentifier: String? = nil,
        deepScanEnabled: Bool? = nil,
        bytesMovedToTrash: Int64? = nil
    ) {
        self.timestamp = timestamp
        self.totalScanned = totalScanned
        self.spaceFreed = spaceFreed
        self.duration = duration
        self.categoryCounts = categoryCounts
        self.scopeIdentifier = scopeIdentifier
        self.deepScanEnabled = deepScanEnabled
        self.bytesMovedToTrash = bytesMovedToTrash
    }
}

enum StorageViewMode: Sendable {
    case pie
    case list
    case tree
    case categories
    case duplicates
}

enum StorageScanState: Equatable, Sendable {
    case idle
    case loadingCache
    case scanning
    case hashingDuplicates
    case completed
    case cancelled
    case failed(String)
}

struct StorageScanIssue: Identifiable, Equatable, Sendable {
    let id: UUID
    let url: URL?
    let message: String

    init(url: URL? = nil, message: String) {
        self.id = UUID()
        self.url = url
        self.message = message
    }
}

struct StorageScanMetrics: Equatable, Sendable {
    var childCount: Int
    var filesVisited: Int
    var directoriesVisited: Int
    var logicalBytesVisited: Int64
    var allocatedBytesVisited: Int64
    var duplicateFileCount: Int
    var duration: TimeInterval
    var cacheHit: Bool
}

enum StorageCapacityAccounting {
    static func normalized<Key: Hashable>(
        _ values: [Key: Int64],
        maximumTotal: Int64
    ) -> [Key: Int64] {
        let nonnegative = values.mapValues { max(0, $0) }
        guard maximumTotal >= 0 else { return nonnegative }
        guard maximumTotal > 0 else { return [:] }
        let rawTotal = nonnegative.values.reduce(Int64(0), saturatingAdd)
        guard rawTotal > maximumTotal else { return nonnegative }

        let scale = Double(maximumTotal) / Double(rawTotal)
        return nonnegative.reduce(into: [:]) { result, element in
            let scaled = max(0, Int64((Double(element.value) * scale).rounded(.down)))
            if scaled > 0 { result[element.key] = scaled }
        }
    }

    static func total<Key: Hashable>(of values: [Key: Int64]) -> Int64 {
        values.values.reduce(Int64(0), saturatingAdd)
    }

    private static func saturatingAdd(_ lhs: Int64, _ rhs: Int64) -> Int64 {
        let (sum, overflow) = lhs.addingReportingOverflow(rhs)
        return overflow ? Int64.max : sum
    }
}

struct StorageDuplicateGroup: Identifiable, Equatable, Sendable {
    let id: String
    let fingerprint: String
    let logicalFileSize: Int64
    let entries: [StorageEntry]
    let reclaimableBytes: Int64
}

struct StorageRemovalResult: Equatable, Sendable {
    let removed: [URL]
    let failures: [StorageScanIssue]
    let bytesMovedToTrash: Int64
    let completedAt: Date
}

@MainActor final class StorageViewModel: ObservableObject {
    @Published private(set) var entries: [StorageEntry] = [] {
        didSet { filteredEntriesCache = nil }
    }
    @Published private(set) var insightEntries: [StorageEntry] = [] {
        didSet { filteredInsightEntriesCache = nil }
    }
    @Published private(set) var total: Int64 = 0
    @Published private(set) var used: Int64 = 0
    @Published private(set) var available: Int64 = 0
    @Published private(set) var availableForImportantUsage: Int64 = 0
    @Published private(set) var purgeableBytes: Int64 = 0
    @Published private(set) var volumeURL = URL(fileURLWithPath: "/")
    @Published private(set) var currentURL = URL(fileURLWithPath: "/")
    @Published private(set) var isLoading = false
    @Published private(set) var indexingProgress: Double = 0
    @Published private(set) var indexingLabel = ""
    @Published private(set) var scanState: StorageScanState = .idle
    @Published private(set) var scanErrors: [StorageScanIssue] = []
    @Published private(set) var scanMetrics: StorageScanMetrics?
    @Published private(set) var duplicateGroups: [StorageDuplicateGroup] = []
    @Published private(set) var reclaimableBytes: Int64 = 0
    @Published private(set) var capacityError: String?

    @Published var viewMode: StorageViewMode = .pie
    @Published var sortBy: SortOption = .size { didSet { invalidateFilteredEntryCaches() } }
    @Published var filterText: String = "" { didSet { invalidateFilteredEntryCaches() } }
    @Published var categoryFilter: StorageCategory? = nil { didSet { invalidateFilteredEntryCaches() } }
    @Published var minSizeFilter: Int64 = 0 { didSet { invalidateFilteredEntryCaches() } }
    @Published var maxSizeFilter: Int64 = Int64.max { didSet { invalidateFilteredEntryCaches() } }
    @Published private(set) var recommendations: [CleanupRecommendation] = []
    @Published private(set) var scanHistory: [ScanResult] = []
    @Published var deepScanEnabled = false {
        didSet {
            guard deepScanEnabled != oldValue else { return }
            clearPresentedScan()
            refreshFromCache()
        }
    }
    @Published var confirmingRemoval = false
    @Published private(set) var pendingRemovalEntries: [StorageEntry] = []
    @Published private(set) var isRemoving = false
    @Published private(set) var lastRemovalResult: StorageRemovalResult?
    @Published private(set) var removalIssues: [StorageScanIssue] = []

    private var loadTask: Task<Void, Never>?
    private var removalTask: Task<Void, Never>?
    private var scanGeneration: UInt64 = 0
    private var categorySizes: [StorageCategory: Int64] = [:]
    private var currentHistoryScopeIdentifier = ""
    private var pendingHistoryBytesMovedToTrash: Int64 = 0
    private var pendingHistoryScopeIdentifier: String?
    private var pendingHistoryDeepScanEnabled: Bool?
    private var filteredEntriesCache: [StorageEntry]?
    private var filteredInsightEntriesCache: [StorageEntry]?
    private var hasValidCapacity = false

    private static let scanHistoryDefaultsKey = "storage.scan-history.v1"
    private static let historyScopeSaltDefaultsKey = "storage.scan-history.scope-salt.v1"
    private static let pendingHistoryBytesDefaultsKey = "storage.scan-history.pending-trash-bytes.v1"
    private static let pendingHistoryScopeDefaultsKey = "storage.scan-history.pending-scope.v1"
    private static let pendingHistoryDeepModeDefaultsKey = "storage.scan-history.pending-deep-mode.v1"
    private static let maximumHistoryEntries = 30

    init() {
        scanHistory = Self.loadPersistedScanHistory()
        currentHistoryScopeIdentifier = Self.makeHistoryScopeIdentifier(for: currentURL)
        let defaults = UserDefaults.standard
        pendingHistoryScopeIdentifier = defaults.string(forKey: Self.pendingHistoryScopeDefaultsKey)
        pendingHistoryDeepScanEnabled = (defaults.object(forKey: Self.pendingHistoryDeepModeDefaultsKey) as? NSNumber)?.boolValue
        if pendingHistoryScopeIdentifier != nil, pendingHistoryDeepScanEnabled != nil {
            pendingHistoryBytesMovedToTrash = max(
                0,
                (defaults.object(forKey: Self.pendingHistoryBytesDefaultsKey) as? NSNumber)?.int64Value ?? 0
            )
        }
    }

    deinit {
        loadTask?.cancel()
        removalTask?.cancel()
    }

    enum SortOption: String, CaseIterable, Sendable {
        case size = "Size (Large to Small)"
        case name = "Name (A to Z)"
        case modified = "Recently Modified"
        case type = "File Type"
    }

    var volumeName: String {
        FileManager.default.displayName(atPath: volumeURL.path)
    }

    var filteredAndSortedEntries: [StorageEntry] {
        if let filteredEntriesCache { return filteredEntriesCache }
        var filtered = entries
        if let categoryFilter {
            filtered = filtered.filter { $0.matches(categoryFilter) }
        }
        if !filterText.isEmpty {
            filtered = filtered.filter { $0.name.localizedCaseInsensitiveContains(filterText) }
        }
        filtered = filtered.filter { $0.size >= minSizeFilter && $0.size <= maxSizeFilter }
        let result = sorted(filtered)
        filteredEntriesCache = result
        return result
    }

    var filteredAndSortedInsightEntries: [StorageEntry] {
        if let filteredInsightEntriesCache { return filteredInsightEntriesCache }
        var filtered = insightEntries
        if let categoryFilter {
            filtered = filtered.filter { $0.matches(categoryFilter) }
        }
        if !filterText.isEmpty {
            filtered = filtered.filter { $0.name.localizedCaseInsensitiveContains(filterText) }
        }
        filtered = filtered.filter { $0.size >= minSizeFilter && $0.size <= maxSizeFilter }
        let result = sorted(filtered)
        filteredInsightEntriesCache = result
        return result
    }

    private func invalidateFilteredEntryCaches() {
        filteredEntriesCache = nil
        filteredInsightEntriesCache = nil
    }

    var totalCategorySize: [StorageCategory: Int64] {
        categorySizes
    }

    var accountedBytes: Int64 {
        StorageCapacityAccounting.total(of: categorySizes)
    }

    private var physicalAccountingLimit: Int64 {
        guard hasValidCapacity, total > 0 else { return -1 }
        return min(total, max(0, used))
    }

    var potentialSpaceSavings: Int64 {
        boundedEstimate(recommendations.reduce(Int64(0)) { partial, recommendation in
            Self.saturatingAdd(partial, max(0, recommendation.potentialSpaceFreed))
        })
    }

    func boundedEstimate(_ bytes: Int64) -> Int64 {
        let nonnegative = max(0, bytes)
        let limit = physicalAccountingLimit
        return limit >= 0 ? min(nonnegative, limit) : nonnegative
    }

    var currentScopeScanHistory: [ScanResult] {
        scanHistory.filter {
            $0.scopeIdentifier == currentHistoryScopeIdentifier
                && $0.deepScanEnabled == deepScanEnabled
        }
    }

    var currentScopeHistory: [ScanResult] { currentScopeScanHistory }

    func refresh() { rescan() }

    func rescan() { load(currentURL, force: true) }

    private static let scanFreshness: TimeInterval = 5 * 60

    func refreshIfNeeded() { load(currentURL, force: false) }

    func refreshFromCache() {
        guard SubscriptionAccess.hasAccess(to: .basicStorageFeatures) else { return }
        let target = currentURL.standardizedFileURL
        scanGeneration &+= 1
        let generation = scanGeneration
        loadTask?.cancel()
        refreshCapacity()
        isLoading = true
        scanState = .loadingCache
        indexingProgress = 0
        indexingLabel = "Looking for a recent storage index…"

        let key = StorageCacheKey(url: target, deepScan: deepScanEnabled)
        let freshness = Self.scanFreshness
        let owner = WeakReference(self)
        loadTask = Task.detached(priority: .utility) {
            if var cached = await StorageSnapshotCache.shared.value(for: key, maxAge: freshness) {
                cached.metrics.cacheHit = true
                let cachedSnapshot = cached
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    owner.value?.apply(snapshot: cachedSnapshot, generation: generation)
                }
                return
            }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self = owner.value, self.scanGeneration == generation else { return }
                self.isLoading = false
                self.scanState = .idle
                self.indexingLabel = "Ready to scan"
            }
        }
    }

    func cancelScan() {
        guard isLoading else { return }
        scanGeneration &+= 1
        loadTask?.cancel()
        loadTask = nil
        isLoading = false
        scanState = .cancelled
        indexingLabel = "Scan cancelled"
    }

    func refreshCapacity() {
        do {
            let values = try currentURL.resourceValues(forKeys: [
                .volumeURLKey,
                .volumeTotalCapacityKey,
                .volumeAvailableCapacityKey,
                .volumeAvailableCapacityForImportantUsageKey
            ])
            volumeURL = values.volume ?? currentURL
            guard let capacity = values.volumeTotalCapacity,
                  let free = values.volumeAvailableCapacity,
                  capacity > 0 else {
                resetCapacityState(message: "Storage capacity is unavailable for this location.")
                return
            }

            total = Int64(capacity)
            available = min(total, max(0, Int64(free)))
            used = max(0, total - available)
            hasValidCapacity = true
            if let important = values.volumeAvailableCapacityForImportantUsage {
                availableForImportantUsage = min(total, max(available, Int64(important)))
            } else {
                availableForImportantUsage = available
            }
            purgeableBytes = min(used, max(0, availableForImportantUsage - available))
            capacityError = nil
            normalizeCurrentScopeHistoryIfNeeded()
        } catch {
            volumeURL = currentURL
            resetCapacityState(message: error.localizedDescription)
        }
    }

    private func resetCapacityState(message: String) {
        total = 0
        used = 0
        available = 0
        availableForImportantUsage = 0
        purgeableBytes = 0
        hasValidCapacity = false
        capacityError = message
    }

    private func clearPresentedScan() {
        entries = []
        insightEntries = []
        recommendations = []
        duplicateGroups = []
        categorySizes = [:]
        reclaimableBytes = 0
        scanMetrics = nil
        scanErrors = []
        confirmingRemoval = false
        pendingRemovalEntries = []
    }

    func open(_ entry: StorageEntry) {
        guard entry.isDirectory, !entry.isPackage, !entry.isSymbolicLink else { return }
        load(entry.url, force: false)
    }

    func reveal(_ entry: StorageEntry) { reveal(entry.url) }

    func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func requestRemoval(_ entry: StorageEntry) {
        requestRemoval(confirmingRemoval ? pendingRemovalEntries + [entry] : [entry])
    }

    func requestRemoval(_ requestedEntries: [StorageEntry]) {
        guard !isRemoving else { return }
        let unique = Dictionary(requestedEntries.map { ($0.url.standardizedFileURL, $0) }, uniquingKeysWith: { first, _ in first })
            .values
            .sorted { $0.url.path.localizedStandardCompare($1.url.path) == .orderedAscending }
        var accepted: [StorageEntry] = []
        var rejected: [StorageScanIssue] = []
        for entry in unique {
            if let reason = StorageDeletionPolicy.rejectionReason(for: entry, within: currentURL) {
                rejected.append(StorageScanIssue(url: entry.url, message: reason))
            } else {
                accepted.append(entry)
            }
        }
        removalIssues = rejected
        pendingRemovalEntries = accepted
        confirmingRemoval = !accepted.isEmpty
    }

    func requestRemoval(_ group: StorageDuplicateGroup, keeping keep: StorageEntry? = nil) {
        let retainedID = keep?.id ?? group.entries.first?.id
        requestRemoval(group.entries.filter { $0.id != retainedID })
    }

    func cancelRemovalRequest() {
        confirmingRemoval = false
        pendingRemovalEntries = []
    }

    func removeConfirmed() {
        confirmingRemoval = false
        guard !pendingRemovalEntries.isEmpty, !isRemoving else { return }
        let entriesToRemove = pendingRemovalEntries
        let scope = currentURL
        let historyScopeIdentifier = currentHistoryScopeIdentifier
        let historyDeepScanEnabled = deepScanEnabled
        pendingRemovalEntries = []
        isRemoving = true
        let owner = WeakReference(self)
        removalTask = Task.detached(priority: .utility) {
            let result = StorageDeletionWorker.moveToTrash(entriesToRemove, within: scope)
            guard !Task.isCancelled else { return }
            await StorageSnapshotCache.shared.invalidate(affectedBy: result.removed)
            await MainActor.run {
                guard let self = owner.value else { return }
                self.isRemoving = false
                self.lastRemovalResult = result
                self.removalIssues = result.failures
                if result.bytesMovedToTrash > 0 {
                    if self.pendingHistoryScopeIdentifier != historyScopeIdentifier
                        || self.pendingHistoryDeepScanEnabled != historyDeepScanEnabled {
                        self.pendingHistoryBytesMovedToTrash = 0
                    }
                    self.pendingHistoryScopeIdentifier = historyScopeIdentifier
                    self.pendingHistoryDeepScanEnabled = historyDeepScanEnabled
                    self.pendingHistoryBytesMovedToTrash = Self.saturatingAdd(
                        self.pendingHistoryBytesMovedToTrash,
                        result.bytesMovedToTrash
                    )
                    UserDefaults.standard.set(
                        self.pendingHistoryBytesMovedToTrash,
                        forKey: Self.pendingHistoryBytesDefaultsKey
                    )
                    UserDefaults.standard.set(historyScopeIdentifier, forKey: Self.pendingHistoryScopeDefaultsKey)
                    UserDefaults.standard.set(historyDeepScanEnabled, forKey: Self.pendingHistoryDeepModeDefaultsKey)
                }
                self.refreshCapacity()
                if !result.removed.isEmpty,
                   self.currentHistoryScopeIdentifier == historyScopeIdentifier {
                    self.rescan()
                }
            }
        }
    }

    var removalMessage: String {
        guard !pendingRemovalEntries.isEmpty else { return "" }
        let bytes = pendingRemovalEntries.reduce(Int64(0)) { partial, entry in
            let (sum, overflow) = partial.addingReportingOverflow(entry.size)
            return overflow ? Int64.max : sum
        }
        if pendingRemovalEntries.count == 1, let entry = pendingRemovalEntries.first {
            return "\(entry.name) (\(bytes.formatted(.byteCount(style: .file)))) will be moved to the Trash."
        }
        return "\(pendingRemovalEntries.count) items (\(bytes.formatted(.byteCount(style: .file)))) will be moved to the Trash."
    }

    func goUp() {
        let parent = currentURL.deletingLastPathComponent()
        guard parent.path != currentURL.path else { return }
        load(parent, force: false)
    }

    private func sorted(_ entries: [StorageEntry]) -> [StorageEntry] {
        switch sortBy {
        case .size:
            return entries.sorted { $0.size > $1.size }
        case .name:
            return entries.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .modified:
            return entries.sorted { ($0.lastModified ?? .distantPast) > ($1.lastModified ?? .distantPast) }
        case .type:
            return entries.sorted { ($0.fileType ?? "") < ($1.fileType ?? "") }
        }
    }

    private func load(_ url: URL, force: Bool) {
        guard SubscriptionAccess.hasAccess(to: .basicStorageFeatures) else { return }
        let target = url.standardizedFileURL
        let changedDirectory = target != currentURL.standardizedFileURL
        scanGeneration &+= 1
        let generation = scanGeneration
        loadTask?.cancel()
        currentURL = target
        currentHistoryScopeIdentifier = Self.makeHistoryScopeIdentifier(for: target)
        refreshCapacity()

        if changedDirectory {
            entries = []
            insightEntries = []
            recommendations = []
            duplicateGroups = []
            categorySizes = [:]
            reclaimableBytes = 0
            scanMetrics = nil
            scanErrors = []
        }

        isLoading = true
        scanState = .loadingCache
        indexingProgress = 0
        indexingLabel = "Preparing \(target.lastPathComponent.isEmpty ? volumeName : target.lastPathComponent)…"

        let deepScan = deepScanEnabled
        let key = StorageCacheKey(url: target, deepScan: deepScan)
        let freshness = Self.scanFreshness
        let owner = WeakReference(self)
        loadTask = Task.detached(priority: .utility) {
            if !force,
               var cached = await StorageSnapshotCache.shared.value(for: key, maxAge: freshness) {
                cached.metrics.cacheHit = true
                let cachedSnapshot = cached
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    owner.value?.apply(snapshot: cachedSnapshot, generation: generation)
                }
                return
            }

            do {
                let request = StorageScanRequest(url: target, deepScan: deepScan)
                try Task.checkCancellation()
                let lease = await StorageScanCoordinator.shared.acquire(request: request) { progress in
                    await MainActor.run {
                        guard let self = owner.value, self.scanGeneration == generation else { return }
                        self.scanState = progress.state
                        self.indexingProgress = progress.fraction
                        self.indexingLabel = progress.label
                    }
                }
                let scannedSnapshot: StorageDirectorySnapshot
                do {
                    scannedSnapshot = try await withTaskCancellationHandler {
                        try await lease.task.value
                    } onCancel: {
                        Task { await StorageScanCoordinator.shared.release(lease) }
                    }
                } catch {
                    await StorageScanCoordinator.shared.release(lease)
                    throw error
                }
                await StorageScanCoordinator.shared.release(lease)
                try Task.checkCancellation()
                var presentedSnapshot = scannedSnapshot
                if !lease.isPrimary { presentedSnapshot.metrics.cacheHit = true }
                let finalSnapshot = presentedSnapshot
                await MainActor.run {
                    owner.value?.apply(snapshot: finalSnapshot, generation: generation)
                }
            } catch is CancellationError {
                return
            } catch {
                await MainActor.run {
                    guard let self = owner.value, self.scanGeneration == generation else { return }
                    self.isLoading = false
                    self.scanState = .failed(error.localizedDescription)
                    self.indexingLabel = "Scan failed"
                    self.scanErrors = [StorageScanIssue(url: target, message: error.localizedDescription)]
                }
            }
        }
    }

    private func apply(snapshot: StorageDirectorySnapshot, generation: UInt64) {
        guard scanGeneration == generation, snapshot.url.standardizedFileURL == currentURL.standardizedFileURL else { return }
        let accountingLimit = physicalAccountingLimit
        entries = snapshot.entries
        insightEntries = snapshot.insightEntries
        recommendations = snapshot.recommendations
        duplicateGroups = snapshot.duplicateGroups
        categorySizes = StorageCapacityAccounting.normalized(
            snapshot.categorySizes,
            maximumTotal: accountingLimit
        )
        reclaimableBytes = accountingLimit >= 0
            ? min(max(0, snapshot.reclaimableBytes), accountingLimit)
            : max(0, snapshot.reclaimableBytes)
        scanErrors = snapshot.issues
        var presentedMetrics = snapshot.metrics
        if accountingLimit >= 0 {
            presentedMetrics.allocatedBytesVisited = min(
                max(0, presentedMetrics.allocatedBytesVisited),
                accountingLimit
            )
        }
        scanMetrics = presentedMetrics
        isLoading = false
        scanState = .completed
        indexingProgress = 1
        let modeName = deepScanEnabled ? "Deep" : "Surface"
        indexingLabel = snapshot.metrics.cacheHit
            ? "Loaded cached \(modeName) scan"
            : "\(modeName) scan complete"
        if !snapshot.metrics.cacheHit {
            recordScanResult(duration: snapshot.metrics.duration)
        }
    }

    fileprivate nonisolated static func generateRecommendations(
        from entries: [StorageEntry],
        duplicateGroups: [StorageDuplicateGroup]
    ) -> [CleanupRecommendation] {
        var recommendations: [CleanupRecommendation] = []
        let categories = Dictionary(grouping: entries) { $0.category }

        if let cacheEntries = categories[.caches]?.filter({ !$0.isSystemProtected }), !cacheEntries.isEmpty {
            let size = cacheEntries.reduce(Int64(0)) { saturatingAdd($0, $1.size) }
            recommendations.append(CleanupRecommendation(
                category: .caches,
                description: "System and app caches can safely be removed",
                potentialSpaceFreed: size,
                actionDescription: "Clear \(cacheEntries.count) cache files",
                isAutomatic: true,
                entries: cacheEntries
            ))
        }

        if let trashEntries = categories[.trash]?.filter({ !$0.isSystemProtected }), !trashEntries.isEmpty {
            let size = trashEntries.reduce(Int64(0)) { saturatingAdd($0, $1.size) }
            recommendations.append(CleanupRecommendation(
                category: .trash,
                description: "Sapphire never permanently deletes Trash contents; review and empty Trash in Finder when ready",
                potentialSpaceFreed: size,
                actionDescription: "Review Trash in Finder",
                isAutomatic: false,
                entries: trashEntries
            ))
        }

        let largeFiles = entries.filter { $0.matches(.largeFiles) && !$0.isSystemProtected }
        if !largeFiles.isEmpty {
            let size = largeFiles.reduce(Int64(0)) { saturatingAdd($0, $1.size) }
            recommendations.append(CleanupRecommendation(
                category: .largeFiles,
                description: "Large files that could be moved or compressed",
                potentialSpaceFreed: size,
                actionDescription: "Review \(largeFiles.count) large files",
                isAutomatic: false,
                entries: largeFiles
            ))
        }

        let oldFiles = entries.filter { $0.matches(.oldFiles) && !$0.isSystemProtected }
        if !oldFiles.isEmpty {
            let size = oldFiles.reduce(Int64(0)) { saturatingAdd($0, $1.size) }
            recommendations.append(CleanupRecommendation(
                category: .oldFiles,
                description: "Older files that may no longer be needed",
                potentialSpaceFreed: size,
                actionDescription: "Review \(oldFiles.count) older file\(oldFiles.count == 1 ? "" : "s")",
                isAutomatic: false,
                entries: oldFiles
            ))
        }

        if let downloads = categories[.downloads]?.filter({ !$0.isSystemProtected }), !downloads.isEmpty {
            let size = downloads.reduce(Int64(0)) { saturatingAdd($0, $1.size) }
            recommendations.append(CleanupRecommendation(
                category: .downloads,
                description: "Downloaded files worth reviewing before removal",
                potentialSpaceFreed: size,
                actionDescription: "Review \(downloads.count) download\(downloads.count == 1 ? "" : "s")",
                isAutomatic: false,
                entries: downloads
            ))
        }

        if !duplicateGroups.isEmpty {
            let size = duplicateGroups.reduce(Int64(0)) { partial, group in
                let (sum, overflow) = partial.addingReportingOverflow(group.reclaimableBytes)
                return overflow ? Int64.max : sum
            }
            recommendations.append(CleanupRecommendation(
                category: .duplicates,
                description: "Byte-for-byte identical files that can be reviewed safely",
                potentialSpaceFreed: size,
                actionDescription: "Review \(duplicateGroups.count) duplicate group\(duplicateGroups.count == 1 ? "" : "s")",
                isAutomatic: false,
                entries: []
            ))
        }

        return recommendations.sorted { $0.potentialSpaceFreed > $1.potentialSpaceFreed }
    }

    private func normalizeCurrentScopeHistoryIfNeeded() {
        guard hasValidCapacity, total > 0 else { return }
        let historyLimit = total
        var changed = false
        let normalizedHistory = scanHistory.map { result -> ScanResult in
            guard result.scopeIdentifier == currentHistoryScopeIdentifier else { return result }
            let categoryTotal = StorageCapacityAccounting.total(of: result.categoryCounts)
            guard result.totalScanned > historyLimit || categoryTotal > historyLimit else { return result }
            changed = true
            return ScanResult(
                timestamp: result.timestamp,
                totalScanned: min(max(0, result.totalScanned), historyLimit),
                spaceFreed: result.spaceFreed,
                duration: result.duration,
                categoryCounts: StorageCapacityAccounting.normalized(
                    result.categoryCounts,
                    maximumTotal: historyLimit
                ),
                scopeIdentifier: result.scopeIdentifier,
                deepScanEnabled: result.deepScanEnabled,
                bytesMovedToTrash: result.bytesMovedToTrash
            )
        }
        guard changed else { return }
        scanHistory = normalizedHistory
        persistScanHistory()
    }

    private func recordScanResult(duration: TimeInterval) {
        let categoryCounts = Dictionary(uniqueKeysWithValues: categorySizes.map {
            ($0.key.rawValue, $0.value)
        })
        let appliesPendingRemoval = pendingHistoryScopeIdentifier == currentHistoryScopeIdentifier
            && pendingHistoryDeepScanEnabled == deepScanEnabled
        let bytesMovedToTrash = appliesPendingRemoval ? pendingHistoryBytesMovedToTrash : 0
        let result = ScanResult(
            timestamp: Date(),
            totalScanned: StorageCapacityAccounting.total(of: categorySizes),
            spaceFreed: 0,
            duration: duration,
            categoryCounts: categoryCounts,
            scopeIdentifier: currentHistoryScopeIdentifier,
            deepScanEnabled: deepScanEnabled,
            bytesMovedToTrash: bytesMovedToTrash
        )
        if appliesPendingRemoval {
            pendingHistoryBytesMovedToTrash = 0
            pendingHistoryScopeIdentifier = nil
            pendingHistoryDeepScanEnabled = nil
            let defaults = UserDefaults.standard
            defaults.removeObject(forKey: Self.pendingHistoryBytesDefaultsKey)
            defaults.removeObject(forKey: Self.pendingHistoryScopeDefaultsKey)
            defaults.removeObject(forKey: Self.pendingHistoryDeepModeDefaultsKey)
        }
        var history = scanHistory
        history.append(result)
        if history.count > Self.maximumHistoryEntries {
            history.removeFirst(history.count - Self.maximumHistoryEntries)
        }
        self.scanHistory = history
        persistScanHistory()
    }

    private func persistScanHistory() {
        guard let data = try? JSONEncoder().encode(scanHistory) else { return }
        UserDefaults.standard.set(data, forKey: Self.scanHistoryDefaultsKey)
    }

    private static func loadPersistedScanHistory() -> [ScanResult] {
        guard let data = UserDefaults.standard.data(forKey: scanHistoryDefaultsKey),
              let history = try? JSONDecoder().decode([ScanResult].self, from: data) else { return [] }
        return Array(history.suffix(maximumHistoryEntries))
    }

    private static func makeHistoryScopeIdentifier(for url: URL) -> String {
        let defaults = UserDefaults.standard
        let salt: Data
        if let stored = defaults.data(forKey: historyScopeSaltDefaultsKey), stored.count == 32 {
            salt = stored
        } else {
            var generator = SystemRandomNumberGenerator()
            let generated = Data((0..<32).map { _ in UInt8.random(in: .min ... .max, using: &generator) })
            defaults.set(generated, forKey: historyScopeSaltDefaultsKey)
            salt = generated
        }
        let canonicalURL = url.standardizedFileURL.resolvingSymlinksInPath()
        let volumeValues = try? canonicalURL.resourceValues(forKeys: [.volumeIdentifierKey])
        let volumeIdentifier = volumeValues.flatMap(StorageFileIdentity.volumeIdentifier(from:)) ?? "unknown-volume"
        var hasher = SHA256()
        hasher.update(data: salt)
        hasher.update(data: Data("\(volumeIdentifier)\u{0}\(canonicalURL.path)".utf8))
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private nonisolated static func saturatingAdd(_ lhs: Int64, _ rhs: Int64) -> Int64 {
        let (sum, overflow) = lhs.addingReportingOverflow(rhs)
        return overflow ? Int64.max : sum
    }

    nonisolated static func categorize(
        url: URL,
        size _: Int64,
        isDirectory: Bool,
        lastModified _: Date?
    ) -> StorageCategory {
        let name = url.lastPathComponent.lowercased()
        return StoragePathCategoryContext(url: url).category(itemName: name, isDirectory: isDirectory)
    }

    fileprivate nonisolated static func fileFacets(
        size: Int64,
        lastModified: Date?,
        oldFileCutoff: Date
    ) -> (isLargeFile: Bool, isOldFile: Bool) {
        (
            isLargeFile: size >= 104_857_600,
            isOldFile: lastModified.map { $0 < oldFileCutoff } ?? false
        )
    }

    fileprivate nonisolated static func isSystemProtected(url: URL) -> Bool {
        StorageDeletionPolicy.isProtectedLocation(url)
    }

}