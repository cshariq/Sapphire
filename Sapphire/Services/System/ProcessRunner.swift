//
//  ProcessRunner.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-30

import Foundation

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
            let item = DispatchWorkItem { if process.isRunning { process.terminate() } }
            timeoutItem = item
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: item)
        }
        process.waitUntilExit()
        timeoutItem?.cancel()
        stdoutPipe.fileHandleForReading.readabilityHandler = nil

        bufferLock.lock()
        collected.append(stdoutPipe.fileHandleForReading.readDataToEndOfFile())
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
}