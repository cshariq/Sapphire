//
//  DragStateManager.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-08-12.
//

import AppKit
import Combine
import UniformTypeIdentifiers

struct DraggedFilePreview: Identifiable, Equatable {
    let id: String
    let url: URL
    let fileName: String
    let icon: NSImage

    static func == (lhs: DraggedFilePreview, rhs: DraggedFilePreview) -> Bool {
        lhs.id == rhs.id
    }
}

enum FileDragPasteboard {
    static let legacyFilenamesType = NSPasteboard.PasteboardType("NSFilenamesPboardType")

    static func containsFiles(
        _ pasteboard: NSPasteboard,
        newerThan baselineChangeCount: Int? = nil
    ) -> Bool {
        if let baselineChangeCount, pasteboard.changeCount == baselineChangeCount {
            return false
        }
        if pasteboard.canReadObject(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) {
            return true
        }
        return !(legacyFilePaths(from: pasteboard)?.isEmpty ?? true)
    }

    static func fileURLs(from pasteboard: NSPasteboard) -> [URL] {
        if let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL], !urls.isEmpty {
            return urls
        }

        if let paths = legacyFilePaths(from: pasteboard), !paths.isEmpty {
            return paths.map(URL.init(fileURLWithPath:))
        }

        guard let items = pasteboard.pasteboardItems else { return [] }
        return items.compactMap { item in
            guard let value = item.string(forType: .fileURL) else { return nil }
            let decoded = value.removingPercentEncoding ?? value
            if let url = URL(string: decoded), url.isFileURL {
                return url
            }
            return decoded.hasPrefix("/") ? URL(fileURLWithPath: decoded) : nil
        }
    }

    private static func legacyFilePaths(from pasteboard: NSPasteboard) -> [String]? {
        pasteboard.propertyList(forType: legacyFilenamesType) as? [String]
    }
}

@MainActor
class DragStateManager: ObservableObject {
    static let shared = DragStateManager()
    @Published var isDraggingFromShelf = false
    @Published var didJustDrop = false
    @Published private(set) var draggedFilePreviews: [DraggedFilePreview] = []

    private var shelfDragItemID: UUID?
    private var shelfDragLocalMouseUpMonitor: Any?
    private var shelfDragGlobalMouseUpToken: UUID?

    private init() {}

    func beginShelfDrag(item: ShelfItem) {
        isDraggingFromShelf = true
        shelfDragItemID = item.id
        startShelfDragMouseUpMonitor()
    }

    private func startShelfDragMouseUpMonitor() {
        guard shelfDragLocalMouseUpMonitor == nil, shelfDragGlobalMouseUpToken == nil else { return }

        shelfDragLocalMouseUpMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] event in
            Task { @MainActor in
                self?.endShelfDragIfNeeded()
            }
            return event
        }
        shelfDragGlobalMouseUpToken = EventMonitorHub.shared.register(for: .leftMouseUp) { [weak self] _ in
            Task { @MainActor in
                self?.endShelfDragIfNeeded()
            }
        }
    }

    private func endShelfDragIfNeeded() {
        guard isDraggingFromShelf || shelfDragItemID != nil else { return }
        let itemID = shelfDragItemID
        isDraggingFromShelf = false
        shelfDragItemID = nil
        stopShelfDragMouseUpMonitor()

        guard SettingsModel.shared.settings.removeFileFromShelfAfterDrag,
              let itemID,
              let item = FileShelfManager.shared.files.first(where: { $0.id == itemID }) else {
            return
        }
        FileShelfManager.shared.removeFile(item)
    }

    private func stopShelfDragMouseUpMonitor() {
        if let monitor = shelfDragLocalMouseUpMonitor {
            NSEvent.removeMonitor(monitor)
            shelfDragLocalMouseUpMonitor = nil
        }
        if let token = shelfDragGlobalMouseUpToken {
            EventMonitorHub.shared.unregister(token: token, for: .leftMouseUp)
            shelfDragGlobalMouseUpToken = nil
        }
    }

    func refreshDraggedFilePreviews() {
        let pasteboard = NSPasteboard(name: .drag)
        let urls = FileDragPasteboard.fileURLs(from: pasteboard)
        guard !urls.isEmpty else {
            if !draggedFilePreviews.isEmpty {
                draggedFilePreviews = []
            }
            return
        }

        let previews = urls.prefix(4).map { url in
            DraggedFilePreview(
                id: url.path,
                url: url,
                fileName: url.lastPathComponent,
                icon: NSWorkspace.shared.icon(forFile: url.path)
            )
        }
        if previews.map(\.id) != draggedFilePreviews.map(\.id) {
            draggedFilePreviews = Array(previews)
        }
    }

    func clearDraggedFilePreviews() {
        if !draggedFilePreviews.isEmpty {
            draggedFilePreviews = []
        }
    }

}