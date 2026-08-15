//
//  MusicPlayerView.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-06-26.
//

import SwiftUI
import AppKit

struct PlayerProgressView: View {
    @EnvironmentObject var musicManager: MusicManager
    @State private var isSeeking = false
    @State private var seekProgress: Double = 0.0

    /// When true, uses light-on-dark styling for full-screen overlays.
    var lightStyle: Bool = false

    private func formatTime(_ seconds: Double) -> String {
        let cleanSeconds = seconds.isNaN || seconds.isInfinite ? 0 : seconds
        let (minutes, seconds) = (Int(cleanSeconds) / 60, Int(cleanSeconds) % 60)
        return String(format: "%d:%02d", minutes, seconds)
    }

    private var timeColor: Color {
        lightStyle ? Color.white.opacity(0.68) : Color.secondary
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: musicManager.isPlaying && !isSeeking ? 0.2 : 60)) { context in
            let liveElapsed = isSeeking
                ? seekProgress * musicManager.totalDuration
                : musicManager.elapsedTime(at: context.date)
            let liveProgress = isSeeking
                ? seekProgress
                : musicManager.progress(at: context.date)

            HStack(alignment: .center, spacing: 8) {
                Text(formatTime(liveElapsed))
                    .font(.system(size: lightStyle ? 11 : 10, weight: .medium, design: .monospaced))
                    .foregroundColor(timeColor)
                    .contentTransition(.numericText())

                InteractiveProgressBar(
                    value: Binding(
                        get: { liveProgress },
                        set: { seekProgress = $0 }
                    ),
                    gradient: Gradient(colors: lightStyle
                        ? [.white, .white.opacity(0.75)]
                        : [musicManager.leftGradientColor, musicManager.rightGradientColor]),
                    onSeek: { newProgress in
                        isSeeking = false
                        let seekTime = newProgress * musicManager.totalDuration
                        if seekTime.isFinite && musicManager.totalDuration > 0 {
                            Task { await musicManager.seek(to: seekTime) }
                        }
                    },
                    onDragChanged: { progress in
                        isSeeking = true
                        seekProgress = progress
                    }
                )
                .frame(height: lightStyle ? 10 : 30)
                .shadow(color: musicManager.accentColor.opacity(lightStyle ? 0.2 : 0.3), radius: lightStyle ? 2 : 4, y: 1)

                Text("-\(formatTime(max(0, musicManager.totalDuration - liveElapsed)))")
                    .font(.system(size: lightStyle ? 11 : 10, weight: .medium, design: .monospaced))
                    .foregroundColor(timeColor)
                    .contentTransition(.numericText())
            }
        }
    }
}

private struct LyricTextView: View {
    @EnvironmentObject var musicManager: MusicManager
    @EnvironmentObject var navigationManager: LockScreenNavigationManager
    @Binding var navigationStack: [NotchWidgetMode]
    let isLockScreenMode: Bool
    var onCustomTap: (() -> Void)? = nil

    var body: some View {
        TimelineView(.periodic(from: .now, by: musicManager.isPlaying ? 0.2 : 1.0)) { context in
            let line = musicManager.lyricLine(at: context.date)
            let lyricText = line?.translatedText ?? line?.text

            Group {
                if let lyricText, !lyricText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(lyricText)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(musicManager.accentColor)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .frame(minHeight: 35, alignment: .center)
                        .contentTransition(.opacity)
                        .id(line?.id ?? UUID())
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if let onCustomTap {
                                onCustomTap()
                            } else if isLockScreenMode {
                                navigationManager.navigateTo(.lyrics)
                            } else {
                                navigationStack.append(.musicLyrics)
                            }
                        }
                }
            }
            .animation(.easeInOut(duration: 0.25), value: line?.id)
        }
    }
}

struct MusicPlayerView: View {
    @Binding var navigationStack: [NotchWidgetMode]
    @EnvironmentObject var musicManager: MusicManager
    @EnvironmentObject var settings: SettingsModel
    @EnvironmentObject var navigationManager: LockScreenNavigationManager

    var isLockScreenMode: Bool = false
    /// When false, only the progress/controls half is shown (no artwork, title, waveform).
    var showArtworkSection: Bool = true
    var onQueueAction: (() -> Void)? = nil
    var onDevicesAction: (() -> Void)? = nil
    var onLoginAction: (() -> Void)? = nil
    var onLyricsTap: (() -> Void)? = nil

    @State private var playlistsFeedbackType: MusicPlayerButtonType?
    @State private var devicesFeedbackType: MusicPlayerButtonType?

    @State private var showLikeAnimation = false
    @State private var showTemporaryLikedGlow = false

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

    private var longPressNavigation: MusicLongPressNavigation {
        MusicLongPressNavigation(
            openQueue: { handleButtonTap(for: .musicQueueAndPlaylists) },
            openDevices: { handleButtonTap(for: .musicDevices) }
        )
    }

    private var isSpotifyPlaying: Bool {
        // Use lastKnownBundleID (MediaRemote — always reliable) as the primary signal.
        // isSpotifyLiveSourceSelected covers the Connect-only playback case.
        // Never gate the Spotify view on private API auth state — show it whenever
        // Spotify is the active source regardless of whether the private API has loaded.
        musicManager.lastKnownBundleID == "com.spotify.client"
            || musicManager.isSpotifyLiveSourceSelected
            || musicManager.isSpotifySourceActive
    }

    private var spotifyArtist: SpotifyArtistProfile? {
        guard isSpotifyPlaying, settings.settings.spotifyShowArtistProfile else { return nil }
        return musicManager.spotifyPrivateAPI.nowPlayingArtist
    }

    private var nextQueueTrack: PlayerState.Track? {
        guard isSpotifyPlaying, settings.settings.spotifyShowNextSong else { return nil }
        return musicManager.nativeQueue.first
    }

    /// Unified "Up Next" pill data covering both Spotify and Apple Music.
    private var nextTrackPillInfo: (title: String, artist: String)? {
        guard settings.settings.spotifyShowNextSong else { return nil }
        if isSpotifyPlaying, let next = nextQueueTrack {
            return (next.metadata?.title ?? "Up next", next.metadata?.artistName ?? "")
        }
        if musicManager.lastKnownBundleID == "com.apple.Music",
           let next = musicManager.appleMusicNextTrack {
            return (next.title, next.artist)
        }
        return nil
    }

    private var suggestedTracks: [SpotifyRecommendedTrack] {
        guard isSpotifyPlaying, settings.settings.spotifyShowSuggestedSongs else { return [] }
        return Array(musicManager.spotifyPrivateAPI.relatedTracks.prefix(4))
    }

    private var showConcertTickets: Bool {
        isSpotifyPlaying
            && settings.settings.spotifyShowConcertTickets
            && !musicManager.spotifyPrivateAPI.artistConcerts.isEmpty
    }

    var body: some View {
        VStack(spacing: 4) {
            if showArtworkSection {
                artworkSection
                    .padding(.top, 8)
            }

            if musicManager.isPlaying || musicManager.totalDuration > 0 {
                controlsSection
                    .transition(.opacity.animation(.easeInOut(duration: 0.3)))
            }
        }
        .frame(width: 400).padding(10)
        .animation(.easeInOut(duration: 0.4), value: musicManager.isPlaying)
        .animation(.default, value: enabledButtons)
        .onAppear {
            resetTransientButtonState()
            Task {
                await musicManager.setDetailPlayerOpen(true)
                await musicManager.refreshPlayerUIAfterReturning()
            }
        }
        .onDisappear {
            resetTransientButtonState()
            Task { await musicManager.setDetailPlayerOpen(false) }
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

    private var artworkSection: some View {
        HStack(spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                    let showLiveCanvas = settings.settings.spotifyCanvasLiveVideo
                        && isSpotifyPlaying
                        && musicManager.spotifyPrivateAPI.currentCanvas?.isPlayableVideo == true
                    if showLiveCanvas, let canvasURL = musicManager.spotifyPrivateAPI.currentCanvas?.videoURL {
                        SpotifyCanvasView(canvasURL: canvasURL)
                            .frame(width: 56, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .id(canvasURL)
                    }

                    if let cover = musicManager.artwork ?? musicManager.appIcon {
                        Image(nsImage: cover)
                            .resizable().aspectRatio(contentMode: .fit).frame(width: 56, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .opacity(showLiveCanvas ? 0.0 : 1.0)
                            .compositingGroup()
                            .shadow(color: musicManager.accentColor.opacity(0.35), radius: 6, y: 3)
                            .id(musicManager.currentTrackArtworkToken)
                    }

                    Image(systemName: "heart.fill")
                        .font(.system(size: 26)).foregroundColor(.white)
                        .scaleEffect(showLikeAnimation ? 1.0 : 0.5).opacity(showLikeAnimation ? 1.0 : 0.0)
                        .shadow(radius: 5)

                    if showConcertTickets {
                        Button {
                            handleButtonTap(for: .musicQueueAndPlaylists)
                            UserDefaults.standard.set(0, forKey: "lastSelectedMusicPane")
                        } label: {
                            Image(systemName: "ticket.fill")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 18, height: 18)
                                .background(Color.pink.gradient, in: Circle())
                                .shadow(color: .pink.opacity(0.45), radius: 3, y: 1)
                        }
                        .buttonStyle(.plain)
                        .offset(x: 4, y: 4)
                        .help("Nearby concerts")
                    }
                }
                .animation(.easeInOut, value: showTemporaryLikedGlow)
                .onTapGesture(count: 2) {
                    guard isSpotifyOrAppleMusic else { return }
                    Task { await musicManager.toggleLike() }
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) { showLikeAnimation = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { withAnimation { showLikeAnimation = false } }
                }
                .onTapGesture {
                    if isLockScreenMode {
                        LockScreenMusicPaneController.shared.open()
                    } else {
                        musicManager.openInSourceApp()
                    }
                }

                Button(action: { handleButtonTap(for: .musicQueueAndPlaylists) }) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(musicManager.title ?? "Title")
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .lineLimit(1)
                            if isSpotifyPlaying, settings.settings.spotifyShowAccountBadge {
                                SpotifyAccountBadge(accountInfo: musicManager.spotifyPrivateAPI.accountInfo)
                            }
                        }

                        if let artist = spotifyArtist {
                            HStack(spacing: 6) {
                                if let url = artist.avatarURL ?? artist.headerImageURL {
                                    CachedAsyncImage(url: url) { $0.resizable().aspectRatio(contentMode: .fill) } placeholder: {
                                        Circle().fill(Color.white.opacity(0.1))
                                    }
                                    .frame(width: 16, height: 16)
                                    .clipShape(Circle())
                                    .id(artist.uri)
                                }
                                Text(artist.name)
                                    .font(.system(size: 12, weight: .medium, design: .rounded))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                if artist.isVerified {
                                    Image(systemName: "checkmark.seal.fill")
                                        .font(.system(size: 9))
                                        .foregroundStyle(.cyan)
                                }
                            }
                            HStack(spacing: 8) {
                                if let listeners = artist.monthlyListeners ?? artist.followers {
                                    Text("Monthly Listener: \(formattedListenerCount(listeners))")
                                        .font(.system(size: 10, weight: .medium, design: .rounded))
                                        .foregroundStyle(.tertiary)
                                        .lineLimit(1)
                                }
                            }
                        } else {
                            Text(musicManager.artist ?? "Artist")
                                .font(.system(size: 12, design: .rounded))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                .buttonStyle(.plain)
                .id("track-\(musicManager.uri ?? musicManager.title ?? "")-\(musicManager.artist ?? "")")

                Spacer(minLength: 4)

                VStack(alignment: .trailing, spacing: 6) {
                    if settings.settings.showPopularityInMusicPlayer {
                        popularityAccessory
                            .id("pop-\(musicManager.uri ?? "")-\(musicManager.playCountValue ?? -1)-\(musicManager.popularity ?? -1)")
                    }

                    if let pill = nextTrackPillInfo {
                        NextTrackPill(
                            title: pill.title,
                            artist: pill.artist,
                            accent: musicManager.accentColor
                        ) {
                            handleButtonTap(for: .musicQueueAndPlaylists)
                            UserDefaults.standard.set(0, forKey: "lastSelectedMusicPane")
                        }
                        .padding(.top, 8)
                        .id("next-pill-\(pill.title)-\(pill.artist)")
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    } else {
                        WaveformView()
                            .environmentObject(musicManager)
                            .scaleEffect(1.05)
                            .transition(.opacity)
                    }
                }
                .frame(minWidth: 110, maxWidth: 168, alignment: .trailing)
                .animation(.easeInOut(duration: 0.2), value: nextTrackPillInfo?.title)
        }
    }

    private var controlsSection: some View {
        VStack(spacing: 3) {
            PlayerProgressView()

            if !suggestedTracks.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(suggestedTracks) { track in
                                    Button {
                                        Task {
                                            _ = await musicManager.play(
                                                trackUri: track.uri,
                                                contextUri: track.albumURI
                                            )
                                        }
                                    } label: {
                                        HStack(spacing: 5) {
                                            Image(systemName: "sparkles")
                                                .font(.system(size: 8, weight: .bold))
                                            Text(track.name)
                                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                                .lineLimit(1)
                                        }
                                        .padding(.horizontal, 9)
                                        .padding(.vertical, 5)
                                        .background(musicManager.accentColor.opacity(0.16), in: Capsule())
                                        .foregroundStyle(musicManager.accentColor)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.leading, 2)
                        }
                        .padding(.top, 1)
                    }

                    LyricTextView(
                        navigationStack: $navigationStack,
                        isLockScreenMode: isLockScreenMode,
                        onCustomTap: onLyricsTap
                    )

                    HStack {
                        MusicPlayerActionButton(type: primaryButtons.first, size: .primary)
                        Spacer()
                        SeekButton(
                            systemName: "backward.fill",
                            onTap: { Task { await musicManager.previousTrack() } },
                            onSeek: { isForward in Task { await musicManager.seek(by: isForward ? 5.0 : -5.0) } },
                            onLongPressAction: MusicLongPressUI.skipHoldHandler(
                                for: .previous,
                                settings: settings.settings,
                                musicManager: musicManager,
                                navigation: longPressNavigation
                            )
                        )
                        .frame(width: 44, height: 44)
                        .help(MusicLongPressUI.skipHelp(primary: "Previous", target: .previous, settings: settings.settings))
                        Spacer()
                        LongPressControlButton(
                            onTap: { Task { await (musicManager.isPlaying ? musicManager.pause() : musicManager.play()) } },
                            onLongPress: accessoryLongPressHandler(for: .playPause)
                        ) {
                            Image(systemName: musicManager.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 28))
                                .contentTransition(.symbolEffect(.replace))
                        }
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                        .animation(.easeInOut(duration: 0.15), value: musicManager.isPlaying)
                        .help(MusicLongPressUI.accessoryHelp(primary: "Play / Pause", target: .playPause, settings: settings.settings))
                        Spacer()
                        SeekButton(
                            systemName: "forward.fill",
                            onTap: { Task { await musicManager.nextTrack() } },
                            onSeek: { isForward in Task { await musicManager.seek(by: isForward ? 5.0 : -5.0) } },
                            onLongPressAction: MusicLongPressUI.skipHoldHandler(
                                for: .next,
                                settings: settings.settings,
                                musicManager: musicManager,
                                navigation: longPressNavigation
                            )
                        )
                        .frame(width: 44, height: 44)
                        .help(MusicLongPressUI.skipHelp(primary: "Next", target: .next, settings: settings.settings))
                        Spacer()
                        MusicPlayerActionButton(type: primaryButtons.dropFirst().first, size: .primary)
                    }
                    .buttonStyle(PlainButtonStyle()).font(.system(size: 22)).foregroundColor(.primary)
                    .padding(.top, (musicManager.currentLyric == nil && accessoryButtons.isEmpty) ? 8 : 0)
                    .padding(.bottom, musicManager.currentLyric == nil ? 4 : 0)

                    if !accessoryButtons.isEmpty {
                        HStack(spacing: 25) { ForEach(accessoryButtons) { buttonType in MusicPlayerActionButton(type: buttonType, size: .accessory) } }
                        .frame(maxWidth: .infinity).padding(.top, 4)
                    }
        }
    }

    private func accessoryLongPressHandler(for target: MusicLongPressTarget) -> (() -> Void)? {
        guard let action = settings.settings.resolvedAccessoryHoldAction(for: target) else { return nil }
        return {
            Task { await musicManager.performLongPressAction(action, navigation: longPressNavigation) }
        }
    }

    private func resetTransientButtonState() {
        longPressTask?.cancel()
        longPressTask = nil
        isPressingPlaylists = false
        isPressingDevices = false
        didTriggerLongPress = false
        playlistsFeedbackType = nil
        devicesFeedbackType = nil
    }

    @ViewBuilder
    private var popularityAccessory: some View {
        if let playCount = musicManager.playCountValue {
            PlayCountIndicator(playCount: playCount)
        } else if let popularity = musicManager.popularity {
            PopularityIndicator(popularity: popularity)
        } else if let fetchedPopularity = musicManager.fetchedSpotifyPopularity {
            PopularityIndicator(popularity: fetchedPopularity)
        }
    }

    private func formattedListenerCount(_ value: Int) -> String {
        if value >= 1_000_000 { return String(format: "%.1fM", Double(value) / 1_000_000) }
        if value >= 1_000 { return String(format: "%.1fK", Double(value) / 1_000) }
        return "\(value)"
    }

    private func handleButtonTap(for targetMode: NotchWidgetMode) {
        if let onQueueAction, targetMode == .musicQueueAndPlaylists {
            if !musicManager.isPrivateAPIAuthenticated && !musicManager.isOfficialAPIAuthenticated && musicManager.lastKnownBundleID != "com.apple.Music" {
                onLoginAction?()
                return
            }
            onQueueAction()
            return
        }

        if let onDevicesAction, targetMode == .musicDevices {
            onDevicesAction()
            return
        }

        if let onLoginAction, targetMode == .musicLoginPrompt {
            onLoginAction()
            return
        }

        if isLockScreenMode {
            let destination: LockScreenMusicView
            switch targetMode {
            case .musicQueueAndPlaylists: destination = .queueAndPlaylists
            case .musicDevices: destination = .devices
            case .musicLoginPrompt: destination = .loginPrompt
            default: return
            }
            if !musicManager.isPrivateAPIAuthenticated && !musicManager.isOfficialAPIAuthenticated && musicManager.lastKnownBundleID != "com.apple.Music" {
                if targetMode != .musicDevices { navigationManager.navigateTo(.loginPrompt); return }
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
                        longPressTask = Task {
                            do {
                                try await Task.sleep(for: .seconds(0.5))
                                guard !Task.isCancelled, isSpotifyOrAppleMusic else { return }
                                didTriggerLongPress = true; isPressingPlaylists = false
                            } catch {}
                        }
                    }
                    .onEnded { _ in
                        longPressTask?.cancel(); longPressTask = nil
                        if !didTriggerLongPress {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { isPressingPlaylists = false }
                            handleButtonTap(for: .musicQueueAndPlaylists)
                        } else { isPressingPlaylists = false }
                        playlistsFeedbackType = nil; didTriggerLongPress = false
                    }
                ZStack {
                    Image(systemName: type.systemImage).font(.system(size: iconSize + 2)).opacity(playlistsFeedbackType != nil ? 0 : 1)
                }
                .modifier(PressableButton(isPressing: $isPressingPlaylists, size: size))
                .foregroundColor(.secondary)
                .frame(width: frameSize, height: frameSize).contentShape(Rectangle()).gesture(gesture)

            case .devices:
                 let gesture = DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard longPressTask == nil else { return }
                        isPressingDevices = true
                        longPressTask = Task {
                            do {
                                try await Task.sleep(for: .seconds(0.5))
                                guard !Task.isCancelled, isSpotifyOrAppleMusic else { return }
                                didTriggerLongPress = true; isPressingDevices = false
                            } catch {}
                        }
                    }
                    .onEnded { _ in
                        longPressTask?.cancel(); longPressTask = nil
                        if !didTriggerLongPress {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { isPressingDevices = false }
                            UserDefaults.standard.set(3, forKey: "lastSelectedMusicPane")
                            handleButtonTap(for: .musicDevices)
                        } else { isPressingDevices = false }
                        devicesFeedbackType = nil; didTriggerLongPress = false
                    }

                let deviceIcon: String = musicManager.currentOutputDeviceSystemImage()
                ZStack {
                    Image(systemName: deviceIcon).font(.system(size: iconSize)).opacity(devicesFeedbackType != nil ? 0 : 1)
                }
                .modifier(PressableButton(isPressing: $isPressingDevices, size: size))
                .foregroundColor(.secondary)
                .frame(width: frameSize, height: frameSize).contentShape(Rectangle()).gesture(gesture)
                .help("Playback device")
                .id(deviceIcon)
                .animation(.easeInOut(duration: 0.2), value: deviceIcon)

            case .like:
                LongPressControlButton(
                    onTap: { Task { await musicManager.toggleLike() } },
                    onLongPress: accessoryLongPressHandler(for: .like)
                ) {
                    Image(systemName: musicManager.isLiked ? "heart.fill" : "heart")
                        .font(.system(size: iconSize))
                }
                .foregroundColor(musicManager.isLiked ? .pink : .secondary)
                .frame(width: frameSize, height: frameSize)
                .animation(.spring(), value: musicManager.isLiked)
                .help(MusicLongPressUI.accessoryHelp(primary: "Like", target: .like, settings: settings.settings))

            case .shuffle:
                LongPressControlButton(
                    onTap: { Task { await musicManager.toggleShuffle() } },
                    onLongPress: accessoryLongPressHandler(for: .shuffle)
                ) {
                    Image(systemName: musicManager.spotifyPrivateAPI.isSmartShuffleActive ? "sparkles" : type.systemImage)
                        .font(.system(size: iconSize))
                }
                .foregroundColor(
                    musicManager.spotifyPrivateAPI.isSmartShuffleActive
                        ? .purple
                        : (musicManager.shuffleState ? .green : .secondary)
                )
                .frame(width: frameSize, height: frameSize)
                .animation(.easeInOut, value: musicManager.shuffleState)
                .animation(.easeInOut, value: musicManager.spotifyPrivateAPI.isSmartShuffleActive)
                .help(
                    musicManager.spotifyPrivateAPI.isSmartShuffleActive
                        ? MusicLongPressUI.accessoryHelp(primary: "Smart Shuffle — tap for Off", target: .shuffle, settings: settings.settings)
                        : (musicManager.shuffleState
                            ? MusicLongPressUI.accessoryHelp(primary: "Shuffle — tap for Smart Shuffle", target: .shuffle, settings: settings.settings)
                            : MusicLongPressUI.accessoryHelp(primary: "Off — tap for Shuffle", target: .shuffle, settings: settings.settings))
                )

            case .repeat:
                LongPressControlButton(
                    onTap: { Task { await musicManager.cycleRepeatMode() } },
                    onLongPress: accessoryLongPressHandler(for: .repeatMode)
                ) {
                    Image(systemName: musicManager.repeatState == .track ? "repeat.1" : "repeat")
                        .font(.system(size: iconSize))
                }
                .foregroundColor(musicManager.repeatState != .off ? .green : .secondary)
                .frame(width: frameSize, height: frameSize)
                .animation(.easeInOut, value: musicManager.repeatState)
                .help(MusicLongPressUI.accessoryHelp(primary: "Repeat", target: .repeatMode, settings: settings.settings))
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

// MARK: - View Modifiers
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

/// Horizontal next-up pill used in place of the live waveform when a queue track is available.
struct NextTrackPill: View {
    let title: String
    let artist: String
    let accent: Color
    var onTap: (() -> Void)? = nil

    private var helpText: String {
        artist.isEmpty ? "Up next: \(title)" : "Up next: \(title) — \(artist)"
    }

    var body: some View {
        Button {
            onTap?()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "music.note.list")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(accent.opacity(0.85))

                Group {
                    if artist.isEmpty {
                        Text(title)
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(.primary.opacity(0.85))
                    } else {
                        (Text(title)
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundColor(.primary.opacity(0.85))
                         + Text(" · \(artist)")
                            .font(.system(size: 10, weight: .regular, design: .rounded))
                            .foregroundColor(.secondary))
                    }
                }
                .lineLimit(1)
                .truncationMode(.tail)
            }
            .frame(maxWidth: 168, alignment: .trailing)
            .padding(.horizontal, 7)
            .padding(.vertical, 3.5)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(helpText)
    }
}

/// Compact app-icon source switcher beside the notch back chevron.
struct NotchMediaSourceSwitcher: View {
    @EnvironmentObject var musicManager: MusicManager

    private var keys: [String] {
        musicManager.activeMediaSources.keys.sorted { a, b in
            if a.contains("spotify-live") { return false }
            if b.contains("spotify-live") { return true }
            return a < b
        }
    }

    var body: some View {
        let sourceKeys = keys
        let selectedKey = musicManager.currentSourceKey
        if sourceKeys.count > 1, let fallbackKey = sourceKeys.first {
            HStack(spacing: 3) {
                ForEach(sourceKeys, id: \.self) { key in
                    let selected = (selectedKey ?? fallbackKey) == key
                    Button {
                        musicManager.selectSource(key: key, userInitiated: true)
                    } label: {
                        Image(nsImage: musicManager.sourceAppIcon(for: key))
                            .resizable()
                            .interpolation(.high)
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 16, height: 16)
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                            .padding(3)
                            .background(
                                Circle()
                                    .fill(selected ? Color.white.opacity(0.22) : Color.clear)
                            )
                            .opacity(selected ? 1.0 : 0.55)
                    }
                    .buttonStyle(.plain)
                    .help(label(for: key))
                }
            }
            .padding(2)
            .background(Capsule(style: .continuous).fill(Color.white.opacity(0.08)))
            .overlay(Capsule(style: .continuous).stroke(Color.white.opacity(0.12), lineWidth: 1))
            .fixedSize()
            .animation(.easeInOut(duration: 0.2), value: selectedKey)
            .animation(.easeInOut(duration: 0.2), value: sourceKeys.joined(separator: "|"))
            .id("sources-\(sourceKeys.joined(separator: "|"))-\(selectedKey ?? "")")
        }
    }

    private func label(for key: String) -> String {
        if key.contains("spotify-live") || key.lowercased().contains("spotify") { return "Spotify" }
        if let track = musicManager.activeMediaSources[key] {
            return musicManager.appName(for: track.payload.bundleIdentifier)
        }
        return "App"
    }
}
