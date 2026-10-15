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

    private struct ShortcutRegistrationSettings: Equatable {
        var planes: [Plane]
        var snapZoneShortcuts: [SnapZoneShortcut]
        var dockLayoutsEnabled: Bool
        var dockLayoutsPresets: [DockLayout]
        var disabledShortcutIDs: Set<String>

        init(_ settings: Settings) {
            planes = settings.planes
            snapZoneShortcuts = settings.snapZoneShortcuts
            dockLayoutsEnabled = settings.dockLayoutsEnabled
            dockLayoutsPresets = settings.dockLayoutsPresets
            disabledShortcutIDs = settings.disabledShortcutIDs
        }

        func isEnabled(_ identifier: String) -> Bool {
            !disabledShortcutIDs.contains(identifier)
        }
    }

    struct ExternalShortcut {
        let identifier: String
        let shortcut: KeyboardShortcut
        let perform: @MainActor () -> Void
    }

    struct ExternalShortcutProvider {
        let shortcuts: @MainActor (Settings) -> [ExternalShortcut]
        let reportUnavailable: @MainActor (Set<String>) -> Void
    }

    private enum ShortcutAction {
        case plane(Plane)
        case snapZone(SnapZoneShortcut)
        case external(ExternalShortcut)
    }

    private var externalProviders: [String: ExternalShortcutProvider] = [:]

    private struct ShortcutTrigger: Hashable {
        let keyCode: UInt16
        let modifiers: UInt64
    }

    private var tapToken: GlobalEventTap.Token?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var cancellables = Set<AnyCancellable>()
    private var shortcutRecordingObserver: ShortcutRecordingObserver?
    private var keyboardInputSourceObserver: NSObjectProtocol?

    private nonisolated(unsafe) var registeredShortcuts: [ShortcutTrigger: ShortcutAction] = [:]
    private let cacheLock = NSLock()
    private let triggerLock = NSLock()
    private nonisolated(unsafe) var lastTriggerAt = Date.distantPast

    private nonisolated(unsafe) var isAccessibilitySuspended = false
    private var isShortcutRecording = false

    private init() {
        registerTrustAwareness()

        keyboardInputSourceObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.Carbon.TISNotifySelectedKeyboardInputSourceChanged"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.installTap()
            }
        }

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

        let initialSettings = ShortcutRegistrationSettings(SettingsModel.shared.settings)
        SettingsModel.shared.changes(of: ShortcutRegistrationSettings.init)
            .prepend(initialSettings)
            .debounce(for: .seconds(0.5), scheduler: DispatchQueue.main)
            .sink { [weak self] settings in
                self?.installTap(using: settings)
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
        installTap(using: ShortcutRegistrationSettings(SettingsModel.shared.settings))
    }

    func registerExternalShortcutProvider(_ provider: ExternalShortcutProvider, named name: String) {
        externalProviders[name] = provider
        installTap()
    }

    private func installTap(using settings: ShortcutRegistrationSettings) {
        guard !isAccessibilitySuspended, !isShortcutRecording else { return }
        removeTap()

        let planesWithShortcuts = settings.planes.filter {
            $0.shortcut != nil && settings.isEnabled(ShortcutIdentifier.plane($0.id))
        }
        let snapZoneShortcuts = PremiumGate.hasAccess(.snapZonesKeyboardShortcuts)
            ? settings.snapZoneShortcuts.filter {
                settings.isEnabled(ShortcutIdentifier.snapZone(layoutID: $0.layoutID, zoneID: $0.zoneID))
            }
            : []

        var registrations: [ShortcutTrigger: ShortcutAction] = [:]
        for plane in planesWithShortcuts {
            if let shortcut = plane.shortcut,
               let trigger = trigger(for: shortcut) {
                registrations[trigger] = .plane(plane)
            }
        }
        for mapping in snapZoneShortcuts {
            if let trigger = trigger(for: mapping.shortcut) {
                registrations[trigger] = .snapZone(mapping)
            }
        }

        let currentSettings = SettingsModel.shared.settings
        for provider in externalProviders.values {
            var unavailable = Set<String>()
            for external in provider.shortcuts(currentSettings) {
                guard settings.isEnabled(external.identifier),
                      let trigger = trigger(for: external.shortcut) else { continue }
                if registrations[trigger] == nil {
                    registrations[trigger] = .external(external)
                } else {
                    unavailable.insert(external.identifier)
                }
            }
            provider.reportUnavailable(unavailable)
        }

        cacheLock.withLock {
            registeredShortcuts = registrations
        }

        if registrations.isEmpty {
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
        let trigger = ShortcutTrigger(
            keyCode: keyCode,
            modifiers: significantModifiers(from: event.flags)
        )

        guard let action = action(for: trigger) else { return .pass }
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
        let trigger = ShortcutTrigger(
            keyCode: keyCode,
            modifiers: significantModifiers(from: event.modifierFlags)
        )

        guard let action = action(for: trigger) else { return false }
        guard shouldTrigger() else { return swallow }

        perform(action)
        return swallow
    }

    private func trigger(for shortcut: KeyboardShortcut) -> ShortcutTrigger? {
        guard let keyCode = KeyCodeTranslator.shared.keyCode(for: shortcut.key) else {
            return nil
        }
        return ShortcutTrigger(
            keyCode: keyCode,
            modifiers: significantModifiers(from: shortcut.significantModifiers)
        )
    }

    nonisolated private func significantModifiers(from flags: CGEventFlags) -> UInt64 {
        flags.rawValue & (
            CGEventFlags.maskCommand.rawValue
                | CGEventFlags.maskAlternate.rawValue
                | CGEventFlags.maskControl.rawValue
                | CGEventFlags.maskShift.rawValue
        )
    }

    private func significantModifiers(from flags: NSEvent.ModifierFlags) -> UInt64 {
        var result: UInt64 = 0
        if flags.contains(.command) { result |= CGEventFlags.maskCommand.rawValue }
        if flags.contains(.option) { result |= CGEventFlags.maskAlternate.rawValue }
        if flags.contains(.control) { result |= CGEventFlags.maskControl.rawValue }
        if flags.contains(.shift) { result |= CGEventFlags.maskShift.rawValue }
        return result
    }

    nonisolated private func action(for trigger: ShortcutTrigger) -> ShortcutAction? {
        cacheLock.withLock {
            registeredShortcuts[trigger]
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
            case .external(let external):
                guard SettingsModel.shared.settings.isShortcutEnabled(external.identifier) else { return }
                MainActor.assumeIsolated { external.perform() }
            }
        }
    }
}