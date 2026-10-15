//
//  AppleMusicAppBridge.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-25
//

import Foundation
import AppKit

@MainActor
final class AppleMusicAppBridge {
    static let shared = AppleMusicAppBridge()

    static let bundleID = "com.apple.Music"

    private init() {}

    struct CurrentTrack: Equatable {
        let persistentID: String
        let title: String
        let artist: String
        let album: String
        let favorited: Bool
        let disliked: Bool
        let playedCount: Int
        let rating: Int
        let isLibraryTrack: Bool
    }

    struct QueueEntry: Equatable {
        let persistentID: String
        let title: String
        let artist: String
    }

    var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID).isEmpty
    }

    // MARK: - Current track

    func currentTrack() async -> CurrentTrack? {
        guard isRunning else { return nil }
        let script = """
        tell application id "com.apple.Music"
            if player state is stopped then return ""
            set t to current track
            set pid to persistent ID of t
            set nm to name of t
            set ar to artist of t
            set al to album of t
            set fav to false
            try
                set fav to favorited of t
            on error
                try
                    set fav to loved of t
                end try
            end try
            set dis to false
            try
                set dis to disliked of t
            end try
            set pc to 0
            try
                set pc to played count of t
            end try
            set rt to 0
            try
                set rt to rating of t
            end try
            set lib to false
            try
                set lib to exists (some track of library playlist 1 whose persistent ID is pid)
            end try
            set AppleScript's text item delimiters to (ASCII character 31)
            return {pid, nm, ar, al, fav as text, dis as text, pc as text, rt as text, lib as text} as text
        end tell
        """
        guard let output = await run(script) else { return nil }
        let parts = output.components(separatedBy: "\u{1F}")
        guard parts.count >= 9 else { return nil }
        return CurrentTrack(
            persistentID: parts[0],
            title: parts[1],
            artist: parts[2],
            album: parts[3],
            favorited: parts[4] == "true",
            disliked: parts[5] == "true",
            playedCount: Int(parts[6]) ?? 0,
            rating: Int(parts[7]) ?? 0,
            isLibraryTrack: parts[8] == "true"
        )
    }

    func setFavorited(_ favorited: Bool, title: String?, artist: String?) async -> Bool {
        guard isRunning || title != nil else { return false }
        let script = """
        on run argv
            set wantFav to (item 1 of argv) is "true"
            set wantTitle to item 2 of argv
            set wantArtist to item 3 of argv
            tell application id "com.apple.Music"
                set t to missing value
                if player state is not stopped then
                    set t to current track
                    if wantTitle is not "" and name of t is not wantTitle then set t to missing value
                end if
                if t is missing value and wantTitle is not "" then
                    set hits to (every track of library playlist 1 whose name is wantTitle and artist contains wantArtist)
                    if (count of hits) is 0 then return "false"
                    set t to item 1 of hits
                end if
                if t is missing value then return "false"
                try
                    set favorited of t to wantFav
                on error
                    set loved of t to wantFav
                end try
                if wantFav then
                    try
                        set disliked of t to false
                    end try
                end if
                return "true"
            end tell
        end run
        """
        return await run(script, arguments: [favorited ? "true" : "false", title ?? "", artist ?? ""]) == "true"
    }

    func setDisliked(_ disliked: Bool) async -> Bool {
        guard isRunning else { return false }
        let script = """
        on run argv
            tell application id "com.apple.Music"
                if player state is stopped then return "false"
                set disliked of current track to ((item 1 of argv) is "true")
                return "true"
            end tell
        end run
        """
        return await run(script, arguments: [disliked ? "true" : "false"]) == "true"
    }

    func addCurrentTrackToLibrary() async -> Bool {
        guard isRunning else { return false }
        let script = """
        tell application id "com.apple.Music"
            if player state is stopped then return "false"
            duplicate current track to source 1
            return "true"
        end tell
        """
        return await run(script) == "true"
    }

    func addCurrentTrack(toPlaylistNamed name: String) async -> Bool {
        guard isRunning else { return false }
        let script = """
        on run argv
            tell application id "com.apple.Music"
                if player state is stopped then return "false"
                set p to first user playlist whose name is (item 1 of argv)
                duplicate current track to p
                return "true"
            end tell
        end run
        """
        return await run(script, arguments: [name]) == "true"
    }

    func createPlaylist(named name: String, addingCurrentTrack: Bool) async -> Bool {
        let script = """
        on run argv
            tell application id "com.apple.Music"
                set p to make new user playlist with properties {name:(item 1 of argv)}
                if (item 2 of argv) is "true" and player state is not stopped then
                    duplicate current track to p
                end if
                return "true"
            end tell
        end run
        """
        return await run(script, arguments: [name, addingCurrentTrack ? "true" : "false"]) == "true"
    }

    func userPlaylistNames() async -> [String] {
        guard isRunning else { return [] }
        let script = """
        tell application id "com.apple.Music"
            set AppleScript's text item delimiters to (ASCII character 31)
            return (name of every user playlist whose smart is false and special kind is none) as text
        end tell
        """
        guard let output = await run(script) else { return [] }
        return output.components(separatedBy: "\u{1F}").filter { !$0.isEmpty }
    }

    func playUserPlaylist(named name: String, startingAtTitle title: String?, shuffled: Bool) async -> Bool {
        let script = """
        on run argv
            set playlistName to item 1 of argv
            set startTitle to item 2 of argv
            tell application id "com.apple.Music"
                set p to first playlist whose name is playlistName
                if (item 3 of argv) is "true" then set shuffle enabled to true
                if startTitle is not "" then
                    set hits to (every track of p whose name is startTitle)
                    if (count of hits) > 0 then
                        play item 1 of hits
                        return "true"
                    end if
                end if
                play p
                return "true"
            end tell
        end run
        """
        return await run(script, arguments: [name, title ?? "", shuffled ? "true" : "false"]) == "true"
    }

    // MARK: - Player modes

    func shuffleEnabled() async -> Bool? {
        guard isRunning else { return nil }
        guard let value = await run("tell application id \"com.apple.Music\" to return shuffle enabled as text") else { return nil }
        return value == "true"
    }

    func setShuffle(_ enabled: Bool) async -> Bool {
        guard isRunning else { return false }
        let script = """
        on run argv
            tell application id "com.apple.Music" to set shuffle enabled to ((item 1 of argv) is "true")
            return "true"
        end run
        """
        return await run(script, arguments: [enabled ? "true" : "false"]) == "true"
    }

    func repeatMode() async -> RepeatMode? {
        guard isRunning else { return nil }
        guard let value = await run("tell application id \"com.apple.Music\" to return song repeat as text") else { return nil }
        switch value {
        case "one": return .track
        case "all": return .context
        default: return .off
        }
    }

    func setRepeat(_ mode: RepeatMode) async -> Bool {
        guard isRunning else { return false }
        let script: String
        switch mode {
        case .off: script = "tell application id \"com.apple.Music\" to set song repeat to off"
        case .context: script = "tell application id \"com.apple.Music\" to set song repeat to all"
        case .track: script = "tell application id \"com.apple.Music\" to set song repeat to one"
        }
        return await run(script + "\nreturn \"true\"") == "true"
    }

    func pauseIfPlaying() async {
        guard isRunning else { return }
        _ = await run("tell application id \"com.apple.Music\" to if player state is playing then pause")
    }

    // MARK: - Up Next

    func upcomingTracks(limit: Int = 20) async -> [QueueEntry] {
        guard isRunning else { return [] }
        let script = """
        on run argv
            set maxCount to (item 1 of argv) as integer
            tell application id "com.apple.Music"
                if player state is stopped then return ""
                if shuffle enabled then return ""
                try
                    set p to current playlist
                    set i to index of current track
                on error
                    return ""
                end try
                set n to count of tracks of p
                set lastIndex to i + maxCount
                if lastIndex > n then set lastIndex to n
                set rows to {}
                repeat with k from (i + 1) to lastIndex
                    set t to track k of p
                    set end of rows to (persistent ID of t) & (ASCII character 31) & (name of t) & (ASCII character 31) & (artist of t)
                end repeat
                set AppleScript's text item delimiters to (ASCII character 30)
                return rows as text
            end tell
        end run
        """
        guard let output = await run(script, arguments: [String(limit)]) else { return [] }
        return output.components(separatedBy: "\u{1E}").compactMap { row in
            let parts = row.components(separatedBy: "\u{1F}")
            guard parts.count >= 3, !parts[0].isEmpty else { return nil }
            return QueueEntry(persistentID: parts[0], title: parts[1], artist: parts[2])
        }
    }

    func playTrackInCurrentPlaylist(persistentID: String) async -> Bool {
        guard isRunning else { return false }
        let script = """
        on run argv
            tell application id "com.apple.Music"
                play (first track of current playlist whose persistent ID is (item 1 of argv))
                return "true"
            end tell
        end run
        """
        return await run(script, arguments: [persistentID]) == "true"
    }

    // MARK: - Reveal

    func revealCurrentTrack() async {
        guard isRunning else {
            open(url: nil)
            return
        }
        _ = await run("""
        tell application id "com.apple.Music"
            activate
            try
                if player state is not stopped then reveal current track
            end try
        end tell
        """)
    }

    func open(url: URL?) {
        if let url, var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            components.scheme = "music"
            if let musicURL = components.url {
                NSWorkspace.shared.open(musicURL)
                return
            }
        }
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.bundleID) {
            NSWorkspace.shared.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    // MARK: - Plumbing

    private func run(_ script: String, arguments: [String] = []) async -> String? {
        let result = await ProcessRunner.runAppleScript(script, extraArguments: arguments, timeout: 6)
        return result
    }
}