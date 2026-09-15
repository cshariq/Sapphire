//
//  DesktopLiveWallpaperController.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-15.
//

import AppKit

@MainActor
final class DesktopLiveWallpaperController {
    static var windowLevel: NSWindow.Level {
        NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
    }

    nonisolated static let coveredThreshold = 0.97
    private static let coverageCheckInterval: TimeInterval = 5

    private var media: WallpaperMedia?
    private var scaling: WallpaperScaling = .fill
    private var source: LiveWallpaperVideoSource?
    private var windows: [CGDirectDisplayID: LiveWallpaperWindow] = [:]
    private var occlusionObservers: [CGDirectDisplayID: NSObjectProtocol] = [:]
    private var screenObserver: NSObjectProtocol?
    private var isScreenReconcileScheduled = false
    private var isSessionLocked = false
    private var playbackFailed = false
    private var isDesktopCovered = false
    private var coverageTimer: Timer?
    private var coverageObservers: [NSObjectProtocol] = []
    private var isCoverageCheckScheduled = false

    var isShowing: Bool { !windows.isEmpty }

    func show(_ newMedia: WallpaperMedia?, scaling newScaling: WallpaperScaling) {
        let newMedia = newMedia?.isVideo == true ? newMedia : nil
        let mediaChanged = newMedia != media
        guard mediaChanged || newScaling != scaling else { return }

        media = newMedia
        scaling = newScaling

        if mediaChanged {
            playbackFailed = false
            tearDownWindows()
            releaseSource()
        }

        guard let newMedia, !playbackFailed else {
            tearDownWindows()
            releaseSource()
            stopObservingScreens()
            return
        }

        if source == nil {
            source = LiveWallpaperVideoSource.acquire(newMedia.url, client: self) { [weak self] in
                self?.handlePlaybackFailure()
            }
        }
        startObservingScreens()
        reconcileWindows()
    }

    func setSessionLocked(_ locked: Bool) {
        guard locked != isSessionLocked else { return }
        isSessionLocked = locked
        if locked {
            for window in windows.values {
                window.wallpaperView.detachPlayer()
            }
            updatePlayback()
        } else {
            reconcileWindows()
        }
    }

    func tearDown() {
        media = nil
        playbackFailed = false
        tearDownWindows()
        releaseSource()
        stopObservingScreens()
    }

    // MARK: - Windows

    private func reconcileWindows() {
        guard let source else { return }
        guard !isSessionLocked else {
            updatePlayback()
            return
        }
        var stale = Set(windows.keys)

        for screen in NSScreen.screens {
            let displayID = Self.displayID(of: screen)
            stale.remove(displayID)

            let window = windows[displayID] ?? makeWindow(for: screen, displayID: displayID)
            if window.frame != screen.frame {
                window.setFrame(screen.frame, display: false)
            }
            window.wallpaperView.attach(player: source.player, scaling: scaling)
            if !window.isVisible {
                window.orderFrontRegardless()
            }
        }

        for displayID in stale {
            removeWindow(for: displayID)
        }
        updatePlayback()
    }

    private func makeWindow(for screen: NSScreen, displayID: CGDirectDisplayID) -> LiveWallpaperWindow {
        let window = LiveWallpaperWindow(frame: screen.frame, level: Self.windowLevel)
        occlusionObservers[displayID] = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updatePlayback()
            }
        }
        windows[displayID] = window
        return window
    }

    private func removeWindow(for displayID: CGDirectDisplayID) {
        if let observer = occlusionObservers.removeValue(forKey: displayID) {
            NotificationCenter.default.removeObserver(observer)
        }
        guard let window = windows.removeValue(forKey: displayID) else { return }
        window.wallpaperView.detachPlayer()
        window.orderOut(nil)
    }

    private func tearDownWindows() {
        for displayID in Array(windows.keys) {
            removeWindow(for: displayID)
        }
    }

    private func releaseSource() {
        source?.release(client: self)
        source = nil
    }

    private var isEligibleToPlay: Bool {
        source != nil
            && !isSessionLocked
            && windows.values.contains { $0.occlusionState.contains(.visible) }
    }

    private func updatePlayback() {
        if isEligibleToPlay {
            if coverageTimer == nil {
                startCoverageMonitoring()
                isDesktopCovered = Self.desktopIsCovered(on: NSScreen.screens)
            }
        } else {
            stopCoverageMonitoring()
            isDesktopCovered = false
        }
        source?.setWantsPlayback(isEligibleToPlay && !isDesktopCovered, client: self)
    }

    // MARK: - Coverage

    private func startCoverageMonitoring() {
        guard coverageTimer == nil else { return }
        let timer = Timer(timeInterval: Self.coverageCheckInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshCoverage()
            }
        }
        timer.tolerance = 1.5
        RunLoop.main.add(timer, forMode: .default)
        coverageTimer = timer

        let workspace = NSWorkspace.shared.notificationCenter
        for name in [
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.activeSpaceDidChangeNotification,
            NSWorkspace.didHideApplicationNotification,
            NSWorkspace.didUnhideApplicationNotification
        ] {
            coverageObservers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.scheduleCoverageCheck()
                }
            })
        }
    }

    private func stopCoverageMonitoring() {
        coverageTimer?.invalidate()
        coverageTimer = nil
        let workspace = NSWorkspace.shared.notificationCenter
        for observer in coverageObservers {
            workspace.removeObserver(observer)
        }
        coverageObservers.removeAll()
    }

    private func scheduleCoverageCheck() {
        guard !isCoverageCheckScheduled else { return }
        isCoverageCheckScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self else { return }
            self.isCoverageCheckScheduled = false
            self.refreshCoverage()
        }
    }

    private func refreshCoverage() {
        guard isEligibleToPlay else { return }
        let covered = Self.desktopIsCovered(on: NSScreen.screens)
        guard covered != isDesktopCovered else { return }
        isDesktopCovered = covered
        source?.setWantsPlayback(!covered, client: self)
    }

    private static func desktopIsCovered(on screens: [NSScreen]) -> Bool {
        guard let primaryHeight = screens.first?.frame.maxY,
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return false
        }
        let floatingLevel = Int(CGWindowLevelForKey(.floatingWindow))
        let rects: [CGRect] = list.compactMap { info in
            guard let layer = info[kCGWindowLayer as String] as? Int,
                  (0...floatingLevel).contains(layer),
                  (info[kCGWindowAlpha as String] as? Double ?? 1) >= 0.95,
                  let boundsDictionary = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDictionary as CFDictionary) else {
                return nil
            }
            return CGRect(x: bounds.minX, y: primaryHeight - bounds.maxY, width: bounds.width, height: bounds.height)
        }
        return screens.allSatisfy { coveredFraction(of: $0.visibleFrame, by: rects) >= coveredThreshold }
    }

    nonisolated static func coveredFraction(of area: CGRect, by rects: [CGRect], columns: Int = 32, rows: Int = 20) -> Double {
        guard area.width > 0, area.height > 0, columns > 0, rows > 0 else { return 1 }
        let relevant = rects.filter { $0.intersects(area) }
        guard !relevant.isEmpty else { return 0 }
        if relevant.contains(where: { $0.contains(area) }) { return 1 }

        var covered = 0
        for row in 0..<rows {
            let y = area.minY + (Double(row) + 0.5) * area.height / Double(rows)
            for column in 0..<columns {
                let x = area.minX + (Double(column) + 0.5) * area.width / Double(columns)
                if relevant.contains(where: { $0.contains(CGPoint(x: x, y: y)) }) {
                    covered += 1
                }
            }
        }
        return Double(covered) / Double(rows * columns)
    }

    private func handlePlaybackFailure() {
        playbackFailed = true
        tearDownWindows()
        releaseSource()
        stopObservingScreens()
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
                self?.scheduleScreenReconcile()
            }
        }
    }

    private func stopObservingScreens() {
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
        screenObserver = nil
    }

    private func scheduleScreenReconcile() {
        guard !isScreenReconcileScheduled else { return }
        isScreenReconcileScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isScreenReconcileScheduled = false
            self.reconcileWindows()
        }
    }

    static func displayID(of screen: NSScreen) -> CGDirectDisplayID {
        let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        return CGDirectDisplayID(number?.uint32Value ?? 0)
    }
}