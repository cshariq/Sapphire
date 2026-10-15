//
//  DevTerminalBridge.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-10-15
//

import AppKit
import ApplicationServices
import Darwin
import Foundation

enum DevTerminalSendResult: Equatable {
    case sent
    case sentToFrontTab
    case needsAccessibility
    case failed(String)

    var message: String? {
        switch self {
        case .sent: return nil
        case .sentToFrontTab: return "Sent to the front tab"
        case .needsAccessibility: return "Allow Accessibility for Sapphire to type into this app"
        case .failed(let reason): return reason
        }
    }
}

nonisolated enum DevTerminalBridge {

    // MARK: - Reading

    static let outputCharacterLimit = 6000

    static func readOutput(host: DevTerminalHost, tty: String) -> String? {
        let script: String
        switch host.kind {
        case .appleTerminal:
            script = """
            tell application id "com.apple.Terminal"
                repeat with w in windows
                    repeat with t in tabs of w
                        if tty of t is "\(escape(tty))" then return contents of t
                    end repeat
                end repeat
            end tell
            return ""
            """
        case .iTerm:
            script = """
            tell application id "com.googlecode.iterm2"
                repeat with w in windows
                    repeat with t in tabs of w
                        repeat with s in sessions of t
                            if tty of s is "\(escape(tty))" then return contents of s
                        end repeat
                    end repeat
                end repeat
            end tell
            return ""
            """
        case .other:
            return nil
        }
        guard isRunning(host), let output = runOSAScript(script, timeout: 3) else { return nil }
        let trimmed = trimTrailingBlankLines(output)
        guard !trimmed.isEmpty else { return nil }
        return trimmed.count > outputCharacterLimit ? String(trimmed.suffix(outputCharacterLimit)) : trimmed
    }

    // MARK: - Typing

    static func send(_ text: String, host: DevTerminalHost, tty: String?) async -> DevTerminalSendResult {
        let line = text.replacingOccurrences(of: "\r\n", with: "\n")
        switch host.kind {
        case .appleTerminal where tty != nil:
            let script = """
            tell application id "com.apple.Terminal"
                repeat with w in windows
                    repeat with t in tabs of w
                        if tty of t is "\(escape(tty!))" then
                            do script "\(escape(line))" in t
                            return "ok"
                        end if
                    end repeat
                end repeat
            end tell
            return "missing"
            """
            return await runSend(script)
        case .iTerm where tty != nil:
            let script = """
            tell application id "com.googlecode.iterm2"
                repeat with w in windows
                    repeat with t in tabs of w
                        repeat with s in sessions of t
                            if tty of s is "\(escape(tty!))" then
                                tell s to write text "\(escape(line))"
                                return "ok"
                            end if
                        end repeat
                    end repeat
                end repeat
            end tell
            return "missing"
            """
            return await runSend(script)
        default:
            return await pasteIntoFrontWindow(of: host, text: line)
        }
    }

    private static func runSend(_ script: String) async -> DevTerminalSendResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let result = runOSAScript(script, timeout: 5)
                switch result?.trimmingCharacters(in: .whitespacesAndNewlines) {
                case "ok": continuation.resume(returning: .sent)
                case "missing": continuation.resume(returning: .failed("The terminal tab was closed"))
                default: continuation.resume(returning: .failed("Allow Sapphire to control the terminal in Privacy & Security › Automation"))
                }
            }
        }
    }

    @MainActor
    private static func pasteIntoFrontWindow(of host: DevTerminalHost, text: String) async -> DevTerminalSendResult {
        guard AXIsProcessTrusted() else { return .needsAccessibility }
        guard let app = NSRunningApplication(processIdentifier: host.pid) else {
            return .failed("\(host.name) is not running")
        }

        let pasteboard = NSPasteboard.general
        let saved = pasteboard.pasteboardItems?.compactMap { item -> NSPasteboardItem? in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) { copy.setData(data, forType: type) }
            }
            return copy
        } ?? []

        app.activate()
        try? await Task.sleep(for: .milliseconds(250))

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        postKey(9, flags: .maskCommand)
        try? await Task.sleep(for: .milliseconds(120))
        postKey(36, flags: [])
        try? await Task.sleep(for: .milliseconds(400))

        pasteboard.clearContents()
        if !saved.isEmpty { pasteboard.writeObjects(saved) }
        return .sentToFrontTab
    }

    private static func postKey(_ code: CGKeyCode, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .combinedSessionState)
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down)
            event?.flags = flags
            event?.post(tap: .cghidEventTap)
        }
    }

    // MARK: - Process control

    @discardableResult
    static func interrupt(pid: pid_t, foregroundProcessGroup: pid_t?) -> Bool {
        if let group = foregroundProcessGroup, group > 1, killpg(group, SIGINT) == 0 { return true }
        return kill(pid, SIGINT) == 0
    }

    @discardableResult
    static func terminate(pid: pid_t) -> Bool {
        kill(pid, SIGTERM) == 0
    }

    // MARK: - Windows

    @MainActor
    static func focus(host: DevTerminalHost, tty: String?) {
        if let tty, host.kind.isScriptable {
            let script: String
            if host.kind == .appleTerminal {
                script = """
                tell application id "com.apple.Terminal"
                    activate
                    repeat with w in windows
                        repeat with t in tabs of w
                            if tty of t is "\(escape(tty))" then
                                set selected of t to true
                                set index of w to 1
                                return
                            end if
                        end repeat
                    end repeat
                end tell
                """
            } else {
                script = """
                tell application id "com.googlecode.iterm2"
                    activate
                    repeat with w in windows
                        repeat with t in tabs of w
                            repeat with s in sessions of t
                                if tty of s is "\(escape(tty))" then
                                    select w
                                    tell t to select
                                    tell s to select
                                    return
                                end if
                            end repeat
                        end repeat
                    end repeat
                end tell
                """
            }
            DispatchQueue.global(qos: .userInitiated).async { _ = runOSAScript(script, timeout: 5) }
            return
        }
        NSRunningApplication(processIdentifier: host.pid)?.activate()
    }

    static func runInNewTerminalWindow(_ command: String, directory: String) {
        let line = "cd \(shellQuote(directory)) && \(command)"
        let script = """
        tell application id "com.apple.Terminal"
            activate
            do script "\(escape(line))"
        end tell
        """
        DispatchQueue.global(qos: .userInitiated).async { _ = runOSAScript(script, timeout: 8) }
    }

    // MARK: - osascript

    static func runOSAScript(_ source: String, timeout: TimeInterval) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", source]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }

        let deadline = DispatchTime.now() + timeout
        let finished = DispatchSemaphore(value: 0)
        var data = Data()
        DispatchQueue.global(qos: .utility).async {
            data = output.fileHandleForReading.readDataToEndOfFile()
            finished.signal()
        }
        if finished.wait(timeout: deadline) == .timedOut {
            process.terminate()
            return nil
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    private static func isRunning(_ host: DevTerminalHost) -> Bool {
        guard let bundleID = host.bundleIdentifier else { return false }
        return !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    static func shellQuote(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func trimTrailingBlankLines(_ text: String) -> String {
        var lines = text.components(separatedBy: "\n")
        while let last = lines.last, last.trimmingCharacters(in: .whitespaces).isEmpty { lines.removeLast() }
        return lines.joined(separator: "\n")
    }
}