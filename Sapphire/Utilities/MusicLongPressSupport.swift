//
//  MusicLongPressSupport.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-10

import SwiftUI

extension Notification.Name {
    static let sapphireOpenMusicQueue = Notification.Name("sapphireOpenMusicQueue")
    static let sapphireOpenMusicDevices = Notification.Name("sapphireOpenMusicDevices")
}

struct MusicLongPressNavigation {
    var openQueue: (() -> Void)?
    var openDevices: (() -> Void)?

    static let notifications = MusicLongPressNavigation(
        openQueue: { NotificationCenter.default.post(name: .sapphireOpenMusicQueue, object: nil) },
        openDevices: { NotificationCenter.default.post(name: .sapphireOpenMusicDevices, object: nil) }
    )
}

@MainActor
extension MusicManager {
    func performLongPressAction(_ action: MusicLongPressAction, navigation: MusicLongPressNavigation? = nil) async {
        switch action {
        case .none, .seek:
            break
        case .shuffle:
            await toggleShuffle()
        case .repeatMode:
            await cycleRepeatMode()
        case .like:
            await toggleLike()
        case .playPause:
            if isPlaying {
                await pause()
            } else {
                await play()
            }
        case .nextTrack:
            await nextTrack()
        case .previousTrack:
            await previousTrack()
        case .openQueue:
            if let openQueue = navigation?.openQueue {
                openQueue()
            } else {
                NotificationCenter.default.post(name: .sapphireOpenMusicQueue, object: nil)
            }
        case .openDevices:
            if let openDevices = navigation?.openDevices {
                openDevices()
            } else {
                NotificationCenter.default.post(name: .sapphireOpenMusicDevices, object: nil)
            }
        }
    }
}

enum MusicLongPressUI {
    @MainActor
    static func skipHoldHandler(
        for target: MusicLongPressTarget,
        settings: Settings,
        musicManager: MusicManager,
        navigation: MusicLongPressNavigation? = nil
    ) -> (() -> Void)? {
        let action = settings.resolvedSkipHoldAction(for: target)
        guard action != .seek else { return nil }
        return {
            Task { await musicManager.performLongPressAction(action, navigation: navigation) }
        }
    }

    static func skipHelp(primary: String, target: MusicLongPressTarget, settings: Settings) -> String {
        let action = settings.resolvedSkipHoldAction(for: target)
        if action == .seek {
            return "\(primary) · hold to seek"
        }
        return "\(primary) · hold for \(action.displayName)"
    }

    static func accessoryHelp(primary: String, target: MusicLongPressTarget, settings: Settings) -> String {
        guard let action = settings.resolvedAccessoryHoldAction(for: target) else {
            return primary
        }
        return "\(primary) · hold for \(action.displayName)"
    }
}

struct LongPressControlButton<Label: View>: View {
    let onTap: () -> Void
    var onLongPress: (() -> Void)? = nil
    @ViewBuilder var label: () -> Label

    var body: some View {
        if let onLongPress {
            LongPressControlButtonBody(onTap: onTap, onLongPress: onLongPress, label: label)
        } else {
            Button(action: onTap, label: label)
        }
    }
}

private struct LongPressControlButtonBody<Label: View>: View {
    let onTap: () -> Void
    let onLongPress: () -> Void
    @ViewBuilder var label: () -> Label

    @GestureState private var isPressing = false
    @State private var longPressTimer: Timer?
    @State private var tapIsEligible = false
    @State private var didFireLongPress = false

    var body: some View {
        label()
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($isPressing) { _, state, _ in state = true }
            )
            .onChange(of: isPressing) { _, nowPressing in
                if nowPressing {
                    tapIsEligible = true
                    didFireLongPress = false
                    longPressTimer?.invalidate()
                    longPressTimer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: false) { _ in
                        tapIsEligible = false
                        didFireLongPress = true
                        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
                        onLongPress()
                    }
                } else {
                    longPressTimer?.invalidate()
                    if tapIsEligible, !didFireLongPress {
                        onTap()
                    }
                    didFireLongPress = false
                }
            }
            .blur(radius: isPressing ? 4 : 0)
            .scaleEffect(isPressing ? 0.9 : 1.0)
            .opacity(isPressing ? 0.8 : 1.0)
            .animation(.spring(response: 0.35, dampingFraction: 0.5), value: isPressing)
    }
}