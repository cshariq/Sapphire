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
    /// BETA
    @State private var showSnippets = false
    @State private var isAddingSnippet = false
    @State private var newSnippetName = ""
    @State private var newSnippetContent = ""

    private var filteredItems: [ClipboardItem] {
        // Pinned items float to the top (stable sort preserves recency order within each group).
        var items = clipboardManager.recentItems.sorted { $0.isPinned && !$1.isPinned }
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

            if showSnippets {
                snippetsView
            } else {
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
                HStack(spacing: 6) {
                    Text(showSnippets ? "Snippets" : "Clipboard")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                    BetaBadge(style: .pill)
                        .help("Pinning and Snippets are new, still-stabilizing features")
                }
                Text(showSnippets ? "\(settings.settings.textSnippets.count) saved" : "\(clipboardManager.recentItems.count) items")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            toolbarButton("doc.plaintext", active: showSnippets) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    showSnippets.toggle()
                    isAddingSnippet = false
                }
            }
            .help(showSnippets ? "Back to History" : "Snippets (Beta)")

            if showSnippets {
                toolbarButton("plus") {
                    isAddingSnippet = true
                }
            } else {
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
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }

    // MARK: - Snippets (BETA)

    private var snippetsView: some View {
        Group {
            if isAddingSnippet {
                addSnippetForm
            } else if settings.settings.textSnippets.isEmpty {
                snippetsEmptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(settings.settings.textSnippets) { snippet in
                            snippetRow(snippet)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                }
            }
        }
    }

    private var snippetsEmptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "doc.plaintext")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.blue.opacity(0.8))
            Text("No snippets yet")
                .font(.headline)
            Text("Save reusable text — signatures, addresses, canned replies — for one-tap copying.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button("Add Snippet") { isAddingSnippet = true }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 20)
    }

    private var addSnippetForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Snippet name", text: $newSnippetName)
                .textFieldStyle(.plain)
                .padding(8)
                .background(Color.black.opacity(0.2))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            TextEditor(text: $newSnippetContent)
                .font(.system(size: 12))
                .scrollContentBackground(.hidden)
                .padding(6)
                .frame(height: 110)
                .background(Color.black.opacity(0.2))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            HStack {
                Button("Cancel") {
                    isAddingSnippet = false
                    newSnippetName = ""
                    newSnippetContent = ""
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Spacer()

                Button("Save") {
                    let name = newSnippetName.trimmingCharacters(in: .whitespacesAndNewlines)
                    let content = newSnippetContent.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !content.isEmpty else { return }
                    TextSnippetManager.shared.addSnippet(name: name.isEmpty ? "Untitled" : name, content: content)
                    isAddingSnippet = false
                    newSnippetName = ""
                    newSnippetContent = ""
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .disabled(newSnippetContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    private func snippetRow(_ snippet: TextSnippet) -> some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.blue.opacity(0.14))
                    .frame(width: 36, height: 36)
                Image(systemName: "doc.plaintext")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.blue)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(snippet.name)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Text(snippet.content)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Button {
                TextSnippetManager.shared.copySnippet(snippet)
            } label: {
                NotchCapsuleIconLabel(systemName: "doc.on.doc", isActive: false, activeTint: .blue)
            }
            .buttonStyle(.plain)
            .help("Copy")
        }
        .padding(12)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(MaterialChartPalette.surface)
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(MaterialChartPalette.cardGradient(for: .blue))
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(MaterialChartPalette.outline, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            TextSnippetManager.shared.copySnippet(snippet)
        }
        .contextMenu {
            Button("Copy") { TextSnippetManager.shared.copySnippet(snippet) }
            Button("Delete", role: .destructive) { TextSnippetManager.shared.deleteSnippet(id: snippet.id) }
        }
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

            PinButton(
                isPinned: item.isPinned,
                onTap: { clipboardManager.togglePin(id: item.id) }
            )
            .help(item.isPinned ? "Unpin" : "Pin (Beta) — keeps this item from being trimmed or cleared")

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
                .stroke(item.isPinned ? Color.orange.opacity(0.45) : MaterialChartPalette.outline, lineWidth: item.isPinned ? 1.5 : 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            clipboardManager.copyItem(item)
        }
        .contextMenu {
            Button(item.isPinned ? "Unpin" : "Pin (Beta)") { clipboardManager.togglePin(id: item.id) }
            Button("Copy") { clipboardManager.copyItem(item) }
            Button("Share…") { clipboardManager.shareItem(item) }
            Button("Delete", role: .destructive) { clipboardManager.removeItem(id: item.id) }
        }
    }

    /// BETA
    private struct PinButton: View {
        let isPinned: Bool
        let onTap: () -> Void

        var body: some View {
            Button(action: onTap) {
                NotchCapsuleIconLabel(
                    systemName: isPinned ? "pin.fill" : "pin",
                    isActive: isPinned,
                    activeTint: .orange
                )
            }
            .buttonStyle(.plain)
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