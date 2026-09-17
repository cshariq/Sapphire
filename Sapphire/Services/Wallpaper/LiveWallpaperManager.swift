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
    var playbackMode: LiveWallpaperPlaybackMode = .adaptive
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
        playbackMode = settings.liveWallpaperPlaybackMode
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

    func shouldShowLockScreenOverlay(nativeWallpaperInstalled: Bool) -> Bool {
        lockScreenVideo != nil && !nativeWallpaperInstalled
    }

    static func resolve(
        desktop: WallpaperMedia?,
        lockScreen: WallpaperMedia?,
        isLocked: Bool,
        playbackMode: LiveWallpaperPlaybackMode = .adaptive
    ) -> LiveWallpaperPlan {
        let lockSurface = lockScreen ?? desktop
        let playsVideo = playbackMode != .never
        return LiveWallpaperPlan(
            desktopVideo: playsVideo && desktop?.isVideo == true ? desktop : nil,
            lockScreenVideo: playsVideo && isLocked && lockSurface?.isVideo == true ? lockSurface : nil,
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
    private let nativeLockScreen = NativeLockScreenWallpaperController()

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
        nativeLockScreen.onChange = { [weak self] in
            self?.refresh()
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

        policy.pauseOnLowPower = configuration.playbackMode == .adaptive && configuration.pauseOnLowPower
        policy.pauseOnBattery = configuration.playbackMode == .adaptive && configuration.pauseOnBattery
        policy.start()
        refresh()
    }

    func screenDidLock() {
        guard isStarted, !isLocked else { return }
        isLocked = true
        nativeLockScreen.screenDidLock()
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
        nativeLockScreen.shutdown()
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
        let plan = LiveWallpaperPlan.resolve(
            desktop: desktopMedia,
            lockScreen: lockMedia,
            isLocked: isLocked,
            playbackMode: configuration.playbackMode
        )
        let lockSurface = lockMedia ?? desktopMedia
        let nativeLockMedia = configuration.playbackMode != .never && lockSurface?.isVideo == true
            ? lockSurface
            : nil
        nativeLockScreen.configure(media: nativeLockMedia)

        policy.pauseOnLowPower = configuration.playbackMode == .adaptive && configuration.pauseOnLowPower
        policy.pauseOnBattery = configuration.playbackMode == .adaptive && configuration.pauseOnBattery

        applySystemWallpaper(plan.systemWallpaper, configured: [desktopMedia, lockMedia].compactMap { $0 })

        if isLocked {
            if let lockVideo = plan.lockScreenVideo,
               plan.shouldShowLockScreenOverlay(
                   nativeWallpaperInstalled: nativeLockScreen.isInstalled(for: lockVideo)
               ) {
                lockScreen.show(lockVideo, options: .init(scaling: configuration.scaling))
            } else {
                lockScreen.hide(animated: false)
            }
            desktop.setSessionLocked(true)
            desktop.show(
                plan.desktopVideo,
                scaling: configuration.scaling,
                playbackMode: configuration.playbackMode
            )
        } else {
            desktop.setSessionLocked(false)
            desktop.show(
                plan.desktopVideo,
                scaling: configuration.scaling,
                playbackMode: configuration.playbackMode
            )
            if lockScreen.isShowing {
                lockScreen.hide(animated: true)
            }
            lockScreen.prepare(nil)
        }
        applyPlaybackPolicy()
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
            isLocked: isLocked,
            mode: configuration.playbackMode
        )
        LiveWallpaperVideoSource.setSuspended(suspended)
        lockScreen.setSuspended(suspended)
    }

    nonisolated static func shouldSuspendPlayback(
        for reasons: Set<LiveWallpaperPlaybackPolicy.Reason>,
        isLocked: Bool,
        mode: LiveWallpaperPlaybackMode = .adaptive
    ) -> Bool {
        if mode == .never { return true }

        return reasons.contains { reason in
            switch reason {
            case .sessionInactive:
                return !isLocked
            case .lowPowerMode, .onBattery:
                return mode == .adaptive
            case .displaysAsleep, .systemSleeping, .thermalPressure:
                return true
            }
        }
    }

    private static var isSessionLocked: Bool {
        let session = CGSessionCopyCurrentDictionary() as? [String: Any]
        return session?["CGSSessionScreenIsLocked"] as? Bool ?? false
    }
}