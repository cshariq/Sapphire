//
//  PlainTextPasteManager.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-02

import AppKit
import Carbon.HIToolbox
import Combine

enum SapphireSyntheticEventMarker {
    static let plainTextPaste: Int64 = 0x5341505048495245
}

private struct StoredPasteboardRepresentation: Sendable {
    let type: String
    let data: Data
}

private struct StoredPasteboardItem: Sendable {
    let representations: [StoredPasteboardRepresentation]
}

private struct PlainTextPastePayload: Sendable {
    let text: String
    let items: [StoredPasteboardItem]
    let sourceChangeCount: Int

    static func capture(from pasteboard: NSPasteboard) -> PlainTextPastePayload? {
        let items = pasteboard.pasteboardItems ?? []
        guard !items.isEmpty else { return nil }

        let types = items.flatMap { $0.types.map(\.rawValue) }
        let hasRichText = types.contains(where: Self.isRichTextType)
        let needsSanitization = SettingsModel.shared.settings.systemEnhancePasteAsPlainNeedsSanitization
        guard (hasRichText || needsSanitization),
              !types.contains(where: Self.isImageType),
              !types.contains(where: Self.isFileType),
              let text = pasteboard.string(forType: .string)
                ?? pasteboard.string(forType: NSPasteboard.PasteboardType("public.utf8-plain-text")) else {
            return nil
        }

        var storedItems: [StoredPasteboardItem] = []
        for item in items {
            let representations = item.types.compactMap { type -> StoredPasteboardRepresentation? in
                guard let data = item.data(forType: type) else { return nil }
                return StoredPasteboardRepresentation(type: type.rawValue, data: data)
            }
            if !representations.isEmpty {
                storedItems.append(StoredPasteboardItem(representations: representations))
            }
        }

        guard !storedItems.isEmpty else { return nil }
        return PlainTextPastePayload(
            text: text,
            items: storedItems,
            sourceChangeCount: pasteboard.changeCount
        )
    }

    func restore(to pasteboard: NSPasteboard) {
        let restoredItems = items.map { storedItem in
            let item = NSPasteboardItem()
            for representation in storedItem.representations {
                item.setData(representation.data, forType: .init(representation.type))
            }
            return item
        }

        pasteboard.clearContents()
        _ = pasteboard.writeObjects(restoredItems)
    }

    private static func isRichTextType(_ type: String) -> Bool {
        [
            "public.rtf",
            "public.rtfd",
            "public.html",
            "text/rtf",
            "text/html",
            "NeXT RTF pasteboard type",
            "Apple HTML pasteboard type",
            "com.apple.webarchive"
        ].contains(type)
    }

    private static func isImageType(_ type: String) -> Bool {
        [
            "public.png",
            "public.tiff",
            "public.jpeg",
            "public.gif",
            "public.heic",
            "public.image"
        ].contains(type)
    }

    private static func isFileType(_ type: String) -> Bool {
        [
            "public.file-url",
            "com.apple.pasteboard.promised-file-url",
            "NSFilenamesPboardType"
        ].contains(type)
    }
}

final class PlainTextPasteManager: @unchecked Sendable {
    static let shared = PlainTextPasteManager()

    private var tapToken: GlobalEventTap.Token?
    private var cancellables = Set<AnyCancellable>()
    private var shortcutRecordingObserver: ShortcutRecordingObserver?

    private let stateLock = NSLock()
    private var isArmed = false
    private var isRecordingShortcut = false

    private init() {
        tapToken = GlobalEventTap.shared.register(
            name: "PlainTextPaste",
            mask: 1 << CGEventType.keyDown.rawValue,
            priority: EventTapPriority.shortcut,
            enabled: false
        ) { [weak self] type, event in
            self?.handle(event: event, type: type) ?? .pass
        }

        shortcutRecordingObserver = ShortcutRecordingObserver { [weak self] in
            self?.setRecordingShortcut($0)
        }

        SettingsModel.shared.changes(of: \.systemEnhancePasteAsPlainTextEnabled)
            .sink { [weak self] _ in self?.updateArming() }
            .store(in: &cancellables)

        updateArming()
    }

    deinit {
        if let tapToken {
            GlobalEventTap.shared.unregister(tapToken)
        }
    }

    private func setRecordingShortcut(_ recording: Bool) {
        stateLock.lock()
        isRecordingShortcut = recording
        stateLock.unlock()
        updateArming()
    }

    private func updateArming() {
        stateLock.lock()
        let armed = SettingsModel.shared.settings.systemEnhancePasteAsPlainTextEnabled && !isRecordingShortcut
        isArmed = armed
        stateLock.unlock()

        guard let tapToken else { return }
        GlobalEventTap.shared.setEnabled(tapToken, armed)
    }

    // MARK: - Event handling (EventTapRunLoop thread)

    private func handle(event: CGEvent, type: CGEventType) -> EventTapDecision {
        guard type == .keyDown,
              event.getIntegerValueField(.keyboardEventAutorepeat) == 0 else {
            return .pass
        }

        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags
        let hasDisallowedModifier = flags.contains(.maskAlternate)
            || flags.contains(.maskControl)
            || flags.contains(.maskShift)
            || flags.contains(.maskSecondaryFn)
        guard keyCode == UInt16(kVK_ANSI_V),
              flags.contains(.maskCommand),
              !hasDisallowedModifier,
              stateAllowsHandling() else {
            return .pass
        }

        guard let payload = PlainTextPastePayload.capture(from: NSPasteboard.general) else {
            return .pass
        }

        rewritePasteboardForPlainTextPaste(payload)
        return .pass
    }

    private func stateAllowsHandling() -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return isArmed && !isRecordingShortcut
    }

    private func rewritePasteboardForPlainTextPaste(_ payload: PlainTextPastePayload) {
        var temporaryChangeCount: Int?
        DispatchQueue.main.sync {
            let pasteboard = NSPasteboard.general
            guard pasteboard.changeCount == payload.sourceChangeCount else { return }

            let clipboardManager = ClipboardManager.shared
            clipboardManager.beginIgnoringExternalPasteboardChanges()

            let cleanedText = Self.sanitizedText(from: payload.text)
            pasteboard.clearContents()
            guard pasteboard.setString(cleanedText, forType: .string) else {
                payload.restore(to: pasteboard)
                clipboardManager.endIgnoringExternalPasteboardChanges(ownChangeCount: pasteboard.changeCount)
                return
            }

            temporaryChangeCount = pasteboard.changeCount
        }

        guard let temporaryChangeCount else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            let pasteboard = NSPasteboard.general
            let clipboardManager = ClipboardManager.shared
            if pasteboard.changeCount == temporaryChangeCount {
                payload.restore(to: pasteboard)
                clipboardManager.endIgnoringExternalPasteboardChanges(ownChangeCount: pasteboard.changeCount)
            } else {
                clipboardManager.endIgnoringExternalPasteboardChanges()
            }
        }
    }

    @MainActor
    func sanitizedText(from text: String) -> String {
        Self.sanitizedText(from: text)
    }

    private static func sanitizedText(from text: String) -> String {
        let settings = SettingsModel.shared.settings
        var result = text
        if settings.systemEnhancePasteAsPlainStripLinks {
            result = stripLinks(from: result)
        }
        if settings.systemEnhancePasteAsPlainStripEmojis {
            result = stripEmojis(from: result)
        }
        if settings.systemEnhancePasteAsPlainStripListMarkers {
            result = stripListMarkers(from: result)
        }
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