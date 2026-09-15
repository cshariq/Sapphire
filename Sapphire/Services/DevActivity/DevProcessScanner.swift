//
//  DevProcessScanner.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-12
//

import Darwin
import Foundation

struct DevProcess {
    let pid: pid_t
    let ppid: pid_t
    let shortName: String
    let startedAt: Date
    var executablePath: String
    var arguments: [String]

    var cpuPercent: Double = 0

    var executableName: String {
        executablePath.isEmpty ? shortName : (executablePath as NSString).lastPathComponent
    }

    var commandLine: String {
        arguments.isEmpty ? executablePath : arguments.joined(separator: " ")
    }

    var elapsed: TimeInterval { Date().timeIntervalSince(startedAt) }
}

nonisolated final class DevProcessScanner {

    private struct CacheKey: Hashable {
        let pid: pid_t
        let startMicroseconds: Int64
    }

    private struct CachedIdentity {
        let shortName: String
        let executablePath: String
        let arguments: [String]
    }

    private struct CPUSample {
        let cumulativeNanos: UInt64
        let timestamp: CFAbsoluteTime
    }

    private var identityCache: [CacheKey: CachedIdentity] = [:]
    private var cpuSamples: [CacheKey: CPUSample] = [:]
    private let uid = getuid()
    private lazy var argumentBuffer = [CChar](repeating: 0, count: argMax)
    private var argMax: Int = {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        var mib: [Int32] = [CTL_KERN, KERN_ARGMAX]
        guard sysctl(&mib, 2, &value, &size, nil, 0) == 0, value > 0 else { return 256 * 1024 }
        return Int(value)
    }()

    func scan() -> [pid_t: DevProcess] {
        guard let table = readProcessTable() else { return [:] }

        var result: [pid_t: DevProcess] = [:]
        result.reserveCapacity(table.count)
        var liveKeys = Set<CacheKey>()
        liveKeys.reserveCapacity(table.count)

        for entry in table {
            guard entry.kp_eproc.e_ucred.cr_uid == uid else { continue }

            let pid = entry.kp_proc.p_pid
            guard pid > 0 else { continue }

            let start = entry.kp_proc.p_un.__p_starttime
            let key = CacheKey(
                pid: pid,
                startMicroseconds: Int64(start.tv_sec) &* 1_000_000 &+ Int64(start.tv_usec)
            )
            liveKeys.insert(key)

            let shortName = Self.shortName(from: entry.kp_proc.p_comm)
            let identity: CachedIdentity
            if let cached = identityCache[key],
               cached.shortName == shortName,
               !cached.executablePath.isEmpty || !cached.arguments.isEmpty {
                identity = cached
            } else {
                identity = CachedIdentity(
                    shortName: shortName,
                    executablePath: Self.executablePath(for: pid),
                    arguments: arguments(for: pid)
                )
                identityCache[key] = identity
            }

            result[pid] = DevProcess(
                pid: pid,
                ppid: entry.kp_eproc.e_ppid,
                shortName: shortName,
                startedAt: Date(
                    timeIntervalSince1970: Double(start.tv_sec) + Double(start.tv_usec) / 1_000_000
                ),
                executablePath: identity.executablePath,
                arguments: identity.arguments
            )
        }

        let staleIdentityKeys = identityCache.keys.filter { !liveKeys.contains($0) }
        for key in staleIdentityKeys { identityCache.removeValue(forKey: key) }
        let staleSampleKeys = cpuSamples.keys.filter { !liveKeys.contains($0) }
        for key in staleSampleKeys { cpuSamples.removeValue(forKey: key) }

        return result
    }

    func sampleCPU(for pids: some Sequence<pid_t>, in processes: inout [pid_t: DevProcess]) {
        let now = CFAbsoluteTimeGetCurrent()

        for pid in pids {
            guard var process = processes[pid] else { continue }
            guard let cumulative = Self.cumulativeCPUNanos(for: pid) else { continue }

            let key = CacheKey(
                pid: pid,
                startMicroseconds: Int64((process.startedAt.timeIntervalSince1970 * 1_000_000).rounded())
            )
            if let previous = cpuSamples[key] {
                let wallSeconds = now - previous.timestamp
                if wallSeconds > 0.05, cumulative >= previous.cumulativeNanos {
                    let cpuSeconds = Double(cumulative - previous.cumulativeNanos) / 1_000_000_000
                    process.cpuPercent = (cpuSeconds / wallSeconds) * 100
                    processes[pid] = process
                }
            }
            cpuSamples[key] = CPUSample(cumulativeNanos: cumulative, timestamp: now)
        }
    }

    // MARK: - Kernel reads

    private func readProcessTable() -> [kinfo_proc]? {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        var size = 0
        guard sysctl(&mib, 4, nil, &size, nil, 0) == 0, size > 0 else { return nil }

        let stride = MemoryLayout<kinfo_proc>.stride
        var minimumBytes = size
        for attempt in 0..<3 {
            let extraEntries = 64 << attempt
            let capacity = max(1, minimumBytes / stride + extraEntries)
            var table = [kinfo_proc](repeating: kinfo_proc(), count: capacity)
            var actual = capacity * stride
            if sysctl(&mib, 4, &table, &actual, nil, 0) == 0 {
                return Array(table.prefix(actual / stride))
            }
            guard errno == ENOMEM else { return nil }
            minimumBytes = max(actual, capacity * stride)
        }
        return nil
    }

    private func arguments(for pid: pid_t) -> [String] {
        var size = argumentBuffer.count
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        guard sysctl(&mib, 3, &argumentBuffer, &size, nil, 0) == 0,
              size > MemoryLayout<Int32>.size else {
            return []
        }
        let buffer = argumentBuffer

        var argc: Int32 = 0
        memcpy(&argc, buffer, MemoryLayout<Int32>.size)
        guard argc > 0 else { return [] }

        return buffer.withUnsafeBufferPointer { pointer -> [String] in
            guard let base = pointer.baseAddress else { return [] }
            var cursor = MemoryLayout<Int32>.size

            while cursor < size, base[cursor] != 0 { cursor += 1 }
            while cursor < size, base[cursor] == 0 { cursor += 1 }

            var parsed: [String] = []
            parsed.reserveCapacity(Int(argc))
            while parsed.count < Int(argc), cursor < size {
                let argument = String(cString: base + cursor)
                parsed.append(argument)
                cursor += argument.utf8.count + 1
            }
            return parsed
        }
    }

    private static func executablePath(for pid: pid_t) -> String {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return "" }
        return String(cString: buffer)
    }

    static func workingDirectory(for pid: pid_t) -> String? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { return nil }

        let path = withUnsafeBytes(of: info.pvi_cdir.vip_path) { raw -> String in
            guard let base = raw.bindMemory(to: CChar.self).baseAddress else { return "" }
            return String(cString: base)
        }
        return path.isEmpty ? nil : path
    }

    private static func cumulativeCPUNanos(for pid: pid_t) -> UInt64? {
        var info = proc_taskinfo()
        let size = Int32(MemoryLayout<proc_taskinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, size) == size else { return nil }
        return info.pti_total_user &+ info.pti_total_system
    }

    private static func shortName(from comm: CommTuple) -> String {
        withUnsafeBytes(of: comm) { raw in
            guard let base = raw.bindMemory(to: CChar.self).baseAddress else { return "" }
            return String(cString: base)
        }
    }

    private typealias CommTuple = (
        CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
        CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar
    )
}