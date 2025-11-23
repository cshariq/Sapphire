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

struct QueueAndPlaylistsView: View {
    @Binding var navigationStack: [NotchWidgetMode]
    @EnvironmentObject var musicManager: MusicManager

    @State private var selection: Int
    @State private var officialQueue: SpotifyQueue?
    @State private var playlists: [SpotifyPlaylist] = []

    @State private var showSpotifyNotOpenAlert = false
    @State private var queueRefreshTimer: Timer?
    
    // MARK: - Animation State
    @Namespace private var namespace

    var isLockScreenMode: Bool = false

    private let lastSelectedPaneKey = "lastSelectedMusicPane"
    private var isAppleMusic: Bool { musicManager.lastKnownBundleID == "com.apple.Music" }
    private var isLoggedIn: Bool { musicManager.isPrivateAPIAuthenticated || musicManager.isOfficialAPIAuthenticated }

    private var animationTriggerValue: String {
        let nowPlayingId = musicManager.isPrivateAPIAuthenticated ? musicManager.nowPlayingTrack?.uri : officialQueue?.currentlyPlaying?.uri
        let nativeQueueIds = musicManager.nativeQueue.map(\.uid).joined(separator: ",")
        let officialQueueIds = officialQueue?.queue.map(\.uri).joined(separator: ",") ?? ""

        return "\(nowPlayingId ?? "none")-\(nativeQueueIds)-\(officialQueueIds)"
    }

    init(navigationStack: Binding<[NotchWidgetMode]>, isLockScreenMode: Bool = false) {
        self._navigationStack = navigationStack
        self._selection = State(initialValue: UserDefaults.standard.integer(forKey: lastSelectedPaneKey))
        self.isLockScreenMode = isLockScreenMode
    }

    var body: some View {
        VStack(spacing: 15) {
            if !isLoggedIn && !isAppleMusic {
                LoginPromptView(navigationStack: $navigationStack)
            } else {
                HStack(spacing: 16) {
                    if let user = musicManager.spotifyOfficialAPI.userProfile { Text("Welcome, \(user.displayName)").font(.caption.bold()).foregroundColor(.secondary)
                    } else if let nativeUser = musicManager.spotifyPrivateAPI.userProfile { Text("Welcome, \(nativeUser.profile.username)").font(.caption.bold()).foregroundColor(.secondary) }

                    Spacer()

                    if !isAppleMusic {
                        // MARK: - Animated Tab Bar
                        HStack(spacing: 0) {
                            TabButton(title: "Queue", systemImage: "list.bullet.rectangle", isSelected: selection == 0) {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { selection = 0 }
                            }
                            TabButton(title: "Playlists", systemImage: "music.note.list", isSelected: selection == 1) {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { selection = 1 }
                            }
                        }
                        .padding(4)
                        .background(Color.black.opacity(0.2))
                        .clipShape(Capsule())
                    }

                    if musicManager.isOfficialAPIAuthenticated { Button("Log out") { Task { await musicManager.spotifyOfficialAPI.logout() } }.buttonStyle(.plain).font(.caption).foregroundColor(.secondary) }
                }

                // MARK: - Content View with Better Transitions
                ZStack(alignment: .top) {
                    if selection == 0 && !isAppleMusic {
                        queueView
                            .transition(slideTransition(edge: .leading))
                    } else {
                        playlistsView
                            .transition(slideTransition(edge: .trailing))
                    }
                }
                // Using a smooth spring for view switching
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: selection)
                // Using standard animation for data updates inside the view
                .animation(.easeInOut(duration: 0.5), value: animationTriggerValue)
            }
        }
        .padding([.top, .horizontal])
        .frame(width: 800, height: 350)
        .task { await fetchData() }
        .onAppear(perform: startQueueRefreshTimer)
        .onDisappear(perform: stopQueueRefreshTimer)
        .onChange(of: selection) { _, newValue in
            UserDefaults.standard.set(newValue, forKey: lastSelectedPaneKey)
        }
    }

    // MARK: - Custom Transitions
    private func slideTransition(edge: Edge) -> AnyTransition {
        // Creates a "depth" effect where the leaving view scales down slightly and fades,
        // while the entering view slides in.
        let oppositeEdge: Edge = (edge == .leading) ? .trailing : .leading
        
        return .asymmetric(
            insertion: .move(edge: edge).combined(with: .opacity),
            removal: .move(edge: oppositeEdge).combined(with: .scale(scale: 0.95)).combined(with: .opacity)
        )
    }

    private func refreshData() {
        Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            await fetchData()
        }
    }

    private func fetchData() async {
        if isAppleMusic {
            self.playlists = musicManager.appleMusic.fetchPlaylists()
            self.selection = 1
        } else {
            if musicManager.isPrivateAPIAuthenticated {
                await musicManager.spotifyPrivateAPI.fetchUserLibrary()
                try? await musicManager.spotifyPrivateAPI.refreshPlayerAndDeviceState()
            } else {
                self.officialQueue = await musicManager.spotifyOfficialAPI.fetchQueue()
                self.playlists = await musicManager.spotifyOfficialAPI.fetchPlaylists()
            }
        }
    }

    private func startQueueRefreshTimer() {
        guard !isAppleMusic else { return }

        stopQueueRefreshTimer()
        queueRefreshTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { _ in
            Task {
                print("[QueueAndPlaylistsView] Refreshing queue data...")
                await fetchData()
            }
        }
    }

    private func stopQueueRefreshTimer() {
        queueRefreshTimer?.invalidate()
        queueRefreshTimer = nil
    }

    @ViewBuilder
    private var queueView: some View {
        if musicManager.isPrivateAPIAuthenticated {
            nativeQueueView
        } else {
            officialQueueView
        }
    }

    private var nativeQueueView: some View {
        HStack(alignment: .top, spacing: 20) {
            if let nowPlaying = musicManager.nowPlayingTrack {
                VStack(alignment: .leading, spacing: 8) {
                    ActiveDeviceView().padding(.bottom, 5).padding(.leading, -4)

                    CachedAsyncImage(url: nowPlaying.metadata?.imageURL) { $0.resizable().aspectRatio(contentMode: .fit) }
                        placeholder: { ZStack { Color.secondary.opacity(0.3); Image(systemName: "music.note") } }
                        .frame(width: 80, height: 80)
                        .cornerRadius(8).shadow(color: .black.opacity(0.4), radius: 6, y: 3)

                    VStack(alignment: .leading, spacing: 0) {
                        Marquee {
                            Text(nowPlaying.metadata?.title ?? "Unknown Track")
                                .font(.headline.bold())
                                .lineLimit(1)
                        }

                        Marquee {
                            Text(nowPlaying.metadata?.artistName ?? "Unknown Artist")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }

                    HStack(spacing: 8) {
                        if let playCountString = musicManager.playCount, let playCountInt = Int(playCountString.replacingOccurrences(of: "K", with: "000").replacingOccurrences(of: "M", with: "000000")) {
                            PlayCountIndicator(playCount: playCountInt)
                        } else if let popularity = musicManager.popularity {
                            PopularityIndicator(popularity: popularity)
                        } else if let fetchedPopularity = musicManager.fetchedSpotifyPopularity {
                            PopularityIndicator(popularity: fetchedPopularity)
                        }
                    }

                    Spacer(minLength: 0)
                    ActionButtonsView(onAction: refreshData)
                }
                .frame(width: 150)
                .padding(.bottom, 10)
                .id(nowPlaying.uri)
                .transition(.opacity)

                VStack(alignment: .leading, spacing: 0) {
                    SectionHeader(title: "Next Up").padding(.bottom, 5)

                    if !musicManager.nativeQueue.isEmpty {
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 8) {
                                ForEach(musicManager.nativeQueue, id: \.uid) { track in
                                    NativeQueueTrackRow(track: track, onPlay: handlePlaybackResult)
                                }
                            }
                            .padding(.bottom, 30)
                        }
                        .mask(LinearGradient(gradient: Gradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.95), .init(color: .clear, location: 1.0)]), startPoint: .top, endPoint: .bottom))
                    } else { CustomUnavailableView(title: "Queue is Empty", systemImage: "music.note.list") }
                }
            } else { CustomUnavailableView(title: "Nothing Playing", systemImage: "speaker.slash.fill", description: "Start playing music in Spotify to view your queue.") }
        }
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
                        if let playCountString = musicManager.playCount, let playCountInt = Int(playCountString.replacingOccurrences(of: "K", with: "000").replacingOccurrences(of: "M", with: "000000")) {
                            PlayCountIndicator(playCount: playCountInt)
                        } else if let popularity = musicManager.popularity {
                            PopularityIndicator(popularity: popularity)
                        } else if let fetchedPopularity = musicManager.fetchedSpotifyPopularity {
                            PopularityIndicator(popularity: fetchedPopularity)
                        }
                    }

                    Spacer(minLength: 0)
                    ActionButtonsView(onAction: refreshData)
                }
                .frame(width: 150)
                .padding(.bottom, 10)
                .id(nowPlaying.uri)
                .transition(.opacity)

                VStack(alignment: .leading, spacing: 0) {
                    SectionHeader(title: "Next Up").padding(.bottom, 5)
                    if !queue.queue.isEmpty {
                        ScrollView {
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

    private var playlistsView: some View {
        ScrollView {
            VStack(spacing: 10) {
                let currentPlaylists = musicManager.isPrivateAPIAuthenticated ? musicManager.spotifyPrivateAPI.nativePlaylists : playlists
                if !currentPlaylists.isEmpty {
                    ForEach(currentPlaylists) { playlist in
                        let isPlaying = playlist.uri == musicManager.spotifyPrivateAPI.currentContextURI
                        FullPlaylistRow(playlist: playlist, navigationStack: $navigationStack, isPlaying: isPlaying, isLockScreenMode: isLockScreenMode)
                    }
                } else { CustomUnavailableView(title: "No Playlists Found", systemImage: "music.mic") }
            }
            .padding(.horizontal)
            .padding(.bottom, 30)
        }
        .mask(LinearGradient(gradient: Gradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.9), .init(color: .clear, location: 1.0)]), startPoint: .top, endPoint: .bottom))
    }

    private func handlePlaybackResult(_ result: PlaybackResult) {
        if case .requiresSpotifyAppOpen = result { showSpotifyNotOpenAlert = true }
        refreshData()
    }

}

// MARK: - Subviews

struct ActionButtonsView: View {
    @EnvironmentObject var musicManager: MusicManager
    let onAction: () -> Void

    private func performAction(_ action: @escaping () -> Void) {
        action()
        onAction()
    }

    var body: some View {
        VStack(spacing: 15) {
            HStack(spacing: 30) {
                Button(action: { performAction(musicManager.previousTrack) }) {
                    Image(systemName: "backward.fill")
                }
                Button(action: { performAction(musicManager.isPlaying ? musicManager.pause : musicManager.play) }) {
                    Image(systemName: musicManager.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 20))
                }
                Button(action: { performAction(musicManager.nextTrack) }) {
                    Image(systemName: "forward.fill")
                }
                Spacer()
            }
            .font(.system(size: 16))

            HStack(spacing: 28) {
                Button(action: { performAction(musicManager.toggleLike) }) { Image(systemName: musicManager.isLiked ? "heart.fill" : "heart") }
                    .foregroundColor(musicManager.isLiked ? .pink : .primary)

                Button(action: { performAction(musicManager.toggleShuffle) }) { Image(systemName: "shuffle") }
                    .foregroundColor(musicManager.shuffleState ? .green : .primary)

                Button(action: { performAction(musicManager.cycleRepeatMode) }) { Image(systemName: musicManager.repeatState == .track ? "repeat.1" : "repeat") }
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
        Button(action: action) {
            HStack { Image(systemName: systemImage); Text(title) }
                .font(.system(size: 10, weight: .semibold))
                .padding(.horizontal, 12).padding(.vertical, 5)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain).background(isSelected ? Color.accentColor : .clear)
        .foregroundColor(isSelected ? .white : .primary).clipShape(Capsule())
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
    }
}

struct SectionHeader: View {
    let title: String
    var body: some View {
        Text(title.uppercased()).font(.caption.bold()).foregroundColor(.secondary).padding(.top, 5)
    }
}

struct NativeQueueTrackRow: View {
    let track: PlayerState.Track
    var onPlay: (PlaybackResult) -> Void
    @State private var isHovered = false
    @EnvironmentObject var musicManager: MusicManager
    var body: some View {
        HStack(spacing: 12) {
            CachedAsyncImage(url: track.metadata?.imageURL) { $0.resizable() } placeholder: { ZStack { Color.secondary.opacity(0.3); Image(systemName: "music.note") } }
                .frame(width: 36, height: 36).cornerRadius(6)
                .overlay(ZStack { if isHovered { Color.black.opacity(0.5); Image(systemName: "play.fill").font(.title3).foregroundColor(.white) }}.cornerRadius(6))

            VStack(alignment: .leading) {
                Text(track.metadata?.title ?? "Unknown Track").fontWeight(.medium).lineLimit(1)
                Text(track.metadata?.artistName ?? "Unknown Artist").font(.caption).foregroundColor(.secondary).lineLimit(1)
            }
            Spacer()
        }
        .padding(.vertical, 6).padding(.horizontal, 10)
        .background(Color.white.opacity(isHovered ? 0.15 : 0.1)).cornerRadius(10)
        .onHover { hovering in self.isHovered = hovering }
        .onTapGesture { Task { onPlay(await musicManager.play(trackUri: track.uri, contextUri: track.metadata?.contextUri, trackUid: track.uid, trackIndex: nil)) }}
        .animation(.easeInOut(duration: 0.15), value: isHovered)

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
    }

    private func iconName(for type: String) -> String {
        switch type.lowercased() {
        case "computer": return "desktopcomputer"
        case "speaker": return "hifispeaker.fill"
        case "smartphone": return "iphone"
        case "avr", "stb", "tv", "castvideo": return "appletv.fill"
        case "castaudio": return "hifispeaker.2.fill"
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
                .foregroundColor(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.black.opacity(0.2))
                .clipShape(Capsule())
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
