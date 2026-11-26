//
//  UnlockConfirmKeyListener.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-11-13
//

import Carbon.HIToolbox
import CoreGraphics
import Foundation
import IOKit.hid

/// Reports a key press on the lock screen, used to confirm a Face ID match.
///
/// The lock screen's password field turns on Secure Event Input, which hides almost every key from
/// other apps: event taps and `NSEvent` monitors get nothing, IOHIDManager gets only stray releases,
/// and the window server's key-state table masks every key except Return and keypad Enter. What
/// still moves for any key is the window server's "seconds since last key down", but only in
/// ~0.5 s steps and without saying which key. So:
/// - Return / keypad Enter confirm on release, read from the key-state table.
/// - Any other key (Space, a letter) confirms when the last-key-down time resets, about 0.5 s late.
/// Both need Input Monitoring. The press itself reaches the login window first; the unlock clears
/// whatever it typed into the password field.
final class UnlockConfirmKeyListener {
    private static let returnKeyCodes: [CGKeyCode] = [
        CGKeyCode(kVK_Return),
        CGKeyCode(kVK_ANSI_KeypadEnter),
    ]
    /// Fast enough to catch a quick Return tap (a press is held ~60 ms or more); runs only during the short confirm window.
    private static let pollInterval: DispatchTimeInterval = .milliseconds(8)

    private let onConfirm: () -> Void
    private var pollTimer: DispatchSourceTimer?
    private var hasFired = false
    /// Return keys seen down. Keys already held when listening starts go in `heldAtStart` and are
    /// ignored until released, so a held key can't confirm a match that came later.
    private var returnDown = Set<CGKeyCode>()
    private var heldAtStart = Set<CGKeyCode>()
    private var lastKeyDownAge: CFTimeInterval = 0

    static var hasPermission: Bool {
        IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }

    /// Shows the Input Monitoring prompt the first time; afterwards returns the current answer.
    @discardableResult
    static func requestPermission() -> Bool {
        IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
    }

    init(onConfirm: @escaping () -> Void) {
        self.onConfirm = onConfirm
    }

    deinit { stop() }

    /// Starts polling on the main queue. Returns false without Input Monitoring.
    @discardableResult
    func start() -> Bool {
        guard pollTimer == nil else { return true }
        guard Self.hasPermission else { return false }
        hasFired = false
        returnDown.removeAll()
        heldAtStart = Set(Self.returnKeyCodes.filter { CGEventSource.keyState(.hidSystemState, key: $0) })
        lastKeyDownAge = Self.keyDownAge()

        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + Self.pollInterval, repeating: Self.pollInterval, leeway: .milliseconds(2))
        timer.setEventHandler { [weak self] in self?.poll() }
        pollTimer = timer
        timer.resume()
        return true
    }

    func stop() {
        pollTimer?.cancel()
        pollTimer = nil
        returnDown.removeAll()
        heldAtStart.removeAll()
    }

    private static func keyDownAge() -> CFTimeInterval {
        CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: .keyDown)
    }

    private func poll() {
        guard !hasFired else { return }

        for key in Self.returnKeyCodes {
            if CGEventSource.keyState(.hidSystemState, key: key) {
                if !heldAtStart.contains(key) { returnDown.insert(key) }
            } else {
                heldAtStart.remove(key)
                if returnDown.remove(key) != nil { return fire() }
            }
        }

        // The age only grows between presses, so any drop means a new key went down.
        let age = Self.keyDownAge()
        defer { lastKeyDownAge = age }
        if age < lastKeyDownAge { fire() }
    }

    private func fire() {
        guard !hasFired else { return }
        hasFired = true
        stop()
        onConfirm()
    }
}
