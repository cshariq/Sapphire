//
//  LiveWallpaperManager.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-15.
//

import AppKit
import Combine

struct LiveWallpaperConfiguration: Equatable {
    var desktopPath: String?
    var lockScreenPath: String?
    var scaling: WallpaperScaling = .fill
    var pauseOnLowPower = false
    var pauseOnBattery = false

    init() {}

    init(settings: Settings) {
        let lockPath = settings.lockScreenCustomWallpaperEnabled
            ? Self.nonEmpty(settings.lockScreenCustomWallpaperPath)
            : nil
        let customDesktopPath = settings.desktopWallpaperEnabled
            ? Self.nonEmpty(settings.desktopWallpaperPath)
            : nil

        lockScreenPath = lockPath
        desktopPath = customDesktopPath ?? (settings.lockScreenKeepWallpaperAfterUnlock ? lockPath : nil)
        scaling = settings.liveWallpaperScaling
        pauseOnLowPower = settings.liveWallpaperPauseOnLowPower
        pauseOnBattery = settings.liveWallpaperPauseOnBattery
    }

    private static func nonEmpty(_ path: String?) -> String? {
        guard let path, !path.isEmpty else { return nil }
        return path
    }
}

struct LiveWallpaperPlan: Equatable {
    var desktopVideo: WallpaperMedia?
    var lockScreenVideo: WallpaperMedia?
    var systemWallpaper: WallpaperMedia?

    static func resolve(desktop: WallpaperMedia?, lockScreen: WallpaperMedia?, isLocked: Bool) -> LiveWallpaperPlan {
        let lockSurface = lockScreen ?? desktop
        return LiveWallpaperPlan(
            desktopVideo: desktop?.isVideo == true ? desktop : nil,
            lockScreenVideo: isLocked && lockSurface?.isVideo == true ? lockSurface : nil,
            systemWallpaper: isLocked ? lockSurface : desktop
        )
    }
}

@MainActor
final class LiveWallpaperManager {
    static let shared = LiveWallpaperManager()

    private struct StillRequest: Equatable {
        let media: WallpaperMedia
        let scaling: WallpaperScaling
    }

    private let policy = LiveWallpaperPlaybackPolicy()
    private let desktop = DesktopLiveWallpaperController()
    private let lockScreen = LockScreenLiveWallpaperController()

    private var configuration = LiveWallpaperConfiguration()
    private var settingsCancellable: AnyCancellable?
    private var screenObserver: NSObjectProtocol?
    private var stillTask: Task<Void, Never>?
    private var requestedStill: StillRequest?
    private var isStarted = false
    private var isLocked = false

    private init() {
        policy.onChange = { [weak self] reasons in
            self?.handlePolicyChange(reasons)
        }
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        isLocked = Self.isSessionLocked

        let settings = SettingsModel.shared
        configuration = LiveWallpaperConfiguration(settings: settings.settings)
        settingsCancellable = settings.changes(of: LiveWallpaperConfiguration.init(settings:))
            .sink { [weak self] configuration in
                self?.configuration = configuration
                self?.refresh()
            }

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.requestedStill = nil
                self?.refresh()
            }
        }

        policy.pauseOnLowPower = configuration.pauseOnLowPower
        policy.pauseOnBattery = configuration.pauseOnBattery
        policy.start()
        refresh()
    }

    func screenDidLock() {
        guard isStarted, !isLocked else { return }
        isLocked = true
        refresh()
        applyPlaybackPolicy()
    }

    func screenDidUnlock() {
        guard isStarted, isLocked else { return }
        isLocked = false
        applyPlaybackPolicy()
        refresh()
    }

    func shutdown() {
        settingsCancellable = nil
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
        screenObserver = nil
        stillTask?.cancel()
        stillTask = nil
        requestedStill = nil
        desktop.tearDown()
        lockScreen.hide(animated: false)
        policy.stop()
        LiveWallpaperVideoSource.setSuspended(false)
        SystemWallpaperOverride.shared.restore()
        isStarted = false
        isLocked = false
    }

    private func refresh() {
        guard isStarted else { return }
        let desktopMedia = WallpaperMedia(path: configuration.desktopPath)
        let lockMedia = WallpaperMedia(path: configuration.lockScreenPath)
        let plan = LiveWallpaperPlan.resolve(desktop: desktopMedia, lockScreen: lockMedia, isLocked: isLocked)

        policy.pauseOnLowPower = configuration.pauseOnLowPower
        policy.pauseOnBattery = configuration.pauseOnBattery

        applySystemWallpaper(plan.systemWallpaper, configured: [desktopMedia, lockMedia].compactMap { $0 })

        desktop.setSessionLocked(isLocked)
        desktop.show(plan.desktopVideo, scaling: configuration.scaling)

        if let lockVideo = plan.lockScreenVideo {
            lockScreen.show(lockVideo, options: .init(
                scaling: configuration.scaling
            ))
        } else {
            lockScreen.hide(animated: true)
        }
    }

    private func applySystemWallpaper(_ media: WallpaperMedia?, configured: [WallpaperMedia]) {
        let request = media.map { StillRequest(media: $0, scaling: configuration.scaling) }
        guard request != requestedStill || (request == nil && SystemWallpaperOverride.shared.isApplied) else {
            return
        }
        requestedStill = request
        stillTask?.cancel()

        guard let request else {
            stillTask = nil
            SystemWallpaperOverride.shared.restore()
            Task.detached(priority: .background) {
                WallpaperAssetStore.prunePosters(keeping: configured)
            }
            return
        }

        let prewarm = configured.filter { $0.isVideo && $0 != request.media }
        stillTask = Task { [weak self] in
            let stillURL = await Task.detached(priority: .userInitiated) {
                await WallpaperAssetStore.stillImageURL(for: request.media)
            }.value
            guard !Task.isCancelled, let self, self.requestedStill == request else { return }
            if let stillURL {
                SystemWallpaperOverride.shared.apply(stillURL, scaling: request.scaling)
            }
            Task.detached(priority: .background) {
                for media in prewarm {
                    _ = await WallpaperAssetStore.stillImageURL(for: media)
                }
                WallpaperAssetStore.prunePosters(keeping: configured)
            }
        }
    }

    private func handlePolicyChange(_ reasons: Set<LiveWallpaperPlaybackPolicy.Reason>) {
        applyPlaybackPolicy(reasons)
    }

    private func applyPlaybackPolicy(
        _ reasons: Set<LiveWallpaperPlaybackPolicy.Reason>? = nil
    ) {
        let suspended = Self.shouldSuspendPlayback(
            for: reasons ?? policy.reasons,
            isLocked: isLocked
        )
        LiveWallpaperVideoSource.setSuspended(suspended)
        lockScreen.setSuspended(suspended)
    }

    nonisolated static func shouldSuspendPlayback(
        for reasons: Set<LiveWallpaperPlaybackPolicy.Reason>,
        isLocked: Bool
    ) -> Bool {
        reasons.contains { $0 != .sessionInactive || !isLocked }
    }

    private static var isSessionLocked: Bool {
        let session = CGSessionCopyCurrentDictionary() as? [String: Any]
        return session?["CGSSessionScreenIsLocked"] as? Bool ?? false
    }
}