//
//  NotchDisplayMetrics.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-10-08

import AppKit
import SwiftUI

struct NotchDisplayMetrics: Equatable {
    struct Input: Equatable {
        var displayID: CGDirectDisplayID
        var frame: CGRect
        var visibleFrame: CGRect
        var safeAreaTop: CGFloat
        var leftArea: CGRect?
        var rightArea: CGRect?
        var scale: CGFloat

        init(
            displayID: CGDirectDisplayID,
            frame: CGRect,
            visibleFrame: CGRect,
            safeAreaTop: CGFloat = 0,
            leftArea: CGRect? = nil,
            rightArea: CGRect? = nil,
            scale: CGFloat = 2
        ) {
            self.displayID = displayID
            self.frame = frame
            self.visibleFrame = visibleFrame
            self.safeAreaTop = safeAreaTop
            self.leftArea = leftArea
            self.rightArea = rightArea
            self.scale = scale
        }

        init(screen: NSScreen) {
            self.init(
                displayID: screen.displayID,
                frame: screen.frame,
                visibleFrame: screen.visibleFrame,
                safeAreaTop: screen.safeAreaInsets.top,
                leftArea: screen.auxiliaryTopLeftArea,
                rightArea: screen.auxiliaryTopRightArea,
                scale: screen.backingScaleFactor
            )
        }
    }

    let cameraWidth: CGFloat?
    let menuBarHeight: CGFloat
    let closedSize: CGSize
    let scale: CGFloat

    var hasHardwareNotch: Bool { cameraWidth != nil }

    static let fallback = NotchDisplayMetrics(
        cameraWidth: nil,
        menuBarHeight: fallbackMenuBarHeight,
        closedSize: CGSize(width: fallbackMenuBarHeight * notchlessWidthPerBarHeight, height: fallbackMenuBarHeight),
        scale: 2
    )

    // MARK: Rules

    static let plausibleMenuBarGap: ClosedRange<CGFloat> = 16...64
    static let menuBarSeparator: CGFloat = 1
    static let fallbackMenuBarHeight: CGFloat = 24
    static let hardwareNotchWidthPadding: CGFloat = 4
    static let notchlessWidthPerBarHeight: CGFloat = 6.25

    static func menuBarGap(frame: CGRect, visibleFrame: CGRect) -> CGFloat {
        frame.maxY - visibleFrame.maxY
    }

    static func cameraWidth(safeAreaTop: CGFloat, leftArea: CGRect?, rightArea: CGRect?) -> CGFloat? {
        guard safeAreaTop > 0, let leftArea, let rightArea else { return nil }
        let width = rightArea.minX - leftArea.maxX
        return width.isFinite && width > 0 ? width : nil
    }

    static func resolve(
        _ input: Input,
        cache: MenuBarHeightCache,
        statusBarThickness: CGFloat
    ) -> NotchDisplayMetrics {
        let scale = input.scale > 0 ? input.scale : 2
        let camera = cameraWidth(safeAreaTop: input.safeAreaTop, leftArea: input.leftArea, rightArea: input.rightArea)
        let key = MenuBarHeightCache.Key(displayID: input.displayID, size: input.frame.size, scale: scale)

        let barHeight: CGFloat
        if camera != nil {
            barHeight = input.safeAreaTop
        } else {
            let gap = menuBarGap(frame: input.frame, visibleFrame: input.visibleFrame)
            if plausibleMenuBarGap.contains(gap) {
                barHeight = gap - menuBarSeparator
                cache.store(barHeight, for: key)
            } else if let cached = cache.value(for: key) {
                barHeight = cached
            } else {
                barHeight = max(fallbackMenuBarHeight, statusBarThickness.isFinite ? statusBarThickness : 0)
            }
        }

        let height = snapToPixel(barHeight, scale: scale)
        let rawWidth = camera.map { $0 + hardwareNotchWidthPadding } ?? height * notchlessWidthPerBarHeight
        return NotchDisplayMetrics(
            cameraWidth: camera,
            menuBarHeight: height,
            closedSize: CGSize(width: snapToEvenPixels(rawWidth, scale: scale), height: height),
            scale: scale
        )
    }

    static func current(for screen: NSScreen) -> NotchDisplayMetrics {
        resolve(Input(screen: screen), cache: .shared, statusBarThickness: NSStatusBar.system.thickness)
    }

    // MARK: Pixel snapping

    static func snapToPixel(_ value: CGFloat, scale: CGFloat) -> CGFloat {
        guard value.isFinite, scale > 0 else { return value }
        return (value * scale).rounded() / scale
    }

    static func snapToEvenPixels(_ value: CGFloat, scale: CGFloat) -> CGFloat {
        guard value.isFinite, scale > 0 else { return value }
        return ((value * scale) / 2).rounded() * 2 / scale
    }

    static func snappedSize(_ size: CGSize, scale: CGFloat) -> CGSize {
        CGSize(width: snapToEvenPixels(size.width, scale: scale), height: snapToPixel(size.height, scale: scale))
    }

    static func snappedSize(atLeast size: CGSize, scale: CGFloat) -> CGSize {
        guard scale > 0, size.width.isFinite, size.height.isFinite else { return size }
        var snapped = snappedSize(size, scale: scale)
        if snapped.width < size.width - 0.0001 { snapped.width += 2 / scale }
        if snapped.height < size.height - 0.0001 { snapped.height += 1 / scale }
        return snapped
    }

    static func centeredOriginX(width: CGFloat, midX: CGFloat, scale: CGFloat) -> CGFloat {
        let value = midX - width / 2
        guard value.isFinite, scale > 0 else { return value }
        return (value * scale + 0.5).rounded(.down) / scale
    }

    static func floatingIslandTopInset(userOffset: CGFloat, islandHeight: CGFloat, menuBarHeight: CGFloat, scale: CGFloat) -> CGFloat {
        snapToPixel(max(0, userOffset), scale: scale)
    }

    static let floatingIslandHeightOverBar: CGFloat = 2
    static let floatingIslandWidthPerHeight: CGFloat = 3.5

    static func resolvedClosedSize(
        measured: NotchDisplayMetrics,
        customWidth: CGFloat,
        customHeight: CGFloat,
        isFloatingIsland: Bool,
        floatingIslandMinimumHeight: CGFloat
    ) -> CGSize {
        var width = customWidth > 0 ? customWidth : measured.closedSize.width
        var height = customHeight > 0 ? customHeight : measured.closedSize.height
        if measured.hasHardwareNotch {
            width = max(width, measured.closedSize.width)
            height = max(height, measured.menuBarHeight)
        }
        if isFloatingIsland {
            let natural = measured.menuBarHeight + floatingIslandHeightOverBar
            height = max(customHeight > 0 ? customHeight : natural, floatingIslandMinimumHeight)
            if customWidth <= 0 { width = height * floatingIslandWidthPerHeight }
        }
        return CGSize(
            width: snapToEvenPixels(width, scale: measured.scale),
            height: snapToPixel(height, scale: measured.scale)
        )
    }
}

final class MenuBarHeightCache: @unchecked Sendable {
    struct Key: Hashable {
        let displayID: CGDirectDisplayID
        let width: CGFloat
        let height: CGFloat
        let scale: CGFloat

        init(displayID: CGDirectDisplayID, size: CGSize, scale: CGFloat) {
            self.displayID = displayID
            self.width = size.width
            self.height = size.height
            self.scale = scale
        }
    }

    static let shared = MenuBarHeightCache()

    private let lock = NSLock()
    private var values: [Key: CGFloat] = [:]

    func value(for key: Key) -> CGFloat? {
        lock.lock(); defer { lock.unlock() }
        return values[key]
    }

    func store(_ value: CGFloat, for key: Key) {
        lock.lock(); defer { lock.unlock() }
        values[key] = value
    }
}

// MARK: - Environment

private struct NotchDisplayWidthKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    var notchDisplayWidth: CGFloat {
        get { self[NotchDisplayWidthKey.self] }
        set { self[NotchDisplayWidthKey.self] = newValue }
    }
}