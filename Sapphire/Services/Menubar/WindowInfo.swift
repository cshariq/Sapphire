//
//  WindowInfo.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-11-08
//

import Cocoa
import ApplicationServices

struct WindowInfo {
    let windowID: CGWindowID
    let frame: CGRect
    let title: String?
    let ownerPID: pid_t
    var owningApplication: NSRunningApplication? { NSRunningApplication(processIdentifier: ownerPID) }
    var ownerName: String?
    let layer: Int
    let isOnScreen: Bool

    private init?(dictionary: CFDictionary) {
        guard let info = dictionary as? [CFString: CFTypeRef],
              let windowID = info[kCGWindowNumber] as? CGWindowID,
              let boundsDict = info[kCGWindowBounds] as? NSDictionary,
              let frame = CGRect(dictionaryRepresentation: boundsDict),
              let layer = info[kCGWindowLayer] as? Int,
              let ownerPID = info[kCGWindowOwnerPID] as? pid_t else { return nil }
        self.windowID = windowID; self.frame = frame; self.title = info[kCGWindowName] as? String
        self.layer = layer; self.ownerPID = ownerPID; self.ownerName = info[kCGWindowOwnerName] as? String
        self.isOnScreen = info[kCGWindowIsOnscreen] as? Bool ?? false
    }

    init?(windowID: CGWindowID) {
        var pointer = UnsafeRawPointer(bitPattern: Int(windowID))
        guard let array = CFArrayCreate(kCFAllocatorDefault, &pointer, 1, nil),
              let list = CGWindowListCreateDescriptionFromArray(array) as? [CFDictionary],
              let dictionary = list.first else { return nil }
        self.init(dictionary: dictionary)
    }

    static func getOnScreenWindows(excludeDesktop: Bool = true) -> [WindowInfo] {
        var options = CGWindowListOption.optionOnScreenOnly
        if excludeDesktop { options.insert(.excludeDesktopElements) }
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [CFDictionary] else { return [] }
        return list.compactMap { WindowInfo(dictionary: $0) }
    }

    static func getMenuBarWindow(for displayID: CGDirectDisplayID) -> WindowInfo? {
        getOnScreenWindows().first {
            $0.ownerName == "Window Server" && $0.layer == kCGMainMenuWindowLevel &&
            $0.title == "Menubar" && CGDisplayBounds(displayID).contains($0.frame)
        }
    }

    static func getWallpaperWindow(for displayID: CGDirectDisplayID) -> WindowInfo? {
        getOnScreenWindows(excludeDesktop: false).first {
            $0.owningApplication?.bundleIdentifier == "com.apple.dock" &&
            $0.title?.hasPrefix("Wallpaper") == true && CGDisplayBounds(displayID).contains($0.frame)
        }
    }

    static func getApplicationMenuFrame(for displayID: CGDirectDisplayID) -> CGRect? {
        let displayBounds = CGDisplayBounds(displayID)
        guard let menuBar = AX.element(atAXPoint: displayBounds.origin) else { return nil }

        var applicationMenuFrame = CGRect.null

        for element in AX.children(of: menuBar) {
            guard AX.role(of: element) == kAXMenuBarItemRole as String else { break }
            guard let frame = AX.frame(of: element) else { continue }
            applicationMenuFrame = applicationMenuFrame.union(frame)
        }

        guard applicationMenuFrame.width > 0 else { return nil }

        return applicationMenuFrame
    }
}