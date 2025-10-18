//
//  DDCControl.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-10-18.
//

import Foundation

final class DDCControl: Control {
    weak var display: Display?
    var isSoftware: Bool { false }
    var isDDC: Bool { true }

    init(display: Display) {
        self.display = display
    }

    func isAvailable() -> Bool {
        guard let display = display else { return false }
        return DDC.isAvailable(for: display)
    }

    func setBrightness(_ brightness: Float, oldValue: Float?) -> Bool {
        guard let display = display else { return false }
        return DDC.setBrightness(for: display.id, to: brightness)
    }

    func getBrightness() -> Float? {
        guard let display = display else { return nil }
        return DDC.getBrightness(for: display.id)
    }

    func setContrast(_ contrast: Float, oldValue: Float?) -> Bool {
        guard let display = display else { return false }
        return DDC.setContrast(for: display.id, to: contrast)
    }

    func getContrast() -> Float? {
        guard let display = display else { return nil }
        return DDC.getContrast(for: display.id)
    }

    func setPower(_ power: PowerState) -> Bool {
        guard let display = display else { return false }
        return DDC.setPower(for: display.id, to: power)
    }
}