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

private func launchpadEventTapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
    let interceptor = Unmanaged<LaunchpadInputInterceptor>.fromOpaque(refcon).takeUnretainedValue()
    return interceptor.handle(event: event, type: type)
}

class LaunchpadInputInterceptor {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
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
        isAwaitingFirstTypingKey = true
        registerTrustAwareness()

        guard AccessibilityTrustMonitor.isCurrentlyTrusted() else {
            print("[LaunchpadInputInterceptor] Accessibility not trusted; event tap deferred until permission is granted.")
            return
        }
        installTap()
    }

    private func installTap() {
        let eventTypes: [CGEventType] = [
            .keyDown, .flagsChanged
        ]
        let eventsToMonitor = eventTypes.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        let selfAsUnsafeMutableRawPointer = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

        eventTap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly, eventsOfInterest: eventsToMonitor, callback: launchpadEventTapCallback, userInfo: selfAsUnsafeMutableRawPointer)

        guard let eventTap = eventTap else {
            print("[LaunchpadInputInterceptor] FATAL ERROR: Failed to create event tap.")
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
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
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        isMonitoring = false
        isAwaitingFirstTypingKey = false
        folderFrame = .zero
        AccessibilityTrustMonitor.shared.unregister(name: "LaunchpadInputInterceptor")
        print("[LaunchpadInputInterceptor] Smart event filter disabled.")
    }

    fileprivate func handle(event: CGEvent, type: CGEventType) -> Unmanaged<CGEvent>? {
        switch type {
        case .keyDown:
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            if isAwaitingFirstTypingKey && !nonTypingKeyCodes.contains(keyCode) {
                self.isAwaitingFirstTypingKey = false
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .userStartedTypingInLaunchpad, object: nil)
                }
            }
            return Unmanaged.passUnretained(event)

        case .flagsChanged:
            return Unmanaged.passUnretained(event)

        default:
            return Unmanaged.passUnretained(event)
        }
    }
}
