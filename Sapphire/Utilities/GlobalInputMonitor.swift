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

    private var leftMouseDownToken: UUID?
    private var leftMouseUpToken: UUID?

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
        guard leftMouseDownToken == nil else { return }
        leftMouseDownToken = EventMonitorHub.shared.register(for: .leftMouseDown) { [weak self] _ in
            guard let self else { return }
            let handlers = Array(self.leftMouseDownHandlers.values)
            for handler in handlers { handler() }
        }
    }

    private func installLeftMouseUpMonitorIfNeeded() {
        guard leftMouseUpToken == nil else { return }
        leftMouseUpToken = EventMonitorHub.shared.register(for: .leftMouseUp) { [weak self] _ in
            guard let self else { return }
            let handlers = Array(self.leftMouseUpHandlers.values)
            for handler in handlers { handler() }
        }
    }

    private func refreshLeftMouseDownMonitor() {
        if leftMouseDownHandlers.isEmpty, let token = leftMouseDownToken {
            EventMonitorHub.shared.unregister(token: token, for: .leftMouseDown)
            leftMouseDownToken = nil
        }
    }

    private func refreshLeftMouseUpMonitor() {
        if leftMouseUpHandlers.isEmpty, let token = leftMouseUpToken {
            EventMonitorHub.shared.unregister(token: token, for: .leftMouseUp)
            leftMouseUpToken = nil
        }
    }
}