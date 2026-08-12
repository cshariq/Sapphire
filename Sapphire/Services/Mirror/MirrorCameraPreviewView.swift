//
//  MirrorCameraPreviewView.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-11
//

import SwiftUI
import AVFoundation
import AppKit

struct MirrorCameraPreviewView: NSViewRepresentable {
    let session: AVCaptureSession
    var flipHorizontally: Bool = true

    func makeNSView(context: Context) -> NSView {
        let host = MirrorPreviewHostView()
        host.wantsLayer = true
        host.layer = CALayer()

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        preview.backgroundColor = NSColor.black.cgColor
        host.previewLayer = preview
        host.layer?.addSublayer(preview)

        applyMirroring(to: preview)

        return host
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let host = nsView as? MirrorPreviewHostView, let preview = host.previewLayer else { return }
        preview.frame = host.bounds
        applyMirroring(to: preview)
    }

    private func applyMirroring(to layer: AVCaptureVideoPreviewLayer) {
        if let connection = layer.connection {
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = flipHorizontally
            }
        }
    }
}

final class MirrorPreviewHostView: NSView {
    var previewLayer: AVCaptureVideoPreviewLayer?

    override func layout() {
        super.layout()
        guard let layer = layer, let preview = previewLayer else { return }
        preview.frame = layer.bounds
    }
}
