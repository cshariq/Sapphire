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

    private init() {
        let fileManager = FileManager.default
        guard let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            fatalError("Could not find Application Support directory.")
        }
        storageURL = appSupportURL.appendingPathComponent("com.shariq.Sapphire.FileShelf")

        if !fileManager.fileExists(atPath: storageURL.path) {
            try? fileManager.createDirectory(at: storageURL, withIntermediateDirectories: true, attributes: nil)
        }

        loadFiles()
        cleanupExpiredFiles()
    }

    func addFiles(from urls: [URL]) {
        let newItems = urls.map { url in
            ShelfItem(id: UUID(), storedAt: url, dateAdded: Date())
        }
        if !newItems.isEmpty {
            files.insert(contentsOf: newItems, at: 0)
            saveFiles()
        }
    }

    func addText(_ content: String, named defaultName: String = "Note") {
        let uniqueID = UUID()
        let destinationURL = storageURL
            .appendingPathComponent(uniqueID.uuidString)
            .appendingPathComponent("\(defaultName).txt")

        do {
            try FileManager.default.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try content.write(to: destinationURL, atomically: true, encoding: .utf8)
            let newItem = ShelfItem(id: uniqueID, storedAt: destinationURL, dateAdded: Date())
            files.insert(newItem, at: 0)
            saveFiles()
        } catch {
            print("[FileShelfManager] Error saving text to shelf: \(error)")
        }
    }

    func removeFile(_ item: ShelfItem) {
        files.removeAll { $0.id == item.id }
        saveFiles()
    }

    /// BETA
    func togglePin(_ item: ShelfItem) {
        guard let index = files.firstIndex(where: { $0.id == item.id }) else { return }
        files[index].isPinned.toggle()
        saveFiles()
    }

    func renameFile(_ item: ShelfItem, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != item.storedAt.lastPathComponent else { return }

        let directory = item.storedAt.deletingLastPathComponent()
        let destination = directory.appendingPathComponent(trimmed)

        do {
            try FileManager.default.moveItem(at: item.storedAt, to: destination)
            if let index = files.firstIndex(where: { $0.id == item.id }) {
                files[index].storedAt = destination
            }
            saveFiles()
        } catch {
            print("[FileShelfManager] Error renaming file: \(error)")
        }
    }

    func duplicateFile(_ item: ShelfItem) {
        let baseName = item.storedAt.deletingPathExtension().lastPathComponent
        let fileExtension = item.storedAt.pathExtension
        let copyName: String
        if fileExtension.isEmpty {
            copyName = "\(baseName) Copy"
        } else {
            copyName = "\(baseName) Copy.\(fileExtension)"
        }

        let destination = item.storedAt
            .deletingLastPathComponent()
            .appendingPathComponent(copyName)

        do {
            try FileManager.default.copyItem(at: item.storedAt, to: destination)
            let newItem = ShelfItem(id: UUID(), storedAt: destination, dateAdded: Date())
            files.insert(newItem, at: 0)
            saveFiles()
        } catch {
            print("[FileShelfManager] Error duplicating file: \(error)")
        }
    }

    func shelfURL(for id: UUID) -> URL? {
        files.first { $0.id == id }?.storedAt
    }

    private func saveFiles() {
        do {
            let encoded = try JSONEncoder().encode(files)
            UserDefaults.standard.set(encoded, forKey: "FileShelfItemsV3")
        } catch {
            print("[FileShelfManager] Error saving file list: \(error)")
        }
    }

    private func loadFiles() {
        guard let data = UserDefaults.standard.data(forKey: "FileShelfItemsV3") else { return }
        do {
            let decoded = try JSONDecoder().decode([ShelfItem].self, from: data)
            self.files = decoded.filter { FileManager.default.fileExists(atPath: $0.storedAt.path) }
        } catch {
            print("[FileShelfManager] Error decoding file list: \(error)")
        }
    }

    private func cleanupExpiredFiles() {
        let oneDayAgo = Date().addingTimeInterval(-24 * 60 * 60)
        let expiredFiles = files.filter { !$0.isPinned && $0.dateAdded < oneDayAgo }
        if !expiredFiles.isEmpty {
            for file in expiredFiles {
                removeFile(file)
            }
        }
    }

    func trimCache() {
        let expired = files.filter { !$0.isPinned && $0.dateAdded < Date().addingTimeInterval(-3600) }
        for file in expired { removeFile(file) }
    }
}

// MARK: - Models

struct ShelfItem: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var storedAt: URL
    let dateAdded: Date
    /// BETA: pinned items are exempt from the shelf's automatic expiry cleanup.
    var isPinned: Bool = false

    var fileName: String { storedAt.lastPathComponent }
    var icon: NSImage { NSWorkspace.shared.icon(forFile: storedAt.path) }

    init(id: UUID, storedAt: URL, dateAdded: Date, isPinned: Bool = false) {
        self.id = id
        self.storedAt = storedAt
        self.dateAdded = dateAdded
        self.isPinned = isPinned
    }

    private enum CodingKeys: String, CodingKey {
        case id, storedAt, dateAdded, isPinned
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        storedAt = try container.decode(URL.self, forKey: .storedAt)
        dateAdded = try container.decode(Date.self, forKey: .dateAdded)
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
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
        .contextMenu {
            Button(item.isPinned ? "Unpin" : "Pin (Beta)") { manager.togglePin(item) }
            Button("Remove", role: .destructive) { manager.removeFile(item) }
        }
    }

    @ViewBuilder
    private var thumbnailView: some View {
        ZStack(alignment: .topTrailing) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.secondary.opacity(0.25))
                Image(systemName: IconGenerator.symbolName(for: item))
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)
            }

            if item.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white, .orange)
                    .symbolRenderingMode(.palette)
                    .padding(3)
                    .background(Circle().fill(.black.opacity(0.55)))
                    .offset(x: -3, y: 3)
                    .help("Pinned (Beta) — exempt from automatic shelf cleanup")
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

private struct IconGenerator {
    static func symbolName(for item: ShelfItem) -> String {
        guard let type = try? item.storedAt.resourceValues(forKeys: [.contentTypeKey]).contentType else {
            return "doc.fill"
        }

        if type.conforms(to: .image) { return "photo.fill" }
        if type.conforms(to: .movie) { return "video.fill" }
        if type.conforms(to: .audio) { return "music.note" }
        if type.conforms(to: .pdf) { return "doc.richtext.fill" }
        if type.conforms(to: .text) { return "doc.text.fill" }
        if type.conforms(to: .folder) { return "folder.fill" }
        if type.conforms(to: .archive) { return "archivebox.fill" }

        return "doc.fill"
    }
}