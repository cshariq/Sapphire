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
    var rotationAngle: CGFloat = 0
    var sessionEpoch: UInt64 = 0

    func makeNSView(context: Context) -> NSView {
        let host = MirrorPreviewHostView()
        host.wantsLayer = true
        host.layer = CALayer()
        attachPreview(to: host)
        host.boundSessionEpoch = sessionEpoch
        return host
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let host = nsView as? MirrorPreviewHostView else { return }
        if host.boundSessionEpoch != sessionEpoch || host.previewLayer?.session !== session {
            host.previewLayer?.removeFromSuperlayer()
            host.previewLayer = nil
            attachPreview(to: host)
            host.boundSessionEpoch = sessionEpoch
        }
        host.previewLayer?.frame = host.bounds
        if let preview = host.previewLayer {
            applyMirroring(to: preview)
            applyRotation(to: preview)
        }
    }

    private func attachPreview(to host: MirrorPreviewHostView) {
        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        preview.backgroundColor = NSColor.black.cgColor
        host.previewLayer = preview
        host.layer?.addSublayer(preview)
        applyMirroring(to: preview)
        applyRotation(to: preview)
    }

    private func applyMirroring(to layer: AVCaptureVideoPreviewLayer) {
        if let connection = layer.connection {
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = flipHorizontally
            }
        }
    }

    private func applyRotation(to layer: AVCaptureVideoPreviewLayer) {
        guard let connection = layer.connection else { return }
        let angle = rotationAngle.truncatingRemainder(dividingBy: 360)
        guard connection.isVideoRotationAngleSupported(angle) else { return }
        connection.videoRotationAngle = angle
    }
}

final class MirrorPreviewHostView: NSView {
    var previewLayer: AVCaptureVideoPreviewLayer?
    var boundSessionEpoch: UInt64 = 0

    override func layout() {
        super.layout()
        guard let layer = layer, let preview = previewLayer else { return }
        preview.frame = layer.bounds
    }
}