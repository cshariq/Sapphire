//
//  DisplayManager.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-10-14.
//

import Cocoa
import CoreGraphics
import os.log

class DisplayManager {
  public static let shared = DisplayManager()

  var displays: [Display] = []

  // MARK: - Display Configuration
  func configureDisplays() {
    self.clearDisplays()
    var onlineDisplayIDs = [CGDirectDisplayID](repeating: 0, count: 16)
    var displayCount: UInt32 = 0
    guard CGGetOnlineDisplayList(16, &onlineDisplayIDs, &displayCount) == .success else {
      os_log("Unable to get display list.", type: .info)
      return
    }
    for onlineDisplayID in onlineDisplayIDs where onlineDisplayID != 0 {
      let name = DisplayManager.getDisplayNameByID(displayID: onlineDisplayID)
      let id = onlineDisplayID
      let vendorNumber = CGDisplayVendorNumber(onlineDisplayID)
      let modelNumber = CGDisplayModelNumber(onlineDisplayID)
      let serialNumber = CGDisplaySerialNumber(onlineDisplayID)
      let isDummy: Bool = DisplayManager.isDummy(displayID: onlineDisplayID)
      let isVirtual: Bool = DisplayManager.isVirtual(displayID: onlineDisplayID)

      if DisplayManager.isAppleDisplay(displayID: onlineDisplayID) {
        let appleDisplay = AppleDisplay(id, name: name, vendorNumber: vendorNumber, modelNumber: modelNumber, serialNumber: serialNumber, isVirtual: isVirtual, isDummy: isDummy)
        self.addDisplay(display: appleDisplay)
      } else {
        let otherDisplay = OtherDisplay(id, name: name, vendorNumber: vendorNumber, modelNumber: modelNumber, serialNumber: serialNumber, isVirtual: isVirtual, isDummy: isDummy)
        self.addDisplay(display: otherDisplay)
      }
    }
  }

  func setupOtherDisplays(firstrun: Bool = false) {
    for otherDisplay in self.getOtherDisplays() {
      if !otherDisplay.isSw && !otherDisplay.readPrefAsBool(key: .unavailableDDC, for: .brightness) {
        otherDisplay.setupCurrentAndMaxValues(command: .brightness, firstrun: firstrun)
      }
    }
  }

  func restoreOtherDisplays() {
    for otherDisplay in self.getDdcCapableDisplays() {
      if !otherDisplay.readPrefAsBool(key: .unavailableDDC, for: .brightness) {
        otherDisplay.restoreDDCSettingsToDisplay(command: .brightness)
      }
    }
  }

  // MARK: - Display Accessors
  func getOtherDisplays() -> [OtherDisplay] {
    return self.displays.compactMap { $0 as? OtherDisplay }
  }

  func getAllDisplays() -> [Display] {
    return self.displays
  }

  func getDdcCapableDisplays() -> [OtherDisplay] {
    return self.displays.compactMap { display -> OtherDisplay? in
      if let otherDisplay = display as? OtherDisplay, !otherDisplay.isSw {
        return otherDisplay
      } else {
        return nil
      }
    }
  }

  func getAppleDisplays() -> [AppleDisplay] {
    return self.displays.compactMap { $0 as? AppleDisplay }
  }

  func getBuiltInDisplay() -> Display? {
    return self.displays.first { $0.isBuiltIn() }
  }

  func getCurrentDisplay() -> Display? {
    let mouseLocation = NSEvent.mouseLocation
    let screens = NSScreen.screens
    if let screenWithMouse = (screens.first { NSMouseInRect(mouseLocation, $0.frame, false) }) {
      return self.displays.first { $0.identifier == screenWithMouse.displayID }
    }
    return self.displays.first
  }

  func addDisplay(display: Display) {
    self.displays.append(display)
  }

  func clearDisplays() {
    self.displays = []
  }

  func addDisplayCounterSuffixes() {
    var nameDisplays: [String: [Display]] = [:]
    for display in self.displays {
      if nameDisplays[display.name] != nil {
        nameDisplays[display.name]?.append(display)
      } else {
        nameDisplays[display.name] = [display]
      }
    }
    for nameDisplayKey in nameDisplays.keys where nameDisplays[nameDisplayKey]?.count ?? 0 > 1 {
      for i in 0 ..< (nameDisplays[nameDisplayKey]!.count) {
        if let display = nameDisplays[nameDisplayKey]?[i] {
          display.name = "\(display.name) (\(i + 1))"
        }
      }
    }
  }

  // MARK: - ARM64 Support
  func updateArm64AVServices() {
    if Arm64DDC.isArm64 {
      os_log("arm64 AVService update requested", type: .info)
      let displayIDs: [CGDirectDisplayID] = self.getOtherDisplays().map { $0.identifier }

      for serviceMatch in Arm64DDC.getServiceMatches(displayIDs: displayIDs) {
        if let otherDisplay = self.getOtherDisplays().first(where: { $0.identifier == serviceMatch.displayID }), serviceMatch.service != nil {
          otherDisplay.arm64avService = serviceMatch.service
          os_log("Display service match successful for display %{public}@", type: .info, String(serviceMatch.displayID))

          otherDisplay.isDiscouraged = serviceMatch.discouraged || serviceMatch.dummy
          if !otherDisplay.isDiscouraged {
            otherDisplay.arm64ddc = true
          }
        }
      }
      os_log("AVService update done", type: .info)
    }
  }

  // MARK: - Brightness Management
  func resetSwBrightnessForAllDisplays(prefsOnly: Bool = false) {
    for otherDisplay in self.getOtherDisplays() {
      if !prefsOnly {
        otherDisplay.setSwBrightness(1)
        otherDisplay.smoothBrightnessTransient = 1
      } else {
        otherDisplay.savePref(1, key: .SwBrightness)
        otherDisplay.smoothBrightnessTransient = 1
      }
      if otherDisplay.isSw {
        otherDisplay.savePref(1, key: .value, for: .brightness)
      }
    }
  }

  // MARK: - Static Utility Functions
  static func isDummy(displayID: CGDirectDisplayID) -> Bool {
    let vendorNumber = CGDisplayVendorNumber(displayID)
    let rawName = DisplayManager.getDisplayRawNameByID(displayID: displayID)
    if rawName.lowercased().contains("dummy") || (self.isVirtual(displayID: displayID) && vendorNumber == 0xF0F0) {
      return true
    }
    return false
  }

  static func isVirtual(displayID: CGDirectDisplayID) -> Bool {
    if #available(macOS 11.0, *) {
      if let dictionary = (CoreDisplay_DisplayCreateInfoDictionary(displayID)?.takeRetainedValue() as NSDictionary?) {
        let isVirtualDevice = dictionary["kCGDisplayIsVirtualDevice"] as? Bool
        let displayIsAirplay = dictionary["kCGDisplayIsAirPlay"] as? Bool
        if isVirtualDevice ?? displayIsAirplay ?? false {
          return true
        }
      }
    }
    return false
  }

  static func isAppleDisplay(displayID: CGDirectDisplayID) -> Bool {
    var brightness: Float = -1
    let ret = DisplayServicesGetBrightness(displayID, &brightness)
    if ret == kCGErrorSuccess, brightness >= 0 {
      return true
    }
    return CGDisplayIsBuiltin(displayID) != 0
  }

  static func getDisplayRawNameByID(displayID: CGDirectDisplayID) -> String {
    let defaultName = "Unknown"
    if #available(macOS 11.0, *) {
      if let dictionary = (CoreDisplay_DisplayCreateInfoDictionary(displayID)?.takeRetainedValue() as NSDictionary?),
         let nameList = dictionary["DisplayProductName"] as? [String: String],
         let name = nameList["en_US"] ?? nameList.first?.value {
        return name
      }
    }
    if let screen = NSScreen.screens.first(where: { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == displayID }) {
        if #available(macOS 10.15, *) {
            return screen.localizedName
        }
    }
    return defaultName
  }

  static func getDisplayNameByID(displayID: CGDirectDisplayID) -> String {
    return getDisplayRawNameByID(displayID: displayID)
  }
}