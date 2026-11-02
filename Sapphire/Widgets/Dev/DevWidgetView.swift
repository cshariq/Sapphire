//
//  DevWidgetView.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-10-15
//

import SwiftUI

struct DevWidgetView: View {
    @ObservedObject private var monitor = DevActivityMonitor.shared
    @ObservedObject private var usage = DevUsageMonitor.shared
    @ObservedObject private var runner = DevCommandRunner.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            if !monitor.tasks.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(monitor.tasks.prefix(2)) { task in
                        row(symbol: task.tool.symbol, tint: task.tool.tint, title: task.title) {
                            DevElapsedText(startedAt: task.startedAt, size: 10)
                                .foregroundStyle(task.tool.tint.opacity(0.9))
                        }
                    }
                }
            } else if !usage.cards.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(usage.cards.prefix(2)) { card in
                        row(symbol: card.symbol, tint: card.tint, title: card.title) {
                            Text(card.compactValue)
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white.opacity(0.75))
                        }
                    }
                }
            } else {
                Text("Nothing running")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.45))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
        }
        .frame(width: 200, height: 96, alignment: .topLeading)
        .contentShape(Rectangle())
        .onAppear { usage.beginObserving() }
        .onDisappear { usage.endObserving() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(LinearGradient(
                        colors: [Color(hue: 0.64, saturation: 0.40, brightness: 0.84), Color(hue: 0.64, saturation: 0.54, brightness: 0.58)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                    .frame(width: 26, height: 26)
                Image(systemName: "chevron.left.forwardslash.chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text("Dev")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text(statusLine)
                    .font(.system(size: 9.5, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            let running = monitor.tasks.count + runner.runningCount
            if running > 0 {
                DevCountBadge(count: running, tint: .green)
            }
        }
    }

    private var statusLine: String {
        if !monitor.tasks.isEmpty {
            let count = monitor.tasks.count
            return count == 1 ? String(localized: "1 task running") : String(localized: "\(String(count)) tasks running")
        }
        if runner.runningCount > 0 { return String(localized: "Running a command") }
        return usage.cards.isEmpty ? String(localized: "Idle") : String(localized: "Today's usage")
    }

    private func row<Trailing: View>(symbol: String, tint: Color, title: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 18, height: 18)
                .background(Circle().fill(tint.opacity(0.18)))
            Text(verbatim: title)
                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
            Spacer(minLength: 4)
            trailing()
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(0.06)))
    }
}