//
//  LyricsViews.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-21

import SwiftUI
import AppKit
import Combine

// MARK: - Consolidated from LyricsView.swift

struct LyricLineView: View {
    let lyric: LyricLine
    let isCurrent: Bool
    let accentColor: Color

    var body: some View {
        VStack(alignment: .center, spacing: 6) {
            Text(lyric.text)
                .font(.system(size: 26, weight: .bold))
                .multilineTextAlignment(.center)
                .foregroundColor(isCurrent ? accentColor : .primary)
                .shadow(radius: 5)

            if let translated = lyric.translatedText, !translated.isEmpty {
                Text(translated)
                    .font(.system(size: 18, weight: .medium))
                    .multilineTextAlignment(.center)
                    .foregroundColor(isCurrent ? accentColor : .secondary)
                    .opacity(isCurrent ? 0.8 : 0.6)
            }
        }
        .scaleEffect(isCurrent ? 1.0 : 0.90)
        .opacity(isCurrent ? 1.0 : 0.5)
        .animation(.spring(response: 0.6, dampingFraction: 0.7), value: isCurrent)
    }
}

struct LyricsView: View {
    @EnvironmentObject var musicManager: MusicManager

    private var lyrics: [LyricLine] { musicManager.lyrics }
    private var accentColor: Color { musicManager.accentColor }

    private let lineSpacing: CGFloat = 70.0

    var body: some View {
        TimelineView(.periodic(from: .now, by: musicManager.isPlaying ? 0.2 : 1.0)) { context in
            let currentIndex = musicManager.lyricIndex(at: context.date)
            let currentLyricID = currentIndex.flatMap { lyrics.indices.contains($0) ? lyrics[$0].id : nil }
            let elapsed = musicManager.elapsedTime(at: context.date)

            GeometryReader { geometry in
                let computedOffset = calculateScrollOffset(
                    fullViewHeight: geometry.size.height,
                    currentLyricID: currentLyricID
                )

                ZStack(alignment: .topLeading) {
                    Group {
                        if lyrics.isEmpty {
                            emptyLyricsView
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            VStack(spacing: 0) {
                                ForEach(lyrics) { lyric in
                                    LyricLineView(
                                        lyric: lyric,
                                        isCurrent: lyric.id == currentLyricID,
                                        accentColor: accentColor
                                    )
                                    .frame(height: lineSpacing)
                                }
                            }
                            .frame(width: geometry.size.width)
                            .offset(y: computedOffset)
                            .animation(.spring(response: 0.8, dampingFraction: 0.8), value: currentLyricID)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .mask {
                        let viewHeight = geometry.size.height

                        if viewHeight > 0 {
                            let topFadeLength: CGFloat = 10
                            let bottomFadeLength: CGFloat = 18
                            let topFadePercentage = topFadeLength / viewHeight
                            let bottomFadePercentage = bottomFadeLength / viewHeight

                            let solidStartLocation = min(topFadePercentage, 0.5)
                            let solidEndLocation = max(1.0 - bottomFadePercentage, 0.5)

                            LinearGradient(
                                gradient: Gradient(stops: [
                                    .init(color: .clear, location: 0.0),
                                    .init(color: .black, location: solidStartLocation),
                                    .init(color: .black, location: solidEndLocation),
                                    .init(color: .clear, location: 1.0)
                                ]),
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            Color.black
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }

                    trackHeaderView(elapsed: elapsed)
                        .padding(.leading, 5)
                }
            }
        }
        .frame(width: 550, height: 250)
        .onAppear {
            Task { await musicManager.setLyricsDetailOpen(true) }
        }
        .onDisappear {
            Task { await musicManager.setLyricsDetailOpen(false) }
        }
    }

    private func calculateScrollOffset(fullViewHeight: CGFloat, currentLyricID: UUID?) -> CGFloat {
        guard let currentIndex = lyrics.firstIndex(where: { $0.id == currentLyricID }) else {
            let totalContentHeight = CGFloat(lyrics.count) * lineSpacing
            return (fullViewHeight - totalContentHeight) / 2
        }

        let targetOffset = (fullViewHeight / 2) - (lineSpacing / 2) - (CGFloat(currentIndex) * lineSpacing)
        return targetOffset
    }

    private var emptyLyricsView: some View {
        Text("No lyrics available.")
            .font(.headline)
            .foregroundColor(.secondary)
    }

    private func trackHeaderView(elapsed: TimeInterval) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .center, spacing: 10) {
                Group {
                    if let artwork = musicManager.artwork {
                        Image(nsImage: artwork)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        Image(systemName: "music.note")
                            .resizable()
                            .scaledToFit()
                            .padding(8)
                            .foregroundStyle(.white.opacity(0.85))
                            .background(.white.opacity(0.12))
                    }
                }
                .frame(width: 25, height: 26)

                VStack(alignment: .leading, spacing: 0.5) {
                    Text(displayTitle)
                        .font(.system(size: 9, weight: .semibold))

                    if let album = musicManager.album, !album.isEmpty {
                        Text(album)
                            .font(.system(size: 8, weight: .medium))
                            .foregroundStyle(.secondary)
                    }

                    if let artist = musicManager.artist, !artist.isEmpty {
                        Text(artist)
                            .font(.system(size: 8, weight: .regular))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Text("\(elapsed.asMinuteSecondClock) / \(musicManager.totalDuration.asMinuteSecondClock)")
                .font(.system(size: 8, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)

            Button(action: openLyricsWindow) {
                HStack(spacing: 4) {
                    Image(systemName: "macwindow")
                    Text("Open in Window")
                }
                .font(.system(size: 8, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
    }

    private var displayTitle: String {
        if let title = musicManager.title, !title.isEmpty {
            return title
        }
        return "Not Playing"
    }

    private func openLyricsWindow() {
        (NSApp.delegate as? AppDelegate)?.openLyricsWindow()
    }
}

// MARK: - Consolidated from LyricsDetachedWindowView.swift

// MARK: - Window Accessor Helper
struct WindowAccessor: NSViewRepresentable {
    var onChange: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                onChange(window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

struct LyricsDetachedWindowView: View {
    @EnvironmentObject var musicManager: MusicManager
    @EnvironmentObject var settings: SettingsModel
    @State private var hostingWindow: NSWindow? = nil

    var body: some View {
        ZStack {
            // MARK: - Apple TV Ambient Background (Micro-Blur optimized)
            GeometryReader { geo in
                ZStack {
                    if let image = musicManager.artwork ?? musicManager.appIcon {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: geo.size.width / 10, height: geo.size.height / 10)
                            .blur(radius: 12, opaque: true)
                            .saturation(1.2)
                            .scaleEffect(10.5)
                            .animation(.easeInOut(duration: 1.5), value: image)
                    } else {
                        musicManager.accentColor
                            .opacity(0.4)
                            .blur(radius: 100)
                    }

                    Color.black.opacity(0.65)

                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .opacity(0.5)
                }
            }
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // MARK: - Top Window Controls (Invisible Drag Area)
                HStack(spacing: 14) {
                    HStack(spacing: 8) {
                        Circle().fill(Color(nsColor: .systemRed)).frame(width: 12, height: 12)
                            .onTapGesture { hostingWindow?.performClose(nil) }
                        Circle().fill(Color(nsColor: .systemYellow)).frame(width: 12, height: 12)
                            .onTapGesture { hostingWindow?.miniaturize(nil) }
                        Circle().fill(Color(nsColor: .systemGreen)).frame(width: 12, height: 12)
                            .onTapGesture { hostingWindow?.zoom(nil) }
                    }
                    Spacer()
                }
                .padding(.top, 16)
                .padding(.leading, 20)
                .frame(height: 30)
                .background(Color.clear)

                // MARK: - Middle Content (Art + Lyrics)
                HStack(alignment: .center, spacing: 60) {
                    LyricsDetachedLeftPane()
                        .frame(width: 320)

                    LyricsDetachedRightPane()
                        .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 60)
                .padding(.top, 20)
                .padding(.bottom, 40)

                // MARK: - Bottom Player Controls (Scrubber & Buttons)
                LyricsDetachedBottomBar()
                    .padding(.horizontal, 60)
                    .padding(.bottom, 30)
            }
        }
        .frame(minWidth: 1100, idealWidth: 1280, minHeight: 650, idealHeight: 760)
        .environment(\.colorScheme, .dark)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
        )
        .background(
            WindowAccessor { window in
                self.hostingWindow = window
                window.titleVisibility = .hidden
                window.titlebarAppearsTransparent = true
                window.styleMask.insert(.fullSizeContentView)
                window.isMovableByWindowBackground = true

                window.standardWindowButton(.closeButton)?.isHidden = true
                window.standardWindowButton(.miniaturizeButton)?.isHidden = true
                window.standardWindowButton(.zoomButton)?.isHidden = true
            }
        )
        .onAppear {
            Task { await musicManager.setDetachedLyricsOpen(true) }
        }
        .onDisappear {
            Task { await musicManager.setDetachedLyricsOpen(false) }
        }
    }
}

// MARK: - Left Pane (Artwork & Text)
private struct LyricsDetachedLeftPane: View {
    @EnvironmentObject var musicManager: MusicManager

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {

            Group {
                if let image = musicManager.artwork ?? musicManager.appIcon {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    ZStack {
                        Color.white.opacity(0.05)
                        Image(systemName: "music.note")
                            .font(.system(size: 80))
                            .foregroundStyle(.white.opacity(0.2))
                    }
                }
            }
            .frame(width: 320, height: 320)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(color: .black.opacity(0.5), radius: 30, y: 15)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5)
            )
            .scaleEffect(musicManager.isPlaying ? 1.0 : 0.95)
            .animation(.spring(response: 0.6, dampingFraction: 0.7), value: musicManager.isPlaying)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Image(systemName: "music.note.tv.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.6))

                    Text(displayTitle)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }

                Text(displayArtist)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
            }
            .padding(.leading, 4)
        }
    }

    private var displayTitle: String {
        if let title = musicManager.title, !title.isEmpty { return title }
        return "Not Playing"
    }

    private var displayArtist: String {
        if let artist = musicManager.artist, !artist.isEmpty { return artist }
        return "Unknown Artist"
    }
}

// MARK: - Right Pane (Lyrics)
private struct LyricsDetachedRightPane: View {
    @EnvironmentObject var musicManager: MusicManager

    private var lyrics: [LyricLine] { musicManager.lyrics }

    var body: some View {
        TimelineView(.periodic(from: .now, by: musicManager.isPlaying ? 0.2 : 1.0)) { context in
            let currentIndex = musicManager.lyricIndex(at: context.date)
            let currentLyricID = currentIndex.flatMap { lyrics.indices.contains($0) ? lyrics[$0].id : nil }

            Group {
                if lyrics.isEmpty {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Lyrics aren't available.")
                            .font(.system(size: 36, weight: .bold))
                            .foregroundColor(.white.opacity(0.4))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView(showsIndicators: false) {
                            LazyVStack(alignment: .leading, spacing: 32) {
                                Spacer().frame(height: 120)

                                ForEach(lyrics) { lyric in
                                    let isCurrent = lyric.id == currentLyricID

                                    LyricLineView(
                                        lyric: lyric,
                                        isCurrent: isCurrent,
                                        accentColor: .white
                                    )
                                    .id(lyric.id)
                                    .multilineTextAlignment(.leading)
                                    .font(.system(
                                        size: isCurrent ? 44 : 36,
                                        weight: .bold
                                    ))
                                    .foregroundStyle(.white)
                                    .scaleEffect(isCurrent ? 1.0 : 0.95, anchor: .leading)
                                    .opacity(isCurrent ? 1.0 : 0.35)
                                    .animation(
                                        .spring(response: 0.45, dampingFraction: 0.8, blendDuration: 0.1),
                                        value: isCurrent
                                    )
                                }

                                Spacer().frame(height: 200)
                            }
                        }
                        .mask(
                            LinearGradient(
                                gradient: Gradient(stops: [
                                    .init(color: .clear, location: 0.0),
                                    .init(color: .black, location: 0.2),
                                    .init(color: .black, location: 0.8),
                                    .init(color: .clear, location: 1.0)
                                ]),
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .onAppear { scrollToCurrentLyric(using: proxy, id: currentLyricID, animated: false) }
                        .onChange(of: currentLyricID) { _, newID in
                            scrollToCurrentLyric(using: proxy, id: newID, animated: true)
                        }
                        .onChange(of: lyrics.count) { _, _ in
                            scrollToCurrentLyric(using: proxy, id: currentLyricID, animated: false)
                        }
                    }
                }
            }
        }
    }

    private func scrollToCurrentLyric(using proxy: ScrollViewProxy, id: UUID?, animated: Bool) {
        guard let id else { return }
        if animated {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                proxy.scrollTo(id, anchor: .center)
            }
        } else {
            proxy.scrollTo(id, anchor: .center)
        }
    }
}

// MARK: - Bottom Pane (Scrubber & Playback)
private struct LyricsDetachedBottomBar: View {
    @EnvironmentObject var musicManager: MusicManager
    @EnvironmentObject var settings: SettingsModel
    @State private var currentProgress: Double = 0.0
    @State private var displayedElapsedTime: TimeInterval = 0
    @State private var holdFeedbackAction: MusicLongPressAction?
    @State private var holdFeedbackIcon: String?
    @State private var holdFeedbackColor: Color = .white
    @State private var holdFeedbackRestoreTask: Task<Void, Never>?
    @State private var holdFeedbackButtonID: String?
    @State private var holdActionInFlight = false

    var body: some View {
        VStack(spacing: 20) {

            VStack(spacing: 8) {
                InteractiveProgressBar(
                    value: $currentProgress,
                    gradient: Gradient(colors: [.white, .white.opacity(0.8)]),
                    onSeek: { newProgress in
                        let seekTime = newProgress * musicManager.totalDuration
                        if seekTime.isFinite && musicManager.totalDuration > 0 {
                            Task { await musicManager.seek(to: seekTime) }
                        }
                    }
                )
                .frame(height: 4)
                .background(Color.white.opacity(0.2))
                .clipShape(Capsule())

                HStack {
                    Text(displayedElapsedTime.asMinuteSecondClock)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.6))

                    Spacer()

                    Text("-" + (max(0, musicManager.totalDuration - displayedElapsedTime)).asMinuteSecondClock)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }

            HStack(spacing: 32) {
                SeekButton(
                    systemName: "backward.fill",
                    onTap: { Task { await musicManager.previousTrack() } },
                    onSeek: { isForward in Task { await musicManager.seek(by: isForward ? 5.0 : -5.0) } },
                    onLongPressAction: skipHoldClosure(for: .previous),
                    holdAction: skipHoldAction(for: .previous),
                    onHoldBegan: { action in beginHoldFeedback(action: action, buttonID: "previous") },
                    onHoldEnded: endHoldFeedback,
                    displayedSystemName: holdFeedbackButtonID == "previous" ? holdFeedbackIcon : nil
                )
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(holdFeedbackButtonID == "previous" ? holdFeedbackColor : .white.opacity(0.8))
                .help(MusicLongPressUI.skipHelp(primary: "Previous", target: .previous, settings: settings.settings))

                LongPressControlButton(
                    onTap: {
                        Task {
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
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(holdFeedbackButtonID == "playPause" ? holdFeedbackColor : .white)
                        .frame(width: 44, height: 44)
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.plain)
                .scaleEffect(musicManager.isPlaying ? 1.0 : 0.95)
                .animation(.easeInOut(duration: 0.15), value: holdFeedbackIcon)
                .help(MusicLongPressUI.accessoryHelp(primary: "Play / Pause", target: .playPause, settings: settings.settings))

                SeekButton(
                    systemName: "forward.fill",
                    onTap: { Task { await musicManager.nextTrack() } },
                    onSeek: { isForward in Task { await musicManager.seek(by: isForward ? 5.0 : -5.0) } },
                    onLongPressAction: skipHoldClosure(for: .next),
                    holdAction: skipHoldAction(for: .next),
                    onHoldBegan: { action in beginHoldFeedback(action: action, buttonID: "next") },
                    onHoldEnded: endHoldFeedback,
                    displayedSystemName: holdFeedbackButtonID == "next" ? holdFeedbackIcon : nil
                )
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(holdFeedbackButtonID == "next" ? holdFeedbackColor : .white.opacity(0.8))
                .help(MusicLongPressUI.skipHelp(primary: "Next", target: .next, settings: settings.settings))
            }
        }
        .onAppear {
            currentProgress = musicManager.playbackProgress
            displayedElapsedTime = musicManager.currentElapsedTime
        }
        .onReceive(musicManager.playbackTimePublisher) { payload in
            displayedElapsedTime = payload.elapsed
            currentProgress = payload.progress
        }
    }

    private func accessoryHoldHandler(for target: MusicLongPressTarget) -> (() -> Void)? {
        guard let action = settings.settings.resolvedAccessoryHoldAction(for: target) else { return nil }
        return {
            Task { @MainActor in
                guard !holdActionInFlight else { return }
                holdActionInFlight = true
                defer { holdActionInFlight = false }
                await musicManager.performLongPressAction(action, navigation: .notifications)
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
                await musicManager.performLongPressAction(action, navigation: .notifications)
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
            holdFeedbackColor = action.feedbackColor(musicManager: musicManager) == .secondary ? .white.opacity(0.7) : action.feedbackColor(musicManager: musicManager)
        }
    }

    private func refreshHoldFeedbackIcon() {
        guard let action = holdFeedbackAction else { return }
        withAnimation(.easeInOut(duration: 0.15)) {
            holdFeedbackIcon = action.feedbackSystemImage(musicManager: musicManager)
            holdFeedbackColor = action.feedbackColor(musicManager: musicManager) == .secondary ? .white.opacity(0.7) : action.feedbackColor(musicManager: musicManager)
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

}