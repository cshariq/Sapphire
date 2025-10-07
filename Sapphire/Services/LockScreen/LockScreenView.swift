//
//  LockScreenView.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-09-11.
//
//

import SwiftUI

private struct LockScreenWidgetHeightKey: EnvironmentKey {
    static let defaultValue: CGFloat? = nil
}

private extension EnvironmentValues {
    var lockScreenWidgetHeight: CGFloat? {
        get { self[LockScreenWidgetHeightKey.self] }
        set { self[LockScreenWidgetHeightKey.self] = newValue }
    }
}

private struct LockScreenMiniWidgetHeightKey: EnvironmentKey {
    static let defaultValue: CGFloat? = nil
}

private extension EnvironmentValues {
    var lockScreenMiniWidgetHeight: CGFloat? {
        get { self[LockScreenMiniWidgetHeightKey.self] }
        set { self[LockScreenMiniWidgetHeightKey.self] = newValue }
    }
}

struct LockScreenMainWidgetContainerView: View {
    @EnvironmentObject var settings: SettingsModel
    @EnvironmentObject var musicManager: MusicManager
    @EnvironmentObject var calendarService: CalendarService

    @State private var maxMainWidgetHeight: CGFloat = 0

    var body: some View {
        HStack(spacing: 24) {
            let _ = print("[Layout Debug - Main] Rebuilding view with max height: \(Int(maxMainWidgetHeight))")
            ForEach(settings.settings.lockScreenMainWidgets, id: \.self) { widgetType in
                widgetView(for: widgetType)
            }
        }
        .frame(height: maxMainWidgetHeight > 0 ? maxMainWidgetHeight : nil)
        .background(
            VStack(spacing: 0) {
                ForEach(settings.settings.lockScreenMainWidgets, id: \.self) { widgetType in
                    measurementPreview(for: widgetType)
                }
            }
            .onPreferenceChange(SizePreferenceKey.self) { sizes in
                let maxHeight = sizes.map { $0.height }.max() ?? 0
                print("[Layout Debug - Main] Measure active widgets -> \(sizes.map { Int($0.height) }) max=\(Int(maxHeight))")
                if self.maxMainWidgetHeight != maxHeight {
                    self.maxMainWidgetHeight = maxHeight
                    print("[Layout Debug - Main] ---> UPDATED maxMainWidgetHeight=\(Int(maxHeight))")
                }
            }
            .opacity(0)
            .allowsHitTesting(false)
        )
        .environment(\.lockScreenWidgetHeight, maxMainWidgetHeight > 0 ? maxMainWidgetHeight : nil)
        .frame(minHeight: maxMainWidgetHeight > 0 ? maxMainWidgetHeight : 1)
        .environmentObject(settings)
        .environmentObject(musicManager)
        .environmentObject(calendarService)
    }

    @ViewBuilder
    private func widgetView(for widgetType: LockScreenMainWidgetType) -> some View {
        switch widgetType {
        case .music:
            if musicManager.isPlaying {
                LockScreenView()
            }
        case .weather:
            LockScreenWeatherView()
        case .calendar:
            LockScreenCalendarView()
        }
    }

    @ViewBuilder
    private func measurementPreview(for widgetType: LockScreenMainWidgetType) -> some View {
        switch widgetType {
        case .music:
            if musicManager.isPlaying {
                LockScreenView().measureSize()
            } else {
                EmptyView().measureSize()
            }
        case .weather:
            LockScreenWeatherView().measureSize()
        case .calendar:
            LockScreenCalendarView().measureSize()
        }
    }
}

struct LockScreenView: View {
    @EnvironmentObject var musicManager: MusicManager
    @EnvironmentObject var settings: SettingsModel

    @Environment(\.lockScreenWidgetHeight) private var _lockScreenWidgetHeight: CGFloat?

    @State private var dummyNavigationStack: [NotchWidgetMode] = [.musicPlayer]

    var body: some View {
        let fixedHeight = _lockScreenWidgetHeight
        return MusicPlayerView(navigationStack: $dummyNavigationStack, isLockScreenMode: true)
            .environmentObject(musicManager)
            .environmentObject(settings)
            .padding(15)
            .frame(height: fixedHeight)
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

struct LockScreenWeatherView: View {
    @EnvironmentObject var settings: SettingsModel
    @Environment(\.lockScreenWidgetHeight) private var _lockScreenWidgetHeight: CGFloat?

    var body: some View {
        WeatherPlayerView()
            .padding(15)
            .frame(height: _lockScreenWidgetHeight)
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

struct LockScreenCalendarView: View {
    @EnvironmentObject var settings: SettingsModel
    @Environment(\.lockScreenWidgetHeight) private var _lockScreenWidgetHeight: CGFloat?

    var body: some View {
        CalendarDetailView()
            .padding(15)
            .frame(height: _lockScreenWidgetHeight)
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
                                gradient: Gradient(colors: [
                                    .white.opacity(0.25),
                                    .clear
                                ]),
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