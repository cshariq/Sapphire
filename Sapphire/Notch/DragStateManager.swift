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

@MainActor
class DragStateManager: ObservableObject {
    static let shared = DragStateManager()
    @Published var isDraggingFromShelf = false
    @Published var didJustDrop = false
    @Published private(set) var draggedFilePreviews: [DraggedFilePreview] = []

    private var shelfDragItemID: UUID?
    private var shelfDragLocalMouseUpMonitor: Any?
    private var shelfDragGlobalMouseUpMonitor: Any?

    private init() {}

    func beginShelfDrag(item: ShelfItem) {
        isDraggingFromShelf = true
        shelfDragItemID = item.id
        startShelfDragMouseUpMonitor()
    }

    private func startShelfDragMouseUpMonitor() {
        guard shelfDragLocalMouseUpMonitor == nil, shelfDragGlobalMouseUpMonitor == nil else { return }

        shelfDragLocalMouseUpMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] event in
            Task { @MainActor in
                self?.endShelfDragIfNeeded()
            }
            return event
        }
        shelfDragGlobalMouseUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] _ in
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
        if let monitor = shelfDragGlobalMouseUpMonitor {
            NSEvent.removeMonitor(monitor)
            shelfDragGlobalMouseUpMonitor = nil
        }
    }

    func refreshDraggedFilePreviews() {
        let pasteboard = NSPasteboard(name: .drag)
        let urls = Self.readFileURLs(from: pasteboard)
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

    private static func readFileURLs(from pasteboard: NSPasteboard) -> [URL] {
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true
        ]) as? [URL], !urls.isEmpty {
            return urls
        }

        if let items = pasteboard.pasteboardItems {
            var urls: [URL] = []
            for item in items {
                if let path = item.string(forType: .fileURL) {
                    let decoded = path.removingPercentEncoding ?? path
                    if let url = URL(string: decoded), url.isFileURL {
                        urls.append(url)
                    } else if decoded.hasPrefix("/") {
                        urls.append(URL(fileURLWithPath: decoded))
                    }
                }
            }
            if !urls.isEmpty { return urls }
        }
        return []
    }
}