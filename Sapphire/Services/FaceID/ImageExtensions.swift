//
//  ImageExtensions.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-09-13.
//

import AppKit
import Vision

extension NSImage {
    var cgImage: CGImage? {
        var imageRect = CGRect(x: 0, y: 0, width: size.width, height: size.height)
        return cgImage(forProposedRect: &imageRect, context: nil, hints: nil)
    }

    func rotated(by radians: CGFloat) -> NSImage? {
        guard let cgImage = self.cgImage else { return nil }

        let rotatedRect = CGRect(origin: . zero, size: self.size).applying(CGAffineTransform(rotationAngle:  radians))
        let rotatedSize = rotatedRect.size

        let newImage = NSImage(size: rotatedSize)
        newImage.lockFocus()

        if let context = NSGraphicsContext.current?. cgContext {
            context.translateBy(x: rotatedSize. width / 2, y: rotatedSize.height / 2)
            context.rotate(by: radians)
            let drawRect = CGRect(x: -self.size.width / 2, y: -self.size.height / 2, width: self. size.width, height: self. size.height)
            context. draw(cgImage, in: drawRect)
        }

        newImage.unlockFocus()
        return newImage
    }

    func withOvalMask() -> NSImage {
        let newImage = NSImage(size: self.size)
        newImage.lockFocus()

        guard let context = NSGraphicsContext. current else {
            newImage.unlockFocus()
            return self
        }

        context.saveGraphicsState()

        let ovalPath = NSBezierPath(ovalIn: NSRect(origin: . zero, size: self.size))
        ovalPath.addClip()

        self.draw(at: .zero, from: . zero, operation: .sourceOver, fraction: 1.0)

        context.restoreGraphicsState()

        newImage.unlockFocus()
        return newImage
    }

    func resized(to newSize: CGSize) -> NSImage? {
        let newImage = NSImage(size: newSize)
        newImage.lockFocus()
        self.draw(in: NSRect(origin: .zero, size: newSize),
                  from: NSRect(origin: .zero, size: self.size),
                  operation: .sourceOver,
                  fraction: 1.0)
        newImage.unlockFocus()
        return newImage
    }

    /// Converts NSImage to CVPixelBuffer for Vision framework processing
    func toPixelBuffer() -> CVPixelBuffer? {
        let width = Int(self.size.width)
        let height = Int(self. size.height)
        
        guard width > 0 && height > 0 else { return nil }
        
        let attrs = [
            kCVPixelBufferCGImageCompatibilityKey:  kCFBooleanTrue,
            kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue,
            kCVPixelBufferIOSurfacePropertiesKey:  [: ] as CFDictionary
        ] as CFDictionary
        
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            attrs,
            &pixelBuffer
        )
        
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            print("❌ Failed to create pixel buffer with status: \(status)")
            return nil
        }
        
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        
        guard let baseAddress = CVPixelBufferGetBaseAddress(buffer) else {
            print("❌ Failed to get pixel buffer base address")
            return nil
        }
        
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
        
        guard let context = CGContext(
            data:  baseAddress,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            print("❌ Failed to create graphics context")
            return nil
        }
        
        guard let cgImage = self.cgImage else {
            print("❌ Failed to get CGImage from NSImage")
            return nil
        }
        
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        return buffer
    }
}
