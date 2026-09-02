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
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        guard AccessibilityTrustMonitor.isCurrentlyTrusted() else {
            if let refcon = refcon {
                let manager = Unmanaged<KeyboardShortcutManager>.fromOpaque(refcon).takeUnretainedValue()
                Task { @MainActor in
                    manager.stopMonitoring()
                }
            }
            return Unmanaged.passRetained(event)
        }
        if let refcon = refcon {
            let manager = Unmanaged<KeyboardShortcutManager>.fromOpaque(refcon).takeUnretainedValue()
            Task { @MainActor in
                manager.ensureEventTapEnabled(forceRebuild: true)
            }
        }
        return Unmanaged.passRetained(event)
    }

    guard AccessibilityTrustMonitor.isCurrentlyTrusted() else {
        return Unmanaged.passRetained(event)
    }

    guard let refcon = refcon else { return Unmanaged.passRetained(event) }
    let manager = Unmanaged<KeyboardShortcutManager>.fromOpaque(refcon).takeUnretainedValue()
    return manager.handle(event: event, type: type)
}

class KeyboardShortcutManager {
    static let shared = KeyboardShortcutManager()

    private enum ShortcutAction {
        case plane(Plane)
        case snapZone(SnapZoneShortcut)
    }

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var cancellables = Set<AnyCancellable>()
    private var notificationObservers: [NSObjectProtocol] = []

    private var registeredShortcuts: [KeyboardShortcut: ShortcutAction] = [:]
    private let cacheLock = NSLock()
    private let triggerLock = NSLock()
    private var lastTriggerAt = Date.distantPast

    private var isAccessibilitySuspended = false
    private var isShortcutRecording = false

    private init() {
        registerTrustAwareness()

        notificationObservers = [
            NotificationCenter.default.addObserver(
                forName: .sapphireShortcutRecordingDidStart,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.isShortcutRecording = true
                self?.stopMonitoring()
            },
            NotificationCenter.default.addObserver(
                forName: .sapphireShortcutRecordingDidEnd,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.isShortcutRecording = false
                self?.setupMonitor()
            }
        ]

        SettingsModel.shared.$settings
            .debounce(for: .seconds(0.5), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.setupMonitor()
            }
            .store(in: &cancellables)
    }

    deinit {
        notificationObservers.forEach(NotificationCenter.default.removeObserver)
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
        guard !isAccessibilitySuspended, !isShortcutRecording else { return }
        stopMonitoring()

        let planesWithShortcuts = SettingsModel.shared.settings.planes.filter { $0.shortcut != nil }
        let snapZoneShortcuts = SettingsModel.shared.settings.snapZoneShortcuts

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

        if eventTap == nil {
            installFallbackMonitors()
        }
    }

    private func installFallbackMonitors() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            Task { @MainActor in
                self?.handleNSEvent(event, swallow: false)
            }
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
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
        guard event.getIntegerValueField(.eventSourceUserData) != SapphireSyntheticEventMarker.plainTextPaste else {
            return Unmanaged.passRetained(event)
        }

        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))

        guard let nsEvent = NSEvent(cgEvent: event) else {
            return Unmanaged.passRetained(event)
        }

        let flags = nsEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)

        guard let keyString = KeyCodeTranslator.shared.string(for: keyCode, from: nsEvent) else {
            return Unmanaged.passRetained(event)
        }

        let currentShortcut = KeyboardShortcut(key: keyString, modifiers: flags)

        guard let action = action(for: currentShortcut) else { return Unmanaged.passRetained(event) }
        guard shouldTrigger() else { return nil }

        perform(action)
        return nil
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

    private func action(for shortcut: KeyboardShortcut) -> ShortcutAction? {
        cacheLock.withLock {
            registeredShortcuts[shortcut]
        }
    }

    private func shouldTrigger() -> Bool {
        triggerLock.withLock {
            let now = Date()
            guard now.timeIntervalSince(lastTriggerAt) > 0.3 else { return false }
            lastTriggerAt = now
            return true
        }
    }

    private func perform(_ action: ShortcutAction) {
        Task { @MainActor in
            switch action {
            case .plane(let plane):
                WindowArrangementManager.shared.activate(plane: plane)
            case .snapZone(let mapping):
                SnappingManager.snap(layoutID: mapping.layoutID, zoneID: mapping.zoneID)
            }
        }
    }
}