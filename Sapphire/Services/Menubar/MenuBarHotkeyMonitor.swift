//
//  MenuBarHotkeyMonitor.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-27
//

import AppKit
import Combine
import os

@MainActor
final class MenuBarHotkeyMonitor {
    static let shared = MenuBarHotkeyMonitor()

    enum Action: CaseIterable {
        case toggleHidden, toggleAlwaysHidden, search, zenMode

        var identifier: String {
            switch self {
            case .toggleHidden: return ShortcutIdentifier.menuBarToggleHidden
            case .toggleAlwaysHidden: return ShortcutIdentifier.menuBarToggleAlwaysHidden
            case .search: return ShortcutIdentifier.menuBarSearch
            case .zenMode: return ShortcutIdentifier.menuBarZenMode
            }
        }

        func shortcut(in settings: Settings) -> KeyboardShortcut {
            switch self {
            case .toggleHidden: return settings.menuBarToggleHiddenShortcut
            case .toggleAlwaysHidden: return settings.menuBarToggleAlwaysHiddenShortcut
            case .search: return settings.menuBarSearchShortcut
            case .zenMode: return settings.menuBarZenModeShortcut
            }
        }
    }

    private struct Trigger: Sendable {
        let keyCode: Int64
        let flags: CGEventFlags
        let actionIndex: Int
    }

    private struct Configuration: Equatable {
        let menuBarEnabled: Bool
        let shortcuts: [KeyboardShortcut]
        let enabled: [Bool]
    }

    private nonisolated static let modifierMask: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl, .maskShift]

    private nonisolated let triggers = OSAllocatedUnfairLock<[Trigger]>(initialState: [])
    private var tapToken: GlobalEventTap.Token?
    private var cancellables = Set<AnyCancellable>()
    private var isStarted = false

    private init() {}

    func start() {
        guard !isStarted else { return }
        isStarted = true
        SettingsModel.shared.$settings
            .map { settings in
                Configuration(
                    menuBarEnabled: settings.menuBarEnabled,
                    shortcuts: Action.allCases.map { $0.shortcut(in: settings) },
                    enabled: Action.allCases.map { settings.isShortcutEnabled($0.identifier) }
                )
            }
            .removeDuplicates()
            .dropFirst()
            .debounce(for: .seconds(0.3), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateTap() }
            .store(in: &cancellables)
        updateTap()
    }

    private func updateTap() {
        let resolved = resolveTriggers()
        triggers.withLock { $0 = resolved }

        if !resolved.isEmpty, tapToken == nil {
            tapToken = GlobalEventTap.shared.register(
                name: "MenuBarHotkeys",
                mask: 1 << CGEventType.keyDown.rawValue,
                priority: EventTapPriority.shortcut
            ) { [weak self] type, event in
                self?.process(type: type, event: event) ?? .pass
            }
        } else if resolved.isEmpty, let tapToken {
            GlobalEventTap.shared.unregister(tapToken)
            self.tapToken = nil
        }
    }

    private func resolveTriggers() -> [Trigger] {
        let settings = SettingsModel.shared.settings
        guard settings.menuBarEnabled else { return [] }

        return Action.allCases.enumerated().compactMap { index, action in
            let shortcut = action.shortcut(in: settings)
            guard settings.isShortcutEnabled(action.identifier),
                  !shortcut.key.isEmpty, shortcut.significantModifiers.rawValue != 0,
                  let keyCode = KeyCodeTranslator.shared.keyCode(for: shortcut.key) else { return nil }

            var flags: CGEventFlags = []
            if shortcut.significantModifiers.contains(.command) { flags.insert(.maskCommand) }
            if shortcut.significantModifiers.contains(.option) { flags.insert(.maskAlternate) }
            if shortcut.significantModifiers.contains(.control) { flags.insert(.maskControl) }
            if shortcut.significantModifiers.contains(.shift) { flags.insert(.maskShift) }
            return Trigger(keyCode: Int64(keyCode), flags: flags, actionIndex: index)
        }
    }

    // MARK: - Event processing (EventTapRunLoop thread)

    private nonisolated func process(type: CGEventType, event: CGEvent) -> EventTapDecision {
        guard type == .keyDown else { return .pass }
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags.intersection(Self.modifierMask)
        guard let trigger = triggers.withLock({ $0.first { $0.keyCode == keyCode && $0.flags == flags } }) else {
            return .pass
        }
        let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        if !isRepeat {
            let index = trigger.actionIndex
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated { self?.perform(Action.allCases[index]) }
            }
        }
        return .swallow
    }

    private func perform(_ action: Action) {
        let controller = (NSApp.delegate as? AppDelegate)?.statusBarController
        switch action {
        case .toggleHidden: controller?.toggleHiddenSection()
        case .toggleAlwaysHidden: controller?.toggleAlwaysHiddenSection()
        case .search: MenuBarSearchPanelController.shared.toggle()
        case .zenMode: controller?.toggleZenMode()
        }
    }
}