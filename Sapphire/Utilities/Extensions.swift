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
import UniformTypeIdentifiers

extension UTType {
    var sapphireFileSymbolName: String {
        if conforms(to: .image) { return "photo.fill" }
        if conforms(to: .movie) { return "video.fill" }
        if conforms(to: .audio) { return "music.note" }
        if conforms(to: .pdf) { return "doc.richtext.fill" }
        if conforms(to: .text) { return "doc.text.fill" }
        if conforms(to: .folder) { return "folder.fill" }
        if conforms(to: .archive) { return "archivebox.fill" }
        return "doc.fill"
    }
}

extension URL {
    var sapphireFileSymbolName: String {
        (try? resourceValues(forKeys: [.contentTypeKey]).contentType)?.sapphireFileSymbolName ?? "doc.fill"
    }
}

extension NSPanel {
    func configureAsSapphireOverlay(acceptsMouseMovedEvents: Bool = false) {
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        isMovable = false
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        self.acceptsMouseMovedEvents = acceptsMouseMovedEvents
    }
}

extension NSPasteboard {
    func copyString(_ string: String) {
        clearContents()
        setString(string, forType: .string)
    }
}

enum SystemPreferencesPane {
    case privacyRoot
    case accessibility
    case camera
    case screenCapture
    case bluetooth
    case allFiles

    var url: URL {
        let suffix: String
        switch self {
        case .privacyRoot: suffix = "Privacy"
        case .accessibility: suffix = "Privacy_Accessibility"
        case .camera: suffix = "Privacy_Camera"
        case .screenCapture: suffix = "Privacy_ScreenCapture"
        case .bluetooth: suffix = "Privacy_Bluetooth"
        case .allFiles: suffix = "Privacy_AllFiles"
        }
        return URL(string: "x-apple.systempreferences:com.apple.preference.security?\(suffix)")!
    }

    func open() {
        NSWorkspace.shared.open(url)
    }
}

private enum DateFormatterCache {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var formatters: [String: DateFormatter] = [:]
    nonisolated(unsafe) private static var environmentObservers: [NSObjectProtocol] = []

    static func formatter(for format: String) -> DateFormatter {
        lock.lock()
        defer { lock.unlock() }

        if let cached = formatters[format] { return cached }

        if environmentObservers.isEmpty {
            let center = NotificationCenter.default
            for name in [NSLocale.currentLocaleDidChangeNotification, .NSSystemTimeZoneDidChange] {
                environmentObservers.append(center.addObserver(forName: name, object: nil, queue: nil) { _ in
                    lock.lock()
                    formatters.removeAll()
                    lock.unlock()
                })
            }
        }

        let formatter = DateFormatter()
        formatter.dateFormat = format
        formatters[format] = formatter
        return formatter
    }
}

extension Date {
    func format(as format: String) -> String {
        DateFormatterCache.formatter(for: format).string(from: self)
    }
    func isSameDay(as otherDate: Date) -> Bool {
        return Calendar.current.isDate(self, inSameDayAs: otherDate)
    }
    var isWeekend: Bool {
        return Calendar.current.isDateInWeekend(self)
    }
}

extension Timer {
    @discardableResult
    static func scheduledCoalescing(
        withTimeInterval interval: TimeInterval,
        repeats: Bool = true,
        toleranceFraction: Double = 0.1,
        block: @escaping (Timer) -> Void
    ) -> Timer {
        let timer = Timer(timeInterval: interval, repeats: repeats, block: block)
        timer.tolerance = interval * toleranceFraction
        RunLoop.main.add(timer, forMode: .common)
        return timer
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

    func ensuringMinimumBrightness(_ minBrightness: CGFloat = 0.48) -> Color {
        let ns = NSColor(self)
        guard let rgb = ns.usingColorSpace(.sRGB) else { return self }
        let c = rgb.hsba
        guard c.brightness < minBrightness else { return self }
        return Color(NSColor(hue: c.hue, saturation: min(c.saturation, 0.85), brightness: minBrightness, alpha: c.alpha))
    }
}

private enum ImageEdgeColorCache {
    private static let cache: NSCache<NSImage, NSArray> = {
        let cache = NSCache<NSImage, NSArray>()
        cache.countLimit = 15
        return cache
    }()

    static func object(forKey key: NSImage) -> NSArray? {
        cache.object(forKey: key)
    }

    static func setObject(_ object: NSArray, forKey key: NSImage) {
        cache.setObject(object, forKey: key)
    }

    static func trim() {
        cache.removeAllObjects()
    }
}
private let ciContext = CIContext(options: [.workingColorSpace: NSNull()])

extension NSImage {
    func getEdgeColors() -> (left: Color, right: Color, accent: Color)? {
        if let cachedColors = ImageEdgeColorCache.object(forKey: self) as? [CGFloat], cachedColors.count == 9 {
            return (Color(red: cachedColors[0], green: cachedColors[1], blue: cachedColors[2]),
                    Color(red: cachedColors[3], green: cachedColors[4], blue: cachedColors[5]),
                    Color(red: cachedColors[6], green: cachedColors[7], blue: cachedColors[8]))
        }

        guard let cgImage = self.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }

        let ciImage = CIImage(cgImage: cgImage)
        let extent = ciImage.extent

        func getRawAverageNSColor(from rect: CGRect) -> NSColor? {
            let filter = CIFilter(name: "CIAreaAverage", parameters: [kCIInputImageKey: ciImage, kCIInputExtentKey: CIVector(cgRect: rect)])!
            guard let outputImage = filter.outputImage else { return nil }
            var bitmap = [UInt8](repeating: 0, count: 4)
            ciContext.render(outputImage, toBitmap: &bitmap, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: nil)
            return NSColor(red: CGFloat(bitmap[0]) / 255.0, green: CGFloat(bitmap[1]) / 255.0, blue: CGFloat(bitmap[2]) / 255.0, alpha: 1.0)
        }

        let edgeWidth = extent.width * 0.1
        let leftRect = CGRect(x: extent.origin.x, y: extent.origin.y, width: edgeWidth, height: extent.height)
        let rightRect = CGRect(x: extent.maxX - edgeWidth, y: extent.origin.y, width: edgeWidth, height: extent.height)

        guard let leftNSColor = getRawAverageNSColor(from: leftRect),
              var rightNSColor = getRawAverageNSColor(from: rightRect) else { return nil }

        if leftNSColor.isSimilar(to: rightNSColor, threshold: 0.05) {
            rightNSColor = rightNSColor.madeDistinct()
        }

        let accentNSColor = leftNSColor.withBrightness(increasedBy: 0.2)
        let (rL, gL, bL) = leftNSColor.saturated(by: 0.3).withMinimumBrightness(0.55).rgb
        let (rR, gR, bR) = rightNSColor.saturated(by: 0.3).withMinimumBrightness(0.55).rgb
        let (rA, gA, bA) = accentNSColor.saturated(by: 0.3).withMinimumBrightness(0.75).rgb

        let colorsToCache: NSArray = [rL, gL, bL, rR, gR, bR, rA, gA, bA]
        ImageEdgeColorCache.setObject(colorsToCache, forKey: self)

        return (Color(red: rL, green: gL, blue: bL),
                Color(red: rR, green: gR, blue: bR),
                Color(red: rA, green: gA, blue: bA))
    }

    static func trimEdgeColorCache() {
        ImageEdgeColorCache.trim()
    }
}

private extension NSColor {
    var rgb: (CGFloat, CGFloat, CGFloat) {
        guard let sRGB = usingColorSpace(.sRGB) else { return (0, 0, 0) }
        return (sRGB.redComponent, sRGB.greenComponent, sRGB.blueComponent)
    }
}

extension NSColor {
    var hsba: (hue: CGFloat, saturation: CGFloat, brightness: CGFloat, alpha: CGFloat) {
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        return (hue, saturation, brightness, alpha)
    }

    func withBrightness(increasedBy amount: CGFloat) -> NSColor {
        let c = hsba
        return NSColor(hue: c.hue, saturation: c.saturation, brightness: min(c.brightness + amount, 1.0), alpha: c.alpha)
    }

    func isSimilar(to otherColor: NSColor, threshold: CGFloat) -> Bool {
        let a = hsba, b = otherColor.hsba
        return abs(a.brightness - b.brightness) < threshold && abs(a.hue - b.hue) < threshold
    }

    func madeDistinct() -> NSColor {
        let c = hsba
        return NSColor(hue: c.hue, saturation: max(c.saturation - 0.15, 0.0), brightness: min(c.brightness + 0.15, 1.0), alpha: c.alpha)
    }

    func saturated(by percentage: CGFloat) -> NSColor {
        let c = hsba
        return NSColor(hue: c.hue, saturation: min(c.saturation + percentage, 1.0), brightness: c.brightness, alpha: c.alpha)
    }

    func withMinimumBrightness(_ minBrightness: CGFloat) -> NSColor {
        let c = hsba
        guard c.brightness < minBrightness else { return self }
        return NSColor(hue: c.hue, saturation: c.saturation, brightness: minBrightness, alpha: c.alpha)
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
        picker.present()
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

extension View {
    func periodicTask(every interval: Duration, perform action: @escaping @MainActor () -> Void) -> some View {
        task {
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled else { return }
                action()
            }
        }
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