//
//  NotchConfiguration.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-05-08.
//

import SwiftUI
import AppKit
import CoreGraphics

struct NotchConfiguration {
    private static let designReferenceResolution = CGSize(width: 1728, height: 1117)

    private static let fallbackClosedNotchSize = (width: CGFloat(185), height: CGFloat(32))

    static func hasHardwareNotch(on screen: NSScreen?) -> Bool {
        guard let screen else { return false }
        return hasHardwareNotch(
            safeAreaTop: screen.safeAreaInsets.top,
            leftArea: screen.auxiliaryTopLeftArea,
            rightArea: screen.auxiliaryTopRightArea
        )
    }

    static func hasHardwareNotch(
        safeAreaTop: CGFloat,
        leftArea: CGRect?,
        rightArea: CGRect?
    ) -> Bool {
        guard safeAreaTop > 0,
              let leftArea,
              let rightArea else { return false }

        let cutoutWidth = rightArea.minX - leftArea.maxX
        return cutoutWidth.isFinite && cutoutWidth > 0
    }

    // MARK: - Screen Size Adjustments
    // MARK: - Measured Notch Geometry
    private static var referenceScreen: NSScreen? {
        CursorPosition.visibleNotchWindows.first?.screen
            ?? CursorPosition.targetNotchScreen()
            ?? NSScreen.main
    }
    static func measuredNotchSize(for screen: NSScreen?) -> (width: CGFloat, height: CGFloat) {
        guard let screen = screen ?? referenceScreen else {
            return fallbackClosedNotchSize
        }
        let size = NotchDisplayMetrics.current(for: screen).closedSize
        return (width: size.width, height: size.height)
    }

    // MARK: - Basic Size Configuration
    static var universalWidth: CGFloat { measuredNotchSize(for: referenceScreen).width }
    static var universalHeight: CGFloat { measuredNotchSize(for: referenceScreen).height }
    static var initialSize: CGSize { CGSize(width: universalWidth, height: universalHeight) }
    static let initialCornerRadius: CGFloat = 10

    static var topBuffer: CGFloat = 0

    static var scaleFactor: CGFloat = 1.10
    static var hoverExpandedSize: CGSize { CGSize(width: universalWidth * scaleFactor, height: universalHeight * scaleFactor) }

    static var autoExpandedContentVerticalPadding: CGFloat = 8

    static var clickExpandedCornerRadius: CGFloat = 40

    static var liveActivityBottomCornerRadius: CGFloat = 18

    static var collapseAnimationDelay: TimeInterval = 0

    // MARK: - Animation Configurations (Represents the 'Snappy' default)
    static var expandAnimation = Animation.notchMorphSpring(response: 0.4, dampingFraction: 0.55)
    static var widgetSwitchAnimation = Animation.notchMorphSpring(response: 0.4, dampingFraction: 0.95)
    static var swipeOpenAnimation = Animation.notchMorphSpring(response: 0.35, dampingFraction: 0.45)
    static var collapseAnimation = Animation.notchMorphSpring(response: 0.3, dampingFraction: 0.98)
    static var hoverAnimation = Animation.notchMorphSpring(response: 0.25, dampingFraction: 0.55)
    static var contentTransitionAnimation = Animation.notchMorphSpring(response: 0.45, dampingFraction: 1.0)
    static var activityToActivityAnimation = Animation.notchMorphSpring(response: 0.4, dampingFraction: 0.98)
    static var bottomContentAnimation = Animation.notchMorphSpring(response: 0.42, dampingFraction: 0.999)
    static var bottomContentTransitionAnimation = Animation.notchMorphTiming(.easeInOut, duration: 0.3)
    static var activityOpacityAnimation = Animation.notchMorphTiming(.easeInOut, duration: 0.2)

    // MARK: - Blur Animation Configurations
    static var blurAnimation = Animation.notchMorphTiming(.easeIn, duration: 0.1)
    static var blurRemovalAnimation = Animation.notchMorphTiming(.easeOut, duration: 0.22)
    static var widgetBlurRadiusMax: CGFloat = 30
    static var focusPullAnimation = Animation.notchMorphTiming(.bezier(x1: 0.2, y1: 0.8, x2: 0.2, y2: 1), duration: 0.8)
    static var widgetBlurAnimation = Animation.notchMorphTiming(.easeIn, duration: 0.08)
    static var widgetBlurRemovalAnimation = focusPullAnimation
    static var contentFadeAnimation = Animation.notchMorphTiming(.easeIn, duration: 0.3)
    static var activityBlurRadiusMax: CGFloat = 40
    static var activityBlurAnimation = Animation.notchMorphTiming(.easeIn, duration: 0.1)
    static var activityBlurRemovalAnimation = Animation.notchMorphTiming(.bezier(x1: 0.33, y1: 0.1, x2: 0.67, y2: 1), duration: 0.4)

    static var expandedShadowColor = Color.black.opacity(0.4)
    static var expandedShadowRadius: CGFloat = 18
    static var expandedShadowOffset: CGPoint { CGPoint(x: 0, y: 8) }
    static var notchShadowBleed: CGFloat = 28

    // MARK: - Content Padding and Layout
    static var contentHorizontalPadding: CGFloat = 35
    static var contentVisibilityThresholdHeight: CGFloat { universalHeight + 1 }
    static var primaryWidgetSwitchDelay: TimeInterval = 0.2
    static var dragActivationCollapseDelay: TimeInterval = 0.05

    // MARK: - Battery View Configuration
    static var batteryTextFontSize: CGFloat = 12
    static var batteryIconSize: CGFloat = 22
    static var batteryValueFontSize: CGFloat = 7
    static var batteryBoltIconSize: CGFloat = 6
    static var batteryIconPadding: CGFloat = 2.7
    static var batteryHorizontalPadding: CGFloat = 10
    static var batteryHStackSpacing: CGFloat = 6
    static var batteryTextTrailingPadding: CGFloat = 2
    static var batteryFrameWidth: CGFloat = 22
    static var batteryFrameHeight: CGFloat = 10

    // MARK: - Notch Activity View Configuration
    static var activityContentHorizontalPadding: CGFloat = 15
    static var activityDefaultHorizontalPadding: CGFloat = 13
    static var activityWithContentHorizontalPadding: CGFloat = 15

    // MARK: - Button Configuration
    static var buttonHoverAnimationDuration: TimeInterval = 0.15
    static var buttonHoverScaleFactor: CGFloat = 1.1
    static var buttonSpringAnimationResponse: Double = 0.4
    static var buttonSpringAnimationDampingFraction: Double = 0.6

    // MARK: - Gemini Button Configuration
    static var geminiButtonBaseSize: CGFloat = 25
    static var geminiButtonInactiveIconSize: CGFloat = 14
    static var geminiButtonActiveIconSize: CGFloat = 12
    static var geminiButtonActiveHorizontalPadding: CGFloat = 10
    static var geminiButtonTextFontSize: CGFloat = 10
    static var geminiButtonSpringResponse: Double = 0.5
    static var geminiButtonSpringDamping: Double = 0.6
    static var geminiGlowBaseOpacityNormal: Double = 0.4
    static var geminiGlowBaseOpacityExpanded: Double = 0.7
    static var geminiGlowAudioMultiplier: Double = 0.3
    static var geminiGlowBaseRadiusNormal: CGFloat = 12
    static var geminiGlowBaseRadiusExpanded: CGFloat = 25
    static var geminiGlowAudioRadiusMultiplier: CGFloat = 15

    // MARK: - Animation Transition Timings
    static var contentUpdateDelay: TimeInterval = 0.1
    static var activityAnimationOutDelay: TimeInterval = 0.3
    static var autoContentRenderDelay: TimeInterval = 0.3
    static var activityBlurUpdateDelay: TimeInterval = 0.15
    static var activitySizeChangeDelay: TimeInterval = 0.25
    static var expandButtonAnimationScaleMultiplier: CGFloat = 1.05

    // MARK: - Settings Window Configuration
    static var settingsWindowWidth: CGFloat = 950
    static var settingsWindowHeight: CGFloat = 720
    static var settingsWindowMinWidth: CGFloat = 800
    static var settingsWindowMinHeight: CGFloat = 520
    static var settingsWindowCornerRadius: CGFloat = 20

    static var onboardingWindowWidth: CGFloat = 1200
    static var onboardingWindowHeight: CGFloat = 820

    // MARK: - Menu Type Detection
}

// MARK: - Notch Screens

enum NotchScreens {
    static func screens(for settings: Settings, among screens: [NSScreen] = NSScreen.screens) -> [NSScreen] {
        let ruleScreens = defaultScreens(for: settings.notchDisplayTarget, among: screens)
        return screens.filter { screen in
            DisplaySettingsKey.value(in: settings.perDisplayShowNotch, for: screen.displayIdentifier)
                ?? ruleScreens.contains(screen)
        }
    }

    static func showsNotch(on screen: NSScreen, settings: Settings) -> Bool {
        screens(for: settings).contains(screen)
    }

    static func defaultScreens(for target: NotchDisplayTarget, among screens: [NSScreen]) -> [NSScreen] {
        let main = screens.filter { $0.displayID == CGMainDisplayID() }
        switch target {
        case .macbookDisplay:
            if let builtIn = screens.first(where: { CGDisplayIsBuiltin($0.displayID) != 0 }) {
                return [builtIn]
            }
            return main
        case .mainDisplay:
            return main
        case .allDisplays:
            return screens
        }
    }
}

// MARK: - Environment

private struct NotchBandHeightKey: EnvironmentKey {
    static let defaultValue: CGFloat = 32
}

extension EnvironmentValues {
    var notchBandHeight: CGFloat {
        get { self[NotchBandHeightKey.self] }
        set { self[NotchBandHeightKey.self] = newValue }
    }
}

// MARK: - Expanded Sizing

enum NotchSizing {
    static func expandedContentSize(
        contentSize: CGSize,
        minimumSize: CGSize,
        scale: CGFloat = 1
    ) -> CGSize {
        let safeScale = max(0, scale)
        return CGSize(
            width: max(contentSize.width * safeScale, minimumSize.width),
            height: max(contentSize.height * safeScale, minimumSize.height)
        )
    }
}

// MARK: - Resolved Configuration
struct ResolvedNotchConfiguration: Equatable {

    // MARK: - Basic Size Configuration
    let universalWidth: CGFloat
    let universalHeight: CGFloat
    var initialSize: CGSize { CGSize(width: universalWidth, height: universalHeight) }
    let initialCornerRadius: CGFloat
    let topBuffer: CGFloat
    let isFloatingIsland: Bool
    let isNotchless: Bool
    let floatingIslandCornerRadius: CGFloat
    let widgetMenuTopInset: CGFloat
    let topInset: CGFloat
    let displayScale: CGFloat
    let cameraWidth: CGFloat

    // MARK: - Hover State
    let scaleFactor: CGFloat
    var hoverExpandedSize: CGSize { CGSize(width: universalWidth * scaleFactor, height: universalHeight * scaleFactor) }
    let hoverExpandedCornerRadius: CGFloat

    // MARK: - Auto-Expanded State
    let autoExpandedCornerRadius: CGFloat
    let autoExpandedTallHeight: CGFloat
    let autoExpandedContentVerticalPadding: CGFloat

    // MARK: - Click-Expanded State
    let clickExpandedCornerRadius: CGFloat
    let liveActivityBottomCornerRadius: CGFloat

    // MARK: - Delays
    let collapseAnimationDelay: TimeInterval
    let dragActivationCollapseDelay: TimeInterval

    // MARK: - Animation Configurations
    let expandAnimation: Animation
    let widgetSwitchAnimation: Animation
    let swipeOpenAnimation: Animation
    let collapseAnimation: Animation
    let hoverAnimation: Animation
    let contentTransitionAnimation: Animation
    let activityToActivityAnimation: Animation
    let bottomContentAnimation: Animation

    let couplesContentToMorph: Bool

    let bottomContentTransitionAnimation: Animation
    let activityOpacityAnimation: Animation

    // MARK: - Blur Animation Configurations
    let blurAnimation = NotchConfiguration.blurAnimation
    let blurRemovalAnimation = NotchConfiguration.blurRemovalAnimation
    let widgetBlurRadiusMax: CGFloat
    let focusPullAnimation = NotchConfiguration.focusPullAnimation
    let activityBlurRadiusMax: CGFloat
    let activityBlurAnimation = NotchConfiguration.activityBlurAnimation

    // MARK: - Shadow
    let expandedShadowColor: Color
    let expandedShadowRadius: CGFloat
    let expandedShadowOffsetY: CGFloat
    var expandedShadowOffset: CGPoint { CGPoint(x: 0, y: expandedShadowOffsetY) }
    let restingShadowOpacity: Double
    let restingShadowRadius: CGFloat
    let restingShadowOffsetY: CGFloat

    // MARK: - Content Padding and Layout
    let contentTopPadding: CGFloat
    let contentBottomPadding: CGFloat
    let contentHorizontalPadding: CGFloat

    // MARK: - Lyric View Configuration
    let lyricsFontSize: CGFloat
    let lyricsMaxWidth: CGFloat

    // MARK: - Navigation Header Configuration
    let navHeaderLeadingPadding: CGFloat
    let navHeaderTopPadding: CGFloat
    let navHeaderTitleFontSize: CGFloat
    let navHeaderTitleTopPadding: CGFloat

    // MARK: - Default Mode Icons Configuration
    let defaultModeIconsHorizontalPadding: CGFloat

    // MARK: - Other static values
    let activityContentHorizontalPadding: CGFloat
    let activityDefaultHorizontalPadding: CGFloat
    let activityWithContentHorizontalPadding: CGFloat
    let activityContentBottomPadding: CGFloat
    let activityCenterGap: CGFloat
    let barMinimumSpacerWidth: CGFloat
    let contentUpdateDelay = NotchConfiguration.contentUpdateDelay
    let activityAnimationOutDelay = NotchConfiguration.activityAnimationOutDelay
    let autoContentRenderDelay = NotchConfiguration.autoContentRenderDelay
    let activityBlurUpdateDelay = NotchConfiguration.activityBlurUpdateDelay
    let activitySizeChangeDelay = NotchConfiguration.activitySizeChangeDelay

    static let floatingIslandMinimumHeight: CGFloat = 30
    static let notchlessClickExpandedCornerRadius: CGFloat = 26

    static func islandCornerInset(radius: CGFloat, depth: CGFloat) -> CGFloat {
        guard depth < radius else { return 0 }
        let rise = radius - max(0, depth)
        return radius - (radius * radius - rise * rise).squareRoot()
    }

    static func islandRowInset(style: FloatingIslandStyle, rowTop: CGFloat) -> CGFloat {
        max(style.openPadding, islandCornerInset(radius: style.openCornerRadius, depth: rowTop) + 4)
    }

    init(from settings: Settings, screen: NSScreen? = nil) {
        let targetScreen = screen ?? CursorPosition.targetNotchScreen() ?? NSScreen.main
        let displayID = targetScreen?.displayIdentifier
        let metrics = targetScreen.map { NotchDisplayMetrics.current(for: $0) } ?? .fallback
        self.displayScale = metrics.scale
        self.cameraWidth = metrics.cameraWidth ?? 0
        self.isNotchless = !metrics.hasHardwareNotch
        self.isFloatingIsland = settings.resolvedFloatingIsland(forDisplayID: displayID)
            && !metrics.hasHardwareNotch

        self.activityContentHorizontalPadding = 15
        let islandStyle = settings.resolvedFloatingIslandStyle(forDisplayID: displayID)
        self.floatingIslandCornerRadius = islandStyle.openCornerRadius
        self.widgetMenuTopInset = isFloatingIsland ? islandStyle.openTopPadding : 0
        self.activityDefaultHorizontalPadding = isFloatingIsland ? islandStyle.sidePadding : 13
        self.activityWithContentHorizontalPadding = isFloatingIsland ? islandStyle.sidePadding + 2 : 15

            self.topBuffer = NotchConfiguration.topBuffer
            self.scaleFactor = NotchConfiguration.scaleFactor
            self.hoverExpandedCornerRadius = 18
            self.autoExpandedCornerRadius = 13
            self.autoExpandedTallHeight = 80
            self.autoExpandedContentVerticalPadding = NotchConfiguration.autoExpandedContentVerticalPadding
            self.clickExpandedCornerRadius = isNotchless
                ? Self.notchlessClickExpandedCornerRadius
                : NotchConfiguration.clickExpandedCornerRadius
            self.liveActivityBottomCornerRadius = 18
            self.collapseAnimationDelay = NotchConfiguration.collapseAnimationDelay
            self.dragActivationCollapseDelay = NotchConfiguration.dragActivationCollapseDelay
            self.widgetBlurRadiusMax = NotchConfiguration.widgetBlurRadiusMax
            self.activityBlurRadiusMax = NotchConfiguration.activityBlurRadiusMax
            self.expandedShadowColor = isNotchless ? Color.black.opacity(0.5) : NotchConfiguration.expandedShadowColor
            self.expandedShadowRadius = isNotchless ? 28 : NotchConfiguration.expandedShadowRadius
            self.expandedShadowOffsetY = isNotchless ? 14 : NotchConfiguration.expandedShadowOffset.y
            self.restingShadowOpacity = isFloatingIsland ? 0.32 : 0
            self.restingShadowRadius = 7
            self.restingShadowOffsetY = 3
            self.contentTopPadding = isFloatingIsland ? islandStyle.openPadding : 10
            self.contentBottomPadding = isFloatingIsland ? islandStyle.openPadding : 10
            self.contentHorizontalPadding = isFloatingIsland
                ? max(0, islandStyle.openPadding - CustomNotchShape.horizontalContentPadding)
                : 35
            self.activityContentBottomPadding = 10
            self.lyricsFontSize = 10
            self.lyricsMaxWidth = 200
            self.navHeaderLeadingPadding = isFloatingIsland
                ? max(0, Self.islandRowInset(style: islandStyle, rowTop: 8) - 10)
                : 40
            self.navHeaderTopPadding = 8
            self.navHeaderTitleFontSize = 18
            self.navHeaderTitleTopPadding = 10
            self.defaultModeIconsHorizontalPadding = isFloatingIsland
                ? Self.islandRowInset(style: islandStyle, rowTop: islandStyle.openTopPadding + 5)
                : 40

        let closedSize = NotchDisplayMetrics.resolvedClosedSize(
            measured: metrics,
            customWidth: settings.resolvedNotchWidth(forDisplayID: displayID),
            customHeight: settings.resolvedNotchHeight(forDisplayID: displayID),
            isFloatingIsland: isFloatingIsland,
            floatingIslandMinimumHeight: Self.floatingIslandMinimumHeight
        )
        self.universalWidth = closedSize.width
        self.universalHeight = closedSize.height
        self.initialCornerRadius = isFloatingIsland ? closedSize.height / 2 : NotchConfiguration.initialCornerRadius
        self.activityCenterGap = isFloatingIsland ? islandStyle.centerGap : max(universalWidth, cameraWidth)
        self.barMinimumSpacerWidth = (!isFloatingIsland && metrics.hasHardwareNotch)
            ? max(universalWidth, cameraWidth)
            : 0
        self.topInset = isFloatingIsland
            ? NotchDisplayMetrics.floatingIslandTopInset(
                userOffset: settings.resolvedFloatingIslandTopOffset(forDisplayID: displayID),
                islandHeight: closedSize.height,
                menuBarHeight: metrics.menuBarHeight,
                scale: metrics.scale
            )
            : 0

        let profile = settings.animationProfile
        let customAnim = settings.customAnimationConfiguration
        self.couplesContentToMorph = profile == .fluid

        switch profile {
        case .snappy:
            self.expandAnimation = NotchConfiguration.expandAnimation
            self.widgetSwitchAnimation = NotchConfiguration.widgetSwitchAnimation
            self.swipeOpenAnimation = NotchConfiguration.swipeOpenAnimation
            self.collapseAnimation = NotchConfiguration.collapseAnimation
            self.hoverAnimation = NotchConfiguration.hoverAnimation
            self.contentTransitionAnimation = NotchConfiguration.contentTransitionAnimation
            self.activityToActivityAnimation = NotchConfiguration.activityToActivityAnimation
            self.bottomContentAnimation = NotchConfiguration.bottomContentAnimation

        case .fluid:
            self.expandAnimation = .notchMorphSpring(response: 0.42, dampingFraction: 0.62)
            self.widgetSwitchAnimation = .notchMorphSpring(response: 0.44, dampingFraction: 0.86)
            self.swipeOpenAnimation = .notchMorphSpring(response: 0.42, dampingFraction: 0.62)
            self.collapseAnimation = .notchMorphSpring(response: 0.4, dampingFraction: 1.0)
            self.hoverAnimation = isFloatingIsland
                ? .notchMorphSpring(response: 0.3, dampingFraction: 0.56)
                : .notchMorphSpring(response: 0.32, dampingFraction: 0.62)
            self.contentTransitionAnimation = .notchMorphSpring(response: 0.44, dampingFraction: 0.9)
            self.activityToActivityAnimation = isFloatingIsland
                ? .notchMorphSpring(response: 0.46, dampingFraction: 0.7)
                : .notchMorphSpring(response: 0.44, dampingFraction: 0.88)
            self.bottomContentAnimation = .notchMorphSpring(response: 0.46, dampingFraction: 0.92)

        case .bouncy:
            self.expandAnimation = .notchMorphSpring(response: 0.4, dampingFraction: 0.65)
            self.widgetSwitchAnimation = .notchMorphSpring(response: 1.0, dampingFraction: 0.85)
            self.swipeOpenAnimation = .notchMorphSpring(response: 0.35, dampingFraction: 0.45)
            self.collapseAnimation = .notchMorphSpring(response: 0.3, dampingFraction: 0.98)
            self.hoverAnimation = .notchMorphSpring(response: 0.25, dampingFraction: 0.45)
            self.contentTransitionAnimation = .notchMorphSpring(response: 0.55, dampingFraction: 0.85)
            self.activityToActivityAnimation = .notchMorphSpring(response: 0.4, dampingFraction: 0.98)
            self.bottomContentAnimation = .notchMorphSpring(response: 0.42, dampingFraction: 0.999)

        case .calm:
            self.expandAnimation = .notchMorphSpring(response: 0.7, dampingFraction: 0.9)
            self.widgetSwitchAnimation = .notchMorphSpring(response: 0.7, dampingFraction: 0.9)
            self.swipeOpenAnimation = .notchMorphSpring(response: 0.7, dampingFraction: 0.9)
            self.collapseAnimation = .notchMorphSpring(response: 0.5, dampingFraction: 0.95)
            self.hoverAnimation = .notchMorphSpring(response: 0.5, dampingFraction: 1.0)
            self.contentTransitionAnimation = .notchMorphSpring(response: 0.75, dampingFraction: 0.9)
            self.activityToActivityAnimation = .notchMorphSpring(response: 0.6, dampingFraction: 0.98)
            self.bottomContentAnimation = .notchMorphSpring(response: 0.6, dampingFraction: 0.98)

        case .custom:
            self.expandAnimation = .notchMorphSpring(response: customAnim.expandResponse, dampingFraction: customAnim.expandDamping)
            self.widgetSwitchAnimation = .notchMorphSpring(response: customAnim.contentTransitionResponse, dampingFraction: customAnim.contentTransitionDamping)
            self.swipeOpenAnimation = .notchMorphSpring(response: customAnim.swipeOpenResponse, dampingFraction: customAnim.swipeOpenDamping)
            self.collapseAnimation = .notchMorphSpring(response: customAnim.collapseResponse, dampingFraction: customAnim.collapseDamping)
            self.hoverAnimation = .notchMorphSpring(response: customAnim.hoverResponse, dampingFraction: customAnim.hoverDamping)
            self.contentTransitionAnimation = .notchMorphSpring(response: customAnim.contentTransitionResponse, dampingFraction: customAnim.contentTransitionDamping)
            self.activityToActivityAnimation = .notchMorphSpring(response: customAnim.activityToActivityResponse, dampingFraction: customAnim.activityToActivityDamping)
            self.bottomContentAnimation = .notchMorphSpring(response: customAnim.bottomContentResponse, dampingFraction: customAnim.bottomContentDamping)
        }

        self.bottomContentTransitionAnimation = NotchConfiguration.bottomContentTransitionAnimation
        self.activityOpacityAnimation = NotchConfiguration.activityOpacityAnimation
    }
}