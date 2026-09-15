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
        timeout: TimeInterval? = nil
    ) -> Result? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments

        let stdoutPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = FileHandle.nullDevice

        var collected = Data()
        let bufferLock = NSLock()
        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            bufferLock.lock()
            collected.append(chunk)
            bufferLock.unlock()
        }

        do {
            try process.run()
        } catch {
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
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
        let tail = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        bufferLock.lock()
        collected.append(tail)
        bufferLock.unlock()

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

                let stdoutAccumulator = LineAccumulator(onLine: onOutputLine)
                let stderrAccumulator = LineAccumulator(onLine: onOutputLine)

                if onOutputLine != nil {
                    stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                        stdoutAccumulator.append(handle.availableData)
                    }
                    stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                        stderrAccumulator.append(handle.availableData)
                    }
                }

                let semaphore = DispatchSemaphore(value: 0)
                task.terminationHandler = { _ in semaphore.signal() }

                do {
                    try task.run()
                } catch {
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

                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil

                stdoutAccumulator.append(stdoutPipe.fileHandleForReading.readDataToEndOfFile())
                stderrAccumulator.append(stderrPipe.fileHandleForReading.readDataToEndOfFile())

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

        var allData: Data {
            lock.lock()
            defer { lock.unlock() }
            return buffer
        }
    }
}