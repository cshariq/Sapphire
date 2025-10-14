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

    var body: some View {
        VStack(alignment: .leading) {
            if settings.settings.selectedShortcuts.isEmpty {
                Text("No shortcuts added.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(width: 100, height: 60)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHGrid(rows: rows, spacing: 12) {
                        ForEach(settings.settings.selectedShortcuts) { shortcut in
                            ShortcutIconView(shortcut: shortcut)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 7)
        .frame(height: 90)
    }
}

fileprivate struct ShortcutIconView: View {
    let shortcut: ShortcutInfo
    @State private var iconImage: NSImage?

    var body: some View {
        Button(action: {
            ShortcutsManager.shared.runShortcut(id: shortcut.id)
        }) {
            Image(nsImage: iconImage ?? NSImage())
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