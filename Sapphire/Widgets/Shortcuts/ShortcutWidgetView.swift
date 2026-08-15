//
//  ShortcutWidgetView.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-08-11.
//

import SwiftUI

struct ShortcutWidgetView: View {
    @EnvironmentObject var settings: SettingsModel

    private let rows: [GridItem] = Array(repeating: .init(.flexible(), spacing: 0), count: 3)
    private let widgetHeight: CGFloat = 90
    private let horizontalPadding: CGFloat = 7

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if settings.settings.selectedShortcuts.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "square.grid.3x1.folder.badge.plus")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text("Add shortcuts")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(height: widgetHeight - 8)
                .padding(.horizontal, 16)

            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHGrid(rows: rows, spacing: 12) {
                        ForEach(settings.settings.selectedShortcuts) { shortcut in
                            ShortcutIconView(shortcut: shortcut)
                        }
                    }
                    .padding(.horizontal, 2)
                }
                .fixedSize(horizontal: true, vertical: false)
                .frame(height: widgetHeight - 8)
            }
        }
        .padding(.horizontal, horizontalPadding)
        .frame(height: widgetHeight)
    }
}

fileprivate struct ShortcutIconView: View {
    let shortcut: ShortcutInfo
    @State private var iconImage: NSImage?

    var body: some View {
        Button(action: {
            ShortcutsManager.shared.runShortcut(id: shortcut.id)
        }) {
            Image(nsImage: iconImage ?? ShortcutsManager.shared.getIcon(for: shortcut))
                .resizable()
                .scaledToFit()
                .font(.system(size: 2, weight: .bold))
                .frame(width: 22, height: 22)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .help(shortcut.name)
        }
        .buttonStyle(.plain)
        .onAppear {
            self.iconImage = ShortcutsManager.shared.getIcon(for: shortcut)
        }
    }
}