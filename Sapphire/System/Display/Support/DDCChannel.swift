//
//  DDCChannel.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-10-07
//

import CoreGraphics
import Foundation
import os.log

protocol DDCTransport: AnyObject {
    func write(command: UInt8, value: UInt16) -> Bool
    func read(command: UInt8) -> (current: UInt16, maximum: UInt16)?
}

private final class Arm64DDCTransport: DDCTransport {
    private let service: IOAVService

    init(service: IOAVService) {
        self.service = service
    }

    func write(command: UInt8, value: UInt16) -> Bool {
        Arm64DDC.write(service: service, command: command, value: value)
    }

    func read(command: UInt8) -> (current: UInt16, maximum: UInt16)? {
        guard let reply = Arm64DDC.read(service: service, command: command) else { return nil }
        return (reply.current, reply.max)
    }
}

private final class IntelDDCTransport: DDCTransport {
    private let ddc: IntelDDC

    init(ddc: IntelDDC) {
        self.ddc = ddc
    }

    func write(command: UInt8, value: UInt16) -> Bool {
        ddc.write(command: command, value: value)
    }

    func read(command: UInt8) -> (current: UInt16, maximum: UInt16)? {
        guard let reply = ddc.read(command: command, tries: 2) else { return nil }
        return (reply.0, reply.1)
    }
}

final class DDCServiceDirectory {
    private let displayIDs: [CGDirectDisplayID]
    private let lock = NSLock()
    private var matches: [CGDirectDisplayID: Arm64DDC.Arm64Service]?

    init(displayIDs: [CGDirectDisplayID]) {
        self.displayIDs = displayIDs
    }

    func transport(for displayID: CGDirectDisplayID) -> DDCTransport? {
        if Arm64DDC.isArm64 {
            lock.lock()
            if matches == nil {
                var resolved: [CGDirectDisplayID: Arm64DDC.Arm64Service] = [:]
                for match in Arm64DDC.getServiceMatches(displayIDs: displayIDs) {
                    resolved[match.displayID] = match
                }
                matches = resolved
            }
            let match = matches?[displayID]
            lock.unlock()
            guard let match, let service = match.service, !match.discouraged, !match.dummy else { return nil }
            return Arm64DDCTransport(service: service)
        }
        guard let ddc = IntelDDC(for: displayID) else { return nil }
        return IntelDDCTransport(ddc: ddc)
    }
}

final class DDCChannel {
    enum ProbeOutcome {
        case available(current: UInt16?, maximum: UInt16?)
        case unavailable
    }

    let displayID: CGDirectDisplayID

    private static let brightnessCommand = Command.brightness.rawValue
    private static let minimumWriteInterval: TimeInterval = 0.05
    private static let failuresBeforeGivingUp = 2

    private let queue: DispatchQueue
    private let directory: DDCServiceDirectory
    private let onProbe: (ProbeOutcome) -> Void
    private let onFailure: () -> Void
    private let logger = Logger(subsystem: "com.shariq.sapphire", category: "DDC")

    private let lock = NSLock()
    private var mailbox = LatestValueMailbox<UInt16>()
    private var isCancelled = false

    private var transport: DDCTransport?
    private var hasProbed = false
    private var hasFailed = false
    private var lastWriteAt: Date?
    private var consecutiveFailures = 0

    init(
        displayID: CGDirectDisplayID,
        directory: DDCServiceDirectory,
        onProbe: @escaping (ProbeOutcome) -> Void,
        onFailure: @escaping () -> Void
    ) {
        self.displayID = displayID
        self.directory = directory
        self.onProbe = onProbe
        self.onFailure = onFailure
        queue = DispatchQueue(label: "com.shariq.sapphire.ddc.\(displayID)", qos: .userInitiated)
    }

    func probe() {
        queue.async { [self] in probeIfNeeded() }
    }

    func writeBrightness(_ value: UInt16) {
        lock.lock()
        let mustDrain = !isCancelled && mailbox.post(value)
        lock.unlock()
        guard mustDrain else { return }
        queue.async { [self] in drain() }
    }

    func cancel() {
        lock.lock()
        isCancelled = true
        while mailbox.take() != nil {}
        lock.unlock()
    }

    private var cancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isCancelled
    }

    private func probeIfNeeded() {
        guard !hasProbed else { return }
        hasProbed = true
        guard !cancelled else { return }

        transport = directory.transport(for: displayID)
        guard let transport else {
            logger.info("No DDC service for display \(self.displayID, privacy: .public)")
            deliver { $0.onProbe(.unavailable) }
            return
        }
        let reading = transport.read(command: Self.brightnessCommand)
        deliver { $0.onProbe(.available(current: reading?.current, maximum: reading?.maximum)) }
    }

    private func drain() {
        probeIfNeeded()
        while true {
            lock.lock()
            let next = isCancelled ? nil : mailbox.take()
            if isCancelled {
                while mailbox.take() != nil {}
            }
            lock.unlock()
            guard let value = next else { return }
            guard let transport, !hasFailed else { continue }

            let wait = DDCPacing.delay(
                sinceLastWrite: lastWriteAt.map { Date().timeIntervalSince($0) },
                minimumInterval: Self.minimumWriteInterval
            )
            if wait > 0 { Thread.sleep(forTimeInterval: wait) }

            let succeeded = transport.write(command: Self.brightnessCommand, value: value)
            lastWriteAt = Date()
            if succeeded {
                consecutiveFailures = 0
                continue
            }
            consecutiveFailures += 1
            logger.debug("DDC write to display \(self.displayID, privacy: .public) failed (\(self.consecutiveFailures))")
            if consecutiveFailures >= Self.failuresBeforeGivingUp {
                hasFailed = true
                deliver { $0.onFailure() }
            }
        }
    }

    private func deliver(_ body: @escaping (DDCChannel) -> Void) {
        DispatchQueue.main.async { [self] in
            guard !cancelled else { return }
            body(self)
        }
    }
}