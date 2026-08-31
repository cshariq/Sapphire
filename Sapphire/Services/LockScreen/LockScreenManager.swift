//
//  LockScreenManager.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-09-11.
//

import Foundation
import SwiftUI
import AppKit
import QuartzCore

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
    static let infoWidgetPillHeight: CGFloat = 40

    static let infoWidgetMediumFontSize: CGFloat = 16
    static let infoWidgetLargeFontSize: CGFloat = 22
    static let infoWidgetBoldFontSize: CGFloat = 19
    static let infoWidgetIconFontSize: CGFloat = 20

    static let infoWidgetMusicArtworkSize: CGFloat = 35
    static let infoWidgetMusicArtworkCornerRadius: CGFloat = 10
    static let infoWidgetFocusIconSize: CGFloat = 20

    // MARK: - Manager Positioning
    static let spacingMainAboveMini: CGFloat = 24

    // MARK: - Vertical Insets
    private static let withoutAvatarInset: CGFloat = 130
    private static let withAvatarInset: CGFloat = 200
    private static let withTextInset: CGFloat = 250
    private static let textMultiplier: CGFloat = 15

    static func getBottomInset() -> CGFloat {
        let loginPrefs = UserDefaults.standard.persistentDomain(forName: "/Library/Preferences/com.apple.loginwindow.plist")

        let loginText = loginPrefs?["LoginwindowText"] as? String ?? ""
        if !loginText.isEmpty {
            let perLineCapacity = 57
            let totalChars = loginText.count
            let lines = Int(ceil(Double(max(totalChars, 1)) / Double(perLineCapacity)))
            let extraLines = min(max(lines - 1, 0), 4)
            return withTextInset + (CGFloat(extraLines) * textMultiplier)
        }

        let isAvatarHidden = loginPrefs?["HideUserAvatarAndName"] as? Bool ?? false
        return isAvatarHidden ? withoutAvatarInset : withAvatarInset
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

    private var delegatedWindowIds: Set<String> = []

    private var lastMeasuredSizes: [String: CGSize] = [:]

    private var generation: UInt64 = 0

    private var windowShownAt: [String: CFTimeInterval] = [:]

    private var pendingReposition: DispatchWorkItem?

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
        public let initialSize: CGSize
        public let positioner: (CGSize, NSScreen) -> NSRect
        public let windowLevel: NSWindow.Level
        let show: (_ manager: LockScreenManager, _ initialFrame: NSRect, _ screen: NSScreen) -> Void

        public init(
            id: String,
            initialSize: CGSize,
            positioner: @escaping (CGSize, NSScreen) -> NSRect,
            windowLevel: NSWindow.Level = .mainMenu + 2,
            show: @escaping (_ manager: LockScreenManager, _ initialFrame: NSRect, _ screen: NSScreen) -> Void
        ) {
            self.id = id
            self.initialSize = initialSize
            self.positioner = positioner
            self.windowLevel = windowLevel
            self.show = show
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
        hideAndDestroyWindows(animated: false)
        let gen = generation

        for (index, config) in configs.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + (Double(index) * 0.03)) {
                guard gen == self.generation else { return }
                let initialFrame = config.positioner(config.initialSize, screen)
                config.show(self, initialFrame, screen)
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            guard gen == self.generation else { return }
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

    func calculateFullScreenMusicFrame(size: CGSize, screen: NSScreen) -> NSRect {
        screen.frame
    }

    private let FULLSCREEN_MUSIC_ID = "fullScreenMusicPane"

    func displayView<Content: View>(_ view: Content,
                                            withId id: String,
                                            initialFrame: NSRect,
                                            positioner: @escaping (CGSize, NSScreen) -> NSRect,
                                            windowLevel: NSWindow.Level,
                                            windowIgnoresMouseEvents: Bool = false,
                                            on screen: NSScreen) {
        assert(Thread.isMainThread, "LockScreenManager window creation must run on the main thread")

        let gen = generation

        if let existingController = windows[id], let window = existingController.window {
            let sizeObservingView = SizeObservingView(content: view) { [weak self] newSize in
                guard let self = self, gen == self.generation, let win = existingController.window else { return }
                self.handleWidgetSizeChange(newSize, id: id, window: win, screen: screen, positioner: positioner)
            }

            let hostingController = NSHostingController(rootView: sizeObservingView)
            hostingController.view.wantsLayer = true
            hostingController.view.layer?.backgroundColor = NSColor.clear.cgColor

            window.contentViewController = hostingController
            window.setFrame(initialFrame, display: false)
            window.alphaValue = 0
            window.level = windowLevel
            window.ignoresMouseEvents = windowIgnoresMouseEvents

            windowShownAt[id] = CACurrentMediaTime()

            RemoteViewCrashGuardRunBlock {
                window.orderFrontRegardless()
            }
            let isFullscreenMusic = id == FULLSCREEN_MUSIC_ID
            NSAnimationContext.runAnimationGroup { context in
                context.duration = isFullscreenMusic ? 0.28 : 0.32
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                window.animator().alphaValue = 1
            }
            return
        }

        let window = UnfocusableWindow(
            contentRect: initialFrame,
            styleMask: NSWindow.StyleMask.borderless,
            backing: NSWindow.BackingStoreType.buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = NSColor.clear
        window.hasShadow = false
        window.level = windowLevel
        window.isExcludedFromWindowsMenu = true
        window.animationBehavior = .none
        window.collectionBehavior = [NSWindow.CollectionBehavior.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.ignoresMouseEvents = windowIgnoresMouseEvents

        let controller = NSWindowController(window: window)
        windows[id] = controller
        delegateWindow(window)
        delegatedWindowIds.insert(id)
        windowShownAt[id] = CACurrentMediaTime()

        let sizeObservingView = SizeObservingView(content: view) { [weak self] newSize in
            guard let self = self, gen == self.generation, let window = controller.window else { return }
            self.handleWidgetSizeChange(newSize, id: id, window: window, screen: screen, positioner: positioner)
        }

        let hostingController = NSHostingController(rootView: sizeObservingView)
        hostingController.view.wantsLayer = true
        hostingController.view.layer?.backgroundColor = NSColor.clear.cgColor

        controller.window?.contentViewController = hostingController

        let isFullscreenMusic = id == FULLSCREEN_MUSIC_ID
        window.setFrame(initialFrame, display: false)
        window.alphaValue = 0
        RemoteViewCrashGuardRunBlock {
            window.orderFrontRegardless()
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = isFullscreenMusic ? 0.28 : 0.32
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1
        }
    }

    private func handleWidgetSizeChange(_ newSize: CGSize,
                                        id: String,
                                        window: NSWindow,
                                        screen: NSScreen,
                                        positioner: @escaping (CGSize, NSScreen) -> NSRect) {
        guard newSize.width > 0, newSize.height > 0 else { return }
        lastMeasuredSizes[id] = newSize

        let newFrame = positioner(newSize, screen)
        let isFullscreenMusic = id == FULLSCREEN_MUSIC_ID

        let delta = abs(window.frame.origin.x - newFrame.origin.x)
            + abs(window.frame.origin.y - newFrame.origin.y)
            + abs(window.frame.width - newFrame.width)
            + abs(window.frame.height - newFrame.height)
        guard delta > 0.5 else { return }

        let elapsed = CACurrentMediaTime() - (windowShownAt[id] ?? 0)
        if elapsed < 0.45 || isFullscreenMusic {
            window.setFrame(newFrame, display: true)
        } else {
            let duration: TimeInterval = delta > 40 ? 0.28 : 0.18
            NSAnimationContext.runAnimationGroup { context in
                context.duration = duration
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                window.animator().setFrame(newFrame, display: true)
            }
        }

        if id.hasPrefix(MINI_ID_PREFIX) || id == MAIN_ID {
            scheduleRepositionMain()
        }
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

    private func scheduleRepositionMain() {
        pendingReposition?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.repositionMainIfPossible()
        }
        pendingReposition = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06, execute: work)
    }

    private func repositionMainIfPossible() {
        pendingReposition = nil
        guard let controller = windows[MAIN_ID],
              let window = controller.window,
              let screen = window.screen else { return }

        let size = lastMeasuredSizes[MAIN_ID] ?? window.frame.size
        let target = calculateMainWidgetFrame(size: size, screen: screen)

        let delta = abs(window.frame.minX - target.minX)
            + abs(window.frame.minY - target.minY)
            + abs(window.frame.width - target.width)
            + abs(window.frame.height - target.height)
        guard delta > 0.5 else { return }

        let elapsed = CACurrentMediaTime() - (windowShownAt[MAIN_ID] ?? 0)
        if elapsed < 0.45 {
            window.setFrame(target, display: true)
        } else {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.22
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                window.animator().setFrame(target, display: true)
            }
        }
    }

    public func hideWindow(withId id: String) {
        guard let controller = windows[id], let window = controller.window else { return }
        lastMeasuredSizes.removeValue(forKey: id)
        windowShownAt.removeValue(forKey: id)
        window.orderOut(nil)
        window.contentViewController = nil
    }

    public func hideAndDestroyWindows(animated: Bool = true, fullyDestroy: Bool = false) {
        generation &+= 1
        pendingReposition?.cancel()
        pendingReposition = nil

        let visibleWindows = windows.values
            .compactMap { $0.window }
            .filter { $0.isVisible && $0.alphaValue > 0.02 }

        let teardown: () -> Void = { [weak self] in
            guard let self else { return }
            for controller in self.windows.values {
                controller.window?.orderOut(nil)
                controller.window?.contentViewController = nil
            }
            if fullyDestroy {
                let windowNumbers = self.windows.values.compactMap { $0.window?.windowNumber }
                if !windowNumbers.isEmpty {
                    _ = self.SLSRemoveWindowsFromSpaces(self.connection, windowNumbers as CFArray, [self.space] as CFArray)
                    print("[LockScreenManager] Explicitly removed \(windowNumbers.count) windows from the lock screen space.")
                }
                for controller in self.windows.values {
                    controller.close()
                }
                self.windows.removeAll()
                self.delegatedWindowIds.removeAll()
                self.lastMeasuredSizes.removeAll()
                self.windowShownAt.removeAll()
            }
        }

        guard animated, !visibleWindows.isEmpty else {
            teardown()
            return
        }

        let gen = generation
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            for window in visibleWindows {
                window.animator().alphaValue = 0
            }
        } completionHandler: {
            guard gen == self.generation else { return }
            teardown()
        }
    }
}