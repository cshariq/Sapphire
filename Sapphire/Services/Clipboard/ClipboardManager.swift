//
//  ClipboardManager.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-10

import AppKit
import Combine

@MainActor
final class PasteboardChangeMonitor {
    struct Token: Hashable {
        fileprivate let id = UUID()
    }

    static let shared = PasteboardChangeMonitor()

    private struct Subscription {
        var interval: TimeInterval
        let priority: Int
        let handler: (Int) -> Void
    }

    private var subscriptions: [Token: Subscription] = [:]
    private var fallbackTimer: Timer?
    private var fallbackTimerInterval: TimeInterval?
    private var eventMonitorTokens: [NSEvent.EventType: UUID] = [:]
    private var workspaceObservers: [NSObjectProtocol] = []
    private var applicationObservers: [NSObjectProtocol] = []
    private var pendingEventChecks: [DispatchWorkItem] = []
    private var lastChangeCount = NSPasteboard.general.changeCount

    private init() {}

    func subscribe(
        interval: TimeInterval,
        priority: Int = 0,
        handler: @escaping (Int) -> Void
    ) -> Token {
        let wasEmpty = subscriptions.isEmpty
        if wasEmpty {
            lastChangeCount = NSPasteboard.general.changeCount
        }
        let token = Token()
        subscriptions[token] = Subscription(
            interval: max(0.1, interval),
            priority: priority,
            handler: handler
        )
        if wasEmpty { startEventMonitoring() }
        synchronizeTimer()
        return token
    }

    func updateInterval(_ interval: TimeInterval, for token: Token) {
        guard var subscription = subscriptions[token] else { return }
        subscription.interval = max(0.1, interval)
        subscriptions[token] = subscription
        synchronizeTimer()
    }

    func unsubscribe(_ token: Token) {
        subscriptions.removeValue(forKey: token)
        if subscriptions.isEmpty { stopEventMonitoring() }
        synchronizeTimer()
    }

    private static let idleInputThreshold: TimeInterval = 30
    private static let activeFallbackInterval: TimeInterval = 10
    private static let idleFallbackInterval: TimeInterval = 30
    private static let highPriorityFallbackInterval: TimeInterval = 1
    private static let anyInputEvent = CGEventType(rawValue: ~0)!

    private func effectiveInterval(requested: TimeInterval) -> TimeInterval {
        if requested <= 0.25 {
            return Self.highPriorityFallbackInterval
        }
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: Self.anyInputEvent)
        return idle >= Self.idleInputThreshold
            ? Self.idleFallbackInterval
            : Self.activeFallbackInterval
    }

    private func synchronizeTimer() {
        guard let fastestInterval = subscriptions.values.map(\.interval).min() else {
            fallbackTimer?.invalidate()
            fallbackTimer = nil
            fallbackTimerInterval = nil
            return
        }
        let requestedInterval = effectiveInterval(requested: fastestInterval)
        guard fallbackTimer == nil || fallbackTimerInterval != requestedInterval else { return }

        fallbackTimer?.invalidate()
        fallbackTimerInterval = requestedInterval
        let timer = Timer(timeInterval: requestedInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = requestedInterval * 0.3
        RunLoop.main.add(timer, forMode: .common)
        fallbackTimer = timer
    }

    private var lastIdleCheck: CFAbsoluteTime = 0

    private func startEventMonitoring() {
        guard eventMonitorTokens.isEmpty else { return }
        eventMonitorTokens = EventMonitorHub.shared.register(
            for: [.keyDown, .leftMouseUp, .rightMouseUp, .otherMouseUp]
        ) { [weak self] event in
            guard let self else { return }
            if event.type == .keyDown {
                let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                guard modifiers.contains(.command), event.keyCode == 7 || event.keyCode == 8 else { return }
            }
            self.scheduleEventChecks()
        }

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        workspaceObservers = [
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.didWakeNotification,
            NSWorkspace.sessionDidBecomeActiveNotification,
        ].map { name in
            workspaceCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.scheduleEventChecks() }
            }
        }

        applicationObservers = [
            NotificationCenter.default.addObserver(
                forName: NSApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.scheduleEventChecks() }
            }
        ]
    }

    private func stopEventMonitoring() {
        EventMonitorHub.shared.unregister(tokens: eventMonitorTokens)
        eventMonitorTokens.removeAll()

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        workspaceObservers.forEach(workspaceCenter.removeObserver)
        workspaceObservers.removeAll()

        applicationObservers.forEach { NotificationCenter.default.removeObserver($0) }
        applicationObservers.removeAll()

        pendingEventChecks.forEach { $0.cancel() }
        pendingEventChecks.removeAll()
    }

    private func scheduleEventChecks() {
        pendingEventChecks.forEach { $0.cancel() }
        pendingEventChecks = [0.04, 0.25, 0.8].map { delay in
            let work = DispatchWorkItem { [weak self] in
                MainActor.assumeIsolated { self?.tick() }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
            return work
        }
    }

    private func tick() {
        let now = CFAbsoluteTimeGetCurrent()
        if now - lastIdleCheck >= Self.activeFallbackInterval {
            lastIdleCheck = now
            synchronizeTimer()
        }
        let changeCount = NSPasteboard.general.changeCount
        guard changeCount != lastChangeCount else { return }
        lastChangeCount = changeCount
        let handlers = subscriptions.values
            .sorted { $0.priority > $1.priority }
            .map(\.handler)
        for handler in handlers { handler(changeCount) }
        lastChangeCount = NSPasteboard.general.changeCount
    }
}

enum ClipboardItemKind: String, Codable, Sendable {
    case text
    case image
    case file
    case folder
}

struct ClipboardItem: Identifiable, Equatable, Codable, Sendable {
    let id: String
    let preview: String
    let copiedAt: Date
    let kind: ClipboardItemKind
    let textContent: String?
    let imagePNGData: Data?
    let fileURLString: String?
    let fileBookmarkData: Data?

    var isImage: Bool { kind == .image }

    static func == (lhs: ClipboardItem, rhs: ClipboardItem) -> Bool {
        lhs.id == rhs.id
    }

    private enum CodingKeys: String, CodingKey {
        case id, preview, copiedAt, kind, textContent, imagePNGData, fileURLString, fileBookmarkData
    }
}

extension ClipboardItem {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        preview = try container.decode(String.self, forKey: .preview)
        copiedAt = try container.decode(Date.self, forKey: .copiedAt)
        textContent = try container.decodeIfPresent(String.self, forKey: .textContent)
        imagePNGData = try container.decodeIfPresent(Data.self, forKey: .imagePNGData)
        fileURLString = try container.decodeIfPresent(String.self, forKey: .fileURLString)
        fileBookmarkData = try container.decodeIfPresent(Data.self, forKey: .fileBookmarkData)
        if let rawKind = try container.decodeIfPresent(String.self, forKey: .kind),
           let decodedKind = ClipboardItemKind(rawValue: rawKind) {
            kind = decodedKind
        } else {
            kind = imagePNGData != nil ? .image : .text
        }
    }
}

@MainActor
final class ClipboardManager: ObservableObject {
    static let shared = ClipboardManager()

    @Published private(set) var recentItems: [ClipboardItem] = []

    private var pasteboardSubscription: PasteboardChangeMonitor.Token?
    private var activeFallbackInterval: TimeInterval?
    private var lastChangeCount: Int = NSPasteboard.general.changeCount
    private var highPriorityConsumers = 0
    private var ignoredExternalPasteboardChanges = 0
    private let maxImageBytes = 8 * 1024 * 1024
    private let maxFilesPerPasteboardChange = 200
    private nonisolated let secureFileURL: URL
    private var persistWorkItem: DispatchWorkItem?
    private var runtimeStateCancellable: AnyCancellable?
    private nonisolated let persistQueue = DispatchQueue(label: "com.sapphire.clipboard.persist", qos: .utility)
    private let continuityRemoteMarker = NSPasteboard.PasteboardType("com.sapphire.continuity.remote")

    private var maxItems: Int? {
        let settings = SettingsModel.shared.settings
        if settings.clipboardHistoryUnlimited || settings.clipboardHistoryLimit <= 0 {
            return nil
        }
        return max(4, settings.clipboardHistoryLimit)
    }

    private var requestedCheckInterval: TimeInterval {
        if highPriorityConsumers > 0 { return 0.2 }
        if NotchRuntimeState.shared.shouldReduceBackgroundWork { return 1.5 }
        return 0.35
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
        runtimeStateCancellable = NotchRuntimeState.shared.reductionChanges
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, self.pasteboardSubscription != nil else { return }
                self.restartMonitoringIfNeeded(force: false)
            }
    }

    func startMonitoring() {
        guard SettingsModel.shared.settings.clipboardMonitoringEnabled else { return }
        restartMonitoringIfNeeded(force: pasteboardSubscription == nil)
        captureCurrentIfNeeded()
    }

    func beginHighPriorityMonitoring() {
        highPriorityConsumers += 1
        if SettingsModel.shared.settings.clipboardMonitoringEnabled {
            restartMonitoringIfNeeded(force: true)
        }
    }

    func endHighPriorityMonitoring() {
        highPriorityConsumers = max(0, highPriorityConsumers - 1)
        if pasteboardSubscription != nil {
            restartMonitoringIfNeeded(force: true)
        }
    }

    func beginIgnoringExternalPasteboardChanges() {
        ignoredExternalPasteboardChanges += 1
    }

    func endIgnoringExternalPasteboardChanges(ownChangeCount: Int? = nil) {
        ignoredExternalPasteboardChanges = max(0, ignoredExternalPasteboardChanges - 1)
        if ignoredExternalPasteboardChanges == 0, let ownChangeCount {
            lastChangeCount = ownChangeCount
        }
    }

    func stopMonitoring() {
        if let pasteboardSubscription {
            PasteboardChangeMonitor.shared.unsubscribe(pasteboardSubscription)
        }
        pasteboardSubscription = nil
        activeFallbackInterval = nil
    }

    private func restartMonitoringIfNeeded(force: Bool) {
        let interval = requestedCheckInterval
        if !force, let activeFallbackInterval, abs(activeFallbackInterval - interval) < 0.01 {
            return
        }
        activeFallbackInterval = interval
        if let pasteboardSubscription {
            PasteboardChangeMonitor.shared.updateInterval(interval, for: pasteboardSubscription)
            return
        }
        pasteboardSubscription = PasteboardChangeMonitor.shared.subscribe(interval: interval) { [weak self] _ in
            self?.captureCurrentIfNeeded()
        }
    }

    func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        lastChangeCount = NSPasteboard.general.changeCount
        prependText(text)
    }

    func writePlainText(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        lastChangeCount = pasteboard.changeCount
    }

    // MARK: - Continuity (remote clipboard)

    func applyRemoteClipboard(text: String, from deviceName: String) {
        let pasteboard = NSPasteboard.general
        beginIgnoringExternalPasteboardChanges()
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        pasteboard.setData(Data("text".utf8), forType: continuityRemoteMarker)
        let ownChangeCount = pasteboard.changeCount
        endIgnoringExternalPasteboardChanges(ownChangeCount: ownChangeCount)
        lastChangeCount = ownChangeCount
        prependText(text)
        NotificationCenter.default.post(name: .continuityClipboardReceived,
                                        object: nil, userInfo: ["device": deviceName, "isImage": false])
    }

    func applyRemoteClipboard(image: NSImage, pngData: Data, from deviceName: String) {
        let pasteboard = NSPasteboard.general
        beginIgnoringExternalPasteboardChanges()
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
        pasteboard.setData(pngData, forType: .png)
        pasteboard.setData(Data("image".utf8), forType: continuityRemoteMarker)
        let ownChangeCount = pasteboard.changeCount
        endIgnoringExternalPasteboardChanges(ownChangeCount: ownChangeCount)
        lastChangeCount = ownChangeCount
        let w = Int(image.size.width.rounded()), h = Int(image.size.height.rounded())
        prependImage(pngData: pngData, preview: (w > 0 && h > 0) ? "Image \(w)×\(h)" : "Image")
        NotificationCenter.default.post(name: .continuityClipboardReceived,
                                        object: nil, userInfo: ["device": deviceName, "isImage": true])
    }

    func applyRemoteClipboard(files urls: [URL], from deviceName: String) {
        guard !urls.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        beginIgnoringExternalPasteboardChanges()
        pasteboard.clearContents()
        pasteboard.writeObjects(urls.map { $0 as NSURL })
        pasteboard.setData(Data("file".utf8), forType: continuityRemoteMarker)
        let ownChangeCount = pasteboard.changeCount
        endIgnoringExternalPasteboardChanges(ownChangeCount: ownChangeCount)
        lastChangeCount = ownChangeCount
        for url in urls { prependFile(url: url) }
        NotificationCenter.default.post(name: .continuityClipboardReceived,
                                        object: nil, userInfo: ["device": deviceName, "isImage": false])
    }

    @discardableResult
    func copyItem(_ item: ClipboardItem) -> Bool {
        let pasteboard = NSPasteboard.general
        if item.isImage, let data = item.imagePNGData, let image = NSImage(data: data) {
            pasteboard.clearContents()
            pasteboard.writeObjects([image])
            pasteboard.setData(data, forType: .png)
        } else if item.kind == .file || item.kind == .folder {
            guard let url = resolvedFileURL(for: item) else { return false }
            pasteboard.clearContents()
            pasteboard.writeObjects([url as NSURL])
        } else {
            let text = item.textContent ?? item.preview
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
        }
        lastChangeCount = pasteboard.changeCount
        return true
    }

    func removeItem(id: String) {
        recentItems.removeAll { $0.id == id }
        schedulePersist()
    }

    func clearHistory() {
        recentItems.removeAll()
        persistWorkItem?.cancel()
        persistWorkItem = nil
        persistQueue.async { [weak self] in
            self?.persistItems([])
        }
    }

    @discardableResult
    func shareItem(_ item: ClipboardItem, relativeTo view: NSView? = nil) -> Bool {
        var items: [Any] = []
        if item.isImage, let data = item.imagePNGData, let image = NSImage(data: data) {
            items.append(image)
        } else if item.kind == .file || item.kind == .folder {
            guard let url = resolvedFileURL(for: item) else { return false }
            items.append(url)
        } else {
            items.append(item.textContent ?? item.preview)
        }
        guard !items.isEmpty else { return false }

        let picker = NSSharingServicePicker(items: items)
        if let view {
            picker.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
        } else if let window = NSApp.keyWindow ?? NSApp.windows.first(where: { $0.isVisible }),
                  let content = window.contentView {
            let rect = NSRect(x: content.bounds.midX - 1, y: content.bounds.midY - 1, width: 2, height: 2)
            picker.show(relativeTo: rect, of: content, preferredEdge: .minY)
        }
        return true
    }

    private func captureCurrentIfNeeded() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastChangeCount else { return }
        guard ignoredExternalPasteboardChanges == 0 else { return }
        lastChangeCount = pasteboard.changeCount
        if pasteboard.data(forType: continuityRemoteMarker) != nil { return }

        let types = pasteboard.types ?? []
        let settings = SettingsModel.shared.settings
        if settings.clipboardIgnoreConcealedItems {
            let ignoredTypes: Set<NSPasteboard.PasteboardType> = [
                .init("org.nspasteboard.ConcealedType"),
                .init("org.nspasteboard.TransientType"),
                .init("org.nspasteboard.AutoGeneratedType")
            ]
            if !types.filter({ ignoredTypes.contains($0) }).isEmpty {
                return
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

        let urls = extractFileURLs(from: pasteboard)
        if !urls.isEmpty {
            for url in urls.prefix(maxFilesPerPasteboardChange).reversed() {
                prependFile(url: url)
            }
            return
        }

        if let string = extractText(from: pasteboard) {
            prependText(string)
        }
    }

    private func extractText(from pasteboard: NSPasteboard) -> String? {
        if let string = pasteboard.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !string.isEmpty {
            return string
        }
        if let objects = pasteboard.readObjects(forClasses: [NSAttributedString.self], options: nil) as? [NSAttributedString],
           let text = objects.first?.string.trimmingCharacters(in: .whitespacesAndNewlines),
           !text.isEmpty {
            return text
        }
        return nil
    }

    private func extractFileURLs(from pasteboard: NSPasteboard) -> [URL] {
        guard let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] else { return [] }
        let fileManager = FileManager.default
        return urls.filter { $0.isFileURL && fileManager.fileExists(atPath: $0.path) }
    }

    private func extractPNGData(from pasteboard: NSPasteboard) -> Data? {
        if let png = pasteboard.data(forType: .png), !png.isEmpty {
            return png.count <= maxImageBytes ? png : downsampledPNG(from: png)
        }
        if let tiff = pasteboard.data(forType: .tiff),
           let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            return png.count <= maxImageBytes ? png : downsampledPNG(from: png)
        }
        if let images = pasteboard.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage],
           let image = images.first,
           let tiff = image.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            return png.count <= maxImageBytes ? png : downsampledPNG(from: png)
        }
        return nil
    }

    private func downsampledPNG(from pngData: Data) -> Data? {
        guard let image = NSImage(data: pngData), image.size.width > 0, image.size.height > 0 else { return nil }
        var scale: CGFloat = 0.85
        var data = pngData
        while data.count > maxImageBytes, scale > 0.05 {
            let newSize = NSSize(width: image.size.width * scale, height: image.size.height * scale)
            let resized = NSImage(size: newSize)
            resized.lockFocus()
            image.draw(in: NSRect(origin: .zero, size: newSize), from: .zero, operation: .copy, fraction: 1.0)
            resized.unlockFocus()
            guard let tiff = resized.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else { return nil }
            data = png
            scale -= 0.15
        }
        return data.count <= maxImageBytes ? data : nil
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
            kind: .text,
            textContent: text,
            imagePNGData: nil,
            fileURLString: nil,
            fileBookmarkData: nil
        )
        recentItems.removeAll {
            $0.kind == .text && ($0.textContent == text || $0.preview == item.preview)
        }
        insert(item)
    }

    private func prependImage(pngData: Data, preview: String) {
        let item = ClipboardItem(
            id: UUID().uuidString,
            preview: preview,
            copiedAt: Date(),
            kind: .image,
            textContent: nil,
            imagePNGData: pngData,
            fileURLString: nil,
            fileBookmarkData: nil
        )
        recentItems.removeAll { $0.kind == .image && $0.imagePNGData == pngData }
        insert(item)
    }

    private func prependFile(url: URL) {
        var isDirectory: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        let kind: ClipboardItemKind = isDirectory.boolValue ? .folder : .file
        let name = url.lastPathComponent
        let preview = String((name.isEmpty ? url.path : name).prefix(240))
        let item = ClipboardItem(
            id: UUID().uuidString,
            preview: preview,
            copiedAt: Date(),
            kind: kind,
            textContent: nil,
            imagePNGData: nil,
            fileURLString: url.path,
            fileBookmarkData: try? url.bookmarkData()
        )
        recentItems.removeAll { $0.fileURLString == url.path }
        insert(item)
    }

    private func resolvedFileURL(for item: ClipboardItem) -> URL? {
        let fileManager = FileManager.default

        if let bookmarkData = item.fileBookmarkData {
            var isStale = false
            if let resolved = try? URL(
                resolvingBookmarkData: bookmarkData,
                options: [],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ), fileManager.fileExists(atPath: resolved.path) {
                if isStale || resolved.path != item.fileURLString {
                    refreshFileReference(itemID: item.id, url: resolved)
                }
                return resolved
            }
        }

        if let path = item.fileURLString, fileManager.fileExists(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return nil
    }

    private func refreshFileReference(itemID: String, url: URL) {
        guard let index = recentItems.firstIndex(where: { $0.id == itemID }) else { return }
        let old = recentItems[index]
        recentItems[index] = ClipboardItem(
            id: old.id,
            preview: old.preview,
            copiedAt: old.copiedAt,
            kind: old.kind,
            textContent: old.textContent,
            imagePNGData: old.imagePNGData,
            fileURLString: url.path,
            fileBookmarkData: try? url.bookmarkData()
        )
        schedulePersist()
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
        let snapshot = recentItems
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.persistQueue.async {
                self.persistItems(snapshot)
            }
        }
        persistWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    private nonisolated func persistItems(_ snapshot: [ClipboardItem]) {
        do {
            if snapshot.isEmpty {
                if FileManager.default.fileExists(atPath: secureFileURL.path) {
                    try FileManager.default.removeItem(at: secureFileURL)
                }
                return
            }
            let jsonData = try JSONEncoder().encode(snapshot)
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