//
//  ProgressScrubMath.swift
//  Sapphire
//

import CoreGraphics
import Foundation

enum ProgressScrubMath {
    static func clampProgress(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(0, value), 1)
    }

    static func progress(fromX x: CGFloat, width: CGFloat) -> Double {
        guard width > 0, x.isFinite, width.isFinite else { return 0 }
        return clampProgress(Double(x / width))
    }

    static func thumbCenterX(progress: Double, width: CGFloat, thumbDiameter: CGFloat) -> CGFloat {
        guard width > 0, thumbDiameter.isFinite, width.isFinite else { return 0 }
        let radius = thumbDiameter / 2
        let usable = max(0, width - thumbDiameter)
        let p = CGFloat(clampProgress(progress))
        return radius + usable * p
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
}
