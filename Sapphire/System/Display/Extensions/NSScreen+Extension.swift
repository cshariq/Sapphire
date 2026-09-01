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
    if let vendor = vendorNumber, let model = modelNumber {
      if let serial = serialNumber, serial != 0 {
        return "v\(vendor)-m\(model)-s\(serial)"
      }
      return "v\(vendor)-m\(model)"
    }
    return "id-\(displayID)"
  }

  var displayLabel: String {
    let name = displayName ?? (CGDisplayIsBuiltin(displayID) != 0 ? "Built-in Display" : "Display")
    return name
  }

  var displayName: String? {
    var servicePortIterator = io_iterator_t()

    let status = IOServiceGetMatchingServices(kIOMasterPortDefault, IOServiceMatching("IODisplayConnect"), &servicePortIterator)
    guard status == KERN_SUCCESS else {
      return nil
    }

    defer {
      assert(IOObjectRelease(servicePortIterator) == KERN_SUCCESS)
    }

    while case let object = IOIteratorNext(servicePortIterator), object != 0 {
      let dict = (IODisplayCreateInfoDictionary(object, UInt32(kIODisplayOnlyPreferredName)).takeRetainedValue() as NSDictionary as? [String: AnyObject])!

      if dict[kDisplayVendorID] as? UInt32 == self.vendorNumber, dict[kDisplayProductID] as? UInt32 == self.modelNumber, dict[kDisplaySerialNumber] as? UInt32 == self.serialNumber {
        if let productName = dict["DisplayProductName"] as? [String: String], let firstKey = Array(productName.keys).first {
          return productName[firstKey]!
        }
      }
    }

    return nil
  }
}