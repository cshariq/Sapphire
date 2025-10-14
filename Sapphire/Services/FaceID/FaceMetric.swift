//
//  FaceMetric.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-09-13.
//

import Vision
import Foundation

struct FacialMetricSet: Codable {
    var eyeDistance: Double = 0
    var eyeToNoseRatio: Double = 0
    var eyeToMouthRatio: Double = 0
    var faceWidthToHeightRatio: Double = 0
    var leftEyeToMouthCornerRatio: Double = 0
    var rightEyeToMouthCornerRatio: Double = 0
    var noseWidthToFaceWidthRatio: Double = 0

    static let eyeDistanceTolerance: Double = 0.15
    static let ratioTolerance: Double = 0.12

    func similarityScore(with other: FacialMetricSet) -> Double {
        let eyeDistanceDiff = abs(eyeDistance - other.eyeDistance) / max(eyeDistance, 0.001)
        let eyeToNoseRatioDiff = abs(eyeToNoseRatio - other.eyeToNoseRatio) / max(eyeToNoseRatio, 0.001)
        let eyeToMouthRatioDiff = abs(eyeToMouthRatio - other.eyeToMouthRatio) / max(eyeToMouthRatio, 0.001)
        let faceRatioDiff = abs(faceWidthToHeightRatio - other.faceWidthToHeightRatio) / max(faceWidthToHeightRatio, 0.001)
        let leftEyeDiff = abs(leftEyeToMouthCornerRatio - other.leftEyeToMouthCornerRatio) / max(leftEyeToMouthCornerRatio, 0.001)
        let rightEyeDiff = abs(rightEyeToMouthCornerRatio - other.rightEyeToMouthCornerRatio) / max(rightEyeToMouthCornerRatio, 0.001)
        let noseWidthDiff = abs(noseWidthToFaceWidthRatio - other.noseWidthToFaceWidthRatio) / max(noseWidthToFaceWidthRatio, 0.001)

        let weightedDiff = eyeDistanceDiff * 0.25 +
                          eyeToNoseRatioDiff * 0.15 +
                          eyeToMouthRatioDiff * 0.15 +
                          faceRatioDiff * 0.15 +
                          leftEyeDiff * 0.1 +
                          rightEyeDiff * 0.1 +
                          noseWidthDiff * 0.1

        return max(0.0, 1.0 - (weightedDiff / 0.3))
    }

    func matches(with other: FacialMetricSet) -> Bool {
        let score = similarityScore(with: other)
        return score > 0.85
    }
}

class FacialMetricsCalculator {

    static func calculateMetrics(from observation: VNFaceObservation) -> FacialMetricSet? {
        guard let landmarks = observation.landmarks else {
            print("️ No landmarks found in face observation")
            return nil
        }

        guard let leftEye = landmarks.leftEye?.normalizedPoints,
              let rightEye = landmarks.rightEye?.normalizedPoints,
              let nose = landmarks.nose?.normalizedPoints,
              let outerLips = landmarks.outerLips?.normalizedPoints,
              leftEye.count >= 6 && rightEye.count >= 6 && nose.count >= 4 && outerLips.count >= 8 else {
            print("️ Incomplete facial landmarks detected")
            return nil
        }

        var metrics = FacialMetricSet()

        let leftEyeCenter = calculateCentroid(from: leftEye)
        let rightEyeCenter = calculateCentroid(from: rightEye)
        let noseCenter = calculateCentroid(from: nose)
        let mouthCenter = calculateCentroid(from: outerLips)

        let mouthCorners = getMouthCorners(from: outerLips)
        let leftMouthCorner = mouthCorners.left
        let rightMouthCorner = mouthCorners.right

        let faceWidth = observation.boundingBox.width
        let faceHeight = observation.boundingBox.height

        let noseWidth = calculateNoseWidth(from: nose)

        let eyeDistance = distance(from: leftEyeCenter, to: rightEyeCenter)
        metrics.eyeDistance = eyeDistance

        metrics.eyeToNoseRatio = distance(from: midpoint(leftEyeCenter, rightEyeCenter), to: noseCenter) / eyeDistance
        metrics.eyeToMouthRatio = distance(from: midpoint(leftEyeCenter, rightEyeCenter), to: mouthCenter) / eyeDistance
        metrics.faceWidthToHeightRatio = faceWidth / faceHeight
        metrics.leftEyeToMouthCornerRatio = distance(from: leftEyeCenter, to: leftMouthCorner) / eyeDistance
        metrics.rightEyeToMouthCornerRatio = distance(from: rightEyeCenter, to: rightMouthCorner) / eyeDistance
        metrics.noseWidthToFaceWidthRatio = noseWidth / faceWidth

        return metrics
    }

    // MARK: - Helper Functions

    private static func calculateCentroid(from points: [CGPoint]) -> CGPoint {
        let sumX = points.reduce(0) { $0 + $1.x }
        let sumY = points.reduce(0) { $0 + $1.y }
        return CGPoint(x: sumX / CGFloat(points.count), y: sumY / CGFloat(points.count))
    }

    private static func getMouthCorners(from mouthPoints: [CGPoint]) -> (left: CGPoint, right: CGPoint) {
        let sortedPoints = mouthPoints.sorted { $0.x < $1.x }

        return (left: sortedPoints.first!, right: sortedPoints.last!)
    }

    private static func calculateNoseWidth(from nosePoints: [CGPoint]) -> CGFloat {
        let sortedPoints = nosePoints.sorted { $0.x < $1.x }

        return sortedPoints.last!.x - sortedPoints.first!.x
    }

    private static func midpoint(_ p1: CGPoint, _ p2: CGPoint) -> CGPoint {
        return CGPoint(x: (p1.x + p2.x) / 2.0, y: (p1.y + p2.y) / 2.0)
    }

    private static func distance(from p1: CGPoint, to p2: CGPoint) -> Double {
        let dx = p2.x - p1.x
        let dy = p2.y - p1.y
        return sqrt(Double(dx*dx + dy*dy))
    }

    static func printMetricsForDiagnostics(_ metrics: FacialMetricSet) {
        print(" FACIAL METRICS:")
        print("  Eye Distance: \(String(format: "%.4f", metrics.eyeDistance))")
        print("  Eye-to-Nose Ratio: \(String(format: "%.4f", metrics.eyeToNoseRatio))")
        print("  Eye-to-Mouth Ratio: \(String(format: "%.4f", metrics.eyeToMouthRatio))")
        print("  Face Width/Height Ratio: \(String(format: "%.4f", metrics.faceWidthToHeightRatio))")
        print("  Left Eye to Mouth Corner: \(String(format: "%.4f", metrics.leftEyeToMouthCornerRatio))")
        print("  Right Eye to Mouth Corner: \(String(format: "%.4f", metrics.rightEyeToMouthCornerRatio))")
        print("  Nose Width to Face Width: \(String(format: "%.4f", metrics.noseWidthToFaceWidthRatio))")
    }
}