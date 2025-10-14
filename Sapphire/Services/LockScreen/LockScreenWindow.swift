//
//  LockScreenWindow.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-09-11.
//

import AppKit

class TopmostWindow: NSWindow {
    override init(
        contentRect: NSRect,
        styleMask: NSWindow.StyleMask,
        backing: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(
            contentRect: contentRect,
            styleMask: styleMask,
            backing: backing,
            defer: flag
        )

        isOpaque = false
        alphaValue = 1
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        backgroundColor = NSColor.clear
        isMovable = false
        collectionBehavior = [
            .fullScreenAuxiliary,
            .stationary,
            .canJoinAllSpaces,
            .ignoresCycle,
        ]
        hasShadow = false
        canBecomeVisibleWithoutLogin = true
        level = .init(rawValue: .init(Int32.max - 2))
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }
}

class TopmostWindowController: NSWindowController {
    init(contentRect: NSRect) {
        let window = TopmostWindow(
            contentRect: contentRect,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) { fatalError() }
}