//
//  FileProgressViews.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-28
//

import SwiftUI
import AppKit

enum FileProgressFormat {
    static func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }

    static func speed(_ bytesPerSecond: Double) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytesPerSecond), countStyle: .file) + "/s"
    }

    static func remaining(_ seconds: TimeInterval) -> String {
        if seconds < 60 { return "\(max(1, Int(seconds))) s left" }
        if seconds < 3600 { return "\(Int(seconds / 60)) min left" }
        let h = Int(seconds / 3600), m = Int(seconds.truncatingRemainder(dividingBy: 3600) / 60)
        return m > 0 ? "\(h) h \(m) min left" : "\(h) h left"
    }

    static func status(percent: Double?, speed: Double?, remaining: TimeInterval?, finished: Bool, failed: Bool,
                       paused: Bool = false, verb: String) -> String {
        if failed { return "Cancelled" }
        if finished { return "Done" }
        if paused { return "Paused" }
        let settings = SettingsModel.shared.settings
        var parts: [String] = []
        if let percent { parts.append("\(Int(percent * 100))%") }
        if settings.fileProgressShowSpeed, let speed, speed > 0 { parts.append(Self.speed(speed)) }
        if settings.fileProgressShowTimeRemaining, let remaining, remaining.isFinite, remaining > 0 { parts.append(Self.remaining(remaining)) }
        return parts.isEmpty ? verb : parts.joined(separator: " · ")
    }
}

struct FileProgressAppGlyph: View {
    let app: FileProgressApp?
    let fallbackSymbol: String
    let fraction: Double?
    var size: CGFloat = 20

    var body: some View {
        ZStack {
            if let fraction {
                Circle().stroke(.white.opacity(0.18), lineWidth: 2)
                Circle()
                    .trim(from: 0, to: max(0.02, fraction))
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.3), value: fraction)
            }
            if let icon = app?.icon, app != .airDrop, app != .other {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(fraction == nil ? 0 : 3.5)
            } else {
                Image(systemName: fallbackSymbol)
                    .font(.system(size: size * 0.5, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
    }
}

struct FileProgressDetailView: View {
    @ObservedObject private var tracker = FileProgressTracker.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(tracker.transfers.count == 1 ? "1 transfer" : "\(tracker.transfers.count) transfers")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                Spacer()
            }
            if tracker.transfers.isEmpty {
                Text("Nothing is downloading or copying.")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(maxWidth: .infinity, minHeight: 50)
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(tracker.transfers) { transfer in
                            FileProgressRow(transfer: transfer, tracker: tracker)
                        }
                    }
                }
                .frame(maxHeight: 230)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(width: 420)
    }
}

private struct FileProgressRow: View {
    let transfer: TrackedTransfer
    let tracker: FileProgressTracker

    private var verb: String {
        switch transfer.operation {
        case .copy: "Copying…"
        case .move: "Moving…"
        case .airDrop: "Receiving…"
        default: "Downloading…"
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            FileProgressAppGlyph(app: transfer.app, fallbackSymbol: "arrow.down.circle.fill", fraction: nil, size: 30)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(transfer.fileName)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Text(transfer.app.displayName)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.white.opacity(0.5))
                }
                if transfer.isFinished || transfer.isFailed {
                    Capsule().fill(transfer.isFailed ? Color.red.opacity(0.6) : Color.green).frame(height: 4)
                } else if let fraction = transfer.fraction {
                    ProgressView(value: fraction).progressViewStyle(.linear).tint(.accentColor)
                } else {
                    ProgressView().progressViewStyle(.linear).tint(.accentColor)
                }
                HStack {
                    Text(FileProgressFormat.status(
                        percent: transfer.fraction, speed: transfer.throughput, remaining: transfer.timeRemaining,
                        finished: transfer.isFinished, failed: transfer.isFailed, paused: transfer.isPaused, verb: verb))
                    Spacer()
                    if let total = transfer.totalBytes, !transfer.isFinished {
                        Text("\(FileProgressFormat.bytes(transfer.completedBytes)) of \(FileProgressFormat.bytes(total))")
                    } else if transfer.completedBytes > 0 {
                        Text(FileProgressFormat.bytes(transfer.completedBytes))
                    }
                }
                .font(.system(size: 10.5).monospacedDigit())
                .foregroundStyle(.white.opacity(0.6))
            }
            HStack(spacing: 2) {
                if transfer.canPause, !transfer.isFinished {
                    iconButton(transfer.isPaused ? "play.fill" : "pause.fill", help: transfer.isPaused ? "Resume" : "Pause") {
                        transfer.isPaused ? tracker.resume(transfer.id) : tracker.pause(transfer.id)
                    }
                }
                if transfer.canCancel, !transfer.isFinished {
                    iconButton("xmark", help: "Cancel") { tracker.cancel(transfer.id) }
                }
                if transfer.isFinished {
                    iconButton("arrow.up.forward.app", help: "Open") { tracker.open(transfer.id) }
                }
                iconButton("magnifyingglass", help: "Show in Finder") { tracker.reveal(transfer.id) }
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(0.06)))
    }

    private func iconButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 24, height: 24)
                .background(Circle().fill(.white.opacity(0.1)))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}