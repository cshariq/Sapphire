//
//  LaunchpadInputInterceptor.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-09-16.
//

import AppKit
import Carbon.HIToolbox

extension Notification.Name {
    static let userStartedTypingInLaunchpad = Notification.Name("userStartedTypingInLaunchpad")
}

class LaunchpadInputInterceptor {
    private var tapToken: GlobalEventTap.Token?
    private let stateLock = NSLock()
    private var isMonitoring = false
    private var isAwaitingFirstTypingKey = false

    var dockFrame: CGRect = .zero
    var folderFrame: CGRect = .zero

    private let nonTypingKeyCodes: Set<Int64> = [
        Int64(kVK_Shift), Int64(kVK_Control), Int64(kVK_Option), Int64(kVK_Command), Int64(kVK_CapsLock),
        Int64(kVK_Function), Int64(kVK_Escape), Int64(kVK_F1), Int64(kVK_F2), Int64(kVK_F3), Int64(kVK_F4), Int64(kVK_F5),
        Int64(kVK_F6), Int64(kVK_F7), Int64(kVK_F8), Int64(kVK_F9), Int64(kVK_F10), Int64(kVK_F11), Int64(kVK_F12),
        Int64(kVK_F13), Int64(kVK_F14), Int64(kVK_F15), Int64(kVK_F16), Int64(kVK_F17), Int64(kVK_F18), Int64(kVK_F19), Int64(kVK_F20),
        Int64(kVK_Home), Int64(kVK_End), Int64(kVK_PageUp), Int64(kVK_PageDown),
        Int64(kVK_LeftArrow), Int64(kVK_RightArrow), Int64(kVK_UpArrow), Int64(kVK_DownArrow)
    ]

    func start() {
        guard !isMonitoring else { return }
        isMonitoring = true
        stateLock.withLock { isAwaitingFirstTypingKey = true }
        registerTrustAwareness()

        guard AccessibilityTrustMonitor.isCurrentlyTrusted() else {
            print("[LaunchpadInputInterceptor] Accessibility not trusted; event tap deferred until permission is granted.")
            return
        }
        installTap()
    }

    private func installTap() {
        // Idempotent: `start()` and the trust-monitor reinstall can both land
        // here. Keep exactly one shared-pipeline registration.
        guard tapToken == nil else { return }

        let eventTypes: [CGEventType] = [
            .keyDown, .flagsChanged
        ]
        let eventsToMonitor = eventTypes.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        tapToken = GlobalEventTap.shared.register(
            name: "LaunchpadInputInterceptor",
            mask: eventsToMonitor,
            // This used to be a listen-only tap, so observe before any shared
            // handler can swallow the first typing event.
            priority: EventTapPriority.filter - 1
        ) { [weak self] type, event in
            self?.handle(event: event, type: type)
            return .pass
        }
        print("[LaunchpadInputInterceptor] Smart event filter enabled.")
    }

    /// Lets `AccessibilityTrustMonitor` tear down and reinstall the tap. If the
    /// launchpad was closed while permission was revoked, `isMonitoring` is
    /// already false and the reinstall is a no-op until the next `start()`.
    private func registerTrustAwareness() {
        AccessibilityTrustMonitor.shared.register(name: "LaunchpadInputInterceptor") { [weak self] in
            self?.stop()
        } reinstall: { [weak self] in
            guard let self, self.isMonitoring else { return }
            self.installTap()
        }
    }

    func stop() {
        guard isMonitoring else { return }
        if let tapToken {
            GlobalEventTap.shared.unregister(tapToken)
        }
        tapToken = nil
        isMonitoring = false
        stateLock.withLock { isAwaitingFirstTypingKey = false }
        folderFrame = .zero
        AccessibilityTrustMonitor.shared.unregister(name: "LaunchpadInputInterceptor")
        print("[LaunchpadInputInterceptor] Smart event filter disabled.")
    }

    private nonisolated func handle(event: CGEvent, type: CGEventType) {
        switch type {
        case .keyDown:
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            let shouldNotify = stateLock.withLock { () -> Bool in
                guard isAwaitingFirstTypingKey, !nonTypingKeyCodes.contains(keyCode) else { return false }
                isAwaitingFirstTypingKey = false
                return true
            }
            if shouldNotify {
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .userStartedTypingInLaunchpad, object: nil)
                }
            }
        default: break
        }
    }
}
