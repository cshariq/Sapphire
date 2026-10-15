//
//  ProcessRunner.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-30

import Foundation
import Darwin

enum ProcessRunner {

    struct Result: Sendable {
        let stdoutData: Data
        var exitCode: Int32

        var stdout: String { String(data: stdoutData, encoding: .utf8) ?? "" }
        var succeeded: Bool { exitCode == 0 }
    }

    // MARK: - Core synchronous runner

    @discardableResult
    static func runSync(
        executablePath: String,
        arguments: [String],
        timeout: TimeInterval? = nil,
        environmentOverrides: [String: String?] = [:]
    ) -> Result? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        if !environmentOverrides.isEmpty {
            var environment = ProcessInfo.processInfo.environment
            for (key, value) in environmentOverrides { environment[key] = value }
            process.environment = environment
        }

        let stdoutPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = FileHandle.nullDevice

        let collector = PipeCollector(pipe: stdoutPipe)

        do {
            try process.run()
        } catch {
            collector.cancel()
            return nil
        }

        var timeoutItem: DispatchWorkItem?
        if let timeout {
            let item = DispatchWorkItem { [weak process] in
                guard let process, process.isRunning else { return }
                process.terminate()
                let processIdentifier = process.processIdentifier
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.5) { [weak process] in
                    guard let process, process.isRunning else { return }
                    Darwin.kill(processIdentifier, SIGKILL)
                }
            }
            timeoutItem = item
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: item)
        }
        process.waitUntilExit()
        timeoutItem?.cancel()
        let collected = collector.finish(waitingUpTo: PipeCollector.drainGrace)

        return Result(
            stdoutData: collected,
            exitCode: process.terminationStatus
        )
    }

    // MARK: - Async wrapper

    static func run(
        executablePath: String,
        arguments: [String],
        timeout: TimeInterval? = nil
    ) async -> Result? {
        await Task.detached(priority: .utility) {
            runSync(executablePath: executablePath, arguments: arguments, timeout: timeout)
        }.value
    }

    // MARK: - Fire-and-forget

    static func runDetached(executablePath: String, arguments: [String]) {
        DispatchQueue.global(qos: .utility).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executablePath)
            process.arguments = arguments
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try? process.run()
        }
    }

    // MARK: - AppleScript convenience

    static func runAppleScript(
        _ script: String,
        extraArguments: [String] = [],
        timeout: TimeInterval? = 5
    ) async -> String? {
        let result = await run(
            executablePath: "/usr/bin/osascript",
            arguments: ["-e", script] + extraArguments,
            timeout: timeout
        )
        guard let result, result.succeeded else { return nil }
        let trimmed = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func runAppleScriptBool(_ script: String, timeout: TimeInterval? = 5) async -> Bool {
        await runAppleScript(script, timeout: timeout)?.lowercased() == "true"
    }

    // MARK: - Captured stdout + stderr

    struct CapturedResult: Sendable {
        let exitStatus: Int32?
        let standardOutput: String
        let standardError: String
        let timedOut: Bool
    }

    static func runCapturing(
        executableURL: URL,
        arguments: [String],
        timeout: TimeInterval,
        standardInput: Data? = nil,
        onOutputLine: (@Sendable (String) -> Void)? = nil
    ) async -> CapturedResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let task = Process()
                task.executableURL = executableURL
                task.arguments = arguments

                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                task.standardOutput = stdoutPipe
                task.standardError = stderrPipe

                if let standardInput {
                    let stdinPipe = Pipe()
                    task.standardInput = stdinPipe
                    try? stdinPipe.fileHandleForWriting.write(contentsOf: standardInput)
                    try? stdinPipe.fileHandleForWriting.close()
                }

                let stdoutAccumulator = LineAccumulator(onLine: onOutputLine)
                let stderrAccumulator = LineAccumulator(onLine: onOutputLine)

                let stdoutCollector = PipeCollector(pipe: stdoutPipe) { stdoutAccumulator.append($0) }
                let stderrCollector = PipeCollector(pipe: stderrPipe) { stderrAccumulator.append($0) }

                let semaphore = DispatchSemaphore(value: 0)
                task.terminationHandler = { _ in semaphore.signal() }

                do {
                    try task.run()
                } catch {
                    stdoutCollector.cancel()
                    stderrCollector.cancel()
                    continuation.resume(returning: CapturedResult(
                        exitStatus: nil,
                        standardOutput: "",
                        standardError: error.localizedDescription,
                        timedOut: false
                    ))
                    return
                }

                var timedOut = false
                if semaphore.wait(timeout: .now() + timeout) == .timedOut {
                    timedOut = true
                    task.terminate()
                    _ = semaphore.wait(timeout: .now() + 1.0)
                    if task.isRunning {
                        kill(task.processIdentifier, SIGKILL)
                        _ = semaphore.wait(timeout: .now() + 1.0)
                    }
                }

                _ = stdoutCollector.finish(waitingUpTo: PipeCollector.drainGrace)
                _ = stderrCollector.finish(waitingUpTo: PipeCollector.drainGrace)
                stdoutAccumulator.flush()
                stderrAccumulator.flush()

                continuation.resume(returning: CapturedResult(
                    exitStatus: task.isRunning ? nil : task.terminationStatus,
                    standardOutput: String(data: stdoutAccumulator.allData, encoding: .utf8) ?? "",
                    standardError: String(data: stderrAccumulator.allData, encoding: .utf8) ?? "",
                    timedOut: timedOut
                ))
            }
        }
    }

    private final class LineAccumulator: @unchecked Sendable {
        private let lock = NSLock()
        private var buffer = Data()
        private var pending = Data()
        private let onLine: (@Sendable (String) -> Void)?

        init(onLine: (@Sendable (String) -> Void)?) {
            self.onLine = onLine
        }

        func append(_ chunk: Data) {
            guard !chunk.isEmpty else { return }
            lock.lock()
            buffer.append(chunk)
            var lines: [String] = []
            if onLine != nil {
                pending.append(chunk)
                while let newlineIndex = pending.firstIndex(of: 0x0A) {
                    let lineData = pending[pending.startIndex..<newlineIndex]
                    if let line = String(data: lineData, encoding: .utf8), !line.isEmpty {
                        lines.append(line)
                    }
                    pending.removeSubrange(pending.startIndex...newlineIndex)
                }
            }
            lock.unlock()
            guard let onLine else { return }
            for line in lines { onLine(line) }
        }

        func flush() {
            lock.lock()
            let tail = pending
            pending.removeAll()
            lock.unlock()
            guard let onLine, !tail.isEmpty,
                  let line = String(data: tail, encoding: .utf8), !line.isEmpty else { return }
            onLine(line)
        }

        var allData: Data {
            lock.lock()
            defer { lock.unlock() }
            return buffer
        }
    }

    final class PipeCollector: @unchecked Sendable {
        static let drainGrace: TimeInterval = 2

        private let handle: FileHandle
        private let lock = NSLock()
        private var data = Data()
        private var reachedEOF = false
        private let eof = DispatchSemaphore(value: 0)
        private let onChunk: ((Data) -> Void)?

        init(pipe: Pipe, onChunk: ((Data) -> Void)? = nil) {
            handle = pipe.fileHandleForReading
            self.onChunk = onChunk
            handle.readabilityHandler = { [self] handle in
                let chunk = handle.availableData
                if chunk.isEmpty {
                    handle.readabilityHandler = nil
                    markEOF()
                } else {
                    lock.lock()
                    data.append(chunk)
                    lock.unlock()
                    onChunk?(chunk)
                }
            }
        }

        private func markEOF() {
            lock.lock()
            let first = !reachedEOF
            reachedEOF = true
            lock.unlock()
            if first { eof.signal() }
        }

        func finish(waitingUpTo grace: TimeInterval) -> Data {
            _ = eof.wait(timeout: .now() + grace)
            handle.readabilityHandler = nil
            lock.lock()
            defer { lock.unlock() }
            return data
        }

        func cancel() {
            handle.readabilityHandler = nil
        }
    }
}