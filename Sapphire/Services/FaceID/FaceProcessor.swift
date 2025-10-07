//
//  FaceProcessor.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-09-16
//

import Vision
import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins

class FaceProcessor {
    static let shared = FaceProcessor()
    private init() {}

    // MARK: - Public Methods

    func prepareImage(from pixelBuffer: CVPixelBuffer, faceObservation: VNFaceObservation) -> NSImage? {
        let originalCIImage = CIImage(cvPixelBuffer: pixelBuffer)
        return processImage(with: originalCIImage, observation: faceObservation)
    }

    private func processImage(with ciImage: CIImage, observation: VNFaceObservation) -> NSImage? {
        guard let croppedCIImage = cropAndPadFace(from: ciImage, with: observation.boundingBox) else { return nil }

        let normalizedCIImage = simpleNormalization(for: croppedCIImage)

        guard let normalizedNSImage = nsImage(from: normalizedCIImage) else { return nil }
        guard let alignedImage = alignFace(from: normalizedNSImage, faceObservation: observation) else { return nil }

        return alignedImage.withOvalMask()
    }

    // MARK: - Simplified Normalization for Performance

    private func simpleNormalization(for image: CIImage) -> CIImage {
        guard let filter = CIFilter(name: "CIColorControls") else { return image }
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(0.05, forKey: kCIInputBrightnessKey)
        filter.setValue(1.1, forKey: kCIInputContrastKey)
        return filter.outputImage ?? image
    }

    // MARK: - Private Helper Methods

    private func cropAndPadFace(from image: CIImage, with normalizedBoundingBox: CGRect) -> CIImage? {
        let imageSize = image.extent.size
        let faceRect = VNImageRectForNormalizedRect(normalizedBoundingBox, Int(imageSize.width), Int(imageSize.height))

        var tighterRect = faceRect
        tighterRect = tighterRect.insetBy(dx: 0, dy: faceRect.height * 0.05)
        tighterRect.origin.y += faceRect.height * 0.10
        tighterRect = tighterRect.insetBy(dx: -tighterRect.width * 0.15, dy: 0)

        guard tighterRect.width > 0, tighterRect.height > 0 else { return nil }
        let safeRect = tighterRect.intersection(image.extent)
        guard safeRect.width > 0, safeRect.height > 0 else { return nil }

        return image.cropped(to: safeRect)
    }

    private func alignFace(from image: NSImage, faceObservation: VNFaceObservation) -> NSImage? {
        guard let rollNumber = faceObservation.roll else { return image }
        let rollAngle = CGFloat(truncating: rollNumber)
        return image.rotated(by: -rollAngle)
    }

    private func nsImage(from ciImage: CIImage) -> NSImage? {
        let rep = NSCIImageRep(ciImage: ciImage)
        let nsImage = NSImage(size: rep.size)
        nsImage.addRepresentation(rep)
        return nsImage
    }
}

// MARK: - NSImage Extensions
extension NSImage {
    var cgImage: CGImage? {
        var imageRect = CGRect(x: 0, y: 0, width: size.width, height: size.height)
        return cgImage(forProposedRect: &imageRect, context: nil, hints: nil)
    }

    func rotated(by radians: CGFloat) -> NSImage? {
        guard let cgImage = self.cgImage else { return nil }
        let rotatedRect = CGRect(origin: .zero, size: self.size).applying(CGAffineTransform(rotationAngle: radians))
        let rotatedSize = rotatedRect.size
        let newImage = NSImage(size: rotatedSize)
        newImage.lockFocus()
        if let context = NSGraphicsContext.current?.cgContext {
            context.translateBy(x: rotatedSize.width / 2, y: rotatedSize.height / 2)
            context.rotate(by: radians)
            let drawRect = CGRect(x: -self.size.width / 2, y: -self.size.height / 2, width: self.size.width, height: self.size.height)
            context.draw(cgImage, in: drawRect)
        }
        newImage.unlockFocus()
        return newImage
    }

    func withOvalMask() -> NSImage {
        let newImage = NSImage(size: self.size)
        newImage.lockFocus()
        guard let context = NSGraphicsContext.current else {
            newImage.unlockFocus()
            return self
        }
        context.saveGraphicsState()
        NSBezierPath(ovalIn: NSRect(origin: .zero, size: self.size)).addClip()
        self.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1.0)
        context.restoreGraphicsState()
        newImage.unlockFocus()
        return newImage
    }
}