//
//  LockScreenMusicPane.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-10

import SwiftUI
import AppKit

private struct LockScreenPaneClickPassthrough: NSViewRepresentable {
    let interactive: Bool
    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { nsView.window?.ignoresMouseEvents = !interactive }
    }
}

// MARK: - Tabs

enum LockScreenMusicTab: String, CaseIterable, Identifiable {
    case nowPlaying, artist, playlists, queue, devices, lyrics

    var id: String { rawValue }

    var title: String {
        switch self {
        case .nowPlaying: "Overview"
        case .artist: "Artist"
        case .playlists: "Playlists"
        case .queue: "Queue"
        case .devices: "Devices"
        case .lyrics: "Lyrics"
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
    func open() { withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) { isPresented = true; selectedTab = .nowPlaying; overlay = nil; isLyricsView = false } }
    func close() { withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { isPresented = false; overlay = nil } }
    func selectTab(_ tab: LockScreenMusicTab) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            selectedTab = tab
            overlay = nil
            isLyricsView = (tab == .lyrics)
        }
    }
    func present(_ destination: LockScreenMusicPaneOverlay) { withAnimation { overlay = destination } }
    func dismissOverlay() { withAnimation { overlay = nil } }
    func reset() { isPresented = false; selectedTab = .nowPlaying; overlay = nil; isLyricsView = false }
}

// MARK: - Main Pane

struct LockScreenFullScreenMusicPane: View {
    @ObservedObject private var controller = LockScreenMusicPaneController.shared
    @EnvironmentObject var musicManager: MusicManager
    @EnvironmentObject var settings: SettingsModel
    @State private var dummyNavigationStack: [NotchWidgetMode] = []
    @State private var desktopWallpaper: NSImage?
    @StateObject private var navigationManager = LockScreenNavigationManager()
    @State private var isAnimatingIn = false
    @State private var spotifyQueue: SpotifyQueue?
    @State private var appleMusicQueueTracks: [AppleMusicManager.QueueTrack] = []
    @Namespace private var tabNamespace
    private var screenSize: CGSize { NSScreen.main?.frame.size ?? CGSize(width: 1440, height: 900) }

    var body: some View {
        ZStack {
            if controller.isPresented { paneContent.transition(.opacity) }
            if let overlay = controller.overlay { overlayPanel(for: overlay).transition(.move(edge: .bottom).combined(with: .opacity)) }
        }
        .frame(width: screenSize.width, height: screenSize.height)
        .opacity(controller.isPresented ? 1 : 0)
        .allowsHitTesting(controller.isPresented)
        .background(LockScreenPaneClickPassthrough(interactive: controller.isPresented))
        .animation(.spring(response: 0.5, dampingFraction: 0.82), value: controller.isPresented)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: controller.selectedTab)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: controller.overlay)
        .onAppear { isAnimatingIn = controller.isPresented }
        .onChange(of: controller.isPresented) { _, presented in
            isAnimatingIn = false
            if presented { withAnimation(.spring(response: 0.52, dampingFraction: 0.76).delay(0.04)) { isAnimatingIn = true } }
        }
        .onChange(of: musicManager.isPlaying) { _, playing in
            if !playing && (musicManager.title?.isEmpty ?? true) { controller.close() }
        }
    }

    private var paneContent: some View {
        ZStack {
            ambientBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                    .padding(.top, 28)
                    .padding(.horizontal, 40)

                tabBar
                    .padding(.horizontal, 40)
                    .padding(.top, 14)

                Spacer(minLength: 16)

                tabContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                Spacer(minLength: 16)

                LockScreenMusicDock(navigationStack: $dummyNavigationStack, navigationManager: navigationManager)
                    .padding(.horizontal, 48)
                    .padding(.bottom, 36)
            }
            .opacity(isAnimatingIn ? 1 : 0)
            .scaleEffect(isAnimatingIn ? 1 : 0.97)
        }
        .environment(\.colorScheme, .dark)
        .onAppear {
            Task { await musicManager.setLyricsDetailOpen(controller.isLyricsView) }
            desktopWallpaper = Self.loadDesktopWallpaper()
            Task {
                await musicManager.ensureSpotifyPlayerExtrasLoaded(force: true)
                await refreshQueueData()
                await refreshPlaylistData()
            }
        }
        .onChange(of: controller.selectedTab) { _, tab in
            Task {
                await musicManager.setLyricsDetailOpen(tab == .lyrics)
                if tab == .artist || tab == .playlists {
                    await musicManager.ensureSpotifyPlayerExtrasLoaded(force: false)
                }
                if tab == .queue { await refreshQueueData() }
                if tab == .playlists { await refreshPlaylistData() }
            }
        }
        .onDisappear { Task { await musicManager.setLyricsDetailOpen(false) } }
    }

    private func refreshQueueData() async {
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
        if musicManager.lastKnownBundleID == "com.apple.Music" { return }
        if musicManager.isPrivateAPIAuthenticated, musicManager.spotifyPrivateAPI.nativePlaylists.isEmpty {
            await musicManager.spotifyPrivateAPI.fetchUserLibrary()
        }
    }

    private static func loadDesktopWallpaper() -> NSImage? {
        guard let screen = NSScreen.main ?? NSScreen.screens.first, let url = NSWorkspace.shared.desktopImageURL(for: screen) else { return nil }
        return NSImage(contentsOf: url)
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            Button(action: { controller.close() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(.white.opacity(0.12), in: Circle())
            }
            .buttonStyle(.plain)

            Spacer()

            VStack(spacing: 2) {
                Text(musicManager.title ?? "Not Playing")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(musicManager.artist ?? "")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(1)
            }

            Spacer()

            Color.clear.frame(width: 38, height: 38)
        }
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        let tabs = visibleTabs
        return HStack(spacing: 0) {
            Spacer()
            HStack(spacing: 2) {
                ForEach(tabs) { tab in
                    Button {
                        if controller.selectedTab == tab, tab == .nowPlaying { controller.close() }
                        else { controller.selectTab(tab) }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: tab.systemImage)
                                .font(.system(size: 11, weight: .semibold))
                            Text(tab.title)
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                        }
                        .padding(.horizontal, 13)
                        .padding(.vertical, 7)
                        .background(
                            controller.selectedTab == tab
                                ? AnyView(Capsule().fill(.white.opacity(0.18)))
                                : AnyView(Capsule().fill(Color.clear))
                        )
                        .foregroundStyle(controller.selectedTab == tab ? .white : .white.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(
                        Capsule()
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
            )
            Spacer()
        }
    }

    private var visibleTabs: [LockScreenMusicTab] {
        let isSpotify = musicManager.isSpotifyLiveSourceSelected || musicManager.isSpotifySourceActive
        let hasArtist = isSpotify && musicManager.spotifyPrivateAPI.nowPlayingArtist != nil
        var tabs: [LockScreenMusicTab] = [.nowPlaying]
        if hasArtist { tabs.append(.artist) }
        tabs.append(.playlists)
        tabs.append(.queue)
        tabs.append(.devices)
        tabs.append(.lyrics)
        return tabs
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var tabContent: some View {
        ZStack {
            switch controller.selectedTab {
            case .nowPlaying: nowPlayingTab
            case .artist: artistTab
            case .playlists: playlistsTab
            case .queue: queueTab
            case .devices: devicesTab
            case .lyrics: lyricsTab
            }
        }
        .transition(.opacity)
    }

    // MARK: - Overview Tab (shows everything)

    private var nowPlayingTab: some View {
        let isSpotify = musicManager.isSpotifyLiveSourceSelected || musicManager.isSpotifySourceActive
        let api = musicManager.spotifyPrivateAPI
        let artist = api.nowPlayingArtist
        let concerts = api.artistConcerts
        let relatedTracks = api.relatedTracks
        let similarAlbums = api.similarAlbums
        let nativePlaylists = musicManager.spotifyPrivateAPI.nativePlaylists
        let queue = spotifyQueue?.queue ?? []

        return ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 28) {
                VStack(spacing: 20) {
                    albumArtwork(size: 260, radius: 28)
                        .shadow(color: musicManager.accentColor.opacity(0.5), radius: 32, y: 16)

                    VStack(spacing: 6) {
                        Text(musicManager.title ?? "Not Playing")
                            .font(.system(size: 34, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)

                        Text(musicManager.artist ?? "Unknown Artist")
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.55))
                            .lineLimit(1)

                        if let album = musicManager.album, !album.isEmpty, album != musicManager.title {
                            Text(album)
                                .font(.system(size: 14, weight: .medium, design: .rounded))
                                .foregroundStyle(.white.opacity(0.3))
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: 440)

                    HStack(spacing: 8) {
                        if let popularity = musicManager.popularity ?? musicManager.fetchedSpotifyPopularity {
                            statPill(icon: "chart.bar.fill", label: "Popularity", value: "\(popularity)/100", color: musicManager.accentColor)
                        }
                        if musicManager.totalDuration > 0 {
                            let mins = Int(musicManager.totalDuration) / 60
                            let secs = Int(musicManager.totalDuration) % 60
                            statPill(icon: "clock.fill", label: "Duration", value: String(format: "%d:%02d", mins, secs), color: .cyan)
                        }
                        if isSpotify {
                            SpotifyNowPlayingExtras()
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.bottom, 8)

                HStack(alignment: .top, spacing: 24) {
                    VStack(alignment: .leading, spacing: 24) {
                        if let artist {
                            overviewCard(accent: musicManager.accentColor) {
                                VStack(alignment: .leading, spacing: 14) {
                                    HStack(spacing: 14) {
                                        if let url = artist.headerImageURL ?? artist.avatarURL {
                                            CachedAsyncImage(url: url) { $0.resizable().aspectRatio(contentMode: .fill) }
                                                placeholder: { Circle().fill(Color.white.opacity(0.06)) }
                                                .frame(width: 56, height: 56)
                                                .clipShape(Circle())
                                                .overlay(Circle().stroke(musicManager.accentColor.opacity(0.35), lineWidth: 2))
                                        }
                                        VStack(alignment: .leading, spacing: 2) {
                                            HStack(spacing: 6) {
                                                Text(artist.name)
                                                    .font(.system(size: 17, weight: .bold, design: .rounded))
                                                    .foregroundStyle(.white)
                                                if artist.isVerified {
                                                    Image(systemName: "checkmark.seal.fill")
                                                        .font(.system(size: 13))
                                                        .foregroundStyle(.cyan)
                                                }
                                            }
                                            if let listeners = artist.monthlyListeners ?? artist.followers {
                                                Text(formatLarge(listeners) + (artist.monthlyListeners != nil ? " monthly listeners" : " followers"))
                                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                                                    .foregroundStyle(.white.opacity(0.45))
                                            }
                                        }
                                    }

                                    if !artist.biography.isEmpty {
                                        Text(artist.biography)
                                            .font(.system(size: 13, weight: .regular, design: .rounded))
                                            .foregroundStyle(.white.opacity(0.55))
                                            .lineLimit(4)
                                            .lineSpacing(4)
                                    }
                                }
                            }
                        }

                        if !relatedTracks.isEmpty {
                            overviewSection(title: "Related Tracks", icon: "sparkles", accent: .orange) {
                                VStack(spacing: 6) {
                                    ForEach(relatedTracks.prefix(5)) { track in
                                        Button {
                                            Task { _ = await musicManager.play(trackUri: track.uri, contextUri: nil) }
                                        } label: {
                                            HStack(spacing: 10) {
                                                Image(systemName: "play.circle.fill")
                                                    .font(.system(size: 14))
                                                    .foregroundStyle(.white.opacity(0.7))
                                                VStack(alignment: .leading, spacing: 1) {
                                                    Text(track.name)
                                                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                                                        .foregroundStyle(.white).lineLimit(1)
                                                    if let name = track.artists.first?.name {
                                                        Text(name)
                                                            .font(.system(size: 11, weight: .medium, design: .rounded))
                                                            .foregroundStyle(.white.opacity(0.35)).lineLimit(1)
                                                    }
                                                }
                                                Spacer()
                                            }
                                            .padding(.horizontal, 12).padding(.vertical, 8)
                                            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.white.opacity(0.05)))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }

                        if !similarAlbums.isEmpty {
                            overviewSection(title: "Similar Albums", icon: "square.stack.fill", accent: .purple) {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 12) {
                                        ForEach(similarAlbums.prefix(6)) { album in
                                            VStack(alignment: .leading, spacing: 5) {
                                                if let url = album.imageURL {
                                                    CachedAsyncImage(url: url) { $0.resizable().aspectRatio(contentMode: .fill) }
                                                        placeholder: { Color.white.opacity(0.05) }
                                                        .frame(width: 110, height: 110)
                                                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                                }
                                                Text(album.name)
                                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                                    .foregroundStyle(.white).lineLimit(1)
                                                Text(album.artistName)
                                                    .font(.system(size: 10, weight: .medium, design: .rounded))
                                                    .foregroundStyle(.white.opacity(0.4)).lineLimit(1)
                                            }
                                            .frame(width: 110)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)

                    VStack(alignment: .leading, spacing: 24) {
                        overviewSection(title: "Up Next", icon: "text.line.first.and.arrowtriangle.forward", accent: .green) {
                            if queue.isEmpty && musicManager.nativeQueue.isEmpty {
                                Text("Nothing queued")
                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.35))
                                    .padding(.vertical, 8)
                            } else if !queue.isEmpty {
                                VStack(spacing: 2) {
                                    ForEach(Array(queue.prefix(5).enumerated()), id: \.offset) { index, track in
                                        HStack(spacing: 10) {
                                            Text("\(index + 1)")
                                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                                .foregroundStyle(.white.opacity(0.2))
                                                .frame(width: 18)
                                            if let url = track.imageURL {
                                                CachedAsyncImage(url: url) { $0.resizable().aspectRatio(contentMode: .fill) }
                                                    placeholder: { Color.white.opacity(0.04) }
                                                    .frame(width: 36, height: 36)
                                                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                            }
                                            VStack(alignment: .leading, spacing: 1) {
                                                Text(track.name)
                                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                                    .foregroundStyle(.white).lineLimit(1)
                                                Text(track.artists.map(\.name).joined(separator: ", "))
                                                    .font(.system(size: 11, weight: .medium, design: .rounded))
                                                    .foregroundStyle(.white.opacity(0.35)).lineLimit(1)
                                            }
                                            Spacer()
                                        }
                                        .padding(.vertical, 6)
                                    }
                                }
                            } else {
                                VStack(spacing: 2) {
                                    ForEach(Array(musicManager.nativeQueue.prefix(5).enumerated()), id: \.offset) { index, track in
                                        HStack(spacing: 10) {
                                            Text("\(index + 1)")
                                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                                .foregroundStyle(.white.opacity(0.2))
                                                .frame(width: 18)
                                            VStack(alignment: .leading, spacing: 1) {
                                                Text(track.metadata?.title ?? "Unknown")
                                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                                    .foregroundStyle(.white).lineLimit(1)
                                                Text(track.metadata?.artistName ?? "Unknown Artist")
                                                    .font(.system(size: 11, weight: .medium, design: .rounded))
                                                    .foregroundStyle(.white.opacity(0.35)).lineLimit(1)
                                            }
                                            Spacer()
                                        }
                                        .padding(.vertical, 6)
                                    }
                                }
                            }
                        }

                        if !concerts.isEmpty {
                            overviewSection(title: "Upcoming Concerts", icon: "ticket.fill", accent: .pink) {
                                VStack(spacing: 6) {
                                    ForEach(concerts.prefix(4)) { concert in
                                        VStack(alignment: .leading, spacing: 4) {
                                            HStack(spacing: 8) {
                                                Image(systemName: "ticket.fill")
                                                    .font(.system(size: 11))
                                                    .foregroundStyle(.pink)
                                                Text(concert.title)
                                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                                    .foregroundStyle(.white).lineLimit(1)
                                            }
                                            Text("\(concert.venue), \(concert.city)")
                                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                                .foregroundStyle(.white.opacity(0.35))
                                            Text(concert.startDateIsoString)
                                                .font(.system(size: 10, weight: .regular, design: .monospaced))
                                                .foregroundStyle(.white.opacity(0.25))
                                        }
                                        .padding(10)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(0.05)))
                                    }
                                }
                            }
                        }

                        if !nativePlaylists.isEmpty {
                            overviewSection(title: "Your Playlists", icon: "list.bullet.rectangle", accent: .cyan) {
                                LazyVGrid(
                                    columns: [GridItem(.adaptive(minimum: 120, maximum: 140), spacing: 10)],
                                    spacing: 10
                                ) {
                                    ForEach(nativePlaylists.prefix(6)) { playlist in
                                        Button { controller.present(.playlistDetail(playlist)) } label: {
                                            VStack(spacing: 5) {
                                                CachedAsyncImage(url: playlist.imageURL) { $0.resizable().aspectRatio(contentMode: .fill) }
                                                    placeholder: { Color.white.opacity(0.05) }
                                                    .frame(width: 120, height: 120)
                                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                                Text(playlist.name)
                                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                                    .foregroundStyle(.white).lineLimit(1)
                                            }
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 56)
            .padding(.bottom, 32)
        }
    }

    // MARK: - Overview Helpers

    private func statPill(icon: String, label: String, value: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.45))
            Text(value)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.white.opacity(0.07))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    private func overviewCard<Content: View>(accent: Color, @ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
            )
    }

    private func overviewSection<Content: View>(title: String, icon: String, accent: Color, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundStyle(accent)
                Text(title)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                )
        )
    }

    private func artistCompactCard(_ artist: SpotifyArtistProfile) -> some View {
        HStack(spacing: 16) {
            if let url = artist.headerImageURL ?? artist.avatarURL {
                CachedAsyncImage(url: url) { $0.resizable().aspectRatio(contentMode: .fill) }
                    placeholder: { Circle().fill(Color.white.opacity(0.06)) }
                    .frame(width: 52, height: 52)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(musicManager.accentColor.opacity(0.3), lineWidth: 1.5))
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(artist.name)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    if artist.isVerified {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.cyan)
                    }
                }
                if let listeners = artist.monthlyListeners ?? artist.followers {
                    Text(formatLarge(listeners) + (artist.monthlyListeners != nil ? " monthly listeners" : " followers"))
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
            Spacer()
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white.opacity(0.06)))
    }

    // MARK: - Lyrics Tab (with artwork)

    private var lyricsTab: some View {
        HStack(alignment: .center, spacing: 48) {
            VStack(alignment: .leading, spacing: 18) {
                albumArtwork(size: 220, radius: 22)
                    .shadow(color: musicManager.accentColor.opacity(0.35), radius: 24, y: 12)

                VStack(alignment: .leading, spacing: 4) {
                    Text(musicManager.title ?? "Not Playing")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    Text(musicManager.artist ?? "Unknown Artist")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.45))
                        .lineLimit(1)
                }
                .frame(width: 220)
            }
            .frame(width: 240, alignment: .leading)

            LockScreenMusicPaneLyrics()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, 56)
        .frame(maxWidth: 800)
    }

    // MARK: - Artist Tab

    private var artistTab: some View {
        let api = musicManager.spotifyPrivateAPI
        return Group {
            if let artist = api.nowPlayingArtist {
                VStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 16) {
                        artistHeader(artist)
                    }
                    .padding(.horizontal, 56)
                    .padding(.top, 4)

                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 28) {
                            if !artist.biography.isEmpty {
                                artistBiography(artist.biography)
                            }
                            if !artist.topCities.isEmpty {
                                artistCities(artist.topCities)
                            }
                            if !artist.merch.isEmpty {
                                artistMerch(artist.merch)
                            }
                            if !api.artistConcerts.isEmpty {
                                artistConcerts(api.artistConcerts)
                            }
                            if !api.similarAlbums.isEmpty {
                                similarAlbumsGrid(api.similarAlbums)
                            }
                            if !api.relatedTracks.isEmpty {
                                relatedTracksList(api.relatedTracks)
                            }
                        }
                        .padding(.horizontal, 56)
                        .padding(.bottom, 32)
                    }
                    .frame(maxWidth: 800)
                }
            } else {
                emptyState("No artist info available")
            }
        }
    }

    private func artistHeader(_ artist: SpotifyArtistProfile) -> some View {
        HStack(spacing: 22) {
            if let url = artist.headerImageURL ?? artist.avatarURL {
                CachedAsyncImage(url: url) { $0.resizable().aspectRatio(contentMode: .fill) }
                    placeholder: { Circle().fill(Color.white.opacity(0.06)) }
                    .frame(width: 100, height: 100)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(musicManager.accentColor.opacity(0.4), lineWidth: 2))
                    .shadow(color: musicManager.accentColor.opacity(0.25), radius: 16, y: 6)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(artist.name)
                        .font(.system(size: 28, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                    if artist.isVerified {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 17))
                            .foregroundStyle(.cyan)
                    }
                }
                if let listeners = artist.monthlyListeners ?? artist.followers {
                    HStack(spacing: 6) {
                        Image(systemName: "music.mic")
                            .font(.system(size: 10))
                            .foregroundStyle(musicManager.accentColor)
                        Text(formatLarge(listeners) + (artist.monthlyListeners != nil ? " monthly listeners" : " followers"))
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
            }
        }
    }

    private func artistBiography(_ bio: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Biography", icon: "text.book.closed.fill")
            Text(bio)
                .font(.system(size: 14, weight: .regular, design: .rounded))
                .foregroundStyle(.white.opacity(0.65))
                .lineLimit(6)
                .lineSpacing(4)
        }
    }

    private func artistCities(_ cities: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Top Cities", icon: "mappin.and.ellipse")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(cities, id: \.self) { city in
                        Label(city, systemImage: "location.fill")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(Capsule().fill(.white.opacity(0.1)))
                            .foregroundStyle(.white.opacity(0.75))
                    }
                }
            }
        }
    }

    private func artistMerch(_ merch: [SpotifyArtistMerch]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Merchandise", icon: "tag.fill")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(merch) { item in
                        VStack(alignment: .leading, spacing: 8) {
                            if let url = item.imageURL {
                                CachedAsyncImage(url: url) { $0.resizable().aspectRatio(contentMode: .fill) }
                                    placeholder: { Color.white.opacity(0.05) }
                                    .frame(width: 140, height: 140)
                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name)
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.white)
                                    .lineLimit(2)
                                if let price = item.price {
                                    Text(price)
                                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                                        .foregroundStyle(.white.opacity(0.5))
                                }
                            }
                            .frame(width: 140)
                        }
                    }
                }
            }
        }
    }

    private func artistConcerts(_ concerts: [SpotifyArtistConcert]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Upcoming Concerts", icon: "ticket.fill")
            VStack(spacing: 6) {
                ForEach(concerts.prefix(6)) { concert in
                    HStack(spacing: 12) {
                        Image(systemName: "ticket.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(.pink)
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(.pink.opacity(0.12)))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(concert.title)
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            Text("\(concert.venue), \(concert.city)")
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(.white.opacity(0.4))
                            Text(concert.startDateIsoString)
                                .font(.system(size: 11, weight: .regular, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.3))
                        }
                        Spacer()
                    }
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(0.04)))
                }
            }
        }
    }

    private func similarAlbumsGrid(_ albums: [SpotifySimilarAlbum]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Similar Albums", icon: "square.stack.fill")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(albums.prefix(8)) { album in
                        VStack(alignment: .leading, spacing: 6) {
                            if let url = album.imageURL {
                                CachedAsyncImage(url: url) { $0.resizable().aspectRatio(contentMode: .fill) }
                                    placeholder: { Color.white.opacity(0.05) }
                                    .frame(width: 120, height: 120)
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            VStack(alignment: .leading, spacing: 1) {
                                Text(album.name)
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.white).lineLimit(1)
                                Text(album.artistName)
                                    .font(.system(size: 11, weight: .medium, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.45)).lineLimit(1)
                                if let year = album.year {
                                    Text("\(year)")
                                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                                        .foregroundStyle(.white.opacity(0.3))
                                }
                            }
                            .frame(width: 120)
                        }
                    }
                }
            }
        }
    }

    private func relatedTracksList(_ tracks: [SpotifyRecommendedTrack]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Related Tracks", icon: "sparkles")
            VStack(spacing: 4) {
                ForEach(tracks.prefix(8)) { track in
                    Button {
                        Task { _ = await musicManager.play(trackUri: track.uri, contextUri: nil) }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(musicManager.accentColor.opacity(0.7))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(track.name)
                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.white).lineLimit(1)
                                if let artistName = track.artists.first?.name {
                                    Text(artistName)
                                        .font(.system(size: 12, weight: .medium, design: .rounded))
                                        .foregroundStyle(.white.opacity(0.4)).lineLimit(1)
                                }
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.white.opacity(0.05)))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Playlists Tab

    private var playlistsTab: some View {
        let isSpotify = musicManager.isSpotifyLiveSourceSelected || musicManager.isSpotifySourceActive
        let isAppleMusic = musicManager.lastKnownBundleID == "com.apple.Music"
        let playlists: [SpotifyPlaylist] = {
            if isAppleMusic { return musicManager.appleMusic.fetchPlaylists() }
            let native = musicManager.spotifyPrivateAPI.nativePlaylists
            return native.isEmpty ? [] : native
        }()

        return Group {
            if playlists.isEmpty {
                emptyState("No playlists found")
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 160, maximum: 180), spacing: 14)],
                        spacing: 14
                    ) {
                        ForEach(playlists) { playlist in
                            Button { controller.present(.playlistDetail(playlist)) } label: {
                                VStack(spacing: 8) {
                                    CachedAsyncImage(url: playlist.imageURL) { $0.resizable().aspectRatio(contentMode: .fill) }
                                        placeholder: {
                                            ZStack {
                                                Color.white.opacity(0.05)
                                                Image(systemName: "music.note.list")
                                                    .font(.system(size: 28, weight: .light))
                                                    .foregroundStyle(.white.opacity(0.2))
                                            }
                                        }
                                        .aspectRatio(1, contentMode: .fill)
                                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(playlist.name)
                                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                                            .foregroundStyle(.white)
                                            .lineLimit(2)
                                        Text(playlist.owner.displayName)
                                            .font(.system(size: 11, weight: .medium, design: .rounded))
                                            .foregroundStyle(.white.opacity(0.4))
                                            .lineLimit(1)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 2)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 56)
                    .padding(.bottom, 32)
                }
            }
        }
    }

    // MARK: - Queue Tab

    private var queueTab: some View {
        let isAppleMusic = musicManager.lastKnownBundleID == "com.apple.Music"
        return Group {
            if isAppleMusic {
                appleMusicQueueContent
            } else {
                if musicManager.isPrivateAPIAuthenticated || musicManager.isOfficialAPIAuthenticated {
                    spotifyQueueContent
                } else {
                    emptyState("Sign in to Spotify to see your queue")
                }
            }
        }
    }

    private var spotifyQueueContent: some View {
        let nativeQueue = musicManager.nativeQueue
        let officialQueue = spotifyQueue?.queue ?? []
        let hasNative = !nativeQueue.isEmpty
        let hasOfficial = !officialQueue.isEmpty

        return Group {
            if hasNative {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        ForEach(Array(nativeQueue.enumerated()), id: \.offset) { index, track in
                            trackRow(
                                index: index + 1,
                                title: track.metadata?.title ?? "Unknown Track",
                                subtitle: track.metadata?.artistName ?? "Unknown Artist",
                                imageURL: track.metadata?.imageURL
                            )
                        }
                    }
                    .padding(.bottom, 32)
                }
            } else if hasOfficial {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        ForEach(Array(officialQueue.enumerated()), id: \.offset) { index, track in
                            trackRow(
                                index: index + 1,
                                title: track.name,
                                subtitle: track.artists.map(\.name).joined(separator: ", "),
                                imageURL: track.imageURL
                            )
                        }
                    }
                    .padding(.bottom, 32)
                }
            } else {
                emptyState("Queue is empty")
            }
        }
    }

    private var appleMusicQueueContent: some View {
        return Group {
            if appleMusicQueueTracks.isEmpty {
                emptyState("Queue is empty")
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        ForEach(Array(appleMusicQueueTracks.enumerated()), id: \.offset) { index, track in
                            trackRow(
                                index: index + 1,
                                title: track.title,
                                subtitle: track.artist,
                                imageURL: nil
                            )
                        }
                    }
                    .padding(.bottom, 32)
                }
            }
        }
    }

    private func trackRow(index: Int, title: String, subtitle: String, imageURL: URL?) -> some View {
        HStack(spacing: 12) {
            Text("\(index)")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.25))
                .frame(width: 24)

            if let url = imageURL {
                CachedAsyncImage(url: url) { $0.resizable().aspectRatio(contentMode: .fill) }
                    placeholder: { Color.white.opacity(0.04) }
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.4))
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, 56)
        .padding(.vertical, 8)
        .id(index)
    }

    // MARK: - Devices Tab

    private var devicesTab: some View {
        let isSpotify = musicManager.isSpotifyLiveSourceSelected || musicManager.isSpotifySourceActive
        let isAppleMusic = musicManager.lastKnownBundleID == "com.apple.Music"
        let devices: [SpotifyNativeDevice] = isSpotify ? musicManager.spotifyPrivateAPI.devices : []
        let activeID = musicManager.spotifyPrivateAPI.activePlayerDeviceID
        let isLoggedIn = musicManager.isPrivateAPIAuthenticated || musicManager.isOfficialAPIAuthenticated

        return Group {
            if isAppleMusic || (!isLoggedIn && !isSpotify) || devices.isEmpty {
                DevicesView(
                    navigationStack: $dummyNavigationStack,
                    audioHubSection: .constant(.system),
                    isLockScreenMode: true,
                    preferSystemTab: true
                )
                .padding(.horizontal, 40)
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 8) {
                        sectionHeader("Spotify Connect", icon: "hifispeaker.2.fill")
                            .padding(.horizontal, 56)

                        ForEach(Array(devices.sorted { d1, d2 in
                            (d1.deviceId == activeID) == (d2.deviceId == activeID) ? d1.deviceId < d2.deviceId : d1.deviceId == activeID
                        }), id: \.deviceId) { device in
                            let isActive = device.deviceId == activeID
                            HStack(spacing: 12) {
                                Image(systemName: deviceIcon(for: device.deviceType))
                                    .font(.system(size: 16))
                                    .foregroundStyle(isActive ? .green : .white.opacity(0.4))
                                    .frame(width: 36)

                                VStack(alignment: .leading, spacing: 1) {
                                    Text(device.name)
                                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                                        .foregroundStyle(isActive ? .green : .white)
                                        .lineLimit(1)
                                    Text(device.deviceType.capitalized)
                                        .font(.system(size: 11, weight: .medium, design: .rounded))
                                        .foregroundStyle(.white.opacity(0.35))
                                }
                                Spacer()
                                if isActive {
                                    Text("Active")
                                        .font(.system(size: 10, weight: .bold, design: .rounded))
                                        .foregroundStyle(.green)
                                        .padding(.horizontal, 8).padding(.vertical, 3)
                                        .background(Capsule().fill(.green.opacity(0.15)))
                                } else {
                                    Button("Transfer") {
                                        Task { _ = await musicManager.spotifyPrivateAPI.transferPlayback(to: device.deviceId) }
                                    }
                                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                                    .padding(.horizontal, 10).padding(.vertical, 4)
                                    .background(Capsule().fill(.white.opacity(0.1)))
                                    .foregroundStyle(.white.opacity(0.75))
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 56)
                            .padding(.vertical, 7)
                        }
                    }
                    .padding(.bottom, 32)
                }
            }
        }
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

    // MARK: - Shared Views

    @ViewBuilder
    private func albumArtwork(size: CGFloat, radius: CGFloat) -> some View {
        Group {
            if let cover = musicManager.artwork ?? musicManager.appIcon {
                Image(nsImage: cover)
                    .resizable().aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    Color.white.opacity(0.06)
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.28, weight: .light))
                        .foregroundStyle(.white.opacity(0.3))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }

    private func sectionHeader(_ title: String, icon: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(musicManager.accentColor)
            Text(title)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
    }

    private func emptyState(_ text: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "music.note")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.white.opacity(0.15))
            Text(text)
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.3))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func formatLarge(_ value: Int) -> String {
        if value >= 1_000_000 { return String(format: "%.1fM", Double(value) / 1_000_000) }
        if value >= 1_000 { return String(format: "%.1fK", Double(value) / 1_000) }
        return "\(value)"
    }

    // MARK: - Overlay

    @ViewBuilder private func overlayPanel(for overlay: LockScreenMusicPaneOverlay) -> some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea().onTapGesture { controller.dismissOverlay() }
            VStack(spacing: 0) {
                HStack {
                    Button(action: { controller.dismissOverlay() }) {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(Color.white.opacity(0.14), in: Circle())
                    }
                    .buttonStyle(.plain)
                    Text(overlayTitle(for: overlay))
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                    Spacer()
                }
                .padding(20)

                switch overlay {
                case .playlistDetail(let playlist):
                    PlaylistView(playlist: playlist, navigationStack: $dummyNavigationStack, isLockScreenMode: true)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .loginPrompt:
                    LoginPromptView(navigationStack: $dummyNavigationStack)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: 700, maxHeight: min(screenSize.height * 0.75, 660))
            .background(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .stroke(Color.white.opacity(0.15), lineWidth: 1)
                    )
            )
            .padding(.horizontal, 40)
            .padding(.bottom, 44)
        }
    }

    private func overlayTitle(for overlay: LockScreenMusicPaneOverlay) -> String {
        switch overlay {
        case .playlistDetail(let p): p.name
        case .loginPrompt: "Connect Spotify"
        }
    }

    // MARK: - Background

    private var ambientBackground: some View {
        GeometryReader { geo in
            ZStack {
                (desktopWallpaper.map { AnyView(Image(nsImage: $0).resizable().aspectRatio(contentMode: .fill)) }
                    ?? AnyView(musicManager.accentColor))
                    .frame(width: geo.size.width, height: geo.size.height)
                    .blur(radius: 64, opaque: true)
                    .clipped()
                if let image = musicManager.artwork ?? musicManager.appIcon {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .blur(radius: 48, opaque: true)
                        .saturation(1.35)
                        .opacity(0.45)
                }
                RadialGradient(
                    colors: [musicManager.leftGradientColor.opacity(0.72), musicManager.accentColor.opacity(0.42), musicManager.rightGradientColor.opacity(0.18), Color.black.opacity(0.55)],
                    center: .topLeading,
                    startRadius: 0,
                    endRadius: max(geo.size.width, geo.size.height)
                )
                LinearGradient(colors: [.black.opacity(0.08), .black.opacity(0.42)], startPoint: .top, endPoint: .bottom)
            }
        }
    }
}

// MARK: - Dock

private struct LockScreenMusicDock: View {
    @Binding var navigationStack: [NotchWidgetMode]
    @ObservedObject var navigationManager: LockScreenNavigationManager
    @EnvironmentObject var settings: SettingsModel
    @EnvironmentObject var musicManager: MusicManager
    var body: some View {
        MusicPlayerView(navigationStack: $navigationStack, isLockScreenMode: true, showArtworkSection: false)
            .environmentObject(navigationManager)
            .padding(.horizontal, 20).padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(musicManager.accentColor.opacity(0.06))
                            .overlay(
                                RoundedRectangle(cornerRadius: 24, style: .continuous)
                                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
                            )
                    )
            )
            .shadow(color: .black.opacity(0.25), radius: 20, y: 10)
            .frame(maxWidth: 600)
    }
}

// MARK: - Lyrics View

private struct LockScreenMusicPaneLyrics: View {
    @EnvironmentObject var musicManager: MusicManager
    var body: some View {
        TimelineView(.periodic(from: .now, by: musicManager.isPlaying ? 0.2 : 1.0)) { _ in
            if musicManager.lyrics.isEmpty {
                Text("Lyrics aren't available.")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.3))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 24) {
                        ForEach(musicManager.lyrics) { lyric in
                            Text(lyric.text)
                                .font(.system(
                                    size: lyric.id == musicManager.currentLyric?.id ? 36 : 26,
                                    weight: .bold,
                                    design: .rounded
                                ))
                                .foregroundStyle(.white)
                                .opacity(lyric.id == musicManager.currentLyric?.id ? 1 : 0.28)
                        }
                    }
                }
                .mask(
                    LinearGradient(colors: [.clear, .black, .black, .clear], startPoint: .top, endPoint: .bottom)
                )
            }
        }
    }
}