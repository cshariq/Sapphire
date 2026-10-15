//
//  XDRUtil.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-10-13.
//

import IOKit
import Cocoa

extension NSScreen {
    var displayId: CGDirectDisplayID? {
        return deviceDescription[NSDeviceDescriptionKey(rawValue: "NSScreenNumber")] as? CGDirectDisplayID
    }
}

enum XDRSupport {
    static let minimumPotentialHeadroom: CGFloat = 2.05

    static func supportsExtraBrightness(_ screen: NSScreen) -> Bool {
        guard let displayId = screen.displayId else { return false }
        guard screen.maximumPotentialExtendedDynamicRangeColorComponentValue > minimumPotentialHeadroom else { return false }
        return CGDisplayIsBuiltin(displayId) != 0 || DisplayManager.isAppleDisplay(displayID: displayId)
    }

    private static let cacheLock = NSLock()
    private static var cachedBuiltInSupport: Bool?

    static func builtInPanelSupportsExtraBrightness() -> Bool {
        cacheLock.lock()
        let cached = cachedBuiltInSupport
        cacheLock.unlock()
        if let cached { return cached }
        guard Thread.isMainThread else { return false }

        guard let builtIn = NSScreen.screens.first(where: { isBuiltInScreen(screen: $0) }) else { return false }
        let supported = supportsExtraBrightness(builtIn)
        cacheLock.lock()
        cachedBuiltInSupport = supported
        cacheLock.unlock()
        return supported
    }
}

public func getXDRDisplays() -> [NSScreen] {
    NSScreen.screens.filter { XDRSupport.supportsExtraBrightness($0) }
}

func isBuiltInScreen(screen: NSScreen) -> Bool {
    guard let displayId = screen.displayId else { return false }
    return CGDisplayIsBuiltin(displayId) != 0
}

func getModelIdentifier() -> String? {
    let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
    guard service != IO_OBJECT_NULL else { return nil }
    var modelIdentifier: String?
    if let modelData = IORegistryEntryCreateCFProperty(service, "model" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Data {
        modelIdentifier = String(data: modelData, encoding: .utf8)?.trimmingCharacters(in: .controlCharacters)
    }
    IOObjectRelease(service)
    return modelIdentifier
}

func isDeviceSupported() -> Bool {
    XDRSupport.builtInPanelSupportsExtraBrightness()
}

func getDeviceMaxBrightness() -> Float {
    if let device = getModelIdentifier(),
        sdr600nitsDevices.contains(device)
    {
        print("[XDRUtil] Device \(device) supports 600 nits SDR brightness.")
        return 1.535
    }
    return 1.6
}

let sdr600nitsDevices = ["Mac15,3", "Mac15,6", "Mac15,7", "Mac15,8", "Mac15,9", "Mac15,10", "Mac15,11", "Mac16,1", "Mac16,6", "Mac16,8", "Mac16,5"]