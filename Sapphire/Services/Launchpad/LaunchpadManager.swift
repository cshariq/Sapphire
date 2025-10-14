//
//  LaunchpadManager.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-09-16.
//

import Cocoa
import SwiftUI
import CoreImage.CIFilterBuiltins

extension Notification.Name {
    static let requestCloseLaunchpad = Notification.Name("requestCloseLaunchpad")
}

fileprivate extension NSImage {
    func blurred(radius: CGFloat) -> NSImage? {
        guard let tiffData = self.tiffRepresentation, let ciImage = CIImage(data: tiffData) else { return nil }
        let filter = CIFilter.gaussianBlur(); filter.inputImage = ciImage; filter.radius = Float(radius)
        guard let outputCIImage = filter.outputImage else { return nil }
        let croppedCIImage = outputCIImage.cropped(to: ciImage.extent)
        let rep = NSCIImageRep(ciImage: croppedCIImage)
        let blurredImage = NSImage(size: rep.size); blurredImage.addRepresentation(rep)
        return blurredImage
    }
}
class KeyableLaunchpadWindow: NSWindow {
    override var canBecomeKey: Bool { return true }
}
class LaunchpadGestureMonitor {
    static let shared = LaunchpadGestureMonitor()
    private var monitor: Any?; private var isMonitoring = false; private var hasProcessedGesture = false
    var onShowLaunchpad: (() -> Void)?; var onHideLaunchpad: (() -> Void)?
    private init() {}
    func startMonitoring() {
        guard !isMonitoring else { return }; isMonitoring = true
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .magnify) { [weak self] event in self?.handleMagnifyEvent(event) }
    }
    func stopMonitoring() {
        if let monitor = monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }; isMonitoring = false
    }
    private func handleMagnifyEvent(_ event: NSEvent) {
        if event.phase == .began { hasProcessedGesture = false }
        if !hasProcessedGesture && (event.phase == .changed) {
            let magnification = event.magnification
            if magnification > 0.08 { onShowLaunchpad?(); hasProcessedGesture = true }
            else if magnification < -0.08 { onHideLaunchpad?(); hasProcessedGesture = true }
        }
        if event.phase == .ended || event.phase == .cancelled { hasProcessedGesture = false }
    }
}

// MARK: - Window Controller

class LaunchpadWindowController: NSWindowController {

    private let inputInterceptor = LaunchpadInputInterceptor()
    private let gestureManager = LaunchpadGestureManager()

    private var isVisible: Bool = false {
        didSet {
            guard oldValue != isVisible else { return }

            if isVisible {
                window?.setFrame(NSScreen.main?.frame ?? .zero, display: true)
                showWindow(self)
                window?.makeKeyAndOrderFront(nil)

                self.inputInterceptor.dockFrame = self.getDockFrame()
                inputInterceptor.start()

                if let window = window {
                    gestureManager.startMonitoring(for: window)
                }
            } else {
                gestureManager.stopMonitoring()
                inputInterceptor.stop()
                window?.orderOut(nil)
            }
        }
    }

    init() {
        LaunchInterceptor.shared.startObserving()

        let screenFrame = NSScreen.main?.frame ?? .zero
        let window = KeyableLaunchpadWindow(
            contentRect: screenFrame,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        window.level = NSWindow.Level(rawValue: 20)
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.isOpaque = false
        window.backgroundColor = .clear

        super.init(window: window)

        NotificationCenter.default.addObserver(forName: .requestCloseLaunchpad, object: nil, queue: .main) { [weak self] _ in
            self?.isVisible = false
        }

        let launchpadView = LaunchpadView(
            interceptor: self.inputInterceptor,
            backgroundImage: nil,
            bottomPadding: 0
        ).environmentObject(gestureManager)

        window.contentView = NSHostingView(rootView: launchpadView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        LaunchInterceptor.shared.stopObserving()
        inputInterceptor.stop()
        let gestureManager = self.gestureManager
        Task { @MainActor in gestureManager.stopMonitoring() }
        if isVisible {
            let notificationName = "com.apple.expose.awake" as CFString
            CoreDockSendNotification(notificationName, 0)
        }
    }

    private func getDockFrame() -> CGRect {
        guard let screen = NSScreen.main else { return .zero }
        let screenFrame = screen.frame
        let visibleFrame = screen.visibleFrame
        let buffer: CGFloat = 10.0

        if visibleFrame.height < screenFrame.height {
            if visibleFrame.origin.y > 0 {
                let dockHeight = visibleFrame.origin.y
                return CGRect(x: 0, y: 0, width: screenFrame.width, height: dockHeight + buffer)
            } else {
                let dockHeight = screenFrame.height - visibleFrame.height
                return CGRect(x: 0, y: visibleFrame.maxY - buffer, width: screenFrame.width, height: dockHeight + buffer)
            }
        } else if visibleFrame.width < screenFrame.width {
            if visibleFrame.origin.x > 0 {
                let dockWidth = visibleFrame.origin.x
                return CGRect(x: 0, y: 0, width: dockWidth + buffer, height: screenFrame.height)
            } else {
                let dockWidth = screenFrame.width - visibleFrame.width
                return CGRect(x: visibleFrame.maxX - buffer, y: 0, width: dockWidth + buffer, height: screenFrame.height)
            }
        }
        return .zero
    }

    private func getDockHeightForPadding() -> CGFloat {
        guard let screen = NSScreen.main else { return 0 }
        let screenFrame = screen.frame
        let visibleFrame = screen.visibleFrame
        if visibleFrame.height < screenFrame.height && visibleFrame.origin.y > 0 { return visibleFrame.origin.y }
        return 0
    }

    func showLaunchpad() {
        guard !isVisible else { return }

        var blurredWallpaper: NSImage?
        if let url = NSWorkspace.shared.desktopImageURL(for: .main!), let image = NSImage(contentsOf: url) {
            blurredWallpaper = image.blurred(radius: 25)
        }

        var bottomPadding: CGFloat = 20
        let dockHeight = getDockHeightForPadding()
        if dockHeight > 0 { bottomPadding = dockHeight + 10 }

        let launchpadView = LaunchpadView(
            interceptor: self.inputInterceptor,
            backgroundImage: blurredWallpaper,
            bottomPadding: bottomPadding
        ).environmentObject(gestureManager)

        self.window?.contentView = NSHostingView(rootView: launchpadView)

        isVisible = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let notificationName = "com.apple.expose.awake" as CFString
            LaunchInterceptor.shared.interceptNextMissionControlLaunch = true
            CoreDockSendNotification(notificationName, 0)
        }
    }

    func hideLaunchpad() {
        isVisible = false
    }
}