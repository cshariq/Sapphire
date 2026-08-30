//
//  ProgressScrubMathTests.swift
//  Sapphire
//

import Foundation
import Testing
@testable import Sapphire

struct ProgressScrubMathTests {
    @Test func clampProgressLimitsToUnitInterval() {
        #expect(ProgressScrubMath.clampProgress(-0.2) == 0)
        #expect(ProgressScrubMath.clampProgress(0.4) == 0.4)
        #expect(ProgressScrubMath.clampProgress(1.5) == 1)
        #expect(ProgressScrubMath.clampProgress(.nan) == 0)
    }

    @Test func progressFromXMapsAndClamps() {
        #expect(ProgressScrubMath.progress(fromX: -10, width: 100) == 0)
        #expect(ProgressScrubMath.progress(fromX: 50, width: 100) == 0.5)
        #expect(ProgressScrubMath.progress(fromX: 150, width: 100) == 1)
        #expect(ProgressScrubMath.progress(fromX: 50, width: 0) == 0)
    }

    @Test func thumbCenterXInsetsAtEnds() {
        #expect(ProgressScrubMath.thumbCenterX(progress: 0, width: 100, thumbDiameter: 10) == 5)
        #expect(ProgressScrubMath.thumbCenterX(progress: 1, width: 100, thumbDiameter: 10) == 95)
        #expect(ProgressScrubMath.thumbCenterX(progress: 0.5, width: 100, thumbDiameter: 10) == 50)
    }

    @Test func formatTimeUsesMinutesAndZeroPaddedSeconds() {
        #expect(ProgressScrubMath.formatTime(0) == "0:00")
        #expect(ProgressScrubMath.formatTime(65) == "1:05")
        #expect(ProgressScrubMath.formatTime(3661) == "61:01")
        #expect(ProgressScrubMath.formatTime(.nan) == "0:00")
    }

    @Test func tooltipTimeRequiresPositiveDuration() {
        #expect(ProgressScrubMath.tooltipTime(progress: 0.5, duration: 0) == nil)
        #expect(ProgressScrubMath.tooltipTime(progress: 0.5, duration: -1) == nil)
        #expect(ProgressScrubMath.tooltipTime(progress: 0.5, duration: 120) == "1:00")
    }

    @Test func thumbDiameterScalesWithFloor() {
        #expect(ProgressScrubMath.thumbDiameter(trackHeight: 10) == 16)
        #expect(ProgressScrubMath.thumbDiameter(trackHeight: 4) == 10)
    }
}
