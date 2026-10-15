//
//  DevTaskInspector.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-10-15
//

import AppKit
import Darwin
import Foundation

struct DevProcessSnapshot: Identifiable, Equatable {
    let pid: pid_t
    let name: String
    let commandLine: String
    let depth: Int
    var cpuPercent: Double?
    var residentBytes: UInt64

    var id: pid_t { pid }
}

struct DevTerminalHost: Equatable {
    let pid: pid_t
    let name: String
    let bundleIdentifier: String?
    let appURL: URL?

    var kind: DevTerminalKind { DevTerminalKind(bundleIdentifier: bundleIdentifier) }

    var isEditor: Bool {
        guard let path = appURL?.path.lowercased() else { return false }
        return DevToolCatalog.editorTerminalPathFragments.contains { (path + "/").contains($0) }
    }
}

enum DevTerminalKind: Equatable {
    case appleTerminal
    case iTerm
    case other

    init(bundleIdentifier: String?) {
        switch bundleIdentifier?.lowercased() {
        case "com.apple.terminal": self = .appleTerminal
        case "com.googlecode.iterm2": self = .iTerm
        default: self = .other
        }
    }

    var isScriptable: Bool { self != .other }
}

struct DevTaskDetail: Equatable {
    let taskID: String
    let pid: pid_t
    var commandLine: String
    var workingDirectory: String?
    var ttyPath: String?
    var foregroundProcessGroup: pid_t?
    var host: DevTerminalHost?
    var processes: [DevProcessSnapshot]
    var agent: DevAgentSnapshot?
    var terminalOutput: String?
    var isAlive: Bool

    var totalCPU: Double { processes.compactMap(\.cpuPercent).reduce(0, +) }
    var totalResidentBytes: UInt64 { processes.reduce(0) { $0 + $1.residentBytes } }
}

nonisolated enum DevProcessInspection {

    struct BSDInfo {
        let ppid: pid_t
        let processGroup: pid_t
        let terminalProcessGroup: pid_t
        let ttyDevice: dev_t
        let name: String
    }

    static func bsdInfo(for pid: pid_t) -> BSDInfo? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        let name = withUnsafeBytes(of: info.pbi_name) { raw -> String in
            guard let base = raw.bindMemory(to: CChar.self).baseAddress else { return "" }
            return String(cString: base)
        }
        let comm = withUnsafeBytes(of: info.pbi_comm) { raw -> String in
            guard let base = raw.bindMemory(to: CChar.self).baseAddress else { return "" }
            return String(cString: base)
        }
        return BSDInfo(
            ppid: pid_t(info.pbi_ppid),
            processGroup: pid_t(info.pbi_pgid),
            terminalProcessGroup: pid_t(info.e_tpgid),
            ttyDevice: dev_t(bitPattern: info.e_tdev),
            name: name.isEmpty ? comm : name
        )
    }

    static func isAlive(_ pid: pid_t) -> Bool {
        pid > 0 && (kill(pid, 0) == 0 || errno == EPERM)
    }

    static func children(of pid: pid_t) -> [pid_t] {
        var capacity = 64
        while capacity <= 8192 {
            var buffer = [pid_t](repeating: 0, count: capacity)
            let bytes = buffer.withUnsafeMutableBytes { raw in
                proc_listpids(UInt32(PROC_PPID_ONLY), UInt32(pid), raw.baseAddress, Int32(raw.count))
            }
            guard bytes > 0 else { return [] }
            let count = Int(bytes) / MemoryLayout<pid_t>.size
            if count < capacity { return buffer.prefix(count).filter { $0 > 0 } }
            capacity *= 4
        }
        return []
    }

    static func executablePath(for pid: pid_t) -> String {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return "" }
        return String(cString: buffer)
    }

    static func arguments(for pid: pid_t) -> [String] {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return [] }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return [] }

        let argc = buffer.withUnsafeBytes { $0.load(as: Int32.self) }
        guard argc > 0 else { return [] }
        var cursor = MemoryLayout<Int32>.size
        while cursor < size, buffer[cursor] != 0 { cursor += 1 }
        while cursor < size, buffer[cursor] == 0 { cursor += 1 }

        var parsed: [String] = []
        while parsed.count < Int(argc), cursor < size {
            var end = cursor
            while end < size, buffer[end] != 0 { end += 1 }
            parsed.append(String(decoding: buffer[cursor..<end], as: UTF8.self))
            cursor = end + 1
        }
        return parsed
    }

    static func commandLine(for pid: pid_t) -> String {
        let arguments = arguments(for: pid)
        guard !arguments.isEmpty else { return executablePath(for: pid) }
        return arguments.map(quoteIfNeeded).joined(separator: " ")
    }

    private static func quoteIfNeeded(_ argument: String) -> String {
        guard argument.contains(where: { $0.isWhitespace || $0 == "\"" }) else { return argument }
        return "'" + argument.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func ttyPath(for device: dev_t) -> String? {
        guard device != DevProcess.noDevice, device != 0 else { return nil }
        guard let name = devname(device, S_IFCHR) else { return nil }
        let value = String(cString: name)
        guard !value.isEmpty, value != "??" else { return nil }
        return "/dev/" + value
    }

    struct TaskUsage {
        let cumulativeNanos: UInt64
        let residentBytes: UInt64
    }

    static func usage(for pid: pid_t) -> TaskUsage? {
        var info = proc_taskinfo()
        let size = Int32(MemoryLayout<proc_taskinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, size) == size else { return nil }
        return TaskUsage(
            cumulativeNanos: info.pti_total_user &+ info.pti_total_system,
            residentBytes: info.pti_resident_size
        )
    }

    static func terminalHost(above pid: pid_t) -> DevTerminalHost? {
        var current = bsdInfo(for: pid)?.ppid ?? 0
        var hops = 0
        while current > 1, hops < 40 {
            let path = executablePath(for: current)
            if !path.isEmpty {
                let process = DevProcess(
                    pid: current,
                    ppid: 0,
                    shortName: (path as NSString).lastPathComponent,
                    startedAt: Date(),
                    executablePath: path,
                    arguments: []
                )
                if DevToolCatalog.isTerminalHost(DevMatchSubject(process)) {
                    return host(pid: current, executablePath: path)
                }
            }
            guard let parent = bsdInfo(for: current)?.ppid, parent != current else { break }
            current = parent
            hops += 1
        }
        return nil
    }

    private static func host(pid: pid_t, executablePath path: String) -> DevTerminalHost {
        let running = NSRunningApplication(processIdentifier: pid)
        var bundleURL = running?.bundleURL
        if bundleURL == nil, let range = path.range(of: ".app/", options: .caseInsensitive) {
            bundleURL = URL(fileURLWithPath: String(path[..<path.index(range.lowerBound, offsetBy: 4)]))
        }
        let bundleID = running?.bundleIdentifier ?? bundleURL.flatMap { Bundle(url: $0)?.bundleIdentifier }
        let name = running?.localizedName
            ?? DevToolCatalog.hostDisplayName(forPath: path)
            ?? (path as NSString).lastPathComponent
        let appPID = bundleID.flatMap { NSRunningApplication.runningApplications(withBundleIdentifier: $0).first?.processIdentifier } ?? pid
        return DevTerminalHost(pid: appPID, name: name, bundleIdentifier: bundleID, appURL: bundleURL)
    }
}

nonisolated final class DevTaskInspector: @unchecked Sendable {

    private struct Sample {
        let nanos: UInt64
        let time: CFAbsoluteTime
    }

    private var samples: [pid_t: Sample] = [:]
    private var hostCache: [pid_t: DevTerminalHost?] = [:]
    private let lock = NSLock()

    func inspect(_ task: DevTask, includeTerminalOutput: Bool) -> DevTaskDetail {
        let pid = task.pid
        let alive = DevProcessInspection.isAlive(pid)
        let info = DevProcessInspection.bsdInfo(for: pid)
        let workingDirectory = DevProcessScanner.workingDirectory(for: pid)

        let host: DevTerminalHost?
        lock.lock()
        let cachedHost = hostCache[pid]
        lock.unlock()
        if let cachedHost {
            host = cachedHost
        } else {
            host = alive ? DevProcessInspection.terminalHost(above: pid) : nil
            lock.lock()
            if hostCache.count > 64 { hostCache.removeAll() }
            hostCache[pid] = host
            lock.unlock()
        }

        let tty = info.flatMap { DevProcessInspection.ttyPath(for: $0.ttyDevice) }
        var detail = DevTaskDetail(
            taskID: task.id,
            pid: pid,
            commandLine: DevProcessInspection.commandLine(for: pid),
            workingDirectory: workingDirectory,
            ttyPath: tty,
            foregroundProcessGroup: info.map(\.terminalProcessGroup).flatMap { $0 > 0 ? $0 : nil },
            host: host,
            processes: alive ? processTree(root: pid) : [],
            agent: nil,
            terminalOutput: nil,
            isAlive: alive
        )

        if task.kind == .ai {
            detail.agent = DevAgentTranscript.snapshot(
                toolID: task.tool.id,
                pid: pid,
                workingDirectory: workingDirectory
            )
        }

        if includeTerminalOutput, let tty, let host, host.kind.isScriptable {
            detail.terminalOutput = DevTerminalBridge.readOutput(host: host, tty: tty)
        }
        return detail
    }

    private func processTree(root: pid_t) -> [DevProcessSnapshot] {
        let now = CFAbsoluteTimeGetCurrent()
        var result: [DevProcessSnapshot] = []
        var queue: [(pid_t, Int)] = [(root, 0)]
        var seen = Set<pid_t>()
        var nextSamples: [pid_t: Sample] = [:]

        lock.lock()
        let previous = samples
        lock.unlock()

        while !queue.isEmpty, result.count < 40 {
            let (pid, depth) = queue.removeFirst()
            guard seen.insert(pid).inserted else { continue }
            let usage = DevProcessInspection.usage(for: pid)
            var cpu: Double?
            if let usage {
                nextSamples[pid] = Sample(nanos: usage.cumulativeNanos, time: now)
                if let last = previous[pid], now > last.time, usage.cumulativeNanos >= last.nanos {
                    cpu = Double(usage.cumulativeNanos - last.nanos) / ((now - last.time) * 1_000_000_000) * 100
                }
            }
            let path = DevProcessInspection.executablePath(for: pid)
            let name = path.isEmpty
                ? (DevProcessInspection.bsdInfo(for: pid)?.name ?? "\(pid)")
                : (path as NSString).lastPathComponent
            result.append(
                DevProcessSnapshot(
                    pid: pid,
                    name: name,
                    commandLine: DevProcessInspection.commandLine(for: pid),
                    depth: depth,
                    cpuPercent: cpu,
                    residentBytes: usage?.residentBytes ?? 0
                )
            )
            for child in DevProcessInspection.children(of: pid) {
                queue.append((child, depth + 1))
            }
        }

        lock.lock()
        samples = samples.filter { now - $0.value.time < 30 }.merging(nextSamples) { $1 }
        lock.unlock()
        return result
    }
}