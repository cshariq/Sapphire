//
//  ClipboardPreviewPane.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-10-07

import AppKit
import ImageIO
import QuickLookThumbnailing
import SwiftUI

struct ClipboardPreviewPane: View {
    let item: ClipboardItem?
    var selectionCount: Int = 0

    var body: some View {
        Group {
            if selectionCount > 1 {
                placeholder(systemImage: "square.stack.3d.up", text: String(localized: "\(String(selectionCount)) items selected\n↵ pastes them together"))
            } else if let item {
                VStack(alignment: .leading, spacing: 10) {
                    content(for: item)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    details(for: item)
                }
                .padding(12)
            } else {
                placeholder(systemImage: "eye", text: String(localized: "Select an item to preview it"))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func content(for item: ClipboardItem) -> some View {
        switch item.kind {
        case .text:
            ScrollView {
                Text(Self.previewText(item))
                    .font(.system(size: 11.5, design: Self.looksLikeCode(item) ? .monospaced : .default))
                    .foregroundStyle(.white.opacity(0.88))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .image:
            ClipboardLargeImageView(item: item)
        case .file, .folder:
            ClipboardFilePreview(item: item)
        }
    }

    private func details(for item: ClipboardItem) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(item.kind.displayName)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(item.kind.spec.color.opacity(0.95))
                if item.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.yellow.opacity(0.9))
                }
                Spacer()
                RelativeMinuteText(date: item.copiedAt)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.4))
            }
            if item.kind == .text, let text = item.textContent {
                Text(item.isTextTruncated
                    ? String(localized: "\(text.count.formatted()) characters · trimmed to 1 MB when saved")
                    : String(localized: "\(text.count.formatted()) characters"))
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.45))
            } else if let path = item.fileURLString {
                Text(path)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
        }
    }

    private func placeholder(systemImage: String, text: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(.white.opacity(0.35))
            Text(text)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.45))
                .multilineTextAlignment(.center)
        }
    }

    private static func previewText(_ item: ClipboardItem) -> String {
        let text = item.textContent ?? item.preview
        guard text.count > 20_000 else { return text }
        return String(text.prefix(20_000)) + "\n…"
    }

    private static func looksLikeCode(_ item: ClipboardItem) -> Bool {
        guard let text = item.textContent?.prefix(2000) else { return false }
        return text.contains("{") && text.contains("}") || text.contains("    ") || text.contains("\t")
    }
}

private struct ClipboardLargeImageView: View {
    let item: ClipboardItem
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: item.id) {
            image = nil
            let source = item
            image = await Task.detached(priority: .userInitiated) { () -> NSImage? in
                guard let data = source.resolvedImageData,
                      let imageSource = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
                let options: [CFString: Any] = [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 720,
                    kCGImageSourceShouldCacheImmediately: true,
                ]
                guard let cgImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary) else { return nil }
                return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            }.value
        }
    }
}

private struct ClipboardFilePreview: View {
    let item: ClipboardItem
    @State private var thumbnail: NSImage?
    @State private var sizeText: String?
    @State private var isMissing = false

    var body: some View {
        VStack(spacing: 10) {
            Group {
                if let thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    Image(systemName: item.kind == .folder ? "folder.fill" : "doc.fill")
                        .font(.system(size: 54, weight: .light))
                        .foregroundStyle(item.kind.spec.color.opacity(0.8))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: 220)

            Text(item.preview)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(2)
                .multilineTextAlignment(.center)
            if isMissing {
                Text("No longer at this location")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange.opacity(0.85))
            } else if let sizeText {
                Text(sizeText)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: item.id) {
            thumbnail = nil
            sizeText = nil
            isMissing = false
            guard let path = item.fileURLString else { return }
            let url = URL(fileURLWithPath: path)
            let info = await Task.detached(priority: .utility) { () -> (exists: Bool, size: Int64?) in
                let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
                guard FileManager.default.fileExists(atPath: path) else { return (false, nil) }
                return (true, values?.isDirectory == true ? nil : values?.fileSize.map(Int64.init))
            }.value
            isMissing = !info.exists
            if let size = info.size {
                sizeText = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
            }
            guard info.exists else { return }
            let request = QLThumbnailGenerator.Request(
                fileAt: url,
                size: CGSize(width: 240, height: 240),
                scale: NSScreen.main?.backingScaleFactor ?? 2,
                representationTypes: [.thumbnail, .icon]
            )
            if let representation = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) {
                thumbnail = representation.nsImage
            }
        }
    }
}