//
//  FanManager.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-10-23
//

import Foundation
import Combine
import AppKit

// MARK: - Data Models

struct FanCurvePoint: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var temperature: Int
    var rpm: Int

    enum CodingKeys: String, CodingKey {
        case temperature, rpm
    }
}

enum FanControlMode: Equatable {
    case auto
    case constant(rpm: Int)
    case sensor(sensorKey: String, minTemp: Int, maxTemp: Int)
    case customCurve(sensorKey: String, points: [FanCurvePoint])
}

struct StoredFanControlMode: Codable, Equatable {
    enum Kind: String, Codable {
        case auto, constant, sensor, customCurve
    }

    var kind: Kind
    var rpm: Int?
    var sensorKey: String?
    var minTemp: Int?
    var maxTemp: Int?
    var points: [FanCurvePoint]?

    init(from mode: FanControlMode) {
        switch mode {
        case .auto:
            kind = .auto
        case .constant(let rpm):
            kind = .constant
            self.rpm = rpm
        case .sensor(let sensorKey, let minTemp, let maxTemp):
            kind = .sensor
            self.sensorKey = sensorKey
            self.minTemp = minTemp
            self.maxTemp = maxTemp
        case .customCurve(let sensorKey, let points):
            kind = .customCurve
            self.sensorKey = sensorKey
            self.points = points
        }
    }

    func toMode() -> FanControlMode {
        switch kind {
        case .auto:
            return .auto
        case .constant:
            return .constant(rpm: rpm ?? 2000)
        case .sensor:
            return .sensor(
                sensorKey: sensorKey ?? "TC0P",
                minTemp: minTemp ?? 40,
                maxTemp: maxTemp ?? 75
            )
        case .customCurve:
            return .customCurve(
                sensorKey: sensorKey ?? "TC0P",
                points: points ?? []
            )
        }
    }
}

struct TemperatureSensor: Identifiable, Hashable {
    let id = UUID()
    let key: String
    var name: String { SensorNameMap.name(for: key) }
    var value: Double = 0
}

// MARK: - Fan Manager

@MainActor
class FanManager: ObservableObject {
    static let shared = FanManager()
    private static weak var liveInstance: FanManager?

    @Published var fans: [FanInfo] = []
    @Published private(set) var sensors: [TemperatureSensor] = []
    @Published private(set) var fanModes: [Int: FanControlMode] = [:]

    private static let monitorInterval: TimeInterval = 3
    private static let heartbeatInterval: TimeInterval = 2
    private static let missingReadingLimit = 3

    private enum LeaseSupport { case unknown, probing, supported, unsupported }

    private var monitorTimer: Timer?
    private var heartbeatTimer: Timer?
    private var leaseSupport: LeaseSupport = .unknown
    private var heartbeatInFlight = false
    private var leaseActivity: NSObjectProtocol?
    private var uiVisibilityCount = 0
    private var curveStates: [Int: FanCurvePolicy.State] = [:]
    private var missingReadings: [Int: Int] = [:]
    private var curveFansOnAutomatic: Set<Int> = []
    private var notificationObservers: [NSObjectProtocol] = []
    private var workspaceObservers: [NSObjectProtocol] = []
    private var updateInFlight = false
    private var hardwareRefreshInFlight = false
    private var restoredPersistedModes = false
    private var fanCommands = FanCommandSlots()
    private var acceptedFanless = false
    private(set) var isSuspended = false

    private var configuredForcedFanIDs: [Int] {
        fans.map(\.id).filter { id in
            if case .auto = fanModes[id] ?? .auto { return false }
            return true
        }
    }

    private var forcedFanIDs: [Int] {
        isSuspended ? [] : configuredForcedFanIDs
    }

    private var hasForcedFans: Bool { !forcedFanIDs.isEmpty }

    private var needsMonitoring: Bool { uiVisibilityCount > 0 || hasForcedFans }

    private init() {
        loadPersistedModes()
        registerHelperObservers()
        registerSleepWakeObservers()
        Self.liveInstance = self
        Task {
            await refreshHardwareState()
        }
    }

    deinit {
        notificationObservers.forEach { NotificationCenter.default.removeObserver($0) }
        workspaceObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
    }

    func beginPolling() {
        uiVisibilityCount += 1
        refreshPollingState()
        Task { await refreshHardwareState() }
    }

    func endPolling() {
        uiVisibilityCount = max(0, uiVisibilityCount - 1)
        refreshPollingState()
    }

    private func refreshPollingState() {
        if needsMonitoring {
            startMonitoring()
        } else {
            stopMonitoring()
        }
        refreshLeaseState()
    }

    private func registerHelperObservers() {
        let center = NotificationCenter.default
        notificationObservers = [
            center.addObserver(forName: .sapphireHelperConnectionRestored, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    self.leaseSupport = .unknown
                    guard !self.isSuspended else { return }
                    await self.refreshHardwareState(forceRediscovery: true)
                }
            },
            center.addObserver(forName: .sapphireHelperConnectionLost, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    self.acceptedFanless = false
                    self.restoredPersistedModes = false
                    self.leaseSupport = .unknown
                    self.resetAppliedState()
                }
            }
        ]
    }

    private func registerSleepWakeObservers() {
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers = [
            center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    guard let self, !self.isSuspended else { return }
                    await self.refreshHardwareState()
                    self.reapplyActiveModes()
                }
            }
        ]
    }

    func refreshHardwareState(forceRediscovery: Bool = false) async {
        guard !hardwareRefreshInFlight else { return }
        hardwareRefreshInFlight = true
        defer { hardwareRefreshInFlight = false }

        if forceRediscovery {
            acceptedFanless = false
            restoredPersistedModes = false
        }
        await initializeFans()
        await initializeSensors()

        if !restoredPersistedModes, !isSuspended, !fans.isEmpty {
            restoredPersistedModes = true
            reapplyActiveModes()
        }
        refreshPollingState()
    }

    private func initializeFans() async {
        guard let helper = getHelper() else { return }

        let fanCount = await helper.getFanCount()
        guard fanCount > 0 else {
            acceptedFanless = true
            fans = []
            resetAppliedState()
            return
        }

        acceptedFanless = false

        var fanArray: [FanInfo] = []
        for index in 0..<fanCount {
            if let fanInfo = await helper.getFanInfo(fanIndex: index) {
                fanArray.append(fanInfo)
                if fanModes[fanInfo.id] == nil {
                    fanModes[fanInfo.id] = .auto
                }
            }
        }

        if fanArray.isEmpty {
            acceptedFanless = true
            fans = []
            resetAppliedState()
            return
        }

        fans = fanArray.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func initializeSensors() async {
        guard let helper = getHelper() else { return }

        let availableKeys = Set(await helper.getAllSMCKeys())
        guard !availableKeys.isEmpty else { return }
        var foundSensors: [TemperatureSensor] = []

        for (key, _) in SensorNameMap.knownSensors where availableKeys.contains(key) {
            foundSensors.append(TemperatureSensor(key: key))
        }

        for i in 0...15 {
            let hexChar = String(format: "%X", i)
            for key in ["TC\(hexChar)c", "TC\(hexChar)C"] where availableKeys.contains(key) {
                foundSensors.append(TemperatureSensor(key: key))
            }
        }

        let previousValues = Dictionary(sensors.map { ($0.key, $0.value) }, uniquingKeysWith: { first, _ in first })
        sensors = foundSensors
            .reduce(into: [TemperatureSensor]()) { result, sensor in
                if !result.contains(where: { $0.key == sensor.key }) {
                    var sensor = sensor
                    sensor.value = previousValues[sensor.key] ?? 0
                    result.append(sensor)
                }
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: - Monitoring loop

    private func startMonitoring() {
        guard monitorTimer == nil else { return }
        monitorTimer = Timer.scheduledCoalescing(withTimeInterval: Self.monitorInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateData() }
        }
        updateData()
    }

    private func stopMonitoring() {
        monitorTimer?.invalidate()
        monitorTimer = nil
    }

    private var controlSensorKeys: Set<String> {
        Set(forcedFanIDs.compactMap { id -> String? in
            switch fanModes[id] {
            case .sensor(let key, _, _), .customCurve(let key, _): return key
            default: return nil
            }
        })
    }

    private func updateData() {
        guard !updateInFlight, needsMonitoring else { return }
        updateInFlight = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { updateInFlight = false }
            guard let helper = getHelper() else { return }

            let keys = uiVisibilityCount > 0 ? Set(sensors.map(\.key)) : controlSensorKeys
            var readings: [String: Double] = [:]
            if !keys.isEmpty {
                let values = await helper.getSensorValues(keys: Array(keys))
                for key in keys {
                    guard let number = values[key] as? NSNumber else { continue }
                    let value = number.doubleValue
                    if value.isFinite, value > 0 { readings[key] = value }
                }
                var updated = sensors
                var changed = false
                for index in updated.indices {
                    if let value = readings[updated[index].key], updated[index].value != value {
                        updated[index].value = value
                        changed = true
                    }
                }
                if changed { sensors = updated }
            }

            await refreshCurrentRPMs(helper: helper)
            applyCurveModes(readings: readings)
        }
    }

    private func refreshCurrentRPMs(helper: HelperProtocol) async {
        let snapshot = fans
        guard !snapshot.isEmpty else { return }
        var refreshed: [Int: FanInfo] = [:]
        for fan in snapshot {
            if let info = await helper.getFanInfo(fanIndex: fan.id) {
                refreshed[fan.id] = info
            }
        }
        var changed = false
        let updated = fans.map { fan -> FanInfo in
            guard let info = refreshed[fan.id], info.currentRPM != fan.currentRPM else { return fan }
            changed = true
            return FanInfo(id: fan.id, name: fan.name, minRPM: fan.minRPM, maxRPM: fan.maxRPM, currentRPM: info.currentRPM)
        }
        if changed { fans = updated }
    }

    private func curvePoints(for fan: FanInfo, mode: FanControlMode) -> (sensorKey: String, points: [FanCurvePoint])? {
        switch mode {
        case .sensor(let key, let minTemp, let maxTemp):
            return (key, [
                FanCurvePoint(temperature: minTemp, rpm: fan.minRPM),
                FanCurvePoint(temperature: maxTemp, rpm: fan.maxRPM)
            ])
        case .customCurve(let key, let points):
            return (key, points)
        case .auto, .constant:
            return nil
        }
    }

    private func applyCurveModes(readings: [String: Double]) {
        guard !isSuspended else { return }
        for fan in fans {
            guard !fanCommands.isRunning(fan.id),
                  let mode = fanModes[fan.id],
                  let curve = curvePoints(for: fan, mode: mode) else { continue }

            guard let temperature = readings[curve.sensorKey] else {
                let misses = (missingReadings[fan.id] ?? 0) + 1
                missingReadings[fan.id] = misses
                if misses >= Self.missingReadingLimit, !curveFansOnAutomatic.contains(fan.id) {
                    curveFansOnAutomatic.insert(fan.id)
                    curveStates[fan.id]?.appliedRPM = nil
                    let fanID = fan.id
                    Task { await self.getHelper()?.setFanMode(fanIndex: fanID, mode: 0) }
                }
                continue
            }
            missingReadings[fan.id] = 0

            var state = curveStates[fan.id] ?? FanCurvePolicy.State()
            let target = FanCurvePolicy.nextTarget(
                state: &state,
                temperature: temperature,
                points: curve.points,
                minRPM: fan.minRPM,
                maxRPM: fan.maxRPM
            )
            curveStates[fan.id] = state
            guard let target else { continue }

            let fanID = fan.id
            let wasOnAutomatic = curveFansOnAutomatic.remove(fanID) != nil
            Task { @MainActor [weak self] in
                guard let self, !self.isSuspended, let helper = self.getHelper() else { return }
                let ok = wasOnAutomatic
                    ? await helper.setFanToConstantRPM(fanIndex: fanID, speed: target)
                    : await helper.setFanTargetSpeed(fanIndex: fanID, speed: target)
                if !ok {
                    self.curveStates[fanID]?.appliedRPM = nil
                    self.curveFansOnAutomatic.insert(fanID)
                }
            }
        }
    }

    // MARK: - Modes

    func setFanMode(for fanID: Int, to mode: FanControlMode) {
        guard fans.contains(where: { $0.id == fanID }) else { return }
        guard fanModes[fanID] != mode else { return }
        fanModes[fanID] = mode
        persistModes()
        refreshPollingState()
        applyFanMode(fanID: fanID, mode: mode)
    }

    private func resetAppliedState() {
        for id in curveStates.keys { curveStates[id]?.appliedRPM = nil }
        missingReadings.removeAll()
        curveFansOnAutomatic.removeAll()
    }

    private func reapplyActiveModes() {
        resetAppliedState()
        for fanID in forcedFanIDs {
            guard let mode = fanModes[fanID] else { continue }
            applyFanMode(fanID: fanID, mode: mode)
        }
    }

    private func applyFanMode(fanID: Int, mode: FanControlMode) {
        guard !isSuspended else { return }
        curveStates[fanID] = nil
        missingReadings[fanID] = nil
        curveFansOnAutomatic.remove(fanID)
        let commandID = fanCommands.reserve(fanID)
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { fanCommands.finish(fanID, commandID: commandID) }
            guard let helper = getHelper() else { return }

            switch mode {
            case .auto:
                await helper.setFanMode(fanIndex: fanID, mode: 0)
            case .constant(let rpm):
                await helper.setFanToConstantRPM(fanIndex: fanID, speed: rpm)
            case .sensor, .customCurve:
                guard let fan = fans.first(where: { $0.id == fanID }),
                      let curve = curvePoints(for: fan, mode: mode) else { return }
                let values = await helper.getSensorValues(keys: [curve.sensorKey])
                guard !Task.isCancelled else { return }
                let reading = (values[curve.sensorKey] as? NSNumber)?.doubleValue ?? 0
                guard reading.isFinite, reading > 0 else {
                    curveFansOnAutomatic.insert(fanID)
                    await helper.setFanMode(fanIndex: fanID, mode: 0)
                    return
                }
                var state = FanCurvePolicy.State()
                guard let target = FanCurvePolicy.nextTarget(
                    state: &state,
                    temperature: reading,
                    points: curve.points,
                    minRPM: fan.minRPM,
                    maxRPM: fan.maxRPM
                ) else { return }
                let ok = await helper.setFanToConstantRPM(fanIndex: fanID, speed: target)
                guard !Task.isCancelled else { return }
                if ok {
                    curveStates[fanID] = state
                } else {
                    state.appliedRPM = nil
                    curveStates[fanID] = state
                    curveFansOnAutomatic.insert(fanID)
                }
            }
        }
        fanCommands.attach(task, to: fanID, commandID: commandID)
    }

    func getMode(for fanID: Int) -> FanControlMode {
        fanModes[fanID] ?? .auto
    }

    func resetAllFansToAutomatic() {
        for fan in fans where getMode(for: fan.id) != .auto {
            fanModes[fan.id] = .auto
            applyFanMode(fanID: fan.id, mode: .auto)
        }
        persistModes()
        refreshPollingState()
    }

    var hasNonAutomaticFans: Bool { hasForcedFans }

    static func defaultCurvePoints(for fan: FanInfo) -> [FanCurvePoint] {
        let midRPM = fan.minRPM + ((fan.maxRPM - fan.minRPM) / 2)
        return [
            FanCurvePoint(temperature: 45, rpm: fan.minRPM),
            FanCurvePoint(temperature: 65, rpm: midRPM),
            FanCurvePoint(temperature: 85, rpm: fan.maxRPM)
        ]
    }

    // MARK: - Lease

    private func refreshLeaseState() {
        guard hasForcedFans, leaseSupport != .unsupported else {
            heartbeatTimer?.invalidate()
            heartbeatTimer = nil
            endLeaseActivity()
            return
        }
        beginLeaseActivity()
        if heartbeatTimer == nil {
            heartbeatTimer = Timer.scheduledCoalescing(withTimeInterval: Self.heartbeatInterval, repeats: true, toleranceFraction: 0.05) { [weak self] _ in
                Task { @MainActor in self?.sendHeartbeat() }
            }
        }
        sendHeartbeat()
    }

    private func beginLeaseActivity() {
        guard leaseActivity == nil else { return }
        leaseActivity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep],
            reason: "Holding manual fan control"
        )
    }

    private func endLeaseActivity() {
        if let leaseActivity { ProcessInfo.processInfo.endActivity(leaseActivity) }
        leaseActivity = nil
    }

    private func sendHeartbeat() {
        guard hasForcedFans, !heartbeatInFlight else { return }
        switch leaseSupport {
        case .unsupported:
            heartbeatTimer?.invalidate()
            heartbeatTimer = nil
            endLeaseActivity()
            return
        case .probing:
            return
        case .unknown:
            probeLeaseSupport()
            return
        case .supported:
            break
        }
        guard let helper = getHelper() else { return }
        heartbeatInFlight = true
        Task { @MainActor [weak self] in
            let holdsForcedState = await helper.renewFanLease()
            guard let self else { return }
            self.heartbeatInFlight = false
            guard holdsForcedState == false,
                  self.hasForcedFans,
                  self.fanCommands.isEmpty else { return }
            let fansNeedingForce = self.forcedFanIDs.filter { !self.curveFansOnAutomatic.contains($0) }
            guard !fansNeedingForce.isEmpty else { return }
            self.reapplyActiveModes()
        }
    }

    private func probeLeaseSupport() {
        leaseSupport = .probing
        Task { @MainActor [weak self] in
            let version = await XPCClient.shared.helperProtocolVersion(timeout: 2)
            guard let self, self.leaseSupport == .probing else { return }
            guard let version else {
                self.leaseSupport = .unknown
                return
            }
            self.leaseSupport = version >= SapphireHelperFanLeaseProtocolVersion ? .supported : .unsupported
            if self.leaseSupport == .supported { self.sendHeartbeat() }
        }
    }

    static func releaseFanControlForTermination() {
        guard let manager = liveInstance else { return }
        let wasSuspended = manager.isSuspended
        let forced = manager.configuredForcedFanIDs
        manager.isSuspended = true
        manager.heartbeatTimer?.invalidate()
        manager.heartbeatTimer = nil
        manager.stopMonitoring()
        manager.fanCommands.cancelAll()
        manager.endLeaseActivity()
        manager.resetAppliedState()
        guard !wasSuspended, !forced.isEmpty, let helper = manager.getHelper() else { return }

        let group = DispatchGroup()
        if manager.leaseSupport == .supported {
            group.enter()
            helper.releaseFanLease { _ in group.leave() }
        } else {
            for fanID in forced {
                group.enter()
                helper.setFanMode(fanIndex: fanID, mode: 0) { _ in group.leave() }
            }
        }
        _ = group.wait(timeout: .now() + 1.0)
    }

    static func resumeAfterSuspension() {
        guard let manager = liveInstance, manager.isSuspended else { return }
        manager.isSuspended = false
        manager.restoredPersistedModes = false
        manager.leaseSupport = .unknown
        Task { @MainActor in
            await manager.refreshHardwareState(forceRediscovery: true)
            guard !manager.isSuspended, !manager.restoredPersistedModes, !manager.fans.isEmpty else { return }
            manager.restoredPersistedModes = true
            manager.reapplyActiveModes()
            manager.refreshPollingState()
        }
    }

    // MARK: - Persistence

    private func loadPersistedModes() {
        let stored = SettingsModel.shared.current.fanControlModes
        fanModes = stored.reduce(into: [:]) { result, entry in
            guard let fanID = Int(entry.key) else { return }
            result[fanID] = entry.value.toMode()
        }
    }

    private func persistModes() {
        var settings = SettingsModel.shared.settings
        settings.fanControlModes = fanModes.reduce(into: [:]) { result, entry in
            result[String(entry.key)] = StoredFanControlMode(from: entry.value)
        }
        SettingsModel.shared.settings = settings
    }

    private func getHelper() -> HelperProtocol? {
        BatteryManager.shared.getHelper()
    }
}

// MARK: - Async Helper Wrappers

private enum HelperAsyncTimeout {
    static let seconds: TimeInterval = 8.0
}

extension HelperProtocol {
    func getFanCount() async -> Int {
        await withTimeoutReply(seconds: HelperAsyncTimeout.seconds, default: 0) { finish in
            getFanCount(reply: finish)
        }
    }

    func getFanInfo(fanIndex: Int) async -> FanInfo? {
        await withTimeoutReply(seconds: HelperAsyncTimeout.seconds, default: nil as FanInfo?) { finish in
            getFanInfo(fanIndex: fanIndex, reply: finish)
        }
    }

    func getSensorValues(keys: [String]) async -> NSDictionary {
        await withTimeoutReply(seconds: HelperAsyncTimeout.seconds, default: NSDictionary()) { finish in
            getSensorValues(keys: keys, reply: finish)
        }
    }

    func getSensorValue(key: String) async -> Double {
        await withTimeoutReply(seconds: HelperAsyncTimeout.seconds, default: -1.0) { finish in
            getSensorValue(key: key, reply: finish)
        }
    }

    @discardableResult
    func setFanMode(fanIndex: Int, mode: UInt8) async -> Bool {
        await withTimeoutReply(seconds: HelperAsyncTimeout.seconds, default: false) { finish in
            setFanMode(fanIndex: fanIndex, mode: mode) { finish($0 == nil) }
        }
    }

    @discardableResult
    func setFanTargetSpeed(fanIndex: Int, speed: Int) async -> Bool {
        await withTimeoutReply(seconds: HelperAsyncTimeout.seconds, default: false) { finish in
            setFanTargetSpeed(fanIndex: fanIndex, speed: speed) { finish($0 == nil) }
        }
    }

    @discardableResult
    func setFanToConstantRPM(fanIndex: Int, speed: Int) async -> Bool {
        await withTimeoutReply(seconds: HelperAsyncTimeout.seconds, default: false) { finish in
            setFanToConstantRPM(fanIndex: fanIndex, speed: speed) { finish($0 == nil) }
        }
    }

    func renewFanLease() async -> Bool? {
        await withTimeoutReply(seconds: 3, default: nil as Bool?) { finish in
            renewFanLease { finish($0) }
        }
    }

    func getAllSMCKeys() async -> [String] {
        await withTimeoutReply(seconds: HelperAsyncTimeout.seconds, default: [String]()) { finish in
            getAllSMCKeys(reply: finish)
        }
    }
}

private func withTimeoutReply<T>(
    seconds: TimeInterval,
    default defaultValue: T,
    start: (@escaping (T) -> Void) -> Void
) async -> T {
    await withCheckedContinuation { continuation in
        let lock = NSLock()
        var finished = false
        let finish: (T) -> Void = { value in
            lock.lock()
            defer { lock.unlock() }
            guard !finished else { return }
            finished = true
            continuation.resume(returning: value)
        }

        start(finish)
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + seconds) {
            finish(defaultValue)
        }
    }
}

struct FanCommandSlots {
    private var tasks: [Int: (id: UInt64, task: Task<Void, Never>?)] = [:]
    private var lastID: UInt64 = 0

    var isEmpty: Bool { tasks.isEmpty }

    func isRunning(_ fanID: Int) -> Bool { tasks[fanID] != nil }

    mutating func reserve(_ fanID: Int) -> UInt64 {
        tasks[fanID]?.task?.cancel()
        lastID &+= 1
        tasks[fanID] = (lastID, nil)
        return lastID
    }

    mutating func attach(_ task: Task<Void, Never>, to fanID: Int, commandID: UInt64) {
        guard tasks[fanID]?.id == commandID else {
            task.cancel()
            return
        }
        tasks[fanID] = (commandID, task)
    }

    mutating func finish(_ fanID: Int, commandID: UInt64) {
        if tasks[fanID]?.id == commandID { tasks[fanID] = nil }
    }

    mutating func cancelAll() {
        tasks.values.forEach { $0.task?.cancel() }
        tasks.removeAll()
    }
}