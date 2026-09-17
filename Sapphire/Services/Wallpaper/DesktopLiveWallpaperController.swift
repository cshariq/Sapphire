//
//  DesktopLiveWallpaperController.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-15.
//

import AppKit

@MainActor
final class DesktopLiveWallpaperController {
    private final class PlaybackClient {}

    static var windowLevel: NSWindow.Level {
        NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) - 1)
    }

    nonisolated static let coveredThreshold = 0.97
    private var media: WallpaperMedia?
    private var scaling: WallpaperScaling = .fill
    private var playbackMode: LiveWallpaperPlaybackMode = .adaptive
    private var sources: [CGDirectDisplayID: LiveWallpaperVideoSource] = [:]
    private var playbackClients: [CGDirectDisplayID: PlaybackClient] = [:]
    private var windows: [CGDirectDisplayID: LiveWallpaperWindow] = [:]
    private var occlusionObservers: [CGDirectDisplayID: NSObjectProtocol] = [:]
    private var screenObserver: NSObjectProtocol?
    private var isScreenReconcileScheduled = false
    private var isSessionLocked = false
    private var playbackFailed = false
    private var isDesktopCovered = false
    private var coverageChangeToken: SystemWindowChangeMonitor.Token?
    private var isCoverageCheckScheduled = false

    var isShowing: Bool { !windows.isEmpty }

    func show(
        _ newMedia: WallpaperMedia?,
        scaling newScaling: WallpaperScaling,
        playbackMode newPlaybackMode: LiveWallpaperPlaybackMode
    ) {
        let newMedia = newMedia?.isVideo == true ? newMedia : nil
        let mediaChanged = newMedia != media
        guard mediaChanged || newScaling != scaling || newPlaybackMode != playbackMode else { return }

        media = newMedia
        scaling = newScaling
        playbackMode = newPlaybackMode

        if mediaChanged {
            playbackFailed = false
            tearDownWindows()
        }

        guard newMedia != nil, !playbackFailed else {
            tearDownWindows()
            stopObservingScreens()
            return
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
        stopObservingScreens()
    }

    // MARK: - Windows

    private func reconcileWindows() {
        guard media != nil else { return }
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
            window.wallpaperView.attach(player: sources[displayID]?.player, scaling: scaling)
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
        if let media {
            let client = PlaybackClient()
            playbackClients[displayID] = client
            sources[displayID] = LiveWallpaperVideoSource.acquire(media.url, client: client) { [weak self] in
                self?.handlePlaybackFailure(on: displayID)
            }
        }
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
        if let source = sources.removeValue(forKey: displayID),
           let client = playbackClients.removeValue(forKey: displayID) {
            source.release(client: client)
        }
    }

    private func tearDownWindows() {
        for displayID in Array(windows.keys) {
            removeWindow(for: displayID)
        }
    }

    private var isEligibleToPlay: Bool {
        guard !sources.isEmpty, !isSessionLocked, !windows.isEmpty else { return false }
        switch playbackMode {
        case .always:
            return true
        case .adaptive:
            return windows.values.contains { $0.occlusionState.contains(.visible) }
        case .never:
            return false
        }
    }

    private func updatePlayback() {
        if playbackMode == .adaptive, isEligibleToPlay {
            if coverageChangeToken == nil {
                startCoverageMonitoring()
                isDesktopCovered = Self.desktopIsCovered(on: NSScreen.screens)
            }
        } else {
            stopCoverageMonitoring()
            isDesktopCovered = false
        }
        for (displayID, source) in sources {
            guard let client = playbackClients[displayID] else { continue }
            let windowVisible = windows[displayID]?.occlusionState.contains(.visible) == true
            let shouldPlay = !isSessionLocked
                && playbackMode != .never
                && (playbackMode == .always || windowVisible)
                && (playbackMode != .adaptive || !isDesktopCovered)
            source.setWantsPlayback(shouldPlay, client: client)
        }
    }

    // MARK: - Coverage

    private func startCoverageMonitoring() {
        guard coverageChangeToken == nil else { return }
        coverageChangeToken = SystemWindowChangeMonitor.shared.subscribe { [weak self] in
            self?.scheduleCoverageCheck()
        }
    }

    private func stopCoverageMonitoring() {
        if let coverageChangeToken {
            SystemWindowChangeMonitor.shared.unsubscribe(coverageChangeToken)
            self.coverageChangeToken = nil
        }
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
        updatePlayback()
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

    private func handlePlaybackFailure(on displayID: CGDirectDisplayID) {
        removeWindow(for: displayID)
        if sources.isEmpty {
            playbackFailed = true
            stopObservingScreens()
        }
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