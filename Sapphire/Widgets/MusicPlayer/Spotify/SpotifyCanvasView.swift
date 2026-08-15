//
//  SpotifyCanvasView.swift
//  Sapphire
//

import SwiftUI
import AVFoundation
import AppKit

/// Loops Canvas video via AVPlayerLayer (no AVKit chrome — avoids volume-slider constraint spam in 60pt frames).
struct SpotifyCanvasView: View {
    let canvasURL: URL
    @StateObject private var model = CanvasPlayerModel()

    var body: some View {
        CanvasPlayerRepresentable(player: model.player)
            .onAppear { model.play(url: canvasURL) }
            .onChange(of: canvasURL) { _, newURL in
                model.play(url: newURL)
            }
            .onDisappear { model.stop() }
    }
}

@MainActor
private final class CanvasPlayerModel: ObservableObject {
    let player = AVPlayer()
    private var loopObserver: NSObjectProtocol?
    private var currentURL: URL?

    func play(url: URL) {
        guard currentURL != url else {
            player.play()
            return
        }
        stop()
        currentURL = url
        let item = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: item)
        player.isMuted = true
        player.actionAtItemEnd = .none
        loopObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            self?.player.seek(to: .zero)
            self?.player.play()
        }
        player.play()
    }

    func stop() {
        if let loopObserver {
            NotificationCenter.default.removeObserver(loopObserver)
        }
        loopObserver = nil
        player.pause()
        player.replaceCurrentItem(with: nil)
        currentURL = nil
    }
}

private struct CanvasPlayerRepresentable: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> CanvasPlayerNSView {
        CanvasPlayerNSView(player: player)
    }

    func updateNSView(_ nsView: CanvasPlayerNSView, context: Context) {
        nsView.playerLayer.player = player
    }
}

private final class CanvasPlayerNSView: NSView {
    let playerLayer = AVPlayerLayer()

    init(player: AVPlayer) {
        super.init(frame: .zero)
        wantsLayer = true
        playerLayer.player = player
        playerLayer.videoGravity = .resizeAspectFill
        layer?.addSublayer(playerLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        playerLayer.frame = bounds
    }
}

struct SpotifyAccountBadge: View {
    let accountInfo: SpotifyAccountInfo?

    var body: some View {
        // Only surface Premium — Free label removed per design.
        if let info = accountInfo, info.isPremium {
            Text("PREMIUM")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.green.opacity(0.25))
                .foregroundColor(.green)
                .clipShape(Capsule())
        }
    }
}
