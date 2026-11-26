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
        visibility: MusicWidgetVisibility,
        isPlaying: Bool,
        hasTrack: Bool,
        isClosedSpotifyOnlySource: Bool
    ) -> Bool {
        guard isEnabled else { return false }
        switch visibility {
        case .always:
            return true
        case .whenSongLoaded:
            return isPlaying || (hasTrack && !isClosedSpotifyOnlySource)
        case .whilePlaying:
            return isPlaying
        }
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
    @Environment(\.notchWidgetRowWidthLimit) private var rowWidthLimit
    @Environment(\.notchIsFloatingIsland) private var isFloatingIsland
    @Environment(\.isCalendarHovered) private var isCalendarHovered
    @ObservedSettings private var settings: SettingsObserver
    @State private var musicVisibility: MusicWidgetVisibilitySnapshot
    @State private var keepsMusicWidgetUntilClosed = false

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
                return showsMusicWidget || (keepsMusicWidgetUntilClosed && settings.settings.musicWidgetEnabled)
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

        let singleIslandRow = isFloatingIsland && rowWidthLimit <= 0
        return WidgetLayoutPolicy.fittingWidgets(
            from: enabled,
            availableWidth: singleIslandRow
                ? WidgetLayoutPolicy.islandSingleRowWidth(notchDisplayWidth: notchDisplayWidth)
                : WidgetLayoutPolicy.availableBarWidth(notchDisplayWidth: notchDisplayWidth),
            showDividers: settings.settings.showDividersBetweenWidgets,
            bypassSpaceLimit: settings.settings.bypassWidgetSpaceLimit,
            countsMusic: singleIslandRow
        )
    }

    private var showsMusicWidget: Bool {
        MusicWidgetVisibilityPolicy.shouldShow(
            isEnabled: settings.settings.musicWidgetEnabled,
            visibility: settings.settings.musicWidgetVisibility,
            isPlaying: musicVisibility.isPlaying,
            hasTrack: musicVisibility.hasTrack,
            isClosedSpotifyOnlySource: musicVisibility.isClosedSpotifyOnlySource
        )
    }

    var body: some View {
        let showDividers = settings.settings.showDividersBetweenWidgets
        let ordered = enabledAndOrderedWidgets
        let rows = WidgetLayoutPolicy.rows(for: ordered, maxRowWidth: rowWidthLimit, showDividers: showDividers)
        let extraPadding = isFloatingIsland && rows.count == 1
            ? WidgetLayoutPolicy.islandSingleRowExtraPadding(for: ordered, showDividers: showDividers)
            : 0
        VStack(spacing: WidgetLayoutPolicy.rowSpacing) {
            ForEach(Array(rows.enumerated()), id: \.element) { index, widgets in
                HStack(spacing: WidgetLayoutPolicy.interWidgetSpacing) {
                    ForEach(widgets) { widgetType in
                        widgetView(for: widgetType)
                            .id(widgetType)

                        if widgetType != widgets.last && showDividers {
                            Divider()
                                .frame(height: 60)
                                .background(Color.white.opacity(0.3))
                        }
                    }
                }
                .padding(rowTrim(widgets, isFirst: index == 0, isLast: index == rows.count - 1))
            }
        }
        .padding(extraPadding)
        .onAppear {
            // The view stays alive between openings; each opening starts from the hide rules again.
            keepsMusicWidgetUntilClosed = false
            musicVisibility = MusicWidgetVisibilitySnapshot(manager: musicWidget)
        }
        .onReceive(Self.musicVisibilityChanges, perform: applyMusicVisibility)
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

    /// On the island the card's margins should look equal on all four sides, so padding that the widgets at a
    /// row's ends carry inside their own frames is taken back out.
    private func rowTrim(_ widgets: [WidgetType], isFirst: Bool, isLast: Bool) -> EdgeInsets {
        guard isFloatingIsland, let first = widgets.first, let last = widgets.last else { return EdgeInsets() }
        let vertical = WidgetLayoutPolicy.rowVerticalSlack(for: widgets)
        return EdgeInsets(
            top: isFirst ? -vertical : 0,
            leading: -WidgetLayoutPolicy.builtInSidePadding(for: first),
            bottom: isLast ? -vertical : 0,
            trailing: -WidgetLayoutPolicy.builtInSidePadding(for: last)
        )
    }

    private static let musicVisibilityChanges = observationPublisher {
        MainActor.assumeIsolated { MusicWidgetVisibilitySnapshot(manager: .shared) }
    }
    .removeDuplicates()

    private func refreshMusicVisibility() {
        applyMusicVisibility(MusicWidgetVisibilitySnapshot(manager: musicWidget))
    }

    private func applyMusicVisibility(_ snapshot: MusicWidgetVisibilitySnapshot) {
        guard snapshot != musicVisibility else { return }
        // Pausing from the open notch shouldn't pull the widget out from under the pointer.
        if showsMusicWidget { keepsMusicWidgetUntilClosed = true }
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
    let hasTrack: Bool
    /// A logged-in Spotify account keeps reporting the last track after the app quits.
    let isClosedSpotifyOnlySource: Bool

    @MainActor
    init(manager: MusicManager) {
        isPlaying = manager.isPlaying
        hasTrack = !(manager.title ?? "").isEmpty
        isClosedSpotifyOnlySource = manager.spotifyPrivateAPI.isLoggedIn
            && manager.isSpotifySourceSelected
            && manager.activeMediaSources.keys.allSatisfy { $0.hasPrefix("com.spotify.client") }
            && !RunningApps.shared.isRunning("com.spotify.client")
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