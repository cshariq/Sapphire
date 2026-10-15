//
//  TrackpadGestureMonitor.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-08-20.
//

import Foundation
import AppKit
import SwiftUI
import Combine
import QuartzCore

final class TrackpadGestureHandler {
    static let shared = TrackpadGestureHandler()

    typealias ClientID = ObjectIdentifier

    private struct Client {
        var displayID: CGDirectDisplayID?
        var onSwipe: ((CGFloat, CGFloat) -> Void)?
        var onTwoFingerTap: (() -> Void)?
        var onPinch: ((CGFloat) -> Void)?
        var activatedAt: TimeInterval?
    }

    private var scrollEventMonitor: Any?
    private var rightClickMonitor: Any?
    private var magnifyEventMonitor: Any?
    private var hasProcessedCurrentGesture = false

    private var lastGestureTime: TimeInterval = 0

    private var clients: [ClientID: Client] = [:]
    private var activeOrder: [ClientID] = []

    private let gestureDebounceInterval: TimeInterval = 0.7
    private let initialStabilizationPeriod: TimeInterval = 0.3

    private init() {}

    // MARK: Clients

    func register(
        _ id: ClientID,
        displayID: CGDirectDisplayID?,
        onSwipe: ((CGFloat, CGFloat) -> Void)?,
        onTwoFingerTap: (() -> Void)?,
        onPinch: ((CGFloat) -> Void)? = nil
    ) {
        var client = clients[id] ?? Client()
        client.displayID = displayID
        client.onSwipe = onSwipe
        client.onTwoFingerTap = onTwoFingerTap
        client.onPinch = onPinch
        clients[id] = client
    }

    func unregister(_ id: ClientID) {
        clients[id] = nil
        activeOrder.removeAll { $0 == id }
        syncMonitors()
    }

    func setActive(_ isActive: Bool, for id: ClientID) {
        guard var client = clients[id] else { return }
        if isActive {
            guard client.activatedAt == nil else { return }
            client.activatedAt = CACurrentMediaTime()
            clients[id] = client
            activeOrder.append(id)
            if activeOrder.count == 1 { hasProcessedCurrentGesture = false }
        } else {
            guard client.activatedAt != nil else { return }
            client.activatedAt = nil
            clients[id] = client
            activeOrder.removeAll { $0 == id }
        }
        syncMonitors()
    }

    private func routedClient() -> Client? {
        let active = activeOrder.compactMap { id in clients[id].map { (id: id, displayID: $0.displayID) } }
        let pointerDisplay: CGDirectDisplayID? = Thread.isMainThread
            ? MainActor.assumeIsolated { NotchDisplayTargeting.pointerDisplayID }
            : nil
        guard let id = TrackpadGestureRouting.route(active: active, pointerDisplay: pointerDisplay) else { return nil }
        return clients[id]
    }

    private func isStabilizing(_ client: Client, now: TimeInterval) -> Bool {
        guard let activatedAt = client.activatedAt else { return true }
        return now - activatedAt < initialStabilizationPeriod
    }

    // MARK: Monitors

    private func syncMonitors() {
        if activeOrder.isEmpty {
            removeMonitors()
        } else {
            installMonitors()
        }
    }

    private func installMonitors() {
        guard scrollEventMonitor == nil else { return }
        hasProcessedCurrentGesture = false

        scrollEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel]) { [weak self] event in
            guard let self = self else { return event }

            if event.type != .scrollWheel ||
               event.modifierFlags.contains(.command) ||
               event.modifierFlags.contains(.option) ||
               event.modifierFlags.contains(.control) {
                return event
            }

            let now = CACurrentMediaTime()
            guard let client = self.routedClient(), !self.isStabilizing(client, now: now) else {
                return event
            }

            if event.phase == .began || event.momentumPhase == .began {
                self.hasProcessedCurrentGesture = false
            }

            if !self.hasProcessedCurrentGesture &&
               (now - self.lastGestureTime > self.gestureDebounceInterval) {

                if abs(event.scrollingDeltaX) > 10 || abs(event.scrollingDeltaY) > 10 {
                    self.hasProcessedCurrentGesture = true
                    self.lastGestureTime = now

                    let dx = event.scrollingDeltaX
                    let dy = event.scrollingDeltaY

                    if let onSwipe = client.onSwipe {
                        DispatchQueue.main.async { onSwipe(dx, dy) }
                    }

                    if abs(dx) > abs(dy) {
                        return event
                    }
                    return nil
                }
            }

            if event.phase == .ended || event.phase == .cancelled ||
               event.momentumPhase == .ended || event.momentumPhase == .cancelled {
                self.hasProcessedCurrentGesture = false
            }

            return event
        }

        rightClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown]) { [weak self] event in
            guard let self = self else { return event }

            let now = CACurrentMediaTime()
            guard let client = self.routedClient(), !self.isStabilizing(client, now: now),
                  let onTwoFingerTap = client.onTwoFingerTap else {
                return event
            }

            if event.clickCount == 1 && !event.modifierFlags.contains(.control) {
                if now - self.lastGestureTime > self.gestureDebounceInterval {
                    self.lastGestureTime = now

                    DispatchQueue.main.async { onTwoFingerTap() }

                    return nil
                }
            }
            return event
        }

        magnifyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.magnify]) { [weak self] event in
            guard let self = self else { return event }

            let now = CACurrentMediaTime()
            guard let client = self.routedClient(), !self.isStabilizing(client, now: now),
                  let onPinch = client.onPinch else {
                return event
            }

            if event.phase == .began {
                self.hasProcessedCurrentGesture = false
            }

            if !self.hasProcessedCurrentGesture && (now - self.lastGestureTime > self.gestureDebounceInterval) {

                if abs(event.magnification) > 0.1 {
                    self.hasProcessedCurrentGesture = true
                    self.lastGestureTime = now

                    let mag = event.magnification
                    DispatchQueue.main.async { onPinch(mag) }

                    return nil
                }
            }

            if event.phase == .ended || event.phase == .cancelled {
                self.hasProcessedCurrentGesture = false
            }

            return event
        }
    }

    private func removeMonitors() {
        if let scrollMonitor = scrollEventMonitor {
            NSEvent.removeMonitor(scrollMonitor)
            scrollEventMonitor = nil
        }

        if let tapMonitor = rightClickMonitor {
            NSEvent.removeMonitor(tapMonitor)
            rightClickMonitor = nil
        }

        if let magnifyMonitor = magnifyEventMonitor {
            NSEvent.removeMonitor(magnifyMonitor)
            magnifyEventMonitor = nil
        }

        hasProcessedCurrentGesture = false
    }
}