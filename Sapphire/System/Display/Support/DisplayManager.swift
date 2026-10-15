//
//  DisplayManager.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-10-14.
//

import Cocoa
import CoreGraphics
import os.log
import Combine

@MainActor
final class DisplayManager {
  public static let shared = DisplayManager()
  static let brightnessStateDidChange = Notification.Name("SapphireDisplayBrightnessStateDidChange")

  private var displays: [Display] = []
  private var isBuilt = false
  private var rebuildWorkItem: DispatchWorkItem?
  private var screenObserver: NSObjectProtocol?
  private var settingsCancellable: AnyCancellable?
  private(set) var isExtraDimmingEnabled = false

  private static let rebuildDelay: TimeInterval = 1.0

  private init() {}

  // MARK: - Display Accessors

  func getAllDisplays() -> [Display] {
    self.ensureDisplays()
    return self.displays
  }

  func getOtherDisplays() -> [OtherDisplay] {
    self.getAllDisplays().compactMap { $0 as? OtherDisplay }
  }

  func getAppleDisplays() -> [AppleDisplay] {
    self.getAllDisplays().compactMap { $0 as? AppleDisplay }
  }

  func getBuiltInDisplay() -> Display? {
    self.getAllDisplays().first { $0.isBuiltIn() }
  }

  func display(for displayID: CGDirectDisplayID) -> Display? {
    self.getAllDisplays().first { $0.identifier == displayID }
  }

  func getCurrentDisplay() -> Display? {
    let displays = self.getAllDisplays()
    let mouseLocation = NSEvent.mouseLocation
    if let screenWithMouse = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) }) {
      return displays.first { $0.identifier == screenWithMouse.displayID }
    }
    return displays.first
  }

  // MARK: - Lifecycle

  func restoreSoftwareDimming() {
    for display in self.getOtherDisplays() where display.getBrightness() < 1 {
      display.restoreSoftwareDimming()
    }
  }

  func notifyBrightnessStateChanged() {
    NotificationCenter.default.post(name: Self.brightnessStateDidChange, object: self)
  }

  private func ensureDisplays() {
    guard !self.isBuilt else { return }
    self.installObservers()
    self.rebuild()
  }

  private func installObservers() {
    if self.screenObserver == nil {
      self.screenObserver = NotificationCenter.default.addObserver(
        forName: NSApplication.didChangeScreenParametersNotification,
        object: nil,
        queue: .main
      ) { [weak self] _ in
        MainActor.assumeIsolated { self?.scheduleRebuild() }
      }
    }
    if self.settingsCancellable == nil {
      self.isExtraDimmingEnabled = SettingsModel.shared.current.displayExtraDimming
      self.settingsCancellable = SettingsModel.shared.changes(of: { $0.displayExtraDimming })
        .sink { [weak self] isEnabled in
          MainActor.assumeIsolated {
            guard let self, self.isExtraDimmingEnabled != isEnabled else { return }
            self.isExtraDimmingEnabled = isEnabled
            self.getOtherDisplays().forEach { $0.reapplyBrightness() }
            self.notifyBrightnessStateChanged()
          }
        }
    }
  }

  private func scheduleRebuild() {
    self.rebuildWorkItem?.cancel()
    let item = DispatchWorkItem { [weak self] in
      MainActor.assumeIsolated {
        self?.rebuildWorkItem = nil
        self?.rebuild()
      }
    }
    self.rebuildWorkItem = item
    DispatchQueue.main.asyncAfter(deadline: .now() + Self.rebuildDelay, execute: item)
  }

  private func rebuild() {
    let previous = self.displays
    self.displays = Self.makeDisplays()
    self.isBuilt = true
    self.addDisplayCounterSuffixes()

    let others = self.displays.compactMap { $0 as? OtherDisplay }
    let directory = DDCServiceDirectory(displayIDs: others.map(\.identifier))
    others.forEach { $0.ddcDirectory = directory }

    let gamma = DisplayGammaController.shared
    for old in previous.compactMap({ $0 as? OtherDisplay }) {
      old.invalidate()
      if !others.contains(where: { $0.identifier == old.identifier }) {
        gamma.removeFactor(for: old.identifier, source: .dimming)
      }
    }
    for display in others where gamma.factor(for: display.identifier, source: .dimming) != 1 {
      if display.prefersSoftware {
        display.reapplyBrightness()
      } else {
        display.prepareBrightnessControl()
      }
    }
    self.notifyBrightnessStateChanged()
  }

  private static func makeDisplays() -> [Display] {
    var onlineDisplayIDs = [CGDirectDisplayID](repeating: 0, count: 16)
    var displayCount: UInt32 = 0
    guard CGGetOnlineDisplayList(16, &onlineDisplayIDs, &displayCount) == .success else {
      os_log("Unable to get display list.", type: .info)
      return []
    }
    return onlineDisplayIDs.prefix(Int(displayCount)).compactMap { displayID -> Display? in
      guard displayID != 0 else { return nil }
      let name = DisplayManager.getDisplayNameByID(displayID: displayID)
      let vendorNumber = CGDisplayVendorNumber(displayID)
      let modelNumber = CGDisplayModelNumber(displayID)
      let serialNumber = CGDisplaySerialNumber(displayID)
      let isDummy = DisplayManager.isDummy(displayID: displayID)
      let isVirtual = DisplayManager.isVirtual(displayID: displayID)
      if DisplayManager.isAppleDisplay(displayID: displayID) {
        return AppleDisplay(displayID, name: name, vendorNumber: vendorNumber, modelNumber: modelNumber, serialNumber: serialNumber, isVirtual: isVirtual, isDummy: isDummy)
      }
      return OtherDisplay(displayID, name: name, vendorNumber: vendorNumber, modelNumber: modelNumber, serialNumber: serialNumber, isVirtual: isVirtual, isDummy: isDummy)
    }
  }

  private func addDisplayCounterSuffixes() {
    var nameDisplays: [String: [Display]] = [:]
    for display in self.displays {
      nameDisplays[display.name, default: []].append(display)
    }
    for group in nameDisplays.values where group.count > 1 {
      for (index, display) in group.enumerated() {
        display.name = "\(display.name) (\(index + 1))"
      }
    }
  }

  // MARK: - Static Utility Functions
  nonisolated static func isDummy(displayID: CGDirectDisplayID) -> Bool {
    let vendorNumber = CGDisplayVendorNumber(displayID)
    let rawName = DisplayManager.getDisplayRawNameByID(displayID: displayID)
    if rawName.lowercased().contains("dummy") || (self.isVirtual(displayID: displayID) && vendorNumber == 0xF0F0) {
      return true
    }
    return false
  }

  nonisolated static func isVirtual(displayID: CGDirectDisplayID) -> Bool {
    if let dictionary = (CoreDisplay_DisplayCreateInfoDictionary(displayID)?.takeRetainedValue() as NSDictionary?) {
      let isVirtualDevice = dictionary["kCGDisplayIsVirtualDevice"] as? Bool
      let displayIsAirplay = dictionary["kCGDisplayIsAirPlay"] as? Bool
      if isVirtualDevice ?? displayIsAirplay ?? false {
        return true
      }
    }
    return false
  }

  nonisolated static func isAppleDisplay(displayID: CGDirectDisplayID) -> Bool {
    var brightness: Float = -1
    let ret = DisplayServicesGetBrightness(displayID, &brightness)
    if ret == kCGErrorSuccess, brightness >= 0 {
      return true
    }
    return CGDisplayIsBuiltin(displayID) != 0
  }

  nonisolated static func getDisplayRawNameByID(displayID: CGDirectDisplayID) -> String {
    let defaultName = "Unknown"
    if let dictionary = (CoreDisplay_DisplayCreateInfoDictionary(displayID)?.takeRetainedValue() as NSDictionary?),
       let nameList = dictionary["DisplayProductName"] as? [String: String],
       let name = nameList["en_US"] ?? nameList.first?.value {
      return name
    }
    if let screen = NSScreen.screens.first(where: { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == displayID }) {
      return screen.localizedName
    }
    return defaultName
  }

  nonisolated static func getDisplayNameByID(displayID: CGDirectDisplayID) -> String {
    return getDisplayRawNameByID(displayID: displayID)
  }
}