//
//  Stats.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-10-28.
//

import Cocoa
import Foundation
import SystemConfiguration
import CoreWLAN
import IOKit.ps
import IOKit.storage
import CoreServices
import Combine

// MARK: - Stats Data Models

public struct CPU_Load: Codable, Equatable, Hashable {
    public var totalUsage: Double = 0
    var usagePerCore: [Double] = []
    var usageECores: Double? = nil
    var usagePCores: Double? = nil
    var systemLoad: Double = 0
    var userLoad: Double = 0
    var idleLoad: Double = 0
}

public struct RAM_Usage: Codable, Equatable, Hashable {
    var total: Double
    var used: Double
    var free: Double
    var active: Double
    var inactive: Double
    var wired: Double
    var compressed: Double
    var app: Double
    var cache: Double
    var swap: Swap
    var pressure: Pressure
    public var usage: Double {
        MemoryUsageMath.usageFraction(used: used, total: total)
    }
}

public struct Swap: Codable, Equatable, Hashable {
    var total: Double
    var used: Double
    var free: Double
}

public enum RAMPressure: String, Codable {
    case normal = "Normal"
    case warning = "Warning"
    case critical = "Critical"
}

public struct Pressure: Codable, Equatable, Hashable {
    let level: Int
    let value: RAMPressure
}

public enum GPU_types: String, Codable {
    case unknown = "", integrated = "i", external = "e", discrete = "d"
}

public struct GPU_Info: Codable, Equatable, Hashable {
    public let id: String
    public var model: String
    public var vendor: String? = nil
    public var type: GPU_types = .unknown
    public var cores: Int? = nil
    public var state: Bool = true
    public var utilization: Double? = nil
    public var temperature: Double? = nil
}

public class GPUs: Codable {
    public var list: [GPU_Info] = []
}

public struct disk_stats: Codable, Equatable, Hashable {
    var read: Int64 = 0
    var write: Int64 = 0
    var readBytes: Int64 = 0
    var writeBytes: Int64 = 0
}

public struct drive: Codable, Equatable, Hashable {
    var parent: io_object_t = 0
    var uuid: String = ""
    var BSDName: String = ""
    var mediaName: String = ""
    var root: Bool = false
    var removable: Bool = false
    var model: String = ""
    var path: URL?
    var connectionType: String = ""
    var fileSystem: String = ""
    var size: Int64 = 1
    var free: Int64 = 0
    var activity: disk_stats = disk_stats()

    public var percentage: Double {
        let total = self.size
        let free = self.free
        var usedSpace = total - free
        if usedSpace < 0 {
            usedSpace = 0
        }
        return Double(usedSpace) / Double(total)
    }

    public static func == (lhs: drive, rhs: drive) -> Bool {
        lhs.uuid == rhs.uuid
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(uuid)
    }
}

public class Disks: Codable {
    public var array: [drive] = []
}

public protocol Sensor_p: Codable, Identifiable, Hashable {
    var id: String { get }
    var key: String { get }
    var name: String { get }
    var value: Double { get set }
    var group: SensorGroup { get }
    var type: SensorType { get }
    var unit: String { get }
    var formattedValue: String { get }
}
public extension Sensor_p {
    var id: String { key }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

private func fetchIOService(_ name: String) -> [[String: Any]]? {
    var iterator: io_iterator_t = 0
    let result = IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(name), &iterator)
    guard result == kIOReturnSuccess, iterator != 0 else { return nil }

    var services: [[String: Any]] = []
    var service: io_object_t
    while true {
        service = IOIteratorNext(iterator)
        guard service != 0 else { break }

        var properties: Unmanaged<CFMutableDictionary>?
        if IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == kIOReturnSuccess, let dict = properties?.takeRetainedValue() as? [String: Any] {
            services.append(dict)
        }
        IOObjectRelease(service)
    }
    IOObjectRelease(iterator)

    return services
}

public struct SensorWrapper: Codable {
    let sensor: any Sensor_p

    private enum CodingKeys: String, CodingKey {
        case base, payload
    }
    private enum SensorTyp: Int, Codable {
        case sensor, fan
    }

    init(_ sensor: any Sensor_p) {
        self.sensor = sensor
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let base = try container.decode(SensorTyp.self, forKey: .base)
        switch base {
        case .sensor: self.sensor = try container.decode(Sensor.self, forKey: .payload)
        case .fan: self.sensor = try container.decode(Fan.self, forKey: .payload)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch sensor {
        case let payload as Sensor:
            try container.encode(SensorTyp.sensor, forKey: .base)
            try container.encode(payload, forKey: .payload)
        case let payload as Fan:
            try container.encode(SensorTyp.fan, forKey: .base)
            try container.encode(payload, forKey: .payload)
        default:
            let context = EncodingError.Context(codingPath: [], debugDescription: "Unknown Sensor_p type.")
            throw EncodingError.invalidValue(sensor, context)
        }
    }
}

public class Sensors_List: Codable {
    public var sensors: [any Sensor_p] = []

    enum CodingKeys: String, CodingKey {
        case sensors
    }

    public init() {}

    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let wrappers = try container.decode([SensorWrapper].self, forKey: .sensors)
        self.sensors = wrappers.map { $0.sensor }
    }

    public func encode(to encoder: Encoder) throws {
        let wrappers = sensors.map { SensorWrapper($0) }
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(wrappers, forKey: .sensors)
    }
}

public struct Sensor: Sensor_p, Codable {
    public var key: String
    public var name: String
    public var value: Double = 0
    public var group: SensorGroup
    public var type: SensorType
    public var unit: String {
        switch self.type {
        case .temperature: return "°C"
        case .voltage: return "V"
        case .current: return "A"
        case .power: return "W"
        case .energy: return "Wh"
        case .fan: return "RPM"
        case .unknown: return ""
        }
    }
    public var formattedValue: String {
        let valStr: String
        switch self.type {
        case .temperature:
            return "\(Int(value))°"
        case .voltage, .current, .power, .energy:
            valStr = String(format: "%.2f", value)
        case .fan:
            valStr = "\(Int(value))"
        case .unknown:
            return ""
        }
        return "\(valStr) \(unit)"
    }
}

public struct Fan: Sensor_p, Codable {
    public var key: String
    public var name: String
    public var value: Double
    public var group: SensorGroup
    public var type: SensorType
    public var unit: String { "RPM" }
    public var formattedValue: String { "\(Int(value)) RPM" }
}

public struct Battery_Usage: Codable, Equatable, Hashable {
    var powerSource: String = ""
    var isCharging: Bool = false
    var level: Double = 0
    var timeToEmpty: Int = 0
    var timeToCharge: Int = 0
    var amperage: Int = 0
    var voltage: Double = 0
    var power: Int = 0

    var powerDraw: Double {
        return voltage * (Double(amperage) / 1000.0)
    }
}

// MARK: - Main Stats Manager
@MainActor
public class StatsManager: ObservableObject {
    public static let shared = StatsManager()

    @Published public private(set) var currentStats: StatsPayload?
    @Published public private(set) var allSensors: [any Sensor_p] = []

    private lazy var cpuReader: CPUUsageReader = CPUUsageReader { [weak self] value in self?.cpu = value }
    private lazy var ramReader: RAMUsageReader = RAMUsageReader { [weak self] value in self?.ram = value }
    private lazy var gpuReader: GPUInfoReader = GPUInfoReader { [weak self] value in self?.gpus = value ?? GPUs() }
    private lazy var diskReader: DiskActivityReader = DiskActivityReader { [weak self] value in self?.disks = value ?? Disks() }
    private lazy var sensorsReader: SensorsStatsReader = SensorsStatsReader(
        onCatalog: { [weak self] catalog in self?.allSensors = catalog },
        onValues: { [weak self] values in self?.sensors = values }
    )
    private lazy var batteryReader: BatteryStatsReader = BatteryStatsReader { [weak self] value in self?.battery = value }

    private var cpu: CPU_Load? { didSet {
        if let cpu { cpuSamples.send((cpu, ProcessInfo.processInfo.systemUptime)) }
        schedulePayloadUpdate()
    } }
    private var ram: RAM_Usage? { didSet { schedulePayloadUpdate() } }
    private var gpus = GPUs() { didSet { schedulePayloadUpdate() } }
    private var disks = Disks() { didSet { schedulePayloadUpdate() } }
    private var sensors = Sensors_List() { didSet {
        if !sensors.sensors.isEmpty { sensorSamples.send((sensors.sensors, ProcessInfo.processInfo.systemUptime)) }
        schedulePayloadUpdate()
    } }
    private var battery: Battery_Usage? { didSet { schedulePayloadUpdate() } }
    private var payloadUpdateTask: Task<Void, Never>?

    private var pollingRequesters: [String: Set<StatType>] = [:]
    private var sensorKeyRequesters: [String: Set<String>] = [:]
    private var sensorIntervals: [String: TimeInterval] = [:]

    let cpuSamples = PassthroughSubject<(load: CPU_Load, uptime: TimeInterval), Never>()
    let sensorSamples = PassthroughSubject<(sensors: [any Sensor_p], uptime: TimeInterval), Never>()

    nonisolated static let defaultSensorInterval: TimeInterval = 3

    static let powerSensorKeys: Set<String> = ["PSTR", "PDTR", "PCPC", "PCTR", "PC0C", "PGTR", "PG0C", "PCGC"]

    private var settingsCancellable: AnyCancellable?
    private var sensorKeysCancellable: AnyCancellable?
    private let settingsModel = SettingsModel.shared

    private init() {
        let initialRequiredStats = Self.requiredStats(from: settingsModel.settings)
        self.settingsCancellable = settingsModel.changes(of: Self.requiredStats(from:))
            .prepend(initialRequiredStats)
            .debounce(for: .milliseconds(250), scheduler: DispatchQueue.main)
            .sink { [weak self] requiredStats in
                self?.setPolling(for: "LiveActivitySettings", requiredStats: requiredStats)
            }
        self.sensorKeysCancellable = settingsModel.changes(of: Self.requiredSensorKeys(from:))
            .prepend(Self.requiredSensorKeys(from: settingsModel.settings))
            .debounce(for: .milliseconds(250), scheduler: DispatchQueue.main)
            .sink { [weak self] keys in
                self?.setSensorKeys(for: "LiveActivitySettings", keys: keys)
            }

        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshActiveReaders()
            }
        }
    }

    private func refreshActiveReaders() {
        let activeStats = pollingRequesters.values.reduce(Set<StatType>()) { $0.union($1) }
        if activeStats.contains(.cpu) { cpuReader.refresh() }
        if activeStats.contains(.ram) { ramReader.refresh() }
        if activeStats.contains(.gpu) { gpuReader.refresh() }
        if activeStats.contains(.disk) { diskReader.refresh() }
        let needsPower = activeStats.contains(.systemPower) || activeStats.contains(.batteryPower)
        if !requiredSensorKeys(for: activeStats).isEmpty {
            Task { @MainActor in await sensorsReader.readNow() }
        }
        if needsPower {
            batteryReader.refresh()
        }
    }

    private static func requiredSensorKeys(from settings: Settings) -> Set<String> {
        guard settings.statsLiveActivityEnabled else { return [] }
        return Set(settings.selectedSensorKeys)
    }

    public func setSensorKeys(for requester: String, keys: Set<String>, interval: TimeInterval? = nil) {
        let previous = sensorKeyRequesters[requester] ?? []
        var changed = previous != keys
        if keys.isEmpty {
            sensorKeyRequesters.removeValue(forKey: requester)
            changed = sensorIntervals.removeValue(forKey: requester) != nil || changed
        } else {
            sensorKeyRequesters[requester] = keys
            if let interval, sensorIntervals[requester] != interval {
                sensorIntervals[requester] = interval
                changed = true
            }
        }
        guard changed else { return }
        updatePollingState()
    }

    public func requestSensorCatalog() {
        guard allSensors.isEmpty else { return }
        Task { @MainActor in await sensorsReader.loadCatalogIfNeeded() }
    }

    private func requiredSensorKeys(for activeStats: Set<StatType>) -> Set<String> {
        var keys = sensorKeyRequesters.values.reduce(Set<String>()) { $0.union($1) }
        if activeStats.contains(.systemPower) || activeStats.contains(.batteryPower) {
            keys.formUnion(Self.powerSensorKeys)
        }
        return keys
    }

    private static func requiredStats(from settings: Settings) -> Set<StatType> {
        var requiredStats: Set<StatType> = []

        if settings.statsLiveActivityEnabled {
            if settings.showPersistentStatsLiveActivity {
                requiredStats.formUnion(settings.selectedStats)
            }

            if settings.statsLiveActivityThresholdEnabled {
                for (statType, threshold) in settings.statThresholds where threshold.isEnabled {
                    requiredStats.insert(statType)
                }
            }
        }

        return requiredStats
    }

    private var pollingIntervals: [String: DispatchTimeInterval] = [:]

    public func setPolling(for requester: String, requiredStats: Set<StatType>, interval: DispatchTimeInterval? = nil) {
        var changed = false
        if requiredStats.isEmpty {
            changed = pollingRequesters.removeValue(forKey: requester) != nil || changed
            changed = pollingIntervals.removeValue(forKey: requester) != nil || changed
        } else {
            if pollingRequesters[requester] != requiredStats {
                pollingRequesters[requester] = requiredStats
                changed = true
            }
            if let interval, pollingIntervals[requester]?.nanoseconds != interval.nanoseconds {
                pollingIntervals[requester] = interval
                changed = true
            }
        }
        guard changed else { return }
        updatePollingState()
    }

    private func updatePollingState() {
        let activeStats = pollingRequesters.values.reduce(Set<StatType>()) { $0.union($1) }
        update(reader: cpuReader, for: .cpu, in: activeStats)
        update(reader: ramReader, for: .ram, in: activeStats)
        update(reader: gpuReader, for: .gpu, in: activeStats)
        update(reader: diskReader, for: .disk, in: activeStats)

        let needsPowerStats = activeStats.contains(.systemPower) || activeStats.contains(.batteryPower)
        let sensorKeys = requiredSensorKeys(for: activeStats)
        sensorsReader.setRequestedKeys(sensorKeys)
        if sensorKeys.isEmpty {
            sensorsReader.stop()
            if !sensors.sensors.isEmpty { sensors = Sensors_List() }
        } else {
            var sensorInterval = sensorKeyRequesters.keys
                .map { sensorIntervals[$0] ?? Self.defaultSensorInterval }
                .min() ?? Self.defaultSensorInterval
            if needsPowerStats { sensorInterval = min(sensorInterval, Self.defaultSensorInterval) }
            sensorsReader.setInterval(sensorInterval)
            sensorsReader.start()
        }
        update(reader: batteryReader, for: .batteryPower, in: activeStats, force: needsPowerStats)

        let fastestBattery = pollingIntervals
            .filter { pollingRequesters[$0.key]?.contains(.batteryPower) == true }
            .values
            .min { $0.nanoseconds < $1.nanoseconds }
        batteryReader.setInterval(fastestBattery ?? .milliseconds(1000))
    }

    private func update<R: Reader<T>, T>(reader: R, for statType: StatType, in activeStats: Set<StatType>, force: Bool = false) {
        if activeStats.contains(statType) || force {
            reader.start()
        } else {
            reader.stop()
        }
    }

    private func schedulePayloadUpdate() {
        guard payloadUpdateTask == nil else { return }
        payloadUpdateTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(10))
            guard let self, !Task.isCancelled else { return }
            self.payloadUpdateTask = nil
            self.updatePayload()
        }
    }

    private func updatePayload() {
        let primaryDisk = disks.array.first(where: { $0.root }) ?? disks.array.first
        let activeGPUs = gpus.list.filter{ $0.state && $0.utilization != nil }.sorted{ $0.utilization ?? 0 > $1.utilization ?? 0 }
        let primaryGPU = activeGPUs.first
        let sensorSnapshot = Sensors_List()
        sensorSnapshot.sensors = sensors.sensors

        let newPayload = StatsPayload(
            cpu: self.cpu,
            ram: self.ram,
            disk: primaryDisk,
            gpu: primaryGPU,
            sensors: sensorSnapshot,
            battery: self.battery
        )
        if currentStats != newPayload {
            self.currentStats = newPayload
        }
    }
}

// MARK: - DispatchTimeInterval Helpers
private extension DispatchTimeInterval {
    var nanoseconds: Int {
        switch self {
        case .seconds(let s): return s * 1_000_000_000
        case .milliseconds(let ms): return ms * 1_000_000
        case .microseconds(let us): return us * 1_000
        case .nanoseconds(let ns): return ns
        case .never: return 0
        @unknown default: return 0
        }
    }
}

// MARK: - Base Reader Class
internal class Reader<T> {
    private var isActive = false
    private var interval: DispatchTimeInterval
    internal let callback: (T?) -> Void
    private let queue: DispatchQueue
    private let readerName: String
    private var source: DispatchSourceTimer?

    init(interval: DispatchTimeInterval = .seconds(3), callback: @escaping (T?) -> Void) {
        self.interval = interval
        self.callback = callback
        self.readerName = String(describing: T.self)
        self.queue = DispatchQueue(label: "com.cshariq.sapphire.reader.\(readerName)", qos: .utility)
    }

    public func start() {
        self.queue.async { [weak self] in
            guard let self else { return }
            guard !self.isActive else { return }
            self.isActive = true
            self.setup()
            self.startTimer()
            self.read()
        }
    }

    public func stop() {
        self.queue.async { [weak self] in
            guard let self, self.isActive else { return }
            self.isActive = false
            self.source?.cancel()
            self.source = nil
            self.teardown()
        }
    }

    public func setInterval(_ interval: DispatchTimeInterval) {
        queue.async { [weak self] in
            guard let self else { return }
            guard self.interval.nanoseconds != interval.nanoseconds else { return }
            self.interval = interval
            if self.isActive {
                self.startTimer()
            }
        }
    }

    public func refresh() {
        queue.async { [weak self] in
            guard let self, self.isActive else { return }
            self.read()
        }
    }

    private func startTimer() {
        source?.cancel()
        let s = DispatchSource.makeTimerSource(queue: queue)
        let nano = interval.nanoseconds
        guard nano > 0 else { return }
        let intervalTI = DispatchTimeInterval.nanoseconds(nano)
        let leeway = DispatchTimeInterval.nanoseconds(Int(Double(nano) * 0.3))
        s.schedule(deadline: .now() + intervalTI, repeating: intervalTI, leeway: leeway)
        s.setEventHandler { [weak self] in
            guard let self, self.isActive else { return }
            self.read()
        }
        s.resume()
        source = s
    }

    func read() {}

    public func setup() {}

    func teardown() {}

    internal func fireCallback(_ value: T?) {
        let callback = callback
        DispatchQueue.main.async {
            callback(value)
        }
    }

    deinit {
        source?.cancel()
    }
}

// MARK: - CPU Readers

final class AggregateCPUUsageSampler: @unchecked Sendable {
    private let lock = NSLock()
    private var previous: CPUTicks?

    func sample() -> Double? {
        guard let current = Self.snapshot() else { return nil }

        lock.lock()
        let previous = self.previous
        self.previous = current
        lock.unlock()

        guard let previous, let load = CPUTickMath.load(from: previous, to: current) else { return nil }
        return max(0, min(1, load.busy))
    }

    func reset() {
        lock.withLock { previous = nil }
    }

    private static func snapshot() -> CPUTicks? {
        let count = MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride
        var infoCount = mach_msg_type_number_t(count)
        var info = host_cpu_load_info()
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: count) {
                host_statistics(host, HOST_CPU_LOAD_INFO, $0, &infoCount)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return CPUTicks(user: info.cpu_ticks.0, system: info.cpu_ticks.1, idle: info.cpu_ticks.2, nice: info.cpu_ticks.3)
    }
}

internal class CPUUsageReader: Reader<CPU_Load> {
    private static let maximumBaselineAge: TimeInterval = 12

    private var prevCpuInfo: processor_info_array_t?
    private var numPrevCpuInfo: mach_msg_type_number_t = 0
    private var numCPUs: uint = 0
    private let CPUUsageLock: NSLock = NSLock()
    private var previousTicks: CPUTicks?
    private var previousSampleUptime: TimeInterval?
    private var numCPUsU: natural_t = 0

    override func setup() {
        [CTL_HW, HW_NCPU].withUnsafeBufferPointer { mib in
            var sizeOfNumCPUs: size_t = MemoryLayout<uint>.size
            let status = sysctl(processor_info_array_t(mutating: mib.baseAddress), 2, &numCPUs, &sizeOfNumCPUs, nil, 0)
            if status != 0 { self.numCPUs = 1 }
        }
    }

    override func teardown() {
        CPUUsageLock.lock()
        releasePreviousCpuInfo()
        previousTicks = nil
        previousSampleUptime = nil
        CPUUsageLock.unlock()
    }

    deinit {
        releasePreviousCpuInfo()
    }

    private func releasePreviousCpuInfo() {
        if let prev = prevCpuInfo {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: prev), vm_size_t(MemoryLayout<integer_t>.stride * Int(numPrevCpuInfo)))
        }
        prevCpuInfo = nil
        numPrevCpuInfo = 0
    }

    override func read() {
        defer { super.read() }

        let now = ProcessInfo.processInfo.systemUptime
        let baselineIsFresh = previousTicks != nil && prevCpuInfo != nil
            && previousSampleUptime.map { now - $0 <= Self.maximumBaselineAge } == true
        previousSampleUptime = now

        var newResponse = CPU_Load()
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }

        var localCpuInfo: processor_info_array_t?
        var localNumCpuInfo: mach_msg_type_number_t = 0

        let result: kern_return_t = host_processor_info(host, PROCESSOR_CPU_LOAD_INFO, &self.numCPUsU, &localCpuInfo, &localNumCpuInfo)

        if result == KERN_SUCCESS, let currentCpuInfo = localCpuInfo {
            CPUUsageLock.lock()

            if baselineIsFresh, let prevCpuInfo {
                var usagePerCore: [Double] = []
                let stride = Int(CPU_STATE_MAX)
                let coreCount = min(Int(numCPUs), Int(localNumCpuInfo) / stride)
                func ticks(_ info: processor_info_array_t, _ core: Int) -> CPUTicks {
                    let base = stride * core
                    return CPUTicks(
                        signedUser: info[base + Int(CPU_STATE_USER)],
                        system: info[base + Int(CPU_STATE_SYSTEM)],
                        idle: info[base + Int(CPU_STATE_IDLE)],
                        nice: info[base + Int(CPU_STATE_NICE)]
                    )
                }
                let previousCoreCount = Int(numPrevCpuInfo) / stride
                for core in 0..<max(0, coreCount) {
                    guard core < previousCoreCount else {
                        usagePerCore.append(0)
                        continue
                    }
                    let busy = CPUTickMath.load(from: ticks(prevCpuInfo, core), to: ticks(currentCpuInfo, core))?.busy ?? 0
                    usagePerCore.append((0...1).contains(busy) ? busy : 0)
                }
                newResponse.usagePerCore = usagePerCore
            }

            releasePreviousCpuInfo()
            prevCpuInfo = localCpuInfo
            numPrevCpuInfo = localNumCpuInfo

            CPUUsageLock.unlock()
        } else if let localCpuInfo = localCpuInfo {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: localCpuInfo), vm_size_t(MemoryLayout<integer_t>.stride * Int(localNumCpuInfo)))
        }

        guard let cpuInfo = hostCPULoadInfo(host) else { return }
        let current = CPUTicks(user: cpuInfo.cpu_ticks.0, system: cpuInfo.cpu_ticks.1, idle: cpuInfo.cpu_ticks.2, nice: cpuInfo.cpu_ticks.3)
        let previous = previousTicks
        previousTicks = current

        guard baselineIsFresh, let previous,
              let load = CPUTickMath.load(from: previous, to: current) else { return }

        newResponse.systemLoad = load.system
        newResponse.userLoad = load.user
        newResponse.idleLoad = load.idle
        newResponse.totalUsage = load.system + load.user

        guard newResponse.totalUsage >= 0 && newResponse.totalUsage <= 1.0 else { return }

        self.fireCallback(newResponse)
    }

    private func hostCPULoadInfo(_ host: host_t) -> host_cpu_load_info? {
        let count = MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride
        var size = mach_msg_type_number_t(count)
        var cpuLoadInfo = host_cpu_load_info()

        let result: kern_return_t = withUnsafeMutablePointer(to: &cpuLoadInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: count) {
                host_statistics(host, HOST_CPU_LOAD_INFO, $0, &size)
            }
        }
        return result == KERN_SUCCESS ? cpuLoadInfo : nil
    }
}

// MARK: - RAM Readers
internal class RAMUsageReader: Reader<RAM_Usage> {
    private var totalSize: Double = 0

    override func setup() {
        var stats = host_basic_info()
        var count = UInt32(MemoryLayout<host_basic_info_data_t>.size / MemoryLayout<integer_t>.size)
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_info(host, HOST_BASIC_INFO, $0, &count)
            }
        }
        if kerr == KERN_SUCCESS, stats.max_mem > 0 {
            self.totalSize = Double(stats.max_mem)
        } else {
            self.totalSize = Double(ProcessInfo.processInfo.physicalMemory)
        }
    }

    override func read() {
        var stats = vm_statistics64()
        var count = UInt32(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }
        let result: kern_return_t = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }

        if result == KERN_SUCCESS {
            let pageSize = Double(vm_page_size)
            let active = Double(stats.active_count) * pageSize
            let inactive = Double(stats.inactive_count) * pageSize
            let memory = MemoryUsageMath.breakdown(
                internalPages: UInt64(stats.internal_page_count),
                purgeablePages: UInt64(stats.purgeable_count),
                externalPages: UInt64(stats.external_page_count),
                wiredPages: UInt64(stats.wire_count),
                compressedPages: UInt64(stats.compressor_page_count),
                pageSize: UInt64(vm_page_size)
            )
            let used = min(memory.used, self.totalSize)

            var pressureLevel: Int32 = 0
            var size = MemoryLayout<Int32>.size
            if sysctlbyname("kern.memorystatus_vm_pressure_level", &pressureLevel, &size, nil, 0) != 0 {
                pressureLevel = 0
            }
            let pressure: RAMPressure = {
                switch pressureLevel {
                case 2: return .warning
                case 4: return .critical
                default: return .normal
                }
            }()

            var swap = xsw_usage()
            size = MemoryLayout<xsw_usage>.size
            if sysctlbyname("vm.swapusage", &swap, &size, nil, 0) != 0 {
                swap = xsw_usage()
            }

            self.fireCallback(RAM_Usage(
                total: self.totalSize, used: used, free: max(0, self.totalSize - used),
                active: active, inactive: inactive, wired: memory.wired, compressed: memory.compressed,
                app: memory.app, cache: memory.cache,
                swap: Swap(total: Double(swap.xsu_total), used: Double(swap.xsu_used), free: Double(swap.xsu_avail)),
                pressure: Pressure(level: Int(pressureLevel), value: pressure)
            ))
        }

        super.read()
    }
}

internal class GPUInfoReader: Reader<GPUs> {
    private var gpus: GPUs = GPUs()
    override func read() {
        guard let accelerators = fetchIOService(kIOAcceleratorClassName) else {
            self.fireCallback(nil)
            super.read()
            return
        }

        var updatedGPUs: [GPU_Info] = []

        for (index, accelerator) in accelerators.enumerated() {
            guard let stats = accelerator["PerformanceStatistics"] as? [String: Any],
                  let IOClass = accelerator["IOClass"] as? String else { continue }

            let model = stats["model"] as? String ?? IOClass
            let id = "\(model)_\(index)"

            var gpu: GPU_Info
            if let existingGPU = self.gpus.list.first(where: { $0.id == id }) {
                gpu = existingGPU
            } else {
                gpu = GPU_Info(id: id, model: model)
                let ioClassLower = IOClass.lowercased()
                if ioClassLower.contains("intel") || ioClassLower.contains("agx") {
                    gpu.type = .integrated
                } else if ioClassLower.contains("amd") || ioClassLower.contains("nvidia") {
                    gpu.type = .discrete
                }
            }

            let deviceUtilization = stats["Device Utilization %"] as? Int ?? stats["GPU Activity(%)"] as? Int
            let renderUtilization = stats["Renderer Utilization %"] as? Int
            let tilerUtilization = stats["Tiler Utilization %"] as? Int

            var finalUtilization: Double? = nil
            if let render = renderUtilization, let tiler = tilerUtilization {
                finalUtilization = Double(max(render, tiler)) / 100.0
            } else if let deviceUtil = deviceUtilization {
                finalUtilization = Double(deviceUtil) / 100.0
            }

            if let util = finalUtilization {
                gpu.utilization = max(0.0, min(1.0, util))
            }

            if let value = stats["Temperature(C)"] as? Int {
                gpu.temperature = Double(value)
            }
            if let agcInfo = accelerator["AGCInfo"] as? [String: Int], let state = agcInfo["poweredOffByAGC"] {
                gpu.state = state == 0
            }

            updatedGPUs.append(gpu)
        }

        self.gpus.list = updatedGPUs.sorted{ !$0.state && $1.state }
        let snapshot = GPUs()
        snapshot.list = self.gpus.list
        self.fireCallback(snapshot)
        super.read()
    }
}

// MARK: - Disk Reader
internal class DiskActivityReader: Reader<Disks> {
    private var list: Disks = Disks()
    private var session: DASession?
    private var readsSinceCapacityRefresh = 0
    private static let capacityRefreshReads = 5

    override func setup() {
        if session == nil {
            session = DASessionCreate(kCFAllocatorDefault)
        }
    }

    override func read() {
        defer { super.read() }
        let keys: [URLResourceKey] = [.volumeNameKey]
        let paths = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []

        guard let session else { return }

        readsSinceCapacityRefresh += 1
        let refreshCapacity = readsSinceCapacityRefresh >= Self.capacityRefreshReads
        if refreshCapacity { readsSinceCapacityRefresh = 0 }

        var active: Set<String> = []
        for url in paths {
            guard url.pathComponents.count == 1 || (url.pathComponents.count > 1 && url.pathComponents[1] == "Volumes") else { continue }
            guard let disk = DADiskCreateFromVolumePath(kCFAllocatorDefault, session, url as CFURL),
                  let diskName = DADiskGetBSDName(disk) else { continue }
            let BSDName: String = String(cString: diskName)
            active.insert(BSDName)

            if let idx = self.list.array.firstIndex(where: { $0.BSDName == BSDName }) {
                var d = self.list.array[idx]
                if refreshCapacity { Self.refreshCapacity(of: &d) }
                driveStats(d: &d)
                self.list.array[idx] = d
            } else if var d = driveDetails(disk, bsdName: BSDName) {
                driveStats(d: &d)
                list.array.append(d)
            }
        }

        for removed in list.array where !active.contains(removed.BSDName) && removed.parent != 0 {
            IOObjectRelease(removed.parent)
        }
        list.array = list.array.filter { active.contains($0.BSDName) }

        let snapshot = Disks()
        snapshot.array = list.array
        self.fireCallback(snapshot)
    }

    deinit {
        for d in list.array where d.parent != 0 {
            IOObjectRelease(d.parent)
        }
    }

    private static func refreshCapacity(of d: inout drive) {
        guard var path = d.path else { return }
        path.removeAllCachedResourceValues()
        guard let resources = try? path.resourceValues(forKeys: [
            .volumeTotalCapacityKey, .volumeAvailableCapacityKey, .volumeAvailableCapacityForImportantUsageKey
        ]) else { return }
        if let total = resources.volumeTotalCapacity, total > 0 { d.size = Int64(total) }
        if let important = resources.volumeAvailableCapacityForImportantUsage, important > 0 {
            d.free = important
        } else if let free = resources.volumeAvailableCapacity {
            d.free = Int64(free)
        }
    }

    private func driveStats(d: inout drive) {
        guard d.parent != 0, let props = getIOProperties(d.parent) else { return }

        if let statistics = props.object(forKey: "Statistics") as? NSDictionary {
            let readBytes = statistics.object(forKey: "Bytes (Read)") as? Int64 ?? 0
            let writeBytes = statistics.object(forKey: "Bytes (Write)") as? Int64 ?? 0

            if d.activity.readBytes != 0 {
                d.activity.read = max(0, readBytes - d.activity.readBytes)
            }
            if d.activity.writeBytes != 0 {
                d.activity.write = max(0, writeBytes - d.activity.writeBytes)
            }

            d.activity.readBytes = readBytes
            d.activity.writeBytes = writeBytes
        }
    }

    private func driveDetails(_ disk: DADisk, bsdName: String) -> drive? {
        var d = drive()
        d.BSDName = bsdName

        if let desc = DADiskCopyDescription(disk) as? [String: Any] {
            d.mediaName = desc[kDADiskDescriptionMediaNameKey as String] as? String ?? ""
            if d.mediaName == "Recovery" { return nil }

            if let path = desc[kDADiskDescriptionVolumePathKey as String] as? URL {
                d.path = path
                d.root = path.pathComponents.count == 1

                do {
                    let resources = try path.resourceValues(forKeys: [
                        .volumeTotalCapacityKey, .volumeAvailableCapacityKey, .volumeAvailableCapacityForImportantUsageKey
                    ])
                    d.size = Int64(resources.volumeTotalCapacity ?? 1)
                    if let important = resources.volumeAvailableCapacityForImportantUsage, important > 0 {
                        d.free = important
                    } else {
                        d.free = Int64(resources.volumeAvailableCapacity ?? 0)
                    }
                } catch { return nil }
            }
        }

        guard d.path != nil else { return nil }

        let partitionLevel = d.BSDName.filter { "0"..."9" ~= $0 }.count
        let media = DADiskCopyIOMedia(disk)
        if media != 0 {
            if let parent = getDeviceIOParent(media, level: Int(partitionLevel)) {
                d.parent = parent
            }
            IOObjectRelease(media)
        }

        return d
    }

    private func getDeviceIOParent(_ obj: io_registry_entry_t, level: Int) -> io_registry_entry_t? {
        var current: io_registry_entry_t = 0
        guard IORegistryEntryGetParentEntry(obj, kIOServicePlane, &current) == KERN_SUCCESS else { return nil }

        for _ in 0..<max(0, level) {
            var next: io_registry_entry_t = 0
            let result = IORegistryEntryGetParentEntry(current, kIOServicePlane, &next)
            IOObjectRelease(current)
            guard result == KERN_SUCCESS else { return nil }
            current = next
        }

        return current
    }

    private func getIOProperties(_ entry: io_registry_entry_t) -> NSDictionary? {
        var properties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(entry, &properties, kCFAllocatorDefault, 0) == kIOReturnSuccess else {
            return nil
        }
        return properties?.takeRetainedValue()
    }
}

// MARK: - Sensors Readers

@MainActor
internal class SensorsStatsReader {
    private var timer: Timer?
    private var startupTask: Task<Void, Never>?
    private var scheduledReadTask: Task<Void, Never>?
    private var catalogTask: Task<Void, Never>?
    private var readInFlight = false
    private var isRunning = false
    private var lifecycleGeneration: UInt = 0
    private let onCatalog: ([any Sensor_p]) -> Void
    private let onValues: (Sensors_List) -> Void
    private var catalog: [Sensor] = []
    private var catalogLoaded = false
    private var requestedKeys: Set<String> = []
    private var lastValues: [String: Double] = [:]
    private var pollInterval: TimeInterval = StatsManager.defaultSensorInterval

    init(onCatalog: @escaping ([any Sensor_p]) -> Void, onValues: @escaping (Sensors_List) -> Void) {
        self.onCatalog = onCatalog
        self.onValues = onValues
    }

    func setRequestedKeys(_ keys: Set<String>) {
        guard keys != requestedKeys else { return }
        requestedKeys = keys
        lastValues = lastValues.filter { keys.contains($0.key) }
        if isRunning {
            scheduleRead(generation: lifecycleGeneration)
        }
    }

    func setInterval(_ interval: TimeInterval) {
        guard interval > 0, interval != pollInterval else { return }
        pollInterval = interval
        if timer != nil {
            startTimer(generation: lifecycleGeneration)
        }
    }

    private func startTimer(generation: UInt) {
        timer?.invalidate()
        timer = Timer.scheduledCoalescing(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.scheduleRead(generation: generation)
            }
        }
    }

    public func start() {
        guard !isRunning else { return }
        isRunning = true
        lifecycleGeneration &+= 1
        let generation = lifecycleGeneration

        startupTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if self.lifecycleGeneration == generation {
                    self.startupTask = nil
                }
            }

            await self.loadCatalogIfNeeded()
            guard self.isCurrent(generation) else { return }
            await self.read(generation: generation)
            guard self.isCurrent(generation) else { return }

            self.startTimer(generation: generation)
        }
    }

    public func stop() {
        isRunning = false
        lifecycleGeneration &+= 1
        startupTask?.cancel()
        startupTask = nil
        scheduledReadTask?.cancel()
        scheduledReadTask = nil
        timer?.invalidate()
        timer = nil
    }

    func readNow() async {
        await loadCatalogIfNeeded()
        await read()
    }

    func loadCatalogIfNeeded() async {
        if catalogLoaded { return }
        if let catalogTask {
            await catalogTask.value
            return
        }
        let task = Task { @MainActor [weak self] in
            guard let helper = BatteryManager.shared.getHelper() else { return }
            let keys = await helper.getAllSMCKeys()
            guard !keys.isEmpty else { return }
            let built = await Task.detached(priority: .utility) { Self.buildCatalog(from: keys) }.value
            guard let self else { return }
            self.catalog = built
            self.catalogLoaded = true
            self.onCatalog(built)
        }
        catalogTask = task
        await task.value
        catalogTask = nil
    }

    nonisolated private static func buildCatalog(from keys: [String]) -> [Sensor] {
        let availableKeys = Set(keys)
        var sensors: [Sensor] = []
        var seen: Set<String> = []

        for def in SENSORS_LIST where availableKeys.contains(def.key) && !seen.contains(def.key) {
            seen.insert(def.key)
            sensors.append(Sensor(key: def.key, name: def.name, value: 0, group: def.group, type: def.type))
        }

        for key in availableKeys where !seen.contains(key) {
            let type: SensorType?
            switch key.prefix(1) {
            case "T": type = .temperature
            case "V": type = .voltage
            case "P": type = .power
            case "I": type = .current
            default: type = nil
            }
            if let type {
                sensors.append(Sensor(key: key, name: key, value: 0, group: .unknown, type: type))
            }
        }

        return sensors.sorted { $0.name == $1.name ? $0.key < $1.key : $0.name < $1.name }
    }

    private func scheduleRead(generation: UInt) {
        guard isCurrent(generation), scheduledReadTask == nil else { return }
        scheduledReadTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if self.lifecycleGeneration == generation {
                    self.scheduledReadTask = nil
                }
            }
            await self.read(generation: generation)
        }
    }

    private func isCurrent(_ generation: UInt) -> Bool {
        isRunning && lifecycleGeneration == generation && !Task.isCancelled
    }

    private func read(generation: UInt? = nil) async {
        if let generation, !isCurrent(generation) { return }
        guard !readInFlight else { return }
        if !catalogLoaded { await loadCatalogIfNeeded() }
        guard catalogLoaded, let helper = BatteryManager.shared.getHelper() else { return }

        let wanted = catalog.filter { requestedKeys.contains($0.key) }
        guard !wanted.isEmpty else {
            onValues(Sensors_List())
            return
        }

        readInFlight = true
        defer { readInFlight = false }

        let values = await helper.getSensorValues(keys: wanted.map(\.key))
        if let generation, !isCurrent(generation) { return }

        let list = Sensors_List()
        list.sensors = wanted.compactMap { sensor -> (any Sensor_p)? in
            if let number = values[sensor.key] as? NSNumber {
                let value = number.doubleValue
                let plausible = value.isFinite && value >= 0 && !(sensor.type == .temperature && value < 10.0)
                if plausible { lastValues[sensor.key] = value }
            }
            guard let value = lastValues[sensor.key] else { return nil }
            var updated = sensor
            updated.value = value
            return updated
        }
        onValues(list)
    }
}

// MARK: - Battery Reader
internal class BatteryStatsReader: Reader<Battery_Usage> {
    private var service: io_service_t = 0

    override func setup() {
        lookUpServiceIfNeeded()
    }

    private func lookUpServiceIfNeeded() {
        guard service == 0 else { return }
        service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
    }

    deinit {
        if service != 0 { IOObjectRelease(service) }
    }

    override func read() {
        lookUpServiceIfNeeded()
        let psInfo = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let psList = IOPSCopyPowerSourcesList(psInfo).takeRetainedValue() as [CFTypeRef]
        if let ps = psList.first,
           let list = IOPSGetPowerSourceDescription(psInfo, ps).takeUnretainedValue() as? [String: Any] {

            let powerSource = list[kIOPSPowerSourceStateKey] as? String ?? "AC Power"
            let isCharging = list[kIOPSIsChargingKey] as? Bool ?? false
            let level = Double(list[kIOPSCurrentCapacityKey] as? Int ?? 0) / 100
            let timeToEmpty = list[kIOPSTimeToEmptyKey] as? Int ?? 0
            let timeToCharge = list[kIOPSTimeToFullChargeKey] as? Int ?? 0

            var amperage: Int = 0
            if let value = getIntValue("Amperage" as CFString) {
                amperage = value
            }

            var voltage: Double = 0
            if let value = getDoubleValue("Voltage" as CFString) {
                voltage = value / 1000.0
            }

            var power: Int = 0
            if let ACDetails = IOPSCopyExternalPowerAdapterDetails(), let ACList = ACDetails.takeRetainedValue() as? [String: Any] {
                if let watts = ACList[kIOPSPowerAdapterWattsKey] as? Int {
                    power = watts
                }
            }

            self.fireCallback(Battery_Usage(
                powerSource: powerSource,
                isCharging: isCharging,
                level: level,
                timeToEmpty: timeToEmpty,
                timeToCharge: timeToCharge,
                amperage: amperage,
                voltage: voltage,
                power: power
            ))
        }
        super.read()
    }

    private func getIntValue(_ identifier: CFString) -> Int? {
        guard service != 0 else { return nil }
        if let value = IORegistryEntryCreateCFProperty(self.service, identifier, kCFAllocatorDefault, 0) {
            return value.takeRetainedValue() as? Int
        }
        return nil
    }

    private func getDoubleValue(_ identifier: CFString) -> Double? {
        guard service != 0 else { return nil }
        if let value = IORegistryEntryCreateCFProperty(self.service, identifier, kCFAllocatorDefault, 0) {
            return value.takeRetainedValue() as? Double
        }
        return nil
    }
}