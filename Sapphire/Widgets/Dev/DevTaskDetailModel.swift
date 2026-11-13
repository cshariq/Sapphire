//
//  DevTaskDetailModel.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-10-15
//

import AppKit
import Combine
import Foundation

@MainActor
final class DevTaskDetailModel: ObservableObject {
    @Published private(set) var detail: DevTaskDetail?
    @Published var draft: String = ""
    @Published private(set) var isSending = false
    @Published private(set) var statusMessage: String?
    @Published var confirmingStop = false

    nonisolated private static let inspector = DevTaskInspector()
    nonisolated private static let queue = DispatchQueue(label: "com.shariq.sapphire.devtask.inspect", qos: .userInitiated)
    private static let pollInterval: Duration = .seconds(2)

    private var statusTask: Task<Void, Never>?
    private var refreshToken = 0

    func track(_ task: DevTask) async {
        if detail?.taskID != task.id {
            detail = nil
            draft = ""
            statusMessage = nil
            confirmingStop = false
        }
        var pass = 0
        while !Task.isCancelled {
            let token = refreshToken
            let includeOutput = pass % 2 == 0 && task.kind != .ai
            let result = await Self.inspect(task, includeOutput: includeOutput)
            guard !Task.isCancelled else { return }
            var next = result
            if !includeOutput, next.terminalOutput == nil, detail?.taskID == task.id {
                next.terminalOutput = detail?.terminalOutput
            }
            if next != detail { detail = next }
            pass += 1
            for _ in 0..<8 {
                try? await Task.sleep(for: Self.pollInterval / 8)
                if Task.isCancelled || refreshToken != token { break }
            }
        }
    }

    nonisolated private static func inspect(_ task: DevTask, includeOutput: Bool) async -> DevTaskDetail {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: inspector.inspect(task, includeTerminalOutput: includeOutput))
            }
        }
    }

    func refreshSoon() { refreshToken &+= 1 }

    // MARK: - Capabilities

    var canSend: Bool {
        guard let detail, detail.isAlive, let host = detail.host else { return false }
        if detail.agent?.isDesktopHosted == true { return false }
        if host.isEditor { return false }
        return detail.ttyPath != nil || !host.kind.isScriptable
    }

    func sendUnavailableReason(for task: DevTask) -> String {
        guard let detail else { return String(localized: "Looking up the session…") }
        if !detail.isAlive { return String(localized: "This task has ended") }
        if detail.agent?.isDesktopHosted == true {
            let hostName = detail.agent?.entrypoint?.replacingOccurrences(of: "-", with: " ").capitalized ?? String(localized: "an app")
            return String(localized: "Runs in \(hostName) — reply there")
        }
        if let host = detail.host, host.isEditor { return String(localized: "Runs in \(host.name)'s terminal — type there") }
        return String(localized: "\(task.title) isn't running in a terminal Sapphire can reach")
    }

    // MARK: - Actions

    func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, canSend, let detail, let host = detail.host, !isSending else { return }
        isSending = true
        (NSApp.delegate as? AppDelegate)?.revertNotchWindowFocus()
        Task {
            let result = await DevTerminalBridge.send(text, host: host, tty: detail.ttyPath)
            isSending = false
            switch result {
            case .sent, .sentToFrontTab:
                draft = ""
                flash(result.message ?? String(localized: "Sent"))
                refreshSoon()
            case .needsAccessibility, .failed:
                flash(result.message ?? String(localized: "Couldn't send"))
            }
        }
    }

    func interrupt() {
        guard let detail else { return }
        let ok = DevTerminalBridge.interrupt(pid: detail.pid, foregroundProcessGroup: detail.foregroundProcessGroup)
        flash(ok ? String(localized: "Sent Ctrl-C") : String(localized: "Couldn't interrupt"))
        refreshSoon()
    }

    func terminate() {
        guard let detail else { return }
        guard confirmingStop else {
            confirmingStop = true
            Task {
                try? await Task.sleep(for: .seconds(3))
                confirmingStop = false
            }
            return
        }
        confirmingStop = false
        flash(DevTerminalBridge.terminate(pid: detail.pid) ? String(localized: "Stopped") : String(localized: "Couldn't stop"))
        refreshSoon()
        DevActivityMonitor.shared.refreshNow()
    }

    func openHost() {
        guard let detail else { return }
        if let host = detail.host {
            DevTerminalBridge.focus(host: host, tty: detail.ttyPath)
        } else if let entrypoint = detail.agent?.entrypoint, entrypoint.contains("desktop"),
                  let claude = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.anthropic.claudefordesktop") {
            NSWorkspace.shared.openApplication(at: claude, configuration: .init())
        }
    }

    func revealFolder() {
        guard let directory = detail?.workingDirectory else { return }
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: directory)
    }

    func copyCommand() {
        guard let command = detail?.commandLine, !command.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
        flash(String(localized: "Copied command"))
    }

    func openTranscript() {
        guard let path = detail?.agent?.transcriptPath else { return }
        NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
    }

    private func flash(_ message: String) {
        statusMessage = message
        statusTask?.cancel()
        statusTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            statusMessage = nil
        }
    }
}