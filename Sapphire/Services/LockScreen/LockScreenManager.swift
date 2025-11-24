//
//  LockScreenManager.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-09-11.
//

import Foundation
import SwiftUI
import AppKit

struct LockScreenConfiguration {

    // MARK: - General Layout
    static let widgetSpacing: CGFloat = 24
    static let cornerRadius: CGFloat = 40
    static let backgroundPadding: CGFloat = 17
    static let backgroundStrokeWidth: CGFloat = 1.5
    static let backgroundStrokeBlur: CGFloat = 1

    // MARK: - Info Widgets (Top)
    static let infoWidgetContainerHorizontalPadding: CGFloat = 18
    static let infoWidgetInternalHSpacing: CGFloat = 12
    static let infoWidgetSmallIconHSpacing: CGFloat = 4
    static let infoWidgetGenericHSpacing: CGFloat = 10

    static let infoWidgetMediumFontSize: CGFloat = 16
    static let infoWidgetLargeFontSize: CGFloat = 22
    static let infoWidgetBoldFontSize: CGFloat = 19
    static let infoWidgetIconFontSize: CGFloat = 20

    static let infoWidgetMusicArtworkSize: CGFloat = 35
    static let infoWidgetMusicArtworkCornerRadius: CGFloat = 10
    static let infoWidgetFocusIconSize: CGFloat = 20

    // MARK: - Manager Positioning
    static let spacingMainAboveMini: CGFloat = 24

    // MARK: - Device-Specific Vertical Insets
    private struct LockScreenOffsets {
        let withoutAvatarInset: CGFloat
        let withAvatarInset: CGFloat
        let withTextInset: CGFloat
        let textMultiplier: CGFloat
    }

    private static func deviceLockScreenOffsets() -> LockScreenOffsets {
        switch DisplayDetection.detectDeviceClass() {
        case .macBookPro14:
            return LockScreenOffsets(withoutAvatarInset: 130, withAvatarInset: 200, withTextInset: 250, textMultiplier: 15)
        case .macBookPro16:
            return LockScreenOffsets(withoutAvatarInset: 130, withAvatarInset: 200, withTextInset: 250, textMultiplier: 15)
        case .macBookAir13:
            return LockScreenOffsets(withoutAvatarInset: 130, withAvatarInset: 200, withTextInset: 250, textMultiplier: 15)
        case .macBookAir15:
            return LockScreenOffsets(withoutAvatarInset: 130, withAvatarInset: 200, withTextInset: 250, textMultiplier: 15)
        case .unknown:
            return LockScreenOffsets(withoutAvatarInset: 130, withAvatarInset: 200, withTextInset: 250, textMultiplier: 15)
        }
    }

    static func getBottomInset() -> CGFloat {
        let offsets = deviceLockScreenOffsets()
        let loginPrefs = UserDefaults.standard.persistentDomain(forName: "/Library/Preferences/com.apple.loginwindow.plist")

        let loginText = loginPrefs?["LoginwindowText"] as? String ?? ""
        if !loginText.isEmpty {
            let perLineCapacity = 57
            let totalChars = loginText.count
            let lines = Int(ceil(Double(max(totalChars, 1)) / Double(perLineCapacity)))
            let extraLines = min(max(lines - 1, 0), 4)
            return offsets.withTextInset + (CGFloat(extraLines) * offsets.textMultiplier)
        }

        let isAvatarHidden = loginPrefs?["HideUserAvatarAndName"] as? Bool ?? false
        return isAvatarHidden ? offsets.withoutAvatarInset : offsets.withAvatarInset
    }
}

private final class UnfocusableWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

struct SizePreferenceKey: PreferenceKey {
    static var defaultValue: [CGSize] = []
    static func reduce(value: inout [CGSize], nextValue: () -> [CGSize]) {
        value.append(contentsOf: nextValue())
    }
}

struct MeasureSizeModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.background(
            GeometryReader { geometry in
                Color.clear.preference(
                    key: SizePreferenceKey.self,
                    value: [geometry.size]
                )
            }
        )
    }
}

extension View {
    func measureSize() -> some View {
        self.modifier(MeasureSizeModifier())
    }
}

private struct WidgetSizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let v = nextValue()
        if v != .zero {
            value = v
        }
    }
}

private struct SizeObservingView<Content: View>: View {
    let content: Content
    let onSizeChange: (CGSize) -> Void

    var body: some View {
        content
            .background(
                GeometryReader { geometry in
                    Color.clear
                        .preference(key: WidgetSizePreferenceKey.self, value: geometry.size)
                }
            )
            .onPreferenceChange(WidgetSizePreferenceKey.self) { newSize in
                DispatchQueue.main.async { onSizeChange(newSize) }
            }
    }
}

public enum LockScreenSpaceLevel: Int32 {
    case kCGSSpaceAbsoluteLevelDefault = 0, kCGSSpaceAbsoluteLevelSetupAssistant = 100, kCGSSpaceAbsoluteLevelSecurityAgent = 200, kCGSSpaceAbsoluteLevelScreenLock = 300, kSLSSpaceAbsoluteLevelNotificationCenterAtScreenLock = 400, kCGSSpaceAbsoluteLevelBootProgress = 500, kCGSSpaceAbsoluteLevelVoiceOver = 600
}

public class LockScreenManager {
    public static let shared = LockScreenManager()

    private let connection: Int32
    private let space: Int32
    private var windows: [String: NSWindowController] = [:]

    private var lastMeasuredSizes: [String: CGSize] = [:]

    private let MAIN_ID = "mainWidgetContainer"
    private let MINI_ID_PREFIX = "mini"

    typealias F_SLSMainConnectionID = @convention(c) () -> Int32
    typealias F_SLSSpaceCreate = @convention(c) (Int32, Int32, Int32) -> Int32
    typealias F_SLSSpaceSetAbsoluteLevel = @convention(c) (Int32, Int32, Int32) -> Int32
    typealias F_SLSShowSpaces = @convention(c) (Int32, CFArray) -> Int32
    typealias F_SLSSpaceAddWindowsAndRemoveFromSpaces = @convention(c) (Int32, Int32, CFArray, Int32) -> Int32
    typealias F_SLSRemoveWindowsFromSpaces = @convention(c) (Int32, CFArray, CFArray) -> Int32

    let SLSMainConnectionID: F_SLSMainConnectionID
    let SLSSpaceCreate: F_SLSSpaceCreate
    let SLSSpaceSetAbsoluteLevel: F_SLSSpaceSetAbsoluteLevel
    let SLSShowSpaces: F_SLSShowSpaces
    let SLSSpaceAddWindowsAndRemoveFromSpaces: F_SLSSpaceAddWindowsAndRemoveFromSpaces
    let SLSRemoveWindowsFromSpaces: F_SLSRemoveWindowsFromSpaces

    public struct LockScreenWidgetConfig {
        public let id: String
        public let view: AnyView
        public let initialSize: CGSize
        public let positioner: (CGSize, NSScreen) -> NSRect

        public init(id: String, view: AnyView, initialSize: CGSize, positioner: @escaping (CGSize, NSScreen) -> NSRect) {
            self.id = id
            self.view = view
            self.initialSize = initialSize
            self.positioner = positioner
        }
    }

    private init() {
        let handler = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight", RTLD_NOW)!
        SLSMainConnectionID = unsafeBitCast(dlsym(handler, "SLSMainConnectionID"), to: F_SLSMainConnectionID.self)
        SLSSpaceCreate = unsafeBitCast(dlsym(handler, "SLSSpaceCreate"), to: F_SLSSpaceCreate.self)
        SLSSpaceSetAbsoluteLevel = unsafeBitCast(dlsym(handler, "SLSSpaceSetAbsoluteLevel"), to: F_SLSSpaceSetAbsoluteLevel.self)
        SLSShowSpaces = unsafeBitCast(dlsym(handler, "SLSShowSpaces"), to: F_SLSShowSpaces.self)
        SLSSpaceAddWindowsAndRemoveFromSpaces = unsafeBitCast(dlsym(handler, "SLSSpaceAddWindowsAndRemoveFromSpaces"), to: F_SLSSpaceAddWindowsAndRemoveFromSpaces.self)
        SLSRemoveWindowsFromSpaces = unsafeBitCast(dlsym(handler, "SLSRemoveWindowsFromSpaces"), to: F_SLSRemoveWindowsFromSpaces.self)
        connection = SLSMainConnectionID()
        space = SLSSpaceCreate(connection, 1, 0)
        _ = SLSSpaceSetAbsoluteLevel(connection, space, LockScreenSpaceLevel.kSLSSpaceAbsoluteLevelNotificationCenterAtScreenLock.rawValue)
        _ = SLSShowSpaces(connection, [space] as CFArray)
    }

    public func delegateWindow(_ window: NSWindow) {
        _ = SLSSpaceAddWindowsAndRemoveFromSpaces(connection, space, [window.windowNumber] as CFArray, 7)
    }

    public func removeWindow(_ window: NSWindow) {
        _ = SLSRemoveWindowsFromSpaces(connection, [window.windowNumber] as CFArray, [space] as CFArray)
    }

    public func setupAndShowWindows(configs: [LockScreenWidgetConfig], on screen: NSScreen) {
        hideAndDestroyWindows()

        for (index, config) in configs.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + (Double(index) * 0.05)) {
                let initialFrame = config.positioner(config.initialSize, screen)
                self.displayView(config.view, withId: config.id, initialFrame: initialFrame, positioner: config.positioner, on: screen)
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.repositionMainIfPossible()
        }
    }

    func calculateMainWidgetFrame(size: CGSize, screen: NSScreen) -> NSRect {
        let x = screen.visibleFrame.midX - (size.width / 2)
        let miniWidgetsAreActive = windows.keys.contains { $0.hasPrefix(MINI_ID_PREFIX) }

        if miniWidgetsAreActive, let miniSize = activeMiniSize(), miniSize.height > 10 {
            let miniFrame = calculateMiniWidgetFrame(size: miniSize, screen: screen)
            let y = miniFrame.maxY + LockScreenConfiguration.spacingMainAboveMini
            return NSRect(x: x, y: y, width: size.width, height: size.height)
        } else {
            let bottomInset = LockScreenConfiguration.getBottomInset()
            let y = screen.visibleFrame.minY + bottomInset
            return NSRect(x: x, y: y, width: size.width, height: size.height)
        }
    }

    func calculateMiniWidgetFrame(size: CGSize, screen: NSScreen) -> NSRect {
        let vis = screen.visibleFrame
        let x = vis.midX - (size.width / 2)
        let bottomInset = LockScreenConfiguration.getBottomInset()
        let y = vis.minY + bottomInset
        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }

    func calculateInfoWidgetFrame(size: CGSize, screen: NSScreen) -> NSRect {
        let vis = screen.visibleFrame
        let x = vis.midX - (size.width / 2)

        let topInset = vis.height * 0.23
        let y = vis.maxY - topInset - size.height

        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }

    private func displayView(_ view: AnyView,
                             withId id: String,
                             initialFrame: NSRect,
                             positioner: @escaping (CGSize, NSScreen) -> NSRect,
                             on screen: NSScreen) {

        let window = UnfocusableWindow(
            contentRect: initialFrame,
            styleMask: NSWindow.StyleMask.borderless,
            backing: NSWindow.BackingStoreType.buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = NSColor.clear
        window.hasShadow = false
        window.level = .mainMenu + 2
        window.collectionBehavior = [NSWindow.CollectionBehavior.canJoinAllSpaces, .stationary]

        let controller = NSWindowController(window: window)
        windows[id] = controller
        delegateWindow(window)

        let sizeObservingView = SizeObservingView(content: view) { [weak self] newSize in
            guard let self = self, let window = controller.window else { return }
            self.lastMeasuredSizes[id] = newSize

            let newFrame = positioner(newSize, screen)
            if !window.isVisible {
                window.setFrame(newFrame, display: false)
                window.alphaValue = 0
                window.makeKeyAndOrderFront(nil)
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.4
                    context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    window.animator().alphaValue = 1
                }
            } else {
                window.animator().setFrame(newFrame, display: true)
            }

            if id.hasPrefix(self.MINI_ID_PREFIX) || id == self.MAIN_ID {
                self.repositionMainIfPossible()
            }
        }

        let hostingController = NSHostingController(rootView: sizeObservingView)
        hostingController.view.wantsLayer = true
        hostingController.view.layer?.backgroundColor = NSColor.clear.cgColor

        controller.window?.contentViewController = hostingController
    }

    private func activeMiniSize() -> CGSize? {
        for (id, controller) in windows {
            guard id.hasPrefix(MINI_ID_PREFIX),
                  let win = controller.window,
                  win.isVisible,
                  let sz = lastMeasuredSizes[id],
                  sz.height > 10 else { continue }
            return sz
        }
        return nil
    }

    private func repositionMainIfPossible() {
        guard let controller = windows[MAIN_ID],
              let window = controller.window,
              let screen = window.screen else { return }

        let size = lastMeasuredSizes[MAIN_ID] ?? window.frame.size
        let target = calculateMainWidgetFrame(size: size, screen: screen)
        if window.frame != target {
            window.animator().setFrame(target, display: true)
        }
    }

    public func hideAndDestroyWindows() {
        let windowNumbers = windows.values.compactMap { $0.window?.windowNumber }

        if !windowNumbers.isEmpty {
            _ = SLSRemoveWindowsFromSpaces(connection, windowNumbers as CFArray, [space] as CFArray)
            print("[LockScreenManager] Explicitly removed \(windowNumbers.count) windows from the lock screen space.")
        }

        windows.values.forEach { controller in
            controller.window?.orderOut(nil)
            controller.window?.contentViewController = nil
            controller.close()
        }
        windows.removeAll()
        lastMeasuredSizes.removeAll()
    }
}