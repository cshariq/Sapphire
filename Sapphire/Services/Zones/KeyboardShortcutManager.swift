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
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        Task { @MainActor in
            manager.ensureEventTapEnabled(forceRebuild: true)
        }
        return Unmanaged.passRetained(event)
    }
    return manager.handle(event: event, type: type)
}

class KeyboardShortcutManager {
    static let shared = KeyboardShortcutManager()

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var cancellables = Set<AnyCancellable>()

    private var registeredShortcuts: [KeyboardShortcut: Plane] = [:]
    private let cacheLock = NSLock()
    private var lastTriggerAt = Date.distantPast

    private init() {
        SettingsModel.shared.$settings
            .debounce(for: .seconds(0.5), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.setupMonitor()
            }
            .store(in: &cancellables)
    }

    func setupMonitor() {
        print("[KeyboardShortcutManager] setupMonitor() called")
        stopMonitoring()

        let planesWithShortcuts = SettingsModel.shared.settings.planes.filter { $0.shortcut != nil }
        print("[KeyboardShortcutManager] Planes with shortcuts: \(planesWithShortcuts.count)")
        for plane in planesWithShortcuts {
            if let shortcut = plane.shortcut {
                print("[KeyboardShortcutManager]   -> plane '\(plane.name)': \(KeyboardShortcutHelper.description(for: shortcut.significantModifiers))\(shortcut.key)")
            }
        }

        cacheLock.withLock {
            registeredShortcuts.removeAll()
            for plane in planesWithShortcuts {
                if let shortcut = plane.shortcut {
                    registeredShortcuts[shortcut] = plane
                }
            }
        }

        if planesWithShortcuts.isEmpty {
            print("[KeyboardShortcutManager] No planes with shortcuts — nothing to monitor.")
            return
        }

        let axTrusted = AXIsProcessTrusted()
        let inputMonitoring = InputMonitoringAccess.isGranted
        print("[KeyboardShortcutManager] Permissions -> Accessibility: \(axTrusted) | Input Monitoring: \(inputMonitoring)")

        if !axTrusted {
            print("[KeyboardShortcutManager] Requesting Accessibility permission...")
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
        }

        if !inputMonitoring {
            print("[KeyboardShortcutManager] Requesting Input Monitoring permission...")
            let granted = InputMonitoringAccess.request()
            print("[KeyboardShortcutManager] Input Monitoring request result: \(granted) (granted now: \(InputMonitoringAccess.isGranted))")
        }

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

        if let eventTap {
            runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
            if let runLoopSource {
                CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            }
            CGEvent.tapEnable(tap: eventTap, enable: true)
            print("[KeyboardShortcutManager] Session event tap CREATED & enabled (Input Monitoring present: \(InputMonitoringAccess.isGranted)). Waiting for key events...")
        } else {
            print("[KeyboardShortcutManager] FAILED to create session event tap — Input Monitoring permission missing or denied.")
        }

        installFallbackMonitors()
    }

    private func installFallbackMonitors() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            print("[KeyboardShortcutManager] [GLOBAL MONITOR] keyDown keyCode=\(event.keyCode) chars=\(event.charactersIgnoringModifiers ?? "nil") flags=0x\(String(event.modifierFlags.rawValue, radix: 16))")
            Task { @MainActor in
                self?.handleNSEvent(event, swallow: false)
            }
        }
        if globalMonitor == nil {
            print("[KeyboardShortcutManager] GLOBAL MONITOR failed to install — requires Accessibility permission.")
        } else {
            print("[KeyboardShortcutManager] GLOBAL MONITOR installed.")
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            print("[KeyboardShortcutManager] [LOCAL MONITOR] keyDown keyCode=\(event.keyCode) chars=\(event.charactersIgnoringModifiers ?? "nil") flags=0x\(String(event.modifierFlags.rawValue, radix: 16))")
            return self.handleNSEvent(event, swallow: true) ? nil : event
        }
        if localMonitor == nil {
            print("[KeyboardShortcutManager] LOCAL MONITOR failed to install.")
        } else {
            print("[KeyboardShortcutManager] LOCAL MONITOR installed.")
        }
    }

    func ensureEventTapEnabled(forceRebuild: Bool = false) {
        if forceRebuild || eventTap == nil {
            setupMonitor()
            return
        }
        if let eventTap, !CGEvent.tapIsEnabled(tap: eventTap) {
            CGEvent.tapEnable(tap: eventTap, enable: true)
            if !CGEvent.tapIsEnabled(tap: eventTap) {
                setupMonitor()
            }
        }
    }

    func stopMonitoring() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
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

    nonisolated func handle(event: CGEvent, type: CGEventType) -> Unmanaged<CGEvent>? {
        guard type == .keyDown else { return Unmanaged.passRetained(event) }

        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))

        guard let nsEvent = NSEvent(cgEvent: event) else {
            return Unmanaged.passRetained(event)
        }

        let flags = nsEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)

        guard let keyString = KeyCodeTranslator.shared.string(for: keyCode, from: nsEvent) else {
            print("[KeyboardShortcutManager] [TAP] keyDown keyCode=\(keyCode) flags=0x\(String(flags.rawValue, radix: 16)) (untranslatable key)")
            return Unmanaged.passRetained(event)
        }

        print("[KeyboardShortcutManager] [TAP] keyDown keyCode=\(keyCode) key=\(keyString) flags=0x\(String(flags.rawValue, radix: 16))")

        let currentShortcut = KeyboardShortcut(key: keyString, modifiers: flags)

        var planeToActivate: Plane?
        cacheLock.withLock {
            planeToActivate = registeredShortcuts[currentShortcut]
        }

        guard let plane = planeToActivate else { return Unmanaged.passRetained(event) }

        let now = Date()
        guard now.timeIntervalSince(lastTriggerAt) > 0.3 else { return nil }
        lastTriggerAt = now

        print("[KeyboardShortcutManager] MATCH '\(plane.name)' via event tap. Consuming event.")
        Task { @MainActor in
            WindowArrangementManager.shared.activate(plane: plane)
        }
        return nil
    }

    @discardableResult
    private func handleNSEvent(_ event: NSEvent, swallow: Bool) -> Bool {
        guard event.type == .keyDown, !event.isARepeat else { return false }

        let keyCode = UInt16(event.keyCode)
        guard let keyString = KeyCodeTranslator.shared.string(for: keyCode, from: event) else {
            return false
        }

        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let currentShortcut = KeyboardShortcut(key: keyString, modifiers: modifiers)

        var planeToActivate: Plane?
        cacheLock.withLock {
            planeToActivate = registeredShortcuts[currentShortcut]
        }

        guard let plane = planeToActivate else { return false }

        let now = Date()
        guard now.timeIntervalSince(lastTriggerAt) > 0.3 else { return swallow }
        lastTriggerAt = now

        print("[KeyboardShortcutManager] MATCH '\(plane.name)' via \(swallow ? "local" : "global") monitor. Swallow=\(swallow)")
        Task { @MainActor in
            WindowArrangementManager.shared.activate(plane: plane)
        }
        return swallow
    }
}