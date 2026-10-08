//
//  ClipboardManager.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-10

import AppKit
import Combine
import CryptoKit
import ImageIO
import UniformTypeIdentifiers

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
        if changeCount < lastChangeCount {
            print("[PasteboardChangeMonitor] Pasteboard change count went backwards (\(lastChangeCount) → \(changeCount)); pasteboard server restarted.")
        }
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
    let isPinned: Bool
    let byteSize: Int
    let contentHash: String?
    let isTextTruncated: Bool

    init(
        id: String,
        preview: String,
        copiedAt: Date,
        kind: ClipboardItemKind,
        textContent: String?,
        imagePNGData: Data?,
        fileURLString: String?,
        fileBookmarkData: Data?,
        isPinned: Bool = false,
        byteSize: Int? = nil,
        contentHash: String? = nil,
        isTextTruncated: Bool = false
    ) {
        self.id = id
        self.preview = preview
        self.copiedAt = copiedAt
        self.kind = kind
        self.textContent = textContent
        self.imagePNGData = imagePNGData
        self.fileURLString = fileURLString
        self.fileBookmarkData = fileBookmarkData
        self.isPinned = isPinned
        self.byteSize = byteSize ?? Self.measure(
            textContent: textContent, imagePNGData: imagePNGData,
            fileURLString: fileURLString, fileBookmarkData: fileBookmarkData
        )
        self.contentHash = contentHash
        self.isTextTruncated = isTextTruncated
    }

    var isImage: Bool { kind == .image }

    var resolvedImageData: Data? {
        if let imagePNGData { return imagePNGData }
        return kind == .image ? ClipboardImageLoader.load(id: id) : nil
    }

    func withoutImageData() -> ClipboardItem {
        guard imagePNGData != nil else { return self }
        return copy(imagePNGData: .some(nil))
    }

    func with(pinned: Bool) -> ClipboardItem {
        copy(isPinned: pinned)
    }

    func with(fileURL url: URL, bookmark: Data?) -> ClipboardItem {
        copy(fileURLString: .some(url.path), fileBookmarkData: .some(bookmark))
    }

    private func copy(
        imagePNGData: Data?? = nil,
        fileURLString: String?? = nil,
        fileBookmarkData: Data?? = nil,
        isPinned: Bool? = nil
    ) -> ClipboardItem {
        ClipboardItem(
            id: id, preview: preview, copiedAt: copiedAt, kind: kind, textContent: textContent,
            imagePNGData: imagePNGData ?? self.imagePNGData,
            fileURLString: fileURLString ?? self.fileURLString,
            fileBookmarkData: fileBookmarkData ?? self.fileBookmarkData,
            isPinned: isPinned ?? self.isPinned,
            byteSize: byteSize, contentHash: contentHash, isTextTruncated: isTextTruncated
        )
    }

    private static func measure(textContent: String?, imagePNGData: Data?, fileURLString: String?, fileBookmarkData: Data?) -> Int {
        (textContent?.utf8.count ?? 0)
            + (imagePNGData?.count ?? 0)
            + (fileURLString?.utf8.count ?? 0)
            + (fileBookmarkData?.count ?? 0)
    }

    static func == (lhs: ClipboardItem, rhs: ClipboardItem) -> Bool {
        lhs.id == rhs.id
            && lhs.isPinned == rhs.isPinned
            && lhs.preview == rhs.preview
            && lhs.kind == rhs.kind
            && lhs.copiedAt == rhs.copiedAt
            && lhs.fileURLString == rhs.fileURLString
            && lhs.contentHash == rhs.contentHash
            && lhs.isTextTruncated == rhs.isTextTruncated
            && lhs.textContent == rhs.textContent
    }

    private enum CodingKeys: String, CodingKey {
        case id, preview, copiedAt, kind, textContent, imagePNGData, fileURLString, fileBookmarkData
        case isPinned, byteSize, contentHash, isTextTruncated
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
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        byteSize = try container.decodeIfPresent(Int.self, forKey: .byteSize)
            ?? Self.measure(textContent: textContent, imagePNGData: imagePNGData,
                            fileURLString: fileURLString, fileBookmarkData: fileBookmarkData)
        contentHash = try container.decodeIfPresent(String.self, forKey: .contentHash)
        isTextTruncated = try container.decodeIfPresent(Bool.self, forKey: .isTextTruncated) ?? false
    }
}

// MARK: - Capture payloads (built off the main thread)

private struct ClipboardRawCapture: @unchecked Sendable {
    enum Payload {
        case ignored
        case empty
        case text(String)
        case image(Data)
        case files([URL])
    }

    let changeCount: Int
    let payload: Payload
}

private enum ClipboardProcessedCapture: @unchecked Sendable {
    case text(String, truncated: Bool)
    case image(png: Data, preview: String, hash: String)
    case files([(url: URL, isDirectory: Bool, bookmark: Data?)])
}

private struct ClipboardCaptureRequest: Sendable {
    let changeCount: Int
    let ignoreMarkedItems: Bool
    let ignoredBundleIDs: Set<String>
    let frontmostBundleID: String?
    let maxFiles: Int
    let continuityMarker: String
}

private struct ClipboardRetentionSettings: Equatable {
    let unlimited: Bool
    let itemLimit: Int
    let storageLimitMB: Int
}

@MainActor
final class ClipboardManager: ObservableObject {
    static let shared = ClipboardManager()

    @Published private(set) var recentItems: [ClipboardItem] = [] {
        didSet { historyRevision &+= 1 }
    }
    private(set) var historyRevision = 0

    private var pasteboardSubscription: PasteboardChangeMonitor.Token?
    private var activeFallbackInterval: TimeInterval?
    private var lastChangeCount: Int = NSPasteboard.general.changeCount
    private var highPriorityConsumers = 0
    private var ignoredExternalPasteboardChanges = 0
    private var captureInFlight = false
    private var captureRequested = false
    private static let maxImageBytes = 8 * 1024 * 1024
    private let maxFilesPerPasteboardChange = 200
    private nonisolated let secureFileURL: URL
    private nonisolated let secureStore: ClipboardSecureStore
    private var persistWorkItem: DispatchWorkItem?
    private var pendingRewriteIDs: Set<String> = []
    private var isHistoryLoaded = false
    private var clearedBeforeHistoryLoaded = false
    private var clearedPinnedBeforeHistoryLoaded = false
    private var cancellables = Set<AnyCancellable>()
    private nonisolated let persistQueue = DispatchQueue(label: "com.sapphire.clipboard.persist", qos: .utility)
    private nonisolated let processingQueue = DispatchQueue(label: "com.sapphire.clipboard.process", qos: .utility)
    private nonisolated static let continuityRemoteMarker = NSPasteboard.PasteboardType("com.sapphire.continuity.remote")

    private var retentionLimits: (maxItems: Int?, maxBytes: Int?) {
        let settings = SettingsModel.shared.settings
        if settings.clipboardHistoryUnlimited || settings.clipboardHistoryLimit <= 0 {
            return (nil, nil)
        }
        let maxBytes = max(ClipboardHistoryBudget.storageLimitRangeMB.lowerBound, settings.clipboardHistoryStorageLimitMB) * 1024 * 1024
        return (max(4, settings.clipboardHistoryLimit), maxBytes)
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
        secureStore = ClipboardSecureStore(appDirectory: appDirectory, legacyFileURL: secureFileURL)
        ClipboardImageLoader.store = secureStore
        loadPersistedHistory()
        NotchRuntimeState.shared.reductionChanges
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, self.pasteboardSubscription != nil else { return }
                self.restartMonitoringIfNeeded(force: false)
            }
            .store(in: &cancellables)
        SettingsModel.shared.changes(of: {
            ClipboardRetentionSettings(
                unlimited: $0.clipboardHistoryUnlimited,
                itemLimit: $0.clipboardHistoryLimit,
                storageLimitMB: $0.clipboardHistoryStorageLimitMB
            )
        })
        .debounce(for: .seconds(2), scheduler: DispatchQueue.main)
        .sink { [weak self] _ in self?.applyRetention() }
        .store(in: &cancellables)
    }

    func startMonitoring() {
        guard SettingsModel.shared.current.clipboardMonitoringEnabled else { return }
        restartMonitoringIfNeeded(force: pasteboardSubscription == nil)
        captureCurrentIfNeeded()
    }

    func beginHighPriorityMonitoring() {
        highPriorityConsumers += 1
        if SettingsModel.shared.current.clipboardMonitoringEnabled {
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

    func noteOwnPasteboardWrite(changeCount: Int) {
        lastChangeCount = changeCount
    }

    func stopMonitoring() {
        if let pasteboardSubscription {
            PasteboardChangeMonitor.shared.unsubscribe(pasteboardSubscription)
        }
        pasteboardSubscription = nil
        activeFallbackInterval = nil
        captureRequested = false
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

    // MARK: - Writing

    func copyToClipboard(_ text: String) {
        writeText(text, completion: nil)
        prependText(text)
    }

    func writePlainText(_ text: String, completion: ((Bool) -> Void)? = nil) {
        writeText(text, completion: completion)
    }

    private func writeText(_ text: String, completion: ((Bool) -> Void)?) {
        PasteboardLane.shared.write({ pasteboard in
            pasteboard.clearContents()
            return pasteboard.setString(text, forType: .string)
        }, completion: { [weak self] changeCount in
            if let changeCount { self?.lastChangeCount = changeCount }
            completion?(changeCount != nil)
        })
    }

    // MARK: - Continuity (remote clipboard)

    func applyRemoteClipboard(text: String, from deviceName: String) {
        let marker = Self.continuityRemoteMarker
        writeRemote({ pasteboard in
            pasteboard.clearContents()
            let wrote = pasteboard.setString(text, forType: .string)
            pasteboard.setData(Data("text".utf8), forType: marker)
            return wrote
        })
        prependText(text)
        NotificationCenter.default.post(name: .continuityClipboardReceived,
                                        object: nil, userInfo: ["device": deviceName, "isImage": false])
    }

    func applyRemoteClipboard(image: NSImage, pngData: Data, from deviceName: String) {
        let marker = Self.continuityRemoteMarker
        writeRemote({ pasteboard in
            pasteboard.clearContents()
            if let image = NSImage(data: pngData) { pasteboard.writeObjects([image]) }
            let wrote = pasteboard.setData(pngData, forType: .png)
            pasteboard.setData(Data("image".utf8), forType: marker)
            return wrote
        })
        let w = Int(image.size.width.rounded()), h = Int(image.size.height.rounded())
        let preview = (w > 0 && h > 0) ? String(localized: "Image \(String(w))×\(String(h))") : String(localized: "Image")
        processingQueue.async { [weak self] in
            let hash = Self.sha256(pngData)
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.prependImage(pngData: pngData, preview: preview, hash: hash) }
            }
        }
        NotificationCenter.default.post(name: .continuityClipboardReceived,
                                        object: nil, userInfo: ["device": deviceName, "isImage": true])
    }

    func applyRemoteClipboard(files urls: [URL], from deviceName: String) {
        guard !urls.isEmpty else { return }
        let marker = Self.continuityRemoteMarker
        writeRemote({ pasteboard in
            pasteboard.clearContents()
            let wrote = pasteboard.writeObjects(urls.map { $0 as NSURL })
            pasteboard.setData(Data("file".utf8), forType: marker)
            return wrote
        })
        processingQueue.async { [weak self] in
            let files = Self.inspectFiles(urls)
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.prependFiles(files) }
            }
        }
        NotificationCenter.default.post(name: .continuityClipboardReceived,
                                        object: nil, userInfo: ["device": deviceName, "isImage": false])
    }

    private func writeRemote(_ work: @escaping (NSPasteboard) -> Bool) {
        beginIgnoringExternalPasteboardChanges()
        PasteboardLane.shared.write(work) { [weak self] changeCount in
            self?.endIgnoringExternalPasteboardChanges(ownChangeCount: changeCount)
        }
    }

    @discardableResult
    func copyItem(_ item: ClipboardItem, completion: ((Bool) -> Void)? = nil) -> Bool {
        switch item.kind {
        case .image:
            let resident = item.imagePNGData
            processingQueue.async { [weak self] in
                guard let data = resident ?? item.resolvedImageData else {
                    DispatchQueue.main.async { completion?(false) }
                    return
                }
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        self?.writeOwn({ pasteboard in
                            pasteboard.clearContents()
                            if let image = NSImage(data: data) { pasteboard.writeObjects([image]) }
                            return pasteboard.setData(data, forType: .png)
                        }, completion: completion)
                    }
                }
            }
            return true
        case .file, .folder:
            guard let url = resolvedFileURL(for: item) else { return false }
            writeOwn({ pasteboard in
                pasteboard.clearContents()
                return pasteboard.writeObjects([url as NSURL])
            }, completion: completion)
            return true
        case .text:
            writeText(item.textContent ?? item.preview, completion: completion)
            return true
        }
    }

    @discardableResult
    func copyItems(_ items: [ClipboardItem], completion: ((Bool) -> Void)? = nil) -> Bool {
        if items.count == 1, let only = items.first { return copyItem(only, completion: completion) }
        guard let plan = ClipboardMultiPaste.plan(for: items) else { return false }
        switch plan {
        case .joinedText(let text):
            writeText(text, completion: completion)
        case .items(let entries):
            let fileURLs: [String: URL] = Dictionary(items.compactMap { item in
                guard item.kind == .file || item.kind == .folder, let path = item.fileURLString,
                      let url = resolvedFileURL(for: item) else { return nil }
                return (path, url)
            }, uniquingKeysWith: { first, _ in first })
            let images = Dictionary(items.filter(\.isImage).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            processingQueue.async { [weak self] in
                var pasteboardItems: [NSPasteboardItem] = []
                for entry in entries {
                    let pasteboardItem = NSPasteboardItem()
                    switch entry {
                    case .text(let text):
                        pasteboardItem.setString(text, forType: .string)
                    case .image(let id):
                        guard let data = images[id]?.resolvedImageData else { continue }
                        pasteboardItem.setData(data, forType: .png)
                    case .file(let path):
                        guard let url = fileURLs[path] else { continue }
                        pasteboardItem.setString(url.absoluteString, forType: .fileURL)
                    }
                    pasteboardItems.append(pasteboardItem)
                }
                let box = UncheckedSendableBox(pasteboardItems)
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        guard !box.value.isEmpty else { completion?(false); return }
                        self?.writeOwn({ pasteboard in
                            pasteboard.clearContents()
                            return pasteboard.writeObjects(box.value)
                        }, completion: completion)
                    }
                }
            }
        }
        return true
    }

    private func writeOwn(_ work: @escaping (NSPasteboard) -> Bool, completion: ((Bool) -> Void)?) {
        PasteboardLane.shared.write(work) { [weak self] changeCount in
            if let changeCount { self?.lastChangeCount = changeCount }
            completion?(changeCount != nil)
        }
    }

    // MARK: - History edits

    func removeItem(id: String) {
        recentItems.removeAll { $0.id == id }
        schedulePersist()
    }

    func setPinned(_ pinned: Bool, id: String) {
        guard let index = recentItems.firstIndex(where: { $0.id == id }),
              recentItems[index].isPinned != pinned else { return }
        recentItems[index] = recentItems[index].with(pinned: pinned)
        pendingRewriteIDs.insert(id)
        if !pinned { applyRetention() }
        schedulePersist()
    }

    func togglePin(id: String) {
        guard let item = recentItems.first(where: { $0.id == id }) else { return }
        setPinned(!item.isPinned, id: id)
    }

    var pinnedItems: [ClipboardItem] { recentItems.filter(\.isPinned) }

    func clearHistory(includingPinned: Bool = false) {
        if !isHistoryLoaded {
            clearedBeforeHistoryLoaded = true
            if includingPinned { clearedPinnedBeforeHistoryLoaded = true }
        }
        if includingPinned {
            recentItems.removeAll()
        } else {
            recentItems.removeAll { !$0.isPinned }
        }
        persistWorkItem?.cancel()
        persistWorkItem = nil
        guard isHistoryLoaded else { return }
        let snapshot = recentItems
        let rewrites = pendingRewriteIDs
        pendingRewriteIDs.removeAll()
        persistQueue.async { [weak self] in
            self?.persistItems(snapshot, rewriting: rewrites)
        }
    }

    @discardableResult
    func shareItem(_ item: ClipboardItem, relativeTo view: NSView? = nil) -> Bool {
        var items: [Any] = []
        if item.isImage, let data = item.resolvedImageData, let image = NSImage(data: data) {
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

    // MARK: - Capture

    private func captureCurrentIfNeeded() {
        guard pasteboardSubscription != nil else { return }
        let changeCount = NSPasteboard.general.changeCount
        guard changeCount != lastChangeCount, ignoredExternalPasteboardChanges == 0 else { return }
        guard !captureInFlight else {
            captureRequested = true
            return
        }
        captureInFlight = true
        captureRequested = false

        let settings = SettingsModel.shared.settings
        let request = ClipboardCaptureRequest(
            changeCount: changeCount,
            ignoreMarkedItems: settings.clipboardIgnoreConcealedItems,
            ignoredBundleIDs: Set(settings.clipboardIgnoredAppBundleIDs),
            frontmostBundleID: ActiveAppMonitor.shared.activeAppBundleID,
            maxFiles: maxFilesPerPasteboardChange,
            continuityMarker: Self.continuityRemoteMarker.rawValue
        )
        PasteboardLane.shared.run(timeout: 1.5, { pasteboard in
            Self.read(pasteboard, request: request)
        }, completion: { [weak self] raw in
            guard let self else { return }
            guard let raw else {
                print("[ClipboardManager] Pasteboard read timed out; skipping change \(request.changeCount).")
                self.lastChangeCount = request.changeCount
                return
            }
            self.receive(raw)
        }, didFinish: { [weak self] in
            guard let self else { return }
            self.captureInFlight = false
            if self.captureRequested || NSPasteboard.general.changeCount != self.lastChangeCount {
                self.captureRequested = false
                if self.pasteboardSubscription != nil { self.captureCurrentIfNeeded() }
            }
        })
    }

    private func receive(_ raw: ClipboardRawCapture) {
        guard raw.changeCount != lastChangeCount, ignoredExternalPasteboardChanges == 0 else { return }
        lastChangeCount = raw.changeCount
        let maxImageBytes = Self.maxImageBytes
        switch raw.payload {
        case .ignored, .empty:
            return
        case .text(let text):
            processingQueue.async { [weak self] in
                let (stored, truncated) = ClipboardTextLimit.truncated(text)
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { self?.prependText(stored, truncated: truncated) }
                }
            }
        case .image(let data):
            processingQueue.async { [weak self] in
                guard let processed = Self.processImage(data, maxBytes: maxImageBytes) else { return }
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        self?.prependImage(pngData: processed.png, preview: processed.preview, hash: processed.hash)
                    }
                }
            }
        case .files(let urls):
            processingQueue.async { [weak self] in
                let files = Self.inspectFiles(urls)
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { self?.prependFiles(files) }
                }
            }
        }
    }

    private nonisolated static func read(_ pasteboard: NSPasteboard, request: ClipboardCaptureRequest) -> ClipboardRawCapture {
        let changeCount = pasteboard.changeCount
        let types = pasteboard.types ?? []
        let typeNames = Set(types.map(\.rawValue))
        if typeNames.contains(request.continuityMarker) {
            return ClipboardRawCapture(changeCount: changeCount, payload: .ignored)
        }
        let source = typeNames.contains(ClipboardCaptureFilter.sourceType)
            ? pasteboard.string(forType: .sapphireSource) : nil
        if ClipboardCaptureFilter.shouldIgnore(
            types: typeNames,
            sourceBundleID: source,
            frontmostBundleID: request.frontmostBundleID,
            ignoredBundleIDs: request.ignoredBundleIDs,
            ignoreMarkedItems: request.ignoreMarkedItems
        ) {
            return ClipboardRawCapture(changeCount: changeCount, payload: .ignored)
        }

        if types.contains(.fileURL),
           let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] {
            let fileURLs = Array(urls.filter(\.isFileURL).prefix(request.maxFiles))
            if !fileURLs.isEmpty {
                return ClipboardRawCapture(changeCount: changeCount, payload: .files(fileURLs))
            }
        }

        if let png = pasteboard.data(forType: .png), !png.isEmpty {
            return ClipboardRawCapture(changeCount: changeCount, payload: .image(png))
        }
        if let tiff = pasteboard.data(forType: .tiff), !tiff.isEmpty {
            return ClipboardRawCapture(changeCount: changeCount, payload: .image(tiff))
        }

        if let string = pasteboard.string(forType: .string),
           !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return ClipboardRawCapture(changeCount: changeCount, payload: .text(string.trimmingCharacters(in: .whitespacesAndNewlines)))
        }
        if let objects = pasteboard.readObjects(forClasses: [NSAttributedString.self], options: nil) as? [NSAttributedString],
           let text = objects.first?.string.trimmingCharacters(in: .whitespacesAndNewlines),
           !text.isEmpty {
            return ClipboardRawCapture(changeCount: changeCount, payload: .text(text))
        }

        if NSImage.canInit(with: pasteboard),
           let image = (pasteboard.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage])?.first,
           let tiff = image.tiffRepresentation {
            return ClipboardRawCapture(changeCount: changeCount, payload: .image(tiff))
        }
        return ClipboardRawCapture(changeCount: changeCount, payload: .empty)
    }

    private nonisolated static func processImage(_ data: Data, maxBytes: Int) -> (png: Data, preview: String, hash: String)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) > 0 else { return nil }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let width = (properties?[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? 0
        let height = (properties?[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? 0
        let isPNG = (CGImageSourceGetType(source) as String?) == UTType.png.identifier

        var png: Data?
        if isPNG, data.count <= maxBytes {
            png = data
        } else if !isPNG, let image = CGImageSourceCreateImageAtIndex(source, 0, nil) {
            png = encodePNG(image)
        }

        var longest = max(width, height)
        while png.map({ $0.count > maxBytes }) ?? true, longest > 64 {
            longest = Int(Double(longest) * 0.75)
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: longest,
            ]
            guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { break }
            png = encodePNG(thumbnail)
        }
        guard let png, !png.isEmpty, png.count <= maxBytes else { return nil }
        let preview = (width > 0 && height > 0) ? String(localized: "Image \(String(width))×\(String(height))") : String(localized: "Image")
        return (png, preview, sha256(png))
    }

    private nonisolated static func encodePNG(_ image: CGImage) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? output as Data : nil
    }

    private nonisolated static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private nonisolated static func inspectFiles(_ urls: [URL]) -> [(url: URL, isDirectory: Bool, bookmark: Data?)] {
        let fileManager = FileManager.default
        return urls.compactMap { url in
            var isDirectory: ObjCBool = false
            guard url.isFileURL, fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return nil }
            return (url, isDirectory.boolValue, try? url.bookmarkData())
        }
    }

    // MARK: - Insertion

    private func prependText(_ text: String, truncated: Bool = false) {
        let preview = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !preview.isEmpty else { return }
        let previewText = String(preview.prefix(240))
        let wasPinned = recentItems.contains { $0.isPinned && $0.kind == .text && $0.textContent == text }

        let item = ClipboardItem(
            id: UUID().uuidString,
            preview: previewText,
            copiedAt: Date(),
            kind: .text,
            textContent: text,
            imagePNGData: nil,
            fileURLString: nil,
            fileBookmarkData: nil,
            isPinned: wasPinned,
            isTextTruncated: truncated
        )
        recentItems.removeAll {
            $0.kind == .text && ($0.textContent == text || $0.preview == previewText)
        }
        insert(item)
    }

    private func prependImage(pngData: Data, preview: String, hash: String) {
        let duplicate: (ClipboardItem) -> Bool = { existing in
            guard existing.kind == .image else { return false }
            if let existingHash = existing.contentHash { return existingHash == hash }
            return existing.imagePNGData == pngData
        }
        let wasPinned = recentItems.contains { $0.isPinned && duplicate($0) }
        let item = ClipboardItem(
            id: UUID().uuidString,
            preview: preview,
            copiedAt: Date(),
            kind: .image,
            textContent: nil,
            imagePNGData: pngData,
            fileURLString: nil,
            fileBookmarkData: nil,
            isPinned: wasPinned,
            contentHash: hash
        )
        recentItems.removeAll(where: duplicate)
        insert(item)
    }

    private func prependFiles(_ files: [(url: URL, isDirectory: Bool, bookmark: Data?)]) {
        guard !files.isEmpty else { return }
        var items = recentItems
        for file in files.reversed() {
            let name = file.url.lastPathComponent
            let preview = String((name.isEmpty ? file.url.path : name).prefix(240))
            let wasPinned = items.contains { $0.isPinned && $0.fileURLString == file.url.path }
            items.removeAll { $0.fileURLString == file.url.path }
            items.insert(ClipboardItem(
                id: UUID().uuidString,
                preview: preview,
                copiedAt: Date(),
                kind: file.isDirectory ? .folder : .file,
                textContent: nil,
                imagePNGData: nil,
                fileURLString: file.url.path,
                fileBookmarkData: file.bookmark,
                isPinned: wasPinned
            ), at: 0)
        }
        recentItems = retained(items)
        schedulePersist()
    }

    private func resolvedFileURL(for item: ClipboardItem) -> URL? {
        let fileManager = FileManager.default

        if let bookmarkData = item.fileBookmarkData {
            var isStale = false
            if let resolved = try? URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withoutUI, .withoutMounting],
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
        recentItems[index] = recentItems[index].with(fileURL: url, bookmark: try? url.bookmarkData())
        pendingRewriteIDs.insert(itemID)
        schedulePersist()
    }

    private func insert(_ item: ClipboardItem) {
        var items = recentItems
        items.insert(item, at: 0)
        recentItems = retained(items)
        schedulePersist()
    }

    private func retained(_ items: [ClipboardItem]) -> [ClipboardItem] {
        let limits = retentionLimits
        return ClipboardHistoryBudget.retained(items, maxItems: limits.maxItems, maxBytes: limits.maxBytes)
    }

    private func applyRetention() {
        guard isHistoryLoaded else { return }
        let trimmed = retained(recentItems)
        guard trimmed.count != recentItems.count else { return }
        recentItems = trimmed
        schedulePersist()
    }

    // MARK: - Secure Persistence

    private func schedulePersist() {
        guard isHistoryLoaded else { return }
        persistWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let snapshot = self.recentItems
            let rewrites = self.pendingRewriteIDs
            self.pendingRewriteIDs.removeAll()
            self.persistQueue.async {
                self.persistItems(snapshot, rewriting: rewrites)
            }
        }
        persistWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    private nonisolated func persistItems(_ snapshot: [ClipboardItem], rewriting: Set<String>) {
        secureStore.persist(snapshot, rewriting: rewriting)
        let persisted = secureStore.persistedIDSnapshot()
        DispatchQueue.main.async {
            MainActor.assumeIsolated { self.evictPersistedImages(persisted) }
        }
    }

    private static let residentImageCount = 6

    private func evictPersistedImages(_ persisted: Set<String>) {
        var seenImages = 0
        var changed = false
        var items = recentItems
        for index in items.indices where items[index].kind == .image {
            seenImages += 1
            guard seenImages > Self.residentImageCount,
                  items[index].imagePNGData != nil,
                  persisted.contains(items[index].id) else { continue }
            items[index] = items[index].withoutImageData()
            changed = true
        }
        if changed { recentItems = items }
    }

    private func loadPersistedHistory() {
        persistQueue.async { [weak self] in
            guard let self else { return }
            let (loaded, needsMigration) = self.secureStore.load()
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self.finishLoadingHistory(loaded, needsMigration: needsMigration)
                }
            }
        }
    }

    private func finishLoadingHistory(_ loaded: [ClipboardItem], needsMigration: Bool) {
        isHistoryLoaded = true
        let isSameContent: (ClipboardItem, ClipboardItem) -> Bool = { new, stored in
            new.id == stored.id
                || (new.kind == .text && stored.kind == .text && new.textContent == stored.textContent)
                || (new.fileURLString != nil && new.fileURLString == stored.fileURLString)
                || (new.contentHash != nil && new.contentHash == stored.contentHash)
        }
        let captured = recentItems.map { new in
            !new.isPinned && !clearedPinnedBeforeHistoryLoaded
                && loaded.contains(where: { $0.isPinned && isSameContent(new, $0) })
                ? new.with(pinned: true) : new
        }
        var items = captured
        if clearedPinnedBeforeHistoryLoaded {
        } else if clearedBeforeHistoryLoaded {
            items += loaded.filter { stored in stored.isPinned && !captured.contains { isSameContent($0, stored) } }
        } else {
            items += loaded.filter { stored in !captured.contains { isSameContent($0, stored) } }
        }
        let trimmed = retained(items)
        recentItems = trimmed
        if needsMigration || !captured.isEmpty || clearedBeforeHistoryLoaded || trimmed.count != items.count {
            schedulePersist()
        }
    }
}

private struct UncheckedSendableBox<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}