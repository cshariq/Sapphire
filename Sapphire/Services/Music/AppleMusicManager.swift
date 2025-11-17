//
//  AppleMusicManager.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-09-29
//

import Foundation
import ScriptingBridge
import AppKit

@MainActor
class AppleMusicManager {
    static let shared = AppleMusicManager()
    private let musicApp: MusicApplication?

    private init() {
        self.musicApp = SBApplication(bundleIdentifier: "com.apple.Music")
    }

    func isAppRunning() -> Bool {
        return NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == "com.apple.Music" }
    }

    func isPlaying() -> Bool {
        return musicApp?.playerState == .playing
    }

    func getShuffleState() -> Bool {
        return musicApp?.shuffleEnabled ?? false
    }

    func getRepeatState() -> RepeatMode {
        guard let repeatMode = musicApp?.songRepeat else { return .off }
        switch repeatMode {
        case .all: return .context
        case .one: return .track
        case .off: return .off
        default: return .off
        }
    }

    func isTrackLiked() -> Bool {
        return musicApp?.currentTrack?.loved ?? false
    }

    func setShuffle(enabled: Bool) {
        musicApp?.setShuffleEnabled?(enabled)
    }

    func setRepeat(mode: RepeatMode) {
        let sbMode: MusicERpt
        switch mode {
        case .off: sbMode = .off
        case .context: sbMode = .all
        case .track: sbMode = .one
        }
        musicApp?.setSongRepeat?(sbMode)
    }

    func setLiked(isLiked: Bool) {
        musicApp?.currentTrack?.setLoved?(isLiked)
    }

    func fetchPlaylists() -> [SpotifyPlaylist] {
        guard let userPlaylists = musicApp?.userPlaylists?().get() as? [MusicUserPlaylist] else { return [] }
        return userPlaylists.compactMap { playlist in
            guard let id = playlist.persistentID, let name = playlist.name else { return nil }
            return SpotifyPlaylist(
                id: id, name: name, uri: id, images: [],
                owner: SpotifyUserSimple(id: "apple_music", displayName: "Me", images: nil),
                collaborators: nil
            )
        }
    }

    func fetchPlaylistTracks(playlistID: String) -> [SpotifyTrack] {
        guard let playlist = musicApp?.userPlaylists?().object(withID: playlistID) as? MusicUserPlaylist,
              let tracks = playlist.tracks?().get() as? [MusicTrack] else { return [] }

        return tracks.compactMap { track in
            guard let id = track.persistentID,
                  let name = track.name,
                  let artist = track.artist,
                  let album = track.album,
                  let duration = track.duration else { return nil }

            return SpotifyTrack(
                id: id, name: name, uri: id,
                album: SpotifyAlbum(name: album, images: []),
                artists: [SpotifyArtist(name: artist)],
                durationMs: Int(duration * 1000),
                popularity: nil
            )
        }
    }

    func fetchAirPlayDevices() async -> [AirPlayDevice] {
        guard let sbDevices = musicApp?.AirPlayDevices?().get() as? [MusicAirPlayDevice] else { return [] }

        return sbDevices.compactMap { device in
            guard let name = device.name, let kind = device.kind else { return nil }
            return AirPlayDevice(
                name: name, kind: kind, isSelected: device.selected ?? false,
                volume: device.soundVolume
            )
        }
    }

    func switchToAirPlayDevice(_ device: AirPlayDevice) async {
        guard let sbDevices = musicApp?.AirPlayDevices?().get() as? [MusicAirPlayDevice],
              let targetDevice = sbDevices.first(where: { $0.name == device.name }) else { return }

        musicApp?.setCurrentAirPlayDevices?([targetDevice])
    }

    func setAirPlayDeviceVolume(deviceName: String, volume: Int) async {
        guard let sbDevices = musicApp?.AirPlayDevices?().get() as? [MusicAirPlayDevice],
              let targetDevice = sbDevices.first(where: { $0.name == deviceName }) else { return }

        targetDevice.setSoundVolume?(volume)
    }

    func revealCurrentTrack() {
        musicApp?.currentTrack?.reveal?()
        musicApp?.activate()
    }
}