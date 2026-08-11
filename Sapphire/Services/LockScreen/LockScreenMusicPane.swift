//
//  LockScreenMusicPane.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-10

import SwiftUI
import AppKit

enum LockScreenMusicPaneOverlay: Identifiable, Equatable {
    case queue
    case devices
    case loginPrompt

    var id: String {
        switch self {
        case .queue: "queue"
        case .devices: "devices"
        case .loginPrompt: "login"
        }
    }
}

@MainActor
final class LockScreenMusicPaneController: ObservableObject {
    static let shared = LockScreenMusicPaneController()

    @Published var isPresented = false
    @Published var showLyrics = false
    @Published var overlay: LockScreenMusicPaneOverlay?

    private init() {}

    func open() {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) {
            isPresented = true
            showLyrics = false
            overlay = nil
        }
    }

    func close() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            isPresented = false
            showLyrics = false
            overlay = nil
        }
    }

    func toggleLyrics() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            showLyrics.toggle()
            overlay = nil
        }
    }

    func present(_ destination: LockScreenMusicPaneOverlay) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            overlay = destination
            showLyrics = false
        }
    }

    func dismissOverlay() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            overlay = nil
        }
    }

    func reset() {
        isPresented = false
        showLyrics = false
        overlay = nil
    }
}

struct LockScreenFullScreenMusicPane: View {
    @ObservedObject private var controller = LockScreenMusicPaneController.shared
    @EnvironmentObject var musicManager: MusicManager
    @EnvironmentObject var settings: SettingsModel

    @State private var dummyNavigationStack: [NotchWidgetMode] = []
    @State private var desktopWallpaper: NSImage?
    @StateObject private var navigationManager = LockScreenNavigationManager()

    @State private var isAnimatingIn = false

    private var screenSize: CGSize {
        NSScreen.main?.frame.size ?? CGSize(width: 1440, height: 900)
    }

    var body: some View {
        ZStack {
            if controller.isPresented {
                paneContent
                    .transition(.opacity)
            }

            if let overlay = controller.overlay {
                overlayPanel(for: overlay)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(width: screenSize.width, height: screenSize.height)
        .opacity(controller.isPresented ? 1 : 0)
        .allowsHitTesting(controller.isPresented)
        .animation(.spring(response: 0.5, dampingFraction: 0.82), value: controller.isPresented)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: controller.showLyrics)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: controller.overlay)
        .onChange(of: controller.isPresented) { _, presented in
            if presented {
                isAnimatingIn = false
                withAnimation(.spring(response: 0.52, dampingFraction: 0.76).delay(0.04)) {
                    isAnimatingIn = true
                }
            } else {
                isAnimatingIn = false
            }
        }
        .onChange(of: musicManager.isPlaying) { _, playing in
            if !playing && (musicManager.title?.isEmpty ?? true) {
                controller.close()
            }
        }
    }

    private var paneContent: some View {
        ZStack {
            ambientBackground
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                    .padding(.top, 28)
                    .padding(.horizontal, 28)
                    .opacity(isAnimatingIn ? 1.0 : 0.0)
                    .offset(y: isAnimatingIn ? 0 : -12)
                    .animation(.spring(response: 0.44, dampingFraction: 0.84).delay(0.06), value: isAnimatingIn)

                Spacer(minLength: 12)

                Group {
                    if controller.showLyrics {
                        lyricsLayout
                            .padding(.horizontal, 48)
                    } else {
                        playerLayout
                    }
                }
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: controller.showLyrics)
                .opacity(isAnimatingIn ? 1.0 : 0.0)
                .scaleEffect(isAnimatingIn ? 1.0 : 0.98)
                .animation(.spring(response: 0.5, dampingFraction: 0.82).delay(0.08), value: isAnimatingIn)

                Spacer(minLength: 12)

                LockScreenPaddedBackground {
                    MusicPlayerView(
                        navigationStack: $dummyNavigationStack,
                        isLockScreenMode: true,
                    )
                    .environmentObject(navigationManager)
                }
                .padding(.horizontal, 48)
                .padding(.bottom, 40)
                .opacity(isAnimatingIn ? 1.0 : 0.0)
                .offset(y: isAnimatingIn ? 0 : 22)
                .animation(.spring(response: 0.48, dampingFraction: 0.82).delay(0.18), value: isAnimatingIn)
            }
        }
        .environment(\.colorScheme, .dark)
        .onAppear {
            Task { await musicManager.setLyricsDetailOpen(controller.showLyrics) }
            desktopWallpaper = Self.loadDesktopWallpaper()
        }
        .onChange(of: controller.showLyrics) { _, showing in
            Task { await musicManager.setLyricsDetailOpen(showing) }
        }
        .onDisappear {
            Task { await musicManager.setLyricsDetailOpen(false) }
        }
    }

    private static func loadDesktopWallpaper() -> NSImage? {
        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let screen, let url = NSWorkspace.shared.desktopImageURL(for: screen) else { return nil }
        return NSImage(contentsOf: url)
    }

    @ViewBuilder
    private func overlayPanel(for overlay: LockScreenMusicPaneOverlay) -> some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture { controller.dismissOverlay() }

            VStack(spacing: 0) {
                HStack {
                    Button(action: { controller.dismissOverlay() }) {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(Color.white.opacity(0.16), in: Circle())
                    }
                    .buttonStyle(.plain)

                    Text(overlayTitle(for: overlay))
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)

                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 12)

                Group {
                    switch overlay {
                    case .queue:
                        QueueAndPlaylistsView(navigationStack: $dummyNavigationStack, isLockScreenMode: true)
                    case .devices:
                        QueueAndPlaylistsView(
                            navigationStack: $dummyNavigationStack,
                            isLockScreenMode: true,
                        )
                    case .loginPrompt:
                        LoginPromptView(navigationStack: $dummyNavigationStack)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: 680, maxHeight: min(screenSize.height * 0.72, 640))
            .background {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(Color.white.opacity(0.18), lineWidth: 1)
                    }
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 48)
        }
    }

    private func overlayTitle(for overlay: LockScreenMusicPaneOverlay) -> String {
        switch overlay {
        case .queue: "Queue & Playlists"
        case .devices: "Devices"
        case .loginPrompt: "Connect Spotify"
        }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Button(action: { controller.close() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Color.white.opacity(0.16), in: Circle())
            }
            .buttonStyle(.plain)
            .help("Close")

            Spacer()

            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(context.date, style: .time)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.75))
                    .contentTransition(.numericText())
                    .animation(.easeInOut(duration: 0.2), value: context.date)
            }

            Spacer()

            Button(action: { controller.toggleLyrics() }) {
                Image(systemName: controller.showLyrics ? "music.note" : "text.quote")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Color.white.opacity(controller.showLyrics ? 0.24 : 0.16), in: Circle())
            }
            .buttonStyle(.plain)
            .help(controller.showLyrics ? "Show player" : "Show lyrics")
        }
    }

    private var playerLayout: some View {
        VStack(spacing: 28) {
            Group {
                if let cover = musicManager.artwork ?? musicManager.appIcon {
                    Image(nsImage: cover)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    ZStack {
                        Color.white.opacity(0.08)
                        Image(systemName: "music.note")
                            .font(.system(size: 72, weight: .light))
                            .foregroundStyle(.white.opacity(0.35))
                    }
                }
            }
            .frame(width: 320, height: 320)
            .clipShape(RoundedRectangle(cornerRadius: isAnimatingIn ? 28 : 14, style: .continuous))
            .shadow(color: musicManager.accentColor.opacity(0.45), radius: 36, y: 18)
            .scaleEffect(isAnimatingIn ? 1.0 : 0.18)
            .opacity(isAnimatingIn ? 1.0 : 0.55)
            .animation(.spring(response: 0.52, dampingFraction: 0.76), value: isAnimatingIn)

            VStack(spacing: 8) {
                Text(musicManager.title ?? "Not Playing")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)

                Text(musicManager.artist ?? "Unknown Artist")
                    .font(.system(size: 20, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)

                if let album = musicManager.album, !album.isEmpty, album != musicManager.title {
                    Text(album)
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.35))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: 560)
            .opacity(isAnimatingIn ? 1.0 : 0.0)
            .offset(y: isAnimatingIn ? 0 : 18)
            .animation(.spring(response: 0.48, dampingFraction: 0.82).delay(0.1), value: isAnimatingIn)
        }
    }

    private var lyricsLayout: some View {
        HStack(alignment: .center, spacing: 56) {
            VStack(alignment: .leading, spacing: 20) {
                Group {
                    if let cover = musicManager.artwork ?? musicManager.appIcon {
                        Image(nsImage: cover)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        Color.white.opacity(0.08)
                    }
                }
                .frame(width: 300, height: 300)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .shadow(color: musicManager.accentColor.opacity(0.4), radius: 28, y: 14)

                VStack(alignment: .leading, spacing: 6) {
                    Text(musicManager.title ?? "Not Playing")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    Text(musicManager.artist ?? "Unknown Artist")
                        .font(.system(size: 17, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1)
                }
            }
            .frame(width: 320, alignment: .leading)

            LockScreenMusicPaneLyrics()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxHeight: 560)
    }

    private var ambientBackground: some View {
        GeometryReader { geo in
            let cornerRadius = max(geo.size.width, geo.size.height) * 0.95

            ZStack {
                Group {
                    if let wallpaper = desktopWallpaper {
                        Image(nsImage: wallpaper)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else if let image = musicManager.artwork ?? musicManager.appIcon {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        musicManager.accentColor
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .blur(radius: 64, opaque: true)
                .clipped()

                if let image = musicManager.artwork ?? musicManager.appIcon {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .blur(radius: 48, opaque: true)
                        .saturation(1.35)
                        .opacity(0.45)
                        .animation(.easeInOut(duration: 0.8), value: musicManager.currentTrackArtworkToken)
                }

                RadialGradient(
                    colors: [
                        musicManager.leftGradientColor.opacity(0.72),
                        musicManager.accentColor.opacity(0.42),
                        musicManager.rightGradientColor.opacity(0.18),
                        Color.black.opacity(0.55)
                    ],
                    center: .topLeading,
                    startRadius: 0,
                    endRadius: cornerRadius
                )
                .animation(.easeInOut(duration: 0.8), value: musicManager.currentTrackArtworkToken)

                LinearGradient(
                    colors: [
                        Color.black.opacity(0.08),
                        Color.black.opacity(0.42)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
    }
}

private struct LockScreenMusicPaneLyrics: View {
    @EnvironmentObject var musicManager: MusicManager

    private var lyrics: [LyricLine] { musicManager.lyrics }

    var body: some View {
        TimelineView(.periodic(from: .now, by: musicManager.isPlaying ? 0.2 : 1.0)) { context in
            let currentIndex = musicManager.lyrics.firstIndex(where: { $0.id == musicManager.currentLyric?.id })
            let currentLyricID = currentIndex.flatMap { lyrics.indices.contains($0) ? lyrics[$0].id : nil }

            Group {
                if lyrics.isEmpty {
                    Text("Lyrics aren't available.")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.35))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView(showsIndicators: false) {
                            LazyVStack(alignment: .leading, spacing: 28) {
                                Spacer().frame(height: 80)
                                ForEach(lyrics) { lyric in
                                    let isCurrent = lyric.id == currentLyricID
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(lyric.text)
                                            .font(.system(size: isCurrent ? 40 : 30, weight: .bold, design: .rounded))
                                            .foregroundStyle(.white)
                                            .opacity(isCurrent ? 1 : 0.32)

                                        if let translated = lyric.translatedText, !translated.isEmpty {
                                            Text(translated)
                                                .font(.system(size: isCurrent ? 20 : 16, weight: .medium, design: .rounded))
                                                .foregroundStyle(.white.opacity(isCurrent ? 0.7 : 0.28))
                                        }
                                    }
                                    .id(lyric.id)
                                }
                                Spacer().frame(height: 160)
                            }
                        }
                        .mask(
                            LinearGradient(
                                gradient: Gradient(stops: [
                                    .init(color: .clear, location: 0),
                                    .init(color: .black, location: 0.15),
                                    .init(color: .black, location: 0.85),
                                    .init(color: .clear, location: 1)
                                ]),
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .onAppear { scroll(proxy, to: currentLyricID, animated: false) }
                        .onChange(of: currentLyricID) { _, newID in
                            scroll(proxy, to: newID, animated: true)
                        }
                    }
                }
            }
        }
    }

    private func scroll(_ proxy: ScrollViewProxy, to id: UUID?, animated: Bool) {
        guard let id else { return }
        if animated {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                proxy.scrollTo(id, anchor: .center)
            }
        } else {
            proxy.scrollTo(id, anchor: .center)
        }
    }
}