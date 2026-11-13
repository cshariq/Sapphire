//
//  OverviewSettingsView.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-26

import AppKit
import SwiftUI

struct OverviewSettingsView: View {
    @EditingSettings var settings: SettingsEditingSession
    @StateObject private var assistant = SettingsAssistant()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Overview").font(.largeTitle.bold())
                    Text("Ask about any setting, get suggestions, or have Sapphire change things for you.")
                        .foregroundStyle(.secondary)
                }

                SettingsAssistantCard(assistant: assistant)
                DisplaySettingsView()
            }
            .padding(25)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .onAppear { assistant.attach(settings) }
    }
}

enum SettingsNavigation {
    static func open(_ section: SettingsSection) {
        NotificationCenter.default.post(name: NSNotification.Name("SapphireSelectSection"), object: section.rawValue)
    }
}

// MARK: - Assistant

private struct SettingsAssistantCard: View {
    @ObservedObject var assistant: SettingsAssistant
    @State private var draft = ""
    @FocusState private var isInputFocused: Bool

    private let starters = [
        String(localized: "Can I hide the notch when nothing is playing?"),
        String(localized: "Suggest settings to save battery"),
        String(localized: "Hide live activities in full screen"),
        String(localized: "What can I change about the music player?")
    ]

    var body: some View {
        SettingsCard(title: "Ask Sapphire", description: "Runs on-device with Apple Intelligence. Changes apply right away and can be undone.") {
            VStack(alignment: .leading, spacing: 12) {
                if let reason = assistant.unavailableReason {
                    InfoContainer(text: Text(verbatim: reason), iconName: "apple.intelligence", color: .orange)
                }

                if assistant.messages.isEmpty {
                    starterPrompts
                } else {
                    conversation
                }

                inputBar
            }
            .padding([.horizontal, .bottom])
        }
    }

    private var starterPrompts: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Try asking")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 8, alignment: .leading)], alignment: .leading, spacing: 8) {
                ForEach(starters, id: \.self) { starter in
                    Button(starter) { assistant.send(starter) }
                        .buttonStyle(.plain)
                        .font(.callout)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Color.white.opacity(0.08), in: Capsule())
                        .disabled(assistant.unavailableReason != nil)
                }
            }
        }
    }

    private var conversation: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(assistant.messages) { message in
                MessageView(message: message, assistant: assistant)
            }
            if assistant.isResponding {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Thinking…").font(.callout).foregroundStyle(.secondary)
                }
            }
            HStack {
                Spacer()
                Button("Clear") { assistant.clearConversation() }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .disabled(assistant.isResponding)
            }
        }
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("Ask about a setting, or say what to change…", text: $draft)
                .textFieldStyle(.plain)
                .focused($isInputFocused)
                .onSubmit(send)
                .padding(10)
                .background(Color.black.opacity(0.2), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            Button(action: send) {
                Image(systemName: "arrow.up.circle.fill").font(.system(size: 22))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
            .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty || assistant.isResponding || assistant.unavailableReason != nil)
            .keyboardShortcut(.return, modifiers: [])
        }
    }

    private func send() {
        let text = draft
        draft = ""
        assistant.send(text)
    }
}

private struct MessageView: View {
    let message: SettingsAssistant.Message
    @ObservedObject var assistant: SettingsAssistant

    var body: some View {
        switch message.role {
        case .user:
            HStack {
                Spacer(minLength: 60)
                Text(verbatim: message.text)
                    .textSelection(.enabled)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.accentColor.opacity(0.25), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        case .assistant:
            VStack(alignment: .leading, spacing: 8) {
                Text(verbatim: message.text)
                    .textSelection(.enabled)
                    .foregroundStyle(message.isError ? Color.orange : Color.primary)
                ForEach(message.changes) { change in
                    ChangeRow(change: change, isUndone: assistant.undoneChangeIDs.contains(change.id)) {
                        assistant.undo(change)
                    }
                }
                if !message.suggestions.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(message.suggestions) { entry in
                            SettingsEntryRow(entry: entry)
                            if entry != message.suggestions.last { Divider().padding(.leading, 12) }
                        }
                    }
                    .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct ChangeRow: View {
    let change: SettingsIndex.Change
    let isUndone: Bool
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isUndone ? "arrow.uturn.backward.circle" : "checkmark.circle.fill")
                .foregroundStyle(isUndone ? Color.secondary : Color.green)
            Text("\(change.entry.displayTitle): \(change.entry.displayValue(change.oldValue)) → \(change.entry.displayValue(change.newValue))")
                .font(.callout)
                .strikethrough(isUndone)
            Spacer()
            if isUndone {
                Text("Undone").font(.caption).foregroundStyle(.secondary)
            } else {
                Button("Undo", action: onUndo).buttonStyle(.plain).font(.caption).foregroundStyle(Color.accentColor)
            }
            if let section = change.entry.section {
                Button("Open") { SettingsNavigation.open(section) }
                    .buttonStyle(.plain).font(.caption).foregroundStyle(Color.accentColor)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.green.opacity(isUndone ? 0.03 : 0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct SettingsEntryRow: View {
    @EditingSettings var settings: SettingsEditingSession
    let entry: SettingsIndex.Entry

    private var value: SettingsIndex.Value? {
        SettingsIndex.value(of: entry.key, in: settings.settings.value)
    }

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.displayTitle).font(.callout)
                if let section = entry.section {
                    Text(section.label).font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            control
            if let section = entry.section {
                Button {
                    SettingsNavigation.open(section)
                } label: {
                    Image(systemName: "arrow.up.forward.square")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Open \(section.label) settings")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var control: some View {
        switch value {
        case .bool(let on)?:
            SettingsSwitch(title: Text(verbatim: entry.displayTitle), isOn: Binding(get: { on }, set: { set($0 ? "on" : "off") }))
        case .text(let current)? where entry.options != nil:
            Picker("", selection: Binding(get: { current }, set: { set($0) })) {
                ForEach(entry.options ?? [], id: \.self) { option in
                    Text(verbatim: entry.displayOption(option)).tag(option)
                }
            }
            .labelsHidden()
            .frame(maxWidth: 150)
        case let current?:
            Text(verbatim: entry.displayValue(current)).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
        case nil:
            EmptyView()
        }
    }

    private func set(_ raw: String) {
        if case .success(let (updated, _)) = SettingsIndex.applying(key: entry.key, rawValue: raw, to: settings.settings.value) {
            settings.settings.value = updated
        }
    }
}