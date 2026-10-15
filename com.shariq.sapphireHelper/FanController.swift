//
//  FanController.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-10-07
//

import Foundation
import IOKit
import IOKit.pwr_mgt
import os.log

final class FanController {

    static let leaseDuration: TimeInterval = 7

    private struct AppliedState: Equatable {
        let mode: FanMode
        let speed: Int?
        var isCurrent = true
    }

    private let smc: SMC
    private let logger = Logger(subsystem: "com.shariq.sapphireHelper", category: "FanController")
    private let queue = DispatchQueue(label: "com.shariq.sapphireHelper.fans", qos: .userInitiated)

    private var applied: [Int: AppliedState] = [:]
    private var pendingRestore: Set<Int> = []

    private var leaseDeadline: DispatchTime?
    private var leaseOwner: ObjectIdentifier?
    private var tickTimer: DispatchSourceTimer?
    private var thermalOverride = false
    private var thermalObserver: NSObjectProtocol?

    private var powerPort: io_connect_t = 0
    private var powerNotifier: io_object_t = 0
    private var powerNotificationPort: IONotificationPortRef?

    init(smc: SMC) {
        self.smc = smc
        queue.async { [weak self] in
            self?.revertFansLeftForcedByPreviousRun()
            self?.thermalOverride = Self.isThermallyConstrained(ProcessInfo.processInfo.thermalState)
        }
        thermalObserver = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.queue.async { self?.handleThermalStateChange() }
        }
        registerForPowerNotifications()
    }

    deinit {
        if let thermalObserver { NotificationCenter.default.removeObserver(thermalObserver) }
        unregisterPowerNotifications()
        tickTimer?.cancel()
    }

    func revertAllSynchronously() {
        queue.sync { revertAllForcedFans(reason: "helper shutdown") }
    }

    // MARK: - Commands

    func setMode(fanIndex: Int, forced: Bool, connection: NSXPCConnection?, reply: @escaping (Error?) -> Void) {
        queue.async { [self] in
            if forced {
                if let error = rejectForcedWriteIfNeeded() { reply(error); return }
                let requested = AppliedState(mode: .forced, speed: applied[fanIndex]?.speed)
                if let state = applied[fanIndex], state.mode == .forced, state.isCurrent {
                    renewLease(owner: connection)
                    reply(nil)
                    return
                }
                let result = smc.setFanMode(fanIndex, mode: .forced)
                guard result == kIOReturnSuccess else {
                    markPossiblyForced(fanIndex, owner: connection)
                    reply(makeError(code: .smcWriteFailed, description: "Failed to set fan mode."))
                    return
                }
                applied[fanIndex] = requested
                pendingRestore.remove(fanIndex)
                renewLease(owner: connection)
                reply(nil)
            } else {
                if applied[fanIndex] == AppliedState(mode: .automatic, speed: 0) {
                    reply(nil)
                    return
                }
                let ok = restoreAutomatic(fanIndex)
                finishIfNoForcedFans()
                reply(ok ? nil : makeError(code: .smcWriteFailed, description: "Failed to set fan mode."))
            }
        }
    }

    func setTargetSpeed(fanIndex: Int, speed: Int, connection: NSXPCConnection?, reply: @escaping (Error?) -> Void) {
        queue.async { [self] in
            if let error = rejectForcedWriteIfNeeded() { reply(error); return }
            let requested = AppliedState(mode: .forced, speed: speed)
            if applied[fanIndex] == requested {
                renewLease(owner: connection)
                reply(nil)
                return
            }
            let result = smc.setFanSpeed(fanIndex, speed: speed)
            guard result == kIOReturnSuccess else {
                markPossiblyForced(fanIndex, owner: connection)
                reply(makeError(code: .smcWriteFailed, description: "Failed to write F\(fanIndex)Tg."))
                return
            }
            applied[fanIndex] = requested
            pendingRestore.remove(fanIndex)
            renewLease(owner: connection)
            reply(nil)
        }
    }

    func setConstantRPM(fanIndex: Int, speed: Int, connection: NSXPCConnection?, reply: @escaping (Error?) -> Void) {
        queue.async { [self] in
            if let error = rejectForcedWriteIfNeeded() { reply(error); return }
            let requested = AppliedState(mode: .forced, speed: speed)
            if applied[fanIndex] == requested {
                renewLease(owner: connection)
                reply(nil)
                return
            }
            renewLease(owner: connection)
            let modeResult = smc.setFanMode(fanIndex, mode: .forced)
            guard modeResult == kIOReturnSuccess else {
                logger.error("Failed to force fan \(fanIndex): \(modeResult)")
                applied[fanIndex] = nil
                _ = restoreAutomatic(fanIndex)
                finishIfNoForcedFans()
                reply(makeError(code: .smcWriteFailed, description: "Failed to set fan to manual mode."))
                return
            }
            let speedResult = smc.setFanSpeed(fanIndex, speed: speed)
            guard speedResult == kIOReturnSuccess else {
                logger.error("Failed to set fan \(fanIndex) target: \(speedResult)")
                applied[fanIndex] = nil
                _ = restoreAutomatic(fanIndex)
                finishIfNoForcedFans()
                reply(makeError(code: .smcWriteFailed, description: "Failed to write F\(fanIndex)Tg."))
                return
            }
            applied[fanIndex] = requested
            pendingRestore.remove(fanIndex)
            reply(nil)
        }
    }

    private func markPossiblyForced(_ fanIndex: Int, owner connection: NSXPCConnection?) {
        applied[fanIndex] = AppliedState(mode: .forced, speed: nil, isCurrent: false)
        renewLease(owner: connection)
    }

    func renew(connection: NSXPCConnection?, reply: @escaping (Bool) -> Void) {
        queue.async { [self] in
            dropForcedEntriesTheSMCNoLongerHonours()
            let holdsForcedState = applied.values.contains { $0.mode == .forced }
            if holdsForcedState {
                renewLease(owner: connection)
            }
            reply(holdsForcedState)
        }
    }

    func release(reply: @escaping (Error?) -> Void) {
        queue.async { [self] in
            revertAllForcedFans(reason: "released by app")
            reply(pendingRestore.isEmpty ? nil : makeError(code: .smcWriteFailed, description: "Failed to restore automatic fan control."))
        }
    }

    func connectionEnded(_ id: ObjectIdentifier) {
        queue.async { [self] in
            guard leaseOwner == id else { return }
            revertAllForcedFans(reason: "client connection ended")
        }
    }

    func invalidateAppliedState() {
        queue.async { [self] in markAppliedStateStale() }
    }

    private func markAppliedStateStale() {
        for (fan, state) in applied {
            if state.mode == .forced {
                applied[fan]?.isCurrent = false
            } else {
                applied[fan] = nil
            }
        }
    }

    // MARK: - Lease

    private func renewLease(owner connection: NSXPCConnection?) {
        leaseDeadline = .now() + Self.leaseDuration
        if let connection { leaseOwner = ObjectIdentifier(connection) }
        startTickTimerIfNeeded()
    }

    private func startTickTimerIfNeeded() {
        guard tickTimer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 1, repeating: 1, leeway: .milliseconds(250))
        timer.setEventHandler { [weak self] in self?.tick() }
        timer.resume()
        tickTimer = timer
    }

    private func stopTickTimer() {
        tickTimer?.cancel()
        tickTimer = nil
    }

    private func tick() {
        if !pendingRestore.isEmpty {
            for fan in pendingRestore.sorted() { _ = restoreAutomatic(fan) }
            finishIfNoForcedFans()
        }
        if Self.isThermallyConstrained(ProcessInfo.processInfo.thermalState) {
            thermalOverride = true
            if applied.values.contains(where: { $0.mode == .forced }) {
                revertAllForcedFans(reason: "thermal pressure")
            }
        }
        if let deadline = leaseDeadline, DispatchTime.now() >= deadline {
            revertAllForcedFans(reason: "lease expired")
        }
        if leaseDeadline == nil, pendingRestore.isEmpty {
            stopTickTimer()
        }
    }

    private func revertAllForcedFans(reason: String) {
        let forced = applied.filter { $0.value.mode == .forced }.map(\.key)
        let targets = Set(forced).union(pendingRestore)
        if !targets.isEmpty {
            logger.log("Reverting \(targets.count) fan(s) to automatic: \(reason, privacy: .public)")
        }
        for fan in targets.sorted() { _ = restoreAutomatic(fan) }
        leaseDeadline = nil
        leaseOwner = nil
        finishIfNoForcedFans()
    }

    @discardableResult
    private func restoreAutomatic(_ fanIndex: Int) -> Bool {
        let modeResult = smc.setFanMode(fanIndex, mode: .automatic)
        #if arch(arm64)
        let speedResult = kIOReturnSuccess
        #else
        let speedResult = smc.setFanSpeed(fanIndex, speed: 0)
        #endif
        if modeResult == kIOReturnSuccess, speedResult == kIOReturnSuccess {
            applied[fanIndex] = AppliedState(mode: .automatic, speed: 0)
            pendingRestore.remove(fanIndex)
            return true
        }
        logger.error("Restoring automatic control on fan \(fanIndex) failed; will retry.")
        applied[fanIndex] = nil
        pendingRestore.insert(fanIndex)
        startTickTimerIfNeeded()
        return false
    }

    private func finishIfNoForcedFans() {
        guard !applied.values.contains(where: { $0.mode == .forced }) else { return }
        leaseDeadline = nil
        leaseOwner = nil
        guard pendingRestore.isEmpty else { return }
        smc.clearFanTestFlagIfSet()
        stopTickTimer()
    }

    private func dropForcedEntriesTheSMCNoLongerHonours() {
        for (fan, state) in applied where state.mode == .forced {
            if smc.isFanForced(fan) == false {
                applied[fan] = nil
            }
        }
        if !applied.values.contains(where: { $0.mode == .forced }) {
            leaseDeadline = nil
            leaseOwner = nil
        }
    }

    // MARK: - Startup / thermal

    private func revertFansLeftForcedByPreviousRun() {
        let count = Int(smc.getValue("FNum") ?? 0)
        guard count > 0 else { return }
        var reverted = false
        for fan in 0..<min(count, 8) where smc.isFanForced(fan) == true {
            logger.log("Fan \(fan) was left forced; restoring automatic control.")
            _ = restoreAutomatic(fan)
            reverted = true
        }
        if reverted { finishIfNoForcedFans() }
    }

    private func handleThermalStateChange() {
        let constrained = Self.isThermallyConstrained(ProcessInfo.processInfo.thermalState)
        thermalOverride = constrained
        if constrained {
            revertAllForcedFans(reason: "thermal pressure")
        }
    }

    private func rejectForcedWriteIfNeeded() -> Error? {
        if thermalOverride {
            thermalOverride = Self.isThermallyConstrained(ProcessInfo.processInfo.thermalState)
        }
        guard thermalOverride else { return nil }
        return makeError(code: .generalError, description: "Fan control is paused while the Mac is under thermal pressure.")
    }

    private static func isThermallyConstrained(_ state: ProcessInfo.ThermalState) -> Bool {
        state == .serious || state == .critical
    }

    // MARK: - Power notifications

    private static let messageCanSystemSleep: UInt32 = 0xE000_0270
    private static let messageSystemWillSleep: UInt32 = 0xE000_0280
    private static let messageSystemHasPoweredOn: UInt32 = 0xE000_0300

    private func registerForPowerNotifications() {
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        var port: IONotificationPortRef?
        let root = IORegisterForSystemPower(refcon, &port, { refcon, _, messageType, messageArgument in
            guard let refcon else { return }
            let controller = Unmanaged<FanController>.fromOpaque(refcon).takeUnretainedValue()
            controller.handlePowerMessage(messageType, argument: messageArgument)
        }, &powerNotifier)
        guard root != 0, let port else {
            logger.error("IORegisterForSystemPower failed; relying on lease verification after wake.")
            return
        }
        powerPort = root
        powerNotificationPort = port
        IONotificationPortSetDispatchQueue(port, queue)
    }

    private func unregisterPowerNotifications() {
        if powerNotifier != 0 {
            IODeregisterForSystemPower(&powerNotifier)
            powerNotifier = 0
        }
        if powerPort != 0 {
            IOServiceClose(powerPort)
            powerPort = 0
        }
        if let powerNotificationPort {
            IONotificationPortDestroy(powerNotificationPort)
            self.powerNotificationPort = nil
        }
    }

    private func handlePowerMessage(_ message: UInt32, argument: UnsafeMutableRawPointer?) {
        switch message {
        case Self.messageCanSystemSleep, Self.messageSystemWillSleep:
            IOAllowPowerChange(powerPort, Int(bitPattern: argument))
        case Self.messageSystemHasPoweredOn:
            markAppliedStateStale()
        default:
            break
        }
    }
}