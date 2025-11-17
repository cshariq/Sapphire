//
//  SpotifyAppleScriptManager.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-09-22.
//

import Foundation
import AppKit

@MainActor
class SpotifyAppleScriptManager {
    static let shared = SpotifyAppleScriptManager()

    private init() {}

    func isAppRunning() -> Bool {
        return NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == "com.spotify.client" }
    }

    func isPlaying() async -> Bool {
        let script = "if application \"Spotify\" is running then return player state is playing"
        return await runAppleScriptWithResult(script) ?? false
    }

    func getShuffleState() async -> Bool {
        let script = "if application \"Spotify\" is running then return shuffling"
        return await runAppleScriptWithResult(script) ?? false
    }

    func getRepeatState() async -> RepeatMode {
        let script = "if application \"Spotify\" is running then return repeating mode as string"
        let result: String? = await runAppleScriptWithResult(script)
        return RepeatMode(rawValue: result ?? "off") ?? .off
    }

    func isCurrentTrackLiked() async -> Bool {
        let script = "if application \"Spotify\" is running then tell application \"Spotify\" to return loved of current track"
        return await runAppleScriptWithResult(script) ?? false
    }

    func play(uri: String) async -> PlaybackResult {
        if !isAppRunning() {
            return .requiresSpotifyAppOpen
        }
        let script = "tell application \"Spotify\" to play track \"\(uri)\""
        let success = await runAppleScriptInBackground(script)
        return success ? .success : .failure(reason: "AppleScript command failed.")
    }

    func setVolume(percent: Int) async -> PlaybackResult {
        if isAppRunning() {
            let script = "tell application \"Spotify\" to set sound volume to \(percent)"
            let success = await runAppleScriptInBackground(script)
            return success ? .success : .failure(reason: "AppleScript failed")
        } else {
            return .requiresSpotifyAppOpen
        }
    }

    func getLocalVolume() -> Int? {
        guard isAppRunning() else { return nil }
        let script = "if application \"Spotify\" is running then tell application \"Spotify\" to get sound volume"
        var error: NSDictionary?
        if let scriptObject = NSAppleScript(source: script) {
            let result = scriptObject.executeAndReturnError(&error)
            if error == nil, let volume = result.int32Value as? Int {
                return volume
            }
        }
        return nil
    }

    private func runAppleScriptInBackground(_ script: String) async -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    private func runAppleScriptWithResult<T>(_ script: String) async -> T? {
        var error: NSDictionary?
        guard let scriptObject = NSAppleScript(source: script) else { return nil }

        return await Task.detached {
            let result = scriptObject.executeAndReturnError(&error)
            if error != nil {
                return nil
            }

            if T.self == Bool.self {
                return result.booleanValue as? T
            } else if T.self == String.self {
                return result.stringValue as? T
            }
            return nil
        }.value
    }
}