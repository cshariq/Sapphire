//
//  FocusSessionShortcutMonitor.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-25
//

import Foundation
import Carbon.HIToolbox
import Combine

@MainActor
final class FocusSessionShortcutMonitor {
    static let shared = FocusSessionShortcutMonitor()

    private var hotKeyRef: EventHotKeyRef?
    private var hotKeyID = EventHotKeyID(signature: 0x53464F43, id: 1)

    private var cancellables = Set<AnyCancellable>()

    private init() {
        SettingsModel.shared.$settings
            .debounce(for: .seconds(0.5), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateRegistration()
            }
            .store(in: &cancellables)
        updateRegistration()
        installEventHandler()
    }

    deinit {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
        }
    }

    // MARK: - Registration

    private func updateRegistration() {
        let shortcut = SettingsModel.shared.settings.focusStartShortcut
        let hasValidShortcut = !shortcut.key.isEmpty
            && shortcut.significantModifiers.rawValue != 0

        unregister()

        guard hasValidShortcut else { return }
        guard let keyCode = KeyCodeTranslator.shared.keyCode(for: shortcut.key) else { return }

        var modifiers = UInt32(0)
        if shortcut.significantModifiers.contains(.command) { modifiers |= UInt32(cmdKey) }
        if shortcut.significantModifiers.contains(.option)  { modifiers |= UInt32(optionKey) }
        if shortcut.significantModifiers.contains(.control) { modifiers |= UInt32(controlKey) }
        if shortcut.significantModifiers.contains(.shift)   { modifiers |= UInt32(shiftKey) }

        var id = hotKeyID
        let status = RegisterEventHotKey(
            UInt32(keyCode),
            modifiers,
            id,
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef
        )
        if status != noErr {
            print("[FocusSessionShortcutMonitor] Failed to register hotkey: \(status)")
        }
    }

    private func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
    }

    // MARK: - Event handler

    private func installEventHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let selfPtr = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

        InstallEventHandler(
            GetEventDispatcherTarget(),
            { (_, event, userData) -> OSStatus in
                guard let userData else { return -1 }
                let monitor = Unmanaged<FocusSessionShortcutMonitor>
                    .fromOpaque(userData)
                    .takeUnretainedValue()
                monitor.handleHotKey()
                return noErr
            },
            1,
            &eventType,
            selfPtr,
            nil
        )
    }

    private func handleHotKey() {
        let manager = FocusSessionManager.shared
        if manager.isSessionActive {
            manager.togglePause()
        } else {
            manager.startFocusSession()
        }
    }
}