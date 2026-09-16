//
//  NotchExpandedChrome.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-02

import SwiftUI
import AppKit

struct NotchExpandedChrome: View {
    let config: ResolvedNotchConfiguration
    let mode: NotchWidgetMode
    let notchState: NotchController.NotchState
    let animatedWidth: CGFloat
    let showRightHUDOverlay: Bool
    @Binding var navigationStack: [NotchWidgetMode]
    @Binding var isPinned: Bool
    @Binding var iconsLeftWidth: CGFloat
    @Binding var iconsRightWidth: CGFloat
    let iconsIntrinsicWidth: CGFloat
    let onPin: (Bool) -> Void
    let onOpenBlipHub: () -> Void
    let onOpenAgentS: () -> Void

    @EnvironmentObject private var settings: SettingsModel
    @EnvironmentObject private var musicWidget: MusicManager
    @EnvironmentObject private var geminiLiveManager: GeminiLiveManager
    @EnvironmentObject private var batteryEstimator: BatteryEstimator
    @ObservedObject private var microphoneManager = MicrophoneUsageManager.shared
    @ObservedObject private var caffeineManager = CaffeineManager.shared

    @State private var isGeminiHovered = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if mode == .defaultWidgets {
                defaultModeIcons
            } else if ![.fileShelfLanding, .snapZones, .dragActivated].contains(mode) {
                navigationHeader
            }
        }
    }

    private var currentViewTitle: String? {
        switch mode {
        case .multiAudioDeviceAdjust: return "Adjust"
        case .multiAudioEQ: return "EQ"
        case .musicDevices: return "Devices"
        case .musicQueueAndPlaylists: return "Queue & Playlists"
        case .multiAudio: return "Audio Devices"
        default: return nil
        }
    }

    private var leftNotchButtons: [NotchButtonType] {
        let allButtons = settings.settings.notchButtonOrder
        if let spacerIndex = allButtons.firstIndex(of: .spacer) {
            return Array(allButtons.prefix(upTo: spacerIndex))
        }
        return allButtons
    }

    private var rightNotchButtons: [NotchButtonType] {
        let allButtons = settings.settings.notchButtonOrder
        if let spacerIndex = allButtons.firstIndex(of: .spacer) {
            return Array(allButtons.suffix(from: allButtons.index(after: spacerIndex)))
        }
        return []
    }

    @ViewBuilder
    private var navigationHeader: some View {
        ZStack {
            HStack {
                Button(action: {
                    if NotchBackRouter.shared.handleBack() { return }
                    if navigationStack.count > 1 {
                        navigationStack.removeLast()
                    } else {
                        navigationStack = [.defaultWidgets]
                    }
                }) {
                    NotchCapsuleBackButtonContent()
                        .padding(.leading, config.navHeaderLeadingPadding + 10)
                }
                .padding(.top, config.navHeaderTopPadding)
                .buttonStyle(.plain)

                if mode == .musicPlayer, musicWidget.activeMediaSources.count > 1 {
                    NotchMediaSourceSwitcher()
                        .environmentObject(musicWidget)
                        .padding(.top, config.navHeaderTopPadding)
                        .padding(.leading, 6)
                }

                if let title = currentViewTitle {
                    Text(title)
                        .font(.system(size: config.navHeaderTitleFontSize, weight: .bold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundColor(.white.opacity(0.9))
                        .padding(.top, config.navHeaderTitleTopPadding)
                }
                Spacer()
            }
        }
        .frame(height: config.initialSize.height)
        .frame(width: animatedWidth)
    }

    @ViewBuilder
    private var defaultModeIcons: some View {
        HStack {
            HStack(spacing: 0) {
                ForEach(leftNotchButtons) { buttonType in
                    notchButton(for: buttonType)
                }
            }
            .fixedSize(horizontal: true, vertical: false)
            .measureIdealWidth(into: $iconsLeftWidth)

            Spacer()

            HStack(spacing: 0) {
                ForEach(rightNotchButtons) { buttonType in
                    notchButton(for: buttonType)
                }
            }
            .opacity(showRightHUDOverlay ? 0.0 : 1.0)
            .animation(.easeInOut(duration: 0.12), value: showRightHUDOverlay)
            .fixedSize(horizontal: true, vertical: false)
            .measureIdealWidth(into: $iconsRightWidth)
        }
        .padding(.horizontal, config.defaultModeIconsHorizontalPadding)
        .frame(height: config.initialSize.height)
        .frame(width: max(animatedWidth, iconsIntrinsicWidth))
    }

    @ViewBuilder
    private var intelligenceButton: some View {
        let isLiveRunning = geminiLiveManager.isSessionRunning
        let baseSize: CGFloat = NotchConfiguration.geminiButtonBaseSize
        let activeGradient = LinearGradient(
            gradient: Gradient(colors: [Color.purple.opacity(0.8), Color.indigo.opacity(0.6)]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        let stopGradient = LinearGradient(
            gradient: Gradient(colors: [Color.orange.opacity(0.8), Color.red.opacity(1)]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        Button(action: {
            if isLiveRunning {
                geminiLiveManager.stopSession()
            } else {
                onOpenBlipHub()
            }
        }) {
            HStack(spacing: 4) {
                Image(systemName: isLiveRunning ? "stop.fill" : "sparkle")
                    .font(.system(
                        size: isGeminiHovered
                            ? NotchConfiguration.geminiButtonActiveIconSize
                            : NotchConfiguration.geminiButtonInactiveIconSize,
                        weight: .medium
                    ))
                    .rotationEffect(.degrees(isGeminiHovered ? 90 : 0))
                    .foregroundStyle(
                        isGeminiHovered
                            ? LinearGradient(
                                gradient: Gradient(colors: [.white, .white.opacity(0.5)]),
                                startPoint: .topLeading, endPoint: .bottomTrailing
                              )
                            : LinearGradient(
                                gradient: Gradient(colors: [Color.purple, Color.indigo]),
                                startPoint: .topLeading, endPoint: .bottomTrailing
                              )
                    )
                    .animation(
                        .spring(
                            response: NotchConfiguration.geminiButtonSpringResponse,
                            dampingFraction: NotchConfiguration.geminiButtonSpringDamping
                        ),
                        value: isGeminiHovered
                    )

                if isGeminiHovered {
                    Text(isLiveRunning ? "Stop" : "Blip")
                        .font(.system(size: NotchConfiguration.geminiButtonTextFontSize, weight: .semibold))
                        .fixedSize()
                        .foregroundColor(.white)
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                }
            }
            .padding(.horizontal, isGeminiHovered ? NotchConfiguration.geminiButtonActiveHorizontalPadding : 0)
            .frame(width: isGeminiHovered ? nil : baseSize, height: baseSize)
            .background(isGeminiHovered ? (isLiveRunning ? stopGradient : activeGradient) : nil)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.spring(
                response: NotchConfiguration.geminiButtonSpringResponse,
                dampingFraction: 1
            )) {
                isGeminiHovered = hovering
            }
        }
        .simultaneousGesture(TapGesture(count: 2).onEnded(onOpenAgentS))
    }

    @ViewBuilder
    private var microphonePill: some View {
        let mic = MicrophoneUsageManager.shared
        if mic.isMicInUse {
            Button(action: {
                haptic()
                MicrophoneUsageManager.shared.toggleMute()
            }) {
                HStack(spacing: 8) {
                    Image(systemName: mic.isMuted ? "mic.slash.fill" : "mic.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(mic.isMuted ? .white.opacity(0.85) : .red)
                    Text(mic.isMuted ? "Muted" : "Mic")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(Color.black.opacity(0.25))
                )
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func notchButton(for type: NotchButtonType) -> some View {
        switch type {
        case .settings:
            SubtleIconButton(systemName: "gearshape", action: {
                (NSApp.delegate as? AppDelegate)?.openSettingsWindow()
            })
        case .fileShelf:
            if settings.settings.fileShelfIconEnabled {
                SubtleIconButton(systemName: "tray.full", action: { navigationStack.append(.fileShelf) })
            }
        case .notes:
            if settings.settings.notesIconEnabled {
                SubtleIconButton(systemName: "note.text", action: { navigationStack.append(.notesPlayer) })
            }
        case .clipboard:
            if settings.settings.clipboardIconEnabled {
                SubtleIconButton(systemName: "list.clipboard", action: { navigationStack.append(.clipboardPlayer) })
            }
        case .intelligence:
            if settings.settings.intelligenceEnabled {
                HStack(spacing: 8) {
                    intelligenceButton
                    if microphoneManager.isMicInUse && notchState == .clickExpanded {
                        microphonePill
                    }
                }
            } else {
                EmptyView()
            }
        case .intelligenceLive:
            EmptyView()
        case .focusSession:
            if settings.settings.focusSessionIconEnabled {
                SubtleIconButton(
                    systemName: "moon.fill",
                    action: { navigationStack.append(.focusSessionDetailView) }
                )
            }
        case .caffeine:
            if settings.settings.caffeinateEnabled {
                SubtleIconButton(systemName: caffeineManager.isActive ? "cup.and.heat.waves.fill" : "cup.and.heat.waves", action: { caffeineManager.toggle() }, horizontalPadding: 6)
                    .offset(y: -2)
            }
        case .battery:
            if settings.settings.batteryEstimatorEnabled {
                BatteryInfoView(
                    level: batteryEstimator.batteryLevel,
                    isCharging: batteryEstimator.isCharging,
                    timeRemaining: batteryEstimator.estimatedTimeRemaining
                )
                .padding(.horizontal, NotchConfiguration.batteryHorizontalPadding)
            } else {
                EmptyView()
            }
        case .multiAudio:
            if settings.settings.showMultiAudioIcon {
                SubtleIconButton(systemName: "hifispeaker.and.homepod.mini.fill", action: { navigationStack.append(.multiAudio) })
            }
        case .pin:
            if settings.settings.pinEnabled {
                SubtleIconButton(systemName: isPinned ? "pin.fill" : "pin", action: {
                    isPinned.toggle()
                    onPin(isPinned)
                }, horizontalPadding: 6)
            }
        case .spacer:
            EmptyView()
        }
    }
}

struct GeminiPickerBridge: View {
    @EnvironmentObject private var pickerHelper: ContentPickerHelper
    @EnvironmentObject private var geminiLiveManager: GeminiLiveManager
    @EnvironmentObject private var liveActivityManager: LiveActivityManager

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