//
//  LockScreenMiniWidgetView.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-10-05.
//

import SwiftUI

struct LockScreenWidgetBackground<Content: View>: View {
    @Environment(\.lockScreenMiniWidgetHeight) private var equalizedHeight: CGFloat?

    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(LockScreenConfiguration.backgroundPadding)
            .measureSize()
            .frame(minHeight: equalizedHeight, alignment: .top)
            .background(backgroundMaterial)
    }

    @ViewBuilder
    private var backgroundMaterial: some View {
        LockScreenWidgetSurface(
            shape: RoundedRectangle(cornerRadius: LockScreenConfiguration.cornerRadius, style: .continuous),
            cornerRadius: LockScreenConfiguration.cornerRadius
        )
    }
}

struct LockScreenMiniWidgetView: View {
    @EnvironmentObject var settings: SettingsModel

    @StateObject private var batteryStatusManager = BatteryStatusManager.shared

    @StateObject private var calendarViewModel = InteractiveCalendarViewModel()
    @State private var dummyNavigationStack: [NotchWidgetMode] = []

    @State private var maxMiniWidgetHeight: CGFloat = 0

    private var animationToken: String {
        let widgets = settings.settings.lockScreenMiniWidgets.map(\.rawValue).joined(separator: ",")
        return "\(widgets)-\(Int(maxMiniWidgetHeight))"
    }

    var body: some View {
        let fadeTransition = AnyTransition.opacity.combined(with: .scale(scale: 0.98))

        HStack(alignment: .top, spacing: LockScreenConfiguration.widgetSpacing) {
            ForEach(settings.settings.lockScreenMiniWidgets, id: \.self) { widgetType in
                switch widgetType {
                case .weather:
                    LockScreenWidgetBackground {
                        WeatherWidgetView()
                            .environment(\.navigationStack, $dummyNavigationStack)
                    }
                    .transition(fadeTransition)

                case .calendar:
                    LockScreenWidgetBackground {
                        CalendarWidgetView(viewModel: calendarViewModel)
                            .environment(\.navigationStack, $dummyNavigationStack)
                    }
                    .transition(fadeTransition)

                case .music:
                    LockScreenMusicMiniSlot()
                        .environment(\.navigationStack, $dummyNavigationStack)
                        .transition(fadeTransition)
                case .battery:
                    LockScreenWidgetBackground {
                        BatteryMiniWidget()
                    }
                    .transition(fadeTransition)

                case .focus:
                    LockScreenWidgetBackground {
                        LockScreenFocusMiniWidget()
                    }
                    .transition(fadeTransition)

                case .caffeine:
                    LockScreenWidgetBackground {
                        LockScreenCaffeineMiniWidget()
                    }
                    .transition(fadeTransition)

                case .timer:
                    LockScreenTimerMiniSlot()
                        .transition(fadeTransition)

                case .bluetooth:
                    LockScreenWidgetBackground {
                        LockScreenBluetoothMiniWidget()
                    }
                    .transition(fadeTransition)

                case .clipboard:
                    LockScreenWidgetBackground {
                        ClipboardWidgetView()
                    }
                    .transition(fadeTransition)

                case .notes:
                    LockScreenWidgetBackground {
                        NotesWidgetView()
                    }
                    .transition(fadeTransition)

                case .system:
                    LockScreenWidgetBackground {
                        LockScreenSystemMiniWidget()
                    }
                    .transition(fadeTransition)

                case .none:
                    EmptyView()
                }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: animationToken)
        .fixedSize(horizontal: true, vertical: false)
        .onPreferenceChange(SizePreferenceKey.self) { sizes in
            let maxHeight = sizes.map(\.height).max() ?? 0
            if maxMiniWidgetHeight != maxHeight {
                maxMiniWidgetHeight = maxHeight
            }
        }
        .environment(\.lockScreenMiniWidgetHeight, maxMiniWidgetHeight > 0 ? maxMiniWidgetHeight : nil)
        .environmentObject(batteryStatusManager)
    }

}

private struct LockScreenMusicMiniSlot: View {
    @EnvironmentObject private var musicManager: MusicManager

    var body: some View {
        Group {
            if musicManager.isPlaying {
                LockScreenWidgetBackground {
                    MusicWidgetView(onExpand: {
                        LockScreenMusicPaneController.shared.open()
                    })
                }
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: musicManager.isPlaying)
    }
}

private struct LockScreenTimerMiniSlot: View {
    @EnvironmentObject private var settings: SettingsModel
    @EnvironmentObject private var timerManager: TimerManager

    var body: some View {
        Group {
            if timerManager.isRunning || !settings.settings.lockScreenHideInactiveInfoWidgets {
                LockScreenWidgetBackground {
                    LockScreenTimerMiniWidget()
                }
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: timerManager.isRunning)
    }
}

struct BatteryMiniWidget: View {
    @EnvironmentObject var batteryMonitor: BatteryMonitor
    @EnvironmentObject var bluetoothManager: BluetoothManager
    @EnvironmentObject var batteryStatusManager: BatteryStatusManager
    @StateObject private var batteryEstimator = BatteryEstimator.shared
    @EnvironmentObject var settings: SettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let internalState = batteryMonitor.currentState {
                HStack {
                    Image(systemName: "laptopcomputer")
                        .font(.body.weight(.semibold))
                        .frame(width: 20)

                    Text("MacBook")
                        .fontWeight(.medium)

                    Spacer()

                    if settings.settings.showEstimatedBatteryTime, let timeRemaining = batteryEstimator.estimatedTimeRemaining, !timeRemaining.isEmpty {
                        Text(timeRemaining)
                            .font(.system(size: 13, design: .rounded))
                            .foregroundStyle(.secondary)
                    }

                    Text("\(internalState.level)%")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))

                    FilledBatteryIcon(
                        level: internalState.level,
                        isCharging: internalState.isCharging,
                        isPluggedIn: internalState.isPluggedIn,
                        isLowBattery: internalState.isLow,
                        managementState: batteryStatusManager.currentState.managementState
                    )
                }
            }

            if let device = bluetoothManager.lastEvent, device.eventType == .connected, let batteryLevel = device.batteryLevel {
                HStack {
                    Image(systemName: device.iconName)
                        .font(.body.weight(.semibold))
                        .frame(width: 20)

                    Text(device.name)
                        .fontWeight(.medium)
                        .lineLimit(1)

                    Spacer()

                    Text("\(batteryLevel)%")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))

                    FilledBatteryIcon(
                        level: batteryLevel,
                        isCharging: false,
                        isPluggedIn: false,
                        isLowBattery: batteryLevel <= 20,
                        managementState: .charging
                    )
                }
            }
        }
        .foregroundColor(.white)
    }
}