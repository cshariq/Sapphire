//
//  ClipboardWidgetView.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-10

import SwiftUI
import AppKit

struct ClipboardWidgetView: View {
    @ObservedObject private var clipboardManager = ClipboardManager.shared

    private let maxHeight: CGFloat = 96

    private var suggestions: [ClipboardItem] {
        Array(clipboardManager.recentItems.prefix(3))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.blue.opacity(0.35), Color.cyan.opacity(0.16)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 26, height: 26)
                    Image(systemName: "list.clipboard")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.blue)
                }
                Text("Clipboard")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                Spacer(minLength: 0)
                Text("\(clipboardManager.recentItems.count)")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(MaterialChartPalette.onSurfaceVariant)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(MaterialChartPalette.surfaceVariant)
                    .clipShape(Capsule())
            }

            if suggestions.isEmpty {
                Text("Nothing copied yet")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(MaterialChartPalette.onSurfaceVariant)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(suggestions) { item in
                        suggestionRow(item)
                    }
                }
            }
        }
        .frame(width: 176, height: maxHeight, alignment: .topLeading)
        .clipped()
        .onAppear {
            clipboardManager.startMonitoring()
        }
    }

    private func suggestionRow(_ item: ClipboardItem) -> some View {
        HStack(spacing: 6) {
            if item.isImage, let data = item.imagePNGData, let nsImage = NSImage(data: data) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 14, height: 14)
                    .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            } else {
                Image(systemName: item.isImage ? "photo" : "doc.text")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(item.isImage ? .purple : .blue)
                    .frame(width: 14)
            }
            Text(item.preview)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.primary.opacity(0.9))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(MaterialChartPalette.surfaceContainer)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture {
            clipboardManager.copyItem(item)
        }
    }
}

struct ClipboardPlayerView: View {
    @Binding var navigationStack: [NotchWidgetMode]
    @EnvironmentObject var settings: SettingsModel
    @ObservedObject private var clipboardManager = ClipboardManager.shared
    @State private var searchText = ""
    @State private var showSearch = false
    @State private var filterImagesOnly = false

    private var filteredItems: [ClipboardItem] {
        var items = clipboardManager.recentItems
        if filterImagesOnly {
            items = items.filter(\.isImage)
        }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return items }
        return items.filter {
            $0.preview.localizedCaseInsensitiveContains(query)
                || ($0.textContent?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar

            if showSearch {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    NotchSearchField(placeholder: "Search clipboard", text: $searchText, autofocus: true)
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(MaterialChartPalette.surfaceContainer)
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(MaterialChartPalette.cardGradient(for: .blue))
                    }
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.blue.opacity(0.22), lineWidth: 1)
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
            }

            if filteredItems.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(filteredItems.prefix(40)) { item in
                            NotchSwipeRow(
                                leading: leadingAction(for: item),
                                trailing: trailingAction(for: item)
                            ) {
                                clipboardRow(item)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                }
            }
        }
        .padding(.top, 10)
        .frame(width: 480, height: 270)
        .clipped()
        .onAppear {
            clipboardManager.startMonitoring()
            clipboardManager.beginHighPriorityPolling()
        }
        .onDisappear {
            clipboardManager.endHighPriorityPolling()
        }
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Clipboard")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                Text("\(clipboardManager.recentItems.count) items")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            toolbarButton("magnifyingglass", active: showSearch) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    showSearch.toggle()
                    if !showSearch { searchText = "" }
                }
            }
            toolbarButton("photo", active: filterImagesOnly) {
                filterImagesOnly.toggle()
            }
            toolbarButton("trash") {
                clipboardManager.clearHistory()
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }

    private func toolbarButton(_ systemName: String, active: Bool = false, action: @escaping () -> Void) -> some View {
        NotchCapsuleIconButton(
            systemName: systemName,
            isActive: active,
            activeTint: .blue,
            action: action
        )
    }

    private func clipboardRow(_ item: ClipboardItem) -> some View {
        HStack(alignment: .center, spacing: 12) {
            thumbnail(for: item)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.preview)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 6) {
                    Text(item.isImage ? "Image" : "Text")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(item.isImage ? Color.purple.opacity(0.9) : Color.blue.opacity(0.9))
                    Text("·")
                        .foregroundStyle(.tertiary)
                    RelativeMinuteText(date: item.copiedAt)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)

            CopyAgainButton(
                isImage: item.isImage,
                onTap: { clipboardManager.copyItem(item) }
            )
            .help("Copy again")
        }
        .padding(12)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(MaterialChartPalette.surface)
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(MaterialChartPalette.cardGradient(for: item.isImage ? .purple : .blue))
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(MaterialChartPalette.outline, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            clipboardManager.copyItem(item)
        }
        .contextMenu {
            Button("Copy") { clipboardManager.copyItem(item) }
            Button("Share…") { clipboardManager.shareItem(item) }
            Button("Delete", role: .destructive) { clipboardManager.removeItem(id: item.id) }
        }
    }

    private struct CopyAgainButton: View {
        let isImage: Bool
        let onTap: () -> Void

        @State private var copied = false

        private var tint: Color { isImage ? .purple : .blue }

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
        if item.isImage, let data = item.imagePNGData, let nsImage = NSImage(data: data) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(MaterialChartPalette.outline, lineWidth: 1)
                )
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(item.isImage ? Color.purple.opacity(0.18) : Color.blue.opacity(0.14))
                    .frame(width: 44, height: 44)
                Image(systemName: item.isImage ? "photo" : "doc.text")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(item.isImage ? .purple : .blue)
            }
        }
    }

    private func leadingAction(for item: ClipboardItem) -> NotchSwipeAction? {
        switch settings.settings.swipeActionSettings.clipboardLeading {
        case .none:
            return nil
        case .share:
            return NotchSwipeAction(systemImage: "square.and.arrow.up", tint: .blue) {
                clipboardManager.shareItem(item)
            }
        case .copy:
            return NotchSwipeAction(systemImage: "doc.on.doc", tint: .cyan) {
                clipboardManager.copyItem(item)
            }
        case .delete:
            return NotchSwipeAction(systemImage: "trash.fill", tint: .red) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                    clipboardManager.removeItem(id: item.id)
                }
            }
        }
    }

    private func trailingAction(for item: ClipboardItem) -> NotchSwipeAction? {
        switch settings.settings.swipeActionSettings.clipboardTrailing {
        case .none:
            return nil
        case .share:
            return NotchSwipeAction(systemImage: "square.and.arrow.up", tint: .blue) {
                clipboardManager.shareItem(item)
            }
        case .copy:
            return NotchSwipeAction(systemImage: "doc.on.doc", tint: .cyan) {
                clipboardManager.copyItem(item)
            }
        case .delete:
            return NotchSwipeAction(systemImage: "trash.fill", tint: .red) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                    clipboardManager.removeItem(id: item.id)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "list.clipboard")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.blue.opacity(0.8))
            Text(filterImagesOnly ? "No images" : (searchText.isEmpty ? "Clipboard is empty" : "No matches"))
                .font(.headline)
            Text(searchText.isEmpty
                 ? "Copy text or images to build history."
                 : "Try a different search.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 20)
    }
}