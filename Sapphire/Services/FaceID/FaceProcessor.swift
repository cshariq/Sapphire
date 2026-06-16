//
//  FaceProcessor.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-09-16.
//

import Vision
import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins

class FaceProcessor {
    static let shared = FaceProcessor()
    
    // Thread-safe background Metal-backed renderer with low-latency priority options
    let ciContext = CIContext(options: [
        .useSoftwareRenderer: false,
        .priorityRequestLow: false,
        .highQualityDownsample: true
    ])
    
    private init() {}

    private let targetWidth: CGFloat = 256.0
    private let targetHeight: CGFloat = 256.0

    // Reference landmarks mathematically pre-scaled to a standard 256x256 coordinate space
    private let targetPointsBottomLeft: [CGPoint] = [
        CGPoint(x: 87.53, y: 137.84),   // Left Eye
        CGPoint(x: 168.07, y: 138.28),  // Right Eye
        CGPoint(x: 128.06, y: 92.03),   // Nose Tip
        CGPoint(x: 94.97, y: 44.88),    // Left Mouth Corner
        CGPoint(x: 161.67, y: 45.25)    // Right Mouth Corner
    ]

    // MARK: - Public Methods

    /// Performs high-precision 5-point similarity transformation alignment returning an aligned CIImage.
    /// This bypasses NSImage/CGImage conversion, maintaining processing purely on the GPU.
    func prepareImage(from pixelBuffer: CVPixelBuffer, faceObservation: VNFaceObservation) -> CIImage? {
        let width = CGFloat(CVPixelBufferGetWidth(pixelBuffer))
        let height = CGFloat(CVPixelBufferGetHeight(pixelBuffer))

        // 1. Extract 5 target landmarks in absolute pixel space (bottom-left coordinate origin)
        guard let sourcePoints = getFiveLandmarks(from: faceObservation, imageWidth: width, imageHeight: height) else {
            return nil
        }

        // 2. Compute 2D similarity transform (Scale, Rotate, Translate)
        guard let transform = SimilarityTransform.estimate(from: sourcePoints, to: targetPointsBottomLeft) else {
            return nil
        }

        // 3. Apply the forward transform and crop to the 256x256 target size
        let originalCIImage = CIImage(cvPixelBuffer: pixelBuffer)
        let warpedImage = originalCIImage.transformed(by: transform)
        let croppedImage = warpedImage.cropped(to: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))

        // 4. Return standard brightness/contrast normalized CIImage
        return simpleNormalization(for: croppedImage)
    }

    /// Extracts a perfect, widescreen center-square crop from scratch (e.g., 720x720 from a 1280x720 frame).
    /// This preserves natural aspect ratios and captures maximum background context for liveness.
    func prepareFullSquareImage(from pixelBuffer: CVPixelBuffer) -> CIImage? {
        let width = CGFloat(CVPixelBufferGetWidth(pixelBuffer))
        let height = CGFloat(CVPixelBufferGetHeight(pixelBuffer))
        
        // Calculate the maximum possible square dimensions from the video frame
        let side = min(width, height)
        let x = (width - side) / 2.0
        let y = (height - side) / 2.0
        let centerSquare = CGRect(x: x, y: y, width: side, height: side)
        
        let originalCIImage = CIImage(cvPixelBuffer: pixelBuffer)
        let cropped = originalCIImage.cropped(to: centerSquare)
        
        // Translate the coordinate origin back to (0, 0) for downstream scaling and rendering
        return cropped.transformed(by: CGAffineTransform(translationX: -x, y: -y))
    }

    /// Renders a masked UI-ready image from an aligned CIImage on demand.
    func makeUiImage(from ciImage: CIImage) -> NSImage? {
        let extent = ciImage.extent
        guard !extent.isEmpty, !extent.isInfinite, extent.width > 0, extent.height > 0 else {
            return nil
        }
        
        guard let cgImage = ciContext.createCGImage(ciImage, from: extent) else {
            return nil
        }
        
        let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: extent.width, height: extent.height))
        return nsImage.withOvalMask()
    }

    // MARK: - Private Helper Methods

    /// Maps normalized Vision landmark coordinates to pixel coordinates, outputting sorted, stable 5-point coordinates.
    private func getFiveLandmarks(from observation: VNFaceObservation, imageWidth: CGFloat, imageHeight: CGFloat) -> [CGPoint]? {
        guard let landmarks = observation.landmarks else { return nil }

        guard let leftEyePoints = landmarks.leftEye?.normalizedPoints, !leftEyePoints.isEmpty,
              let rightEyePoints = landmarks.rightEye?.normalizedPoints, !rightEyePoints.isEmpty,
              let nosePoints = landmarks.nose?.normalizedPoints, !nosePoints.isEmpty,
              let mouthPoints = landmarks.outerLips?.normalizedPoints, !mouthPoints.isEmpty else {
            return nil
        }

        // Helper: Converts a normalized point within the face's bounding box to absolute bottom-left pixel coordinates
        func mapPointToBottomLeft(_ p: CGPoint) -> CGPoint {
            let bbox = observation.boundingBox
            let imgX = bbox.origin.x + p.x * bbox.size.width
            let imgY = bbox.origin.y + p.y * bbox.size.height
            return CGPoint(x: imgX * imageWidth, y: imgY * imageHeight)
        }

        func calculateCentroid(_ points: [CGPoint]) -> CGPoint {
            var sumX: CGFloat = 0
            var sumY: CGFloat = 0
            for p in points {
                let mapped = mapPointToBottomLeft(p)
                sumX += mapped.x
                sumY += mapped.y
            }
            return CGPoint(x: sumX / CGFloat(points.count), y: sumY / CGFloat(points.count))
        }

        let leftEyeCentroid = calculateCentroid(leftEyePoints)
        let rightEyeCentroid = calculateCentroid(rightEyePoints)
        let noseCentroid = calculateCentroid(nosePoints)

        // Map mouth points and sort them on the X-axis to find the leftmost and rightmost corners
        let mappedMouth = mouthPoints.map { mapPointToBottomLeft($0) }
        let sortedMouth = mappedMouth.sorted { $0.x < $1.x }
        guard let leftMouth = sortedMouth.first, let rightMouth = sortedMouth.last else { return nil }

        // Sort eyes and mouth corners by screen coordinate X to gracefully handle mirror modes
        let sortedEyes = [leftEyeCentroid, rightEyeCentroid].sorted { $0.x < $1.x }
        let leftEye = sortedEyes[0]
        let rightEye = sortedEyes[1]

        let sortedMouthCorners = [leftMouth, rightMouth].sorted { $0.x < $1.x }
        let leftMouthCorner = sortedMouthCorners[0]
        let rightMouthCorner = sortedMouthCorners[1]

        return [leftEye, rightEye, noseCentroid, leftMouthCorner, rightMouthCorner]
    }

    private func simpleNormalization(for image: CIImage) -> CIImage {
        guard let filter = CIFilter(name: "CIColorControls") else { return image }
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(0.05, forKey: kCIInputBrightnessKey)
        filter.setValue(1.1, forKey: kCIInputContrastKey)
        return filter.outputImage ?? image
    }
}

// MARK: - Similarity Transform Estimation
struct SimilarityTransform {
    /// Computes the closed-form least-squares similarity transformation matrix (translation, scale, and rotation)
    /// to align a set of 5 points with target reference coordinates.
    static func estimate(from sourcePoints: [CGPoint], to targetPoints: [CGPoint]) -> CGAffineTransform? {
        guard sourcePoints.count == 5, targetPoints.count == 5 else { return nil }

        var srcMeanX: CGFloat = 0
        var srcMeanY: CGFloat = 0
        var dstMeanX: CGFloat = 0
        var dstMeanY: CGFloat = 0

        for i in 0..<5 {
            srcMeanX += sourcePoints[i].x
            srcMeanY += sourcePoints[i].y
            dstMeanX += targetPoints[i].x
            dstMeanY += targetPoints[i].y
        }
        srcMeanX /= 5.0
        srcMeanY /= 5.0
        dstMeanX /= 5.0
        dstMeanY /= 5.0

        var s_xx: CGFloat = 0
        var s_xu: CGFloat = 0
        var s_xv: CGFloat = 0

        for i in 0..<5 {
            let dx = sourcePoints[i].x - srcMeanX
            let dy = sourcePoints[i].y - srcMeanY
            let du = targetPoints[i].x - dstMeanX
            let dv = targetPoints[i].y - dstMeanY

            s_xx += dx * dx + dy * dy
            s_xu += dx * du + dy * dv
            s_xv += dx * dv - dy * du
        }

        guard s_xx > 0.000001 else { return nil }

        let a = s_xu / s_xx
        let b = s_xv / s_xx

        let tx = dstMeanX - (a * srcMeanX - b * srcMeanY)
        let ty = dstMeanY - (b * srcMeanX + a * srcMeanY)

        // Map computed linear coefficients to CGAffineTransform mapping:
        // u = a * x - b * y + tx
        // v = b * x + a * y + ty
        return CGAffineTransform(a: a, b: b, c: -b, d: a, tx: tx, ty: ty)
    }
}

// MARK: - NSImage Helper Extensions

extension NSImage {
    var cgImage: CGImage? {
        var imageRect = CGRect(x: 0, y: 0, width: size.width, height: size.height)
        return cgImage(forProposedRect: &imageRect, context: nil, hints: nil)
    }

    /// Thread-safe oval masking performed inside an offscreen CGContext.
    func withOvalMask() -> NSImage {
        guard let cgImage = self.cgImage else { return self }
        let width = Int(self.size.width)
        let height = Int(self.size.height)
        
        guard width > 0, height > 0 else { return self }
        
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil,
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bytesPerRow: width * 4,
                  space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            return self
        }
        
        context.addEllipse(in: CGRect(x: 0, y: 0, width: width, height: height))
        context.clip()
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        guard let maskedCGImage = context.makeImage() else { return self }
        return NSImage(cgImage: maskedCGImage, size: self.size)
    }
}
