//
//  NotchConfiguration.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-05-08.
//

import SwiftUI
import AppKit
import CoreGraphics

private enum NotchDeviceClass: String {
    case macBookPro14
    case macBookPro16
    case macBookAir13
    case macBookAir15
    case unknown
}

public enum DisplayDetection {

    public enum DeviceClass {
        case macBookPro14
        case macBookPro16
        case macBookAir13
        case macBookAir15
        case unknown
    }

    public static func detectDeviceClass() -> DeviceClass {
        guard let model = getModelIdentifier() else {
            return .unknown
        }

        switch model {
        case "MacBookPro18,3", "MacBookPro18,4", "Mac14,5", "Mac14,9", "Mac15,3", "Mac15,6", "Mac15,8", "Mac15,10", "Mac16,1", "Mac16,6", "Mac16,8":
            return .macBookPro14

        case "MacBookPro18,1", "MacBookPro18,2", "Mac14,6", "Mac14,10", "Mac15,7", "Mac15,9", "Mac15,11", "Mac15,6", "Mac15,8", "Mac15,10", "Mac16,5", "Mac16,7":
            return .macBookPro16

        case "MacBookAir10,1", "Mac14,2", "Mac15,12", "Mac16,12":
            return .macBookAir13

        case "Mac14,15", "Mac15,13", "Mac16,13":
            return .macBookAir15

        default:
            return .unknown
        }
    }
}

struct NotchConfiguration {
    // MARK: - Device-based Base Notch Sizes
    private static func baseNotchSize() -> (width: CGFloat, height: CGFloat) {
        switch DisplayDetection.detectDeviceClass() {
        case .macBookPro14:
            return (width: 205, height: 34)
        case .macBookPro16:
            return (width: 195, height: 32)
        case .macBookAir13:
            return (width: 190, height: 32.5)
        case .macBookAir15:
            return (width: 205, height: 32)
        case .unknown:
            return (width: 195, height: 32)
        }
    }

    private static func deviceBaselineLogicalResolution() -> CGSize {
        switch DisplayDetection.detectDeviceClass() {
        case .macBookPro14:
            return CGSize(width: 1512, height: 982)
        case .macBookPro16:
            return CGSize(width: 1728, height: 1117)
        case .macBookAir13:
            return CGSize(width: 1470, height: 956)
        case .macBookAir15:
            return CGSize(width: 1710, height: 1107)
        case .unknown:
            return CGSize(width: 1728, height: 1117)
        }
    }
    // MARK: - Screen Size Adjustments
    static var screenWidthAdjustment: CGFloat {
        let baseline = deviceBaselineLogicalResolution()
        let currentWidth = NSScreen.main?.frame.size.width ?? baseline.width
        return currentWidth / baseline.width
    }

    static var screenHeightAdjustment: CGFloat {
        let baseline = deviceBaselineLogicalResolution()
        let currentHeight = NSScreen.main?.frame.size.height ?? baseline.height
        return currentHeight / baseline.height
    }

    // MARK: - Basic Size Configuration
    static var universalWidth: CGFloat { baseNotchSize().width * screenWidthAdjustment }
    static var universalHeight: CGFloat { baseNotchSize().height * screenHeightAdjustment }
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

    static var collapseAnimationDelay: TimeInterval = 0.07
    static var initialOpenCollapseDelay: TimeInterval = 1.5
    static var widgetSwitchCollapseDelay: TimeInterval = 3.0

    // MARK: - Animation Configurations (Represents the 'Snappy' default)
    static var expandAnimation = Animation.spring(response: 0.4, dampingFraction: 0.55, blendDuration: 0)
    static var widgetSwitchAnimation = Animation.spring(response: 0.4, dampingFraction: 0.85, blendDuration: 0)
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

    // MARK: - Content Padding and Layout
    static var contentTopPadding: CGFloat = 10 * screenHeightAdjustment
    static var contentBottomPadding: CGFloat = 10 * screenHeightAdjustment
    static var contentHorizontalPadding: CGFloat = 35 * screenWidthAdjustment
    static var contentVisibilityThresholdHeight: CGFloat { universalHeight + 1 }
    static var primaryWidgetSwitchDelay: TimeInterval = 0.2
    static var dragActivationCollapseDelay: TimeInterval = 0.1

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
    static var activityContentHorizontalPadding: CGFloat = 15 * screenWidthAdjustment
    static var activityDefaultHorizontalPadding: CGFloat = 13 * screenWidthAdjustment
    static var activityWithContentHorizontalPadding: CGFloat = 15 * screenWidthAdjustment
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
    static var settingsWindowWidth: CGFloat = 950 * screenWidthAdjustment
    static var settingsWindowHeight: CGFloat = 650 * screenHeightAdjustment

    // MARK: - Menu Type Detection
    static func isLargeVerticalMenu(_ mode: NotchWidgetMode) -> Bool {
        switch mode {
        case .musicPlayer, .nearDrop, .fileShelf, .weatherPlayer, .calendarPlayer, .geminiApiKeysMissing:
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
    let initialOpenCollapseDelay: TimeInterval
    let widgetSwitchCollapseDelay: TimeInterval
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
    let activityContentHorizontalPadding = NotchConfiguration.activityContentHorizontalPadding
    let activityDefaultHorizontalPadding = NotchConfiguration.activityDefaultHorizontalPadding
    let activityWithContentHorizontalPadding = NotchConfiguration.activityWithContentHorizontalPadding
    let activityContentBottomPadding = NotchConfiguration.activityContentBottomPadding
    let contentUpdateDelay = NotchConfiguration.contentUpdateDelay
    let activityAnimationOutDelay = NotchConfiguration.activityAnimationOutDelay
    let autoContentRenderDelay = NotchConfiguration.autoContentRenderDelay
    let activityBlurUpdateDelay = NotchConfiguration.activityBlurUpdateDelay
    let activitySizeChangeDelay = NotchConfiguration.activitySizeChangeDelay

    init(from settings: Settings) {
        if settings.useCustomNotchConfiguration {
            let custom = settings.customNotchConfiguration
            let screenWidthAdj = NotchConfiguration.screenWidthAdjustment
            let screenHeightAdj = NotchConfiguration.screenHeightAdjustment

            self.universalWidth = custom.universalWidth * screenWidthAdj
            self.universalHeight = custom.universalHeight * screenHeightAdj
            self.initialCornerRadius = custom.initialCornerRadius * screenHeightAdj
            self.topBuffer = custom.topBuffer

            self.scaleFactor = custom.scaleFactor
            self.hoverExpandedCornerRadius = custom.hoverExpandedCornerRadius * screenWidthAdj

            self.autoExpandedCornerRadius = custom.autoExpandedCornerRadius * screenWidthAdj
            self.autoExpandedTallHeight = custom.autoExpandedTallHeight * screenHeightAdj
            self.autoExpandedContentVerticalPadding = custom.autoExpandedContentVerticalPadding * screenWidthAdj

            self.clickExpandedCornerRadius = custom.clickExpandedCornerRadius * screenWidthAdj
            self.liveActivityBottomCornerRadius = custom.liveActivityBottomCornerRadius * screenWidthAdj

            self.collapseAnimationDelay = custom.collapseAnimationDelay
            self.initialOpenCollapseDelay = custom.initialOpenCollapseDelay
            self.widgetSwitchCollapseDelay = custom.widgetSwitchCollapseDelay
            self.dragActivationCollapseDelay = custom.dragActivationCollapseDelay

            self.widgetBlurRadiusMax = custom.widgetBlurRadiusMax
            self.activityBlurRadiusMax = custom.activityBlurRadiusMax
            self.expandedShadowRadius = custom.expandedShadowRadius
            self.expandedShadowOffsetY = custom.expandedShadowOffsetY

            self.contentTopPadding = custom.contentTopPadding * screenHeightAdj
            self.contentBottomPadding = custom.contentBottomPadding * screenHeightAdj
            self.contentHorizontalPadding = custom.contentHorizontalPadding * screenWidthAdj

        } else {
            self.universalWidth = NotchConfiguration.universalWidth
            self.universalHeight = NotchConfiguration.universalHeight
            self.initialCornerRadius = NotchConfiguration.initialCornerRadius
            self.topBuffer = NotchConfiguration.topBuffer
            self.scaleFactor = NotchConfiguration.scaleFactor
            self.hoverExpandedCornerRadius = NotchConfiguration.hoverExpandedCornerRadius
            self.autoExpandedCornerRadius = NotchConfiguration.autoExpandedCornerRadius
            self.autoExpandedTallHeight = NotchConfiguration.autoExpandedTallHeight
            self.autoExpandedContentVerticalPadding = NotchConfiguration.autoExpandedContentVerticalPadding
            self.clickExpandedCornerRadius = NotchConfiguration.clickExpandedCornerRadius
            self.liveActivityBottomCornerRadius = NotchConfiguration.liveActivityBottomCornerRadius
            self.collapseAnimationDelay = NotchConfiguration.collapseAnimationDelay
            self.initialOpenCollapseDelay = NotchConfiguration.initialOpenCollapseDelay
            self.widgetSwitchCollapseDelay = NotchConfiguration.widgetSwitchCollapseDelay
            self.dragActivationCollapseDelay = NotchConfiguration.dragActivationCollapseDelay
            self.widgetBlurRadiusMax = NotchConfiguration.widgetBlurRadiusMax
            self.activityBlurRadiusMax = NotchConfiguration.activityBlurRadiusMax
            self.expandedShadowRadius = NotchConfiguration.expandedShadowRadius
            self.expandedShadowOffsetY = NotchConfiguration.expandedShadowOffset.y
            self.contentTopPadding = NotchConfiguration.contentTopPadding
            self.contentBottomPadding = NotchConfiguration.contentBottomPadding
            self.contentHorizontalPadding = NotchConfiguration.contentHorizontalPadding
        }

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