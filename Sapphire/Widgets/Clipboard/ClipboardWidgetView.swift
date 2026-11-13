//
//  ClipboardWidgetView.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-10

import SwiftUI
import AppKit

@MainActor
private func performCopy(_ item: ClipboardItem, via manager: ClipboardManager) {
    if !manager.copyItem(item) { NSSound.beep() }
}

@MainActor
private func performShare(_ item: ClipboardItem, via manager: ClipboardManager) {
    if !manager.shareItem(item) { NSSound.beep() }
}

extension ClipboardItemKind {
    var spec: (systemImage: String, color: Color) {
        switch self {
        case .text:
            return ("doc.text", .blue)
        case .image:
            return ("photo", .purple)
        case .file:
            return ("doc", .teal)
        case .folder:
            return ("folder.fill", .orange)
        }
    }

    var displayName: String {
        switch self {
        case .text:
            return String(localized: "Text")
        case .image:
            return String(localized: "Image")
        case .file:
            return String(localized: "File")
        case .folder:
            return String(localized: "Folder")
        }
    }
}

struct ClipboardWidgetView: View {
    @ObservedObject private var clipboardManager = ClipboardManager.shared

    var body: some View {
        NotchMiniListWidget(
            title: String(localized: "Clipboard"),
            systemImage: "list.clipboard",
            tint: .blue,
            gradient: [Color.blue.opacity(0.35), Color.cyan.opacity(0.16)],
            count: clipboardManager.recentItems.count,
            items: Array(clipboardManager.recentItems.prefix(3)),
            emptyText: String(localized: "Nothing copied yet")
        ) { item in
            let spec = item.kind.spec
            if item.isImage {
                ClipboardItemThumbnailView(
                    item: item,
                    size: 14,
                    cornerRadius: 3,
                    fallbackSystemImage: spec.systemImage,
                    fallbackTint: spec.color
                )
            } else {
                Image(systemName: spec.systemImage)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(spec.color)
                    .frame(width: 14)
            }
            Text(item.preview)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.primary.opacity(0.9))
                .lineLimit(1)
        }
        .onAppear {
            clipboardManager.startMonitoring()
        }
        .contentShape(Rectangle())
    }
}

struct ClipboardPlayerView: View {
    static func itemCountDescription(_ count: Int) -> String {
        String(localized: "\(String(count)) items")
    }

    @Binding var navigationStack: [NotchWidgetMode]
    @ObservedSettings var settings: SettingsObserver
    @ObservedObject private var clipboardManager = ClipboardManager.shared
    @State private var searchText = ""
    @State private var showSearch = false
    @State private var filterImagesOnly = false
    @StateObject private var search = ClipboardSearchModel()

    private var filteredItems: [ClipboardItem] {
        let results = search.results
        return results.filter(\.isPinned) + results.filter { !$0.isPinned }
    }

    private func refreshSearch(debounce: Bool) {
        search.update(
            items: clipboardManager.recentItems,
            revision: clipboardManager.historyRevision,
            kinds: filterImagesOnly ? [.image] : nil,
            query: searchText,
            debounce: debounce
        )
    }

    var body: some View {
        NotchSwipeListPanel(
            title: String(localized: "Clipboard"),
            subtitle: Self.itemCountDescription(clipboardManager.recentItems.count),
            accent: .blue,
            searchPlaceholder: String(localized: "Search clipboard"),
            searchText: $searchText,
            showSearch: $showSearch,
            width: 480,
            items: Array(filteredItems.prefix(40)),
            leadingAction: { action(settings.settings.swipeActionSettings.clipboardLeading, for: $0) },
            trailingAction: { action(settings.settings.swipeActionSettings.clipboardTrailing, for: $0) }
        ) {
            NotchCapsuleIconButton(systemName: "photo", isActive: filterImagesOnly, activeTint: .blue) {
                filterImagesOnly.toggle()
            }
            NotchCapsuleIconButton(systemName: "trash", activeTint: .blue) {
                clipboardManager.clearHistory()
            }
        } row: { item in
            clipboardRow(item)
        } emptyState: {
            NotchListEmptyState(
                systemImage: "list.clipboard",
                tint: .blue,
                title: filterImagesOnly ? String(localized: "No images") : (searchText.isEmpty ? String(localized: "Clipboard is empty") : String(localized: "No matches")),
                message: searchText.isEmpty ? String(localized: "Copy text or images to build history.") : String(localized: "Try a different search.")
            )
        }
        .onAppear {
            clipboardManager.startMonitoring()
            clipboardManager.beginHighPriorityMonitoring()
            refreshSearch(debounce: false)
        }
        .onDisappear {
            clipboardManager.endHighPriorityMonitoring()
        }
        .onChange(of: searchText) { _, _ in refreshSearch(debounce: true) }
        .onChange(of: filterImagesOnly) { _, _ in refreshSearch(debounce: false) }
        .onReceive(clipboardManager.$recentItems.dropFirst()) { _ in
            DispatchQueue.main.async { refreshSearch(debounce: false) }
        }
    }

    private func clipboardRow(_ item: ClipboardItem) -> some View {
        let tint = item.kind.spec.color
        return HStack(alignment: .center, spacing: 12) {
            thumbnail(for: item)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.preview)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 6) {
                    Text(item.kind.displayName)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(tint.opacity(0.9))
                    Text("·")
                        .foregroundStyle(.tertiary)
                    RelativeMinuteText(date: item.copiedAt)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if item.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.yellow.opacity(0.85))
                    }
                }
            }

            Spacer(minLength: 0)

            CopyAgainButton(
                tint: tint,
                onTap: { performCopy(item, via: clipboardManager) }
            )
            .help("Copy again")
        }
        .padding(12)
        .notchTintedCard(tint)
        .contentShape(Rectangle())
        .onTapGesture {
            performCopy(item, via: clipboardManager)
        }
        .contextMenu {
            Button("Copy") { performCopy(item, via: clipboardManager) }
            Button(item.isPinned ? "Unpin" : "Pin") { clipboardManager.togglePin(id: item.id) }
            Button("Share…") { performShare(item, via: clipboardManager) }
            Button("Delete", role: .destructive) { clipboardManager.removeItem(id: item.id) }
        }
    }

    private struct CopyAgainButton: View {
        let tint: Color
        let onTap: () -> Void

        @State private var copied = false

        var body: some View {
            Button {
                onTap()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { copied = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    withAnimation(.easeInOut(duration: 0.25)) { copied = false }
                }
            } label: {
                ZStack {
                    NotchCapsuleIconLabel(
                        systemName: copied ? "checkmark" : "doc.on.doc",
                        isActive: copied,
                        activeTint: tint
                    )
                    .scaleEffect(copied ? 1.12 : 1.0)
                    .rotationEffect(.degrees(copied ? -6 : 0))
                    .animation(.spring(response: 0.35, dampingFraction: 0.55), value: copied)
                }
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func thumbnail(for item: ClipboardItem) -> some View {
        let spec = item.kind.spec
        if item.isImage {
            ClipboardItemThumbnailView(
                item: item,
                size: 44,
                cornerRadius: 10,
                fallbackSystemImage: spec.systemImage,
                fallbackTint: spec.color,
                strokeColor: MaterialChartPalette.outline
            )
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(spec.color.opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: spec.systemImage)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(spec.color)
            }
        }
    }

    private func action(_ configuredAction: ClipboardSwipeAction, for item: ClipboardItem) -> NotchSwipeAction? {
        switch configuredAction {
        case .none:
            return nil
        case .share:
            return NotchSwipeAction(systemImage: "square.and.arrow.up", tint: .blue) {
                performShare(item, via: clipboardManager)
            }
        case .copy:
            return NotchSwipeAction(systemImage: "doc.on.doc", tint: .cyan) {
                performCopy(item, via: clipboardManager)
            }
        case .delete:
            return NotchSwipeAction(systemImage: "trash.fill", tint: .red) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                    clipboardManager.removeItem(id: item.id)
                }
            }
        }
    }
}
