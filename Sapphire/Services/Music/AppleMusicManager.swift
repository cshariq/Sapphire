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
        // ScriptingBridge can hang for seconds if Music.app is unresponsive.
        // Never block the notch UI — time out and return whatever we have.
        await withTaskGroup(of: [AirPlayDevice].self) { group in
            group.addTask { @MainActor in
                guard let sbDevices = self.musicApp?.AirPlayDevices?().get() as? [MusicAirPlayDevice] else {
                    return []
                }
                return sbDevices.compactMap { device in
                    guard let name = device.name, let kind = device.kind else { return nil }
                    return AirPlayDevice(
                        name: name, kind: kind, isSelected: device.selected ?? false,
                        volume: device.soundVolume
                    )
                }
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(1.5))
                return []
            }
            let first = await group.next() ?? []
            group.cancelAll()
            return first
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

    struct QueueTrack: Identifiable, Equatable {
        let id: String
        let title: String
        let artist: String
    }

    func fetchUpNextTracks() async -> [QueueTrack] {
        guard isAppRunning() else { return [] }
        let script = """
        tell application "Music"
            if not running then return ""
            set queueNames to {"Queue", "Music Queue", "Up Next"}
            repeat with queueName in queueNames
                try
                    if not (exists playlist queueName) then error "missing"
                    set rows to {}
                    repeat with t in (tracks of playlist queueName)
                        try
                            set trackID to persistent ID of t as string
                            set trackTitle to name of t as string
                            set trackArtist to artist of t as string
                            set end of rows to trackID & "|" & trackTitle & "|" & trackArtist
                        end try
                    end repeat
                    set AppleScript's text item delimiters to linefeed
                    set joined to rows as string
                    set AppleScript's text item delimiters to ""
                    return joined
                end try
            end repeat
            return ""
        end tell
        """
        let raw: String = await Task.detached(priority: .utility) {
            Self.runOsascript(script) ?? ""
        }.value
        guard !raw.isEmpty else { return [] }
        return raw.split(separator: "\n").compactMap { line -> QueueTrack? in
            let parts = line.split(separator: "|", maxSplits: 2).map(String.init)
            guard parts.count == 3 else { return nil }
            return QueueTrack(id: parts[0], title: parts[1], artist: parts[2])
        }
    }

    private nonisolated static func runOsascript(_ script: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            let timeoutItem = DispatchWorkItem { process.terminate() }
            DispatchQueue.global().asyncAfter(deadline: .now() + 5.0, execute: timeoutItem)
            process.waitUntilExit()
            timeoutItem.cancel()
            guard process.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return output?.isEmpty == false ? output : nil
        } catch {
            return nil
        }
    }
}