//
//  Control.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-10-18.
//

import Foundation

enum PowerState {
    case on, off, toggle
}

protocol Control {
    var display: Display? { get set }
    var isSoftware: Bool { get }
    var isDDC: Bool { get }

    func setBrightness(_ brightness: Float, oldValue: Float?) -> Bool
    func setContrast(_ contrast: Float, oldValue: Float?) -> Bool
    func setPower(_ power: PowerState) -> Bool

    func getBrightness() -> Float?
    func getContrast() -> Float?

    func isAvailable() -> Bool
}