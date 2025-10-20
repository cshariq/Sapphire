//
//  LockScreenView.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-09-11.
//

import SwiftUI

// MARK: - Lock Screen Navigation
enum LockScreenMusicView: Hashable {
    case player
    case queueAndPlaylists
    case playlistDetail(SpotifyPlaylist)
    case devices
    case lyrics
    case loginPrompt
}

class LockScreenNavigationManager: ObservableObject {
    @Published var viewStack: [LockScreenMusicView] = [.player]

    var currentView: LockScreenMusicView {
        viewStack.last ?? .player
    }

    func navigateTo(_ view: LockScreenMusicView) {
        viewStack.append(view)
    }

    func goBack() {
        if viewStack.count > 1 {
            _ = viewStack.popLast()
        }
    }
}

private struct LockScreenBackButton: View {
    @EnvironmentObject var navigationManager: LockScreenNavigationManager

    var body: some View {
        Button(action: {
            navigationManager.goBack()
        }) {
            Image(systemName: "chevron.backward")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)
                .padding(10)
                .background(Color.white.opacity(0.15).clipShape(Circle()))
        }
        .buttonStyle(.plain)
        .padding()
    }
}

// MARK: - Environment Keys
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

// MARK: - Main View Container
struct LockScreenMainWidgetContainerView: View {
    @EnvironmentObject var settings: SettingsModel
    @EnvironmentObject var musicManager: MusicManager
    @EnvironmentObject var calendarService: CalendarService

    @StateObject private var navigationManager = LockScreenNavigationManager()
    @State private var maxMainWidgetHeight: CGFloat = 0
    @State private var dummyStack: [NotchWidgetMode] = []

    var body: some View {
        HStack(spacing: LockScreenConfiguration.widgetSpacing) {
            let _ = print("[Layout Debug - Main] Rebuilding view with max height: \(Int(maxMainWidgetHeight))")
            ForEach(settings.settings.lockScreenMainWidgets, id: \.self) { widgetType in
                widgetView(for: widgetType)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: navigationManager.currentView)

        .frame(height: maxMainWidgetHeight > 0 ? maxMainWidgetHeight : nil)

        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: maxMainWidgetHeight)

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
        .environmentObject(navigationManager)
    }

    @ViewBuilder
    private func widgetView(for widgetType: LockScreenMainWidgetType) -> some View {
        let fadeTransition = AnyTransition.opacity.animation(.easeInOut(duration: 0.2))

        switch widgetType {
        case .music:
            if musicManager.isPlaying {
                musicNavigationHostView
                    .transition(fadeTransition)
            }
        case .weather:
            LockScreenWeatherView()
                .transition(fadeTransition)
        case .calendar:
            LockScreenCalendarView()
                .transition(fadeTransition)
        }
    }

    @ViewBuilder
    private var musicNavigationHostView: some View {
        ZStack {
            switch navigationManager.currentView {
            case .player:
                LockScreenView()
            case .queueAndPlaylists:
                LockScreenPaddedBackground {
                    ZStack(alignment: .topLeading) {
                        QueueAndPlaylistsView(navigationStack: $dummyStack, isLockScreenMode: true)
                        LockScreenBackButton()
                    }
                }
            case .playlistDetail(let playlist):
                LockScreenPaddedBackground {
                    ZStack(alignment: .topLeading) {
                        PlaylistView(playlist: playlist, isLockScreenMode: true)
                        LockScreenBackButton()
                    }
                }
            case .devices:
                LockScreenPaddedBackground {
                    ZStack(alignment: .topLeading) {
                        DevicesView(navigationStack: $dummyStack, isLockScreenMode: true)
                        LockScreenBackButton()
                    }
                }
            case .lyrics:
                 LockScreenPaddedBackground {
                    ZStack(alignment: .topLeading) {
                        LyricsView()
                        LockScreenBackButton()
                    }
                }
            case .loginPrompt:
                LockScreenPaddedBackground {
                    ZStack(alignment: .topLeading) {
                        LoginPromptView(navigationStack: $dummyStack)
                        LockScreenBackButton()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func measurementPreview(for widgetType: LockScreenMainWidgetType) -> some View {
        switch widgetType {
        case .music:
            if musicManager.isPlaying {
                switch navigationManager.currentView {
                case .player:
                    LockScreenView().measureSize()
                case .queueAndPlaylists:
                    LockScreenPaddedBackground {
                        QueueAndPlaylistsView(navigationStack: $dummyStack, isLockScreenMode: true)
                    }.measureSize()
                case .playlistDetail(let playlist):
                    LockScreenPaddedBackground {
                        PlaylistView(playlist: playlist, isLockScreenMode: true)
                    }.measureSize()
                case .devices:
                    LockScreenPaddedBackground {
                        DevicesView(navigationStack: $dummyStack, isLockScreenMode: true)
                    }.measureSize()
                case .lyrics:
                    LockScreenPaddedBackground {
                        LyricsView()
                    }.measureSize()
                case .loginPrompt:
                    LockScreenPaddedBackground {
                        LoginPromptView(navigationStack: $dummyStack)
                    }.measureSize()
                }
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

// MARK: - Reusable Background
struct LockScreenPaddedBackground<Content: View>: View {
    @EnvironmentObject var settings: SettingsModel
    @Environment(\.lockScreenWidgetHeight) private var _lockScreenWidgetHeight: CGFloat?
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(LockScreenConfiguration.backgroundPadding)
            .frame(height: _lockScreenWidgetHeight)
            .background(backgroundMaterial)
    }

    @ViewBuilder
    private var backgroundMaterial: some View {
        if settings.settings.lockScreenLiquidGlassLook {
            if #available(macOS 26, *) {
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

// MARK: - Specific Widget Views
struct LockScreenView: View {
    @EnvironmentObject var musicManager: MusicManager
    @EnvironmentObject var settings: SettingsModel
    @State private var dummyNavigationStack: [NotchWidgetMode] = [.musicPlayer]

    var body: some View {
        LockScreenPaddedBackground {
            MusicPlayerView(navigationStack: $dummyNavigationStack, isLockScreenMode: true)
                .environmentObject(musicManager)
                .environmentObject(settings)
        }
    }
}

struct LockScreenWeatherView: View {
    @EnvironmentObject var settings: SettingsModel
    @Environment(\.lockScreenWidgetHeight) private var _lockScreenWidgetHeight: CGFloat?

    var body: some View {
        WeatherPlayerView()
            .padding(LockScreenConfiguration.backgroundPadding)
            .frame(height: _lockScreenWidgetHeight)
            .background(LockScreenPaddedBackground { EmptyView() })
    }
}

struct LockScreenCalendarView: View {
    @EnvironmentObject var settings: SettingsModel
    @Environment(\.lockScreenWidgetHeight) private var _lockScreenWidgetHeight: CGFloat?

    var body: some View {
        CalendarDetailView()
            .padding(LockScreenConfiguration.backgroundPadding)
            .frame(height: _lockScreenWidgetHeight)
            .background(LockScreenPaddedBackground { EmptyView() })
    }
}