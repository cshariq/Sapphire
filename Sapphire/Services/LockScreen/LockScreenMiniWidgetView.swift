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
        if settings.settings.lockScreenLiquidGlassLook {
            if #available(macOS 26.0, *) {
                RoundedRectangle(cornerRadius: LockScreenConfiguration.cornerRadius, style: .continuous)
                    .glassEffect(.clear, in: RoundedRectangle(cornerRadius: LockScreenConfiguration.cornerRadius, style: .continuous))
            } else {
                ZStack {
                    VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                    LinearGradient(
                        gradient: Gradient(colors: [
                            .white.opacity(0.15),
                            .white.opacity(0.05),
                            .clear
                        ]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
                .clipShape(RoundedRectangle(cornerRadius: LockScreenConfiguration.cornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: LockScreenConfiguration.cornerRadius, style: .continuous)
                        .stroke(
                            LinearGradient(
                                gradient: Gradient(colors: [.white.opacity(0.25), .clear]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: LockScreenConfiguration.backgroundStrokeWidth
                        )
                        .blur(radius: LockScreenConfiguration.backgroundStrokeBlur)
                )
            }
        } else {
            ZStack {
                VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
            }
            .clipShape(RoundedRectangle(cornerRadius: LockScreenConfiguration.cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: LockScreenConfiguration.cornerRadius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                .white.opacity(0.2),
                                .white.opacity(0.05)
                            ]),
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: LockScreenConfiguration.backgroundStrokeWidth
                    )
                    .blur(radius: LockScreenConfiguration.backgroundStrokeBlur)
            )
        }
    }
}

struct LockScreenMiniWidgetView: View {
    @EnvironmentObject var settings: SettingsModel
    @EnvironmentObject var musicManager: MusicManager
    @EnvironmentObject var calendarService: CalendarService
    @EnvironmentObject var musicWidget: MusicManager
    @EnvironmentObject var batteryMonitor: BatteryMonitor
    @EnvironmentObject var bluetoothManager: BluetoothManager

    @StateObject private var batteryStatusManager = BatteryStatusManager.shared

    @StateObject private var calendarViewModel = InteractiveCalendarViewModel()
    @State private var dummyNavigationStack: [NotchWidgetMode] = []

    @State private var maxMiniWidgetHeight: CGFloat = 0

    private var animationValue: (Bool, [LockScreenMiniWidgetType], CGFloat) {
        (musicWidget.isPlaying, settings.settings.lockScreenMiniWidgets, maxMiniWidgetHeight)
    }

    var body: some View {
        let fadeTransition = AnyTransition.opacity

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
                            MusicWidgetView()
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

                case .none:
                    EmptyView()
                        .frame(minHeight: maxMiniWidgetHeight, alignment: .top)
                }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: animationValue.0)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: animationValue.1)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: animationValue.2)
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
                    MusicWidgetView()
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