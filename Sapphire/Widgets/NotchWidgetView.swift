//
//  NotchWidgetView.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-11-16

import Combine
import SwiftUI

enum MusicWidgetVisibilityPolicy {
    static func shouldShow(
        isEnabled: Bool,
        hideWhenNotPlaying: Bool,
        isPlaying: Bool,
        hidePausedSpotifyWhenIdle: Bool,
        isSpotifyPausedWithNoOtherPlayback: Bool,
        hideSpotifyWhenAppClosed: Bool,
        isLoggedIntoSpotify: Bool,
        isSpotifyOnlySource: Bool,
        isSpotifyAppRunning: Bool
    ) -> Bool {
        guard isEnabled else { return false }
        if hideWhenNotPlaying && !isPlaying { return false }
        if hidePausedSpotifyWhenIdle && isSpotifyPausedWithNoOtherPlayback { return false }
        if hideSpotifyWhenAppClosed,
           isLoggedIntoSpotify,
           isSpotifyOnlySource,
           !isSpotifyAppRunning {
            return false
        }
        return true
    }
}

private struct NavigationStackKey: EnvironmentKey {
    static let defaultValue: Binding<[NotchWidgetMode]> = .constant([.defaultWidgets])
}
private struct ActiveDropZoneKey: EnvironmentKey {
    static let defaultValue: Binding<DropZone?> = .constant(nil)
}

private struct OnActiveSnapZoneChangeKey: EnvironmentKey {
    static let defaultValue: (SnapZone?) -> Void = { _ in }
}

private struct OnDropZoneFramesChangeKey: EnvironmentKey {
    static let defaultValue: ([DropZone: CGRect]) -> Void = { _ in }
}

private struct OnSnapZoneHitRegionsChangeKey: EnvironmentKey {
    static let defaultValue: ([SnapZoneHitRegion]) -> Void = { _ in }
}

private struct FileDragModeKey: EnvironmentKey {
    static let defaultValue: FileDragMode = .newFile
}

private struct IsCalendarHoveredKey: EnvironmentKey {
    static let defaultValue: Binding<Bool> = .constant(false)
}

extension EnvironmentValues {
    var navigationStack: Binding<[NotchWidgetMode]> {
        get { self[NavigationStackKey.self] }
        set { self[NavigationStackKey.self] = newValue }
    }
    var activeDropZone: Binding<DropZone?> {
        get { self[ActiveDropZoneKey.self] }
        set { self[ActiveDropZoneKey.self] = newValue }
    }
    var onActiveSnapZoneChange: (SnapZone?) -> Void {
        get { self[OnActiveSnapZoneChangeKey.self] }
        set { self[OnActiveSnapZoneChangeKey.self] = newValue }
    }
    var onDropZoneFramesChange: ([DropZone: CGRect]) -> Void {
        get { self[OnDropZoneFramesChangeKey.self] }
        set { self[OnDropZoneFramesChangeKey.self] = newValue }
    }
    var onSnapZoneHitRegionsChange: ([SnapZoneHitRegion]) -> Void {
        get { self[OnSnapZoneHitRegionsChangeKey.self] }
        set { self[OnSnapZoneHitRegionsChangeKey.self] = newValue }
    }
    var fileDragMode: FileDragMode {
        get { self[FileDragModeKey.self] }
        set { self[FileDragModeKey.self] = newValue }
    }
    var isCalendarHovered: Binding<Bool> {
        get { self[IsCalendarHoveredKey.self] }
        set { self[IsCalendarHoveredKey.self] = newValue }
    }
}

extension CoordinateSpaceProtocol where Self == NamedCoordinateSpace {
    static var notchDrag: NamedCoordinateSpace { .named("NotchDragCoordinateSpace") }
}

@MainActor
final class NotchDragLocationState: ObservableObject {
    @Published private(set) var location: CGPoint?

    func update(_ newLocation: CGPoint?) {
        guard location != newLocation else { return }
        location = newLocation
    }
}

struct NotchWidgetView: View {
    @Environment(\.navigationStack) var navigationStack
    @Environment(\.activeDropZone) var activeDropZone
    @Environment(\.onActiveSnapZoneChange) var onActiveSnapZoneChange
    @Environment(\.onDropZoneFramesChange) var onDropZoneFramesChange
    @Environment(\.onSnapZoneHitRegionsChange) var onSnapZoneHitRegionsChange
    @Environment(\.fileDragMode) var fileDragMode

    private let calendarViewModel: InteractiveCalendarViewModel

    private var currentMode: NotchWidgetMode {
        navigationStack.wrappedValue.last ?? .defaultWidgets
    }
    @State private var displayedMode: NotchWidgetMode = .defaultWidgets
    @Environment(\.notchWidgetSwitchGate) private var switchGate

    init(calendarViewModel: InteractiveCalendarViewModel) {
        self.calendarViewModel = calendarViewModel
    }

    var body: some View {
        contentSwitch(for: displayedMode)
            .id(displayedMode)
            .onAppear {
                self.displayedMode = self.currentMode
            }
            .onChange(of: currentMode) {
                guard displayedMode != currentMode else { return }
                if switchGate?.isSuppressed == true {
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) { self.displayedMode = self.currentMode }
                    return
                }
                playSwitch()
            }
            .notchHorizontalPadding()
    }

    private func playSwitch() {
        switchGate?.willSwitch?()
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { self.displayedMode = self.currentMode }
    }

    @ViewBuilder
    private func contentSwitch(for mode: NotchWidgetMode) -> some View {
        switch mode {
        case .defaultWidgets:
            NotchDefaultWidgetsView(calendarViewModel: calendarViewModel)
        case .musicApiKeysMissing:
            ApiKeysMissingView(navigationStack: navigationStack)
        case .geminiApiKeysMissing:
            GeminiApiKeysMissingView(navigationStack: navigationStack)
        case .musicPlayer:
            MusicPlayerView(navigationStack: navigationStack)
        case .sportsPlayer:
            SportsPlayerView(navigationStack: navigationStack)
        case .financePlayer:
            FinancePlayerView(navigationStack: navigationStack)
        case .shopifyOrders:
            ShopifyOrdersView()
        case .notesPlayer:
            NotesPlayerView(navigationStack: navigationStack)
        case .clipboardPlayer:
            ClipboardPlayerView(navigationStack: navigationStack)
        case .mirrorPlayer:
            MirrorPlayerView()
        case .musicLoginPrompt:
            LoginPromptView(navigationStack: navigationStack)
        case .musicQueueAndPlaylists:
            QueueAndPlaylistsView(navigationStack: navigationStack)
        case .musicDevices:
            QueueAndPlaylistsView(navigationStack: navigationStack)
        case .musicLyrics:
            LyricsView()
        case .musicPlaylistDetail(let playlist):
            PlaylistView(playlist: playlist)
        case .musicArtistDetail(let uri, let name):
            SpotifyArtistDetailView(uri: uri, name: name, navigationStack: navigationStack)
        case .musicAlbumDetail(let uri, let name):
            SpotifyAlbumDetailView(uri: uri, name: name, navigationStack: navigationStack)
        case .nearbyTransfer:
            FileTaskView(navigationStack: navigationStack)
        case .weatherPlayer:
            WeatherPlayerView()
        case .calendarPlayer:
            CalendarDetailView(viewModel: calendarViewModel)
        case .timerDetailView:
            TimerDetailView(navigationStack: navigationStack)
        case .snapZones:
            SnapZonesWidgetView(
                onActiveZoneChange: onActiveSnapZoneChange,
                onHitRegionsChange: onSnapZoneHitRegionsChange
            )
        case .fileShelf:
            FileShelfView()
        case .fileShelfLanding:
            FileDragLandingView(
                mode: fileDragMode,
                activeZone: activeDropZone,
                onZoneFramesChange: onDropZoneFramesChange
            )
        case .fileActionPreview:
            FileActionPreviewContent()
        case .multiAudio:
            MultiAudioView(navigationStack: navigationStack)
        case .multiAudioDeviceAdjust(let device):
            DeviceAdjustView(device: device)
        case .multiAudioEQ(let device):
            DeviceEQView(device: device)
        case .earbudControls(let device):
            EarbudControlsView(device: device)
        case .multiAudioAppEQ(let bundleID, let appName):
            AppEQView(bundleID: bundleID, appName: appName)
        case .multiAudioApp8D(let bundleID, let appName):
            EightDAudioView(bundleID: bundleID, appName: appName)
        case .multiAudioAppSurround(let bundleID, let appName):
            SurroundAudioView(bundleID: bundleID, appName: appName)

        case .dragActivated:
            Color.clear
                .frame(width: 300, height: 200)
        case .agentS:
            IntelligenceNotchView(navigationStack: navigationStack)
        case .blipHub:
            BlipHubView(navigationStack: navigationStack)
        case .circleToSearch:
            CircleToSearchResultsView(navigationStack: navigationStack)
        case .updateAvailable:
            UpdateAvailableWidgetView()
        case .focusSessionDetailView:
            FocusSessionDetailView(navigationStack: navigationStack)
        case .batteryDetailView:
            BatteryDetailView()
        case .storageDetailView:
            StorageDetailView()
        case .continuityDetail:
            ContinuityNotchDetailView(navigationStack: navigationStack)
        case .continuityActivityDetail:
            ContinuityExternalActivityDetailView(bridge: ContinuityManager.shared.liveActivityBridge)
        case .fileProgressDetail:
            FileProgressDetailView()
        case .appActivityDetail:
            AppActivityDetailView()
        case .devDashboard:
            DevDashboardView(initialTab: .activity)
        case .devActivityDetail:
            DevDashboardView(initialTab: .activity)
        }
    }

}

private struct NotchDefaultWidgetsView: View {
    @Environment(\.navigationStack) private var navigationStack
    @Environment(\.notchDisplayWidth) private var notchDisplayWidth
    @Environment(\.isCalendarHovered) private var isCalendarHovered
    @ObservedSettings private var settings: SettingsObserver
    @State private var musicVisibility: MusicWidgetVisibilitySnapshot

    let calendarViewModel: InteractiveCalendarViewModel
    private let musicWidget = MusicManager.shared

    init(calendarViewModel: InteractiveCalendarViewModel) {
        self.calendarViewModel = calendarViewModel
        _musicVisibility = State(
            initialValue: MusicWidgetVisibilitySnapshot(manager: MusicManager.shared)
        )
    }

    private var enabledAndOrderedWidgets: [WidgetType] {
        let enabled = settings.settings.widgetOrder.filter { widgetType in
            guard !widgetType.isPremiumLocked else { return false }
            switch widgetType {
            case .music:
                return MusicWidgetVisibilityPolicy.shouldShow(
                    isEnabled: settings.settings.musicWidgetEnabled,
                    hideWhenNotPlaying: settings.settings.hideMusicWidgetWhenNotPlaying,
                    isPlaying: musicVisibility.isPlaying,
                    hidePausedSpotifyWhenIdle: settings.settings.hideMusicWidgetWhenSpotifyPausedAndIdle,
                    isSpotifyPausedWithNoOtherPlayback: musicVisibility.isSpotifyPausedWithNoOtherPlayback,
                    hideSpotifyWhenAppClosed: settings.settings.hideSpotifyWidgetWhenAppClosed,
                    isLoggedIntoSpotify: musicVisibility.isLoggedIntoSpotify,
                    isSpotifyOnlySource: musicVisibility.isSpotifyOnlySource,
                    isSpotifyAppRunning: musicVisibility.isSpotifyAppRunning
                )
            case .weather:
                return settings.settings.weatherWidgetEnabled
            case .sports:
                return settings.settings.sportsWidgetEnabled
            case .finance:
                return settings.settings.financeWidgetEnabled
            case .shopify:
                return settings.settings.shopifyWidgetEnabled
            case .calendar:
                return settings.settings.calendarWidgetEnabled
            case .battery:
                return settings.settings.batteryWidgetEnabled
            case .timer:
                return settings.settings.timerWidgetEnabled
            case .shortcuts:
                return settings.settings.shortcutsWidgetEnabled
            case .notes:
                return settings.settings.notesWidgetEnabled
            case .clipboard:
                return settings.settings.clipboardWidgetEnabled
            case .mirror:
                return settings.settings.mirrorWidgetEnabled
            case .storage:
                return settings.settings.storageWidgetEnabled
            case .dev:
                return settings.settings.devWidgetEnabled
            case .agent:
                return false
            case .focusSession:
                return settings.settings.focusSessionWidgetEnabled
            }
        }

        return WidgetLayoutPolicy.fittingWidgets(
            from: enabled,
            availableWidth: WidgetLayoutPolicy.availableBarWidth(notchDisplayWidth: notchDisplayWidth),
            showDividers: settings.settings.showDividersBetweenWidgets,
            bypassSpaceLimit: settings.settings.bypassWidgetSpaceLimit
        )
    }

    var body: some View {
        let widgets = enabledAndOrderedWidgets
        HStack(spacing: 20) {
            ForEach(widgets) { widgetType in
                widgetView(for: widgetType)
                    .id(widgetType)

                if widgetType != widgets.last && settings.settings.showDividersBetweenWidgets {
                    Divider()
                        .frame(height: 60)
                        .background(Color.white.opacity(0.3))
                }
            }
        }
        .onAppear(perform: refreshMusicVisibility)
        .onReceive(Self.musicVisibilityChanges) { snapshot in
            if snapshot != musicVisibility { musicVisibility = snapshot }
        }
        .onReceive(
            NSWorkspace.shared.notificationCenter
                .publisher(for: NSWorkspace.didLaunchApplicationNotification)
                .merge(with: NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didTerminateApplicationNotification))
                .filter { notification in
                    (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier == "com.spotify.client"
                }
        ) { _ in
            refreshMusicVisibility()
        }
    }

    private static let musicVisibilityChanges = observationPublisher {
        MainActor.assumeIsolated { MusicWidgetVisibilitySnapshot(manager: .shared) }
    }
    .removeDuplicates()

    private func refreshMusicVisibility() {
        let snapshot = MusicWidgetVisibilitySnapshot(manager: musicWidget)
        guard snapshot != musicVisibility else { return }
        musicVisibility = snapshot
    }

    @ViewBuilder
    private func widgetView(for widgetType: WidgetType) -> some View {
        switch widgetType {
        case .music:
            MusicWidgetView()
                .onTapGesture {
                    if settings.settings.musicOpenOnClick {
                        Task {
                            try? await Task.sleep(for: .seconds(NotchConfiguration.primaryWidgetSwitchDelay))
                            navigationStack.wrappedValue.append(NotchWidgetMode.musicPlayer)
                        }
                    }
                }
        case .weather:
            WeatherWidgetView()
                .onTapGesture {
                    if settings.settings.weatherOpenOnClick {
                        Task {
                            try? await Task.sleep(for: .seconds(NotchConfiguration.primaryWidgetSwitchDelay))
                            navigationStack.wrappedValue.append(NotchWidgetMode.weatherPlayer)
                        }
                    }
                }
        case .sports:
            SportsWidgetView()
                .onTapGesture {
                    if settings.settings.sportsOpenOnClick, SubscriptionManager.shared.hasAccess(to: .sportsWidget) {
                        Task {
                            try? await Task.sleep(for: .seconds(NotchConfiguration.primaryWidgetSwitchDelay))
                            navigationStack.wrappedValue.append(NotchWidgetMode.sportsPlayer)
                        }
                    }
                }
        case .finance:
            FinanceWidgetView()
                .onTapGesture {
                    if settings.settings.financeOpenOnClick {
                        Task {
                            try? await Task.sleep(for: .seconds(NotchConfiguration.primaryWidgetSwitchDelay))
                            navigationStack.wrappedValue.append(NotchWidgetMode.financePlayer)
                        }
                    }
                }
        case .shopify:
            ShopifyOrdersWidgetView()
        case .calendar:
            CalendarWidgetView(viewModel: calendarViewModel)
                .onTapGesture {
                    if settings.settings.calendarOpenOnClick {
                        Task {
                            try? await Task.sleep(for: .seconds(NotchConfiguration.primaryWidgetSwitchDelay))
                            navigationStack.wrappedValue.append(NotchWidgetMode.calendarPlayer)
                        }
                    }
                }
                .onHover { hovering in
                    self.isCalendarHovered.wrappedValue = hovering
                }
        case .shortcuts:
            ShortcutWidgetView()
        case .notes:
            NotesWidgetView()
                .onTapGesture {
                    if settings.settings.notesOpenOnClick {
                        Task {
                            try? await Task.sleep(for: .seconds(NotchConfiguration.primaryWidgetSwitchDelay))
                            navigationStack.wrappedValue.append(NotchWidgetMode.notesPlayer)
                        }
                    }
                }
        case .clipboard:
            ClipboardWidgetView()
                .onTapGesture {
                    if settings.settings.clipboardOpenOnClick {
                        Task {
                            try? await Task.sleep(for: .seconds(NotchConfiguration.primaryWidgetSwitchDelay))
                            navigationStack.wrappedValue.append(NotchWidgetMode.clipboardPlayer)
                        }
                    }
                }
        case .mirror:
            MirrorWidgetView()
        case .focusSession:
            FocusWidgetView()
        case .timer:
            TimerWidgetView()
        case .battery:
            BatteryWidgetView()
        case .storage:
            StorageWidgetView()
                .onTapGesture {
                    if settings.settings.storageOpenOnClick {
                        Task {
                            try? await Task.sleep(for: .seconds(NotchConfiguration.primaryWidgetSwitchDelay))
                            navigationStack.wrappedValue.append(NotchWidgetMode.storageDetailView)
                        }
                    }
                }
        case .dev:
            DevWidgetView()
                .onTapGesture {
                    Task {
                        try? await Task.sleep(for: .seconds(NotchConfiguration.primaryWidgetSwitchDelay))
                        navigationStack.wrappedValue.append(NotchWidgetMode.devDashboard)
                    }
                }
        case .agent:
            EmptyView()
        }
    }
}

private struct MusicWidgetVisibilitySnapshot: Equatable {
    let isPlaying: Bool
    let isSpotifyPausedWithNoOtherPlayback: Bool
    let isLoggedIntoSpotify: Bool
    let isSpotifyOnlySource: Bool
    let isSpotifyAppRunning: Bool

    @MainActor
    init(manager: MusicManager) {
        isPlaying = manager.isPlaying
        isSpotifyPausedWithNoOtherPlayback = manager.isSpotifyPausedWithNoSystemMediaPlaying
        isLoggedIntoSpotify = manager.spotifyPrivateAPI.isLoggedIn
        isSpotifyOnlySource = manager.isSpotifySourceSelected
            && manager.activeMediaSources.keys.allSatisfy { key in
                key == "com.spotify.client:spotify-live" || key.hasPrefix("com.spotify.client")
            }
        isSpotifyAppRunning = RunningApps.shared.isRunning("com.spotify.client")
    }
}

private struct FileActionPreviewContent: View {
    @Environment(\.navigationStack) private var navigationStack
    @EnvironmentObject private var fileShelfState: FileShelfState

    var body: some View {
        if let item = fileShelfState.selectedItemForPreview {
            FileActionView(item: item, onDismiss: {
                if navigationStack.wrappedValue.last == .fileActionPreview {
                    navigationStack.wrappedValue.removeLast()
                }
            })
        } else {
            FileShelfView()
        }
    }
}

struct NotchCornerRadiusKey: EnvironmentKey {
    static let defaultValue: CGFloat = 10.0
}

extension EnvironmentValues {
    var notchCornerRadius: CGFloat {
        get { self[NotchCornerRadiusKey.self] }
        set { self[NotchCornerRadiusKey.self] = newValue }
    }
}