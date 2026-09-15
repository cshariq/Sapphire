//
//  LiveWallpaperWindow.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-15.
//

import AppKit
import AVFoundation

final class LiveWallpaperWindow: NSWindow {
    let wallpaperView: LiveWallpaperView

    init(frame: NSRect, level: NSWindow.Level) {
        wallpaperView = LiveWallpaperView(frame: NSRect(origin: .zero, size: frame.size))
        super.init(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        animationBehavior = .none
        isExcludedFromWindowsMenu = true
        canBecomeVisibleWithoutLogin = true
        self.level = level
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        contentView = wallpaperView
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class LiveWallpaperView: NSView {
    var onVideoVisible: (() -> Void)?

    private var playerLayer: AVPlayerLayer?
    private var readyObservation: NSKeyValueObservation?
    private var overlayView: NSView?
    private var opaqueWorkItem: DispatchWorkItem?
    private(set) var isVideoVisible = false

    private static let fadeInDuration: CFTimeInterval = 0.6

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        autoresizingMask = [.width, .height]
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var wantsUpdateLayer: Bool { true }
    override var isOpaque: Bool { false }

    func attach(player: AVPlayer?, scaling: WallpaperScaling) {
        if let playerLayer, playerLayer.player === player, player != nil {
            if playerLayer.videoGravity != scaling.videoGravity {
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                playerLayer.videoGravity = scaling.videoGravity
                CATransaction.commit()
            }
            return
        }

        detachPlayer()
        guard let player, let hostLayer = layer else { return }

        let newLayer = AVPlayerLayer(player: player)
        newLayer.videoGravity = scaling.videoGravity
        newLayer.frame = bounds
        newLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        newLayer.backgroundColor = NSColor.clear.cgColor
        newLayer.opacity = 0
        newLayer.contentsScale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        newLayer.actions = ["bounds": NSNull(), "position": NSNull(), "contents": NSNull()]
        hostLayer.insertSublayer(newLayer, at: 0)
        playerLayer = newLayer

        readyObservation = newLayer.observe(\.isReadyForDisplay, options: [.initial, .new]) { [weak self] layer, _ in
            guard layer.isReadyForDisplay else { return }
            DispatchQueue.main.async {
                self?.showVideo(for: layer)
            }
        }
    }

    func detachPlayer() {
        readyObservation = nil
        opaqueWorkItem?.cancel()
        opaqueWorkItem = nil
        playerLayer?.player = nil
        playerLayer?.removeFromSuperlayer()
        playerLayer = nil
        isVideoVisible = false
        setWindowOpaque(false)
    }

    func setOverlay(_ view: NSView?) {
        guard view !== overlayView else { return }
        overlayView?.removeFromSuperview()
        overlayView = view
        guard let view else { return }
        view.frame = bounds
        view.autoresizingMask = [.width, .height]
        addSubview(view)
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        guard let scale = window?.backingScaleFactor else { return }
        playerLayer?.contentsScale = scale
    }

    private func showVideo(for layer: AVPlayerLayer) {
        guard layer === playerLayer, !isVideoVisible else { return }
        isVideoVisible = true

        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        fade.duration = Self.fadeInDuration
        fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.opacity = 1
        layer.add(fade, forKey: "liveWallpaperFadeIn")

        let work = DispatchWorkItem { [weak self] in
            guard let self, self.isVideoVisible else { return }
            self.setWindowOpaque(true)
        }
        opaqueWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.fadeInDuration + 0.05, execute: work)

        onVideoVisible?()
    }

    private func setWindowOpaque(_ opaque: Bool) {
        guard let window, window.isOpaque != opaque else { return }
        window.backgroundColor = opaque ? .black : .clear
        window.isOpaque = opaque
    }
}