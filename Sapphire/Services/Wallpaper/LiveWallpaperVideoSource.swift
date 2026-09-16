//
//  LiveWallpaperVideoSource.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-15.
//

import AVFoundation
import AppKit

@MainActor
final class LiveWallpaperVideoSource {
    private struct Client {
        var wantsPlayback: Bool
        let onFailure: @MainActor () -> Void
    }

    private static var sources: [ObjectIdentifier: LiveWallpaperVideoSource] = [:]
    private static var isSuspended = false

    static func acquire(
        _ url: URL,
        client: AnyObject,
        onFailure: @escaping @MainActor () -> Void
    ) -> LiveWallpaperVideoSource {
        let source = LiveWallpaperVideoSource(url: url.standardizedFileURL)
        sources[ObjectIdentifier(source)] = source
        source.clients[ObjectIdentifier(client)] = Client(wantsPlayback: false, onFailure: onFailure)
        if source.hasFailed {
            DispatchQueue.main.async { onFailure() }
        }
        return source
    }

    static func setSuspended(_ suspended: Bool) {
        guard isSuspended != suspended else { return }
        isSuspended = suspended
        for source in sources.values {
            source.applyPlaybackState()
        }
    }

    static var activeSourceCount: Int { sources.count }

    let url: URL
    let player = AVQueuePlayer()

    private var looper: AVPlayerLooper?
    private var looperStatusObservation: NSKeyValueObservation?
    private var loadTask: Task<Void, Never>?
    private var clients: [ObjectIdentifier: Client] = [:]
    private(set) var hasFailed = false

    private init(url: URL) {
        self.url = url
        player.isMuted = true
        player.volume = 0
        player.preventsDisplaySleepDuringVideoPlayback = false
        player.audiovisualBackgroundPlaybackPolicy = .continuesIfPossible
        player.automaticallyWaitsToMinimizeStalling = true
        player.allowsExternalPlayback = false
        player.appliesMediaSelectionCriteriaAutomatically = false
        loadTask = Task { [weak self] in
            await self?.load()
        }
    }

    func setWantsPlayback(_ wants: Bool, client: AnyObject) {
        let id = ObjectIdentifier(client)
        guard let existing = clients[id], existing.wantsPlayback != wants else { return }
        clients[id]?.wantsPlayback = wants
        applyPlaybackState()
    }

    func release(client: AnyObject) {
        guard clients.removeValue(forKey: ObjectIdentifier(client)) != nil else { return }
        guard clients.isEmpty else {
            applyPlaybackState()
            return
        }
        loadTask?.cancel()
        loadTask = nil
        looperStatusObservation = nil
        looper?.disableLooping()
        looper = nil
        player.pause()
        player.removeAllItems()
        Self.sources.removeValue(forKey: ObjectIdentifier(self))
    }

    private func load() async {
        let asset = AVURLAsset(url: url)
        do {
            guard let track = try await asset.loadTracks(withMediaType: .video).first else {
                throw CocoaError(.fileReadCorruptFile)
            }
            let timeRange = try await track.load(.timeRange)
            guard timeRange.duration.isNumeric, timeRange.duration.seconds > 0.05 else {
                throw CocoaError(.fileReadCorruptFile)
            }

            guard !Task.isCancelled, !clients.isEmpty else { return }

            let item = AVPlayerItem(asset: asset)
            item.preferredForwardBufferDuration = 1
            item.preferredMaximumResolution = Self.maximumDisplayResolution
            let looper = AVPlayerLooper(player: player, templateItem: item)
            looperStatusObservation = looper.observe(\.status) { [weak self] looper, _ in
                guard looper.status == .failed else { return }
                let error = looper.error
                Task { @MainActor in
                    self?.markFailed(error)
                }
            }
            self.looper = looper
            applyPlaybackState()
        } catch {
            guard !Task.isCancelled else { return }
            markFailed(error)
        }
    }

    private func applyPlaybackState() {
        let shouldPlay = looper != nil
            && !hasFailed
            && !Self.isSuspended
            && clients.values.contains(where: \.wantsPlayback)
        if shouldPlay {
            if player.rate == 0 { player.play() }
        } else if player.rate != 0 {
            player.pause()
        }
    }

    private func markFailed(_ error: Error?) {
        guard !hasFailed else { return }
        hasFailed = true
        NSLog("[LiveWallpaper] Can't play \(url.lastPathComponent): \(error?.localizedDescription ?? "unknown error")")
        player.pause()
        let callbacks = clients.values.map(\.onFailure)
        for callback in callbacks {
            callback()
        }
    }

    private static var maximumDisplayResolution: CGSize {
        NSScreen.screens.reduce(.zero) { result, screen in
            let scale = screen.backingScaleFactor
            return CGSize(
                width: max(result.width, screen.frame.width * scale),
                height: max(result.height, screen.frame.height * scale)
            )
        }
    }
}