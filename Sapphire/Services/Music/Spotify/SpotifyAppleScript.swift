//
//  SpotifyAppleScript.swift
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

    @discardableResult
    func play() async -> Bool {
        guard isAppRunning() else { return false }
        return await runAppleScriptInBackground("tell application \"Spotify\" to play")
    }

    @discardableResult
    func pause() async -> Bool {
        guard isAppRunning() else { return false }
        return await runAppleScriptInBackground("tell application \"Spotify\" to pause")
    }

    func play(uri: String) async -> PlaybackResult {
        if !isAppRunning() {
            return .requiresSpotifyAppOpen
        }
        let script = "tell application \"Spotify\" to play track \"\(uri)\""
        let success = await runAppleScriptInBackground(script)
        return success ? .success : .failure(reason: "AppleScript command failed.")
    }

    func launchAndPlay() async {
        if isAppRunning() {
            let script = "tell application \"Spotify\" to play"
            _ = await runAppleScriptInBackground(script)
        } else {
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.spotify.client") else { return }
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = false
            configuration.addsToRecentItems = false
            do {
                _ = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
            } catch {
                NSWorkspace.shared.open(url)
            }

            for _ in 0..<10 {
                try? await Task.sleep(nanoseconds: 500_000_000)
                if isAppRunning() {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    let script = "tell application \"Spotify\" to play"
                    _ = await runAppleScriptInBackground(script)
                    return
                }
            }
        }
    }

    @discardableResult
    func relaunchWithoutActivating() async -> Bool {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.spotify.client").first,
              let bundleURL = app.bundleURL ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.spotify.client") else {
            return false
        }

        app.terminate()
        let softDeadline = Date().addingTimeInterval(4.0)
        while !app.isTerminated, Date() < softDeadline {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        if !app.isTerminated {
            app.forceTerminate()
            let forceDeadline = Date().addingTimeInterval(2.0)
            while !app.isTerminated, Date() < forceDeadline {
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
        guard app.isTerminated else { return false }

        try? await Task.sleep(nanoseconds: 350_000_000)

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.hides = false
        configuration.promptsUserIfNeeded = false
        configuration.addsToRecentItems = false
        do {
            _ = try await NSWorkspace.shared.openApplication(at: bundleURL, configuration: configuration)
        } catch {
            print("[SpotifyAppleScript] Background relaunch failed: \(error.localizedDescription)")
            return false
        }

        for _ in 0..<20 {
            try? await Task.sleep(nanoseconds: 150_000_000)
            if isAppRunning() { return true }
        }
        return isAppRunning()
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
        return nil
    }

    func getLocalVolumeAsync() async -> Int? {
        guard isAppRunning() else { return nil }
        let script = "if application \"Spotify\" is running then tell application \"Spotify\" to get sound volume"
        let output = await runOsascriptReturningString(script)
        return output.flatMap(Int.init)
    }

    @discardableResult
    func nextTrack() async -> Bool {
        guard isAppRunning() else { return false }
        return await runAppleScriptInBackground("tell application \"Spotify\" to next track")
    }

    @discardableResult
    func previousTrack() async -> Bool {
        guard isAppRunning() else { return false }
        let positionScript = "if application \"Spotify\" is running then tell application \"Spotify\" to get player position"
        if let position = await runOsascriptReturningString(positionScript).flatMap(Double.init), position > 3 {
            return await runAppleScriptInBackground("tell application \"Spotify\" to set player position to 0")
        }
        return await runAppleScriptInBackground("tell application \"Spotify\" to previous track")
    }

    @discardableResult
    func seek(to seconds: TimeInterval) async -> Bool {
        guard isAppRunning() else { return false }
        let clamped = max(0, seconds)
        return await runAppleScriptInBackground(
            "tell application \"Spotify\" to set player position to \(clamped)"
        )
    }

    private func runOsascriptReturningString(_ script: String) async -> String? {
        guard let result = await ProcessRunner.run(
            executablePath: "/usr/bin/osascript",
            arguments: ["-e", script],
            timeout: 2
        ), result.succeeded else { return nil }
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func runAppleScriptInBackground(_ script: String) async -> Bool {
        guard let result = await ProcessRunner.run(
            executablePath: "/usr/bin/osascript",
            arguments: ["-e", script],
            timeout: 2
        ) else { return false }
        return result.succeeded
    }

    private func runAppleScriptWithResult<T>(_ script: String) async -> T? {
        if T.self == Bool.self {
            let value = await ProcessRunner.runAppleScriptBool(script, timeout: 2)
            return value as? T
        }
        if T.self == String.self {
            return await runOsascriptReturningString(script) as? T
        }
        return nil
    }
}