//
//  Display.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-10-14.
//

import Foundation
import Cocoa

class Display {
  let identifier: CGDirectDisplayID
  var name: String
  let vendorNumber: UInt32?
  let modelNumber: UInt32?
  let serialNumber: UInt32?
  var isVirtual: Bool = false
  var isDummy: Bool = false

  internal var brightness: Float = 1.0

  init(_ identifier: CGDirectDisplayID, name: String, vendorNumber: UInt32?, modelNumber: UInt32?, serialNumber: UInt32?, isVirtual: Bool = false, isDummy: Bool = false) {
    self.identifier = identifier
    self.name = name
    self.vendorNumber = vendorNumber
    self.modelNumber = modelNumber
    self.serialNumber = serialNumber
    self.isVirtual = isVirtual
    self.isDummy = isDummy
  }

  func stepBrightness(isUp: Bool, isSmallIncrement: Bool) {}

  func getBrightness() -> Float {
    return 1.0
  }

  @discardableResult
  func setBrightness(_ level: Float) -> Bool {
    return false
  }

  @discardableResult
  func setDirectBrightness(_ level: Float) -> Bool {
    return false
  }

  @discardableResult
  func setSwBrightness(_ level: Float) -> Bool {
    return false
  }

  func getPrefKey(for command: Command) -> String {
    return "display\(self.identifier)\(command.rawValue)"
  }

  func prefExists(key: PrefKey, for command: Command = .none) -> Bool {
    return UserDefaults.standard.object(forKey: self.getPrefKey(for: command) + key.rawValue) != nil
  }

  func readPref<T>(key: PrefKey, for command: Command = .none) -> T? {
    return UserDefaults.standard.object(forKey: self.getPrefKey(for: command) + key.rawValue) as? T
  }

  func readPrefAsFloat(key: PrefKey, for command: Command = .none) -> Float {
    return self.readPref(key: key, for: command) ?? 0
  }

  func readPrefAsInt(key: PrefKey, for command: Command = .none) -> Int {
    return self.readPref(key: key, for: command) ?? 0
  }

  func readPrefAsBool(key: PrefKey, for command: Command = .none) -> Bool {
    return self.readPref(key: key, for: command) ?? false
  }

  func readPrefAsString(key: PrefKey, for command: Command = .none) -> String {
    return self.readPref(key: key, for: command) ?? ""
  }

  func savePref<T>(_ value: T, key: PrefKey, for command: Command = .none) {
    UserDefaults.standard.set(value, forKey: self.getPrefKey(for: command) + key.rawValue)
  }

  func removePref(key: PrefKey, for command: Command = .none) {
    UserDefaults.standard.removeObject(forKey: self.getPrefKey(for: command) + key.rawValue)
  }

  func isBuiltIn() -> Bool {
    return CGDisplayIsBuiltin(self.identifier) != 0
  }
}