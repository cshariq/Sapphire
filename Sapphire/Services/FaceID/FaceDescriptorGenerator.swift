//
//  FaceDescriptorGenerator.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-09-15
//

import Vision
import Accelerate
import CoreImage

class FaceDescriptorGenerator {
    
    static let shared = FaceDescriptorGenerator()
    
    private init() {}
    
    /// Generates a 512-dimensional face descriptor from facial landmarks and image texture
    func generateDescriptor(from observation: VNFaceObservation, pixelBuffer: CVPixelBuffer) -> [Float]? {
        guard let landmarks = observation.landmarks else { return nil }
        
        // Part 1: Geometric features from landmarks (128 dimensions)
        guard let geometricFeatures = extractGeometricFeatures(from: landmarks, observation: observation) else {
            return nil
        }
        
        // Part 2: Enhanced texture features from face regions (256 dimensions)
        guard let textureFeatures = extractEnhancedTextureFeatures(from: pixelBuffer, observation: observation, landmarks: landmarks) else {
            return nil
        }
        
        // Part 3: Local Binary Pattern features (128 dimensions)
        guard let lbpFeatures = extractLBPFeatures(from: pixelBuffer, observation: observation) else {
            return nil
        }
        
        // Combine all features
        let combined = geometricFeatures + textureFeatures + lbpFeatures
        return l2Normalize(combined)
    }
    
    // MARK: - Geometric Features (Landmark-based)
    
    private func extractGeometricFeatures(from landmarks: VNFaceLandmarks2D, observation: VNFaceObservation) -> [Float]? {
        var features: [Float] = []
        
        // Extract key landmark centroids
        guard let leftEye = landmarks.leftEye?.normalizedPoints,
              let rightEye = landmarks.rightEye?.normalizedPoints,
              let nose = landmarks.nose?.normalizedPoints,
              let mouth = landmarks.outerLips?.normalizedPoints,
              !leftEye.isEmpty, !rightEye.isEmpty, !nose.isEmpty, !mouth.isEmpty else {
            return nil
        }
        
        let leftEyeCenter = centroid(leftEye)
        let rightEyeCenter = centroid(rightEye)
        let noseCenter = centroid(nose)
        let mouthCenter = centroid(mouth)
        
        let eyeDistance = distance(leftEyeCenter, rightEyeCenter)
        guard eyeDistance > 0.001 else { return nil }
        
        // 1.  Normalized landmark positions relative to eye distance (40 features)
        var allPoints = [leftEyeCenter, rightEyeCenter, noseCenter, mouthCenter]
        
        if let leftEyebrow = landmarks.leftEyebrow?.normalizedPoints, !leftEyebrow.isEmpty {
            allPoints.append(centroid(leftEyebrow))
        }
        if let rightEyebrow = landmarks.rightEyebrow?.normalizedPoints, !rightEyebrow.isEmpty {
            allPoints.append(centroid(rightEyebrow))
        }
        if let leftPupil = landmarks.leftPupil?.normalizedPoints, !leftPupil.isEmpty {
            allPoints.append(centroid(leftPupil))
        }
        if let rightPupil = landmarks.rightPupil?.normalizedPoints, !rightPupil.isEmpty {
            allPoints.append(centroid(rightPupil))
        }
        if let noseCrest = landmarks.noseCrest?.normalizedPoints, !noseCrest.isEmpty {
            allPoints.append(centroid(noseCrest))
        }
        if let medianLine = landmarks.medianLine?.normalizedPoints, !medianLine.isEmpty {
            allPoints.append(centroid(medianLine))
        }
        
        for point in allPoints {
            features.append(Float(point.x))
            features.append(Float(point.y))
        }
        
        // 2. Pairwise distance ratios (36 features)
        let keyPoints = [leftEyeCenter, rightEyeCenter, noseCenter, mouthCenter]
        for i in 0..<keyPoints.count {
            for j in (i+1)..<keyPoints.count {
                let dist = distance(keyPoints[i], keyPoints[j])
                features.append(Float(dist / eyeDistance))
            }
        }
        
        // 3. Triangle areas for geometric relationships (12 features)
        let triangles: [(CGPoint, CGPoint, CGPoint)] = [
            (leftEyeCenter, rightEyeCenter, noseCenter),
            (leftEyeCenter, rightEyeCenter, mouthCenter),
            (leftEyeCenter, noseCenter, mouthCenter),
            (rightEyeCenter, noseCenter, mouthCenter)
        ]
        
        for triangle in triangles {
            let area = triangleArea(triangle.0, triangle.1, triangle.2)
            features.append(Float(area / (eyeDistance * eyeDistance)))
        }
        
        // 4. Detailed mouth features (16 features)
        if mouth.count >= 12 {
            let mouthWidth = distance(mouth[0], mouth[6])
            let mouthHeight = distance(mouth[3], mouth[9])
            features.append(Float(mouthWidth / eyeDistance))
            features.append(Float(mouthHeight / eyeDistance))
            features.append(Float(mouthHeight / mouthWidth)) // aspect ratio
            
            // Mouth corner positions
            for i in [0, 3, 6, 9] {
                features.append(Float(mouth[i].x))
                features.append(Float(mouth[i].y))
            }
        } else {
            features.append(contentsOf: [Float](repeating: 0, count: 11))
        }
        
        // 5. Eye details (12 features)
        if leftEye.count >= 8 && rightEye.count >= 8 {
            let leftEyeWidth = distance(leftEye[0], leftEye[4])
            let leftEyeHeight = distance(leftEye[2], leftEye[6])
            let rightEyeWidth = distance(rightEye[0], rightEye[4])
            let rightEyeHeight = distance(rightEye[2], rightEye[6])
            
            features.append(Float(leftEyeWidth / eyeDistance))
            features.append(Float(leftEyeHeight / eyeDistance))
            features.append(Float(rightEyeWidth / eyeDistance))
            features.append(Float(rightEyeHeight / eyeDistance))
            features.append(Float(leftEyeHeight / leftEyeWidth))
            features.append(Float(rightEyeHeight / rightEyeWidth))
        } else {
            features.append(contentsOf: [Float](repeating: 0, count: 6))
        }
        
        // 6. Nose dimensions (6 features)
        if nose.count >= 9 {
            let noseWidth = distance(nose[0], nose[nose.count - 1])
            let noseHeight = distance(nose[nose.count / 2], mouthCenter)
            features.append(Float(noseWidth / eyeDistance))
            features.append(Float(noseHeight / eyeDistance))
        } else {
            features.append(contentsOf: [Float](repeating: 0, count: 2))
        }
        
        // 7. Pose information (3 features)
        features.append(Float(observation.roll?.doubleValue ?? 0))
        features.append(Float(observation.yaw?.doubleValue ?? 0))
        features.append(Float(observation.pitch?.doubleValue ?? 0))
        
        // Pad or trim to exactly 128
        while features.count < 128 {
            features.append(0)
        }
        
        return Array(features.prefix(128))
    }
    
    // MARK: - Enhanced Texture Features
    
    private func extractEnhancedTextureFeatures(from pixelBuffer: CVPixelBuffer, observation: VNFaceObservation, landmarks: VNFaceLandmarks2D) -> [Float]? {
        
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            return nil
        }
        
        let faceRect = VNImageRectForNormalizedRect(observation.boundingBox, width, height)
        
        var features: [Float] = []
        
        // Extract high-resolution texture from key regions (192 features)
        let regions: [(String, [CGPoint]?)] = [
            ("leftEye", landmarks.leftEye?.normalizedPoints),
            ("rightEye", landmarks.rightEye?.normalizedPoints),
            ("nose", landmarks.nose?.normalizedPoints),
            ("mouth", landmarks.outerLips?.normalizedPoints),
            ("leftCheek", landmarks.leftEye?.normalizedPoints), // We'll offset this
            ("rightCheek", landmarks.rightEye?.normalizedPoints) // We'll offset this
        ]
        
        for (regionName, points) in regions {
            if let points = points, !points.isEmpty {
                var regionPoints = points
                
                // For cheeks, offset the eye regions
                if regionName == "leftCheek" {
                    regionPoints = points.map { CGPoint(x: $0.x - 0.1, y: $0.y - 0.15) }
                } else if regionName == "rightCheek" {
                    regionPoints = points.map { CGPoint(x: $0.x + 0.1, y: $0.y - 0.15) }
                }
                
                let regionFeatures = extractHighResRegionTexture(
                    baseAddress: baseAddress,
                    width: width,
                    height: height,
                    bytesPerRow: bytesPerRow,
                    points: regionPoints,
                    faceRect: faceRect
                )
                features.append(contentsOf: regionFeatures)
            } else {
                features.append(contentsOf: [Float](repeating: 0, count: 32))
            }
        }
        
        // Extract texture histograms (64 features)
        let histogramFeatures = extractTextureHistogram(
            baseAddress: baseAddress,
            width: width,
            height: height,
            bytesPerRow: bytesPerRow,
            faceRect: faceRect
        )
        features.append(contentsOf: histogramFeatures)
        
        // Ensure exactly 256 features
        while features.count < 256 {
            features.append(0)
        }
        
        return Array(features.prefix(256))
    }
    
    private func extractHighResRegionTexture(baseAddress: UnsafeMutableRawPointer, width: Int, height: Int, bytesPerRow: Int, points: [CGPoint], faceRect: CGRect) -> [Float] {
        
        let regionBounds = boundingBox(for: points)
        let pixelRect = CGRect(
            x: faceRect.origin.x + regionBounds.origin.x * faceRect.width,
            y: faceRect.origin.y + regionBounds.origin.y * faceRect.height,
            width: regionBounds.width * faceRect.width,
            height: regionBounds.height * faceRect.height
        )
        
        var samples: [Float] = []
        let gridSize = 8 // Increased from 4 to 8 for more detail
        
        for row in 0..<gridSize {
            for col in 0..<gridSize {
                let x = Int(pixelRect.origin.x + (CGFloat(col) + 0.5) * pixelRect.width / CGFloat(gridSize))
                let y = Int(pixelRect.origin.y + (CGFloat(row) + 0.5) * pixelRect.height / CGFloat(gridSize))
                
                if x >= 1 && x < width - 1 && y >= 1 && y < height - 1 {
                    // Extract pixel value
                    let offset = y * bytesPerRow + x * 4
                    let pixel = baseAddress.advanced(by: offset)
                    let b = pixel.load(fromByteOffset: 0, as: UInt8.self)
                    let g = pixel.load(fromByteOffset: 1, as: UInt8.self)
                    let r = pixel.load(fromByteOffset: 2, as: UInt8.self)
                    
                    // Grayscale value
                    let gray = Float(r) * 0.299 + Float(g) * 0.587 + Float(b) * 0.114
                    samples.append(gray / 255.0)
                    
                    // Compute gradient magnitude for texture
                    let offset_right = y * bytesPerRow + (x + 1) * 4
                    let offset_down = (y + 1) * bytesPerRow + x * 4
                    
                    let pixel_right = baseAddress.advanced(by: offset_right)
                    let pixel_down = baseAddress.advanced(by: offset_down)
                    
                    let r_right = pixel_right.load(fromByteOffset: 2, as: UInt8.self)
                    let g_right = pixel_right.load(fromByteOffset: 1, as: UInt8.self)
                    let b_right = pixel_right.load(fromByteOffset: 0, as: UInt8.self)
                    
                    let r_down = pixel_down.load(fromByteOffset: 2, as: UInt8.self)
                    let g_down = pixel_down.load(fromByteOffset: 1, as: UInt8.self)
                    let b_down = pixel_down.load(fromByteOffset: 0, as: UInt8.self)
                    
                    let gray_right = Float(r_right) * 0.299 + Float(g_right) * 0.587 + Float(b_right) * 0.114
                    let gray_down = Float(r_down) * 0.299 + Float(g_down) * 0.587 + Float(b_down) * 0.114
                    
                    let gradient = sqrt(pow(gray_right - gray, 2) + pow(gray_down - gray, 2))
                    samples.append(gradient / 255.0)
                } else {
                    samples.append(0)
                    samples.append(0)
                }
            }
        }
        
        // Normalize samples
        let mean = samples.reduce(0, +) / Float(samples.count)
        let vintelligencence = samples.map { pow($0 - mean, 2) }.reduce(0, +) / Float(samples.count)
        let std = sqrt(vintelligencence)
        
        if std > 0.001 {
            return samples.map { ($0 - mean) / std }
        }
        
        // Pad to 32
        while samples.count < 32 {
            samples.append(0)
        }
        
        return Array(samples.prefix(32))
    }
    
    private func extractTextureHistogram(baseAddress: UnsafeMutableRawPointer, width: Int, height: Int, bytesPerRow: Int, faceRect: CGRect) -> [Float] {
        
        var histogram = [Float](repeating: 0, count: 64)
        let bins = 64
        var totalPixels = 0
        
        let startX = max(0, Int(faceRect.origin.x))
        let startY = max(0, Int(faceRect.origin.y))
        let endX = min(width, Int(faceRect.origin.x + faceRect.width))
        let endY = min(height, Int(faceRect.origin.y + faceRect.height))
        
        for y in stride(from: startY, to: endY, by: 2) {
            for x in stride(from: startX, to: endX, by: 2) {
                let offset = y * bytesPerRow + x * 4
                let pixel = baseAddress.advanced(by: offset)
                let b = pixel.load(fromByteOffset: 0, as: UInt8.self)
                let g = pixel.load(fromByteOffset: 1, as: UInt8.self)
                let r = pixel.load(fromByteOffset: 2, as: UInt8.self)
                
                let gray = Float(r) * 0.299 + Float(g) * 0.587 + Float(b) * 0.114
                let binIndex = min(bins - 1, Int(gray / 255.0 * Float(bins)))
                histogram[binIndex] += 1
                totalPixels += 1
            }
        }
        
        // Normalize histogram
        if totalPixels > 0 {
            histogram = histogram.map { $0 / Float(totalPixels) }
        }
        
        return histogram
    }
    
    // MARK: - Local Binary Pattern Features
    
    private func extractLBPFeatures(from pixelBuffer: CVPixelBuffer, observation: VNFaceObservation) -> [Float]? {
        
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            return nil
        }
        
        let faceRect = VNImageRectForNormalizedRect(observation.boundingBox, width, height)
        
        var lbpHistogram = [Float](repeating: 0, count: 128)
        var totalPatterns = 0
        
        let startX = max(2, Int(faceRect.origin.x))
        let startY = max(2, Int(faceRect.origin.y))
        let endX = min(width - 2, Int(faceRect.origin.x + faceRect.width))
        let endY = min(height - 2, Int(faceRect.origin.y + faceRect.height))
        
        for y in stride(from: startY, to: endY, by: 3) {
            for x in stride(from: startX, to: endX, by: 3) {
                let lbpValue = computeLBP(baseAddress: baseAddress, x: x, y: y, bytesPerRow: bytesPerRow)
                let binIndex = min(127, lbpValue % 128)
                lbpHistogram[binIndex] += 1
                totalPatterns += 1
            }
        }
        
        // Normalize LBP histogram
        if totalPatterns > 0 {
            lbpHistogram = lbpHistogram.map { $0 / Float(totalPatterns) }
        }
        
        return lbpHistogram
    }
    
    private func computeLBP(baseAddress: UnsafeMutableRawPointer, x: Int, y: Int, bytesPerRow: Int) -> Int {
        let centerOffset = y * bytesPerRow + x * 4
        let centerPixel = baseAddress.advanced(by: centerOffset)
        let centerR = centerPixel.load(fromByteOffset: 2, as: UInt8.self)
        let centerG = centerPixel.load(fromByteOffset: 1, as: UInt8.self)
        let centerB = centerPixel.load(fromByteOffset: 0, as: UInt8.self)
        let centerGray = grayscaleValue(red: centerR, green: centerG, blue: centerB)
        
        var lbpValue = 0
        let neighbors: [(Int, Int)] = [
            (-1, -1), (0, -1), (1, -1),
            (1, 0), (1, 1), (0, 1),
            (-1, 1), (-1, 0)
        ]
        
        for (i, (dx, dy)) in neighbors.enumerated() {
            let nx = x + dx
            let ny = y + dy
            let offset = ny * bytesPerRow + nx * 4
            let pixel = baseAddress.advanced(by: offset)
            let r = pixel.load(fromByteOffset: 2, as: UInt8.self)
            let g = pixel.load(fromByteOffset: 1, as: UInt8.self)
            let b = pixel.load(fromByteOffset: 0, as: UInt8.self)
            let gray = grayscaleValue(red: r, green: g, blue: b)
            
            if gray >= centerGray {
                lbpValue |= (1 << i)
            }
        }
        
        return lbpValue
    }
    
    // MARK: - Helper Functions
    
    private func centroid(_ points: [CGPoint]) -> CGPoint {
        let sum = points.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
        let count = CGFloat(points.count)
        return CGPoint(x: sum.x / count, y: sum.y / count)
    }
    
    private func distance(_ p1: CGPoint, _ p2: CGPoint) -> Double {
        let dx = p2.x - p1.x
        let dy = p2.y - p1.y
        return sqrt(Double(dx * dx + dy * dy))
    }
    
    private func triangleArea(_ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint) -> Double {
        return abs(Double(
            p1.x * (p2.y - p3.y) +
            p2.x * (p3.y - p1.y) +
            p3.x * (p1.y - p2.y)
        )) / 2.0
    }
    
    private func boundingBox(for points: [CGPoint]) -> CGRect {
        guard !points.isEmpty else { return .zero }
        
        var minX = points[0].x
        var maxX = points[0].x
        var minY = points[0].y
        var maxY = points[0].y
        
        for point in points {
            minX = min(minX, point.x)
            maxX = max(maxX, point.x)
            minY = min(minY, point.y)
            maxY = max(maxY, point.y)
        }
        
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private func grayscaleValue(red: UInt8, green: UInt8, blue: UInt8) -> Int {
        let redComponent = Float(red) * 0.299
        let greenComponent = Float(green) * 0.587
        let blueComponent = Float(blue) * 0.114
        return Int(redComponent + greenComponent + blueComponent)
    }
    
    private func l2Normalize(_ vector: [Float]) -> [Float] {
        let norm = sqrt(vector.map { $0 * $0 }.reduce(0, +))
        guard norm > 0 else { return vector }
        return vector.map { $0 / norm }
    }
}

