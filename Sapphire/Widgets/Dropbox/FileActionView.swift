//
//  FileActionView.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-08-12.
//

import SwiftUI
import UniformTypeIdentifiers
import QuickLookThumbnailing
import AppKit

private struct FileMetadata: Sendable {
    let type: String
    let size: String
    let added: String
    let iconName: String

    static func load(from url: URL, dateAdded: Date) -> FileMetadata {
        let values = try? url.resourceValues(forKeys: [.contentTypeKey, .fileSizeKey])
        let contentType = values?.contentType
        let size = values?.fileSize.map {
            ByteFormatter.string(Int64($0))
        } ?? "—"
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return FileMetadata(
            type: contentType?.localizedDescription ?? String(localized: "Unknown Type"),
            size: size,
            added: formatter.string(from: dateAdded),
            iconName: contentType?.sapphireFileSymbolName ?? "doc.fill"
        )
    }
}

// MARK: - Main Detail View

struct FileActionView: View {
    let item: ShelfItem
    let onDismiss: () -> Void

    @StateObject private var fileDropManager = FileDropManager.shared
    @StateObject private var manager = FileShelfManager.shared

    private var liveItem: ShelfItem { manager.files.first { $0.id == item.id } ?? item }

    @State private var isRenaming = false
    @State private var shareAnchor = ShareAnchor()
    @State private var renameText = ""
    @State private var isConfirmingDelete = false
    @State private var fileMetadata: FileMetadata?
    @State private var availableFormats: [ConversionFormat] = []
    @State private var optimizeKind: MediaOptimizeKind?
    @State private var canExtractText = false
    @State private var isRunningOptimizer = false
    @State private var optimizerMessage: String?
    @State private var optimizerFailed = false
    @FocusState private var renameFocused: Bool

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private var metadata: FileMetadata {
        fileMetadata ?? FileMetadata(
            type: String(localized: "Unknown Type"),
            size: "—",
            added: Self.dateFormatter.string(from: liveItem.dateAdded),
            iconName: "doc.fill"
        )
    }

    var body: some View {
        HStack(spacing: 0) {
            previewPanel
                .frame(width: 560, height: 372)
                .padding(15)

            Divider()
                .frame(height: 340)
                .overlay(Color.white.opacity(0.1))

            infoAndActionsPanel
                .frame(width: 288)
                .padding(15)
        }
        .background(Color.black.opacity(0.3), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .onAppear {
            renameText = liveItem.fileName
        }
        .task(id: liveItem.storedAt) {
            let url = liveItem.storedAt
            let dateAdded = liveItem.dateAdded
            let showsOptimizerActions = SettingsModel.shared.current.mediaToolsShowShelfActions
            let loaded = await Task.detached(priority: .utility) {
                (
                    metadata: FileMetadata.load(from: url, dateAdded: dateAdded),
                    optimizeKind: showsOptimizerActions ? MediaOptimizer.kind(for: url) : nil,
                    canExtractText: showsOptimizerActions && MediaOptimizer.canOCR(url)
                )
            }.value
            guard !Task.isCancelled else { return }
            fileMetadata = loaded.metadata
            optimizeKind = loaded.optimizeKind
            canExtractText = loaded.canExtractText
            optimizerMessage = nil
            optimizerFailed = false
            availableFormats = FileConversionManager.shared.availableFormats(for: url)
        }
    }

    // MARK: Preview

    private var previewPanel: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.black.opacity(0.4))

            QuickLookView(url: liveItem.storedAt)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .padding(2)
        }
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    // MARK: Info & Actions

    private var infoAndActionsPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            primaryActions
            quickActions
            metadataSection
            convertSection
            optimizerSection
            Spacer(minLength: 0)
            footer
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.accentColor.opacity(0.22))
                Image(systemName: metadata.iconName)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundColor(.white)
            }
            .frame(width: 54, height: 54)

            VStack(alignment: .leading, spacing: 3) {
                if isRenaming {
                    HStack(spacing: 5) {
                        TextField("File name", text: $renameText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13, weight: .semibold))
                            .focused($renameFocused)
                            .onSubmit { performRename() }
                        Button {
                            performRename()
                        } label: {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.accentColor)
                        }
                        .buttonStyle(.plain)
                        .disabled(renameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        Button {
                            cancelRename()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    Text("Type a new name, then press Return or tap .")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text(liveItem.fileName)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(2)
                        .truncationMode(.middle)
                    Text("\(metadata.type) · \(metadata.size)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    private var primaryActions: some View {
        HStack(spacing: 8) {
            DetailButton(title: String(localized: "Open"), systemImage: "play.fill", isProminent: true) {
                NSWorkspace.shared.open(liveItem.storedAt)
            }
            DetailButton(title: String(localized: "In Finder"), systemImage: "folder.fill", isProminent: false, tint: .primary) {
                NSWorkspace.shared.activateFileViewerSelecting([liveItem.storedAt])
            }
        }
    }

    private var quickActions: some View {
        HStack(spacing: 8) {
            QuickIconAction(systemImage: "square.and.arrow.up", title: String(localized: "Share")) {
                presentSharePicker()
            }
            .background(ShareAnchorView(anchor: shareAnchor))
            QuickIconAction(systemImage: "plus.square.on.square", title: String(localized: "Duplicate")) {
                manager.duplicateFile(item)
            }
            QuickIconAction(systemImage: "doc.on.clipboard", title: String(localized: "Copy Path")) {
                copyPath()
            }
        }
    }

    private var metadataSection: some View {
        VStack(spacing: 0) {
            MetadataRow(label: String(localized: "Type"), value: metadata.type, icon: "doc.text")
            Divider().overlay(Color.white.opacity(0.08))
            MetadataRow(label: String(localized: "Size"), value: metadata.size, icon: "internaldrive")
            Divider().overlay(Color.white.opacity(0.08))
            MetadataRow(label: String(localized: "Added"), value: metadata.added, icon: "calendar")
            Divider().overlay(Color.white.opacity(0.08))
            MetadataRow(label: String(localized: "Location"), value: liveItem.storedAt.path, icon: "folder")
        }
        .padding(.vertical, 4)
        .background(Color.black.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private var convertSection: some View {
        if !availableFormats.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Convert To")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                    .kerning(0.5)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(availableFormats) { format in
                            ConversionButton(format: format) {
                                fileDropManager.addConversion(sourceURL: liveItem.storedAt, targetFormat: format)
                                onDismiss()
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var optimizerSection: some View {
        if optimizeKind != nil || canExtractText {
            VStack(alignment: .leading, spacing: 6) {
                Text(optimizerMessage ?? "Optimize")
                    .font(.caption)
                    .foregroundColor(optimizerFailed ? .red : .secondary)
                    .textCase(optimizerMessage == nil ? .uppercase : nil)
                    .kerning(optimizerMessage == nil ? 0.5 : 0)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    if let kind = optimizeKind {
                        DetailButton(title: kind.actionTitle, systemImage: kind.systemImage, isProminent: false, tint: .primary) {
                            runOptimize()
                        }
                    }
                    if canExtractText {
                        DetailButton(title: "Extract Text", systemImage: "text.viewfinder", isProminent: false, tint: .primary) {
                            runExtractText()
                        }
                    }
                }
                .disabled(isRunningOptimizer)
                .opacity(isRunningOptimizer ? 0.5 : 1)
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 8) {
            if isConfirmingDelete {
                Text("\"\(liveItem.fileName)\" will be removed from your File Shelf. The actual file stays in place.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                HStack(spacing: 8) {
                    DetailButton(title: String(localized: "Delete"), systemImage: "trash", isProminent: true, tint: .red) {
                        performDelete()
                    }
                    DetailButton(title: String(localized: "Cancel"), systemImage: nil, isProminent: false, tint: .primary) {
                        isConfirmingDelete = false
                    }
                }
            } else {
                HStack(spacing: 8) {
                    DetailButton(title: String(localized: "Rename"), systemImage: "pencil", isProminent: false, tint: .primary) {
                        beginRename()
                    }
                    DetailButton(title: String(localized: "Trash"), systemImage: "trash", isProminent: false, tint: .red) {
                        isConfirmingDelete = true
                    }
                }
                Button(action: onDismiss) {
                    Text("Done")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(9)
                        .background(Color.white.opacity(0.15), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Actions

    private func copyPath() {
        NSPasteboard.general.copyString(liveItem.storedAt.path)
    }

    private func beginRename() {
        renameText = liveItem.fileName
        isRenaming = true
        (NSApp.delegate as? AppDelegate)?.makeNotchWindowFocusable()
        DispatchQueue.main.async {
            self.renameFocused = true
        }
    }

    private func cancelRename() {
        isRenaming = false
        renameFocused = false
        (NSApp.delegate as? AppDelegate)?.revertNotchWindowFocus()
    }

    private func performRename() {
        manager.renameFile(item, to: renameText)
        isRenaming = false
        renameFocused = false
        (NSApp.delegate as? AppDelegate)?.revertNotchWindowFocus()
    }

    private func performDelete() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            manager.removeFile(item)
        }
        onDismiss()
    }

    // MARK: Media Optimizer

    private func runOptimize() {
        guard !isRunningOptimizer else { return }
        guard PremiumGate.hasAccess(.mediaTools) else {
            PremiumGate.require(.mediaTools)
            return
        }
        let url = liveItem.storedAt
        isRunningOptimizer = true
        optimizerFailed = false
        optimizerMessage = "Working on \(url.lastPathComponent)…"
        Task {
            let outcome = await MediaOptimizerManager.shared.optimizeFile(url)
            isRunningOptimizer = false
            switch outcome {
            case .success(let result):
                manager.addFiles(from: [result.outputURL])
                optimizerFailed = false
                optimizerMessage = "Saved \(result.savedPercent)% (\(ByteFormatter.string(result.savedBytes))) — \(result.outputURL.lastPathComponent) added to the shelf"
            case .failure(let error):
                optimizerFailed = true
                optimizerMessage = error.localizedDescription
                NSSound.beep()
            }
        }
    }

    private func runExtractText() {
        guard !isRunningOptimizer else { return }
        guard PremiumGate.hasAccess(.ocrFeature) else {
            PremiumGate.require(.ocrFeature)
            return
        }
        let url = liveItem.storedAt
        isRunningOptimizer = true
        optimizerFailed = false
        optimizerMessage = "Reading text in \(url.lastPathComponent)…"
        Task {
            let text = await MediaOptimizerManager.shared.recognizeText(in: url)
            isRunningOptimizer = false
            guard let text, !text.isEmpty else {
                optimizerFailed = true
                optimizerMessage = "No text found in \(url.lastPathComponent)"
                NSSound.beep()
                return
            }
            NSPasteboard.general.copyString(text)
            manager.addText(text, named: "\(url.deletingPathExtension().lastPathComponent) Text")
            optimizerFailed = false
            optimizerMessage = "Copied \(text.count) characters and added a note to the shelf"
        }
    }

    private func presentSharePicker() {
        let picker = NSSharingServicePicker(items: [liveItem.storedAt])
        if let anchor = shareAnchor.view, anchor.window != nil {
            picker.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
        } else if let contentView = NSWindow.visibleNotchWindow?.contentView {
            picker.show(relativeTo: contentView.bounds, of: contentView, preferredEdge: .maxY)
        }
    }
}

// MARK: - Supporting Views

private final class ShareAnchor {
    weak var view: NSView?
}

private struct ShareAnchorView: NSViewRepresentable {
    let anchor: ShareAnchor

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        anchor.view = view
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        anchor.view = nsView
    }
}

private struct MetadataRow: View {
    let label: String
    let value: String
    let icon: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 18)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer(minLength: 6)
            Text(value)
                .font(.caption.weight(.medium))
                .foregroundColor(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }
}

private struct DetailButton: View {
    let title: String
    var systemImage: String? = nil
    var isProminent: Bool = false
    var tint: Color = .accentColor
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 12, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 13, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .foregroundColor(isProminent ? .white : tint)
            .background(
                (isProminent ? tint : Color.black.opacity(0.18)),
                in: RoundedRectangle(cornerRadius: 9, style: .continuous)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

private struct QuickIconAction: View {
    let systemImage: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
                Text(title)
                    .font(.system(size: 10, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .foregroundColor(.primary)
            .background(Color.black.opacity(0.14), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(PlainButtonStyle())
    }
}

private struct ConversionButton: View {
    let format: ConversionFormat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: format.iconName)
                    .font(.system(size: 11, weight: .semibold))
                Text(format.displayName)
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct QuickLookView: NSViewRepresentable {
    static let previewSize = CGSize(width: 556, height: 368)

    let url: URL

    final class Coordinator {
        weak var imageView: NSImageView?
        private(set) var currentURL: URL?
        private var requestToken = UUID()

        func load(_ url: URL, into imageView: NSImageView) {
            self.imageView = imageView
            guard url != currentURL else { return }
            currentURL = url

            let token = UUID()
            requestToken = token

            let request = QLThumbnailGenerator.Request(
                fileAt: url,
                size: CGSize(
                    width: QuickLookView.previewSize.width * 2,
                    height: QuickLookView.previewSize.height * 2
                ),
                scale: 2,
                representationTypes: [.thumbnail, .lowQualityThumbnail, .icon]
            )
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, _ in
                DispatchQueue.main.async { [weak self] in
                    guard let self, requestToken == token else { return }
                    if let image = representation?.nsImage {
                        self.imageView?.image = image
                    } else {
                        self.imageView?.image = NSWorkspace.shared.icon(forFile: url.path)
                    }
                }
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let imageView = NSImageView()
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.wantsLayer = true
        imageView.layer?.masksToBounds = true
        context.coordinator.load(url, into: imageView)
        return imageView
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let imageView = nsView as? NSImageView else { return }
        context.coordinator.load(url, into: imageView)
    }
}