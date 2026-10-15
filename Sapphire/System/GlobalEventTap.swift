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

struct EventTapDispatchEntry {
    let id: UInt64
    let name: String
    let mask: CGEventMask
    let priority: Int
    let body: GlobalEventTap.Body
}

enum EventTapDispatchPlan {
    static func ordered(_ entries: [EventTapDispatchEntry]) -> [EventTapDispatchEntry] {
        entries.sorted { lhs, rhs in
            lhs.priority != rhs.priority ? lhs.priority < rhs.priority : lhs.id < rhs.id
        }
    }

    static func combinedMask(_ entries: [EventTapDispatchEntry]) -> CGEventMask {
        entries.reduce(CGEventMask(0)) { $0 | $1.mask }
    }

    static func run(
        _ entries: [EventTapDispatchEntry],
        type: CGEventType,
        event: CGEvent,
        clock: () -> UInt64 = { DispatchTime.now().uptimeNanoseconds },
        finished: (EventTapDispatchEntry, _ elapsed: UInt64, _ finishedAt: UInt64) -> Void = { _, _, _ in }
    ) -> EventTapDecision {
        guard type.rawValue < 64 else { return .pass }
        let typeBit = CGEventMask(1) << CGEventMask(type.rawValue)
        for entry in entries where entry.mask & typeBit != 0 {
            let startedAt = clock()
            let decision = entry.body(type, event)
            let finishedAt = clock()
            finished(entry, finishedAt &- startedAt, finishedAt)
            if case .pass = decision { continue }
            return decision
        }
        return .pass
    }
}

final class GlobalEventTap: @unchecked Sendable {
    static let shared = GlobalEventTap()

    private static let handlerDeadlineNanoseconds: UInt64 = 100_000_000
    private static let slowHandlerCorrelationWindowNanoseconds: UInt64 = 2_000_000_000
    private static let timeoutStrikeResetNanoseconds: UInt64 = 10_000_000_000
    private static let initialRecoveryDelay: TimeInterval = 0.25
    private static let maximumRecoveryDelay: TimeInterval = 4.0
    private static let initialQuarantineDelay: TimeInterval = 2.0
    private static let maximumQuarantineDelay: TimeInterval = 30.0
    private static let quarantineStrikeResetNanoseconds: UInt64 = 60_000_000_000
    private static let maskShrinkDelayNanoseconds: UInt64 = 3_000_000_000

    // MARK: - Handler registry

    typealias Body = (CGEventType, CGEvent) -> EventTapDecision
    typealias Reset = () -> Void

    struct Token: Hashable {
        fileprivate let id: UInt64
    }

    private struct Registration {
        let entry: EventTapDispatchEntry
        var isEnabled: Bool
        let reset: Reset?
        var isQuarantined = false
        var quarantineStrikes = 0
        var lastQuarantineAt: UInt64?
        var quarantineGeneration: UInt64 = 0
    }

    private struct DispatchState {
        var entries: [EventTapDispatchEntry] = []
        var tapGeneration: UInt64 = 0
    }

    private let dispatchState = OSAllocatedUnfairLock(uncheckedState: DispatchState())

    private let reconcileLock = NSLock()

    private let lock = NSLock()
    private var registrations: [Registration] = []
    private var nextID: UInt64 = 1

    // MARK: - Tap state (all mutations under `lock`)

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var installedMask: CGEventMask = 0
    private var installedGeneration: UInt64 = 0
    private var lastTapGeneration: UInt64 = 0
    private var isSuspended = false
    private var lastSlowHandler: (name: String, elapsedMilliseconds: Double, finishedAt: UInt64)?
    private var lastTimeoutAt: UInt64?
    private var consecutiveTimeouts = 0
    private var recoveryGeneration: UInt64 = 0
    private var isRecoveryPending = false
    private var maskShrinkDeadline: UInt64?

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
        reset: Reset? = nil,
        body: @escaping Body
    ) -> Token {
        lock.lock()
        let id = nextID
        nextID += 1
        let entry = EventTapDispatchEntry(id: id, name: name, mask: mask, priority: priority, body: body)
        registrations.append(Registration(entry: entry, isEnabled: enabled, reset: reset))
        lock.unlock()
        reconcile()
        return Token(id: id)
    }

    func unregister(_ token: Token) {
        lock.lock()
        let before = registrations.count
        registrations.removeAll { $0.entry.id == token.id }
        let changed = registrations.count != before
        lock.unlock()
        if changed { reconcile() }
    }

    func setEnabled(_ token: Token, _ enabled: Bool) {
        lock.lock()
        guard let index = registrations.firstIndex(where: { $0.entry.id == token.id }) else {
            lock.unlock()
            return
        }
        registrations[index].isQuarantined = false
        registrations[index].quarantineGeneration &+= 1
        guard registrations[index].isEnabled != enabled else {
            lock.unlock()
            return
        }
        registrations[index].isEnabled = enabled
        lock.unlock()
        reconcile()
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
        lock.unlock()
        reconcile()
        log.info("Accessibility revoked — shared event tap torn down.")
    }

    private func resume() {
        lock.lock()
        isSuspended = false
        lock.unlock()
        reconcile()
        log.info("Accessibility granted — shared event tap reinstalled.")
    }

    // MARK: - Tap construction

    private struct InstalledTap {
        let tap: CFMachPort
        let source: CFRunLoopSource
    }

    private func reconcile() {
        reconcileLock.lock()
        defer { reconcileLock.unlock() }

        lock.lock()
        let entries = publishEntriesLocked()
        let wanted = EventTapDispatchPlan.combinedMask(entries)

        if tap != nil, !isSuspended, !isRecoveryPending,
           installedMask != wanted, installedMask & wanted == wanted {
            let now = DispatchTime.now().uptimeNanoseconds
            guard let deadline = maskShrinkDeadline else {
                maskShrinkDeadline = now &+ Self.maskShrinkDelayNanoseconds
                lock.unlock()
                DispatchQueue.main.asyncAfter(
                    deadline: .now() + .nanoseconds(Int(Self.maskShrinkDelayNanoseconds))
                ) { [weak self] in self?.reconcile() }
                return
            }
            if now < deadline {
                lock.unlock()
                return
            }
        }
        maskShrinkDeadline = nil

        guard !isSuspended, wanted != 0, AccessibilityTrustMonitor.isCurrentlyTrusted() else {
            let old = detachTapLocked()
            lock.unlock()
            destroy(old)
            if old != nil { notifyResets() }
            return
        }

        if let tap, installedMask == wanted {
            if !isRecoveryPending, !CGEvent.tapIsEnabled(tap: tap) {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            lock.unlock()
            return
        }

        lastTapGeneration &+= 1
        if lastTapGeneration == 0 { lastTapGeneration = 1 }
        let generation = lastTapGeneration
        lock.unlock()

        guard let created = createTap(mask: wanted, generation: generation) else { return }

        lock.lock()
        let old = detachTapLocked()
        tap = created.tap
        source = created.source
        installedMask = wanted
        installedGeneration = generation
        dispatchState.withLockUnchecked { $0.tapGeneration = generation }
        let count = entries.count
        lock.unlock()

        destroy(old)
        if old != nil { notifyResets() }
        log.info("Shared event tap installed for \(count) handlers, mask \(wanted, format: .hex).")
    }

    private func publishEntriesLocked() -> [EventTapDispatchEntry] {
        let entries = EventTapDispatchPlan.ordered(registrations.filter(\.isEnabled).map(\.entry))
        dispatchState.withLockUnchecked { $0.entries = entries }
        return entries
    }

    private func notifyResets(only id: UInt64? = nil) {
        lock.lock()
        let resets = registrations
            .filter { id == nil || $0.entry.id == id }
            .compactMap(\.reset)
        lock.unlock()
        guard !resets.isEmpty else { return }
        recoveryQueue.async {
            for reset in resets { reset() }
        }
    }

    private func createTap(mask: CGEventMask, generation: UInt64) -> InstalledTap? {
        guard let newTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: globalEventTapCallback,
            userInfo: UnsafeMutableRawPointer(bitPattern: UInt(truncatingIfNeeded: generation))
        ) else {
            log.error("CGEvent.tapCreate failed — no events will be intercepted.")
            return nil
        }

        guard let newSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, newTap, 0) else {
            CFMachPortInvalidate(newTap)
            log.error("CFMachPortCreateRunLoopSource failed.")
            return nil
        }

        EventTapRunLoop.shared.add(newSource)
        CGEvent.tapEnable(tap: newTap, enable: true)
        return InstalledTap(tap: newTap, source: newSource)
    }

    private func detachTapLocked() -> InstalledTap? {
        recoveryGeneration &+= 1
        isRecoveryPending = false
        defer {
            source = nil
            tap = nil
            installedMask = 0
            installedGeneration = 0
        }
        guard let tap, let source else {
            if let tap { CFMachPortInvalidate(tap) }
            return nil
        }
        return InstalledTap(tap: tap, source: source)
    }

    private func destroy(_ installed: InstalledTap?) {
        guard let installed else { return }
        EventTapRunLoop.shared.remove(installed.source)
        CGEvent.tapEnable(tap: installed.tap, enable: false)
        CFMachPortInvalidate(installed.tap)
    }

    // MARK: - Event dispatch (runs on the EventTapRunLoop thread)

    fileprivate func dispatch(
        type: CGEventType,
        event: CGEvent,
        generation: UInt64
    ) -> Unmanaged<CGEvent>? {
        let state = dispatchState.withLockUnchecked { $0 }
        guard generation == state.tapGeneration else {
            return Unmanaged.passUnretained(event)
        }

        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            scheduleRecovery(after: type, generation: generation)
            return Unmanaged.passUnretained(event)
        }

        guard AccessibilityTrustMonitor.isCurrentlyTrusted() else {
            return Unmanaged.passUnretained(event)
        }

        let decision = EventTapDispatchPlan.run(state.entries, type: type, event: event, finished: { entry, elapsed, finishedAt in
            if elapsed >= Self.handlerDeadlineNanoseconds {
                scheduleSlowHandlerQuarantine(entry, elapsedNanoseconds: elapsed, finishedAt: finishedAt)
            }
        })

        switch decision {
        case .pass:
            return Unmanaged.passUnretained(event)
        case .swallow:
            return nil
        case .replace(let replacement):
            if replacement === event { return Unmanaged.passUnretained(event) }
            return Unmanaged.passRetained(replacement)
        }
    }

    private func scheduleRecovery(after type: CGEventType, generation: UInt64) {
        recoveryQueue.async { [weak self] in
            self?.prepareRecovery(after: type, generation: generation)
        }
    }

    private func prepareRecovery(after type: CGEventType, generation tapGeneration: UInt64) {
        let now = DispatchTime.now().uptimeNanoseconds

        lock.lock()
        guard tap != nil, installedGeneration == tapGeneration else {
            lock.unlock()
            return
        }
        guard !isSuspended,
              registrations.contains(where: \.isEnabled),
              AccessibilityTrustMonitor.isCurrentlyTrusted() else {
            lock.unlock()
            reconcile()
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

        notifyResets()

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
              registrations.contains(where: \.isEnabled),
              AccessibilityTrustMonitor.isCurrentlyTrusted() else {
            lock.unlock()
            reconcile()
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
        _ entry: EventTapDispatchEntry,
        elapsedNanoseconds: UInt64,
        finishedAt: UInt64
    ) {
        recoveryQueue.async { [weak self] in
            self?.quarantineSlowHandler(
                entry,
                elapsedNanoseconds: elapsedNanoseconds,
                finishedAt: finishedAt
            )
        }
    }

    private func quarantineSlowHandler(_ entry: EventTapDispatchEntry, elapsedNanoseconds: UInt64, finishedAt: UInt64) {
        let elapsedMilliseconds = Double(elapsedNanoseconds) / 1_000_000

        lock.lock()
        guard let index = registrations.firstIndex(where: { $0.entry.id == entry.id }),
              registrations[index].isEnabled else {
            lock.unlock()
            return
        }

        let now = DispatchTime.now().uptimeNanoseconds
        if let last = registrations[index].lastQuarantineAt, now &- last <= Self.quarantineStrikeResetNanoseconds {
            registrations[index].quarantineStrikes += 1
        } else {
            registrations[index].quarantineStrikes = 1
        }
        registrations[index].lastQuarantineAt = now
        let exponent = min(registrations[index].quarantineStrikes - 1, 4)
        let delay = min(Self.initialQuarantineDelay * pow(2.0, Double(exponent)), Self.maximumQuarantineDelay)

        registrations[index].isEnabled = false
        registrations[index].isQuarantined = true
        registrations[index].quarantineGeneration &+= 1
        let generation = registrations[index].quarantineGeneration
        _ = publishEntriesLocked()
        lastSlowHandler = (entry.name, elapsedMilliseconds, finishedAt)
        lock.unlock()

        log.fault(
            "Event-tap handler '\(entry.name, privacy: .public)' exceeded its callback budget (\(elapsedMilliseconds, format: .fixed(precision: 1)) ms) and was disabled; re-enabling in \(delay, format: .fixed(precision: 1)) s."
        )
        notifyResets(only: entry.id)

        recoveryQueue.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.releaseQuarantine(id: entry.id, generation: generation)
        }
    }

    private func releaseQuarantine(id: UInt64, generation: UInt64) {
        lock.lock()
        guard let index = registrations.firstIndex(where: { $0.entry.id == id }),
              registrations[index].isQuarantined,
              registrations[index].quarantineGeneration == generation else {
            lock.unlock()
            return
        }
        registrations[index].isQuarantined = false
        registrations[index].isEnabled = true
        let name = registrations[index].entry.name
        lock.unlock()
        reconcile()
        log.info("Event-tap handler '\(name, privacy: .public)' re-enabled after quarantine.")
    }
}

private let globalEventTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
    let generation = UInt64(UInt(bitPattern: userInfo))
    return GlobalEventTap.shared.dispatch(type: type, event: event, generation: generation)
}