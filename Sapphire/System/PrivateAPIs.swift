//
//  PrivateAPIs.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-07-04.
//
//
//
//

import SwiftUI
import Cocoa
import AudioToolbox
import IOKit.hidsystem

// MARK: - Private API Type Definitions (Single Source of Truth)
internal typealias CGSConnectionID = Int32
internal typealias CGSSpaceID = UInt64
internal typealias CGError = Int32

// MARK: - CoreGraphics Services Private APIs (for Notch Window)
@_silgen_name("_CGSDefaultConnection")
internal func _CGSDefaultConnection() -> CGSConnectionID

@_silgen_name("CGSSpaceCreate")
fileprivate func CGSSpaceCreate(_ cid: CGSConnectionID, _ unknown: Int, _ options: NSDictionary?) -> CGSSpaceID
@_silgen_name("CGSSpaceDestroy")
fileprivate func CGSSpaceDestroy(_ cid: CGSConnectionID, _ space: CGSSpaceID)
@_silgen_name("CGSSpaceSetAbsoluteLevel")
fileprivate func CGSSpaceSetAbsoluteLevel(_ cid: CGSConnectionID, _ space: CGSSpaceID, _ level: Int)
@_silgen_name("CGSAddWindowsToSpaces")
fileprivate func CGSAddWindowsToSpaces(_ cid: CGSConnectionID, _ windows: NSArray, _ spaces: NSArray)
@_silgen_name("CGSRemoveWindowsFromSpaces")
fileprivate func CGSRemoveWindowsFromSpaces(_ cid: CGSConnectionID, _ windows: NSArray, _ spaces: NSArray)
@_silgen_name("CGSHideSpaces")
fileprivate func CGSHideSpaces(_ cid: CGSConnectionID, _ spaces: NSArray)
@_silgen_name("CGSShowSpaces")
fileprivate func CGSShowSpaces(_ cid: CGSConnectionID, _ spaces: NSArray)
@_silgen_name("CGSGetActiveSpace")
private func CGSGetActiveSpace(_ cid: CGSConnectionID) -> CGSSpaceID
@_silgen_name("CGSCopyManagedDisplaySpaces")
private func CGSCopyManagedDisplaySpaces(_ cid: CGSConnectionID) -> CFArray

@_silgen_name("CoreDockSendNotification")
internal func CoreDockSendNotification(_ notification: CFString, _ unknown: CInt) -> Void

// MARK: - DisplayServices Private APIs
@_silgen_name("DisplayServicesGetBrightness")
private func DisplayServicesGetBrightness(_ display: CGDirectDisplayID, _ brightness: UnsafeMutablePointer<Float>) -> Int32
@_silgen_name("DisplayServicesSetBrightness")
private func DisplayServicesSetBrightness(_ display: CGDirectDisplayID, _ brightness: Float) -> Int32

// MARK: - SwiftUI Private APIs
@_silgen_name("$s7SwiftUI5ImageV19_internalSystemNameACSS_tcfC")
private func _swiftUI_image(internalSystemName: String) -> Image?

extension Image {
    init?(privateName: String) {
        guard let systemImage = _swiftUI_image(internalSystemName: privateName) else {
            return nil
        }
        self = systemImage
    }
}

// MARK: - CGS Space Management (for Notch Window)
public final class CGSSpace {
    private let identifier: CGSSpaceID
    private let createdByInit: Bool
    private let connectionID: CGSConnectionID

    public var windows: Set<NSWindow> = [] {
        didSet {
            let remove = oldValue.subtracting(self.windows)
            let add = self.windows.subtracting(oldValue)

            if connectionID != 0 {
                 if !remove.isEmpty {
                     CGSRemoveWindowsFromSpaces(connectionID, remove.map { $0.windowNumber } as NSArray, [self.identifier] as NSArray)
                 }
                if !add.isEmpty {
                     CGSAddWindowsToSpaces(connectionID, add.map { $0.windowNumber } as NSArray, [self.identifier] as NSArray)
                }
            }
        }
    }

    public init(level: Int = Int(CGWindowLevelForKey(.normalWindow))) {
        self.connectionID = _CGSDefaultConnection()
        let flag = 0x1

        self.identifier = CGSSpaceCreate(connectionID, flag, nil as NSDictionary?)
        CGSSpaceSetAbsoluteLevel(connectionID, self.identifier, level)
        CGSShowSpaces(connectionID, [self.identifier] as NSArray)
        self.createdByInit = true
    }

    deinit {
         if connectionID != 0 && identifier != 0 {
             CGSHideSpaces(connectionID, [self.identifier] as NSArray)
             if createdByInit {
                 CGSSpaceDestroy(connectionID, self.identifier)
             }
         }
    }
}

// MARK: - System HUD Management
class OSDManager {
    static func disableSystemHUD() {
        print("[OSDManager] LOG: `disableSystemHUD` called. Native HUD suppression is handled by consuming media key events in `SystemHUDManager`.")
    }

    static func enableSystemHUD() {
        print("[OSDManager] LOG: `enableSystemHUD` called. No action needed.")
    }
}

// MARK: - System Control Interface
struct SystemControl {
    private static var brightnessAnimationTask: Task<Void, Never>?

    private static let keyboardManager = KeyboardBacklightManager.sharedManager() as! KeyboardBacklightManager

    static func configureKeyboardBacklight() {
        Self.keyboardManager.configure()
    }

    static func getVolume() -> Float {
        let scriptSource = "output volume of (get volume settings)"
        if let script = NSAppleScript(source: scriptSource) {
            var error: NSDictionary?
            let result = script.executeAndReturnError(&error)
            if error == nil {
                return Float(result.int32Value) / 100.0
            }
        }
        return 0.5 // Fallback
    }

    static func setVolume(to level: Float) {
        let cleanLevel = max(0.0, min(1.0, level))

        let scriptVolume: Int
        if cleanLevel < 0.05 {
            scriptVolume = Int(ceil(cleanLevel * 100))
        } else {
            scriptVolume = Int((cleanLevel * 100).rounded(.toNearestOrAwayFromZero))
        }

        let scriptSource = "set volume output volume \(scriptVolume)"

        if let script = NSAppleScript(source: scriptSource) {
            var error: NSDictionary?
            script.executeAndReturnError(&error)
            if let err = error {
                print("[SystemControl] ERROR: AppleScript failed to set volume: \(err)")
            }
        }
    }

    static func isMuted() -> Bool {
        let scriptSource = "output muted of (get volume settings)"
        if let script = NSAppleScript(source: scriptSource) {
            var error: NSDictionary?
            let result = script.executeAndReturnError(&error)
            if error == nil {
                return result.booleanValue
            }
        }
        return false // Fallback
    }

    static func setMuted(to isMuted: Bool) {
        let scriptSource = isMuted ? "set volume with output muted" : "set volume without output muted"
        if let script = NSAppleScript(source: scriptSource) {
            var error: NSDictionary?
            script.executeAndReturnError(&error)
            if let err = error {
                print("[SystemControl] ERROR: AppleScript failed to set mute state: \(err)")
            }
        }
    }

    static func getBrightness() -> Float {
        var brightness: Float = 0.0
        guard let screen = NSScreen.main else { return 0.5 }
        let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? 0
        if DisplayServicesGetBrightness(displayID, &brightness) != 0 {
            return 0.5
        }
        return brightness
    }

    static func setBrightness(to level: Float) {
        let clampedLevel = min(1.0, max(0.0, level))
        for screen in NSScreen.screens {
            let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? 0
            let result = DisplayServicesSetBrightness(displayID, clampedLevel)
            if result != 0 {
                print("[SystemControl] ERROR: DisplayServicesSetBrightness failed for display \(displayID) with result code \(result).")
            }
        }
    }

    static func setBrightnessSmoothly(to targetBrightness: Float, duration: TimeInterval = 0.2) {
        brightnessAnimationTask?.cancel()

        brightnessAnimationTask = Task {
            let startBrightness = getBrightness()
            let startTime = Date()
            let endTime = startTime.addingTimeInterval(duration)

            while Date() < endTime {
                if Task.isCancelled { break }

                let elapsed = Date().timeIntervalSince(startTime)
                let progress = min(1.0, elapsed / duration)

                let interpolatedBrightness = startBrightness + (targetBrightness - startBrightness) * Float(progress)
                setBrightness(to: interpolatedBrightness)

                try? await Task.sleep(for: .milliseconds(16))
            }

            if !Task.isCancelled {
                setBrightness(to: targetBrightness)
            }
        }
    }

    static func getKeyboardBrightness() -> Float {
        return Self.keyboardManager.getBrightness()
    }

    static func setKeyboardBrightness(to level: Float) {
        let clampedLevel = level.clamped(to: 0...1)
        Self.keyboardManager.setBrightness(clampedLevel)
    }
}

// MARK: - CGS Desktop Helper
struct CGSHelper {
    private static let connection = _CGSDefaultConnection()

    static func getActiveDesktopNumber() -> Int? {
        let activeSpaceID = CGSGetActiveSpace(connection)

        guard let displaySpaces = CGSCopyManagedDisplaySpaces(connection) as? [[String: Any]],
              let mainDisplay = displaySpaces.first,
              let spacesForMainDisplay = mainDisplay["Spaces"] as? [[String: Any]] else {
            return nil
        }

        if let index = spacesForMainDisplay.firstIndex(where: { ($0["id64"] as? CGSSpaceID) == activeSpaceID }) {
            return index + 1
        }

        return nil
    }
}