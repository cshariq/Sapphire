//
//  DevActivityScanEngine.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-12
//

import Darwin
import Foundation

nonisolated final class DevActivityScanEngine: @unchecked Sendable {

    struct Configuration {
        var enabledKinds: Set<String>
        var sensitivity: Double
        var includeIDEAgents: Bool
        var minimumCommandDuration: TimeInterval = 4
    }

    private let scanner = DevProcessScanner()

    private struct Traits {
        let executablePath: String
        let argumentCount: Int
        let rule: DevToolRule?
        let isCommandCandidate: Bool
        let isTerminalHost: Bool
    }

    private struct TraitsKey: Hashable {
        let pid: pid_t
        let startedAt: Date
    }

    private var traitsCache: [TraitsKey: Traits] = [:]

    struct RawTask {
        let id: String
        let pid: pid_t
        let tool: DevTool
        let kind: DevTaskKind
        let title: String
        let detail: String
        let cpuPercent: Double
        let processStart: Date
        let usesActivitySignal: Bool
        var groupedBySession: Bool = false
    }

    func collect(_ configuration: Configuration) -> [RawTask] {
        var processes = scanner.scan()
        return classify(&processes, configuration: configuration) { [scanner] pids, table in
            scanner.sampleCPU(for: pids, in: &table)
        }
    }

    func classify(
        _ processes: inout [pid_t: DevProcess],
        configuration: Configuration,
        sampleCPU: (Set<pid_t>, inout [pid_t: DevProcess]) -> Void
    ) -> [RawTask] {
        let enabledKinds = configuration.enabledKinds
        let sensitivity = configuration.sensitivity
        let includeIDEAgents = configuration.includeIDEAgents

        guard !processes.isEmpty else { return [] }

        var children: [pid_t: [pid_t]] = [:]
        for process in processes.values {
            children[process.ppid, default: []].append(process.pid)
        }

        var matched: [pid_t: DevToolRule] = [:]
        var matchedByKind: [DevTaskKind: Set<pid_t>] = [:]
        var looseCommands: [pid_t] = []

        let detectCommands = enabledKinds.contains(DevTaskKind.command.rawValue)
        for process in processes.values {
            let traits = traits(for: process)
            if let rule = traits.rule {
                if !includeIDEAgents, rule.isEditorHeuristic { continue }
                matched[process.pid] = rule
                matchedByKind[rule.kind, default: []].insert(process.pid)
                continue
            }

            if detectCommands, traits.isCommandCandidate,
               terminalHost(of: process, in: processes) != nil {
                looseCommands.append(process.pid)
            }
        }

        if traitsCache.count > processes.count {
            traitsCache = traitsCache.filter { processes[$0.key.pid]?.startedAt == $0.key.startedAt }
        }

        let roots = matched.keys.filter { pid in
            guard let kind = matched[pid]?.kind else { return false }
            guard enabledKinds.contains(kind.rawValue) else { return false }
            return !hasAncestor(
                in: matchedByKind[kind] ?? [],
                from: pid,
                processes: processes
            )
        }
        let matchedPIDs = Set(matched.keys)
        let looseCommandPIDs = Set(looseCommands)
        let commandRoots = looseCommands.filter { pid in
            !hasAncestor(in: matchedPIDs, from: pid, processes: processes)
                && !hasAncestor(in: looseCommandPIDs, from: pid, processes: processes)
        }

        var sampleTargets = Set<pid_t>()
        var subtreeByRoot: [pid_t: Set<pid_t>] = [:]
        subtreeByRoot.reserveCapacity(roots.count + commandRoots.count)
        for pid in roots + commandRoots {
            let members = subtree(of: pid, children: children)
            subtreeByRoot[pid] = members
            sampleTargets.formUnion(members)
        }
        sampleCPU(sampleTargets, &processes)

        var result: [RawTask] = []

        for pid in roots {
            guard let process = processes[pid], let rule = matched[pid] else { continue }
            guard enabledKinds.contains(rule.kind.rawValue) else { continue }

            let subtreePids = subtreeByRoot[pid] ?? [pid]
            let cpu = subtreePids.reduce(0.0) { $0 + (processes[$1]?.cpuPercent ?? 0) }

            var workingDirectory: String?
            var busyBySession = false

            switch rule.signal {
            case .presence:
                guard process.elapsed >= 1.0 else { continue }

            case .activity(let threshold):
                workingDirectory = DevProcessScanner.workingDirectory(for: pid)
                let busyByCPU = cpu >= threshold * sensitivity
                busyBySession = DevAgentSessionActivity.isActive(
                    toolID: rule.tool.id,
                    workingDirectory: workingDirectory
                ) == true
                guard busyByCPU || busyBySession else { continue }
            }

            result.append(
                RawTask(
                    id: identifier(for: process),
                    pid: pid,
                    tool: rule.tool,
                    kind: rule.kind,
                    title: title(for: process, rule: rule),
                    detail: detail(for: process, rule: rule, workingDirectory: workingDirectory),
                    cpuPercent: cpu,
                    processStart: process.startedAt,
                    usesActivitySignal: rule.signal.isActivity,
                    groupedBySession: busyBySession
                )
            )
        }

        result = collapse(result)

        for pid in commandRoots {
            guard let process = processes[pid] else { continue }
            guard process.elapsed >= configuration.minimumCommandDuration else { continue }

            let subtreePids = subtreeByRoot[pid] ?? [pid]
            let cpu = subtreePids.reduce(0.0) { $0 + (processes[$1]?.cpuPercent ?? 0) }

            result.append(
                RawTask(
                    id: identifier(for: process),
                    pid: pid,
                    tool: DevTool.genericCommand,
                    kind: .command,
                    title: commandTitle(for: process),
                    detail: commandDetail(for: process, processes: processes),
                    cpuPercent: cpu,
                    processStart: process.startedAt,
                    usesActivitySignal: false
                )
            )
        }

        return result
    }

    private func collapse(_ tasks: [RawTask]) -> [RawTask] {
        var groups: [String: RawTask] = [:]
        var passthrough: [RawTask] = []

        for task in tasks {
            guard let key = groupKey(for: task) else {
                passthrough.append(task)
                continue
            }

            guard let existing = groups[key] else {
                groups[key] = RawTask(
                    id: key,
                    pid: task.pid,
                    tool: task.tool,
                    kind: task.kind,
                    title: task.title,
                    detail: task.detail,
                    cpuPercent: task.cpuPercent,
                    processStart: task.processStart,
                    usesActivitySignal: task.usesActivitySignal,
                    groupedBySession: task.groupedBySession
                )
                continue
            }

            let busiest = task.cpuPercent > existing.cpuPercent ? task : existing
            let mergedUsesActivitySignal = existing.usesActivitySignal && task.usesActivitySignal
            let mergedStart: Date
            if existing.usesActivitySignal == task.usesActivitySignal {
                mergedStart = min(task.processStart, existing.processStart)
            } else {
                mergedStart = existing.usesActivitySignal ? task.processStart : existing.processStart
            }
            groups[key] = RawTask(
                id: key,
                pid: busiest.pid,
                tool: busiest.tool,
                kind: busiest.kind,
                title: busiest.title,
                detail: existing.detail.isEmpty ? task.detail : existing.detail,
                cpuPercent: max(task.cpuPercent, existing.cpuPercent),
                processStart: mergedStart,
                usesActivitySignal: mergedUsesActivitySignal,
                groupedBySession: existing.groupedBySession || task.groupedBySession
            )
        }

        return passthrough + Array(groups.values)
    }

    private func groupKey(for task: RawTask) -> String? {
        switch task.kind {
        case .ai:
            guard task.groupedBySession else { return nil }
            return "ai|\(task.tool.id)|\(task.detail)"
        case .build:
            return "build|\(task.tool.id)"
        case .command:
            return nil
        }
    }

    // MARK: - Process-tree helpers

    private func identifier(for process: DevProcess) -> String {
        "\(process.pid)-\(Int(process.startedAt.timeIntervalSince1970))"
    }

    private func subtree(of pid: pid_t, children: [pid_t: [pid_t]]) -> Set<pid_t> {
        var seen: Set<pid_t> = [pid]
        var queue = children[pid] ?? []
        while let next = queue.popLast() {
            guard seen.insert(next).inserted else { continue }
            queue.append(contentsOf: children[next] ?? [])
        }
        return seen
    }

    private func hasAncestor(
        in candidates: Set<pid_t>,
        from pid: pid_t,
        processes: [pid_t: DevProcess]
    ) -> Bool {
        var current = processes[pid]?.ppid ?? 0
        var hops = 0
        while current > 1, hops < 32 {
            if candidates.contains(current) { return true }
            current = processes[current]?.ppid ?? 0
            hops += 1
        }
        return false
    }

    private func traits(for process: DevProcess) -> Traits {
        let key = TraitsKey(pid: process.pid, startedAt: process.startedAt)
        if let cached = traitsCache[key],
           cached.executablePath == process.executablePath,
           cached.argumentCount == process.arguments.count {
            return cached
        }

        let subject = DevMatchSubject(process)
        let traits = Traits(
            executablePath: process.executablePath,
            argumentCount: process.arguments.count,
            rule: DevToolCatalog.rule(for: subject),
            isCommandCandidate: Self.isCommandCandidate(process, subject: subject),
            isTerminalHost: DevToolCatalog.isTerminalHost(subject)
        )
        traitsCache[key] = traits
        return traits
    }

    private static func isCommandCandidate(_ process: DevProcess, subject: DevMatchSubject) -> Bool {
        guard !DevToolCatalog.isShell(subject) else { return false }
        guard !process.executablePath.isEmpty else { return false }

        for fragment in DevToolCatalog.neverEndingFragments where subject.command.containsBytes(fragment) {
            return false
        }

        return !subject.path.containsBytes(".app/contents/")
    }

    private func terminalHost(of process: DevProcess, in processes: [pid_t: DevProcess]) -> DevProcess? {
        var current = processes[process.ppid]
        var hops = 0
        while let candidate = current, hops < 32 {
            if traits(for: candidate).isTerminalHost { return candidate }
            current = processes[candidate.ppid]
            hops += 1
        }
        return nil
    }

    // MARK: - Labelling

    private func title(for process: DevProcess, rule: DevToolRule) -> String {
        switch rule.kind {
        case .ai:
            return rule.tool.displayName
        case .build:
            return buildTitle(for: process, rule: rule)
        case .command:
            return commandTitle(for: process)
        }
    }

    private func buildTitle(for process: DevProcess, rule: DevToolRule) -> String {
        let arguments = process.arguments.dropFirst().map { $0.lowercased() }

        if arguments.contains("test") || process.executableName.lowercased().contains("test") {
            return "\(rule.tool.displayName) Tests"
        }
        if arguments.contains(where: { $0 == "install" || $0 == "ci" || $0 == "sync" || $0 == "resolve" }) {
            return "Installing Packages"
        }
        if arguments.contains("clean") { return "Cleaning" }
        return "\(rule.tool.displayName) Build"
    }

    private func commandTitle(for process: DevProcess) -> String {
        let name = process.executableName
        let arguments = process.arguments.dropFirst().filter { !$0.hasPrefix("-") }
        guard let first = arguments.first else { return name }

        let shortened = first.contains("/") ? (first as NSString).lastPathComponent : first
        let combined = "\(name) \(shortened)"
        return combined.count > 28 ? name : combined
    }

    private func detail(
        for process: DevProcess,
        rule: DevToolRule,
        workingDirectory: String?
    ) -> String {
        let directory = workingDirectory ?? DevProcessScanner.workingDirectory(for: process.pid)
        if let directory, let name = projectName(from: directory) {
            return name
        }
        return ""
    }

    private func commandDetail(for process: DevProcess, processes: [pid_t: DevProcess]) -> String {
        if let directory = DevProcessScanner.workingDirectory(for: process.pid),
           let name = projectName(from: directory) {
            return name
        }
        guard let host = terminalHost(of: process, in: processes) else { return "" }
        return DevToolCatalog.hostDisplayName(forPath: host.executablePath) ?? ""
    }

    private func projectName(from directory: String) -> String? {
        let home = NSHomeDirectory()
        guard directory != "/", directory != home else { return nil }
        let name = (directory as NSString).lastPathComponent
        return name.isEmpty ? nil : name
    }
}

extension DevBusySignal {
    var isActivity: Bool {
        if case .activity = self { return true }
        return false
    }
}