//
//  ClipboardManager.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-10

import AppKit

struct ClipboardItem: Identifiable, Equatable, Codable {
    let id: String
    let preview: String
    let copiedAt: Date
    let isImage: Bool
    let textContent: String?
    let imagePNGData: Data?

    static func == (lhs: ClipboardItem, rhs: ClipboardItem) -> Bool {
        lhs.id == rhs.id
    }
}

@MainActor
final class ClipboardManager: ObservableObject {
    static let shared = ClipboardManager()

    @Published private(set) var recentItems: [ClipboardItem] = []

    private var pollTimer: Timer?
    private var lastChangeCount: Int = NSPasteboard.general.changeCount
    private var highPriorityConsumers = 0
    private let maxImageBytes = 8 * 1024 * 1024
    private let secureFileURL: URL
    private var persistWorkItem: DispatchWorkItem?

    private var maxItems: Int? {
        let settings = SettingsModel.shared.settings
        if settings.clipboardHistoryUnlimited || settings.clipboardHistoryLimit <= 0 {
            return nil
        }
        return max(4, settings.clipboardHistoryLimit)
    }

    private var pollInterval: TimeInterval {
        if highPriorityConsumers > 0 { return 1.0 }
        if NotchRuntimeState.shared.shouldReduceBackgroundWork { return 5.0 }
        return 3.5
    }

    private init() {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDirectory = appSupport.appendingPathComponent(Bundle.main.bundleIdentifier ?? "com.sapphire.app")
        if !fileManager.fileExists(atPath: appDirectory.path) {
            try? fileManager.createDirectory(at: appDirectory, withIntermediateDirectories: true)
        }
        secureFileURL = appDirectory.appendingPathComponent("clipboard_history.encrypted")
        loadPersistedHistory()
    }

    func startMonitoring() {
        guard SettingsModel.shared.settings.clipboardMonitoringEnabled else { return }
        restartPollingIfNeeded(force: pollTimer == nil)
        captureCurrentIfNeeded()
    }

    func beginHighPriorityPolling() {
        highPriorityConsumers += 1
        if SettingsModel.shared.settings.clipboardMonitoringEnabled {
            restartPollingIfNeeded(force: true)
        }
    }

    func endHighPriorityPolling() {
        highPriorityConsumers = max(0, highPriorityConsumers - 1)
        if pollTimer != nil {
            restartPollingIfNeeded(force: true)
        }
    }

    func stopMonitoring() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func restartPollingIfNeeded(force: Bool) {
        let interval = pollInterval
        if !force, let pollTimer, pollTimer.isValid, abs(pollTimer.timeInterval - interval) < 0.01 {
            return
        }
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.captureCurrentIfNeeded()
            }
        }
        if let pollTimer {
            RunLoop.main.add(pollTimer, forMode: .common)
        }
    }

    func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        lastChangeCount = NSPasteboard.general.changeCount
        prependText(text)
    }

    func copyItem(_ item: ClipboardItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if item.isImage, let data = item.imagePNGData, let image = NSImage(data: data) {
            pasteboard.writeObjects([image])
            pasteboard.setData(data, forType: .png)
        } else if let text = item.textContent ?? (item.isImage ? nil : item.preview) {
            pasteboard.setString(text, forType: .string)
        }
        lastChangeCount = pasteboard.changeCount
    }

    func removeItem(id: String) {
        recentItems.removeAll { $0.id == id }
        schedulePersist()
    }

    func clearHistory() {
        recentItems.removeAll()
        persistHistoryImmediately()
    }

    func shareItem(_ item: ClipboardItem, relativeTo view: NSView? = nil) {
        var items: [Any] = []
        if item.isImage, let data = item.imagePNGData, let image = NSImage(data: data) {
            items.append(image)
        } else if let text = item.textContent ?? (item.isImage ? nil : item.preview) {
            items.append(text)
        }
        guard !items.isEmpty else { return }

        let picker = NSSharingServicePicker(items: items)
        if let view {
            picker.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
        } else if let window = NSApp.keyWindow ?? NSApp.windows.first(where: { $0.isVisible }),
                  let content = window.contentView {
            let rect = NSRect(x: content.bounds.midX - 1, y: content.bounds.midY - 1, width: 2, height: 2)
            picker.show(relativeTo: rect, of: content, preferredEdge: .minY)
        }
    }

    private func captureCurrentIfNeeded() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount

        // Check if clipboard contains concealed/transient/auto-generated types
        let types = pasteboard.types ?? []
        let settings = SettingsModel.shared.settings
        if settings.clipboardIgnoreConcealedItems {
            let ignoredTypes: Set<NSPasteboard.PasteboardType> = [
                .init("org.nspasteboard.ConcealedType"),
                .init("org.nspasteboard.TransientType"),
                .init("org.nspasteboard.AutoGeneratedType")
            ]
            if !types.filter({ ignoredTypes.contains($0) }).isEmpty {
                return // Skip storing this item
            }
        }

        if let imageData = extractPNGData(from: pasteboard) {
            let image = NSImage(data: imageData)
            let w = Int(image?.size.width.rounded() ?? 0)
            let h = Int(image?.size.height.rounded() ?? 0)
            let preview = (w > 0 && h > 0) ? "Image \(w)×\(h)" : "Image"
            prependImage(pngData: imageData, preview: preview)
            return
        }

        if let string = pasteboard.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !string.isEmpty {
            prependText(string)
        }
    }

    private func extractPNGData(from pasteboard: NSPasteboard) -> Data? {
        if let png = pasteboard.data(forType: .png), !png.isEmpty, png.count <= maxImageBytes {
            return png
        }
        if let tiff = pasteboard.data(forType: .tiff),
           let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]),
           png.count <= maxImageBytes {
            return png
        }
        if let images = pasteboard.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage],
           let image = images.first,
           let tiff = image.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]),
           png.count <= maxImageBytes {
            return png
        }
        return nil
    }

    private func prependText(_ text: String) {
        let preview = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !preview.isEmpty else { return }

        let item = ClipboardItem(
            id: UUID().uuidString,
            preview: String(preview.prefix(240)),
            copiedAt: Date(),
            isImage: false,
            textContent: text,
            imagePNGData: nil
        )
        recentItems.removeAll {
            !$0.isImage && ($0.textContent == text || $0.preview == item.preview)
        }
        insert(item)
    }

    private func prependImage(pngData: Data, preview: String) {
        let item = ClipboardItem(
            id: UUID().uuidString,
            preview: preview,
            copiedAt: Date(),
            isImage: true,
            textContent: nil,
            imagePNGData: pngData
        )
        recentItems.removeAll { $0.isImage && $0.imagePNGData == pngData }
        insert(item)
    }

    private func insert(_ item: ClipboardItem) {
        recentItems.insert(item, at: 0)
        if let maxItems, recentItems.count > maxItems {
            recentItems = Array(recentItems.prefix(maxItems))
        }
        schedulePersist()
    }

    // MARK: - Secure Persistence

    private func schedulePersist() {
        persistWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.persistHistoryImmediately()
            }
        }
        persistWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    private func persistHistoryImmediately() {
        persistWorkItem?.cancel()
        persistWorkItem = nil

        do {
            if recentItems.isEmpty {
                if FileManager.default.fileExists(atPath: secureFileURL.path) {
                    try FileManager.default.removeItem(at: secureFileURL)
                }
                return
            }
            let jsonData = try JSONEncoder().encode(recentItems)
            guard let encrypted = CryptoManager.shared.encrypt(data: jsonData) else { return }
            try encrypted.write(to: secureFileURL, options: [.atomic])
        } catch {
            print("[ClipboardManager] Failed to persist history: \(error)")
        }
    }

    private func loadPersistedHistory() {
        guard FileManager.default.fileExists(atPath: secureFileURL.path) else { return }
        do {
            let encrypted = try Data(contentsOf: secureFileURL)
            guard let decrypted = CryptoManager.shared.decrypt(data: encrypted) else { return }
            var items = try JSONDecoder().decode([ClipboardItem].self, from: decrypted)
            if let maxItems, items.count > maxItems {
                items = Array(items.prefix(maxItems))
            }
            recentItems = items
        } catch {
            print("[ClipboardManager] Failed to load history: \(error)")
        }
    }
}