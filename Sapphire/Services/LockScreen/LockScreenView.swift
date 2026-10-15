//
//  LockScreenView.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-09-11.
//

import SwiftUI
import AppKit

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

struct LockScreenMiniWidgetHeightKey: EnvironmentKey {
    static let defaultValue: CGFloat? = nil
}

extension EnvironmentValues {
    var lockScreenMiniWidgetHeight: CGFloat? {
        get { self[LockScreenMiniWidgetHeightKey.self] }
        set { self[LockScreenMiniWidgetHeightKey.self] = newValue }
    }
}

// MARK: - Main View Container
struct LockScreenMainWidgetContainerView: View {
    @ObservedSettings var settings: SettingsObserver
    @StateObject private var navigationManager = LockScreenNavigationManager()
    @State private var maxMainWidgetHeight: CGFloat = 0
    @State private var dummyStack: [NotchWidgetMode] = []
    @State private var playerStack: [NotchWidgetMode] = [.musicPlayer]

    var body: some View {
        HStack(alignment: .top, spacing: LockScreenConfiguration.widgetSpacing) {
            ForEach(settings.settings.lockScreenMainWidgets, id: \.self) { widgetType in
                widgetView(for: widgetType)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: navigationManager.currentView)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: maxMainWidgetHeight)
        .fixedSize(horizontal: true, vertical: false)
        .onPreferenceChange(SizePreferenceKey.self) { sizes in
            let maxHeight = sizes.map(\.height).max() ?? 0
            if maxMainWidgetHeight != maxHeight {
                maxMainWidgetHeight = maxHeight
            }
        }
        .environment(\.lockScreenWidgetHeight, maxMainWidgetHeight > 0 ? maxMainWidgetHeight : nil)
        .environmentObject(navigationManager)
    }

    @ViewBuilder
    private func widgetView(for widgetType: LockScreenMainWidgetType) -> some View {
        let fadeTransition = AnyTransition.opacity.animation(.easeInOut(duration: 0.2))

        switch widgetType {
        case .music:
            LockScreenConditionalMusicView(
                showWhenPaused: settings.settings.lockScreenShowMusicWhenPaused
            ) {
                musicNavigationHostView
            }
            .transition(fadeTransition)
        case .weather:
            LockScreenWeatherView()
                .transition(fadeTransition)
        case .calendar:
            LockScreenCalendarView()
                .transition(fadeTransition)
        case .battery:
            LockScreenBatteryMainView()
                .transition(fadeTransition)
        case .focus:
            LockScreenFocusMainView()
                .transition(fadeTransition)
        case .timer:
            LockScreenTimerMainView()
                .transition(fadeTransition)
        case .notes:
            LockScreenNotesMainView()
                .transition(fadeTransition)
        case .clipboard:
            LockScreenClipboardMainView()
                .transition(fadeTransition)
        }
    }

    private var musicNavigationHostView: some View {
        LockScreenPaddedBackground {
            ZStack(alignment: .topLeading) {
                musicPage(for: navigationManager.currentView)
                    .id(navigationManager.currentView)
                    .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))

                if navigationManager.currentView != .player {
                    LockScreenBackButton()
                        .padding(.top, 52)
                        .zIndex(10)
                        .transition(.opacity)
                }
            }
        }
    }

    @ViewBuilder
    private func musicPage(for page: LockScreenMusicView) -> some View {
        switch page {
        case .player:
            MusicPlayerView(navigationStack: $playerStack, isLockScreenMode: true)
        case .queueAndPlaylists, .devices:
            QueueAndPlaylistsView(navigationStack: $dummyStack, isLockScreenMode: true)
        case .playlistDetail(let playlist):
            PlaylistView(playlist: playlist, isLockScreenMode: true)
        case .lyrics:
            LyricsView()
        case .loginPrompt:
            LoginPromptView(navigationStack: $dummyStack)
        }
    }

}

private struct LockScreenConditionalMusicView<Content: View>: View {
    private var musicManager: MusicManager { .shared }

    let showWhenPaused: Bool
    let content: Content

    init(showWhenPaused: Bool, @ViewBuilder content: () -> Content) {
        self.showWhenPaused = showWhenPaused
        self.content = content()
    }

    var body: some View {
        let hasTrack = !(musicManager.title?.isEmpty ?? true)
        if musicManager.isPlaying || (showWhenPaused && hasTrack) {
            content
                .transition(.opacity.animation(.easeInOut(duration: 0.2)))
        }
    }
}

// MARK: - Reusable Background
struct LockScreenPaddedBackground<Content: View>: View {
    @Environment(\.lockScreenWidgetHeight) private var _lockScreenWidgetHeight: CGFloat?
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(LockScreenConfiguration.backgroundPadding)
            .measureSize()
            .frame(minHeight: _lockScreenWidgetHeight, alignment: .top)
            .background(backgroundMaterial)
    }

    @ViewBuilder
    private var backgroundMaterial: some View {
        LockScreenCardSurface()
    }
}

// MARK: - Specific Widget Views
struct LockScreenWeatherView: View {
    @Environment(\.lockScreenWidgetHeight) private var _lockScreenWidgetHeight: CGFloat?

    var body: some View {
        WeatherPlayerView()
            .padding(LockScreenConfiguration.backgroundPadding)
            .measureSize()
            .frame(minHeight: _lockScreenWidgetHeight, alignment: .top)
            .background(
                LockScreenCardSurface()
            )
    }
}

struct LockScreenCalendarView: View {
    @Environment(\.lockScreenWidgetHeight) private var _lockScreenWidgetHeight: CGFloat?

    var body: some View {
        CalendarDetailView()
            .padding(LockScreenConfiguration.backgroundPadding)
            .measureSize()
            .frame(minHeight: _lockScreenWidgetHeight, alignment: .top)
            .background(
                LockScreenCardSurface()
            )
    }
}