//
//  MusicPlayerViews.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-21

import SwiftUI
import AppKit
import Combine
import QuartzCore

// MARK: - Consolidated from MusicPlayerView.swift

struct PlayerProgressView: View {
    @EnvironmentObject var musicManager: MusicManager
    @State private var isSeeking = false
    @State private var seekProgress: Double = 0.0

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
                        seekProgress = newProgress
                        isSeeking = true
                        let seekTime = newProgress * musicManager.totalDuration
                        if seekTime.isFinite && musicManager.totalDuration > 0 {
                            Task {
                                await musicManager.seek(to: seekTime)
                                await MainActor.run {
                                    seekProgress = newProgress
                                    isSeeking = false
                                }
                            }
                        } else {
                            isSeeking = false
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
        TimelineView(.periodic(from: .now, by: musicManager.isPlaying ? 0.25 : 1.0)) { context in
            let line = musicManager.lyricLine(at: context.date)
            let lyricText = line?.translatedText ?? line?.text
            let trimmed = lyricText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            if !trimmed.isEmpty {
                Text(trimmed)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(musicManager.accentColor)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, minHeight: 35, alignment: .center)
                    .contentTransition(.opacity)
                    .animation(.easeInOut(duration: 0.2), value: line?.id)
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
    }
}

struct MusicPlayerView: View {
    @Binding var navigationStack: [NotchWidgetMode]
    @EnvironmentObject var musicManager: MusicManager
    @EnvironmentObject var settings: SettingsModel
    @EnvironmentObject var navigationManager: LockScreenNavigationManager

    var isLockScreenMode: Bool = false
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
    @State private var holdFeedbackAction: MusicLongPressAction?
    @State private var holdFeedbackIcon: String?
    @State private var holdFeedbackColor: Color = .primary
    @State private var holdFeedbackRestoreTask: Task<Void, Never>?
    @State private var holdFeedbackButtonID: String?
    @State private var holdActionInFlight = false

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
        musicManager.isSpotifyLiveSourceSelected || musicManager.isSpotifySourceActive
    }

    private var spotifyArtist: SpotifyArtistProfile? {
        guard isSpotifyPlaying, settings.settings.spotifyShowArtistProfile else { return nil }
        guard let profile = musicManager.spotifyPrivateAPI.nowPlayingArtist else { return nil }
        // Never show a profile that doesn't belong to the currently displayed track artist.
        guard let trackArtist = musicManager.artist?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !trackArtist.isEmpty else { return profile }
        let profileName = profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let track = trackArtist.lowercased()
        let name = profileName.lowercased()
        guard track == name || track.contains(name) || name.contains(track) else {
            return nil
        }
        return profile
    }

    private var displayedArtistName: String {
        musicManager.artist ?? spotifyArtist?.name ?? "Artist"
    }

    private var nextQueueTrack: PlayerState.Track? {
        guard isSpotifyPlaying, settings.settings.spotifyShowNextSong else { return nil }
        return musicManager.nativeQueue.first
    }

    private var nextTrackPillInfo: (title: String, artist: String)? {
        guard settings.settings.spotifyShowNextSong else { return nil }
        if isSpotifyPlaying, let next = nextQueueTrack {
            return (next.metadata?.title ?? "", next.metadata?.artistName ?? "")
        }
        if musicManager.lastKnownBundleID == "com.apple.Music",
           let next = musicManager.appleMusicNextTrack {
            return (next.title, next.artist)
        }
        return nil
    }

    private var nextTrackArtworkURL: URL? {
        nextQueueTrack?.metadata?.imageURL
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
            ZStack {
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
                        .font(.system(size: 26, weight: .bold))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.35), radius: 4, y: 1)
                        .scaleEffect(showLikeAnimation ? 1.0 : 0.45)
                        .opacity(showLikeAnimation ? 1.0 : 0.0)
                        .frame(width: 56, height: 56)

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
                        .frame(width: 56, height: 56, alignment: .bottomTrailing)
                        .offset(x: 4, y: 4)
                        .help("Nearby concerts")
                    }
                }
                .frame(width: 56, height: 56)
                .animation(.easeInOut, value: showTemporaryLikedGlow)
                .onTapGesture(count: 2) {
                    guard isSpotifyOrAppleMusic else { return }
                    Task {
                        let wasLiked = musicManager.isLiked
                        await musicManager.toggleLike()
                        if musicManager.isLiked || musicManager.isLiked != wasLiked {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) { showLikeAnimation = true }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                                withAnimation { showLikeAnimation = false }
                            }
                        }
                    }
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
                                Text(displayedArtistName)
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
                    if let pill = nextTrackPillInfo {
                        ZStack(alignment: .topTrailing) {
                            NextTrackInline(
                                title: pill.title,
                                artist: pill.artist,
                                artworkURL: nextTrackArtworkURL,
                                accent: musicManager.accentColor
                            ) {
                                handleButtonTap(for: .musicQueueAndPlaylists)
                                UserDefaults.standard.set(0, forKey: "lastSelectedMusicPane")
                            }
                            .id("next-inline-\(pill.title)-\(pill.artist)")
                            .transition(.opacity)

                            if settings.settings.showPopularityInMusicPlayer {
                                popularityAccessory
                                    .id("pop-\(musicManager.uri ?? "")-\(musicManager.playCountValue ?? -1)-\(musicManager.popularity ?? -1)")
                                    .padding(.trailing, 4)
                                    .offset(y: -26)
                            }
                        }
                        .offset(y: 8)
                        .transition(.opacity)
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

                    if musicManager.hasCurrentDisplayableLyric {
                        LyricTextView(
                            navigationStack: $navigationStack,
                            isLockScreenMode: isLockScreenMode,
                            onCustomTap: onLyricsTap
                        )
                    }

                    HStack {
                        MusicPlayerActionButton(type: primaryButtons.first, size: .primary)
                        Spacer()
                        SeekButton(
                            systemName: "backward.fill",
                            onTap: { Task { await musicManager.previousTrack() } },
                            onSeek: { isForward in Task { await musicManager.seek(by: isForward ? 5.0 : -5.0) } },
                            onLongPressAction: skipHoldClosure(for: .previous),
                            holdAction: skipHoldAction(for: .previous),
                            onHoldBegan: { action in
                                beginHoldFeedback(action: action, buttonID: "previous")
                            },
                            onHoldEnded: endHoldFeedback,
                            displayedSystemName: holdFeedbackButtonID == "previous" ? holdFeedbackIcon : nil
                        )
                        .frame(width: 44, height: 44)
                        .foregroundStyle(holdFeedbackButtonID == "previous" ? holdFeedbackColor : .primary)
                        .help(MusicLongPressUI.skipHelp(primary: "Previous", target: .previous, settings: settings.settings))
                        Spacer()
                        LongPressControlButton(
                            onTap: { Task { await (musicManager.isPlaying ? musicManager.pause() : musicManager.play()) } },
                            onLongPress: accessoryLongPressHandler(for: .playPause),
                            onHoldBegan: { action in beginHoldFeedback(action: action, buttonID: "playPause") },
                            holdAction: settings.settings.resolvedAccessoryHoldAction(for: .playPause),
                            onHoldEnded: endHoldFeedback
                        ) {
                            Image(systemName: holdFeedbackButtonID == "playPause"
                                  ? (holdFeedbackIcon ?? (musicManager.isPlaying ? "pause.fill" : "play.fill"))
                                  : (musicManager.isPlaying ? "pause.fill" : "play.fill"))
                                .font(.system(size: 28))
                                .contentTransition(.symbolEffect(.replace))
                                .foregroundStyle(holdFeedbackButtonID == "playPause" ? holdFeedbackColor : .primary)
                        }
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                        .animation(.easeInOut(duration: 0.15), value: musicManager.isPlaying)
                        .animation(.easeInOut(duration: 0.15), value: holdFeedbackIcon)
                        .help(MusicLongPressUI.accessoryHelp(primary: "Play / Pause", target: .playPause, settings: settings.settings))
                        Spacer()
                        SeekButton(
                            systemName: "forward.fill",
                            onTap: { Task { await musicManager.nextTrack() } },
                            onSeek: { isForward in Task { await musicManager.seek(by: isForward ? 5.0 : -5.0) } },
                            onLongPressAction: skipHoldClosure(for: .next),
                            holdAction: skipHoldAction(for: .next),
                            onHoldBegan: { action in
                                beginHoldFeedback(action: action, buttonID: "next")
                            },
                            onHoldEnded: endHoldFeedback,
                            displayedSystemName: holdFeedbackButtonID == "next" ? holdFeedbackIcon : nil
                        )
                        .frame(width: 44, height: 44)
                        .foregroundStyle(holdFeedbackButtonID == "next" ? holdFeedbackColor : .primary)
                        .help(MusicLongPressUI.skipHelp(primary: "Next", target: .next, settings: settings.settings))
                        Spacer()
                        MusicPlayerActionButton(type: primaryButtons.dropFirst().first, size: .primary)
                    }
                    .buttonStyle(PlainButtonStyle()).font(.system(size: 22)).foregroundColor(.primary)
                    .padding(.top, (!musicManager.hasCurrentDisplayableLyric && accessoryButtons.isEmpty) ? 8 : 0)
                    .padding(.bottom, !musicManager.hasCurrentDisplayableLyric ? 4 : 0)

                    if !accessoryButtons.isEmpty {
                        HStack(spacing: 25) { ForEach(accessoryButtons) { buttonType in MusicPlayerActionButton(type: buttonType, size: .accessory) } }
                        .frame(maxWidth: .infinity).padding(.top, 4)
                    }
        }
    }

    private func accessoryLongPressHandler(for target: MusicLongPressTarget) -> (() -> Void)? {
        guard let action = settings.settings.resolvedAccessoryHoldAction(for: target) else { return nil }
        return {
            Task { @MainActor in
                guard !holdActionInFlight else { return }
                holdActionInFlight = true
                defer { holdActionInFlight = false }
                await musicManager.performLongPressAction(action, navigation: longPressNavigation)
                refreshHoldFeedbackIcon()
            }
        }
    }

    private func skipHoldAction(for target: MusicLongPressTarget) -> MusicLongPressAction? {
        let action = settings.settings.resolvedSkipHoldAction(for: target)
        if action == .none || action == .seek { return nil }
        return action
    }

    private func skipHoldClosure(for target: MusicLongPressTarget) -> (() -> Void)? {
        guard let action = skipHoldAction(for: target) else { return nil }
        return {
            Task { @MainActor in
                guard !holdActionInFlight else { return }
                holdActionInFlight = true
                defer { holdActionInFlight = false }
                await musicManager.performLongPressAction(action, navigation: longPressNavigation)
                refreshHoldFeedbackIcon()
            }
        }
    }

    private func beginHoldFeedback(action: MusicLongPressAction, buttonID: String) {
        holdFeedbackRestoreTask?.cancel()
        withAnimation(.easeInOut(duration: 0.15)) {
            holdFeedbackButtonID = buttonID
            holdFeedbackAction = action
            holdFeedbackIcon = action.feedbackSystemImage(musicManager: musicManager)
            holdFeedbackColor = action.feedbackColor(musicManager: musicManager)
        }
    }

    private func refreshHoldFeedbackIcon() {
        guard let action = holdFeedbackAction else { return }
        withAnimation(.easeInOut(duration: 0.15)) {
            holdFeedbackIcon = action.feedbackSystemImage(musicManager: musicManager)
            holdFeedbackColor = action.feedbackColor(musicManager: musicManager)
        }
    }

    private func endHoldFeedback() {
        holdFeedbackRestoreTask?.cancel()
        holdFeedbackRestoreTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.25)) {
                holdFeedbackAction = nil
                holdFeedbackIcon = nil
                holdFeedbackButtonID = nil
            }
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
        holdFeedbackRestoreTask?.cancel()
        holdFeedbackAction = nil
        holdFeedbackIcon = nil
        holdFeedbackButtonID = nil
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
                LongPressControlButton(
                    onTap: { handleButtonTap(for: .musicQueueAndPlaylists) },
                    onLongPress: accessoryLongPressHandler(for: .playlists),
                    onHoldBegan: { action in beginHoldFeedback(action: action, buttonID: "playlists") },
                    holdAction: settings.settings.resolvedAccessoryHoldAction(for: .playlists),
                    onHoldEnded: endHoldFeedback
                ) {
                    Image(systemName: holdFeedbackButtonID == "playlists"
                          ? (holdFeedbackIcon ?? type.systemImage)
                          : type.systemImage)
                        .font(.system(size: iconSize + 2))
                        .contentTransition(.symbolEffect(.replace))
                }
                .foregroundStyle(holdFeedbackButtonID == "playlists" ? holdFeedbackColor : .secondary)
                .frame(width: frameSize, height: frameSize)
                .animation(.easeInOut(duration: 0.15), value: holdFeedbackIcon)
                .help(MusicLongPressUI.accessoryHelp(primary: "Queue", target: .playlists, settings: settings.settings))

            case .devices:
                let deviceIcon: String = musicManager.currentOutputDeviceSystemImage()
                LongPressControlButton(
                    onTap: {
                        UserDefaults.standard.set(3, forKey: "lastSelectedMusicPane")
                        handleButtonTap(for: .musicDevices)
                    },
                    onLongPress: accessoryLongPressHandler(for: .devices),
                    onHoldBegan: { action in beginHoldFeedback(action: action, buttonID: "devices") },
                    holdAction: settings.settings.resolvedAccessoryHoldAction(for: .devices),
                    onHoldEnded: endHoldFeedback
                ) {
                    Image(systemName: holdFeedbackButtonID == "devices"
                          ? (holdFeedbackIcon ?? deviceIcon)
                          : deviceIcon)
                        .font(.system(size: iconSize))
                        .contentTransition(.symbolEffect(.replace))
                }
                .foregroundStyle(holdFeedbackButtonID == "devices" ? holdFeedbackColor : .secondary)
                .frame(width: frameSize, height: frameSize)
                .help(MusicLongPressUI.accessoryHelp(primary: "Playback device", target: .devices, settings: settings.settings))
                .id(deviceIcon)
                .animation(.easeInOut(duration: 0.2), value: deviceIcon)
                .animation(.easeInOut(duration: 0.15), value: holdFeedbackIcon)

            case .like:
                LongPressControlButton(
                    onTap: { Task { await musicManager.toggleLike() } },
                    onLongPress: accessoryLongPressHandler(for: .like),
                    onHoldBegan: { action in beginHoldFeedback(action: action, buttonID: "like") },
                    holdAction: settings.settings.resolvedAccessoryHoldAction(for: .like),
                    onHoldEnded: endHoldFeedback
                ) {
                    Image(systemName: holdFeedbackButtonID == "like"
                          ? (holdFeedbackIcon ?? (musicManager.isLiked ? "heart.fill" : "heart"))
                          : (musicManager.isLiked ? "heart.fill" : "heart"))
                        .font(.system(size: iconSize))
                        .contentTransition(.symbolEffect(.replace))
                }
                .foregroundColor(holdFeedbackButtonID == "like"
                                 ? holdFeedbackColor
                                 : (musicManager.isLiked ? .pink : .secondary))
                .frame(width: frameSize, height: frameSize)
                .animation(.spring(), value: musicManager.isLiked)
                .animation(.easeInOut(duration: 0.15), value: holdFeedbackIcon)
                .help(MusicLongPressUI.accessoryHelp(primary: "Like", target: .like, settings: settings.settings))

            case .shuffle:
                LongPressControlButton(
                    onTap: { Task { await musicManager.toggleShuffle() } },
                    onLongPress: accessoryLongPressHandler(for: .shuffle),
                    onHoldBegan: { action in beginHoldFeedback(action: action, buttonID: "shuffle") },
                    holdAction: settings.settings.resolvedAccessoryHoldAction(for: .shuffle),
                    onHoldEnded: endHoldFeedback
                ) {
                    Image(systemName: holdFeedbackButtonID == "shuffle"
                          ? (holdFeedbackIcon ?? (musicManager.spotifyPrivateAPI.isSmartShuffleActive ? "sparkles" : type.systemImage))
                          : (musicManager.spotifyPrivateAPI.isSmartShuffleActive ? "sparkles" : type.systemImage))
                        .font(.system(size: iconSize))
                        .contentTransition(.symbolEffect(.replace))
                }
                .foregroundColor(
                    holdFeedbackButtonID == "shuffle"
                        ? holdFeedbackColor
                        : (musicManager.spotifyPrivateAPI.isSmartShuffleActive
                            ? .purple
                            : (musicManager.shuffleState ? .green : .secondary))
                )
                .frame(width: frameSize, height: frameSize)
                .animation(.easeInOut, value: musicManager.shuffleState)
                .animation(.easeInOut, value: musicManager.spotifyPrivateAPI.isSmartShuffleActive)
                .animation(.easeInOut(duration: 0.15), value: holdFeedbackIcon)
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
                    onLongPress: accessoryLongPressHandler(for: .repeatMode),
                    onHoldBegan: { action in beginHoldFeedback(action: action, buttonID: "repeat") },
                    holdAction: settings.settings.resolvedAccessoryHoldAction(for: .repeatMode),
                    onHoldEnded: endHoldFeedback
                ) {
                    Image(systemName: holdFeedbackButtonID == "repeat"
                          ? (holdFeedbackIcon ?? (musicManager.repeatState == .track ? "repeat.1" : "repeat"))
                          : (musicManager.repeatState == .track ? "repeat.1" : "repeat"))
                        .font(.system(size: iconSize))
                        .contentTransition(.symbolEffect(.replace))
                }
                .foregroundColor(holdFeedbackButtonID == "repeat"
                                 ? holdFeedbackColor
                                 : (musicManager.repeatState != .off ? .green : .secondary))
                .frame(width: frameSize, height: frameSize)
                .animation(.easeInOut, value: musicManager.repeatState)
                .animation(.easeInOut(duration: 0.15), value: holdFeedbackIcon)
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

struct NextTrackInline: View {
    let title: String
    let artist: String
    let artworkURL: URL?
    let accent: Color
    var onTap: (() -> Void)? = nil

    @State private var isHovering = false

    private let cornerRadius: CGFloat = 10

    private var helpText: String {
        artist.isEmpty ? "Up next: \(title)" : "Up next: \(title) — \(artist)"
    }

    var body: some View {
        Button {
            onTap?()
        } label: {
            HStack(spacing: 8) {
                Group {
                    if let artworkURL {
                        CachedAsyncImage(url: artworkURL) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } placeholder: {
                            placeholderTile
                        }
                    } else {
                        placeholderTile
                    }
                }
                .frame(width: 26, height: 26)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 1) {
                    Text("UP NEXT")
                        .font(.system(size: 7, weight: .heavy, design: .rounded))
                        .kerning(1.1)
                        .foregroundStyle(accent)
                    Text(title.isEmpty ? "Unknown track" : title)
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if !artist.isEmpty {
                        Text(artist)
                            .font(.system(size: 6, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                .frame(alignment: .leading)
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 5)
            .frame(alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(accent.opacity(isHovering ? 0.14 : 0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(accent.opacity(isHovering ? 0.4 : 0.22), lineWidth: 1)
            )
            .scaleEffect(isHovering ? 1.02 : 1.0)
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovering)
        .onHover { isHovering = $0 }
        .help(helpText)
    }

    private var placeholderTile: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(accent.opacity(0.18))
            Image(systemName: "music.note")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(accent)
        }
    }
}

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

// MARK: - Consolidated from MusicWidgetView.swift

struct MusicWidgetView: View {
    @Environment(\.navigationStack) var navigationStack
    @EnvironmentObject var musicManager: MusicManager
    @EnvironmentObject var settings: SettingsModel
    @State private var isHoveringArtwork = false

    var onExpand: (() -> Void)? = nil

    var body: some View {
        if let title = musicManager.title, !title.isEmpty {
            HStack(alignment: .center, spacing: 16) {
                albumArt

                VStack(alignment: .leading, spacing: 8) {
                    MusicInfoView(
                        title: musicManager.title,
                        album: musicManager.album,
                        artist: musicManager.artist
                    )
                    .id("info-\(musicManager.title ?? "")-\(musicManager.album ?? "")-\(musicManager.artist ?? "")-\(musicManager.uri ?? "")")
                    .animation(.easeInOut(duration: 0.2), value: musicManager.title)
                    .animation(.easeInOut(duration: 0.2), value: musicManager.artist)
                    .animation(.easeInOut(duration: 0.2), value: musicManager.album)

                    MusicControlsView(
                        isPlaying: musicManager.isPlaying,
                        onPrevious: { Task { await musicManager.previousTrack() } },
                        onPlayPause: { Task { await (musicManager.isPlaying ? musicManager.pause() : musicManager.play()) } },
                        onNext: { Task { await musicManager.nextTrack() } }
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 100)
            .frame(maxWidth: 300)
            .fixedSize()
            .contentShape(Rectangle())
            .onTapGesture {
                if let onExpand {
                    onExpand()
                } else {
                    navigationStack.wrappedValue.append(.musicPlayer)
                }
            }

        } else {
            OpenPlayerView(
                player: settings.settings.defaultMusicPlayer,
                action: openDefaultPlayer
            )
        }
    }

    private var albumArt: some View {
        Image(nsImage: musicManager.artwork ?? musicManager.appIcon ?? NSImage(systemSymbolName: "waveform", accessibilityDescription: "Album art")!)
            .resizable().aspectRatio(contentMode: .fill)
            .frame(width: 100, height: 100).cornerRadius(30)
            .shadow(color: musicManager.accentColor.opacity(0.7), radius: 8, y: 5)
            .onHover { hovering in
                self.isHoveringArtwork = hovering
            }
    }

    private func openDefaultPlayer() {
        let player = settings.settings.defaultMusicPlayer
        let bundleId = player == .appleMusic ? "com.apple.Music" : "com.spotify.client"

        NSWorkspace.shared.launchApplication(
            withBundleIdentifier: bundleId,
            options: [],
            additionalEventParamDescriptor: nil,
            launchIdentifier: nil
        )
    }
}

private struct OpenPlayerView: View {
    let player: DefaultMusicPlayer
    let action: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "music.note")
                .font(.system(size: 40, weight: .light))
                .foregroundColor(.white.opacity(0.8))

            Button(action: action) {
                Text("Open \(player.displayName)")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.15))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .frame(width: 300, height: 100)
    }
}

private struct MusicInfoView: View {
    let title: String?
    let album: String?
    let artist: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let title = title, !title.isEmpty {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
            }

            if let album = album, !album.isEmpty, album != title {
                Text(album)
                    .font(.system(size: 14, weight: .medium))
            }
            if let artist = artist, !artist.isEmpty {
                Text(artist)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(.white.opacity(0.7))
            }
        }
        .foregroundStyle(.white)
        .lineLimit(1)
        .padding(.top, 8)
        .minimumScaleFactor(0.8)
    }
}

private struct MusicControlsView: View {
    let isPlaying: Bool
    let onPrevious: () -> Void
    let onPlayPause: () -> Void
    let onNext: () -> Void

    @EnvironmentObject var musicManager: MusicManager
    @EnvironmentObject var settings: SettingsModel

    let buttonHitboxSize: CGFloat = 37

    var body: some View {
        HStack(spacing: 0) {
            SeekButton(
                systemName: "backward.end.fill",
                onTap: onPrevious,
                onSeek: { isForward in
                    Task { await musicManager.seek(by: isForward ? 5.0 : -5.0) }
                },
                onLongPressAction: MusicLongPressUI.skipHoldHandler(
                    for: .previous,
                    settings: settings.settings,
                    musicManager: musicManager,
                    navigation: .notifications
                )
            )
            .frame(width: buttonHitboxSize, height: buttonHitboxSize)
            .help(MusicLongPressUI.skipHelp(primary: "Previous", target: .previous, settings: settings.settings))

            Button(action: onPlayPause) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .frame(width: buttonHitboxSize, height: buttonHitboxSize)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            SeekButton(
                systemName: "forward.end.fill",
                onTap: onNext,
                onSeek: { isForward in
                    Task { await musicManager.seek(by: isForward ? 5.0 : -5.0) }
                },
                onLongPressAction: MusicLongPressUI.skipHoldHandler(
                    for: .next,
                    settings: settings.settings,
                    musicManager: musicManager,
                    navigation: .notifications
                )
            )
            .frame(width: buttonHitboxSize, height: buttonHitboxSize)
            .help(MusicLongPressUI.skipHelp(primary: "Next", target: .next, settings: settings.settings))
        }
        .font(.system(size: 16))
        .foregroundColor(.white)
    }
}

// MARK: - Consolidated from WaveformView.swift

struct CoreAnimationWaveformView: NSViewRepresentable, Equatable {
    var isPlaying: Bool
    var barCount: Int
    var volumeScale: CGFloat
    var barThickness: CGFloat
    var leftGradientColor: Color
    var rightGradientColor: Color

    static func == (lhs: CoreAnimationWaveformView, rhs: CoreAnimationWaveformView) -> Bool {
        return lhs.isPlaying == rhs.isPlaying &&
               lhs.barCount == rhs.barCount &&
               lhs.volumeScale == rhs.volumeScale &&
               lhs.barThickness == rhs.barThickness &&
               lhs.leftGradientColor == rhs.leftGradientColor &&
               lhs.rightGradientColor == rhs.rightGradientColor
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.frame = CGRect(x: 0, y: 0, width: 22, height: 22)
        context.coordinator.setupLayers(in: view.layer!, with: context)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.update(isPlaying: isPlaying)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator {
        var parent: CoreAnimationWaveformView
        var maskLayers: [CAShapeLayer] = []
        private var hasSetup = false

        private var lastIsPlaying: Bool? = nil
        private var lastLeftColor: Color? = nil
        private var lastRightColor: Color? = nil
        private var lastVolumeScale: CGFloat? = nil

        init(_ parent: CoreAnimationWaveformView) {
            self.parent = parent
        }

        func setupLayers(in parentLayer: CALayer, with context: Context) {
            guard !hasSetup else { return }
            hasSetup = true

            let totalSpacing = CGFloat(parent.barCount - 1) * 3.0
            let totalWidth = CGFloat(parent.barCount) * parent.barThickness + totalSpacing
            var xOffset = (parentLayer.bounds.width - totalWidth) / 2.0

            for _ in 0..<parent.barCount {
                let barContainerLayer = CALayer()
                barContainerLayer.frame = CGRect(x: xOffset, y: 0, width: parent.barThickness, height: parentLayer.bounds.height)

                let gradientLayer = CAGradientLayer()
                gradientLayer.frame = barContainerLayer.bounds
                gradientLayer.colors = [
                    NSColor(parent.leftGradientColor).cgColor,
                    NSColor(parent.rightGradientColor).cgColor
                ]
                gradientLayer.startPoint = CGPoint(x: 0.5, y: 0.0)
                gradientLayer.endPoint = CGPoint(x: 0.5, y: 1.0)

                let maskLayer = CAShapeLayer()
                maskLayer.frame = barContainerLayer.bounds

                gradientLayer.mask = maskLayer
                barContainerLayer.addSublayer(gradientLayer)
                parentLayer.addSublayer(barContainerLayer)

                maskLayers.append(maskLayer)

                xOffset += parent.barThickness + 3.0
            }
        }

        func update(isPlaying: Bool) {
            let colorsChanged = parent.leftGradientColor != lastLeftColor || parent.rightGradientColor != lastRightColor
            let playStateChanged = isPlaying != lastIsPlaying
            let scaleChanged = parent.volumeScale != lastVolumeScale

            guard colorsChanged || playStateChanged || scaleChanged else { return }

            lastLeftColor = parent.leftGradientColor
            lastRightColor = parent.rightGradientColor
            lastIsPlaying = isPlaying
            lastVolumeScale = parent.volumeScale

            let minHeight = parent.barThickness
            let animationKey = "pathAnimation"

            for (index, maskLayer) in maskLayers.enumerated() {
                if let gradient = (maskLayer.superlayer as? CAGradientLayer), colorsChanged {
                     gradient.colors = [
                        NSColor(parent.leftGradientColor).cgColor,
                        NSColor(parent.rightGradientColor).cgColor
                    ]
                }

                if isPlaying {
                    if playStateChanged || scaleChanged || maskLayer.animation(forKey: animationKey) == nil {
                        maskLayer.removeAnimation(forKey: animationKey)

                        let animation = CABasicAnimation(keyPath: "path")
                        let highValues = [0.5, 0.8, 0.65, 0.7, 0.9, 0.6]
                        let speeds = [1.8, 1.2, 1.4, 1.6, 1.0, 1.7]

                        let maxHeight = 22.0
                        let targetHeight = minHeight + (maxHeight - minHeight) * (highValues[index] * parent.volumeScale)

                        let fromY = (maskLayer.bounds.height - minHeight) / 2.0
                        let toY = (maskLayer.bounds.height - targetHeight) / 2.0

                        let fromPath = CGPath(roundedRect: CGRect(x: 0, y: fromY, width: parent.barThickness, height: minHeight),
                                             cornerWidth: parent.barThickness / 2,
                                             cornerHeight: parent.barThickness / 2,
                                             transform: nil)

                        let toPath = CGPath(roundedRect: CGRect(x: 0, y: toY, width: parent.barThickness, height: targetHeight),
                                           cornerWidth: parent.barThickness / 2,
                                           cornerHeight: parent.barThickness / 2,
                                           transform: nil)

                        maskLayer.path = fromPath

                        animation.fromValue = fromPath
                        animation.toValue = toPath
                        animation.duration = 1.5 / speeds[index]
                        animation.autoreverses = true
                        animation.repeatCount = .infinity
                        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

                        maskLayer.add(animation, forKey: animationKey)
                    }
                } else if playStateChanged || maskLayer.animation(forKey: animationKey) != nil {
                    maskLayer.removeAllAnimations()
                    let finalY = (maskLayer.bounds.height - minHeight) / 2.0
                    let finalPath = CGPath(roundedRect: CGRect(x: 0, y: finalY, width: parent.barThickness, height: minHeight),
                                         cornerWidth: parent.barThickness / 2,
                                         cornerHeight: parent.barThickness / 2,
                                         transform: nil)
                    maskLayer.path = finalPath
                }
            }
        }
    }
}

struct WaveformView: View {
    @EnvironmentObject var musicManager: MusicManager
    @EnvironmentObject var settingsModel: SettingsModel

    @State private var isHovering = false
    @State private var volumeScale: CGFloat = 0.7

    enum TransientIcon: Equatable {
        case paused, played, skippedForward, skippedBackward

        var systemName: String {
            switch self {
            case .paused: return "pause.fill"
            case .played: return "play"
            case .skippedForward: return "forward.end.fill"
            case .skippedBackward: return "backward.end.fill"
            }
        }
    }

    private var barCount: Int {
        min(max(settingsModel.settings.waveformBarCount, 1), 6)
    }

    private var minHeight: CGFloat {
        settingsModel.settings.waveformBarThickness
    }

    private var waveformGradient: LinearGradient {
        LinearGradient(
            gradient: Gradient(colors: [musicManager.leftGradientColor, musicManager.rightGradientColor]),
            startPoint: .top,
            endPoint: .bottom
        )
    }

    var body: some View {
        ZStack {
            if isHovering {
                Button(action: {
                    Task {
                        if musicManager.isPlaying {
                            await musicManager.pause()
                        } else {
                            await musicManager.play()
                        }
                    }
                }) {
                    Image(systemName: musicManager.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(musicManager.accentColor)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .transition(.opacity.combined(with: .scale(scale: 0.8)))

            } else if let icon = musicManager.transientIcon {
                iconBody(systemName: icon.systemName)

            } else if musicManager.isPlaying && !settingsModel.settings.useStaticWaveform {
                animatedWaveformBody

            } else {
                staticWaveformBody
            }
        }
        .frame(width: 22, height: 22, alignment: .center)
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: musicManager.isPlaying)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovering)
        .animation(.default, value: musicManager.transientIcon)
        .onHover { hovering in
            self.isHovering = hovering
        }
        .onAppear(perform: setupInitialState)
        .onReceive(musicManager.volumePublisher.receive(on: RunLoop.main)) { newVolume in
            if settingsModel.settings.musicWaveformIsVolumeSensitive {
                self.volumeScale = CGFloat(newVolume)
            }
        }
        .onChange(of: settingsModel.settings.musicWaveformIsVolumeSensitive) { _, isSensitive in
            if !isSensitive {
                self.volumeScale = 0.7
            } else {
                self.volumeScale = CGFloat(musicManager.systemVolume)
            }
        }
    }

    private func setupInitialState() {
        if settingsModel.settings.musicWaveformIsVolumeSensitive {
            volumeScale = CGFloat(musicManager.systemVolume)
        } else {
            volumeScale = 0.7
        }
    }

    private var animatedWaveformBody: some View {
        CoreAnimationWaveformView(
            isPlaying: musicManager.isPlaying,
            barCount: barCount,
            volumeScale: volumeScale,
            barThickness: settingsModel.settings.waveformBarThickness,
            leftGradientColor: musicManager.leftGradientColor,
            rightGradientColor: musicManager.rightGradientColor
        )
    }

    private var staticWaveformBody: some View {
        let barFill = settingsModel.settings.waveformUseGradient ?
            AnyShapeStyle(waveformGradient) :
            AnyShapeStyle(musicManager.accentColor)

        return HStack(spacing: 3) {
            ForEach(0..<barCount, id: \.self) { _ in
                Capsule()
                    .fill(barFill)
                    .frame(width: settingsModel.settings.waveformBarThickness, height: minHeight)
            }
        }
        .frame(width: 18, height: 22)
        .drawingGroup()
        .transition(.opacity)
    }

    private func iconBody(systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(musicManager.accentColor)
            .transition(.opacity.animation(.easeOut(duration: 0.2)))
    }
}