import SwiftUI
import AppKit

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
    @State private var hostingWindow: NSWindow? = nil

    var body: some View {
        ZStack {
            // MARK: - Apple TV Ambient Background (Micro-Blur optimized)
            GeometryReader { geo in
                ZStack {
                    // 1. Base Ambient Artwork
                    if let image = musicManager.artwork ?? musicManager.appIcon {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            // Downsample mathematically to bypass heavy GPU processing
                            .frame(width: geo.size.width / 10, height: geo.size.height / 10)
                            .blur(radius: 12, opaque: true) // Low-cost blur on small frame
                            .saturation(1.2) // Enhance colors
                            .scaleEffect(10.5) // Scale back to fill original geometry
                            .animation(.easeInOut(duration: 1.5), value: image)
                    } else {
                        musicManager.accentColor
                            .opacity(0.4)
                            .blur(radius: 100)
                    }
                    
                    // 2. Heavy Dark TV Overlay
                    Color.black.opacity(0.65)
                    
                    // 3. Ultra-thin glass texture
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
                    // LEFT: Album Art & Info
                    LyricsDetachedLeftPane()
                        .frame(width: 320)
                    
                    // RIGHT: Massive Lyrics
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
        .environment(\.colorScheme, .dark) // Force dark mode contrast
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
        )
        // Background accessor dynamically configures the host NSWindow details
        .background(
            WindowAccessor { window in
                self.hostingWindow = window
                window.titleVisibility = .hidden
                window.titlebarAppearsTransparent = true
                window.styleMask.insert(.fullSizeContentView)
                window.isMovableByWindowBackground = true // Draggable from background canvas
                
                // Hide system standard window control buttons
                window.standardWindowButton(.closeButton)?.isHidden = true
                window.standardWindowButton(.miniaturizeButton)?.isHidden = true
                window.standardWindowButton(.zoomButton)?.isHidden = true
            }
        )
        .onAppear {
            musicManager.setDetachedLyricsOpen(true)
        }
        .onDisappear {
            musicManager.setDetachedLyricsOpen(false)
        }
    }
}

// MARK: - Left Pane (Artwork & Text)
private struct LyricsDetachedLeftPane: View {
    @EnvironmentObject var musicManager: MusicManager

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            
            // Artwork
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

            // Track Info
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
    private var currentLyricID: UUID? { musicManager.currentLyric?.id }

    var body: some View {
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
                            Spacer().frame(height: 120) // Padding for smooth scroll centering
                            
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
                                    size: isCurrent ? 44 : 36, // Apple TV massive fonts
                                    weight: .bold
                                ))
                                .foregroundStyle(.white)
                                .scaleEffect(isCurrent ? 1.0 : 0.95, anchor: .leading)
                                .opacity(isCurrent ? 1.0 : 0.35)
                                // OPTIMIZATION: Animates exclusively on state shifts (avoids layout engine thrashing)
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
                    .onAppear { scrollToCurrentLyric(using: proxy, animated: false) }
                    .onChange(of: currentLyricID) { _, _ in scrollToCurrentLyric(using: proxy, animated: true) }
                    .onChange(of: lyrics.count) { _, _ in scrollToCurrentLyric(using: proxy, animated: false) }
                }
            }
        }
    }

    private func scrollToCurrentLyric(using proxy: ScrollViewProxy, animated: Bool) {
        guard let currentLyricID = currentLyricID else { return }
        if animated {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                proxy.scrollTo(currentLyricID, anchor: .center)
            }
        } else {
            proxy.scrollTo(currentLyricID, anchor: .center)
        }
    }
}

// MARK: - Bottom Pane (Scrubber & Playback)
private struct LyricsDetachedBottomBar: View {
    @EnvironmentObject var musicManager: MusicManager
    @State private var currentProgress: Double = 0.0
    @State private var displayedElapsedTime: TimeInterval = 0

    var body: some View {
        VStack(spacing: 20) {
            
            // Ultra-thin Scrubber Line
            VStack(spacing: 8) {
                InteractiveProgressBar(
                    value: $currentProgress,
                    gradient: Gradient(colors: [.white, .white.opacity(0.8)]),
                    onSeek: { newProgress in
                        let seekTime = newProgress * musicManager.totalDuration
                        if seekTime.isFinite && musicManager.totalDuration > 0 {
                            musicManager.seek(to: seekTime)
                        }
                    }
                )
                .frame(height: 4) // Extremely thin TV style
                .background(Color.white.opacity(0.2))
                .clipShape(Capsule())

                // Time Labels
                HStack {
                    Text(formatTime(displayedElapsedTime))
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.6))
                    
                    Spacer()
                    
                    Text("-" + formatTime(max(0, musicManager.totalDuration - displayedElapsedTime)))
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            
            // Minimal Playback Controls
            HStack(spacing: 32) {
                SeekButton(
                    systemName: "backward.fill",
                    onTap: { musicManager.previousTrack() },
                    onSeek: { isForward in musicManager.seek(by: isForward ? 5.0 : -5.0) }
                )
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white.opacity(0.8))

                Button(action: {
                    musicManager.isPlaying ? musicManager.pause() : musicManager.play()
                }) {
                    Image(systemName: musicManager.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.plain)
                .scaleEffect(musicManager.isPlaying ? 1.0 : 0.95)

                SeekButton(
                    systemName: "forward.fill",
                    onTap: { musicManager.nextTrack() },
                    onSeek: { isForward in musicManager.seek(by: isForward ? 5.0 : -5.0) }
                )
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white.opacity(0.8))
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

    private func formatTime(_ seconds: TimeInterval) -> String {
        let clamped = max(0, seconds.isFinite ? seconds : 0)
        let minutes = Int(clamped) / 60
        let remainingSeconds = Int(clamped) % 60
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }
}
