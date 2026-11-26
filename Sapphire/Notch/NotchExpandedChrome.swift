//
//  NotchExpandedChrome.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-02
//

import SwiftUI
import AppKit

enum NotchExpandedChrome {
    struct Context {
        var config: ResolvedNotchConfiguration
        var mode: NotchWidgetMode
        var notchState: NotchController.NotchState
        var barWidth: CGFloat
        var fixedSpacer: Bool
        var showRightHUDOverlay: Bool
        var navigationStack: Binding<[NotchWidgetMode]>
        var isPinned: Binding<Bool>
        var iconsLeftWidth: Binding<CGFloat>
        var iconsRightWidth: Binding<CGFloat>
        var iconsIntrinsicWidth: CGFloat
        var islandBarItems: [NotchIslandBar.Item] = []
        var onPin: (Bool) -> Void
        var onOpenBlipHub: () -> Void
        var onOpenAgentS: () -> Void
    }

    static func showsHeader(for mode: NotchWidgetMode) -> Bool {
        mode == .defaultWidgets || ![.fileShelfLanding, .snapZones, .dragActivated].contains(mode)
    }

    static func key(_ context: Context) -> NotchContentKey {
        NotchContentKey(
            config: context.config,
            numbers: [context.fixedSpacer ? context.barWidth : 0, context.iconsIntrinsicWidth],
            flags: [context.fixedSpacer, context.showRightHUDOverlay],
            tags: [String(describing: context.mode), String(describing: context.notchState)]
                + context.islandBarItems.map { String(describing: $0) }
        )
    }

    static func pieces(_ context: Context) -> [NotchChromeSlot: NotchChromePiece] {
        var pieces = unkeyedPieces(context)
        let key = key(context)
        for slot in pieces.keys { pieces[slot]?.key = key }
        return pieces
    }

    private static func unkeyedPieces(_ context: Context) -> [NotchChromeSlot: NotchChromePiece] {
        let config = context.config
        if config.isFloatingIsland {
            guard NotchIslandBar.showsBar(for: context.mode), !context.islandBarItems.isEmpty else { return [:] }
            return [
                .islandBar: NotchChromePiece(
                    anchor: .center,
                    bottom: 0,
                    view: AnyView(NotchIslandBarView(items: context.islandBarItems, context: context))
                ),
            ]
        }
        if context.mode == .defaultWidgets {
            let top = config.widgetMenuTopInset
            let inset = config.defaultModeIconsHorizontalPadding
            if context.fixedSpacer {
                return [
                    .centerBar: NotchChromePiece(
                        anchor: .center,
                        top: top,
                        view: AnyView(NotchChromeFixedBar(context: context))
                    ),
                ]
            }
            return [
                .leadingIcons: NotchChromePiece(
                    anchor: .leading,
                    inset: inset,
                    top: top,
                    view: AnyView(NotchChromeIconGroup(side: .leading, context: context))
                ),
                .trailingIcons: NotchChromePiece(
                    anchor: .trailing,
                    inset: inset,
                    top: top,
                    view: AnyView(NotchChromeIconGroup(side: .trailing, context: context))
                ),
            ]
        }
        guard showsHeader(for: context.mode) else { return [:] }
        return [
            .header: NotchChromePiece(
                anchor: .leading,
                width: .outline,
                height: config.initialSize.height,
                view: AnyView(NotchChromeNavigationHeader(context: context))
            ),
        ]
    }

    static func title(for mode: NotchWidgetMode) -> String? {
        switch mode {
        case .multiAudioDeviceAdjust: return String(localized: "Adjust")
        case .multiAudioEQ: return String(localized: "EQ")
        case .earbudControls: return String(localized: "Earbuds")
        case .musicDevices: return String(localized: "Devices")
        case .musicQueueAndPlaylists: return String(localized: "Queue & Playlists")
        case .multiAudio: return String(localized: "Audio Devices")
        case .continuityDetail: return String(localized: "Phone")
        default: return nil
        }
    }

    static func split(_ buttons: [NotchButtonType]) -> (leading: [NotchButtonType], trailing: [NotchButtonType]) {
        guard let spacerIndex = buttons.firstIndex(of: .spacer) else { return (buttons, []) }
        return (
            Array(buttons.prefix(upTo: spacerIndex)),
            Array(buttons.suffix(from: buttons.index(after: spacerIndex)))
        )
    }
}

// MARK: - Pieces

struct NotchChromeIconGroup: View {
    enum Side { case leading, trailing }

    let side: Side
    let context: NotchExpandedChrome.Context

    @ObservedSettings private var settings: SettingsObserver
    @State private var isBlipHovered = false

    var body: some View {
        let buttons = NotchExpandedChrome.split(settings.settings.notchButtonOrder)
        let types = side == .leading ? buttons.leading : buttons.trailing
        let hasBlip = settings.settings.intelligenceEnabled && types.contains(.intelligence)
        let group = HStack(spacing: 0) {
            if hasBlip && side == .trailing { NotchBlipSlack(isHovered: isBlipHovered) }
            ForEach(types) { buttonType in
                NotchChromeButton(type: buttonType, context: context)
            }
            if hasBlip && side == .leading { NotchBlipSlack(isHovered: isBlipHovered) }
        }
        .fixedSize(horizontal: true, vertical: false)
        .environment(\.notchBlipHovered, $isBlipHovered)

        Group {
            switch side {
            case .leading:
                group.measureIdealWidth(into: context.iconsLeftWidth)
            case .trailing:
                group
                    .opacity(context.showRightHUDOverlay ? 0.0 : 1.0)
                    .animation(.easeInOut(duration: 0.12), value: context.showRightHUDOverlay)
                    .measureIdealWidth(into: context.iconsRightWidth)
            }
        }
        .frame(height: context.config.initialSize.height)
    }
}

struct NotchChromeFixedBar: View {
    let context: NotchExpandedChrome.Context

    @ObservedSettings private var settings: SettingsObserver

    private var spacerWidth: CGFloat {
        NotchBarSpacerPolicy.resolvedSpacerWidth(
            configuredWidth: settings.settings.notchBarSpacerWidth,
            barWidth: max(context.barWidth, context.iconsIntrinsicWidth),
            itemsWidth: context.iconsIntrinsicWidth,
            minimumSpacerWidth: context.config.barMinimumSpacerWidth
        )
    }

    private var halfWidth: CGFloat? {
        let half = max(context.iconsLeftWidth.wrappedValue, context.iconsRightWidth.wrappedValue)
        return half > 0 ? half : nil
    }

    var body: some View {
        HStack(spacing: spacerWidth) {
            NotchChromeIconGroup(side: .leading, context: context)
                .frame(width: halfWidth, alignment: .leading)
            NotchChromeIconGroup(side: .trailing, context: context)
                .frame(width: halfWidth, alignment: .trailing)
        }
        .padding(.horizontal, context.config.defaultModeIconsHorizontalPadding)
        .frame(height: context.config.initialSize.height)
    }
}

struct NotchChromeNavigationHeader: View {
    let context: NotchExpandedChrome.Context

    var body: some View {
        let config = context.config
        HStack {
            Button(action: {
                if NotchBackRouter.shared.handleBack() { return }
                if context.navigationStack.wrappedValue.count > 1 {
                    context.navigationStack.wrappedValue.removeLast()
                } else {
                    context.navigationStack.wrappedValue = [.defaultWidgets]
                }
            }) {
                NotchCapsuleBackButtonContent()
                    .padding(.leading, config.navHeaderLeadingPadding + 10)
            }
            .padding(.top, config.navHeaderTopPadding)
            .buttonStyle(.plain)

            NotchMediaSourceSwitcherSlot(
                mode: context.mode,
                topPadding: config.navHeaderTopPadding
            )

            if let title = NotchExpandedChrome.title(for: context.mode) {
                Text(title)
                    .font(.system(size: config.navHeaderTitleFontSize, weight: .bold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundColor(.white.opacity(0.9))
                    .padding(.top, config.navHeaderTitleTopPadding)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: config.initialSize.height)
    }
}

private struct NotchChromeButton: View {
    let type: NotchButtonType
    let context: NotchExpandedChrome.Context

    @ObservedSettings private var settings: SettingsObserver
    @ObservedObject private var caffeineManager = CaffeineManager.shared

    var body: some View {
        switch type {
        case .settings:
            SubtleIconButton(systemName: "gearshape", action: {
                (NSApp.delegate as? AppDelegate)?.openSettingsWindow()
            })
        case .fileShelf:
            if settings.settings.fileShelfIconEnabled {
                SubtleIconButton(systemName: "tray.full", action: { context.navigationStack.wrappedValue.append(.fileShelf) })
            }
        case .notes:
            if settings.settings.notesIconEnabled {
                SubtleIconButton(systemName: "note.text", action: { context.navigationStack.wrappedValue.append(.notesPlayer) })
            }
        case .clipboard:
            if settings.settings.clipboardIconEnabled {
                SubtleIconButton(systemName: "list.clipboard", action: { context.navigationStack.wrappedValue.append(.clipboardPlayer) })
            }
        case .intelligence:
            if settings.settings.intelligenceEnabled {
                NotchIntelligenceControls(
                    notchState: context.notchState,
                    onOpenBlipHub: context.onOpenBlipHub,
                    onOpenAgentS: context.onOpenAgentS
                )
            } else {
                EmptyView()
            }
        case .intelligenceLive:
            EmptyView()
        case .focusSession:
            if settings.settings.focusSessionIconEnabled {
                SubtleIconButton(
                    systemName: "moon.fill",
                    action: { context.navigationStack.wrappedValue.append(.focusSessionDetailView) }
                )
            }
        case .caffeine:
            if settings.settings.caffeinateEnabled {
                SubtleIconButton(systemName: caffeineManager.isActive ? "cup.and.heat.waves.fill" : "cup.and.heat.waves", action: { NotchCaffeinateHoldMenu.shared.toggleUnlessHeld(caffeineManager) }, horizontalPadding: 6)
                    .offset(y: -2)
                    .caffeinateMenu(caffeineManager)
            }
        case .battery:
            if settings.settings.batteryEstimatorEnabled {
                NotchBatteryInfoSlot()
            } else {
                EmptyView()
            }
        case .continuity:
            if settings.settings.continuityEnabled && settings.settings.continuityShowPhoneBattery {
                ContinuityPhoneStatusItem {
                    context.navigationStack.wrappedValue.append(.continuityDetail)
                }
            } else {
                EmptyView()
            }
        case .multiAudio:
            if settings.settings.showMultiAudioIcon {
                SubtleIconButton(systemName: "hifispeaker.and.homepod.mini.fill", action: { context.navigationStack.wrappedValue.append(.multiAudio) })
            }
        case .pin:
            if settings.settings.pinEnabled {
                SubtleIconButton(systemName: context.isPinned.wrappedValue ? "pin.fill" : "pin", action: {
                    context.isPinned.wrappedValue.toggle()
                    context.onPin(context.isPinned.wrappedValue)
                }, horizontalPadding: 6)
            }
        case .spacer:
            EmptyView()
        }
    }
}

struct NotchCaffeinateMenu: View {
    @ObservedObject var caffeineManager: CaffeineManager

    static let durations: [(label: String, minutes: Double)] = [
        ("15 Minutes", 15), ("30 Minutes", 30), ("1 Hour", 60), ("2 Hours", 120), ("4 Hours", 240), ("8 Hours", 480)
    ]

    var body: some View {
        if caffeineManager.isActive, let endsAt = caffeineManager.timeoutEndsAt {
            Text("Awake until \(endsAt.formatted(date: .omitted, time: .shortened))")
        }
        Section("Keep Awake For") {
            ForEach(Self.durations, id: \.minutes) { duration in
                Button(duration.label) { caffeineManager.start(forMinutes: duration.minutes) }
            }
            Button("Until Turned Off") { caffeineManager.startIndefinitely() }
        }
        if caffeineManager.isActive {
            Divider()
            Button("Turn Off") { caffeineManager.stop() }
        }
    }
}

extension View {
    /// Right-click or press-and-hold opens the one-off Keep Awake timer menu. Pair it with
    /// `NotchCaffeinateHoldMenu.toggleUnlessHeld` as the tap action so a hold doesn't also toggle.
    func caffeinateMenu(_ caffeineManager: CaffeineManager) -> some View {
        contextMenu { NotchCaffeinateMenu(caffeineManager: caffeineManager) }
            .simultaneousGesture(
                LongPressGesture(minimumDuration: NotchCaffeinateHoldMenu.holdDuration)
                    .onEnded { _ in NotchCaffeinateHoldMenu.shared.present(for: caffeineManager) }
            )
    }
}

/// SwiftUI's contextMenu only opens on right-click, so a hold pops an equivalent NSMenu while
/// the mouse is still down - releasing over an item picks it, like a classic held menu.
@MainActor
final class NotchCaffeinateHoldMenu: NSObject {
    static let shared = NotchCaffeinateHoldMenu()
    static let holdDuration: Double = 0.45

    private var suppressTap = false
    private var actions: [() -> Void] = []

    func toggleUnlessHeld(_ caffeineManager: CaffeineManager) {
        guard !suppressTap else { return }
        caffeineManager.toggle()
    }

    func present(for caffeineManager: CaffeineManager) {
        let menu = NSMenu()
        menu.autoenablesItems = false
        actions.removeAll()

        if caffeineManager.isActive, let endsAt = caffeineManager.timeoutEndsAt {
            let status = NSMenuItem(title: "Awake until \(endsAt.formatted(date: .omitted, time: .shortened))", action: nil, keyEquivalent: "")
            status.isEnabled = false
            menu.addItem(status)
        }
        menu.addItem(.sectionHeader(title: "Keep Awake For"))
        for duration in NotchCaffeinateMenu.durations {
            addItem(duration.label, to: menu) { caffeineManager.start(forMinutes: duration.minutes) }
        }
        addItem("Until Turned Off", to: menu) { caffeineManager.startIndefinitely() }
        if caffeineManager.isActive {
            menu.addItem(.separator())
            addItem("Turn Off", to: menu) { caffeineManager.stop() }
        }

        // The release that ends the hold can still reach the button after the menu closes.
        suppressTap = true
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.suppressTap = false
        }
    }

    private func addItem(_ title: String, to menu: NSMenu, action: @escaping () -> Void) {
        let item = NSMenuItem(title: title, action: #selector(runAction(_:)), keyEquivalent: "")
        item.target = self
        item.tag = actions.count
        actions.append(action)
        menu.addItem(item)
    }

    @objc private func runAction(_ sender: NSMenuItem) {
        guard actions.indices.contains(sender.tag) else { return }
        actions[sender.tag]()
    }
}

private struct NotchMediaSourceSwitcherSlot: View {
    private var musicManager: MusicManager { .shared }

    let mode: NotchWidgetMode
    let topPadding: CGFloat

    var body: some View {
        if mode == .musicPlayer, musicManager.activeMediaSources.count > 1 {
            NotchMediaSourceSwitcher()
                .padding(.top, topPadding)
                .padding(.leading, 6)
        }
    }
}

private struct NotchBatteryInfoSlot: View {
    @EnvironmentObject private var batteryEstimator: BatteryEstimator

    var body: some View {
        BatteryInfoView(
            level: batteryEstimator.batteryLevel,
            isCharging: batteryEstimator.isCharging,
            timeRemaining: batteryEstimator.estimatedTimeRemaining
        )
        .padding(.horizontal, NotchConfiguration.batteryHorizontalPadding)
    }
}

/// The Blip pill's expansion width, parked at the notch-side end of its icon group. It collapses
/// on the same spring the pill grows on, so the group's width never changes: items between the
/// pill and the notch slide over instead of the hosting view re-fitting and re-centering the bar,
/// which slid the pill out from under the cursor and looped hover on/off.
private struct NotchBlipSlack: View {
    @Environment(GeminiLiveManager.self) private var geminiLiveManager
    let isHovered: Bool

    var body: some View {
        Text(geminiLiveManager.isSessionRunning ? "Stop" : "Blip")
            .font(.system(size: NotchConfiguration.geminiButtonTextFontSize, weight: .semibold))
            .fixedSize()
            .padding(.trailing, NotchConfiguration.geminiButtonActiveHorizontalPadding)
            .hidden()
            .frame(width: isHovered ? 0 : nil)
            .allowsHitTesting(false)
    }
}

private struct NotchBlipHoveredKey: EnvironmentKey {
    static let defaultValue: Binding<Bool> = .constant(false)
}

private extension EnvironmentValues {
    var notchBlipHovered: Binding<Bool> {
        get { self[NotchBlipHoveredKey.self] }
        set { self[NotchBlipHoveredKey.self] = newValue }
    }
}

private struct NotchIntelligenceControls: View {
    @Environment(GeminiLiveManager.self) private var geminiLiveManager
    @ObservedObject private var microphoneManager = MicrophoneUsageManager.shared

    let notchState: NotchController.NotchState
    let onOpenBlipHub: () -> Void
    let onOpenAgentS: () -> Void

    @Environment(\.notchBlipHovered) private var isHoveredBinding
    private var isHovered: Bool { isHoveredBinding.wrappedValue }

    var body: some View {
        HStack(spacing: 8) {
            intelligenceButton
            if microphoneManager.isMicInUse && notchState == .clickExpanded {
                microphonePill
            }
        }
    }

    private var intelligenceButton: some View {
        let isLiveRunning = geminiLiveManager.isSessionRunning
        let baseSize = NotchConfiguration.geminiButtonBaseSize
        let activeFill = Color.purple.opacity(0.8)
        let stopFill = Color.red

        let title = isLiveRunning ? "Stop" : "Blip"
        let titleFont = Font.system(size: NotchConfiguration.geminiButtonTextFontSize, weight: .semibold)
        let trailingPadding = NotchConfiguration.geminiButtonActiveHorizontalPadding

        let button = Button {
            if isLiveRunning {
                geminiLiveManager.stopSession()
            } else {
                onOpenBlipHub()
            }
        } label: {
            HStack(spacing: 0) {
                Image(systemName: isLiveRunning ? "stop.fill" : "sparkle")
                    .font(.system(
                        size: isHovered
                            ? NotchConfiguration.geminiButtonActiveIconSize
                            : NotchConfiguration.geminiButtonInactiveIconSize,
                        weight: .medium
                    ))
                    .rotationEffect(.degrees(isHovered ? 90 : 0))
                    .foregroundStyle(isHovered ? Color.white : Color.purple)
                    .animation(
                        .spring(
                            response: NotchConfiguration.geminiButtonSpringResponse,
                            dampingFraction: NotchConfiguration.geminiButtonSpringDamping
                        ),
                        value: isHovered
                    )
                    .frame(width: baseSize, height: baseSize)

                // Always in the tree and revealed by width, so a hover flicker can't strand a
                // half-finished insertion/removal transition ("✦lip" ghosts).
                Text(title)
                    .font(titleFont)
                    .fixedSize()
                    .foregroundColor(.white)
                    .padding(.trailing, trailingPadding)
                    .opacity(isHovered ? 1 : 0)
                    .frame(width: isHovered ? nil : 0, alignment: .leading)
            }
            .frame(height: baseSize)
            .background(isHovered ? (isLiveRunning ? stopFill : activeFill) : nil)
            .clipShape(Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.spring(
                response: NotchConfiguration.geminiButtonSpringResponse,
                dampingFraction: 1
            )) {
                isHoveredBinding.wrappedValue = hovering
            }
        }
        .simultaneousGesture(TapGesture(count: 2).onEnded(onOpenAgentS))

        return button
    }

    @ViewBuilder
    private var microphonePill: some View {
        if microphoneManager.isMicInUse {
            Button {
                haptic()
                microphoneManager.toggleMute()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: microphoneManager.isMuted ? "mic.slash.fill" : "mic.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(microphoneManager.isMuted ? .white.opacity(0.85) : .red)
                    Text(microphoneManager.isMuted ? "Muted" : "Mic")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.black.opacity(0.25)))
            }
            .buttonStyle(.plain)
        }
    }
}

struct GeminiPickerBridge: View {
    @EnvironmentObject private var pickerHelper: ContentPickerHelper
    @Environment(GeminiLiveManager.self) private var geminiLiveManager
    @Environment(LiveActivityManager.self) private var liveActivityManager

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
            .onReceive(pickerHelper.pickerResultPublisher) { result in
                switch result {
                case .success(let filter):
                    geminiLiveManager.startSession(with: filter)
                    liveActivityManager.startGeminiLive()
                case .failure(let error):
                    if let error { print("Picker failed with error: \(error)") }
                    else { print("Picker was cancelled by the user.") }
                }
            }
    }
}

private struct ContinuityPhoneStatusItem: View {
    let action: () -> Void

    private var manager: ContinuityManager { .shared }

    private var snapshot: ContinuityConnectivitySnapshot { manager.connectivity }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: snapshot.hasDevice ? "iphone" : "iphone.slash")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(snapshot.severity.tint)

                Image(systemName: "cellularbars")
                    .font(.system(size: 10, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(snapshot.phoneSignalLevel > 0 ? Color.white.opacity(0.9) : Color.white.opacity(0.35))

                if let battery = snapshot.phoneBatteryPercent {
                    HStack(spacing: 2) {
                        Image(systemName: snapshot.phoneCharging ? "battery.100percent.bolt" : "battery.100percent")
                            .font(.system(size: 10, weight: .medium))
                        Text("\(battery)")
                            .font(.system(size: 9, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                    }
                    .foregroundStyle(battery <= 20 && !snapshot.phoneCharging ? Color.orange : Color.white.opacity(0.9))
                }
            }
            .padding(.horizontal, 6)
            .frame(height: 22)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(snapshot.deviceName.isEmpty ? String(localized: "Phone") : snapshot.deviceName)
    }
}
