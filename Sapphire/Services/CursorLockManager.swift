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
    private var lockedY: CGFloat = 0

    private init() {
        // Monitor global flag changes to detect Caps Lock state.
        NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            guard let self = self else { return }
            let capsOn = event.modifierFlags.contains(.capsLock)
            // Respect the user setting.
            let settingEnabled = SettingsModel.shared.settings.capsLockHorizontalLockEnabled
            self.lockEnabled = capsOn && settingEnabled
        }
        // Monitor mouse movements globally to enforce the lock.
        NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
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
