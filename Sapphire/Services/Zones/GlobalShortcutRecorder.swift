//
//  GlobalShortcutRecorder.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-08-12.
//

import AppKit
import SwiftUI
import Carbon.HIToolbox

private class ShortcutRecorderWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
class GlobalShortcutRecorder: ObservableObject {
    static let shared = GlobalShortcutRecorder()

    @Published private(set) var isRecording = false

    private var recorderWindow: NSWindow?
    private var onCapture: ((String, NSEvent.ModifierFlags) -> Void)?

    private init() {}

    func startRecording(onCapture: @escaping (String, NSEvent.ModifierFlags) -> Void) {
        guard !isRecording else { return }

        self.onCapture = onCapture
        self.isRecording = true

        guard let mainScreen = NSScreen.main else { stopRecording(); return }

        let window = ShortcutRecorderWindow(
            contentRect: mainScreen.frame, styleMask: [.borderless],
            backing: .buffered, defer: false
        )

        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .modalPanel
        window.hasShadow = false

        let captureView = KeyCaptureView(
            onCapture: { key, flags in
                self.onCapture?(key, flags)
                self.stopRecording()
            },
            onCancel: {
                self.stopRecording()
            }
        )

        window.contentView = NSHostingView(rootView: captureView)
        window.makeKeyAndOrderFront(nil)
        self.recorderWindow = window
    }

    func stopRecording() {
        recorderWindow?.orderOut(nil)
        recorderWindow = nil
        self.onCapture = nil
        self.isRecording = false
    }
}

fileprivate struct KeyCaptureView: NSViewRepresentable {
    var onCapture: (String, NSEvent.ModifierFlags) -> Void
    var onCancel: () -> Void

    func makeNSView(context: Context) -> CaptureNSView {
        let view = CaptureNSView()
        view.onCapture = self.onCapture
        view.onCancel = self.onCancel
        return view
    }

    func updateNSView(_ nsView: CaptureNSView, context: Context) {
        DispatchQueue.main.async {
            if nsView.window?.firstResponder != nsView {
                nsView.window?.makeFirstResponder(nsView)
            }
        }
    }
}

fileprivate class CaptureNSView: NSView {
    var onCapture: ((String, NSEvent.ModifierFlags) -> Void)?
    var onCancel: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    private let standaloneAllowedKeyCodes: Set<UInt16> = Set([
        UInt16(kVK_F1), UInt16(kVK_F2), UInt16(kVK_F3), UInt16(kVK_F4), UInt16(kVK_F5),
        UInt16(kVK_F6), UInt16(kVK_F7), UInt16(kVK_F8), UInt16(kVK_F9), UInt16(kVK_F10),
        UInt16(kVK_F11), UInt16(kVK_F12), UInt16(kVK_F13), UInt16(kVK_F14), UInt16(kVK_F15),
        UInt16(kVK_F16), UInt16(kVK_F17), UInt16(kVK_F18), UInt16(kVK_F19), UInt16(kVK_F20),
        kVK_MissionControl, kVK_Launchpad, kVK_Dictation, UInt16(kVK_Function)
    ])

    override func keyDown(with event: NSEvent) {
        if event.isARepeat { return }

        if event.keyCode == kVK_Escape {
            onCancel?(); return
        }

        let keyCode = event.keyCode
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        guard let keyString = KeyCodeTranslator.shared.string(for: keyCode, from: event) else {
            NSSound.beep(); return
        }

        print("[ShortcutRecorder] KeyDown Detected: \(KeyboardShortcutHelper.description(for: modifiers))\(keyString) (KeyCode: \(keyCode))")

        if modifiers.isEmpty && !standaloneAllowedKeyCodes.contains(keyCode) {
            NSSound.beep()
            return
        }

        onCapture?(keyString, modifiers)
    }
}