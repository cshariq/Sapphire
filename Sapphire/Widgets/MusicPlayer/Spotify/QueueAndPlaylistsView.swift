//
//  QueueAndPlaylistsView.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-06-26.
//

import SwiftUI

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

/// Unified music hub panes. Home + Search merged into Discover; devices live under Audio.
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

    /// Migrates old pane indices (Home=2, Search=3) into the unified hub.
    static func resolveStoredSelection(override: MusicHubPane?) -> Int {
        if let override { return override.rawValue }
        let raw = UserDefaults.standard.integer(forKey: paneDefaultsKey)
        if !UserDefaults.standard.bool(forKey: unifiedMigrationKey) {
            UserDefaults.standard.set(true, forKey: unifiedMigrationKey)
            // Old Search (3) → Discover; Audio is new at 3 after migration flag is set.
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
    /// Audio (devices / AirPlay / system) works without Spotify login.
    private var showLoginGate: Bool { !isLoggedIn && !isAppleMusic && hubPane != .audio }

    private var hubTabs: [MusicHubPane] {
        // Apple Music gets all tabs — Discover uses iTunes Search API (no key needed)
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
            if isAppleMusic, hubPane == .now {
                // Apple Music has a proper Now pane — don't redirect away from it
            }
            // When nothing is playing, land on Library instead of an empty Now pane.
            if musicManager.nowPlayingTrack == nil, hubPane == .now, !isAppleMusic {
                selection = MusicHubPane.library.rawValue
            }
            if audioHubSection == .spotify, !availableAudioHubSections.contains(.spotify) {
                audioHubSection = .apps
            }
        }
        .onDisappear(perform: stopQueueRefreshTimer)
        .onChange(of: selection) { _, newValue in
            UserDefaults.standard.set(newValue, forKey: MusicHubPane.paneDefaultsKey)
            Task { await fetchData(for: MusicHubPane(rawValue: newValue) ?? .now) }
        }
        .onChange(of: audioHubSection) { _, newValue in
            UserDefaults.standard.set(newValue.rawValue, forKey: MusicAudioHubSection.defaultsKey)
        }
        .onChange(of: musicManager.nowPlayingTrack?.uri) { _, newURI in
            if newURI == nil, hubPane == .now, !isAppleMusic {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                    selection = MusicHubPane.library.rawValue
                }
            } else if newURI != nil, hubPane == .now {
                // Track advanced while Now is open — refresh queue shelves immediately.
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
            self.playlists = musicManager.appleMusic.fetchPlaylists()
            self.appleMusicQueue = await musicManager.appleMusic.fetchUpNextTracks()
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
                // Track identity + album art
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

                        // Shuffle / Repeat / Like state row
                        HStack(spacing: 10) {
                            // Like
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

                            // Shuffle
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

                            // Repeat
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

                            // Open in Apple Music
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
    }

    @ViewBuilder
    private var nativeQueueView: some View {
        // Use Connect nowPlayingTrack when available; fall back to MediaRemote
        // metadata (title/artist from MusicManager) so the view never goes blank
        // while the private API is still bootstrapping.
        let hasConnectTrack = musicManager.nowPlayingTrack != nil
        if hasConnectTrack, let nowPlaying = musicManager.nowPlayingTrack {
            nativeQueueContent(nowPlaying: nowPlaying)
        } else if musicManager.title != nil {
            // Private API hasn't loaded yet — show a loading hero using MediaRemote data
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
            // Retry bootstrap so the view fills in as soon as the session loads
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
                                                    VStack(alignment: .leading, spacing: 2) {
                                                        Text(credit.name).font(.caption.bold()).lineLimit(1)
                                                        if let role = credit.role, !role.isEmpty {
                                                            Text(role).font(.caption2).foregroundColor(.secondary).lineLimit(1)
                                                        }
                                                    }
                                                    .padding(.horizontal, 10)
                                                    .padding(.vertical, 8)
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
                            // Nested horizontal ScrollViews can leave the left column slightly
                            // scrolled on open — pin back to the top after layout settles.
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
            // Title block first — track identity before chrome / device.
            VStack(alignment: .leading, spacing: 4) {
                Text(nowPlaying.metadata?.title ?? "Unknown Track")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .lineLimit(2)
                Text(nowPlaying.metadata?.artistName ?? "Unknown Artist")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
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
                                            // Open playlist in Apple Music
                                            if let url = URL(string: "music://") {
                                                NSWorkspace.shared.open(url)
                                            }
                                            musicManager.appleMusic.revealCurrentTrack()
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

    private func performAction(_ action: @escaping () async -> Void) {
        Task {
            await action()
            onAction()
        }
    }

    private func accessoryHoldHandler(for target: MusicLongPressTarget) -> (() -> Void)? {
        guard let action = settings.settings.resolvedAccessoryHoldAction(for: target) else { return nil }
        return {
            Task { await musicManager.performLongPressAction(action, navigation: longPressNavigation) }
        }
    }

    var body: some View {
        VStack(spacing: 15) {
            HStack(spacing: 30) {
                SeekButton(
                    systemName: "backward.fill",
                    onTap: { performAction(musicManager.previousTrack) },
                    onSeek: { isForward in Task { await musicManager.seek(by: isForward ? 5.0 : -5.0) } },
                    onLongPressAction: MusicLongPressUI.skipHoldHandler(
                        for: .previous,
                        settings: settings.settings,
                        musicManager: musicManager,
                        navigation: longPressNavigation
                    )
                )
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
                    onLongPress: accessoryHoldHandler(for: .playPause)
                ) {
                    Image(systemName: musicManager.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 20))
                }
                SeekButton(
                    systemName: "forward.fill",
                    onTap: { performAction(musicManager.nextTrack) },
                    onSeek: { isForward in Task { await musicManager.seek(by: isForward ? 5.0 : -5.0) } },
                    onLongPressAction: MusicLongPressUI.skipHoldHandler(
                        for: .next,
                        settings: settings.settings,
                        musicManager: musicManager,
                        navigation: longPressNavigation
                    )
                )
                Spacer()
            }
            .font(.system(size: 16))

            HStack(spacing: 28) {
                LongPressControlButton(
                    onTap: { performAction(musicManager.toggleLike) },
                    onLongPress: accessoryHoldHandler(for: .like)
                ) {
                    Image(systemName: musicManager.isLiked ? "heart.fill" : "heart")
                }
                .foregroundColor(musicManager.isLiked ? .pink : .primary)

                LongPressControlButton(
                    onTap: { performAction(musicManager.toggleShuffle) },
                    onLongPress: accessoryHoldHandler(for: .shuffle)
                ) {
                    Image(systemName: musicManager.spotifyPrivateAPI.isSmartShuffleActive ? "sparkles" : "shuffle")
                }
                .foregroundColor(
                    musicManager.spotifyPrivateAPI.isSmartShuffleActive
                        ? .purple
                        : (musicManager.shuffleState ? .green : .primary)
                )

                LongPressControlButton(
                    onTap: { performAction(musicManager.cycleRepeatMode) },
                    onLongPress: accessoryHoldHandler(for: .repeatMode)
                ) {
                    Image(systemName: musicManager.repeatState == .track ? "repeat.1" : "repeat")
                }
                .foregroundColor(musicManager.repeatState != .off ? .green : .primary)
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
        .padding(.horizontal, 10)
        .background(Color.white.opacity(isHovered ? 0.15 : 0.1)).cornerRadius(10)
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

    /// Matches `SpotifyNativeDeviceRow` / devices menu icons for the active Connect player.
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
        .onHover { isHovered = $0 }
    }
}

struct RecentlyPlayedCard: View {
    let item: SpotifyRecentlyPlayedItem
    let onTap: () -> Void

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
    }
}

struct PopularReleaseCard: View {
    let release: SpotifyPopularRelease
    let onPlay: (PlaybackResult) -> Void
    @EnvironmentObject var musicManager: MusicManager

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

            Button {
                Task {
                    _ = await musicManager.spotifyPrivateAPI.addToQueue(
                        uri: track.uri,
                        metadata: [
                            "title": track.name,
                            "artist_name": track.artists.map(\.name).joined(separator: ", ")
                        ]
                    )
                }
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(isHovered ? MaterialChartPalette.primary : .secondary.opacity(0.55))
            }
            .buttonStyle(.plain)
            .help("Add to queue")
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
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
