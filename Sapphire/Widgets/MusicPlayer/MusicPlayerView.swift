//
//  MusicPlayerView.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-06-26.
//

import SwiftUI
import AppKit

private struct TimeLabel: View {
    @EnvironmentObject var musicManager: MusicManager
    let isRemainingTime: Bool

    private func formatTime(_ seconds: Double) -> String {
        let cleanSeconds = seconds.isNaN || seconds.isInfinite ? 0 : seconds
        let (minutes, seconds) = (Int(cleanSeconds) / 60, Int(cleanSeconds) % 60)
        return String(format: "%d:%02d", minutes, seconds)
    }

    var body: some View {
        Text(isRemainingTime ? "-\(formatTime(musicManager.totalDuration - musicManager.currentElapsedTime))" : formatTime(musicManager.currentElapsedTime))
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundColor(.secondary)
            .onReceive(musicManager.playbackTimePublisher) { _ in
            }
    }
}

private struct LyricTextView: View {
    @EnvironmentObject var musicManager: MusicManager
    @EnvironmentObject var navigationManager: LockScreenNavigationManager
    @Binding var navigationStack: [NotchWidgetMode]
    let isLockScreenMode: Bool

    var body: some View {
        let currentLyricText = musicManager.currentLyric?.translatedText ?? musicManager.currentLyric?.text

        Group {
            if let lyricText = currentLyricText, !lyricText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(lyricText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(musicManager.accentColor)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(minHeight: 35, alignment: .center)
                    .transition(.opacity.animation(.easeInOut(duration: 0.3)))
                    .id("lyric-\(lyricText)")
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if isLockScreenMode {
                            navigationManager.navigateTo(.lyrics)
                        } else {
                            navigationStack.append(.musicLyrics)
                        }
                    }
            }
        }
    }
}

struct MusicPlayerView: View {
    @Binding var navigationStack: [NotchWidgetMode]
    @EnvironmentObject var musicManager: MusicManager
    @EnvironmentObject var settings: SettingsModel
    @EnvironmentObject var navigationManager: LockScreenNavigationManager

    var isLockScreenMode: Bool = false

    @State private var playlistsFeedbackType: MusicPlayerButtonType?
    @State private var devicesFeedbackType: MusicPlayerButtonType?

    @State private var showLikeAnimation = false
    @State private var showTemporaryLikedGlow = false

    @State private var currentProgress: Double = 0.0

    @State private var isPressingPlaylists = false
    @State private var isPressingDevices = false
    @State private var longPressTask: Task<Void, Never>?
    @State private var didTriggerLongPress = false

    private var isSpotifyOrAppleMusic: Bool {
        let bundleID = musicManager.lastKnownBundleID
        return bundleID == "com.spotify.client" || bundleID == "com.apple.Music"
    }

    private var shouldShowAirPlay: Bool {
        if settings.settings.preferAirPlayOverSpotify { return true }
        return !musicManager.isPrivateAPIAuthenticated && musicManager.lastKnownBundleID != "com.spotify.client"
    }

    private var enabledButtons: [MusicPlayerButtonType] {
        settings.settings.musicPlayerButtonOrder.filter { type in
            switch type {
            case .like: return isSpotifyOrAppleMusic && settings.settings.musicLikeButtonEnabled
            case .shuffle: return isSpotifyOrAppleMusic && (settings.settings.musicShuffleButtonEnabled ?? true)
            case .repeat: return isSpotifyOrAppleMusic && (settings.settings.musicRepeatButtonEnabled ?? true)
            case .playlists: return settings.settings.musicPlaylistsButtonEnabled
            case .devices: return settings.settings.musicDevicesButtonEnabled
            }
        }
    }

    private var primaryButtons: [MusicPlayerButtonType] { Array(enabledButtons.prefix(2)) }
    private var accessoryButtons: [MusicPlayerButtonType] { Array(enabledButtons.dropFirst(2)) }

    private var playlistsLongPressAction: MusicPlayerButtonType? {
        let isShufflePrimary = primaryButtons.contains(.shuffle)
        let isRepeatPrimary = primaryButtons.contains(.repeat)
        let isPlaylistsPrimary = primaryButtons.contains(.playlists)
        let isDevicesPrimary = primaryButtons.contains(.devices)

        if isDevicesPrimary && isRepeatPrimary { return nil }
        if isDevicesPrimary && isShufflePrimary { return nil }
        if isPlaylistsPrimary && isShufflePrimary { return enabledButtons.contains(.repeat) ? nil : .repeat }
        if enabledButtons.contains(.shuffle) { return nil }
        return .shuffle
    }

    private var devicesLongPressAction: MusicPlayerButtonType? {
        let isShufflePrimary = primaryButtons.contains(.shuffle)
        let isRepeatPrimary = primaryButtons.contains(.repeat)
        let isPlaylistsPrimary = primaryButtons.contains(.playlists)
        let isDevicesPrimary = primaryButtons.contains(.devices)

        if isPlaylistsPrimary && isShufflePrimary { return nil }
        if isPlaylistsPrimary && isRepeatPrimary { return nil }
        if isDevicesPrimary && isRepeatPrimary { return enabledButtons.contains(.shuffle) ? nil : .shuffle }
        if enabledButtons.contains(.repeat) { return nil }
        return .repeat
    }

    var body: some View {
        VStack(spacing: 3) {
            HStack(spacing: 12) {
                ZStack {
                    Image(nsImage: musicManager.artwork ?? musicManager.appIcon ?? NSImage(systemSymbolName: "waveform", accessibilityDescription: "Album art")!)
                        .resizable().aspectRatio(contentMode: .fit).frame(width: 60, height: 60)
                        .cornerRadius(8)
                        .compositingGroup()
                        .shadow(color: musicManager.accentColor.opacity(0.8), radius: 8)
                        .shadow(color: showTemporaryLikedGlow ? .pink.opacity(0.8) : .clear, radius: 15)

                    Image(systemName: "heart.fill")
                        .font(.system(size: 30)).foregroundColor(.white)
                        .scaleEffect(showLikeAnimation ? 1.0 : 0.5).opacity(showLikeAnimation ? 1.0 : 0.0)
                        .shadow(radius: 5)
                }
                .animation(.easeInOut, value: showTemporaryLikedGlow)
                .onTapGesture(count: 2) {
                    guard isSpotifyOrAppleMusic else { return }
                    musicManager.toggleLike()
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) { showLikeAnimation = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { withAnimation { showLikeAnimation = false } }
                }
                .onTapGesture { musicManager.openInSourceApp() }

                Button(action: { handleButtonTap(for: .musicQueueAndPlaylists) }) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(musicManager.title ?? "Title").font(.system(size: 16, weight: .semibold)).lineLimit(1)
                        HStack(spacing: 8) {
                            Text(musicManager.artist ?? "Artist").font(.system(size: 13)).foregroundColor(.secondary).lineLimit(1)
                            if let playCountString = musicManager.playCount, let playCountInt = Int(playCountString.replacingOccurrences(of: "K", with: "000").replacingOccurrences(of: "M", with: "000000")) {
                                PlayCountIndicator(playCount: playCountInt)
                            } else if let popularity = musicManager.popularity {
                                PopularityIndicator(popularity: popularity)
                            } else if let fetchedPopularity = musicManager.fetchedSpotifyPopularity {
                                PopularityIndicator(popularity: fetchedPopularity)
                            }
                        }
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                WaveformView()
                    .environmentObject(musicManager)
                    .scaleEffect(1.3)
                    .compositingGroup()
            }
            .padding(.top, 10)

            if musicManager.isPlaying || musicManager.totalDuration > 0 {
                VStack(spacing: 3) {
                    HStack(alignment: .center, spacing: 8) {
                        TimeLabel(isRemainingTime: false)
                        InteractiveProgressBar(value: $currentProgress, gradient: Gradient(colors: [musicManager.leftGradientColor, musicManager.rightGradientColor]), onSeek: { newProgress in
                            let seekTime = newProgress * musicManager.totalDuration
                            if seekTime.isFinite && musicManager.totalDuration > 0 { musicManager.seek(to: seekTime) }
                        }).frame(height: 30).shadow(color: musicManager.accentColor.opacity(0.5), radius: 8, y: 3)
                        TimeLabel(isRemainingTime: true)
                    }

                    LyricTextView(navigationStack: $navigationStack, isLockScreenMode: isLockScreenMode)

                    HStack {
                        MusicPlayerActionButton(type: primaryButtons.first, size: .primary)
                        Spacer()
                        SeekButton(systemName: "backward.fill", onTap: { musicManager.previousTrack() }, onSeek: { isForward in musicManager.seek(by: isForward ? 5.0 : -5.0) }).frame(width: 44, height: 44)
                        Spacer()
                        Button(action: { musicManager.isPlaying ? musicManager.pause() : musicManager.play() }) { Image(systemName: musicManager.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 28)) }.frame(width: 44, height: 44).contentShape(Rectangle())
                        Spacer()
                        SeekButton(systemName: "forward.fill", onTap: { musicManager.nextTrack() }, onSeek: { isForward in musicManager.seek(by: isForward ? 5.0 : -5.0) }).frame(width: 44, height: 44)
                        Spacer()
                        MusicPlayerActionButton(type: primaryButtons.dropFirst().first, size: .primary)
                    }
                    .buttonStyle(PlainButtonStyle()).font(.system(size: 22)).foregroundColor(.primary)
                    .padding(.top, (musicManager.currentLyric == nil && accessoryButtons.isEmpty) ? 10 : 0)
                    .padding(.bottom, musicManager.currentLyric == nil ? 5 : 0)

                    if !accessoryButtons.isEmpty {
                        HStack(spacing: 25) { ForEach(accessoryButtons) { buttonType in MusicPlayerActionButton(type: buttonType, size: .accessory) } }
                        .frame(maxWidth: .infinity).padding(.top, 5)
                    }
                }.transition(.opacity.animation(.easeInOut(duration: 0.3)))
            }
        }
        .frame(width: 400).padding(10)
        .animation(.easeInOut(duration: 0.4), value: musicManager.isPlaying)
        .animation(.default, value: enabledButtons)
        .onAppear {
            self.currentProgress = musicManager.playbackProgress
        }
        .onReceive(musicManager.playbackTimePublisher) { (_, newProgress) in
            self.currentProgress = newProgress
        }
        .onChange(of: musicManager.isLiked) { isLiked in
            if isLiked {
                showTemporaryLikedGlow = true
                Task {
                    try? await Task.sleep(for: .seconds(4))
                    showTemporaryLikedGlow = false
                }
            } else {
                showTemporaryLikedGlow = false
            }
        }
    }

    private func handleButtonTap(for targetMode: NotchWidgetMode) {
        if isLockScreenMode {
            let destination: LockScreenMusicView
            switch targetMode {
            case .musicQueueAndPlaylists:
                destination = .queueAndPlaylists
            case .musicDevices:
                destination = .devices
            case .musicLoginPrompt:
                destination = .loginPrompt
            default:
                return
            }

            if !musicManager.isPrivateAPIAuthenticated && !musicManager.isOfficialAPIAuthenticated && musicManager.lastKnownBundleID != "com.apple.Music" {
                if targetMode != .musicDevices {
                    navigationManager.navigateTo(.loginPrompt)
                    return
                }
            }
            navigationManager.navigateTo(destination)

        } else {
            if !musicManager.isPrivateAPIAuthenticated && !musicManager.isOfficialAPIAuthenticated && musicManager.lastKnownBundleID != "com.apple.Music" {
                if targetMode != .musicDevices { navigationStack.append(.musicLoginPrompt); return }
            }
            navigationStack.append(targetMode)
        }
    }

    private func triggerHapticFeedback() { NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now) }

    @ViewBuilder
    private func MusicPlayerActionButton(type: MusicPlayerButtonType?, size: ButtonSize) -> some View {
        if let type = type {
            let iconSize: CGFloat = size == .primary ? 18 : 16
            let frameSize: CGFloat = size == .primary ? 40 : 30

            switch type {
            case .playlists:
                let gesture = DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard longPressTask == nil else { return }
                        isPressingPlaylists = true
                        guard let action = playlistsLongPressAction else { return }
                        didTriggerLongPress = false
                        longPressTask = Task {
                            do {
                                try await Task.sleep(for: .seconds(0.5))
                                guard !Task.isCancelled, isSpotifyOrAppleMusic else { return }
                                didTriggerLongPress = true; isPressingPlaylists = false
                                withAnimation { playlistsFeedbackType = action }
                                while !Task.isCancelled {
                                    triggerHapticFeedback()
                                    if action == .shuffle { musicManager.toggleShuffle() }
                                    else if action == .repeat { musicManager.cycleRepeatMode() }
                                    try await Task.sleep(for: .seconds(1.0))
                                }
                            } catch {}
                        }
                    }
                    .onEnded { _ in
                        longPressTask?.cancel(); longPressTask = nil
                        if !didTriggerLongPress {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { isPressingPlaylists = false }
                            handleButtonTap(for: .musicQueueAndPlaylists)
                        } else {
                            isPressingPlaylists = false
                        }
                        playlistsFeedbackType = nil; didTriggerLongPress = false
                    }
                ZStack {
                    Image(systemName: musicManager.repeatState == .track ? "repeat.1" : "repeat").font(.system(size: iconSize)).opacity(playlistsFeedbackType == .repeat ? 1 : 0)
                    Image(systemName: "shuffle").font(.system(size: iconSize)).opacity(playlistsFeedbackType == .shuffle ? 1 : 0)
                    Image(systemName: type.systemImage).font(.system(size: iconSize + 2)).opacity(playlistsFeedbackType != nil ? 0 : 1)
                }
                .modifier(PressableButton(isPressing: $isPressingPlaylists, size: size))
                .foregroundColor( (playlistsFeedbackType == .shuffle && musicManager.shuffleState) || (playlistsFeedbackType == .repeat && musicManager.repeatState != .off) ? .green : .secondary)
                .frame(width: frameSize, height: frameSize).contentShape(Rectangle()).gesture(gesture)

            case .devices:
                 let gesture = DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard longPressTask == nil else { return }
                        isPressingDevices = true
                        guard let action = devicesLongPressAction else { return }
                        didTriggerLongPress = false
                        longPressTask = Task {
                            do {
                                try await Task.sleep(for: .seconds(0.5))
                                guard !Task.isCancelled, isSpotifyOrAppleMusic else { return }
                                didTriggerLongPress = true; isPressingDevices = false
                                withAnimation { devicesFeedbackType = action }
                                while !Task.isCancelled {
                                    triggerHapticFeedback()
                                    if action == .shuffle { musicManager.toggleShuffle() }
                                    else if action == .repeat { musicManager.cycleRepeatMode() }
                                    try await Task.sleep(for: .seconds(1.0))
                                }
                            } catch {}
                        }
                    }
                    .onEnded { _ in
                        longPressTask?.cancel(); longPressTask = nil
                        if !didTriggerLongPress {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { isPressingDevices = false }
                            handleButtonTap(for: .musicDevices)
                        } else {
                            isPressingDevices = false
                        }
                        devicesFeedbackType = nil; didTriggerLongPress = false
                    }

                let deviceIcon: String = {
                    if shouldShowAirPlay, let device = AudioDeviceManager().getCurrentOutputDevice() { return IconMapper.icon(for: device) }
                    return type.systemImage
                }()
                ZStack {
                    Image(systemName: "shuffle").font(.system(size: iconSize)).opacity(devicesFeedbackType == .shuffle ? 1 : 0)
                    Image(systemName: musicManager.repeatState == .track ? "repeat.1" : "repeat").font(.system(size: iconSize)).opacity(devicesFeedbackType == .repeat ? 1 : 0)
                    Image(systemName: deviceIcon).font(.system(size: iconSize)).opacity(devicesFeedbackType != nil ? 0 : 1)
                }
                .modifier(PressableButton(isPressing: $isPressingDevices, size: size))
                .foregroundColor( (devicesFeedbackType == .shuffle && musicManager.shuffleState) || (devicesFeedbackType == .repeat && musicManager.repeatState != .off) ? .green : .secondary)
                .frame(width: frameSize, height: frameSize).contentShape(Rectangle()).gesture(gesture)

            case .like:
                Button(action: musicManager.toggleLike) { Image(systemName: musicManager.isLiked ? "heart.fill" : "heart").font(.system(size: iconSize)) }
                .buttonStyle(size.style).foregroundColor(musicManager.isLiked ? .pink : .secondary).frame(width: frameSize, height: frameSize).contentShape(Rectangle())
                .animation(.spring(), value: musicManager.isLiked)

            case .shuffle:
                Button(action: { musicManager.toggleShuffle() }) { Image(systemName: type.systemImage).font(.system(size: iconSize)) }
                .buttonStyle(size.style).foregroundColor(musicManager.shuffleState ? .green : .secondary).frame(width: frameSize, height: frameSize).contentShape(Rectangle())
                .animation(.easeInOut, value: musicManager.shuffleState)

            case .repeat:
                Button(action: musicManager.cycleRepeatMode) { Image(systemName: musicManager.repeatState == .track ? "repeat.1" : "repeat").font(.system(size: iconSize)) }
                .buttonStyle(size.style).foregroundColor(musicManager.repeatState != .off ? .green : .secondary).frame(width: frameSize, height: frameSize).contentShape(Rectangle())
                .animation(.easeInOut, value: musicManager.repeatState)
            }
        } else {
            Rectangle().fill(Color.clear).frame(width: 40, height: 40)
        }
    }

    enum ButtonSize {
        case primary, accessory
        var style: AnyButtonStyle { AnyButtonStyle(BlurButtonStyle()) }
    }
    struct AnyButtonStyle: ButtonStyle {
        private let _makeBody: (Configuration) -> AnyView
        init<S: ButtonStyle>(_ style: S) { _makeBody = { configuration in AnyView(style.makeBody(configuration: configuration)) } }
        func makeBody(configuration: Configuration) -> some View { _makeBody(configuration) }
    }
}

struct PressableButton: ViewModifier {
    @Binding var isPressing: Bool
    var size: MusicPlayerView.ButtonSize
    func body(content: Content) -> some View {
        content
            .scaleEffect(isPressing ? 0.9 : 1.0)
            .blur(radius: isPressing ? 2 : 0)
            .animation(.interpolatingSpring(stiffness: 300, damping: 15), value: isPressing)
    }
}