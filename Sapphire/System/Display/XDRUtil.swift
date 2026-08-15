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

public func getXDRDisplays() -> [NSScreen] {
    return NSScreen.screens.filter { screen in
        (isBuiltInScreen(screen: screen) && isDeviceSupported()) || externalXdrDisplays.contains(screen.localizedName)
    }
}

func isBuiltInScreen(screen: NSScreen) -> Bool {
    guard let displayId = screen.displayId else { return false }
    return CGDisplayIsBuiltin(displayId) != 0
}

func getModelIdentifier() -> String? {
    let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
    var modelIdentifier: String?
    if let modelData = IORegistryEntryCreateCFProperty(service, "model" as CFString, kCFAllocatorDefault, 0).takeRetainedValue() as? Data {
        modelIdentifier = String(data: modelData, encoding: .utf8)?.trimmingCharacters(in: .controlCharacters)
    }
    IOObjectRelease(service)
    return modelIdentifier
}

func isDeviceSupported() -> Bool {
    if let device = getModelIdentifier(), supportedDevices.contains(device) {
        return true
    }
    return false
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

let supportedDevices = ["MacBookPro18,1", "MacBookPro18,2", "MacBookPro18,3", "MacBookPro18,4", "Mac14,6", "Mac14,10", "Mac14,5", "Mac14,9", "Mac15,7", "Mac15,9", "Mac15,11", "Mac15,6", "Mac15,8", "Mac15,10", "Mac15,3", "Mac16,1", "Mac16,6", "Mac16,8", "Mac16,7", "Mac16,5"]

let externalXdrDisplays = ["Pro Display XDR"]

let sdr600nitsDevices = ["Mac15,3", "Mac15,6", "Mac15,7", "Mac15,8", "Mac15,9", "Mac15,10", "Mac15,11", "Mac16,1", "Mac16,6", "Mac16,8", "Mac16,5"]