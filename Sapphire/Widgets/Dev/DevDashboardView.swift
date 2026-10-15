//
//  DevDashboardView.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-10-15
//

import AppKit
import SwiftUI

enum DevDashboardTab: String, CaseIterable, Hashable {
    case activity
    case usage
    case terminal

    var title: String {
        switch self {
        case .activity: return "ACTIVITY"
        case .usage: return "USAGE"
        case .terminal: return "TERMINAL"
        }
    }
}

struct DevDashboardView: View {
    @ObservedObject private var monitor = DevActivityMonitor.shared
    @ObservedObject private var runner = DevCommandRunner.shared
    @State private var tab: DevDashboardTab
    @State private var selectedTaskID: String?

    static let size = CGSize(width: 640, height: 300)

    init(initialTab: DevDashboardTab) {
        _tab = State(initialValue: initialTab)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            Group {
                switch tab {
                case .activity: activity
                case .usage: DevUsageGrid()
                case .terminal: DevTerminalPanel()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .padding(.horizontal, 14)
        .padding(.top, 6)
        .padding(.bottom, 12)
        .frame(width: Self.size.width, height: Self.size.height, alignment: .top)
        .onAppear { monitor.refreshNow() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(LinearGradient(
                        colors: [Color(hue: 0.64, saturation: 0.40, brightness: 0.84), Color(hue: 0.64, saturation: 0.54, brightness: 0.58)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                    .frame(width: 24, height: 24)
                Image(systemName: "chevron.left.forwardslash.chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
            }
            Text("Developer")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            if !monitor.tasks.isEmpty {
                DevCountBadge(count: monitor.tasks.count, tint: .green)
            }
            Spacer(minLength: 0)
            RoundedPillSwitcher(items: DevDashboardTab.allCases, title: { tabTitle($0) }, selection: $tab)
        }
    }

    private func tabTitle(_ tab: DevDashboardTab) -> String {
        if tab == .terminal, runner.runningCount > 0 { return "\(tab.title) · \(runner.runningCount)" }
        return tab.title
    }

    // MARK: - Activity

    private var selectedTask: DevTask? {
        if let selectedTaskID, let task = monitor.tasks.first(where: { $0.id == selectedTaskID }) { return task }
        return monitor.tasks.first
    }

    @ViewBuilder
    private var activity: some View {
        if monitor.tasks.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "moon.zzz.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.white.opacity(0.35))
                Text("Nothing is running")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.8))
                Text(emptyHint)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
                Button { tab = .terminal } label: {
                    Label("Run a command", systemImage: "terminal")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                }
                .buttonStyle(DevPillButtonStyle(tint: .white))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            HStack(alignment: .top, spacing: 10) {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 4) {
                        ForEach(monitor.tasks) { task in
                            DevTaskListRow(task: task, isSelected: task.id == selectedTask?.id)
                                .contentShape(Rectangle())
                                .onTapGesture { selectedTaskID = task.id }
                        }
                    }
                }
                .frame(width: 176)

                if let task = selectedTask {
                    DevTaskDetailPane(task: task)
                        .id(task.id)
                }
            }
        }
    }

    private var emptyHint: String {
        let settings = SettingsModel.shared.current
        if !settings.devActivityEnabled, !settings.devWidgetEnabled, !settings.caffeinateAutoDuringTasks {
            return "Turn on Dev Activity in Settings to see AI agents, builds and terminal commands here."
        }
        return "AI agents, builds and long terminal commands show up here while they run."
    }
}

// MARK: - Task list

private struct DevTaskListRow: View {
    let task: DevTask
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            DevToolGlyph(tool: task.tool, size: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(task.title)
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(task.detail.isEmpty ? task.kind.displayName : task.detail)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            DevElapsedText(startedAt: task.startedAt, size: 10)
                .foregroundStyle(task.tool.tint.opacity(0.9))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? Color.white.opacity(0.13) : Color.white.opacity(0.04))
        )
    }
}

// MARK: - Task detail

private enum DevDetailSection: String, CaseIterable, Hashable {
    case conversation, output, processes

    var title: String {
        switch self {
        case .conversation: return "CHAT"
        case .output: return "OUTPUT"
        case .processes: return "PROCESSES"
        }
    }
}

struct DevTaskDetailPane: View {
    let task: DevTask
    @StateObject private var model = DevTaskDetailModel()
    @State private var section: DevDetailSection

    init(task: DevTask) {
        self.task = task
        _section = State(initialValue: task.kind == .ai ? .conversation : .output)
    }

    private var sections: [DevDetailSection] {
        task.kind == .ai ? [.conversation, .processes] : [.output, .processes]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            chips
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.black.opacity(0.35)))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task(id: task.id) { await model.track(task) }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(model.detail?.agent?.sessionName ?? task.title)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            RoundedPillSwitcher(items: sections, title: \.title, selection: $section)
        }
    }

    private var subtitle: String {
        var parts: [String] = []
        if model.detail?.agent?.sessionName != nil { parts.append(task.title) }
        if let status = model.detail?.agent?.status { parts.append(status == "busy" ? "Working" : status.capitalized) }
        if !task.detail.isEmpty { parts.append(task.detail) }
        if let host = model.detail?.host { parts.append(host.name) }
        if parts.isEmpty { parts.append(task.kind.displayName) }
        return parts.joined(separator: " · ")
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 5) {
                DevChip(symbol: "timer", text: nil, tint: task.tool.tint) {
                    DevElapsedText(startedAt: task.startedAt, size: 10)
                }
                if let detail = model.detail {
                    DevChip(symbol: "cpu", text: String(format: "%.0f%%", detail.totalCPU), tint: .white)
                    if detail.totalResidentBytes > 0 {
                        DevChip(symbol: "memorychip", text: ByteCountFormatter.string(fromByteCount: Int64(detail.totalResidentBytes), countStyle: .memory), tint: .white)
                    }
                    if let directory = detail.workingDirectory {
                        DevChip(symbol: "folder.fill", text: (directory as NSString).lastPathComponent, tint: .blue, action: model.revealFolder)
                    }
                    if let branch = detail.agent?.gitBranch {
                        DevChip(symbol: "arrow.triangle.branch", text: branch, tint: .orange)
                    }
                    if let model = detail.agent?.model {
                        DevChip(symbol: "cpu.fill", text: ClaudePricing.displayName(for: model), tint: task.tool.tint)
                    }
                    if let context = detail.agent?.contextTokens {
                        DevChip(symbol: "text.alignleft", text: "\(UsageFormat.tokens(context)) ctx", tint: .white)
                    }
                    if let output = detail.agent?.sessionOutputTokens, output > 0 {
                        DevChip(symbol: "arrow.up.right", text: "\(UsageFormat.tokens(output)) out", tint: .white)
                    }
                    if let tty = detail.ttyPath {
                        DevChip(symbol: "terminal", text: (tty as NSString).lastPathComponent, tint: .white)
                    }
                    DevChip(symbol: "number", text: "\(detail.pid)", tint: .white)
                }
            }
        }
        .frame(height: 20)
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if model.detail == nil {
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            switch section {
            case .conversation: conversation
            case .output: output
            case .processes: DevProcessList(processes: model.detail?.processes ?? [])
            }
        }
    }

    @ViewBuilder
    private var conversation: some View {
        if let messages = model.detail?.agent?.messages, !messages.isEmpty {
            DevTranscriptView(messages: messages, tint: task.tool.tint)
        } else {
            DevPlaceholder(
                symbol: "text.bubble",
                text: task.tool.id == DevToolCatalog.claude.id || task.tool.id == DevToolCatalog.codex.id
                    ? "No conversation recorded yet."
                    : "\(task.tool.displayName) doesn't keep a transcript Sapphire can read. Processes are listed on the right tab."
            )
        }
    }

    @ViewBuilder
    private var output: some View {
        if let text = model.detail?.terminalOutput, !text.isEmpty {
            DevMonospaceLog(text: text)
        } else if let detail = model.detail {
            VStack(alignment: .leading, spacing: 8) {
                Text(detail.commandLine)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(4)
                    .textSelection(.enabled)
                Text(outputHint(detail))
                    .font(.system(size: 10.5))
                    .foregroundStyle(.white.opacity(0.45))
            }
            .padding(10)
        }
    }

    private func outputHint(_ detail: DevTaskDetail) -> String {
        guard let host = detail.host else { return "This task has no terminal window; its processes are on the Processes tab." }
        if host.kind.isScriptable {
            return "Reading \(host.name)… If nothing appears, allow Sapphire to control \(host.name) in System Settings › Privacy & Security › Automation."
        }
        return "\(host.name) doesn't let other apps read its tabs. Send input below or open it to see the output."
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: task.kind == .ai ? "text.bubble.fill" : "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(task.tool.tint)
                if model.canSend {
                    NotchSearchField(placeholder: placeholder, text: $model.draft, onSubmit: model.send)
                        .font(.system(size: 11.5, design: task.kind == .ai ? .rounded : .monospaced))
                        .foregroundStyle(.white)
                } else {
                    Text(model.sendUnavailableReason(for: task))
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.4))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                if model.isSending {
                    ProgressView().controlSize(.mini)
                } else if model.canSend {
                    Button(action: model.send) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(model.draft.isEmpty ? Color.white.opacity(0.25) : task.tool.tint)
                    }
                    .buttonStyle(.plain)
                    .disabled(model.draft.isEmpty)
                    .help("Send and press Return")
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(Capsule().fill(Color.white.opacity(0.08)))
            .overlay(alignment: .top) {
                if let status = model.statusMessage {
                    Text(status)
                        .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.black.opacity(0.8)))
                        .offset(y: -12)
                        .transition(.opacity)
                }
            }

            DevIconButton(symbol: "stop.fill", help: task.kind == .ai ? "Interrupt (Ctrl-C)" : "Send Ctrl-C", action: model.interrupt)
                .disabled(model.detail?.isAlive != true)
            DevIconButton(
                symbol: model.confirmingStop ? "exclamationmark.octagon.fill" : "xmark.octagon",
                help: model.confirmingStop ? "Click again to end the process" : "End the process",
                tint: model.confirmingStop ? .red : .white,
                action: model.terminate
            )
            .disabled(model.detail?.isAlive != true)
            DevIconButton(symbol: "arrow.up.forward.app", help: "Show in \(model.detail?.host?.name ?? "app")", action: model.openHost)
            Menu {
                Button("Copy Command", action: model.copyCommand)
                Button("Reveal Folder in Finder", action: model.revealFolder)
                    .disabled(model.detail?.workingDirectory == nil)
                if model.detail?.agent?.transcriptPath != nil {
                    Button("Reveal Transcript", action: model.openTranscript)
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color.white.opacity(0.08)))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 28, height: 28)
        }
        .animation(.easeOut(duration: 0.18), value: model.statusMessage)
    }

    private var placeholder: String {
        if task.kind == .ai { return "Message \(task.tool.displayName)…" }
        return "Type into \(model.detail?.host?.name ?? "the terminal")…"
    }
}

// MARK: - Transcript

private struct DevTranscriptView: View {
    let messages: [DevAgentMessage]
    let tint: Color

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(messages) { message in
                        row(message).id(message.id)
                    }
                }
                .padding(10)
            }
            .onAppear { proxy.scrollTo(messages.last?.id, anchor: .bottom) }
            .onChange(of: messages.last?.id) { _, id in
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(id, anchor: .bottom) }
            }
        }
    }

    @ViewBuilder
    private func row(_ message: DevAgentMessage) -> some View {
        switch message.role {
        case .user:
            HStack {
                Spacer(minLength: 40)
                Text(message.text)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(tint.opacity(0.35)))
                    .textSelection(.enabled)
            }
        case .assistant:
            Text(message.text)
                .font(.system(size: 11.5))
                .foregroundStyle(.white.opacity(0.88))
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        case .tool:
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Image(systemName: "wrench.and.screwdriver.fill")
                    .font(.system(size: 8.5))
                    .foregroundStyle(tint.opacity(0.8))
                Text(message.text)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(2)
            }
        case .toolResult(let isError):
            Text(message.text)
                .font(.system(size: 9.5, design: .monospaced))
                .foregroundStyle(isError ? Color.red.opacity(0.8) : Color.white.opacity(0.38))
                .lineLimit(3)
                .padding(.leading, 14)
        }
    }
}

// MARK: - Processes & output

private struct DevProcessList: View {
    let processes: [DevProcessSnapshot]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(processes) { process in
                    HStack(spacing: 6) {
                        Text(process.name)
                            .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.9))
                            .padding(.leading, CGFloat(min(process.depth, 6)) * 10)
                        Text(process.commandLine)
                            .font(.system(size: 9.5, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.4))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 4)
                        Text(process.cpuPercent.map { String(format: "%.0f%%", $0) } ?? "–")
                            .font(.system(size: 9.5, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.6))
                            .frame(width: 36, alignment: .trailing)
                        Text("\(process.pid)")
                            .font(.system(size: 9.5, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.35))
                            .frame(width: 44, alignment: .trailing)
                    }
                }
            }
            .padding(10)
        }
    }
}

struct DevMonospaceLog: View {
    let text: String

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Text(text)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.82))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(10)
                Color.clear.frame(height: 1).id("end")
            }
            .onAppear { proxy.scrollTo("end", anchor: .bottom) }
            .onChange(of: text) { _, _ in proxy.scrollTo("end", anchor: .bottom) }
        }
    }
}

// MARK: - Usage

private struct DevUsageGrid: View {
    @ObservedObject private var usage = DevUsageMonitor.shared

    var body: some View {
        Group {
            if usage.cards.isEmpty {
                DevPlaceholder(
                    symbol: usage.isRefreshing ? "hourglass" : "chart.bar.xaxis",
                    text: usage.isRefreshing ? "Reading usage…" : "No Claude Code, Codex, Cursor, Antigravity or Gemini CLI data found on this Mac."
                )
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                        ForEach(usage.cards) { card in
                            DevUsageCardView(card: card)
                        }
                    }
                }
            }
        }
        .onAppear { usage.beginObserving() }
        .onDisappear { usage.endObserving() }
    }
}

private struct DevUsageCardView: View {
    let card: DevUsageCard

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: card.symbol)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(card.tint)
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(card.tint.opacity(0.18)))
                Text(card.title)
                    .font(.system(size: 11.5, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
                Spacer(minLength: 0)
                if !card.daily.isEmpty { DevSparkBars(values: card.daily, tint: card.tint) }
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(card.headline)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if let subtitle = card.subtitle {
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                }
            }
            ForEach(card.meters) { meter in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(meter.label)
                        Spacer()
                        Text("\(Int((meter.usedFraction * 100).rounded()))% used")
                    }
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.1))
                            Capsule()
                                .fill(meter.usedFraction > 0.85 ? Color.red : card.tint)
                                .frame(width: max(3, geometry.size.width * meter.usedFraction))
                        }
                    }
                    .frame(height: 4)
                    if let caption = meter.caption {
                        Text(caption)
                            .font(.system(size: 8.5))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                }
            }
            if !card.stats.isEmpty {
                VStack(spacing: 2) {
                    ForEach(card.stats) { stat in
                        HStack {
                            Text(stat.label).foregroundStyle(.white.opacity(0.45))
                            Spacer()
                            Text(stat.value).foregroundStyle(.white.opacity(0.8)).lineLimit(1)
                        }
                        .font(.system(size: 9.5, weight: .medium))
                    }
                }
            }
            if let footnote = card.footnote {
                Text(footnote)
                    .font(.system(size: 8.5))
                    .foregroundStyle(.white.opacity(0.3))
                    .lineLimit(2)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.06)))
    }
}

private struct DevSparkBars: View {
    let values: [Double]
    let tint: Color

    var body: some View {
        let peak = max(values.max() ?? 0, 0.0001)
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                Capsule()
                    .fill(index == values.count - 1 ? tint : tint.opacity(0.4))
                    .frame(width: 3, height: max(2, 16 * value / peak))
            }
        }
        .frame(height: 16, alignment: .bottom)
        .help("Last 7 days")
    }
}

// MARK: - Terminal

private struct DevTerminalPanel: View {
    @ObservedObject private var runner = DevCommandRunner.shared
    @ObservedObject private var monitor = DevActivityMonitor.shared
    @State private var command = ""
    @State private var recentDirectories: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                directoryMenu
                HStack(spacing: 6) {
                    Text("$")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(.green)
                    NotchSearchField(placeholder: "Run a command…", text: $command, onSubmit: run)
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(.white)
                    if !runner.history.isEmpty {
                        Menu {
                            ForEach(runner.history, id: \.self) { entry in
                                Button(entry) { command = entry }
                            }
                        } label: {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.6))
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .frame(width: 18)
                        .help("Recent commands")
                    }
                }
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(Capsule().fill(Color.white.opacity(0.08)))

                Button(action: run) {
                    Image(systemName: "play.fill").font(.system(size: 10, weight: .bold))
                }
                .buttonStyle(DevPillButtonStyle(tint: .green))
                .disabled(command.trimmingCharacters(in: .whitespaces).isEmpty)
                .help("Run here and show the output")

                Button {
                    let line = command.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !line.isEmpty else { return }
                    DevTerminalBridge.runInNewTerminalWindow(line, directory: runner.directory)
                    command = ""
                } label: {
                    Image(systemName: "macwindow.badge.plus").font(.system(size: 10, weight: .bold))
                }
                .buttonStyle(DevPillButtonStyle(tint: .white))
                .disabled(command.trimmingCharacters(in: .whitespaces).isEmpty)
                .help("Run in a new Terminal window (for interactive commands)")
            }

            if !runner.runs.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 5) {
                        ForEach(runner.runs.reversed()) { run in
                            DevRunChip(run: run, isSelected: run.id == runner.selectedRun?.id)
                                .onTapGesture { runner.selectedRunID = run.id }
                        }
                        if runner.runs.contains(where: { !$0.isRunning }) {
                            Button("Clear") { runner.clearFinished() }
                                .buttonStyle(.plain)
                                .font(.system(size: 9.5, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.45))
                        }
                    }
                }
                .frame(height: 22)
            }

            if let run = runner.selectedRun {
                ZStack(alignment: .topTrailing) {
                    Group {
                        if run.output.isEmpty {
                            DevPlaceholder(symbol: run.isRunning ? "hourglass" : "text.alignleft", text: run.isRunning ? "Waiting for output…" : "No output.")
                        } else {
                            DevMonospaceLog(text: run.output)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.black.opacity(0.35)))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    HStack(spacing: 4) {
                        if run.isRunning {
                            DevIconButton(symbol: "stop.fill", help: "Stop", size: 22) { runner.stop(run.id) }
                        } else {
                            DevIconButton(symbol: "arrow.clockwise", help: "Run again", size: 22) { runner.rerun(run) }
                        }
                        DevIconButton(symbol: "doc.on.doc", help: "Copy output", size: 22) {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(run.output, forType: .string)
                        }
                    }
                    .padding(6)
                }
            } else {
                DevPlaceholder(
                    symbol: "terminal",
                    text: "Commands run in your login shell in the folder on the left. Use the window button for interactive programs."
                )
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.black.opacity(0.25)))
            }
        }
        .onAppear(perform: loadRecentDirectories)
    }

    private var directoryMenu: some View {
        Menu {
            ForEach(recentDirectories, id: \.self) { directory in
                Button(abbreviate(directory)) { runner.setDirectory(directory) }
            }
            Divider()
            Button("Choose Folder…", action: chooseFolder)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "folder.fill").font(.system(size: 9.5))
                Text((runner.directory as NSString).lastPathComponent)
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .lineLimit(1)
            }
            .foregroundStyle(.white.opacity(0.85))
            .padding(.horizontal, 9)
            .frame(height: 28)
            .background(Capsule().fill(Color.white.opacity(0.08)))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(runner.directory)
    }

    private func run() {
        runner.run(command)
        command = ""
    }

    private func loadRecentDirectories() {
        var directories: [String] = []
        for task in monitor.tasks {
            if let directory = DevProcessScanner.workingDirectory(for: task.pid),
               directory != "/", !directories.contains(directory) {
                directories.append(directory)
            }
        }
        for run in runner.runs.reversed() where !directories.contains(run.directory) {
            directories.append(run.directory)
        }
        let home = NSHomeDirectory()
        if !directories.contains(home) { directories.append(home) }
        recentDirectories = Array(directories.prefix(8))
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: runner.directory)
        NSApp.activate(ignoringOtherApps: true)
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                DevCommandRunner.shared.setDirectory(url.path)
                loadRecentDirectories()
            }
        }
    }

    private func abbreviate(_ path: String) -> String {
        let home = NSHomeDirectory()
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}

private struct DevRunChip: View {
    let run: DevCommandRun
    let isSelected: Bool

    private var color: Color {
        switch run.state {
        case .running: return .yellow
        case .finished(let code): return code == 0 ? .green : .red
        case .stopped: return .orange
        case .failedToStart: return .red
        }
    }

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(run.command)
                .font(.system(size: 10, design: .monospaced))
                .lineLimit(1)
                .frame(maxWidth: 150)
            if case .finished(let code) = run.state, code != 0 {
                Text("\(code)").font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundStyle(.red)
            }
        }
        .foregroundStyle(.white.opacity(isSelected ? 0.95 : 0.6))
        .padding(.horizontal, 8)
        .frame(height: 20)
        .background(Capsule().fill(Color.white.opacity(isSelected ? 0.15 : 0.06)))
    }
}

// MARK: - Shared pieces

struct DevToolGlyph: View {
    let tool: DevTool
    var size: CGFloat = 24

    var body: some View {
        Image(systemName: tool.symbol)
            .font(.system(size: size * 0.42, weight: .bold))
            .foregroundStyle(tool.tint)
            .frame(width: size, height: size)
            .background(Circle().fill(tool.tint.opacity(0.2)))
    }
}

struct DevElapsedText: View {
    let startedAt: Date
    var size: CGFloat = 11

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Text(DevTaskFormatting.elapsed(context.date.timeIntervalSince(startedAt)))
                .font(.system(size: size, weight: .semibold, design: .monospaced))
        }
    }
}

struct DevCountBadge: View {
    let count: Int
    let tint: Color

    var body: some View {
        Text("\(count)")
            .font(.system(size: 9.5, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(tint.opacity(0.55)))
    }
}

private struct DevChip<Accessory: View>: View {
    let symbol: String
    let text: String?
    let tint: Color
    var action: (() -> Void)?
    @ViewBuilder var accessory: () -> Accessory

    init(symbol: String, text: String?, tint: Color, action: (() -> Void)? = nil, @ViewBuilder accessory: @escaping () -> Accessory) {
        self.symbol = symbol
        self.text = text
        self.tint = tint
        self.action = action
        self.accessory = accessory
    }

    var body: some View {
        let label = HStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: 8.5, weight: .bold)).foregroundStyle(tint.opacity(0.85))
            if let text {
                Text(text).font(.system(size: 10, weight: .medium)).lineLimit(1)
            }
            accessory()
        }
        .foregroundStyle(.white.opacity(0.8))
        .padding(.horizontal, 7)
        .frame(height: 19)
        .background(Capsule().fill(Color.white.opacity(0.07)))

        if let action {
            Button(action: action) { label }.buttonStyle(.plain)
        } else {
            label
        }
    }
}

private extension DevChip where Accessory == EmptyView {
    init(symbol: String, text: String?, tint: Color, action: (() -> Void)? = nil) {
        self.init(symbol: symbol, text: text, tint: tint, action: action) { EmptyView() }
    }
}

struct DevIconButton: View {
    let symbol: String
    let help: String
    var tint: Color = .white
    var size: CGFloat = 28
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.38, weight: .bold))
                .foregroundStyle(tint.opacity(0.85))
                .frame(width: size, height: size)
                .background(Circle().fill(tint.opacity(tint == .white ? 0.08 : 0.2)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

struct DevPillButtonStyle: ButtonStyle {
    let tint: Color
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(tint.opacity(isEnabled ? 0.95 : 0.35))
            .padding(.horizontal, 11)
            .frame(height: 28)
            .background(Capsule().fill(tint.opacity(configuration.isPressed ? 0.3 : 0.16)))
    }
}

private struct DevPlaceholder: View {
    let symbol: String
    let text: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 16))
                .foregroundStyle(.white.opacity(0.3))
            Text(text)
                .font(.system(size: 10.5))
                .foregroundStyle(.white.opacity(0.45))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}