//
//  FocusRestrictedAppActivityView.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-25
//

import SwiftUI
import AppKit

@MainActor
struct FocusRestrictedAppActivityView: View {
    let appName: String
    let bundleID: String
    let onDismiss: () -> Void
    let onUnlocked: () -> Void

    @State private var requested = false

    private static let unlockWindow: TimeInterval = 15 * 60

    private var appIcon: NSImage? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    private var hasPendingRequest: Bool {
        requested || FocusSessionManager.shared.hasPendingUnlockRequest(bundleID: bundleID)
    }

    var body: some View {
        VStack(spacing: 0) {
            Color.clear
                .frame(height: NotchConfiguration.universalHeight)

            VStack(spacing: 12) {
                HStack(alignment: .center, spacing: 12) {
                    iconView

                    VStack(alignment: .leading, spacing: 4) {
                        Text(appName)
                            .font(.headline)
                            .fontWeight(.bold)
                            .lineLimit(1)
                        message
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxHeight: 100)

                    Spacer()
                }

                actionButtons
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
            .frame(minWidth: 360, maxWidth: 440)
            .frame(minHeight: 120)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var message: some View {
        if hasPendingRequest {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let remaining = min(
                    FocusSessionManager.shared.remainingUnlockTime(bundleID: bundleID) ?? Self.unlockWindow,
                    FocusSessionManager.shared.remainingSeconds
                )
                Text("Unlocked in \(Self.format(remaining)) — or when your session ends, whichever comes first.")
                    .contentTransition(.numericText(countsDown: true))
                    .onChange(of: context.date) { _, _ in
                        if remaining <= 0 { onUnlocked() }
                    }
            }
        } else {
            Text("This app was closed because it's blocked during your focus session.")
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        HStack {
            actionButton(title: "Dismiss", systemName: "xmark", isPrimary: false) {
                onDismiss()
            }

            Spacer()

            if hasPendingRequest {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let remaining = FocusSessionManager.shared.remainingUnlockTime(bundleID: bundleID) ?? Self.unlockWindow
                    HStack(spacing: 6) {
                        Image(systemName: "hourglass")
                            .font(.system(size: 12, weight: .semibold))
                        Text(Self.format(remaining))
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .contentTransition(.numericText(countsDown: true))
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Color.orange.opacity(0.22))
                    .foregroundStyle(.orange)
                    .clipShape(Capsule())
                    .onChange(of: context.date) { _, _ in
                        if remaining <= 0 { onUnlocked() }
                    }
                }
            } else {
                actionButton(title: "Unlock", systemName: "lock.open.fill", isPrimary: true) {
                    FocusSessionManager.shared.requestTemporaryUnlock(bundleID: bundleID)
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        requested = true
                    }
                }
            }
        }
    }

    private func actionButton(title: String, systemName: String, isPrimary: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemName)
                .font(.system(size: 13, weight: .medium))
                .padding(.horizontal, 12).padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .background(
            Group {
                if isPrimary {
                    LinearGradient(colors: [.purple, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing)
                } else {
                    Color.primary.opacity(0.15)
                }
            }
        )
        .foregroundStyle(isPrimary ? .white : .primary)
        .clipShape(Capsule())
        .shadow(color: isPrimary ? Color.indigo.opacity(0.35) : .clear, radius: 6, y: 2)
    }

    private var iconView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.08))
            if let appIcon {
                Image(nsImage: appIcon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(3)
            } else {
                Image(systemName: "app.badge.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white.opacity(0.5))
            }
        }
        .frame(width: 50, height: 50)
    }

    private static func format(_ time: TimeInterval) -> String {
        let total = Int(max(0, time.rounded()))
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}