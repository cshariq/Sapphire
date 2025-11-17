//
//  PrivateAPIs.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-07-04.
//

import SwiftUI
import Cocoa
import AudioToolbox
import IOKit.hidsystem

// MARK: - Bridged Types from Ice
internal typealias CGSConnectionID = Int32
internal typealias CGSSpaceID = UInt64
internal typealias CGError = Int32

internal let kCGErrorSuccess: CGError = 0

internal enum CGSSpaceType: UInt32 {
    case user = 0
    case system = 2
    case fullscreen = 4
}

internal struct CGSSpaceMask: OptionSet {
    let rawValue: UInt32

    static let includesCurrent = CGSSpaceMask(rawValue: 1 << 0)
    static let includesOthers = CGSSpaceMask(rawValue: 1 << 1)
    static let includesUser = CGSSpaceMask(rawValue: 1 << 2)
    static let includesVisible = CGSSpaceMask(rawValue: 1 << 16)
    static let currentSpace: CGSSpaceMask = [.includesUser, .includesCurrent]
    static let otherSpaces: CGSSpaceMask = [.includesOthers, .includesCurrent]
    static let allSpaces: CGSSpaceMask = [.includesUser, .includesOthers, .includesCurrent]
    static let allVisibleSpaces: CGSSpaceMask = [.includesVisible, .allSpaces]
}

// MARK: - CGSConnection Functions (from Ice)
@_silgen_name("CGSMainConnectionID")
internal func CGSMainConnectionID() -> CGSConnectionID

@_silgen_name("CGSCopyConnectionProperty")
internal func CGSCopyConnectionProperty(
    _ cid: CGSConnectionID,
    _ targetCID: CGSConnectionID,
    _ key: CFString,
    _ outValue: inout Unmanaged<CFTypeRef>?
) -> CGError

@_silgen_name("CGSSetConnectionProperty")
internal func CGSSetConnectionProperty(
    _ cid: CGSConnectionID,
    _ targetCID: CGSConnectionID,
    _ key: CFString,
    _ value: CFTypeRef
) -> CGError

// MARK: - CGSEvent Functions (from Ice)
@_silgen_name("CGSEventIsAppUnresponsive")
internal func CGSEventIsAppUnresponsive(
    _ cid: CGSConnectionID,
    _ psn: inout ProcessSerialNumber
) -> Bool

// MARK: - CGSSpace Functions (from Ice)
@_silgen_name("CGSGetActiveSpace")
internal func CGSGetActiveSpace(_ cid: CGSConnectionID) -> CGSSpaceID

@_silgen_name("CGSCopySpacesForWindows")
internal func CGSCopySpacesForWindows(
    _ cid: CGSConnectionID,
    _ mask: CGSSpaceMask,
    _ windowIDs: CFArray
) -> Unmanaged<CFArray>?

@_silgen_name("CGSSpaceGetType")
internal func CGSSpaceGetType(
    _ cid: CGSConnectionID,
    _ sid: CGSSpaceID
) -> CGSSpaceType

// MARK: - CGSWindow Functions (from Ice)
@_silgen_name("CGSGetWindowList")
internal func CGSGetWindowList(
    _ cid: CGSConnectionID,
    _ targetCID: CGSConnectionID,
    _ count: Int32,
    _ list: UnsafeMutablePointer<CGWindowID>,
    _ outCount: inout Int32
) -> CGError

@_silgen_name("CGSGetOnScreenWindowList")
internal func CGSGetOnScreenWindowList(
    _ cid: CGSConnectionID,
    _ targetCID: CGSConnectionID,
    _ count: Int32,
    _ list: UnsafeMutablePointer<CGWindowID>,
    _ outCount: inout Int32
) -> CGError

@_silgen_name("CGSGetProcessMenuBarWindowList")
internal func CGSGetProcessMenuBarWindowList(
    _ cid: CGSConnectionID,
    _ targetCID: CGSConnectionID,
    _ count: Int32,
    _ list: UnsafeMutablePointer<CGWindowID>,
    _ outCount: inout Int32
) -> CGError

@_silgen_name("CGSGetWindowCount")
internal func CGSGetWindowCount(
    _ cid: CGSConnectionID,
    _ targetCID: CGSConnectionID,
    _ outCount: inout Int32
) -> CGError

@_silgen_name("CGSGetOnScreenWindowCount")
internal func CGSGetOnScreenWindowCount(
    _ cid: CGSConnectionID,
    _ targetCID: CGSConnectionID,
    _ outCount: inout Int32
) -> CGError

@_silgen_name("CGSGetScreenRectForWindow")
internal func CGSGetScreenRectForWindow(
    _ cid: CGSConnectionID,
    _ wid: CGWindowID,
    _ outRect: inout CGRect
) -> CGError

// MARK: - CGSConnection Functions
@_silgen_name("_CGSDefaultConnection") internal func _CGSDefaultConnection() -> CGSConnectionID
@_silgen_name("CGSGetConnectionProperty") internal func CGSGetConnectionProperty(_ cid: CGSConnectionID, _ key: CFString) -> Unmanaged<CFTypeRef>
@_silgen_name("CGSSetConnectionProperty") internal func CGSSetConnectionProperty(_ cid: CGSConnectionID, _ key: CFString, _ value: CFTypeRef) -> CGError

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
@_silgen_name("CGSCopyManagedDisplaySpaces")
private func CGSCopyManagedDisplaySpaces(_ cid: CGSConnectionID) -> CFArray

@_silgen_name("CoreDockSendNotification")
internal func CoreDockSendNotification(_ notification: CFString, _ unknown: CInt) -> Void

// MARK: - DisplayServices Private APIs
@_silgen_name("DisplayServicesGetBrightness")
internal func DisplayServicesGetBrightness(_ display: CGDirectDisplayID, _ brightness: UnsafeMutablePointer<Float>) -> Int32
@_silgen_name("DisplayServicesSetBrightness")
internal func DisplayServicesSetBrightness(_ display: CGDirectDisplayID, _ brightness: Float) -> Int32

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

// MARK: - System HUD Management (Sapphire's placeholder)
class SapphireOSDManager {
    static func disableSystemHUD() {
        print("[SapphireOSDManager] LOG: `disableSystemHUD` called.")
    }

    static func enableSystemHUD() {
        print("[SapphireOSDManager] LOG: `enableSystemHUD` called.")
    }
}

// MARK: - System Control Interface
struct SystemControl {
    private static var brightnessAnimationTask: Task<Void, Never>?

    private static let keyboardManager = KeyboardBacklightManager.sharedManager() as! KeyboardBacklightManager

    static func configureKeyboardBacklight() {
        Self.keyboardManager.configure()
    }

    static func getKeyboardBrightness() -> Float {
        return Self.keyboardManager.getBrightness()
    }

    static func setKeyboardBrightness(to level: Float) {
        let clampedLevel = max(0.0, min(1.0, level))
        Self.keyboardManager.setBrightness(clampedLevel)
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
        return 0.5
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
        return false
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