//
//  LockScreenMusicPane.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-10

import SwiftUI
import AppKit

private struct LockScreenPaneWindowPresence: NSViewRepresentable {
    let isPresented: Bool

    final class Coordinator {
        var pendingOrderOut: DispatchWorkItem?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ nsView: NSView, context: Context) {
        let coordinator = context.coordinator
        let presented = isPresented
        DispatchQueue.main.async {
            guard let window = nsView.window else { return }
            coordinator.pendingOrderOut?.cancel()
            coordinator.pendingOrderOut = nil
            window.ignoresMouseEvents = !presented
            if presented {
                if !window.isVisible { RemoteViewCrashGuardRunBlock { window.orderFrontRegardless() } }
            } else if window.isVisible {
                let orderOut = DispatchWorkItem { [weak window] in window?.orderOut(nil) }
                coordinator.pendingOrderOut = orderOut
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: orderOut)
            }
        }
    }
}

// MARK: - Tabs

enum LockScreenMusicTab: String, CaseIterable, Identifiable {
    case nowPlaying, artist, playlists, queue, devices, lyrics

    var id: String { rawValue }

    var title: String {
        switch self {
        case .nowPlaying: String(localized: "Overview")
        case .artist: String(localized: "Artist")
        case .playlists: String(localized: "Library")
        case .queue: String(localized: "Queue")
        case .devices: String(localized: "Devices")
        case .lyrics: String(localized: "Lyrics")
        }
    }

    var systemImage: String {
        switch self {
        case .nowPlaying: "square.grid.2x2"
        case .artist: "person.crop.square.fill"
        case .playlists: "list.bullet.rectangle"
        case .queue: "text.line.first.and.arrowtriangle.forward"
        case .devices: "hifispeaker.2.fill"
        case .lyrics: "text.quote"
        }
    }
}

enum LockScreenMusicPaneOverlay: Identifiable, Equatable {
    case playlistDetail(SpotifyPlaylist), loginPrompt
    var id: String {
        switch self { case .playlistDetail(let p): p.uri; case .loginPrompt: "login" }
    }
}

// MARK: - Controller

@MainActor
final class LockScreenMusicPaneController: ObservableObject {
    static let shared = LockScreenMusicPaneController()
    @Published var isPresented = false
    @Published var selectedTab: LockScreenMusicTab = .nowPlaying
    @Published var overlay: LockScreenMusicPaneOverlay?
    @Published var isLyricsView = false
    private init() {}
    func open() {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) { isPresented = true; selectedTab = .nowPlaying; overlay = nil; isLyricsView = false }
        LockScreenManager.shared.setWidgetWindowsCovered(true)
        LiveWallpaperManager.shared.setCoveredByLockScreenMusicPane(true)
    }
    func close() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { isPresented = false; overlay = nil }
        LockScreenManager.shared.setWidgetWindowsCovered(false)
        LiveWallpaperManager.shared.setCoveredByLockScreenMusicPane(false)
    }
    func selectTab(_ tab: LockScreenMusicTab) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            selectedTab = tab
            overlay = nil
            isLyricsView = (tab == .lyrics)
        }
    }
    func present(_ destination: LockScreenMusicPaneOverlay) { withAnimation { overlay = destination } }
    func dismissOverlay() { withAnimation { overlay = nil } }
    func reset() {
        isPresented = false; selectedTab = .nowPlaying; overlay = nil; isLyricsView = false
        LiveWallpaperManager.shared.setCoveredByLockScreenMusicPane(false)
    }
}

// MARK: - Layout

private struct PaneMetrics {
    let size: CGSize
    let k: CGFloat

    init(size: CGSize) {
        self.size = size
        k = min(max(min(size.width / 1440, size.height / 900), 0.8), 1.8)
    }

    var hPad: CGFloat { 72 * k }
    var heroArtwork: CGFloat { min(size.height * 0.44, size.width * 0.3) }
    var lyricsArtwork: CGFloat { min(size.height * 0.3, size.width * 0.2) }
}

private struct PaneTrack: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let imageURL: URL?
    var play: (() async -> Void)?
}

// MARK: - Main Pane

struct LockScreenFullScreenMusicPane: View {
    @ObservedObject private var controller = LockScreenMusicPaneController.shared
    @StateObject private var navigationManager = LockScreenNavigationManager()
    private var screenSize: CGSize { NSScreen.main?.frame.size ?? CGSize(width: 1440, height: 900) }

    var body: some View {
        ZStack {
            if controller.isPresented {
                LockScreenMusicPaneContent(controller: controller, m: PaneMetrics(size: screenSize))
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
            }
        }
        .frame(width: screenSize.width, height: screenSize.height)
        .allowsHitTesting(controller.isPresented)
        .background(LockScreenPaneWindowPresence(isPresented: controller.isPresented))
        .environmentObject(navigationManager)
        .environment(\.colorScheme, .dark)
        .animation(.spring(response: 0.5, dampingFraction: 0.84), value: controller.isPresented)
    }
}

private struct LockScreenMusicPaneContent: View {
    @ObservedObject var controller: LockScreenMusicPaneController
    let m: PaneMetrics
    var musicManager: MusicManager { .shared }
    @ObservedSettings var settings: SettingsObserver
    @State private var dummyNavigationStack: [NotchWidgetMode] = []
    @State private var spotifyQueue: SpotifyQueue?
    @State private var appleMusicQueueTracks: [AppleMusicManager.QueueTrack] = []
    @State private var playlists: [SpotifyPlaylist] = []
    @State private var isLoadingLibrary = false
    @State private var officialDevices: [SpotifyDevice] = []
    @Namespace private var tabNamespace

    var body: some View {
        ZStack {
            paneContent(m)
            if let overlay = controller.overlay {
                overlayPanel(for: overlay, m).transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: controller.selectedTab)
        .animation(.spring(response: 0.4, dampingFraction: 0.84), value: controller.overlay)
        .onChange(of: musicManager.isPlaying) { _, playing in
            if !playing && (musicManager.title?.isEmpty ?? true) { controller.close() }
        }
    }

    private func paneContent(_ m: PaneMetrics) -> some View {
        ZStack {
            wallpaperBackdrop

            VStack(spacing: 0) {
                topBar(m)
                    .padding(.horizontal, m.hPad)
                    .padding(.top, 30 * m.k)

                tabContent(m)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.top, 20 * m.k)

                if showsMiniPlayer {
                    miniPlayer(m)
                        .padding(.horizontal, m.hPad)
                        .padding(.bottom, 32 * m.k)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .onAppear {
            Task { await musicManager.setLyricsDetailOpen(controller.isLyricsView) }
            Task {
                await musicManager.ensureSpotifyPlayerExtrasLoaded(force: true)
                await refreshQueueData()
            }
        }
        .onChange(of: controller.selectedTab) { _, tab in
            Task {
                await musicManager.setLyricsDetailOpen(tab == .lyrics)
                if tab == .artist || tab == .playlists {
                    await musicManager.ensureSpotifyPlayerExtrasLoaded(force: false)
                }
                if tab == .queue || tab == .nowPlaying { await refreshQueueData() }
                if tab == .playlists { await refreshPlaylistData() }
            }
        }
        .onDisappear { Task { await musicManager.setLyricsDetailOpen(false) } }
    }

    private var wallpaperBackdrop: some View {
        ZStack {
            LockScreenWidgetSurface(shape: Rectangle(), cacheKey: "pane-backdrop")
            LinearGradient(
                colors: [.black.opacity(0.3), .black.opacity(0.15), .black.opacity(0.35)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private var showsMiniPlayer: Bool {
        controller.selectedTab != .nowPlaying && controller.selectedTab != .lyrics
    }

    private func refreshQueueData() async {
        musicManager.spotifyPrivateAPI.bootstrapIfNeeded(policy: .onDemand)
        if musicManager.lastKnownBundleID == "com.apple.Music" {
            appleMusicQueueTracks = await musicManager.appleMusic.fetchUpNextTracks()
        } else if musicManager.isPrivateAPIAuthenticated {
            await musicManager.spotifyPrivateAPI.refreshQueueForUI()
            if spotifyQueue == nil || spotifyQueue?.queue.isEmpty == true {
                spotifyQueue = await musicManager.spotifyOfficialAPI.fetchQueue()
            }
        } else if musicManager.isOfficialAPIAuthenticated {
            spotifyQueue = await musicManager.spotifyOfficialAPI.fetchQueue()
        }
    }

    private func refreshPlaylistData() async {
        isLoadingLibrary = true
        defer { isLoadingLibrary = false }
        if isAppleMusic {
            let apple = musicManager.appleMusic
            if apple.isMusicKitAuthorized { await apple.refreshPlaylists() }
            playlists = apple.fetchPlaylists()
            return
        }
        musicManager.spotifyPrivateAPI.bootstrapIfNeeded(policy: .onDemand)
        if musicManager.isPrivateAPIAuthenticated {
            if musicManager.spotifyPrivateAPI.nativePlaylists.isEmpty {
                await musicManager.spotifyPrivateAPI.fetchUserLibrary()
            }
            playlists = musicManager.spotifyPrivateAPI.nativePlaylists
        } else if musicManager.isOfficialAPIAuthenticated {
            playlists = await musicManager.spotifyOfficialAPI.fetchPlaylists()
        }
    }

    private var isSpotify: Bool { musicManager.isSpotifyLiveSourceSelected || musicManager.isSpotifySourceActive }
    private var isAppleMusic: Bool { musicManager.lastKnownBundleID == "com.apple.Music" }

    private var upcomingTracks: [PaneTrack] {
        if isAppleMusic {
            return appleMusicQueueTracks.enumerated().map { index, track in
                PaneTrack(id: "am-\(index)-\(track.id)", title: track.title, subtitle: track.artist, imageURL: track.artworkURL) {
                    await musicManager.appleMusic.playQueueTrack(track)
                    await refreshQueueData()
                }
            }
        }
        if !musicManager.nativeQueue.isEmpty {
            return musicManager.nativeQueue.enumerated().map { index, track in
                PaneTrack(
                    id: "sp-\(index)-\(track.uid)",
                    title: track.metadata?.title ?? String(localized: "Unknown Track"),
                    subtitle: track.metadata?.artistName ?? String(localized: "Unknown Artist"),
                    imageURL: track.metadata?.imageURL
                )
            }
        }
        return (spotifyQueue?.queue ?? []).enumerated().map { index, track in
            PaneTrack(
                id: "web-\(index)-\(track.id)",
                title: track.name,
                subtitle: track.artists.map(\.name).joined(separator: ", "),
                imageURL: track.imageURL
            )
        }
    }

    // MARK: - Top Bar

    private func topBar(_ m: PaneMetrics) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: 2 * m.k) {
                topBarButton("xmark", help: String(localized: "Close"), selected: false, m) { controller.close() }
                Capsule()
                    .fill(Color.white.opacity(0.18))
                    .frame(width: 1, height: 18 * m.k)
                    .padding(.horizontal, 6 * m.k)
                ForEach(visibleTabs) { tab in
                    topBarButton(tab.systemImage, help: tab.title, selected: controller.selectedTab == tab, m) {
                        controller.selectTab(tab)
                    }
                }
            }
            .padding(4 * m.k)
            .background(LockScreenWidgetSurface(shape: Capsule(style: .continuous), cacheKey: "pane-tabs"))

            Spacer(minLength: 0)

            if let icon = musicManager.appIcon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 24 * m.k, height: 24 * m.k)
                    .opacity(0.85)
            }
        }
    }

    private func topBarButton(_ systemName: String, help: String, selected: Bool, _ m: PaneMetrics, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14 * m.k, weight: .medium))
                .foregroundStyle(selected ? Color.white : Color.white.opacity(0.55))
                .frame(width: 34 * m.k, height: 34 * m.k)
                .background {
                    if selected {
                        Circle()
                            .fill(Color.white.opacity(0.18))
                            .matchedGeometryEffect(id: "tab", in: tabNamespace)
                    }
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }

    private var visibleTabs: [LockScreenMusicTab] {
        let hasArtist = isSpotify && musicManager.spotifyPrivateAPI.nowPlayingArtist != nil
        var tabs: [LockScreenMusicTab] = [.nowPlaying, .lyrics]
        if hasArtist { tabs.append(.artist) }
        tabs.append(contentsOf: [.queue, .playlists, .devices])
        return tabs
    }

    // MARK: - Tab Content

    @ViewBuilder
    private func tabContent(_ m: PaneMetrics) -> some View {
        ZStack {
            switch controller.selectedTab {
            case .nowPlaying: nowPlayingTab(m)
            case .lyrics: lyricsTab(m)
            case .artist: artistTab(m)
            case .playlists: playlistsTab(m)
            case .queue: queueTab(m)
            case .devices: devicesTab(m)
            }
        }
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
        .id(controller.selectedTab)
    }

    // MARK: - Now Playing

    private func nowPlayingTab(_ m: PaneMetrics) -> some View {
        let upcoming = Array(upcomingTracks.prefix(3))
        let artist = isSpotify ? musicManager.spotifyPrivateAPI.nowPlayingArtist : nil
        let moreByArtist = isAppleMusic ? Array(musicManager.appleNowPlaying.moreByArtist.prefix(3)) : []

        return VStack(spacing: 34 * m.k) {
            HStack(alignment: .center, spacing: 64 * m.k) {
                VStack(alignment: .leading, spacing: 16 * m.k) {
                    albumArtwork(size: m.heroArtwork, radius: 36 * m.k)
                        .shadow(color: .black.opacity(0.35), radius: 30 * m.k, y: 14 * m.k)
                    if let output = playbackOutput {
                        HStack(spacing: 8 * m.k) {
                            Image(systemName: output.icon)
                                .font(.system(size: 13 * m.k, weight: .medium))
                            Text("Playing on \(output.name)")
                                .font(.system(size: 13 * m.k, weight: .medium, design: .rounded))
                                .lineLimit(1)
                        }
                        .foregroundStyle(.white.opacity(0.6))
                    }
                }
                .frame(width: m.heroArtwork, alignment: .leading)

                VStack(alignment: .leading, spacing: 0) {
                    albumLine(m)

                    Text(musicManager.title ?? String(localized: "Not Playing"))
                        .font(.system(size: 50 * m.k, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.55)
                        .padding(.top, 10 * m.k)

                    artistLine(artist, m)
                        .padding(.top, 6 * m.k)

                    statChips(m)
                        .padding(.top, 18 * m.k)

                    PaneScrubber(k: m.k, style: .hero)
                        .padding(.top, 28 * m.k)

                    transportControls(m, style: .hero)
                        .padding(.top, 18 * m.k)

                    if !musicManager.lyrics.isEmpty {
                        lyricPreview(m)
                            .padding(.top, 24 * m.k)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !upcoming.isEmpty || artist != nil || !moreByArtist.isEmpty {
                HStack(alignment: .top, spacing: 20 * m.k) {
                    if !upcoming.isEmpty {
                        upNextCard(upcoming, m)
                    }
                    if let artist {
                        artistCard(artist, m)
                    } else if !moreByArtist.isEmpty {
                        moreByCard(moreByArtist, m)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, m.hPad)
        .padding(.bottom, 36 * m.k)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var playbackOutput: (icon: String, name: String)? {
        let api = musicManager.spotifyPrivateAPI
        if isSpotify, let id = api.activePlayerDeviceID,
           let device = api.devices.first(where: { $0.deviceId == id }) {
            return (deviceIcon(for: device.deviceType), device.name)
        }
        if let airplay = musicManager.airplayDevices.first(where: \.isSelected) {
            return (airplay.iconName, airplay.name)
        }
        let audio = MultiAudioManager.shared
        if let id = audio.defaultOutputDeviceID,
           let device = audio.availableOutputDevices.first(where: { $0.id == id }) {
            return (IconMapper.icon(for: device), device.name)
        }
        return nil
    }

    private func albumLine(_ m: PaneMetrics) -> some View {
        let details = musicManager.appleNowPlaying
        let album = musicManager.album.flatMap { $0.isEmpty || $0 == musicManager.title ? nil : $0 }
        let year = isAppleMusic ? details.releaseDate.map { String(Calendar.current.component(.year, from: $0)) } : nil
        let label = [album, year].compactMap { $0 }.joined(separator: " · ")

        return HStack(spacing: 10 * m.k) {
            eyebrow(label.isEmpty ? String(localized: "Now Playing") : label, m)
            if isAppleMusic {
                ForEach(details.audioBadges.prefix(2), id: \.self) { badge in
                    Label(badge.displayName, systemImage: badge.systemImage)
                        .font(.system(size: 11 * m.k, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.75))
                        .padding(.horizontal, 8 * m.k)
                        .padding(.vertical, 3 * m.k)
                        .background(Capsule().strokeBorder(Color.white.opacity(0.3), lineWidth: 1))
                }
            }
        }
    }

    private func artistLine(_ artist: SpotifyArtistProfile?, _ m: PaneMetrics) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10 * m.k) {
            Text(musicManager.artist ?? String(localized: "Unknown Artist"))
                .font(.system(size: 23 * m.k, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.75))
                .lineLimit(1)
            if let artist, artist.isVerified {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 15 * m.k))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
    }

    private func statChips(_ m: PaneMetrics) -> some View {
        let popularity = musicManager.popularity ?? musicManager.fetchedSpotifyPopularity
        let details = musicManager.appleNowPlaying
        let plays: String? = {
            if isAppleMusic, let count = details.playCount ?? musicManager.applePlayCount, count > 0 {
                return count == 1 ? String(localized: "Played once") : String(localized: "Played \(String(count)) times")
            }
            return musicManager.playCount.map { String(localized: "\(String($0)) plays") }
        }()

        return HStack(spacing: 8 * m.k) {
            if let popularity {
                HStack(spacing: 7 * m.k) {
                    PopularityMeter(value: popularity, k: m.k)
                    Text("\(popularity)")
                        .monospacedDigit()
                }
                .modifier(PaneChip(k: m.k))
            }
            if let plays {
                Label(plays, systemImage: "play.circle")
                    .modifier(PaneChip(k: m.k))
            }
            if let genre = details.genreNames.first, isAppleMusic {
                Label(genre, systemImage: "guitars")
                    .modifier(PaneChip(k: m.k))
            }
            if musicManager.totalDuration > 0 {
                Label(musicManager.totalDuration.asMinuteSecondClock, systemImage: "clock")
                    .modifier(PaneChip(k: m.k))
            }
        }
    }

    private func lyricPreview(_ m: PaneMetrics) -> some View {
        let lyrics = musicManager.lyrics
        let current = musicManager.currentLyric
        let index = current.flatMap { line in lyrics.firstIndex { $0.id == line.id } }
        let next = index.flatMap { lyrics.indices.contains($0 + 1) ? lyrics[$0 + 1] : nil } ?? (current == nil ? lyrics.first : nil)

        return Button { controller.selectTab(.lyrics) } label: {
            VStack(alignment: .leading, spacing: 4 * m.k) {
                Text(current?.text.isEmpty == false ? current!.text : "")
                    .font(.system(size: 21 * m.k, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if let next, !next.text.isEmpty {
                    Text(next.text)
                        .font(.system(size: 16 * m.k, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.45))
                        .lineLimit(1)
                }
            }
            .padding(.leading, 14 * m.k)
            .overlay(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.5)).frame(width: 3 * m.k)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .animation(.easeInOut(duration: 0.25), value: current?.id)
        }
        .buttonStyle(.plain)
        .help("Show Lyrics")
    }

    private func upNextCard(_ tracks: [PaneTrack], _ m: PaneMetrics) -> some View {
        VStack(alignment: .leading, spacing: 10 * m.k) {
            HStack {
                eyebrow(String(localized: "Up Next"), m)
                Spacer()
                Button { controller.selectTab(.queue) } label: {
                    Text("See All")
                        .font(.system(size: 12 * m.k, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
            }
            ForEach(tracks) { track in
                Button { if let play = track.play { Task { await play() } } } label: {
                    HStack(spacing: 12 * m.k) {
                        remoteArtwork(track.imageURL, size: 42 * m.k, radius: 9 * m.k)
                        VStack(alignment: .leading, spacing: 1 * m.k) {
                            Text(track.title)
                                .font(.system(size: 15 * m.k, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            Text(track.subtitle)
                                .font(.system(size: 13 * m.k, weight: .medium, design: .rounded))
                                .foregroundStyle(.white.opacity(0.55))
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(track.play == nil)
            }
        }
        .padding(18 * m.k)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(PaneCardFill(cornerRadius: 24 * m.k))
    }

    private func artistCard(_ artist: SpotifyArtistProfile, _ m: PaneMetrics) -> some View {
        let concert = musicManager.spotifyPrivateAPI.artistConcerts.first
        return Button { controller.selectTab(.artist) } label: {
            HStack(alignment: .top, spacing: 16 * m.k) {
                remoteArtwork(artist.avatarURL ?? artist.headerImageURL, size: 64 * m.k, radius: 32 * m.k)
                VStack(alignment: .leading, spacing: 6 * m.k) {
                    eyebrow(String(localized: "About the Artist"), m)
                    Text(artist.name)
                        .font(.system(size: 19 * m.k, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if let listeners = artist.monthlyListeners ?? artist.followers {
                        Text(artist.monthlyListeners != nil
                            ? String(localized: "\(listeners.compactFormatted) monthly listeners")
                            : String(localized: "\(listeners.compactFormatted) followers"))
                            .font(.system(size: 13 * m.k, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    if let concert {
                        Label("\(concert.city) · \(Self.concertDate(concert.startDateIsoString))", systemImage: "ticket")
                            .font(.system(size: 13 * m.k, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.75))
                            .lineLimit(1)
                    } else if !artist.biography.isEmpty {
                        Text(artist.biography)
                            .font(.system(size: 13 * m.k, weight: .regular, design: .rounded))
                            .foregroundStyle(.white.opacity(0.6))
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(18 * m.k)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(PaneCardFill(cornerRadius: 24 * m.k))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func moreByCard(_ songs: [AppleMusicSong], _ m: PaneMetrics) -> some View {
        VStack(alignment: .leading, spacing: 10 * m.k) {
            eyebrow(musicManager.artist.map { String(localized: "More by \($0)") } ?? String(localized: "More by the Artist"), m)
            ForEach(songs) { song in
                HStack(spacing: 12 * m.k) {
                    remoteArtwork(song.artworkURL, size: 42 * m.k, radius: 9 * m.k)
                    VStack(alignment: .leading, spacing: 1 * m.k) {
                        Text(song.title)
                            .font(.system(size: 15 * m.k, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text(song.albumTitle ?? song.artistName)
                            .font(.system(size: 13 * m.k, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.55))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(18 * m.k)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(PaneCardFill(cornerRadius: 24 * m.k))
    }

    private static let concertInputFormatter = ISO8601DateFormatter()
    private static let concertOutputFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMMd")
        return formatter
    }()

    private static func concertDate(_ iso: String) -> String {
        guard let date = concertInputFormatter.date(from: iso) else { return String(iso.prefix(10)) }
        return concertOutputFormatter.string(from: date)
    }

    // MARK: - Lyrics

    private func lyricsTab(_ m: PaneMetrics) -> some View {
        HStack(alignment: .center, spacing: 72 * m.k) {
            VStack(alignment: .leading, spacing: 0) {
                albumArtwork(size: m.lyricsArtwork, radius: 30 * m.k)
                    .shadow(color: .black.opacity(0.3), radius: 24 * m.k, y: 10 * m.k)

                Text(musicManager.title ?? String(localized: "Not Playing"))
                    .font(.system(size: 24 * m.k, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                    .padding(.top, 22 * m.k)
                Text(musicManager.artist ?? String(localized: "Unknown Artist"))
                    .font(.system(size: 17 * m.k, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.65))
                    .lineLimit(1)
                    .padding(.top, 4 * m.k)

                PaneScrubber(k: m.k, style: .compact)
                    .padding(.top, 22 * m.k)
                transportControls(m, style: .compact)
                    .padding(.top, 14 * m.k)
            }
            .frame(width: m.lyricsArtwork)

            PaneLyrics(k: m.k, viewportHeight: m.size.height)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.leading, m.hPad)
        .padding(.trailing, m.hPad * 0.6)
    }

    // MARK: - Artist

    @ViewBuilder
    private func artistTab(_ m: PaneMetrics) -> some View {
        let api = musicManager.spotifyPrivateAPI
        if let artist = api.nowPlayingArtist {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 40 * m.k) {
                    HStack(spacing: 40 * m.k) {
                        if let url = artist.avatarURL ?? artist.headerImageURL {
                            remoteArtwork(url, size: 150 * m.k, radius: 75 * m.k)
                                .shadow(color: .black.opacity(0.3), radius: 20 * m.k, y: 8 * m.k)
                        }
                        VStack(alignment: .leading, spacing: 8 * m.k) {
                            eyebrow(artist.isVerified ? String(localized: "Verified Artist") : String(localized: "Artist"), m)
                            Text(artist.name)
                                .font(.system(size: 52 * m.k, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.45)
                            if let listeners = artist.monthlyListeners ?? artist.followers {
                                Text(artist.monthlyListeners != nil
                                    ? String(localized: "\(listeners.compactFormatted) monthly listeners")
                                    : String(localized: "\(listeners.compactFormatted) followers"))
                                    .font(.system(size: 18 * m.k, weight: .medium, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.65))
                            }
                        }
                    }

                    HStack(alignment: .top, spacing: 28 * m.k) {
                        if !artist.biography.isEmpty {
                            paneCard(m, key: "bio") {
                                cardTitle(String(localized: "About"), m)
                                Text(artist.biography)
                                    .font(.system(size: 17 * m.k, weight: .regular, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.78))
                                    .lineSpacing(5 * m.k)
                                    .lineLimit(9)
                            }
                        }
                        if !api.artistConcerts.isEmpty || !artist.topCities.isEmpty {
                            VStack(spacing: 28 * m.k) {
                                if !api.artistConcerts.isEmpty {
                                    paneCard(m, key: "concerts") {
                                        cardTitle(String(localized: "On Tour"), m)
                                        ForEach(api.artistConcerts.prefix(4)) { concert in
                                            VStack(alignment: .leading, spacing: 2 * m.k) {
                                                Text(concert.title)
                                                    .font(.system(size: 16 * m.k, weight: .bold, design: .rounded))
                                                    .foregroundStyle(.white)
                                                    .lineLimit(1)
                                                Text("\(concert.venue) · \(concert.city)")
                                                    .font(.system(size: 14 * m.k, weight: .medium, design: .rounded))
                                                    .foregroundStyle(.white.opacity(0.55))
                                                    .lineLimit(1)
                                            }
                                        }
                                    }
                                }
                                if !artist.topCities.isEmpty {
                                    paneCard(m, key: "cities") {
                                        cardTitle(String(localized: "Top Cities"), m)
                                        ForEach(Array(artist.topCities.prefix(5).enumerated()), id: \.offset) { index, city in
                                            HStack(spacing: 12 * m.k) {
                                                Text("\(index + 1)")
                                                    .font(.system(size: 15 * m.k, weight: .semibold, design: .rounded))
                                                    .foregroundStyle(.white.opacity(0.35))
                                                    .frame(width: 22 * m.k, alignment: .leading)
                                                Text(city)
                                                    .font(.system(size: 16 * m.k, weight: .semibold, design: .rounded))
                                                    .foregroundStyle(.white)
                                                    .lineLimit(1)
                                            }
                                        }
                                    }
                                }
                            }
                            .frame(width: min(440 * m.k, m.size.width * 0.32))
                        }
                    }

                    if !api.relatedTracks.isEmpty {
                        VStack(alignment: .leading, spacing: 16 * m.k) {
                            sectionTitle(String(localized: "Related Tracks"), m)
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16 * m.k), count: 3), spacing: 16 * m.k) {
                                ForEach(api.relatedTracks.prefix(9)) { track in
                                    Button { Task { _ = await musicManager.play(trackUri: track.uri, contextUri: nil) } } label: {
                                        HStack(spacing: 14 * m.k) {
                                            Image(systemName: "play.fill")
                                                .font(.system(size: 14 * m.k, weight: .bold))
                                                .foregroundStyle(.white)
                                                .frame(width: 38 * m.k, height: 38 * m.k)
                                                .background(Circle().fill(.white.opacity(0.14)))
                                            VStack(alignment: .leading, spacing: 2 * m.k) {
                                                Text(track.name)
                                                    .font(.system(size: 16 * m.k, weight: .bold, design: .rounded))
                                                    .foregroundStyle(.white)
                                                    .lineLimit(1)
                                                Text(track.artists.first?.name ?? "")
                                                    .font(.system(size: 13 * m.k, weight: .medium, design: .rounded))
                                                    .foregroundStyle(.white.opacity(0.55))
                                                    .lineLimit(1)
                                            }
                                            Spacer(minLength: 0)
                                        }
                                        .padding(14 * m.k)
                                        .background(RoundedRectangle(cornerRadius: 18 * m.k, style: .continuous).fill(.white.opacity(0.08)))
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }

                    if !api.similarAlbums.isEmpty {
                        tileRow(String(localized: "Fans Also Like"), m, items: Array(api.similarAlbums.prefix(10))) { album in
                            tile(url: album.imageURL, title: album.name, subtitle: album.artistName, m)
                        }
                    }

                    if !artist.merch.isEmpty {
                        tileRow(String(localized: "Merch"), m, items: artist.merch) { item in
                            tile(url: item.imageURL, title: item.name, subtitle: item.price ?? "", m)
                        }
                    }
                }
                .padding(.horizontal, m.hPad)
                .padding(.vertical, 24 * m.k)
            }
        } else {
            emptyState(String(localized: "No artist info for this track"), icon: "person.crop.circle", m)
        }
    }

    // MARK: - Library

    @ViewBuilder
    private func playlistsTab(_ m: PaneMetrics) -> some View {
        let signedIn = isAppleMusic
            ? musicManager.appleMusic.isMusicKitAuthorized
            : musicManager.isPrivateAPIAuthenticated || musicManager.isOfficialAPIAuthenticated
        if playlists.isEmpty && isLoadingLibrary {
            ProgressView().controlSize(.large).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if playlists.isEmpty {
            emptyState(
                signedIn ? String(localized: "No playlists found") : (isAppleMusic ? String(localized: "Allow Apple Music access to see your library") : String(localized: "Sign in to Spotify to see your library")),
                icon: "music.note.list",
                m
            )
        } else {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24 * m.k) {
                    headline(String(localized: "Your Library"), detail: String(localized: "\(String(playlists.count)) playlists"), m)
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 190 * m.k, maximum: 260 * m.k), spacing: 28 * m.k)],
                        alignment: .leading,
                        spacing: 30 * m.k
                    ) {
                        ForEach(playlists) { playlist in
                            Button { controller.present(.playlistDetail(playlist)) } label: {
                                VStack(alignment: .leading, spacing: 10 * m.k) {
                                    CachedAsyncImage(url: playlist.imageURL) { $0.resizable().aspectRatio(contentMode: .fill) }
                                        placeholder: {
                                            ZStack {
                                                Color.white.opacity(0.08)
                                                Image(systemName: "music.note.list")
                                                    .font(.system(size: 36 * m.k, weight: .light))
                                                    .foregroundStyle(.white.opacity(0.35))
                                            }
                                        }
                                        .aspectRatio(1, contentMode: .fit)
                                        .clipShape(RoundedRectangle(cornerRadius: 22 * m.k, style: .continuous))
                                        .shadow(color: .black.opacity(0.3), radius: 16 * m.k, y: 8 * m.k)
                                    Text(playlist.name)
                                        .font(.system(size: 17 * m.k, weight: .bold, design: .rounded))
                                        .foregroundStyle(.white)
                                        .lineLimit(1)
                                    Text(playlist.owner.displayName)
                                        .font(.system(size: 14 * m.k, weight: .medium, design: .rounded))
                                        .foregroundStyle(.white.opacity(0.55))
                                        .lineLimit(1)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, m.hPad)
                .padding(.vertical, 24 * m.k)
            }
        }
    }

    // MARK: - Queue

    private func queueTab(_ m: PaneMetrics) -> some View {
        let tracks = upcomingTracks
        let signedIn = isAppleMusic || musicManager.isPrivateAPIAuthenticated || musicManager.isOfficialAPIAuthenticated
        return Group {
            paneCard(m, key: "queue", padding: 28 * m.k) {
                headline(String(localized: "Up Next"), detail: tracks.isEmpty ? nil : String(localized: "\(String(tracks.count)) songs"), m)
                if !signedIn {
                    emptyState(String(localized: "Sign in to Spotify to see your queue"), icon: "person.crop.circle.badge.questionmark", m)
                } else if tracks.isEmpty {
                    emptyState(String(localized: "Nothing queued"), icon: "text.line.first.and.arrowtriangle.forward", m)
                } else {
                    ScrollView(showsIndicators: false) {
                        LazyVStack(spacing: 4 * m.k) {
                            ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                                Button { if let play = track.play { Task { await play() } } } label: {
                                    HStack(spacing: 18 * m.k) {
                                        Text("\(index + 1)")
                                            .font(.system(size: 15 * m.k, weight: .semibold, design: .rounded))
                                            .foregroundStyle(.white.opacity(0.35))
                                            .frame(width: 30 * m.k)
                                        remoteArtwork(track.imageURL, size: 58 * m.k, radius: 12 * m.k)
                                        VStack(alignment: .leading, spacing: 3 * m.k) {
                                            Text(track.title)
                                                .font(.system(size: 17 * m.k, weight: .semibold, design: .rounded))
                                                .foregroundStyle(.white)
                                                .lineLimit(1)
                                            Text(track.subtitle)
                                                .font(.system(size: 15 * m.k, weight: .medium, design: .rounded))
                                                .foregroundStyle(.white.opacity(0.55))
                                                .lineLimit(1)
                                        }
                                        Spacer(minLength: 0)
                                    }
                                    .padding(.vertical, 8 * m.k)
                                    .padding(.horizontal, 10 * m.k)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .disabled(track.play == nil)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, m.hPad)
        .padding(.vertical, 24 * m.k)
    }

    // MARK: - Devices

    private func devicesTab(_ m: PaneMetrics) -> some View {
        let api = musicManager.spotifyPrivateAPI
        let activeID = api.activePlayerDeviceID
        let connect = api.devices
            .filter { $0.deviceId != api.controllerDeviceID }
            .sorted { ($0.deviceId == activeID ? 0 : 1, $0.name) < ($1.deviceId == activeID ? 0 : 1, $1.name) }

        return ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 26 * m.k) {
                headline(String(localized: "Play On"), detail: nil, m)

                if isSpotify, !connect.isEmpty {
                    deviceSection("Spotify Connect", key: "connect", m) {
                        ForEach(connect, id: \.deviceId) { device in
                            let isActive = device.deviceId == activeID
                            deviceTile(
                                icon: deviceIcon(for: device.deviceType),
                                name: device.name,
                                detail: isActive ? String(localized: "Playing") : device.deviceType.capitalized,
                                isActive: isActive,
                                m
                            ) {
                                guard !isActive else { return }
                                Task { _ = await api.transferPlayback(to: device.deviceId) }
                            }
                        }
                    }
                } else if isSpotify, !officialDevices.isEmpty {
                    deviceSection("Spotify Connect", key: "connect", m) {
                        ForEach(officialDevices, id: \.self) { device in
                            deviceTile(
                                icon: deviceIcon(for: device.type),
                                name: device.name,
                                detail: device.isActive ? String(localized: "Playing") : device.type.capitalized,
                                isActive: device.isActive,
                                m
                            ) {
                                guard !device.isActive, let id = device.id else { return }
                                Task { _ = await musicManager.spotifyOfficialAPI.transferPlayback(to: id) }
                            }
                        }
                    }
                }

                if !musicManager.airplayDevices.isEmpty {
                    deviceSection("AirPlay", key: "airplay", m) {
                        ForEach(musicManager.airplayDevices) { device in
                            deviceTile(
                                icon: device.iconName,
                                name: device.name,
                                detail: device.isSelected ? String(localized: "Connected") : "AirPlay",
                                isActive: device.isSelected,
                                m
                            ) {
                                Task {
                                    _ = await musicManager.switchToAirPlayDevice(device)
                                    try? await Task.sleep(for: .seconds(1))
                                    await musicManager.updateAirPlayDevices()
                                }
                            }
                        }
                    }
                }

                PaneMacOutputs(m: m)
            }
            .padding(.horizontal, m.hPad)
            .padding(.vertical, 24 * m.k)
        }
        .task {
            api.bootstrapIfNeeded(policy: .onDemand)
            if musicManager.isPrivateAPIAuthenticated {
                try? await api.refreshPlayerAndDeviceState()
            } else if musicManager.isOfficialAPIAuthenticated {
                officialDevices = await musicManager.spotifyOfficialAPI.fetchDevices()
            }
            await musicManager.updateAirPlayDevices()
        }
    }

    private func deviceSection<Content: View>(_ title: String, key: String, _ m: PaneMetrics, @ViewBuilder content: () -> Content) -> some View {
        paneCard(m, key: "devices-\(key)", padding: 18 * m.k) {
            eyebrow(title, m)
            LazyVGrid(columns: PaneDeviceTile.columns(m), alignment: .leading, spacing: 10 * m.k) {
                content()
            }
        }
    }

    private func deviceTile(icon: String, name: String, detail: String, isActive: Bool, _ m: PaneMetrics, action: @escaping () -> Void) -> some View {
        PaneDeviceTile(icon: icon, name: name, detail: detail, isActive: isActive, m: m, action: action)
    }

    private func deviceIcon(for type: String) -> String {
        switch type.lowercased() {
        case "computer": "macbook.gen2"
        case "speaker": "hifispeaker.2.fill"
        case "smartphone": "iphone"
        case "tablet": "ipad"
        case "tv": "tv.fill"
        case "avr", "stb", "castvideo": "tv.inset.filled"
        case "gameconsole": "gamecontroller.fill"
        case "automobile": "car.fill"
        default: "speaker.wave.2.fill"
        }
    }

    // MARK: - Mini Player

    private func miniPlayer(_ m: PaneMetrics) -> some View {
        HStack(spacing: 20 * m.k) {
            albumArtwork(size: 58 * m.k, radius: 12 * m.k)
            VStack(alignment: .leading, spacing: 2 * m.k) {
                Text(musicManager.title ?? String(localized: "Not Playing"))
                    .font(.system(size: 17 * m.k, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(musicManager.artist ?? "")
                    .font(.system(size: 14 * m.k, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
            }
            .frame(width: 260 * m.k, alignment: .leading)

            PaneScrubber(k: m.k, style: .compact)
                .frame(maxWidth: .infinity)

            transportControls(m, style: .mini)
        }
        .padding(.horizontal, 20 * m.k)
        .padding(.vertical, 14 * m.k)
        .frame(maxWidth: 1240 * m.k)
        .background(LockScreenWidgetSurface(
            shape: RoundedRectangle(cornerRadius: 28 * m.k, style: .continuous),
            cacheKey: "pane-mini"
        ))
    }

    // MARK: - Transport

    private enum TransportStyle { case hero, compact, mini }

    private func transportControls(_ m: PaneMetrics, style: TransportStyle) -> some View {
        let playSize: CGFloat = switch style { case .hero: 72; case .compact: 56; case .mini: 46 }
        let skipSize: CGFloat = switch style { case .hero: 26; case .compact: 21; case .mini: 18 }
        let sideSize: CGFloat = switch style { case .hero: 18; case .compact: 15; case .mini: 15 }
        let spacing: CGFloat = switch style { case .hero: 26; case .compact: 16; case .mini: 14 }
        let repeatIcon = musicManager.repeatState == .track ? "repeat.1" : "repeat"

        return HStack(spacing: spacing * m.k) {
            if style != .mini {
                toggleIcon("shuffle", size: sideSize * m.k, isOn: musicManager.shuffleState) {
                    Task { await musicManager.toggleShuffle() }
                }
            }
            iconButton("backward.fill", size: skipSize * m.k) { Task { await musicManager.previousTrack() } }

            Button {
                Task { musicManager.isPlaying ? await musicManager.pause() : await musicManager.play() }
            } label: {
                Image(systemName: musicManager.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: playSize * 0.36 * m.k, weight: .bold))
                    .foregroundStyle(.white)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: playSize * m.k, height: playSize * m.k)
                    .background(LockScreenWidgetSurface(shape: Circle(), cacheKey: "pane-play-\(style)"))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)

            iconButton("forward.fill", size: skipSize * m.k) { Task { await musicManager.nextTrack() } }
            if style != .mini {
                toggleIcon(repeatIcon, size: sideSize * m.k, isOn: musicManager.repeatState != .off) {
                    Task { await musicManager.cycleRepeatMode() }
                }
            }
            if style == .hero {
                Spacer(minLength: 0)
                iconButton(musicManager.isLiked ? "heart.fill" : "heart", size: 22 * m.k, tint: musicManager.isLiked ? .pink : .white) {
                    Task { await musicManager.toggleLike() }
                }
            }
        }
    }

    private func iconButton(_ systemName: String, size: CGFloat, tint: Color = .white, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: size * 1.9, height: size * 1.9)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func toggleIcon(_ systemName: String, size: CGFloat, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size, weight: .bold))
                .foregroundStyle(isOn ? Color.black.opacity(0.85) : .white.opacity(0.7))
                .frame(width: size * 2, height: size * 2)
                .background(Circle().fill(isOn ? Color.white.opacity(0.9) : Color.clear))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }

    private func glassIconButton(_ systemName: String, size: CGFloat, key: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size * 0.34, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(LockScreenWidgetSurface(shape: Circle(), cacheKey: "pane-\(key)"))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Building Blocks

    @ViewBuilder
    private func albumArtwork(size: CGFloat, radius: CGFloat) -> some View {
        MusicArtworkImage(image: musicManager.artwork, size: size)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }

    private func remoteArtwork(_ url: URL?, size: CGFloat, radius: CGFloat) -> some View {
        CachedAsyncImage(url: url) { $0.resizable().aspectRatio(contentMode: .fill) }
            placeholder: { Color.white.opacity(0.08) }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }

    private func eyebrow(_ text: String, _ m: PaneMetrics) -> some View {
        Text(text.uppercased())
            .font(.system(size: 12 * m.k, weight: .semibold, design: .rounded))
            .tracking(1.6 * m.k)
            .foregroundStyle(.white.opacity(0.55))
            .lineLimit(1)
    }

    private func headline(_ title: String, detail: String?, _ m: PaneMetrics) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14 * m.k) {
            Text(title)
                .font(.system(size: 32 * m.k, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            if let detail {
                Text(detail)
                    .font(.system(size: 17 * m.k, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
            }
            Spacer(minLength: 0)
        }
    }

    private func sectionTitle(_ title: String, _ m: PaneMetrics) -> some View {
        Text(title)
            .font(.system(size: 22 * m.k, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
    }

    private func cardTitle(_ title: String, _ m: PaneMetrics) -> some View {
        Text(title)
            .font(.system(size: 18 * m.k, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.bottom, 2 * m.k)
    }

    private func paneCard<Content: View>(
        _ m: PaneMetrics,
        key: String,
        padding: CGFloat? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14 * m.k) {
            content()
        }
        .padding(padding ?? 26 * m.k)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(PaneCardFill(cornerRadius: 30 * m.k))
    }

    private func tileRow<Item: Identifiable, Tile: View>(
        _ title: String,
        _ m: PaneMetrics,
        items: [Item],
        @ViewBuilder tile: @escaping (Item) -> Tile
    ) -> some View {
        VStack(alignment: .leading, spacing: 16 * m.k) {
            sectionTitle(title, m)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 22 * m.k) {
                    ForEach(items) { tile($0) }
                }
            }
        }
    }

    private func tile(url: URL?, title: String, subtitle: String, _ m: PaneMetrics) -> some View {
        VStack(alignment: .leading, spacing: 8 * m.k) {
            remoteArtwork(url, size: 190 * m.k, radius: 20 * m.k)
                .shadow(color: .black.opacity(0.3), radius: 14 * m.k, y: 6 * m.k)
            Text(title)
                .font(.system(size: 16 * m.k, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
            Text(subtitle)
                .font(.system(size: 13 * m.k, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(1)
        }
        .frame(width: 190 * m.k, alignment: .leading)
    }

    private func emptyState(_ text: String, icon: String, _ m: PaneMetrics) -> some View {
        VStack(spacing: 14 * m.k) {
            Image(systemName: icon)
                .font(.system(size: 52 * m.k, weight: .light))
                .foregroundStyle(.white.opacity(0.35))
            Text(text)
                .font(.system(size: 22 * m.k, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.55))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Overlay

    @ViewBuilder private func overlayPanel(for overlay: LockScreenMusicPaneOverlay, _ m: PaneMetrics) -> some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea().onTapGesture { controller.dismissOverlay() }
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    glassIconButton("xmark", size: 38 * m.k, key: "overlay-close") { controller.dismissOverlay() }
                }
                .padding([.top, .horizontal], 20 * m.k)

                switch overlay {
                case .playlistDetail(let playlist):
                    PlaylistView(playlist: playlist, navigationStack: $dummyNavigationStack, isLockScreenMode: true)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .loginPrompt:
                    LoginPromptView(navigationStack: $dummyNavigationStack)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: min(1180 * m.k, m.size.width - m.hPad * 2), maxHeight: m.size.height * 0.8)
            .background(LockScreenWidgetSurface(shape: RoundedRectangle(cornerRadius: 36 * m.k, style: .continuous), cacheKey: "pane-sheet"))
        }
    }
}

// MARK: - Scrubber

private struct PaneScrubber: View {
    enum Style { case hero, compact }

    var musicManager: MusicManager { .shared }
    let k: CGFloat
    let style: Style
    @State private var dragProgress: Double?
    @State private var isHovering = false

    var body: some View {
        let barHeight = (style == .hero ? 9 : 6) * k * (isHovering || dragProgress != nil ? 1.6 : 1)
        let timeSize = (style == .hero ? 15 : 12) * k

        let trajectory = musicManager.playbackTrajectory

        VStack(spacing: 8 * k) {
            GeometryReader { geo in
                LayerProgressBar(
                    motion: dragProgress.map { LinearProgressMotion(progress: $0) } ?? trajectory.progressMotion,
                    colors: [.white],
                    trackColor: Color.white.opacity(0.22),
                    barHeight: barHeight,
                    catchUpDuration: dragProgress == nil ? 0.5 : 0
                )
                .frame(width: geo.size.width, height: geo.size.height)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            dragProgress = min(max(Double(value.location.x / geo.size.width), 0), 1)
                        }
                        .onEnded { value in
                            let target = min(max(Double(value.location.x / geo.size.width), 0), 1) * musicManager.totalDuration
                            dragProgress = nil
                            if target.isFinite, musicManager.totalDuration > 0 {
                                Task { await musicManager.seek(to: target) }
                            }
                        }
                )
            }
            .frame(height: 22 * k)
            .onHover { hovering in withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { isHovering = hovering } }

            TimelineView(trajectory.clockSchedule) { context in
                let duration = musicManager.totalDuration
                let elapsed = dragProgress.map { $0 * duration } ?? trajectory.elapsed(at: context.date)
                HStack {
                    Text(elapsed.asMinuteSecondClock)
                    Spacer()
                    Text("-\(max(0, duration - elapsed).asMinuteSecondClock)")
                }
                .font(.system(size: timeSize, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(.white.opacity(0.6))
            }
        }
    }
}

// MARK: - Lyrics

private struct PaneLyrics: View {
    var musicManager: MusicManager { .shared }
    let k: CGFloat
    let viewportHeight: CGFloat

    var body: some View {
        TimelineView(KaraokeFillSchedule(
            referenceDate: Date(),
            referenceElapsed: musicManager.lyricsElapsedTime(),
            windows: musicManager.isPlaying
                ? KaraokeFillSchedule.eventWindows(for: musicManager.lyrics)
                : []
        )) { context in
            let activeIndices = musicManager.activeLyricIndices(at: context.date)
                .filter { musicManager.lyrics.indices.contains($0) }
            let activeIDs = Set(activeIndices.map { musicManager.lyrics[$0].id })
            let focusID = activeIndices.first.map { musicManager.lyrics[$0].id }
            let elapsed = musicManager.lyricsElapsedTime(at: context.date)

            if musicManager.lyrics.isEmpty {
                Text("Lyrics aren't available for this song.")
                    .font(.system(size: 30 * k, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.4))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            } else {
                ScrollViewReader { proxy in
                    ScrollView(showsIndicators: false) {
                        LazyVStack(alignment: .leading, spacing: 24 * k) {
                            ForEach(musicManager.lyrics) { lyric in
                                let isActive = activeIDs.contains(lyric.id)
                                WordSyncedLyricText(
                                    lyric: lyric,
                                    elapsedTime: elapsed,
                                    isActive: isActive,
                                    highlightColor: .white,
                                    inactiveColor: .white
                                )
                                .font(.system(size: 38 * k, weight: .bold, design: .rounded))
                                .opacity(isActive ? 1 : 0.35)
                                .scaleEffect(isActive ? 1 : 0.96, anchor: .leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                                .onTapGesture { Task { await musicManager.seek(to: lyric.timestamp) } }
                                .animation(.spring(response: 0.45, dampingFraction: 0.85), value: isActive)
                                .id(lyric.id)
                            }
                        }
                        .padding(.vertical, viewportHeight * 0.3)
                    }
                    .onAppear { if let focusID { proxy.scrollTo(focusID, anchor: UnitPoint(x: 0, y: 0.38)) } }
                    .onChange(of: focusID) { _, id in
                        guard let id else { return }
                        withAnimation(.spring(response: 0.6, dampingFraction: 0.9)) {
                            proxy.scrollTo(id, anchor: UnitPoint(x: 0, y: 0.38))
                        }
                    }
                }
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .black, location: 0.16),
                            .init(color: .black, location: 0.8),
                            .init(color: .clear, location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
        }
    }
}

// MARK: - Devices

private struct PaneDeviceTile: View {
    let icon: String
    let name: String
    let detail: String
    let isActive: Bool
    let m: PaneMetrics
    let action: () -> Void

    static func columns(_ m: PaneMetrics) -> [GridItem] {
        [GridItem(.adaptive(minimum: 230 * m.k, maximum: 360 * m.k), spacing: 10 * m.k)]
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14 * m.k) {
                Image(systemName: icon)
                    .font(.system(size: 19 * m.k, weight: .medium))
                    .frame(width: 42 * m.k, height: 42 * m.k)
                    .background(Circle().fill(isActive ? Color.black.opacity(0.1) : Color.white.opacity(0.1)))
                VStack(alignment: .leading, spacing: 2 * m.k) {
                    Text(name)
                        .font(.system(size: 15 * m.k, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                    Text(detail)
                        .font(.system(size: 12 * m.k, weight: .medium, design: .rounded))
                        .opacity(0.6)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(isActive ? Color.black.opacity(0.85) : .white)
            .padding(.horizontal, 12 * m.k)
            .frame(height: 66 * m.k)
            .background(
                RoundedRectangle(cornerRadius: 18 * m.k, style: .continuous)
                    .fill(isActive ? Color.white.opacity(0.9) : Color.white.opacity(0.07))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct PaneMacOutputs: View {
    @ObservedObject private var audio = MultiAudioManager.shared
    let m: PaneMetrics

    var body: some View {
        if !audio.availableOutputDevices.isEmpty {
            VStack(alignment: .leading, spacing: 14 * m.k) {
                Text("THIS MAC")
                    .font(.system(size: 12 * m.k, weight: .semibold, design: .rounded))
                    .tracking(1.6 * m.k)
                    .foregroundStyle(.white.opacity(0.55))
                LazyVGrid(columns: PaneDeviceTile.columns(m), alignment: .leading, spacing: 10 * m.k) {
                    ForEach(audio.availableOutputDevices) { device in
                        let selected = audio.selectedOutputDeviceIDs.contains(device.id)
                        let active = selected || (audio.selectedOutputDeviceIDs.isEmpty && device.id == audio.defaultOutputDeviceID)
                        PaneDeviceTile(
                            icon: IconMapper.icon(for: device),
                            name: device.name,
                            detail: active ? String(localized: "Playing") : String(localized: "Output"),
                            isActive: active,
                            m: m
                        ) {
                            if selected { audio.selectedOutputDeviceIDs.remove(device.id) }
                            else { audio.selectedOutputDeviceIDs.insert(device.id) }
                        }
                    }
                }
            }
            .padding(18 * m.k)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PaneCardFill(cornerRadius: 30 * m.k))
        }
    }
}

private struct PaneCardFill: View {
    let cornerRadius: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        shape
            .fill(Color.white.opacity(0.08))
            .overlay(shape.strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
    }
}

private struct PaneChip: ViewModifier {
    let k: CGFloat

    func body(content: Content) -> some View {
        content
            .font(.system(size: 13 * k, weight: .semibold, design: .rounded))
            .foregroundStyle(.white.opacity(0.8))
            .padding(.horizontal, 11 * k)
            .padding(.vertical, 6 * k)
            .background(Capsule().fill(Color.white.opacity(0.1)))
    }
}

private struct PopularityMeter: View {
    let value: Int
    let k: CGFloat

    var body: some View {
        HStack(alignment: .bottom, spacing: 2 * k) {
            ForEach(0..<5, id: \.self) { bar in
                Capsule()
                    .fill(Color.white.opacity(value > bar * 20 ? 0.9 : 0.25))
                    .frame(width: 3 * k, height: (5 + CGFloat(bar) * 2.2) * k)
            }
        }
    }
}