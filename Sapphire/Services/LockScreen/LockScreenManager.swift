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
    static let spacingBelowClock: CGFloat = 16
    static let spacingMainBelowInfo: CGFloat = 20
    static let minimumMainWidgetScale: CGFloat = 0.6

    // MARK: - System Clock
    private static let legacyClockBottomFraction: CGFloat = 0.23
    private static let modernClockBottomFraction: CGFloat = 0.31

    static func clockBottomY(on screen: NSScreen) -> CGFloat {
        let fraction = ProcessInfo.processInfo.isOperatingSystemAtLeast(
            OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 0)
        ) ? modernClockBottomFraction : legacyClockBottomFraction
        return screen.frame.maxY - screen.frame.height * fraction - spacingBelowClock
    }

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

    override var isKeyWindow: Bool { true }
    override var isMainWindow: Bool { true }
    @objc func hasKeyAppearance() -> Bool { true }
    @objc func hasMainAppearance() -> Bool { true }
    @objc func _hasActiveAppearance() -> Bool { true }
    @objc func _hasActiveAppearanceIgnoringKeyFocus() -> Bool { true }
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

final class LockScreenWidgetScale: ObservableObject {
    @Published var value: CGFloat = 1
}

private struct SizeObservingView<Content: View>: View {
    let content: Content
    let alignment: Alignment
    let fitsContent: Bool
    @ObservedObject var scale: LockScreenWidgetScale
    let onSizeChange: (CGSize) -> Void

    @State private var measuredSize: CGSize = .zero

    var body: some View {
        let s = scale.value
        let isScaled = s < 0.999 && measuredSize != .zero
        content
            .fixedSize(horizontal: fitsContent, vertical: fitsContent)
            .background(
                GeometryReader { geometry in
                    Color.clear
                        .preference(key: WidgetSizePreferenceKey.self, value: geometry.size)
                }
            )
            .onPreferenceChange(WidgetSizePreferenceKey.self) { newSize in
                measuredSize = newSize
                DispatchQueue.main.async { onSizeChange(newSize) }
            }
            .scaleEffect(s, anchor: Self.anchor(for: alignment))
            .frame(
                width: isScaled ? measuredSize.width * s : nil,
                height: isScaled ? measuredSize.height * s : nil,
                alignment: alignment
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
    }

    private static func anchor(for alignment: Alignment) -> UnitPoint {
        switch alignment {
        case .top: return .top
        case .bottom: return .bottom
        default: return .center
        }
    }
}

public enum LockScreenSpaceLevel: Int32 {
    case kCGSSpaceAbsoluteLevelDefault = 0
    case kCGSSpaceAbsoluteLevelSetupAssistant = 100
    case kCGSSpaceAbsoluteLevelSecurityAgent = 200
    case kCGSSpaceAbsoluteLevelScreenLock = 300
    case kSLSSpaceAbsoluteLevelNotificationCenterAtScreenLock = 400
    case kCGSSpaceAbsoluteLevelBootProgress = 500
    case kCGSSpaceAbsoluteLevelVoiceOver = 600

    static let lockScreenWallpaper = kCGSSpaceAbsoluteLevelScreenLock.rawValue
}

public class LockScreenManager {
    public static let shared = LockScreenManager()

    private let connection: Int32
    private let space: Int32
    private let wallpaperSpace: Int32
    private var windows: [String: NSWindowController] = [:]

    private var delegatedWindowIds: Set<String> = []

    private var lastMeasuredSizes: [String: CGSize] = [:]

    private var generation: UInt64 = 0

    private var windowShownAt: [String: CFTimeInterval] = [:]

    private var contentScales: [String: LockScreenWidgetScale] = [:]

    private let MAIN_ID = "mainWidgetContainer"
    private let INFO_ID = "infoWidget"
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
        wallpaperSpace = SLSSpaceCreate(connection, 1, 0)
        _ = SLSSpaceSetAbsoluteLevel(connection, wallpaperSpace, LockScreenSpaceLevel.lockScreenWallpaper)
        space = SLSSpaceCreate(connection, 1, 0)
        _ = SLSSpaceSetAbsoluteLevel(connection, space, LockScreenSpaceLevel.kSLSSpaceAbsoluteLevelNotificationCenterAtScreenLock.rawValue)
        _ = SLSShowSpaces(connection, [wallpaperSpace, space] as CFArray)
    }

    public func delegateWindow(_ window: NSWindow) {
        _ = SLSSpaceAddWindowsAndRemoveFromSpaces(connection, space, [window.windowNumber] as CFArray, 7)
    }

    public func delegateWallpaperWindow(_ window: NSWindow) {
        _ = SLSSpaceAddWindowsAndRemoveFromSpaces(connection, wallpaperSpace, [window.windowNumber] as CFArray, 7)
    }

    public func removeWindow(_ window: NSWindow) {
        _ = SLSRemoveWindowsFromSpaces(connection, [window.windowNumber] as CFArray, [space] as CFArray)
    }

    public func removeWallpaperWindow(_ window: NSWindow) {
        _ = SLSRemoveWindowsFromSpaces(connection, [window.windowNumber] as CFArray, [wallpaperSpace] as CFArray)
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
        let bottomY: CGFloat
        if windows.keys.contains(where: { $0.hasPrefix(MINI_ID_PREFIX) }),
           let miniSize = activeMiniSize(), miniSize.height > 10 {
            let miniFrame = calculateMiniWidgetFrame(size: miniSize, screen: screen)
            bottomY = miniFrame.maxY + LockScreenConfiguration.spacingMainAboveMini
        } else {
            bottomY = screen.frame.minY + LockScreenConfiguration.getBottomInset()
        }

        let contentHeight = lastMeasuredSizes[MAIN_ID]?.height ?? size.height
        let available = mainWidgetTopLimit(on: screen) - bottomY
        var scale: CGFloat = 1
        if contentHeight > 0, available > 0, contentHeight > available {
            scale = max(LockScreenConfiguration.minimumMainWidgetScale, available / contentHeight)
        }
        if let model = contentScales[MAIN_ID], abs(model.value - scale) > 0.001 {
            model.value = scale
        }

        let width = size.width * scale
        let height = size.height * scale
        return NSRect(x: screen.frame.midX - width / 2, y: bottomY, width: width, height: height)
    }

    private func mainWidgetTopLimit(on screen: NSScreen) -> CGFloat {
        if let info = windows[INFO_ID]?.window, info.contentViewController != nil,
           let infoSize = lastMeasuredSizes[INFO_ID], infoSize.height > 1 {
            return calculateInfoWidgetFrame(size: infoSize, screen: screen).minY
                - LockScreenConfiguration.spacingMainBelowInfo
        }
        return LockScreenConfiguration.clockBottomY(on: screen)
    }

    func calculateMiniWidgetFrame(size: CGSize, screen: NSScreen) -> NSRect {
        let vis = screen.frame
        let x = vis.midX - (size.width / 2)
        let bottomInset = LockScreenConfiguration.getBottomInset()
        let y = vis.minY + bottomInset
        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }

    func calculateInfoWidgetFrame(size: CGSize, screen: NSScreen) -> NSRect {
        let vis = screen.frame
        let x = vis.midX - (size.width / 2)
        let y = LockScreenConfiguration.clockBottomY(on: screen) - size.height

        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }

    func calculateFullScreenMusicFrame(size: CGSize, screen: NSScreen) -> NSRect {
        screen.frame
    }

    private let FULLSCREEN_MUSIC_ID = "fullScreenMusicPane"

    private static let frameSpringTiming = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.25, 1)
    private static let frameSpringDuration: TimeInterval = 0.4
    private static let contentSettleDelay: TimeInterval = 0.5

    private var pendingSettle: [String: DispatchWorkItem] = [:]
    private var pendingCoverChange: DispatchWorkItem?

    private func contentAlignment(for id: String) -> Alignment {
        if id == MAIN_ID || id.hasPrefix(MINI_ID_PREFIX) { return .bottom }
        if id == FULLSCREEN_MUSIC_ID { return .center }
        return .top
    }

    func displayView<Content: View>(_ view: Content,
                                            withId id: String,
                                            initialFrame: NSRect,
                                            positioner: @escaping (CGSize, NSScreen) -> NSRect,
                                            windowLevel: NSWindow.Level,
                                            windowIgnoresMouseEvents: Bool = false,
                                            on screen: NSScreen) {
        assert(Thread.isMainThread, "LockScreenManager window creation must run on the main thread")

        let gen = generation
        let controller: NSWindowController
        let window: NSWindow

        if let existingController = windows[id], let existingWindow = existingController.window {
            controller = existingController
            window = existingWindow
        } else {
            window = UnfocusableWindow(
                contentRect: initialFrame,
                styleMask: NSWindow.StyleMask.borderless,
                backing: NSWindow.BackingStoreType.buffered,
                defer: false
            )
            window.isOpaque = false
            window.backgroundColor = NSColor.clear
            window.hasShadow = false
            window.isExcludedFromWindowsMenu = true
            window.animationBehavior = .none
            window.collectionBehavior = [NSWindow.CollectionBehavior.canJoinAllSpaces, .stationary, .ignoresCycle]

            controller = NSWindowController(window: window)
            windows[id] = controller
            delegateWindow(window)
            delegatedWindowIds.insert(id)
        }

        let scale = contentScales[id] ?? LockScreenWidgetScale()
        scale.value = 1
        contentScales[id] = scale

        let sizeObservingView = SizeObservingView(
            content: view,
            alignment: contentAlignment(for: id),
            fitsContent: id != FULLSCREEN_MUSIC_ID,
            scale: scale
        ) { [weak self, weak controller] newSize in
            guard let self, gen == self.generation, let window = controller?.window else { return }
            self.handleWidgetSizeChange(newSize, id: id, window: window, screen: screen, positioner: positioner)
        }

        let hostingController = NSHostingController(rootView: sizeObservingView)
        hostingController.sizingOptions = []
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
    }

    private func handleWidgetSizeChange(_ newSize: CGSize,
                                        id: String,
                                        window: NSWindow,
                                        screen: NSScreen,
                                        positioner: @escaping (CGSize, NSScreen) -> NSRect) {
        guard newSize.width > 0, newSize.height > 0 else { return }
        lastMeasuredSizes[id] = newSize
        pendingSettle[id]?.cancel()
        pendingSettle[id] = nil

        let settledFrame = positioner(newSize, screen)
        let elapsed = CACurrentMediaTime() - (windowShownAt[id] ?? 0)

        if elapsed < 0.45 || id == FULLSCREEN_MUSIC_ID {
            setFrameIfNeeded(window, settledFrame, animated: false)
        } else {
            let s = max(contentScales[id]?.value ?? 1, 0.01)
            let coverSize = CGSize(
                width: max(window.frame.width / s, newSize.width),
                height: max(window.frame.height / s, newSize.height)
            )
            setFrameIfNeeded(window, positioner(coverSize, screen), animated: false)

            if coverSize != newSize {
                let settle = DispatchWorkItem { [weak self, weak window] in
                    guard let self, let window else { return }
                    self.pendingSettle[id] = nil
                    guard let size = self.lastMeasuredSizes[id] else { return }
                    self.setFrameIfNeeded(window, positioner(size, screen), animated: false)
                    if id.hasPrefix(self.MINI_ID_PREFIX) || id == self.INFO_ID { self.repositionMainIfPossible() }
                }
                pendingSettle[id] = settle
                DispatchQueue.main.asyncAfter(deadline: .now() + Self.contentSettleDelay, execute: settle)
            }
        }

        if id.hasPrefix(MINI_ID_PREFIX) || id == INFO_ID {
            repositionMainIfPossible()
        }
    }

    private func setFrameIfNeeded(_ window: NSWindow, _ frame: NSRect, animated: Bool) {
        let current = window.frame
        let delta = abs(current.minX - frame.minX) + abs(current.minY - frame.minY)
            + abs(current.width - frame.width) + abs(current.height - frame.height)
        guard delta > 0.5 else { return }
        guard animated else {
            window.setFrame(frame, display: true)
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.frameSpringDuration
            context.timingFunction = Self.frameSpringTiming
            window.animator().setFrame(frame, display: true)
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

    private func repositionMainIfPossible() {
        guard let controller = windows[MAIN_ID],
              let window = controller.window,
              let screen = window.screen else { return }

        let s = max(contentScales[MAIN_ID]?.value ?? 1, 0.01)
        let size = lastMeasuredSizes[MAIN_ID]
            ?? CGSize(width: window.frame.width / s, height: window.frame.height / s)
        let target = calculateMainWidgetFrame(size: size, screen: screen)
        let elapsed = CACurrentMediaTime() - (windowShownAt[MAIN_ID] ?? 0)
        setFrameIfNeeded(window, target, animated: elapsed >= 0.45)
    }

    func setWidgetWindowsCovered(_ covered: Bool) {
        let widgets = windows.filter { $0.key != FULLSCREEN_MUSIC_ID }.compactMap { $0.value.window }
        pendingCoverChange?.cancel()
        pendingCoverChange = nil
        if covered {
            let work = DispatchWorkItem { widgets.forEach { $0.orderOut(nil) } }
            pendingCoverChange = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: work)
        } else {
            for window in widgets where window.contentViewController != nil && !window.isVisible {
                RemoteViewCrashGuardRunBlock { window.orderFrontRegardless() }
            }
        }
    }

    public func hideWindow(withId id: String) {
        guard let controller = windows[id], let window = controller.window else { return }
        pendingSettle.removeValue(forKey: id)?.cancel()
        lastMeasuredSizes.removeValue(forKey: id)
        windowShownAt.removeValue(forKey: id)
        window.orderOut(nil)
        window.contentViewController = nil
    }

    public func hideAndDestroyWindows(animated: Bool = true, fullyDestroy: Bool = false) {
        generation &+= 1
        pendingSettle.values.forEach { $0.cancel() }
        pendingSettle.removeAll()
        pendingCoverChange?.cancel()
        pendingCoverChange = nil

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