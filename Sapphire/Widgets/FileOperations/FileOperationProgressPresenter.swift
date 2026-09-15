//
//  FileOperationProgressPresenter.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-13

import AppKit
import SwiftUI

@MainActor
final class FileOperationProgressPresenter {
    static let shared = FileOperationProgressPresenter()

    private var panel: NSPanel?
    private let state = FileOperationProgressState()
    private var dismissWorkItem: DispatchWorkItem?

    private init() {}

    func update(_ task: FileTransferTask?) {
        dismissWorkItem?.cancel()
        dismissWorkItem = nil

        guard let task else {
            hide()
            return
        }

        state.task = task
        showPanelIfNeeded()

        if task.isComplete {
            let workItem = DispatchWorkItem { [weak self] in self?.hide() }
            dismissWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: workItem)
        }
    }

    private func showPanelIfNeeded() {
        guard panel == nil else { return }

        let size = NSSize(width: 340, height: 92)
        let hosting = NSHostingView(rootView: FileOperationProgressPopupView(state: state))
        hosting.frame = NSRect(origin: .zero, size: size)

        let panel = NSPanel(
            contentRect: hosting.frame,
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.hasShadow = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.contentView = hosting
        panel.isReleasedWhenClosed = false

        if let screen = NSScreen.main {
            let margin: CGFloat = 20
            let origin = NSPoint(
                x: screen.visibleFrame.maxX - size.width - margin,
                y: screen.visibleFrame.minY + margin
            )
            panel.setFrameOrigin(origin)
        }

        panel.orderFrontRegardless()
        self.panel = panel
    }

    private func hide() {
        panel?.orderOut(nil)
        panel = nil
        state.task = nil
    }
}

@MainActor
private final class FileOperationProgressState: ObservableObject {
    @Published var task: FileTransferTask?
}

private struct FileOperationProgressPopupView: View {
    @ObservedObject fileprivate var state: FileOperationProgressState

    private var icon: String {
        switch state.task?.sourceType {
        case .dmgInstall: return "externaldrive.fill.badge.plus"
        case .archiveExtraction: return "archivebox.fill"
        default: return "doc.fill"
        }
    }

    private var tint: Color {
        switch state.task?.sourceType {
        case .dmgInstall: return .indigo
        case .archiveExtraction: return .brown
        default: return .accentColor
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(tint.opacity(0.18))
                    .frame(width: 44, height: 44)
                if state.task?.isComplete == true {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.green)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(tint)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(state.task?.fileName ?? "")
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)

                if let task = state.task, !task.isComplete {
                    ProgressView(value: task.progress ?? 0)
                        .progressViewStyle(.linear)
                    Text(detailText(for: task))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text("Done")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
        .frame(width: 340, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private func detailText(for task: FileTransferTask) -> String {
        var parts: [String] = []
        if let progress = task.progress {
            parts.append("\(Int(progress * 100))%")
        }
        if task.speed > 0 {
            parts.append(TransferMetricsFormatter.speed(task.speed))
        }
        if let eta = TransferMetricsFormatter.eta(
            currentBytes: task.currentSize,
            totalBytes: task.totalSize,
            bytesPerSecond: task.speed
        ) {
            parts.append("\(eta) left")
        }
        return parts.isEmpty ? "Working…" : parts.joined(separator: " • ")
    }

}