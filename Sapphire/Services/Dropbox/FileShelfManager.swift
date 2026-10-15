//
//  FileShelfManager.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-08-12.
//

import SwiftUI
import UniformTypeIdentifiers
import QuickLookUI

class FileShelfState: ObservableObject {
    @Published var selectedItemForPreview: ShelfItem?
}

// MARK: - File Shelf Manager (Singleton)

@MainActor
class FileShelfManager: ObservableObject {
    static let shared = FileShelfManager()

    @Published var files: [ShelfItem] = []
    private let storageURL: URL
    private let legacyTemporaryRoot: URL
    private let ioQueue = DispatchQueue(label: "com.sapphire.file-shelf.io", qos: .utility)
    private var expiryTimer: Timer?
    private var activeCopies = 0
    private var copyProgress: [UUID: (copied: Int64, total: Int64)] = [:]

    private nonisolated static let defaultsKey = "FileShelfItemsV3"
    private static let expiryInterval: TimeInterval = 24 * 60 * 60
    private static let deletionGrace: TimeInterval = 120

    private init() {
        let fileManager = FileManager.default
        let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        storageURL = appSupportURL.appendingPathComponent("com.shariq.Sapphire.FileShelf", isDirectory: true)
        legacyTemporaryRoot = fileManager.temporaryDirectory
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "com.shariq.Sapphire")
            .appendingPathComponent("TemporaryDrop", isDirectory: true)

        try? fileManager.createDirectory(at: storageURL, withIntermediateDirectories: true, attributes: nil)

        loadFiles()
    }

    // MARK: - Adding

    func addFiles(from urls: [URL]) {
        let fileURLs = urls.filter(\.isFileURL)
        guard !fileURLs.isEmpty else { return }
        let storageURL = storageURL
        let legacyRoot = legacyTemporaryRoot
        ioQueue.async { [weak self] in
            var referenced: [ShelfItem] = []
            var toPark: [URL] = []
            for url in fileURLs {
                let standardized = url.standardizedFileURL
                guard FileManager.default.fileExists(atPath: standardized.path) else { continue }
                if Self.isInside(standardized, storageURL) || Self.isInside(standardized, legacyRoot) {
                    referenced.append(ShelfItem(id: UUID(), storedAt: standardized, dateAdded: Date(), isOwnedCopy: true))
                } else if Self.isVolatileLocation(standardized) {
                    toPark.append(standardized)
                } else {
                    referenced.append(ShelfItem(
                        id: UUID(), storedAt: standardized, dateAdded: Date(),
                        bookmark: try? standardized.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
                    ))
                }
            }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.insert(referenced)
                    if !toPark.isEmpty { self.park(toPark) }
                }
            }
        }
    }

    func addText(_ content: String, named defaultName: String = "Note") {
        let uniqueID = UUID()
        let safeName = defaultName.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        let destinationURL = storageURL
            .appendingPathComponent(uniqueID.uuidString)
            .appendingPathComponent("\(safeName.isEmpty ? "Note" : safeName).txt")
        ioQueue.async { [weak self] in
            do {
                try FileManager.default.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try content.write(to: destinationURL, atomically: true, encoding: .utf8)
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        self?.insert([ShelfItem(id: uniqueID, storedAt: destinationURL, dateAdded: Date(), isOwnedCopy: true)])
                    }
                }
            } catch {
                try? FileManager.default.removeItem(at: destinationURL.deletingLastPathComponent())
                print("[FileShelfManager] Error saving text to shelf: \(error)")
            }
        }
    }

    private func insert(_ items: [ShelfItem]) {
        guard !items.isEmpty else { return }
        let paths = Set(items.map(\.storedAt.path))
        files.removeAll { paths.contains($0.storedAt.path) }
        files.insert(contentsOf: items, at: 0)
        saveFiles()
        updateExpiryTimer()
    }

    // MARK: - Parking (copies into Sapphire's storage)

    private func park(_ sources: [URL], renamedTo newName: String? = nil, replacing replacedID: UUID? = nil) {
        let batchID = UUID()
        let storageURL = storageURL
        activeCopies += 1
        ioQueue.async { [weak self] in
            let total = sources.reduce(Int64(0)) { $0 + Self.allocatedSize(of: $1) }
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.reportProgress(batchID: batchID, copied: 0, total: total, name: sources.first?.lastPathComponent) }
            }
            var parked: [ShelfItem] = []
            var copiedSoFar: Int64 = 0
            for source in sources {
                let id = UUID()
                let folder = storageURL.appendingPathComponent(id.uuidString, isDirectory: true)
                let destination = folder.appendingPathComponent(newName ?? source.lastPathComponent)
                do {
                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    let base = copiedSoFar
                    let poller = Self.startProgressPoller(destination: destination) { bytes in
                        DispatchQueue.main.async {
                            MainActor.assumeIsolated {
                                self?.reportProgress(batchID: batchID, copied: base + bytes, total: total, name: source.lastPathComponent)
                            }
                        }
                    }
                    defer { poller.cancel() }
                    try FileManager.default.copyItem(at: source, to: destination)
                    copiedSoFar += Self.allocatedSize(of: destination)
                    parked.append(ShelfItem(id: id, storedAt: destination, dateAdded: Date(), isOwnedCopy: true))
                } catch {
                    try? FileManager.default.removeItem(at: folder)
                    print("[FileShelfManager] Could not park \(source.lastPathComponent): \(error.localizedDescription)")
                }
            }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.activeCopies -= 1
                    self.finishProgress(batchID: batchID)
                    if let replacedID, let index = self.files.firstIndex(where: { $0.id == replacedID }), let replacement = parked.first {
                        self.files[index] = replacement
                        self.saveFiles()
                    } else {
                        self.insert(parked)
                    }
                }
            }
        }
    }

    private func reportProgress(batchID: UUID, copied: Int64, total: Int64, name: String?) {
        copyProgress[batchID] = (copied, total)
        let copiedAll = copyProgress.values.reduce(Int64(0)) { $0 + $1.copied }
        let totalAll = copyProgress.values.reduce(Int64(0)) { $0 + $1.total }
        guard totalAll > 50 * 1024 * 1024 else { return }
        let placeholder = storageURL.appendingPathComponent("shelf-copy")
        FileDropManager.shared.updateExternalTask(FileTransferTask(
            fileURL: placeholder,
            fileName: copyProgress.count > 1 ? "Adding \(copyProgress.count) items to Shelf" : "Adding \(name ?? "file") to Shelf",
            destinationURL: placeholder,
            currentSize: min(copiedAll, totalAll),
            totalSize: totalAll,
            lastChangeDate: Date(),
            sourceType: .manual
        ), sourceType: .manual)
    }

    private func finishProgress(batchID: UUID) {
        copyProgress.removeValue(forKey: batchID)
        if copyProgress.isEmpty {
            FileDropManager.shared.updateExternalTask(nil, sourceType: .manual)
        }
    }

    private nonisolated static func startProgressPoller(destination: URL, report: @escaping (Int64) -> Void) -> DispatchSourceTimer {
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        timer.schedule(deadline: .now() + 0.3, repeating: 0.3, leeway: .milliseconds(100))
        timer.setEventHandler { report(allocatedSize(of: destination)) }
        timer.resume()
        return timer
    }

    // MARK: - Removing

    func removeFile(_ item: ShelfItem) {
        files.removeAll { $0.id == item.id }
        saveFiles()
        updateExpiryTimer()
        guard let folder = ownedFolder(for: item) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.deletionGrace) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.files.contains(where: { Self.isInside($0.storedAt, folder) }) else { return }
                self.ioQueue.async { try? FileManager.default.removeItem(at: folder) }
            }
        }
    }

    private func ownedFolder(for item: ShelfItem) -> URL? {
        let path = item.storedAt.standardizedFileURL
        for root in [storageURL, legacyTemporaryRoot] where Self.isInside(path, root) {
            let resolvedRoot = root.standardizedFileURL.resolvingSymlinksInPath().pathComponents
            let components = path.resolvingSymlinksInPath().pathComponents
            guard components.count > resolvedRoot.count else { return nil }
            return URL(fileURLWithPath: NSString.path(withComponents: Array(components.prefix(resolvedRoot.count + 1))))
        }
        return nil
    }

    // MARK: - Rename / duplicate

    func renameFile(_ item: ShelfItem, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        guard !trimmed.isEmpty, trimmed != item.storedAt.lastPathComponent else { return }

        guard item.isOwnedCopy, ownedFolder(for: item) != nil else {
            park([item.storedAt], renamedTo: trimmed, replacing: item.id)
            return
        }

        let destination = item.storedAt.deletingLastPathComponent().appendingPathComponent(trimmed)
        let source = item.storedAt
        ioQueue.async { [weak self] in
            do {
                guard !FileManager.default.fileExists(atPath: destination.path) else {
                    throw CocoaError(.fileWriteFileExists)
                }
                try FileManager.default.moveItem(at: source, to: destination)
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        guard let self, let index = self.files.firstIndex(where: { $0.id == item.id }) else { return }
                        self.files[index].storedAt = destination
                        self.saveFiles()
                    }
                }
            } catch {
                print("[FileShelfManager] Error renaming file: \(error)")
                DispatchQueue.main.async { NSSound.beep() }
            }
        }
    }

    func duplicateFile(_ item: ShelfItem) {
        let name = UniqueFileName.copyName(for: item.storedAt.lastPathComponent)
        park([item.storedAt], renamedTo: name)
    }

    func shelfURL(for id: UUID) -> URL? {
        files.first { $0.id == id }?.storedAt
    }

    // MARK: - Persistence

    private func saveFiles() {
        let snapshot = files
        ioQueue.async {
            do {
                let encoded = try JSONEncoder().encode(snapshot)
                UserDefaults.standard.set(encoded, forKey: Self.defaultsKey)
            } catch {
                print("[FileShelfManager] Error saving file list: \(error)")
            }
        }
    }

    private func loadFiles() {
        guard let data = UserDefaults.standard.data(forKey: Self.defaultsKey) else {
            sweepOrphans(keeping: [])
            return
        }
        do {
            files = try JSONDecoder().decode([ShelfItem].self, from: data)
        } catch {
            print("[FileShelfManager] Error decoding file list: \(error)")
            return
        }
        refreshFiles(sweepingOrphans: true)
    }

    private func refreshFiles(sweepingOrphans: Bool = false) {
        let snapshot = files
        let cutoff = Date().addingTimeInterval(-Self.expiryInterval)
        ioQueue.async { [weak self] in
            var expired: [ShelfItem] = []
            let validated: [ShelfItem] = snapshot.compactMap { item in
                if item.dateAdded < cutoff {
                    expired.append(item)
                    return nil
                }
                return Self.validated(item)
            }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    let checkedIDs = Set(snapshot.map(\.id))
                    let validatedByID = Dictionary(uniqueKeysWithValues: validated.map { ($0.id, $0) })
                    let merged = self.files.compactMap { item -> ShelfItem? in
                        guard checkedIDs.contains(item.id) else { return item }
                        return validatedByID[item.id]
                    }
                    if merged != self.files {
                        self.files = merged
                        self.saveFiles()
                    }
                    for item in expired { self.removeFile(item) }
                    if sweepingOrphans, self.activeCopies == 0 { self.sweepOrphans(keeping: merged) }
                    self.updateExpiryTimer()
                }
            }
        }
    }

    private nonisolated static func validated(_ item: ShelfItem) -> ShelfItem? {
        if FileManager.default.fileExists(atPath: item.storedAt.path) { return item }
        guard let bookmark = item.bookmark else { return nil }
        var isStale = false
        guard let resolved = try? URL(resolvingBookmarkData: bookmark, options: [.withoutUI, .withoutMounting],
                                      relativeTo: nil, bookmarkDataIsStale: &isStale),
              FileManager.default.fileExists(atPath: resolved.path) else { return nil }
        var moved = item
        moved.storedAt = resolved
        if isStale { moved.bookmark = try? resolved.bookmarkData() }
        return moved
    }

    private func sweepOrphans(keeping items: [ShelfItem]) {
        let referenced = Set(items.map { $0.storedAt.standardizedFileURL.path })
        let roots = [storageURL, legacyTemporaryRoot]
        ioQueue.async {
            let fileManager = FileManager.default
            for root in roots {
                let children = (try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
                for child in children {
                    let childPath = child.standardizedFileURL.path
                    let inUse = referenced.contains { $0 == childPath || $0.hasPrefix(childPath + "/") }
                    if !inUse { try? fileManager.removeItem(at: child) }
                }
            }
        }
    }

    // MARK: - Expiry

    private func updateExpiryTimer() {
        if files.isEmpty {
            expiryTimer?.invalidate()
            expiryTimer = nil
            return
        }
        guard expiryTimer == nil else { return }
        let timer = Timer(timeInterval: 15 * 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshFiles() }
        }
        timer.tolerance = 60
        RunLoop.main.add(timer, forMode: .common)
        expiryTimer = timer
    }

    func trimCache() {
        let expired = files.filter { $0.dateAdded < Date().addingTimeInterval(-3600) }
        for file in expired { removeFile(file) }
    }

    // MARK: - Locations

    nonisolated static func isInside(_ url: URL, _ root: URL) -> Bool {
        let path = url.standardizedFileURL.resolvingSymlinksInPath().path
        let rootPath = root.standardizedFileURL.resolvingSymlinksInPath().path
        return path.hasPrefix(rootPath.hasSuffix("/") ? rootPath : rootPath + "/")
    }

    nonisolated static func isVolatileLocation(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.resolvingSymlinksInPath().path
        let volatileRoots = [
            FileManager.default.temporaryDirectory.resolvingSymlinksInPath().path,
            "/private/var/folders/", "/private/tmp/", "/tmp/",
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Caches").path,
        ]
        return volatileRoots.contains { path.hasPrefix($0) }
    }

    nonisolated static func allocatedSize(of url: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isDirectoryKey]
        guard let values = try? url.resourceValues(forKeys: keys) else { return 0 }
        if values.isDirectory != true {
            return Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        }
        var total: Int64 = 0
        let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(keys))
        while let child = enumerator?.nextObject() as? URL {
            let childValues = try? child.resourceValues(forKeys: keys)
            total += Int64(childValues?.totalFileAllocatedSize ?? childValues?.fileAllocatedSize ?? 0)
        }
        return total
    }
}

// MARK: - Models

struct ShelfItem: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var storedAt: URL
    let dateAdded: Date
    var bookmark: Data?
    var isOwnedCopy: Bool

    var fileName: String { storedAt.lastPathComponent }

    init(id: UUID, storedAt: URL, dateAdded: Date, bookmark: Data? = nil, isOwnedCopy: Bool = false) {
        self.id = id
        self.storedAt = storedAt
        self.dateAdded = dateAdded
        self.bookmark = bookmark
        self.isOwnedCopy = isOwnedCopy
    }

    private enum CodingKeys: String, CodingKey {
        case id, storedAt, dateAdded, bookmark, isOwnedCopy
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        storedAt = try container.decode(URL.self, forKey: .storedAt)
        dateAdded = try container.decode(Date.self, forKey: .dateAdded)
        bookmark = try container.decodeIfPresent(Data.self, forKey: .bookmark)
        isOwnedCopy = try container.decodeIfPresent(Bool.self, forKey: .isOwnedCopy)
            ?? (storedAt.path.contains("/TemporaryDrop/") || storedAt.path.contains("/com.shariq.Sapphire.FileShelf/"))
    }
}

// MARK: - Main Shelf View (RESTORED)

struct FileShelfView: View {
    @StateObject private var manager = FileShelfManager.shared

    var body: some View {
        ShelfContentView(files: manager.files)
    }
}

// MARK: - Shelf Content View

private struct ShelfContentView: View {
    let files: [ShelfItem]
    @EnvironmentObject private var state: FileShelfState

    var body: some View {
        HStack(spacing: 15) {
            FileShelfScrollView(files: files, onSelect: { item in
                state.selectedItemForPreview = item
            })
        }
        .padding(15)
        .frame(width: 680, height: 140)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: files.isEmpty)
    }
}

private struct ShelfEmptyStateView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray")
                .font(.system(size: 36, weight: .light))
                .foregroundColor(.white.opacity(0.6))
            Text("Shelf is Empty")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white.opacity(0.8))
            Text("Drag files here to add them.")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct FileShelfScrollView: View {
    let files: [ShelfItem]
    let onSelect: (ShelfItem) -> Void

    var body: some View {
        Group {
            if files.isEmpty {
                ShelfEmptyStateView()
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 20) {
                        ForEach(files) { file in
                            FileShelfItemView(item: file, onSelect: onSelect)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                }
                .transition(.opacity)
            }
        }
        .frame(height: 110)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(style: StrokeStyle(lineWidth: 1.5, dash: [7]))
                .foregroundColor(.white.opacity(0.25))
        )
    }
}

private struct FileShelfItemView: View {
    let item: ShelfItem
    let onSelect: (ShelfItem) -> Void
    @StateObject private var manager = FileShelfManager.shared
    @EnvironmentObject private var dragState: DragStateManager

    @State private var isHovering = false

    var body: some View {
        VStack(spacing: 6) {
            thumbnailView
                .onTapGesture { onSelect(item) }

            Text(item.fileName)
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.8))
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
        }
        .frame(width: 85)
        .padding(.vertical, 8)
        .background(.white.opacity(isHovering ? 0.15 : 0), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .scaleEffect(isHovering ? 1.05 : 1.0)
        .onDrag {
            dragState.beginShelfDrag(item: item)
            return NSItemProvider(object: item.storedAt as NSURL)
        }
        .onHover { hovering in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isHovering = hovering
            }
        }
    }

    @ViewBuilder
    private var thumbnailView: some View {
        ZStack(alignment: .topTrailing) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.secondary.opacity(0.25))
                Image(systemName: item.storedAt.sapphireFileSymbolName)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)
            }

            if isHovering {
                Button(action: { manager.removeFile(item) }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .red)
                }
                .buttonStyle(.plain)
                .offset(x: 5, y: -5)
                .transition(.scale.animation(.spring(response: 0.2, dampingFraction: 0.6)))
            }
        }
        .frame(width: 50, height: 50)
    }
}