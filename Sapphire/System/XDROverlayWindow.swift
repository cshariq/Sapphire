//
//  XDROverlayWindow.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-10-13.
//

import Cocoa
import MetalKit

class OverlayWindow: NSWindow {
    init() {
        let rect = NSRect(x: 0, y: 0, width: 1, height: 1)
        super.init(contentRect: rect, styleMask: [], backing: .buffered, defer: false)

        collectionBehavior = [.stationary, .ignoresCycle, .canJoinAllSpaces]
        level = .screenSaver
        isOpaque = false
        hasShadow = false
        backgroundColor = .clear
        ignoresMouseEvents = true
        isReleasedWhenClosed = true
        hidesOnDeactivate = false
    }

    func addMetalOverlay(screen: NSScreen) {
        let overlay = Overlay(frame: frame)
        overlay.autoresizingMask = [.width, .height]
        contentView = overlay
    }
}

final class OverlayWindowController: NSWindowController, NSWindowDelegate {
    public let screen: NSScreen

    init(screen: NSScreen) {
        self.screen = screen
        let overlayWindow = OverlayWindow()
        super.init(window: overlayWindow)
        overlayWindow.delegate = self
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func open(rect: NSRect) {
        guard let window = self.window as? OverlayWindow else { return }
        window.setFrame(rect, display: true)
        reposition(screen: screen)
        window.orderFrontRegardless()
        window.addMetalOverlay(screen: screen)
    }

    func reposition(screen: NSScreen) {
        var position = screen.frame.origin
        position.y += screen.frame.height - 1
        window?.setFrameOrigin(position)
    }
}