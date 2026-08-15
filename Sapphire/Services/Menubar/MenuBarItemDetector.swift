//
//  MenuBarItemDetector.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-11-07
//

import Cocoa

struct MenuBarItemInfo {
    let frame: CGRect
    let ownerPID: pid_t
    let bundleIdentifier: String?
}

class MenuBarItemDetector {
    static func detectItems() -> [MenuBarItem] {
        return detectItemsWithInfo().map { MenuBarItem(frame: $0.frame) }
    }

    static func detectItemsWithInfo() -> [MenuBarItemInfo] {
        var items: [MenuBarItemInfo] = []

        let windowListOptions: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windowList = CGWindowListCopyWindowInfo(windowListOptions, kCGNullWindowID) as? [[String: Any]] else {
            return items
        }

        let statusBarLevel = Int(CGWindowLevelForKey(.statusWindow))

        for windowInfo in windowList {
            guard let windowLayer = windowInfo[kCGWindowLayer as String] as? Int,
                  windowLayer == statusBarLevel,
                  let boundsDict = windowInfo[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = boundsDict["X"], let y = boundsDict["Y"],
                  let width = boundsDict["Width"], let height = boundsDict["Height"],
                  width > 5, height > 10 else {
                continue
            }

            guard width < 500 else {
                continue
            }

            let frame = CGRect(x: x, y: y, width: width, height: height)
            let ownerPID = windowInfo[kCGWindowOwnerPID as String] as? pid_t ?? 0

            var bundleID: String?
            if ownerPID != 0, let app = NSRunningApplication(processIdentifier: ownerPID) {
                bundleID = app.bundleIdentifier
            }

            items.append(MenuBarItemInfo(frame: frame, ownerPID: ownerPID, bundleIdentifier: bundleID))
        }

        items.sort { $0.frame.minX < $1.frame.minX }
        return items
    }
}

struct MenuBarItem {
    let frame: CGRect
}