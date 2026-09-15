//
//  EventMonitorHub.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-14

import AppKit

@MainActor
final class EventMonitorHub {
    static let shared = EventMonitorHub()

    private var monitor: Any?
    private var installedMask: NSEvent.EventTypeMask = []
    private var handlers: [NSEvent.EventType: [UUID: (NSEvent) -> Void]] = [:]

    private init() {}

    private static let pointerMotionTypes: Set<NSEvent.EventType> = [
        .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
    ]

    private static func rejectPointerMotion(_ eventType: NSEvent.EventType) -> Bool {
        guard pointerMotionTypes.contains(eventType) else { return false }
        assertionFailure("EventMonitorHub: global pointer-motion monitors are not allowed (\(eventType))")
        return true
    }

    @discardableResult
    func register(for eventType: NSEvent.EventType, handler: @escaping (NSEvent) -> Void) -> UUID {
        let token = UUID()
        guard !Self.rejectPointerMotion(eventType) else { return token }
        if handlers[eventType] == nil {
            handlers[eventType] = [:]
        }
        handlers[eventType]?[token] = handler
        synchronizeMonitor()
        return token
    }

    @discardableResult
    func register(
        for eventTypes: [NSEvent.EventType],
        handler: @escaping (NSEvent) -> Void
    ) -> [NSEvent.EventType: UUID] {
        var tokens: [NSEvent.EventType: UUID] = [:]
        for eventType in Set(eventTypes) where !Self.rejectPointerMotion(eventType) {
            let token = UUID()
            handlers[eventType, default: [:]][token] = handler
            tokens[eventType] = token
        }
        synchronizeMonitor()
        return tokens
    }

    func unregister(token: UUID, for eventType: NSEvent.EventType) {
        handlers[eventType]?.removeValue(forKey: token)

        if handlers[eventType]?.isEmpty ?? false {
            handlers.removeValue(forKey: eventType)
        }
        synchronizeMonitor()
    }

    func unregister(tokens: [NSEvent.EventType: UUID]) {
        for (eventType, token) in tokens {
            handlers[eventType]?.removeValue(forKey: token)
            if handlers[eventType]?.isEmpty == true {
                handlers.removeValue(forKey: eventType)
            }
        }
        synchronizeMonitor()
    }

    func setRegistered(
        _ isActive: Bool,
        tokens: inout [NSEvent.EventType: UUID],
        for eventTypes: [NSEvent.EventType],
        handler: @escaping (NSEvent) -> Void
    ) {
        if isActive {
            if tokens.isEmpty { tokens = register(for: eventTypes, handler: handler) }
        } else if !tokens.isEmpty {
            unregister(tokens: tokens)
            tokens.removeAll()
        }
    }

    private func synchronizeMonitor() {
        let wantedMask = handlers.keys.reduce(into: NSEvent.EventTypeMask()) { mask, eventType in
            mask.insert(NSEvent.EventTypeMask(rawValue: 1 << eventType.rawValue))
        }
        guard wantedMask != installedMask || (monitor == nil && !wantedMask.isEmpty) else { return }

        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        installedMask = []
        guard !wantedMask.isEmpty else { return }

        monitor = NSEvent.addGlobalMonitorForEvents(matching: wantedMask) { [weak self] event in
            MainActor.assumeIsolated {
                self?.dispatch(event)
            }
        }
        if monitor != nil { installedMask = wantedMask }
    }

    private func dispatch(_ event: NSEvent) {
        let handlers = handlers[event.type] ?? [:]
        for (_, handler) in handlers {
            handler(event)
        }
    }
}