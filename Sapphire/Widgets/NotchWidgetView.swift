//
//  NotchWidgetView.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-06-26.
//
//
//
//
//

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
}

struct NotchWidgetView: View {
    @Environment(\.navigationStack) var navigationStack
    @Environment(\.activeDropZone) var activeDropZone
    @Environment(\.isFileDropTargeted) var isFileDropTargeted

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

    init(navigationStack: Binding<[NotchWidgetMode]>, activeDropZone: Binding<DropZone?>, isFileDropTargeted: Binding<Bool>, calendarViewModel: InteractiveCalendarViewModel) {
        self.musicWidgetView = MusicWidgetView()
        self.weatherWidgetView = WeatherWidgetView()
        self.calendarWidgetView = CalendarWidgetView(viewModel: calendarViewModel)
        self.shortcutWidgetView = ShortcutWidgetView()

    }

    private var currentMode: NotchWidgetMode {
        navigationStack.wrappedValue.last ?? .defaultWidgets
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
            contentSwitch
                .animation(.spring(response: 0.4, dampingFraction: 0.85), value: currentMode)
        }
        .padding(.top, NotchConfiguration.universalHeight - 10)
        .notchHorizontalPadding(cornerRadius: cornerRadius)
    }

    @ViewBuilder
    private var contentSwitch: some View {
        switch currentMode {
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
                .transition(.asymmetric(insertion: .scale(scale: 0.9).combined(with: .opacity), removal: .scale(scale: 0.9).combined(with: .opacity)))
        case .geminiApiKeysMissing:
            GeminiApiKeysMissingView(navigationStack: navigationStack)
                .transition(.asymmetric(insertion: .scale(scale: 0.9).combined(with: .opacity), removal: .scale(scale: 0.9).combined(with: .opacity)))
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
            SnapZonesWidgetView(onDragEnd: {})
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
                            navigationStack.wrappedValue.append(.musicPlayer)
                        }
                    }
                }
        case .weather:
            weatherWidgetView
                .onTapGesture {
                    if settings.settings.weatherOpenOnClick {
                        Task {
                            try? await Task.sleep(for: .seconds(NotchConfiguration.primaryWidgetSwitchDelay))
                            navigationStack.wrappedValue.append(.weatherPlayer)
                        }
                    }
                }
        case .calendar:
            calendarWidgetView
                .onTapGesture {
                    if settings.settings.calendarOpenOnClick {
                        Task {
                            try? await Task.sleep(for: .seconds(NotchConfiguration.primaryWidgetSwitchDelay))
                            navigationStack.wrappedValue.append(.calendarPlayer)
                        }
                    }
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