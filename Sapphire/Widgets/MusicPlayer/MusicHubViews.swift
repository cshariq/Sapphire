//
//  MusicHubViews.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-21

import SwiftUI
import AppKit
import Combine
import AVKit
import AVFoundation

// MARK: - Consolidated from QueueAndPlaylistsView.swift

struct CustomUnavailableView: View {
    let title: String, systemImage: String, description: String?
    init(title: String, systemImage: String, description: String? = nil) {
        self.title = title
        self.systemImage = systemImage
        self.description = description
    }
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: systemImage).font(.system(size: 40, weight: .light)).foregroundColor(.secondary.opacity(0.7))
            Text(title).font(.title3.bold()).foregroundColor(.primary)
            if let description = description { Text(description).font(.subheadline).foregroundColor(.secondary).multilineTextAlignment(.center).padding(.horizontal) }
        }.padding(30).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

fileprivate enum MusicHubPane: Int, CaseIterable {
    case now = 0
    case library = 1
    case discover = 2
    case audio = 3

    var title: String {
        switch self {
        case .now: return "Now"
        case .library: return "Library"
        case .discover: return "Discover"
        case .audio: return "Audio"
        }
    }

    var systemImage: String {
        switch self {
        case .now: return "music.note.list"
        case .library: return "books.vertical.fill"
        case .discover: return "magnifyingglass"
        case .audio: return "hifispeaker.fill"
        }
    }

    static let paneDefaultsKey = "lastSelectedMusicPane"
    private static let unifiedMigrationKey = "musicHubUnifiedV1"

    static func resolveStoredSelection(override: MusicHubPane?) -> Int {
        if let override { return override.rawValue }
        let raw = UserDefaults.standard.integer(forKey: paneDefaultsKey)
        if !UserDefaults.standard.bool(forKey: unifiedMigrationKey) {
            UserDefaults.standard.set(true, forKey: unifiedMigrationKey)
            if raw == 3 { return MusicHubPane.discover.rawValue }
        }
        return MusicHubPane(rawValue: raw)?.rawValue ?? MusicHubPane.now.rawValue
    }
}

struct QueueAndPlaylistsView: View {
    @Binding var navigationStack: [NotchWidgetMode]
    @EnvironmentObject var musicManager: MusicManager

    @State private var selection: Int
    @State private var audioHubSection: MusicAudioHubSection
    @State private var officialQueue: SpotifyQueue?
    @State private var playlists: [SpotifyPlaylist] = []
    @State private var appleMusicQueue: [AppleMusicManager.QueueTrack] = []

    @State private var showSpotifyNotOpenAlert = false
    @State private var queueRefreshTimer: Timer?

    // MARK: - Animation State
    @Namespace private var namespace

    var isLockScreenMode: Bool = false
    private var preferSystemAudioTab: Bool = false

    private var isAppleMusic: Bool { musicManager.lastKnownBundleID == "com.apple.Music" }
    private var isSpotifyActive: Bool { musicManager.isSpotifySourceActive }
    private var isLoggedIn: Bool { musicManager.isPrivateAPIAuthenticated || musicManager.isOfficialAPIAuthenticated }
    private var hubPane: MusicHubPane { MusicHubPane(rawValue: selection) ?? .now }
    private var showLoginGate: Bool { !isLoggedIn && !isAppleMusic && hubPane != .audio }

    private var hubTabs: [MusicHubPane] {
        return MusicHubPane.allCases
    }

    private var availableAudioHubSections: [MusicAudioHubSection] {
        var sections: [MusicAudioHubSection] = []
        if !isAppleMusic && isLoggedIn { sections.append(.spotify) }
        sections.append(contentsOf: [.airplay, .apps, .system])
        return sections
    }

    init(
        navigationStack: Binding<[NotchWidgetMode]>,
        isLockScreenMode: Bool = false,
        openAudio: Bool = false,
        preferSystemAudioTab: Bool = false
    ) {
        self._navigationStack = navigationStack
        self._selection = State(
            initialValue: MusicHubPane.resolveStoredSelection(override: openAudio ? .audio : nil)
        )
        self.isLockScreenMode = isLockScreenMode
        self.preferSystemAudioTab = preferSystemAudioTab

        let music = MusicManager.shared
        let canShowSpotify = music.lastKnownBundleID != "com.apple.Music"
            && (music.isPrivateAPIAuthenticated || music.isOfficialAPIAuthenticated)
        let savedSection = MusicAudioHubSection(rawValue: UserDefaults.standard.integer(forKey: MusicAudioHubSection.defaultsKey)) ?? .apps
        let initialSection: MusicAudioHubSection
        if preferSystemAudioTab {
            initialSection = .system
        } else if savedSection == .spotify && !canShowSpotify {
            initialSection = .apps
        } else {
            initialSection = savedSection
        }
        self._audioHubSection = State(initialValue: initialSection)
    }

    var body: some View {
        VStack(spacing: 15) {
            HStack(spacing: 10) {
                if isAppleMusic {
                    appleMusicHubPill
                } else if isLoggedIn || hubPane == .audio {
                    musicHubUserPill
                }

                Spacer(minLength: 0)

                HStack(spacing: 2) {
                    ForEach(hubTabs, id: \.rawValue) { pane in
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { selection = pane.rawValue }
                        } label: {
                            Label(pane.title, systemImage: pane.systemImage)
                                .labelStyle(.titleAndIcon)
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .padding(.horizontal, 10)
                                .frame(height: 30)
                                .background(
                                    Capsule().fill(selection == pane.rawValue ? MaterialChartPalette.primary.opacity(0.22) : Color.clear)
                                )
                                .foregroundStyle(selection == pane.rawValue ? MaterialChartPalette.primary : MaterialChartPalette.onSurfaceVariant)
                        }
                        .buttonStyle(.plain)
                    }

                    if hubPane == .audio {
                        Capsule()
                            .fill(Color.white.opacity(0.14))
                            .frame(width: 1, height: 16)
                            .padding(.horizontal, 4)

                        ForEach(availableAudioHubSections, id: \.rawValue) { section in
                            Button {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                                    audioHubSection = section
                                }
                            } label: {
                                Label(section.title, systemImage: section.systemImage)
                                    .labelStyle(.titleAndIcon)
                                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                                    .padding(.horizontal, 8)
                                    .frame(height: 30)
                                    .background(
                                        Capsule().fill(
                                            audioHubSection == section
                                                ? MaterialChartPalette.primary.opacity(0.22)
                                                : Color.clear
                                        )
                                    )
                                    .foregroundStyle(
                                        audioHubSection == section
                                            ? MaterialChartPalette.primary
                                            : MaterialChartPalette.onSurfaceVariant
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(3)
                .background(MaterialChartPalette.surfaceContainer, in: Capsule())
            }

            ZStack(alignment: .top) {
                if showLoginGate {
                    LoginPromptView(navigationStack: $navigationStack)
                        .transition(.opacity)
                } else {
                    switch hubPane {
                    case .now:
                        if isAppleMusic {
                            appleMusicNowView.transition(slideTransition(edge: .trailing))
                        } else {
                            queueView.transition(slideTransition(edge: .leading))
                        }
                    case .library:
                        playlistsView.transition(slideTransition(edge: .bottom))
                    case .discover:
                        if isAppleMusic {
                            AppleMusicSearchView(navigationStack: $navigationStack)
                                .transition(slideTransition(edge: .trailing))
                        } else {
                            discoverPane.transition(slideTransition(edge: .trailing))
                        }
                    case .audio:
                        DevicesView(
                            navigationStack: $navigationStack,
                            audioHubSection: $audioHubSection,
                            isLockScreenMode: isLockScreenMode,
                            preferSystemTab: preferSystemAudioTab,
                            embedded: true
                        )
                        .transition(slideTransition(edge: .trailing))
                    }
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: selection)
        }
        .padding(.top, 10)
        .padding(.horizontal, 18)
        .frame(width: 800, height: 350)
        .task { await fetchData(for: hubPane) }
        .onAppear {
            startQueueRefreshTimer()
            Task { await musicManager.setMusicHubOpen(true) }
            if isAppleMusic, hubPane == .now {
            }
            if musicManager.nowPlayingTrack == nil,
               musicManager.title == nil,
               hubPane == .now,
               !isAppleMusic {
                selection = MusicHubPane.library.rawValue
            }
            if audioHubSection == .spotify, !availableAudioHubSections.contains(.spotify) {
                audioHubSection = .apps
            }
        }
        .onDisappear {
            stopQueueRefreshTimer()
            Task { await musicManager.setMusicHubOpen(false) }
        }
        .onChange(of: selection) { _, newValue in
            UserDefaults.standard.set(newValue, forKey: MusicHubPane.paneDefaultsKey)
            Task { await fetchData(for: MusicHubPane(rawValue: newValue) ?? .now) }
        }
        .onChange(of: audioHubSection) { _, newValue in
            UserDefaults.standard.set(newValue.rawValue, forKey: MusicAudioHubSection.defaultsKey)
        }
        .onChange(of: musicManager.nowPlayingTrack?.uri) { _, newURI in
            if newURI == nil, musicManager.title == nil, hubPane == .now, !isAppleMusic {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                    selection = MusicHubPane.library.rawValue
                }
            } else if newURI != nil, hubPane == .now {
                refreshData()
            }
        }
    }

    private var discoverPane: some View {
        SpotifyMusicSearchView(
            navigationStack: $navigationStack,
            onPlaySuccess: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                    selection = MusicHubPane.now.rawValue
                }
            },
            emptyReplacement: { AnyView(discoverView) },
            autofocusSearch: false
        )
    }

    private var hubDisplayName: String {
        if let user = musicManager.spotifyOfficialAPI.userProfile {
            return user.displayName
        }
        if let nativeUser = musicManager.spotifyPrivateAPI.userProfile {
            return nativeUser.profile.friendlyName
        }
        return hubPane == .audio ? "Audio" : "Spotify"
    }

    private var hubFollowerCount: Int? {
        if let count = musicManager.spotifyPrivateAPI.profileFollowerCount { return count }
        return musicManager.spotifyOfficialAPI.userProfile?.followerCount
    }

    private var musicHubUserPill: some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 4) {
                    Text(hubDisplayName)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.primary.opacity(0.9))
                        .lineLimit(1)
                    SpotifyAccountBadge(accountInfo: musicManager.spotifyPrivateAPI.accountInfo)
                    if musicManager.spotifyPrivateAPI.hasUnreadNotifications {
                        Image(systemName: "bell.badge.fill")
                            .font(.system(size: 7, weight: .semibold))
                            .foregroundStyle(.orange.opacity(0.9))
                    }
                }
                if let followers = hubFollowerCount {
                    Text("\(formatCompactCount(followers)) followers")
                        .font(.system(size: 8, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary.opacity(0.85))
                }
            }

            if musicManager.isOfficialAPIAuthenticated || musicManager.isPrivateAPIAuthenticated {
                Capsule()
                    .fill(Color.white.opacity(0.1))
                    .frame(width: 1, height: 14)

                Button {
                    if musicManager.isOfficialAPIAuthenticated {
                        Task { await musicManager.spotifyOfficialAPI.logout() }
                    } else {
                        musicManager.spotifyPrivateAPI.logout()
                    }
                } label: {
                    Text("Log out")
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary.opacity(0.9))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(MaterialChartPalette.surfaceContainer.opacity(0.75), in: Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.06), lineWidth: 1))
        .task(id: musicManager.spotifyPrivateAPI.userProfile?.profile.username) {
            if let username = musicManager.spotifyPrivateAPI.userProfile?.profile.username,
               !username.isEmpty,
               musicManager.spotifyPrivateAPI.profileFollowerCount == nil {
                await musicManager.spotifyPrivateAPI.fetchProfileFollowerCount(username: username)
            }
        }
    }

    private func formatCompactCount(_ value: Int) -> String {
        if value >= 1_000_000 { return String(format: "%.1fM", Double(value) / 1_000_000) }
        if value >= 1_000 { return String(format: "%.1fK", Double(value) / 1_000) }
        return "\(value)"
    }

    private var appleMusicHubPill: some View {
        HStack(spacing: 6) {
            Image("applemusic_logo")
                .resizable()
                .renderingMode(.template)
                .foregroundStyle(Color(red: 1, green: 0.176, blue: 0.333))
                .frame(width: 12, height: 12)

            Text("Apple Music")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary.opacity(0.9))

            if let title = musicManager.title, !title.isEmpty {
                Capsule()
                    .fill(Color.white.opacity(0.1))
                    .frame(width: 1, height: 14)
                Button {
                    musicManager.appleMusic.revealCurrentTrack()
                } label: {
                    Text("Open")
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary.opacity(0.9))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(MaterialChartPalette.surfaceContainer.opacity(0.75), in: Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.06), lineWidth: 1))
    }

    // MARK: - Custom Transitions
    private func slideTransition(edge: Edge) -> AnyTransition {
        let oppositeEdge: Edge = (edge == .leading) ? .trailing : .leading

        return .asymmetric(
            insertion: .move(edge: edge).combined(with: .opacity),
            removal: .move(edge: oppositeEdge).combined(with: .scale(scale: 0.95)).combined(with: .opacity)
        )
    }

    private var hubLongPressNavigation: MusicLongPressNavigation {
        MusicLongPressNavigation(
            openQueue: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                    selection = MusicHubPane.now.rawValue
                }
            },
            openDevices: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                    selection = MusicHubPane.audio.rawValue
                    if availableAudioHubSections.contains(.spotify) {
                        audioHubSection = .spotify
                    }
                }
            }
        )
    }

    private func refreshData() {
        Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            await fetchData(for: hubPane)
        }
    }

    private func fetchData(for pane: MusicHubPane) async {
        if isAppleMusic {
            let apple = musicManager.appleMusic
            if !apple.isMusicKitAuthorized, apple.isMusicKitConfigured {
                await apple.requestAuthorization()
            }
            if apple.isMusicKitAuthorized {
                await apple.refreshPlaylists()
            }
            self.playlists = apple.fetchPlaylists()
            self.appleMusicQueue = await apple.fetchUpNextTracks()
            return
        }

        musicManager.spotifyPrivateAPI.bootstrapIfNeeded(policy: .onDemand)

        guard musicManager.isPrivateAPIAuthenticated else {
            self.officialQueue = await musicManager.spotifyOfficialAPI.fetchQueue()
            self.playlists = await musicManager.spotifyOfficialAPI.fetchPlaylists()
            return
        }

        switch pane {
        case .now:
            await musicManager.spotifyPrivateAPI.refreshQueueForUI()
            await musicManager.ensureSpotifyPlayerExtrasLoaded(force: true)
        case .library:
            async let library: Void = musicManager.spotifyPrivateAPI.fetchUserLibrary()
            async let profile: Void = {
                if musicManager.spotifyPrivateAPI.accountInfo == nil {
                    await musicManager.spotifyPrivateAPI.refreshExtendedSessionData()
                }
            }()
            _ = await (library, profile)
        case .discover:
            if musicManager.spotifyPrivateAPI.homeSections.isEmpty {
                _ = await musicManager.spotifyPrivateAPI.fetchHomeSections()
            }
        case .audio:
            break
        }
    }

    private func startQueueRefreshTimer() {
        stopQueueRefreshTimer()
        queueRefreshTimer = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: true) { _ in
            Task { @MainActor in
                let manager = MusicManager.shared
                guard manager.isPrivateAPIAuthenticated else { return }
                let paneRaw = UserDefaults.standard.integer(forKey: MusicHubPane.paneDefaultsKey)
                let pane = MusicHubPane(rawValue: paneRaw) ?? .now
                switch pane {
                case .now:
                    await manager.spotifyPrivateAPI.refreshQueueForUI()
                case .library where manager.spotifyPrivateAPI.nativePlaylists.isEmpty:
                    await manager.spotifyPrivateAPI.fetchUserLibrary()
                default:
                    break
                }
            }
        }
    }

    private func stopQueueRefreshTimer() {
        queueRefreshTimer?.invalidate()
        queueRefreshTimer = nil
    }

    @ViewBuilder
    private var queueView: some View {
        if isSpotifyActive && musicManager.isPrivateAPIAuthenticated {
            nativeQueueView
        } else if isSpotifyActive {
            officialQueueView
        } else {
            appleMusicNowView
        }
    }

    private var appleMusicNowView: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 14) {
                    if let artwork = musicManager.artwork {
                        Image(nsImage: artwork)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 88, height: 88)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .shadow(color: musicManager.accentColor.opacity(0.3), radius: 8, y: 4)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(musicManager.title ?? "Not Playing")
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .lineLimit(2)
                            Text(musicManager.artist ?? "Apple Music")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            if let album = musicManager.album, !album.isEmpty,
                               album != musicManager.title {
                                Text(album)
                                    .font(.system(size: 11, weight: .medium, design: .rounded))
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                            }
                        }

                        HStack(spacing: 8) {
                            if let playCount = musicManager.applePlayCount {
                                PlayCountIndicator(playCount: playCount)
                            }
                            if let popularity = musicManager.applePopularity {
                                PopularityIndicator(popularity: popularity)
                            }
                        }
                        .padding(.top, 2)

                        HStack(spacing: 10) {
                            Button {
                                Task {
                                    await musicManager.toggleLike()
                                    refreshData()
                                }
                            } label: {
                                Image(systemName: musicManager.isLiked ? "heart.fill" : "heart")
                                    .font(.system(size: 13))
                                    .foregroundStyle(musicManager.isLiked ? Color.pink : Color.secondary)
                            }
                            .buttonStyle(.plain)
                            .help(musicManager.isLiked ? "Unlike" : "Love this song")

                            Button {
                                Task {
                                    await musicManager.toggleShuffle()
                                    refreshData()
                                }
                            } label: {
                                Image(systemName: "shuffle")
                                    .font(.system(size: 12))
                                    .foregroundStyle(musicManager.shuffleState ? musicManager.accentColor : Color.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Shuffle")

                            Button {
                                Task {
                                    await musicManager.cycleRepeatMode()
                                    refreshData()
                                }
                            } label: {
                                Image(systemName: musicManager.repeatState == .track ? "repeat.1" : "repeat")
                                    .font(.system(size: 12))
                                    .foregroundStyle(musicManager.repeatState != .off ? musicManager.accentColor : Color.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Repeat")

                            Spacer(minLength: 0)

                            Button {
                                musicManager.appleMusic.revealCurrentTrack()
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.up.right.square")
                                        .font(.system(size: 11))
                                    Text("Open")
                                        .font(.system(size: 10, weight: .medium, design: .rounded))
                                }
                                .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Show in Apple Music")
                        }
                    }
                }

                ActionButtonsView(onAction: refreshData, longPressNavigation: hubLongPressNavigation)

                if !musicManager.appleSuggestedTracks.isEmpty {
                    materialExpressiveCard(title: "More Like This", systemImage: "sparkles", accent: MaterialChartPalette.secondary) {
                        LazyVStack(spacing: 4) {
                            ForEach(musicManager.appleSuggestedTracks.prefix(5)) { track in
                                SuggestedAppleTrackRow(track: track) {
                                    Task { _ = musicManager.appleMusic.playTrack(persistentID: track.id) }
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            materialExpressiveCard(title: "Up Next", systemImage: "list.bullet", accent: MaterialChartPalette.primary) {
                if appleMusicQueue.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "music.note.list")
                            .font(.system(size: 20, weight: .light))
                            .foregroundStyle(.tertiary)
                        Text("Nothing queued in Apple Music.")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                } else {
                    ScrollView(showsIndicators: false) {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(appleMusicQueue) { track in
                                Button {
                                    Task {
                                        _ = musicManager.appleMusic.playTrack(persistentID: track.id)
                                        refreshData()
                                    }
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: "music.note")
                                            .font(.system(size: 9))
                                            .foregroundStyle(.tertiary)
                                            .frame(width: 14)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(track.title)
                                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                                .lineLimit(1)
                                            Text(track.artist)
                                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }
                                        Spacer(minLength: 0)
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.bottom, 12)
                    }
                }
            }
            .frame(width: 292, alignment: .top)
        }
        .padding(.leading, 2)
    }

    @ViewBuilder
    private var nativeQueueView: some View {
        let hasConnectTrack = musicManager.nowPlayingTrack != nil
        if hasConnectTrack, let nowPlaying = musicManager.nowPlayingTrack {
            nativeQueueContent(nowPlaying: nowPlaying)
        } else if musicManager.title != nil {
            nativeQueueBootstrappingView
        } else {
            CustomUnavailableView(title: "Nothing Playing", systemImage: "speaker.slash.fill", description: "Start playing music in Spotify to see artist picks, concerts, and your queue.")
        }
    }

    private var nativeQueueBootstrappingView: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(musicManager.title ?? "Now Playing")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .lineLimit(2)
                    Text(musicManager.artist ?? "Spotify")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let artwork = musicManager.artwork {
                    Image(nsImage: artwork)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 88, height: 88)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                ActionButtonsView(onAction: refreshData, longPressNavigation: hubLongPressNavigation)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            materialExpressiveCard(title: "Loading…", systemImage: "arrow.clockwise", accent: MaterialChartPalette.primary) {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Connecting to Spotify…")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            }
            .frame(width: 292, alignment: .top)
        }
        .padding(.leading, 2)
        .task {
            musicManager.spotifyPrivateAPI.bootstrapIfNeeded(policy: .onDemand)
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await fetchData(for: .now)
        }
    }

    @ViewBuilder
    private func nativeQueueContent(nowPlaying: PlayerState.Track) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                            VStack(alignment: .leading, spacing: 14) {
                                Color.clear
                                    .frame(height: 0)
                                    .id("now-left-top")

                                nowPlayingHeroCard(nowPlaying)

                                if !musicManager.spotifyPrivateAPI.similarAlbums.isEmpty {
                                    materialExpressiveCard(title: "Similar Albums", systemImage: "square.stack", accent: MaterialChartPalette.tertiary) {
                                        ScrollView(.horizontal, showsIndicators: false) {
                                            HStack(spacing: 12) {
                                                ForEach(musicManager.spotifyPrivateAPI.similarAlbums.prefix(10)) { album in
                                                    SimilarAlbumCard(album: album, onPlay: handlePlaybackResult)
                                                }
                                            }
                                            .padding(.leading, 2)
                                            .padding(.trailing, 4)
                                        }
                                    }
                                }

                                if !musicManager.spotifyPrivateAPI.relatedTracks.isEmpty {
                                    materialExpressiveCard(title: "More Like This", systemImage: "sparkles", accent: MaterialChartPalette.secondary) {
                                        LazyVStack(spacing: 4) {
                                            ForEach(musicManager.spotifyPrivateAPI.relatedTracks.prefix(6)) { track in
                                                RecommendedTrackRow(track: track, onPlay: handlePlaybackResult)
                                            }
                                        }
                                    }
                                }

                                if !musicManager.spotifyPrivateAPI.artistConcerts.isEmpty {
                                    materialExpressiveCard(title: "Nearby Concerts", systemImage: "ticket.fill", accent: MaterialChartPalette.error) {
                                        ScrollView(.horizontal, showsIndicators: false) {
                                            HStack(spacing: 12) {
                                                ForEach(musicManager.spotifyPrivateAPI.artistConcerts.prefix(8)) { concert in
                                                    ConcertCard(concert: concert)
                                                }
                                            }
                                            .padding(.leading, 2)
                                            .padding(.trailing, 4)
                                        }
                                    }
                                }

                                if !musicManager.spotifyPrivateAPI.trackArtistCredits.isEmpty {
                                    materialExpressiveCard(title: "Credits", systemImage: "person.2.fill", accent: MaterialChartPalette.secondary) {
                                        ScrollView(.horizontal, showsIndicators: false) {
                                            HStack(spacing: 10) {
                                                ForEach(musicManager.spotifyPrivateAPI.trackArtistCredits) { credit in
                                                    Button {
                                                        navigationStack.append(
                                                            .musicArtistDetail(uri: credit.uri, name: credit.name)
                                                        )
                                                    } label: {
                                                        VStack(alignment: .leading, spacing: 2) {
                                                            Text(credit.name).font(.caption.bold()).lineLimit(1)
                                                            if let role = credit.role, !role.isEmpty {
                                                                Text(role).font(.caption2).foregroundColor(.secondary).lineLimit(1)
                                                            }
                                                        }
                                                        .padding(.horizontal, 10)
                                                        .padding(.vertical, 8)
                                                    }
                                                    .buttonStyle(.plain)
                                                }
                                            }
                                            .padding(.leading, 2)
                                            .padding(.trailing, 4)
                                        }
                                    }
                                }

                                if let artist = musicManager.spotifyPrivateAPI.nowPlayingArtist, !artist.merch.isEmpty {
                                    materialExpressiveCard(title: "Merch", systemImage: "bag.fill", accent: MaterialChartPalette.warning) {
                                        ScrollView(.horizontal, showsIndicators: false) {
                                            HStack(spacing: 12) {
                                                ForEach(artist.merch.prefix(8)) { item in
                                                    MerchCard(item: item)
                                                }
                                            }
                                            .padding(.leading, 2)
                                            .padding(.trailing, 4)
                                        }
                                    }
                                }
                            }
                            .padding(.leading, 4)
                            .padding(.trailing, 2)
                            .padding(.top, 0)
                            .padding(.bottom, 28)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                        }
                        .onAppear {
                            DispatchQueue.main.async {
                                proxy.scrollTo("now-left-top", anchor: .top)
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                                proxy.scrollTo("now-left-top", anchor: .top)
                            }
                        }
                    }
                    .mask(fadeMask)

                    materialExpressiveCard(title: "Up Next", systemImage: "list.bullet", accent: MaterialChartPalette.primary) {
                        if musicManager.nativeQueue.isEmpty {
                            Text("Nothing queued — add tracks from Library or suggestions.")
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 6)
                            Spacer(minLength: 0)
                        } else {
                            ScrollView(showsIndicators: false) {
                                LazyVStack(spacing: 2) {
                                    ForEach(musicManager.nativeQueue, id: \.uid) { track in
                                        NativeQueueTrackRow(track: track, onPlay: handlePlaybackResult)
                                            .onAppear {
                                                Task(priority: .utility) {
                                                    await musicManager.spotifyPrivateAPI.hydrateQueueItemIfNeeded(uid: track.uid)
                                                }
                                            }
                                    }
                                }
                                .padding(.bottom, 12)
                            }
                        }
                    }
                    .frame(width: 292, alignment: .top)
                }
                .padding(.leading, 2)
                .task {
                    await musicManager.spotifyPrivateAPI.refreshQueueForUI()
                }
    }

    private func nowPlayingHeroCard(_ nowPlaying: PlayerState.Track) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(nowPlaying.metadata?.title ?? "Unknown Track")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .lineLimit(2)

                Button {
                    openArtistFromNowPlaying(fallbackName: nowPlaying.metadata?.artistName)
                } label: {
                    HStack(spacing: 4) {
                        Text(nowPlaying.metadata?.artistName ?? "Unknown Artist")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
                .disabled(musicManager.currentSpotifyArtistNavigation() == nil
                          && (nowPlaying.metadata?.artistUri?.isEmpty ?? true))
            }

            HStack(alignment: .center, spacing: 14) {
                CachedAsyncImage(url: nowPlaying.metadata?.imageURL) { $0.resizable().aspectRatio(contentMode: .fill) }
                    placeholder: { ZStack { MaterialChartPalette.surfaceVariant; Image(systemName: "music.note") } }
                    .frame(width: 88, height: 88)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                VStack(alignment: .leading, spacing: 8) {
                    ActiveDeviceView()

                    if let artist = musicManager.spotifyPrivateAPI.nowPlayingArtist {
                        Button {
                            navigationStack.append(.musicArtistDetail(uri: artist.uri, name: artist.name))
                        } label: {
                            HStack(spacing: 6) {
                                if let url = artist.avatarURL ?? artist.headerImageURL {
                                    CachedAsyncImage(url: url) { $0.resizable().aspectRatio(contentMode: .fill) } placeholder: {
                                        Circle().fill(MaterialChartPalette.surfaceVariant)
                                    }
                                    .frame(width: 18, height: 18)
                                    .clipShape(Circle())
                                }
                                Text(artist.name)
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                    .lineLimit(1)
                                if artist.isVerified {
                                    Image(systemName: "checkmark.seal.fill")
                                        .font(.system(size: 9))
                                        .foregroundStyle(.cyan)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }

                    HStack(spacing: 10) {
                        if let artist = musicManager.spotifyPrivateAPI.nowPlayingArtist,
                           let listeners = artist.monthlyListeners ?? artist.followers {
                            Text("\(listeners.formatted()) monthly")
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .foregroundStyle(.tertiary)
                        }
                        if let playCount = musicManager.playCountValue {
                            PlayCountIndicator(playCount: playCount)
                        } else if let popularity = musicManager.popularity {
                            PopularityIndicator(popularity: popularity)
                        } else if let fetchedPopularity = musicManager.fetchedSpotifyPopularity {
                            PopularityIndicator(popularity: fetchedPopularity)
                        }
                    }
                }
                Spacer(minLength: 0)
            }

                    ActionButtonsView(onAction: refreshData, longPressNavigation: hubLongPressNavigation)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(MaterialChartPalette.cardGradient(for: musicManager.accentColor))
        )
        .id(nowPlaying.uri)
    }

    private func openArtistFromNowPlaying(fallbackName: String?) {
        if let nav = musicManager.currentSpotifyArtistNavigation() {
            navigationStack.append(.musicArtistDetail(uri: nav.uri, name: nav.name))
            return
        }
        if let uri = musicManager.nowPlayingTrack?.metadata?.artistUri
            ?? musicManager.spotifyPrivateAPI.playerState?.track?.metadata?.artistUri,
           !uri.isEmpty {
            navigationStack.append(
                .musicArtistDetail(uri: uri, name: fallbackName ?? musicManager.artist ?? "Artist")
            )
        }
    }

    private func materialExpressiveCard<Content: View>(
        title: String,
        systemImage: String,
        accent: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(accent)
                .labelStyle(.titleAndIcon)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(MaterialChartPalette.surface.opacity(0.45))
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(MaterialChartPalette.cardGradient(for: accent))
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var fadeMask: some View {
        LinearGradient(
            gradient: Gradient(stops: [
                .init(color: .black, location: 0),
                .init(color: .black, location: 0.92),
                .init(color: .clear, location: 1.0)
            ]),
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var officialQueueView: some View {
        HStack(alignment: .top, spacing: 20) {
            if let queue = officialQueue, let nowPlaying = queue.currentlyPlaying {
                VStack(alignment: .leading, spacing: 8) {
                     CachedAsyncImage(url: nowPlaying.imageURL) { $0.resizable().aspectRatio(contentMode: .fit) }
                        placeholder: { ZStack { Color.secondary.opacity(0.3); Image(systemName: "music.note") } }
                        .frame(width: 80, height: 80)
                        .cornerRadius(8).shadow(color: .black.opacity(0.4), radius: 6, y: 3)

                    VStack(alignment: .leading, spacing: 0) {
                        Marquee {
                            Text(nowPlaying.name)
                                .font(.headline.bold())
                                .lineLimit(1)
                        }

                        Marquee {
                            Text(nowPlaying.artists.map(\.name).joined(separator: ", "))
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }

                    HStack(spacing: 8) {
                        if let playCount = musicManager.playCountValue {
                            PlayCountIndicator(playCount: playCount)
                        } else if let popularity = musicManager.popularity {
                            PopularityIndicator(popularity: popularity)
                        } else if let fetchedPopularity = musicManager.fetchedSpotifyPopularity {
                            PopularityIndicator(popularity: fetchedPopularity)
                        }
                    }

                    Spacer(minLength: 0)
                    ActionButtonsView(onAction: refreshData, longPressNavigation: hubLongPressNavigation)
                }
                .frame(width: 150)
                .padding(.bottom, 10)
                .id(nowPlaying.uri)
                .transition(.opacity)

                VStack(alignment: .leading, spacing: 0) {
                    SectionHeader(title: "Next Up").padding(.bottom, 5)
                    if !queue.queue.isEmpty {
                        ScrollView(showsIndicators: false) {
                            LazyVStack(alignment: .leading, spacing: 8) {
                                ForEach(queue.queue) { track in QueueTrackRow(track: track, onPlay: handlePlaybackResult) }
                            }
                            .padding(.bottom, 30)
                        }
                        .mask(LinearGradient(gradient: Gradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.95), .init(color: .clear, location: 1.0)]), startPoint: .top, endPoint: .bottom))
                    } else { CustomUnavailableView(title: "No Songs Up Next", systemImage: "music.note.list", description: "Add songs to your queue to see them here.") }
                }
            } else { CustomUnavailableView(title: "Queue Unavailable", systemImage: "speaker.slash.fill", description: "Start playing music with a Premium account to view your queue.") }
        }

    }

    private var playlistsView: some View { libraryView }

    private var libraryView: some View {
        VStack(spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Library")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                    Text(isAppleMusic ? "Your Apple Music playlists" : "Playlists sorted by Spotify")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if musicManager.isPrivateAPIAuthenticated && !isAppleMusic {
                    let orders = musicManager.spotifyPrivateAPI.librarySortOrders.isEmpty
                        ? [
                            UserLibraryResponse.SortOrder(id: "Recents", name: "Recents"),
                            UserLibraryResponse.SortOrder(id: "Recently Added", name: "Recently Added"),
                            UserLibraryResponse.SortOrder(id: "Alphabetical", name: "Alphabetical"),
                            UserLibraryResponse.SortOrder(id: "Creator", name: "Creator")
                          ]
                        : musicManager.spotifyPrivateAPI.librarySortOrders
                    Menu {
                        ForEach(orders) { order in
                            Button {
                                Task {
                                    await musicManager.spotifyPrivateAPI.fetchUserLibrary(order: order.id)
                                    await musicManager.spotifyPrivateAPI.logSortTelemetry()
                                }
                            } label: {
                                if musicManager.spotifyPrivateAPI.selectedLibrarySortOrderId == order.id {
                                    Label(order.name, systemImage: "checkmark")
                                } else {
                                    Text(order.name)
                                }
                            }
                        }
                    } label: {
                        Label(
                            musicManager.spotifyPrivateAPI.selectedLibrarySortOrderId,
                            systemImage: "arrow.up.arrow.down.circle.fill"
                        )
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(MaterialChartPalette.primary.opacity(0.18), in: Capsule())
                        .foregroundStyle(MaterialChartPalette.primary)
                    }
                    .menuStyle(.borderlessButton)
                } else if isAppleMusic {
                    Button { Task { await fetchData(for: .library) } } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(MaterialChartPalette.primary.opacity(0.18), in: Capsule())
                            .foregroundStyle(MaterialChartPalette.primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 4)

            let currentPlaylists = isAppleMusic
                ? playlists
                : (musicManager.isPrivateAPIAuthenticated ? musicManager.spotifyPrivateAPI.nativePlaylists : playlists)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    if currentPlaylists.isEmpty {
                        CustomUnavailableView(
                            title: "No Playlists Found",
                            systemImage: "music.mic",
                            description: isAppleMusic ? "Add playlists in Apple Music to see them here." : nil
                        )
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 12)], spacing: 12) {
                            ForEach(currentPlaylists) { playlist in
                                let isPlaying = playlist.uri == musicManager.spotifyPrivateAPI.currentContextURI
                                PlaylistGridCard(
                                    playlist: playlist,
                                    isPlaying: isPlaying,
                                    onTap: { navigateToPlaylist(playlist) },
                                    onPlay: {
                                        if isAppleMusic {
                                            Task {
                                                let ok = musicManager.appleMusic.playPlaylist(persistentID: playlist.id)
                                                if ok {
                                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                                                        selection = MusicHubPane.now.rawValue
                                                    }
                                                } else {
                                                    musicManager.appleMusic.revealCurrentTrack()
                                                }
                                            }
                                        } else {
                                            Task {
                                                let result = await musicManager.play(contextUri: playlist.uri)
                                                handlePlaybackResult(result)
                                            }
                                        }
                                    }
                                )
                            }
                        }
                        .padding(.horizontal, 4)
                    }
                }
                .padding(.leading, 4)
                .padding(.bottom, 30)
            }
            .mask(fadeMask)
        }
    }

    private var discoverView: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                if let greeting = musicManager.spotifyPrivateAPI.homeGreeting, !greeting.isEmpty {
                    Text(greeting)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .padding(.horizontal, 4)
                }

                HStack(spacing: 10) {
                    if musicManager.spotifyPrivateAPI.jamSessionActive {
                        Label("Jam Active", systemImage: "person.3.fill")
                            .font(.caption.bold())
                            .foregroundColor(.green)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Color.green.opacity(0.15))
                            .clipShape(Capsule())
                    }
                    if musicManager.spotifyPrivateAPI.libraryImportEligible {
                        Label("Import Available", systemImage: "square.and.arrow.down")
                            .font(.caption.bold())
                            .foregroundColor(.blue)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Color.blue.opacity(0.15))
                            .clipShape(Capsule())
                    }
                }
                .padding(.horizontal, 4)

                if !musicManager.spotifyPrivateAPI.homeSections.isEmpty {
                    ForEach(Array(musicManager.spotifyPrivateAPI.homeSections.prefix(24).enumerated()), id: \.element.id) { index, section in
                        let accent = [MaterialChartPalette.primary, MaterialChartPalette.secondary, MaterialChartPalette.tertiary, MaterialChartPalette.warning][index % 4]
                        VStack(alignment: .leading, spacing: 10) {
                            SectionHeader(title: section.title ?? "For You")
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(section.items.prefix(24)) { item in
                                        Button {
                                            openHomeItem(item)
                                        } label: {
                                            VStack(alignment: .leading, spacing: 6) {
                                                CachedAsyncImage(url: item.imageURL) { $0.resizable().aspectRatio(contentMode: .fill) } placeholder: {
                                                    ZStack {
                                                        MaterialChartPalette.surfaceVariant
                                                        Image(systemName: "music.note.list")
                                                    }
                                                }
                                                .frame(width: 110, height: 110)
                                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                                Text(item.name)
                                                    .font(.caption.bold())
                                                    .lineLimit(2)
                                                    .frame(width: 110, alignment: .leading)
                                                if let subtitle = item.subtitle, !subtitle.isEmpty {
                                                    Text(subtitle)
                                                        .font(.caption2)
                                                        .foregroundStyle(.secondary)
                                                        .lineLimit(1)
                                                        .frame(width: 110, alignment: .leading)
                                                }
                                            }
                                        }
                                        .buttonStyle(.plain)
                                        .contentShape(Rectangle())
                                        .contextMenu {
                                            Button("Play") {
                                                Task { handlePlaybackResult(await musicManager.play(contextUri: item.uri)) }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        .padding(12)
                        .background(
                            ZStack {
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(MaterialChartPalette.surfaceContainer)
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(MaterialChartPalette.cardGradient(for: accent))
                            }
                        )
                        .padding(.horizontal, 4)
                    }
                } else {
                    if !musicManager.spotifyPrivateAPI.recentlyPlayedItems.isEmpty {
                        SectionHeader(title: "Recently Played")
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(musicManager.spotifyPrivateAPI.recentlyPlayedItems) { item in
                                    RecentlyPlayedCard(item: item) {
                                        if let playlist = musicManager.spotifyPrivateAPI.nativePlaylists.first(where: { $0.uri == item.uri }) {
                                            navigateToPlaylist(playlist)
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal)
                        }
                    }

                    if !musicManager.spotifyPrivateAPI.popularReleases.isEmpty {
                        SectionHeader(title: "Popular Releases")
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(musicManager.spotifyPrivateAPI.popularReleases) { release in
                                    PopularReleaseCard(release: release) { result in
                                        handlePlaybackResult(result)
                                    }
                                }
                            }
                            .padding(.horizontal)
                        }
                    }

                    if !musicManager.spotifyPrivateAPI.playlistRecommendations.isEmpty {
                        SectionHeader(title: "Made For You")
                        LazyVStack(spacing: 8) {
                            ForEach(musicManager.spotifyPrivateAPI.playlistRecommendations) { track in
                                RecommendedTrackRow(track: track) { result in
                                    handlePlaybackResult(result)
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                }

                if musicManager.spotifyPrivateAPI.homeSections.isEmpty
                    && musicManager.spotifyPrivateAPI.recentlyPlayedItems.isEmpty
                    && musicManager.spotifyPrivateAPI.popularReleases.isEmpty
                    && musicManager.spotifyPrivateAPI.playlistRecommendations.isEmpty {
                    CustomUnavailableView(
                        title: "Your Home",
                        systemImage: "house.fill",
                        description: "Home shelves from Spotify will appear here once loaded."
                    )
                }
            }
            .padding(.bottom, 30)
        }
        .task {
            if musicManager.isPrivateAPIAuthenticated {
                async let home = musicManager.spotifyPrivateAPI.fetchHomeSections()
                async let jam = musicManager.spotifyPrivateAPI.fetchJamSession()
                async let importEligible = musicManager.spotifyPrivateAPI.fetchLibraryImportEligible()
                if musicManager.spotifyPrivateAPI.recentlyPlayedItems.isEmpty {
                    let recentURIs = musicManager.spotifyPrivateAPI.nativePlaylists.prefix(6).map(\.uri)
                    if !recentURIs.isEmpty {
                        _ = await musicManager.spotifyPrivateAPI.fetchRecentlyPlayedEntities(uris: Array(recentURIs))
                    }
                }
                _ = await (home, jam, importEligible)
            }
        }
    }

    private func openHomeItem(_ item: SpotifyHomeItem) {
        if item.uri.contains(":artist:") {
            let name = item.name
            navigationStack.append(.musicArtistDetail(uri: item.uri, name: name))
            return
        }
        if item.uri.contains(":album:") {
            navigationStack.append(.musicAlbumDetail(uri: item.uri, name: item.name))
            return
        }
        if item.uri.contains(":playlist:") {
            let id = item.uri.components(separatedBy: ":").last ?? item.id
            let playlist = SpotifyPlaylist(
                id: id,
                name: item.name,
                uri: item.uri,
                images: item.imageURL.map { [SpotifyImage(url: $0.absoluteString)] } ?? [],
                owner: SpotifyUserSimple(id: "", displayName: item.subtitle ?? "Spotify", images: nil),
                collaborators: nil
            )
            navigateToPlaylist(playlist)
            return
        }
        Task {
            handlePlaybackResult(await musicManager.play(contextUri: item.uri))
        }
    }

    private func navigateToPlaylist(_ playlist: SpotifyPlaylist) {
        if isLockScreenMode {
            navigationManager.navigateTo(.playlistDetail(playlist))
        } else {
            navigationStack.append(.musicPlaylistDetail(playlist))
        }
    }

    @EnvironmentObject private var navigationManager: LockScreenNavigationManager

    private func handlePlaybackResult(_ result: PlaybackResult) {
        if case .requiresSpotifyAppOpen = result { showSpotifyNotOpenAlert = true }
        if case .success = result {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                selection = MusicHubPane.now.rawValue
            }
        }
        refreshData()
    }

}

// MARK: - Subviews

struct ActionButtonsView: View {
    @EnvironmentObject var musicManager: MusicManager
    @EnvironmentObject var settings: SettingsModel
    let onAction: () -> Void
    var longPressNavigation: MusicLongPressNavigation = .notifications

    @State private var holdFeedbackAction: MusicLongPressAction?
    @State private var holdFeedbackIcon: String?
    @State private var holdFeedbackColor: Color = .primary
    @State private var holdFeedbackRestoreTask: Task<Void, Never>?
    @State private var holdFeedbackButtonID: String?
    @State private var holdActionInFlight = false

    private func performAction(_ action: @escaping () async -> Void) {
        Task {
            await action()
            onAction()
        }
    }

    private func accessoryHoldHandler(for target: MusicLongPressTarget) -> (() -> Void)? {
        guard let action = settings.settings.resolvedAccessoryHoldAction(for: target) else { return nil }
        return {
            Task { @MainActor in
                guard !holdActionInFlight else { return }
                holdActionInFlight = true
                defer { holdActionInFlight = false }
                await musicManager.performLongPressAction(action, navigation: longPressNavigation)
                refreshHoldFeedbackIcon()
                onAction()
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
                onAction()
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

    var body: some View {
        VStack(spacing: 15) {
            HStack(spacing: 30) {
                SeekButton(
                    systemName: "backward.fill",
                    onTap: { performAction(musicManager.previousTrack) },
                    onSeek: { isForward in Task { await musicManager.seek(by: isForward ? 5.0 : -5.0) } },
                    onLongPressAction: skipHoldClosure(for: .previous),
                    holdAction: skipHoldAction(for: .previous),
                    onHoldBegan: { action in beginHoldFeedback(action: action, buttonID: "previous") },
                    onHoldEnded: endHoldFeedback,
                    displayedSystemName: holdFeedbackButtonID == "previous" ? holdFeedbackIcon : nil
                )
                .foregroundStyle(holdFeedbackButtonID == "previous" ? holdFeedbackColor : .primary)

                LongPressControlButton(
                    onTap: {
                        performAction {
                            if musicManager.isPlaying {
                                await musicManager.pause()
                            } else {
                                await musicManager.play()
                            }
                        }
                    },
                    onLongPress: accessoryHoldHandler(for: .playPause),
                    onHoldBegan: { action in beginHoldFeedback(action: action, buttonID: "playPause") },
                    holdAction: settings.settings.resolvedAccessoryHoldAction(for: .playPause),
                    onHoldEnded: endHoldFeedback
                ) {
                    Image(systemName: holdFeedbackButtonID == "playPause"
                          ? (holdFeedbackIcon ?? (musicManager.isPlaying ? "pause.fill" : "play.fill"))
                          : (musicManager.isPlaying ? "pause.fill" : "play.fill"))
                        .font(.system(size: 20))
                        .contentTransition(.symbolEffect(.replace))
                }
                .foregroundStyle(holdFeedbackButtonID == "playPause" ? holdFeedbackColor : .primary)
                .animation(.easeInOut(duration: 0.15), value: holdFeedbackIcon)

                SeekButton(
                    systemName: "forward.fill",
                    onTap: { performAction(musicManager.nextTrack) },
                    onSeek: { isForward in Task { await musicManager.seek(by: isForward ? 5.0 : -5.0) } },
                    onLongPressAction: skipHoldClosure(for: .next),
                    holdAction: skipHoldAction(for: .next),
                    onHoldBegan: { action in beginHoldFeedback(action: action, buttonID: "next") },
                    onHoldEnded: endHoldFeedback,
                    displayedSystemName: holdFeedbackButtonID == "next" ? holdFeedbackIcon : nil
                )
                .foregroundStyle(holdFeedbackButtonID == "next" ? holdFeedbackColor : .primary)

                Spacer()
            }
            .font(.system(size: 16))

            HStack(spacing: 28) {
                LongPressControlButton(
                    onTap: { performAction(musicManager.toggleLike) },
                    onLongPress: accessoryHoldHandler(for: .like),
                    onHoldBegan: { action in beginHoldFeedback(action: action, buttonID: "like") },
                    holdAction: settings.settings.resolvedAccessoryHoldAction(for: .like),
                    onHoldEnded: endHoldFeedback
                ) {
                    Image(systemName: holdFeedbackButtonID == "like"
                          ? (holdFeedbackIcon ?? (musicManager.isLiked ? "heart.fill" : "heart"))
                          : (musicManager.isLiked ? "heart.fill" : "heart"))
                        .contentTransition(.symbolEffect(.replace))
                }
                .foregroundColor(holdFeedbackButtonID == "like"
                                 ? holdFeedbackColor
                                 : (musicManager.isLiked ? .pink : .primary))
                .animation(.easeInOut(duration: 0.15), value: holdFeedbackIcon)

                LongPressControlButton(
                    onTap: { performAction(musicManager.toggleShuffle) },
                    onLongPress: accessoryHoldHandler(for: .shuffle),
                    onHoldBegan: { action in beginHoldFeedback(action: action, buttonID: "shuffle") },
                    holdAction: settings.settings.resolvedAccessoryHoldAction(for: .shuffle),
                    onHoldEnded: endHoldFeedback
                ) {
                    Image(systemName: holdFeedbackButtonID == "shuffle"
                          ? (holdFeedbackIcon ?? (musicManager.spotifyPrivateAPI.isSmartShuffleActive ? "sparkles" : "shuffle"))
                          : (musicManager.spotifyPrivateAPI.isSmartShuffleActive ? "sparkles" : "shuffle"))
                        .contentTransition(.symbolEffect(.replace))
                }
                .foregroundColor(
                    holdFeedbackButtonID == "shuffle"
                        ? holdFeedbackColor
                        : (musicManager.spotifyPrivateAPI.isSmartShuffleActive
                            ? .purple
                            : (musicManager.shuffleState ? .green : .primary))
                )
                .animation(.easeInOut(duration: 0.15), value: holdFeedbackIcon)

                LongPressControlButton(
                    onTap: { performAction(musicManager.cycleRepeatMode) },
                    onLongPress: accessoryHoldHandler(for: .repeatMode),
                    onHoldBegan: { action in beginHoldFeedback(action: action, buttonID: "repeat") },
                    holdAction: settings.settings.resolvedAccessoryHoldAction(for: .repeatMode),
                    onHoldEnded: endHoldFeedback
                ) {
                    Image(systemName: holdFeedbackButtonID == "repeat"
                          ? (holdFeedbackIcon ?? (musicManager.repeatState == .track ? "repeat.1" : "repeat"))
                          : (musicManager.repeatState == .track ? "repeat.1" : "repeat"))
                        .contentTransition(.symbolEffect(.replace))
                }
                .foregroundColor(holdFeedbackButtonID == "repeat"
                                 ? holdFeedbackColor
                                 : (musicManager.repeatState != .off ? .green : .primary))
                .animation(.easeInOut(duration: 0.15), value: holdFeedbackIcon)

                Spacer()
            }
            .font(.system(size: 14))
        }
        .buttonStyle(.plain)
    }
}

struct TabButton: View {
    let title: String, systemImage: String, isSelected: Bool, action: () -> Void
    var body: some View {
        Button {
            action()
        } label: {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .background(isSelected ? Color.accentColor : Color.white.opacity(0.08))
        .foregroundColor(isSelected ? .white : .primary).clipShape(Capsule())
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
    }
}

struct SectionHeader: View {
    let title: String
    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(MaterialChartPalette.onSurfaceVariant)
            .padding(.top, 4)
    }
}

struct TrackHoverActionsView: View {
    let trackURI: String
    let trackName: String
    let artistName: String
    var uid: String? = nil
    var onAddToQueue: (() -> Void)? = nil

    @EnvironmentObject var musicManager: MusicManager
    @EnvironmentObject var settings: SettingsModel
    @State private var showingPlaylistMenu = false
    @State private var containedPlaylistURIs: Set<String> = []
    @State private var isCheckingMembership = false
    @State private var feedbackMessage: String? = nil
    @State private var feedbackTask: Task<Void, Never>?

    var body: some View {
        HStack(spacing: 4) {
            Button {
                showingPlaylistMenu.toggle()
                if showingPlaylistMenu {
                    checkPlaylistMembership()
                }
            } label: {
                Image(systemName: "plus.circle")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary.opacity(0.85))
            }
            .buttonStyle(.plain)
            .help("Add to Playlist")
            .popover(isPresented: $showingPlaylistMenu) {
                AddToPlaylistMenuView(
                    trackURI: trackURI,
                    containedPlaylistURIs: $containedPlaylistURIs,
                    isCheckingMembership: $isCheckingMembership,
                    feedbackMessage: $feedbackMessage
                )
            }

            Button {
                if let onAddToQueue {
                    onAddToQueue()
                } else {
                    Task {
                        _ = await musicManager.spotifyPrivateAPI.addToQueue(
                            uri: trackURI,
                            uid: uid,
                            metadata: [
                                "title": trackName,
                                "artist_name": artistName
                            ]
                        )
                        showFeedback("Added to queue")
                    }
                }
            } label: {
                Image(systemName: "text.badge.plus")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary.opacity(0.85))
            }
            .buttonStyle(.plain)
            .help("Add to Queue")
        }
    }

    private func checkPlaylistMembership() {
        isCheckingMembership = true
        let playlists = musicManager.spotifyPrivateAPI.nativePlaylists
        guard !playlists.isEmpty else {
            isCheckingMembership = false
            return
        }
        feedbackTask?.cancel()
        feedbackTask = Task {
            let contained = await musicManager.spotifyPrivateAPI.checkTrackMembership(
                trackURI: trackURI,
                playlists: playlists
            )
            if !Task.isCancelled {
                await MainActor.run {
                    containedPlaylistURIs = contained
                    isCheckingMembership = false
                }
            }
        }
    }

    private func showFeedback(_ message: String) {
        feedbackTask?.cancel()
        feedbackMessage = message
        feedbackTask = Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if !Task.isCancelled {
                await MainActor.run { feedbackMessage = nil }
            }
        }
    }
}

struct AddToPlaylistMenuView: View {
    let trackURI: String
    @Binding var containedPlaylistURIs: Set<String>
    @Binding var isCheckingMembership: Bool
    @Binding var feedbackMessage: String?

    @EnvironmentObject var musicManager: MusicManager
    @EnvironmentObject var settings: SettingsModel
    @State private var feedbackTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Add to Playlist")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

            Divider()

            if isCheckingMembership {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini)
                    Text("Checking playlists…")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }

            let addCandidates = allPlaylists.filter { !containedPlaylistURIs.contains($0.uri) }
            let removeCandidates = allPlaylists.filter { containedPlaylistURIs.contains($0.uri) }

            if addCandidates.isEmpty && removeCandidates.isEmpty {
                Text("No playlists available.")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(addCandidates) { playlist in
                            playlistRow(playlist, isContained: false)
                        }

                        if !removeCandidates.isEmpty {
                            Divider()
                                .padding(.vertical, 4)
                        }

                        ForEach(removeCandidates) { playlist in
                            playlistRow(playlist, isContained: true)
                        }
                    }
                }
            }

            if let feedback = feedbackMessage {
                Divider()
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.system(size: 11))
                    Text(feedback)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
        }
        .frame(width: 240)
        .frame(minHeight: 100, maxHeight: 320)
    }

    private var allPlaylists: [SpotifyPlaylist] {
        return musicManager.spotifyPrivateAPI.nativePlaylists
    }

    @ViewBuilder
    private func playlistRow(_ playlist: SpotifyPlaylist, isContained: Bool) -> some View {
        Button {
            Task {
                if isContained {
                    let ok = await musicManager.spotifyPrivateAPI.removeTracksFromPlaylist(
                        playlistURI: playlist.uri,
                        trackURIs: [trackURI]
                    )
                    if ok {
                        await MainActor.run {
                            containedPlaylistURIs.remove(playlist.uri)
                        }
                        showFeedback("Removed from \(playlist.name)")
                    } else {
                        showFeedback("Could not remove from \(playlist.name)")
                    }
                } else {
                    let ok = await musicManager.spotifyPrivateAPI.addTracksToPlaylist(
                        playlistURI: playlist.uri,
                        trackURIs: [trackURI]
                    )
                    if ok {
                        await MainActor.run {
                            containedPlaylistURIs.insert(playlist.uri)
                        }
                        showFeedback("Added to \(playlist.name)")
                    } else {
                        showFeedback("Could not add to \(playlist.name)")
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                CachedAsyncImage(url: playlist.imageURL) { image in
                    image.resizable()
                } placeholder: {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.secondary.opacity(0.2))
                }
                .frame(width: 28, height: 28)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                Text(playlist.name)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .lineLimit(1)
                    .foregroundStyle(.primary)

                Spacer(minLength: 0)

                if isContained {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.green)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func showFeedback(_ message: String) {
        feedbackTask?.cancel()
        feedbackMessage = message
        feedbackTask = Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if !Task.isCancelled {
                await MainActor.run { feedbackMessage = nil }
            }
        }
    }
}

struct NativeQueueTrackRow: View {
    let track: PlayerState.Track
    var onPlay: (PlaybackResult) -> Void
    @State private var isHovered = false
    @EnvironmentObject var musicManager: MusicManager
    var body: some View {
        HStack(spacing: 10) {
            Button {
                Task {
                    onPlay(await musicManager.play(
                        trackUri: track.uri,
                        contextUri: track.metadata?.contextUri,
                        trackUid: track.uid,
                        trackIndex: nil
                    ))
                }
            } label: {
                HStack(spacing: 10) {
                    CachedAsyncImage(url: track.metadata?.imageURL) { $0.resizable() } placeholder: {
                        ZStack { MaterialChartPalette.surfaceVariant; Image(systemName: "music.note") }
                    }
                    .frame(width: 34, height: 34)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(track.metadata?.title ?? "Unknown Track")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .lineLimit(1)
                            .foregroundStyle(.primary)
                        Text(track.metadata?.artistName ?? "Unknown Artist")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            TrackHoverActionsView(
                trackURI: track.uri,
                trackName: track.metadata?.title ?? "Unknown Track",
                artistName: track.metadata?.artistName ?? "Unknown Artist",
                uid: track.uid
            )
            .opacity(isHovered ? 1 : 0)

            Button {
                Task {
                    _ = await musicManager.spotifyPrivateAPI.removeFromQueue(uid: track.uid)
                }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(isHovered ? MaterialChartPalette.error : .secondary.opacity(0.55))
            }
            .buttonStyle(.plain)
            .help("Remove from queue")
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 8)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isHovered ? MaterialChartPalette.surface : MaterialChartPalette.surfaceContainer.opacity(0.65))
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(MaterialChartPalette.cardGradient(for: MaterialChartPalette.primary))
            }
        )
        .contentShape(Rectangle())
        .onHover { hovering in self.isHovered = hovering }
        .contextMenu {
            Button("Play") {
                Task {
                    onPlay(await musicManager.play(
                        trackUri: track.uri,
                        contextUri: track.metadata?.contextUri,
                        trackUid: track.uid,
                        trackIndex: nil
                    ))
                }
            }
            Button("Remove from Queue", role: .destructive) {
                Task { _ = await musicManager.spotifyPrivateAPI.removeFromQueue(uid: track.uid) }
            }
        }
    }
}

struct QueueTrackRow: View {
    let track: SpotifyTrack
    var onPlay: (PlaybackResult) -> Void
    @State private var isHovered = false
    @EnvironmentObject var musicManager: MusicManager
    private func formatDuration(ms: Int) -> String {
        let s = ms / 1000; return "\(s / 60):\(String(format: "%02d", s % 60))"
    }

    var body: some View {
        HStack(spacing: 12) {
            CachedAsyncImage(url: track.imageURL) { $0.resizable() } placeholder: { ZStack { Color.secondary.opacity(0.3); Image(systemName: "music.note") } }
                .frame(width: 36, height: 36).cornerRadius(6)
                .overlay(ZStack { if isHovered { Color.black.opacity(0.5); Image(systemName: "play.fill").font(.title3).foregroundColor(.white) }}.cornerRadius(6))

            VStack(alignment: .leading) {
                Text(track.name).fontWeight(.medium).lineLimit(1)
                Text(track.artists.map(\.name).joined(separator: ", ")).font(.caption).foregroundColor(.secondary).lineLimit(1)
            }
            Spacer()
            Text(formatDuration(ms: track.durationMs)).font(.caption.monospacedDigit()).foregroundColor(.secondary)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)        .background(Color.white.opacity(isHovered ? 0.15 : 0.1)).cornerRadius(10)
        .contentShape(Rectangle())
        .onHover { hovering in self.isHovered = hovering }
        .onTapGesture { Task { onPlay(await musicManager.play(trackUri: track.uri, contextUri: nil, trackUid: nil, trackIndex: nil)) }}
        .animation(.easeInOut(duration: 0.15), value: isHovered)

    }
}

struct FullPlaylistRow: View {
    let playlist: SpotifyPlaylist
    @Binding var navigationStack: [NotchWidgetMode]
    let isPlaying: Bool
    let isLockScreenMode: Bool
    @EnvironmentObject var navigationManager: LockScreenNavigationManager
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 15) {
            CachedAsyncImage(url: playlist.imageURL) { $0.resizable() } placeholder: { ZStack { Color.secondary.opacity(0.3); Image(systemName: "music.note.list") } }
                .frame(width: 50, height: 50).cornerRadius(8)

            VStack(alignment: .leading) {
                Text(playlist.name).fontWeight(.bold).lineLimit(1).foregroundColor(isPlaying ? .green : .primary)
                Text("By \(playlist.owner.displayName)").font(.subheadline).foregroundColor(.secondary).lineLimit(1)
            }
            Spacer()
            if isPlaying { Image(systemName: "speaker.wave.2.fill").foregroundColor(.green).font(.headline) }
            Image(systemName: "chevron.right").foregroundColor(.secondary)
        }
        .padding(10)
        .background(Color.white.opacity(isHovered ? 0.15 : 0.1)).cornerRadius(12)
        .contentShape(Rectangle())
        .onHover { hovering in self.isHovered = hovering }
        .onTapGesture {
            if isLockScreenMode {
                navigationManager.navigateTo(.playlistDetail(playlist))
            } else {
                navigationStack.append(.musicPlaylistDetail(playlist))
            }
        }
        .animation(.easeInOut(duration: 0.15), value: isHovered)
    }
}

struct NowPlayingInfoView: View {
    let systemName: String
    let text: String
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: systemName).font(.caption2).foregroundColor(.secondary)
            Text(text).font(.caption).fontWeight(.medium).foregroundColor(.primary)
        }
    }
}

struct ActiveDeviceView: View {
    @EnvironmentObject var musicManager: MusicManager
    private var activeDevice: SpotifyNativeDevice? {
        guard let activeID = musicManager.spotifyPrivateAPI.activePlayerDeviceID else { return nil }
        return musicManager.spotifyPrivateAPI.devices.first { $0.deviceId == activeID }
            ?? musicManager.spotifyPrivateAPI.devices.first {
                $0.deviceId.hasSuffix(activeID) || activeID.hasSuffix($0.deviceId)
            }
    }

    private func iconName(for type: String) -> String {
        switch type.lowercased() {
        case "computer": return "macbook.gen2"
        case "speaker": return "hifispeaker.2.fill"
        case "smartphone": return "iphone"
        case "tablet": return "ipad"
        case "tv": return "tv.fill"
        case "avr", "stb", "castvideo": return "tv.inset.filled"
        case "gameconsole": return "gamecontroller.fill"
        case "automobile": return "car.fill"
        case "castaudio", "audiodongle": return "hifispeaker.2.fill"
        default: return "speaker.wave.2.fill"
        }
    }

    var body: some View {
        HStack {
            if let device = activeDevice {
                HStack(spacing: 6) {
                    Image(systemName: iconName(for: device.deviceType))
                    Text(device.name)
                }
                .font(.caption)
                .foregroundColor(.green)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.black.opacity(0.2))
                .clipShape(Capsule())
                .help("Playing on \(device.name)")
            }
        }
    }
}

struct PlaylistGridCard: View {
    let playlist: SpotifyPlaylist
    let isPlaying: Bool
    let onTap: () -> Void
    var onPlay: (() -> Void)? = nil
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onTap) {
                HStack(spacing: 12) {
                    CachedAsyncImage(url: playlist.imageURL) { $0.resizable().aspectRatio(contentMode: .fill) }
                        placeholder: { ZStack { MaterialChartPalette.surfaceVariant; Image(systemName: "music.note.list") } }
                        .frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(playlist.name)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .lineLimit(1)
                            .foregroundStyle(isPlaying ? MaterialChartPalette.tertiary : .primary)
                        Text(playlist.owner.displayName)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if let onPlay {
                Button(action: onPlay) {
                    Image(systemName: isPlaying ? "waveform" : "play.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(isPlaying ? MaterialChartPalette.tertiary : .primary)
                        .frame(width: 32, height: 32)
                        .background(MaterialChartPalette.primary.opacity(0.16), in: Circle())
                }
                .buttonStyle(.plain)
                .help("Play playlist")
            } else if isPlaying {
                Image(systemName: "waveform")
                    .foregroundStyle(MaterialChartPalette.tertiary)
                    .font(.caption)
            }
        }
        .padding(12)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isHovered ? MaterialChartPalette.surface : MaterialChartPalette.surfaceContainer)
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(MaterialChartPalette.cardGradient(for: isPlaying ? MaterialChartPalette.tertiary : MaterialChartPalette.primary))
            }
        )
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
    }
}

struct RecentlyPlayedCard: View {
    let item: SpotifyRecentlyPlayedItem
    let onTap: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
                CachedAsyncImage(url: item.imageURL) { $0.resizable().aspectRatio(contentMode: .fill) }
                    placeholder: { Color.secondary.opacity(0.3) }
                    .frame(width: 100, height: 100)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                Text(item.name).font(.caption.bold()).lineLimit(1).frame(width: 100, alignment: .leading)
                Text(item.ownerName).font(.caption2).foregroundColor(.secondary).lineLimit(1).frame(width: 100, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
        .padding(4)
        .background(Color.white.opacity(isHovered ? 0.1 : 0), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
    }
}

struct PopularReleaseCard: View {
    let release: SpotifyPopularRelease
    let onPlay: (PlaybackResult) -> Void
    @EnvironmentObject var musicManager: MusicManager

    @State private var isHovered = false

    var body: some View {
        Button {
            Task { onPlay(await musicManager.play(trackUri: release.uri, contextUri: nil, trackUid: nil, trackIndex: nil)) }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                CachedAsyncImage(url: release.imageURL) { $0.resizable().aspectRatio(contentMode: .fill) }
                    placeholder: { ZStack { Color.secondary.opacity(0.3); Image(systemName: "music.note") } }
                    .frame(width: 100, height: 100)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                Text(release.name).font(.caption.bold()).lineLimit(2).frame(width: 100, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
        .padding(4)
        .background(Color.white.opacity(isHovered ? 0.1 : 0), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
    }
}

struct RecommendedTrackRow: View {
    let track: SpotifyRecommendedTrack
    let onPlay: (PlaybackResult) -> Void
    @EnvironmentObject var musicManager: MusicManager
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            Button {
                Task { onPlay(await musicManager.play(trackUri: track.uri, contextUri: track.albumURI, trackUid: nil, trackIndex: nil)) }
            } label: {
                HStack(spacing: 10) {
                    CachedAsyncImage(url: track.imageURL) { $0.resizable() }
                        placeholder: { ZStack { MaterialChartPalette.surfaceVariant; Image(systemName: "music.note") } }
                        .frame(width: 34, height: 34)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(track.name)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .lineLimit(1)
                            .foregroundStyle(.primary)
                        Text(track.artists.map(\.name).joined(separator: ", "))
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            TrackHoverActionsView(
                trackURI: track.uri,
                trackName: track.name,
                artistName: track.artists.map(\.name).joined(separator: ", ")
            )
            .opacity(isHovered ? 1 : 0)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .contextMenu {
            Button("Play") {
                Task { onPlay(await musicManager.play(trackUri: track.uri, contextUri: track.albumURI, trackUid: nil, trackIndex: nil)) }
            }
            Button("Add to Queue") {
                Task {
                    _ = await musicManager.spotifyPrivateAPI.addToQueue(
                        uri: track.uri,
                        metadata: [
                            "title": track.name,
                            "artist_name": track.artists.map(\.name).joined(separator: ", ")
                        ]
                    )
                }
            }
        }
    }
}

fileprivate struct Marquee<Content: View>: View {
    @ViewBuilder var content: Content

    @State private var animate = false
    @State private var containerWidth: CGFloat = 0
    @State private var contentWidth: CGFloat = 0

    private var isOverflowing: Bool {
        contentWidth > containerWidth
    }

    private var animation: Animation {
        .linear(duration: contentWidth / 30)
        .delay(1.5)
        .repeatForever(autoreverses: false)
    }

    var body: some View {
        let base = content
            .fixedSize(horizontal: true, vertical: false)
            .background(GeometryReader { proxy in
                Color.clear.onAppear { contentWidth = proxy.size.width }
            })

        GeometryReader { proxy in
            HStack(spacing: 0) {
                if isOverflowing && animate {
                    base
                        .offset(x: -contentWidth)
                        .onAppear {
                            withAnimation(animation.delay(0)) {
                                animate = false
                            }
                        }
                }
                base
            }
            .offset(x: animate ? contentWidth : 0)
            .onAppear {
                containerWidth = proxy.size.width
                guard isOverflowing else { return }
                withAnimation(animation) {
                    animate = true
                }
            }
        }
        .clipped()
    }
}

// MARK: - Consolidated from DevicesView.swift

fileprivate class Throttler {
    private let delay: TimeInterval
    private var workItem: DispatchWorkItem?
    private let queue: DispatchQueue

    init(delay: TimeInterval, queue: DispatchQueue = .main) {
        self.delay = delay
        self.queue = queue
    }

    func throttle(action: @escaping (() -> Void)) {
        guard workItem == nil else { return }
        action()
        workItem = DispatchWorkItem { [weak self] in
            self?.workItem = nil
        }
        queue.asyncAfter(deadline: .now() + delay, execute: workItem!)
    }
}

fileprivate enum DeviceTab: Int {
    case spotify = 0
    case airplay = 1
    case system = 2
}

enum MusicAudioHubSection: Int, CaseIterable {
    case spotify = 0
    case airplay = 1
    case apps = 2
    case system = 3

    var title: String {
        switch self {
        case .spotify: return "Spotify"
        case .airplay: return "AirPlay"
        case .apps: return "Apps"
        case .system: return "System"
        }
    }

    var systemImage: String {
        switch self {
        case .spotify: return "music.note"
        case .airplay: return "airplayaudio"
        case .apps: return "square.grid.2x2"
        case .system: return "hifispeaker.and.homepod.mini.fill"
        }
    }

    static let defaultsKey = "lastSelectedAudioHubSection"
}

struct DevicesView: View {
    @EnvironmentObject var musicManager: MusicManager
    @EnvironmentObject var settings: SettingsModel

    @Binding var navigationStack: [NotchWidgetMode]
    @Binding var audioHubSection: MusicAudioHubSection

    @State private var selectedTab: DeviceTab

    @State private var spotifyNativeDevices: [SpotifyNativeDevice] = []
    @State private var spotifyOfficialDevices: [SpotifyDevice] = []

    @State private var spotifyVolume: Double = 75

    @State private var isLoading = true

    var isLockScreenMode: Bool = false
    var embedded: Bool = false

    private let volumeThrottler = Throttler(delay: 0.1)

    private let lastSelectedTabKey = "lastSelectedDeviceTab"

    private var isAppleMusic: Bool {
        musicManager.lastKnownBundleID == "com.apple.Music"
    }

    private var isLoggedIn: Bool {
        musicManager.isPrivateAPIAuthenticated || musicManager.isOfficialAPIAuthenticated
    }

    private var showsSpotifyTab: Bool {
        !isAppleMusic && isLoggedIn
    }

    var availableAudioHubSections: [MusicAudioHubSection] {
        var sections: [MusicAudioHubSection] = []
        if showsSpotifyTab { sections.append(.spotify) }
        sections.append(contentsOf: [.airplay, .apps, .system])
        return sections
    }

    init(
        navigationStack: Binding<[NotchWidgetMode]>,
        audioHubSection: Binding<MusicAudioHubSection>,
        isLockScreenMode: Bool = false,
        preferSystemTab: Bool = false,
        embedded: Bool = false
    ) {
        self._navigationStack = navigationStack
        self._audioHubSection = audioHubSection
        self.isLockScreenMode = isLockScreenMode
        self.embedded = embedded
        let savedTab = DeviceTab(rawValue: UserDefaults.standard.integer(forKey: lastSelectedTabKey)) ?? .spotify
        self._selectedTab = State(initialValue: preferSystemTab ? .system : savedTab)
    }

    private func sendVolumeUpdate() {
        Task {
            _ = await musicManager.setSpotifyVolume(percent: Int(spotifyVolume))
        }
    }

    var body: some View {
        Group {
            if embedded {
                unifiedAudioBody
            } else {
                legacyTabbedBody
            }
        }
        .padding(.horizontal, embedded ? 0 : 20)
        .padding(.top, 0)
        .frame(width: embedded ? nil : 760)
        .frame(maxWidth: embedded ? .infinity : nil)
        .frame(maxHeight: embedded ? .infinity : 360)
        .fixedSize(horizontal: false, vertical: !embedded)
        .onAppear {
            normalizeSelectedTab()
            normalizeAudioHubSection()
            if !musicManager.spotifyPrivateAPI.devices.isEmpty {
                spotifyNativeDevices = musicManager.spotifyPrivateAPI.devices
                isLoading = false
            }
        }
        .onReceive(musicManager.spotifyPrivateAPI.$devices.receive(on: DispatchQueue.main)) { devices in
            guard !devices.isEmpty else { return }
            spotifyNativeDevices = devices
            if isLoading { isLoading = false }
        }
        .onChange(of: showsSpotifyTab) { _, _ in
            normalizeSelectedTab()
            normalizeAudioHubSection()
        }
        .onChange(of: audioHubSection) { _, newValue in
            UserDefaults.standard.set(newValue.rawValue, forKey: MusicAudioHubSection.defaultsKey)
        }
        .task(id: embedded ? "\(audioHubSection)" : "\(effectiveDeviceTab)") {
            if embedded {
                await fetchDataForAudioHubSection(audioHubSection)
            } else {
                await fetchData(for: effectiveDeviceTab)
            }
        }
    }

    private var unifiedAudioBody: some View {
        ZStack {
            if isLoading && (audioHubSection == .spotify || audioHubSection == .airplay) {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                switch effectiveAudioHubSection {
                case .spotify:
                    ScrollView(.vertical, showsIndicators: false) {
                        spotifyDeviceListContent
                            .padding(.bottom, 16)
                    }
                case .airplay:
                    ScrollView(.vertical, showsIndicators: false) {
                        appleMusicDeviceListContent
                            .padding(.bottom, 16)
                    }
                case .apps:
                    ScrollView(.vertical, showsIndicators: false) {
                        AppSectionView(navigationStack: $navigationStack, omitOuterPadding: true)
                            .padding(.bottom, 16)
                    }
                case .system:
                    ScrollView(.vertical, showsIndicators: false) {
                        DeviceSectionView(navigationStack: $navigationStack, omitOuterPadding: true)
                            .padding(.bottom, 16)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeInOut(duration: 0.18), value: effectiveAudioHubSection)
    }

    private var effectiveAudioHubSection: MusicAudioHubSection {
        if audioHubSection == .spotify && !showsSpotifyTab { return .apps }
        return audioHubSection
    }

    private func normalizeAudioHubSection() {
        if audioHubSection == .spotify && !showsSpotifyTab {
            audioHubSection = .apps
        }
    }

    private func fetchDataForAudioHubSection(_ section: MusicAudioHubSection) async {
        switch section {
        case .spotify:
            await loadSpotifyDevices(manageLoading: true)
        case .airplay:
            await MainActor.run { isLoading = true }
            await musicManager.updateAirPlayDevices()
            await MainActor.run { isLoading = false }
        case .apps, .system:
            await MainActor.run { isLoading = false }
        }
    }

    private var legacyTabbedBody: some View {
        VStack(spacing: 10) {
            HStack {
                if let user = musicManager.spotifyOfficialAPI.userProfile {
                    Text("Welcome, \(user.displayName)").font(.caption.bold()).foregroundColor(.secondary)
                } else if let nativeUser = musicManager.spotifyPrivateAPI.userProfile {
                    Text("Welcome, \(nativeUser.profile.friendlyName)").font(.caption.bold()).foregroundColor(.secondary)
                }
                Spacer()
                deviceSubTabBar
                if musicManager.isOfficialAPIAuthenticated {
                    Button("Log out") { musicManager.spotifyOfficialAPI.logout() }
                        .buttonStyle(.plain).font(.caption).foregroundColor(.secondary)
                }
            }

            ZStack {
                if isLoading && selectedTab != .system {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    switch effectiveDeviceTab {
                    case .spotify:
                        spotifyDeviceList
                            .transition(.asymmetric(
                                insertion: .move(edge: .leading).combined(with: .opacity),
                                removal: .move(edge: .leading).combined(with: .opacity)
                            ))
                    case .airplay:
                        appleMusicDeviceList
                            .transition(.asymmetric(
                                insertion: .move(edge: .trailing).combined(with: .opacity),
                                removal: .move(edge: .trailing).combined(with: .opacity)
                            ))
                    case .system:
                        SystemAudioPanel(navigationStack: $navigationStack)
                            .transition(.opacity)
                    }
                }
            }
            .animation(.easeInOut(duration: 0.2), value: effectiveDeviceTab)
            .frame(minHeight: 220)
        }
    }

    private var deviceSubTabBar: some View {
        HStack(spacing: 6) {
            if showsSpotifyTab {
                TabButton(title: "Spotify", systemImage: "music.note", isSelected: selectedTab == .spotify) {
                    selectedTab = .spotify
                }
            }
            TabButton(title: "AirPlay", systemImage: "airplayaudio", isSelected: selectedTab == .airplay) {
                selectedTab = .airplay
            }
            TabButton(title: "System", systemImage: "hifispeaker.and.homepod.mini.fill", isSelected: selectedTab == .system) {
                selectedTab = .system
            }
        }
        .padding(5)
        .background(Color.black.opacity(0.2))
        .clipShape(Capsule())
    }

    private var effectiveDeviceTab: DeviceTab {
        if selectedTab == .spotify && !showsSpotifyTab { return .airplay }
        return selectedTab
    }

    private func normalizeSelectedTab() {
        if selectedTab == .spotify && !showsSpotifyTab {
            selectedTab = settings.settings.preferAirPlayOverSpotify ? .airplay : .system
        }
    }

    @ViewBuilder
    private var appleMusicDeviceListContent: some View {
        if musicManager.airplayDevices.isEmpty {
            Text("No AirPlay devices found.")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(musicManager.airplayDevices) { device in
                    AppleMusicDeviceRow(
                        device: device,
                        onSelect: {
                            Task {
                                await musicManager.switchToAirPlayDevice(device)
                                try await Task.sleep(for: .seconds(1))
                                await musicManager.updateAirPlayDevices()
                            }
                        }
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var appleMusicDeviceList: some View {
        if musicManager.airplayDevices.isEmpty {
            Text("No AirPlay devices found.")
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 15) {
                    ForEach(musicManager.airplayDevices) { device in
                        AppleMusicDeviceRow(
                            device: device,
                            onSelect: {
                                Task {
                                    await musicManager.switchToAirPlayDevice(device)
                                    try await Task.sleep(for: .seconds(1))
                                    await musicManager.updateAirPlayDevices()
                                }
                            }
                        )
                    }
                }
                .padding(.bottom, 30)
            }
            .mask(LinearGradient(gradient: Gradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.9), .init(color: .clear, location: 1.0)]), startPoint: .top, endPoint: .bottom))
        }
    }

    @ViewBuilder
    private var spotifyDeviceListContent: some View {
        let sortedNativeDevices = spotifyNativeDevices.sorted { d1, d2 in
            let d1IsActive = d1.deviceId == musicManager.spotifyPrivateAPI.activePlayerDeviceID
            let d2IsActive = d2.deviceId == musicManager.spotifyPrivateAPI.activePlayerDeviceID
            if d1IsActive && !d2IsActive { return true }
            if !d1IsActive && d2IsActive { return false }
            return d1.name.localizedCompare(d2.name) == .orderedAscending
        }

        let sortedOfficialDevices = spotifyOfficialDevices.sorted { d1, d2 in
            if d1.isActive && !d2.isActive { return true }
            if !d1.isActive && d2.isActive { return false }
            return d1.name.localizedCompare(d2.name) == .orderedAscending
        }

        VStack(alignment: .leading, spacing: 12) {
            if let notice = musicManager.spotifyPrivateAPI.deviceTransferNotice {
                Text(notice)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.orange)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            if musicManager.isPrivateAPIAuthenticated,
               sortedNativeDevices.filter({ $0.deviceId != musicManager.spotifyPrivateAPI.controllerDeviceID }).isEmpty,
               sortedOfficialDevices.isEmpty {
                Text("No Spotify speakers online. Open the Spotify desktop app (or another Connect device) to play audio — Sapphire only controls playback.")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            if !sortedNativeDevices.isEmpty {
                ForEach(sortedNativeDevices, id: \.deviceId) { device in
                    let isSapphireController = device.deviceId == musicManager.spotifyPrivateAPI.controllerDeviceID
                    SpotifyNativeDeviceRow(
                        device: device,
                        isActive: device.deviceId == musicManager.spotifyPrivateAPI.activePlayerDeviceID,
                        isControllerOnly: isSapphireController,
                        volume: $spotifyVolume,
                        onTransfer: {
                            Task.detached(priority: .userInitiated) {
                                _ = await musicManager.transferSpotifyPlayback(to: device.deviceId)
                                try? await Task.sleep(for: .seconds(1))
                                await fetchInitialData()
                            }
                        },
                        onCommit: { sendVolumeUpdate() }
                    )
                }
            } else if !sortedOfficialDevices.isEmpty {
                ForEach(sortedOfficialDevices) { device in
                    SpotifyDeviceRow(
                        device: device,
                        volume: $spotifyVolume,
                        onTransfer: {
                            guard let deviceId = device.id else { return }
                            Task.detached(priority: .userInitiated) {
                                _ = await musicManager.transferSpotifyPlayback(to: deviceId)
                                try? await Task.sleep(for: .seconds(1))
                                await fetchInitialData()
                            }
                        },
                        onCommit: { sendVolumeUpdate() }
                    )
                }
            }

            if !musicManager.isPremiumUser && spotifyNativeDevices.isEmpty {
                FreeUserNoticeView()
            }
        }
        .onChange(of: spotifyVolume) { _, _ in
            volumeThrottler.throttle { sendVolumeUpdate() }
        }
    }

    @ViewBuilder
    private var spotifyDeviceList: some View {
        ScrollView {
            spotifyDeviceListContent
                .padding(.bottom, 30)
        }
        .mask(LinearGradient(gradient: Gradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.9), .init(color: .clear, location: 1.0)]), startPoint: .top, endPoint: .bottom))
    }

    // MARK: - Data Fetching

    private func fetchAllAudioData() async {
        await MainActor.run { isLoading = true }
        async let airplay: Void = musicManager.updateAirPlayDevices()
        if showsSpotifyTab {
            await loadSpotifyDevices(manageLoading: false)
        }
        _ = await airplay
        await MainActor.run { isLoading = false }
    }

    private func fetchData(for tab: DeviceTab) async {
        UserDefaults.standard.set(tab.rawValue, forKey: lastSelectedTabKey)

        switch tab {
        case .system:
            await MainActor.run { isLoading = false }

        case .airplay:
            await MainActor.run { isLoading = true }
            await musicManager.updateAirPlayDevices()
            await MainActor.run { isLoading = false }

        case .spotify:
            await loadSpotifyDevices(manageLoading: true)
        }
    }

    private func loadSpotifyDevices(manageLoading: Bool) async {
        let cached = musicManager.spotifyPrivateAPI.devices
        if !cached.isEmpty {
            await MainActor.run {
                self.spotifyNativeDevices = cached
                if manageLoading { self.isLoading = false }
            }
        } else if manageLoading {
            await MainActor.run { isLoading = false }
        }

        guard isLoggedIn else { return }

        if musicManager.isPrivateAPIAuthenticated {
            musicManager.spotifyPrivateAPI.bootstrapIfNeeded(policy: .onDemand)
            Task(priority: .utility) {
                try? await musicManager.spotifyPrivateAPI.refreshPlayerAndDeviceState()
            }
        }

        var fetchedOfficialDevices: [SpotifyDevice] = []
        if musicManager.isOfficialAPIAuthenticated {
            fetchedOfficialDevices = await musicManager.spotifyOfficialAPI.fetchDevices()
        }

        let fetchedNativeDevices = musicManager.spotifyPrivateAPI.devices
        var newVolume: Double?
        if let activeNativeID = musicManager.spotifyPrivateAPI.activePlayerDeviceID,
           let activeNativeDevice = fetchedNativeDevices.first(where: { $0.deviceId == activeNativeID }) {
            newVolume = (Double(activeNativeDevice.volume ?? 65535) / 65535.0) * 100.0
        } else if let activeOfficial = fetchedOfficialDevices.first(where: { $0.isActive }),
                  let currentVolume = activeOfficial.volumePercent {
            newVolume = Double(currentVolume)
        } else if let localVolume = await musicManager.spotifyAppleScript.getLocalVolumeAsync() {
            newVolume = Double(localVolume)
        }

        await MainActor.run {
            if !fetchedNativeDevices.isEmpty {
                self.spotifyNativeDevices = fetchedNativeDevices
            }
            self.spotifyOfficialDevices = fetchedOfficialDevices
            if let newVolume { self.spotifyVolume = newVolume }
            if manageLoading { self.isLoading = false }
        }
    }

    private func fetchInitialData() async {
        if embedded {
            await fetchAllAudioData()
        } else {
            await fetchData(for: selectedTab)
        }
    }
}

// MARK: - Row Views

fileprivate struct AppleMusicDeviceRow: View {
    let device: AirPlayDevice
    let onSelect: () -> Void
    @State private var volume: Double
    private let throttler = Throttler(delay: 0.1)
    @EnvironmentObject var musicManager: MusicManager

    init(device: AirPlayDevice, onSelect: @escaping () -> Void) {
        self.device = device
        self.onSelect = onSelect
        _volume = State(initialValue: Double(device.volume ?? 75))
    }

    private func sendVolumeUpdate() {
        Task {
            SystemControl.setVolume(to: Float(volume / 100.0))
            SystemControl.setMuted(to: false)

            await musicManager.setAirPlayDeviceVolume(deviceName: device.name, volume: Int(volume))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 15) {
                Image(systemName: device.iconName).font(.title2).frame(width: 30).foregroundColor(device.isSelected ? .blue : .primary)
                Text(device.name).fontWeight(.medium)
                Spacer()
                if device.isSelected { Image(systemName: "checkmark.circle.fill").font(.title2).foregroundColor(.blue).transition(.opacity.combined(with: .scale(scale: 0.8))) }
            }
            if device.isSelected {
                BoldPillSlider(label: "Volume", value: $volume, range: 0...100, specifier: "%.0f %%", onCommit: sendVolumeUpdate)
                    .padding(.leading, 45)
                    .transition(.opacity.combined(with: .offset(y: 5)))
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 16).background(.gray.opacity(0.13)).clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous)).contentShape(Rectangle())
        .onTapGesture { if !device.isSelected { onSelect() } }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: device.isSelected)
        .onChange(of: volume) { _, _ in
            throttler.throttle { sendVolumeUpdate() }
        }
    }
}

fileprivate struct SpotifyDeviceRow: View {
    let device: SpotifyDevice
    @Binding var volume: Double
    let onTransfer: () -> Void
    let onCommit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 15) {
                Image(systemName: iconName(for: device.type))
                    .font(.title2)
                    .frame(width: 30)
                    .foregroundColor(device.isActive ? .green : .primary)
                Text(device.name).fontWeight(.medium)
                Spacer()
                if device.isActive { Image(systemName: "checkmark.circle.fill").font(.title2).foregroundColor(.green).transition(.opacity.combined(with: .scale(scale: 0.8))) }
            }
            if device.isActive && device.volumePercent != nil {
                BoldPillSlider(label: "Volume", value: $volume, range: 0...100, specifier: "%.0f %%", onCommit: onCommit)
                    .padding(.leading, 45)
                    .transition(.opacity.combined(with: .offset(y: 5)))
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 16).background(.gray.opacity(0.13)).clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous)).contentShape(Rectangle())
        .onTapGesture { guard !device.isActive else { return }; onTransfer() }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: device.isActive)
    }

    private func iconName(for type: String) -> String {
        switch type.lowercased() {
        case "computer": return "desktopcomputer"
        case "speaker": return "hifispeaker.fill"
        case "smartphone": return "iphone"
        case "tv": return "tv.fill"
        case "avr", "stb", "castvideo": return "tv.inset.filled"
        case "gameconsole": return "gamecontroller.fill"
        case "automobile": return "car.fill"
        case "tablet": return "ipad"
        case "castaudio", "audiodongle": return "hifispeaker.2.fill"
        default: return "speaker.wave.2.fill"
        }
    }
}

fileprivate struct SpotifyNativeDeviceRow: View {
    let device: SpotifyNativeDevice
    let isActive: Bool
    var isControllerOnly: Bool = false
    @Binding var volume: Double
    let onTransfer: () -> Void
    let onCommit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 15) {
                Image(systemName: iconName(for: device.deviceType))
                    .font(.title2)
                    .frame(width: 30)
                    .foregroundColor(isActive ? .green : (isControllerOnly ? .secondary : .primary))
                VStack(alignment: .leading, spacing: 2) {
                    Text(device.name).fontWeight(.medium)
                    if isControllerOnly {
                        Text("This Mac · controls only (no audio)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if isActive {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.green)
                        .transition(.opacity.combined(with: .scale(scale: 0.8)))
                }
            }
            if isActive && (device.capabilities.volumeSteps ?? 0) > 0 {
                BoldPillSlider(label: "Volume", value: $volume, range: 0...100, specifier: "%.0f %%", onCommit: onCommit)
                    .padding(.leading, 45)
                    .transition(.opacity.combined(with: .offset(y: 5)))
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 16)
        .background(.gray.opacity(isControllerOnly ? 0.08 : 0.13))
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .contentShape(Rectangle())
        .opacity(isControllerOnly ? 0.72 : 1)
        .onTapGesture {
            guard !isActive else { return }
            if isControllerOnly { return }
            onTransfer()
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isActive)
    }

    private func iconName(for type: String) -> String {
        switch type.lowercased() {
        case "computer": return "macbook.gen2"
        case "speaker": return "hifispeaker.2.fill"
        case "smartphone": return "iphone"
        case "avr", "stb": return "tv.inset.filled"
        default: return "questionmark.circle"
        }
    }
}

fileprivate struct FreeUserNoticeView: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.lock.fill").font(.title3).foregroundColor(.yellow)
            Text("Switching devices requires a Spotify Premium account or a private api login.").font(.subheadline).foregroundColor(.secondary)
        }.padding().background(Color.yellow.opacity(0.1)).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

fileprivate struct BoldPillSlider: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let specifier: String
    var onCommit: (() -> Void)? = nil

    private var displayValue: String { String(format: specifier, value) }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let progress = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
            let progressWidth = width * progress
            let textView = HStack { Text(label).fontWeight(.bold); Spacer(); Text(displayValue).font(.system(.body, design: .monospaced)).fontWeight(.bold) }.font(.system(size: 16)).padding(.horizontal, 20)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.gray.opacity(0.25))
                textView.foregroundColor(.primary.opacity(0.8))
                ZStack { Capsule().fill(Color.accentColor); textView.foregroundColor(.white) }.mask(Rectangle().frame(width: progressWidth).frame(maxWidth: .infinity, alignment: .leading))
            }
            .clipShape(Capsule()).contentShape(Capsule())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { gesture in
                    let percentage = (gesture.location.x / width).clamped(to: 0...1)
                    let newValue = (range.upperBound - range.lowerBound) * percentage + range.lowerBound
                    self.value = newValue.clamped(to: range)
                }
                .onEnded { _ in onCommit?() }
            )
        }.frame(height: 44)
    }
}

// MARK: - Consolidated from PlaylistView.swift

fileprivate let isoDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    return formatter
}()

fileprivate let displayDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .none
    return formatter
}()

class TrackViewModel: ObservableObject, Identifiable {
    let id = UUID()

    let name: String
    let artists: String
    let firstArtistName: String
    let firstArtistURI: String?
    let albumName: String
    let albumURI: String?
    let imageURL: URL?
    let uri: String
    let uid: String?
    let dateAdded: TimeInterval?
    let addedByName: String?
    let playCount: Int?
    let publicationYear: Int?

    @Published var trackDetails: SpotifyTrackDetailsResponse.TrackUnion?

    private var hydrationTask: Task<Void, Never>?
    private let canHydrate: Bool

    init(playlistItem: SpotifyPlaylistDetailsResponse.PlaylistItem) {
        let data = playlistItem.itemV2.data
        self.uid = playlistItem.uid
        self.name = data.name ?? "Unknown Track"
        let artistItems = data.artists?.items ?? []
        self.artists = artistItems.map(\.profile.name).joined(separator: ", ").nilIfEmpty ?? "Unknown Artist"
        self.firstArtistName = artistItems.first?.profile.name ?? "Unknown Artist"
        self.firstArtistURI = artistItems.first?.uri
        self.albumName = data.albumOfTrack?.name ?? "Unknown Album"
        self.albumURI = data.albumOfTrack?.uri
        self.imageURL = data.imageURL
        self.uri = data.uri ?? ""
        self.dateAdded = playlistItem.addedAt
        self.addedByName = playlistItem.addedByDisplayName
        self.playCount = data.playcountInt
        self.publicationYear = data.albumOfTrack?.publishDate?.year
        self.canHydrate = true
    }

    init(track: SpotifyTrack) {
        self.uid = nil
        self.name = track.name
        self.artists = track.artists.map(\.name).joined(separator: ", ")
        self.firstArtistName = track.artists.first?.name ?? "Unknown Artist"
        self.firstArtistURI = nil
        self.albumName = track.album.name
        self.albumURI = nil
        self.imageURL = track.album.images.first.flatMap { URL(string: $0.url) }
        self.uri = track.uri
        self.dateAdded = nil
        self.addedByName = nil
        self.playCount = nil
        self.publicationYear = nil
        self.canHydrate = false
    }

    func hydrate(completion: (() -> Void)? = nil) {
        guard canHydrate, trackDetails == nil, hydrationTask == nil else {
            completion?()
            return
        }
        hydrationTask = Task { [weak self] in
            guard let self else { return }
            let trackId = self.uri.components(separatedBy: ":").last ?? ""
            guard !trackId.isEmpty else {
                await MainActor.run { completion?(); self.hydrationTask = nil }
                return
            }
            if Task.isCancelled { return }
            let details = await SpotifyPrivateAPIManager.shared.fetchTrackDetails(trackId: trackId)
            if !Task.isCancelled {
                await MainActor.run {
                    self.trackDetails = details
                    completion?()
                    self.hydrationTask = nil
                }
            }
        }
    }

    func cancelHydration() {
        hydrationTask?.cancel()
        hydrationTask = nil
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

struct PlaylistView: View {
    let playlist: SpotifyPlaylist
    let isLockScreenMode: Bool

    @EnvironmentObject var musicManager: MusicManager
    @EnvironmentObject private var navigationManager: LockScreenNavigationManager
    @Binding var navigationStack: [NotchWidgetMode]

    @ObservedObject private var spotifyPrivateAPI = SpotifyPrivateAPIManager.shared

    @State private var viewModels: [TrackViewModel] = []
    @State private var isLoading = false
    @State private var showSpotifyNotOpenAlert = false
    @State private var sortOption: SortOption = .customOrder
    @State private var sortDirection: SortDirection = .ascending
    @State private var isUsingPrivateAPI = true

    private let playlistSortStateKey = "playlistSortDescriptors"

    enum SortOption: String, CaseIterable, Identifiable {
        case customOrder = "Custom order"
        case title = "Title"
        case artist = "Artist"
        case album = "Album"
        case dateAdded = "Date added"
        case playCount = "Play count"

        var id: String { rawValue }

        static var playlistColumns: [SortOption] { [.title, .artist, .album, .dateAdded, .playCount] }
    }

    enum SortDirection: String { case ascending, descending }

    init(playlist: SpotifyPlaylist, navigationStack: Binding<[NotchWidgetMode]> = .constant([]), isLockScreenMode: Bool = false) {
        self.playlist = playlist
        self._navigationStack = navigationStack
        self.isLockScreenMode = isLockScreenMode
    }

    private var sortedViewModels: [TrackViewModel] {
        if sortOption == .customOrder {
            return sortDirection == .ascending ? viewModels : viewModels.reversed()
        }
        return viewModels.sorted { lhs, rhs in
            let result: ComparisonResult = {
                switch sortOption {
                case .title: return lhs.name.localizedStandardCompare(rhs.name)
                case .artist: return lhs.artists.localizedStandardCompare(rhs.artists)
                case .album: return lhs.albumName.localizedStandardCompare(rhs.albumName)
                case .dateAdded:
                    let l = lhs.dateAdded ?? 0, r = rhs.dateAdded ?? 0
                    return l < r ? .orderedAscending : (l > r ? .orderedDescending : .orderedSame)
                case .playCount:
                    let l = lhs.playCount ?? 0, r = rhs.playCount ?? 0
                    return l < r ? .orderedAscending : (l > r ? .orderedDescending : .orderedSame)
                case .customOrder: return .orderedSame
                }
            }()
            return sortDirection == .ascending ? (result == .orderedAscending) : (result == .orderedDescending)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            playlistHero

            columnHeaders
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 4)

            ZStack {
                if viewModels.isEmpty {
                    if isLoading {
                        ProgressView().scaleEffect(1.2)
                    } else {
                        Text("This playlist is empty.")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(Array(sortedViewModels.enumerated()), id: \.element.id) { index, viewModel in
                                PlaylistTrackRow(
                                    index: index + 1,
                                    viewModel: viewModel,
                                    contextUri: playlist.uri,
                                    onPlay: handlePlaybackResult,
                                    onArtist: { openArtist(viewModel) },
                                    onAlbum: { openAlbum(viewModel) },
                                    onAddToQueue: {
                                        Task {
                                            _ = await musicManager.spotifyPrivateAPI.addToQueue(
                                                uri: viewModel.uri,
                                                uid: viewModel.uid,
                                                metadata: [
                                                    "title": viewModel.name,
                                                    "artist_name": viewModel.artists,
                                                    "album_title": viewModel.albumName
                                                ]
                                            )
                                        }
                                    }
                                )
                                .onAppear {
                                    if index >= sortedViewModels.count - 5 {
                                        Task { await spotifyPrivateAPI.loadMorePlaylistTracks() }
                                    }
                                }
                            }

                            if spotifyPrivateAPI.isPlaylistLoadingMore {
                                ProgressView()
                                    .padding(.vertical, 12)
                            } else if spotifyPrivateAPI.playlistHasMore {
                                Text("Scroll for more")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                    .padding(.vertical, 8)
                            }

                            if !spotifyPrivateAPI.playlistRecommendations.isEmpty {
                                Text("Recommended")
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.top, 14)
                                    .padding(.horizontal, 4)

                                ForEach(spotifyPrivateAPI.playlistRecommendations) { track in
                                    RecommendedTrackRow(track: track, onPlay: handlePlaybackResult)
                                }
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.bottom, 16)
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
        .frame(width: 820, height: 360)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.ultraThinMaterial.opacity(0.001))
        )
        .task(id: playlist.id) { await loadPlaylistContent() }
        .onReceive(spotifyPrivateAPI.$playlistTrackViewModels.receive(on: DispatchQueue.main)) { models in
            guard isUsingPrivateAPI else { return }
            viewModels = models
        }
        .alert("Spotify App Is Not Open", isPresented: $showSpotifyNotOpenAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("To control playback with a free account, please open the Spotify desktop app first.")
        }
        .onChange(of: sortOption) { _, _ in saveSortState() }
        .onChange(of: sortDirection) { _, _ in saveSortState() }
        .onAppear { loadSortState() }
    }

    // MARK: - Hero

    private var playlistHero: some View {
        HStack(alignment: .center, spacing: 16) {
            CachedAsyncImage(url: playlist.images.first.flatMap { URL(string: $0.url) }) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.accentColor.opacity(0.2))
                    .overlay(Image(systemName: "music.note.list").font(.title2))
            }
            .frame(width: 88, height: 88)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(0.35), radius: 10, y: 4)

            VStack(alignment: .leading, spacing: 6) {
                Text(playlist.name)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .lineLimit(2)

                HStack(spacing: 8) {
                    Text(playlist.owner.displayName)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                    Text("·").foregroundStyle(.tertiary)
                    Text("\(spotifyPrivateAPI.playlistTotalCount > 0 ? spotifyPrivateAPI.playlistTotalCount : viewModels.count) songs")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                    if let perms = musicManager.spotifyPrivateAPI.currentPlaylistPermissions {
                        Text(perms.canEditItems ? "Editable" : "View only")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.primary.opacity(0.08), in: Capsule())
                    }
                }

                HStack(spacing: 8) {
                    tonalButton("Play", systemImage: "play.fill") {
                        Task {
                            if !playlist.uri.hasPrefix("spotify:"),
                               musicManager.lastKnownBundleID == "com.apple.Music" {
                                let ok = musicManager.appleMusic.playPlaylist(persistentID: playlist.id)
                                handlePlaybackResult(ok ? .success : .failure(reason: "Couldn’t play playlist."))
                            } else {
                                handlePlaybackResult(await musicManager.play(contextUri: playlist.uri))
                            }
                        }
                    }
                    tonalButton("Shuffle", systemImage: "shuffle") {
                        Task {
                            if !playlist.uri.hasPrefix("spotify:"),
                               musicManager.lastKnownBundleID == "com.apple.Music" {
                                let ok = musicManager.appleMusic.playPlaylist(persistentID: playlist.id)
                                if ok {
                                    musicManager.appleMusic.setShuffle(enabled: true)
                                    handlePlaybackResult(.success)
                                } else {
                                    handlePlaybackResult(.failure(reason: "Couldn’t play playlist."))
                                }
                            } else {
                                handlePlaybackResult(await musicManager.play(contextUri: playlist.uri))
                                try? await Task.sleep(for: .milliseconds(400))
                                await musicManager.toggleShuffle()
                            }
                        }
                    }
                    if musicManager.spotifyPrivateAPI.smartShuffleAvailable && playlist.uri.hasPrefix("spotify:") {
                        tonalButton("Smart", systemImage: "sparkles") {
                            Task {
                                handlePlaybackResult(await musicManager.spotifyPrivateAPI.playSmartShuffle(playlistURI: playlist.uri))
                            }
                        }
                    }
                    if playlist.uri.hasPrefix("spotify:") {
                        tonalButton(
                            musicManager.spotifyPrivateAPI.isEnhanceLoading ? "…" : "Enhance",
                            systemImage: "wand.and.stars"
                        ) {
                            Task {
                                let ok = await musicManager.spotifyPrivateAPI.applyPlaylistEnhance(playlistId: playlist.id)
                                if ok { handlePlaybackResult(.success) }
                            }
                        }
                        .disabled(musicManager.spotifyPrivateAPI.isEnhanceLoading)
                    }
                }
                .padding(.top, 2)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 8)
    }

    private func tonalButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.accentColor.opacity(0.16), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Column headers (client-side sort)

    private var columnHeaders: some View {
        HStack(spacing: 0) {
            Text("#")
                .frame(width: 28, alignment: .leading)
                .foregroundStyle(.tertiary)

            sortHeader(.title, width: nil, alignment: .leading)
                .frame(minWidth: 220, maxWidth: .infinity, alignment: .leading)

            Text("Added by")
                .frame(width: 100, alignment: .leading)
                .foregroundStyle(.secondary)

            sortHeader(.dateAdded, width: 96, alignment: .trailing)
            sortHeader(.playCount, width: 64, alignment: .trailing)
        }
        .font(.system(size: 10, weight: .bold, design: .rounded))
        .textCase(.uppercase)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func sortHeader(_ option: SortOption, width: CGFloat?, alignment: Alignment) -> some View {
        Button {
            if sortOption == option {
                sortDirection = sortDirection == .ascending ? .descending : .ascending
            } else {
                sortOption = option
                sortDirection = option == .playCount || option == .dateAdded ? .descending : .ascending
            }
            Task { await musicManager.spotifyPrivateAPI.logSortTelemetry() }
        } label: {
            HStack(spacing: 3) {
                Text(option.rawValue)
                if sortOption == option {
                    Image(systemName: sortDirection == .ascending ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                }
            }
            .foregroundStyle(sortOption == option ? Color.accentColor : Color.secondary)
            .frame(width: width, alignment: alignment)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Navigation

    private func openArtist(_ viewModel: TrackViewModel) {
        guard let uri = viewModel.firstArtistURI, !uri.isEmpty else { return }
        push(.musicArtistDetail(uri: uri, name: viewModel.firstArtistName))
    }

    private func openAlbum(_ viewModel: TrackViewModel) {
        guard let uri = viewModel.albumURI, !uri.isEmpty else { return }
        push(.musicAlbumDetail(uri: uri, name: viewModel.albumName))
    }

    private func push(_ mode: NotchWidgetMode) {
        if isLockScreenMode {
            navigationStack.append(mode)
        } else {
            navigationStack.append(mode)
        }
    }

    // MARK: - Load / sort persistence

    private func loadPlaylistContent() async {
        isLoading = true
        viewModels = []

        let isAppleMusicPlaylist = !playlist.uri.hasPrefix("spotify:")
            && musicManager.lastKnownBundleID == "com.apple.Music"
        if isAppleMusicPlaylist {
            isUsingPrivateAPI = false
            let apple = AppleMusicManager.shared
            if !apple.isMusicKitAuthorized, apple.isMusicKitConfigured {
                await apple.requestAuthorization()
            }
            if apple.isMusicKitAuthorized {
                await apple.refreshPlaylistTracks(playlistID: playlist.id)
            }
            let tracks = apple.fetchPlaylistTracks(playlistID: playlist.id)
            viewModels = tracks.map { TrackViewModel(track: $0) }
            isLoading = false
            loadSortState()
            return
        }

        if spotifyPrivateAPI.isLoggedIn {
            isUsingPrivateAPI = true
            spotifyPrivateAPI.playlistTrackViewModels = []
            if playlist.uri.contains(":collection") || playlist.uri.contains(":tracks") {
                await spotifyPrivateAPI.loadLikedSongs(for: playlist)
            } else {
                await spotifyPrivateAPI.loadPlaylist(playlistId: playlist.id)
            }
        } else if musicManager.spotifyOfficialAPI.isAuthenticated {
            isUsingPrivateAPI = false
            if !(playlist.uri.contains(":collection") || playlist.uri.contains(":tracks")),
               let tracks = await musicManager.spotifyOfficialAPI.fetchPlaylistTracks(playlistID: playlist.id) {
                viewModels = tracks.map { TrackViewModel(track: $0) }
            }
        }
        isLoading = false
        loadSortState()
    }

    private func loadSortState() {
        guard let saved = UserDefaults.standard.dictionary(forKey: playlistSortStateKey) as? [String: [String: String]],
              let entry = saved[playlist.id],
              let optionRaw = entry["option"],
              let option = SortOption(rawValue: optionRaw) else { return }
        sortOption = option
        if let dir = entry["direction"], let direction = SortDirection(rawValue: dir) {
            sortDirection = direction
        }
    }

    private func saveSortState() {
        var saved = UserDefaults.standard.dictionary(forKey: playlistSortStateKey) as? [String: [String: String]] ?? [:]
        saved[playlist.id] = ["option": sortOption.rawValue, "direction": sortDirection.rawValue]
        UserDefaults.standard.set(saved, forKey: playlistSortStateKey)
    }

    private func handlePlaybackResult(_ result: PlaybackResult) {
        if case .requiresSpotifyAppOpen = result { showSpotifyNotOpenAlert = true }
    }
}

// MARK: - Track row

private struct PlaylistTrackRow: View {
    let index: Int
    @ObservedObject var viewModel: TrackViewModel
    let contextUri: String
    var onPlay: (PlaybackResult) -> Void
    var onArtist: () -> Void
    var onAlbum: () -> Void
    var onAddToQueue: () -> Void

    @EnvironmentObject var musicManager: MusicManager
    @State private var isHovered = false

    private static let exactDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM d, yyyy"
        return formatter
    }()

    private var dateAddedString: String? {
        guard let timestamp = viewModel.dateAdded else { return nil }
        return Self.exactDateFormatter.string(from: Date(timeIntervalSince1970: timestamp))
    }

    var body: some View {
        HStack(spacing: 0) {
            ZStack {
                Text("\(index)")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .opacity(isHovered ? 0 : 1)
                Image(systemName: "play.fill")
                    .font(.system(size: 10, weight: .bold))
                    .opacity(isHovered ? 1 : 0)
            }
            .frame(width: 28, alignment: .leading)

            HStack(spacing: 10) {
                CachedAsyncImage(url: viewModel.imageURL) { $0.resizable() } placeholder: {
                    RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.2))
                }
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.name)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        Button(action: onArtist) {
                            Text(viewModel.artists)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .disabled(viewModel.firstArtistURI == nil)
                        Text("·").foregroundStyle(.quaternary)
                        Button(action: onAlbum) {
                            Text(viewModel.albumName)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .disabled(viewModel.albumURI == nil)
                    }
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .lineLimit(1)
                }
            }
            .frame(minWidth: 220, maxWidth: .infinity, alignment: .leading)

            Text(viewModel.addedByName ?? "—")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 100, alignment: .leading)

            Text(dateAddedString ?? "—")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.tertiary)
                .frame(width: 96, alignment: .trailing)

            Group {
                if isHovered {
                    TrackHoverActionsView(
                        trackURI: viewModel.uri,
                        trackName: viewModel.name,
                        artistName: viewModel.artists,
                        uid: viewModel.uid
                    )
                    .frame(width: 64, alignment: .trailing)
                } else if let count = viewModel.playCount {
                    PlayCountIndicator(playCount: count)
                        .frame(width: 64, alignment: .trailing)
                } else {
                    Text("—")
                        .foregroundStyle(.tertiary)
                        .frame(width: 64, alignment: .trailing)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isHovered ? Color.primary.opacity(0.07) : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture {
            Task {
                if !contextUri.hasPrefix("spotify:"),
                   musicManager.lastKnownBundleID == "com.apple.Music" {
                    let ok = musicManager.appleMusic.playTrack(
                        persistentID: viewModel.uri,
                        inPlaylistPersistentID: contextUri
                    )
                    onPlay(ok ? .success : .failure(reason: "Couldn’t play this track in Apple Music."))
                } else {
                    onPlay(await musicManager.play(
                        trackUri: viewModel.uri,
                        contextUri: contextUri,
                        trackUid: viewModel.uid,
                        trackIndex: nil
                    ))
                }
            }
        }
        .contextMenu {
            Button("Add to Queue", action: onAddToQueue)
            Button("Play") {
                Task {
                    if !contextUri.hasPrefix("spotify:"),
                       musicManager.lastKnownBundleID == "com.apple.Music" {
                        let ok = musicManager.appleMusic.playTrack(
                            persistentID: viewModel.uri,
                            inPlaylistPersistentID: contextUri
                        )
                        onPlay(ok ? .success : .failure(reason: "Couldn’t play this track in Apple Music."))
                    } else {
                        onPlay(await musicManager.play(
                            trackUri: viewModel.uri,
                            contextUri: contextUri,
                            trackUid: viewModel.uid,
                            trackIndex: nil
                        ))
                    }
                }
            }
        }
    }
}

extension TimeInterval {
    fileprivate func timeAgoDisplay() -> String {
        let date = Date(timeIntervalSince1970: self)
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Consolidated from SpotifyEntityDetailViews.swift

struct SpotifyArtistDetailView: View {
    let uri: String
    let name: String
    @Binding var navigationStack: [NotchWidgetMode]
    @EnvironmentObject var musicManager: MusicManager

    @State private var overview: SpotifyArtistOverview?
    @State private var isLoading = true
    @State private var showSpotifyNotOpenAlert = false

    private var profile: SpotifyArtistProfile? { overview?.profile }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if isLoading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if let profile {
                            ArtistProfileCard(artist: profile)
                        }

                        if let tracks = overview?.topTracks, !tracks.isEmpty {
                            sectionTitle("Popular")
                            ForEach(Array(tracks.prefix(10).enumerated()), id: \.element.id) { index, track in
                                artistTrackRow(track, rank: index + 1)
                            }
                        }

                        if let albums = overview?.albums, !albums.isEmpty {
                            sectionTitle("Albums")
                            horizontalAlbums(albums)
                        }

                        if let singles = overview?.singles, !singles.isEmpty {
                            sectionTitle("Singles & EPs")
                            horizontalAlbums(singles)
                        }

                        if let playlists = overview?.featuringPlaylists, !playlists.isEmpty {
                            sectionTitle("Featuring")
                            ForEach(playlists.prefix(8)) { playlist in
                                featuringPlaylistRow(playlist)
                            }
                        }

                        if let related = overview?.relatedArtists, !related.isEmpty {
                            sectionTitle("Fans also like")
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(related.prefix(12)) { artist in
                                        Button {
                                            navigationStack.append(
                                                .musicArtistDetail(uri: artist.uri, name: artist.name)
                                            )
                                        } label: {
                                            VStack(spacing: 6) {
                                                CachedAsyncImage(url: artist.imageURL) { $0.resizable().aspectRatio(contentMode: .fill) }
                                                    placeholder: { Circle().fill(MaterialChartPalette.surfaceVariant) }
                                                    .frame(width: 64, height: 64)
                                                    .clipShape(Circle())
                                                Text(artist.name)
                                                    .font(.caption.bold())
                                                    .lineLimit(2)
                                                    .frame(width: 72)
                                            }
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }

                        if let concerts = overview?.concerts, !concerts.isEmpty {
                            sectionTitle("Concerts")
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 10) {
                                    ForEach(concerts.prefix(8)) { ConcertCard(concert: $0) }
                                }
                            }
                        }

                        if let profile, !profile.merch.isEmpty {
                            sectionTitle("Merch")
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 10) {
                                    ForEach(profile.merch.prefix(8)) { MerchCard(item: $0) }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                }
            }
        }
        .frame(width: 820, height: 360)
        .task { await load() }
        .alert("Spotify App Is Not Open", isPresented: $showSpotifyNotOpenAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("To control playback with a free account, please open the Spotify desktop app first.")
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(profile?.name ?? name)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                    if profile?.isVerified == true {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(.cyan)
                            .font(.system(size: 14))
                    }
                }
                if let listeners = profile?.monthlyListeners {
                    Text("\(listeners.formatted()) monthly listeners")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                } else if let followers = profile?.followers {
                    Text("\(followers.formatted()) followers")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button {
                Task { handle(await musicManager.play(contextUri: uri)) }
            } label: {
                Label("Play", systemImage: "play.fill")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Color.accentColor.opacity(0.18), in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .bold, design: .rounded))
    }

    private func horizontalAlbums(_ albums: [SpotifySearchAlbum]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(albums.prefix(16)) { album in
                    Button {
                        navigationStack.append(.musicAlbumDetail(uri: album.uri, name: album.name))
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            CachedAsyncImage(url: album.imageURL) { $0.resizable().aspectRatio(contentMode: .fill) }
                                placeholder: { RoundedRectangle(cornerRadius: 10).fill(MaterialChartPalette.surfaceVariant) }
                                .frame(width: 100, height: 100)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            Text(album.name)
                                .font(.caption.bold())
                                .lineLimit(2)
                                .frame(width: 100, alignment: .leading)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @State private var hoveredArtistTrackURI: String?

    private func artistTrackRow(_ track: SpotifySearchTrack, rank: Int) -> some View {
        let isHovered = hoveredArtistTrackURI == track.uri
        return HStack(spacing: 10) {
            Text("\(rank)")
                .font(.system(size: 11, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 18, alignment: .trailing)

            CachedAsyncImage(url: track.imageURL) { $0.resizable() }
                placeholder: { RoundedRectangle(cornerRadius: 6).fill(MaterialChartPalette.surfaceVariant) }
                .frame(width: 34, height: 34)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(track.name)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                Text(track.artists)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            TrackHoverActionsView(
                trackURI: track.uri,
                trackName: track.name,
                artistName: track.artists
            )
            .opacity(isHovered ? 1 : 0)
            Button {
                Task { handle(await musicManager.play(trackUri: track.uri, contextUri: uri)) }
            } label: {
                Image(systemName: "play.fill")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 28, height: 28)
                    .background(MaterialChartPalette.primary.opacity(0.16), in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
        .onHover { hovering in hoveredArtistTrackURI = hovering ? track.uri : nil }
    }

    private func featuringPlaylistRow(_ playlist: SpotifySearchPlaylistHit) -> some View {
        Button {
            let id = playlist.uri.components(separatedBy: ":").last ?? playlist.id
            navigationStack.append(
                .musicPlaylistDetail(
                    SpotifyPlaylist(
                        id: id,
                        name: playlist.name,
                        uri: playlist.uri,
                        images: playlist.imageURL.map { [SpotifyImage(url: $0.absoluteString)] } ?? [],
                        owner: SpotifyUserSimple(id: "", displayName: playlist.ownerName ?? "Spotify", images: nil),
                        collaborators: nil
                    )
                )
            )
        } label: {
            HStack(spacing: 10) {
                CachedAsyncImage(url: playlist.imageURL) { $0.resizable() }
                    placeholder: { RoundedRectangle(cornerRadius: 8).fill(MaterialChartPalette.surfaceVariant) }
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(playlist.name)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                    Text(playlist.ownerName ?? "Playlist")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    private func load() async {
        isLoading = true
        if let result = await musicManager.spotifyPrivateAPI.fetchArtistOverview(uri: uri) {
            overview = result
        } else {
            let trackURI = musicManager.uri ?? musicManager.nowPlayingTrack?.uri ?? "spotify:track:0"
            let concerts = await musicManager.spotifyPrivateAPI.fetchArtistConcerts(
                artistURI: uri,
                trackURI: trackURI
            )
            if let npv = musicManager.spotifyPrivateAPI.nowPlayingArtist, npv.uri == uri || npv.name == name {
                overview = SpotifyArtistOverview(
                    profile: npv,
                    topTracks: [],
                    albums: [],
                    singles: [],
                    featuringPlaylists: [],
                    relatedArtists: [],
                    concerts: concerts
                )
            } else {
                overview = SpotifyArtistOverview(
                    profile: SpotifyArtistProfile(
                        uri: uri,
                        name: name,
                        biography: "",
                        monthlyListeners: nil,
                        followers: nil,
                        headerImageURL: nil,
                        avatarURL: nil,
                        isVerified: false,
                        topCities: [],
                        merch: []
                    ),
                    topTracks: [],
                    albums: [],
                    singles: [],
                    featuringPlaylists: [],
                    relatedArtists: [],
                    concerts: concerts
                )
            }
        }
        isLoading = false
    }

    private func handle(_ result: PlaybackResult) {
        if case .requiresSpotifyAppOpen = result { showSpotifyNotOpenAlert = true }
    }
}

struct SpotifyAlbumDetailView: View {
    let uri: String
    let name: String
    @Binding var navigationStack: [NotchWidgetMode]
    @EnvironmentObject var musicManager: MusicManager

    @State private var tracks: [SpotifyRecommendedTrack] = []
    @State private var isLoading = true
    @State private var showSpotifyNotOpenAlert = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Text(name)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .lineLimit(1)
                Spacer()
                Button {
                    Task { handle(await musicManager.play(contextUri: uri)) }
                } label: {
                    Label("Play album", systemImage: "play.fill")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Color.accentColor.opacity(0.18), in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)

            if isLoading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if tracks.isEmpty {
                ContentUnavailableView(
                    "Album tracks",
                    systemImage: "opticaldisc",
                    description: Text("Play the album, or open it in Spotify for the full track list.")
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(tracks) { track in
                            RecommendedTrackRow(track: track) { handle($0) }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                }
            }
        }
        .frame(width: 820, height: 360)
        .task { await load() }
        .alert("Spotify App Is Not Open", isPresented: $showSpotifyNotOpenAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("To control playback with a free account, please open the Spotify desktop app first.")
        }
    }

    private func load() async {
        isLoading = true
        tracks = await musicManager.spotifyPrivateAPI.fetchAlbumTracks(albumURI: uri)
        isLoading = false
    }

    private func handle(_ result: PlaybackResult) {
        if case .requiresSpotifyAppOpen = result { showSpotifyNotOpenAlert = true }
    }
}

// MARK: - Consolidated from SpotifyMusicSearchView.swift

struct SpotifyMusicSearchView: View {
    @Binding var navigationStack: [NotchWidgetMode]
    var onPlaySuccess: () -> Void = {}
    var emptyReplacement: (() -> AnyView)? = nil
    var autofocusSearch: Bool = true

    @EnvironmentObject var musicManager: MusicManager

    @State private var query = ""
    @State private var suggestions: [SpotifySearchSuggestion] = []
    @State private var results: SpotifySearchTopResults = .empty
    @State private var isSearching = false
    @State private var debounceTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                NotchSearchField(
                    placeholder: "Search songs, artists, albums…",
                    text: $query,
                    autofocus: autofocusSearch
                )
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .onChange(of: query) { _, newValue in
                    scheduleSearch(newValue)
                }
                if !query.isEmpty {
                    Button {
                        query = ""
                        suggestions = []
                        results = .empty
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(MaterialChartPalette.surfaceContainer)
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(MaterialChartPalette.cardGradient(for: MaterialChartPalette.primary))
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(MaterialChartPalette.primary.opacity(0.2), lineWidth: 1)
            )

            if isSearching && results.isEmpty && suggestions.isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if let emptyReplacement {
                    emptyReplacement()
                } else {
                    CustomUnavailableView(
                        title: "Search Spotify",
                        systemImage: "magnifyingglass",
                        description: "Find tracks, artists, albums, and playlists."
                    )
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if !suggestions.isEmpty {
                            Text("Suggestions")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundStyle(.secondary)
                            FlowWrap(items: suggestions.prefix(8).map(\.text)) { text in
                                Button {
                                    query = text
                                    scheduleSearch(text, immediate: true)
                                } label: {
                                    Text(text)
                                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(MaterialChartPalette.primary.opacity(0.14), in: Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        if !results.tracks.isEmpty {
                            sectionHeader("Songs")
                            ForEach(results.tracks.prefix(8)) { track in
                                searchTrackRow(track)
                            }
                        }
                        if !results.artists.isEmpty {
                            sectionHeader("Artists")
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(results.artists.prefix(12)) { artist in
                                        Button {
                                            navigationStack.append(
                                                .musicArtistDetail(uri: artist.uri, name: artist.name)
                                            )
                                        } label: {
                                            VStack(spacing: 6) {
                                                CachedAsyncImage(url: artist.imageURL) { $0.resizable().aspectRatio(contentMode: .fill) }
                                                    placeholder: { Circle().fill(MaterialChartPalette.surfaceVariant) }
                                                    .frame(width: 72, height: 72)
                                                    .clipShape(Circle())
                                                Text(artist.name)
                                                    .font(.caption.bold())
                                                    .lineLimit(2)
                                                    .frame(width: 80)
                                            }
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                        if !results.albums.isEmpty {
                            sectionHeader("Albums")
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(results.albums.prefix(12)) { album in
                                        Button {
                                            navigationStack.append(
                                                .musicAlbumDetail(uri: album.uri, name: album.name)
                                            )
                                        } label: {
                                            VStack(alignment: .leading, spacing: 6) {
                                                CachedAsyncImage(url: album.imageURL) { $0.resizable().aspectRatio(contentMode: .fill) }
                                                    placeholder: { RoundedRectangle(cornerRadius: 10).fill(MaterialChartPalette.surfaceVariant) }
                                                    .frame(width: 100, height: 100)
                                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                                Text(album.name).font(.caption.bold()).lineLimit(2).frame(width: 100, alignment: .leading)
                                                Text(album.artistName).font(.caption2).foregroundStyle(.secondary).lineLimit(1).frame(width: 100, alignment: .leading)
                                            }
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                        if !results.playlists.isEmpty {
                            sectionHeader("Playlists")
                            ForEach(results.playlists.prefix(8)) { playlist in
                                Button {
                                    let id = playlist.uri.components(separatedBy: ":").last ?? playlist.id
                                    navigationStack.append(
                                        .musicPlaylistDetail(
                                            SpotifyPlaylist(
                                                id: id,
                                                name: playlist.name,
                                                uri: playlist.uri,
                                                images: playlist.imageURL.map { [SpotifyImage(url: $0.absoluteString)] } ?? [],
                                                owner: SpotifyUserSimple(id: "", displayName: playlist.ownerName ?? "Spotify", images: nil),
                                                collaborators: nil
                                            )
                                        )
                                    )
                                } label: {
                                    HStack(spacing: 10) {
                                        CachedAsyncImage(url: playlist.imageURL) { $0.resizable() }
                                            placeholder: { RoundedRectangle(cornerRadius: 8).fill(MaterialChartPalette.surfaceVariant) }
                                            .frame(width: 40, height: 40)
                                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(playlist.name).font(.system(size: 12, weight: .semibold, design: .rounded)).lineLimit(1)
                                            Text(playlist.ownerName ?? "Playlist")
                                                .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                        }
                                        Spacer()
                                        Button {
                                            Task {
                                                let result = await musicManager.play(contextUri: playlist.uri)
                                                if case .success = result { onPlaySuccess() }
                                            }
                                        } label: {
                                            Image(systemName: "play.fill")
                                                .font(.system(size: 11, weight: .bold))
                                                .frame(width: 28, height: 28)
                                                .background(MaterialChartPalette.primary.opacity(0.16), in: Circle())
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(.vertical, 4)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.bottom, 24)
                }
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(.secondary)
            .padding(.top, 4)
    }

    @State private var hoveredSearchTrackURI: String?

    private func searchTrackRow(_ track: SpotifySearchTrack) -> some View {
        let isHovered = hoveredSearchTrackURI == track.uri
        return HStack(spacing: 10) {
            CachedAsyncImage(url: track.imageURL) { $0.resizable() }
                placeholder: { RoundedRectangle(cornerRadius: 8).fill(MaterialChartPalette.surfaceVariant) }
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(track.name).font(.system(size: 12, weight: .semibold, design: .rounded)).lineLimit(1)
                Text(track.artists).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            TrackHoverActionsView(
                trackURI: track.uri,
                trackName: track.name,
                artistName: track.artists
            )
            .opacity(isHovered ? 1 : 0)
            Button {
                Task {
                    let result = await musicManager.play(trackUri: track.uri, contextUri: nil)
                    if case .success = result { onPlaySuccess() }
                }
            } label: {
                Image(systemName: "play.fill")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 28, height: 28)
                    .background(MaterialChartPalette.secondary.opacity(0.18), in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(MaterialChartPalette.surfaceContainer)
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(MaterialChartPalette.cardGradient(for: MaterialChartPalette.secondary))
            }
        )
        .onHover { hovering in hoveredSearchTrackURI = hovering ? track.uri : nil }
    }

    private func scheduleSearch(_ raw: String, immediate: Bool = false) {
        debounceTask?.cancel()
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            suggestions = []
            results = .empty
            isSearching = false
            return
        }
        debounceTask = Task {
            if !immediate {
                try? await Task.sleep(for: .milliseconds(280))
            }
            guard !Task.isCancelled else { return }
            await MainActor.run { isSearching = true }
            async let sugg = musicManager.spotifyPrivateAPI.searchSuggestions(query: trimmed)
            async let top = musicManager.spotifyPrivateAPI.searchTopResults(query: trimmed)
            let (s, t) = await (sugg, top)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                suggestions = s
                results = t
                isSearching = false
            }
        }
    }
}

private struct FlowWrap<Item: Hashable, Content: View>: View {
    let items: [Item]
    @ViewBuilder let content: (Item) -> Content

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(items, id: \.self) { content($0) }
            }
        }
    }
}

// MARK: - Consolidated from SpotifyNowPlayingExtras.swift

struct SpotifyNowPlayingExtras: View {
    @EnvironmentObject var musicManager: MusicManager

    private var artist: SpotifyArtistProfile? {
        musicManager.spotifyPrivateAPI.nowPlayingArtist
    }

    private var concerts: [SpotifyArtistConcert] {
        musicManager.spotifyPrivateAPI.artistConcerts
    }

    private var related: [SpotifyRecommendedTrack] {
        Array(musicManager.spotifyPrivateAPI.relatedTracks.prefix(4))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let artist {
                HStack(spacing: 10) {
                    if let url = artist.avatarURL ?? artist.headerImageURL {
                        CachedAsyncImage(url: url) { $0.resizable().aspectRatio(contentMode: .fill) } placeholder: {
                            Circle().fill(Color.white.opacity(0.08))
                        }
                        .frame(width: 28, height: 28)
                        .clipShape(Circle())
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 4) {
                            Text(artist.name)
                                .font(.system(size: 11, weight: .semibold))
                                .lineLimit(1)
                            if artist.isVerified {
                                Image(systemName: "checkmark.seal.fill")
                                    .font(.system(size: 9))
                                    .foregroundColor(.cyan)
                            }
                        }
                        if let listeners = artist.monthlyListeners {
                            Text(formattedCount(listeners) + " monthly listeners")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }

            if !concerts.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(concerts.prefix(4)) { concert in
                            HStack(spacing: 6) {
                                Image(systemName: "ticket.fill").font(.caption2)
                                Text("\(concert.title) · \(concert.city)")
                                    .font(.caption2)
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.white.opacity(0.08))
                            .clipShape(Capsule())
                        }
                    }
                }
            }

            if !related.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(related) { track in
                            Button {
                                Task {
                                    _ = await musicManager.play(trackUri: track.uri, contextUri: nil)
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "sparkles").font(.caption2)
                                    Text(track.name)
                                        .font(.caption2)
                                        .lineLimit(1)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.accentColor.opacity(0.15))
                                .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func formattedCount(_ value: Int) -> String {
        if value >= 1_000_000 { return String(format: "%.1fM", Double(value) / 1_000_000) }
        if value >= 1_000 { return String(format: "%.1fK", Double(value) / 1_000) }
        return "\(value)"
    }
}

struct ArtistProfileCard: View {
    let artist: SpotifyArtistProfile

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                if let url = artist.avatarURL ?? artist.headerImageURL {
                    CachedAsyncImage(url: url) { $0.resizable().aspectRatio(contentMode: .fill) } placeholder: {
                        RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.08))
                    }
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(artist.name).font(.headline.bold()).lineLimit(1)
                        if artist.isVerified {
                            Image(systemName: "checkmark.seal.fill").foregroundColor(.cyan)
                        }
                    }
                    if let listeners = artist.monthlyListeners {
                        Text("\(listeners.formatted()) monthly listeners")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    if !artist.topCities.isEmpty {
                        Text(artist.topCities.joined(separator: " · "))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }

            if !artist.biography.isEmpty {
                Text(artist.biography)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(4)
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct SimilarAlbumCard: View {
    let album: SpotifySimilarAlbum
    var onPlay: (PlaybackResult) -> Void
    @EnvironmentObject var musicManager: MusicManager
    @State private var isHovered = false

    var body: some View {
        Button {
            Task {
                onPlay(await musicManager.play(contextUri: album.uri))
            }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                CachedAsyncImage(url: album.imageURL) { $0.resizable().aspectRatio(contentMode: .fill) } placeholder: {
                    ZStack {
                        Color.secondary.opacity(0.25)
                        Image(systemName: "opticaldisc")
                    }
                }
                .frame(width: 110, height: 110)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                Text(album.name)
                    .font(.caption.bold())
                    .lineLimit(1)
                    .frame(width: 110, alignment: .leading)
                Text(album.artistName)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .frame(width: 110, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
        .padding(4)
        .background(Color.white.opacity(isHovered ? 0.1 : 0), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
    }
}

struct ConcertCard: View {
    let concert: SpotifyArtistConcert
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: "ticket.fill")
                .font(.title3)
                .foregroundColor(.pink)
            Text(concert.title)
                .font(.caption.bold())
                .lineLimit(2)
                .frame(width: 130, alignment: .leading)
            Text(concert.venue.isEmpty ? concert.city : "\(concert.venue), \(concert.city)")
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(2)
                .frame(width: 130, alignment: .leading)
            if !concert.startDateIsoString.isEmpty {
                Text(concert.startDateIsoString.prefix(10))
                    .font(.caption2.monospacedDigit())
                    .foregroundColor(.secondary)
            }
        }
        .padding(10)
        .frame(width: 150, alignment: .leading)
        .background(Color.white.opacity(isHovered ? 0.15 : 0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
    }
}

struct MerchCard: View {
    let item: SpotifyArtistMerch
    @State private var isHovered = false

    var body: some View {
        Button {
            if let url = URL(string: item.uri) {
                NSWorkspace.shared.open(url)
            }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                CachedAsyncImage(url: item.imageURL) { $0.resizable().aspectRatio(contentMode: .fill) } placeholder: {
                    ZStack {
                        Color.secondary.opacity(0.25)
                        Image(systemName: "tshirt")
                    }
                }
                .frame(width: 110, height: 110)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                Text(item.name)
                    .font(.caption.bold())
                    .lineLimit(2)
                    .frame(width: 110, alignment: .leading)
                if let price = item.price {
                    Text(price)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
        .padding(4)
        .background(Color.white.opacity(isHovered ? 0.1 : 0), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
    }
}

// MARK: - Consolidated from SpotifyCanvasView.swift

struct SpotifyCanvasView: View {
    let canvasURL: URL
    @StateObject private var model = CanvasPlayerModel()

    var body: some View {
        CanvasPlayerRepresentable(player: model.player)
            .onAppear { model.play(url: canvasURL) }
            .onChange(of: canvasURL) { _, newURL in
                model.play(url: newURL)
            }
            .onDisappear { model.stop() }
    }
}

@MainActor
private final class CanvasPlayerModel: ObservableObject {
    let player = AVPlayer()
    private var loopObserver: NSObjectProtocol?
    private var currentURL: URL?

    func play(url: URL) {
        guard currentURL != url else {
            player.play()
            return
        }
        stop()
        currentURL = url
        let item = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: item)
        player.isMuted = true
        player.actionAtItemEnd = .none
        loopObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            self?.player.seek(to: .zero)
            self?.player.play()
        }
        player.play()
    }

    func stop() {
        if let loopObserver {
            NotificationCenter.default.removeObserver(loopObserver)
        }
        loopObserver = nil
        player.pause()
        player.replaceCurrentItem(with: nil)
        currentURL = nil
    }
}

private struct CanvasPlayerRepresentable: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> CanvasPlayerNSView {
        CanvasPlayerNSView(player: player)
    }

    func updateNSView(_ nsView: CanvasPlayerNSView, context: Context) {
        nsView.playerLayer.player = player
    }
}

private final class CanvasPlayerNSView: NSView {
    let playerLayer = AVPlayerLayer()

    init(player: AVPlayer) {
        super.init(frame: .zero)
        wantsLayer = true
        playerLayer.player = player
        playerLayer.videoGravity = .resizeAspectFill
        layer?.addSublayer(playerLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        playerLayer.frame = bounds
    }
}

struct SpotifyAccountBadge: View {
    let accountInfo: SpotifyAccountInfo?

    var body: some View {
        if let info = accountInfo, info.isPremium {
            Text("PREMIUM")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.green.opacity(0.25))
                .foregroundColor(.green)
                .clipShape(Capsule())
        }
    }
}

// MARK: - Consolidated from LoginPromptView.swift

struct LoginPromptView: View {
    @Binding var navigationStack: [NotchWidgetMode]

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundColor(.yellow)

            Text("Login Required")
                .font(.title2).bold()

            Text("Please log in to Spotify via the Music section in Sapphire's settings to use this feature.")
                .font(.subheadline).foregroundColor(.secondary).multilineTextAlignment(.center)

            Text("Use the back control in the notch to return.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(30)
        .frame(width: 400)
    }
}

struct ApiKeysMissingView: View {
    @Binding var navigationStack: [NotchWidgetMode]

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "key.viewfinder")
                .font(.system(size: 40))
                .foregroundColor(.yellow)

            Text("Spotify API Keys Missing")
                .font(.title2).bold()

            Text("To enable Spotify integration, please add your API credentials in Sapphire's settings.")
                .font(.subheadline).foregroundColor(.secondary).multilineTextAlignment(.center)

            Text("Use the back control in the notch to return.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(30)
        .frame(width: 400)
    }
}

struct GeminiApiKeysMissingView: View {
    @Binding var navigationStack: [NotchWidgetMode]

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "key.viewfinder")
                .font(.system(size: 40))
                .symbolRenderingMode(.multicolor)

            Text("Gemini API Key Missing")
                .font(.title2).bold()

            Text("To use Gemini Live, please add your Google AI Studio API key in Sapphire's settings.")
                .font(.subheadline).foregroundColor(.secondary).multilineTextAlignment(.center)

            Text("Use the back control in the notch to return.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(30)
        .frame(width: 400)
    }
}

// MARK: - Consolidated from AppleMusicSearchView.swift

// MARK: - View Model

@MainActor
private class AppleMusicSearchViewModel: ObservableObject {
    @Published var query = ""
    @Published var results = AppleMusicSearchResults()
    @Published var charts: [AppleMusicSong] = []
    @Published var albumCharts: [AppleMusicAlbum] = []
    @Published var recentlyPlayed: [AppleMusicSong] = []
    @Published var recentlyAdded: [AppleMusicSong] = []
    @Published var forYou: [AppleMusicPlaylist] = []
    @Published var heavyRotation: [AppleMusicAlbum] = []
    @Published var replay = AppleMusicReplaySummary()
    @Published var suggestions: [String] = []
    @Published var discoverLoaded = false
    @Published var isSearching = false
    @Published var errorMessage: String?
    @Published var hasSearched = false

    private var searchTask: Task<Void, Never>?
    private var suggestionTask: Task<Void, Never>?

    func loadDiscover() async {
        guard !discoverLoaded else { return }
        discoverLoaded = true
        let apple = MusicManager.shared.appleMusic
        async let c1 = apple.charts()
        async let a1 = apple.albumCharts()
        async let r1 = apple.recentlyPlayed()
        async let ra1 = apple.recentlyAdded()
        async let f1 = apple.forYouPlaylists()
        async let h1 = apple.heavyRotationAlbums()
        async let p1 = apple.latestReplay()
        let (chartsValue, albumChartsValue, recentValue, recentlyAddedValue, forYouValue, heavyValue, replayValue) =
            await (c1, a1, r1, ra1, f1, h1, p1)
        guard !Task.isCancelled else { return }
        self.charts = chartsValue
        self.albumCharts = albumChartsValue
        self.recentlyPlayed = recentValue
        self.recentlyAdded = recentlyAddedValue
        self.forYou = forYouValue
        self.heavyRotation = heavyValue
        self.replay = replayValue
    }

    func search() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { results = AppleMusicSearchResults(); hasSearched = false; return }

        searchTask?.cancel()
        isSearching = true
        errorMessage = nil

        searchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }

            let apple = MusicManager.shared.appleMusic
            if let loaded = await apple.search(trimmed) as AppleMusicSearchResults? {
                guard !Task.isCancelled else { return }
                self.results = loaded
            }
            self.isSearching = false
            self.hasSearched = true
        }
    }

    func updateSuggestions() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            suggestions = []
            suggestionTask?.cancel()
            return
        }
        suggestionTask?.cancel()
        suggestionTask = Task {
            try? await Task.sleep(nanoseconds: 180_000_000)
            guard !Task.isCancelled else { return }
            let loaded = await MusicManager.shared.appleMusic.searchSuggestions(trimmed)
            guard !Task.isCancelled else { return }
            self.suggestions = loaded
        }
    }

    func play(_ song: AppleMusicSong) {
        Task {
            _ = await MusicKitAppleMusicManager.shared.play(songIDs: [song.id])
            MusicManager.shared.appleMusic.setUpNextFromSearch(self.results.songs)
        }
    }

    func playAlbum(_ album: AppleMusicAlbum) {
        Task {
            _ = await MusicManager.shared.appleMusic.playAlbum(albumID: album.id)
        }
    }

    func playArtist(_ artist: AppleMusicArtist) {
        Task {
            _ = await MusicManager.shared.appleMusic.playArtistTopTracks(artistID: artist.id)
        }
    }

    func playPlaylist(_ playlist: AppleMusicPlaylist) {
        Task {
            _ = await MusicManager.shared.appleMusic.playCatalogPlaylist(playlistID: playlist.id)
        }
    }

    func addToLibrary(_ song: AppleMusicSong) {
        Task {
            _ = await MusicManager.shared.appleMusic.addToLibrary(songIDs: [song.id])
        }
    }
}

// MARK: - View

struct AppleMusicSearchView: View {
    @Binding var navigationStack: [NotchWidgetMode]
    @EnvironmentObject var musicManager: MusicManager
    @EnvironmentObject var settings: SettingsModel
    @StateObject private var vm = AppleMusicSearchViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                TextField("Search Apple Music…", text: $vm.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .onSubmit { vm.search() }
                    .onChange(of: vm.query) { _, _ in
                        vm.search()
                        vm.updateSuggestions()
                    }
                if vm.isSearching {
                    ProgressView().controlSize(.small)
                } else if !vm.query.isEmpty {
                    Button {
                        vm.query = ""
                        vm.results = AppleMusicSearchResults()
                        vm.suggestions = []
                        vm.hasSearched = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )

            Group {
                if let error = vm.errorMessage {
                    centeredPlaceholder(systemImage: "wifi.exclamationmark", label: error)
                } else if vm.isSearching && vm.results.isEmpty {
                    centeredPlaceholder(systemImage: "magnifyingglass", label: "Searching…")
                } else if vm.results.isEmpty && vm.hasSearched {
                    centeredPlaceholder(systemImage: "music.note", label: "No results for \"\(vm.query)\"")
                } else if !vm.suggestions.isEmpty && vm.query.count >= 2 && vm.results.isEmpty && !vm.hasSearched {
                    suggestionsList
                } else if vm.results.isEmpty {
                    let seed = musicManager.artist ?? ""
                    if seed.isEmpty && vm.query.isEmpty {
                        discoverSections
                    } else {
                        centeredPlaceholder(
                            systemImage: "music.quarternote.3",
                            label: seed.isEmpty ? "Search for songs, artists or albums" : "Discover more like \(seed)"
                        )
                        .onAppear {
                            if !seed.isEmpty && vm.query.isEmpty {
                                vm.query = seed
                                vm.search()
                            }
                        }
                    }
                } else {
                    resultsList
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task { await vm.loadDiscover() }
    }

    private var suggestionsList: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(vm.suggestions, id: \.self) { suggestion in
                    Button {
                        vm.query = suggestion
                        vm.search()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                            Text(suggestion)
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(.primary)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.bottom, 20)
        }
    }

    private var resultsList: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 8) {
                if !vm.results.songs.isEmpty {
                    resultSection("Songs", systemImage: "music.note") {
                        ForEach(vm.results.songs.prefix(8)) { song in
                            AppleMusicSongRow(song: song) {
                                vm.play(song)
                            }
                            .contextMenu {
                                Button("Play") { vm.play(song) }
                                Button("Add to Library") { vm.addToLibrary(song) }
                            }
                        }
                    }
                }
                if !vm.results.albums.isEmpty {
                    resultSection("Albums", systemImage: "square.stack") {
                        ForEach(vm.results.albums.prefix(6)) { album in
                            AppleMusicAlbumRow(album: album) {
                                vm.playAlbum(album)
                            }
                        }
                    }
                }
                if !vm.results.artists.isEmpty {
                    resultSection("Artists", systemImage: "music.mic") {
                        ForEach(vm.results.artists.prefix(6)) { artist in
                            AppleMusicArtistRow(artist: artist) {
                                vm.playArtist(artist)
                            }
                        }
                    }
                }
                if !vm.results.playlists.isEmpty {
                    resultSection("Playlists", systemImage: "music.note.list") {
                        ForEach(vm.results.playlists.prefix(6)) { playlist in
                            AppleMusicPlaylistRow(playlist: playlist) {
                                vm.playPlaylist(playlist)
                            }
                        }
                    }
                }
                if vm.results.isEmpty {
                    centeredPlaceholder(systemImage: "music.note", label: "No results for \"\(vm.query)\"")
                }
            }
            .padding(.bottom, 20)
        }
    }

    private func resultSection<Content: View>(
        _ title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .textCase(.uppercase)
                .foregroundStyle(.tertiary)
            content()
        }
    }

    private var discoverSections: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                if !vm.forYou.isEmpty {
                    discoverSection(title: "Made for You", systemImage: "sparkles") {
                        ForEach(vm.forYou.prefix(5)) { playlist in
                            AppleMusicPlaylistRow(playlist: playlist) {
                                Task { _ = await musicManager.appleMusic.playCatalogPlaylist(playlistID: playlist.id) }
                            }
                        }
                    }
                }
                if !vm.replay.topSongs.isEmpty {
                    discoverSection(title: "Your Replay", systemImage: "arrow.clockwise.circle.fill") {
                        ForEach(vm.replay.topSongs.prefix(6)) { track in
                            SuggestedAppleTrackRow(track: track) {
                                Task { _ = musicManager.appleMusic.playTrack(persistentID: track.id) }
                            }
                        }
                    }
                }
                if !vm.charts.isEmpty {
                    discoverSection(title: "Top Charts", systemImage: "chart.bar.fill") {
                        ForEach(vm.charts.prefix(8)) { track in
                            SuggestedAppleTrackRow(track: track) {
                                Task { _ = musicManager.appleMusic.playTrack(persistentID: track.id) }
                            }
                        }
                    }
                }
                if !vm.albumCharts.isEmpty {
                    discoverSection(title: "Top Albums", systemImage: "square.stack.fill") {
                        ForEach(vm.albumCharts.prefix(6)) { album in
                            AppleMusicAlbumRow(album: album) {
                                Task { _ = await musicManager.appleMusic.playAlbum(albumID: album.id) }
                            }
                        }
                    }
                }
                if !vm.recentlyPlayed.isEmpty {
                    discoverSection(title: "Recently Played", systemImage: "clock.fill") {
                        ForEach(vm.recentlyPlayed.prefix(6)) { track in
                            SuggestedAppleTrackRow(track: track) {
                                Task { _ = musicManager.appleMusic.playTrack(persistentID: track.id) }
                            }
                        }
                    }
                }
                if !vm.recentlyAdded.isEmpty {
                    discoverSection(title: "Recently Added", systemImage: "plus.circle.fill") {
                        ForEach(vm.recentlyAdded.prefix(6)) { track in
                            SuggestedAppleTrackRow(track: track) {
                                Task { _ = musicManager.appleMusic.playTrack(persistentID: track.id) }
                            }
                        }
                    }
                }
                if !vm.heavyRotation.isEmpty {
                    discoverSection(title: "Heavy Rotation", systemImage: "repeat") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(vm.heavyRotation.prefix(8)) { album in
                                    Button {
                                        Task { _ = await musicManager.appleMusic.playAlbum(albumID: album.id) }
                                    } label: {
                                        VStack(alignment: .leading, spacing: 4) {
                                            CachedAsyncImage(url: album.artworkURL) { img in
                                                img.resizable().aspectRatio(contentMode: .fill)
                                            } placeholder: {
                                                ZStack {
                                                    Color.white.opacity(0.08)
                                                    Image(systemName: "square.stack")
                                                        .foregroundStyle(.secondary)
                                                }
                                            }
                                            .frame(width: 64, height: 64)
                                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                                            Text(album.title)
                                                .font(.system(size: 9, weight: .semibold, design: .rounded))
                                                .lineLimit(1)
                                                .frame(width: 64, alignment: .leading)
                                        }
                                        .frame(width: 64)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.leading, 2)
                        }
                    }
                }
                if vm.discoverLoaded && vm.charts.isEmpty && vm.recentlyPlayed.isEmpty && vm.forYou.isEmpty && vm.replay.topSongs.isEmpty {
                    centeredPlaceholder(
                        systemImage: "music.quarternote.3",
                        label: "Search for songs, artists or albums"
                    )
                }

                appleMusicStatusCard
            }
            .padding(.top, 2)
            .padding(.bottom, 20)
        }
    }

    private var appleMusicStatusCard: some View {
        let api = MusicManager.shared.appleMusicPrivateAPI
        let devOK = MusicKitTokenStore.hasDeveloperToken
        let userOK = api.isLoggedIn
        let symbol = devOK && userOK ? "checkmark.circle.fill" : (devOK ? "exclamationmark.triangle.fill" : "xmark.circle.fill")
        let tint: Color = devOK && userOK ? .green : (devOK ? .orange : .red)
        return VStack(alignment: .leading, spacing: 4) {
            Label("Apple Music connection", systemImage: symbol)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(tint)
            Text(api.diagnosticsSummary)
                .font(.system(size: 10, weight: .regular, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(4)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }

    private func discoverSection<Content: View>(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(MaterialChartPalette.secondary)
                .labelStyle(.titleAndIcon)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(MaterialChartPalette.surface.opacity(0.45))
        )
    }

    private func centeredPlaceholder(systemImage: String, label: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.tertiary)
            Text(label)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Apple Music result rows

private struct AppleMusicSongRow: View {
    let song: AppleMusicSong
    let onTap: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                CachedAsyncImage(url: song.artworkURL) { img in
                    img.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    ZStack {
                        Color.white.opacity(0.08)
                        Image(systemName: "music.note")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 38, height: 38)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(song.title)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                    Text(song.artistName)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)

                Image(systemName: "play.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isHovered ? Color.secondary : Color.clear)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(isHovered ? 0.07 : 0))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

private struct AppleMusicAlbumRow: View {
    let album: AppleMusicAlbum
    let onTap: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                CachedAsyncImage(url: album.artworkURL) { img in
                    img.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    ZStack {
                        Color.white.opacity(0.08)
                        Image(systemName: "square.stack")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 38, height: 38)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(album.title)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                    Text(album.artistName)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)

                Image(systemName: "play.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isHovered ? Color.secondary : Color.clear)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

private struct AppleMusicArtistRow: View {
    let artist: AppleMusicArtist
    let onTap: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                CachedAsyncImage(url: artist.artworkURL) { img in
                    img.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    ZStack {
                        Color.white.opacity(0.08)
                        Image(systemName: "music.mic")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 38, height: 38)
                .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(artist.name)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                    Text("Artist")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)

                Image(systemName: "play.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isHovered ? Color.secondary : Color.clear)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

private struct SuggestedAppleTrackRow: View {
    let track: AppleMusicSong
    let onTap: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                CachedAsyncImage(url: track.artworkURL) { img in
                    img.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    ZStack {
                        Color.white.opacity(0.08)
                        Image(systemName: "music.note")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 34, height: 34)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                        .foregroundStyle(.primary)
                    Text(track.artistName)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)

                Image(systemName: "play.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isHovered ? Color.secondary : Color.clear)
            }
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

private struct AppleMusicPlaylistRow: View {
    let playlist: AppleMusicPlaylist
    let onTap: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                CachedAsyncImage(url: playlist.artworkURL) { img in
                    img.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    ZStack {
                        Color.white.opacity(0.08)
                        Image(systemName: "music.note.list")
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 34, height: 34)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(playlist.name)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                        .foregroundStyle(.primary)
                    if let curator = playlist.curatorName, !curator.isEmpty {
                        Text(curator)
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)

                Image(systemName: "play.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isHovered ? Color.secondary : Color.clear)
            }
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}