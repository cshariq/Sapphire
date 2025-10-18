//
//  AppleNativeControl.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-10-18.
//

import Foundation

final class AppleNativeControl: Control {
    weak var display: Display?
    var isSoftware: Bool { false }
    var isDDC: Bool { false }

    init(display: Display) {
        self.display = display
    }

    static func isAvailable(for display: Display) -> Bool {
        guard let id = display.id as CGDirectDisplayID? else { return false }
        return DisplayServicesCanChangeBrightness(id)
    }

    func isAvailable() -> Bool {
        guard let display = display else { return false }
        return Self.isAvailable(for: display)
    }

    func setBrightness(_ brightness: Float, oldValue: Float?) -> Bool {
        guard let display = display else { return false }
        let level = min(1.0, max(0.0, brightness / 100.0))

        if let old = oldValue {
            let oldLevel = min(1.0, max(0.0, old / 100.0))
            DisplayServicesSetBrightnessSmooth(display.id, level - oldLevel)
            return true
        }

        return DisplayServicesSetBrightness(display.id, level) == 0
    }

    func getBrightness() -> Float? {
        guard let display = display else { return nil }
        var brightness: Float = 0.0
        if DisplayServicesGetBrightness(display.id, &brightness) == 0 {
            return brightness * 100.0
        }
        return nil
    }

    func setContrast(_ contrast: Float, oldValue: Float?) -> Bool { return false }
    func getContrast() -> Float? { return nil }
    func setPower(_ power: PowerState) -> Bool { return false }
}