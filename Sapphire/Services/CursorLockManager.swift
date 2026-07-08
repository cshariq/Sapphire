//
//  CursorLockManager.swift
//  Sapphire
//
//  Created by OpenAI on 2026-07-08.
//
import AppKit
import SwiftUI
import CoreGraphics
import OSLog

/// A singleton manager that locks the cursor to a horizontal line (prevents vertical movement) when Caps Lock is pressed,
/// based on the user setting `capsLockHorizontalLockEnabled`.
final class CursorLockManager {
    static let shared = CursorLockManager()
    
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Sapphire", category: "CursorLock")

    private var lockEnabled: Bool = false {
        didSet {
            if lockEnabled {
                // Capture the current cursor Y coordinate when lock activates.
                lockedY = NSEvent.mouseLocation.y
                logger.debug("CapsLock horizontal lock enabled at Y: \(self.lockedY, privacy: .public)")
            } else {
                logger.debug("CapsLock horizontal lock disabled")
            }
        }
    }

    // Update lock state based on Caps Lock flag and user setting.
    private func updateLockState(capsOn: Bool) {
        let settingEnabled = SettingsModel.shared.settings.capsLockHorizontalLockEnabled
        self.lockEnabled = capsOn && settingEnabled
        logger.debug("CapsLock state changed: \(capsOn), lockEnabled: \(self.lockEnabled, privacy: .public)")
    }
    private var lockedY: CGFloat = 0

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    private init() {
        // Create a CGEventTap to monitor Caps Lock flag changes (low‑level).
        let flagsMask = CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        let tap = CGEvent.tapCreate(tap: .cghidEventTap,
                                    place: .headInsertEventTap,
                                    options: .defaultTap,
                                    eventsOfInterest: flagsMask,
                                    callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                                        guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
                                        let manager = Unmanaged<CursorLockManager>.fromOpaque(refcon).takeUnretainedValue()
                                        let capsOn = event.flags.contains(.maskAlphaShift)
                                        DispatchQueue.main.async {
                                            manager.updateLockState(capsOn: capsOn)
                                        }
                                        return Unmanaged.passUnretained(event)
                                    },
                                    userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()))
        if let tap = tap {
            self.eventTap = tap
            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            self.runLoopSource = source
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
        }
        // Monitor mouse movements and drags globally to enforce the lock.
        let mouseMask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
        NSEvent.addGlobalMonitorForEvents(matching: mouseMask) { [weak self] event in
            guard let self = self else { return }
            // Ensure the warp runs on the main thread.
            DispatchQueue.main.async {
                self.applyLockIfNeeded(to: event)
            }
        }
    }

    /// Apply the horizontal lock to a mouse moved event if locking is active.
    /// This method warps the cursor back to the locked Y coordinate while preserving X.
    func applyLockIfNeeded(to event: NSEvent) {
        guard lockEnabled else { return }
        // Get the current mouse location (global screen coordinates).
        let mouseLocation = NSEvent.mouseLocation
        // Warp the cursor to the locked Y, preserving the X coordinate.
        let target = CGPoint(x: mouseLocation.x, y: lockedY)
        logger.debug("Warping cursor to Y: \(self.lockedY, privacy: .public) (original Y: \(mouseLocation.y, privacy: .public))")
        CGWarpMouseCursorPosition(target)
    }
}
