//
//  PlainTextPasteManager.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-02

import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Combine

enum SapphireSyntheticEventMarker {
    static let plainTextPaste: Int64 = 0x5341505048495245
}

private struct PasteboardSnapshot: @unchecked Sendable {
    let changeCount: Int
    let text: String?
    let items: [[(type: NSPasteboard.PasteboardType, data: Data)]]
    let isComplete: Bool

    static func read(from pasteboard: NSPasteboard) -> PasteboardSnapshot {
        let changeCount = pasteboard.changeCount
        let text = pasteboard.string(forType: .string)
        var stored: [[(NSPasteboard.PasteboardType, Data)]] = []
        var complete = true
        for item in pasteboard.pasteboardItems ?? [] {
            var representations: [(NSPasteboard.PasteboardType, Data)] = []
            for type in item.types {
                guard let data = item.data(forType: type) else {
                    complete = false
                    continue
                }
                representations.append((type, data))
            }
            if !representations.isEmpty { stored.append(representations) }
        }
        return PasteboardSnapshot(changeCount: changeCount, text: text, items: stored, isComplete: complete)
    }

    func restore(to pasteboard: NSPasteboard) -> Bool {
        let restored = items.map { representations -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for representation in representations {
                item.setData(representation.data, forType: representation.type)
            }
            return item
        }
        pasteboard.clearContents()
        return restored.isEmpty || pasteboard.writeObjects(restored)
    }
}

private final class TransientTextProvider: NSObject, NSPasteboardItemDataProvider, @unchecked Sendable {
    private let text: String
    private let onRead: @Sendable () -> Void

    init(text: String, onRead: @escaping @Sendable () -> Void) {
        self.text = text
        self.onRead = onRead
    }

    func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem, provideDataForType type: NSPasteboard.PasteboardType) {
        item.setString(text, forType: type)
        onRead()
    }

    func pasteboardFinishedWithDataProvider(_ pasteboard: NSPasteboard) {}
}

final class PlainTextPasteManager: @unchecked Sendable {
    static let shared = PlainTextPasteManager()

    private struct Trigger {
        let keyCode: Int64
        let flags: CGEventFlags
    }

    private struct PendingRestore {
        let snapshot: PasteboardSnapshot
        let transientChangeCount: Int
        let provider: TransientTextProvider
    }

    private var tapToken: GlobalEventTap.Token?
    private var cancellables = Set<AnyCancellable>()
    private var shortcutRecordingObserver: ShortcutRecordingObserver?
    private var inputSourceObserver: NSObjectProtocol?
    private let axQueue = DispatchQueue(label: "com.sapphire.plain-paste.ax", qos: .userInitiated)

    private let stateLock = NSLock()
    private var trigger: Trigger?
    private var isRecordingShortcut = false

    private var isPerforming = false
    private var pendingRestore: PendingRestore?
    private var restoreWork: DispatchWorkItem?
    private var acceptsTargetReads = false

    private static let modifierMask: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl, .maskShift]

    private init() {
        tapToken = GlobalEventTap.shared.register(
            name: "PlainTextPaste",
            mask: 1 << CGEventType.keyDown.rawValue,
            priority: EventTapPriority.shortcut,
            enabled: false
        ) { [weak self] type, event in
            self?.handle(event: event, type: type) ?? .pass
        }

        shortcutRecordingObserver = ShortcutRecordingObserver { [weak self] recording in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.setRecordingShortcut(recording) }
            }
        }

        inputSourceObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.Carbon.TISNotifySelectedKeyboardInputSourceChanged"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateArming() }
        }

        SettingsModel.shared.changes(of: { PlainPasteConfiguration(settings: $0) })
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.updateArming() }
            }
            .store(in: &cancellables)

        if Thread.isMainThread {
            MainActor.assumeIsolated { updateArming() }
        } else {
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated { self?.updateArming() }
            }
        }
    }

    deinit {
        if let tapToken { GlobalEventTap.shared.unregister(tapToken) }
        if let inputSourceObserver { DistributedNotificationCenter.default().removeObserver(inputSourceObserver) }
    }

    private struct PlainPasteConfiguration: Equatable {
        let enabled: Bool
        let shortcut: KeyboardShortcut

        init(settings: Settings) {
            enabled = settings.systemEnhancePasteAsPlainTextEnabled
            shortcut = settings.systemEnhancePasteAsPlainShortcut
        }
    }

    @MainActor
    private func setRecordingShortcut(_ recording: Bool) {
        stateLock.lock()
        isRecordingShortcut = recording
        stateLock.unlock()
        updateArming()
    }

    @MainActor
    private func updateArming() {
        let settings = SettingsModel.shared.settings
        var resolved: Trigger?
        if settings.systemEnhancePasteAsPlainTextEnabled {
            let shortcut = settings.systemEnhancePasteAsPlainShortcut
            if shortcut.modifiers.contains(.command) || shortcut.modifiers.contains(.control),
               let keyCode = KeyCodeTranslator.shared.keyCode(for: shortcut.key) {
                var flags: CGEventFlags = []
                if shortcut.modifiers.contains(.command) { flags.insert(.maskCommand) }
                if shortcut.modifiers.contains(.option) { flags.insert(.maskAlternate) }
                if shortcut.modifiers.contains(.control) { flags.insert(.maskControl) }
                if shortcut.modifiers.contains(.shift) { flags.insert(.maskShift) }
                resolved = Trigger(keyCode: Int64(keyCode), flags: flags)
            }
        }

        stateLock.lock()
        trigger = resolved
        let armed = resolved != nil && !isRecordingShortcut
        stateLock.unlock()

        guard let tapToken else { return }
        GlobalEventTap.shared.setEnabled(tapToken, armed)
        if !armed { cancelPendingRestore(restoreNow: true) }
    }

    // MARK: - Event handling (EventTapRunLoop thread)

    private func handle(event: CGEvent, type: CGEventType) -> EventTapDecision {
        guard type == .keyDown,
              event.getIntegerValueField(.eventSourceUserData) != SapphireSyntheticEventMarker.plainTextPaste else {
            return .pass
        }
        stateLock.lock()
        let trigger = isRecordingShortcut ? nil : self.trigger
        stateLock.unlock()
        guard let trigger,
              event.getIntegerValueField(.keyboardEventKeycode) == trigger.keyCode,
              event.flags.intersection(Self.modifierMask) == trigger.flags else {
            return .pass
        }
        guard event.getIntegerValueField(.keyboardEventAutorepeat) == 0 else { return .swallow }

        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated { self?.performPlainTextPaste() }
        }
        return .swallow
    }

    // MARK: - Paste (main thread)

    @MainActor
    private func performPlainTextPaste() {
        guard !isPerforming else { return }
        isPerforming = true

        let frontmost = NSWorkspace.shared.frontmostApplication
        let pid = frontmost?.processIdentifier ?? 0
        let bundleID = frontmost?.bundleIdentifier
        let isSelf = pid == ProcessInfo.processInfo.processIdentifier
        guard pid > 0, !isSelf, pendingRestore == nil else {
            pasteThroughPasteboard()
            return
        }
        axQueue.async { [weak self] in
            var pressed = false
            defer {
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        guard let self else { return }
                        if pressed {
                            self.isPerforming = false
                        } else {
                            self.pasteThroughPasteboard()
                        }
                    }
                }
            }
            pressed = Self.pressPasteAndMatchStyle(pid: pid, bundleID: bundleID)
        }
    }

    private static let menuWalkTimeout: Float = 0.35

    private static let menuItemCacheLock = NSLock()
    nonisolated(unsafe) private static var menuItemCache: [String: AXUIElement] = [:]

    private static func pressPasteAndMatchStyle(pid: pid_t, bundleID: String?) -> Bool {
        guard AccessibilityTrustMonitor.isCurrentlyTrusted() else { return false }
        let app = AX.application(pid: pid)
        AX.setMessagingTimeout(menuWalkTimeout, on: app)

        if let bundleID {
            menuItemCacheLock.lock()
            let cached = menuItemCache[bundleID]
            menuItemCacheLock.unlock()
            if let cached {
                AX.setMessagingTimeout(menuWalkTimeout, on: cached)
                if AX.pid(of: cached) == pid, let enabled = AX.bool(kAXEnabledAttribute as String, of: cached) {
                    return enabled && AX.perform(kAXPressAction as String, on: cached)
                }
                menuItemCacheLock.lock()
                if let current = menuItemCache[bundleID], CFEqual(current, cached) {
                    menuItemCache.removeValue(forKey: bundleID)
                }
                menuItemCacheLock.unlock()
            }
        }

        guard let menuBar = AX.element(kAXMenuBarAttribute as String, of: app) else { return false }
        AX.setMessagingTimeout(menuWalkTimeout, on: menuBar)
        let keyCharacter = { AX.string(kAXMenuItemCmdCharAttribute as String, of: $0)?.uppercased() }
        let modifiers = { AX.int(kAXMenuItemCmdModifiersAttribute as String, of: $0) ?? 0 }
        for barItem in AX.children(of: menuBar).dropFirst() {
            AX.setMessagingTimeout(menuWalkTimeout, on: barItem)
            guard let menu = AX.children(of: barItem).first else { continue }
            AX.setMessagingTimeout(menuWalkTimeout, on: menu)
            let items = AX.children(of: menu)
            guard items.contains(where: { keyCharacter($0) == "V" && modifiers($0) == 0 }) else { continue }
            let match = items.first { item in
                let mods = modifiers(item)
                guard keyCharacter(item) == "V", mods & 1 != 0, mods & (4 | 8) == 0 else { return false }
                let title = AX.title(of: item)?.lowercased() ?? ""
                return !title.contains("preserve") && !title.contains("keep")
            }
            guard let match, AX.bool(kAXEnabledAttribute as String, of: match) ?? true else { return false }
            if let bundleID {
                menuItemCacheLock.lock()
                menuItemCache[bundleID] = match
                menuItemCacheLock.unlock()
            }
            return AX.perform(kAXPressAction as String, on: match)
        }
        return false
    }

    @MainActor
    private func pasteThroughPasteboard() {
        let clipboard = ClipboardManager.shared
        let previous = pendingRestore
        restoreWork?.cancel()
        restoreWork = nil
        acceptsTargetReads = false
        if previous == nil { clipboard.beginIgnoringExternalPasteboardChanges() }

        PasteboardLane.shared.run(timeout: 2, { pasteboard -> (snapshot: PasteboardSnapshot, current: Int) in
            if let previous, pasteboard.changeCount == previous.transientChangeCount {
                return (previous.snapshot, previous.transientChangeCount)
            }
            let snapshot = PasteboardSnapshot.read(from: pasteboard)
            return (snapshot, snapshot.changeCount)
        }, completion: { [weak self] result in
            guard let self else { return }
            guard let result, let text = result.snapshot.text, !text.isEmpty, result.snapshot.isComplete else {
                self.finishWithoutRestore()
                self.postPasteWhenModifiersReleased()
                return
            }
            self.writeTransient(
                text: Self.sanitizedText(from: text),
                snapshot: result.snapshot,
                expectedChangeCount: result.current
            )
        })
    }

    @MainActor
    private func writeTransient(text: String, snapshot: PasteboardSnapshot, expectedChangeCount: Int) {
        let provider = TransientTextProvider(text: text) { [weak self] in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.targetDidRead() }
            }
        }
        PasteboardLane.shared.write({ pasteboard in
            guard pasteboard.changeCount == expectedChangeCount else { return false }
            let item = NSPasteboardItem()
            item.setDataProvider(provider, forTypes: [.string])
            item.setData(Data(), forType: .sapphireTransient)
            pasteboard.clearContents()
            return pasteboard.writeObjects([item])
        }, completion: { [weak self] changeCount in
            guard let self else { return }
            guard let changeCount else {
                self.finishWithoutRestore()
                return
            }
            self.pendingRestore = PendingRestore(snapshot: snapshot, transientChangeCount: changeCount, provider: provider)
            self.postPasteWhenModifiersReleased {
                self.isPerforming = false
                self.acceptsTargetReads = true
                self.scheduleRestore(after: 3)
            }
        })
    }

    @MainActor
    private func targetDidRead() {
        guard acceptsTargetReads, pendingRestore != nil else { return }
        scheduleRestore(after: 0.25)
    }

    @MainActor
    private func scheduleRestore(after delay: TimeInterval) {
        restoreWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.restoreNow() }
        }
        restoreWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    @MainActor
    private func restoreNow() {
        restoreWork = nil
        acceptsTargetReads = false
        guard let pending = pendingRestore else { return }
        pendingRestore = nil
        PasteboardLane.shared.run(timeout: 3, { pasteboard -> Int? in
            guard pasteboard.changeCount == pending.transientChangeCount else { return nil }
            return pending.snapshot.restore(to: pasteboard) ? pasteboard.changeCount : nil
        }, completion: { changeCount in
            ClipboardManager.shared.endIgnoringExternalPasteboardChanges(ownChangeCount: changeCount)
        })
    }

    @MainActor
    private func cancelPendingRestore(restoreNow shouldRestore: Bool) {
        guard pendingRestore != nil else { return }
        if shouldRestore {
            restoreWork?.cancel()
            restoreNow()
        }
    }

    @MainActor
    private func finishWithoutRestore() {
        if pendingRestore != nil {
            scheduleRestore(after: 0.25)
        } else {
            ClipboardManager.shared.endIgnoringExternalPasteboardChanges()
        }
        isPerforming = false
    }

    @MainActor
    private func postPasteWhenModifiersReleased(attempt: Int = 0, then completion: (() -> Void)? = nil) {
        let held = CGEventSource.flagsState(.combinedSessionState).intersection(Self.modifierMask)
        guard held.isEmpty || attempt >= 75 else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { [weak self] in
                MainActor.assumeIsolated { self?.postPasteWhenModifiersReleased(attempt: attempt + 1, then: completion) }
            }
            return
        }
        Self.postCommandV()
        completion?()
    }

    private static func postCommandV() {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false) else {
            return
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.setIntegerValueField(.eventSourceUserData, value: SapphireSyntheticEventMarker.plainTextPaste)
        keyUp.setIntegerValueField(.eventSourceUserData, value: SapphireSyntheticEventMarker.plainTextPaste)
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }

    // MARK: - Sanitizing

    @MainActor
    func sanitizedText(from text: String) -> String {
        Self.sanitizedText(from: text)
    }

    @MainActor
    private static func sanitizedText(from text: String) -> String {
        let settings = SettingsModel.shared.settings
        return PlainTextSanitizer.sanitize(
            text,
            stripLinks: settings.systemEnhancePasteAsPlainStripLinks,
            stripEmojis: settings.systemEnhancePasteAsPlainStripEmojis,
            stripListMarkers: settings.systemEnhancePasteAsPlainStripListMarkers
        )
    }
}

nonisolated enum PlainTextSanitizer {
    static func sanitize(_ text: String, stripLinks: Bool, stripEmojis: Bool, stripListMarkers: Bool) -> String {
        var result = text
        if stripLinks { result = Self.stripLinks(from: result) }
        if stripEmojis { result = Self.stripEmojis(from: result) }
        if stripListMarkers { result = Self.stripListMarkers(from: result) }
        return result
    }

    private static func stripLinks(from text: String) -> String {
        let pattern = #"(?i)\b(?:https?|ftp)://[^\s<>"']+|www\.[^\s<>"']+|mailto:[^\s<>"']+"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        var result = text
        let fullRange = NSRange(result.startIndex..., in: result)
        let matches = regex.matches(in: result, range: fullRange).reversed()
        for match in matches {
            guard let range = Range(match.range, in: result) else { continue }
            var link = result[range]
            while let last = link.last, ".,;:!?)]}»”’\"".contains(last) {
                link = link.dropLast()
            }
            guard !link.isEmpty else { continue }
            let linkRange = link.startIndex..<link.endIndex
            result.replaceSubrange(linkRange, with: "")
        }
        return result
    }

    private static func stripEmojis(from text: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            let shouldRemove = scalar.properties.isEmojiPresentation
                || (0xFE00...0xFE0F).contains(scalar.value)
                || scalar.value == 0x200D
                || (0x1F3FB...0x1F3FF).contains(scalar.value)
                || (0x1F1E6...0x1F1FF).contains(scalar.value)
                || (0xE0020...0xE007F).contains(scalar.value)
                || scalar.value == 0x20E3
            if !shouldRemove {
                scalars.append(scalar)
            }
        }
        return String(scalars)
    }

    private static func stripListMarkers(from text: String) -> String {
        let pattern = #"(?m)^[ \t]*(?:[•◦‣▪▫⁃·–—]|\*|\+|-|\d+[.)]|\(\d+\))(?=[ \t]|$)[ \t]*"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
    }
}