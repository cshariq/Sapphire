//
//  LockScreenAdditionalWidgets.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-10

import SwiftUI
import AppKit

// MARK: - Shared helpers

private func lockScreenFormatTimer(_ seconds: TimeInterval) -> String {
    let clamped = max(0, seconds.isFinite ? seconds : 0)
    let total = Int(clamped)
    let hours = total / 3600
    let minutes = (total % 3600) / 60
    let secs = total % 60
    if hours > 0 {
        return String(format: "%d:%02d:%02d", hours, minutes, secs)
    }
    return String(format: "%d:%02d", minutes, secs)
}

// MARK: - Info widgets

struct LockScreenCaffeineInfoView: View {
    @ObservedObject private var caffeineManager = CaffeineManager.shared
    @EnvironmentObject var settings: SettingsModel

    var body: some View {
        if caffeineManager.isActive {
            HStack(spacing: LockScreenConfiguration.infoWidgetGenericHSpacing) {
                Image(systemName: "cup.and.saucer.fill")
                    .font(.system(size: LockScreenConfiguration.infoWidgetIconFontSize))
                Text("Caffeine On")
                    .fontWeight(.semibold)
            }
            .foregroundColor(.orange)
            .modifier(TransparentEffect())
        } else if !settings.settings.lockScreenHideInactiveInfoWidgets {
            HStack(spacing: LockScreenConfiguration.infoWidgetGenericHSpacing) {
                Image(systemName: "cup.and.saucer")
                    .font(.system(size: LockScreenConfiguration.infoWidgetIconFontSize))
                Text("Caffeine Off")
            }
            .foregroundColor(.secondary)
            .modifier(TransparentEffect())
        }
    }
}

struct LockScreenTimerInfoView: View {
    @EnvironmentObject var timerManager: TimerManager
    @EnvironmentObject var settings: SettingsModel

    var body: some View {
        if timerManager.isRunning {
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                HStack(spacing: LockScreenConfiguration.infoWidgetGenericHSpacing) {
                    Image(systemName: timerManager.activeTimer == .stopwatch ? "stopwatch.fill" : "timer")
                        .font(.system(size: LockScreenConfiguration.infoWidgetIconFontSize))
                    Text(lockScreenFormatTimer(timerManager.displayTime))
                        .font(.system(size: LockScreenConfiguration.infoWidgetBoldFontSize, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
                .foregroundColor(.white)
                .modifier(TransparentEffect())
            }
        } else if !settings.settings.lockScreenHideInactiveInfoWidgets {
            HStack(spacing: LockScreenConfiguration.infoWidgetGenericHSpacing) {
                Image(systemName: "timer")
                    .font(.system(size: LockScreenConfiguration.infoWidgetIconFontSize))
                Text("No Timer")
            }
            .foregroundColor(.secondary)
            .modifier(TransparentEffect())
        }
    }
}

struct LockScreenClockInfoView: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            HStack(spacing: LockScreenConfiguration.infoWidgetGenericHSpacing) {
                Image(systemName: "clock.fill")
                    .font(.system(size: LockScreenConfiguration.infoWidgetIconFontSize))
                Text(context.date, style: .time)
                    .font(.system(size: LockScreenConfiguration.infoWidgetBoldFontSize, weight: .bold, design: .rounded))
                    .monospacedDigit()
            }
            .foregroundColor(.white)
            .modifier(TransparentEffect())
        }
    }
}

struct LockScreenNotesInfoView: View {
    @ObservedObject private var notesManager = NotesManager.shared
    @EnvironmentObject var settings: SettingsModel

    private var latestTitle: String? {
        notesManager.notes
            .sorted { $0.updatedAt > $1.updatedAt }
            .first
            .map { note in
                let title = note.title.trimmingCharacters(in: .whitespacesAndNewlines)
                if !title.isEmpty { return title }
                let body = note.body.trimmingCharacters(in: .whitespacesAndNewlines)
                return body.isEmpty ? "Untitled" : body
            }
    }

    var body: some View {
        if let latestTitle, !notesManager.notes.isEmpty {
            HStack(spacing: LockScreenConfiguration.infoWidgetGenericHSpacing) {
                Image(systemName: "note.text")
                    .font(.system(size: LockScreenConfiguration.infoWidgetIconFontSize))
                VStack(alignment: .leading, spacing: 2) {
                    Text(latestTitle)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                    Text("\(notesManager.notes.count) notes")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            .foregroundColor(.white)
            .modifier(TransparentEffect())
        } else if !settings.settings.lockScreenHideInactiveInfoWidgets {
            HStack(spacing: LockScreenConfiguration.infoWidgetGenericHSpacing) {
                Image(systemName: "note.text")
                    .font(.system(size: LockScreenConfiguration.infoWidgetIconFontSize))
                Text("No Notes")
            }
            .foregroundColor(.secondary)
            .modifier(TransparentEffect())
        }
    }
}

struct LockScreenClipboardInfoView: View {
    @ObservedObject private var clipboardManager = ClipboardManager.shared
    @EnvironmentObject var settings: SettingsModel

    private var latestPreview: String? {
        guard let item = clipboardManager.recentItems.first else { return nil }
        if item.isImage { return "Image" }
        let text = item.preview.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "Clipboard item" : text
    }

    var body: some View {
        if let latestPreview, !clipboardManager.recentItems.isEmpty {
            HStack(spacing: LockScreenConfiguration.infoWidgetGenericHSpacing) {
                Image(systemName: "list.clipboard")
                    .font(.system(size: LockScreenConfiguration.infoWidgetIconFontSize))
                VStack(alignment: .leading, spacing: 2) {
                    Text(latestPreview)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                    Text("\(clipboardManager.recentItems.count) items")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            .foregroundColor(.white)
            .modifier(TransparentEffect())
            .onAppear { clipboardManager.startMonitoring() }
        } else if !settings.settings.lockScreenHideInactiveInfoWidgets {
            HStack(spacing: LockScreenConfiguration.infoWidgetGenericHSpacing) {
                Image(systemName: "list.clipboard")
                    .font(.system(size: LockScreenConfiguration.infoWidgetIconFontSize))
                Text("Clipboard Empty")
            }
            .foregroundColor(.secondary)
            .modifier(TransparentEffect())
        }
    }
}

struct LockScreenSystemInfoView: View {
    @ObservedObject private var statsManager = StatsManager.shared

    var body: some View {
        let cpu = Int(((statsManager.currentStats?.cpu?.totalUsage ?? 0) * 100).rounded())
        let ram = Int(((statsManager.currentStats?.ram?.usage ?? 0) * 100).rounded())

        HStack(spacing: LockScreenConfiguration.infoWidgetInternalHSpacing) {
            HStack(spacing: LockScreenConfiguration.infoWidgetSmallIconHSpacing) {
                Image(systemName: "cpu")
                Text("\(cpu)%")
                    .font(.system(size: LockScreenConfiguration.infoWidgetBoldFontSize, weight: .bold, design: .rounded))
                    .monospacedDigit()
            }
            HStack(spacing: LockScreenConfiguration.infoWidgetSmallIconHSpacing) {
                Image(systemName: "memorychip")
                Text("\(ram)%")
                    .font(.system(size: LockScreenConfiguration.infoWidgetBoldFontSize, weight: .bold, design: .rounded))
                    .monospacedDigit()
            }
        }
        .font(.system(size: LockScreenConfiguration.infoWidgetMediumFontSize, weight: .medium))
        .foregroundColor(.white)
        .modifier(TransparentEffect())
    }
}

// MARK: - Mini widgets

struct LockScreenCaffeineMiniWidget: View {
    @ObservedObject private var caffeineManager = CaffeineManager.shared

    var body: some View {
        Button(action: { caffeineManager.toggle() }) {
            HStack(spacing: 14) {
                Image(systemName: caffeineManager.isActive ? "cup.and.saucer.fill" : "cup.and.saucer")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(caffeineManager.isActive ? .orange : .white.opacity(0.7))
                    .frame(width: 44, height: 44)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Caffeine")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                    Text(caffeineManager.isActive ? "Keeping awake" : "Tap to enable")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Text(caffeineManager.isActive ? "On" : "Off")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(caffeineManager.isActive ? .orange : .secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.1), in: Capsule())
            }
            .foregroundStyle(.white)
            .frame(minWidth: 220)
        }
        .buttonStyle(.plain)
    }
}

struct LockScreenTimerMiniWidget: View {
    @EnvironmentObject var timerManager: TimerManager

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            HStack(spacing: 14) {
                Image(systemName: timerManager.activeTimer == .stopwatch ? "stopwatch.fill" : "timer")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.orange)
                    .frame(width: 44, height: 44)
                    .background(Color.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(timerManager.activeTimer == .stopwatch ? "Stopwatch" : "Timer")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                    Text(timerManager.isRunning ? lockScreenFormatTimer(timerManager.displayTime) : "No active timer")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(timerManager.isRunning ? .white : .secondary)
                        .contentTransition(.numericText())
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(.white)
            .frame(minWidth: 220)
        }
    }
}

struct LockScreenFocusMiniWidget: View {
    @EnvironmentObject var focusModeManager: FocusModeManager

    private let customImageAssetNames: Set<String> = [
        "rocket.fill",
        "apple.mindfulness",
        "person.lanyardcard.fill"
    ]

    var body: some View {
        let status = focusModeManager.currentStatus
        let info = status.toFocusModeInfo(isActive: status.isActive)

        HStack(spacing: 14) {
            focusIcon(for: status)
                .frame(width: 44, height: 44)
                .background(Color.indigo.opacity(0.18), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text("Focus")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Text(status.isActive ? info.name : "Focus Off")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(status.isActive ? .white : .secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .frame(minWidth: 200)
    }

    @ViewBuilder
    private func focusIcon(for status: FocusStatus) -> some View {
        if status.identifier == "com.apple.focus.reduce-interruptions" {
            Image(systemName: "apple.intelligence")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.purple)
        } else if customImageAssetNames.contains(status.symbolName) {
            Image(status.symbolName)
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 22, height: 22)
                .foregroundStyle(.indigo)
        } else {
            Image(systemName: status.isActive ? status.symbolName : "moon.zzz.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(status.isActive ? .indigo : .secondary)
        }
    }
}

struct LockScreenBluetoothMiniWidget: View {
    @EnvironmentObject var bluetoothManager: BluetoothManager

    var body: some View {
        let device = bluetoothManager.lastEvent

        HStack(spacing: 14) {
            Image(systemName: device?.iconName ?? "headphones")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.blue)
                .frame(width: 44, height: 44)
                .background(Color.blue.opacity(0.15), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(device?.name ?? "Bluetooth")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                if let level = device?.batteryLevel, device?.eventType == .connected {
                    Text("\(level)% battery")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                } else {
                    Text("No device connected")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)

            if let level = device?.batteryLevel, device?.eventType == .connected {
                Text("\(level)%")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
            }
        }
        .foregroundStyle(.white)
        .frame(minWidth: 220)
    }
}

struct LockScreenSystemMiniWidget: View {
    @ObservedObject private var statsManager = StatsManager.shared

    var body: some View {
        let cpu = Int(((statsManager.currentStats?.cpu?.totalUsage ?? 0) * 100).rounded())
        let ram = Int(((statsManager.currentStats?.ram?.usage ?? 0) * 100).rounded())
        let gpu = Int(((statsManager.currentStats?.gpu?.utilization ?? 0) * 100).rounded())

        VStack(alignment: .leading, spacing: 10) {
            Text("System")
                .font(.system(size: 14, weight: .bold, design: .rounded))

            HStack(spacing: 16) {
                systemMeter(title: "CPU", value: cpu, color: .cyan)
                systemMeter(title: "RAM", value: ram, color: .purple)
                systemMeter(title: "GPU", value: gpu, color: .green)
            }
        }
        .foregroundStyle(.white)
        .frame(minWidth: 240)
    }

    private func systemMeter(title: String, value: Int, color: Color) -> some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.12), lineWidth: 5)
                Circle()
                    .trim(from: 0, to: CGFloat(min(max(value, 0), 100)) / 100)
                    .stroke(color, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(value)")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .monospacedDigit()
            }
            .frame(width: 44, height: 44)

            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Main widgets

struct LockScreenBatteryMainView: View {
    var body: some View {
        LockScreenPaddedBackground {
            BatteryMiniWidget()
                .frame(minWidth: 280)
        }
    }
}

struct LockScreenFocusMainView: View {
    @EnvironmentObject var focusModeManager: FocusModeManager
    @EnvironmentObject var settings: SettingsModel

    var body: some View {
        LockScreenPaddedBackground {
            LockScreenFocusMiniWidget()
                .environmentObject(focusModeManager)
                .frame(minWidth: 280, minHeight: 80)
        }
    }
}

struct LockScreenTimerMainView: View {
    @EnvironmentObject var timerManager: TimerManager
    @State private var dummyStack: [NotchWidgetMode] = []

    var body: some View {
        LockScreenPaddedBackground {
            TimerDetailView(navigationStack: $dummyStack)
                .environmentObject(timerManager)
                .frame(minWidth: 320)
        }
    }
}

struct LockScreenNotesMainView: View {
    var body: some View {
        LockScreenPaddedBackground {
            NotesWidgetView()
        }
    }
}

struct LockScreenClipboardMainView: View {
    var body: some View {
        LockScreenPaddedBackground {
            ClipboardWidgetView()
        }
    }
}