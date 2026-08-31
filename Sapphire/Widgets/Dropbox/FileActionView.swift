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

// MARK: - ShelfItem Presentation Metadata

private extension ShelfItem {
    var contentType: UTType? {
        (try? storedAt.resourceValues(forKeys: [.contentTypeKey]).contentType) ?? nil
    }

    var typeDescription: String {
        contentType?.localizedDescription ?? "Unknown Type"
    }

    var sizeString: String {
        guard let values = try? storedAt.resourceValues(forKeys: [.fileSizeKey]),
              let bytes = values.fileSize else { return "—" }
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    var typeIconName: String {
        IconGenerator.symbolName(for: self)
    }
}

private struct FileMetadata {
    let type: String
    let size: String
    let added: String
}

// MARK: - Main Detail View

struct FileActionView: View {
    let item: ShelfItem
    let onDismiss: () -> Void

    @StateObject private var fileDropManager = FileDropManager.shared
    @StateObject private var manager = FileShelfManager.shared

    private var liveItem: ShelfItem { manager.files.first { $0.id == item.id } ?? item }

    @State private var isRenaming = false
    @State private var renameText = ""
    @State private var isConfirmingDelete = false
    @FocusState private var renameFocused: Bool

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private var metadata: FileMetadata {
        FileMetadata(
            type: liveItem.typeDescription,
            size: liveItem.sizeString,
            added: dateFormatter.string(from: liveItem.dateAdded)
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
            Spacer(minLength: 0)
            footer
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.accentColor.opacity(0.22))
                Image(systemName: liveItem.typeIconName)
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
                    Text("\(liveItem.typeDescription) · \(liveItem.sizeString)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    private var primaryActions: some View {
        HStack(spacing: 8) {
            DetailButton(title: "Open", systemImage: "play.fill", isProminent: true) {
                NSWorkspace.shared.open(liveItem.storedAt)
            }
            DetailButton(title: "In Finder", systemImage: "folder.fill", isProminent: false, tint: .primary) {
                NSWorkspace.shared.activateFileViewerSelecting([liveItem.storedAt])
            }
        }
    }

    private var quickActions: some View {
        HStack(spacing: 8) {
            QuickIconAction(systemImage: "square.and.arrow.up", title: "Share") {
                presentSharePicker()
            }
            QuickIconAction(systemImage: "plus.square.on.square", title: "Duplicate") {
                manager.duplicateFile(item)
            }
            QuickIconAction(systemImage: "doc.on.clipboard", title: "Copy Path") {
                copyPath()
            }
        }
    }

    private var metadataSection: some View {
        VStack(spacing: 0) {
            MetadataRow(label: "Type", value: metadata.type, icon: "doc.text")
            Divider().overlay(Color.white.opacity(0.08))
            MetadataRow(label: "Size", value: metadata.size, icon: "internaldrive")
            Divider().overlay(Color.white.opacity(0.08))
            MetadataRow(label: "Added", value: metadata.added, icon: "calendar")
            Divider().overlay(Color.white.opacity(0.08))
            MetadataRow(label: "Location", value: liveItem.storedAt.path, icon: "folder")
        }
        .padding(.vertical, 4)
        .background(Color.black.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private var convertSection: some View {
        let formats = FileConversionManager.shared.availableFormats(for: liveItem.storedAt)

        if !formats.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Convert To")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                    .kerning(0.5)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(formats) { format in
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

    private var footer: some View {
        VStack(spacing: 8) {
            if isConfirmingDelete {
                Text("\"\(liveItem.fileName)\" will be removed from your File Shelf. The actual file stays in place.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                HStack(spacing: 8) {
                    DetailButton(title: "Delete", systemImage: "trash", isProminent: true, tint: .red) {
                        performDelete()
                    }
                    DetailButton(title: "Cancel", systemImage: nil, isProminent: false, tint: .primary) {
                        isConfirmingDelete = false
                    }
                }
            } else {
                HStack(spacing: 8) {
                    DetailButton(title: "Rename", systemImage: "pencil", isProminent: false, tint: .primary) {
                        beginRename()
                    }
                    DetailButton(title: "Trash", systemImage: "trash", isProminent: false, tint: .red) {
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
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(liveItem.storedAt.path, forType: .string)
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

    private func presentSharePicker() {
        let picker = NSSharingServicePicker(items: [liveItem.storedAt])
        if let contentView = NSWindow.visibleNotchWindow?.contentView {
            picker.show(relativeTo: contentView.bounds, of: contentView, preferredEdge: .maxY)
        }
    }
}

// MARK: - Supporting Views

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

private struct IconGenerator {
    static func symbolName(for url: URL) -> String {
        guard let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType else {
            return "doc.fill"
        }
        return symbolName(for: type)
    }

    static func symbolName(for item: ShelfItem) -> String {
        guard let type = try? item.storedAt.resourceValues(forKeys: [.contentTypeKey]).contentType else {
            return "doc.fill"
        }
        return symbolName(for: type)
    }

    static func symbolName(for type: UTType) -> String {
        if type.conforms(to: .image) { return "photo.fill" }
        if type.conforms(to: .movie) { return "video.fill" }
        if type.conforms(to: .audio) { return "music.note" }
        if type.conforms(to: .pdf) { return "doc.richtext.fill" }
        if type.conforms(to: .text) { return "doc.text.fill" }
        if type.conforms(to: .folder) { return "folder.fill" }
        if type.conforms(to: .archive) { return "archivebox.fill" }

        return "doc.fill"
    }
}