//
//  FileActionView.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-08-12.
//

import SwiftUI
import UniformTypeIdentifiers
import QuickLookUI

struct FileActionView: View {
    let item: ShelfItem
    let onDismiss: () -> Void
    @StateObject private var fileDropManager = FileDropManager.shared

    @State private var isPreviewReady = false

    var body: some View {
        HStack(spacing: 0) {
            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.black.opacity(0.3))

                if isPreviewReady {
                    QuickLookView(url: item.storedAt)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .transition(.opacity.animation(.easeInOut(duration: 0.3)))
                } else {
                    ProgressView()
                        .controlSize(.large)
                }
            }
            .frame(width: 650, height: 300)
            .padding(15)

            VStack(alignment: .leading, spacing: 10) {
                Text(item.fileName)
                    .font(.headline)
                    .lineLimit(2)
                    .truncationMode(.middle)

                HStack {
                    ActionButton(title: "Open", systemImage: "arrow.up.forward.app.fill") { NSWorkspace.shared.open(item.storedAt) }
                    ActionButton(title: "Finder", systemImage: "folder.fill") { NSWorkspace.shared.activateFileViewerSelecting([item.storedAt]) }
                }

                Divider().padding(.vertical, 5)

                Text("Convert To...").font(.caption).foregroundColor(.secondary)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(FileConversionManager.shared.availableFormats(for: item.storedAt)) { format in
                            ConversionButton(format: format) {
                                fileDropManager.addConversion(sourceURL: item.storedAt, targetFormat: format)
                                onDismiss()
                            }
                        }
                    }
                }

                Spacer()

                Button(action: onDismiss) {
                    Text("Done")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(8)
                        .background(.white.opacity(0.15))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(15)
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self.isPreviewReady = true
            }
        }
    }
}

private struct ActionButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: systemImage)
                Text(title)
            }
            .font(.system(size: 13, weight: .medium))
            .frame(maxWidth: .infinity)
            .padding(8)
            .background(.white.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}

private struct ConversionButton: View {
    let format: ConversionFormat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: format.iconName)
                Text(format.displayName)
            }
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.white.opacity(0.1))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct QuickLookView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> QLPreviewView {
        let previewView = QLPreviewView(frame: .zero, style: .normal)
        previewView?.autostarts = true
        previewView?.previewItem = url as QLPreviewItem
        return previewView ?? QLPreviewView()
    }

    func updateNSView(_ nsView: QLPreviewView, context: Context) {
        if (nsView.previewItem as? URL) != url {
            nsView.previewItem = url as QLPreviewItem
        }
    }
}