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
        get { Double((self.total - self.free) / self.total) }
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
    let result = IOServiceGetMatchingServices(kIOMasterPortDefault, IOServiceMatching(name), &iterator)
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
    let sensor: Sensor_p

    private enum CodingKeys: String, CodingKey {
        case base, payload
    }
    private enum SensorTyp: Int, Codable {
        case sensor, fan
    }

    init(_ sensor: Sensor_p) {
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
    public var sensors: [Sensor_p] = []

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
    @Published public private(set) var allSensors: [Sensor_p] = []

    private lazy var cpuReader: CPUUsageReader = CPUUsageReader { [weak self] value in self?.cpu = value }
    private lazy var ramReader: RAMUsageReader = RAMUsageReader { [weak self] value in self?.ram = value }
    private lazy var gpuReader: GPUInfoReader = GPUInfoReader { [weak self] value in self?.gpus = value ?? GPUs() }
    private lazy var diskReader: DiskActivityReader = DiskActivityReader { [weak self] value in self?.disks = value ?? Disks() }
    private lazy var sensorsReader: SensorsStatsReader = SensorsStatsReader { [weak self] value in self?.sensors = value ?? Sensors_List() }
    private lazy var batteryReader: BatteryStatsReader = BatteryStatsReader { [weak self] value in self?.battery = value }

    private var cpu: CPU_Load? { didSet { updatePayload() } }
    private var ram: RAM_Usage? { didSet { updatePayload() } }
    private var gpus = GPUs() { didSet { updatePayload() } }
    private var disks = Disks() { didSet { updatePayload() } }
    private var sensors = Sensors_List() { didSet {
        self.allSensors = sensors.sensors.sorted(by: { $0.name < $1.name })
        updatePayload()
    }}
    private var battery: Battery_Usage? { didSet { updatePayload() } }

    private var pollingRequesters: [String: Set<StatType>] = [:]

    private var settingsCancellable: AnyCancellable?
    private let settingsModel = SettingsModel.shared

    private init() {
        self.settingsCancellable = settingsModel.$settings
            .debounce(for: .milliseconds(250), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updatePollingBasedOnSettings()
            }
    }

    private func updatePollingBasedOnSettings() {
        let settings = self.settingsModel.settings
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

        self.setPolling(for: "LiveActivitySettings", requiredStats: requiredStats)
    }

    public func setPolling(for requester: String, requiredStats: Set<StatType>) {
        if requiredStats.isEmpty {
            pollingRequesters.removeValue(forKey: requester)
        } else {
            pollingRequesters[requester] = requiredStats
        }
        updatePollingState()
    }

    private func updatePollingState() {
        let activeStats = pollingRequesters.values.reduce(Set<StatType>()) { $0.union($1) }
        update(reader: cpuReader, for: .cpu, in: activeStats)
        update(reader: ramReader, for: .ram, in: activeStats)
        update(reader: gpuReader, for: .gpu, in: activeStats)
        update(reader: diskReader, for: .disk, in: activeStats)

        let needsPowerStats = activeStats.contains(.systemPower) || activeStats.contains(.batteryPower)
        update(reader: sensorsReader, for: .systemPower, in: activeStats, force: needsPowerStats)
        update(reader: batteryReader, for: .batteryPower, in: activeStats, force: needsPowerStats)
    }

    private func update<R: Reader<T>, T>(reader: R, for statType: StatType, in activeStats: Set<StatType>, force: Bool = false) {
        if activeStats.contains(statType) || force {
            reader.start()
        } else {
            reader.stop()
        }
    }

    private func update(reader: SensorsStatsReader, for statType: StatType, in activeStats: Set<StatType>, force: Bool = false) {
        if activeStats.contains(statType) || force {
            reader.start()
        } else {
            reader.stop()
        }
    }

    private func updatePayload() {
        let primaryDisk = disks.array.first(where: { $0.root }) ?? disks.array.first
        let activeGPUs = gpus.list.filter{ $0.state && $0.utilization != nil }.sorted{ $0.utilization ?? 0 > $1.utilization ?? 0 }
        let primaryGPU = activeGPUs.first

        self.currentStats = StatsPayload(
            cpu: self.cpu,
            ram: self.ram,
            disk: primaryDisk,
            gpu: primaryGPU,
            sensors: self.sensors,
            battery: self.battery
        )
    }
}

// MARK: - Base Reader Class
internal class Reader<T> {
    public var active: Bool = false
    internal var interval: DispatchTimeInterval
    internal let callback: (T?) -> Void
    private let queue: DispatchQueue
    private let readerName: String

    init(interval: DispatchTimeInterval = .seconds(1), callback: @escaping (T?) -> Void) {
        self.interval = interval
        self.callback = callback
        self.readerName = String(describing: T.self)
        self.queue = DispatchQueue(label: "com.shariq.sapphire.reader.\(readerName)", qos: .default)
    }

    public func start() {
        guard !self.active else { return }
        self.active = true
        self.queue.async {
            self.setup()
            self.read()
        }
    }

    public func stop() {
        guard self.active else { return }
        self.active = false
    }

    @objc func read() {
        guard self.active else { return }

        self.queue.asyncAfter(deadline: .now() + self.interval) { [weak self] in
            self?.read()
        }
    }

    public func setup() {}

    internal func fireCallback(_ value: T?) {
        DispatchQueue.main.async {
            self.callback(value)
        }
    }
}

// MARK: - CPU Readers
internal class CPUUsageReader: Reader<CPU_Load> {
    private var prevCpuInfo: processor_info_array_t?
    private var numPrevCpuInfo: mach_msg_type_number_t = 0
    private var numCPUs: uint = 0
    private let CPUUsageLock: NSLock = NSLock()
    private var previousInfo = host_cpu_load_info()
    private var numCPUsU: natural_t = 0

    override func setup() {
        [CTL_HW, HW_NCPU].withUnsafeBufferPointer { mib in
            var sizeOfNumCPUs: size_t = MemoryLayout<uint>.size
            let status = sysctl(processor_info_array_t(mutating: mib.baseAddress), 2, &numCPUs, &sizeOfNumCPUs, nil, 0)
            if status != 0 { self.numCPUs = 1 }
        }
    }

    override func read() {
        var newResponse = CPU_Load()

        var localCpuInfo: processor_info_array_t?
        var localNumCpuInfo: mach_msg_type_number_t = 0

        let result: kern_return_t = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &self.numCPUsU, &localCpuInfo, &localNumCpuInfo)

        if result == KERN_SUCCESS, let currentCpuInfo = localCpuInfo {
            CPUUsageLock.lock()

            var usagePerCore: [Double] = []
            for i in 0 ..< Int32(numCPUs) {
                var inUse: Int32, total: Int32
                if let prev = prevCpuInfo {
                    inUse = (currentCpuInfo[Int(CPU_STATE_MAX * i + CPU_STATE_USER)] - prev[Int(CPU_STATE_MAX * i + CPU_STATE_USER)])
                        + (currentCpuInfo[Int(CPU_STATE_MAX * i + CPU_STATE_SYSTEM)] - prev[Int(CPU_STATE_MAX * i + CPU_STATE_SYSTEM)])
                        + (currentCpuInfo[Int(CPU_STATE_MAX * i + CPU_STATE_NICE)] - prev[Int(CPU_STATE_MAX * i + CPU_STATE_NICE)])
                    total = inUse + (currentCpuInfo[Int(CPU_STATE_MAX * i + CPU_STATE_IDLE)] - prev[Int(CPU_STATE_MAX * i + CPU_STATE_IDLE)])
                } else {
                    inUse = currentCpuInfo[Int(CPU_STATE_MAX * i + CPU_STATE_USER)] + currentCpuInfo[Int(CPU_STATE_MAX * i + CPU_STATE_SYSTEM)] + currentCpuInfo[Int(CPU_STATE_MAX * i + CPU_STATE_NICE)]
                    total = inUse + currentCpuInfo[Int(CPU_STATE_MAX * i + CPU_STATE_IDLE)]
                }

                if total > 0 {
                    let coreUsage = Double(inUse) / Double(total)
                    usagePerCore.append( (coreUsage >= 0 && coreUsage <= 1.0) ? coreUsage : 0.0 )
                } else {
                    usagePerCore.append(0.0)
                }
            }
            newResponse.usagePerCore = usagePerCore

            CPUUsageLock.unlock()

            if let prev = prevCpuInfo {
                vm_deallocate(mach_task_self_, vm_address_t(bitPattern: prev), vm_size_t(MemoryLayout<integer_t>.stride * Int(numPrevCpuInfo)))
            }

            prevCpuInfo = localCpuInfo
            numPrevCpuInfo = localNumCpuInfo

        } else if let localCpuInfo = localCpuInfo {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: localCpuInfo), vm_size_t(MemoryLayout<integer_t>.stride * Int(localNumCpuInfo)))
        }

        if let cpuInfo = hostCPULoadInfo() {
            let userDiff = Double(cpuInfo.cpu_ticks.0 - previousInfo.cpu_ticks.0)
            let sysDiff  = Double(cpuInfo.cpu_ticks.1 - previousInfo.cpu_ticks.1)
            let idleDiff = Double(cpuInfo.cpu_ticks.2 - previousInfo.cpu_ticks.2)
            let niceDiff = Double(cpuInfo.cpu_ticks.3 - previousInfo.cpu_ticks.3)
            let totalTicks = sysDiff + userDiff + niceDiff + idleDiff

            guard totalTicks > 0 else {
                super.read()
                return
            }

            newResponse.systemLoad = sysDiff / totalTicks
            newResponse.userLoad = userDiff / totalTicks
            newResponse.idleLoad = idleDiff / totalTicks
            newResponse.totalUsage = newResponse.systemLoad + newResponse.userLoad
            previousInfo = cpuInfo

            guard newResponse.totalUsage >= 0 && newResponse.totalUsage <= 1.0 else {
                super.read()
                return
            }

            self.fireCallback(newResponse)
        }

        super.read()
    }

    private func hostCPULoadInfo() -> host_cpu_load_info? {
        let count = MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride
        var size = mach_msg_type_number_t(count)
        var cpuLoadInfo = host_cpu_load_info()

        let result: kern_return_t = withUnsafeMutablePointer(to: &cpuLoadInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: count) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &size)
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
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_info(mach_host_self(), HOST_BASIC_INFO, $0, &count)
            }
        }
        if kerr == KERN_SUCCESS { self.totalSize = Double(stats.max_mem) }
    }

    override func read() {
        var stats = vm_statistics64()
        var count = UInt32(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result: kern_return_t = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }

        if result == KERN_SUCCESS {
            let active = Double(stats.active_count) * Double(vm_page_size)
            let inactive = Double(stats.inactive_count) * Double(vm_page_size)
            let wired = Double(stats.wire_count) * Double(vm_page_size)
            let compressed = Double(stats.compressor_page_count) * Double(vm_page_size)
            let speculative = Double(stats.speculative_count) * Double(vm_page_size)
            let purgeable = Double(stats.purgeable_count) * Double(vm_page_size)
            let external = Double(stats.external_page_count) * Double(vm_page_size)

            let used = active + inactive + speculative + wired + compressed - purgeable - external

            var pressureLevel: Int = 0
            var size: size_t = MemoryLayout<uint>.size
            sysctlbyname("kern.memorystatus_vm_pressure_level", &pressureLevel, &size, nil, 0)
            let pressure: RAMPressure = {
                switch pressureLevel {
                case 2: return .warning
                case 4: return .critical
                default: return .normal
                }
            }()

            var swap: xsw_usage = xsw_usage()
            size = MemoryLayout<xsw_usage>.size
            sysctlbyname("vm.swapusage", &swap, &size, nil, 0)

            self.fireCallback(RAM_Usage(
                total: self.totalSize, used: used, free: self.totalSize - used,
                active: active, inactive: inactive, wired: wired, compressed: compressed,
                app: used - wired - compressed, cache: purgeable + external,
                swap: Swap(total: Double(swap.xsu_total), used: Double(swap.xsu_used), free: Double(swap.xsu_avail)),
                pressure: Pressure(level: pressureLevel, value: pressure)
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
        self.fireCallback(gpus)
        super.read()
    }
}

// MARK: - Disk Reader
internal class DiskActivityReader: Reader<Disks> {
    private var list: Disks = Disks()

    override func read() {
        let keys: [URLResourceKey] = [.volumeNameKey]
        let paths = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []

        guard let session = DASessionCreate(kCFAllocatorDefault) else {
            super.read()
            return
        }

        var active: [String] = []
        for url in paths {
            if url.pathComponents.count == 1 || (url.pathComponents.count > 1 && url.pathComponents[1] == "Volumes") {
                if let disk = DADiskCreateFromVolumePath(kCFAllocatorDefault, session, url as CFURL), let diskName = DADiskGetBSDName(disk) {
                    let BSDName: String = String(cString: diskName)
                    active.append(BSDName)

                    if let idx = self.list.array.firstIndex(where: { $0.BSDName == BSDName }) {
                        var d = self.list.array[idx]
                        driveStats(d: &d)
                        self.list.array[idx] = d
                    } else if var d = driveDetails(disk, bsdName: BSDName) {
                        driveStats(d: &d)
                        list.array.append(d)
                    }
                }
            }
        }

        list.array = list.array.filter { active.contains($0.BSDName) }

        self.fireCallback(list)
        super.read()
    }

    private func driveStats(d: inout drive) {
        guard d.parent != 0, let props = getIOProperties(d.parent) else { return }

        if let statistics = props.object(forKey: "Statistics") as? NSDictionary {
            let readBytes = statistics.object(forKey: "Bytes (Read)") as? Int64 ?? 0
            let writeBytes = statistics.object(forKey: "Bytes (Write)") as? Int64 ?? 0

            if d.activity.readBytes != 0 {
                d.activity.read = readBytes - d.activity.readBytes
            }
            if d.activity.writeBytes != 0 {
                d.activity.write = writeBytes - d.activity.writeBytes
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
                    let resources = try path.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityKey])
                    d.size = Int64(resources.volumeTotalCapacity ?? 1)
                    d.free = Int64(resources.volumeAvailableCapacity ?? 0)
                } catch { return nil }
            }
        }

        let partitionLevel = d.BSDName.filter { "0"..."9" ~= $0 }.count
        if let parent = getDeviceIOParent(DADiskCopyIOMedia(disk), level: Int(partitionLevel)) {
            d.parent = parent
        }

        return d.path != nil ? d : nil
    }

    private func getDeviceIOParent(_ obj: io_registry_entry_t, level: Int) -> io_registry_entry_t? {
        var parent: io_registry_entry_t = 0
        guard IORegistryEntryGetParentEntry(obj, kIOServicePlane, &parent) == KERN_SUCCESS else { return nil }

        for _ in 1...level where IORegistryEntryGetParentEntry(parent, kIOServicePlane, &parent) != KERN_SUCCESS {
            IOObjectRelease(parent)
            return nil
        }

        return parent
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
internal class SensorsStatsReader {
    private var timer: Timer?
    internal let callback: (Sensors_List?) -> Void
    private var list: Sensors_List = Sensors_List()
    private var initialized: Bool = false

    init(callback: @escaping (Sensors_List?) -> Void) {
        self.callback = callback
    }

    @MainActor
    public func start() {
        guard self.timer == nil else { return }
        Task {
            if !self.initialized {
                await self.initializeSensors()
                self.initialized = true
            }
            await self.read()

            self.timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
                Task {
                    await self?.read()
                }
            }
        }
    }

    public func stop() {
        guard self.timer != nil else { return }
        self.timer?.invalidate()
        self.timer = nil
    }

    private func initializeSensors() async {
        guard let helper = BatteryManager.shared.getHelper() else { return }

        let availableKeys = Set(await helper.getAllSMCKeys())
        var sensors: [Sensor_p] = []

        SENSORS_LIST.forEach { def in
            if availableKeys.contains(def.key) {
                sensors.append(Sensor(key: def.key, name: def.name, value: 0, group: def.group, type: def.type))
            }
        }

        availableKeys.forEach { key in
            if !sensors.contains(where: { $0.key == key }) {
                if SENSORS_LIST.first(where: { $0.key == key }) == nil {
                    var type: SensorType?
                    switch key.prefix(1) {
                    case "T": type = .temperature
                    case "V": type = .voltage
                    case "P": type = .power
                    case "I": type = .current
                    default: break
                    }
                    if let type = type {
                        sensors.append(Sensor(key: key, name: key, value: 0, group: .unknown, type: type))
                    }
                }
            }
        }

        self.list.sensors = sensors.sorted(by: { $0.name < $1.name })
    }

    private func read() async {
        guard initialized, let helper = BatteryManager.shared.getHelper() else { return }

        var updatedSensors = self.list.sensors
        for i in updatedSensors.indices {
            let key = updatedSensors[i].key
            let newValue = await helper.getSensorValue(key: key)

            if newValue >= 0 {
                if updatedSensors[i].type == .temperature && newValue < 10.0 {
                    continue
                }
                updatedSensors[i].value = newValue
            }
        }

        self.list.sensors = updatedSensors

        DispatchQueue.main.async {
            self.callback(self.list)
        }
    }
}

// MARK: - Battery Reader
internal class BatteryStatsReader: Reader<Battery_Usage> {
    private var service: io_connect_t = 0

    override func setup() {
        service = IOServiceGetMatchingService(kIOMasterPortDefault, IOServiceMatching("AppleSmartBattery"))
    }

    override func read() {
        let psInfo = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        if let psList = IOPSCopyPowerSourcesList(psInfo).takeRetainedValue() as? [CFTypeRef],
           let ps = psList.first,
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
        if let value = IORegistryEntryCreateCFProperty(self.service, identifier, kCFAllocatorDefault, 0) {
            return value.takeRetainedValue() as? Int
        }
        return nil
    }

    private func getDoubleValue(_ identifier: CFString) -> Double? {
        if let value = IORegistryEntryCreateCFProperty(self.service, identifier, kCFAllocatorDefault, 0) {
            return value.takeRetainedValue() as? Double
        }
        return nil
    }
}