//
//  LyricsView.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-06-26.
//

import SwiftUI
import AppKit

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
    @State private var displayedElapsedTime: TimeInterval = 0

    private var lyrics: [LyricLine] { musicManager.lyrics }
    private var currentLyricID: UUID? { musicManager.currentLyric?.id }
    private var accentColor: Color { musicManager.accentColor }

    private let lineSpacing: CGFloat = 70.0

    var body: some View {
        GeometryReader { geometry in
            let computedOffset = calculateScrollOffset(fullViewHeight: geometry.size.height)

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
                        .animation(.spring(response: 0.8, dampingFraction: 0.8), value: computedOffset)
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

                trackHeaderView
                    .padding(.leading, 5)
            }
        }
        .frame(width: 550, height: 250)
        .onAppear {
            displayedElapsedTime = musicManager.currentElapsedTime
            musicManager.setLyricsDetailOpen(true)
        }
        .onDisappear {
            musicManager.setLyricsDetailOpen(false)
        }
        .onReceive(musicManager.playbackTimePublisher) { payload in
            displayedElapsedTime = payload.elapsed
        }
    }

    private func calculateScrollOffset(fullViewHeight: CGFloat) -> CGFloat {
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

    private var trackHeaderView: some View {
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
            
            Text("\(formatTime(displayedElapsedTime)) / \(formatTime(musicManager.totalDuration))")
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

    private func formatTime(_ seconds: TimeInterval) -> String {
        let clamped = max(0, seconds.isFinite ? seconds : 0)
        let minutes = Int(clamped) / 60
        let remainingSeconds = Int(clamped) % 60
        return String(format: "%d:%02d", minutes, remainingSeconds)
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
