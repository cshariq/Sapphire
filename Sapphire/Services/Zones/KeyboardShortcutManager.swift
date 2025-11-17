//
//  KeyboardShortcutManager.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-08-11.
//

import AppKit
import Combine
import Carbon.HIToolbox

private func executionTapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let refcon = refcon else { return Unmanaged.passRetained(event) }

    let manager = Unmanaged<KeyboardShortcutManager>.fromOpaque(refcon).takeUnretainedValue()
    return manager.handle(event: event, type: type)
}

class KeyboardShortcutManager {
    static let shared = KeyboardShortcutManager()

    private var eventTap: CFMachPort?
    private var cancellables = Set<AnyCancellable>()

    private var registeredShortcuts: [KeyboardShortcut: Plane] = [:]
    private let cacheLock = NSLock()

    private init() {
        SettingsModel.shared.$settings
            .debounce(for: .seconds(0.5), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.setupMonitor()
            }
            .store(in: &cancellables)
    }

    func setupMonitor() {
        stopMonitoring()

        let planesWithShortcuts = SettingsModel.shared.settings.planes.filter { $0.shortcut != nil }

        cacheLock.withLock {
            registeredShortcuts.removeAll()
            guard !planesWithShortcuts.isEmpty else {
                return
            }
            for plane in planesWithShortcuts {
                if let shortcut = plane.shortcut {
                    registeredShortcuts[shortcut] = plane
                }
            }
        }

        if planesWithShortcuts.isEmpty { return }

        let eventsToMonitor: CGEventMask = (1 << CGEventType.keyDown.rawValue)
        let selfAsUnsafeMutableRawPointer = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventsToMonitor,
            callback: executionTapCallback,
            userInfo: selfAsUnsafeMutableRawPointer
        )

        guard let eventTap = eventTap else {
            print("[KeyboardShortcutManager] FATAL ERROR: Failed to create execution event tap. Check Accessibility Permissions.")
            return
        }

        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }

    func stopMonitoring() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        eventTap = nil
        cacheLock.withLock {
            registeredShortcuts.removeAll()
        }
    }

    nonisolated func handle(event: CGEvent, type: CGEventType) -> Unmanaged<CGEvent>? {
        guard type == .keyDown else { return Unmanaged.passRetained(event) }

        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))

        guard let nsEvent = NSEvent(cgEvent: event) else {
            return Unmanaged.passRetained(event)
        }

        let flags = nsEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)

        guard let keyString = KeyCodeTranslator.shared.string(for: keyCode, from: nsEvent) else {
            return Unmanaged.passRetained(event)
        }

        let currentShortcut = KeyboardShortcut(key: keyString, modifiers: flags)

        var planeToActivate: Plane?
        cacheLock.withLock {
            planeToActivate = registeredShortcuts[currentShortcut]
        }

        if let plane = planeToActivate {
            print("[KeyboardShortcutManager] Activating event plane.")
            Task { @MainActor in
                WindowArrangementManager.shared.activate(plane: plane)
            }
            return nil
        }

        return Unmanaged.passRetained(event)
    }
}