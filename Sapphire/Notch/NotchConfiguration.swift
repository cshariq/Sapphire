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
    private static let externalMonitorNotchWidth: CGFloat = 150

    // MARK: - Screen Size Adjustments
    static func screenWidthAdjustment(for screen: NSScreen?) -> CGFloat {
        let currentWidth = (screen ?? NSScreen.main)?.frame.size.width ?? designReferenceResolution.width
        return currentWidth / designReferenceResolution.width
    }

    static func screenHeightAdjustment(for screen: NSScreen?) -> CGFloat {
        let currentHeight = (screen ?? NSScreen.main)?.frame.size.height ?? designReferenceResolution.height
        return currentHeight / designReferenceResolution.height
    }

    static func cornerRadiusAdjustment(for screen: NSScreen?) -> CGFloat {
        let widthScale = screenWidthAdjustment(for: screen)
        let heightScale = screenHeightAdjustment(for: screen)
        return min(max(min(widthScale, heightScale), 0.85), 1.10)
    }

    static var screenWidthAdjustment: CGFloat {
        screenWidthAdjustment(for: NSScreen.main)
    }

    static var screenHeightAdjustment: CGFloat {
        screenHeightAdjustment(for: NSScreen.main)
    }

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

        var width = fallbackClosedNotchSize.width
        var height = fallbackClosedNotchSize.height

        if screen.safeAreaInsets.top > 0,
           let leftArea = screen.auxiliaryTopLeftArea,
           let rightArea = screen.auxiliaryTopRightArea {
            let notchMinX = leftArea.maxX
            let notchMaxX = rightArea.minX
            let measuredWidth = notchMaxX - notchMinX
            if measuredWidth.isFinite, measuredWidth > 0 {
                width = measuredWidth + 4
            }
        } else if CGDisplayIsBuiltin(screen.displayID) != 0 {
            width = fallbackClosedNotchSize.width * screenWidthAdjustment(for: screen)
        } else {
            width = externalMonitorNotchWidth
        }

        let menuBarHeight = getMenuBarHeight(for: screen)
        if menuBarHeight > 0 {
            height = max(0, menuBarHeight - 0.2)
        } else if screen.safeAreaInsets.top > 0 {
            height = screen.safeAreaInsets.top
        }

        return (width: width, height: height)
    }

    // MARK: - Basic Size Configuration
    static var universalWidth: CGFloat { measuredNotchSize(for: referenceScreen).width }
    static var universalHeight: CGFloat { measuredNotchSize(for: referenceScreen).height }
    static var initialSize: CGSize { CGSize(width: universalWidth, height: universalHeight) }
    static var initialCornerRadius: CGFloat = 10 * screenHeightAdjustment

    static var topBuffer: CGFloat = 0

    static var scaleFactor: CGFloat = 1.10
    static var hoverExpandedSize: CGSize { CGSize(width: universalWidth * scaleFactor, height: universalHeight * scaleFactor) }
    static var hoverExpandedCornerRadius: CGFloat = 18 * screenWidthAdjustment

    static var autoExpandedCornerRadius: CGFloat = 13 * screenWidthAdjustment
    static var autoExpandedTallHeight: CGFloat = 80 * screenHeightAdjustment

    static var autoExpandedContentVerticalPadding: CGFloat = 8

    static var clickExpandedCornerRadius: CGFloat = 40

    static var liveActivityBottomCornerRadius: CGFloat = 18

    static var collapseAnimationDelay: TimeInterval = 0

    // MARK: - Animation Configurations (Represents the 'Snappy' default)
    static var expandAnimation = Animation.spring(response: 0.4, dampingFraction: 0.55, blendDuration: 0)
    static var widgetSwitchAnimation = Animation.spring(response: 0.4, dampingFraction: 0.95, blendDuration: 0)
    static var swipeOpenAnimation = Animation.spring(response: 0.35, dampingFraction: 0.45, blendDuration: 0)
    static var collapseAnimation = Animation.spring(response: 0.3, dampingFraction: 0.98, blendDuration: 0)
    static var hoverAnimation = Animation.spring(response: 0.25, dampingFraction: 0.55, blendDuration: 0)
    static var contentTransitionAnimation = Animation.spring(response: 0.45, dampingFraction: 1.0, blendDuration: 0)
    static var activityToActivityAnimation = Animation.spring(response: 0.4, dampingFraction: 0.98, blendDuration: 0)
    static var bottomContentAnimation = Animation.spring(response: 0.42, dampingFraction: 0.999, blendDuration: 0)
    static var bottomContentTransitionAnimation = Animation.easeInOut(duration: 0.3)
    static var activityOpacityAnimation = Animation.easeInOut(duration: 0.2)

    // MARK: - Blur Animation Configurations
    static var blurAnimation = Animation.easeIn(duration: 0.1)
    static var blurRemovalAnimation = Animation.easeOut(duration: 0.22)
    static var widgetBlurRadiusMax: CGFloat = 30
    static var focusPullAnimation = Animation.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.8)
    static var widgetBlurAnimation = Animation.easeIn(duration: 0.08)
    static var widgetBlurRemovalAnimation = focusPullAnimation
    static var contentFadeAnimation = Animation.easeIn(duration: 0.3)
    static var activityBlurRadiusMax: CGFloat = 40
    static var activityBlurAnimation = Animation.easeIn(duration: 0.1)
    static var activityBlurRemovalAnimation = Animation.timingCurve(0.33, 0.1, 0.67, 1, duration: 0.4)

    static var expandedShadowColor = Color.black.opacity(0.4)
    static var expandedShadowRadius: CGFloat = 18
    static var expandedShadowOffset: CGPoint { CGPoint(x: 0, y: 8) }
    static var notchShadowBleed: CGFloat = 28

    // MARK: - Content Padding and Layout
    static var contentTopPadding: CGFloat = 10 * screenHeightAdjustment
    static var contentBottomPadding: CGFloat = 10 * screenHeightAdjustment
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
    static var activityContentBottomPadding: CGFloat = 10 * screenHeightAdjustment

    // MARK: - Lyric View Configuration
    static var lyricsFontSize: CGFloat = 10 * screenHeightAdjustment
    static var lyricsMaxWidth: CGFloat = 200 * screenWidthAdjustment

    // MARK: - Navigation Header Configuration
    static var navHeaderLeadingPadding: CGFloat = 40 * screenWidthAdjustment
    static var navHeaderTopPadding: CGFloat = 8 * screenHeightAdjustment
    static var navHeaderTitleFontSize: CGFloat = 18 * screenHeightAdjustment
    static var navHeaderTitleTopPadding: CGFloat = 10 * screenHeightAdjustment

    // MARK: - Default Mode Icons Configuration
    static var defaultModeIconsHorizontalPadding: CGFloat = 40 * screenWidthAdjustment

    // MARK: - Button Configuration
    static var buttonDefaultIconSize: CGFloat = 14 * screenHeightAdjustment
    static var buttonDefaultHorizontalPadding: CGFloat = 8 * screenWidthAdjustment
    static var buttonDefaultVerticalPadding: CGFloat = 6 * screenHeightAdjustment
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

    static var onboardingWindowWidth: CGFloat = 1200
    static var onboardingWindowHeight: CGFloat = 820

    static var hostWindowMaxWidth: CGFloat = 1400 * screenWidthAdjustment
    static var hostWindowMaxHeight: CGFloat = 720 * screenHeightAdjustment

    // MARK: - Menu Type Detection
    static func isLargeVerticalMenu(_ mode: NotchWidgetMode) -> Bool {
        switch mode {
        case .musicPlayer, .sportsPlayer, .financePlayer, .notesPlayer, .clipboardPlayer, .nearDrop, .fileShelf, .weatherPlayer, .calendarPlayer, .geminiApiKeysMissing, .agentS, .blipHub, .circleToSearch, .multiAudio, .multiAudioDeviceAdjust, .multiAudioEQ, .multiAudioAppEQ:
            return true
        default:
            return false
        }
    }
}

// MARK: - Resolved Configuration
struct ResolvedNotchConfiguration {

    // MARK: - Basic Size Configuration
    let universalWidth: CGFloat
    let universalHeight: CGFloat
    var initialSize: CGSize { CGSize(width: universalWidth, height: universalHeight) }
    let initialCornerRadius: CGFloat
    let topBuffer: CGFloat

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
    let expandedShadowColor = NotchConfiguration.expandedShadowColor
    let expandedShadowRadius: CGFloat
    let expandedShadowOffsetY: CGFloat
    var expandedShadowOffset: CGPoint { CGPoint(x: 0, y: expandedShadowOffsetY) }

    // MARK: - Content Padding and Layout
    let contentTopPadding: CGFloat
    let contentBottomPadding: CGFloat
    let contentHorizontalPadding: CGFloat

    // MARK: - Other static values
    let activityContentHorizontalPadding: CGFloat
    let activityDefaultHorizontalPadding: CGFloat
    let activityWithContentHorizontalPadding: CGFloat
    let activityContentBottomPadding = NotchConfiguration.activityContentBottomPadding
    let contentUpdateDelay = NotchConfiguration.contentUpdateDelay
    let activityAnimationOutDelay = NotchConfiguration.activityAnimationOutDelay
    let autoContentRenderDelay = NotchConfiguration.autoContentRenderDelay
    let activityBlurUpdateDelay = NotchConfiguration.activityBlurUpdateDelay
    let activitySizeChangeDelay = NotchConfiguration.activitySizeChangeDelay

    init(from settings: Settings, screen: NSScreen? = nil) {
        let targetScreen = screen ?? CursorPosition.targetNotchScreen() ?? NSScreen.main
        let screenWidthAdj = NotchConfiguration.screenWidthAdjustment(for: targetScreen)
        let screenHeightAdj = NotchConfiguration.screenHeightAdjustment(for: targetScreen)

        self.activityContentHorizontalPadding = 15 * screenHeightAdj
        self.activityDefaultHorizontalPadding = 13 * screenHeightAdj
        self.activityWithContentHorizontalPadding = 15 * screenHeightAdj

        var baseWidth: CGFloat
        var baseHeight: CGFloat

        let measured = NotchConfiguration.measuredNotchSize(for: targetScreen)
        baseWidth = measured.width
        baseHeight = measured.height
            self.initialCornerRadius = 10 * NotchConfiguration.cornerRadiusAdjustment(for: targetScreen)
            self.topBuffer = NotchConfiguration.topBuffer
            self.scaleFactor = NotchConfiguration.scaleFactor
            self.hoverExpandedCornerRadius = 18 * NotchConfiguration.cornerRadiusAdjustment(for: targetScreen)
            self.autoExpandedCornerRadius = 13 * NotchConfiguration.cornerRadiusAdjustment(for: targetScreen)
            self.autoExpandedTallHeight = 80 * screenHeightAdj
            self.autoExpandedContentVerticalPadding = NotchConfiguration.autoExpandedContentVerticalPadding
            self.clickExpandedCornerRadius = NotchConfiguration.clickExpandedCornerRadius
            self.liveActivityBottomCornerRadius = 18 * NotchConfiguration.cornerRadiusAdjustment(for: targetScreen)
            self.collapseAnimationDelay = NotchConfiguration.collapseAnimationDelay
            self.dragActivationCollapseDelay = NotchConfiguration.dragActivationCollapseDelay
            self.widgetBlurRadiusMax = NotchConfiguration.widgetBlurRadiusMax
            self.activityBlurRadiusMax = NotchConfiguration.activityBlurRadiusMax
            self.expandedShadowRadius = NotchConfiguration.expandedShadowRadius
            self.expandedShadowOffsetY = NotchConfiguration.expandedShadowOffset.y
            self.contentTopPadding = 10 * screenHeightAdj
            self.contentBottomPadding = 10 * screenHeightAdj
            self.contentHorizontalPadding = 35 * screenHeightAdj

        let displayID = targetScreen?.displayIdentifier
        let resolvedWidth = settings.resolvedNotchWidth(forDisplayID: displayID)
        let resolvedHeight = settings.resolvedNotchHeight(forDisplayID: displayID)
        self.universalWidth = resolvedWidth > 0 ? resolvedWidth * screenWidthAdj : baseWidth
        self.universalHeight = resolvedHeight > 0 ? resolvedHeight * screenHeightAdj : baseHeight

        let profile = settings.animationProfile
        let customAnim = settings.customAnimationConfiguration

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

        case .bouncy:
            self.expandAnimation = .spring(response: 0.4, dampingFraction: 0.65)
            self.widgetSwitchAnimation = .spring(response: 1.0, dampingFraction: 0.85)
            self.swipeOpenAnimation = .spring(response: 0.35, dampingFraction: 0.45)
            self.collapseAnimation = .spring(response: 0.3, dampingFraction: 0.98)
            self.hoverAnimation = .spring(response: 0.25, dampingFraction: 0.45)
            self.contentTransitionAnimation = .spring(response: 0.55, dampingFraction: 0.85)
            self.activityToActivityAnimation = .spring(response: 0.4, dampingFraction: 0.98)
            self.bottomContentAnimation = .spring(response: 0.42, dampingFraction: 0.999)

        case .calm:
            self.expandAnimation = .spring(response: 0.7, dampingFraction: 0.9)
            self.widgetSwitchAnimation = .spring(response: 0.7, dampingFraction: 0.9)
            self.swipeOpenAnimation = .spring(response: 0.7, dampingFraction: 0.9)
            self.collapseAnimation = .spring(response: 0.5, dampingFraction: 0.95)
            self.hoverAnimation = .spring(response: 0.5, dampingFraction: 1.0)
            self.contentTransitionAnimation = .spring(response: 0.75, dampingFraction: 0.9)
            self.activityToActivityAnimation = .spring(response: 0.6, dampingFraction: 0.98)
            self.bottomContentAnimation = .spring(response: 0.6, dampingFraction: 0.98)

        case .custom:
            self.expandAnimation = .spring(response: customAnim.expandResponse, dampingFraction: customAnim.expandDamping)
            self.widgetSwitchAnimation = .spring(response: customAnim.contentTransitionResponse, dampingFraction: customAnim.contentTransitionDamping)
            self.swipeOpenAnimation = .spring(response: customAnim.swipeOpenResponse, dampingFraction: customAnim.swipeOpenDamping)
            self.collapseAnimation = .spring(response: customAnim.collapseResponse, dampingFraction: customAnim.collapseDamping)
            self.hoverAnimation = .spring(response: customAnim.hoverResponse, dampingFraction: customAnim.hoverDamping)
            self.contentTransitionAnimation = .spring(response: customAnim.contentTransitionResponse, dampingFraction: customAnim.contentTransitionDamping)
            self.activityToActivityAnimation = .spring(response: customAnim.activityToActivityResponse, dampingFraction: customAnim.activityToActivityDamping)
            self.bottomContentAnimation = .spring(response: customAnim.bottomContentResponse, dampingFraction: customAnim.bottomContentDamping)
        }

        self.bottomContentTransitionAnimation = NotchConfiguration.bottomContentTransitionAnimation
        self.activityOpacityAnimation = NotchConfiguration.activityOpacityAnimation
    }
}