//
//  VolumeMapping.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-21

import Foundation

enum VolumeMapping {
    static func sliderToGain(_ slider: Double) -> Float {
        if slider <= 0 { return 0 }
        let t = min(slider, 1.0)
        return Float(t * t)
    }

    static func gainToSlider(_ gain: Float) -> Double {
        if gain <= 0 { return 0 }
        return Double(sqrt(min(gain, 1.0)))
    }
}