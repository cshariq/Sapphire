import AppKit
import os

/// Tracks whether one of Sapphire's own windows has keyboard focus in a text view, as a flag
/// global event taps can read off the main thread. The notch panel never makes Sapphire the
/// frontmost app, so taps can't use that to tell the user is typing into Notes, Blip and so on.
@MainActor
final class TextInputFocusTracker {
    static let shared = TextInputFocusTracker()

    private nonisolated static let focused = OSAllocatedUnfairLock(initialState: false)

    /// True while a Sapphire key window's first responder is an editable text view. Safe from any thread.
    nonisolated static var isTextInputFocused: Bool { focused.withLock { $0 } }

    private var started = false
    private var observers: [NSObjectProtocol] = []
    private var responderObservation: NSKeyValueObservation?

    private init() {}

    func start() {
        guard !started else { return }
        started = true
        let center = NotificationCenter.default
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.keyWindowChanged() }
            })
        }
        keyWindowChanged()
    }

    private func keyWindowChanged() {
        responderObservation = nil
        guard let window = NSApp.keyWindow else {
            Self.focused.withLock { $0 = false }
            return
        }
        responderObservation = window.observe(\.firstResponder, options: [.initial, .new]) { window, _ in
            let editing = (window.firstResponder as? NSTextView).map { $0.isEditable } ?? false
            Self.focused.withLock { $0 = editing }
        }
    }
}
