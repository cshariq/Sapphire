//
//  ProgressScrubMath.swift
//  Sapphire
//

import CoreGraphics
import Foundation
import SwiftUI

enum ProgressScrubMath {
    static func clampProgress(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(0, value), 1)
    }

    static func progress(fromX x: CGFloat, width: CGFloat) -> Double {
        guard width > 0, x.isFinite, width.isFinite else { return 0 }
        return clampProgress(Double(x / width))
    }

    static func formatTime(_ seconds: Double) -> String {
        let clean = seconds.isFinite ? max(0, seconds) : 0
        let total = Int(clean)
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    static func tooltipTime(progress: Double, duration: TimeInterval) -> String? {
        guard duration.isFinite, duration > 0 else { return nil }
        return formatTime(clampProgress(progress) * duration)
    }

    static func thumbDiameter(trackHeight: CGFloat, multiplier: CGFloat = 1.6, minimum: CGFloat = 10) -> CGFloat {
        guard trackHeight.isFinite, trackHeight > 0 else { return minimum }
        return max(minimum, trackHeight * multiplier)
    }

    static func color(at progress: Double, in gradient: Gradient) -> Color {
        let stops = gradient.stops
        guard let first = stops.first else { return .white }
        guard stops.count > 1 else { return first.color }

        let p = clampProgress(progress)
        let scaled = p * Double(stops.count - 1)
        let lowerIndex = min(Int(floor(scaled)), stops.count - 2)
        let upperIndex = lowerIndex + 1
        let fraction = scaled - Double(lowerIndex)
        return blend(stops[lowerIndex].color, stops[upperIndex].color, fraction)
    }

    private static func blend(_ start: Color, _ end: Color, _ amount: Double) -> Color {
        let t = clampProgress(amount)
        #if canImport(AppKit)
        let startNS = NSColor(start)
        let endNS = NSColor(end)
        guard let startRGB = startNS.usingColorSpace(.deviceRGB),
              let endRGB = endNS.usingColorSpace(.deviceRGB) else {
            return t < 0.5 ? start : end
        }
        let r = startRGB.redComponent + (endRGB.redComponent - startRGB.redComponent) * t
        let g = startRGB.greenComponent + (endRGB.greenComponent - startRGB.greenComponent) * t
        let b = startRGB.blueComponent + (endRGB.blueComponent - startRGB.blueComponent) * t
        let a = startRGB.alphaComponent + (endRGB.alphaComponent - startRGB.alphaComponent) * t
        return Color(red: r, green: g, blue: b, opacity: a)
        #else
        return t < 0.5 ? start : end
        #endif
    }
}
