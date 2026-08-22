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

    private var isAccessibilitySuspended = false

    private init() {
        registerTrustAwareness()

        SettingsModel.shared.$settings
            .debounce(for: .seconds(0.5), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.setupMonitor()
            }
            .store(in: &cancellables)
    }

    private func registerTrustAwareness() {
        AccessibilityTrustMonitor.shared.register(name: "KeyboardShortcutManager") { [weak self] in
            self?.isAccessibilitySuspended = true
            self?.stopMonitoring()
        } reinstall: { [weak self] in
            self?.isAccessibilitySuspended = false
            self?.setupMonitor()
        }
    }

    func setupMonitor() {
        guard !isAccessibilitySuspended else { return }
        stopMonitoring()

        let planesWithShortcuts = SettingsModel.shared.settings.planes.filter { $0.shortcut != nil }
        for plane in planesWithShortcuts {
            if let shortcut = plane.shortcut {
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
            return
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
        }

        installFallbackMonitors()
    }

    private func installFallbackMonitors() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            Task { @MainActor in
                self?.handleNSEvent(event, swallow: false)
            }
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            print("[KeyboardShortcutManager] [LOCAL MONITOR] keyDown keyCode=\(event.keyCode) chars=\(event.charactersIgnoringModifiers ?? "nil") flags=0x\(String(event.modifierFlags.rawValue, radix: 16))")
            return self.handleNSEvent(event, swallow: true) ? nil : event
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
            CFMachPortInvalidate(tap)
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
            return Unmanaged.passRetained(event)
        }

        let currentShortcut = KeyboardShortcut(key: keyString, modifiers: flags)

        var planeToActivate: Plane?
        cacheLock.withLock {
            planeToActivate = registeredShortcuts[currentShortcut]
        }

        guard let plane = planeToActivate else { return Unmanaged.passRetained(event) }

        let now = Date()
        guard now.timeIntervalSince(lastTriggerAt) > 0.3 else { return nil }
        lastTriggerAt = now

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

        Task { @MainActor in
            WindowArrangementManager.shared.activate(plane: plane)
        }
        return swallow
    }
}