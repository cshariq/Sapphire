//
//  NotchHostWindowSizer.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-10-05

import AppKit

struct NotchHostWindowExtent: Equatable {
    var isFull: Bool
    var notchSize: CGSize
    var notchTopOffset: CGFloat
    var collapsedHeight: CGFloat
    var fullBandInset: CGFloat
    var margin: CGFloat = NotchHostWindowSizer.fittedMargin
}

@MainActor
final class NotchHostWindowSizer {
    nonisolated static let fittedMargin: CGFloat = 48
    static let shrinkDelay: Duration = .seconds(4)
    private static let settleSlack: TimeInterval = 0.05

    var onFrameChange: (() -> Void)?

    private weak var window: NSWindow?
    private var extent: NotchHostWindowExtent?
    private var settledNotchSize: CGSize?
    private var shrinkTask: Task<Void, Never>?
    private weak var morphEngine: NotchMorphEngine?

    init(window: NSWindow?) {
        self.window = window
    }

    func attach(_ engine: NotchMorphEngine) {
        guard morphEngine !== engine else { return }
        morphEngine?.removeObserver(self)
        morphEngine = engine
        engine.addObserver(self) { [weak self] event in
            guard event == .retarget else { return }
            DispatchQueue.main.async {
                guard let self, let extent = self.extent else { return }
                self.update(extent)
            }
        }
    }

    deinit {
        shrinkTask?.cancel()
    }

    func update(_ newExtent: NotchHostWindowExtent) {
        extent = newExtent
        guard let window, let screen = assignedScreen(of: window) else { return }
        place(newExtent, in: window, on: screen)
    }

    @discardableResult
    func reapply(on screen: NSScreen? = nil) -> Bool {
        guard let extent, let window, let screen = screen ?? assignedScreen(of: window) else { return false }
        place(extent, in: window, on: screen)
        return true
    }

    private func place(_ newExtent: NotchHostWindowExtent, in window: NSWindow, on screen: NSScreen) {
        let target = Self.frame(for: newExtent, on: screen)
        let growth = Self.frame(
            for: Self.growthExtent(newExtent, from: settledNotchSize ?? newExtent.notchSize),
            on: screen
        )
        let current = window.frame
        let now = CACurrentMediaTime()
        var peak = growth
        if let morphEngine, morphEngine.isAnimating(at: now), !newExtent.isFull {
            var peakExtent = newExtent
            let size = morphEngine.peakSize(from: now)
            peakExtent.notchSize = CGSize(
                width: max(newExtent.notchSize.width, size.width),
                height: max(newExtent.notchSize.height, size.height)
            )
            peak = Self.frame(for: peakExtent, on: screen)
        }

        let staysOnScreen = Self.isWithin(current, screen.frame)
        let grown = Self.centered(
            width: max(growth.width, peak.width, staysOnScreen ? current.width : 0),
            height: max(growth.height, peak.height, staysOnScreen ? current.height : 0),
            screenFrame: screen.frame,
            scale: screen.backingScaleFactor
        )
        shrinkTask?.cancel()
        shrinkTask = nil
        apply(grown, to: window, on: screen)

        guard !Self.approximatelyEqual(grown, target) else {
            settledNotchSize = newExtent.notchSize
            return
        }
        shrinkTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.shrinkDelay)
            while !Task.isCancelled, let end = self?.morphEngine?.endTime {
                let remaining = end - CACurrentMediaTime()
                guard remaining > 0 else { break }
                try? await Task.sleep(for: .seconds(remaining + Self.settleSlack))
            }
            guard !Task.isCancelled, let self else { return }
            self.shrinkTask = nil
            self.settle()
        }
    }

    private func settle() {
        guard let extent, let window, let screen = assignedScreen(of: window) else { return }
        settledNotchSize = extent.notchSize
        let fitted = Self.frame(for: extent, on: screen)
        if Self.isWithin(window.frame, screen.frame),
           window.frame.width >= fitted.width, window.frame.height >= fitted.height,
           abs(window.frame.midX - fitted.midX) <= 0.5, abs(window.frame.maxY - fitted.maxY) <= 0.5 {
            return
        }
        guard !Self.isSlightlyLarger(window.frame, than: fitted, slack: Self.shrinkSlack) else { return }
        apply(fitted, to: window, on: screen)
    }

    nonisolated static let shrinkSlack = CGSize(width: 240, height: 160)

    nonisolated static func isSlightlyLarger(_ frame: NSRect, than fitted: NSRect, slack: CGSize) -> Bool {
        guard abs(frame.midX - fitted.midX) <= 0.5, abs(frame.maxY - fitted.maxY) <= 0.5 else { return false }
        let extraWidth = frame.width - fitted.width
        let extraHeight = frame.height - fitted.height
        return extraWidth >= -0.5 && extraHeight >= -0.5 && extraWidth <= slack.width && extraHeight <= slack.height
    }

    nonisolated static func isPlaced(_ frame: NSRect, onScreen screenFrame: NSRect) -> Bool {
        isWithin(frame, screenFrame)
            && abs(frame.midX - screenFrame.midX) <= 1
            && abs(frame.maxY - screenFrame.maxY) <= 1
    }

    nonisolated static func isWithin(_ frame: NSRect, _ screenFrame: NSRect) -> Bool {
        !frame.isEmpty && screenFrame.insetBy(dx: -1, dy: -1).contains(frame)
    }

    static func growthExtent(_ extent: NotchHostWindowExtent, from origin: CGSize) -> NotchHostWindowExtent {
        guard !extent.isFull else { return extent }
        var grown = extent
        grown.notchSize = CGSize(
            width: extent.notchSize.width + max(0, extent.notchSize.width - origin.width),
            height: extent.notchSize.height + max(0, extent.notchSize.height - origin.height)
        )
        return grown
    }

    private func assignedScreen(of window: NSWindow) -> NSScreen? {
        let assigned = (window as? DynamicFocusWindow)?.displayID ?? 0
        let screens = NSScreen.screens
        let index = Self.screenIndex(
            assignedDisplayID: assigned,
            displayIDs: screens.map(\.displayID),
            windowScreenIndex: window.screen.flatMap { screen in screens.firstIndex { $0 === screen } }
        )
        return index.map { screens[$0] }
    }

    static func screenIndex(
        assignedDisplayID: CGDirectDisplayID,
        displayIDs: [CGDirectDisplayID],
        windowScreenIndex: Int?
    ) -> Int? {
        if assignedDisplayID != 0 {
            return displayIDs.firstIndex(of: assignedDisplayID)
        }
        return windowScreenIndex
    }

    private func apply(_ frame: NSRect, to window: NSWindow, on screen: NSScreen) {
        let container = window.contentView as? NotchStageContainerView
        let stageSize = container.flatMap { container in
            extent.map { extent in
                Self.stageSize(
                    current: container.stageSize,
                    extent: extent,
                    windowSize: frame.size,
                    screenFrame: screen.frame,
                    visibleFrame: screen.visibleFrame,
                    scale: screen.backingScaleFactor
                )
            }
        }
        let stageChanges = stageSize.map { size in
            guard let container else { return false }
            return abs(size.width - container.stageSize.width) > 0.5 || abs(size.height - container.stageSize.height) > 0.5
        } ?? false
        let frameChanges = !Self.approximatelyEqual(frame, window.frame)
        guard stageChanges || frameChanges else { return }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer {
            CATransaction.commit()
            CATransaction.flush()
        }
        if let container, let stageSize {
            container.setStageSize(stageSize)
        }
        guard frameChanges else { return }
        if window.isVisible, Self.isOverviewShowing() {
            window.orderOut(nil)
            window.setFrame(frame, display: false, animate: false)
            (NSApp.delegate as? AppDelegate)?.reassertNotchSpaceMembership(window)
            window.orderFrontRegardless()
        } else {
            window.setFrame(frame, display: false, animate: false)
        }
        onFrameChange?()
    }

    // MARK: Overview detection

    nonisolated static let overviewOwner = "WindowManager"
    nonisolated static let overviewLayer = 19

    nonisolated static func isOverviewWindow(
        owner: String?,
        layer: Int?,
        alpha: Double? = nil,
        size: CGSize?,
        screenSizes: [CGSize]
    ) -> Bool {
        guard owner == overviewOwner, layer == overviewLayer, (alpha ?? 1) > 0, let size else { return false }
        return screenSizes.contains { screen in
            screen.width > 0 && screen.height > 0
                && size.width >= screen.width * 0.9 && size.height >= screen.height * 0.9
        }
    }

    private static func isOverviewShowing() -> Bool {
        guard let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] else { return false }
        let screenSizes = NSScreen.screens.map(\.frame.size)
        return info.contains { entry in
            let bounds = (entry[kCGWindowBounds as String] as? NSDictionary)
                .flatMap { CGRect(dictionaryRepresentation: $0 as CFDictionary) }
            return isOverviewWindow(
                owner: entry[kCGWindowOwnerName as String] as? String,
                layer: entry[kCGWindowLayer as String] as? Int,
                alpha: entry[kCGWindowAlpha as String] as? Double,
                size: bounds?.size,
                screenSizes: screenSizes
            )
        }
    }

    static func stageSize(
        current: CGSize?,
        extent: NotchHostWindowExtent,
        windowSize: CGSize,
        screenFrame: CGRect,
        visibleFrame: CGRect,
        scale: CGFloat = 2
    ) -> CGSize {
        let width = NotchDisplayMetrics.snapToEvenPixels(ceil(screenFrame.width) + 0.5 / max(scale, 1), scale: max(scale, 1))
        var fullExtent = extent
        fullExtent.isFull = true
        var fittedExtent = extent
        fittedExtent.isFull = false
        let full = frame(for: fullExtent, screenFrame: screenFrame, visibleFrame: visibleFrame)
        let fitted = frame(for: fittedExtent, screenFrame: screenFrame, visibleFrame: visibleFrame)
        var height = max(full.height, fitted.height, ceil(windowSize.height))
        if let current, abs(current.width - width) <= 0.5 {
            height = max(height, current.height)
        }
        return CGSize(width: width, height: height)
    }

    static func frame(for extent: NotchHostWindowExtent, on screen: NSScreen) -> NSRect {
        frame(for: extent, screenFrame: screen.frame, visibleFrame: screen.visibleFrame, scale: screen.backingScaleFactor)
    }

    static func frame(for extent: NotchHostWindowExtent, screenFrame: CGRect, visibleFrame: CGRect, scale: CGFloat = 2) -> NSRect {
        if extent.isFull {
            let baseline = max(
                extent.collapsedHeight + extent.fullBandInset + 24,
                screenFrame.height * 0.42
            )
            let required = extent.notchSize.height + extent.fullBandInset + 36
            let height = ceil(min(max(baseline, required), max(baseline, visibleFrame.height)))
            return NSRect(
                x: screenFrame.minX,
                y: screenFrame.maxY - height,
                width: ceil(screenFrame.width),
                height: height
            )
        }
        let margin = max(0, extent.margin)
        var width = ceil(extent.notchSize.width + 2 * margin)
        if width.truncatingRemainder(dividingBy: 2) != 0 { width += 1 }
        let height = ceil(max(0, extent.notchTopOffset) + extent.notchSize.height + margin)
        return centered(width: min(width, ceil(screenFrame.width)), height: height, screenFrame: screenFrame, scale: scale)
    }

    static func centered(width: CGFloat, height: CGFloat, screenFrame: CGRect, scale: CGFloat) -> NSRect {
        if width >= ceil(screenFrame.width) {
            return NSRect(x: screenFrame.minX, y: screenFrame.maxY - height, width: ceil(screenFrame.width), height: height)
        }
        let snapped = min(NotchDisplayMetrics.snapToEvenPixels(ceil(width), scale: scale), ceil(screenFrame.width))
        let w = snapped < ceil(width) ? snapped + 2 / max(scale, 1) : snapped
        return NSRect(
            x: NotchDisplayMetrics.centeredOriginX(width: w, midX: screenFrame.midX, scale: scale),
            y: screenFrame.maxY - height,
            width: w,
            height: height
        )
    }

    private static func approximatelyEqual(_ a: NSRect, _ b: NSRect) -> Bool {
        abs(a.minX - b.minX) <= 0.5 && abs(a.minY - b.minY) <= 0.5
            && abs(a.width - b.width) <= 0.5 && abs(a.height - b.height) <= 0.5
    }
}