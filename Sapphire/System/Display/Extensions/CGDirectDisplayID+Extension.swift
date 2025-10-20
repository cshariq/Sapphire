//
//  CGDirectDisplayID+Extension.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-10-20

import Cocoa

public extension CGDirectDisplayID {
  var vendorNumber: UInt32? {
    CGDisplayVendorNumber(self)
  }

  var modelNumber: UInt32? {
    CGDisplayModelNumber(self)
  }

  var serialNumber: UInt32? {
    CGDisplaySerialNumber(self)
  }
}