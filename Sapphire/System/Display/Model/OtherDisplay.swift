//
//  OtherDisplay.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-10-14.
//

import Foundation
import Cocoa
import os.log

class OtherDisplay: Display {
  var ddc: DDC?
  var arm64ddc: Bool = false
  var arm64avService: IOAVService?
  var isSwOnly: Bool = false
  var isDiscouraged: Bool = false

  var smoothBrightnessTransient: Float = 1

  var isSw: Bool {
    return self.isSwOnly || self.readPrefAsBool(key: .forceSw)
  }

  var brightnessSyncSourceValue: Float = 0

  // MARK: - Initializers
  override init(_ identifier: CGDirectDisplayID, name: String, vendorNumber: UInt32?, modelNumber: UInt32?, serialNumber: UInt32?, isVirtual: Bool = false, isDummy: Bool = false) {
    super.init(identifier, name: name, vendorNumber: vendorNumber, modelNumber: modelNumber, serialNumber: serialNumber, isVirtual: isVirtual, isDummy: isDummy)
    if !isVirtual {
        self.ddc = DDC(for: identifier)
    }
  }

  // MARK: - Brightness
  override func getBrightness() -> Float {
    if self.isSw {
      return self.getSwBrightness()
    } else {
      return self.readPrefAsFloat(key: .value, for: .brightness)
    }
  }

  @discardableResult
  override func setBrightness(_ level: Float) -> Bool {
    let prefLevel = max(0, min(1, level))
    self.savePref(prefLevel, key: .value, for: .brightness)

    if self.isSw {
      return self.setSwBrightness(level)
    }

    let ddcValue = self.convValueToDDC(for: .brightness, from: prefLevel)
    return self.writeDDCValues(command: .brightness, value: ddcValue)
  }

  override func stepBrightness(isUp: Bool, isSmallIncrement: Bool) {
    let currentValue = self.getBrightness()
    let step: Float = isSmallIncrement ? 0.01 : 0.0625
    var nextValue = isUp ? currentValue + step : currentValue - step
    nextValue = max(0, min(1, nextValue))
    self.setBrightness(nextValue)
  }

  @discardableResult
  override func setDirectBrightness(_ level: Float) -> Bool {
    let ddcValue = self.convValueToDDC(for: .brightness, from: level)
    return self.writeDDCValues(command: .brightness, value: ddcValue)
  }

  // MARK: - Software Brightness
  func getSwBrightness() -> Float {
    return self.readPrefAsFloat(key: .SwBrightness)
  }

  @discardableResult
  override func setSwBrightness(_ level: Float) -> Bool {
    self.savePref(level, key: .SwBrightness)
    return true
  }

  // MARK: - DDC Methods
  func writeDDCValues(command: Command, value: UInt16) -> Bool {
    var success = false
    if self.arm64ddc {
      success = Arm64DDC.write(service: self.arm64avService, command: command.rawValue, value: value)
    } else {
      success = self.ddc?.write(command: command.rawValue, value: value) ?? false
    }
    if !success {
      os_log("DDC write to display %{public}@ failed, command: %{public}@, value: %{public}@", type: .debug, String(self.identifier), String(command.rawValue), String(value))
    }
    return success
  }

  func readDDCValues(command: Command) -> (current: UInt16, max: UInt16)? {
    if self.arm64ddc {
      return Arm64DDC.read(service: self.arm64avService, command: command.rawValue)
    } else {
      return self.ddc?.read(command: command.rawValue, tries: 2)
    }
  }

  func convValueToDDC(for command: Command, from value: Float) -> UInt16 {
    let min = Float(self.readPrefAsInt(key: .minDDCOverride, for: command))
    let max = Float(self.readPrefAsInt(key: .maxDDC, for: command))
    let result = min + (max - min) * value
    return UInt16(result)
  }

  func setupCurrentAndMaxValues(command: Command, firstrun: Bool) {
    if (firstrun || self.isDummy) && !self.prefExists(key: .maxDDC, for: command) {
        self.savePref(100, key: .maxDDC, for: command)
        self.savePref(1, key: .value, for: command)
        return
    }

    if let (current, max) = self.readDDCValues(command: command) {
        self.savePref(Int(max), key: .maxDDC, for: command)
        let prefValue = (max > 0) ? Float(current) / Float(max) : 0
        self.savePref(prefValue, key: .value, for: command)
    } else {
        self.savePref(true, key: .unavailableDDC, for: command)
    }
  }

  func restoreDDCSettingsToDisplay(command: Command) {
    let value = self.readPrefAsFloat(key: .value, for: command)
    let ddcValue = self.convValueToDDC(for: command, from: value)
    self.writeDDCValues(command: command, value: ddcValue)
  }

  func combinedBrightnessSwitchingValue() -> Float {
    return Float(self.readPrefAsInt(key: .combinedBrightnessSwitchingPoint)) / 100
  }
}