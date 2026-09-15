//
//  LiveWallpaperTests.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-15

import AVFoundation
import Foundation
import Testing
@testable import Sapphire

@Suite("Live wallpaper")
struct LiveWallpaperTests {
    private let video = WallpaperMedia(url: URL(fileURLWithPath: "/tmp/sapphire-tests/ocean.mov"), kind: .video)
    private let otherVideo = WallpaperMedia(url: URL(fileURLWithPath: "/tmp/sapphire-tests/forest.mp4"), kind: .video)
    private let image = WallpaperMedia(url: URL(fileURLWithPath: "/tmp/sapphire-tests/peak.jpg"), kind: .image)

    @Test("New wallpaper features are disabled by default")
    func featuresDefaultToDisabled() {
        let settings = Settings()
        let configuration = LiveWallpaperConfiguration(settings: settings)

        #expect(!settings.lockScreenCustomWallpaperEnabled)
        #expect(!settings.desktopWallpaperEnabled)
        #expect(!settings.liveWallpaperPauseOnLowPower)
        #expect(!settings.liveWallpaperPauseOnBattery)
        #expect(configuration.desktopPath == nil)
        #expect(configuration.lockScreenPath == nil)
        #expect(!configuration.pauseOnLowPower)
        #expect(!configuration.pauseOnBattery)
    }

    @Test("Classifies movies as video and everything else as a still")
    func mediaKind() {
        for name in ["clip.mov", "clip.MP4", "clip.m4v"] {
            #expect(WallpaperMedia.kind(of: URL(fileURLWithPath: "/nonexistent/\(name)")) == .video)
        }
        for name in ["photo.jpg", "photo.heic", "photo.png", "sequence.heics", "song.mp3", "noextension"] {
            #expect(WallpaperMedia.kind(of: URL(fileURLWithPath: "/nonexistent/\(name)")) == .image)
        }
        #expect(WallpaperMedia(path: nil) == nil)
        #expect(WallpaperMedia(path: "") == nil)
        #expect(WallpaperMedia(path: "/nonexistent/clip.mov") == nil)
    }

    @Test("Desktop video plays on the desktop and mirrors onto the lock screen")
    func desktopVideoOnly() {
        let unlocked = LiveWallpaperPlan.resolve(desktop: video, lockScreen: nil, isLocked: false)
        #expect(unlocked == LiveWallpaperPlan(desktopVideo: video, lockScreenVideo: nil, systemWallpaper: video))

        let locked = LiveWallpaperPlan.resolve(desktop: video, lockScreen: nil, isLocked: true)
        #expect(locked == LiveWallpaperPlan(desktopVideo: video, lockScreenVideo: video, systemWallpaper: video))
    }

    @Test("Lock screen media only applies while locked")
    func lockScreenOnly() {
        #expect(LiveWallpaperPlan.resolve(desktop: nil, lockScreen: video, isLocked: false) == LiveWallpaperPlan())
        #expect(
            LiveWallpaperPlan.resolve(desktop: nil, lockScreen: video, isLocked: true)
                == LiveWallpaperPlan(desktopVideo: nil, lockScreenVideo: video, systemWallpaper: video)
        )
        #expect(
            LiveWallpaperPlan.resolve(desktop: nil, lockScreen: image, isLocked: true)
                == LiveWallpaperPlan(desktopVideo: nil, lockScreenVideo: nil, systemWallpaper: image)
        )
    }

    @Test("A separate lock screen wallpaper wins while locked")
    func separateWallpapers() {
        let locked = LiveWallpaperPlan.resolve(desktop: otherVideo, lockScreen: image, isLocked: true)
        #expect(locked == LiveWallpaperPlan(desktopVideo: otherVideo, lockScreenVideo: nil, systemWallpaper: image))

        let unlocked = LiveWallpaperPlan.resolve(desktop: image, lockScreen: video, isLocked: false)
        #expect(unlocked == LiveWallpaperPlan(desktopVideo: nil, lockScreenVideo: nil, systemWallpaper: image))
    }

    @Test("Settings normalise into desktop and lock screen paths")
    func configurationFromSettings() {
        var settings = Settings()
        #expect(LiveWallpaperConfiguration(settings: settings).desktopPath == nil)
        #expect(LiveWallpaperConfiguration(settings: settings).lockScreenPath == nil)

        settings.lockScreenCustomWallpaperEnabled = true
        settings.lockScreenCustomWallpaperPath = "/lock.mov"
        #expect(LiveWallpaperConfiguration(settings: settings).lockScreenPath == "/lock.mov")
        #expect(LiveWallpaperConfiguration(settings: settings).desktopPath == nil)

        settings.lockScreenKeepWallpaperAfterUnlock = true
        #expect(LiveWallpaperConfiguration(settings: settings).desktopPath == "/lock.mov")

        settings.desktopWallpaperEnabled = true
        settings.desktopWallpaperPath = ""
        #expect(LiveWallpaperConfiguration(settings: settings).desktopPath == "/lock.mov")

        settings.desktopWallpaperPath = "/desk.mp4"
        #expect(LiveWallpaperConfiguration(settings: settings).desktopPath == "/desk.mp4")

        settings.lockScreenCustomWallpaperEnabled = false
        #expect(LiveWallpaperConfiguration(settings: settings).lockScreenPath == nil)
        #expect(LiveWallpaperConfiguration(settings: settings).desktopPath == "/desk.mp4")

    }

    @Test("Only the user's own wallpapers are captured as originals")
    func adoptsOriginals() {
        let userWallpaper = URL(fileURLWithPath: "/Users/someone/Pictures/beach.heic")
        let applied = URL(fileURLWithPath: "/Users/someone/Movies/ocean-still.jpg")
        let poster = WallpaperAssetStore.postersDirectory.appendingPathComponent("abc.jpg")

        #expect(SystemWallpaperOverride.shouldAdoptAsOriginal(current: userWallpaper, applied: nil, target: poster))
        #expect(SystemWallpaperOverride.shouldAdoptAsOriginal(current: userWallpaper, applied: applied, target: poster))
        #expect(!SystemWallpaperOverride.shouldAdoptAsOriginal(current: applied, applied: applied, target: poster))
        #expect(!SystemWallpaperOverride.shouldAdoptAsOriginal(current: poster, applied: nil, target: applied))
        #expect(!SystemWallpaperOverride.shouldAdoptAsOriginal(current: userWallpaper, applied: nil, target: userWallpaper))
    }

    @Test("Override state survives a round trip to disk")
    func overrideStateCodable() throws {
        let snapshot = SystemWallpaperOverride.DisplaySnapshot(
            url: URL(fileURLWithPath: "/Users/someone/Pictures/beach.heic"),
            options: [.imageScaling: NSNumber(value: 3), .allowClipping: NSNumber(value: true)]
        )
        #expect(snapshot.imageScaling == 3)
        #expect(snapshot.allowClipping == true)

        let state = SystemWallpaperOverride.State(
            originals: ["UUID-1": snapshot],
            appliedURL: URL(fileURLWithPath: "/tmp/poster.jpg"),
            appliedScaling: .fit
        )
        let decoded = try JSONDecoder().decode(
            SystemWallpaperOverride.State.self,
            from: JSONEncoder().encode(state)
        )
        #expect(decoded == state)
    }

    @Test("Desktop coverage counts the union of windows over the visible area")
    func desktopCoverage() {
        let screen = CGRect(x: 0, y: 0, width: 1600, height: 1000)
        let coverage = DesktopLiveWallpaperController.coveredFraction(of:by:columns:rows:)

        #expect(coverage(screen, [], 32, 20) == 0)
        #expect(coverage(screen, [screen], 32, 20) == 1)
        #expect(coverage(screen, [screen.insetBy(dx: -10, dy: -10)], 32, 20) == 1)
        let halves = [
            CGRect(x: 0, y: 0, width: 800, height: 1000),
            CGRect(x: 800, y: 0, width: 800, height: 1000)
        ]
        #expect(coverage(screen, halves, 32, 20) == 1)
        #expect(coverage(screen, [CGRect(x: 400, y: 250, width: 800, height: 500)], 32, 20) == 0.25)
        #expect(coverage(screen, [CGRect(x: 400, y: 250, width: 800, height: 500)], 32, 20) < DesktopLiveWallpaperController.coveredThreshold)
        #expect(coverage(screen, [CGRect(x: 1600, y: 0, width: 1600, height: 1000)], 32, 20) == 0)
    }

    @Test("Scaling maps onto video gravity")
    func scalingGravity() {
        #expect(WallpaperScaling.fill.videoGravity == .resizeAspectFill)
        #expect(WallpaperScaling.fit.videoGravity == .resizeAspect)
        #expect(WallpaperScaling.stretch.videoGravity == .resize)
    }

    @Test("Lock screen video stays behind the login UI space")
    func lockScreenSpaceLayering() {
        let wallpaper = LockScreenSpaceLevel.lockScreenWallpaper
        let loginUI = LockScreenSpaceLevel.kCGSSpaceAbsoluteLevelScreenLock.rawValue

        #expect(wallpaper == loginUI - 1)
        #expect(loginUI < LockScreenSpaceLevel.kSLSSpaceAbsoluteLevelNotificationCenterAtScreenLock.rawValue)
    }

    @Test("An inactive session does not pause lock-screen playback")
    func lockScreenPlaybackPolicy() {
        #expect(LiveWallpaperManager.shouldSuspendPlayback(for: [.sessionInactive], isLocked: false))
        #expect(!LiveWallpaperManager.shouldSuspendPlayback(for: [.sessionInactive], isLocked: true))
        #expect(LiveWallpaperManager.shouldSuspendPlayback(for: [.displaysAsleep], isLocked: true))
        #expect(
            LiveWallpaperManager.shouldSuspendPlayback(
                for: [.sessionInactive, .thermalPressure],
                isLocked: true
            )
        )
    }
}