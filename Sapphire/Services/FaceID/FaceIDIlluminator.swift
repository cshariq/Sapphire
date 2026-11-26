//
//  FaceIDIlluminator.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-11-23
//

import AppKit
import CoreVideo

@MainActor
final class FaceIDIlluminator {
    static let shared = FaceIDIlluminator()

    private static let darkLuma: Float = 0.14
    private static let brightLuma: Float = 0.25
    private static let darkReadingsNeeded = 2
    private static let fadeDuration: TimeInterval = 0.15
    /// After the light was needed, the next Face ID session lights up at once instead of waiting
    /// for the camera, unless a bright frame was seen since.
    private static let darknessMemory: TimeInterval = 30 * 60

    private var darkReadings = 0
    private var lastDarkAt: Date?
    private var windows: [NSWindow] = []
    private var savedBrightness: Float?

    private(set) var isActive = false

    private init() {}

    nonisolated static func meanLuma(of pixelBuffer: CVPixelBuffer) -> Float? {
        guard CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_32BGRA else { return nil }
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let rowBytes = CVPixelBufferGetBytesPerRow(pixelBuffer)
        guard width > 0, height > 0 else { return nil }

        let pixels = base.assumingMemoryBound(to: UInt8.self)
        let columns = 32, rows = 24
        var total = 0
        for row in 0..<rows {
            let y = (row * 2 + 1) * height / (rows * 2)
            for column in 0..<columns {
                let x = (column * 2 + 1) * width / (columns * 2)
                let p = pixels + y * rowBytes + x * 4
                total += (114 * Int(p[0]) + 587 * Int(p[1]) + 299 * Int(p[2])) / 1000
            }
        }
        return Float(total) / Float(columns * rows * 255)
    }

    func sessionStarted() {
        guard SettingsModel.shared.current.faceIDIlluminateInDark, !isActive,
              let lastDarkAt, Date().timeIntervalSince(lastDarkAt) < Self.darknessMemory else { return }
        illuminate(need: lastNeed)
    }

    func report(luma: Float) {
        guard SettingsModel.shared.current.faceIDIlluminateInDark else { return }
        if isActive {
            adapt(to: luma)
            return
        }
        if luma > Self.brightLuma { lastDarkAt = nil }
        darkReadings = luma < Self.darkLuma ? darkReadings + 1 : 0
        guard darkReadings >= Self.darkReadingsNeeded else { return }
        lastDarkAt = Date()
        illuminate(need: Self.initialNeed(forLuma: luma))
    }

    func end() {
        darkReadings = 0
        guard isActive else { return }
        isActive = false
        lastNeed = need
        let closing = windows
        windows = []
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.fadeDuration
            closing.forEach { $0.animator().alphaValue = 0 }
        } completionHandler: {
            MainActor.assumeIsolated {
                closing.forEach {
                    LockScreenManager.shared.removeWindow($0)
                    $0.orderOut(nil)
                }
            }
        }
        if let savedBrightness {
            SystemControl.setBrightnessSmoothly(to: savedBrightness, duration: Self.fadeDuration)
            self.savedBrightness = nil
        }
    }

    // MARK: - Adaptive

    /// How much light is needed, 0...1. Full mode always uses 1.
    private var need: Float = 1
    private var lastNeed: Float = 1
    private var lastAdaptAt: CFTimeInterval = 0

    private static let targetLuma: Float = 0.3
    private static let minimumNeed: Float = 0.25

    private var isAdaptive: Bool { SettingsModel.shared.current.faceIDIlluminationLevel == .adaptive }

    private static func initialNeed(forLuma luma: Float) -> Float {
        min(1, max(minimumNeed, (targetLuma - luma) / targetLuma))
    }

    /// The camera keeps auto-exposing, so this only nudges: a still-dark frame asks for more light,
    /// a clearly bright one for less.
    private func adapt(to luma: Float) {
        guard isAdaptive else { return }
        let now = CACurrentMediaTime()
        guard now - lastAdaptAt > 0.5 else { return }
        var next = need
        if luma < Self.targetLuma * 0.75 { next = min(1, need + 0.15) }
        else if luma > Self.targetLuma * 1.6 { next = max(Self.minimumNeed, need - 0.1) }
        guard next != need else { return }
        lastAdaptAt = now
        apply(need: next, animated: true)
    }

    private func brightness(for need: Float) -> Float {
        isAdaptive ? 0.45 + 0.55 * need : 1
    }

    private static func ringFraction(for need: Float, adaptive: Bool) -> CGFloat {
        adaptive ? CGFloat(0.07 + 0.13 * need) : 0.17
    }

    private func apply(need newNeed: Float, animated: Bool) {
        need = isAdaptive ? newNeed : 1
        let fraction = Self.ringFraction(for: need, adaptive: isAdaptive)
        for window in windows {
            (window.contentView as? EdgeLightView)?.bandFraction = fraction
        }
        if let savedBrightness {
            SystemControl.setBrightnessSmoothly(to: max(savedBrightness, brightness(for: need)), duration: animated ? 0.3 : Self.fadeDuration)
        }
    }

    // MARK: - Showing

    private func illuminate(need initialNeed: Float) {
        guard let screen = Self.cameraScreen() else { return }
        isActive = true
        need = isAdaptive ? initialNeed : 1

        if SettingsModel.shared.current.faceIDIlluminationRing {
            let window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.level = .screenSaver
            window.backgroundColor = .clear
            window.isOpaque = false
            let view = EdgeLightView(frame: NSRect(origin: .zero, size: screen.frame.size))
            view.bandFraction = Self.ringFraction(for: need, adaptive: isAdaptive)
            window.contentView = view
            window.hasShadow = false
            window.ignoresMouseEvents = true
            window.sharingType = .none
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
            window.alphaValue = 0
            window.setFrame(screen.frame, display: false)
            window.orderFrontRegardless()
            LockScreenManager.shared.delegateWindow(window)
            windows = [window]

            NSAnimationContext.runAnimationGroup { context in
                context.duration = Self.fadeDuration
                window.animator().alphaValue = 1
            }
        }

        if savedBrightness == nil, CGDisplayIsBuiltin(screen.displayID) != 0 {
            let current = SystemControl.getBrightness()
            savedBrightness = current
            SystemControl.setBrightnessSmoothly(to: max(current, brightness(for: need)), duration: Self.fadeDuration)
        }
    }

    private static func cameraScreen() -> NSScreen? {
        NSScreen.screens.first { CGDisplayIsBuiltin($0.displayID) != 0 } ?? NSScreen.main
    }
}

private final class EdgeLightView: NSView {
    var bandFraction: CGFloat = 0.17 {
        didSet { if bandFraction != oldValue { needsDisplay = true } }
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let band = min(bounds.width, bounds.height) * bandFraction
        let hole = bounds.insetBy(dx: band, dy: band)
        let path = NSBezierPath(rect: bounds)
        path.append(NSBezierPath(roundedRect: hole, xRadius: band * 0.6, yRadius: band * 0.6))
        path.windingRule = .evenOdd
        NSColor(calibratedRed: 1, green: 0.96, blue: 0.9, alpha: 1).setFill()
        path.fill()
    }
}
