//
//  Extensions.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-07-04.
//

import SwiftUI
import AppKit
import Combine
import ScreenCaptureKit

extension Date {
    func format(as format: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = format
        return formatter.string(from: self)
    }
    func isSameDay(as otherDate: Date) -> Bool {
        return Calendar.current.isDate(self, inSameDayAs: otherDate)
    }
    var isWeekend: Bool {
        return Calendar.current.isDateInWeekend(self)
    }
}

extension Color {
    func lerp(to otherColor: Color, t: CGFloat) -> Color {
        let t_clamped = min(max(t, 0), 1)
        let from = self.resolve(in: .init())
        let to = otherColor.resolve(in: .init())
        let r = from.red + (to.red - from.red) * Float(t_clamped)
        let g = from.green + (to.green - from.green) * Float(t_clamped)
        let b = from.blue + (to.blue - from.blue) * Float(t_clamped)
        return Color(red: Double(r), green: Double(g), blue: Double(b))
    }
}

private let imageColorCache = NSCache<NSData, NSArray>()

extension NSImage {
    func getEdgeColors() -> (left: Color, right: Color, accent: Color)? {
        guard let tiffData = self.tiffRepresentation as NSData? else { return nil }

        if let cachedColors = imageColorCache.object(forKey: tiffData) as? [CGFloat], cachedColors.count == 9 {
            let left = Color(red: cachedColors[0], green: cachedColors[1], blue: cachedColors[2])
            let right = Color(red: cachedColors[3], green: cachedColors[4], blue: cachedColors[5])
            let accent = Color(red: cachedColors[6], green: cachedColors[7], blue: cachedColors[8])
            return (left, right, accent)
        }

        guard let cgImage = self.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }

        let ciImage = CIImage(cgImage: cgImage)
        let extent = ciImage.extent
        let context = CIContext()

        func getRawAverageNSColor(from rect: CGRect) -> NSColor? {
            let filter = CIFilter(name: "CIAreaAverage", parameters: [kCIInputImageKey: ciImage, kCIInputExtentKey: CIVector(cgRect: rect)])!
            guard let outputImage = filter.outputImage else { return nil }

            var bitmap = [UInt8](repeating: 0, count: 4)
            context.render(outputImage, toBitmap: &bitmap, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: nil)

            return NSColor(red: CGFloat(bitmap[0]) / 255.0, green: CGFloat(bitmap[1]) / 255.0, blue: CGFloat(bitmap[2]) / 255.0, alpha: 1.0)
        }

        let edgeWidth = extent.width * 0.1
        let leftRect = CGRect(x: extent.origin.x, y: extent.origin.y, width: edgeWidth, height: extent.height)
        let rightRect = CGRect(x: extent.maxX - edgeWidth, y: extent.origin.y, width: edgeWidth, height: extent.height)

        guard var leftNSColor = getRawAverageNSColor(from: leftRect),
              var rightNSColor = getRawAverageNSColor(from: rightRect) else {
            return nil
        }

        if leftNSColor.isSimilar(to: rightNSColor, threshold: 0.05) {
            rightNSColor = rightNSColor.madeDistinct()
        }

        let accentNSColor = leftNSColor.withBrightness(increasedBy: 0.2)

        let finalLeftColor = Color(leftNSColor.saturated(by: 0.3).withMinimumBrightness(0.55))
        let finalRightColor = Color(rightNSColor.saturated(by: 0.3).withMinimumBrightness(0.55))
        let finalAccentColor = Color(accentNSColor.saturated(by: 0.3).withMinimumBrightness(0.75))

        let leftComps = finalLeftColor.resolve(in: .init())
        let rightComps = finalRightColor.resolve(in: .init())
        let accentComps = finalAccentColor.resolve(in: .init())
        let colorsToCache: NSArray = [
            CGFloat(leftComps.red), CGFloat(leftComps.green), CGFloat(leftComps.blue),
            CGFloat(rightComps.red), CGFloat(rightComps.green), CGFloat(rightComps.blue),
            CGFloat(accentComps.red), CGFloat(accentComps.green), CGFloat(accentComps.blue)
        ]
        imageColorCache.setObject(colorsToCache, forKey: tiffData)

        return (left: finalLeftColor, right: finalRightColor, accent: finalAccentColor)
    }
}

extension NSColor {
    func withBrightness(increasedBy amount: CGFloat) -> NSColor {
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        self.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        let newBrightness = min(brightness + amount, 1.0)
        return NSColor(hue: hue, saturation: saturation, brightness: newBrightness, alpha: alpha)
    }

    func isSimilar(to otherColor: NSColor, threshold: CGFloat) -> Bool {
        var h1: CGFloat = 0, s1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var h2: CGFloat = 0, s2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        self.getHue(&h1, saturation: &s1, brightness: &b1, alpha: &a1)
        otherColor.getHue(&h2, saturation: &s2, brightness: &b2, alpha: &a2)
        let brightnessDiff = abs(b1 - b2)
        let hueDiff = abs(h1 - h2)
        return brightnessDiff < threshold && hueDiff < threshold
    }

    func madeDistinct() -> NSColor {
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        self.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        let newBrightness = min(brightness + 0.15, 1.0)
        let newSaturation = max(saturation - 0.15, 0.0)
        return NSColor(hue: hue, saturation: newSaturation, brightness: newBrightness, alpha: alpha)
    }

    func saturated(by percentage: CGFloat) -> NSColor {
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        self.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        let newSaturation = min(saturation + percentage, 1.0)
        return NSColor(hue: hue, saturation: newSaturation, brightness: brightness, alpha: alpha)
    }

    func withMinimumBrightness(_ minBrightness: CGFloat) -> NSColor {
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        self.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        if brightness < minBrightness {
            return NSColor(hue: hue, saturation: saturation, brightness: minBrightness, alpha: alpha)
        }
        return self
    }
}

enum PickerResult {
    case success(SCContentFilter)
    case failure(Error?)
}

class ContentPickerHelper: NSObject, ObservableObject, SCContentSharingPickerObserver {
    let pickerResultPublisher = PassthroughSubject<PickerResult, Never>()
    private lazy var picker = SCContentSharingPicker.shared

    override init() {
        super.init()
    }

    deinit {
        picker.remove(self)
    }

    func showPicker() {
        picker.add(self)
        picker.isActive = true
        Task {
            do {
                try await picker.present()
            } catch {
                self.pickerResultPublisher.send(.failure(error))
            }
        }
    }

    func contentSharingPicker(_ picker: SCContentSharingPicker, didUpdateWith filter: SCContentFilter, for stream: SCStream?) {
        picker.remove(self)
        picker.isActive = false
        self.pickerResultPublisher.send(.success(filter))
    }

    func contentSharingPicker(_ picker: SCContentSharingPicker, didCancelFor stream: SCStream?) {
        picker.remove(self)
        picker.isActive = false
        self.pickerResultPublisher.send(.failure(nil))
    }

    func contentSharingPickerStartDidFailWithError(_ error: Error) {
        picker.remove(self)
        picker.isActive = false
        self.pickerResultPublisher.send(.failure(error))
    }
}

@MainActor
extension NSStatusItem {
    func showMenu(_ menu: NSMenu) {
        let previous = self.menu
        self.menu = menu
        self.button?.performClick(nil)
        DispatchQueue.main.async { [weak self] in
            self?.menu = previous
        }
    }
}