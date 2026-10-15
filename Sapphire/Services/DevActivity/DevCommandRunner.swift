//
//  DevCommandRunner.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-10-15
//

import Combine
import Foundation

struct DevCommandRun: Identifiable, Equatable {
    enum State: Equatable {
        case running
        case finished(exitCode: Int32)
        case stopped
        case failedToStart(String)
    }

    let id: UUID
    let command: String
    let directory: String
    let startedAt: Date
    var endedAt: Date?
    var state: State
    var output: String

    var isRunning: Bool { state == .running }
}

@MainActor
final class DevCommandRunner: ObservableObject {
    static let shared = DevCommandRunner()

    @Published private(set) var runs: [DevCommandRun] = []
    @Published var selectedRunID: UUID?
    @Published var directory: String = NSHomeDirectory()
    @Published private(set) var history: [String] = []

    private static let outputLimit = 48 * 1024
    private static let runLimit = 8
    private static let historyKey = "devCommandRunner.history"
    private static let directoryKey = "devCommandRunner.directory"

    private var processes: [UUID: Process] = [:]
    private var pendingOutput: [UUID: String] = [:]
    private var flushScheduled = false

    private init() {
        history = UserDefaults.standard.stringArray(forKey: Self.historyKey) ?? []
        if let saved = UserDefaults.standard.string(forKey: Self.directoryKey),
           FileManager.default.fileExists(atPath: saved) {
            directory = saved
        }
    }

    var selectedRun: DevCommandRun? {
        if let selectedRunID, let run = runs.first(where: { $0.id == selectedRunID }) { return run }
        return runs.last
    }

    var runningCount: Int { runs.filter(\.isRunning).count }

    func setDirectory(_ path: String) {
        directory = path
        UserDefaults.standard.set(path, forKey: Self.directoryKey)
    }

    func run(_ rawCommand: String) {
        let command = rawCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else { return }
        remember(command)

        let id = UUID()
        var run = DevCommandRun(
            id: id, command: command, directory: directory, startedAt: Date(),
            endedAt: nil, state: .running, output: ""
        )

        let process = Process()
        let shell = ProcessInfo.processInfo.environment["SHELL"].flatMap { $0.isEmpty ? nil : $0 } ?? "/bin/zsh"
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-l", "-c", command]
        process.currentDirectoryURL = URL(fileURLWithPath: directory, isDirectory: true)
        var environment = ProcessInfo.processInfo.environment
        environment["TERM"] = "dumb"
        environment["NO_COLOR"] = "1"
        environment["CLICOLOR"] = "0"
        environment["GIT_PAGER"] = "cat"
        environment["PAGER"] = "cat"
        process.environment = environment
        process.standardInput = FileHandle.nullDevice

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            let text = String(decoding: data, as: UTF8.self)
            Task { @MainActor [weak self] in self?.append(text, to: id) }
        }
        process.terminationHandler = { [weak self] finished in
            let status = finished.terminationStatus
            let reason = finished.terminationReason
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(80))
                self?.finish(id, status: status, uncaughtSignal: reason == .uncaughtSignal)
            }
        }

        do {
            try process.run()
            processes[id] = process
        } catch {
            run.state = .failedToStart(error.localizedDescription)
            run.endedAt = Date()
        }

        runs.append(run)
        if runs.count > Self.runLimit {
            let removable = runs.firstIndex { !$0.isRunning }
            if let removable { runs.remove(at: removable) }
        }
        selectedRunID = id
    }

    func stop(_ id: UUID) {
        guard let process = processes[id], process.isRunning else { return }
        process.interrupt()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let process = self?.processes[id], process.isRunning else { return }
            process.terminate()
        }
        if let index = runs.firstIndex(where: { $0.id == id }) { runs[index].state = .stopped }
    }

    func clearFinished() {
        runs.removeAll { !$0.isRunning }
        if let selectedRunID, !runs.contains(where: { $0.id == selectedRunID }) {
            self.selectedRunID = runs.last?.id
        }
    }

    func rerun(_ run: DevCommandRun) {
        setDirectory(run.directory)
        self.run(run.command)
    }

    // MARK: - Output

    private func append(_ text: String, to id: UUID) {
        pendingOutput[id, default: ""] += text
        guard !flushScheduled else { return }
        flushScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            MainActor.assumeIsolated { self?.flushOutput() }
        }
    }

    private func flushOutput() {
        flushScheduled = false
        let pending = pendingOutput
        pendingOutput.removeAll()
        for (id, text) in pending {
            guard let index = runs.firstIndex(where: { $0.id == id }) else { continue }
            var output = runs[index].output + Self.stripEscapes(text)
            if output.utf8.count > Self.outputLimit {
                output = String(output.suffix(Self.outputLimit))
            }
            runs[index].output = output
        }
    }

    private func finish(_ id: UUID, status: Int32, uncaughtSignal: Bool) {
        flushOutput()
        processes[id] = nil
        guard let index = runs.firstIndex(where: { $0.id == id }) else { return }
        runs[index].endedAt = Date()
        if runs[index].state == .running {
            runs[index].state = uncaughtSignal ? .stopped : .finished(exitCode: status)
        }
    }

    private func remember(_ command: String) {
        history.removeAll { $0 == command }
        history.insert(command, at: 0)
        if history.count > 20 { history.removeLast(history.count - 20) }
        UserDefaults.standard.set(history, forKey: Self.historyKey)
    }

    nonisolated static func stripEscapes(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.utf8.count)
        var iterator = text.unicodeScalars.makeIterator()
        while let scalar = iterator.next() {
            if scalar == "\u{1B}" {
                guard let next = iterator.next() else { break }
                if next == "[" {
                    while let c = iterator.next(), !(0x40...0x7E).contains(c.value) {}
                } else if next == "]" {
                    while let c = iterator.next(), c != "\u{07}", c != "\u{1B}" {}
                }
                continue
            }
            if scalar == "\r" { continue }
            result.unicodeScalars.append(scalar)
        }
        return result
    }
}