//
//  AppActivityViews.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-28
//

import SwiftUI
import AppKit

private extension AppActivityControl {
    func symbol(isOn: Bool?) -> String {
        switch self {
        case .mute: isOn == true ? "mic.slash.fill" : "mic.fill"
        case .video: isOn == false ? "video.slash.fill" : "video.fill"
        case .share: "rectangle.on.rectangle"
        case .deafen: "headphones"
        case .stop: "stop.fill"
        case .leave: "phone.down.fill"
        case .show: "arrow.up.forward.app"
        }
    }

    func label(isOn: Bool?) -> String {
        switch self {
        case .mute: isOn == true ? String(localized: "Unmute") : String(localized: "Mute")
        case .video: isOn == false ? String(localized: "Start Video") : (isOn == true ? String(localized: "Stop Video") : String(localized: "Video"))
        case .share: isOn == true ? String(localized: "Stop Share") : String(localized: "Share")
        case .deafen: String(localized: "Deafen")
        case .stop: String(localized: "Stop")
        case .leave: String(localized: "Leave")
        case .show: String(localized: "Show")
        }
    }
}

struct AppActivityIcon: View {
    let app: AppActivityApp
    var size: CGFloat = 20

    var body: some View {
        Group {
            if app == .googleMeet {
                Image(systemName: "video.fill")
                    .font(.system(size: size * 0.55, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: size, height: size)
                    .background(RoundedRectangle(cornerRadius: size * 0.25).fill(Color(red: 0.0, green: 0.54, blue: 0.40)))
            } else if let icon = app.icon {
                Image(nsImage: icon).resizable().aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "app.fill").foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
    }
}

enum AppActivityLiveActivityView {
    static func left(for activity: AppActivity) -> some View {
        AppActivityIcon(app: activity.app, size: 20)
    }

    static func right(for activity: AppActivity, additionalCount: Int) -> some View {
        HStack(spacing: 6) {
            if activity.app.kind == .recording {
                Circle().fill(.red).frame(width: 7, height: 7)
            }
            if activity.states[.mute] == true {
                Image(systemName: "mic.slash.fill").font(.system(size: 11, weight: .bold)).foregroundStyle(.red)
            }
            if activity.states[.share] == true {
                Image(systemName: "rectangle.on.rectangle").font(.system(size: 11, weight: .semibold)).foregroundStyle(.green)
            }
            Text(activity.startedAt, style: .timer)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(activity.app.kind == .recording ? Color.red : Color.green)
                .fixedSize()
            if additionalCount > 0 {
                Text("+\(additionalCount)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
    }
}

struct AppActivityDetailView: View {
    @ObservedObject private var monitor = AppActivityMonitor.shared

    var body: some View {
        VStack(spacing: 10) {
            if monitor.activities.isEmpty {
                Text("Nothing active right now.")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(maxWidth: .infinity, minHeight: 60)
            } else {
                ForEach(monitor.activities) { activity in
                    AppActivityCard(activity: activity, monitor: monitor)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(width: 400)
    }
}

private struct AppActivityCard: View {
    let activity: AppActivity
    let monitor: AppActivityMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                AppActivityIcon(app: activity.app, size: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text(activity.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(activity.subtitle ?? activity.app.kind.verb)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }
                Spacer()
                Text(activity.startedAt, style: .timer)
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(activity.app.kind == .recording ? Color.red : Color.green)
                    .fixedSize()
            }
            HStack(spacing: 10) {
                ForEach(activity.controls) { control in
                    let isOn = activity.states[control]
                    let destructive = control == .leave || control == .stop
                    Button { monitor.perform(control, on: activity) } label: {
                        VStack(spacing: 4) {
                            Image(systemName: control.symbol(isOn: isOn))
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 42, height: 42)
                                .background(Circle().fill(background(control, isOn: isOn, destructive: destructive)))
                            Text(control.label(isOn: isOn))
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.white.opacity(0.75))
                                .lineLimit(1)
                        }
                        .frame(minWidth: 52)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.white.opacity(0.06)))
    }

    private func background(_ control: AppActivityControl, isOn: Bool?, destructive: Bool) -> Color {
        if destructive { return .red.opacity(0.85) }
        if control == .mute, isOn == true { return .red.opacity(0.7) }
        if control == .video, isOn == false { return .red.opacity(0.7) }
        if control == .share, isOn == true { return .green.opacity(0.7) }
        return .white.opacity(0.14)
    }
}