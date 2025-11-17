//
//  NotchWidgetView.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-11-16

import SwiftUI

private struct NavigationStackKey: EnvironmentKey {
    static let defaultValue: Binding<[NotchWidgetMode]> = .constant([.defaultWidgets])
}
private struct ActiveDropZoneKey: EnvironmentKey {
    static let defaultValue: Binding<DropZone?> = .constant(nil)
}
private struct IsFileDropTargetedKey: EnvironmentKey {
    static let defaultValue: Binding<Bool> = .constant(false)
}

private struct OnSnapDragEndKey: EnvironmentKey {
    static let defaultValue: () -> Void = {}
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
    var isFileDropTargeted: Binding<Bool> {
        get { self[IsFileDropTargetedKey.self] }
        set { self[IsFileDropTargetedKey.self] = newValue }
    }

    var onSnapDragEnd: () -> Void {
        get { self[OnSnapDragEndKey.self] }
        set { self[OnSnapDragEndKey.self] = newValue }
    }
    var isCalendarHovered: Binding<Bool> {
        get { self[IsCalendarHoveredKey.self] }
        set { self[IsCalendarHoveredKey.self] = newValue }
    }
}

struct NotchWidgetView: View {
    @Environment(\.navigationStack) var navigationStack
    @Environment(\.activeDropZone) var activeDropZone
    @Environment(\.isFileDropTargeted) var isFileDropTargeted
    @Environment(\.isCalendarHovered) var isCalendarHovered
    @Environment(\.onSnapDragEnd) var onSnapDragEnd

    private let musicWidgetView: MusicWidgetView
    private let weatherWidgetView: WeatherWidgetView
    private let calendarWidgetView: CalendarWidgetView
    private let shortcutWidgetView: ShortcutWidgetView

    @EnvironmentObject var settings: SettingsModel
    @EnvironmentObject private var fileShelfState: FileShelfState
    @EnvironmentObject var musicWidget: MusicManager
    @EnvironmentObject private var calendarService: CalendarService

    @Environment(\.notchCornerRadius) private var cornerRadius

    @StateObject private var dragState = DragStateManager.shared

    private var currentMode: NotchWidgetMode {
        navigationStack.wrappedValue.last ?? .defaultWidgets
    }
    @State private var displayedMode: NotchWidgetMode = .defaultWidgets

    @State private var blurRadius: CGFloat = 20

    @State private var isScaledIn: Bool = false
    @State private var isFadedIn: Bool = false
    @State private var isPositioned: Bool = false

    init(navigationStack: Binding<[NotchWidgetMode]>, activeDropZone: Binding<DropZone?>, isFileDropTargeted: Binding<Bool>, calendarViewModel: InteractiveCalendarViewModel) {
        self.musicWidgetView = MusicWidgetView()
        self.weatherWidgetView = WeatherWidgetView()
        self.calendarWidgetView = CalendarWidgetView(viewModel: calendarViewModel)
        self.shortcutWidgetView = ShortcutWidgetView()
    }

    private var enabledAndOrderedWidgets: [WidgetType] {
        let orderedTypes = settings.settings.widgetOrder

        return orderedTypes.filter { widgetType in
            switch widgetType {
            case .music:
                return settings.settings.musicWidgetEnabled && (!settings.settings.hideMusicWidgetWhenNotPlaying || (musicWidget.title != nil && !musicWidget.title!.isEmpty))
            case .weather:
                return settings.settings.weatherWidgetEnabled
            case .calendar:
                return settings.settings.calendarWidgetEnabled
            case .shortcuts:
                return settings.settings.shortcutsWidgetEnabled
            }
        }
    }

    var body: some View {
        ZStack {
            contentSwitch(for: displayedMode)
                .id(displayedMode)
                .blur(radius: blurRadius)
                .scaleEffect(isScaledIn ? 1.0 : 0.7, anchor: .top)
                .opacity(isFadedIn ? 1.0 : 0.0)
                .offset(y: isPositioned ? 0 : -50)
        }
        .onAppear {
            self.displayedMode = self.currentMode
            let animation: Animation
            if self.currentMode == .defaultWidgets {
                animation = .interpolatingSpring(stiffness: 230, damping: 22)
            } else {
                animation = .interpolatingSpring(stiffness: 220, damping: 18)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(animation) {
                    self.isScaledIn = true
                    self.isPositioned = true
                    self.isFadedIn = true
                }

                withAnimation(.easeOut(duration: 0.6)) {
                    self.blurRadius = 0
                }
            }
        }
        .onChange(of: currentMode) {
            withAnimation(.easeIn(duration: 0.2)) {
                self.isFadedIn = false
                self.blurRadius = 20
            }

            self.displayedMode = self.currentMode
            self.isScaledIn = false
            self.isPositioned = false

            let animation: Animation
            if self.currentMode == .defaultWidgets {
                animation = .interpolatingSpring(stiffness: 220, damping: 22)
            } else {
                animation = .interpolatingSpring(stiffness: 220, damping: 20)
            }

            withAnimation(animation) {
                self.isScaledIn = true
                self.isPositioned = true
                self.isFadedIn = true
            }

            withAnimation(.easeOut(duration: 0.6)) {
                self.blurRadius = 0
            }
        }
        .notchHorizontalPadding(cornerRadius: cornerRadius)
    }

    @ViewBuilder
    private func contentSwitch(for mode: NotchWidgetMode) -> some View {
        switch mode {
        case .defaultWidgets:
            HStack(spacing: 20) {
                ForEach(enabledAndOrderedWidgets) { widgetType in
                    widgetView(for: widgetType)
                        .id(widgetType)

                    if widgetType != enabledAndOrderedWidgets.last && settings.settings.showDividersBetweenWidgets {
                        Divider()
                            .frame(height: 60)
                            .background(Color.white.opacity(0.3))
                    }
                }
            }
        case .musicApiKeysMissing:
            ApiKeysMissingView(navigationStack: navigationStack)
        case .geminiApiKeysMissing:
            GeminiApiKeysMissingView(navigationStack: navigationStack)
        case .musicPlayer:
            MusicPlayerView(navigationStack: navigationStack)
        case .musicLoginPrompt:
            LoginPromptView(navigationStack: navigationStack)
        case .musicQueueAndPlaylists:
            QueueAndPlaylistsView(navigationStack: navigationStack)
        case .musicDevices:
            DevicesView(navigationStack: navigationStack)
        case .musicLyrics:
            LyricsView()
        case .musicPlaylistDetail(let playlist):
            PlaylistView(playlist: playlist)
        case .nearDrop:
            FileTaskView(navigationStack: navigationStack)
        case .weatherPlayer:
            WeatherPlayerView()
        case .calendarPlayer:
            CalendarDetailView()
        case .timerDetailView:
            TimerDetailView(navigationStack: navigationStack)
        case .snapZones:
            SnapZonesWidgetView(onDragEnd: onSnapDragEnd)
        case .fileShelf:
            FileShelfView()
        case .fileShelfLanding:
            FileDragLandingView(
                mode: dragState.isDraggingFromShelf ? .existingFile : .newFile,
                activeZone: activeDropZone
            )
        case .fileActionPreview:
            if let item = fileShelfState.selectedItemForPreview {
                FileActionView(item: item, onDismiss: {
                    if navigationStack.wrappedValue.last == .fileActionPreview {
                        navigationStack.wrappedValue.removeLast()
                    }
                })
            } else {
                FileShelfView()
            }
        case .multiAudio:
            MultiAudioView(navigationStack: navigationStack)
        case .multiAudioDeviceAdjust(let device):
            DeviceAdjustView(device: device)
        case .multiAudioEQ(let device):
            DeviceEQView(device: device)
        case .dragActivated:
            Color.clear
                .frame(width: 300, height: 200)
                .onDrop(of: [.fileURL], isTargeted: isFileDropTargeted) { _ in return false }
        }
    }

    @ViewBuilder
    private func widgetView(for widgetType: WidgetType) -> some View {
        switch widgetType {
        case .music:
            musicWidgetView
                .onTapGesture {
                    if settings.settings.musicOpenOnClick {
                        Task {
                            try? await Task.sleep(for: .seconds(NotchConfiguration.primaryWidgetSwitchDelay))
                            navigationStack.wrappedValue.append(NotchWidgetMode.musicPlayer)
                        }
                    }
                }
        case .weather:
            weatherWidgetView
                .onTapGesture {
                    if settings.settings.weatherOpenOnClick {
                        Task {
                            try? await Task.sleep(for: .seconds(NotchConfiguration.primaryWidgetSwitchDelay))
                            navigationStack.wrappedValue.append(NotchWidgetMode.weatherPlayer)
                        }
                    }
                }
        case .calendar:
            calendarWidgetView
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
            shortcutWidgetView
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