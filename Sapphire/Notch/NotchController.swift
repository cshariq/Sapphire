//
//  NotchController.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-07-04
//

import SwiftUI
import Combine
import ScreenCaptureKit
import NearbyShare
import UniformTypeIdentifiers
import AppKit
import os.log

private let notchLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Sapphire", category: "NotchController")

fileprivate struct BatteryInfoView: View {
    let level: Int
    let isCharging: Bool
    let timeRemaining: String?

    private var batteryColor: Color {
        if isCharging { return .green }
        if level <= 10 { return .red }
        if level <= 20 { return .yellow }
        return .white
    }

    private var contentColor: Color {
        return .black
    }

    var body: some View {
        HStack(spacing: NotchConfiguration.batteryHStackSpacing) {
            if let timeString = timeRemaining {
                Text(timeString)
                    .font(.system(size: NotchConfiguration.batteryTextFontSize, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .transition(.opacity.animation(.easeInOut))
                    .padding(.trailing, NotchConfiguration.batteryTextTrailingPadding)
            }
            ZStack {
                Image(systemName: "battery.100")
                    .font(.system(size: NotchConfiguration.batteryIconSize, weight: .light))
                    .foregroundColor(.white.opacity(0.7))

                HStack(spacing: 0) {
                    Rectangle()
                        .fill(batteryColor)
                        .frame(width: 35 * (CGFloat(level) / 100.0))
                    Spacer(minLength: 0)
                }
                .padding(.leading, NotchConfiguration.batteryIconPadding)
                .padding(.vertical, NotchConfiguration.batteryIconPadding)
                .mask {
                    Image(systemName: "battery.100")
                        .font(.system(size: NotchConfiguration.batteryIconSize, weight: .light))
                }

                if isCharging {
                    HStack(spacing: 0) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: NotchConfiguration.batteryBoltIconSize, weight: .bold))
                        Text("\(level)")
                            .font(.system(size: NotchConfiguration.batteryValueFontSize, weight: .medium, design: .rounded))
                    }
                    .foregroundColor(level > 10 ? contentColor : .white)
                } else {
                    Text("\(level)")
                        .font(.system(size: NotchConfiguration.batteryValueFontSize, weight: .medium, design: .rounded))
                        .foregroundColor(level > 10 ? contentColor : .white)
                }
            }
            .frame(width: NotchConfiguration.batteryFrameWidth, height: NotchConfiguration.batteryFrameHeight)
        }
    }
}

fileprivate class SettingsWindowDelegate: NSObject, NSWindowDelegate {
    var onClose: () -> Void
    init(onClose: @escaping () -> Void) { self.onClose = onClose }
    func windowWillClose(_ notification: Notification) { onClose() }
}

fileprivate struct MaxContentWidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct NotchController: View {
    let notchWindow: NSWindow?
    private let notchWidget: NotchWidgetView

    enum NotchState: Hashable {
        case initial, autoExpanded, hoverExpanded, clickExpanded
    }

    private static let widgetSwitchProtectionDuration: TimeInterval = 2.5
    private static let hoverDetectionMargin: CGFloat = 8
    private static let hoverCollapseMargin: CGFloat = 60
    private static let hoverProximityMargin: CGFloat = 32
    private static let revealSettlingInterval: TimeInterval = 0.7

    // MARK: - Environment Objects
    @EnvironmentObject var liveActivityManager: LiveActivityManager
    @EnvironmentObject var musicWidget: MusicManager
    @EnvironmentObject var geminiLiveManager: GeminiLiveManager
    @EnvironmentObject var pickerHelper: ContentPickerHelper
    @EnvironmentObject var settings: SettingsModel
    @EnvironmentObject var batteryEstimator: BatteryEstimator
    @EnvironmentObject var timerManager: TimerManager
    @EnvironmentObject var desktopManager: DesktopManager

    // MARK: - State Objects
    @StateObject private var fileShelfState = FileShelfState()
    @StateObject private var dragManager = GlobalDragManager.shared
    @StateObject private var dragState = DragStateManager.shared
    @StateObject private var audioManager = MultiAudioManager.shared
    @StateObject private var caffeineManager = CaffeineManager.shared
    @StateObject private var calendarViewModel: InteractiveCalendarViewModel

    @ObservedObject private var activeAppMonitor = ActiveAppMonitor.shared
    @ObservedObject private var microphoneManager = MicrophoneUsageManager.shared
    @ObservedObject private var systemHUD = SystemHUDManager.shared

    // MARK: - State Properties
    @State private var config: ResolvedNotchConfiguration?
    @State private var notchState: NotchState = .initial
    @State private var isHovered: Bool = false
    @State private var collapseTask: Task<Void, Never>?
    @State private var isCollapseTimerActive: Bool = false
    @State private var widgetSwitchProtectionTask: Task<Void, Never>?
    @State private var widgetSwitchProtectionGeneration: UInt64 = 0
    @State private var isPinned = false
    @State private var settingsWindow: NSWindow?
    @State private var settingsDelegate: SettingsWindowDelegate?
    @State private var isGeminiHovered = false
    @State private var animatedWidth: CGFloat = 0
    @State private var animatedHeight: CGFloat = 0
    @State private var animatedCornerRadius: CGFloat = 0
    @State private var animatedBottomCornerRadius: CGFloat = 0
    @State private var animatedContentScale: CGFloat = 1.0

    @State private var shadowOpacity: Double = 0
    @State private var measuredClickContentSize: CGSize = .zero
    @State private var measuredAutoContentSize: CGSize = .zero
    @State private var notchIconsLeftWidth: CGFloat = 0
    @State private var notchIconsRightWidth: CGFloat = 0
    @State private var navigationStack: [NotchWidgetMode] = [.defaultWidgets]
    @State private var autoContentOpacity: Double = 0
    @State private var activityBlurRadius: CGFloat = 0
    @State private var contentBlurOpacity: Double = 0
    @State private var activityContentScale: CGFloat = 1.0
    @State private var canRenderAutoContent: Bool = false
    @State private var isAnimatingActivityOut = false
    @State public var isFileDropTargeted: Bool = false
    @State private var draggedAppBundleID: String? = nil
    @State private var activeDropZone: DropZone? = nil
    @State private var showLyrics: Bool = false
    @State private var maxActivityContentWidth: CGFloat = 0
    @State private var liveActivityHorizontalPadding: CGFloat = 0
    @State private var expansionAnimation: Animation = .default
    @State private var cancellables = Set<AnyCancellable>()
    @State private var awaitingDropCompletion: Bool = false
    @State private var hudOverlayOpacity: Double = 0.0
    @State private var hudOverlayBlur: CGFloat = 10.0

    @State private var notchInteractionPollingTimer: Timer?
    @State private var lastSampledMouseLocation: CGPoint?
    @State private var lastInteractionRefreshTime: TimeInterval = 0
    @State private var lastPublishedInteractiveFrame: CGRect = .null
    @State private var appliedTargetFPS: Int = 0
    @State private var lastActivityShapeSignature: String = ""
    @State private var isCalendarHovered: Bool = false
    @State private var fileDropFlowObserver: NSObjectProtocol?
    @State private var completeHideReason: NotchCompleteHideReason? = nil
    @State private var inactiveHideUserOverride: Bool = false
    @State private var suppressHoverAfterReveal = false
    @State private var revealSettlingUntil: Date = .distantPast
    @State private var hoverExpandTask: Task<Void, Never>?

    private enum NotchCompleteHideReason {
        case manualSwipe
        case inactive
    }

    private var isManuallyHidden: Bool { completeHideReason != nil }

    // MARK: - Computed Properties
    private var isLiveActivityActive: Bool { liveActivityManager.currentActivity != .none }

    private var effectiveActivity: ActivityType {
        let activity = liveActivityManager.currentActivity
        guard activity != .none else { return .none }
        if shouldHideActivityForFullScreen || shouldHideActivityForInactiveDisplay {
            return .none
        }
        return activity
    }
    private var isFullViewActivity: Bool { liveActivityManager.isFullViewActivity }
    private var isGeminiActive: Bool { liveActivityManager.currentActivity == .geminiLive || liveActivityManager.currentActivity == .intelligenceAgent }

    private var isDisplayingMusicLiveActivity: Bool {
        let isMusic = (liveActivityManager.currentActivity == .music)
        let isShowingActivityView = (notchState == .autoExpanded || notchState == .hoverExpanded)
        return isMusic && isShowingActivityView
    }

    private var isInteractiveLiveActivity: Bool {
        guard isLiveActivityActive else { return false }

        let activityType = liveActivityManager.currentActivity

        switch activityType {
        case .nearbyShare:
            if let payload = liveActivityManager.currentNearDropPayload,
               payload.state == .waitingForConsent {
                return true
            }
        case .eyeBreak, .notification, .otp, .parcel:
            return true
        default:
            break
        }

        return false
    }

    private var currentMode: NotchWidgetMode { navigationStack.last ?? .defaultWidgets }

    private var notchIconsIntrinsicWidth: CGFloat {
        notchIconsLeftWidth + notchIconsRightWidth + NotchConfiguration.defaultModeIconsHorizontalPadding * 2
    }

    private var activeAppearanceSettings: NotchAppearanceSettings {
        switch notchState {
        case .initial, .clickExpanded:
            return settings.settings.notchWidgetAppearance
        case .autoExpanded, .hoverExpanded:
            if isLiveActivityActive {
                return settings.settings.notchLiveActivityAppearance
            } else {
                return settings.settings.notchWidgetAppearance
            }
        }
    }

    private var isExpandedLiveActivity: Bool {
        (notchState == .autoExpanded || notchState == .hoverExpanded) && isLiveActivityActive
    }

    private var liveActivityFadeStartLocation: Double {
        guard let config, animatedHeight > 0 else { return 1 }
        let initialHeight = config.initialSize.height
        guard animatedHeight > initialHeight else { return 1 }
        return min(max(Double(initialHeight / animatedHeight), 0), 1)
    }

    private var resolvedAppearanceSettings: NotchAppearanceSettings {
        var appearance = activeAppearanceSettings
        switch appearance.mode {
        case .default:
            appearance.solidColor = CodableColor(color: .black)
            appearance.opacity = 1
            appearance.enableTransparencyBlur = false
            appearance.liquidGlassLook = true
            if appearance.bottomFadeEnabled {
                if isExpandedLiveActivity {
                    if liveActivityManager.isFullViewActivity || liveActivityManager.activityHasBottomContent {
                        appearance.backgroundStyle = .gradient
                        appearance.gradientAngle = 90
                        appearance.gradientColors = [
                            CodableColor(color: .black, location: liveActivityFadeStartLocation),
                            CodableColor(color: Color.black.opacity(0), location: 1.0)
                        ]
                    } else {
                        appearance.backgroundStyle = .solid
                    }
                } else {
                    appearance.backgroundStyle = .gradient
                    appearance.gradientAngle = 90
                    appearance.gradientColors = [
                        CodableColor(color: .black, location: 0.7),
                        CodableColor(color: Color.black.opacity(0), location: 1.0)
                    ]
                }
            } else {
                appearance.backgroundStyle = .solid
            }
        case .liquidGlass:
            appearance.backgroundStyle = .solid
            appearance.solidColor = CodableColor(color: .black)
            appearance.opacity = 0.0
            appearance.enableTransparencyBlur = false
            appearance.liquidGlassLook = true
            appearance.bottomFadeEnabled = false
        case .blur:
            appearance.backgroundStyle = .solid
            appearance.solidColor = CodableColor(color: .black)
            appearance.opacity = 0.55
            appearance.enableTransparencyBlur = true
            appearance.liquidGlassLook = false
            appearance.bottomFadeEnabled = false
        case .custom:
            appearance.bottomFadeEnabled = false
        }
        return appearance
    }

    private var isInteractive: Bool {
        !isManuallyHidden && (notchState == .clickExpanded || isHovered || dragManager.isDraggingInActivationZone || activeAppMonitor.isWindowDragging)
    }

    private var resolvedDesktopNumber: Int {
        desktopManager.desktopNumber(for: notchWindow?.screen) ?? 1
    }

    private var cursorIsOnMyScreen: Bool {
        guard let notchScreen = notchWindow?.screen else {
            return CursorPosition.targetNotchScreen() == nil
        }
        let mouseLocation = NSEvent.mouseLocation
        return notchScreen.frame.contains(mouseLocation)
    }

    private var myScreenIsFullScreen: Bool {
        guard activeAppMonitor.isFullScreen,
              let fsDisplayID = activeAppMonitor.fullScreenDisplayID,
              let notchScreen = notchWindow?.screen,
              let myDisplayID = notchScreen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
            return false
        }
        return fsDisplayID == myDisplayID
    }

    private var shouldHideActivityForFullScreen: Bool {
        guard settings.settings.hideLiveActivityInFullScreen, myScreenIsFullScreen else {
            return false
        }
        notchLog.info("shouldHideActivityForFullScreen: hiding on this display (fullscreen on my screen)")
        return true
    }

    private var shouldHideActivityForInactiveDisplay: Bool {
        guard liveActivityManager.currentActivity == .systemHUD else { return false }
        return !cursorIsOnMyScreen
    }

    private var shouldHideWindowForSharing: Bool {
        settings.settings.hideFromScreenSharing
    }

    private var shouldBlockNotchExpansionWhileLocked: Bool {
        settings.settings.preventNotchExpandWhenLocked
            && ((NSApp.delegate as? AppDelegate)?.isScreenLocked == true)
    }

    private var geminiShadowGradient: LinearGradient {
        LinearGradient(
            gradient: Gradient(colors: [
                .purple.opacity(0.7),
                .indigo.opacity(0.8),
            ]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var glowOpacity: Double {
        guard isGeminiActive else { return 0 }
        let baseOpacity = (notchState == .initial || notchState == .autoExpanded) ?
        NotchConfiguration.geminiGlowBaseOpacityNormal :
        NotchConfiguration.geminiGlowBaseOpacityExpanded
        return baseOpacity + (Double(geminiLiveManager.currentAudioLevel) * NotchConfiguration.geminiGlowAudioMultiplier)
    }

    private var glowRadius: CGFloat {
        guard isGeminiActive else { return 0 }
        let baseRadius: CGFloat = (notchState == .initial || notchState == .autoExpanded) ?
        NotchConfiguration.geminiGlowBaseRadiusNormal :
        NotchConfiguration.geminiGlowBaseRadiusExpanded
        return baseRadius + (CGFloat(geminiLiveManager.currentAudioLevel) * NotchConfiguration.geminiGlowAudioRadiusMultiplier)
    }

    private var currentViewTitle: String? {
        switch currentMode {
        case .multiAudioDeviceAdjust: return "Adjust"
        case .multiAudioEQ: return "EQ"
        case .musicDevices: return "Devices"
        case .musicQueueAndPlaylists: return "Queue & Playlists"
        case .multiAudio: return "Audio Devices"
        default: return nil
        }
    }

    private var activeScaleFactor: CGFloat {
        guard let config = config, notchState == .hoverExpanded && !isFullViewActivity else { return 1.0 }
        return config.scaleFactor
    }

    private var enabledAndOrderedWidgets: [WidgetType] {
        let orderedTypes = settings.settings.widgetOrder
        return orderedTypes.filter { widgetType in
            switch widgetType {
            case .music:
                return settings.settings.musicWidgetEnabled && (!settings.settings.hideMusicWidgetWhenNotPlaying || (musicWidget.title != nil && !musicWidget.title!.isEmpty))
            case .weather:
                return settings.settings.weatherWidgetEnabled
            case .calendar:
                return settings.settings.calendarWidgetEnabled
            case .sports:
                return settings.settings.sportsWidgetEnabled && SubscriptionManager.shared.hasAccess(to: .sportsWidget)
            case .finance:
                return settings.settings.financeWidgetEnabled && SubscriptionManager.shared.hasAccess(to: .financeWidget)
            case .shopify:
                return settings.settings.shopifyWidgetEnabled
            case .shortcuts:
                return settings.settings.shortcutsWidgetEnabled
            case .agent:
                return settings.settings.intelligenceEnabled
            case .notes:
                return settings.settings.notesWidgetEnabled
            case .clipboard:
                return settings.settings.clipboardWidgetEnabled
            case .mirror:
                return settings.settings.mirrorWidgetEnabled
            case .focusSession:
                return settings.settings.focusSessionWidgetEnabled
            }
        }
    }

    private var switchableWidgetModes: [NotchWidgetMode] {
        return enabledAndOrderedWidgets.compactMap { widgetType in
            switch widgetType {
            case .music: return .musicPlayer
            case .weather: return .weatherPlayer
            case .calendar: return .calendarPlayer
            case .sports: return .sportsPlayer
            case .finance: return .financePlayer
            case .shopify: return .shopifyOrders
            case .shortcuts: return nil
            case .agent: return .agentS
            case .notes: return .notesPlayer
            case .clipboard: return .clipboardPlayer
            case .mirror: return .mirrorPlayer
            case .focusSession: return .focusSessionDetailView
            }
        }
    }

    private var currentSnapLayout: SnapLayout {
        let allLayouts = LayoutTemplate.allTemplates + settings.settings.customSnapLayouts
        if let bundleID = draggedAppBundleID,
           let config = settings.settings.appSpecificLayoutConfigurations[bundleID] {
            switch config {
            case .single(let layoutID):
                if let layout = allLayouts.first(where: { $0.id == layoutID }) {
                    return layout
                }
            case .useGlobalDefault, .multi:
                break
            }
        }
        return settings.settings.defaultSnapLayout
    }

    private var leftNotchButtons: [NotchButtonType] {
        let allButtons = settings.settings.notchButtonOrder
        if let spacerIndex = allButtons.firstIndex(of: .spacer) {
            return Array(allButtons.prefix(upTo: spacerIndex))
        }
        return allButtons
    }

    private var rightNotchButtons: [NotchButtonType] {
        let allButtons = settings.settings.notchButtonOrder
        if let spacerIndex = allButtons.firstIndex(of: .spacer) {
            return Array(allButtons.suffix(from: allButtons.index(after: spacerIndex)))
        }
        return []
    }

    private var showRightHUDOverlay: Bool {
        guard notchState == .clickExpanded else { return false }
        guard cursorIsOnMyScreen else { return false }
        guard let hud = systemHUD.currentHUD else { return false }
        switch hud.caseIdentifier {
        case .volume, .externalDeviceVolume, .appVolume:
            guard settings.settings.enableVolumeHUD else { return false }
            return true
        case .brightness, .keyboardBrightness, .multiDisplayBrightness:
            guard settings.settings.enableBrightnessHUD else { return false }
            return true
        }
    }

    private func updateHUDOverlayAnimation() {
        if showRightHUDOverlay {
            withAnimation(.easeOut(duration: 0.18)) {
                hudOverlayOpacity = 1.0
                hudOverlayBlur = 0.0
            }
        } else {
            withAnimation(.easeIn(duration: 0.12)) {
                hudOverlayOpacity = 0.0
                hudOverlayBlur = 10.0
            }
        }
    }

    private var activeShape: CustomNotchShape {
        CustomNotchShape(
            cornerRadius: animatedCornerRadius,
            bottomCornerRadius: animatedBottomCornerRadius,
            isMusicActivity: isDisplayingMusicLiveActivity
        )
    }

    // MARK: - Initializer
    public init(notchWindow: NSWindow?) {
        self.notchWindow = notchWindow
        let calendarViewModel = InteractiveCalendarViewModel()
        _calendarViewModel = StateObject(wrappedValue: calendarViewModel)
self.notchWidget = NotchWidgetView(calendarViewModel: calendarViewModel)
    }

    // MARK: - Body
    var body: some View {
        if let config = config {
            configuredNotchView(config: config)
        } else {
            Color.clear
                .onAppear {
                    let targetScreen = notchWindow?.screen ?? CursorPosition.targetNotchScreen()
                    let initialConfig = ResolvedNotchConfiguration(from: settings.settings, screen: targetScreen)
                    self.config = initialConfig
                    self.animatedWidth = initialConfig.initialSize.width
                    self.animatedHeight = initialConfig.initialSize.height
                    self.animatedCornerRadius = initialConfig.initialCornerRadius
                    self.animatedBottomCornerRadius = initialConfig.initialCornerRadius
                    self.expansionAnimation = initialConfig.expandAnimation
                    self.liveActivityHorizontalPadding = initialConfig.activityDefaultHorizontalPadding
                }
        }
    }

    @ViewBuilder
    private func configuredNotchView(config: ResolvedNotchConfiguration) -> some View {
        let chrome = applyNotchChrome(to: notchVisualStack(config: config), config: config)
        applyNotchSettingsHandlers(
            to: applyNotchNotificationHandlers(
                to: applyNotchStateHandlers(to: chrome)
            )
        )
    }

    @ViewBuilder
    private func notchVisualStack(config: ResolvedNotchConfiguration) -> some View {
        ZStack(alignment: .top) {
            if isGeminiActive {
                let isShadowVisible = (notchState != .initial)
                let shadowRadius = notchState == .clickExpanded ? config.expandedShadowRadius : 12
                let shadowYOffset = notchState == .clickExpanded ? config.expandedShadowOffsetY : 6
                activeShape
                    .fill(geminiShadowGradient)
                    .blur(radius: shadowRadius)
                    .offset(y: shadowYOffset)
                    .opacity(isShadowVisible ? 0.75 : 0)
                    .allowsHitTesting(false)
            }

            notchBackground
                .mask(activeShape)

            if shouldShowBottomEdgeFade(config: config) {
                bottomEdgeFade(config: config)
                    .mask(activeShape)
                    .allowsHitTesting(false)
            }

            ZStack(alignment: .top) {
                let showActivityView = (notchState == .autoExpanded || notchState == .hoverExpanded || isAnimatingActivityOut)
                if showActivityView && effectiveActivity != .none && canRenderAutoContent {
                    let activityTransition = liveActivityManager.activityHasBottomContent
                        ? config.bottomContentTransitionAnimation
                        : config.activityToActivityAnimation
                    autoActivityView
                        .fixedSize(horizontal: true, vertical: false)
                        .blur(radius: activityBlurRadius)
                        .scaleEffect(activityContentScale)
                        .id(liveActivityManager.currentActivity)
                        .animation(activityTransition, value: liveActivityManager.activityAnimationKey)
                        .opacity(autoContentOpacity)
                        .scaleEffect(animatedContentScale)
                } else {
                    contentView
                        .mask(activeShape)
                }

                if notchState == .clickExpanded {
                    expandedOverlayIcons
                        .transition(.opacity.animation(.easeInOut(duration: 0.2)))
                        .zIndex(1)

                    hudOverlayView
                        .transition(.opacity.animation(.easeOut(duration: 0.18)))
                        .zIndex(3)
                }
            }
        }
    }

    private func applyNotchChrome<V: View>(to view: V, config: ResolvedNotchConfiguration) -> some View {
        let shadowRadius: CGFloat = {
            if isGeminiActive { return 0 }
            switch notchState {
            case .clickExpanded: return config.expandedShadowRadius
            case .hoverExpanded: return 12
            default: return 0
            }
        }()
        let shadowY: CGFloat = {
            if isGeminiActive { return 0 }
            switch notchState {
            case .clickExpanded: return config.expandedShadowOffsetY
            case .hoverExpanded: return 6
            default: return 0
            }
        }()
        return view
            .shadow(
                color: isGeminiActive ? .clear : config.expandedShadowColor.opacity(shadowOpacity),
                radius: shadowRadius,
                y: shadowY
            )
            .frame(width: animatedWidth, height: animatedHeight)
            .contentShape(activeShape)
            .onDrop(of: [UTType.fileURL, .plainText], isTargeted: $isFileDropTargeted, perform: handleItemDrop)
            .padding(.top, -config.topBuffer)
            .frame(maxWidth: .infinity, alignment: .top)
            .preferredColorScheme(.dark)
    }

    private func applyNotchStateHandlers<V: View>(to view: V) -> some View {
        view
            .onAppear(perform: setupMonitors)
            .onDisappear(perform: teardownMonitors)
            .onChange(of: fileShelfState.selectedItemForPreview, perform: handlePreviewItemChange)
            .onChange(of: liveActivityManager.currentActivity, perform: handleActivityChange)
            .onChange(of: showRightHUDOverlay) { _, _ in
                updateHUDOverlayAnimation()
            }
            .onChange(of: liveActivityManager.contentUpdateID) {
                handleLiveActivityContentUpdate()
            }
            .onChange(of: notchState, handleStateChange)
            .onChange(of: navigationStack, handleNavigationStackChange)
            .onChange(of: dragManager.isDraggingInActivationZone, perform: handleDragActivationZoneChange)
            .onChange(of: activeAppMonitor.isWindowDragging, perform: handleActiveWindowDragChange)
            .onChange(of: isFileDropTargeted, perform: handleFileDropTargetChange)
            .onChange(of: measuredClickContentSize, perform: handleMeasuredClickSizeChange)
            .onChange(of: measuredAutoContentSize, perform: handleMeasuredAutoSizeChange)
    }

    private func applyNotchNotificationHandlers<V: View>(to view: V) -> some View {
        view
            .onReceive(pickerHelper.pickerResultPublisher, perform: handlePickerResult)
            .onReceive(NotificationCenter.default.publisher(for: .sapphireOpenMusicQueue), perform: handleOpenMusicQueueNotification)
            .onReceive(NotificationCenter.default.publisher(for: .sapphireOpenMusicDevices), perform: handleOpenMusicDevicesNotification)
            .onReceive(NotificationCenter.default.publisher(for: .sapphireRevealHiddenNotch), perform: handleRevealHiddenNotchNotification)
            .onReceive(NotificationCenter.default.publisher(for: .sapphireOpenCircleToSearch), perform: handleOpenCircleToSearchNotification)
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
                handleScreenParametersChange()
            }
    }

    private func applyNotchSettingsHandlers<V: View>(to view: V) -> some View {
        view
            .onChange(of: showLyrics, perform: handleShowLyricsChange)
            .onChange(of: isInteractive, perform: handleInteractiveChange)
            .onChange(of: animatedWidth, perform: handleAnimatedSizeChange)
            .onChange(of: animatedHeight, perform: handleAnimatedSizeChange)
            .onChange(of: notchIconsIntrinsicWidth) { _, _ in
                applyNotchIconsWidthFloor()
            }
            .onChange(of: shouldHideWindowForSharing, perform: handleSharingVisibilityChange)
            .onChange(of: isInteractive, perform: handleMenuBarMonitoringChange)
            .onChange(of: settings.settings, perform: handleSettingsChange)
            .onChange(of: activeAppMonitor.isFullScreen) { _ in
                evaluateInactiveNotchVisibility()
            }
            .onChange(of: activeAppMonitor.fullScreenDisplayID) { _ in
                evaluateInactiveNotchVisibility()
            }
    }

    private func handleDragActivationZoneChange(_ isDragging: Bool) {
        if isDragging {
            let mouseLocation = NSEvent.mouseLocation
            let notchScreen = notchWindow?.screen
            let notchScreenFrame = notchScreen?.frame ?? .zero
            let myDisplayID = notchScreen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
            notchLog.info("handleDragActivationZoneChange: isDragging=true mouse=\(mouseLocation.x),\(mouseLocation.y) myDisplayID=\(myDisplayID.map(String.init) ?? "nil") notchScreenFrame=\(notchScreenFrame.minX),\(notchScreenFrame.minY)-\(notchScreenFrame.maxX),\(notchScreenFrame.maxY) cursorIsOnMyScreen=\(cursorIsOnMyScreen)")
            guard cursorIsOnMyScreen else { return }
        }
        Task {
            await handleDragActivationChange(isDragging: isDragging)
        }
    }

    private func handleActiveWindowDragChange(_ isDragging: Bool) {
        guard settings.settings.snapOnWindowDragEnabled else { return }
        if isDragging {
            let mouseLocation = NSEvent.mouseLocation
            let notchScreen = notchWindow?.screen
            let notchScreenFrame = notchScreen?.frame ?? .zero
            let myDisplayID = notchScreen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
            notchLog.info("handleActiveWindowDragChange: isDragging=true mouse=\(mouseLocation.x),\(mouseLocation.y) myDisplayID=\(myDisplayID.map(String.init) ?? "nil") notchScreenFrame=\(notchScreenFrame.minX),\(notchScreenFrame.minY)-\(notchScreenFrame.maxX),\(notchScreenFrame.maxY) cursorIsOnMyScreen=\(cursorIsOnMyScreen)")
            guard cursorIsOnMyScreen else { return }
        }
        handleWindowDragChange(isDragging: isDragging)
    }

    private func handleMeasuredClickSizeChange(_ newSize: CGSize) {
        handleSizeChange(newSize, for: .clickExpanded)
    }

    private func handleMeasuredAutoSizeChange(_ newSize: CGSize) {
        handleSizeChange(newSize, for: .autoExpanded)
    }

    private func handleOpenMusicQueueNotification(_ notification: Notification) {
        openMusicHub(mode: .musicQueueAndPlaylists)
    }

    private func handleOpenMusicDevicesNotification(_ notification: Notification) {
        openMusicHub(mode: .musicDevices)
    }

    private func handleRevealHiddenNotchNotification(_ notification: Notification) {
        guard isManuallyHidden else { return }
        haptic()
        inactiveHideUserOverride = true
        revealNotchFromCompleteHide()
    }

    private func handleOpenCircleToSearchNotification(_ notification: Notification) {
        openCircleToSearch(object: notification.object as? String)
    }

    private func handleInteractiveChange(_ isInteractive: Bool) {
        updateMouseEventHandling(isInteractive: isInteractive)
    }

    private func handleAnimatedSizeChange(_ _: CGFloat) {
        updateMouseEventHandling(isInteractive: isInteractive)
    }

    private func handleSharingVisibilityChange(_ shouldBeHidden: Bool) {
        updateWindowSharingBehavior(shouldBeHidden: shouldBeHidden)
    }

    private func handleMenuBarMonitoringChange(_ isNowInteractive: Bool) {
        if isNowInteractive {
            MenuBarInteractionManager.shared.stopMonitoring()
        } else {
            MenuBarInteractionManager.shared.startMonitoring()
        }
    }

    private func handleLiveActivityContentUpdate() {
        guard notchState == .autoExpanded || notchState == .hoverExpanded else { return }
        let shapeSignature = liveActivityManager.notchShapeSignature
        if shapeSignature != lastActivityShapeSignature {
            lastActivityShapeSignature = shapeSignature
            handleStateChange(from: notchState, to: notchState)
        } else {
            updateAutoContentSize()
        }
    }

    private func handleSettingsChange(_ newSettings: Settings) {
        let targetScreen = notchWindow?.screen ?? CursorPosition.targetNotchScreen()
        let newConfig = ResolvedNotchConfiguration(from: newSettings, screen: targetScreen)
        self.config = newConfig
        self.expansionAnimation = newConfig.expandAnimation
        handleStateChange(from: notchState, to: notchState)
        if !newSettings.swipeToHideNotch, completeHideReason == .manualSwipe {
            revealNotchFromCompleteHide()
        }
        let displayID = notchWindow?.screen?.displayIdentifier
        if !newSettings.resolvedHideNotchWhenInactive(forDisplayID: displayID) {
            inactiveHideUserOverride = false
            if completeHideReason == .inactive {
                revealNotchFromCompleteHide()
            }
        }
        evaluateInactiveNotchVisibility()
    }

    private func handleScreenParametersChange() {
        let targetScreen = notchWindow?.screen ?? CursorPosition.targetNotchScreen()
        let newConfig = ResolvedNotchConfiguration(from: settings.settings, screen: targetScreen)

        guard let currentConfig = config,
              currentConfig.initialSize != newConfig.initialSize ||
              currentConfig.initialCornerRadius != newConfig.initialCornerRadius else {
            return
        }

        self.config = newConfig
        self.expansionAnimation = newConfig.expandAnimation
        handleStateChange(from: notchState, to: notchState)
    }

    // MARK: - Subviews
    @ViewBuilder
    private var notchBackground: some View {
        let appearance = resolvedAppearanceSettings

        if #available(macOS 26.0, *), appearance.usesLiquidGlass {
            let intensity = appearance.liquidGlassIntensity
            let material = LiquidGlassMaterial.forIntensity(intensity)

            ZStack {
                LiquidGlassShapeFill(
                    material: material,
                    shape: activeShape,
                    cornerRadius: 0,
                    tint: nil,
                    intensity: intensity,
                    blendingMode: .behindWindow,
                    appearance: .dark,
                    interaction: .normal
                )

                activeShape
                    .fill(notchFillMaterial)
                    .opacity(appearance.opacity)
            }
            .contentShape(activeShape)
            .onTapGesture(perform: handleTap)
        } else {
            ZStack {
                if appearance.enableTransparencyBlur {
                    VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                }
                activeShape
                    .fill(notchFillMaterial)
                    .opacity(appearance.opacity)
            }
            .contentShape(activeShape)
            .clipShape(activeShape)
            .onTapGesture(perform: handleTap)
        }
    }

    private func shouldShowBottomEdgeFade(config: ResolvedNotchConfiguration) -> Bool {
        guard resolvedAppearanceSettings.mode != .default else { return false }
        guard resolvedAppearanceSettings.bottomFadeEnabled else { return false }
        guard notchState == .clickExpanded || notchState == .autoExpanded || notchState == .hoverExpanded else { return false }
        guard isLiveActivityActive else { return notchState == .clickExpanded }
        return liveActivityManager.isFullViewActivity || liveActivityManager.activityHasBottomContent
    }

    private func bottomEdgeFade(config: ResolvedNotchConfiguration) -> some View {
        let initialHeight = config.initialSize.height
        let fadeHeight = max(animatedHeight - initialHeight, 0)
        let fadeStart = animatedHeight > 0 ? min(max(initialHeight / animatedHeight, 0), 1) : 0
        let configuredStops = resolvedAppearanceSettings.gradientColors
            .sorted { $0.location < $1.location }
            .map { Gradient.Stop(color: $0.color, location: fadeStart + $0.location * (1 - fadeStart)) }
        let stops = (configuredStops.isEmpty
            ? [Gradient.Stop(color: .black.opacity(0.8), location: fadeStart)]
            : configuredStops)
            + [Gradient.Stop(color: .clear, location: 1)]

        return LinearGradient(
            gradient: Gradient(stops: stops),
            startPoint: .top,
            endPoint: .bottom
        )
        .opacity(fadeHeight > 0 ? 1 : 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .compositingGroup()
    }

    private var notchFillMaterial: AnyShapeStyle {
        let appearance = resolvedAppearanceSettings
        let style = appearance.backgroundStyle
        switch style {
        case .solid:
            return AnyShapeStyle(appearance.solidColor.color)
        case .gradient:
            let stops = appearance.gradientColors
                .map { Gradient.Stop(color: $0.color, location: $0.location) }
                .sorted { $0.location < $1.location }
            let angle = appearance.gradientAngle * .pi / 180
            let startPoint = UnitPoint(x: 0.5 - cos(angle) * 0.5, y: 0.5 - sin(angle) * 0.5)
            let endPoint = UnitPoint(x: 0.5 + cos(angle) * 0.5, y: 0.5 + sin(angle) * 0.5)
            return AnyShapeStyle(LinearGradient(
                gradient: Gradient(stops: stops.isEmpty ? [Gradient.Stop(color: .black, location: 0)] : stops),
                startPoint: startPoint,
                endPoint: endPoint
            ))
        case .radial:
            let stops = appearance.gradientColors
                .map { Gradient.Stop(color: $0.color, location: $0.location) }
                .sorted { $0.location < $1.location }
            return AnyShapeStyle(RadialGradient(
                gradient: Gradient(stops: stops.isEmpty ? [Gradient.Stop(color: .black, location: 0)] : stops),
                center: .center,
                startRadius: 0,
                endRadius: animatedWidth / 2
            ))
        }
    }

    @ViewBuilder
    private var contentView: some View {
        if let config = config, notchState == .clickExpanded {
            notchWidget
                .environmentObject(fileShelfState)
                .environmentObject(dragState)
                .environment(\.navigationStack, $navigationStack)
                .environment(\.activeDropZone, $activeDropZone)
                .environment(\.isFileDropTargeted, $isFileDropTargeted)
                .environment(\.isCalendarHovered, $isCalendarHovered)
                .environment(\.onSnapDragEnd, {
                    GlobalDragManager.shared.endDrag()
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(100))
                        if !isPinned {
                            notchState = isLiveActivityActive ? .autoExpanded : .initial
                        }
                    }
                })
                .padding(.top, config.contentTopPadding)
                .padding(.bottom, config.contentBottomPadding)
                .padding(.horizontal, config.contentHorizontalPadding)
                .padding(.top, config.initialSize.height)
                .background(GeometryReader { geo in
                    Color.clear
                        .onAppear { measuredClickContentSize = geo.size }
                        .onChange(of: geo.size) { _, newSize in measuredClickContentSize = newSize }
            .onDisappear {
                if notchState != .clickExpanded {
                    measuredClickContentSize = .zero
                }
            }
                })
                .frame(width: animatedWidth, height: animatedHeight, alignment: .top)
                .clipped()
                .id(notchState)
                .allowsHitTesting(true)
        } else {
            EmptyView()
        }
    }

    @ViewBuilder
    private var autoActivityView: some View {
        if let config = config {
            Group {
                switch liveActivityManager.activityContent {
            case .full(let view, _, _):
                view
                    .padding(.horizontal, config.activityContentHorizontalPadding)
                    .clipShape(activeShape)
            case .standard(let data, _):
                buildStandardActivityView(from: data)
                    .clipShape(activeShape)
            case .none:
                EmptyView()
            }
            }
            .fixedSize(horizontal: true, vertical: false)
            .background(GeometryReader { geo in
                Color.clear
                    .onAppear {
                        let newSize = geo.size
                        let epsilon: CGFloat = 0.5
                        if abs(newSize.width - self.measuredAutoContentSize.width) > epsilon ||
                            abs(newSize.height - self.measuredAutoContentSize.height) > epsilon {
                            self.measuredAutoContentSize = newSize
                        }
                    }
                    .onChange(of: geo.size) { _, newSize in
                        let epsilon: CGFloat = 0.5
                        if abs(newSize.width - self.measuredAutoContentSize.width) > epsilon ||
                            abs(newSize.height - self.measuredAutoContentSize.height) > epsilon {
                            self.measuredAutoContentSize = newSize
                        }
                    }
            })
        }
    }

    @ViewBuilder
    private func buildStandardActivityView(from data: StandardActivityData) -> some View {
        if let config = config {
            let bottomIsUpNext: Bool = {
                if case .music(let bottom) = data, case .upNext = bottom { return true }
                return false
            }()
            VStack(alignment: bottomIsUpNext ? .leading : .center, spacing: 0) {
                let left = buildLeftView(for: data)
                let right = buildRightView(for: data)

                HStack(spacing: 0) {
                    HStack {
                        Spacer()
                        left
                            .fixedSize()
                            .background(GeometryReader { geo in
                                Color.clear.preference(key: MaxContentWidthPreferenceKey.self, value: geo.size.width)
                            })
                    }
                    Spacer().frame(width: config.initialSize.width)
                    HStack {
                        right
                            .fixedSize()
                            .background(GeometryReader { geo in
                                Color.clear.preference(key: MaxContentWidthPreferenceKey.self, value: geo.size.width)
                            })
                        Spacer()
                    }
                }
                .hidden()
                .frame(height: 0)
                .onPreferenceChange(MaxContentWidthPreferenceKey.self) { newMaxWidth in
                    guard self.notchState != .hoverExpanded else { return }
                    withAnimation(config.activityToActivityAnimation) {
                        self.maxActivityContentWidth = newMaxWidth
                    }
                }

                GeometryReader { geometry in
                    let totalWidth = geometry.size.width
                    HStack(spacing: 0) {
                        HStack(alignment: .center) {
                            left
                            Spacer(minLength: 0)
                        }
                        .frame(width: (totalWidth - config.initialSize.width) / 2, alignment: .leading)

                        Spacer()
                            .frame(width: config.initialSize.width)

                        HStack(alignment: .center) {
                            Spacer(minLength: 0)
                            right
                        }
                        .frame(width: (totalWidth - config.initialSize.width) / 2, alignment: .trailing)
                    }
                    .frame(height: geometry.size.height, alignment: .center)
                }
                .frame(width: maxActivityContentWidth * 2 + config.initialSize.width)
                .frame(height: config.initialSize.height)
                .padding(.horizontal, liveActivityHorizontalPadding)

                if let bottomView = getBottomView(for: data) {
                    VStack {
                        bottomView
                            .padding(.bottom, config.activityContentBottomPadding)
                    }
                    .padding(.horizontal, liveActivityHorizontalPadding)
                }
            }
        }
    }

    @ViewBuilder
    private var expandedOverlayIcons: some View {
        ZStack(alignment: .topTrailing) {
            if currentMode == .defaultWidgets {
                defaultModeIcons
            } else if ![.fileShelfLanding, .snapZones, .dragActivated].contains(currentMode) {
                navigationHeader
            }

            hudOverlayView
        }
        .onChange(of: showRightHUDOverlay) { oldValue, newValue in
            if newValue {
                hudOverlayBlur = 10.0
                hudOverlayOpacity = 0.0
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
                    withAnimation(.easeOut(duration: 0.18)) {
                        hudOverlayBlur = 0.0
                        hudOverlayOpacity = 1.0
                    }
                }
            } else {
                withAnimation(.easeIn(duration: 0.12)) {
                    hudOverlayOpacity = 0.0
                    hudOverlayBlur = 5.0
                }
            }
        }
    }

    @ViewBuilder
    private var hudOverlayView: some View {
        if let config = config, showRightHUDOverlay, let hud = systemHUD.currentHUD {
            let trailingPadding = NotchConfiguration.defaultModeIconsHorizontalPadding
            let availableWidth = max(0, animatedWidth - trailingPadding)
            HStack {
                Spacer()
                HStack(spacing: 8) {
                    SystemHUDSlimActivityView.left(type: hud, settings: settings)
                    SystemHUDSlimActivityView.right(
                        type: hud,
                        settings: settings,
                        availableWidth: availableWidth
                    )
                }
                .padding(.trailing, trailingPadding)
            }
            .frame(height: config.initialSize.height)
            .opacity(hudOverlayOpacity)
            .blur(radius: hudOverlayBlur)
            .allowsHitTesting(hudOverlayOpacity > 0.5)
            .zIndex(3)
        }
    }

    @ViewBuilder
    private var navigationHeader: some View {
        if let config = config {
            ZStack {
                HStack {
                    Button(action: {
                        if NotchBackRouter.shared.handleBack() { return }
                        if navigationStack.count > 1 {
                            navigationStack.removeLast()
                        } else {
                            navigationStack = [.defaultWidgets]
                        }
                    }) {
                        NotchCapsuleBackButtonContent()
                            .padding(.leading, NotchConfiguration.navHeaderLeadingPadding + 10)
                    }
                    .padding(.top, NotchConfiguration.navHeaderTopPadding)
                    .buttonStyle(.plain)

                    if currentMode == .musicPlayer, musicWidget.activeMediaSources.count > 1 {
                        NotchMediaSourceSwitcher()
                            .environmentObject(musicWidget)
                            .padding(.top, NotchConfiguration.navHeaderTopPadding)
                            .padding(.leading, 6)
                    }

                    if let title = currentViewTitle {
                        Text(title)
                            .font(.system(size: NotchConfiguration.navHeaderTitleFontSize, weight: .bold))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundColor(.white.opacity(0.9))
                            .padding(.top, NotchConfiguration.navHeaderTitleTopPadding)
                    }
                    Spacer()
                }
            }
            .frame(height: config.initialSize.height)
            .frame(width: animatedWidth)
        }
    }

    @ViewBuilder
    private var defaultModeIcons: some View {
        if let config = config {
            HStack {
                HStack(spacing: 0) {
                    ForEach(leftNotchButtons) { buttonType in
                        notchButton(for: buttonType)
                    }
                }
                .fixedSize(horizontal: true, vertical: false)
                .background(GeometryReader { geo in
                    Color.clear
                        .onAppear { notchIconsLeftWidth = geo.size.width }
                        .onChange(of: geo.size.width) { _, newWidth in
                            notchIconsLeftWidth = newWidth
                        }
                })

                Spacer()

                HStack(spacing: 0) {
                    ForEach(rightNotchButtons) { buttonType in
                        notchButton(for: buttonType)
                    }
                }
                .opacity(showRightHUDOverlay ? 0.0 : 1.0)
                .animation(.easeInOut(duration: 0.12), value: showRightHUDOverlay)
                .fixedSize(horizontal: true, vertical: false)
                .background(GeometryReader { geo in
                    Color.clear
                        .onAppear { notchIconsRightWidth = geo.size.width }
                        .onChange(of: geo.size.width) { _, newWidth in
                            notchIconsRightWidth = newWidth
                        }
                })
            }
            .padding(.horizontal, NotchConfiguration.defaultModeIconsHorizontalPadding)
            .frame(height: config.initialSize.height)
            .frame(width: max(animatedWidth, notchIconsIntrinsicWidth))
        }
    }

    @ViewBuilder
    private var intelligenceButton: some View {
        let isLiveRunning = geminiLiveManager.isSessionRunning
        let baseSize: CGFloat = NotchConfiguration.geminiButtonBaseSize
        let activeGradient = LinearGradient(
            gradient: Gradient(colors: [Color.purple.opacity(0.8), Color.indigo.opacity(0.6)]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        let stopGradient = LinearGradient(
            gradient: Gradient(colors: [Color.orange.opacity(0.8), Color.red.opacity(1)]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        Button(action: {
            if isLiveRunning {
                geminiLiveManager.stopSession()
            } else {
                openBlipHub()
            }
        }) {
            HStack(spacing: 4) {
                Image(systemName: isLiveRunning ? "stop.fill" : "sparkle")
                    .font(.system(
                        size: isGeminiHovered
                            ? NotchConfiguration.geminiButtonActiveIconSize
                            : NotchConfiguration.geminiButtonInactiveIconSize,
                        weight: .medium
                    ))
                    .rotationEffect(.degrees(isGeminiHovered ? 90 : 0))
                    .foregroundStyle(
                        isGeminiHovered
                            ? LinearGradient(
                                gradient: Gradient(colors: [.white, .white.opacity(0.5)]),
                                startPoint: .topLeading, endPoint: .bottomTrailing
                              )
                            : LinearGradient(
                                gradient: Gradient(colors: [Color.purple, Color.indigo]),
                                startPoint: .topLeading, endPoint: .bottomTrailing
                              )
                    )
                    .animation(
                        .spring(
                            response: NotchConfiguration.geminiButtonSpringResponse,
                            dampingFraction: NotchConfiguration.geminiButtonSpringDamping
                        ),
                        value: isGeminiHovered
                    )

                if isGeminiHovered {
                    Text(isLiveRunning ? "Stop" : "Blip")
                        .font(.system(size: NotchConfiguration.geminiButtonTextFontSize, weight: .semibold))
                        .fixedSize()
                        .foregroundColor(.white)
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                }
            }
            .padding(.horizontal, isGeminiHovered ? NotchConfiguration.geminiButtonActiveHorizontalPadding : 0)
            .frame(width: isGeminiHovered ? nil : baseSize, height: baseSize)
            .background(isGeminiHovered ? (isLiveRunning ? stopGradient : activeGradient) : nil)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.spring(
                response: NotchConfiguration.geminiButtonSpringResponse,
                dampingFraction: 1
            )) {
                isGeminiHovered = hovering
            }
        }
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                openBlipHub()
                navigationStack.append(.agentS)
            }
        )
    }

    @ViewBuilder
    private var microphonePill: some View {
        let mic = MicrophoneUsageManager.shared
        if mic.isMicInUse {
            Button(action: {
                haptic()
                MicrophoneUsageManager.shared.toggleMute()
            }) {
                HStack(spacing: 8) {
                    Image(systemName: mic.isMuted ? "mic.slash.fill" : "mic.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(mic.isMuted ? .white.opacity(0.85) : .red)
                    Text(mic.isMuted ? "Muted" : "Mic")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(Color.black.opacity(0.25))
                )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Activity View Builders
    private func getBottomView(for data: StandardActivityData) -> AnyView? {
        switch data {
        case .music(let bottomContentType):
            switch bottomContentType {
            case .none:
                return nil
            case .peek(let title, let artist):
                return AnyView(QuickPeekView(title: title, artist: artist))
            case .lyrics(let text, let id):
                let view = Text(text)
                    .font(.system(size: NotchConfiguration.lyricsFontSize, weight: .semibold, design: .rounded))
                    .foregroundColor(musicWidget.accentColor.opacity(0.9))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: NotchConfiguration.lyricsMaxWidth)
                    .transition(.opacity.animation(.easeInOut(duration: 0.3)))
                    .id("lyric-\(id.uuidString)")
                    .onTapGesture { showLyrics = true }
                return AnyView(view)
            case .upNext(let title, let artist, let artworkURL):
                return AnyView(MusicUpNextView(title: title, artist: artist, artworkURL: artworkURL))
            }
        default:
            return nil
        }
    }

    @ViewBuilder
    private func buildLeftView(for data: StandardActivityData) -> some View {
        switch data {
        case .music: AlbumArtView()
        case .intelligenceAgent: IntelligenceAgentActivityView.left()
        case .weather(let data): WeatherActivityView.left(for: data)
        case .calendar: CalendarProximityActivityView.left()
        case .reminder: ReminderProximityActivityView.left()
        case .timer: TimerActivityView.left(timerManager: timerManager)
        case .battery(let state, let style, let timeRemaining, let systemState):
            switch style {
            case .persistent: PersistentBatteryActivityView.left(for: state, timeRemaining: timeRemaining, systemState: systemState)
            case .default: DefaultBatteryActivityView.left(for: state, systemState: systemState)
            case .compact: CompactBatteryActivityView.left(for: state, systemState: systemState)
            }
        case .desktop: DesktopActivityView.left(for: resolvedDesktopNumber)
        case .focus(let mode): FocusModeActivityView.left(for: mode)
        case .fileShelf: FileShelfActivityView.left()
        case .fileProgress(let task): FileProgressLiveActivityView.left(for: task)
        case .bluetooth(let device):
            switch device.eventType {
            case .connected:
                if device.isContinuityDevice { BluetoothConnectedContinuityView.left(for: device) }
                else { BluetoothConnectedPeripheralView.left(for: device) }
            case .disconnected: BluetoothDisconnectedView.left(for: device)
            case .batteryLow: BluetoothBatteryLowView.left(for: device)
            }
        case .audioSwitch(let event): AudioSwitchActivityView.left(for: event)
        case .geminiLive: GeminiActiveActivityView.left()
        case .sports(let payload, _): SportsLiveActivityView.left(for: payload, preferLogo: settings.settings.sportsPreferLogo)
        case .finance(let payload): FinanceLiveActivityView.left(for: payload)
        case .microphone:
            MicrophoneLiveActivityView.left { MicrophoneUsageManager.shared.toggleMute() }
        case .nearDrop: NearDropCompactActivityView.left()
        case .hud(let type): SystemHUDSlimActivityView.left(type: type, settings: settings)
        case .lockScreen: LockScreenLiveActivityView.left()
        case .updateAvailable: UpdateAvailableActivityView.left()
        case .focusSession: FocusSessionActivityView.left()
        case .unlocked: LockScreenLiveActivityView.left()
        case .stats(let payload): statsLiveActivityView.left(for: payload, selectedStats: settings.settings.selectedStats, selectedSensorKeys: settings.settings.selectedSensorKeys)
        }
    }

    @ViewBuilder
    private func buildRightView(for data: StandardActivityData) -> some View {
        switch data {
        case .music: WaveformView()
        case .intelligenceAgent(let status, let stepTitle, let current, let total): IntelligenceAgentActivityView.right(status: status, stepTitle: stepTitle, current: current, total: total)
        case .weather(let data): WeatherActivityView.right(for: data)
        case .calendar(let event): CalendarProximityActivityView.right(event: event)
        case .reminder(let reminder): ReminderProximityActivityView.right(reminder: reminder)
        case .timer: TimerActivityView.right(timerManager: timerManager)
        case .battery(let state, let style, let timeRemaining, let systemState):
            switch style {
            case .persistent: PersistentBatteryActivityView.right(for: state, systemState: systemState)
            case .default: DefaultBatteryActivityView.right(for: state, timeRemaining: timeRemaining, systemState: systemState)
            case .compact: CompactBatteryActivityView.right(for: state)
            }
        case .desktop: DesktopActivityView.right(for: resolvedDesktopNumber)
        case .focus(let mode): FocusModeActivityView.right(for: mode, displayMode: settings.settings.focusDisplayMode)
        case .fileShelf(let count): FileShelfActivityView.right(count: count)
        case .fileProgress(let task): FileProgressLiveActivityView.right(for: task)
        case .bluetooth(let device):
            switch device.eventType {
            case .connected:
                if device.isContinuityDevice { BluetoothConnectedContinuityView.right(for: device) }
                else { BluetoothConnectedPeripheralView.right(for: device) }
            case .disconnected: BluetoothDisconnectedView.right(for: device)
            case .batteryLow: BluetoothBatteryLowView.right(for: device)
            }
        case .audioSwitch(let event): AudioSwitchActivityView.right(for: event)
        case .geminiLive(let payload): GeminiActiveActivityView.right(isMuted: payload.isMicMuted) { geminiLiveManager.toggleMicrophone() }
        case .sports(let payload, _):
            SportsLiveActivityView.right(for: payload, preferLogo: settings.settings.sportsPreferLogo)
        case .finance(let payload):
            FinanceLiveActivityView.right(for: payload)
        case .microphone: MicrophoneLiveActivityView.right { MicrophoneUsageManager.shared.toggleMute() }
        case .nearDrop(let payload): NearDropCompactActivityView.right(payload: payload)
        case .hud(let type): SystemHUDSlimActivityView.right(type: type, settings: SettingsModel.shared)
        case .lockScreen: LockScreenLiveActivityView.right()
        case .updateAvailable(let version): UpdateAvailableActivityView.right(version: version)
        case .focusSession: FocusSessionActivityView.right()
        case .unlocked: LockScreenLiveActivityView.right()
        case .stats(let payload): statsLiveActivityView.right(for: payload, selectedStats: settings.settings.selectedStats, selectedSensorKeys: settings.settings.selectedSensorKeys)
        }
    }

    @ViewBuilder
    private func notchButton(for type: NotchButtonType) -> some View {
        switch type {
        case .settings:
            SubtleIconButton(systemName: "gearshape", action: {
                (NSApp.delegate as? AppDelegate)?.openSettingsWindow()
            })
        case .fileShelf:
            if settings.settings.fileShelfIconEnabled {
                SubtleIconButton(systemName: "tray.full", action: { navigationStack.append(.nearDrop) })
            }
        case .notes:
            if settings.settings.notesIconEnabled {
                SubtleIconButton(systemName: "note.text", action: { navigationStack.append(.notesPlayer) })
            }
        case .clipboard:
            if settings.settings.clipboardIconEnabled {
                SubtleIconButton(systemName: "list.clipboard", action: { navigationStack.append(.clipboardPlayer) })
            }
        case .intelligence:
            if settings.settings.intelligenceEnabled {
                HStack(spacing: 8) {
                    intelligenceButton
                    if microphoneManager.isMicInUse && notchState == .clickExpanded {
                        microphonePill
                    }
                }
            } else {
                EmptyView()
            }
        case .intelligenceLive:
            EmptyView()
        case .caffeine:
            if settings.settings.caffeinateEnabled {
                SubtleIconButton(systemName: caffeineManager.isActive ? "cup.and.heat.waves.fill" : "cup.and.heat.waves", action: { caffeineManager.toggle() }, horizontalPadding: 6)
                    .offset(y: -2)
            }
        case .battery:
            if settings.settings.batteryEstimatorEnabled {
                BatteryInfoView(
                    level: batteryEstimator.batteryLevel,
                    isCharging: batteryEstimator.isCharging,
                    timeRemaining: batteryEstimator.estimatedTimeRemaining
                )
                .padding(.horizontal, NotchConfiguration.batteryHorizontalPadding)
            }
        case .multiAudio:
            if settings.settings.showMultiAudioIcon {
                SubtleIconButton(systemName: "hifispeaker.and.homepod.mini.fill", action: { navigationStack.append(.multiAudio) })
            }
        case .pin:
            if settings.settings.pinEnabled {
                SubtleIconButton(systemName: isPinned ? "pin.fill" : "pin", action: {
                    isPinned.toggle()
                    if isPinned {
                        collapseTask?.cancel()
                        isCollapseTimerActive = false
                    }
                }, horizontalPadding: 6)
            }
        case .spacer:
            EmptyView()
        }
    }

    // MARK: - Setup and Teardown
    private func setupMonitors() {
        dragManager.startMonitoring()
        liveActivityManager.showLyricsBinding = $showLyrics
        updateFPS()

        if isInteractive {
            MenuBarInteractionManager.shared.stopMonitoring()
        } else {
            MenuBarInteractionManager.shared.startMonitoring()
        }

        TrackpadGestureHandler.shared.onSwipe = { dx, dy in
            self.handleTrackpadSwipe(vector: CGVector(dx: dx, dy: dy))
        }
        TrackpadGestureHandler.shared.onTwoFingerTap = {
            self.handleTrackpadTwoFingerTap()
        }

        if fileDropFlowObserver == nil {
            fileDropFlowObserver = NotificationCenter.default.addObserver(
                forName: .fileDropFlowCompleted,
                object: nil,
                queue: .main
            ) { _ in
                self.awaitingDropCompletion = false
                if self.notchState == .clickExpanded && !self.isPinned {
                    self.startWidgetSwitchProtection()
                }
            }
        }

        startNotchInteractionMonitoring()
        updateMouseEventHandling(isInteractive: isInteractive)
        updateWindowSharingBehavior(shouldBeHidden: shouldHideWindowForSharing)
        lastActivityShapeSignature = liveActivityManager.notchShapeSignature
        evaluateInactiveNotchVisibility()
    }

    private func teardownMonitors() {
        dragManager.stopMonitoring()
        TrackpadGestureHandler.shared.stopMonitoring()
        TrackpadGestureHandler.shared.onSwipe = nil
        TrackpadGestureHandler.shared.onTwoFingerTap = nil
        HiddenNotchRevealMonitor.shared.stop()
        if let fileDropFlowObserver {
            NotificationCenter.default.removeObserver(fileDropFlowObserver)
            self.fileDropFlowObserver = nil
        }
        collapseTask?.cancel()
        cancelWidgetSwitchProtection()
        cancellables.removeAll()
        stopNotchInteractionMonitoring()
        MenuBarInteractionManager.shared.startMonitoring()
    }

    // MARK: - Event Handlers
    private func handleTap() {
        guard !isManuallyHidden else { return }
        guard !shouldBlockNotchExpansionWhileLocked else { return }
        guard let config = config else { return }
        if notchState == .clickExpanded { return }

        let flags = NSEvent.modifierFlags
        if flags.contains(.command) {
            collapseTask?.cancel()
            isCollapseTimerActive = false
            measuredClickContentSize = .zero
            navigationStack = [.defaultWidgets]
            notchState = .clickExpanded
            return
        }

        collapseTask?.cancel()
        isCollapseTimerActive = false
        if isPinned { return }

        let activityType = liveActivityManager.currentActivity
        if (notchState == .autoExpanded || notchState == .hoverExpanded) {
            let initiateWidgetView: (NotchWidgetMode) -> Void = { mode in
                self.measuredClickContentSize = .zero
                self.navigationStack = [mode]
                self.notchState = .clickExpanded
            }
            if activityType == .music, settings.settings.musicOpenOnClick { initiateWidgetView(.musicPlayer); return }
            if activityType == .weather, settings.settings.weatherOpenOnClick { initiateWidgetView(.weatherPlayer); return }
            if activityType == .sports, settings.settings.sportsOpenOnClick, SubscriptionManager.shared.hasAccess(to: .sportsWidget) { initiateWidgetView(.sportsPlayer); return }
            if activityType == .finance, settings.settings.financeOpenOnClick { initiateWidgetView(.financePlayer); return }
            if activityType == .calendar, settings.settings.calendarOpenOnClick { initiateWidgetView(.calendarPlayer); return }
            if activityType == .fileShelf, settings.settings.clickToOpenFileShelf { initiateWidgetView(.fileShelf); return }
            if activityType == .timer, settings.settings.clickToShowTimerView { initiateWidgetView(.timerDetailView); return }
            if activityType == .intelligenceAgent { initiateWidgetView(.agentS); return }
            if activityType == .updateAvailable { initiateWidgetView(.updateAvailable); return }
        }

        switch notchState {
        case .initial, .autoExpanded, .hoverExpanded:
            self.expansionAnimation = config.expandAnimation
            measuredClickContentSize = .zero
            var targetStack: [NotchWidgetMode]
            if settings.settings.clickToOpenFileShelf && !FileShelfManager.shared.files.isEmpty {
                targetStack = [.fileShelf]
            } else if settings.settings.rememberLastMenu, let savedStack = settings.settings.lastNotchNavigationStack, !savedStack.isEmpty {
                targetStack = savedStack.map { $0.toNotchWidgetMode() }
            } else {
                targetStack = [.defaultWidgets]
            }
            navigationStack = targetStack
            notchState = .clickExpanded
        case .clickExpanded:
            return
        }
    }

    private func handleHover(hovering: Bool) {
        guard !isManuallyHidden else { return }
        guard let config = config else { return }
        self.isHovered = hovering

        if hovering {
            TrackpadGestureHandler.shared.startMonitoring()
        } else {
            TrackpadGestureHandler.shared.stopMonitoring()
            suppressHoverAfterReveal = false
            cancelHoverExpandTask()
        }

        if hovering {
            guard !suppressHoverAfterReveal else { return }
            guard !shouldBlockNotchExpansionWhileLocked else { return }
            collapseTask?.cancel()
            isCollapseTimerActive = false
            let activityType = liveActivityManager.currentActivity

            if activityType == .fileShelf, settings.settings.hoverToOpenFileShelf {
                cancelHoverExpandTask()
                if notchState != .clickExpanded {
                    navigationStack = [.fileShelf]
                    notchState = .clickExpanded
                }
        } else if settings.settings.expandOnHover && !isFullViewActivity && !isInteractiveLiveActivity {
                if notchState != .clickExpanded {
                    NSApp.activate(ignoringOtherApps: true)
                    notchWindow?.makeKeyAndOrderFront(nil)
                    self.expansionAnimation = config.expandAnimation
                    var targetStack: [NotchWidgetMode]
                    if settings.settings.hoverToOpenFileShelf && !FileShelfManager.shared.files.isEmpty {
                        targetStack = [.fileShelf]
                    } else if settings.settings.rememberLastMenu, let savedStack = settings.settings.lastNotchNavigationStack, !savedStack.isEmpty {
                        targetStack = savedStack.map { $0.toNotchWidgetMode() }
                    } else {
                        targetStack = [.defaultWidgets]
                    }
                    navigationStack = targetStack
                    let delay = settings.settings.expandOnHoverDelay
                    if delay > 0 {
                        cancelHoverExpandTask()
                        hoverExpandTask = Task { @MainActor in
                            do {
                                try await Task.sleep(for: .milliseconds(Int(delay * 1000)))
                            } catch { return }
                            guard !Task.isCancelled, self.isHovered else { return }
                            guard !self.dragManager.isDraggingInActivationZone else { return }
                            guard self.notchState != .clickExpanded else { return }
                            guard settings.settings.expandOnHover else { return }
                            guard !self.isInteractiveLiveActivity else { return }
                            self.notchState = .clickExpanded
                        }
                    } else {
                        cancelHoverExpandTask()
                        guard !isInteractiveLiveActivity else { return }
                        notchState = .clickExpanded
                    }
                }
            } else {
                cancelHoverExpandTask()
                if notchState == .initial || notchState == .autoExpanded {
                    guard !isInteractiveLiveActivity else { return }
                    notchState = .hoverExpanded
                    haptic()
                }
            }
        } else {
            if notchState == .clickExpanded {
                handleClickExpandedHoverOut(config: config)
            } else {
                scheduleCollapse(after: 0)
            }
        }
    }

    private func handleActivityChange(_ newActivity: ActivityType) {
        let newActivity = shouldHideActivityForFullScreen || shouldHideActivityForInactiveDisplay ? .none : newActivity
        if newActivity != .none {
            inactiveHideUserOverride = false
            if completeHideReason == .inactive {
                revealNotchFromCompleteHide()
            } else if completeHideReason == .manualSwipe {
                return
            }
        } else if completeHideReason == .manualSwipe {
            return
        } else if completeHideReason == .inactive {
            updateFPS()
            return
        }

        guard notchState != .clickExpanded, let config = config else {
            evaluateInactiveNotchVisibility()
            return
        }

        if newActivity != .none {
            activityBlurRadius = config.activityBlurRadiusMax
            activityContentScale = 0.9
            DispatchQueue.main.async {
                withAnimation(config.focusPullAnimation) {
                    self.activityBlurRadius = 0
                    self.activityContentScale = 1.0
                }
            }
        }

        let previousState = notchState
        notchState = newActivity != .none ? .autoExpanded : .initial
        if previousState == notchState {
            handleStateChange(from: notchState, to: notchState)
            lastActivityShapeSignature = liveActivityManager.notchShapeSignature
        }
        updateFPS()
        evaluateInactiveNotchVisibility()
    }

    private func handleStateChange(from oldState: NotchState, to newState: NotchState) {
        guard let config = config else { return }
        if isManuallyHidden {
            animatedWidth = 0
            animatedHeight = 0
            notchWindow?.alphaValue = 0
            return
        }

        let isContentUpdate = oldState == newState
        let animation: Animation
        if isContentUpdate {
            animation = config.bottomContentAnimation
        } else {
            switch newState {
            case .initial:
                animation = (oldState == .clickExpanded) ? config.collapseAnimation : config.activityToActivityAnimation
            case .hoverExpanded: animation = config.hoverAnimation
            case .clickExpanded: animation = self.expansionAnimation
            case .autoExpanded: animation = (oldState == .clickExpanded) ? config.collapseAnimation : config.activityToActivityAnimation
            }
        }

        withAnimation(animation) {
            updateRadiiForCurrentState(state: newState)
            self.liveActivityHorizontalPadding = liveActivityManager.activityHasBottomContent ?
            config.activityWithContentHorizontalPadding :
            config.activityDefaultHorizontalPadding
            if isContentUpdate {
                refreshAnimatedSizeForCurrentState()
            }
        }

        if isContentUpdate { return }

        if newState != .clickExpanded {
            CircleToSearchManager.shared.endResultsPresentation()
        }

        if oldState == .clickExpanded && newState != .clickExpanded {
            if navigationStack.contains(.mirrorPlayer) {
                navigationStack.removeAll { $0 == .mirrorPlayer }
                if navigationStack.isEmpty {
                    navigationStack = [.defaultWidgets]
                }
            }
            if MirrorCameraManager.shared.isLive {
                MirrorCameraManager.shared.teardown()
            }
        }

        switch newState {
        case .initial:
            let wasShowingActivity = (oldState == .autoExpanded || oldState == .hoverExpanded)
            if wasShowingActivity { isAnimatingActivityOut = true }
            self.canRenderAutoContent = false
            collapseTask?.cancel(); isCollapseTimerActive = false
            cancelHoverExpandTask()
            cancelWidgetSwitchProtection()

            let idleMorphAnimation = (oldState == .clickExpanded)
                ? config.collapseAnimation
                : config.activityToActivityAnimation

            withAnimation(idleMorphAnimation) {
                shadowOpacity = 0
                if wasShowingActivity { activityBlurRadius = 20; activityContentScale = 0.9; autoContentOpacity = 0 }
                animatedWidth = config.initialSize.width; animatedHeight = config.initialSize.height
                animatedContentScale = 1.0
                isPinned = false
            }
            syncNotchHostWindowHeight(contentHeight: config.initialSize.height)

            DispatchQueue.main.asyncAfter(deadline: .now() + config.activityAnimationOutDelay) {
                guard self.notchState == .initial else { return }
                if wasShowingActivity { self.isAnimatingActivityOut = false }
                self.activityBlurRadius = 0; self.activityContentScale = 1.0
            }

        case .hoverExpanded:
            isAnimatingActivityOut = false; self.canRenderAutoContent = true

            let scale = activeScaleFactor
            let rawWidth = isLiveActivityActive ? measuredAutoContentSize.width * scale : config.hoverExpandedSize.width
            let rawHeight = isLiveActivityActive ? measuredAutoContentSize.height * scale : config.hoverExpandedSize.height
            let targetWidth = max(rawWidth, config.initialSize.width)
            let targetHeight = max(rawHeight, config.initialSize.height)

            withAnimation(config.hoverAnimation) {
                animatedWidth = targetWidth; animatedHeight = targetHeight
                if isLiveActivityActive { autoContentOpacity = 1 }
                animatedContentScale = scale
                shadowOpacity = 1
            }

        case .clickExpanded:
            isAnimatingActivityOut = false; self.canRenderAutoContent = false

            shadowOpacity = 0

            if isLiveActivityActive && (oldState == .autoExpanded || oldState == .hoverExpanded) {
                withAnimation(config.activityBlurAnimation) { activityBlurRadius = config.activityBlurRadiusMax; autoContentOpacity = 0; activityContentScale = 1.05 }
            }

            withAnimation(self.expansionAnimation) {
                autoContentOpacity = 0
            }
             DispatchQueue.main.asyncAfter(deadline: .now() + config.contentUpdateDelay) {
                withAnimation(config.focusPullAnimation) {
                    self.activityContentScale = 1.0
                }
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.expansionAnimation = config.expandAnimation
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                if self.notchState == .clickExpanded {
                    withAnimation(.easeIn(duration: 0.2)) { self.shadowOpacity = 1 }
                }
            }

        case .autoExpanded:
            isAnimatingActivityOut = false
            let isCollapsingFromClick = (oldState == .clickExpanded)
            if isCollapsingFromClick {
                cancelWidgetSwitchProtection()
                self.canRenderAutoContent = false
                withAnimation(config.blurAnimation) { activityContentScale = 0.92; activityBlurRadius = config.activityBlurRadiusMax * 1.5 }
            } else {
                self.canRenderAutoContent = true; self.autoContentOpacity = 1
            }
            let animationToUse = isCollapsingFromClick ? config.collapseAnimation : config.activityToActivityAnimation

            shadowOpacity = 0

            withAnimation(animationToUse) {
                animatedWidth = max(measuredAutoContentSize.width, config.initialSize.width)
                animatedHeight = max(measuredAutoContentSize.height, config.initialSize.height)
                animatedContentScale = 1.0
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + config.activitySizeChangeDelay) {
                withAnimation(config.blurRemovalAnimation) {
                    self.activityBlurRadius = 0; self.activityContentScale = 1.0
                }
            }
            if isCollapsingFromClick {
                DispatchQueue.main.asyncAfter(deadline: .now() + config.autoContentRenderDelay) {
                    if self.notchState == .autoExpanded {
                        self.canRenderAutoContent = true
                        withAnimation(config.activityOpacityAnimation) { self.autoContentOpacity = 1 }
                    }
                }
            }
        }
        updateFPS()
        updateMouseEventHandling(isInteractive: isInteractive)
    }

    private func refreshAnimatedSizeForCurrentState() {
        guard let config = config else { return }
        switch notchState {
        case .initial:
            animatedWidth = config.initialSize.width
            animatedHeight = config.initialSize.height
        case .autoExpanded:
            animatedWidth = max(measuredAutoContentSize.width, config.initialSize.width)
            animatedHeight = max(measuredAutoContentSize.height, config.initialSize.height)
        case .hoverExpanded:
            let scale = activeScaleFactor
            let rawWidth = isLiveActivityActive ? measuredAutoContentSize.width * scale : config.hoverExpandedSize.width
            let rawHeight = isLiveActivityActive ? measuredAutoContentSize.height * scale : config.hoverExpandedSize.height
            animatedWidth = max(rawWidth, config.initialSize.width)
            animatedHeight = max(rawHeight, config.initialSize.height)
        case .clickExpanded:
            break
        }
    }

    private func handlePreviewItemChange(newItem: ShelfItem?) {
        if newItem != nil {
            navigationStack.append(.fileActionPreview)
        } else {
            if navigationStack.last == .fileActionPreview {
                navigationStack.removeLast()
            }
        }
    }

    private func handleNavigationStackChange(oldStack: [NotchWidgetMode], newStack: [NotchWidgetMode]) {
        guard let config = config else { return }
        if oldStack.contains(.circleToSearch) && !newStack.contains(.circleToSearch) {
            CircleToSearchManager.shared.endResultsPresentation()
        }
        if oldStack.contains(.snapZones) && !newStack.contains(.snapZones) {
            SnapPreviewManager.shared.hidePreview()
        }
        if oldStack.contains(.mirrorPlayer) && !newStack.contains(.mirrorPlayer) {
            MirrorCameraManager.shared.teardown()
        }

        if notchState == .clickExpanded && oldStack != newStack {
            self.expansionAnimation = config.widgetSwitchAnimation
            startWidgetSwitchProtection()
        }

        if notchState == .clickExpanded {
            if settings.settings.rememberLastMenu {
                let restorableStack = newStack.compactMap { toRestorableMenu(mode: $0) }
                if !restorableStack.isEmpty {
                    settings.settings.lastNotchNavigationStack = restorableStack
                }
            }
        }
    }

    private func handleItemDrop(providers: [NSItemProvider]) -> Bool {
        let capturedDropZone = activeDropZone
        dragState.didJustDrop = true
        NotificationCenter.default.post(name: .fileDropFlowCompleted, object: nil)

        Task {
            var successfullyConvertedURLs: [URL] = []

            for provider in providers {
                do {
                    let url = try await provider.convertToAccessibleURL()
                    successfullyConvertedURLs.append(url)
                } catch {
                    print("[NotchController] Failed to process one of the dropped items: \(error.localizedDescription)")
                }
            }

            guard !successfullyConvertedURLs.isEmpty else {
                return
            }

            await MainActor.run {
                if let dropZone = capturedDropZone {
                    switch dropZone {
                    case .shelf:
                        FileShelfManager.shared.addFiles(from: successfullyConvertedURLs)
                        self.navigationStack = [.fileShelf]
                    case .airdrop:
                        SharingManager.shared.share(items: successfullyConvertedURLs, via: .sendViaAirDrop)
                        self.navigationStack = []
                    }
                } else {
                    FileShelfManager.shared.addFiles(from: successfullyConvertedURLs)
                    self.navigationStack = [.fileShelf]
                }
            }
        }
        return true
    }

    private func handleDragActivationChange(isDragging: Bool) async {
        guard let config = config else { return }
        collapseTask?.cancel()
        isCollapseTimerActive = false

        if isDragging {
            if isPinned {
                isPinned = false
            }

            dragState.didJustDrop = false

            awaitingDropCompletion = false

            if isFileDropTargeted {
                (NSApp.delegate as? AppDelegate)?.makeNotchWindowFocusable()
                let frontmostApp = NSWorkspace.shared.runningApplications.first { $0.isActive }
                self.draggedAppBundleID = frontmostApp?.bundleIdentifier
                notchState = .clickExpanded
                navigationStack = [.fileShelfLanding]

            } else {
                if settings.settings.snapDragEnabled {
                    self.navigationStack = [.snapZones]
                    notchState = .clickExpanded
                }
            }

        } else {
            try? await Task.sleep(for: .milliseconds(50))
            (NSApp.delegate as? AppDelegate)?.revertNotchWindowFocus()

            if dragState.didJustDrop {
                return
            }

            if awaitingDropCompletion {
                return
            }

            draggedAppBundleID = nil

            self.notchState = isLiveActivityActive ? .autoExpanded : .initial
        }
    }

    private func handleWindowDragChange(isDragging: Bool) {
        collapseTask?.cancel()
        isCollapseTimerActive = false

        if isDragging {
            if isPinned {
                isPinned = false
            }

            self.navigationStack = [.snapZones]
            if notchState != .clickExpanded {
                notchState = .clickExpanded
            }

        } else {
            (NSApp.delegate as? AppDelegate)?.revertNotchWindowFocus()

            draggedAppBundleID = nil
            if !self.isHovered && !self.dragManager.isDraggingInActivationZone {
                self.notchState = isLiveActivityActive ? .autoExpanded : .initial
            }
        }
    }

    private func handleFileDropTargetChange(isTargeted: Bool) {
        if isTargeted {
            guard cursorIsOnMyScreen else { return }
            SnapPreviewManager.shared.hidePreview()
            if navigationStack.last != .fileShelfLanding {
                (NSApp.delegate as? AppDelegate)?.makeNotchWindowFocusable()
                let frontmostApp = NSWorkspace.shared.runningApplications.first { $0.isActive }
                self.draggedAppBundleID = frontmostApp?.bundleIdentifier
                navigationStack = [.fileShelfLanding]
                notchState = .clickExpanded
            }
        }
    }

    private func handleSizeChange(_ newSize: CGSize, for state: NotchState) {
        guard let config = config else { return }
        if state == .clickExpanded && notchState == .clickExpanded {
            guard newSize.width > 1 && newSize.height > 1 else { return }
            let minimumWidth = currentMode == .defaultWidgets ? notchIconsIntrinsicWidth : 0
            let targetWidth = max(newSize.width, minimumWidth)
            guard abs(targetWidth - animatedWidth) > 1 || abs(newSize.height - animatedHeight) > 1 else { return }
            withAnimation(self.expansionAnimation) {
                animatedWidth = targetWidth
                animatedHeight = newSize.height
            }
            syncNotchHostWindowHeight(contentHeight: newSize.height)

        } else if state == .autoExpanded {
            updateAutoContentSize()
        }
    }

    private func applyNotchIconsWidthFloor() {
        guard notchState == .clickExpanded, currentMode == .defaultWidgets else { return }
        let targetWidth = max(animatedWidth, notchIconsIntrinsicWidth)
        guard abs(targetWidth - animatedWidth) > 1 else { return }
        withAnimation(self.expansionAnimation) {
            animatedWidth = targetWidth
        }
    }

    private func handlePickerResult(result: PickerResult) {
        switch result {
        case .success(let filter):
            geminiLiveManager.startSession(with: filter)
            liveActivityManager.startGeminiLive()
        case .failure(let error):
            if let error = error { print("Picker failed with error: \(error)") }
            else { print("Picker was cancelled by the user.") }
        }
    }

    private func handleShowLyricsChange(newValue: Bool) {
        if newValue {
            navigationStack.append(.musicLyrics)
            DispatchQueue.main.async { self.showLyrics = false }
        }
    }

    private func handleTrackpadSwipe(vector: CGVector) {
        guard !isCalendarHovered else {
            return
        }
        guard let config = config else { return }

        if isManuallyHidden {
            return
        }

        guard Date() >= revealSettlingUntil else { return }

        let isCollapsed = notchState == .initial || notchState == .hoverExpanded
        let isSwipeUp = vector.dy < 0
        let isSwipeDown = vector.dy > 0

        if settings.settings.swipeToHideNotch, isCollapsed {
            let verticalThreshold: CGFloat = 10.0
            let isVertical = abs(vector.dy) > abs(vector.dx) && abs(vector.dy) > verticalThreshold
            if isVertical, isSwipeUp {
                haptic()
                hideNotchCompletely(reason: .manualSwipe)
                return
            }
        }

        if isCollapsed {
            let verticalThreshold: CGFloat = 10.0
            if abs(vector.dy) > abs(vector.dx) && abs(vector.dy) > verticalThreshold {
                if settings.settings.swipeToHideNotch, isSwipeUp {
                    return
                }
                guard !shouldBlockNotchExpansionWhileLocked else { return }
                haptic()
                self.expansionAnimation = config.swipeOpenAnimation
                measuredClickContentSize = .zero
                navigationStack = [.defaultWidgets]
                notchState = .clickExpanded
                return
            }
        }
        else if notchState == .clickExpanded {
            guard currentMode != .nearDrop else {
                return
            }

            let allowsMenuSwitch = settings.settings.swipeToSwitchWidgets
                && navigationStack.count <= 1
                && (currentMode == .defaultWidgets || currentMode == .fileShelf)

            if allowsMenuSwitch, abs(vector.dx) > abs(vector.dy) && abs(vector.dx) > 10 {
                haptic()
                let isSwipeRight = vector.dx > 0
                let invertGestures = settings.settings.invertMusicGestures

                let isLogicalBackward = (isSwipeRight && !invertGestures) || (!isSwipeRight && invertGestures)

                if isLogicalBackward {
                    if navigationStack.count > 1 {
                        navigationStack.removeLast()
                    } else if currentMode == .fileShelf {
                        navigationStack = [.defaultWidgets]
                    }
                } else {
                    if currentMode == .defaultWidgets {
                        navigationStack.append(.fileShelf)
                    } else if currentMode == .fileShelf {
                        navigationStack = [.defaultWidgets]
                    }
                }
                return
            }
        }

        guard isLiveActivityActive && (notchState == .autoExpanded || notchState == .hoverExpanded) else { return }

        if abs(vector.dx) > abs(vector.dy) {
            if liveActivityManager.currentActivity == .music {
                let isSwipeRight = vector.dx > 0
                let invert = settings.settings.invertMusicGestures
                let shouldSkipForward = (isSwipeRight && !invert) || (!isSwipeRight && invert)
                let shouldGoBackward = (!isSwipeRight && !invert) || (isSwipeRight && invert)

                if shouldSkipForward && settings.settings.swipeToSkipMusic {
                    haptic()
                    musicWidget.transientIcon = .skippedForward
                    Task { await musicWidget.nextTrack() }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        if musicWidget.transientIcon == .skippedForward { musicWidget.transientIcon = nil }
                    }
                } else if shouldGoBackward && settings.settings.swipeToRewindMusic {
                    haptic()
                    musicWidget.transientIcon = .skippedBackward
                    Task { await musicWidget.previousTrack() }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        if musicWidget.transientIcon == .skippedBackward { musicWidget.transientIcon = nil }
                    }
                }
            } else if settings.settings.swipeToDismissLiveActivity {
                haptic()
                liveActivityManager.dismissCurrentActivity()
            }
        }
    }

    private func hideNotchCompletely(reason: NotchCompleteHideReason) {
        switch reason {
        case .manualSwipe:
            guard settings.settings.swipeToHideNotch else { return }
        case .inactive:
            guard settings.settings.hideNotchWhenInactive else { return }
            guard !inactiveHideUserOverride else { return }
        }
        guard completeHideReason == nil else {
            completeHideReason = reason
            return
        }

        completeHideReason = reason
        if reason == .manualSwipe {
            inactiveHideUserOverride = false
        }
        isPinned = false
        isHovered = false
        collapseTask?.cancel()
        isCollapseTimerActive = false
        cancelHoverExpandTask()
        cancelWidgetSwitchProtection()
        navigationStack = [.defaultWidgets]
        notchState = .initial
        TrackpadGestureHandler.shared.stopMonitoring()

        withAnimation(.spring(response: 0.22, dampingFraction: 0.9)) {
            animatedWidth = 0
            animatedHeight = 0
            shadowOpacity = 0
        }
        if let dynamicWindow = notchWindow as? DynamicFocusWindow {
            dynamicWindow.forceMouseEventPassthrough = true
            dynamicWindow.updateInteractiveContentFrame(.zero)
        }
        notchWindow?.alphaValue = 0
        notchWindow?.ignoresMouseEvents = true
        syncNotchHostWindowHeight(contentHeight: 0)
        startHiddenNotchSwipeMonitor()
    }

    private func revealNotchFromCompleteHide() {
        guard completeHideReason != nil else { return }
        let wasManualSwipeReveal = completeHideReason == .manualSwipe
        completeHideReason = nil
        stopHiddenNotchSwipeMonitor()
        if let dynamicWindow = notchWindow as? DynamicFocusWindow {
            dynamicWindow.forceMouseEventPassthrough = false
        }
        notchWindow?.alphaValue = 1
        if wasManualSwipeReveal {
            revealSettlingUntil = Date().addingTimeInterval(Self.revealSettlingInterval)
            suppressHoverAfterReveal = true
        }
        guard let config else { return }

        let hasActivity = liveActivityManager.currentActivity != .none
        if hasActivity, notchState != .clickExpanded {
            notchState = .autoExpanded
        } else {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                animatedWidth = config.initialSize.width
                animatedHeight = config.initialSize.height
            }
            syncNotchHostWindowHeight(contentHeight: config.initialSize.height)
        }
        updateMouseEventHandling(isInteractive: isInteractive)
    }

    private var shouldHideWhenInactive: Bool {
        let displayID = notchWindow?.screen?.displayIdentifier
        return settings.settings.resolvedHideNotchWhenInactive(forDisplayID: displayID)
    }

    private func evaluateInactiveNotchVisibility() {
        if liveActivityManager.currentActivity == .lockScreen { return }
        notchLog.info("evaluateInactiveNotchVisibility: shouldHideWhenInactive=\(shouldHideWhenInactive) completeHideReason=\(completeHideReason.map { "\($0)" } ?? "nil")")
        guard shouldHideWhenInactive else { return }
        if completeHideReason == .manualSwipe { return }

        let hasActivity = liveActivityManager.currentActivity != .none
        let isBusy = notchState == .clickExpanded
            || isPinned
            || isHovered
            || dragManager.isDraggingInActivationZone
            || activeAppMonitor.isWindowDragging

        if hasActivity {
            inactiveHideUserOverride = false
            if completeHideReason == .inactive {
                revealNotchFromCompleteHide()
            }
            return
        }

        guard !isBusy else { return }
        guard !inactiveHideUserOverride else { return }

        if completeHideReason == nil, notchState == .initial || notchState == .hoverExpanded {
            hideNotchCompletely(reason: .inactive)
        }
    }

    private func startHiddenNotchSwipeMonitor() {
        HiddenNotchRevealMonitor.shared.start(screen: nil)
    }

    private func stopHiddenNotchSwipeMonitor() {
        HiddenNotchRevealMonitor.shared.stop()
    }

    private func openMusicHub(mode: NotchWidgetMode) {
        measuredClickContentSize = .zero
        navigationStack = [mode]
        notchState = .clickExpanded
    }

    private func openBlipHub() {
        measuredClickContentSize = .zero
        navigationStack = [.blipHub]
        notchState = .clickExpanded
        (NSApp.delegate as? AppDelegate)?.makeNotchWindowFocusable()
    }

    private func openCircleToSearch(object: String?) {
        measuredClickContentSize = .zero
        switch object {
        case "askBlip":
            navigationStack = [.agentS]
        case "askBlipMissingKey":
            navigationStack = [.geminiApiKeysMissing]
        default:
            navigationStack = [.circleToSearch]
        }
        notchState = .clickExpanded
        (NSApp.delegate as? AppDelegate)?.makeNotchWindowFocusable()
    }

    private func handleTrackpadTwoFingerTap() {
        guard (notchState == .autoExpanded || notchState == .hoverExpanded) else { return }

        if liveActivityManager.currentActivity == .microphone && settings.settings.microphoneLiveActivityEnabled && settings.settings.microphoneLiveActivityBehavior == .iconAndGesture {
            haptic()
            MicrophoneUsageManager.shared.toggleMute()
            return
        }

        if settings.settings.twoFingerTapToPauseMusic {
            haptic()
            musicWidget.transientIcon = musicWidget.isPlaying ? .paused : .played
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                if musicWidget.transientIcon == .paused || musicWidget.transientIcon == .played {
                    musicWidget.transientIcon = nil
                }
            }
            Task {
                if musicWidget.isPlaying {
                    await musicWidget.pause()
                } else {
                    await musicWidget.play()
                }
            }
        }
    }

    // MARK: - Helper Methods
    private func startNotchInteractionMonitoring() {
        guard notchInteractionPollingTimer == nil else { return }

        let interval = 1.0 / 30.0
        let timer = Timer(timeInterval: interval, repeats: true) { _ in
            self.refreshNotchInteractionState()
        }
        timer.tolerance = 0.01
        notchInteractionPollingTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopNotchInteractionMonitoring() {
        notchInteractionPollingTimer?.invalidate()
        notchInteractionPollingTimer = nil
        lastSampledMouseLocation = nil
        lastPublishedInteractiveFrame = .null
        lastInteractionRefreshTime = 0
    }

    private func refreshNotchInteractionState() {
        guard let config = config, let window = notchWindow else { return }

        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastInteractionRefreshTime >= 0.02 else { return }
        lastInteractionRefreshTime = now
        if isManuallyHidden {
            window.ignoresMouseEvents = true
            if let dynamicWindow = window as? DynamicFocusWindow {
                dynamicWindow.forceMouseEventPassthrough = true
            }
            if isHovered { isHovered = false }
            return
        }

        let mouseLocation = window.mouseLocationOutsideOfEventStream
        let interactiveBounds = interactiveFrame(for: window, config: config)
        let isNear = isMouseNearNotchFrame(interactiveBounds, mouseLocation: mouseLocation)
        let detectionBounds = interactiveBounds.insetBy(
            dx: -Self.hoverDetectionMargin,
            dy: -Self.hoverDetectionMargin
        )
        let isPointerInside = detectionBounds.contains(mouseLocation)

        if !isInteractive, !isNear, lastSampledMouseLocation == mouseLocation {
            return
        }

        lastSampledMouseLocation = mouseLocation

        if !isInteractive && !isNear {
            if isHovered {
                handleHover(hovering: false)
            }
            updateMouseEventHandling(isInteractive: false)
            return
        }

        if interactiveBounds != lastPublishedInteractiveFrame {
            lastPublishedInteractiveFrame = interactiveBounds
        }

        if suppressHoverAfterReveal, !isPointerInside {
            suppressHoverAfterReveal = false
        }

        if isPointerInside != isHovered, !dragManager.isDraggingInActivationZone, !activeAppMonitor.isWindowDragging {
            if !isPointerInside, notchState == .clickExpanded, widgetSwitchProtectionTask != nil {
                return
            }
            handleHover(hovering: isPointerInside)
        }

        updateMouseEventHandling(isInteractive: isInteractive || isPointerInside)
    }

    private func isMouseNearNotchFrame(_ notchFrame: CGRect, mouseLocation: CGPoint) -> Bool {
        guard !notchFrame.isEmpty else { return false }
        let proximityFrame = notchFrame.insetBy(
            dx: -Self.hoverProximityMargin,
            dy: -Self.hoverProximityMargin
        )
        return proximityFrame.contains(mouseLocation)
    }

    private func interactiveFrame(for window: NSWindow, config: ResolvedNotchConfiguration) -> CGRect {
        if isManuallyHidden { return .zero }

        let contentBounds = window.contentView?.bounds ?? .zero
        guard !contentBounds.isEmpty else { return .zero }

        let notchWidth: CGFloat
        let notchHeight: CGFloat
        switch notchState {
        case .initial:
            notchWidth = config.initialSize.width
            notchHeight = config.initialSize.height
        case .hoverExpanded, .autoExpanded, .clickExpanded:
            notchWidth = animatedWidth
            notchHeight = animatedHeight
        }

        let topInset = config.topBuffer
        let frame = CGRect(
            x: contentBounds.midX - (notchWidth / 2),
            y: contentBounds.maxY - notchHeight - topInset,
            width: notchWidth,
            height: notchHeight
        ).integral

        return frame.insetBy(dx: -1, dy: -1)
    }

    private func toRestorableMenu(mode: NotchWidgetMode) -> RestorableNotchMenu? {
        switch mode {
        case .defaultWidgets: return .defaultWidgets
        case .musicPlayer: return .musicPlayer
        case .musicQueueAndPlaylists: return .musicQueueAndPlaylists
        case .musicDevices: return .musicDevices
        case .nearDrop: return .nearDrop
        case .fileShelf: return .fileShelf
        case .multiAudio: return .multiAudio
        case .weatherPlayer: return .weatherPlayer
        case .calendarPlayer: return .calendarPlayer
        case .timerDetailView: return .timerDetailView
        case .sportsPlayer: return .sportsPlayer
        case .financePlayer: return .financePlayer
        case .shopifyOrders: return nil
        case .notesPlayer: return .notesPlayer
        case .clipboardPlayer: return .clipboardPlayer
        case .mirrorPlayer: return nil
        case .musicApiKeysMissing, .geminiApiKeysMissing, .musicLoginPrompt, .musicLyrics,
                .musicPlaylistDetail, .musicArtistDetail, .musicAlbumDetail, .snapZones, .fileShelfLanding, .fileActionPreview,
                .multiAudioDeviceAdjust, .multiAudioAppEQ, .multiAudioEQ, .dragActivated,
                .agentS, .blipHub, .circleToSearch, .updateAvailable, .focusSessionDetailView:
            return nil
        }
    }

    private func updateRadiiForCurrentState(state: NotchState) {
        guard let config = config else { return }
        let hasBottom = liveActivityManager.activityHasBottomContent

        switch state {
        case .initial:
            animatedCornerRadius = config.initialCornerRadius
            animatedBottomCornerRadius = config.initialCornerRadius
        case .hoverExpanded:
            if isLiveActivityActive {
                animatedCornerRadius = config.autoExpandedCornerRadius + (hasBottom ? 10 : 0)
                if case .full(_, _, let customRadius) = liveActivityManager.activityContent {
                    animatedBottomCornerRadius = customRadius ?? (hasBottom ? config.liveActivityBottomCornerRadius : animatedCornerRadius)
                } else {
                    animatedBottomCornerRadius = hasBottom ? config.liveActivityBottomCornerRadius : animatedCornerRadius
                }
            } else {
                animatedCornerRadius = config.initialCornerRadius
                animatedBottomCornerRadius = config.initialCornerRadius
            }
        case .clickExpanded:
            animatedCornerRadius = config.clickExpandedCornerRadius
            animatedBottomCornerRadius = config.clickExpandedCornerRadius
        case .autoExpanded:
            animatedCornerRadius = config.autoExpandedCornerRadius + (hasBottom ? 10 : 0)
            if case .full(_, _, let customRadius) = liveActivityManager.activityContent {
                animatedBottomCornerRadius = customRadius ?? (hasBottom ? config.liveActivityBottomCornerRadius : animatedCornerRadius)
            } else {
                animatedBottomCornerRadius = hasBottom ? config.liveActivityBottomCornerRadius : animatedCornerRadius
            }
        }
    }

    private func updateFPS() {
        guard let layer = notchWindow?.contentView?.layer else { return }
        let targetFPS: Int
        switch notchState {
        case .clickExpanded:
            targetFPS = 60
        case .autoExpanded, .hoverExpanded:
            targetFPS = isLiveActivityActive ? 45 : 30
        case .initial:
            targetFPS = 30
        }
        guard targetFPS != appliedTargetFPS else { return }

        appliedTargetFPS = targetFPS
        let key = "preferredFrameRateRange"
        let rateRange = CAFrameRateRange(minimum: 0, maximum: Float(targetFPS), preferred: Float(targetFPS))
        layer.setValue(rateRange, forKey: key)
    }

    private func updateAutoContentSize() {
        guard let config = config, notchState == .autoExpanded || (notchState == .hoverExpanded && isLiveActivityActive) else { return }
        let scale = activeScaleFactor
        let targetWidth = measuredAutoContentSize.width * scale
        let targetHeight = measuredAutoContentSize.height * scale
        let epsilon: CGFloat = 0.5

        guard targetWidth > 0 && targetHeight > 0,
              (abs(targetWidth - animatedWidth) > epsilon || abs(targetHeight - animatedHeight) > epsilon) else { return }

        let currentActivityType = liveActivityManager.currentActivity
        let isExemptFromBlur = (currentActivityType == .music || currentActivityType == .systemHUD)

        if !isExemptFromBlur {
            withAnimation(.easeIn(duration: config.activityBlurUpdateDelay)) { activityBlurRadius = 15 }
        }

        withAnimation(config.activityToActivityAnimation) {
            animatedWidth = targetWidth
            animatedHeight = targetHeight
        }

        if !isExemptFromBlur {
            DispatchQueue.main.asyncAfter(deadline: .now() + config.autoContentRenderDelay) {
                withAnimation(config.blurRemovalAnimation) { self.activityBlurRadius = 0 }
            }
        } else {
            activityBlurRadius = 0
        }
    }

    private func updateMouseEventHandling(isInteractive: Bool) {
        guard let window = notchWindow, let config = config else { return }

        if isManuallyHidden {
            window.ignoresMouseEvents = true
            if let dynamicWindow = window as? DynamicFocusWindow {
                dynamicWindow.forceMouseEventPassthrough = true
                dynamicWindow.updateInteractiveContentFrame(.zero)
            }
            return
        }

        if let dynamicWindow = window as? DynamicFocusWindow {
            dynamicWindow.forceMouseEventPassthrough = false
            dynamicWindow.updateInteractiveContentFrame(interactiveFrame(for: dynamicWindow, config: config))
            dynamicWindow.syncMouseEventPassthrough(forceEnable: isInteractive && notchState == .clickExpanded)
        } else if window.contentView != nil {
            let shouldIgnore = !isInteractive
            if window.ignoresMouseEvents != shouldIgnore {
                window.ignoresMouseEvents = shouldIgnore
            }
        }
    }

    private func updateWindowSharingBehavior(shouldBeHidden: Bool) {
        guard let window = notchWindow else { return }
        let desired: NSWindow.SharingType = shouldBeHidden ? .none : .readOnly
        if window.sharingType != desired {
            window.sharingType = desired
        }
    }

    private func syncNotchHostWindowHeight(contentHeight: CGFloat) {
        (NSApp.delegate as? AppDelegate)?.updateNotchHostWindowHeight(requiredContentHeight: contentHeight, for: notchWindow)
    }

    private func handleClickExpandedHoverOut(config: ResolvedNotchConfiguration) {
        guard !isPinned else { return }
        guard widgetSwitchProtectionTask == nil else { return }
        scheduleCollapse(after: 0)
    }

    private func startWidgetSwitchProtection() {
        widgetSwitchProtectionTask?.cancel()
        widgetSwitchProtectionGeneration &+= 1
        let generation = widgetSwitchProtectionGeneration

        widgetSwitchProtectionTask = Task { @MainActor in
            defer {
                if generation == self.widgetSwitchProtectionGeneration {
                    self.widgetSwitchProtectionTask = nil
                }
            }
            let settleThreshold: TimeInterval = 0.25
            let pollInterval: TimeInterval = 0.1
            let deadline = Date().addingTimeInterval(NotchController.widgetSwitchProtectionDuration)
            var lastSample: (width: CGFloat, height: CGFloat)?
            var stableSince: Date?

            while Date() < deadline {
                guard !Task.isCancelled else { return }
                if let window = self.notchWindow, let config = self.config {
                    let mouseLocation = window.mouseLocationOutsideOfEventStream
                    let interactiveBounds = self.interactiveFrame(for: window, config: config)
                        .insetBy(dx: -Self.hoverCollapseMargin, dy: -Self.hoverCollapseMargin)
                    if interactiveBounds.contains(mouseLocation) {
                        let sample = (width: self.animatedWidth, height: self.animatedHeight)
                        if let last = lastSample,
                           abs(last.width - sample.width) < 0.5,
                           abs(last.height - sample.height) < 0.5 {
                            if let since = stableSince,
                               Date().timeIntervalSince(since) >= settleThreshold {
                                return
                            }
                            stableSince = stableSince ?? Date()
                        } else {
                            stableSince = nil
                        }
                        lastSample = sample
                    } else {
                        lastSample = nil
                        stableSince = nil
                    }
                }
                try? await Task.sleep(for: .milliseconds(Int(pollInterval * 1000)))
            }

            guard !Task.isCancelled else { return }
            guard generation == self.widgetSwitchProtectionGeneration else { return }
            self.evaluateCollapseIfCursorOutsideHoverZone()
        }
    }

    private func cancelWidgetSwitchProtection() {
        widgetSwitchProtectionGeneration &+= 1
        widgetSwitchProtectionTask?.cancel()
        widgetSwitchProtectionTask = nil
    }

    private func evaluateCollapseIfCursorOutsideHoverZone() {
        guard let window = notchWindow, let config = config, !isPinned else { return }
        let mouseLocation = window.mouseLocationOutsideOfEventStream
        let interactiveBounds = interactiveFrame(for: window, config: config)
        let hoverBounds = notchState == .initial
            ? interactiveBounds
            : interactiveBounds.insetBy(dx: -Self.hoverCollapseMargin, dy: -Self.hoverCollapseMargin)
        guard !hoverBounds.contains(mouseLocation) else { return }
        guard !dragManager.isDraggingInActivationZone && !activeAppMonitor.isWindowDragging else { return }
        scheduleCollapse(after: 0)
    }

    private func scheduleCollapse(after delay: TimeInterval) {
        collapseTask?.cancel()
        guard !isPinned else { return }
        isCollapseTimerActive = true
        collapseTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(Int(delay * 1000)))
                guard !Task.isCancelled else { return }
                if !self.isHovered && !self.dragManager.isDraggingInActivationZone && !self.activeAppMonitor.isWindowDragging {
                    self.notchState = isLiveActivityActive ? .autoExpanded : .initial
                    self.evaluateInactiveNotchVisibility()
                }
                self.isCollapseTimerActive = false
            } catch {
                self.isCollapseTimerActive = false
            }
        }
    }

    private func cancelHoverExpandTask() {
        hoverExpandTask?.cancel()
        hoverExpandTask = nil
    }
}

final class KeyWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

fileprivate struct SubtleIconButton: View {
    let systemName: String
    let action: () -> Void
    let horizontalPadding: CGFloat
    let verticalPadding: CGFloat

    @State private var isHovering = false

    init(systemName: String, action: @escaping () -> Void, horizontalPadding: CGFloat = 8, verticalPadding: CGFloat = 6) {
        self.systemName = systemName
        self.action = action
        self.horizontalPadding = horizontalPadding
        self.verticalPadding = verticalPadding
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white.opacity(isHovering ? 1.0 : 0.7))
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, verticalPadding)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) { isHovering = hovering }
        }
        .scaleEffect(isHovering ? 1.1 : 1.0)
        .animation(.spring(response: 0.4, dampingFraction: 0.6), value: isHovering)
    }
}

extension LiveActivityManager {
    var activityAnimationKey: String {
        switch activityContent {
        case .none:
            return "none"
        case .full(_, let id, _):
            return "full:\(String(describing: id))"
        case .standard(let data, let id):
            switch data {
            case .music(let bottomContentType):
                return "music:\(musicBottomContentKind(bottomContentType))"
            default:
                return "standard:\(String(describing: id))"
            }
        }
    }

    var notchShapeSignature: String {
        switch activityContent {
        case .none:
            return "none"
        case .full(_, _, let bottomCornerRadius):
            let radiusComponent = Int((bottomCornerRadius ?? -1) * 10)
            return "full:\(radiusComponent)"
        case .standard(let data, _):
            switch data {
            case .music(let bottomContentType):
                return "music:\(musicBottomContentKind(bottomContentType))"
            default:
                return "standard"
            }
        }
    }

    var activityHasBottomContent: Bool {
        switch activityContent {
        case .full:
            return true
        case .standard(let data, _):
            switch data {
            case .music(let bottomContentType):
                return bottomContentType != .none
            case .focusSession:
                return true
            default:
                return false
            }
        case .none:
            return false
        }
    }

    private func musicBottomContentKind(_ contentType: MusicBottomContentType) -> String {
        switch contentType {
        case .none:
            return "none"
        case .peek:
            return "peek"
        case .lyrics:
            return "lyrics"
        case .upNext:
            return "upNext"
        }
    }
}