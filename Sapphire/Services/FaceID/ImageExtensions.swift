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

        let ovalPath = NSBezierPath(ovalIn: NSRect(origin: .zero, size: self.size))
        ovalPath.addClip()

        self.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1.0)

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
}