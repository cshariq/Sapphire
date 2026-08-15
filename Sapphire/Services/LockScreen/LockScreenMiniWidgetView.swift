//
//  LockScreenMiniWidgetView.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-10-05.
//

import SwiftUI

struct LockScreenWidgetBackground<Content: View>: View {
    @EnvironmentObject var settings: SettingsModel

    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(LockScreenConfiguration.backgroundPadding)
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
    @EnvironmentObject var musicManager: MusicManager
    @EnvironmentObject var calendarService: CalendarService
    @EnvironmentObject var musicWidget: MusicManager
    @EnvironmentObject var batteryMonitor: BatteryMonitor
    @EnvironmentObject var bluetoothManager: BluetoothManager
    @EnvironmentObject var focusModeManager: FocusModeManager
    @EnvironmentObject var timerManager: TimerManager

    @StateObject private var batteryStatusManager = BatteryStatusManager.shared

    @StateObject private var calendarViewModel = InteractiveCalendarViewModel()
    @State private var dummyNavigationStack: [NotchWidgetMode] = []

    @State private var maxMiniWidgetHeight: CGFloat = 0

    private var animationToken: String {
        let widgets = settings.settings.lockScreenMiniWidgets.map(\.rawValue).joined(separator: ",")
        return "\(musicWidget.isPlaying)-\(widgets)-\(Int(maxMiniWidgetHeight))-\(timerManager.isRunning)"
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
                    .frame(minHeight: maxMiniWidgetHeight, alignment: .top)
                    .transition(fadeTransition)

                case .calendar:
                    LockScreenWidgetBackground {
                        CalendarWidgetView(viewModel: calendarViewModel)
                            .environmentObject(calendarService)
                            .environment(\.navigationStack, $dummyNavigationStack)
                    }
                    .frame(minHeight: maxMiniWidgetHeight, alignment: .top)
                    .transition(fadeTransition)

                case .music:
                    if musicWidget.isPlaying {
                        LockScreenWidgetBackground {
                            MusicWidgetView(onExpand: {
                                LockScreenMusicPaneController.shared.open()
                            })
                                .environmentObject(musicManager)
                                .environmentObject(settings)
                                .environment(\.navigationStack, $dummyNavigationStack)
                        }
                        .frame(minHeight: maxMiniWidgetHeight, alignment: .top)
                        .transition(fadeTransition)
                    }
                case .battery:
                    LockScreenWidgetBackground {
                        BatteryMiniWidget()
                    }
                    .frame(minHeight: maxMiniWidgetHeight, alignment: .top)
                    .transition(fadeTransition)

                case .focus:
                    LockScreenWidgetBackground {
                        LockScreenFocusMiniWidget()
                    }
                    .frame(minHeight: maxMiniWidgetHeight, alignment: .top)
                    .transition(fadeTransition)

                case .caffeine:
                    LockScreenWidgetBackground {
                        LockScreenCaffeineMiniWidget()
                    }
                    .frame(minHeight: maxMiniWidgetHeight, alignment: .top)
                    .transition(fadeTransition)

                case .timer:
                    if timerManager.isRunning || !settings.settings.lockScreenHideInactiveInfoWidgets {
                        LockScreenWidgetBackground {
                            LockScreenTimerMiniWidget()
                        }
                        .frame(minHeight: maxMiniWidgetHeight, alignment: .top)
                        .transition(fadeTransition)
                    }

                case .bluetooth:
                    LockScreenWidgetBackground {
                        LockScreenBluetoothMiniWidget()
                    }
                    .frame(minHeight: maxMiniWidgetHeight, alignment: .top)
                    .transition(fadeTransition)

                case .clipboard:
                    LockScreenWidgetBackground {
                        ClipboardWidgetView()
                    }
                    .frame(minHeight: maxMiniWidgetHeight, alignment: .top)
                    .transition(fadeTransition)

                case .notes:
                    LockScreenWidgetBackground {
                        NotesWidgetView()
                    }
                    .frame(minHeight: maxMiniWidgetHeight, alignment: .top)
                    .transition(fadeTransition)

                case .system:
                    LockScreenWidgetBackground {
                        LockScreenSystemMiniWidget()
                    }
                    .frame(minHeight: maxMiniWidgetHeight, alignment: .top)
                    .transition(fadeTransition)

                case .none:
                    EmptyView()
                        .frame(minHeight: maxMiniWidgetHeight, alignment: .top)
                }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: animationToken)
        .fixedSize(horizontal: true, vertical: false)
        .background(
            VStack(spacing: 0) {
                ForEach(settings.settings.lockScreenMiniWidgets, id: \.self) { widgetType in
                    measurementPreview(for: widgetType)
                }
            }
            .onPreferenceChange(SizePreferenceKey.self) { sizes in
                let maxH = sizes.map { $0.height }.max() ?? 0
                if maxMiniWidgetHeight != maxH {
                    maxMiniWidgetHeight = maxH
                    print("[Layout Debug - Mini] ---> UPDATING maxMiniWidgetHeight to \(Int(maxH))")
                }
            }
            .opacity(0)
            .allowsHitTesting(false)
        )
        .environmentObject(musicManager)
        .environmentObject(calendarService)
        .environmentObject(settings)
        .environmentObject(batteryMonitor)
        .environmentObject(bluetoothManager)
        .environmentObject(batteryStatusManager)
        .environmentObject(focusModeManager)
        .environmentObject(timerManager)
    }

    @ViewBuilder
    private func measurementPreview(for widgetType: LockScreenMiniWidgetType) -> some View {
        switch widgetType {
        case .weather:
            LockScreenWidgetBackground {
                WeatherWidgetView()
                    .environment(\.navigationStack, $dummyNavigationStack)
            }
            .measureSize()

        case .calendar:
            LockScreenWidgetBackground {
                CalendarWidgetView(viewModel: calendarViewModel)
                    .environmentObject(calendarService)
                    .environment(\.navigationStack, $dummyNavigationStack)
            }
            .measureSize()

        case .music:
            if musicWidget.isPlaying {
                LockScreenWidgetBackground {
                    MusicWidgetView(onExpand: {
                        LockScreenMusicPaneController.shared.open()
                    })
                        .environmentObject(musicManager)
                        .environmentObject(settings)
                        .environment(\.navigationStack, $dummyNavigationStack)
                }
                .measureSize()
            } else {
                EmptyView().measureSize()
            }

        case .battery:
            LockScreenWidgetBackground {
                BatteryMiniWidget()
            }
            .measureSize()

        case .focus:
            LockScreenWidgetBackground {
                LockScreenFocusMiniWidget()
            }
            .measureSize()

        case .caffeine:
            LockScreenWidgetBackground {
                LockScreenCaffeineMiniWidget()
            }
            .measureSize()

        case .timer:
            LockScreenWidgetBackground {
                LockScreenTimerMiniWidget()
            }
            .measureSize()

        case .bluetooth:
            LockScreenWidgetBackground {
                LockScreenBluetoothMiniWidget()
            }
            .measureSize()

        case .clipboard:
            LockScreenWidgetBackground {
                ClipboardWidgetView()
            }
            .measureSize()

        case .notes:
            LockScreenWidgetBackground {
                NotesWidgetView()
            }
            .measureSize()

        case .system:
            LockScreenWidgetBackground {
                LockScreenSystemMiniWidget()
            }
            .measureSize()

        case .none:
            EmptyView().measureSize()
        }
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