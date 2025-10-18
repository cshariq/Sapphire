//
//  SpoofDetector.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-09-17
//

import Vision
import Foundation

enum SpoofConfidence {
    case high, medium, low
}

class SpoofDetector {

    private var poseHistory: [(yaw: Double, pitch: Double, roll: Double)] = []
    private let poseHistoryLimit = 5

    private let movementThreshold: Double = 0.005

    func getSpoofConfidence(observation: VNFaceObservation, depthScore: Double, metricsScore: Double, faceSimilarity: Double) -> SpoofConfidence {

        guard depthScore > 0.40 else {
            print(" SPOOF DETECTED: Very low depth score (\(String(format: "%.2f", depthScore))). Likely a 2D image.")
            return .low
        }

        let naturalMovementScore = calculateNaturalMovement(observation: observation)

        let depthWeight = 0.4
        let metricsWeight = 0.3
        let similarityWeight = 0.5
        var finalScore = 0.0

        if depthScore >= 0.9 || naturalMovementScore > 0.15 {
            finalScore = (depthScore * depthWeight) + (metricsScore * metricsWeight) + (faceSimilarity * similarityWeight)
        } else {
            finalScore = (depthScore * 0.5) + (metricsScore * 0.25) + (naturalMovementScore * 0.25)
        }

        print("Combined Score: \(String(format: "%.2f", finalScore)) (Depth: \(String(format: "%.2f", depthScore)), Metrics: \(String(format: "%.2f", metricsScore)), Similarity: \(String(format: "%.2f", faceSimilarity)), Movement: \(String(format: "%.2f", naturalMovementScore)))")

        if finalScore > 0.8 {
            return .high
        } else if finalScore > 0.65 {
            return .medium
        } else {
            print(" SPOOF WARNING: Low combined anti-spoof score (\(String(format: "%.2f", finalScore))).")
            return .low
        }
    }

    private func calculateNaturalMovement(observation: VNFaceObservation) -> Double {
        guard let yaw = observation.yaw?.doubleValue,
              let pitch = observation.pitch?.doubleValue,
              let roll = observation.roll?.doubleValue else {
            return 0.0
        }

        let currentPose = (yaw: yaw, pitch: pitch, roll: roll)

        poseHistory.append(currentPose)
        if poseHistory.count > poseHistoryLimit {
            poseHistory.removeFirst()
        }

        guard poseHistory.count > 1 else {
            return 0.5
        }

        let yawAvg = poseHistory.map { $0.yaw }.reduce(0, +) / Double(poseHistory.count)
        let pitchAvg = poseHistory.map { $0.pitch }.reduce(0, +) / Double(poseHistory.count)

        let yawVariance = poseHistory.map { pow($0.yaw - yawAvg, 2) }.reduce(0, +) / Double(poseHistory.count)
        let pitchVariance = poseHistory.map { pow($0.pitch - pitchAvg, 2) }.reduce(0, +) / Double(poseHistory.count)

        let totalMovement = sqrt(yawVariance) + sqrt(pitchVariance)

        return min(totalMovement / movementThreshold, 1.0)
    }
}