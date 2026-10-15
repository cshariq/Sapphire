//
//  NotchActivityContentView.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-02

import SwiftUI
import AppKit

struct NotchActivityContentView: View {
    let content: LiveActivityContent
    let config: ResolvedNotchConfiguration
    let horizontalPadding: CGFloat
    let screen: NSScreen?
    @Binding var measuredSize: CGSize
    @Binding var showLyrics: Bool
    var region: NotchActivityRegionSlot? = nil

    @ObservedSettings private var settings: SettingsObserver
    @Environment(\.notchRegionRowWidth) private var rowWidth
    @State private var reservedLyric: LyricLine?

    private var musicBottom: MusicBottomContentType? {
        guard case .standard(.music(let bottom), _) = content else { return nil }
        return bottom
    }

    var body: some View {
        if let region {
            regionBody(region)
        } else {
            wholeBody
        }
    }

    @ViewBuilder
    private func regionBody(_ region: NotchActivityRegionSlot) -> some View {
        Group {
            if case .standard(let data, _) = content {
                switch region {
                case .leading:
                    buildLeftView(for: data)
                case .trailing:
                    buildRightView(for: data)
                case .bottom:
                    if let bottom = getBottomView(for: data) {
                        bottom
                            .padding(.bottom, config.activityContentBottomPadding)
                            .padding(.horizontal, horizontalPadding)
                            .frame(width: rowWidth, alignment: .leading)
                    }
                }
            }
        }
        .fixedSize()
        .onChange(of: musicBottom, initial: true) { _, bottom in
            switch bottom {
            case .lyrics(let line): reservedLyric = line
            case .peek: break
            default: reservedLyric = nil
            }
        }
    }

    private var wholeBody: some View {
        Group {
            switch content {
            case .full(let view, _, _):
                view
                    .padding(.horizontal, config.activityContentHorizontalPadding)
            case .standard, .none:
                EmptyView()
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .measureIdealSize(
            into: $measuredSize,
            sizeIsProposalIndependent: content.layoutKind == .standard
        )
    }

    private func getBottomView(for data: StandardActivityData) -> AnyView? {
        switch data {
        case .music(let bottomContentType):
            switch bottomContentType {
            case .none:
                return nil
            case .peek(let title, let artist):
                guard let reservedLyric else {
                    return AnyView(QuickPeekView(title: title, artist: artist))
                }
                return AnyView(
                    ZStack {
                        MusicKaraokeActivityTicker(lyric: reservedLyric, config: config, showLyrics: $showLyrics)
                            .hidden()
                        QuickPeekView(title: title, artist: artist)
                    }
                )
            case .lyrics(let line):
                let view = MusicKaraokeActivityTicker(
                    lyric: line,
                    config: config,
                    showLyrics: $showLyrics
                )
                return AnyView(view)
            case .upNext(let title, let artist, let artworkURL):
                return AnyView(MusicUpNextView(title: title, artist: artist, artworkURL: artworkURL))
            }
        default:
            return nil
        }
    }

    @ViewBuilder
    private func buildLeftView(for data: StandardActivityData) -> some View {
        switch data {
        case .music: AlbumArtView()
        case .intelligenceAgent: IntelligenceAgentActivityView.left()
        case .devActivity(let task, _): DevActivityLiveActivityView.left(for: task)
        case .appActivity(let activity, _): AppActivityLiveActivityView.left(for: activity)
        case .weather(let data): WeatherActivityView.left(for: data)
        case .calendar: CalendarProximityActivityView.left()
        case .reminder: ReminderProximityActivityView.left()
        case .timer: TimerActivityLeftView()
        case .battery(let state, let style, let timeRemaining, let systemState):
            switch style {
            case .persistent: PersistentBatteryActivityView.left(for: state, timeRemaining: timeRemaining, systemState: systemState)
            case .default: DefaultBatteryActivityView.left(for: state, systemState: systemState)
            case .compact: CompactBatteryActivityView.left(for: state, systemState: systemState)
            }
        case .desktop: DesktopActivityLeftView(screen: screen)
        case .focus(let mode): FocusModeActivityView.left(for: mode)
        case .fileShelf: FileShelfActivityView.left()
        case .fileProgress(let task): FileProgressLiveActivityView.left(for: task)
        case .bluetooth(let device):
            switch device.eventType {
            case .connected:
                if device.isContinuityDevice { BluetoothConnectedContinuityView.left(for: device) }
                else { BluetoothConnectedPeripheralView.left(for: device) }
            case .disconnected: BluetoothDisconnectedView.left(for: device)
            case .batteryLow: BluetoothBatteryLowView.left(for: device)
            }
        case .audioSwitch(let event): AudioSwitchActivityView.left(for: event)
        case .continuity(let snapshot): ContinuityNotchActivityView.left(for: snapshot)
        case .continuityExternal(let activity): ContinuityExternalActivityView.left(for: activity)
        case .continuityMedia(let state, let artwork, _): ContinuityMediaActivityView.left(state: state, artwork: artwork)
        case .geminiLive: GeminiActiveActivityView.left()
        case .sports(let payload, _): SportsLiveActivityView.left(for: payload, preferLogo: settings.settings.sportsPreferLogo)
        case .finance(let payload): FinanceLiveActivityView.left(for: payload)
        case .microphone:
            MicrophoneLiveActivityView.left { MicrophoneUsageManager.shared.toggleMute() }
        case .nearbyTransfer: NearbyTransferCompactActivityView.left()
        case .hud(let type): SystemHUDSlimActivityView.left(type: type, settings: settings)
        case .lockScreen: LockScreenLiveActivityView.left()
        case .capsLock: CapsLockLiveActivityView.left()
        case .updateAvailable: UpdateAvailableActivityView.left()
        case .focusSession: FocusSessionActivityView.left()
        case .unlocked: LockScreenLiveActivityView.left()
        case .stats(let payload): statsLiveActivityView.left(for: payload, selectedStats: settings.settings.selectedStats, selectedSensorKeys: settings.settings.selectedSensorKeys)
        }
    }

    @ViewBuilder
    private func buildRightView(for data: StandardActivityData) -> some View {
        switch data {
        case .music: MusicLiveActivityRightView()
        case .intelligenceAgent(let status, let stepTitle, let current, let total): IntelligenceAgentActivityView.right(status: status, stepTitle: stepTitle, current: current, total: total)
        case .devActivity(let task, let additionalCount): DevActivityLiveActivityView.right(for: task, additionalCount: additionalCount)
        case .appActivity(let activity, let additionalCount): AppActivityLiveActivityView.right(for: activity, additionalCount: additionalCount)
        case .weather(let data): WeatherActivityView.right(for: data)
        case .calendar(let event): CalendarProximityActivityView.right(event: event)
        case .reminder(let reminder): ReminderProximityActivityView.right(reminder: reminder)
        case .timer: TimerActivityRightView()
        case .battery(let state, let style, let timeRemaining, let systemState):
            switch style {
            case .persistent: PersistentBatteryActivityView.right(for: state, systemState: systemState)
            case .default: DefaultBatteryActivityView.right(for: state, timeRemaining: timeRemaining, systemState: systemState)
            case .compact: CompactBatteryActivityView.right(for: state)
            }
        case .desktop: DesktopActivityRightView(screen: screen)
        case .focus(let mode): FocusModeActivityView.right(for: mode, displayMode: settings.settings.focusDisplayMode)
        case .fileShelf(let count): FileShelfActivityView.right(count: count)
        case .fileProgress(let task): FileProgressLiveActivityView.right(for: task)
        case .bluetooth(let device):
            switch device.eventType {
            case .connected:
                if device.isContinuityDevice { BluetoothConnectedContinuityView.right(for: device) }
                else { BluetoothConnectedPeripheralView.right(for: device) }
            case .disconnected: BluetoothDisconnectedView.right(for: device)
            case .batteryLow: BluetoothBatteryLowView.right(for: device)
            }
        case .audioSwitch(let event): AudioSwitchActivityView.right(for: event)
        case .continuity(let snapshot): ContinuityNotchActivityView.right(for: snapshot)
        case .continuityExternal(let activity): ContinuityExternalActivityView.right(for: activity)
        case .continuityMedia(let state, _, let device): ContinuityMediaActivityView.right(state: state, deviceName: device)
        case .geminiLive(let payload): GeminiActivityRightView(payload: payload)
        case .sports(let payload, _):
            SportsLiveActivityView.right(for: payload, preferLogo: settings.settings.sportsPreferLogo)
        case .finance(let payload):
            FinanceLiveActivityView.right(for: payload)
        case .microphone: MicrophoneLiveActivityView.right { MicrophoneUsageManager.shared.toggleMute() }
        case .nearbyTransfer(let payload): NearbyTransferCompactActivityView.right(payload: payload)
        case .hud(let type): SystemHUDSlimActivityView.right(type: type, settings: settings)
        case .lockScreen: LockScreenLiveActivityView.right()
        case .capsLock: CapsLockLiveActivityView.right()
        case .updateAvailable(let version): UpdateAvailableActivityView.right(version: version)
        case .focusSession: FocusSessionActivityView.right()
        case .unlocked: LockScreenLiveActivityView.right()
        case .stats(let payload): statsLiveActivityView.right(for: payload, selectedStats: settings.settings.selectedStats, selectedSensorKeys: settings.settings.selectedSensorKeys)
        }
    }
}

private struct DesktopActivityLeftView: View {
    @EnvironmentObject private var desktopManager: DesktopManager

    let screen: NSScreen?

    var body: some View {
        DesktopActivityView.left(for: desktopManager.desktopNumber(for: screen) ?? 1)
    }
}

private struct DesktopActivityRightView: View {
    @EnvironmentObject private var desktopManager: DesktopManager

    let screen: NSScreen?

    var body: some View {
        DesktopActivityView.right(for: desktopManager.desktopNumber(for: screen) ?? 1)
    }
}

private struct MusicKaraokeActivityTicker: View {
    private var musicManager: MusicManager { .shared }

    let lyric: LyricLine
    let config: ResolvedNotchConfiguration
    @Binding var showLyrics: Bool

    var body: some View {
        KaraokeLyricTicker(
            lyric: lyric,
            containerWidth: config.lyricsMaxWidth,
            fontSize: config.lyricsFontSize,
            highlightColor: musicManager.accentColor.opacity(0.9),
            inactiveColor: musicManager.accentColor
        )
        .frame(maxWidth: config.lyricsMaxWidth)
        .onTapGesture { showLyrics = true }
    }
}

private struct GeminiActivityRightView: View {
    @Environment(GeminiLiveManager.self) private var geminiLiveManager

    let payload: GeminiPayload

    var body: some View {
        GeminiActiveActivityView.right(isMuted: payload.isMicMuted) {
            geminiLiveManager.toggleMicrophone()
        }
    }
}

private struct TimerActivityLeftView: View {
    @EnvironmentObject private var timerManager: TimerManager

    var body: some View {
        TimerActivityView.left(timerManager: timerManager)
    }
}

private struct TimerActivityRightView: View {
    @EnvironmentObject private var timerManager: TimerManager

    var body: some View {
        TimerActivityView.right(timerManager: timerManager)
    }
}