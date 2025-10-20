//
//  AppleDisplay.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-10-14.
//

import Foundation
import Cocoa

class AppleDisplay: Display {

  override func stepBrightness(isUp: Bool, isSmallIncrement: Bool) {
    let currentValue = self.getBrightness()
    let step: Float = isSmallIncrement ? 0.01 : 0.0625
    let nextValue = isUp ? min(1, currentValue + step) : max(0, currentValue - step)
    self.setBrightness(nextValue)
  }

  override func getBrightness() -> Float {
    var brightness: Float = 0.0
    if DisplayServicesGetBrightness(self.identifier, &brightness) == kCGErrorSuccess {
      return brightness
    }
    return 0.0
  }

  @discardableResult
  override func setBrightness(_ level: Float) -> Bool {
    let success = DisplayServicesSetBrightness(self.identifier, level) == kCGErrorSuccess
    if success {
      self.brightness = level
    }
    return success
  }
}