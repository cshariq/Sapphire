//
//  DevActivitySettingsView.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-12
//

import SwiftUI

struct DevActivitySettingsView: View {
    @EnvironmentObject var settings: SettingsEditingSession
    @ObservedObject private var monitor = DevActivityMonitor.shared

    private func kindBinding(_ kind: DevTaskKind, keyPath: WritableKeyPath<Settings, Set<String>>) -> Binding<Bool> {
        Binding(
            get: { settings.settings[keyPath: keyPath].contains(kind.rawValue) },
            set: { isOn in
                if isOn {
                    settings.settings[keyPath: keyPath].insert(kind.rawValue)
                } else {
                    settings.settings[keyPath: keyPath].remove(kind.rawValue)
                }
            }
        )
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                Text("Dev Activity")
                    .font(.largeTitle.bold())
                    .padding(.bottom)

                detectionSection
                whatIsRunningSection
                accuracySection
                stayAwakeSection
                supportedToolsSection
            }
            .padding(25)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .onAppear { monitor.refreshNow() }
    }

    // MARK: - Sections

    private var detectionSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            ToggleRow(
                title: "Show Running Work in the Notch",
                description: "Surface a live activity while an AI agent, a build, or a terminal command is running.",
                isOn: $settings.settings.devActivityEnabled
            )

            Divider().padding(.leading, 20)

            ToggleRow(
                title: "AI Agents",
                description: "Claude, Codex, Cursor, Antigravity, GitHub Copilot, Devin/Windsurf, Gemini, Aider, and other coding agents.",
                isOn: kindBinding(.ai, keyPath: \.devActivityKinds)
            )

            Divider().padding(.leading, 20)

            ToggleRow(
                title: "Builds & Tests",
                description: "Xcode, Android Studio and Gradle, Swift, cargo, Go, npm and friends, make, Docker, and test runs.",
                isOn: kindBinding(.build, keyPath: \.devActivityKinds)
            )

            Divider().padding(.leading, 20)

            ToggleRow(
                title: "Terminal Commands",
                description: "Anything long-running you started in Terminal, iTerm, Warp, Ghostty, or an editor's built-in terminal. Watchers and dev servers are ignored, since they never finish.",
                isOn: kindBinding(.command, keyPath: \.devActivityKinds)
            )

            Divider().padding(.leading, 20)

            ToggleRow(
                title: "Prioritize Over Other Activities",
                description: "Rank running work alongside notifications instead of with the ambient readouts, so it shows even while music is playing.",
                isOn: $settings.settings.devActivityHighPriority
            )
        }
        .modifier(SettingsContainerModifier())
    }

    private var whatIsRunningSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Detected Right Now")
                    .font(.system(size: 14, weight: .medium))
                Spacer()
                Button("Refresh") { monitor.refreshNow() }
                    .buttonStyle(.borderless)
                    .font(.caption)
            }
            .padding()

            Divider().padding(.leading, 20)

            if monitor.tasks.isEmpty {
                Text(settings.settings.devActivityEnabled || settings.settings.caffeinateAutoDuringTasks
                     ? "Nothing running. Start a build or send an agent a prompt and it will appear here."
                     : "Detection is off. Turn on the notch activity or auto-caffeinate above to start watching.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding()
            } else {
                ForEach(monitor.tasks) { task in
                    DevTaskRow(task: task)
                    if task.id != monitor.tasks.last?.id {
                        Divider().padding(.leading, 20)
                    }
                }
            }
        }
        .modifier(SettingsContainerModifier())
    }

    private var accuracySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            ToggleRow(
                title: "Detect Agents Inside Editors",
                description: "Cursor, Antigravity, Devin, VS Code and Zed keep their agent in the editor process, so activity there is inferred from how hard it is working. Turn this off if idle typing registers as a running agent.",
                isOn: $settings.settings.devActivityDetectIDEAgents
            )

            Divider().padding(.leading, 20)

            VStack(alignment: .leading, spacing: 4) {
                CustomSliderRowView(
                    label: "Sensitivity",
                    value: $settings.settings.devActivitySensitivity,
                    range: 0.4...2.0,
                    specifier: "%.1f×"
                )
                Text("Lower catches quieter work but may misread a busy editor as a running agent. Higher only reports sustained activity. Command-line tools that only exist while they run are unaffected.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
        .modifier(SettingsContainerModifier())
    }

    private var stayAwakeSection: some View { CaffeineAutoTaskSettingsView() }

    private var supportedToolsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("How Detection Works")
                .font(.system(size: 14, weight: .medium))

            Text("""
            Sapphire watches your own processes — nothing is read from inside an app, no accessibility \
            permission is used, and nothing leaves the Mac.

            Tools that only exist while they run (xcodebuild, cargo, gradle, npm run build, a command you \
            typed) are detected the moment they start. Tools that stay resident between turns (Claude, \
            Codex, an editor's built-in agent, a Gradle daemon) are reported only while they are actually \
            working, which is why sensitivity exists.
            """)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(SettingsContainerModifier())
    }
}

private struct DevTaskRow: View {
    let task: DevTask

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: task.tool.symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(task.tool.tint)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(.system(size: 13, weight: .medium))
                HStack(spacing: 6) {
                    Text(task.kind.displayName)
                    if !task.detail.isEmpty {
                        Text("·")
                        Text(task.detail)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Text(DevTaskFormatting.elapsed(task.elapsed))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

enum DevTaskFormatting {
    static func elapsed(_ interval: TimeInterval) -> String {
        let total = Int(max(0, interval))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60

        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, seconds) }
        return String(format: "%d:%02d", minutes, seconds)
    }
}

struct CaffeineAutoTaskSettingsView: View {
    @EnvironmentObject var settings: SettingsEditingSession
    @ObservedObject private var monitor = DevActivityMonitor.shared

    private var unmonitoredKinds: [DevTaskKind] {
        DevTaskKind.allCases.filter {
            settings.settings.caffeinateAutoTaskKinds.contains($0.rawValue)
                && !settings.settings.devActivityKinds.contains($0.rawValue)
        }
    }

    private var runningSummary: String {
        let kinds = settings.settings.caffeinateAutoTaskKinds
        let relevant = monitor.tasks.filter { kinds.contains($0.kind.rawValue) }
        guard let first = relevant.first else { return "Nothing running" }
        if relevant.count == 1 { return first.title }
        return "\(first.title) + \(relevant.count - 1) more"
    }

    private func kindBinding(_ kind: DevTaskKind) -> Binding<Bool> {
        Binding(
            get: { settings.settings.caffeinateAutoTaskKinds.contains(kind.rawValue) },
            set: { isOn in
                if isOn {
                    settings.settings.caffeinateAutoTaskKinds.insert(kind.rawValue)
                } else {
                    settings.settings.caffeinateAutoTaskKinds.remove(kind.rawValue)
                }
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ToggleRow(
                title: "Keep Awake While a Task Runs",
                description: "Automatically turn caffeinate on when an AI agent, build, or terminal command starts, and off again once everything finishes. Caffeinate you switched on yourself is never turned off by this.",
                isOn: $settings.settings.caffeinateAutoDuringTasks
            )

            if settings.settings.caffeinateAutoDuringTasks {
                Divider().padding(.leading, 20)

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Currently Detected")
                        Text(runningSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Circle()
                        .fill(monitor.isBusy ? Color.green : Color.secondary.opacity(0.4))
                        .frame(width: 8, height: 8)
                }
                .padding()

                Divider().padding(.leading, 20)

                ToggleRow(title: "AI Agents", description: "", isOn: kindBinding(.ai))

                Divider().padding(.leading, 20)

                ToggleRow(title: "Builds & Tests", description: "", isOn: kindBinding(.build))

                Divider().padding(.leading, 20)

                ToggleRow(
                    title: "Terminal Commands",
                    description: "Off by default — not every long command is worth holding the display on for.",
                    isOn: kindBinding(.command)
                )

                Divider().padding(.leading, 20)

                VStack(alignment: .leading, spacing: 4) {
                    CustomSliderRowView(
                        label: "Keep Awake After Finishing",
                        value: $settings.settings.caffeinateAutoTaskGrace,
                        range: 0...600,
                        specifier: "%.0fs"
                    )
                    Text("Grace period after the last task ends, so back-to-back runs don't let the display sleep in between. Detection settings live in Dev Activity.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if !unmonitoredKinds.isEmpty {
                        Label(
                            "\(unmonitoredKinds.map(\.displayName).formatted(.list(type: .and))) "
                            + "\(unmonitoredKinds.count == 1 ? "is" : "are") switched off in Dev Activity, "
                            + "so nothing of that kind will keep the Mac awake.",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .font(.caption)
                        .foregroundStyle(.orange)
                    }
                }
                .padding()
            }
        }
        .modifier(SettingsContainerModifier())
        .onAppear { monitor.refreshNow() }
    }
}