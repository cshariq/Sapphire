//
//  NSScreen+Extension.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-10-20

import Cocoa

public extension NSScreen {
  var displayID: CGDirectDisplayID {
    (self.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID)!
  }

  var vendorNumber: UInt32? {
    switch CGDisplayVendorNumber(self.displayID) {
    case 0xFFFF_FFFF:
      return nil
    case let vendorNumber:
      return vendorNumber
    }
  }

  var modelNumber: UInt32? {
    switch CGDisplayModelNumber(self.displayID) {
    case 0xFFFF_FFFF:
      return nil
    case let modelNumber:
      return modelNumber
    }
  }

  var serialNumber: UInt32? {
    switch CGDisplaySerialNumber(self.displayID) {
    case 0x0000_0000:
      return nil
    case let serialNumber:
      return serialNumber
    }
  }

  var cgsDisplayIdentifier: String? {
    let unmanaged = CGDisplayCreateUUIDFromDisplayID(self.displayID)
    guard unmanaged != nil else { return nil }
    guard let uuid = unmanaged?.takeRetainedValue() else { return nil }
    return CFUUIDCreateString(kCFAllocatorDefault, uuid) as String
  }

  var displayIdentifier: String {
    DisplaySettingsKey.key(
      vendor: vendorNumber,
      model: modelNumber,
      serial: serialNumber,
      uuid: cgsDisplayIdentifier,
      displayID: displayID
    )
  }

  var displayIdentifierCandidates: [String] {
    DisplaySettingsKey.candidates(for: displayIdentifier)
  }

  var displayLabel: String {
    let name = displayName ?? (CGDisplayIsBuiltin(displayID) != 0 ? "Built-in Display" : "Display")
    return name
  }

  var displayName: String? {
    var servicePortIterator = io_iterator_t()

    let status = IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IODisplayConnect"), &servicePortIterator)
    guard status == KERN_SUCCESS else {
      return nil
    }

    defer {
      IOObjectRelease(servicePortIterator)
    }

    while case let object = IOIteratorNext(servicePortIterator), object != 0 {
      defer { IOObjectRelease(object) }
      guard let dict = IODisplayCreateInfoDictionary(object, UInt32(kIODisplayOnlyPreferredName))?.takeRetainedValue() as NSDictionary? as? [String: AnyObject] else {
        continue
      }

      if dict[kDisplayVendorID] as? UInt32 == self.vendorNumber, dict[kDisplayProductID] as? UInt32 == self.modelNumber, dict[kDisplaySerialNumber] as? UInt32 == self.serialNumber {
        if let productName = dict["DisplayProductName"] as? [String: String], let firstKey = Array(productName.keys).first {
          return productName[firstKey]
        }
      }
    }

    return nil
  }
}

enum DisplaySettingsKey {
  private static let uuidMarker = "-u"

  static func key(vendor: UInt32?, model: UInt32?, serial: UInt32?, uuid: @autoclosure () -> String?, displayID: CGDirectDisplayID) -> String {
    guard let vendor, let model else { return "id-\(displayID)" }
    if let serial, serial != 0 {
      return "v\(vendor)-m\(model)-s\(serial)"
    }
    let base = "v\(vendor)-m\(model)"
    guard let uuid = uuid(), !uuid.isEmpty else { return base }
    return base + uuidMarker + uuid
  }

  static func legacyKey(for key: String) -> String? {
    guard key.hasPrefix("v"), let range = key.range(of: uuidMarker) else { return nil }
    let base = String(key[..<range.lowerBound])
    return base.isEmpty ? nil : base
  }

  static func candidates(for key: String) -> [String] {
    [key] + (legacyKey(for: key).map { [$0] } ?? [])
  }

  static func removeValue<Value>(from dictionary: inout [String: Value], for key: String, connectedKeys: [String]) {
    dictionary.removeValue(forKey: key)
    guard let legacy = legacyKey(for: key), let inherited = dictionary[legacy] else { return }
    for other in connectedKeys where other != key && legacyKey(for: other) == legacy && dictionary[other] == nil {
      dictionary[other] = inherited
    }
    dictionary.removeValue(forKey: legacy)
  }

  static func value<Value>(in dictionary: [String: Value], for key: String?) -> Value? {
    guard let key else { return nil }
    for candidate in candidates(for: key) {
      if let value = dictionary[candidate] { return value }
    }
    return nil
  }
}