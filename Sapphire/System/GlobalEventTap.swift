//
//  GlobalEventTap.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-13

import ApplicationServices
import CoreGraphics
import Foundation
import os

enum EventTapDecision {
    case pass
    case swallow
    case replace(CGEvent)
}

enum EventTapPriority {
    static let filter = 100
    static let shortcut = 200
    static let media = 300
    static let transform = 400
    static let observer = 900
}

final class GlobalEventTap: @unchecked Sendable {
    static let shared = GlobalEventTap()

    private static let handlerDeadlineNanoseconds: UInt64 = 100_000_000
    private static let slowHandlerCorrelationWindowNanoseconds: UInt64 = 2_000_000_000
    private static let timeoutStrikeResetNanoseconds: UInt64 = 10_000_000_000
    private static let initialRecoveryDelay: TimeInterval = 0.25
    private static let maximumRecoveryDelay: TimeInterval = 4.0

    // MARK: - Handler registry

    typealias Body = (CGEventType, CGEvent) -> EventTapDecision

    struct Token: Hashable {
        fileprivate let id: UInt64
    }

    private final class Handler {
        let id: UInt64
        let name: String
        let mask: CGEventMask
        let priority: Int
        var isEnabled: Bool
        let body: Body

        init(id: UInt64, name: String, mask: CGEventMask, priority: Int, isEnabled: Bool, body: @escaping Body) {
            self.id = id
            self.name = name
            self.mask = mask
            self.priority = priority
            self.isEnabled = isEnabled
            self.body = body
        }
    }

    private let lock = NSLock()
    private var handlers: [Handler] = []
    private var dispatchList: [Handler] = []
    private var nextID: UInt64 = 1

    // MARK: - Tap state (all mutations under `lock`)

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var installedMask: CGEventMask = 0
    private var isSuspended = false
    private var lastSlowHandler: (name: String, elapsedMilliseconds: Double, finishedAt: UInt64)?
    private var lastTimeoutAt: UInt64?
    private var consecutiveTimeouts = 0
    private var recoveryGeneration: UInt64 = 0
    private var isRecoveryPending = false

    private let recoveryQueue = DispatchQueue(
        label: "com.sapphire.event-tap-recovery",
        qos: .userInitiated
    )

    private let log = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.cshariq.sapphire",
        category: "GlobalEventTap"
    )

    private init() {}

    // MARK: - Lifecycle

    @MainActor
    func installTrustAwareness() {
        AccessibilityTrustMonitor.shared.register(name: "GlobalEventTap") { [weak self] in
            self?.suspend()
        } reinstall: { [weak self] in
            self?.resume()
        }
    }

    @discardableResult
    func register(
        name: String,
        mask: CGEventMask,
        priority: Int,
        enabled: Bool = true,
        body: @escaping Body
    ) -> Token {
        lock.lock()
        let id = nextID
        nextID += 1
        handlers.append(Handler(id: id, name: name, mask: mask, priority: priority, isEnabled: enabled, body: body))
        rebuildLocked()
        lock.unlock()
        return Token(id: id)
    }

    func unregister(_ token: Token) {
        lock.lock()
        handlers.removeAll { $0.id == token.id }
        rebuildLocked()
        lock.unlock()
    }

    func setEnabled(_ token: Token, _ enabled: Bool) {
        lock.lock()
        guard let handler = handlers.first(where: { $0.id == token.id }), handler.isEnabled != enabled else {
            lock.unlock()
            return
        }
        handler.isEnabled = enabled
        rebuildLocked()
        lock.unlock()
    }

    var isActive: Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let tap else { return false }
        return CGEvent.tapIsEnabled(tap: tap)
    }

    private func suspend() {
        lock.lock()
        isSuspended = true
        teardownTapLocked()
        lock.unlock()
        log.info("Accessibility revoked — shared event tap torn down.")
    }

    private func resume() {
        lock.lock()
        isSuspended = false
        rebuildLocked()
        lock.unlock()
        log.info("Accessibility granted — shared event tap reinstalled.")
    }

    // MARK: - Tap construction (caller holds `lock`)

    private func rebuildLocked() {
        dispatchList = handlers
            .filter(\.isEnabled)
            .sorted { $0.priority < $1.priority }

        let wanted = dispatchList.reduce(CGEventMask(0)) { $0 | $1.mask }

        guard !isSuspended, wanted != 0, AccessibilityTrustMonitor.isCurrentlyTrusted() else {
            teardownTapLocked()
            return
        }

        if let tap, installedMask == wanted {
            if !isRecoveryPending, !CGEvent.tapIsEnabled(tap: tap) {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return
        }

        teardownTapLocked()

        guard let newTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: wanted,
            callback: globalEventTapCallback,
            userInfo: nil
        ) else {
            log.error("CGEvent.tapCreate failed — no events will be intercepted.")
            return
        }

        guard let newSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, newTap, 0) else {
            CFMachPortInvalidate(newTap)
            log.error("CFMachPortCreateRunLoopSource failed.")
            return
        }

        EventTapRunLoop.shared.add(newSource)
        CGEvent.tapEnable(tap: newTap, enable: true)

        tap = newTap
        source = newSource
        installedMask = wanted
        log.info("Shared event tap installed for \(self.dispatchList.count) handlers, mask \(wanted, format: .hex).")
    }

    private func teardownTapLocked() {
        recoveryGeneration &+= 1
        isRecoveryPending = false
        if let source {
            EventTapRunLoop.shared.remove(source)
        }
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        source = nil
        tap = nil
        installedMask = 0
    }

    // MARK: - Event dispatch (runs on the EventTapRunLoop thread)

    fileprivate func dispatch(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            scheduleRecovery(after: type)
            return Unmanaged.passUnretained(event)
        }

        guard AccessibilityTrustMonitor.isCurrentlyTrusted() else {
            return Unmanaged.passUnretained(event)
        }

        guard lock.try() else {
            return Unmanaged.passUnretained(event)
        }
        let list = dispatchList
        lock.unlock()

        let typeBit = CGEventMask(1) << CGEventMask(type.rawValue)
        for handler in list where handler.mask & typeBit != 0 {
            let startedAt = DispatchTime.now().uptimeNanoseconds
            let decision = handler.body(type, event)
            let finishedAt = DispatchTime.now().uptimeNanoseconds
            let elapsed = finishedAt &- startedAt
            if elapsed >= Self.handlerDeadlineNanoseconds {
                scheduleSlowHandlerQuarantine(
                    handler,
                    elapsedNanoseconds: elapsed,
                    finishedAt: finishedAt
                )
            }

            switch decision {
            case .pass:
                continue
            case .swallow:
                return nil
            case .replace(let replacement):
                return Unmanaged.passUnretained(replacement)
            }
        }
        return Unmanaged.passUnretained(event)
    }

    private func scheduleRecovery(after type: CGEventType) {
        recoveryQueue.async { [weak self] in
            self?.prepareRecovery(after: type)
        }
    }

    private func prepareRecovery(after type: CGEventType) {
        let now = DispatchTime.now().uptimeNanoseconds

        lock.lock()
        guard tap != nil,
              !isSuspended,
              !dispatchList.isEmpty,
              AccessibilityTrustMonitor.isCurrentlyTrusted() else {
            teardownTapLocked()
            lock.unlock()
            return
        }

        let recentSlowHandler = lastSlowHandler.flatMap { slow -> (String, Double)? in
            guard now &- slow.finishedAt <= Self.slowHandlerCorrelationWindowNanoseconds else { return nil }
            return (slow.name, slow.elapsedMilliseconds)
        }

        let delay: TimeInterval
        if type == .tapDisabledByTimeout {
            if let lastTimeoutAt, now &- lastTimeoutAt <= Self.timeoutStrikeResetNanoseconds {
                consecutiveTimeouts += 1
            } else {
                consecutiveTimeouts = 1
            }
            lastTimeoutAt = now
            let exponent = min(consecutiveTimeouts - 1, 4)
            delay = min(
                Self.initialRecoveryDelay * pow(2.0, Double(exponent)),
                Self.maximumRecoveryDelay
            )
        } else {
            delay = Self.initialRecoveryDelay
        }

        recoveryGeneration &+= 1
        let generation = recoveryGeneration
        isRecoveryPending = true
        lock.unlock()

        if let recentSlowHandler, type == .tapDisabledByTimeout {
            log.error(
                "Shared event tap timed out after handler '\(recentSlowHandler.0, privacy: .public)' took \(recentSlowHandler.1, format: .fixed(precision: 1)) ms; the handler was disabled. Recovery in \(delay, format: .fixed(precision: 2)) s."
            )
        } else {
            log.error(
                "Shared event tap was disabled by the system (\(type == .tapDisabledByTimeout ? "timeout" : "user input")); recovery in \(delay, format: .fixed(precision: 2)) s."
            )
        }

        recoveryQueue.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.recoverTap(generation: generation)
        }
    }

    private func recoverTap(generation: UInt64) {
        lock.lock()
        guard generation == recoveryGeneration, isRecoveryPending else {
            lock.unlock()
            return
        }
        isRecoveryPending = false
        guard let tap,
              !isSuspended,
              !dispatchList.isEmpty,
              AccessibilityTrustMonitor.isCurrentlyTrusted() else {
            teardownTapLocked()
            lock.unlock()
            return
        }
        CGEvent.tapEnable(tap: tap, enable: true)
        let recovered = CGEvent.tapIsEnabled(tap: tap)
        lock.unlock()

        if recovered {
            log.info("Shared event tap recovered after system disable.")
        } else {
            log.error("Shared event tap could not be re-enabled after system disable.")
        }
    }

    private func scheduleSlowHandlerQuarantine(
        _ handler: Handler,
        elapsedNanoseconds: UInt64,
        finishedAt: UInt64
    ) {
        recoveryQueue.async { [weak self] in
            self?.quarantineSlowHandler(
                handler,
                elapsedNanoseconds: elapsedNanoseconds,
                finishedAt: finishedAt
            )
        }
    }

    private func quarantineSlowHandler(_ handler: Handler, elapsedNanoseconds: UInt64, finishedAt: UInt64) {
        let elapsedMilliseconds = Double(elapsedNanoseconds) / 1_000_000

        lock.lock()
        guard let registeredHandler = handlers.first(where: { $0.id == handler.id }),
              registeredHandler === handler,
              registeredHandler.isEnabled else {
            lock.unlock()
            return
        }

        registeredHandler.isEnabled = false
        dispatchList.removeAll { $0.id == handler.id }
        lastSlowHandler = (handler.name, elapsedMilliseconds, finishedAt)
        lock.unlock()

        log.fault(
            "Event-tap handler '\(handler.name, privacy: .public)' exceeded its callback budget (\(elapsedMilliseconds, format: .fixed(precision: 1)) ms) and was disabled."
        )
    }
}

private let globalEventTapCallback: CGEventTapCallBack = { _, type, event, _ in
    GlobalEventTap.shared.dispatch(type: type, event: event)
}