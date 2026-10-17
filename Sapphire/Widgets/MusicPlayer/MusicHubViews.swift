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
        case .now: return String(localized: "music.hub.now", defaultValue: "Now")
        case .library: return String(localized: "Library")
        case .discover: return String(localized: "Discover")
        case .audio: return String(localized: "Audio")
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
    var musicManager: MusicManager { .shared }

    @State private var selection: Int
    @State private var audioHubSection: MusicAudioHubSection
    @State private var officialQueue: SpotifyQueue?
    @State private var playlists: [SpotifyPlaylist] = []
    @State private var appleMusicQueue: [AppleMusicManager.QueueTrack] = []

    @State private var showSpotifyNotOpenAlert = false
    @State private var delayedRefreshTask: Task<Void, Never>?

    // MARK: - Animation State
    @Namespace private var namespace

    var isLockScreenMode: Bool = false
    private var preferSystemAudioTab: Bool = false

    private var isAppleMusic: Bool { musicManager.isAppleMusicContext }
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
        let canShowSpotify = !music.isAppleMusicContext
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
        .task(id: selection) {
            await fetchData(for: hubPane)
        }
        .onAppear {
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
            delayedRefreshTask?.cancel()
            delayedRefreshTask = nil
            Task { await musicManager.setMusicHubOpen(false) }
        }
        .onChange(of: selection) { _, newValue in
            delayedRefreshTask?.cancel()
            UserDefaults.standard.set(newValue, forKey: MusicHubPane.paneDefaultsKey)
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
        return hubPane == .audio ? String(localized: "Audio") : "Spotify"
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
                        Task { musicManager.spotifyOfficialAPI.logout() }
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
        if ChineseFormatting.isActive { return ChineseFormatting.compactCount(value) }
        if value >= 1_000_000 { return String(format: "%.1fM", Double(value) / 1_000_000) }
        if value >= 1_000 { return String(format: "%.1fK", Double(value) / 1_000) }
        return "\(value)"
    }

    private var appleMusicHubPill: some View {
        HStack(spacing: 6) {
            Image("apple_logo")
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
        delayedRefreshTask?.cancel()
        let pane = hubPane
        delayedRefreshTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(500))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await fetchData(for: pane)
        }
    }

    private func fetchData(for pane: MusicHubPane) async {
        if isAppleMusic {
            let apple = musicManager.appleMusic
            if !apple.isMusicKitAuthorized, apple.isMusicKitConfigured {
                await apple.requestAuthorization()
            }
            if apple.isMusicKitAuthorized {
                async let playlists: Void = apple.refreshPlaylists()
                async let nowPlaying: Void = musicManager.refreshAppleMusicNowPlaying()
                _ = await (playlists, nowPlaying)
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
            let needsProfileRefresh = musicManager.spotifyPrivateAPI.accountInfo == nil
            async let library: Void = musicManager.spotifyPrivateAPI.fetchUserLibrary()
            async let profile: Void = {
                if needsProfileRefresh {
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

    private var appleNowPlayingCaption: String? {
        let details = musicManager.appleNowPlaying
        let parts = [
            details.genreNames.first,
            details.releaseDate.map { String(Calendar.current.component(.year, from: $0)) },
            details.composer.map { "Written by \($0)" }
        ].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var appleMusicNowView: some View {
        HStack(alignment: .top, spacing: 14) {
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        Color.clear
                            .frame(height: 0)
                            .id("apple-now-top")

                        appleNowHeroCard

                        let details = musicManager.appleNowPlaying
                        if !musicManager.appleSuggestedTracks.isEmpty {
                            materialExpressiveCard(title: String(localized: "More by \(details.artist?.name ?? musicManager.artist ?? String(localized: "This Artist"))"), systemImage: "sparkles", accent: MaterialChartPalette.secondary) {
                                LazyVStack(spacing: 4) {
                                    ForEach(musicManager.appleSuggestedTracks.prefix(6)) { track in
                                        SuggestedAppleTrackRow(track: track) {
                                            Task {
                                                _ = await musicManager.appleMusic.play(song: track, within: musicManager.appleSuggestedTracks)
                                                refreshData()
                                            }
                                        }
                                        .contextMenu {
                                            Button("Play Next") { Task { _ = await musicManager.appleMusic.playNext(songIDs: [track.id]); refreshData() } }
                                            Button("Play Later") { Task { _ = await musicManager.appleMusic.playLater(songIDs: [track.id]); refreshData() } }
                                        }
                                    }
                                }
                            }
                        }

                        if !details.relatedAlbums.isEmpty {
                            materialExpressiveCard(title: String(localized: "Similar Albums"), systemImage: "square.stack", accent: MaterialChartPalette.tertiary) {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    LazyHStack(spacing: 12) {
                                        ForEach(details.relatedAlbums) { album in
                                            appleNowTile(title: album.title, subtitle: album.artistName, artworkURL: album.artworkURL, circular: false) {
                                                openAppleMusicDetail(.album(album))
                                            }
                                        }
                                    }
                                    .padding(.horizontal, 2)
                                }
                            }
                        }

                        if !details.similarArtists.isEmpty {
                            materialExpressiveCard(title: String(localized: "Similar Artists"), systemImage: "person.2.fill", accent: MaterialChartPalette.primary) {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    LazyHStack(spacing: 12) {
                                        ForEach(details.similarArtists) { artist in
                                            appleNowTile(title: artist.name, subtitle: nil, artworkURL: artist.artworkURL, circular: true) {
                                                openAppleMusicDetail(.artist(artist))
                                            }
                                        }
                                    }
                                    .padding(.horizontal, 2)
                                }
                            }
                        }

                        if details.song != nil {
                            appleNowAboutCard(details)
                        }
                    }
                    .padding(.leading, 4)
                    .padding(.trailing, 2)
                    .padding(.bottom, 28)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .onAppear {
                    DispatchQueue.main.async { proxy.scrollTo("apple-now-top", anchor: .top) }
                }
            }
            .mask(fadeMask)

            appleUpNextCard
                .frame(width: 292, alignment: .top)
        }
        .padding(.leading, 2)
        .task(id: musicManager.title) {
            appleMusicQueue = await musicManager.appleMusic.fetchUpNextTracks()
        }
    }

    private var appleNowHeroCard: some View {
        let details = musicManager.appleNowPlaying
        return VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(musicManager.title ?? String(localized: "Not Playing"))
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .lineLimit(2)
                Button {
                    if let artist = details.artist { openAppleMusicDetail(.artist(artist)) }
                } label: {
                    HStack(spacing: 4) {
                        Text(musicManager.artist ?? "Apple Music")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        if details.artist != nil {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(details.artist == nil)
            }

            HStack(alignment: .center, spacing: 14) {
                Group {
                    if let artwork = musicManager.artwork {
                        Image(nsImage: artwork).resizable().aspectRatio(contentMode: .fill)
                    } else {
                        ZStack { MaterialChartPalette.surfaceVariant; Image(systemName: "music.note") }
                    }
                }
                .frame(width: 88, height: 88)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                VStack(alignment: .leading, spacing: 7) {
                    if let album = musicManager.album, !album.isEmpty, album != musicManager.title {
                        Button {
                            if let catalogAlbum = details.album { openAppleMusicDetail(.album(catalogAlbum)) }
                        } label: {
                            Label(album, systemImage: "square.stack")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .lineLimit(1)
                        }
                        .buttonStyle(.plain)
                        .disabled(details.album == nil)
                    }
                    if let caption = appleNowPlayingCaption {
                        Text(caption)
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                    if !details.audioBadges.isEmpty {
                        AppleMusicAudioBadgeRow(badges: details.audioBadges)
                    }
                    HStack(spacing: 8) {
                        if let playCount = musicManager.applePlayCount {
                            PlayCountIndicator(playCount: playCount)
                        }
                        if details.isInLibrary {
                            Label("In Library", systemImage: "checkmark.circle.fill")
                                .font(.system(size: 9, weight: .semibold, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 12) {
                appleNowIconButton(musicManager.isLiked ? "heart.fill" : "heart",
                                   tint: musicManager.isLiked ? .pink : .secondary,
                                   help: musicManager.isLiked ? String(localized: "Unfavorite") : String(localized: "Favorite")) {
                    Task { await musicManager.toggleLike() }
                }
                appleNowIconButton("shuffle", tint: musicManager.shuffleState ? musicManager.accentColor : .secondary, help: String(localized: "Shuffle")) {
                    Task { await musicManager.toggleShuffle(); refreshData() }
                }
                appleNowIconButton(musicManager.repeatState == .track ? "repeat.1" : "repeat",
                                   tint: musicManager.repeatState != .off ? musicManager.accentColor : .secondary,
                                   help: String(localized: "Repeat")) {
                    Task { await musicManager.cycleRepeatMode() }
                }
                if let songID = details.song?.id, details.hasStation {
                    appleNowIconButton("dot.radiowaves.left.and.right", tint: .secondary, help: String(localized: "Start station from this song")) {
                        Task { _ = await musicManager.appleMusic.playSongStation(songID: songID) }
                    }
                }
                if details.song != nil, !details.isInLibrary, !musicManager.appleMusic.isInAppPlaybackActive {
                    appleNowIconButton("plus.circle", tint: .secondary, help: String(localized: "Add to Library")) {
                        Task {
                            if await musicManager.appleMusic.addCurrentTrackToLibrary() {
                                await musicManager.refreshAppleMusicNowPlaying()
                            }
                        }
                    }
                }
                Spacer(minLength: 0)
                appleNowIconButton("arrow.up.right.square", tint: .secondary, help: String(localized: "Show in Apple Music")) {
                    musicManager.appleMusic.revealCurrentTrack()
                }
            }

            ActionButtonsView(onAction: refreshData, longPressNavigation: hubLongPressNavigation)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(MaterialChartPalette.cardGradient(for: musicManager.accentColor))
        )
    }

    private func appleNowAboutCard(_ details: AppleMusicNowPlayingDetails) -> some View {
        let rows: [(String, String)] = [
            details.album.map { (String(localized: "Album"), $0.title) },
            details.composer.map { (String(localized: "Written by"), $0) },
            details.genreNames.isEmpty ? nil : (String(localized: "Genre"), details.genreNames.joined(separator: ", ")),
            details.releaseDate.map { (String(localized: "Released"), $0.formatted(date: .abbreviated, time: .omitted)) },
            details.lastPlayedDate.map { (String(localized: "Last played"), $0.formatted(.relative(presentation: .named))) },
            details.libraryAddedDate.map { (String(localized: "Added"), $0.formatted(date: .abbreviated, time: .omitted)) },
            details.hasLyrics ? (String(localized: "Lyrics"), String(localized: "Available")) : nil
        ].compactMap { $0 }
        return materialExpressiveCard(title: String(localized: "About This Song"), systemImage: "info.circle", accent: MaterialChartPalette.tertiary) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(rows, id: \.0) { row in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(row.0)
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(.tertiary)
                            .frame(width: 72, alignment: .leading)
                        Text(row.1)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }
        }
    }

    private var appleUpNextCard: some View {
        materialExpressiveCard(title: String(localized: "Up Next"), systemImage: "list.bullet", accent: MaterialChartPalette.primary) {
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
                Spacer(minLength: 0)
            } else {
                HStack {
                    Text("\(appleMusicQueue.count) songs")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.tertiary)
                    Spacer()
                    if musicManager.appleMusic.canEditQueue {
                        Button("Clear") {
                            Task {
                                _ = await musicManager.appleMusic.clearUpNext()
                                appleMusicQueue = await musicManager.appleMusic.fetchUpNextTracks()
                            }
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                    }
                }
                ScrollView(showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(appleMusicQueue) { track in
                            AppleQueueRow(track: track) {
                                Task {
                                    await musicManager.appleMusic.playQueueTrack(track)
                                    try? await Task.sleep(nanoseconds: 400_000_000)
                                    appleMusicQueue = await musicManager.appleMusic.fetchUpNextTracks()
                                }
                            }
                            .contextMenu {
                                Button("Play Now") {
                                    Task {
                                        await musicManager.appleMusic.playQueueTrack(track)
                                        appleMusicQueue = await musicManager.appleMusic.fetchUpNextTracks()
                                    }
                                }
                                if musicManager.appleMusic.canRemove(track) {
                                    Button("Remove from Up Next") {
                                        appleMusicQueue.removeAll { $0.id == track.id }
                                        Task {
                                            _ = await musicManager.appleMusic.removeFromQueue(track)
                                            appleMusicQueue = await musicManager.appleMusic.fetchUpNextTracks()
                                        }
                                    }
                                }
                                if let storeID = track.catalogID {
                                    Button("Go to Artist") {
                                        Task {
                                            if let artist = await musicManager.appleMusic.findArtist(named: track.artist) {
                                                openAppleMusicDetail(.artist(artist))
                                            }
                                        }
                                    }
                                    Button("Start Station") { Task { _ = await musicManager.appleMusic.playSongStation(songID: storeID) } }
                                }
                            }
                        }
                    }
                    .padding(.bottom, 12)
                }
            }
        }
    }

    private func appleNowIconButton(_ systemImage: String, tint: Color, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13))
                .foregroundStyle(tint)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func appleNowTile(title: String, subtitle: String?, artworkURL: URL?, circular: Bool, onTap: @escaping () -> Void) -> some View {
        Button(action: onTap) {
            VStack(alignment: circular ? .center : .leading, spacing: 4) {
                CachedAsyncImage(url: artworkURL) { $0.resizable().aspectRatio(contentMode: .fill) } placeholder: {
                    ZStack { MaterialChartPalette.surfaceVariant; Image(systemName: circular ? "music.mic" : "square.stack") }
                }
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: circular ? 36 : 12, style: .continuous))
                Text(title)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(width: 72)
        }
        .buttonStyle(.plain)
    }

    private func openAppleMusicDetail(_ route: AppleMusicDetailRoute) {
        AppleMusicNavigator.shared.pending = route
        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
            selection = MusicHubPane.discover.rawValue
        }
    }

    @ViewBuilder
    private var nativeQueueView: some View {
        let hasConnectTrack = musicManager.nowPlayingTrack != nil
        if hasConnectTrack, let nowPlaying = musicManager.nowPlayingTrack {
            nativeQueueContent(nowPlaying: nowPlaying)
        } else if musicManager.title != nil {
            nativeQueueBootstrappingView
        } else {
            CustomUnavailableView(title: String(localized: "Nothing Playing"), systemImage: "speaker.slash.fill", description: String(localized: "Start playing music in Spotify to see artist picks, concerts, and your queue."))
        }
    }

    private var nativeQueueBootstrappingView: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(musicManager.title ?? String(localized: "Now Playing"))
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

            materialExpressiveCard(title: String(localized: "Loading…"), systemImage: "arrow.clockwise", accent: MaterialChartPalette.primary) {
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
                            LazyVStack(alignment: .leading, spacing: 14) {
                                Color.clear
                                    .frame(height: 0)
                                    .id("now-left-top")

                                nowPlayingHeroCard(nowPlaying)

                                if !musicManager.spotifyPrivateAPI.similarAlbums.isEmpty {
                                    materialExpressiveCard(title: String(localized: "Similar Albums"), systemImage: "square.stack", accent: MaterialChartPalette.tertiary) {
                                        ScrollView(.horizontal, showsIndicators: false) {
                                            LazyHStack(spacing: 12) {
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
                                    materialExpressiveCard(title: String(localized: "More Like This"), systemImage: "sparkles", accent: MaterialChartPalette.secondary) {
                                        LazyVStack(spacing: 4) {
                                            ForEach(musicManager.spotifyPrivateAPI.relatedTracks.prefix(6)) { track in
                                                RecommendedTrackRow(track: track, onPlay: handlePlaybackResult)
                                            }
                                        }
                                    }
                                }

                                if !musicManager.spotifyPrivateAPI.artistConcerts.isEmpty {
                                    materialExpressiveCard(title: String(localized: "Nearby Concerts"), systemImage: "ticket.fill", accent: MaterialChartPalette.error) {
                                        ScrollView(.horizontal, showsIndicators: false) {
                                            LazyHStack(spacing: 12) {
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
                                    materialExpressiveCard(title: String(localized: "Credits"), systemImage: "person.2.fill", accent: MaterialChartPalette.secondary) {
                                        ScrollView(.horizontal, showsIndicators: false) {
                                            LazyHStack(spacing: 10) {
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
                                    materialExpressiveCard(title: String(localized: "Merch"), systemImage: "bag.fill", accent: MaterialChartPalette.warning) {
                                        ScrollView(.horizontal, showsIndicators: false) {
                                            LazyHStack(spacing: 12) {
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

                    materialExpressiveCard(title: String(localized: "Up Next"), systemImage: "list.bullet", accent: MaterialChartPalette.primary) {
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
                Text(nowPlaying.metadata?.title ?? String(localized: "Unknown Track"))
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .lineLimit(2)

                Button {
                    openArtistFromNowPlaying(fallbackName: nowPlaying.metadata?.artistName)
                } label: {
                    HStack(spacing: 4) {
                        Text(nowPlaying.metadata?.artistName ?? String(localized: "Unknown Artist"))
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
                .musicArtistDetail(uri: uri, name: fallbackName ?? musicManager.artist ?? String(localized: "Artist"))
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
                    SectionHeader(title: String(localized: "Next Up")).padding(.bottom, 5)
                    if !queue.queue.isEmpty {
                        ScrollView(showsIndicators: false) {
                            LazyVStack(alignment: .leading, spacing: 8) {
                                ForEach(queue.queue) { track in QueueTrackRow(track: track, onPlay: handlePlaybackResult) }
                            }
                            .padding(.bottom, 30)
                        }
                        .mask(LinearGradient(gradient: Gradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.95), .init(color: .clear, location: 1.0)]), startPoint: .top, endPoint: .bottom))
                    } else { CustomUnavailableView(title: String(localized: "No Songs Up Next"), systemImage: "music.note.list", description: String(localized: "Add songs to your queue to see them here.")) }
                }
            } else { CustomUnavailableView(title: String(localized: "Queue Unavailable"), systemImage: "speaker.slash.fill", description: String(localized: "Start playing music with a Premium account to view your queue.")) }
        }

    }

    private var playlistsView: some View { libraryView }

    private var libraryView: some View {
        VStack(spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Library")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                    Text(isAppleMusic ? String(localized: "Your Apple Music playlists") : String(localized: "Playlists sorted by Spotify"))
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if musicManager.isPrivateAPIAuthenticated && !isAppleMusic {
                    let orders = musicManager.spotifyPrivateAPI.librarySortOrders.isEmpty
                        ? [
                            UserLibraryResponse.SortOrder(id: "Recents", name: String(localized: "Recents")),
                            UserLibraryResponse.SortOrder(id: "Recently Added", name: String(localized: "Recently Added")),
                            UserLibraryResponse.SortOrder(id: "Alphabetical", name: String(localized: "Alphabetical")),
                            UserLibraryResponse.SortOrder(id: "Creator", name: String(localized: "Creator"))
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
                            title: String(localized: "No Playlists Found"),
                            systemImage: "music.mic",
                            description: isAppleMusic ? String(localized: "Add playlists in Apple Music to see them here.") : nil
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
            LazyVStack(alignment: .leading, spacing: 16) {
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
                            SectionHeader(title: section.title ?? String(localized: "For You"))
                            ScrollView(.horizontal, showsIndicators: false) {
                                LazyHStack(spacing: 12) {
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
                        SectionHeader(title: String(localized: "Recently Played"))
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(spacing: 12) {
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
                        SectionHeader(title: String(localized: "Popular Releases"))
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(spacing: 12) {
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
                        SectionHeader(title: String(localized: "Made For You"))
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
                        title: String(localized: "Your Home"),
                        systemImage: "house.fill",
                        description: String(localized: "Home shelves from Spotify will appear here once loaded.")
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
    var musicManager: MusicManager { .shared }
    @ObservedSettings var settings: SettingsObserver
    let onAction: () -> Void
    var longPressNavigation: MusicLongPressNavigation = .notifications

    @StateObject private var holdFeedback = MusicHoldFeedbackController()

    private var holdFeedbackIcon: String? { holdFeedback.icon }
    private var holdFeedbackColor: Color { holdFeedback.color }
    private var holdFeedbackButtonID: String? { holdFeedback.buttonID }

    private func performAction(_ action: @escaping () async -> Void) {
        Task {
            await action()
            onAction()
        }
    }

    private func accessoryHoldHandler(for target: MusicLongPressTarget) -> (() -> Void)? {
        guard let action = settings.settings.value.resolvedAccessoryHoldAction(for: target) else { return nil }
        return holdFeedback.handler(
            for: action,
            musicManager: musicManager,
            navigation: longPressNavigation,
            onCompletion: onAction
        )
    }

    private func skipHoldAction(for target: MusicLongPressTarget) -> MusicLongPressAction? {
        holdFeedback.skipAction(for: target, settings: settings.settings.value)
    }

    private func skipHoldClosure(for target: MusicLongPressTarget) -> (() -> Void)? {
        guard let action = skipHoldAction(for: target) else { return nil }
        return holdFeedback.handler(
            for: action,
            musicManager: musicManager,
            navigation: longPressNavigation,
            onCompletion: onAction
        )
    }

    private func beginHoldFeedback(action: MusicLongPressAction, buttonID: String) {
        holdFeedback.begin(action: action, buttonID: buttonID, musicManager: musicManager)
    }

    private func endHoldFeedback() {
        holdFeedback.end()
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
                    holdAction: settings.settings.value.resolvedAccessoryHoldAction(for: .playPause),
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
                    holdAction: settings.settings.value.resolvedAccessoryHoldAction(for: .like),
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
                    holdAction: settings.settings.value.resolvedAccessoryHoldAction(for: .shuffle),
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
                    holdAction: settings.settings.value.resolvedAccessoryHoldAction(for: .repeatMode),
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

    var musicManager: MusicManager { .shared }
    @ObservedSettings var settings: SettingsObserver
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
                        showFeedback(String(localized: "Added to queue"))
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

    var musicManager: MusicManager { .shared }
    @ObservedSettings var settings: SettingsObserver
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
                    LazyVStack(alignment: .leading, spacing: 2) {
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
                        _ = await MainActor.run {
                            containedPlaylistURIs.remove(playlist.uri)
                        }
                        showFeedback(String(localized: "Removed from \(playlist.name)"))
                    } else {
                        showFeedback(String(localized: "Could not remove from \(playlist.name)"))
                    }
                } else {
                    let ok = await musicManager.spotifyPrivateAPI.addTracksToPlaylist(
                        playlistURI: playlist.uri,
                        trackURIs: [trackURI]
                    )
                    if ok {
                        _ = await MainActor.run {
                            containedPlaylistURIs.insert(playlist.uri)
                        }
                        showFeedback(String(localized: "Added to \(playlist.name)"))
                    } else {
                        showFeedback(String(localized: "Could not add to \(playlist.name)"))
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
    var musicManager: MusicManager { .shared }
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
                        Text(track.metadata?.title ?? String(localized: "Unknown Track"))
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .lineLimit(1)
                            .foregroundStyle(.primary)
                        Text(track.metadata?.artistName ?? String(localized: "Unknown Artist"))
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
                trackName: track.metadata?.title ?? String(localized: "Unknown Track"),
                artistName: track.metadata?.artistName ?? String(localized: "Unknown Artist"),
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
    var musicManager: MusicManager { .shared }

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
            Text((Double(track.durationMs) / 1000.0).asMinuteSecondClock).font(.caption.monospacedDigit()).foregroundColor(.secondary)
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
    var musicManager: MusicManager { .shared }
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
    var musicManager: MusicManager { .shared }

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
    var musicManager: MusicManager { .shared }
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

fileprivate struct MarqueeContentWidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

fileprivate struct Marquee<Content: View>: View {
    @ViewBuilder var content: Content

    @State private var animate = false
    @State private var containerWidth: CGFloat = 0
    @State private var contentWidth: CGFloat = 0
    @State private var isVisible = false
    @State private var animationTask: Task<Void, Never>?

    private let spacing: CGFloat = 24

    private var isOverflowing: Bool {
        contentWidth > containerWidth
    }

    private var animation: Animation {
        .linear(duration: max((contentWidth + spacing) / 30, 0.1))
        .delay(1.5)
        .repeatForever(autoreverses: false)
    }

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: spacing) {
                measuredContent
                if isOverflowing {
                    content
                        .fixedSize(horizontal: true, vertical: false)
                        .accessibilityHidden(true)
                }
            }
            .offset(x: isOverflowing && animate ? -(contentWidth + spacing) : 0)
            .frame(maxWidth: .infinity, alignment: .leading)
            .onAppear {
                updateContainerWidth(proxy.size.width)
            }
            .onChange(of: proxy.size.width) { _, width in
                updateContainerWidth(width)
            }
        }
        .clipped()
        .onPreferenceChange(MarqueeContentWidthPreferenceKey.self) { width in
            guard abs(contentWidth - width) > 0.5 else { return }
            contentWidth = width
            restartAnimation()
        }
        .onAppear {
            isVisible = true
            restartAnimation()
        }
        .onDisappear {
            isVisible = false
            animationTask?.cancel()
            animationTask = nil
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { animate = false }
        }
    }

    private var measuredContent: some View {
        content
            .fixedSize(horizontal: true, vertical: false)
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: MarqueeContentWidthPreferenceKey.self,
                        value: proxy.size.width
                    )
                }
            }
    }

    private func updateContainerWidth(_ width: CGFloat) {
        guard abs(containerWidth - width) > 0.5 else { return }
        containerWidth = width
        restartAnimation()
    }

    private func restartAnimation() {
        animationTask?.cancel()
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { animate = false }

        guard isVisible, isOverflowing else { return }
        animationTask = Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled, isVisible, isOverflowing else { return }
            withAnimation(animation) { animate = true }
        }
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
        case .apps: return String(localized: "Apps")
        case .system: return String(localized: "System")
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
    var musicManager: MusicManager { .shared }
    @ObservedSettings var settings: SettingsObserver

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
        musicManager.isAppleMusicContext
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
        .onReceive(musicManager.spotifyPrivateAPI.valuePublisher(\.devices).receive(on: DispatchQueue.main)) { devices in
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
            TabButton(title: String(localized: "System"), systemImage: "hifispeaker.and.homepod.mini.fill", isSelected: selectedTab == .system) {
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
                LazyVStack(alignment: .leading, spacing: 15) {
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
    var musicManager: MusicManager { .shared }

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
                BoldPillSlider(label: String(localized: "Volume"), value: $volume, range: 0...100, specifier: "%.0f %%", style: .large, onCommit: sendVolumeUpdate)
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
                BoldPillSlider(label: String(localized: "Volume"), value: $volume, range: 0...100, specifier: "%.0f %%", style: .large, onCommit: onCommit)
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
                BoldPillSlider(label: String(localized: "Volume"), value: $volume, range: 0...100, specifier: "%.0f %%", style: .large, onCommit: onCommit)
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
        self.name = data.name ?? String(localized: "Unknown Track")
        let artistItems = data.artists?.items ?? []
        self.artists = artistItems.map(\.profile.name).joined(separator: ", ").nilIfEmpty ?? String(localized: "Unknown Artist")
        self.firstArtistName = artistItems.first?.profile.name ?? String(localized: "Unknown Artist")
        self.firstArtistURI = artistItems.first?.uri
        self.albumName = data.albumOfTrack?.name ?? String(localized: "Unknown Album")
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
        self.firstArtistName = track.artists.first?.name ?? String(localized: "Unknown Artist")
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

    var musicManager: MusicManager { .shared }
    @Binding var navigationStack: [NotchWidgetMode]

    private var spotifyPrivateAPI: SpotifyPrivateAPIManager { .shared }

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

        var displayName: String {
            switch self {
            case .customOrder: return String(localized: "Custom order")
            case .title: return String(localized: "Title")
            case .artist: return String(localized: "Artist")
            case .album: return String(localized: "Album")
            case .dateAdded: return String(localized: "Date added")
            case .playCount: return String(localized: "Play count")
            }
        }

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
                                            if !playlist.uri.hasPrefix("spotify:"), musicManager.isAppleMusicContext {
                                                _ = await musicManager.appleMusic.playLater(songIDs: [viewModel.uri])
                                                return
                                            }
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
        .onReceive(spotifyPrivateAPI.valuePublisher(\.playlistTrackViewModels).receive(on: DispatchQueue.main)) { models in
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
                        Text(perms.canEditItems ? String(localized: "Editable") : String(localized: "View only"))
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.primary.opacity(0.08), in: Capsule())
                    }
                }

                HStack(spacing: 8) {
                    tonalButton(String(localized: "Play"), systemImage: "play.fill") {
                        Task {
                            if !playlist.uri.hasPrefix("spotify:"),
                               musicManager.isAppleMusicContext {
                                let ok = musicManager.appleMusic.playPlaylist(persistentID: playlist.id)
                                handlePlaybackResult(ok ? .success : .failure(reason: String(localized: "Couldn’t play playlist.")))
                            } else {
                                handlePlaybackResult(await musicManager.play(contextUri: playlist.uri))
                            }
                        }
                    }
                    tonalButton(String(localized: "Shuffle"), systemImage: "shuffle") {
                        Task {
                            if !playlist.uri.hasPrefix("spotify:"),
                               musicManager.isAppleMusicContext {
                                let ok = musicManager.appleMusic.playPlaylist(persistentID: playlist.id)
                                if ok {
                                    musicManager.appleMusic.setShuffle(enabled: true)
                                    handlePlaybackResult(.success)
                                } else {
                                    handlePlaybackResult(.failure(reason: String(localized: "Couldn’t play playlist.")))
                                }
                            } else {
                                handlePlaybackResult(await musicManager.play(contextUri: playlist.uri))
                                try? await Task.sleep(for: .milliseconds(400))
                                await musicManager.toggleShuffle()
                            }
                        }
                    }
                    if musicManager.spotifyPrivateAPI.smartShuffleAvailable && playlist.uri.hasPrefix("spotify:") {
                        tonalButton(String(localized: "Smart"), systemImage: "sparkles") {
                            Task {
                                handlePlaybackResult(await musicManager.spotifyPrivateAPI.playSmartShuffle(playlistURI: playlist.uri))
                            }
                        }
                    }
                    if playlist.uri.hasPrefix("spotify:") {
                        tonalButton(
                            musicManager.spotifyPrivateAPI.isEnhanceLoading ? "…" : String(localized: "Enhance"),
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
                Text(option.displayName)
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
            && musicManager.isAppleMusicContext
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

    var musicManager: MusicManager { .shared }
    @State private var isHovered = false

    private static let exactDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        if ChineseFormatting.isActive {
            formatter.setLocalizedDateFormatFromTemplate("yMMMd")
        } else {
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "MMM d, yyyy"
        }
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
                   musicManager.isAppleMusicContext {
                    let ok = musicManager.appleMusic.playTrack(
                        persistentID: viewModel.uri,
                        inPlaylistPersistentID: contextUri
                    )
                    onPlay(ok ? .success : .failure(reason: String(localized: "Couldn’t play this track in Apple Music.")))
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
                       musicManager.isAppleMusicContext {
                        let ok = musicManager.appleMusic.playTrack(
                            persistentID: viewModel.uri,
                            inPlaylistPersistentID: contextUri
                        )
                        onPlay(ok ? .success : .failure(reason: String(localized: "Couldn’t play this track in Apple Music.")))
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

fileprivate let musicRelativeDateFormatter: RelativeDateTimeFormatter = {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .abbreviated
    return formatter
}()

extension TimeInterval {
    fileprivate func timeAgoDisplay() -> String {
        let date = Date(timeIntervalSince1970: self)
        return musicRelativeDateFormatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Consolidated from SpotifyEntityDetailViews.swift

struct SpotifyArtistDetailView: View {
    let uri: String
    let name: String
    @Binding var navigationStack: [NotchWidgetMode]
    var musicManager: MusicManager { .shared }

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
                    LazyVStack(alignment: .leading, spacing: 16) {
                        if let profile {
                            ArtistProfileCard(artist: profile)
                        }

                        if let tracks = overview?.topTracks, !tracks.isEmpty {
                            sectionTitle(String(localized: "Popular"))
                            ForEach(Array(tracks.prefix(10).enumerated()), id: \.element.id) { index, track in
                                artistTrackRow(track, rank: index + 1)
                            }
                        }

                        if let albums = overview?.albums, !albums.isEmpty {
                            sectionTitle(String(localized: "Albums"))
                            horizontalAlbums(albums)
                        }

                        if let singles = overview?.singles, !singles.isEmpty {
                            sectionTitle(String(localized: "Singles & EPs"))
                            horizontalAlbums(singles)
                        }

                        if let playlists = overview?.featuringPlaylists, !playlists.isEmpty {
                            sectionTitle(String(localized: "Featuring"))
                            ForEach(playlists.prefix(8)) { playlist in
                                featuringPlaylistRow(playlist)
                            }
                        }

                        if let related = overview?.relatedArtists, !related.isEmpty {
                            sectionTitle(String(localized: "Fans also like"))
                            ScrollView(.horizontal, showsIndicators: false) {
                                LazyHStack(spacing: 12) {
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
                            sectionTitle(String(localized: "Concerts"))
                            ScrollView(.horizontal, showsIndicators: false) {
                                LazyHStack(spacing: 10) {
                                    ForEach(concerts.prefix(8)) { ConcertCard(concert: $0) }
                                }
                            }
                        }

                        if let profile, !profile.merch.isEmpty {
                            sectionTitle(String(localized: "Merch"))
                            ScrollView(.horizontal, showsIndicators: false) {
                                LazyHStack(spacing: 10) {
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
            LazyHStack(spacing: 12) {
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
                    Text(playlist.ownerName ?? String(localized: "Playlist"))
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
    var musicManager: MusicManager { .shared }

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

    var musicManager: MusicManager { .shared }

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
                    placeholder: String(localized: "Search songs, artists, albums…"),
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
                        title: String(localized: "Search Spotify"),
                        systemImage: "magnifyingglass",
                        description: String(localized: "Find tracks, artists, albums, and playlists.")
                    )
                }
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
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
                            sectionHeader(String(localized: "Songs"))
                            ForEach(results.tracks.prefix(8)) { track in
                                searchTrackRow(track)
                            }
                        }
                        if !results.artists.isEmpty {
                            sectionHeader(String(localized: "Artists"))
                            ScrollView(.horizontal, showsIndicators: false) {
                                LazyHStack(spacing: 12) {
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
                            sectionHeader(String(localized: "Albums"))
                            ScrollView(.horizontal, showsIndicators: false) {
                                LazyHStack(spacing: 12) {
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
                            sectionHeader(String(localized: "Playlists"))
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
                                            Text(playlist.ownerName ?? String(localized: "Playlist"))
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
    var musicManager: MusicManager { .shared }

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
        if ChineseFormatting.isActive { return ChineseFormatting.compactCount(value) }
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
    var musicManager: MusicManager { .shared }
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
    var onReadyForDisplay: (Bool) -> Void = { _ in }
    @StateObject private var model = CanvasPlayerModel()

    var body: some View {
        CanvasPlayerRepresentable(player: model.player, onReadyForDisplay: onReadyForDisplay)
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
    let onReadyForDisplay: (Bool) -> Void

    func makeNSView(context: Context) -> CanvasPlayerNSView {
        CanvasPlayerNSView(player: player, onReadyForDisplay: onReadyForDisplay)
    }

    func updateNSView(_ nsView: CanvasPlayerNSView, context: Context) {
        nsView.playerLayer.player = player
        nsView.onReadyForDisplay = onReadyForDisplay
    }
}

private final class CanvasPlayerNSView: NSView {
    let playerLayer = AVPlayerLayer()
    var onReadyForDisplay: (Bool) -> Void
    private var readyObservation: NSKeyValueObservation?

    init(player: AVPlayer, onReadyForDisplay: @escaping (Bool) -> Void) {
        self.onReadyForDisplay = onReadyForDisplay
        super.init(frame: .zero)
        wantsLayer = true
        playerLayer.player = player
        playerLayer.videoGravity = .resizeAspectFill
        layer?.addSublayer(playerLayer)
        readyObservation = playerLayer.observe(\.isReadyForDisplay, options: [.initial, .new]) { [weak self] layer, _ in
            let ready = layer.isReadyForDisplay
            DispatchQueue.main.async { self?.onReadyForDisplay(ready) }
        }
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

// MARK: - Apple Music (native MusicKit): search, discover & detail pages

private enum AppleMusicDetailRoute: Hashable {
    case artist(AppleMusicArtist)
    case album(AppleMusicAlbum)
    case playlist(AppleMusicPlaylist)
}

@MainActor
private final class AppleMusicNavigator: ObservableObject {
    static let shared = AppleMusicNavigator()
    @Published var pending: AppleMusicDetailRoute?
}

private struct AppleQueueRow: View {
    let track: AppleMusicManager.QueueTrack
    let onTap: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 9) {
                CachedAsyncImage(url: track.artworkURL) { $0.resizable().aspectRatio(contentMode: .fill) } placeholder: {
                    ZStack {
                        Color.white.opacity(0.08)
                        Image(systemName: "music.note")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(width: 30, height: 30)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
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
                Image(systemName: "play.fill")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(isHovered ? Color.secondary : Color.clear)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(isHovered ? 0.07 : 0))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - View Model

@MainActor
private final class AppleMusicSearchViewModel: ObservableObject {
    @Published var query = ""
    @Published var results = AppleMusicSearchResults()
    @Published var suggestions: [String] = []
    @Published var isSearching = false
    @Published var hasSearched = false

    @Published var recommendations: [AppleMusicRecommendationShelf] = []
    @Published var charts = AppleMusicChartSet()
    @Published var genres: [AppleMusicGenre] = []
    @Published var selectedGenre: AppleMusicGenre?
    @Published var recentContainers: [AppleMusicShelfItem] = []
    @Published var recentlyPlayed: [AppleMusicSong] = []
    @Published var recentlyAdded: [AppleMusicSong] = []
    @Published var mostPlayed: [AppleMusicSong] = []
    @Published var heavyRotation: [AppleMusicAlbum] = []
    @Published var replay = AppleMusicReplaySummary()
    @Published var discoverLoaded = false
    @Published var isLoadingDiscover = false

    @Published var route: [AppleMusicDetailRoute] = []
    @Published var artistDetail: AppleMusicArtistDetail?
    @Published var albumDetail: AppleMusicAlbumDetail?
    @Published var playlistDetail: AppleMusicPlaylistDetail?
    @Published var isLoadingDetail = false

    @Published var toast: String?

    private var searchTask: Task<Void, Never>?
    private var suggestionTask: Task<Void, Never>?
    private var detailTask: Task<Void, Never>?
    private var toastTask: Task<Void, Never>?

    private var apple: AppleMusicManager { MusicManager.shared.appleMusic }

    // MARK: Discover

    func loadDiscover(force: Bool = false) async {
        guard force || !discoverLoaded else { return }
        guard apple.isMusicKitAuthorized else { return }
        discoverLoaded = true
        isLoadingDiscover = true
        async let recs = apple.recommendations()
        async let chartSet = apple.charts(genreID: selectedGenre?.id)
        async let genreList = apple.topGenres()
        async let containers = apple.recentlyPlayedContainers()
        async let recent = apple.recentlyPlayed()
        async let added = apple.recentlyAdded()
        async let top = apple.mostPlayed()
        async let heavy = apple.heavyRotationAlbums()
        async let replaySummary = apple.latestReplay()
        let values = await (recs, chartSet, genreList, containers, recent, added, top, heavy, replaySummary)
        guard !Task.isCancelled else { return }
        recommendations = values.0
        charts = values.1
        genres = values.2
        recentContainers = values.3
        recentlyPlayed = values.4
        recentlyAdded = values.5
        mostPlayed = values.6
        heavyRotation = values.7
        replay = values.8
        isLoadingDiscover = false
    }

    func selectGenre(_ genre: AppleMusicGenre?) {
        selectedGenre = genre
        Task {
            let set = await apple.charts(genreID: genre?.id)
            guard selectedGenre == genre else { return }
            charts = set
        }
    }

    var discoverIsEmpty: Bool {
        recommendations.isEmpty && charts.songs.isEmpty && recentlyPlayed.isEmpty
            && recentContainers.isEmpty && mostPlayed.isEmpty && replay.topSongs.isEmpty
    }

    // MARK: Search

    func search() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            results = AppleMusicSearchResults()
            hasSearched = false
            isSearching = false
            return
        }
        searchTask?.cancel()
        isSearching = true
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            let loaded = await apple.search(trimmed)
            guard !Task.isCancelled else { return }
            results = loaded
            isSearching = false
            hasSearched = true
        }
    }

    func updateSuggestions() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        suggestionTask?.cancel()
        guard trimmed.count >= 2 else {
            suggestions = []
            return
        }
        suggestionTask = Task {
            try? await Task.sleep(nanoseconds: 180_000_000)
            guard !Task.isCancelled else { return }
            let loaded = await apple.searchSuggestions(trimmed)
            guard !Task.isCancelled else { return }
            suggestions = loaded
        }
    }

    func clearSearch() {
        query = ""
        results = AppleMusicSearchResults()
        suggestions = []
        hasSearched = false
    }

    // MARK: Navigation

    func open(_ destination: AppleMusicDetailRoute) {
        route.append(destination)
        loadDetail(for: destination)
    }

    func back() {
        guard !route.isEmpty else { return }
        route.removeLast()
        if let previous = route.last {
            loadDetail(for: previous)
        }
    }

    func openArtist(named name: String) {
        Task {
            guard let artist = await apple.findArtist(named: name) else {
                showToast(String(localized: "Couldn’t find \(name) on Apple Music"))
                return
            }
            open(.artist(artist))
        }
    }

    private func loadDetail(for destination: AppleMusicDetailRoute) {
        detailTask?.cancel()
        artistDetail = nil
        albumDetail = nil
        playlistDetail = nil
        isLoadingDetail = true
        detailTask = Task {
            switch destination {
            case .artist(let artist):
                let detail = await apple.artistDetail(id: artist.id)
                guard !Task.isCancelled else { return }
                artistDetail = detail ?? AppleMusicArtistDetail(artist: artist)
            case .album(let album):
                let detail = await apple.albumDetail(id: album.id)
                guard !Task.isCancelled else { return }
                albumDetail = detail ?? AppleMusicAlbumDetail(album: album)
            case .playlist(let playlist):
                let detail = await apple.playlistDetail(id: playlist.id, isLibrary: playlist.isLibrary)
                guard !Task.isCancelled else { return }
                playlistDetail = detail ?? AppleMusicPlaylistDetail(playlist: playlist)
            }
            isLoadingDetail = false
        }
    }

    // MARK: Actions

    func perform(_ failure: String, _ operation: @escaping () async -> Bool) {
        Task {
            let ok = await operation()
            guard !ok else { return }
            let account = MusicKitAppleMusicManager.shared.account
            if account.isAuthorized && !account.canPlayCatalogContent {
                showToast(String(localized: "An Apple Music subscription is needed to play this."))
            } else {
                showToast(account.lastError ?? failure)
            }
        }
    }

    func play(_ song: AppleMusicSong, in songs: [AppleMusicSong]) {
        perform(String(localized: "Couldn’t play \(song.title).")) { await self.apple.play(song: song, within: songs) }
    }

    func playNext(_ song: AppleMusicSong) {
        perform(String(localized: "Couldn’t queue \(song.title).")) {
            let ok = await self.apple.playNext(songIDs: [song.catalogID ?? song.id])
            if ok { self.showToast(String(localized: "Playing next: \(song.title)")) }
            return ok
        }
    }

    func playLater(_ song: AppleMusicSong) {
        perform(String(localized: "Couldn’t queue \(song.title).")) {
            let ok = await self.apple.playLater(songIDs: [song.catalogID ?? song.id])
            if ok { self.showToast(String(localized: "Added to queue: \(song.title)")) }
            return ok
        }
    }

    func startStation(for song: AppleMusicSong) {
        perform(String(localized: "No station for \(song.title).")) { await self.apple.playSongStation(songID: song.catalogID ?? song.id) }
    }

    func addToLibrary(_ song: AppleMusicSong) {
        Task {
            if await apple.addToLibrary(song: song) {
                showToast(String(localized: "Added \(song.title) to your library"))
            } else {
                showToast(String(localized: "Opened in Music — add it from there"))
            }
        }
    }

    func copyLink(_ url: URL?) {
        guard let url else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
        showToast(String(localized: "Link copied"))
    }

    func showToast(_ message: String) {
        toast = message
        toastTask?.cancel()
        toastTask = Task {
            try? await Task.sleep(nanoseconds: 2_600_000_000)
            guard !Task.isCancelled else { return }
            toast = nil
        }
    }
}

// MARK: - View

struct AppleMusicSearchView: View {
    @Binding var navigationStack: [NotchWidgetMode]
    var musicManager: MusicManager { .shared }
    @ObservedSettings var settings: SettingsObserver
    @StateObject private var vm = AppleMusicSearchViewModel()
    private var musicKit: MusicKitAppleMusicManager { .shared }
    @ObservedObject private var navigator = AppleMusicNavigator.shared

    private var apple: AppleMusicManager { musicManager.appleMusic }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let destination = vm.route.last {
                detailHeader(for: destination)
                detailContent(for: destination)
            } else {
                searchField
                searchContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .overlay(alignment: .bottom) { toastView }
        .task { await vm.loadDiscover() }
        .onAppear { consumePendingRoute() }
        .onChange(of: navigator.pending) { _, _ in consumePendingRoute() }
        .onChange(of: musicKit.account.authorization) { _, status in
            guard status == .authorized else { return }
            Task { await vm.loadDiscover(force: true) }
        }
    }

    private func consumePendingRoute() {
        guard let route = navigator.pending else { return }
        navigator.pending = nil
        vm.route = []
        vm.open(route)
    }

    // MARK: Search field

    private var searchField: some View {
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
                Button { vm.clearSearch() } label: {
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
    }

    @ViewBuilder
    private var searchContent: some View {
        if !musicKit.account.isAuthorized {
            accessCard
        } else if vm.isSearching && vm.results.isEmpty {
            centeredPlaceholder(systemImage: "magnifyingglass", label: String(localized: "Searching…"))
        } else if !vm.suggestions.isEmpty && vm.results.isEmpty && !vm.hasSearched {
            suggestionsList
        } else if vm.results.isEmpty && vm.hasSearched {
            centeredPlaceholder(systemImage: "music.note", label: String(localized: "No results for \"\(vm.query)\""))
        } else if vm.results.isEmpty {
            discoverSections
        } else {
            resultsList
        }
    }

    // MARK: Access

    private var accessCard: some View {
        let denied = musicKit.account.authorization == .denied || musicKit.account.authorization == .restricted
        return VStack(spacing: 12) {
            Image(systemName: "music.note.house.fill")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.pink)
            Text(denied ? String(localized: "Apple Music access is off") : String(localized: "Connect Apple Music"))
                .font(.system(size: 14, weight: .bold, design: .rounded))
            Text(denied
                 ? String(localized: "Allow Sapphire under System Settings → Privacy & Security → Media & Apple Music.")
                 : String(localized: "Browse your library, recommendations and the full catalog, and play without leaving the notch."))
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            Button {
                if denied {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Media") {
                        NSWorkspace.shared.open(url)
                    }
                } else {
                    Task { await apple.requestAuthorization() }
                }
            } label: {
                Text(denied ? String(localized: "Open Privacy Settings") : String(localized: "Allow Access"))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Color.pink.opacity(0.85), in: Capsule())
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Suggestions & results

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
            LazyVStack(alignment: .leading, spacing: 10) {
                if let top = vm.results.topResults.first {
                    resultSection(String(localized: "Top Result"), systemImage: "star.fill") {
                        topResultRow(top)
                    }
                }
                if !vm.results.songs.isEmpty {
                    resultSection(String(localized: "Songs"), systemImage: "music.note") {
                        ForEach(vm.results.songs.prefix(8)) { song in
                            songRow(song, in: vm.results.songs)
                        }
                    }
                }
                if !vm.results.librarySongs.isEmpty {
                    resultSection(String(localized: "In Your Library"), systemImage: "books.vertical.fill") {
                        ForEach(vm.results.librarySongs) { song in
                            songRow(song, in: vm.results.librarySongs)
                        }
                    }
                }
                if !vm.results.artists.isEmpty {
                    resultSection(String(localized: "Artists"), systemImage: "music.mic") {
                        tileStrip(vm.results.artists.prefix(10).map { .artist($0) })
                    }
                }
                if !vm.results.albums.isEmpty {
                    resultSection(String(localized: "Albums"), systemImage: "square.stack") {
                        tileStrip(vm.results.albums.prefix(10).map { .album($0) })
                    }
                }
                if !vm.results.playlists.isEmpty {
                    resultSection(String(localized: "Playlists"), systemImage: "music.note.list") {
                        tileStrip(vm.results.playlists.prefix(10).map { .playlist($0) })
                    }
                }
                if !vm.results.stations.isEmpty {
                    resultSection(String(localized: "Stations"), systemImage: "dot.radiowaves.left.and.right") {
                        tileStrip(vm.results.stations.prefix(10).map { .station($0) })
                    }
                }
            }
            .padding(.bottom, 24)
        }
    }

    @ViewBuilder
    private func topResultRow(_ top: AppleMusicTopResult) -> some View {
        switch top {
        case .song(let song): songRow(song, in: vm.results.songs)
        case .album(let album):
            AppleMusicAlbumRow(album: album) { vm.open(.album(album)) }
        case .artist(let artist):
            AppleMusicArtistRow(artist: artist) { vm.open(.artist(artist)) }
        case .playlist(let playlist):
            AppleMusicPlaylistRow(playlist: playlist) { vm.open(.playlist(playlist)) }
        case .station(let station):
            AppleMusicMediaTile(item: .station(station), width: 72) {
                vm.perform(String(localized: "Couldn’t start \(station.name).")) { await apple.playStation(stationID: station.id) }
            }
        }
    }

    private func songRow(_ song: AppleMusicSong, in list: [AppleMusicSong]) -> some View {
        AppleMusicSongRow(song: song) { vm.play(song, in: list) }
            .contextMenu { songMenu(song, in: list) }
    }

    @ViewBuilder
    private func songMenu(_ song: AppleMusicSong, in list: [AppleMusicSong]) -> some View {
        Button("Play") { vm.play(song, in: list) }
        Button("Play Next") { vm.playNext(song) }
        Button("Play Later") { vm.playLater(song) }
        Divider()
        Button("Start Station") { vm.startStation(for: song) }
        Button("Go to Artist") { vm.openArtist(named: song.artistName) }
        Divider()
        Button("Add to Library") { vm.addToLibrary(song) }
        Button("Open in Music") { apple.open(url: song.url) }
        if song.url != nil {
            Button("Copy Link") { vm.copyLink(song.url) }
        }
    }

    private func tileStrip(_ items: [AppleMusicTileItem], width: CGFloat = 72) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: 10) {
                ForEach(items) { item in
                    AppleMusicMediaTile(item: item, width: width) { activate(item) }
                        .contextMenu { tileMenu(item) }
                }
            }
            .padding(.leading, 2)
        }
    }

    private func activate(_ item: AppleMusicTileItem) {
        switch item {
        case .album(let album): vm.open(.album(album))
        case .artist(let artist): vm.open(.artist(artist))
        case .playlist(let playlist): vm.open(.playlist(playlist))
        case .station(let station):
            vm.perform(String(localized: "Couldn’t start \(station.name).")) { await apple.playStation(stationID: station.id) }
        }
    }

    @ViewBuilder
    private func tileMenu(_ item: AppleMusicTileItem) -> some View {
        switch item {
        case .album(let album):
            Button("Play") { vm.perform(String(localized: "Couldn’t play \(album.title).")) { await apple.playAlbum(albumID: album.id) } }
            Button("Go to Artist") { vm.openArtist(named: album.artistName) }
            Button("Open in Music") { apple.open(url: album.url) }
        case .artist(let artist):
            Button("Play Top Songs") { vm.perform(String(localized: "Couldn’t play \(artist.name).")) { await apple.playArtistTopTracks(artistID: artist.id) } }
            Button("Start Station") { vm.perform(String(localized: "No station for \(artist.name).")) { await apple.playArtistStation(artistID: artist.id) } }
            Button("Open in Music") { apple.open(url: artist.url) }
        case .playlist(let playlist):
            Button("Play") { vm.perform(String(localized: "Couldn’t play \(playlist.name).")) { await apple.playPlaylist(playlist) } }
            Button("Shuffle") { vm.perform(String(localized: "Couldn’t play \(playlist.name).")) { await apple.playPlaylist(playlist, shuffled: true) } }
            Button("Open in Music") { apple.open(url: playlist.url) }
        case .station(let station):
            Button("Play") { vm.perform(String(localized: "Couldn’t start \(station.name).")) { await apple.playStation(stationID: station.id) } }
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

    // MARK: Discover

    private var discoverSections: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 14) {
                if vm.isLoadingDiscover && vm.discoverIsEmpty {
                    ProgressView()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                }

                ForEach(vm.recommendations) { shelf in
                    discoverSection(title: shelf.title, systemImage: "sparkles", subtitle: shelf.reason) {
                        shelfStrip(shelf.items)
                    }
                }

                if !vm.recentContainers.isEmpty {
                    discoverSection(title: String(localized: "Recently Played"), systemImage: "clock.fill") {
                        shelfStrip(vm.recentContainers)
                    }
                }

                if !vm.recentlyPlayed.isEmpty {
                    discoverSection(title: String(localized: "Recent Songs"), systemImage: "clock.arrow.circlepath") {
                        songList(vm.recentlyPlayed, limit: 6)
                    }
                }

                if !vm.replay.topSongs.isEmpty {
                    discoverSection(title: vm.replay.playlistName ?? String(localized: "Your Replay"), systemImage: "arrow.clockwise.circle.fill") {
                        songList(vm.replay.topSongs, limit: 6)
                        if !vm.replay.topArtists.isEmpty {
                            Text(String(localized: "Top artists: \(vm.replay.topArtists.prefix(5).map(\.name).joined(separator: ", "))"))
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                }

                if !vm.mostPlayed.isEmpty {
                    discoverSection(title: String(localized: "Your Most Played"), systemImage: "flame.fill") {
                        songList(vm.mostPlayed, limit: 6, showPlayCount: true)
                    }
                }

                if !vm.heavyRotation.isEmpty {
                    discoverSection(title: String(localized: "Heavy Rotation"), systemImage: "repeat") {
                        tileStrip(vm.heavyRotation.map { .album($0) }, width: 64)
                    }
                }

                chartsSection

                if !vm.recentlyAdded.isEmpty {
                    discoverSection(title: String(localized: "Recently Added"), systemImage: "plus.circle.fill") {
                        songList(vm.recentlyAdded, limit: 6)
                    }
                }

                if vm.discoverLoaded && !vm.isLoadingDiscover && vm.discoverIsEmpty {
                    centeredPlaceholder(systemImage: "music.quarternote.3", label: String(localized: "Search for songs, artists or albums"))
                        .frame(height: 140)
                }

                appleMusicStatusCard
            }
            .padding(.top, 2)
            .padding(.bottom, 20)
        }
    }

    @ViewBuilder
    private var chartsSection: some View {
        if !vm.charts.songs.isEmpty || !vm.charts.albums.isEmpty || !vm.genres.isEmpty {
            discoverSection(title: vm.selectedGenre.map { String(localized: "Top \($0.name)") } ?? String(localized: "Top Charts"), systemImage: "chart.bar.fill") {
                if !vm.genres.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            genreChip(nil)
                            ForEach(vm.genres) { genreChip($0) }
                        }
                    }
                }
                if !vm.charts.songs.isEmpty {
                    songList(vm.charts.songs, limit: 8, numbered: true)
                }
                if !vm.charts.albums.isEmpty {
                    tileStrip(vm.charts.albums.prefix(12).map { .album($0) }, width: 64)
                }
                let playlists = vm.charts.dailyGlobalTop + vm.charts.cityTop + vm.charts.playlists
                if !playlists.isEmpty {
                    tileStrip(playlists.prefix(12).map { .playlist($0) }, width: 64)
                }
            }
        }
    }

    private func genreChip(_ genre: AppleMusicGenre?) -> some View {
        let selected = vm.selectedGenre == genre
        return Button { vm.selectGenre(genre) } label: {
            Text(genre?.name ?? String(localized: "All"))
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(selected ? Color.pink.opacity(0.8) : Color.white.opacity(0.08), in: Capsule())
                .foregroundStyle(selected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
    }

    private func shelfStrip(_ items: [AppleMusicShelfItem]) -> some View {
        tileStrip(items.map(AppleMusicTileItem.init))
    }

    private func songList(_ songs: [AppleMusicSong], limit: Int, numbered: Bool = false, showPlayCount: Bool = false) -> some View {
        LazyVStack(spacing: 2) {
            ForEach(Array(songs.prefix(limit).enumerated()), id: \.element.id) { index, song in
                HStack(spacing: 6) {
                    if numbered {
                        Text("\(index + 1)")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(.tertiary)
                            .frame(width: 16)
                    }
                    songRow(song, in: songs)
                    if showPlayCount, let plays = song.playCount {
                        Text("\(plays) plays")
                            .font(.system(size: 9, weight: .semibold, design: .rounded))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    private var appleMusicStatusCard: some View {
        let account = musicKit.account
        let healthy = account.isAuthorized && account.canPlayCatalogContent && account.lastError == nil
        let symbol = healthy ? "checkmark.circle.fill" : (account.isAuthorized ? "exclamationmark.triangle.fill" : "xmark.circle.fill")
        let tint: Color = healthy ? .green : (account.isAuthorized ? .orange : .red)
        return VStack(alignment: .leading, spacing: 4) {
            Label("Apple Music connection", systemImage: symbol)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(tint)
            Text(apple.diagnosticsSummary)
                .font(.system(size: 10, weight: .regular, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(5)
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
        subtitle: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Label(title, systemImage: systemImage)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(MaterialChartPalette.secondary)
                    .labelStyle(.titleAndIcon)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(MaterialChartPalette.surface.opacity(0.45))
        )
    }

    // MARK: Detail pages

    private func detailHeader(for destination: AppleMusicDetailRoute) -> some View {
        HStack(spacing: 8) {
            Button { vm.back() } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .bold))
                    Text(vm.route.count > 1 ? String(localized: "Back") : String(localized: "Search"))
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.07), in: Capsule())
            }
            .buttonStyle(.plain)
            Spacer(minLength: 0)
            if vm.isLoadingDetail {
                ProgressView().controlSize(.small)
            }
        }
    }

    @ViewBuilder
    private func detailContent(for destination: AppleMusicDetailRoute) -> some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 14) {
                switch destination {
                case .artist(let artist):
                    artistPage(vm.artistDetail ?? AppleMusicArtistDetail(artist: artist))
                case .album(let album):
                    albumPage(vm.albumDetail ?? AppleMusicAlbumDetail(album: album))
                case .playlist(let playlist):
                    playlistPage(vm.playlistDetail ?? AppleMusicPlaylistDetail(playlist: playlist))
                }
            }
            .padding(.bottom, 24)
        }
    }

    @ViewBuilder
    private func artistPage(_ detail: AppleMusicArtistDetail) -> some View {
        let artist = detail.artist
        detailHero(
            artworkURL: artist.artworkURL,
            circular: true,
            title: artist.name,
            subtitle: artist.genreNames.first,
            caption: nil,
            badges: []
        ) {
            pillButton(String(localized: "Play"), systemImage: "play.fill", prominent: true) {
                vm.perform(String(localized: "Couldn’t play \(artist.name).")) { await apple.playArtistTopTracks(artistID: artist.id) }
            }
            if detail.station != nil {
                pillButton(String(localized: "Station"), systemImage: "dot.radiowaves.left.and.right") {
                    vm.perform(String(localized: "No station for \(artist.name).")) { await apple.playArtistStation(artistID: artist.id) }
                }
            }
            pillButton(String(localized: "Open"), systemImage: "arrow.up.right.square") { apple.open(url: artist.url) }
        }
        if let bio = detail.bio, !bio.isEmpty {
            Text(bio.strippingSimpleHTML)
                .font(.system(size: 11, weight: .regular, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(4)
        }
        if let latest = detail.latestRelease {
            discoverSection(title: String(localized: "Latest Release"), systemImage: "sparkle") {
                AppleMusicAlbumRow(album: latest) { vm.open(.album(latest)) }
            }
        }
        if !detail.topSongs.isEmpty {
            discoverSection(title: String(localized: "Top Songs"), systemImage: "music.note") {
                songList(detail.topSongs, limit: 10, numbered: true)
            }
        }
        albumShelf(String(localized: "Albums"), detail.albums)
        albumShelf(String(localized: "Singles & EPs"), detail.singles)
        albumShelf(String(localized: "Live Albums"), detail.liveAlbums)
        albumShelf(String(localized: "Compilations"), detail.compilations)
        albumShelf(String(localized: "Appears On"), detail.appearsOn)
        if !detail.featuredPlaylists.isEmpty {
            discoverSection(title: String(localized: "Featured Playlists"), systemImage: "music.note.list") {
                tileStrip(detail.featuredPlaylists.map { .playlist($0) })
            }
        }
        if !detail.similarArtists.isEmpty {
            discoverSection(title: String(localized: "Similar Artists"), systemImage: "person.2.fill") {
                tileStrip(detail.similarArtists.map { .artist($0) })
            }
        }
    }

    @ViewBuilder
    private func albumShelf(_ title: String, _ albums: [AppleMusicAlbum]) -> some View {
        if !albums.isEmpty {
            discoverSection(title: title, systemImage: "square.stack.fill") {
                tileStrip(albums.map { .album($0) })
            }
        }
    }

    @ViewBuilder
    private func albumPage(_ detail: AppleMusicAlbumDetail) -> some View {
        let album = detail.album
        let caption = [
            album.releaseDate.map { String(Calendar.current.component(.year, from: $0)) },
            detail.genreNames.first,
            detail.tracks.isEmpty ? nil : String(localized: "\(String(detail.tracks.count)) songs")
        ].compactMap { $0 }.joined(separator: " · ")
        detailHero(
            artworkURL: album.artworkURL,
            circular: false,
            title: album.title,
            subtitle: album.artistName,
            caption: caption.isEmpty ? nil : caption,
            badges: detail.audioBadges,
            onSubtitleTap: { vm.openArtist(named: album.artistName) }
        ) {
            pillButton(String(localized: "Play"), systemImage: "play.fill", prominent: true) {
                vm.perform(String(localized: "Couldn’t play \(album.title).")) { await apple.playAlbum(albumID: album.id) }
            }
            pillButton(String(localized: "Shuffle"), systemImage: "shuffle") {
                vm.perform(String(localized: "Couldn’t play \(album.title).")) {
                    let ok = await apple.playAlbum(albumID: album.id)
                    if ok { apple.setShuffle(enabled: true) }
                    return ok
                }
            }
            pillButton(String(localized: "Open"), systemImage: "arrow.up.right.square") { apple.open(url: album.url) }
        }
        if !detail.tracks.isEmpty {
            LazyVStack(spacing: 2) {
                ForEach(Array(detail.tracks.enumerated()), id: \.element.id) { index, song in
                    HStack(spacing: 6) {
                        Text("\(index + 1)")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(.tertiary)
                            .frame(width: 18)
                        AppleMusicSongRow(song: song) {
                            vm.perform(String(localized: "Couldn’t play \(song.title).")) { await apple.playAlbum(albumID: album.id, startingAt: song.id) }
                        }
                        .contextMenu { songMenu(song, in: detail.tracks) }
                    }
                }
            }
        }
        if let notes = detail.notes, !notes.isEmpty {
            Text(notes.strippingSimpleHTML)
                .font(.system(size: 11, weight: .regular, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(5)
        }
        if let footer = [detail.recordLabel, detail.copyright].compactMap({ $0 }).first {
            Text(footer)
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(.tertiary)
        }
        albumShelf(String(localized: "Other Versions"), detail.otherVersions)
        albumShelf(String(localized: "You Might Also Like"), detail.relatedAlbums)
        if !detail.appearsOn.isEmpty {
            discoverSection(title: String(localized: "Featured On"), systemImage: "music.note.list") {
                tileStrip(detail.appearsOn.map { .playlist($0) })
            }
        }
    }

    @ViewBuilder
    private func playlistPage(_ detail: AppleMusicPlaylistDetail) -> some View {
        let playlist = detail.playlist
        detailHero(
            artworkURL: playlist.artworkURL,
            circular: false,
            title: playlist.name,
            subtitle: playlist.curatorName,
            caption: detail.tracks.isEmpty ? playlist.shortDescription : String(localized: "\(String(detail.tracks.count)) songs"),
            badges: []
        ) {
            pillButton(String(localized: "Play"), systemImage: "play.fill", prominent: true) {
                vm.perform(String(localized: "Couldn’t play \(playlist.name).")) { await apple.playPlaylist(playlist) }
            }
            pillButton(String(localized: "Shuffle"), systemImage: "shuffle") {
                vm.perform(String(localized: "Couldn’t play \(playlist.name).")) { await apple.playPlaylist(playlist, shuffled: true) }
            }
            if playlist.url != nil {
                pillButton(String(localized: "Open"), systemImage: "arrow.up.right.square") { apple.open(url: playlist.url) }
            }
        }
        if !detail.tracks.isEmpty {
            LazyVStack(spacing: 2) {
                ForEach(detail.tracks) { song in
                    AppleMusicSongRow(song: song) {
                        vm.perform(String(localized: "Couldn’t play \(song.title).")) { await apple.playPlaylist(playlist, startingAt: song.id) }
                    }
                    .contextMenu { songMenu(song, in: detail.tracks) }
                }
            }
        }
        if !detail.featuredArtists.isEmpty {
            discoverSection(title: String(localized: "Featured Artists"), systemImage: "person.2.fill") {
                tileStrip(detail.featuredArtists.map { .artist($0) })
            }
        }
        if !detail.moreByCurator.isEmpty {
            discoverSection(title: String(localized: "More by \(playlist.curatorName ?? String(localized: "Curator"))"), systemImage: "music.note.list") {
                tileStrip(detail.moreByCurator.map { .playlist($0) })
            }
        }
    }

    private func detailHero<Buttons: View>(
        artworkURL: URL?,
        circular: Bool,
        title: String,
        subtitle: String?,
        caption: String?,
        badges: [AppleMusicAudioBadge],
        onSubtitleTap: (() -> Void)? = nil,
        @ViewBuilder buttons: () -> Buttons
    ) -> some View {
        HStack(alignment: .top, spacing: 14) {
            CachedAsyncImage(url: artworkURL) { img in
                img.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                ZStack {
                    Color.white.opacity(0.08)
                    Image(systemName: circular ? "music.mic" : "music.note")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 92, height: 92)
            .clipShape(RoundedRectangle(cornerRadius: circular ? 46 : 14, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .lineLimit(2)
                if let subtitle, !subtitle.isEmpty {
                    Button { onSubtitleTap?() } label: {
                        Text(subtitle)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(onSubtitleTap == nil ? Color.secondary : Color.pink)
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                    .disabled(onSubtitleTap == nil)
                }
                if let caption, !caption.isEmpty {
                    Text(caption)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                }
                if !badges.isEmpty {
                    AppleMusicAudioBadgeRow(badges: badges)
                }
                HStack(spacing: 6) { buttons() }
                    .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
    }

    private func pillButton(_ title: String, systemImage: String, prominent: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(prominent ? Color.pink.opacity(0.85) : Color.white.opacity(0.09), in: Capsule())
                .foregroundStyle(prominent ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
    }

    // MARK: Misc

    @ViewBuilder
    private var toastView: some View {
        if let toast = vm.toast {
            Text(toast)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(.bottom, 6)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
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

// MARK: - Apple Music tiles & badges

private enum AppleMusicTileItem: Identifiable, Hashable {
    case album(AppleMusicAlbum)
    case artist(AppleMusicArtist)
    case playlist(AppleMusicPlaylist)
    case station(AppleMusicStation)

    init(_ shelfItem: AppleMusicShelfItem) {
        switch shelfItem {
        case .album(let album): self = .album(album)
        case .playlist(let playlist): self = .playlist(playlist)
        case .station(let station): self = .station(station)
        }
    }

    var id: String {
        switch self {
        case .album(let item): "album:\(item.id)"
        case .artist(let item): "artist:\(item.id)"
        case .playlist(let item): "playlist:\(item.id)"
        case .station(let item): "station:\(item.id)"
        }
    }

    var title: String {
        switch self {
        case .album(let item): item.title
        case .artist(let item): item.name
        case .playlist(let item): item.name
        case .station(let item): item.name
        }
    }

    var subtitle: String? {
        switch self {
        case .album(let item): item.artistName
        case .artist: "Artist"
        case .playlist(let item): item.curatorName
        case .station(let item): item.isLive ? String(localized: "Live") : String(localized: "Station")
        }
    }

    var artworkURL: URL? {
        switch self {
        case .album(let item): item.artworkURL
        case .artist(let item): item.artworkURL
        case .playlist(let item): item.artworkURL
        case .station(let item): item.artworkURL
        }
    }

    var placeholderSymbol: String {
        switch self {
        case .album: "square.stack"
        case .artist: "music.mic"
        case .playlist: "music.note.list"
        case .station: "dot.radiowaves.left.and.right"
        }
    }

    var isCircular: Bool {
        if case .artist = self { return true }
        return false
    }
}

private struct AppleMusicMediaTile: View {
    let item: AppleMusicTileItem
    let width: CGFloat
    let onTap: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: item.isCircular ? .center : .leading, spacing: 4) {
                CachedAsyncImage(url: item.artworkURL) { img in
                    img.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    ZStack {
                        Color.white.opacity(0.08)
                        Image(systemName: item.placeholderSymbol)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: width, height: width)
                .clipShape(RoundedRectangle(cornerRadius: item.isCircular ? width / 2 : 10, style: .continuous))
                .scaleEffect(isHovered ? 1.03 : 1)

                Text(item.title)
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                if let subtitle = item.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 8, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(width: width)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { isHovered = hovering }
        }
    }
}

struct AppleMusicAudioBadgeRow: View {
    let badges: [AppleMusicAudioBadge]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(badges, id: \.self) { badge in
                Label(badge.displayName, systemImage: badge.systemImage)
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .labelStyle(.titleAndIcon)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.white.opacity(0.09), in: Capsule())
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private extension String {
    var strippingSimpleHTML: String {
        replacingOccurrences(of: "<br />", with: "\n")
            .replacingOccurrences(of: "<br/>", with: "\n")
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
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
