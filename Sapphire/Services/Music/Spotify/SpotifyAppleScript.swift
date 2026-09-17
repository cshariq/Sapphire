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
                let app = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
                _ = await waitUntilLaunched(app, timeout: 5)
            } catch {
                NSWorkspace.shared.open(url)
                guard await waitUntilSpotifyIsRunning(timeout: 5) else { return }
            }
            let script = "tell application \"Spotify\" to play"
            _ = await runAppleScriptInBackground(script)
        }
    }

    @discardableResult
    func relaunchWithoutActivating() async -> Bool {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.spotify.client").first,
              let bundleURL = app.bundleURL ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.spotify.client") else {
            return false
        }

        app.terminate()
        if !(await waitUntilTerminated(app, timeout: 4)) {
            app.forceTerminate()
            _ = await waitUntilTerminated(app, timeout: 2)
        }
        guard app.isTerminated else { return false }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.hides = false
        configuration.promptsUserIfNeeded = false
        configuration.addsToRecentItems = false
        do {
            let relaunched = try await NSWorkspace.shared.openApplication(at: bundleURL, configuration: configuration)
            return await waitUntilLaunched(relaunched, timeout: 4)
        } catch {
            print("[SpotifyAppleScript] Background relaunch failed: \(error.localizedDescription)")
            return false
        }
    }

    private func waitUntilTerminated(_ app: NSRunningApplication, timeout: TimeInterval) async -> Bool {
        guard !app.isTerminated else { return true }
        return await waitForWorkspaceEvent(
            NSWorkspace.didTerminateApplicationNotification,
            processIdentifier: app.processIdentifier,
            timeout: timeout,
            stateCheck: { app.isTerminated }
        )
    }

    private func waitUntilLaunched(_ app: NSRunningApplication, timeout: TimeInterval) async -> Bool {
        guard !app.isFinishedLaunching else { return true }
        return await waitForWorkspaceEvent(
            NSWorkspace.didLaunchApplicationNotification,
            processIdentifier: app.processIdentifier,
            timeout: timeout,
            stateCheck: { app.isFinishedLaunching }
        )
    }

    private func waitUntilSpotifyIsRunning(timeout: TimeInterval) async -> Bool {
        if isAppRunning() { return true }
        return await waitForWorkspaceEvent(
            NSWorkspace.didLaunchApplicationNotification,
            bundleIdentifier: "com.spotify.client",
            timeout: timeout,
            stateCheck: { self.isAppRunning() }
        )
    }

    private func waitForWorkspaceEvent(
        _ name: Notification.Name,
        processIdentifier: pid_t? = nil,
        bundleIdentifier: String? = nil,
        timeout: TimeInterval,
        stateCheck: @escaping () -> Bool
    ) async -> Bool {
        if stateCheck() { return true }

        let center = NSWorkspace.shared.notificationCenter
        return await withCheckedContinuation { continuation in
            var observer: NSObjectProtocol?
            var didFinish = false

            let finish: (Bool) -> Void = { result in
                guard !didFinish else { return }
                didFinish = true
                if let observer { center.removeObserver(observer) }
                continuation.resume(returning: result)
            }

            observer = center.addObserver(forName: name, object: nil, queue: .main) { notification in
                let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                if let processIdentifier,
                   application?.processIdentifier != processIdentifier { return }
                if let bundleIdentifier,
                   application?.bundleIdentifier != bundleIdentifier { return }
                finish(true)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
                finish(stateCheck())
            }

            if stateCheck() { finish(true) }
        }
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