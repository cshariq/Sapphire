//
//  SnapPreviewManager.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-08-24.
//

import SwiftUI
import AppKit

@MainActor
class SnapPreviewManager {
    static let shared = SnapPreviewManager()

    private var previewWindow: NSWindow?

    private init() {}

    func showPreview(for zone: SnapZone) {
        if previewWindow == nil {
            createPreviewWindow()
        }

        guard let screen = NSScreen.main else { return }
        let visibleFrame = screen.visibleFrame

        let targetFrame = CGRect(
            x: visibleFrame.origin.x + visibleFrame.width * zone.x,
            y: visibleFrame.origin.y + visibleFrame.height * (1 - zone.y - zone.height),
            width: visibleFrame.width * zone.width,
            height: visibleFrame.height * zone.height
        )

        if !(previewWindow?.isVisible ?? false) {
            previewWindow?.contentView?.alphaValue = 0
            previewWindow?.setFrame(targetFrame, display: true)
            previewWindow?.orderFront(nil)
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            previewWindow?.animator().setFrame(targetFrame, display: true)
            previewWindow?.contentView?.animator().alphaValue = 1.0
        }
    }

    func hidePreview() {
        guard let window = previewWindow, window.isVisible else { return }

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.1
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.contentView?.animator().alphaValue = 0
        }, completionHandler: {
            window.orderOut(nil)
        })
    }

    private func createPreviewWindow() {
        let window = NSWindow(
            contentRect: .zero,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.level = .mainMenu - 1
        window.backgroundColor = .clear
        window.isOpaque = false
        window.ignoresMouseEvents = true

        let previewView = SnapPreviewView()
        let hostingView = NSHostingView(rootView: previewView)

        window.contentView = hostingView
        self.previewWindow = window
    }
}

fileprivate struct SnapPreviewView: View {
    var body: some View {
        VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(1)
    }
}