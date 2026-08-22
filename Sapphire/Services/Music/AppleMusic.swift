//
//  AppleMusic.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-21

import Foundation
import AppKit
import ScriptingBridge

// MARK: - Consolidated from AppleMusicClient.swift

// MARK: MusicEKnd
@objc public enum MusicEKnd : AEKeyword {
    case trackListing = 0x6b54726b, albumListing = 0x6b416c62, cdInsert = 0x6b434469
}
@objc public enum MusicEnum : AEKeyword {
    case standard = 0x6c777374, detailed = 0x6c776474
}
@objc public enum MusicEPlS : AEKeyword {
    case stopped = 0x6b505353, playing = 0x6b505350, paused = 0x6b505370, fastForwarding = 0x6b505346, rewinding = 0x6b505352
}
@objc public enum MusicERpt : AEKeyword {
    case off = 0x6b52704f, one = 0x6b527031, all = 0x6b416c6c
}
@objc public enum MusicEShM : AEKeyword {
    case songs = 0x6b536853, albums = 0x6b536841, groupings = 0x6b536847
}

@objc public protocol SBObjectProtocol: NSObjectProtocol {
    func get() -> Any!
}
@objc public protocol SBApplicationProtocol: SBObjectProtocol {
    func activate()
    var isRunning: Bool { get }
}

@objc public protocol MusicItem: SBObjectProtocol {
    @objc optional var name: String { get }
    @objc optional var persistentID: String { get }
    @objc optional func reveal()
}
extension SBObject: MusicItem {}

@objc public protocol MusicTrack: MusicItem {
    @objc optional var artist: String { get }
    @objc optional var album: String { get }
    @objc optional var duration: Double { get }
    @objc optional var loved: Bool { get }
    @objc optional func setLoved(_ loved: Bool)
}
extension SBObject: MusicTrack {}

@objc public protocol MusicPlaylist: MusicItem {
    @objc optional func tracks() -> SBElementArray
    @objc optional func play()
}
extension SBObject: MusicPlaylist {}

@objc public protocol MusicUserPlaylist: MusicPlaylist {}
extension SBObject: MusicUserPlaylist {}

@objc public protocol MusicApplication: SBApplicationProtocol {
    @objc optional func userPlaylists() -> SBElementArray
    @objc optional func tracks() -> SBElementArray
    @objc optional var currentTrack: MusicTrack { get }
    @objc optional var playerState: MusicEPlS { get }
    @objc optional var shuffleEnabled: Bool { get }
    @objc optional var songRepeat: MusicERpt { get }
    @objc optional func setShuffleEnabled(_ shuffleEnabled: Bool)
    @objc optional func setSongRepeat(_ songRepeat: MusicERpt)
    @objc optional func play(_: SBObject!)
    @objc optional func playpause()
    @objc optional func nextTrack()
    @objc optional func previousTrack()
}
extension SBApplication: MusicApplication {}

// MARK: - Consolidated from AppleMusicManager.swift

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

    func revealCurrentTrack() {
        musicApp?.currentTrack?.reveal?()
        musicApp?.activate()
    }

    @discardableResult
    func playPlaylist(persistentID: String) -> Bool {
        guard let playlist = musicApp?.userPlaylists?().object(withID: persistentID) as? MusicUserPlaylist else {
            return false
        }
        if let play = playlist.play {
            play()
            return true
        }
        musicApp?.play?(playlist as! SBObject)
        return true
    }

    @discardableResult
    func playTrack(persistentID: String) -> Bool {
        if let track = musicApp?.tracks?().object(withID: persistentID) as? MusicTrack {
            musicApp?.play?(track as! SBObject)
            return true
        }
        return false
    }

    @discardableResult
    func playTrack(persistentID: String, inPlaylistPersistentID playlistID: String) -> Bool {
        guard let playlist = musicApp?.userPlaylists?().object(withID: playlistID) as? MusicUserPlaylist,
              let tracks = playlist.tracks?().get() as? [MusicTrack],
              let track = tracks.first(where: { $0.persistentID == persistentID }) else {
            return playTrack(persistentID: persistentID)
        }
        musicApp?.play?(track as! SBObject)
        return true
    }

    func currentPlaylistName() -> String? {
        return musicApp?.currentTrack?.album
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