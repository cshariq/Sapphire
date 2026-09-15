//
//  NotchActivityContentView.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-02

import SwiftUI
import AppKit

struct NotchActivitySplitLayout: Layout {
    let centerGap: CGFloat

    struct Measurements {
        var leading: CGSize = .zero
        var trailing: CGSize = .zero

        var half: CGFloat { max(leading.width, trailing.width) }
        var intrinsicHeight: CGFloat { max(leading.height, trailing.height) }
    }

    func makeCache(subviews: Subviews) -> Measurements { measure(subviews) }

    func updateCache(_ cache: inout Measurements, subviews: Subviews) {
        cache = measure(subviews)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Measurements) -> CGSize {
        CGSize(
            width: cache.half * 2 + centerGap,
            height: proposal.height ?? cache.intrinsicHeight
        )
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Measurements) {
        guard let leading = subviews.first else { return }
        leading.place(
            at: CGPoint(x: bounds.minX, y: bounds.midY),
            anchor: .leading,
            proposal: ProposedViewSize(cache.leading)
        )

        guard subviews.count > 1 else { return }
        subviews[subviews.count - 1].place(
            at: CGPoint(x: bounds.maxX, y: bounds.midY),
            anchor: .trailing,
            proposal: ProposedViewSize(cache.trailing)
        )
    }

    private func measure(_ subviews: Subviews) -> Measurements {
        var measurements = Measurements()
        guard let leading = subviews.first else { return measurements }
        measurements.leading = leading.sizeThatFits(.unspecified)
        guard subviews.count > 1 else { return measurements }
        measurements.trailing = subviews[subviews.count - 1].sizeThatFits(.unspecified)
        return measurements
    }
}

struct NotchActivityContentView: View {
    let content: LiveActivityContent
    let config: ResolvedNotchConfiguration
    let horizontalPadding: CGFloat
    let screen: NSScreen?
    @Binding var measuredSize: CGSize
    @Binding var showLyrics: Bool
    var blurRadius: CGFloat = 0

    @EnvironmentObject private var settings: SettingsModel
    @EnvironmentObject private var musicWidget: MusicManager
    @EnvironmentObject private var timerManager: TimerManager
    @EnvironmentObject private var geminiLiveManager: GeminiLiveManager
    @EnvironmentObject private var desktopManager: DesktopManager

    private var desktopNumber: Int {
        desktopManager.desktopNumber(for: screen) ?? 1
    }

    var body: some View {
        Group {
            switch content {
            case .full(let view, _, _):
                view
                    .padding(.horizontal, config.activityContentHorizontalPadding)
                    .blur(radius: blurRadius)
            case .standard(let data, _):
                standardActivityView(from: data)
                    .fixedSize()
            case .none:
                EmptyView()
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .measureIdealSize(
            into: $measuredSize,
            sizeIsProposalIndependent: content.layoutKind == .standard
        )
    }

    @ViewBuilder
    private func standardActivityView(from data: StandardActivityData) -> some View {
        let bottomIsUpNext: Bool = {
            if case .music(let bottom) = data, case .upNext = bottom { return true }
            return false
        }()
        VStack(alignment: bottomIsUpNext ? .leading : .center, spacing: 0) {
            let left = buildLeftView(for: data)
            let right = buildRightView(for: data)

            NotchActivitySplitLayout(centerGap: config.initialSize.width) {
                ZStack { left }
                    .blur(radius: blurRadius)
                ZStack { right }
                    .blur(radius: blurRadius)
            }
            .frame(height: config.initialSize.height)
            .padding(.horizontal, horizontalPadding)

            if let bottomView = getBottomView(for: data) {
                VStack {
                    bottomView
                        .padding(.bottom, config.activityContentBottomPadding)
                }
                .blur(radius: blurRadius)
                .padding(.horizontal, horizontalPadding)
            }
        }
    }

    // MARK: - Activity View Builders
    private func getBottomView(for data: StandardActivityData) -> AnyView? {
        switch data {
        case .music(let bottomContentType):
            switch bottomContentType {
            case .none:
                return nil
            case .peek(let title, let artist):
                return AnyView(QuickPeekView(title: title, artist: artist))
            case .lyrics(let line):
                let view = KaraokeLyricTicker(
                    lyric: line,
                    containerWidth: NotchConfiguration.lyricsMaxWidth,
                    font: .system(size: NotchConfiguration.lyricsFontSize, weight: .semibold, design: .rounded),
                    highlightColor: musicWidget.accentColor.opacity(0.9),
                    inactiveColor: musicWidget.accentColor
                )
                    .frame(maxWidth: NotchConfiguration.lyricsMaxWidth)
                    .transition(.opacity.animation(.easeInOut(duration: 0.3)))
                    .id("lyric-\(line.id.uuidString)")
                    .onTapGesture { showLyrics = true }
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
        case .weather(let data): WeatherActivityView.left(for: data)
        case .calendar: CalendarProximityActivityView.left()
        case .reminder: ReminderProximityActivityView.left()
        case .timer: TimerActivityView.left(timerManager: timerManager)
        case .battery(let state, let style, let timeRemaining, let systemState):
            switch style {
            case .persistent: PersistentBatteryActivityView.left(for: state, timeRemaining: timeRemaining, systemState: systemState)
            case .default: DefaultBatteryActivityView.left(for: state, systemState: systemState)
            case .compact: CompactBatteryActivityView.left(for: state, systemState: systemState)
            }
        case .desktop: DesktopActivityView.left(for: desktopNumber)
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
        case .nearDrop: NearDropCompactActivityView.left()
        case .hud(let type): SystemHUDSlimActivityView.left(type: type, settings: settings)
        case .lockScreen: LockScreenLiveActivityView.left()
        case .updateAvailable: UpdateAvailableActivityView.left()
        case .focusSession: FocusSessionActivityView.left()
        case .unlocked: LockScreenLiveActivityView.left()
        case .stats(let payload): statsLiveActivityView.left(for: payload, selectedStats: settings.settings.selectedStats, selectedSensorKeys: settings.settings.selectedSensorKeys)
        }
    }

    @ViewBuilder
    private func buildRightView(for data: StandardActivityData) -> some View {
        switch data {
        case .music: WaveformView()
        case .intelligenceAgent(let status, let stepTitle, let current, let total): IntelligenceAgentActivityView.right(status: status, stepTitle: stepTitle, current: current, total: total)
        case .devActivity(let task, let additionalCount): DevActivityLiveActivityView.right(for: task, additionalCount: additionalCount)
        case .weather(let data): WeatherActivityView.right(for: data)
        case .calendar(let event): CalendarProximityActivityView.right(event: event)
        case .reminder(let reminder): ReminderProximityActivityView.right(reminder: reminder)
        case .timer: TimerActivityView.right(timerManager: timerManager)
        case .battery(let state, let style, let timeRemaining, let systemState):
            switch style {
            case .persistent: PersistentBatteryActivityView.right(for: state, systemState: systemState)
            case .default: DefaultBatteryActivityView.right(for: state, timeRemaining: timeRemaining, systemState: systemState)
            case .compact: CompactBatteryActivityView.right(for: state)
            }
        case .desktop: DesktopActivityView.right(for: desktopNumber)
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
        case .geminiLive(let payload): GeminiActiveActivityView.right(isMuted: payload.isMicMuted) { geminiLiveManager.toggleMicrophone() }
        case .sports(let payload, _):
            SportsLiveActivityView.right(for: payload, preferLogo: settings.settings.sportsPreferLogo)
        case .finance(let payload):
            FinanceLiveActivityView.right(for: payload)
        case .microphone: MicrophoneLiveActivityView.right { MicrophoneUsageManager.shared.toggleMute() }
        case .nearDrop(let payload): NearDropCompactActivityView.right(payload: payload)
        case .hud(let type): SystemHUDSlimActivityView.right(type: type, settings: SettingsModel.shared)
        case .lockScreen: LockScreenLiveActivityView.right()
        case .updateAvailable(let version): UpdateAvailableActivityView.right(version: version)
        case .focusSession: FocusSessionActivityView.right()
        case .battery: EmptyView()
        case .unlocked: LockScreenLiveActivityView.right()
        case .stats(let payload): statsLiveActivityView.right(for: payload, selectedStats: settings.settings.selectedStats, selectedSensorKeys: settings.settings.selectedSensorKeys)
        }
    }
}