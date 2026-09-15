//
//  KeyboardShortcutManager.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-08-11.
//

import AppKit
import Combine
import Carbon.HIToolbox

@MainActor
class KeyboardShortcutManager {
    static let shared = KeyboardShortcutManager()

    private enum ShortcutAction {
        case plane(Plane)
        case snapZone(SnapZoneShortcut)
    }

    private var tapToken: GlobalEventTap.Token?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var cancellables = Set<AnyCancellable>()
    private var shortcutRecordingObserver: ShortcutRecordingObserver?

    private nonisolated(unsafe) var registeredShortcuts: [KeyboardShortcut: ShortcutAction] = [:]
    private let cacheLock = NSLock()
    private let triggerLock = NSLock()
    private nonisolated(unsafe) var lastTriggerAt = Date.distantPast

    private nonisolated(unsafe) var isAccessibilitySuspended = false
    private var isShortcutRecording = false

    private init() {
        registerTrustAwareness()

        shortcutRecordingObserver = ShortcutRecordingObserver { [weak self] isRecording in
            MainActor.assumeIsolated {
                self?.isShortcutRecording = isRecording
                if isRecording {
                    self?.removeTap()
                } else {
                    self?.installTap()
                }
            }
        }

        SettingsModel.shared.$settings
            .debounce(for: .seconds(0.5), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.installTap()
            }
            .store(in: &cancellables)

        PremiumGate.accessChanges
            .sink { [weak self] in self?.installTap() }
            .store(in: &cancellables)
    }

    private func registerTrustAwareness() {
        AccessibilityTrustMonitor.shared.register(name: "KeyboardShortcutManager", owner: self) {
            $0.isAccessibilitySuspended = true
            $0.removeTap()
        } reinstall: {
            $0.isAccessibilitySuspended = false
            $0.installTap()
        }
    }

    private func installTap() {
        guard !isAccessibilitySuspended, !isShortcutRecording else { return }
        removeTap()

        let settings = SettingsModel.shared.settings
        let planesWithShortcuts = settings.planes.filter {
            $0.shortcut != nil && settings.isShortcutEnabled(ShortcutIdentifier.plane($0.id))
        }
        let snapZoneShortcuts = PremiumGate.hasAccess(.snapZonesKeyboardShortcuts)
            ? settings.snapZoneShortcuts.filter {
                settings.isShortcutEnabled(ShortcutIdentifier.snapZone(layoutID: $0.layoutID, zoneID: $0.zoneID))
            }
            : []

        cacheLock.withLock {
            registeredShortcuts.removeAll()

            for plane in planesWithShortcuts {
                if let shortcut = plane.shortcut {
                    registeredShortcuts[shortcut] = .plane(plane)
                }
            }
            for mapping in snapZoneShortcuts {
                registeredShortcuts[mapping.shortcut] = .snapZone(mapping)
            }
        }

        if planesWithShortcuts.isEmpty && snapZoneShortcuts.isEmpty {
            return
        }

        let eventsToMonitor: CGEventMask = (1 << CGEventType.keyDown.rawValue)

        tapToken = GlobalEventTap.shared.register(
            name: "KeyboardShortcutManager",
            mask: eventsToMonitor,
            priority: EventTapPriority.shortcut
        ) { [weak self] type, event in
            self?.handleEvent(type, event) ?? .pass
        }

        if tapToken == nil {
            installFallbackMonitors()
        }
    }

    private func installFallbackMonitors() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            MainActor.assumeIsolated {
                _ = self?.handleNSEvent(event, swallow: false)
            }
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handleNSEvent(event, swallow: true) ? nil : event
        }
    }

    private func removeTap() {
        if let token = tapToken {
            GlobalEventTap.shared.unregister(token)
            tapToken = nil
        }
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
        globalMonitor = nil
        localMonitor = nil
        cacheLock.withLock {
            registeredShortcuts.removeAll()
        }
    }

    nonisolated private func handleEvent(_ type: CGEventType, _ event: CGEvent) -> EventTapDecision {
        guard type == .keyDown else { return .pass }
        guard event.getIntegerValueField(.eventSourceUserData) != SapphireSyntheticEventMarker.plainTextPaste else {
            return .pass
        }

        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))

        guard let nsEvent = NSEvent(cgEvent: event) else {
            return .pass
        }

        let flags = nsEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)

        guard let keyString = KeyCodeTranslator.shared.string(for: keyCode, from: nsEvent) else {
            return .pass
        }

        let currentShortcut = KeyboardShortcut(key: keyString, modifiers: flags)

        guard let action = action(for: currentShortcut) else { return .pass }
        guard shouldTrigger() else { return .swallow }

        perform(action)
        return .swallow
    }

    @discardableResult
    private func handleNSEvent(_ event: NSEvent, swallow: Bool) -> Bool {
        guard event.type == .keyDown, !event.isARepeat else { return false }
        guard event.cgEvent?.getIntegerValueField(.eventSourceUserData) != SapphireSyntheticEventMarker.plainTextPaste else {
            return false
        }

        let keyCode = UInt16(event.keyCode)
        guard let keyString = KeyCodeTranslator.shared.string(for: keyCode, from: event) else {
            return false
        }

        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let currentShortcut = KeyboardShortcut(key: keyString, modifiers: modifiers)

        guard let action = action(for: currentShortcut) else { return false }
        guard shouldTrigger() else { return swallow }

        perform(action)
        return swallow
    }

    nonisolated private func action(for shortcut: KeyboardShortcut) -> ShortcutAction? {
        cacheLock.withLock {
            registeredShortcuts[shortcut]
        }
    }

    nonisolated private func shouldTrigger() -> Bool {
        triggerLock.withLock {
            let now = Date()
            guard now.timeIntervalSince(lastTriggerAt) > 0.3 else { return false }
            lastTriggerAt = now
            return true
        }
    }

    nonisolated private func perform(_ action: ShortcutAction) {
        DispatchQueue.main.async {
            switch action {
            case .plane(let plane):
                guard SettingsModel.shared.settings.isShortcutEnabled(ShortcutIdentifier.plane(plane.id)) else { return }
                WindowArrangementManager.shared.activate(plane: plane)
            case .snapZone(let mapping):
                guard SettingsModel.shared.settings.isShortcutEnabled(
                    ShortcutIdentifier.snapZone(layoutID: mapping.layoutID, zoneID: mapping.zoneID)
                ) else { return }
                SnappingManager.snap(layoutID: mapping.layoutID, zoneID: mapping.zoneID)
            }
        }
    }
}