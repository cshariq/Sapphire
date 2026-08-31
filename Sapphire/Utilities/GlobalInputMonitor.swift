//
//  GlobalInputMonitor.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-25
//

import Cocoa

@MainActor
final class GlobalInputMonitor {

    static let shared = GlobalInputMonitor()

    private var leftMouseDownHandlers: [UUID: () -> Void] = [:]
    private var leftMouseUpHandlers: [UUID: () -> Void] = [:]

    private var leftMouseDownMonitor: Any?
    private var leftMouseUpMonitor: Any?

    private init() {}

    // MARK: - Subscription

    @discardableResult
    func onLeftMouseDown(_ handler: @escaping () -> Void) -> UUID {
        let token = UUID()
        leftMouseDownHandlers[token] = handler
        installLeftMouseDownMonitorIfNeeded()
        return token
    }

    @discardableResult
    func onLeftMouseUp(_ handler: @escaping () -> Void) -> UUID {
        let token = UUID()
        leftMouseUpHandlers[token] = handler
        installLeftMouseUpMonitorIfNeeded()
        return token
    }

    func remove(_ token: UUID) {
        if leftMouseDownHandlers.removeValue(forKey: token) != nil {
            refreshLeftMouseDownMonitor()
        } else if leftMouseUpHandlers.removeValue(forKey: token) != nil {
            refreshLeftMouseUpMonitor()
        }
    }

    // MARK: - Monitor lifecycle

    private func installLeftMouseDownMonitorIfNeeded() {
        guard leftMouseDownMonitor == nil else { return }
        leftMouseDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            Task { @MainActor in
                guard let handlers = self?.leftMouseDownHandlers.values else { return }
                for handler in handlers { handler() }
            }
        }
    }

    private func installLeftMouseUpMonitorIfNeeded() {
        guard leftMouseUpMonitor == nil else { return }
        leftMouseUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in
            Task { @MainActor in
                guard let handlers = self?.leftMouseUpHandlers.values else { return }
                for handler in handlers { handler() }
            }
        }
    }

    private func refreshLeftMouseDownMonitor() {
        if leftMouseDownHandlers.isEmpty, let monitor = leftMouseDownMonitor {
            NSEvent.removeMonitor(monitor)
            leftMouseDownMonitor = nil
        }
    }

    private func refreshLeftMouseUpMonitor() {
        if leftMouseUpHandlers.isEmpty, let monitor = leftMouseUpMonitor {
            NSEvent.removeMonitor(monitor)
            leftMouseUpMonitor = nil
        }
    }
}