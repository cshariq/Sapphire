//
//  ClipboardSettingsRows.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-10-07
//

import SwiftUI

struct PlainTextPasteShortcutRow: View {
    @EditingSettings var settings: SettingsEditingSession
    @ObservedObject private var shortcutRecorder = GlobalShortcutRecorder.shared

    private static let recordingIdentifier = "plainTextPasteShortcut"

    private var isRecording: Bool {
        shortcutRecorder.isRecording && shortcutRecorder.recordingIdentifier == Self.recordingIdentifier
    }

    private var label: String {
        let shortcut = settings.settings.systemEnhancePasteAsPlainShortcut
        return "\(KeyboardShortcutHelper.description(for: shortcut.modifiers))\(shortcut.key)"
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Shortcut")
                    .font(.system(size: 14, weight: .medium))
                Text("Uses the app's own Paste and Match Style when it has one. Must include ⌘ or ⌃. Plain ⌘V is never changed.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            if !isRecording {
                Text(label)
                    .font(.caption.monospaced())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(0.07))
                    .clipShape(Capsule())
            }
            Button(isRecording ? String(localized: "Cancel") : String(localized: "Record…")) {
                if isRecording {
                    shortcutRecorder.stopRecording()
                } else {
                    shortcutRecorder.startRecording(identifier: Self.recordingIdentifier) { key, modifiers in
                        guard modifiers.contains(.command) || modifiers.contains(.control) else {
                            NSSound.beep()
                            return
                        }
                        settings.settings.systemEnhancePasteAsPlainShortcut = KeyboardShortcut(key: key, modifiers: modifiers)
                    }
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding()
    }
}

struct ClipboardStorageLimitRow: View {
    @EditingSettings var settings: SettingsEditingSession

    var body: some View {
        CustomSliderRowView(
            label: "Storage Limit",
            value: Binding(
                get: { Double(settings.settings.clipboardHistoryStorageLimitMB) },
                set: { settings.settings.clipboardHistoryStorageLimitMB = Int($0.rounded()) }
            ),
            range: Double(ClipboardHistoryBudget.storageLimitRangeMB.lowerBound)...Double(ClipboardHistoryBudget.storageLimitRangeMB.upperBound),
            specifier: "%.0f MB"
        )
        .help("Oldest items go first once history passes this size. Pinned items are always kept.")
    }
}

struct ClipboardIgnoredAppsRow: View {
    @EditingSettings var settings: SettingsEditingSession
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ignored Apps")
                        .font(.system(size: 14, weight: .medium))
                    Text(settings.settings.clipboardIgnoredAppBundleIDs.count == 1
                        ? String(localized: "Nothing copied in these apps is saved. 1 app ignored.")
                        : String(localized: "Nothing copied in these apps is saved. \(String(settings.settings.clipboardIgnoredAppBundleIDs.count)) apps ignored."))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button(isExpanded ? String(localized: "Done") : String(localized: "Edit…")) { isExpanded.toggle() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            if isExpanded {
                AppTogglesListView(
                    isEnabled: { app in $settings.settings.clipboardIgnoredAppBundleIDs.membership(of: app.id) },
                    showSearch: true
                )
                HStack {
                    Spacer()
                    Button("Restore Password Manager Defaults") {
                        var ids = settings.settings.clipboardIgnoredAppBundleIDs
                        for id in ClipboardIgnoredApps.defaultBundleIDs where !ids.contains(id) { ids.append(id) }
                        settings.settings.clipboardIgnoredAppBundleIDs = ids
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                }
            }
        }
        .padding()
    }
}