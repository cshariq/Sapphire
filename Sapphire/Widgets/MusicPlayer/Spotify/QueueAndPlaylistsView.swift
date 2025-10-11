//
//  QueueAndPlaylistsView.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-06-26.
//
//
//
//
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

    @State private var isLoading = true
    @State private var showSpotifyNotOpenAlert = false

    @State private var queueRefreshTimer: Timer?

    private let lastSelectedPaneKey = "lastSelectedMusicPane"
    private var isAppleMusic: Bool { musicManager.lastKnownBundleID == "com.apple.Music" }
    private var isLoggedIn: Bool { musicManager.isPrivateAPIAuthenticated || musicManager.isOfficialAPIAuthenticated }

    init(navigationStack: Binding<[NotchWidgetMode]>) {
        self._navigationStack = navigationStack
        self._selection = State(initialValue: UserDefaults.standard.integer(forKey: lastSelectedPaneKey))
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
                        HStack(spacing: 10) {
                            TabButton(title: "Queue", systemImage: "list.bullet.rectangle", isSelected: selection == 0) { selection = 0 }
                            TabButton(title: "Playlists", systemImage: "music.note.list", isSelected: selection == 1) { selection = 1 }
                        }.padding(6).background(Color.black.opacity(0.2)).clipShape(Capsule())
                    }

                    if musicManager.isOfficialAPIAuthenticated { Button("Log out") { Task { await musicManager.spotifyOfficialAPI.logout() } }.buttonStyle(.plain).font(.caption).foregroundColor(.secondary) }
                }

                if isLoading { ProgressView().frame(maxHeight: .infinity)
                } else {
                    ZStack {
                        if selection == 0 && !isAppleMusic {
                            queueView.transition(.asymmetric(insertion: .move(edge: .leading).combined(with: .opacity), removal: .move(edge: .trailing).combined(with: .opacity)))
                        } else {
                            playlistsView.transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity)))
                        }
                    }.animation(.easeInOut(duration: 0.2), value: selection)
                }
            }
        }
        .padding()
        .frame(width: 800, height: 350)
        .task { await fetchData() }
        .onAppear(perform: startQueueRefreshTimer)
        .onDisappear(perform: stopQueueRefreshTimer)
        .onChange(of: selection) { _, newValue in
            UserDefaults.standard.set(newValue, forKey: lastSelectedPaneKey)
        }

    }

    private func fetchData() async {
        isLoading = true
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
        self.isLoading = false
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

                    VStack(alignment: .leading, spacing: 2) {
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

                    HStack(spacing: 12) {
                        if let playCount = musicManager.playCount { NowPlayingInfoView(systemName: "play.circle.fill", text: playCount) }
                        if let popularity = musicManager.popularity { NowPlayingInfoView(systemName: "flame.fill", text: "\(popularity)%") }
                    }

                    Spacer(minLength: 0)
                    ActionButtonsView()
                }
                .frame(width: 150)
                .id(nowPlaying.uri)

                VStack(alignment: .leading, spacing: 0) {
                    SectionHeader(title: "Next Up").padding(.bottom, 5)

                    if !musicManager.nativeQueue.isEmpty {
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 8) {
                                ForEach(musicManager.nativeQueue, id: \.uid) { track in
                                    NativeQueueTrackRow(track: track, onPlay: handlePlaybackResult)
                                }
                            }
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

                    VStack(alignment: .leading, spacing: 2) {
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

                    HStack(spacing: 12) {
                        if let playCount = musicManager.playCount { NowPlayingInfoView(systemName: "play.circle.fill", text: playCount) }
                        if let popularity = musicManager.popularity { NowPlayingInfoView(systemName: "flame.fill", text: "\(popularity)%") }
                    }

                    Spacer(minLength: 0)
                    ActionButtonsView()
                }
                .frame(width: 150)
                .id(nowPlaying.uri)

                VStack(alignment: .leading, spacing: 0) {
                    SectionHeader(title: "Next Up").padding(.bottom, 5)
                    if !queue.queue.isEmpty {
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 8) {
                                ForEach(queue.queue) { track in QueueTrackRow(track: track, onPlay: handlePlaybackResult) }
                            }
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
                        FullPlaylistRow(playlist: playlist, navigationStack: $navigationStack, isPlaying: isPlaying)
                    }
                } else { CustomUnavailableView(title: "No Playlists Found", systemImage: "music.mic") }
            }.padding(.horizontal)
        }
        .mask(LinearGradient(gradient: Gradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.9), .init(color: .clear, location: 1.0)]), startPoint: .top, endPoint: .bottom))
    }

    private func handlePlaybackResult(_ result: PlaybackResult) {
        if case .requiresSpotifyAppOpen = result { showSpotifyNotOpenAlert = true }
    }

}

// MARK: - Subviews

struct ActionButtonsView: View {
    @EnvironmentObject var musicManager: MusicManager
    var body: some View {
        HStack {
            HStack(spacing: 24) {
                Button(action: musicManager.toggleLike) { Image(systemName: musicManager.isLiked ? "heart.fill" : "heart") }
                    .foregroundColor(musicManager.isLiked ? .pink : .primary)

                Button(action: { musicManager.toggleShuffle() }) { Image(systemName: "shuffle") }
                    .foregroundColor(musicManager.shuffleState ? .green : .primary)

                Button(action: musicManager.cycleRepeatMode) { Image(systemName: musicManager.repeatState == .track ? "repeat.1" : "repeat") }
                    .foregroundColor(musicManager.repeatState != .off ? .green : .primary)
            }
            .font(.system(size: 16))
            .buttonStyle(.plain)

            Spacer()
        }
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
        .padding(.vertical, 6).padding(.horizontal, 10)
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
        .padding(10).background(Color.white.opacity(isHovered ? 0.15 : 0.1)).cornerRadius(12)
        .onHover { hovering in self.isHovered = hovering }
        .onTapGesture { navigationStack.append(.musicPlaylistDetail(playlist)) }
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

    @State private var isAnimating = false
    @State private var contentWidth: CGFloat = 0

    var body: some View {
        GeometryReader { geometry in
            let containerWidth = geometry.size.width
            let isOverflowing = contentWidth > containerWidth

            HStack(spacing: isOverflowing ? 20 : 0) {
                content
                if isOverflowing {
                    content
                }
            }
            .background(
                GeometryReader { contentGeometry in
                    Color.clear.onAppear {
                        contentWidth = contentGeometry.size.width
                        if isOverflowing {
                            isAnimating = true
                        }
                    }
                }
            )
            .offset(x: isAnimating ? -contentWidth - 20 : 0)
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(
                isAnimating ? .linear(duration: contentWidth / 30).repeatForever(autoreverses: false) : .default,
                value: isAnimating
            )
        }
        .clipped()
    }
}