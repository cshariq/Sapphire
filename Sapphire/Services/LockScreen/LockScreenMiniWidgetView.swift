//
//  LockScreenMiniWidgetView.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-10-05.
//
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
            .padding(15) // Standard padding consistent with main widgets
            .background(backgroundMaterial)
    }

    @ViewBuilder
    private var backgroundMaterial: some View {
        if settings.settings.lockScreenLiquidGlassLook {
            if #available(macOS 26, *) {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .glassEffect(.clear, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
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
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(
                            LinearGradient(
                                gradient: Gradient(colors: [.white.opacity(0.25), .clear]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.5
                        )
                        .blur(radius: 1)
                )
            }
        } else {
            ZStack {
                VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
            }
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                .white.opacity(0.2),
                                .white.opacity(0.05)
                            ]),
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1.5
                    )
                    .blur(radius: 1)
            )
        }
    }
}

struct LockScreenMiniWidgetView: View {
    @EnvironmentObject var settings: SettingsModel
    @EnvironmentObject var musicManager: MusicManager
    @EnvironmentObject var calendarService: CalendarService
    @EnvironmentObject var musicWidget: MusicManager

    @StateObject private var calendarViewModel = InteractiveCalendarViewModel()
    @State private var dummyNavigationStack: [NotchWidgetMode] = []

    @State private var maxMiniWidgetHeight: CGFloat = 0

    var body: some View {
        HStack(spacing: 24) {
            ForEach(settings.settings.lockScreenMiniWidgets, id: \.self) { widgetType in
                switch widgetType {
                case .weather:
                    LockScreenWidgetBackground {
                        WeatherWidgetView()
                            .environment(\.navigationStack, $dummyNavigationStack)
                    }
                    .frame(height: maxMiniWidgetHeight > 0 ? maxMiniWidgetHeight : nil)

                case .calendar:
                    LockScreenWidgetBackground {
                        CalendarWidgetView(viewModel: calendarViewModel)
                            .environmentObject(calendarService)
                            .environment(\.navigationStack, $dummyNavigationStack)
                    }
                    .frame(height: maxMiniWidgetHeight > 0 ? maxMiniWidgetHeight : nil)

                case .music:
                    if musicWidget.isPlaying {
                        LockScreenWidgetBackground {
                            MusicWidgetView()
                                .environmentObject(musicManager)
                                .environmentObject(settings)
                                .environment(\.navigationStack, $dummyNavigationStack)
                        }
                        .frame(height: maxMiniWidgetHeight > 0 ? maxMiniWidgetHeight : nil)
                    }

                case .none:
                    EmptyView()
                        .frame(height: maxMiniWidgetHeight > 0 ? maxMiniWidgetHeight : nil)
                }
            }
        }
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

        case .none:
            EmptyView().measureSize()
        }
    }
}