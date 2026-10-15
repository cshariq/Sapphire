//
//  MenuBarLayoutEditorView.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-10-12
//

import AppKit
import SwiftUI

struct MenuBarLayoutEditorView: View {
    @EditingSettings var settings: SettingsEditingSession
    @StateObject private var model = MenuBarLayoutEditorModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Menu Bar Layout").font(.headline)
                    Text("Choose where each app's items go. Option-click the control item to arrange them in the menu bar instead; Sapphire learns the new layout when you click it again.")
                        .font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                Button("Refresh") { model.reload() }
                    .buttonStyle(.bordered).controlSize(.small)
            }
            .padding()

            ForEach(model.rows) { row in
                Divider().padding(.leading, 20)
                rowView(row)
            }

            Divider().padding(.leading, 20)
            ToggleRow(
                title: "Show Hidden Items in a Bar",
                description: "Clicking the control item opens a bar under the menu bar with the hidden items instead of making room for them. Useful when the notch leaves no space",
                isOn: $settings.settings.menuBarUseHiddenItemsBar
            )

            InfoContainer(
                text: "macOS 27 shows and hides all of an app's items together. While items are hidden, Apple items not listed here (Focus, Now Playing, Siri, Live Activities) and apps that aren't in the Applications folder are hidden too. Clicking the clock still opens Notification Center.",
                iconName: "info.circle",
                color: .blue
            )
            .padding()
        }
        .modifier(SettingsContainerModifier())
        .onAppear { model.reload() }
        .onReceive(NotificationCenter.default.publisher(for: .menuBarSectionsDidChange)) { _ in model.refreshSections() }
    }

    private func rowView(_ row: MenuBarLayoutEditorModel.Row) -> some View {
        HStack(spacing: 12) {
            Group {
                if let icon = row.icon {
                    Image(nsImage: icon).resizable().scaledToFit()
                } else {
                    Image(systemName: row.symbolName).font(.system(size: 15, weight: .medium)).foregroundStyle(.secondary)
                }
            }
            .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 1) {
                Text(row.title).font(.system(size: 14, weight: .medium)).lineLimit(1)
                if !row.isRunning {
                    Text("Not running").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 12)
            Picker("", selection: Binding(
                get: { row.section },
                set: { model.assign($0, to: row) }
            )) {
                ForEach(availableSections, id: \.self) { section in
                    Text(section.title).tag(section)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: availableSections.count == 3 ? 270 : 180)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private var availableSections: [MenuBarSectionKind] {
        settings.settings.enableAlwaysHiddenSection ? MenuBarSectionKind.allCases : [.shown, .hidden]
    }
}

@MainActor
final class MenuBarLayoutEditorModel: ObservableObject {
    struct Row: Identifiable, Equatable {
        let id: String
        let title: String
        let icon: NSImage?
        let symbolName: String
        let isRunning: Bool
        var section: MenuBarSectionKind
    }

    @Published private(set) var rows: [Row] = []

    func reload() {
        MenuBarItemCatalog.shared.start()
        MenuBarItemCatalog.shared.items(maxAge: 1) { [weak self] items in
            self?.build(from: items)
        }
    }

    func refreshSections() {
        let store = MenuBarSectionStore.shared
        rows = rows.map { row in
            var row = row
            row.section = store.section(for: row.id)
            return row
        }
    }

    func assign(_ section: MenuBarSectionKind, to row: Row) {
        MenuBarSectionStore.shared.set(section, for: row.id, name: row.title)
        refreshSections()
    }

    private func build(from items: [MenuBarStatusItem]) {
        let store = MenuBarSectionStore.shared
        let ownBundleID = Bundle.main.bundleIdentifier
        let agentPID = MenuBarAgentHost.agentPID

        var appRows: [String: Row] = [:]
        for pid in Set(items.map(\.pid)) where pid != agentPID {
            guard let app = NSRunningApplication(processIdentifier: pid),
                  let key = MenuBarSectionStore.key(for: app), key != ownBundleID else { continue }
            appRows[key] = Row(
                id: key, title: app.localizedName ?? key, icon: app.icon, symbolName: "app",
                isRunning: true, section: store.section(for: key)
            )
        }
        for (key, section) in store.assignments where appRows[key] == nil && !key.hasPrefix("system:") {
            appRows[key] = Row(
                id: key, title: store.names[key] ?? key,
                icon: NSWorkspace.shared.urlForApplication(withBundleIdentifier: key).map { NSWorkspace.shared.icon(forFile: $0.path) },
                symbolName: "app", isRunning: false, section: section
            )
        }

        let systemRows = MenuBarSystemItem.allCases.map { item in
            Row(id: item.key, title: item.title, icon: nil, symbolName: item.symbolName, isRunning: true, section: store.section(for: item.key))
        }
        rows = appRows.values.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending } + systemRows
    }
}