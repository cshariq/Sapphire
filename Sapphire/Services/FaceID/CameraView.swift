//
//  CameraView.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-09-13.
//

import SwiftUI
import AVFoundation

struct CameraView: NSViewRepresentable {
    var session: AVCaptureSession

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true

        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        view.layer = previewLayer

        previewLayer.frame = view.bounds
        previewLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]

        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}