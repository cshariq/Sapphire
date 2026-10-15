//
//  EnergyReader.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-11-08.
//

import Foundation
import AppKit
import Darwin

struct TopProcess: Identifiable, Equatable {
    var id: Int { pid }
    let pid: Int
    let name: String
    let usage: Double
}

final class EnergyReader {
    private static let interval: TimeInterval = 5
    private static let resultLimit = 3
    private static let minimumUsagePercent = 0.5

    private struct ProcessSample {
        let cpuTime: UInt64
        let energy: UInt64
        let startTime: UInt64
    }

    private let callback: ([TopProcess]) -> Void
    private let queue = DispatchQueue(label: "com.shariq.sapphire.energy-reader", qos: .utility)
    private var timer: DispatchSourceTimer?

    private var previous: [pid_t: ProcessSample] = [:]
    private var previousUptime: TimeInterval?
    private var sampling = false
    private var generation: UInt = 0
    private var nameCache: [String: String] = [:]

    init(callback: @escaping ([TopProcess]) -> Void) {
        self.callback = callback
    }

    deinit {
        timer?.cancel()
    }

    private let runningLock = NSLock()
    private var running = false
    private var isRunning: Bool { runningLock.withLock { running } }

    func start() {
        runningLock.withLock { running = true }
        queue.async { [weak self] in
            guard let self, self.timer == nil else { return }
            self.generation &+= 1
            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now(), repeating: Self.interval, leeway: .seconds(1))
            timer.setEventHandler { [weak self] in self?.sample() }
            timer.resume()
            self.timer = timer
        }
    }

    func stop() {
        runningLock.withLock { running = false }
        queue.async { [weak self] in
            guard let self else { return }
            self.generation &+= 1
            self.timer?.cancel()
            self.timer = nil
            self.previous.removeAll()
            self.previousUptime = nil
        }
    }

    // MARK: - Sampling

    private func sample() {
        guard !sampling else { return }
        sampling = true
        defer { sampling = false }
        let generation = self.generation

        let uptime = ProcessInfo.processInfo.systemUptime
        let current = Self.readAllProcesses()
        defer {
            previous = current
            previousUptime = uptime
        }
        guard let previousUptime, uptime > previousUptime else { return }
        let elapsedNanos = (uptime - previousUptime) * 1_000_000_000

        var cpuByOwner: [pid_t: UInt64] = [:]
        var energyByOwner: [pid_t: UInt64] = [:]
        for (pid, now) in current {
            guard let before = previous[pid], before.startTime == now.startTime,
                  now.cpuTime >= before.cpuTime else { continue }
            let owner = Self.responsiblePID(for: pid)
            cpuByOwner[owner, default: 0] += now.cpuTime - before.cpuTime
            energyByOwner[owner, default: 0] += now.energy >= before.energy ? now.energy - before.energy : 0
        }

        struct Ranked {
            let pid: pid_t
            let usage: Double
            let energy: UInt64
        }
        var candidates: [Ranked] = []
        for (owner, cpuNanos) in cpuByOwner where owner > 0 {
            let usage = Double(cpuNanos) / elapsedNanos * 100
            guard usage >= Self.minimumUsagePercent else { continue }
            candidates.append(Ranked(pid: owner, usage: usage, energy: energyByOwner[owner] ?? 0))
        }
        candidates.sort { lhs, rhs in
            lhs.usage == rhs.usage ? lhs.energy > rhs.energy : lhs.usage > rhs.usage
        }
        let ranked = candidates.prefix(Self.resultLimit)

        let processes = ranked.map {
            TopProcess(pid: Int($0.pid), name: displayName(for: $0.pid), usage: $0.usage)
        }

        guard self.generation == generation, timer != nil else { return }
        let callback = self.callback
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isRunning else { return }
            callback(processes)
        }
    }

    private static let timebase: (numer: UInt64, denom: UInt64) = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return (UInt64(max(info.numer, 1)), UInt64(max(info.denom, 1)))
    }()

    private static func readAllProcesses() -> [pid_t: ProcessSample] {
        let capacity = Int(proc_listallpids(nil, 0))
        guard capacity > 0 else { return [:] }
        var pids = [pid_t](repeating: 0, count: capacity + 64)
        let count = pids.withUnsafeMutableBytes { buffer in
            Int(proc_listallpids(buffer.baseAddress, Int32(buffer.count)))
        }
        guard count > 0 else { return [:] }

        var samples: [pid_t: ProcessSample] = [:]
        samples.reserveCapacity(count)
        for pid in pids.prefix(min(count, pids.count)) where pid > 0 {
            var info = rusage_info_v6()
            let result = withUnsafeMutablePointer(to: &info) { pointer in
                pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                    proc_pid_rusage(pid, RUSAGE_INFO_V6, $0)
                }
            }
            guard result == 0 else { continue }
            let ticks = info.ri_user_time &+ info.ri_system_time
            let nanos = ticks.multipliedFullWidth(by: timebase.numer)
            let cpuTime = timebase.denom.dividingFullWidth(nanos).quotient
            samples[pid] = ProcessSample(cpuTime: cpuTime, energy: info.ri_energy_nj, startTime: info.ri_proc_start_abstime)
        }
        return samples
    }

    // MARK: - Attribution

    private typealias ResponsibilityFunction = @convention(c) (pid_t) -> pid_t

    private static let responsibilityFunction: ResponsibilityFunction? = {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "responsibility_get_pid_responsible_for_pid") else {
            return nil
        }
        return unsafeBitCast(symbol, to: ResponsibilityFunction.self)
    }()

    private static func responsiblePID(for pid: pid_t) -> pid_t {
        guard let responsibilityFunction else { return pid }
        let owner = responsibilityFunction(pid)
        return owner > 0 ? owner : pid
    }

    private func displayName(for pid: pid_t) -> String {
        var pathBuffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        let length = proc_pidpath(pid, &pathBuffer, UInt32(pathBuffer.count))
        guard length > 0 else { return Self.processName(pid) ?? "Process \(pid)" }
        let path = String(cString: pathBuffer)
        if let cached = nameCache[path] { return cached }

        var name = (path as NSString).lastPathComponent
        if let range = path.range(of: ".app/") {
            let outermost = String(path[..<range.lowerBound]) + ".app"
            if let bundle = Bundle(path: outermost) {
                name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                    ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
                    ?? ((outermost as NSString).lastPathComponent as NSString).deletingPathExtension
            }
        }
        if nameCache.count > 512 { nameCache.removeAll() }
        nameCache[path] = name
        return name
    }

    private static func processName(_ pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 256)
        guard proc_name(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        let name = String(cString: buffer)
        return name.isEmpty ? nil : name
    }
}