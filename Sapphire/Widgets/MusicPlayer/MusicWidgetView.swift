//
//  MusicWidgetView.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-06-26.
//

import SwiftUI
import AppKit

struct MusicWidgetView: View {
    @Environment(\.navigationStack) var navigationStack
    @EnvironmentObject var musicManager: MusicManager
    @EnvironmentObject var settings: SettingsModel
    @State private var isHoveringArtwork = false

    var body: some View {
        if let title = musicManager.title, !title.isEmpty {
            HStack(alignment: .center, spacing: 16) {
                albumArt

                VStack(alignment: .leading, spacing: 8) {
                    MusicInfoView(
                        title: musicManager.title,
                        album: musicManager.album,
                        artist: musicManager.artist
                    )

                    MusicControlsView(
                        isPlaying: musicManager.isPlaying,
                        onPrevious: musicManager.previousTrack,
                        onPlayPause: { musicManager.isPlaying ? musicManager.pause() : musicManager.play() },
                        onNext: musicManager.nextTrack
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 100)
            .frame(maxWidth: 300)
            .fixedSize()
            .contentShape(Rectangle())
            .onTapGesture {
                navigationStack.wrappedValue.append(.musicPlayer)
            }

        } else {
            OpenPlayerView(
                player: settings.settings.defaultMusicPlayer,
                action: openDefaultPlayer
            )
        }
    }

    private var albumArt: some View {
        Image(nsImage: musicManager.artwork ?? musicManager.appIcon ?? NSImage(systemSymbolName: "waveform", accessibilityDescription: "Album art")!)
            .resizable().aspectRatio(contentMode: .fill)
            .frame(width: 100, height: 100).cornerRadius(30)
            .shadow(color: musicManager.accentColor.opacity(0.7), radius: 8, y: 5)
            .onHover { hovering in
                self.isHoveringArtwork = hovering
            }
    }

    private func openDefaultPlayer() {
        let player = settings.settings.defaultMusicPlayer
        let bundleId = player == .appleMusic ? "com.apple.Music" : "com.spotify.client"

        NSWorkspace.shared.launchApplication(
            withBundleIdentifier: bundleId,
            options: [],
            additionalEventParamDescriptor: nil,
            launchIdentifier: nil
        )
    }
}

private struct OpenPlayerView: View {
    let player: DefaultMusicPlayer
    let action: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "music.note")
                .font(.system(size: 40, weight: .light))
                .foregroundColor(.white.opacity(0.8))

            Button(action: action) {
                Text("Open \(player.displayName)")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.15))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .frame(width: 300, height: 100)
    }
}

private struct MusicInfoView: View {
    let title: String?
    let album: String?
    let artist: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let title = title, !title.isEmpty {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
            }

            if let album = album, !album.isEmpty, album != title {
                Text(album)
                    .font(.system(size: 14, weight: .medium))
            }
            if let artist = artist, !artist.isEmpty {
                Text(artist)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(.white.opacity(0.7))
            }
        }
        .foregroundStyle(.white)
        .lineLimit(1)
        .padding(.top, 8)
        .minimumScaleFactor(0.8)
    }
}

private struct MusicControlsView: View {
    let isPlaying: Bool
    let onPrevious: () -> Void
    let onPlayPause: () -> Void
    let onNext: () -> Void

    @EnvironmentObject var musicManager: MusicManager

    let buttonHitboxSize: CGFloat = 37

    var body: some View {
        HStack(spacing: 0) {
            SeekButton(
                systemName: "backward.end.fill",
                onTap: onPrevious,
                onSeek: { isForward in
                    musicManager.seek(by: isForward ? 5.0 : -5.0)
                }
            )
            .frame(width: buttonHitboxSize, height: buttonHitboxSize)

            Button(action: onPlayPause) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .frame(width: buttonHitboxSize, height: buttonHitboxSize)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            SeekButton(
                systemName: "forward.end.fill",
                onTap: onNext,
                onSeek: { isForward in
                    musicManager.seek(by: isForward ? 5.0 : -5.0)
                }
            )
            .frame(width: buttonHitboxSize, height: buttonHitboxSize)
        }
        .font(.system(size: 16))
        .foregroundColor(.white)
    }
}