//
//  Bridging.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-11-08
//

import Cocoa

enum Bridging {
    static func getWindowFrame(for windowID: CGWindowID) -> CGRect? {
        var rect = CGRect.zero
        let result = CGSGetScreenRectForWindow(CGSMainConnectionID(), windowID, &rect)
        guard result == kCGErrorSuccess else {
            return nil
        }
        return rect
    }

    struct WindowListOption: OptionSet {
        let rawValue: Int
        static let onScreen = WindowListOption(rawValue: 1 << 0)
        static let menuBarItems = WindowListOption(rawValue: 1 << 1)
        static let activeSpace = WindowListOption(rawValue: 1 << 2)
    }

    private static func getOnScreenWindowList() -> [CGWindowID] {
        var count: Int32 = 0
        CGSGetOnScreenWindowCount(CGSMainConnectionID(), 0, &count)
        var list = [CGWindowID](repeating: 0, count: Int(count))
        var realCount: Int32 = 0
        CGSGetOnScreenWindowList(CGSMainConnectionID(), 0, count, &list, &realCount)
        return Array(list.prefix(Int(realCount)))
    }

    private static func getMenuBarWindowList() -> [CGWindowID] {
        var count: Int32 = 0
        CGSGetWindowCount(CGSMainConnectionID(), 0, &count)
        var list = [CGWindowID](repeating: 0, count: Int(count))
        var realCount: Int32 = 0
        CGSGetProcessMenuBarWindowList(CGSMainConnectionID(), 0, count, &list, &realCount)
        return Array(list.prefix(Int(realCount)))
    }

    private static func getOnScreenMenuBarWindowList() -> [CGWindowID] {
        let onScreenList = Set(getOnScreenWindowList())
        return getMenuBarWindowList().filter(onScreenList.contains)
    }

    private static var activeSpaceID: CGSSpaceID { CGSGetActiveSpace(CGSMainConnectionID()) }

    private static func getSpaceList(for windowID: CGWindowID) -> [CGSSpaceID] {
        guard let spaces = CGSCopySpacesForWindows(CGSMainConnectionID(), .allSpaces, [windowID] as CFArray) else { return [] }
        return spaces.takeRetainedValue() as? [CGSSpaceID] ?? []
    }

    private static func isWindowOnActiveSpace(_ windowID: CGWindowID) -> Bool {
        getSpaceList(for: windowID).contains(activeSpaceID)
    }

    static func getWindowList(option: WindowListOption = []) -> [CGWindowID] {
        let baseList: [CGWindowID]

        if option.contains(.menuBarItems) {
            if option.contains(.onScreen) {
                baseList = getOnScreenMenuBarWindowList()
            } else {
                baseList = getMenuBarWindowList()
            }
        } else if option.contains(.onScreen) {
            baseList = getOnScreenWindowList()
        } else {
            var count: Int32 = 0
            CGSGetWindowCount(CGSMainConnectionID(), 0, &count)
            var list = [CGWindowID](repeating: 0, count: Int(count))
            var realCount: Int32 = 0
            CGSGetWindowList(CGSMainConnectionID(), 0, count, &list, &realCount)
            baseList = Array(list.prefix(Int(realCount)))
        }

        if option.contains(.activeSpace) {
            return baseList.filter(isWindowOnActiveSpace)
        } else {
            return baseList
        }
    }
}