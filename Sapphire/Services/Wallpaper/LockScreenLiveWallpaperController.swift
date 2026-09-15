//
//  LockScreenLiveWallpaperController.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-15.
//

import AppKit

@MainActor
final class LockScreenLiveWallpaperController {
    struct Options: Equatable {
        var scaling: WallpaperScaling = .fill
    }

    private static let windowLevel = NSWindow.Level.normal

    private var media: WallpaperMedia?
    private var options = Options()
    private var source: LiveWallpaperVideoSource?
    private var windows: [LiveWallpaperWindow] = []
    private var isSuspended = false
    private var playbackFailed = false
    private var activity: NSObjectProtocol?
    private var screenObserver: NSObjectProtocol?
    private var generation = 0

    var isShowing: Bool { !windows.isEmpty }

    func show(_ newMedia: WallpaperMedia, options newOptions: Options) {
        let mediaChanged = newMedia != media
        guard mediaChanged || newOptions != options || windows.isEmpty else { return }

        if mediaChanged {
            removeWindowsImmediately()
            releaseSource()
            playbackFailed = false
        }
        media = newMedia
        options = newOptions
        guard !playbackFailed else { return }

        generation &+= 1
        if source == nil {
            source = LiveWallpaperVideoSource.acquire(newMedia.url, client: self) { [weak self] in
                self?.handlePlaybackFailure()
            }
        }

        rebuildWindows()
        startObservingScreens()
        if !isSuspended {
            beginActivity()
        }
        updatePlayback()
    }

    func hide(animated: Bool) {
        guard media != nil || !windows.isEmpty else { return }
        generation &+= 1
        let hideGeneration = generation

        media = nil
        playbackFailed = false
        endActivity()
        stopObservingScreens()

        let closing = windows
        let closingSource = source
        windows = []
        source = nil
        closingSource?.setWantsPlayback(false, client: self)

        let finish = { [weak self] in
            guard let self else { return }
            for window in closing {
                LockScreenManager.shared.removeWallpaperWindow(window)
                window.wallpaperView.detachPlayer()
                window.orderOut(nil)
            }
            if let closingSource, self.source !== closingSource || self.generation == hideGeneration {
                closingSource.release(client: self)
            }
        }

        guard animated, closing.contains(where: { $0.isVisible && $0.alphaValue > 0.01 }) else {
            finish()
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            for window in closing {
                window.animator().alphaValue = 0
            }
        } completionHandler: {
            MainActor.assumeIsolated { finish() }
        }
    }

    func setSuspended(_ suspended: Bool) {
        guard suspended != isSuspended else { return }
        isSuspended = suspended
        if suspended {
            endActivity()
        } else if media != nil, !windows.isEmpty {
            beginActivity()
        }
        updatePlayback()
    }

    // MARK: - Windows

    private func rebuildWindows() {
        guard let source else { return }
        let screens = NSScreen.screens

        if windows.count != screens.count || zip(windows, screens).contains(where: { $0.frame != $1.frame }) {
            removeWindowsImmediately()
            for screen in screens {
                let window = LiveWallpaperWindow(frame: screen.frame, level: Self.windowLevel)
                LockScreenManager.shared.delegateWallpaperWindow(window)
                windows.append(window)
                window.orderFrontRegardless()
            }
        }

        for window in windows {
            window.wallpaperView.attach(player: source.player, scaling: options.scaling)
        }
    }

    private func removeWindowsImmediately() {
        for window in windows {
            LockScreenManager.shared.removeWallpaperWindow(window)
            window.wallpaperView.detachPlayer()
            window.orderOut(nil)
        }
        windows.removeAll()
    }

    private func releaseSource() {
        source?.release(client: self)
        source = nil
    }

    private func updatePlayback() {
        source?.setWantsPlayback(!isSuspended && !windows.isEmpty, client: self)
    }

    private func handlePlaybackFailure() {
        playbackFailed = true
        endActivity()
        removeWindowsImmediately()
        releaseSource()
    }

    // MARK: - App Nap

    private func beginActivity() {
        guard activity == nil else { return }
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep],
            reason: "Live lock screen wallpaper"
        )
    }

    private func endActivity() {
        if let activity {
            ProcessInfo.processInfo.endActivity(activity)
        }
        activity = nil
    }

    // MARK: - Screens

    private func startObservingScreens() {
        guard screenObserver == nil else { return }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.media != nil else { return }
                self.rebuildWindows()
                self.updatePlayback()
            }
        }
    }

    private func stopObservingScreens() {
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
        screenObserver = nil
    }
}