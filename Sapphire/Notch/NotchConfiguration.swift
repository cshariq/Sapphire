//
//  NotchConfiguration.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-05-08.
//
//

import SwiftUI
import AppKit

struct NotchConfiguration {

    static let universalWidth: CGFloat = 195*((NSScreen.main?.frame.size.width ?? 1728)/1728)
    static let universalHeight: CGFloat = 32*((NSScreen.main?.frame.size.height ?? 1117)/1117)
    static let initialSize = CGSize(width: universalWidth, height: universalHeight)
    static let initialCornerRadius: CGFloat = 10

    static let topBuffer: CGFloat = 0

    static let scaleFactor: CGFloat = 1.10
    static let hoverExpandedSize = CGSize(width: universalWidth * scaleFactor, height: universalHeight * scaleFactor)
    static let hoverExpandedCornerRadius: CGFloat = 18*((NSScreen.main?.frame.size.width ?? 1728)/1728)

    static let autoExpandedCornerRadius: CGFloat = 13*((NSScreen.main?.frame.size.width ?? 1728)/1728)
    static let autoExpandedTallHeight: CGFloat = 80*((NSScreen.main?.frame.size.width ?? 1728)/1728)

    static let autoExpandedContentVerticalPadding: CGFloat = 8*((NSScreen.main?.frame.size.width ?? 1728)/1728)

    static let clickExpandedCornerRadius: CGFloat = 40*((NSScreen.main?.frame.size.width ?? 1728)/1728)

    static let liveActivityBottomCornerRadius: CGFloat = 20*((NSScreen.main?.frame.size.width ?? 1728)/1728)

    static let collapseAnimationDelay: TimeInterval = 0.07
    static let initialOpenCollapseDelay: TimeInterval = 1.5
    static let widgetSwitchCollapseDelay: TimeInterval = 3.0

    // MARK: - Animation Configurations

    static let expandAnimation = Animation.spring(response: 0.45, dampingFraction: 0.68, blendDuration: 0)
    static let swipeOpenAnimation = Animation.spring(response: 0.5, dampingFraction: 0.85, blendDuration: 0)
    static let collapseAnimation = Animation.spring(response: 0.3, dampingFraction: 0.98, blendDuration: 0)
    static let autoExpandAnimation = Animation.spring(response: 0.42, dampingFraction: 0.92, blendDuration: 0)
    static let hoverAnimation = Animation.spring(response: 0.38, dampingFraction: 0.96, blendDuration: 0)
    static let contentTransitionAnimation = Animation.spring(response: 0.35, dampingFraction: 0.9, blendDuration: 0)
    static let activityToActivityAnimation = Animation.spring(response: 0.4, dampingFraction: 0.98, blendDuration: 0)
    static let activityMorphAnimation = Animation.spring(response: 0.5, dampingFraction: 0.88, blendDuration: 0)
    static let bottomContentAnimation = Animation.spring(response: 0.42, dampingFraction: 0.999, blendDuration: 0)
    static let heightIncreaseAnimation = Animation.spring(response: 0.38, dampingFraction: 0.995, blendDuration: 0)
    static let heightDecreaseAnimation = Animation.spring(response: 0.36, dampingFraction: 0.999, blendDuration: 0)
    static let largeMenuAnimation = Animation.spring(response: 0.5, dampingFraction: 0.97, blendDuration: 0)
    static let bottomContentTransitionAnimation = Animation.easeInOut(duration: 0.3)
    static let activityOpacityAnimation = Animation.easeInOut(duration: 0.2)
    static let immediateAnimation = Animation.linear(duration: 0)

    // MARK: - Blur Animation Configurations

    static let blurAnimation = Animation.easeIn(duration: 0.1)
    static let blurRemovalAnimation = Animation.easeOut(duration: 0.22)
    static let widgetBlurRadiusMax: CGFloat = 30
    static let focusPullAnimation = Animation.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.8)
    static let widgetBlurAnimation = Animation.easeIn(duration: 0.08)
    static let widgetBlurRemovalAnimation = focusPullAnimation
    static let contentFadeAnimation = Animation.easeIn(duration: 0.3)
    static let activityBlurRadiusMax: CGFloat = 40
    static let activityBlurAnimation = Animation.easeIn(duration: 0.1)
    static let activityBlurRemovalAnimation = Animation.timingCurve(0.33, 0.1, 0.67, 1, duration: 0.4)

    static let expandedShadowColor = Color.black.opacity(0.4)
    static let expandedShadowRadius: CGFloat = 18
    static let expandedShadowOffset = CGPoint(x: 0, y: 8)

    static let contentTopPadding: CGFloat = 10
    static let contentBottomPadding: CGFloat = 10
    static let contentHorizontalPadding: CGFloat = 35
    static let contentVisibilityThresholdHeight: CGFloat = universalHeight + 1
    static let primaryWidgetSwitchDelay: TimeInterval = 0.2 // Delay for switching between main widgets
    static let dragActivationCollapseDelay: TimeInterval = 0.1 // Faster collapse for drag-related views
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