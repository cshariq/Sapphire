//
//  AppleDisplay.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-10-14.
//

import Foundation
import Cocoa

class AppleDisplay: Display {

  override func getBrightness() -> Float {
    var brightness: Float = 0.0
    if DisplayServicesGetBrightness(self.identifier, &brightness) == kCGErrorSuccess {
      return brightness
    }
    return self.brightness
  }

  @discardableResult
  override func setBrightness(_ level: Float) -> Bool {
    let level = level.clamped(to: 0...1)
    let success = DisplayServicesSetBrightness(self.identifier, level) == kCGErrorSuccess
    if success {
      self.brightness = level
    }
    return success
  }
}