//
//  DebugTestDisplay.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-27

import AppKit
import CoreMedia
import OSLog
import ScreenCaptureKit

@MainActor
final class DebugTestDisplay: NSObject, ObservableObject {
    static let shared = DebugTestDisplay()

    static let size = (width: 1920, height: 1080)

    @Published private(set) var isActive = false
    @Published private(set) var captureError: String?

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Sapphire", category: "DebugTestDisplay")
    private var display: CGVirtualDisplay?
    private var window: NSWindow?
    private var previewLayer: CALayer?
    private var stream: SCStream?
    private let frameQueue = DispatchQueue(label: "Sapphire.DebugTestDisplay.frames")

    func toggle() {
        isActive ? stop() : start()
    }

    func start() {
        guard display == nil else { return }

        let descriptor = CGVirtualDisplayDescriptor()
        descriptor.name = "Sapphire Test Display"
        descriptor.maxPixelsWide = UInt32(Self.size.width)
        descriptor.maxPixelsHigh = UInt32(Self.size.height)
        descriptor.sizeInMillimeters = CGSize(width: 600, height: 340)
        descriptor.vendorID = 0x5A50
        descriptor.productID = 0x7E57
        descriptor.serialNum = 1
        descriptor.queue = .main
        descriptor.terminationHandler = { [weak self] _, _ in
            Task { @MainActor in self?.stop() }
        }

        guard let virtualDisplay = CGVirtualDisplay(descriptor: descriptor) else {
            logger.error("Could not create the virtual display")
            captureError = "macOS refused to create the test display."
            return
        }
        let settings = CGVirtualDisplaySettings()
        settings.hiDPI = 0
        settings.modes = [CGVirtualDisplayMode(width: UInt32(Self.size.width), height: UInt32(Self.size.height), refreshRate: 60)]
        guard virtualDisplay.apply(settings) else {
            logger.error("Could not apply virtual display settings")
            captureError = "macOS refused the test display's mode."
            return
        }

        display = virtualDisplay
        captureError = nil
        isActive = true
        logger.info("Test display added: displayID=\(virtualDisplay.displayID, privacy: .public)")
        showWindow()
        Task { await startCapture(displayID: virtualDisplay.displayID) }
    }

    func stop() {
        guard display != nil || window != nil else { return }
        if let stream {
            self.stream = nil
            Task { try? await stream.stopCapture() }
        }
        let closingWindow = window
        window = nil
        previewLayer = nil
        closingWindow?.delegate = nil
        closingWindow?.close()
        display = nil
        isActive = false
        logger.info("Test display removed")
    }

    // MARK: - Window

    private func showWindow() {
        let aspect = CGFloat(Self.size.width) / CGFloat(Self.size.height)
        let contentSize = CGSize(width: 960, height: 960 / aspect)
        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: contentSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.title = "Test Display (\(Self.size.width) × \(Self.size.height), no notch)"
        window.contentAspectRatio = contentSize
        window.delegate = self

        let view = NSView(frame: CGRect(origin: .zero, size: contentSize))
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor
        let layer = CALayer()
        layer.frame = view.bounds
        layer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        layer.contentsGravity = .resizeAspect
        view.layer?.addSublayer(layer)
        window.contentView = view
        previewLayer = layer

        if let screen = NSScreen.main, screen.displayID != display?.displayID {
            let frame = screen.visibleFrame
            window.setFrameOrigin(CGPoint(x: frame.midX - contentSize.width / 2, y: frame.midY - contentSize.height / 2))
        }
        window.makeKeyAndOrderFront(nil)
        self.window = window
    }

    // MARK: - Capture

    private func startCapture(displayID: CGDirectDisplayID) async {
        do {
            var scDisplay: SCDisplay?
            for _ in 0..<20 where scDisplay == nil {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
                scDisplay = content.displays.first { $0.displayID == displayID }
                if scDisplay == nil { try await Task.sleep(for: .milliseconds(100)) }
            }
            guard let scDisplay, display?.displayID == displayID else { return }

            let configuration = SCStreamConfiguration()
            configuration.width = Self.size.width
            configuration.height = Self.size.height
            configuration.minimumFrameInterval = CMTime(value: 1, timescale: 30)
            configuration.showsCursor = true
            configuration.queueDepth = 3

            let stream = SCStream(filter: SCContentFilter(display: scDisplay, excludingWindows: []), configuration: configuration, delegate: self)
            try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: frameQueue)
            try await stream.startCapture()
            self.stream = stream
        } catch {
            logger.error("Test display capture failed: \(error.localizedDescription, privacy: .public)")
            captureError = "Can't show the test display: \(error.localizedDescription). Sapphire needs Screen Recording permission. The display still works; drag windows to it."
        }
    }

    fileprivate func show(_ surface: IOSurface) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        previewLayer?.contents = surface
        CATransaction.commit()
    }
}

extension DebugTestDisplay: NSWindowDelegate {
    nonisolated func windowWillClose(_ notification: Notification) {
        Task { @MainActor in self.stop() }
    }
}

extension DebugTestDisplay: SCStreamOutput, SCStreamDelegate {
    nonisolated func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen,
              let imageBuffer = sampleBuffer.imageBuffer,
              let surface = CVPixelBufferGetIOSurface(imageBuffer)?.takeUnretainedValue() else { return }
        let ioSurface = unsafeBitCast(surface, to: IOSurface.self)
        DispatchQueue.main.async { [weak self] in
            self?.show(ioSurface)
        }
    }

    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor in
            self.logger.error("Test display capture stopped: \(error.localizedDescription, privacy: .public)")
        }
    }
}