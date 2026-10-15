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
import AppKit
import Carbon.HIToolbox
import os.log

private let notchLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Sapphire", category: "NotchController")

private struct FileDropResult {
    let fallbackZone: DropZone?
    let finalLocation: CGPoint?
    let copiedURLs: [URL]
    let wasDraggedFromShelf: Bool
}

private struct NotchRuntimeSettings: Equatable {
    let animationProfile: AnimationProfile
    let customAnimationConfiguration: CustomizableAnimationConfiguration
    let notchWidth: CGFloat
    let notchHeight: CGFloat
    let perDisplayNotchSize: [String: NotchSizeOverride]
    let floatingIslandOnNotchlessDisplays: Bool
    let floatingIslandTopOffset: CGFloat
    let floatingIslandStyle: FloatingIslandStyle
    let swipeToHideNotch: Bool
    let hideWhenInactive: Bool
    let hideInFullScreen: Bool
    let suppressHoverExpansionForTransientLiveActivities: Bool
    let notchBarSpacerWidth: CGFloat
}

struct NotchController: View {
    let notchWindow: NSWindow?
    private let notchWidget: NotchWidgetView
    private let timerManager: TimerManager
    private let systemHUD = SystemHUDManager.shared
    private let runtimeStateSource: ObjectIdentifier?
    private let widgetEnvironment: (AnyView) -> AnyView

    enum NotchState: Hashable {
        case initial, autoExpanded, hoverExpanded, clickExpanded
    }

    private static let widgetSwitchProtectionDuration: TimeInterval = 2.5
    private static let hoverDetectionMargin: CGFloat = 8
    private static let expandedHoverStayMargin: CGFloat = 24
    private static let hoverCollapseMargin: CGFloat = 60
    private static let hoverProximityMargin: CGFloat = 32
    private static let revealSettlingInterval: TimeInterval = 0.7
    private static let activitySwitchBlurWindow: TimeInterval = 0.45

    // MARK: - Environment Objects
    @Environment(LiveActivityManager.self) var liveActivityManager
    @ObservedSettings var settings: SettingsObserver

    // MARK: - State Objects
    @StateObject private var fileShelfState = FileShelfState()
    @StateObject private var dragManager = GlobalDragManager()
    @StateObject private var calendarViewModel: InteractiveCalendarViewModel
    @StateObject private var widgetPlane = NotchWidgetPlane()

    @ObservedObject private var windowDrag = WindowDragState.shared
    private var dragState: DragStateManager { .shared }
    // MARK: - State Properties
    @State private var config: ResolvedNotchConfiguration?
    @State private var notchState: NotchState = .initial
    @State private var isHovered: Bool = false
    @State private var isPinned = false
    @State private var animatedWidth: CGFloat = 0
    @State private var animatedHeight: CGFloat = 0
    @State private var animatedCornerRadius: CGFloat = 0
    @State private var animatedBottomCornerRadius: CGFloat = 0
    @State private var animatedSatellites = NotchSatellitePresence.none

    @State private var measuredClickContentSize: CGSize = .zero
    @State private var clickContentLayoutSize: CGSize = .zero
    @State private var measuredAutoContentSize: CGSize = .zero
    @State private var notchIconsLeftWidth: CGFloat = 0
    @State private var notchIconsRightWidth: CGFloat = 0
    @State private var navigationStack: [NotchWidgetMode] = [.defaultWidgets]
    @State private var canRenderAutoContent: Bool = false
    @State private var isAnimatingActivityOut = false
    @State private var isAnimatingPlaneOut = false
    @State private var planeMorphDetached = false
    @State public var isFileDropTargeted: Bool = false
    @State private var activeDropZone: DropZone? = nil
    @State private var activeSnapZone: SnapZone? = nil
    @State private var notchDragLocationState = NotchDragLocationState()
    @State private var dropZoneFrames: [DropZone: CGRect] = [:]
    @State private var snapZoneHitRegions: [SnapZoneHitRegion] = []
    @State private var showLyrics: Bool = false
    @State private var liveActivityHorizontalPadding: CGFloat = 0
    @State private var expansionAnimation: Animation = NotchConfiguration.expandAnimation
    @StateObject private var stage = NotchStageCoordinator()
    @State private var scratch = Scratch()

    @MainActor
    private final class Scratch {
        var expandedSizeByMode: [NotchWidgetMode: CGSize] = [:]
        var lastExpandedStagePass: CFTimeInterval = 0
        var lastActivityStagePass: CFTimeInterval = 0
        var lastActivitySize: CGSize = .zero
        var islandBarSize: CGSize = .zero
        var lastStandardActivity: (content: LiveActivityContent, activity: ActivityType)?
        var pendingHoverExit: DispatchWorkItem?
        var expandedStageSince: CFTimeInterval = 0
        var lastStagePassExpanded = false
        var lastSampledMouseLocation: CGPoint?
        var lastPublishedInteractiveFrame: CGRect = .null
        var collapseTask: Task<Void, Never>?
        var lastCollapseReason = "unknown"
        var dragEndCollapseTask: Task<Void, Never>?
        var fileDragExitTask: Task<Void, Never>?
        var windowDragCleanupTask: Task<Void, Never>?
        var isCollapseTimerActive: Bool = false
        var widgetSwitchProtectionTask: Task<Void, Never>?
        var widgetSwitchSettleTask: Task<Void, Never>?
        var widgetSwitchProtectionGeneration: UInt64 = 0
        var clickExpandedOpenedAt: Date = .distantPast
        var awaitingDropCompletion: Bool = false
        var nextFileDropSequence: UInt64 = 0
        var nextFileDropSequenceToRoute: UInt64 = 0
        var pendingFileDropSequences: Set<UInt64> = []
        var completedFileDrops: [UInt64: FileDropResult] = [:]
        var dropZoneResolutionTask: Task<Void, Never>?
        var isHandlingActiveWindowDrag = false
        var lastActivityShapeSignature: NotchShapeSignature = .none
        var fileDropFlowObserver: NSObjectProtocol?
        var snapZoneEscapeMonitorToken: UUID?
        var spacePlayPauseTapToken: GlobalEventTap.Token?
        var lastInactiveVisibilityEvaluation: (hideWhenInactive: Bool, hideReason: NotchCompleteHideReason?)?
        var inactiveHideUserOverride: Bool = false
        var inactiveRehideTask: Task<Void, Never>?
        var suppressHoverAfterReveal = false
        var revealSettlingUntil: Date = .distantPast
        var hoverExpandTask: Task<Void, Never>?
        var blurRemovalTask: Task<Void, Never>?
        var activitySwitchBlurWindowEnd: Date = .distantPast
        var stateTransitionGeneration: UInt64 = 0
        var activityEffectGeneration: UInt64 = 0
        var registeredDisplayID: CGDirectDisplayID?
    }
    private var morphEngine: NotchMorphEngine { stage.engine }
    private var effects: NotchEffects { stage.effects }
    @State private var isFileDragSessionInProgress = false
    @State private var activeFileDragIsFromShelf = false
    @State private var displayedFileDragMode: FileDragMode = .newFile

    @State private var hoverMonitor: NotchHoverMonitor?
    @State private var isCalendarHovered: Bool = false
    @State private var completeHideReason: NotchCompleteHideReason? = nil
    @State private var hasRingingTimer: Bool
    @State private var hudOverlayKind: HUDOverlayKind?

    private enum HUDOverlayKind: Equatable {
        case volume
        case brightness
    }

    private enum NotchCompleteHideReason {
        case manualSwipe
        case inactive
    }

    private var isManuallyHidden: Bool { completeHideReason != nil }

    // MARK: - Computed Properties
    private var isLiveActivityActive: Bool { effectiveActivity != .none }

    private var shouldSuppressSnapZoneActivation: Bool {
        (notchState == .clickExpanded && navigationStack.last != .snapZones)
            || (windowDrag.isDragging && windowDrag.isSnapZoneDismissedForCurrentDrag)
            || (windowDrag.isDragging && windowDrag.isSnapZoneBypassModifierPressed)
    }

    private var notchDisplayID: CGDirectDisplayID? {
        if let window = notchWindow as? DynamicFocusWindow, window.displayID != 0 {
            return window.displayID
        }
        return notchWindow?.screen?.displayID
    }

    private var assignedScreen: NSScreen? {
        if let window = notchWindow as? DynamicFocusWindow, window.displayID != 0 {
            return NSScreen.screens.first { $0.displayID == window.displayID }
        }
        return notchWindow?.screen ?? CursorPosition.targetNotchScreen()
    }

    private var runtimeSettings: NotchRuntimeSettings {
        let current = settings.settings.value
        let displayKey = assignedScreen?.displayIdentifier
        return NotchRuntimeSettings(
            animationProfile: current.animationProfile,
            customAnimationConfiguration: current.customAnimationConfiguration,
            notchWidth: current.notchWidth,
            notchHeight: current.notchHeight,
            perDisplayNotchSize: current.perDisplayNotchSize,
            floatingIslandOnNotchlessDisplays: current.resolvedFloatingIsland(
                forDisplayID: displayKey
            ),
            floatingIslandTopOffset: current.resolvedFloatingIslandTopOffset(
                forDisplayID: displayKey
            ),
            floatingIslandStyle: current.resolvedFloatingIslandStyle(
                forDisplayID: displayKey
            ),
            swipeToHideNotch: current.swipeToHideNotch,
            hideWhenInactive: current.resolvedHideNotchWhenInactive(
                forDisplayID: displayKey
            ),
            hideInFullScreen: current.resolvedFullScreenBehavior(
                forDisplayID: displayKey
            ).hideNotch,
            suppressHoverExpansionForTransientLiveActivities: current.suppressHoverExpansionForTransientLiveActivities,
            notchBarSpacerWidth: current.notchBarSpacerWidth
        )
    }

    private var effectiveActivity: ActivityType {
        liveActivityManager.effectiveActivity(onDisplayID: notchDisplayID)
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
            if let payload = liveActivityManager.currentNearbyTransferPayload,
               payload.state == .waitingForConsent {
                return true
            }
        case .eyeBreak, .notification, .otp, .parcel:
            return true
        case .timer:
            return hasRingingTimer
        default:
            break
        }

        return false
    }

    private var currentMode: NotchWidgetMode { navigationStack.last ?? .defaultWidgets }

    private var shouldSuppressHoverExpansionForLiveActivity: Bool {
        guard settings.settings.suppressHoverExpansionForTransientLiveActivities else { return false }
        return LiveActivityHoverExpansionPolicy.shouldSuppress(activity: effectiveActivity)
    }

    private var notchIconsIntrinsicWidth: CGFloat {
        NotchBarSpacerPolicy.symmetricItemsWidth(
            leading: notchIconsLeftWidth,
            trailing: notchIconsRightWidth,
            inset: config?.defaultModeIconsHorizontalPadding ?? 0
        )
    }

    private var notchBarMinimumWidth: CGFloat {
        NotchBarSpacerPolicy.minimumBarWidth(
            configuredWidth: settings.settings.notchBarSpacerWidth,
            itemsWidth: notchIconsIntrinsicWidth,
            minimumSpacerWidth: config?.barMinimumSpacerWidth ?? 0
        )
    }

    private var activeAppearanceSettings: NotchAppearanceSettings {
        let displayKey = assignedScreen?.displayIdentifier
        let expanded = {
            DisplaySettingsKey.value(in: settings.settings.perDisplayNotchWidgetAppearance, for: displayKey)
                ?? settings.settings.notchWidgetAppearance
        }
        switch notchState {
        case .initial, .clickExpanded:
            return expanded()
        case .autoExpanded, .hoverExpanded:
            guard isLiveActivityActive else { return expanded() }
            return DisplaySettingsKey.value(in: settings.settings.perDisplayNotchLiveActivityAppearance, for: displayKey)
                ?? settings.settings.notchLiveActivityAppearance
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

    private enum DefaultAppearancePalette {
        static let opaqueBlack = NSColor(Color.black).cgColor
        static let clearBlack = NSColor(Color.black.opacity(0)).cgColor

        static func black(at location: CGFloat) -> CodableColor {
            CodableColor(cgColor: opaqueBlack, location: location)
        }

        static func fadedOut(at location: CGFloat) -> CodableColor {
            CodableColor(cgColor: clearBlack, location: location)
        }
    }

    static func resolveAppearance(
        _ activeAppearance: NotchAppearanceSettings,
        isExpandedLiveActivity: Bool,
        fadeStartLocation: Double,
        hasBottomSurface: () -> Bool
    ) -> NotchAppearanceSettings {
        var appearance = activeAppearance
        switch appearance.mode {
        case .default:
            appearance.solidColor = DefaultAppearancePalette.black(at: 0)
            appearance.opacity = 1
            appearance.enableTransparencyBlur = false
            appearance.liquidGlassLook = true
            if appearance.bottomFadeEnabled {
                if isExpandedLiveActivity {
                    if hasBottomSurface() {
                        appearance.backgroundStyle = .gradient
                        appearance.gradientAngle = 90
                        appearance.gradientColors = [
                            DefaultAppearancePalette.black(at: CGFloat(fadeStartLocation)),
                            DefaultAppearancePalette.fadedOut(at: 1.0)
                        ]
                    } else {
                        appearance.backgroundStyle = .solid
                    }
                } else {
                    appearance.backgroundStyle = .gradient
                    appearance.gradientAngle = 90
                    appearance.gradientColors = [
                        DefaultAppearancePalette.black(at: 0.7),
                        DefaultAppearancePalette.fadedOut(at: 1.0)
                    ]
                }
            } else {
                appearance.backgroundStyle = .solid
            }
        case .liquidGlass:
            appearance.backgroundStyle = .solid
            appearance.solidColor = DefaultAppearancePalette.black(at: 0)
            appearance.opacity = 0.0
            appearance.enableTransparencyBlur = false
            appearance.liquidGlassLook = true
            appearance.bottomFadeEnabled = false
        case .blur:
            appearance.backgroundStyle = .solid
            appearance.solidColor = DefaultAppearancePalette.black(at: 0)
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
        !isManuallyHidden && (notchState == .clickExpanded || isHovered || dragManager.isDraggingInActivationZone || windowDrag.isDragging)
    }

    private var isPointerInteractionActive: Bool {
        !isManuallyHidden && (isHovered || dragManager.isDraggingInActivationZone || windowDrag.isDragging)
    }

    private var isPointerCaptureActive: Bool {
        dragManager.isDraggingInActivationZone
            || windowDrag.isDragging
            || (isHovered && NSEvent.pressedMouseButtons != 0)
    }

    private var cursorIsOnMyScreen: Bool {
        guard let notchScreen = assignedScreen else {
            return CursorPosition.targetNotchScreen() == nil
        }
        return NotchDisplayTargeting.screen(containing: NSEvent.mouseLocation)?.displayID == notchScreen.displayID
    }

    private var shouldHideWindowForSharing: Bool {
        settings.settings.hideFromScreenSharing
    }

    private var shouldBlockNotchExpansionWhileLocked: Bool {
        settings.settings.preventNotchExpandWhenLocked
            && ((NSApp.delegate as? AppDelegate)?.isScreenLocked == true)
    }

    private var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    private var activeScaleFactor: CGFloat {
        guard let config = config, notchState == .hoverExpanded && !isFullViewActivity else { return 1.0 }
        return config.scaleFactor
    }

    private var showRightHUDOverlay: Bool {
        guard notchState == .clickExpanded else { return false }
        guard cursorIsOnMyScreen else { return false }
        switch hudOverlayKind {
        case .volume:
            guard settings.settings.enableVolumeHUD else { return false }
            return true
        case .brightness:
            guard settings.settings.enableBrightnessHUD else { return false }
            return true
        case nil:
            return false
        }
    }

    private static func overlayKind(for hud: HUDType?) -> HUDOverlayKind? {
        switch hud?.caseIdentifier {
        case .volume, .externalDeviceVolume, .appVolume:
            return .volume
        case .brightness, .keyboardBrightness, .multiDisplayBrightness:
            return .brightness
        case nil:
            return nil
        }
    }

    private func updateHUDOverlayAnimation() {
        if showRightHUDOverlay {
            effects.update(.notchMorphTiming(.easeOut, duration: 0.18)) { $0.hudOpacity = 1; $0.hudBlur = 0 }
        } else {
            effects.update(.notchMorphTiming(.easeIn, duration: 0.12)) { $0.hudOpacity = 0; $0.hudBlur = 10 }
        }
    }

    private var surfaceShadowOpacity: Double {
        guard !isGeminiActive, !isManuallyHidden else { return 0 }
        return effects.values.shadowOpacity
    }

    private var activeShape: CustomNotchShape {
        var shape = CustomNotchShape(
            cornerRadius: animatedCornerRadius,
            bottomCornerRadius: animatedBottomCornerRadius,
            isMusicActivity: isDisplayingMusicLiveActivity,
            isFloatingIsland: config?.isFloatingIsland ?? false,
            floatingIslandCornerRadius: config?.floatingIslandCornerRadius ?? CustomNotchShape.floatingIslandExpandedCornerRadius,
            isNotchless: config?.isNotchless ?? false
        )
        if let config { shape.satelliteLayout = satelliteLayout(config: config) }
        if let config, config.isFloatingIsland, let barSize = islandBarShapeSize(config: config) {
            shape.islandBarSize = barSize
            shape.islandBarGap = NotchIslandBar.gap
            shape.islandCollapsedHeight = isLiveActivityActive
                ? max(config.initialSize.height, measuredAutoContentSize.height)
                : config.initialSize.height
        }
        return shape
    }

    // MARK: Satellites (extra live activities)

    private func satelliteLayout(config: ResolvedNotchConfiguration) -> NotchSatelliteLayout {
        guard settings.settings.showLiveActivitySatellites else { return .none }
        let band = config.initialSize.height
        if config.isFloatingIsland {
            return NotchSatelliteLayout(diameter: (band * 1.06).rounded(), gap: (band * 0.2).rounded(), centerY: band / 2)
        }
        return NotchSatelliteLayout(diameter: max(18, band - 6), gap: 6, centerY: band / 2)
    }

    private var visibleSatellites: [NotchSatelliteActivity] {
        guard settings.settings.showLiveActivitySatellites, !isManuallyHidden,
              notchState == .autoExpanded || notchState == .hoverExpanded,
              isLiveActivityActive, case .standard = liveActivityManager.activityContent,
              effectiveActivity != .systemHUD, effectiveActivity != .lockScreen, effectiveActivity != .unlocked
        else { return [] }
        return Array(liveActivityManager.satelliteActivities.prefix(max(1, min(NotchSatelliteSlot.count, settings.settings.liveActivitySatelliteLimit))))
    }

    private func updateSatellitePresence(stateChange: (NotchState, NotchState)? = nil) {
        let target = NotchSatellitePresence.showing(visibleSatellites.count)
        guard target != animatedSatellites else { return }
        let growing = NotchSatelliteSlot.allCases.contains { target[$0] > animatedSatellites[$0] }
        let animation: Animation
        if let (_, newState) = stateChange, newState == .clickExpanded, let config {
            animation = config.expandAnimation
        } else if growing {
            animation = .notchMorphSpring(response: 0.5, dampingFraction: 0.58)
        } else {
            animation = .notchMorphSpring(response: 0.38, dampingFraction: 0.92)
        }
        withAnimation(animation) {
            animatedSatellites = target
        }
    }

    private func satellitePieces(config: ResolvedNotchConfiguration) -> [NotchSatelliteSlot: NotchSatellitePiece] {
        let layout = satelliteLayout(config: config)
        guard layout.diameter > 0 else { return [:] }
        var pieces: [NotchSatelliteSlot: NotchSatellitePiece] = [:]
        for (side, satellite) in zip(NotchSatelliteSlot.allCases, visibleSatellites) {
            let type = satellite.type
            let view = NotchActivityContentView(
                content: satellite.content,
                config: config,
                horizontalPadding: 0,
                screen: assignedScreen,
                measuredSize: .constant(.zero),
                showLyrics: .constant(false),
                region: .leading
            )
            .scaleEffect(0.78)
            .frame(width: layout.diameter, height: layout.diameter)
            .contentShape(Circle())
            .onTapGesture { openSatellite(type) }
            .help(Self.satelliteHelp(type))
            pieces[side] = NotchSatellitePiece(
                view: widgetEnvironment(AnyView(view)),
                key: NotchContentKey(
                    config: config,
                    numbers: [layout.diameter],
                    tags: ["satellite", String(describing: type)]
                        + (type == .fileProgress ? [String(describing: satellite.content.renderIdentity)] : [])
                )
            )
        }
        return pieces
    }

    private func openSatellite(_ type: ActivityType) {
        guard let config else { return }
        let destination: NotchWidgetMode?
        switch type {
        case .music: destination = .musicPlayer
        case .timer: destination = .timerDetailView
        case .focusSession: destination = .focusSessionDetailView
        case .fileProgress: destination = .fileProgressDetail
        case .geminiLive: destination = .blipHub
        case .weather: destination = .weatherPlayer
        case .calendar: destination = .calendarPlayer
        case .battery: destination = .batteryDetailView
        case .fileShelf: destination = .fileShelf
        default: destination = nil
        }
        expansionAnimation = config.expandAnimation
        measuredClickContentSize = .zero
        navigationStack = [.defaultWidgets] + (destination.map { [$0] } ?? [])
        notchState = .clickExpanded
    }

    private static func satelliteHelp(_ type: ActivityType) -> String {
        switch type {
        case .music: return "Now Playing"
        case .timer: return "Timer"
        case .focusSession: return "Focus Session"
        case .fileProgress: return "File Transfer"
        case .microphone: return "Microphone"
        case .devActivity: return "Developer Activity"
        case .geminiLive: return "Blip"
        case .desktopChange: return "Desktop"
        case .focusModeChange: return "Focus"
        case .battery: return "Battery"
        case .weather: return "Weather"
        case .calendar: return "Calendar"
        case .reminder: return "Reminder"
        case .fileShelf: return "File Shelf"
        case .bluetooth: return "Bluetooth"
        case .audioSwitch: return "Audio Output"
        case .stats: return "Stats"
        case .eyeBreak: return "Eye Break"
        case .sports: return "Sports"
        case .finance: return "Finance"
        default: return "Live Activity"
        }
    }

    private func islandBarItems(config: ResolvedNotchConfiguration) -> [NotchIslandBar.Item] {
        NotchIslandBar.items(
            settings: settings.settings.value,
            navigationDepth: navigationStack.count,
            maxWidth: max(0, animatedWidth - 2 * NotchIslandBar.gap)
        )
    }

    private func islandBarShapeSize(config: ResolvedNotchConfiguration) -> CGSize? {
        if notchState == .clickExpanded {
            let size = NotchIslandBar.showsBar(for: currentMode)
                ? NotchIslandBar.size(of: islandBarItems(config: config))
                : .zero
            scratch.islandBarSize = size
            return size.width > 0 ? size : nil
        }
        guard scratch.islandBarSize.width > 0,
              CACurrentMediaTime() - scratch.lastExpandedStagePass < Self.fluidCarryDuration else { return nil }
        return scratch.islandBarSize
    }

    // MARK: - Initializer
    public init(
        notchWindow: NSWindow?,
        initialConfiguration: ResolvedNotchConfiguration? = nil,
        timerManager: TimerManager,
        widgetEnvironment: @escaping (AnyView) -> AnyView = { $0 }
    ) {
        if let initialConfiguration {
            _config = State(initialValue: initialConfiguration)
            _animatedWidth = State(initialValue: initialConfiguration.initialSize.width)
            _animatedHeight = State(initialValue: initialConfiguration.initialSize.height)
            _animatedCornerRadius = State(initialValue: initialConfiguration.initialCornerRadius)
            _animatedBottomCornerRadius = State(initialValue: initialConfiguration.initialCornerRadius)
            _expansionAnimation = State(initialValue: initialConfiguration.expandAnimation)
            _liveActivityHorizontalPadding = State(initialValue: initialConfiguration.activityDefaultHorizontalPadding)
        }
        self.widgetEnvironment = widgetEnvironment
        self.notchWindow = notchWindow
        self.timerManager = timerManager
        self.runtimeStateSource = notchWindow.map(ObjectIdentifier.init)
        _hasRingingTimer = State(initialValue: timerManager.hasRingingTimer)
        _hudOverlayKind = State(
            initialValue: Self.overlayKind(for: SystemHUDManager.shared.currentHUD)
        )
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
                    let initialConfig = ResolvedNotchConfiguration(from: settings.settings.value, screen: assignedScreen)
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
        let stageView = NotchStage(coordinator: stage, content: stageContent(config: config))
            .background { signalBridges }
            .environment(\.notchBandHeight, config.initialSize.height)
            .preferredColorScheme(.dark)
        applyNotchSettingsHandlers(
            to: applyNotchNotificationHandlers(
                to: applyNotchStateHandlers(to: stageView)
            )
        )
    }

    private var signalBridges: some View {
        ZStack {
            NotchStageSignalBridge(coordinator: stage, signal: .size(CGSize(width: animatedWidth, height: animatedHeight)))
            NotchStageSignalBridge(coordinator: stage, signal: .radii(corner: animatedCornerRadius, bottom: animatedBottomCornerRadius))
            NotchStageSignalBridge(coordinator: stage, signal: .satellites(animatedSatellites))
        }
        .allowsHitTesting(false)
    }

    #if DEBUG
    private static let profilingHidden: Set<String> = Set(
        (ProcessInfo.processInfo.environment["SAPPHIRE_PROF_HIDE"] ?? "").split(separator: ",").map(String.init)
    )
    #else
    private static let profilingHidden: Set<String> = []
    #endif

    private static var systemGlassAvailable: Bool {
        if #available(macOS 26.0, *) { return true }
        return false
    }

    private var resolvedAppearance: NotchAppearanceSettings {
        Self.resolveAppearance(
            activeAppearanceSettings,
            isExpandedLiveActivity: isExpandedLiveActivity,
            fadeStartLocation: liveActivityFadeStartLocation
        ) {
            liveActivityManager.isFullViewActivity || liveActivityManager.activityHasBottomContent
        }
    }

    private func stageContent(config: ResolvedNotchConfiguration) -> NotchStageContent {
        let targetSize = CGSize(width: animatedWidth, height: animatedHeight)
        let layout = NotchStageLayout(
            topInset: config.topInset - config.topBuffer,
            bandHeight: config.initialSize.height,
            displayScale: notchWindow?.backingScaleFactor ?? config.displayScale,
            isFloatingIsland: config.isFloatingIsland,
            floatingIslandCornerRadius: config.floatingIslandCornerRadius,
            outlineSize: targetSize,
            satelliteLayout: satelliteLayout(config: config)
        )
        let appearance = resolvedAppearance
        let surface = NotchSurfaceStyle.resolve(NotchSurfaceStyle.Inputs(
            appearance: appearance,
            config: config,
            shape: activeShape,
            notchState: notchState,
            isGeminiActive: isGeminiActive,
            isManuallyHidden: isManuallyHidden,
            surfaceShadowOpacity: surfaceShadowOpacity,
            radialEndRadius: appearance.backgroundStyle == .radial ? animatedWidth / 2 : 0,
            systemGlassAvailable: Self.systemGlassAvailable
        ))

        var content = NotchStageContent(layout: layout, surface: surface)
        let fluid = config.couplesContentToMorph && !reduceMotion
        let now = CACurrentMediaTime()
        let showActivityView = (notchState == .autoExpanded || notchState == .hoverExpanded || isAnimatingActivityOut)
        let carriesActivity = fluid && notchState == .clickExpanded && effectiveActivity != .none
        let fluidActivityOut = fluid && effectiveActivity == .none && scratch.lastActivitySize.width > 1
            && (isAnimatingActivityOut && notchState == .initial
                || notchState == .autoExpanded || notchState == .hoverExpanded)
        let collapsingIntoActivity = fluid && effectiveActivity != .none
            && now - scratch.lastExpandedStagePass < Self.fluidCarryDuration
        if showActivityView && (effectiveActivity != .none || fluidActivityOut)
            && (canRenderAutoContent || fluidActivityOut || collapsingIntoActivity) && !Self.profilingHidden.contains("activity") {
            assignActivity(to: &content, config: config, tag: "")
            if fluidActivityOut {
                content.activitySize = scratch.lastActivitySize
            } else {
                content.activitySize = targetSize
                scratch.lastActivitySize = targetSize
            }
            scratch.lastActivityStagePass = now
        } else if notchState == .clickExpanded && !Self.profilingHidden.contains("plane") {
            applyPlane(to: &content, config: config, targetSize: targetSize)
            if carriesActivity && scratch.lastActivitySize.width > 1 && !Self.profilingHidden.contains("activity") {
                assignActivity(to: &content, config: config, tag: "carry")
                content.activitySize = scratch.lastActivitySize
            }
        }
        if notchState == .clickExpanded {
            scratch.lastExpandedStagePass = now
            if !scratch.lastStagePassExpanded { scratch.expandedStageSince = now }
        }
        scratch.lastStagePassExpanded = notchState == .clickExpanded
        let carriesPlaneOut = isAnimatingPlaneOut
            || (fluid && now - scratch.lastExpandedStagePass < Self.fluidCarryDuration)
        content.activityFollowsOutline = fluid
        content.activityBehindPanel = notchState == .clickExpanded
        if carriesPlaneOut && content.plane == nil && !Self.profilingHidden.contains("plane") {
            applyPlane(to: &content, config: config, targetSize: targetSize)
        }
        if notchState == .clickExpanded && !Self.profilingHidden.contains("chrome") {
            content.chrome = chromePieces(config: config)
            if showRightHUDOverlay && !config.isFloatingIsland {
                content.chrome[.hud] = NotchChromePiece(
                    anchor: .trailing,
                    fade: .hud,
                    hitTestable: effects.values.hudOpacity > 0.5,
                    key: NotchContentKey(config: config, numbers: [animatedWidth]),
                    view: widgetEnvironment(AnyView(NotchHUDOverlayContent(config: config, animatedWidth: animatedWidth)))
                )
            }
        }
        content.satellites = satellitePieces(config: config)
        content.onTap = handleTap
        return content
    }

    private static let fluidCarryDuration: CFTimeInterval = 0.9

    private func applyPlane(to content: inout NotchStageContent, config: ResolvedNotchConfiguration, targetSize: CGSize) {
        content.plane = preparedWidgetPlane(config: config)
        content.planeSize = clickContentLayoutSize.width > 1 && clickContentLayoutSize.height > 1
            ? clickContentLayoutSize
            : targetSize
        content.planeEntranceStiffness = currentMode == .defaultWidgets ? 230 : 220
        content.planeEntranceDamping = currentMode == .defaultWidgets ? 22 : 18
        content.planeFollowsOutline = config.couplesContentToMorph && !reduceMotion && !planeMorphDetached
    }

    private func assignActivity(to content: inout NotchStageContent, config: ResolvedNotchConfiguration, tag: String) {
        if let regions = activityRegions(config: config, tag: tag) {
            content.activityRegions = regions
            return
        }
        content.activity = widgetEnvironment(AnyView(activityContent(config: config)))
        content.activityKey = NotchContentKey(
            config: config,
            numbers: [liveActivityHorizontalPadding],
            tags: [String(assignedScreen?.displayID ?? 0)] + (tag.isEmpty ? [] : [tag])
        )
    }

    private func activityRegions(config: ResolvedNotchConfiguration, tag: String) -> NotchActivityRegions? {
        var live = liveActivityManager.activityContent
        var activity = liveActivityManager.currentActivity
        if case .none = live {
            live = scratch.lastStandardActivity?.content ?? .none
            activity = scratch.lastStandardActivity?.activity ?? activity
        } else if case .standard = live {
            scratch.lastStandardActivity = (live, activity)
        }
        guard case .standard(let data, _) = live else { return nil }

        let padding = liveActivityHorizontalPadding
        let screen = assignedScreen
        func piece(_ slot: NotchActivityRegionSlot) -> AnyView {
            widgetEnvironment(AnyView(
                NotchActivityContentView(
                    content: live,
                    config: config,
                    horizontalPadding: padding,
                    screen: screen,
                    measuredSize: .constant(.zero),
                    showLyrics: $showLyrics,
                    region: slot
                )
                .contentShape(Rectangle())
                .onTapGesture(perform: handleTap)
            ))
        }
        let bottomKind = NotchActivityRegions.bottomKind(for: data)
        return NotchActivityRegions(
            leading: piece(.leading),
            trailing: piece(.trailing),
            bottom: bottomKind == nil ? nil : piece(.bottom),
            identity: AnyHashable(activity),
            bottomKind: bottomKind ?? "",
            bottomLeading: NotchActivityRegions.bottomIsLeading(for: data),
            key: .init(
                content: live,
                base: NotchContentKey(
                    config: config,
                    numbers: [padding],
                    tags: [String(screen?.displayID ?? 0)] + (tag.isEmpty ? [] : [tag])
                )
            ),
            horizontalPadding: padding,
            centerGap: config.activityCenterGap,
            bandHeight: config.initialSize.height,
            onSizeChange: { size in
                guard self.measuredAutoContentSize != size else { return }
                self.measuredAutoContentSize = size
            }
        )
    }

    private func activityContent(config: ResolvedNotchConfiguration) -> some View {
        NotchLiveActivityContent(
            liveActivityManager: liveActivityManager,
            config: config,
            horizontalPadding: liveActivityHorizontalPadding,
            screen: assignedScreen,
            measuredSize: $measuredAutoContentSize,
            showLyrics: $showLyrics
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .contentShape(Rectangle())
        .onTapGesture(perform: handleTap)
    }

    private func applyNotchStateHandlers<V: View>(to view: V) -> some View {
        view
            .onReceive(Self.debugHookPublisher) { handleDebugHook($0.object as? String) }
            .background(LiveActivityContentUpdateObserver(
                liveActivityManager: liveActivityManager,
                onUpdate: handleLiveActivityContentUpdate
            ))
            .onAppear(perform: setupMonitors)
            .onDisappear(perform: teardownMonitors)
            .onChange(of: fileShelfState.selectedItemForPreview, perform: handlePreviewItemChange)
            .onChange(of: liveActivityManager.currentActivity, perform: handleActivityChange)
            .onChange(of: liveActivityManager.satelliteActivities) { _, _ in updateSatellitePresence() }
            .onChange(of: showRightHUDOverlay) { _, _ in
                updateHUDOverlayAnimation()
            }
            .onChange(of: notchState) { oldState, newState in
                traceCollapseIfNeeded(from: oldState, to: newState)
                handleStateChange(from: oldState, to: newState)
                updateSatellitePresence(stateChange: (oldState, newState))
                updateRuntimeExpansionState()
                updateSpacePlayPauseTap()
            }
            .onChange(of: navigationStack, handleNavigationStackChange)
            .onChange(of: navigationStack) { _, _ in syncWidgetPlaneState() }
            .onChange(of: activeDropZone) { _, _ in syncWidgetPlaneState() }
            .onChange(of: isCalendarHovered) { _, _ in syncWidgetPlaneState() }
            .onChange(of: dragManager.isDraggingInActivationZone, perform: handleDragActivationZoneChange)
            .onChange(of: windowDrag.isDragging, perform: handleActiveWindowDragChange)
            .onChange(of: windowDrag.cursorDisplayID, perform: handleWindowDragDisplayChange)
            .onChange(of: windowDrag.isSnapZoneDismissedForCurrentDrag, perform: handleSnapZoneDismissalChange)
            .onChange(of: windowDrag.isSnapZoneBypassModifierPressed) { _, isPressed in
                handleSnapZoneBypassModifierChange(isPressed)
            }
            .onChange(of: isFileDropTargeted, perform: handleFileDropTargetChange)
            .onChange(of: measuredClickContentSize, perform: handleMeasuredClickSizeChange)
            .onChange(of: measuredAutoContentSize, perform: handleMeasuredAutoSizeChange)
            .onChange(of: liveActivityManager.fullScreenDisplayIDs) { _, _ in
                handleFullScreenDisplayChange()
            }
            .onReceive(
                timerManager.$ringingTimers
                    .map { !$0.isEmpty }
                    .removeDuplicates()
            ) { isRinging in
                hasRingingTimer = isRinging
            }
            .onReceive(
                systemHUD.$currentHUD
                    .map(Self.overlayKind(for:))
                    .removeDuplicates()
            ) { kind in
                hudOverlayKind = kind
            }
    }

    private static let notchNotifications = Publishers.MergeMany(
        [
            Notification.Name.sapphireOpenMusicQueue,
            .sapphireOpenMusicDevices,
            .sapphireRevealHiddenNotch,
            .sapphireOpenCircleToSearch
        ].map { NotificationCenter.default.publisher(for: $0) }
    )

    private func applyNotchNotificationHandlers<V: View>(to view: V) -> some View {
        view
            .background(GeminiPickerBridge())
            .onReceive(Self.notchNotifications) { notification in
                switch notification.name {
                case .sapphireOpenMusicQueue:
                    guard isTargetOfAppWideRequest(notification) else { return }
                    openMusicHub(mode: .musicQueueAndPlaylists)
                case .sapphireOpenMusicDevices:
                    guard isTargetOfAppWideRequest(notification) else { return }
                    openMusicHub(mode: .musicDevices)
                case .sapphireRevealHiddenNotch:
                    guard isManuallyHidden,
                          let displayID = notchDisplayID,
                          (notification.object as? NSNumber)?.uint32Value == displayID else { return }
                    haptic()
                    scratch.inactiveHideUserOverride = true
                    revealNotchFromCompleteHide()
                    scheduleInactiveRehideAfterReveal()
                case .sapphireOpenCircleToSearch:
                    guard isTargetOfAppWideRequest(notification) else { return }
                    openCircleToSearch(object: notification.object as? String)
                default:
                    break
                }
            }
    }

    private func applyNotchSettingsHandlers<V: View>(to view: V) -> some View {
        view
            .onChange(of: showLyrics, perform: handleShowLyricsChange)
            .onChange(of: isInteractive) { _, isNowInteractive in
                updateMouseEventHandling(isInteractive: isNowInteractive)
                if let runtimeStateSource {
                    MenuBarInteractionManager.shared.setSuspended(isNowInteractive, by: runtimeStateSource)
                }
            }
            .onChange(of: CGSize(width: animatedWidth, height: animatedHeight)) { _, _ in
                updateMouseEventHandling(isInteractive: isInteractive)
                scheduleWidgetSwitchSettledCheck()
            }
            .onChange(of: hostWindowExtent) { _, _ in syncHostWindowExtent() }
            .onChange(of: notchIconsIntrinsicWidth) { _, _ in
                applyNotchIconsWidthFloor()
            }
            .onChange(of: notchBarMinimumWidth) { _, _ in
                applyNotchIconsWidthFloor()
            }
            .onChange(of: shouldHideWindowForSharing, perform: handleSharingVisibilityChange)
            .onChange(of: runtimeSettings, perform: handleSettingsChange)
    }

    private func handleDragActivationZoneChange(_ isDragging: Bool) {
        if !isDragging { reevaluatePointerInteraction() }
        if isDragging {
            let mouseLocation = NSEvent.mouseLocation
            let notchScreen = assignedScreen
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
        scratch.windowDragCleanupTask?.cancel()
        scratch.windowDragCleanupTask = nil
        if !isDragging {
            let wasHandlingActiveWindowDrag = scratch.isHandlingActiveWindowDrag
            scratch.isHandlingActiveWindowDrag = false
            hoverMonitor?.setExternalMouseDragActive(false)
            scheduleWindowDragCleanup()
            reevaluatePointerInteraction()
            guard wasHandlingActiveWindowDrag else { return }
            handleWindowDragChange(isDragging: false)
            return
        }

        handleWindowDragDisplayChange(windowDrag.cursorDisplayID)
    }

    private func scheduleWindowDragCleanup() {
        scratch.windowDragCleanupTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, !windowDrag.isDragging else { return }
            scratch.windowDragCleanupTask = nil
            dragManager.cancelActivation()
            guard navigationStack.last == .snapZones,
                  !isPinned,
                  !isFileDropTargeted,
                  !isFileDragSessionInProgress else {
                SnapPreviewManager.shared.hidePreview()
                return
            }
            dismissActiveSnapZones()
        }
    }

    private func handleWindowDragDisplayChange(_ displayID: CGDirectDisplayID?) {
        guard windowDrag.isDragging else { return }

        let isOnThisScreen: Bool
        if let displayID {
            isOnThisScreen = displayID == notchDisplayID
        } else {
            isOnThisScreen = cursorIsOnMyScreen
        }

        if !isOnThisScreen {
            dragManager.cancelActivation()
            if navigationStack.last == .snapZones {
                activeSnapZone = nil
                SnapPreviewManager.shared.hidePreview()
            }
            guard scratch.isHandlingActiveWindowDrag else {
                if navigationStack.last == .snapZones { handleWindowDragChange(isDragging: false) }
                return
            }
            scratch.isHandlingActiveWindowDrag = false
            hoverMonitor?.setExternalMouseDragActive(false)
            handleWindowDragChange(isDragging: false)
            return
        }

        guard settings.settings.snapOnWindowDragEnabled,
              !shouldSuppressSnapZoneActivation else { return }
        let mouseLocation = NSEvent.mouseLocation
        let notchScreen = assignedScreen
        let notchScreenFrame = notchScreen?.frame ?? .zero
        let myDisplayID = notchScreen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
        notchLog.info("handleWindowDragDisplayChange: display=\(displayID.map(String.init) ?? "nil") mouse=\(mouseLocation.x),\(mouseLocation.y) myDisplayID=\(myDisplayID.map(String.init) ?? "nil") notchScreenFrame=\(notchScreenFrame.minX),\(notchScreenFrame.minY)-\(notchScreenFrame.maxX),\(notchScreenFrame.maxY)")
        guard !scratch.isHandlingActiveWindowDrag else { return }
        scratch.isHandlingActiveWindowDrag = true
        hoverMonitor?.setExternalMouseDragActive(true)
        handleWindowDragChange(isDragging: true)
    }

    private func handleSnapZoneDismissalChange(_ isDismissed: Bool) {
        guard isDismissed,
              windowDrag.isDragging,
              navigationStack.last == .snapZones else { return }
        dismissActiveSnapZones()
    }

    private func handleSnapZoneBypassModifierChange(_ isPressed: Bool) {
        guard windowDrag.isDragging else { return }

        if isPressed {
            scratch.isHandlingActiveWindowDrag = false
            dragManager.cancelActivation()
            if navigationStack.last == .snapZones {
                dismissActiveSnapZones()
            }
            return
        }

        guard settings.settings.snapOnWindowDragEnabled,
              !windowDrag.isSnapZoneDismissedForCurrentDrag,
              cursorIsOnMyScreen else { return }
        scratch.isHandlingActiveWindowDrag = true
        hoverMonitor?.setExternalMouseDragActive(true)
        handleWindowDragChange(isDragging: true)
    }

    private func updateSpacePlayPauseTap() {
        let wantsTap = (notchState == .hoverExpanded || notchState == .clickExpanded)
            && MusicManager.shared.title?.isEmpty == false
        if scratch.spacePlayPauseTapToken == nil {
            guard wantsTap else { return }
            let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
                | CGEventMask(1 << CGEventType.keyUp.rawValue)
            let ownPID = ProcessInfo.processInfo.processIdentifier
            scratch.spacePlayPauseTapToken = GlobalEventTap.shared.register(
                name: "Notch.spacePlayPause",
                mask: mask,
                priority: EventTapPriority.shortcut
            ) { type, event in
                guard event.getIntegerValueField(.keyboardEventKeycode) == Int64(kVK_Space) else { return .pass }
                let modifiers: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift]
                guard event.flags.intersection(modifiers).isEmpty else { return .pass }
                guard NSWorkspace.shared.frontmostApplication?.processIdentifier != ownPID else { return .pass }
                if type == .keyDown, event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
                    DispatchQueue.main.async { NotchController.toggleMusicPlayback() }
                }
                return .swallow
            }
        }
        if let token = scratch.spacePlayPauseTapToken {
            GlobalEventTap.shared.setEnabled(token, wantsTap)
        }
    }

    private static func toggleMusicPlayback() {
        let music = MusicManager.shared
        music.transientIcon = music.isPlaying ? .paused : .played
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if music.transientIcon == .paused || music.transientIcon == .played {
                music.transientIcon = nil
            }
        }
        Task {
            if music.isPlaying { await music.pause() } else { await music.play() }
        }
    }

    private func startSnapZoneEscapeMonitoring() {
        guard scratch.snapZoneEscapeMonitorToken == nil else { return }
        scratch.snapZoneEscapeMonitorToken = EventMonitorHub.shared.register(for: .keyDown) { event in
            guard event.keyCode == CGKeyCode(kVK_Escape),
                  windowDrag.isDragging,
                  navigationStack.last == .snapZones else { return }
            windowDrag.dismissSnapZonesForCurrentDrag()
            dismissActiveSnapZones()
        }
    }

    private func stopSnapZoneEscapeMonitoring() {
        guard let snapZoneEscapeMonitorToken = scratch.snapZoneEscapeMonitorToken else { return }
        EventMonitorHub.shared.unregister(token: snapZoneEscapeMonitorToken, for: .keyDown)
        self.scratch.snapZoneEscapeMonitorToken = nil
    }

    private func dismissActiveSnapZones() {
        scratch.dragEndCollapseTask?.cancel()
        scratch.dragEndCollapseTask = nil
        dragManager.cancelActivation()
        SnapPreviewManager.shared.hidePreview()
        activeSnapZone = nil
        snapZoneHitRegions = []
        notchDragLocationState.update(nil)
        navigationStack = []
        noteCollapseReason("direct in dismissActiveSnapZones")
        notchState = isLiveActivityActive ? .autoExpanded : .initial
    }

    private func handleMeasuredClickSizeChange(_ newSize: CGSize) {
        handleSizeChange(newSize, for: .clickExpanded)
    }

    private func handleMeasuredAutoSizeChange(_ newSize: CGSize) {
        handleSizeChange(newSize, for: .autoExpanded)
    }

    private func handleSharingVisibilityChange(_ shouldBeHidden: Bool) {
        updateWindowSharingBehavior(shouldBeHidden: shouldBeHidden)
    }

    private func handleLiveActivityContentUpdate() {
        guard notchState == .autoExpanded || notchState == .hoverExpanded else { return }
        let shapeSignature = liveActivityManager.notchShapeSignature
        if shapeSignature != scratch.lastActivityShapeSignature {
            scratch.lastActivityShapeSignature = shapeSignature
            handleStateChange(from: notchState, to: notchState, refreshSize: false)
        } else {
            updateAutoContentSize()
        }
        updateSatellitePresence()
    }

    private func handleSettingsChange(_ runtimeSettings: NotchRuntimeSettings) {
        let newSettings = settings.settings.value
        if let targetScreen = assignedScreen,
           case let newConfig = ResolvedNotchConfiguration(from: newSettings, screen: targetScreen),
           newConfig != config {
            self.config = newConfig
            self.expansionAnimation = newConfig.expandAnimation
            handleStateChange(from: notchState, to: notchState)
        }
        if !runtimeSettings.swipeToHideNotch, completeHideReason == .manualSwipe {
            revealNotchFromCompleteHide()
        }
        evaluateInactiveNotchVisibility()
    }

    private func handleDisplayConfigurationChange() {
        reregisterDisplayKeyedMonitorsIfNeeded()
        if let window = notchWindow, widgetPlane.isConfigured {
            widgetPlane.setDisplayScale(window.backingScaleFactor)
            widgetPlane.setDisplay(of: window)
        }
        guard let targetScreen = assignedScreen else { return }
        let newConfig = ResolvedNotchConfiguration(from: settings.settings.value, screen: targetScreen)
        if newConfig != config {
            self.config = newConfig
            self.expansionAnimation = newConfig.expandAnimation
            handleStateChange(from: notchState, to: notchState)
        }
        syncHostWindowExtent()
        evaluateInactiveNotchVisibility()
    }

    private func reregisterDisplayKeyedMonitorsIfNeeded() {
        let current = notchDisplayID
        guard current != scratch.registeredDisplayID else { return }
        let previous = scratch.registeredDisplayID
        scratch.registeredDisplayID = current
        if let runtimeStateSource {
            TrackpadGestureHandler.shared.register(
                runtimeStateSource,
                displayID: current,
                onSwipe: { dx, dy in
                    self.handleTrackpadSwipe(vector: CGVector(dx: dx, dy: dy))
                },
                onTwoFingerTap: {
                    self.handleTrackpadTwoFingerTap()
                }
            )
        }
        if isManuallyHidden {
            if let previous { HiddenNotchRevealMonitor.shared.stop(displayID: previous) }
            startHiddenNotchSwipeMonitor()
        }
    }

    // MARK: - Subviews
    private func expandedTopReserve(config: ResolvedNotchConfiguration) -> CGFloat {
        config.isFloatingIsland ? 0 : config.initialSize.height
    }

    private func expandedBottomReserve(config: ResolvedNotchConfiguration) -> CGFloat {
        guard config.isFloatingIsland, NotchIslandBar.showsBar(for: currentMode) else { return 0 }
        return NotchIslandBar.reservedHeight
    }

    private func widgetPlaneInputs(config: ResolvedNotchConfiguration) -> NotchWidgetPlaneInputs {
        NotchWidgetPlaneInputs(
            fileDragMode: displayedFileDragMode,
            padding: EdgeInsets(
                top: config.contentTopPadding + expandedTopReserve(config: config),
                leading: config.contentHorizontalPadding,
                bottom: config.contentBottomPadding + expandedBottomReserve(config: config),
                trailing: config.contentHorizontalPadding
            ),
            notchBandHeight: config.initialSize.height,
            displayScale: notchWindow?.backingScaleFactor ?? 2
        )
    }

    private func syncWidgetPlaneState() {
        widgetPlane.state.sync(
            navigationStack: navigationStack,
            activeDropZone: activeDropZone,
            isCalendarHovered: isCalendarHovered
        )
    }

    private func preparedWidgetPlane(config: ResolvedNotchConfiguration) -> NotchWidgetPlane {
        let plane = widgetPlane
        if !plane.isConfigured {
            plane.state.sync(
                navigationStack: navigationStack,
                activeDropZone: activeDropZone,
                isCalendarHovered: isCalendarHovered
            )
            plane.state.onNavigationStackChange = { navigationStack = $0 }
            plane.state.onActiveDropZoneChange = { activeDropZone = $0 }
            plane.state.onCalendarHoverChange = { isCalendarHovered = $0 }
        }
        plane.configure(
            content: {
                widgetEnvironment(AnyView(
                    notchWidget
                        .environmentObject(fileShelfState)
                        .environmentObject(dragState)
                        .environment(\.onActiveSnapZoneChange, { activeSnapZone = $0 })
                        .environment(\.onDropZoneFramesChange, plane.dropZoneFramesHandler(handleDropZoneFramesChange))
                        .environment(\.onSnapZoneHitRegionsChange, plane.snapRegionsHandler { snapZoneHitRegions = $0 })
                        .environmentObject(plane.dragLocation)
                ))
            },
            inputs: widgetPlaneInputs(config: config),
            measuredSize: $measuredClickContentSize,
            outerDragLocation: notchDragLocationState
        )
        return plane
    }

    private func chromePieces(config: ResolvedNotchConfiguration) -> [NotchChromeSlot: NotchChromePiece] {
        let context = NotchExpandedChrome.Context(
            config: config,
            mode: currentMode,
            notchState: notchState,
            barWidth: animatedWidth,
            fixedSpacer: NotchBarSpacerPolicy.hasFixedWidth(settings.settings.notchBarSpacerWidth),
            showRightHUDOverlay: showRightHUDOverlay,
            navigationStack: $navigationStack,
            isPinned: $isPinned,
            iconsLeftWidth: $notchIconsLeftWidth,
            iconsRightWidth: $notchIconsRightWidth,
            iconsIntrinsicWidth: notchIconsIntrinsicWidth,
            islandBarItems: config.isFloatingIsland ? islandBarItems(config: config) : [],
            onPin: { pinned in
                if pinned {
                    scratch.collapseTask?.cancel()
                    scratch.isCollapseTimerActive = false
                }
            },
            onOpenBlipHub: openBlipHub,
            onOpenAgentS: {
                openBlipHub()
                navigationStack.append(.agentS)
            }
        )
        var pieces = NotchExpandedChrome.pieces(context)
        for (slot, piece) in pieces {
            var wrapped = piece
            wrapped.view = widgetEnvironment(piece.view)
            pieces[slot] = wrapped
        }
        return pieces
    }

    // MARK: - Setup and Teardown
    private func setupMonitors() {
        (notchWindow as? DynamicFocusWindow)?.monitorsTornDown = false
        if let runtimeStateSource {
            NotchRuntimeState.shared.register(
                source: runtimeStateSource,
                isExpanded: notchState != .initial && !isManuallyHidden
            )
        }
        dragManager.startMonitoring()

        scratch.registeredDisplayID = notchDisplayID
        if let runtimeStateSource {
            MenuBarInteractionManager.shared.setSuspended(isInteractive, by: runtimeStateSource)
            TrackpadGestureHandler.shared.register(
                runtimeStateSource,
                displayID: notchDisplayID,
                onSwipe: { dx, dy in
                    self.handleTrackpadSwipe(vector: CGVector(dx: dx, dy: dy))
                },
                onTwoFingerTap: {
                    self.handleTrackpadTwoFingerTap()
                }
            )
        }

        if scratch.fileDropFlowObserver == nil {
            scratch.fileDropFlowObserver = NotificationCenter.default.addObserver(
                forName: .fileDropFlowCompleted,
                object: nil,
                queue: .main
            ) { _ in
                guard self.scratch.pendingFileDropSequences.isEmpty,
                      self.scratch.completedFileDrops.isEmpty else { return }
                self.scratch.awaitingDropCompletion = false
                if self.notchState == .clickExpanded,
                   !self.isPinned,
                   !self.isFileDragSessionInProgress {
                    self.startWidgetSwitchProtection()
                }
            }
        }

        startNotchInteractionMonitoring()
        startSnapZoneEscapeMonitoring()
        (notchWindow as? DynamicFocusWindow)?.hostSizer.attach(morphEngine)
        (notchWindow as? DynamicFocusWindow)?.hostSizer.onFrameChange = {
            hoverMonitor?.invalidatePlacement()
            updateMouseEventHandling(isInteractive: isInteractive)
        }
        (notchWindow as? DynamicFocusWindow)?.onDisplayConfigurationChange = {
            handleDisplayConfigurationChange()
        }
        (notchWindow as? DynamicFocusWindow)?.onTeardown = {
            teardownMonitors()
        }
        syncHostWindowExtent()
        updateMouseEventHandling(isInteractive: isInteractive)
        updateWindowSharingBehavior(shouldBeHidden: shouldHideWindowForSharing)
        scratch.lastActivityShapeSignature = liveActivityManager.notchShapeSignature
        evaluateInactiveNotchVisibility()
    }

    private func teardownMonitors() {
        if let window = notchWindow as? DynamicFocusWindow {
            guard !window.monitorsTornDown else { return }
            window.monitorsTornDown = true
        }
        if let runtimeStateSource {
            NotchRuntimeState.shared.unregister(source: runtimeStateSource)
        }
        dragManager.stopMonitoring()
        if let runtimeStateSource {
            TrackpadGestureHandler.shared.unregister(runtimeStateSource)
        }
        stopHiddenNotchSwipeMonitor()
        scratch.inactiveRehideTask?.cancel()
        if let fileDropFlowObserver = scratch.fileDropFlowObserver {
            NotificationCenter.default.removeObserver(fileDropFlowObserver)
            self.scratch.fileDropFlowObserver = nil
        }
        scratch.collapseTask?.cancel()
        scratch.dragEndCollapseTask?.cancel()
        scratch.dragEndCollapseTask = nil
        scratch.dropZoneResolutionTask?.cancel()
        scratch.dropZoneResolutionTask = nil
        cancelWidgetSwitchProtection()
        stopSnapZoneEscapeMonitoring()
        if let spacePlayPauseTapToken = scratch.spacePlayPauseTapToken {
            GlobalEventTap.shared.unregister(spacePlayPauseTapToken)
            self.scratch.spacePlayPauseTapToken = nil
        }
        stopNotchInteractionMonitoring()
        (notchWindow as? DynamicFocusWindow)?.hostSizer.onFrameChange = nil
        (notchWindow as? DynamicFocusWindow)?.onDisplayConfigurationChange = nil
        (notchWindow as? DynamicFocusWindow)?.onTeardown = nil
        if let runtimeStateSource {
            MenuBarInteractionManager.shared.setSuspended(false, by: runtimeStateSource)
        }
    }

    // MARK: - Profiling hook

    private static let debugHookPublisher: AnyPublisher<Notification, Never> = {
        #if DEBUG
        let enabled = true
        #else
        let enabled = ProcessInfo.processInfo.environment["SAPPHIRE_NOTCH_DEBUG_HOOKS"] == "1"
        #endif
        guard enabled else {
            return Empty().eraseToAnyPublisher()
        }
        return DistributedNotificationCenter.default()
            .publisher(for: Notification.Name("com.cshariq.sapphire.debug.notch"))
            .receive(on: RunLoop.main)
            .eraseToAnyPublisher()
    }()

    private func debugHookAction(_ raw: String?) -> String? {
        guard let raw, raw.hasPrefix("@"), let colon = raw.firstIndex(of: ":") else { return raw }
        let target = raw[raw.index(after: raw.startIndex)..<colon].split(separator: "/")
        guard let pid = target.first.flatMap({ Int32($0) }), pid == ProcessInfo.processInfo.processIdentifier else { return nil }
        if target.count > 1, let display = CGDirectDisplayID(target[1]), display != notchDisplayID { return nil }
        return String(raw[raw.index(after: colon)...])
    }

    private func handleDebugHook(_ raw: String?) {
        let action = debugHookAction(raw)
        switch action {
        case "open": handleTap()
        case "openDefault":
            guard let config, notchState != .clickExpanded else { return }
            expansionAnimation = config.expandAnimation
            measuredClickContentSize = .zero
            navigationStack = [.defaultWidgets]
            notchState = .clickExpanded
        case "close": notchState = isLiveActivityActive ? .autoExpanded : .initial
        case "hoverIn": handleHover(hovering: true)
        case "hoverOut": handleHover(hovering: false)
        case "navigateMusic": navigationStack.append(.musicPlayer)
        case "back": if navigationStack.count > 1 { navigationStack.removeLast() }
        #if DEBUG
        case "capsLockOn": liveActivityManager.debugSimulateCapsLock(true)
        case "capsLockOff": liveActivityManager.debugSimulateCapsLock(false)
        case "lockOn": (NSApp.delegate as? AppDelegate)?.debugSimulateLockScreen(true)
        case "lockOff": (NSApp.delegate as? AppDelegate)?.debugSimulateLockScreen(false)
        case let action? where action.hasPrefix("navigate:"):
            let modes: [String: NotchWidgetMode] = [
                "music": .musicPlayer, "fileShelf": .fileShelf, "notes": .notesPlayer,
                "clipboard": .clipboardPlayer, "multiAudio": .multiAudio, "focus": .focusSessionDetailView,
                "continuity": .continuityDetail, "battery": .batteryDetailView, "weather": .weatherPlayer,
                "calendar": .calendarPlayer, "queue": .musicQueueAndPlaylists, "devices": .musicDevices,
            ]
            guard let mode = modes[String(action.dropFirst("navigate:".count))] else { return }
            navigationStack.append(mode)
        case "satellites:on", "satellites:off":
            settings.settings.showLiveActivitySatellites = action == "satellites:on"
        case let action? where action.hasPrefix("satelliteLimit:"):
            settings.settings.liveActivitySatelliteLimit = Int(action.dropFirst("satelliteLimit:".count)) ?? 2
        case let action? where action.hasPrefix("desktop:"):
            liveActivityManager.debugSimulateDesktopChange(to: Int(action.dropFirst("desktop:".count)) ?? 1)
        case let action? where action.hasPrefix("satelliteFill:"):
            liveActivityManager.debugFillSatellites(Int(action.dropFirst("satelliteFill:".count)) ?? 0)
        case "notchlessStyle:island", "notchlessStyle:notch", "notchlessStyle:default":
            guard let screen = assignedScreen, !NotchConfiguration.hasHardwareNotch(on: screen) else { return }
            let key = screen.displayIdentifier
            if action == "notchlessStyle:default" {
                settings.settings.perDisplayFloatingIsland.removeValue(forKey: key)
            } else {
                settings.settings.perDisplayFloatingIsland[key] = action == "notchlessStyle:island"
            }
        #endif
        case "dumpLayers": dumpNotchLayerTree()
        case "dumpTracking": dumpTrackingAreas()
        case "snapshot": snapshotNotchWindow()
        case let action? where action.hasPrefix("profile:"):
            guard let profile = AnimationProfile(rawValue: String(action.dropFirst("profile:".count))) else { return }
            settings.settings.animationProfile = profile
        default: break
        }
    }

    private func snapshotNotchWindow() {
        guard let window = notchWindow,
              let image = CGWindowListCreateImage(.null, .optionIncludingWindow, CGWindowID(window.windowNumber), [.boundsIgnoreFraming, .bestResolution]) else { return }
        let rep = NSBitmapImageRep(cgImage: image)
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("sapphire-notch-\(ProcessInfo.processInfo.processIdentifier).png")
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }

    private func dumpNotchLayerTree() {
        guard let root = notchWindow?.contentView?.layer else { return }
        var lines: [String] = [
            "state=\(notchState) stack=\(navigationStack) target=\(animatedWidth)x\(animatedHeight)"
                + " drawn=\(morphEngine.currentFrame.values.size) measuredClick=\(measuredClickContentSize)"
                + " layout=\(clickContentLayoutSize) detached=\(planeMorphDetached) planeOut=\(isAnimatingPlaneOut)"
                + " autoSize=\(measuredAutoContentSize) radii=\(animatedCornerRadius),\(animatedBottomCornerRadius)",
        ]
        func walk(_ layer: CALayer, _ depth: Int) {
            let delegate = layer.delegate.map { String(describing: type(of: $0)) } ?? "-"
            let contents = layer.contents.map { String(describing: type(of: $0)) } ?? "nil"
            let b = layer.bounds
            var state = " opacity=\(layer.opacity)"
            let shown = layer.presentation() ?? layer
            if shown.opacity != layer.opacity { state += " shownOpacity=\(shown.opacity)" }
            state += " origin=\(Int(b.minX)),\(Int(b.minY)) pos=\(Int(layer.position.x)),\(Int(layer.position.y))"
            if shown.position != layer.position { state += " shownPos=\(Int(shown.position.x)),\(Int(shown.position.y))" }
            if layer.isHidden { state += " HIDDEN" }
            if let filters = layer.filters, !filters.isEmpty {
                let described = filters.map { filter -> String in
                    let object = filter as AnyObject
                    let name = (object.value(forKey: "name") as? String) ?? "?"
                    let radius = (object.value(forKey: "inputRadius") as? NSNumber)?.doubleValue ?? -1
                    return "\(name):\(radius)"
                }
                state += " filters=\(described)"
            }
            if !CATransform3DIsIdentity(layer.sublayerTransform) { state += " sublayerTransform(m11=\(layer.sublayerTransform.m11))" }
            if !CATransform3DIsIdentity(layer.transform) { state += " transform(m11=\(layer.transform.m11))" }
            if layer.contents != nil || layer.contentsScale != 1 { state += " contentsScale=\(layer.contentsScale)" }
            if layer.shouldRasterize { state += " RASTER(\(layer.rasterizationScale))" }
            if let keys = layer.animationKeys(), !keys.isEmpty { state += " anims=\(keys)" }
            lines.append(String(repeating: "  ", count: depth)
                + "\(type(of: layer)) delegate=\(delegate) size=\(Int(b.width))x\(Int(b.height)) contents=\(contents)"
                + " drawsAsync=\(layer.drawsAsynchronously) format=\(layer.contentsFormat.rawValue) needsDisplay=\(layer.needsDisplay())"
                + state)
            for sub in layer.sublayers ?? [] where depth < 40 { walk(sub, depth + 1) }
        }
        walk(root, 0)
        let name = "sapphire-notch-layers-\(ProcessInfo.processInfo.processIdentifier)-\(notchDisplayID.map(String.init) ?? "unknown").txt"
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(name)
        try? lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    private func dumpTrackingAreas() {
        var lines: [String] = []
        func flag(_ window: NSWindow, _ name: String) -> String {
            let selector = NSSelectorFromString(name)
            guard window.responds(to: selector) else { return "?" }
            typealias Getter = @convention(c) (AnyObject, Selector) -> Bool
            return String(unsafeBitCast(window.method(for: selector), to: Getter.self)(window, selector))
        }
        for window in NSApp.windows {
            lines.append(
                "WINDOW \(type(of: window)) #\(window.windowNumber) frame=\(window.frame) level=\(window.level.rawValue)"
                + " visible=\(window.isVisible) ignoresMouse=\(window.ignoresMouseEvents)"
                + " acceptsMoved=\(window.acceptsMouseMovedEvents) key=\(window.isKeyWindow)"
                + " cursorRects=\(window.areCursorRectsEnabled)"
                + " movedListeners=\(flag(window, "_hasMouseMovedListeners"))"
                + " movesInBackground=\(flag(window, "_wantsMouseMoveEventsInBackground"))"
            )
            guard let root = window.contentView?.superview ?? window.contentView else { continue }
            func walk(_ view: NSView, _ depth: Int) {
                for area in view.trackingAreas {
                    let local = area.options.contains(.inVisibleRect) ? view.visibleRect : area.rect
                    let screen = window.convertToScreen(view.convert(local, to: nil))
                    let owner = area.owner.map { String(String(describing: type(of: $0)).prefix(60)) } ?? "-"
                    lines.append(
                        String(repeating: "  ", count: depth)
                        + "\(String(String(describing: type(of: view)).prefix(80))) hidden=\(view.isHiddenOrHasHiddenAncestor)"
                        + " area=\(screen.integral) options=0x\(String(area.options.rawValue, radix: 16)) owner=\(owner)"
                    )
                }
                for sub in view.subviews where depth < 60 { walk(sub, depth + 1) }
            }
            walk(root, 1)
        }
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("sapphire-tracking.txt")
        try? lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - Event Handlers
    private func handleTap() {
        #if DEBUG
        NSLog("CLICK-TRACE handleTap state=%@ hidden=%d locked=%d", String(describing: notchState), isManuallyHidden ? 1 : 0, shouldBlockNotchExpansionWhileLocked ? 1 : 0)
        #endif
        guard !isManuallyHidden else { return }
        guard !shouldBlockNotchExpansionWhileLocked else { return }
        guard let config = config else { return }
        if notchState == .clickExpanded { return }

        let flags = NSEvent.modifierFlags
        if flags.contains(.command) {
            scratch.collapseTask?.cancel()
            scratch.isCollapseTimerActive = false
            measuredClickContentSize = .zero
            navigationStack = [.defaultWidgets]
            notchState = .clickExpanded
            return
        }

        scratch.collapseTask?.cancel()
        scratch.isCollapseTimerActive = false
        if isPinned { return }

        let activityType = liveActivityManager.currentActivity
        if (notchState == .autoExpanded || notchState == .hoverExpanded) {
            let initiateWidgetView: (NotchWidgetMode) -> Void = { mode in
                self.measuredClickContentSize = .zero
                self.navigationStack = [mode]
                self.notchState = .clickExpanded
            }
            if activityType == .music, settings.settings.musicOpenOnClick { initiateWidgetView(.musicPlayer); return }
            if activityType == .weather || activityType == .persistentWeather, settings.settings.weatherOpenOnClick { initiateWidgetView(.weatherPlayer); return }
            if activityType == .sports, settings.settings.sportsOpenOnClick, PremiumGate.hasAccess(.sportsWidget) { initiateWidgetView(.sportsPlayer); return }
            if activityType == .finance, settings.settings.financeOpenOnClick, PremiumGate.hasAccess(.financeWidget) { initiateWidgetView(.financePlayer); return }
            if activityType == .calendar, settings.settings.calendarOpenOnClick { initiateWidgetView(.calendarPlayer); return }
            if activityType == .fileShelf, settings.settings.clickToOpenFileShelf { initiateWidgetView(.fileShelf); return }
            if activityType == .timer, settings.settings.clickToShowTimerView { initiateWidgetView(.timerDetailView); return }
            if activityType == .continuity { initiateWidgetView(.continuityDetail); return }
            if activityType == .continuityExternal { initiateWidgetView(.continuityActivityDetail); return }
            if activityType == .fileProgress, settings.settings.fileProgressOpenOnClick,
               !FileProgressTracker.shared.transfers.isEmpty { initiateWidgetView(.fileProgressDetail); return }
            if activityType == .appActivity { initiateWidgetView(.appActivityDetail); return }
            if activityType == .devActivity, settings.settings.devActivityOpenOnClick { initiateWidgetView(.devActivityDetail); return }
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
            } else if settings.settings.rememberLastMenu, let savedStack = settings.lastNotchNavigationStack, !savedStack.isEmpty {
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

    private func receivePointerHover(_ hovering: Bool) {
        if hovering {
            scratch.pendingHoverExit?.cancel()
            scratch.pendingHoverExit = nil
            if !isHovered { handleHover(hovering: true) }
            return
        }
        guard isHovered, scratch.pendingHoverExit == nil else { return }
        noteCollapseReason("hover exit scheduled")
        let exit = DispatchWorkItem {
            self.scratch.pendingHoverExit = nil
            guard self.isHovered else { return }
            self.noteCollapseReason("hover exit fired")
            handleHover(hovering: false)
        }
        scratch.pendingHoverExit = exit
        let grace = notchState == .clickExpanded ? Self.expandedHoverExitGrace : Self.hoverExitGrace
        DispatchQueue.main.asyncAfter(deadline: .now() + grace, execute: exit)
    }

    private static let hoverExitGrace: TimeInterval = 0.12
    private static let expandedHoverExitGrace: TimeInterval = 0.3

    private func handleHover(hovering: Bool) {
        guard !isManuallyHidden else { return }
        guard let config = config else { return }
        self.isHovered = hovering

        if let runtimeStateSource {
            TrackpadGestureHandler.shared.setActive(hovering, for: runtimeStateSource)
        }
        if !hovering {
            scratch.suppressHoverAfterReveal = false
            cancelHoverExpandTask()
        }

        if hovering {
            guard !scratch.suppressHoverAfterReveal else { return }
            guard !shouldBlockNotchExpansionWhileLocked else { return }
            scratch.collapseTask?.cancel()
            scratch.isCollapseTimerActive = false
            let activityType = liveActivityManager.currentActivity
            if activityType == .music, settings.settings.musicOpenOnClick {
                MusicManager.shared.prewarmDetailPlayer()
            }

            if shouldSuppressHoverExpansionForLiveActivity {
                cancelHoverExpandTask()
                return
            }

            if activityType == .fileShelf, settings.settings.hoverToOpenFileShelf {
                cancelHoverExpandTask()
                if notchState != .clickExpanded {
                    navigationStack = [.fileShelf]
                    notchState = .clickExpanded
                }
        } else if settings.settings.expandOnHover && !isFullViewActivity && !isInteractiveLiveActivity {
                if notchState != .clickExpanded {
                    self.expansionAnimation = config.expandAnimation
                    var targetStack: [NotchWidgetMode]
                    if settings.settings.hoverToOpenFileShelf && !FileShelfManager.shared.files.isEmpty {
                        targetStack = [.fileShelf]
                    } else if settings.settings.rememberLastMenu, let savedStack = settings.lastNotchNavigationStack, !savedStack.isEmpty {
                        targetStack = savedStack.map { $0.toNotchWidgetMode() }
                    } else {
                        targetStack = [.defaultWidgets]
                    }
                    navigationStack = targetStack
                    let delay = settings.settings.expandOnHoverDelay
                    if delay > 0 {
                        cancelHoverExpandTask()
                        scratch.hoverExpandTask = Task { @MainActor in
                            do {
                                try await Task.sleep(for: .milliseconds(Int(delay * 1000)))
                            } catch { return }
                            guard !Task.isCancelled, self.isHovered else { return }
                            guard !self.dragManager.isDraggingInActivationZone else { return }
                            guard self.notchState != .clickExpanded else { return }
                            guard settings.settings.expandOnHover else { return }
                            guard !self.isInteractiveLiveActivity else { return }
                            guard !self.shouldSuppressHoverExpansionForLiveActivity else { return }
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

    private func handleActivityChange(_: ActivityType) {
        let newActivity = liveActivityManager.effectiveActivity(onDisplayID: notchDisplayID)
        if newActivity != .none {
            scratch.inactiveHideUserOverride = false
            if completeHideReason == .inactive {
                revealNotchFromCompleteHide()
            } else if completeHideReason == .manualSwipe {
                return
            }
        } else if completeHideReason == .manualSwipe {
            return
        } else if completeHideReason == .inactive {
            return
        }

        guard notchState != .clickExpanded, let config = config else {
            evaluateInactiveNotchVisibility()
            return
        }

        if newActivity != .none {
            scratch.activitySwitchBlurWindowEnd = Date().addingTimeInterval(Self.activitySwitchBlurWindow)
            scratch.blurRemovalTask?.cancel()
            scratch.blurRemovalTask = nil
            let appearsFromNotch = notchState == .initial && config.couplesContentToMorph
            let switchesAsRegions: Bool = {
                if case .standard = liveActivityManager.activityContent { return true }
                return false
            }()
            if reduceMotion || appearsFromNotch || switchesAsRegions {
                effects.update { $0.activityBlurRadius = 0; $0.activityContentScale = 1.0 }
            } else {
                effects.update { $0.activityBlurRadius = config.activityBlurRadiusMax; $0.activityContentScale = 0.9 }
                DispatchQueue.main.async {
                    self.effects.update(config.focusPullAnimation) {
                        $0.activityBlurRadius = 0
                        $0.activityContentScale = 1.0
                    }
                }
            }
        }

        let previousState = notchState
        notchState = newActivity != .none ? .autoExpanded : .initial
        if previousState == notchState {
            handleStateChange(from: notchState, to: notchState, refreshSize: false)
            scratch.lastActivityShapeSignature = liveActivityManager.notchShapeSignature
        }
        evaluateInactiveNotchVisibility()
    }

    private func handleFullScreenDisplayChange() {
        handleActivityChange(liveActivityManager.currentActivity)
        evaluateInactiveNotchVisibility()
    }

    private func handleStateChange(from oldState: NotchState, to newState: NotchState, refreshSize: Bool = true) {
        guard let config = config else { return }
        if isManuallyHidden {
            animatedWidth = 0
            animatedHeight = 0
            setWindowHidden(true)
            return
        }

        let isContentUpdate = oldState == newState
        if oldState == .clickExpanded && newState != .clickExpanded {
            expansionAnimation = config.expandAnimation
        }
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
            if isContentUpdate && refreshSize {
                refreshAnimatedSizeForCurrentState()
            }
        }

        if isContentUpdate { return }

        let transition = scratch.stateTransitionGeneration &+ 1
        scratch.stateTransitionGeneration = transition

        if newState == .clickExpanded {
            scratch.clickExpandedOpenedAt = Date()
        }

        if newState != .clickExpanded {
            CircleToSearchManager.shared.endResultsPresentation()
        }

        if oldState == .clickExpanded && newState != .clickExpanded && config.couplesContentToMorph && !reduceMotion {
            planeMorphDetached = false
            isAnimatingPlaneOut = true
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.fluidCarryDuration) {
                guard self.scratch.stateTransitionGeneration == transition else { return }
                self.isAnimatingPlaneOut = false
            }
        }

        if oldState == .clickExpanded && newState != .clickExpanded {
            measuredClickContentSize = .zero
            if navigationStack.contains(.mirrorPlayer) {
                navigationStack.removeAll { $0 == .mirrorPlayer }
                if navigationStack.isEmpty {
                    navigationStack = [.defaultWidgets]
                }
            }
            if let mirror = MirrorCameraManager.existing, mirror.isLive {
                mirror.teardown()
            }
        }

        switch newState {
        case .initial:
            let wasShowingActivity = (oldState == .autoExpanded || oldState == .hoverExpanded)
            if wasShowingActivity { isAnimatingActivityOut = true }
            if !(wasShowingActivity && config.couplesContentToMorph && !reduceMotion) {
                self.canRenderAutoContent = false
            }
            scratch.collapseTask?.cancel(); scratch.isCollapseTimerActive = false
            cancelHoverExpandTask()
            cancelWidgetSwitchProtection()

            let idleMorphAnimation = (oldState == .clickExpanded)
                ? config.collapseAnimation
                : config.activityToActivityAnimation

            let fluidOut = wasShowingActivity && config.couplesContentToMorph && !reduceMotion
            let setsActivityEffect = wasShowingActivity && !reduceMotion && !fluidOut
            withAnimation(idleMorphAnimation) {
                animatedWidth = config.initialSize.width; animatedHeight = config.initialSize.height
                isPinned = false
            }
            effects.update(idleMorphAnimation) {
                $0.shadowOpacity = 0
                if wasShowingActivity && !fluidOut {
                    $0.activityOpacity = 0
                    if setsActivityEffect { $0.activityBlurRadius = 20; $0.activityContentScale = 0.9 }
                }
                $0.animatedContentScale = 1.0
            }
            syncHostWindowExtent()

            let effect = setsActivityEffect ? claimActivityEffect() : scratch.activityEffectGeneration
            DispatchQueue.main.asyncAfter(deadline: .now() + config.activityAnimationOutDelay) {
                guard self.notchState == .initial, self.scratch.stateTransitionGeneration == transition else { return }
                if wasShowingActivity {
                    self.isAnimatingActivityOut = false
                    self.canRenderAutoContent = false
                }
                guard self.scratch.activityEffectGeneration == effect else { return }
                self.effects.update { $0.activityBlurRadius = 0; $0.activityContentScale = 1.0 }
            }

        case .hoverExpanded:
            isAnimatingActivityOut = false; self.canRenderAutoContent = true

            let scale = activeScaleFactor
            let rawWidth = isLiveActivityActive ? measuredAutoContentSize.width * scale : config.hoverExpandedSize.width
            let rawHeight = isLiveActivityActive ? measuredAutoContentSize.height * scale : config.hoverExpandedSize.height
            let target = snappedNotchTarget(width: rawWidth, height: rawHeight, config: config)

            withAnimation(config.hoverAnimation) {
                animatedWidth = target.width; animatedHeight = target.height
            }
            effects.update(config.hoverAnimation) {
                if isLiveActivityActive { $0.activityOpacity = 1 }
                $0.animatedContentScale = scale
                $0.shadowOpacity = 1
            }

        case .clickExpanded:
            isAnimatingActivityOut = false; self.canRenderAutoContent = false
            let followsMorph = config.couplesContentToMorph && !reduceMotion
            isAnimatingPlaneOut = false
            if followsMorph { planeMorphDetached = false }

            if followsMorph, let size = scratch.expandedSizeByMode[currentMode] {
                setClickContentLayoutSize(size)
                withAnimation(self.expansionAnimation) {
                    animatedWidth = size.width
                    animatedHeight = size.height
                }
                syncHostWindowExtent()
            }
            let opensFromActivity = isLiveActivityActive && (oldState == .autoExpanded || oldState == .hoverExpanded)
            if followsMorph && opensFromActivity {
                effects.update { $0.activityOpacity = 1; $0.activityBlurRadius = 0; $0.activityContentScale = 1 }
            }
            if followsMorph {
                effects.update(self.expansionAnimation) { $0.shadowOpacity = 1 }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) {
                    guard self.notchState == .clickExpanded, self.scratch.stateTransitionGeneration == transition else { return }
                    self.planeMorphDetached = true
                }
            } else {
                effects.update { $0.shadowOpacity = 0 }
            }

            if !followsMorph && isLiveActivityActive && (oldState == .autoExpanded || oldState == .hoverExpanded) {
                effects.update(config.activityBlurAnimation) {
                    $0.activityOpacity = 0
                    if !reduceMotion { $0.activityBlurRadius = config.activityBlurRadiusMax; $0.activityContentScale = 1.05 }
                }
            }

            if !followsMorph { effects.update(self.expansionAnimation) { $0.activityOpacity = 0 } }
            let setsActivityEffect = !followsMorph && isLiveActivityActive
                && (oldState == .autoExpanded || oldState == .hoverExpanded)
                && !reduceMotion
            let effect = setsActivityEffect ? claimActivityEffect() : scratch.activityEffectGeneration
            DispatchQueue.main.asyncAfter(deadline: .now() + config.contentUpdateDelay) {
                guard self.scratch.activityEffectGeneration == effect else { return }
                self.effects.update(config.focusPullAnimation) { $0.activityContentScale = 1.0 }
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.expansionAnimation = config.expandAnimation
            }

            if !followsMorph {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    guard self.notchState == .clickExpanded, self.scratch.stateTransitionGeneration == transition else { return }
                    self.effects.update(.notchMorph(.timing(.easeIn, duration: 0.2))) { $0.shadowOpacity = 1 }
                }
            }

        case .autoExpanded:
            isAnimatingActivityOut = false
            let isCollapsingFromClick = (oldState == .clickExpanded)
            let fluidCollapse = isCollapsingFromClick && config.couplesContentToMorph && !reduceMotion
            if fluidCollapse {
                cancelWidgetSwitchProtection()
                self.canRenderAutoContent = true
                effects.update { $0.activityOpacity = 1; $0.activityBlurRadius = 0; $0.activityContentScale = 1 }
            } else if isCollapsingFromClick {
                cancelWidgetSwitchProtection()
                self.canRenderAutoContent = false
                if !reduceMotion {
                    effects.update(config.blurAnimation) { $0.activityContentScale = 0.92; $0.activityBlurRadius = config.activityBlurRadiusMax * 1.5 }
                }
            } else {
                self.canRenderAutoContent = true
                effects.update { $0.activityOpacity = 1 }
            }
            let animationToUse = isCollapsingFromClick ? config.collapseAnimation : config.activityToActivityAnimation

            effects.update { $0.shadowOpacity = 0 }

            let target = snappedNotchTarget(
                width: measuredAutoContentSize.width,
                height: measuredAutoContentSize.height,
                config: config
            )
            withAnimation(animationToUse) {
                animatedWidth = target.width
                animatedHeight = target.height
            }
            effects.update(animationToUse) { $0.animatedContentScale = 1.0 }

            let effect = (isCollapsingFromClick && !reduceMotion) ? claimActivityEffect() : scratch.activityEffectGeneration
            if !fluidCollapse { DispatchQueue.main.asyncAfter(deadline: .now() + config.activitySizeChangeDelay) {
                guard self.scratch.activityEffectGeneration == effect else { return }
                self.effects.update(config.blurRemovalAnimation) { $0.activityBlurRadius = 0; $0.activityContentScale = 1.0 }
            } }
            if isCollapsingFromClick && !fluidCollapse {
                DispatchQueue.main.asyncAfter(deadline: .now() + config.autoContentRenderDelay) {
                    guard self.notchState == .autoExpanded, self.scratch.stateTransitionGeneration == transition else { return }
                    self.canRenderAutoContent = true
                    self.effects.update(config.activityOpacityAnimation) { $0.activityOpacity = 1 }
                }
            }
        }
        updateMouseEventHandling(isInteractive: isInteractive)
    }

    private func claimActivityEffect() -> UInt64 {
        let next = scratch.activityEffectGeneration &+ 1
        scratch.activityEffectGeneration = next
        return next
    }

    private func refreshAnimatedSizeForCurrentState() {
        guard let config = config else { return }
        switch notchState {
        case .initial:
            animatedWidth = config.initialSize.width
            animatedHeight = config.initialSize.height
        case .autoExpanded:
            let target = snappedNotchTarget(
                width: measuredAutoContentSize.width,
                height: measuredAutoContentSize.height,
                config: config
            )
            animatedWidth = target.width
            animatedHeight = target.height
        case .hoverExpanded:
            let scale = activeScaleFactor
            let rawWidth = isLiveActivityActive ? measuredAutoContentSize.width * scale : config.hoverExpandedSize.width
            let rawHeight = isLiveActivityActive ? measuredAutoContentSize.height * scale : config.hoverExpandedSize.height
            let target = snappedNotchTarget(width: rawWidth, height: rawHeight, config: config)
            animatedWidth = target.width
            animatedHeight = target.height
        case .clickExpanded:
            break
        }
    }

    private func snappedNotchTarget(width: CGFloat, height: CGFloat, config: ResolvedNotchConfiguration) -> CGSize {
        NotchDisplayMetrics.snappedSize(
            atLeast: CGSize(width: max(width, config.initialSize.width), height: max(height, config.initialSize.height)),
            scale: config.displayScale
        )
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
            MirrorCameraManager.existing?.teardown()
        }

        let openedWithThisStack = CACurrentMediaTime() - scratch.expandedStageSince < 0.1
        if notchState == .clickExpanded && oldStack != newStack && !planeMorphDetached && !openedWithThisStack {
            planeMorphDetached = true
        }

        if notchState == .clickExpanded && oldStack != newStack {
            let panelJustOpened = Date().timeIntervalSince(scratch.clickExpandedOpenedAt) < 0.1
            if !panelJustOpened {
                self.expansionAnimation = config.widgetSwitchAnimation
                startWidgetSwitchProtection()
            }
            if config.isFloatingIsland {
                withAnimation(config.widgetSwitchAnimation) { updateRadiiForCurrentState(state: .clickExpanded) }
            }
        }

        if notchState == .clickExpanded {
            if settings.settings.rememberLastMenu {
                let restorableStack = newStack.compactMap { toRestorableMenu(mode: $0) }
                if !restorableStack.isEmpty {
                    settings.lastNotchNavigationStack = restorableStack
                }
            }
        }
    }

    private func handleFileDrop(urls: [URL], at screenLocation: NSPoint) -> Bool {
        let fileManager = FileManager.default
        let readableURLs = urls.filter {
            $0.isFileURL
                && fileManager.fileExists(atPath: $0.path)
                && fileManager.isReadableFile(atPath: $0.path)
        }
        guard !readableURLs.isEmpty else { return false }

        let finalLocation = updateNotchDragLocation(from: screenLocation)
        let fallbackDropZone: DropZone?
        let wasDraggedFromShelf = isFileDragSessionInProgress
            ? activeFileDragIsFromShelf
            : dragState.isDraggingFromShelf
        fallbackDropZone = activeDropZone ?? (wasDraggedFromShelf ? nil : .shelf)
        let accessGrants = readableURLs.map { url in
            (url: url, shouldStopAccessing: url.startAccessingSecurityScopedResource())
        }

        let sequence = scratch.nextFileDropSequence
        scratch.nextFileDropSequence &+= 1
        scratch.pendingFileDropSequences.insert(sequence)
        scratch.awaitingDropCompletion = true

        Task {
            let copiedURLs = accessGrants.map { grant -> URL in
                if grant.shouldStopAccessing { grant.url.stopAccessingSecurityScopedResource() }
                return grant.url
            }

            await MainActor.run {
                self.scratch.pendingFileDropSequences.remove(sequence)
                self.scratch.completedFileDrops[sequence] = FileDropResult(
                    fallbackZone: fallbackDropZone,
                    finalLocation: finalLocation,
                    copiedURLs: copiedURLs,
                    wasDraggedFromShelf: wasDraggedFromShelf
                )
                self.routeCompletedFileDropsInOrder()
            }
        }
        return true
    }

    private func routeCompletedFileDropsInOrder(allowUnresolvedTarget: Bool = false) {
        guard !isFileDragSessionInProgress else {
            scratch.awaitingDropCompletion = !scratch.pendingFileDropSequences.isEmpty || !scratch.completedFileDrops.isEmpty
            return
        }

        while let result = scratch.completedFileDrops.removeValue(forKey: scratch.nextFileDropSequenceToRoute) {
            guard !result.copiedURLs.isEmpty else {
                scratch.nextFileDropSequenceToRoute &+= 1
                continue
            }

            let resolvedZone: DropZone?
            if let finalLocation = result.finalLocation, !dropZoneFrames.isEmpty {
                resolvedZone = SnapZoneHitTesting.nearest(
                    dropZoneFrames.map { (zone: $0.key, frame: $0.value) },
                    to: finalLocation
                ) { $0.frame }?.zone
                    ?? result.fallbackZone
            } else if result.finalLocation != nil, !allowUnresolvedTarget {
                scratch.completedFileDrops[scratch.nextFileDropSequenceToRoute] = result
                scheduleDropZoneResolutionFallback()
                break
            } else {
                resolvedZone = result.fallbackZone
            }

            scratch.nextFileDropSequenceToRoute &+= 1
            dragState.didJustDrop = true
            NotificationCenter.default.post(name: .fileDropFlowCompleted, object: nil)

            switch resolvedZone {
            case .shelf:
                FileShelfManager.shared.addFiles(from: result.copiedURLs)
                navigationStack = [.fileShelf]
            case .airdrop:
                SharingManager.shared.share(items: result.copiedURLs, via: .sendViaAirDrop)
                navigationStack = []
            case .device(let peerID):
                ContinuityManager.shared.sendFiles(result.copiedURLs, toPeerID: peerID)
                navigationStack = []
            case nil:
                if result.wasDraggedFromShelf {
                    navigationStack = []
                } else {
                    FileShelfManager.shared.addFiles(from: result.copiedURLs)
                    navigationStack = [.fileShelf]
                }
            }
        }

        scratch.awaitingDropCompletion = !scratch.pendingFileDropSequences.isEmpty || !scratch.completedFileDrops.isEmpty
        if !scratch.awaitingDropCompletion,
           !dragState.didJustDrop,
           !isFileDragSessionInProgress,
           !isFileDropTargeted,
           navigationStack.last == .fileShelfLanding,
           !isPinned {
            noteCollapseReason("direct in routeCompletedFileDropsInOrder")
            notchState = isLiveActivityActive ? .autoExpanded : .initial
        }
    }

    private func handleDropZoneFramesChange(_ frames: [DropZone: CGRect]) {
        dropZoneFrames = frames
        guard !frames.isEmpty else { return }
        scratch.dropZoneResolutionTask?.cancel()
        scratch.dropZoneResolutionTask = nil
        routeCompletedFileDropsInOrder()
    }

    private func scheduleDropZoneResolutionFallback() {
        guard scratch.dropZoneResolutionTask == nil else { return }
        scratch.dropZoneResolutionTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            scratch.dropZoneResolutionTask = nil
            routeCompletedFileDropsInOrder(allowUnresolvedTarget: true)
        }
    }

    private func handleDragActivationChange(isDragging: Bool) async {
        scratch.collapseTask?.cancel()
        scratch.isCollapseTimerActive = false

        if isDragging {
            guard !shouldSuppressSnapZoneActivation else { return }
            if isPinned {
                isPinned = false
            }

            dragState.didJustDrop = false

            if isFileDropTargeted {
                notchState = .clickExpanded
                navigationStack = [.fileShelfLanding]

            } else {
                if settings.settings.snapDragEnabled {
                    self.navigationStack = [.snapZones]
                    notchState = .clickExpanded
                }
            }

        } else {
            guard navigationStack.last == .snapZones else { return }
            try? await Task.sleep(for: .milliseconds(50))
            (NSApp.delegate as? AppDelegate)?.revertNotchWindowFocus(notchWindow)

            if dragState.didJustDrop {
                return
            }

            if scratch.awaitingDropCompletion {
                return
            }

            if isFileDropTargeted || isFileDragSessionInProgress {
                return
            }

            self.noteCollapseReason("direct in handleDragActivationChange")
            self.notchState = isLiveActivityActive ? .autoExpanded : .initial
        }
    }

    private func handleWindowDragChange(isDragging: Bool) {
        scratch.collapseTask?.cancel()
        scratch.isCollapseTimerActive = false

        if isDragging {
            scratch.dragEndCollapseTask?.cancel()
            scratch.dragEndCollapseTask = nil
            if isPinned {
                isPinned = false
            }

            self.navigationStack = [.snapZones]
            if notchState != .clickExpanded {
                notchState = .clickExpanded
            }

        } else {
            (NSApp.delegate as? AppDelegate)?.revertNotchWindowFocus(notchWindow)

            guard navigationStack.last == .snapZones else { return }
            scratch.dragEndCollapseTask?.cancel()
            scratch.dragEndCollapseTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled,
                      !isPinned,
                      !(isHovered && cursorIsOnMyScreen),
                      !dragManager.isDraggingInActivationZone,
                      !isFileDropTargeted,
                      !isFileDragSessionInProgress,
                      navigationStack.last == .snapZones else { return }
                noteCollapseReason("direct in handleWindowDragChange")
                notchState = isLiveActivityActive ? .autoExpanded : .initial
                scratch.dragEndCollapseTask = nil
            }
        }
    }

    private func handleFileDropTargetChange(isTargeted: Bool) {
        guard isTargeted, cursorIsOnMyScreen else { return }
        presentFileDragLanding()
    }

    private func presentFileDragLanding() {
        scratch.collapseTask?.cancel()
        scratch.collapseTask = nil
        scratch.isCollapseTimerActive = false
        scratch.dragEndCollapseTask?.cancel()
        scratch.dragEndCollapseTask = nil
        SnapPreviewManager.shared.hidePreview()
        if navigationStack.last != .fileShelfLanding {
            navigationStack = [.fileShelfLanding]
        }
        if notchState != .clickExpanded {
            notchState = .clickExpanded
        }
    }

    private func handleSizeChange(_ newSize: CGSize, for state: NotchState) {
        guard let config else { return }
        if state == .clickExpanded && notchState == .clickExpanded {
            guard newSize.width > 1 && newSize.height > 1 else { return }
            let minimumSize = CGSize(
                width: max(
                    config.initialSize.width,
                    currentMode == .defaultWidgets ? notchBarMinimumWidth : 0
                ),
                height: config.initialSize.height
            )
            let contentSize = NotchSizing.expandedContentSize(contentSize: newSize, minimumSize: minimumSize)
            let targetSize = snappedNotchTarget(width: contentSize.width, height: contentSize.height, config: config)
            let targetWidth = targetSize.width
            let targetHeight = targetSize.height
            setClickContentLayoutSize(targetSize)
            scratch.expandedSizeByMode[currentMode] = targetSize
            guard abs(targetWidth - animatedWidth) > 1 || abs(targetHeight - animatedHeight) > 1 else { return }
            withAnimation(self.expansionAnimation) {
                animatedWidth = targetWidth
                animatedHeight = targetHeight
            }
            syncHostWindowExtent()

        } else if state == .autoExpanded {
            updateAutoContentSize()
        }
    }

    private func applyNotchIconsWidthFloor() {
        guard notchState == .clickExpanded, currentMode == .defaultWidgets else { return }
        let scale = config?.displayScale ?? 2
        let targetWidth = NotchDisplayMetrics.snappedSize(
            atLeast: CGSize(width: max(animatedWidth, notchBarMinimumWidth), height: 0),
            scale: scale
        ).width
        if clickContentLayoutSize.height > 1, targetWidth > clickContentLayoutSize.width {
            setClickContentLayoutSize(CGSize(width: targetWidth, height: clickContentLayoutSize.height))
        }
        guard abs(targetWidth - animatedWidth) > 1 else { return }
        withAnimation(self.expansionAnimation) {
            animatedWidth = targetWidth
        }
    }

    private func setClickContentLayoutSize(_ size: CGSize) {
        guard abs(size.width - clickContentLayoutSize.width) > 0.5
            || abs(size.height - clickContentLayoutSize.height) > 0.5 else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { clickContentLayoutSize = size }
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

        guard Date() >= scratch.revealSettlingUntil else { return }

        let isCollapsed = notchState == .initial || notchState == .hoverExpanded
        let isSwipeUp = vector.dy < 0

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
            guard currentMode != .nearbyTransfer else {
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
                    MusicManager.shared.transientIcon = .skippedForward
                    Task { await MusicManager.shared.nextTrack() }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        if MusicManager.shared.transientIcon == .skippedForward { MusicManager.shared.transientIcon = nil }
                    }
                } else if shouldGoBackward && settings.settings.swipeToRewindMusic {
                    haptic()
                    MusicManager.shared.transientIcon = .skippedBackward
                    Task { await MusicManager.shared.previousTrack() }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        if MusicManager.shared.transientIcon == .skippedBackward { MusicManager.shared.transientIcon = nil }
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
            guard shouldHideWhenInactive else { return }
            guard !scratch.inactiveHideUserOverride else { return }
        }
        guard completeHideReason == nil else {
            completeHideReason = reason
            return
        }

        notchLog.info("hideNotchCompletely: displayID=\(notchDisplayID.map(String.init) ?? "nil", privacy: .public) reason=\(String(describing: reason), privacy: .public)")
        completeHideReason = reason
        if reason == .manualSwipe {
            scratch.inactiveHideUserOverride = false
        }
        isPinned = false
        isHovered = false
        scratch.collapseTask?.cancel()
        scratch.isCollapseTimerActive = false
        cancelHoverExpandTask()
        cancelWidgetSwitchProtection()
        navigationStack = [.defaultWidgets]
        noteCollapseReason("direct in hideNotchCompletely")
        notchState = .initial
        if let runtimeStateSource {
            TrackpadGestureHandler.shared.setActive(false, for: runtimeStateSource)
        }

        withAnimation(.notchMorphSpring(response: 0.22, dampingFraction: 0.9)) {
            animatedWidth = 0
            animatedHeight = 0
        }
        effects.update(.notchMorphSpring(response: 0.22, dampingFraction: 0.9)) { $0.shadowOpacity = 0 }
        if let dynamicWindow = notchWindow as? DynamicFocusWindow {
            dynamicWindow.setMouseEventHandlingEnabled()
        } else {
            notchWindow?.ignoresMouseEvents = true
        }
        setWindowHidden(true)
        syncHostWindowExtent()
        if let runtimeStateSource {
            NotchRuntimeState.shared.update(
                source: runtimeStateSource,
                isUserNear: false,
                isExpanded: false
            )
        }
        startHiddenNotchSwipeMonitor()
    }

    private func revealNotchFromCompleteHide() {
        guard completeHideReason != nil else { return }
        let wasManualSwipeReveal = completeHideReason == .manualSwipe
        notchLog.info("revealNotchFromCompleteHide: displayID=\(notchDisplayID.map(String.init) ?? "nil", privacy: .public) previousReason=\(completeHideReason.map { "\($0)" } ?? "nil", privacy: .public) effectiveActivity=\(String(describing: effectiveActivity), privacy: .public) currentActivity=\(String(describing: liveActivityManager.currentActivity), privacy: .public) swipeOverride=\(scratch.inactiveHideUserOverride, privacy: .public)")
        completeHideReason = nil
        stopHiddenNotchSwipeMonitor()
        if let dynamicWindow = notchWindow as? DynamicFocusWindow {
            dynamicWindow.setMouseEventHandlingEnabled()
        }
        setWindowHidden(false)
        if wasManualSwipeReveal {
            scratch.revealSettlingUntil = Date().addingTimeInterval(Self.revealSettlingInterval)
            scratch.suppressHoverAfterReveal = true
        }
        guard let config else { return }

        let hasActivity = effectiveActivity != .none
        if hasActivity, notchState != .clickExpanded {
            notchState = .autoExpanded
        } else {
            withAnimation(.notchMorphSpring(response: 0.28, dampingFraction: 0.86)) {
                animatedWidth = config.initialSize.width
                animatedHeight = config.initialSize.height
            }
            syncHostWindowExtent()
        }
        updateMouseEventHandling(isInteractive: isInteractive)
        reevaluatePointerInteraction()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            guard !self.isManuallyHidden else { return }
            self.reevaluatePointerInteraction()
        }
    }

    private func setWindowHidden(_ hidden: Bool) {
        if let window = notchWindow as? DynamicFocusWindow {
            window.setNotchHidden(hidden)
        } else {
            notchWindow?.alphaValue = hidden ? 0 : 1
        }
    }

    private var shouldHideWhenInactive: Bool {
        let displayID = assignedScreen?.displayIdentifier
        if settings.settings.value.resolvedHideNotchWhenInactive(forDisplayID: displayID) { return true }
        guard let notchDisplayID else { return false }
        return liveActivityManager.fullScreenBehavior(onDisplayID: notchDisplayID)?.hideNotch == true
    }

    private func evaluateInactiveNotchVisibility() {
        if liveActivityManager.currentActivity == .lockScreen { return }
        let hideWhenInactive = shouldHideWhenInactive
        let evaluation = (hideWhenInactive, completeHideReason)
        if scratch.lastInactiveVisibilityEvaluation?.hideWhenInactive != evaluation.0
            || scratch.lastInactiveVisibilityEvaluation?.hideReason != evaluation.1 {
            notchLog.info("evaluateInactiveNotchVisibility: displayID=\(notchDisplayID.map(String.init) ?? "nil", privacy: .public) shouldHideWhenInactive=\(hideWhenInactive) completeHideReason=\(completeHideReason.map { "\($0)" } ?? "nil") effectiveActivity=\(effectiveActivity.rawValue, privacy: .public)")
            scratch.lastInactiveVisibilityEvaluation = evaluation
        }
        guard hideWhenInactive else {
            if completeHideReason == .inactive {
                scratch.inactiveHideUserOverride = false
                revealNotchFromCompleteHide()
            }
            return
        }
        if completeHideReason == .manualSwipe { return }

        let hasActivity = effectiveActivity != .none
        let isBusy = notchState == .clickExpanded
            || isPinned
            || isHovered
            || dragManager.isDraggingInActivationZone
            || windowDrag.isDragging

        if hasActivity {
            scratch.inactiveHideUserOverride = false
            if completeHideReason == .inactive {
                revealNotchFromCompleteHide()
            }
            return
        }

        guard !isBusy else { return }
        guard !scratch.inactiveHideUserOverride else { return }

        if completeHideReason == nil, notchState == .initial || notchState == .hoverExpanded {
            hideNotchCompletely(reason: .inactive)
        }
    }

    private func startHiddenNotchSwipeMonitor() {
        guard let displayID = notchDisplayID else { return }
        HiddenNotchRevealMonitor.shared.start(displayID: displayID)
    }

    private func stopHiddenNotchSwipeMonitor() {
        guard let displayID = notchDisplayID else { return }
        HiddenNotchRevealMonitor.shared.stop(displayID: displayID)
    }

    private static let revealedIdleRehideDelay: Duration = .seconds(3)

    private func scheduleInactiveRehideAfterReveal() {
        scratch.inactiveRehideTask?.cancel()
        scratch.inactiveRehideTask = Task { @MainActor in
            try? await Task.sleep(for: Self.revealedIdleRehideDelay)
            guard !Task.isCancelled else { return }
            releaseInactiveHideOverrideIfIdle()
        }
    }

    private func releaseInactiveHideOverrideIfIdle() {
        guard scratch.inactiveHideUserOverride else {
            evaluateInactiveNotchVisibility()
            return
        }
        guard !isHovered,
              !isPinned,
              notchState != .clickExpanded,
              !dragManager.isDraggingInActivationZone,
              !windowDrag.isDragging else { return }
        notchLog.info("Releasing swipe-reveal override on displayID=\(notchDisplayID.map(String.init) ?? "nil", privacy: .public)")
        scratch.inactiveHideUserOverride = false
        evaluateInactiveNotchVisibility()
    }

    private func isTargetOfAppWideRequest(_ notification: Notification) -> Bool {
        guard let myDisplayID = notchDisplayID else { return true }
        let notchDisplays = ((NSApp.delegate as? AppDelegate)?.notchWindows ?? [])
            .compactMap { ($0 as? DynamicFocusWindow)?.displayID }
            .filter { $0 != 0 }
        guard !notchDisplays.isEmpty else { return true }
        let target = NotchDisplayTargeting.display(
            requested: (notification.userInfo?["displayID"] as? NSNumber)?.uint32Value,
            pointer: NotchDisplayTargeting.pointerDisplayID,
            notchDisplays: notchDisplays
        )
        return target == myDisplayID
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
        (NSApp.delegate as? AppDelegate)?.makeNotchWindowFocusable(notchWindow)
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
        (NSApp.delegate as? AppDelegate)?.makeNotchWindowFocusable(notchWindow)
    }

    private func handleTrackpadTwoFingerTap() {
        guard (notchState == .autoExpanded || notchState == .hoverExpanded) else { return }

        if liveActivityManager.currentActivity == .microphone && settings.settings.microphoneLiveActivityEnabled && settings.settings.microphoneLiveActivityBehavior == .iconAndGesture {
            haptic()
            MicrophoneUsageManager.shared.toggleMute()
            return
        }

        if liveActivityManager.cycleSportsActivity() {
            haptic()
            return
        }

        if settings.settings.twoFingerTapToPauseMusic {
            haptic()
            MusicManager.shared.transientIcon = MusicManager.shared.isPlaying ? .paused : .played
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                if MusicManager.shared.transientIcon == .paused || MusicManager.shared.transientIcon == .played {
                    MusicManager.shared.transientIcon = nil
                }
            }
            Task {
                if MusicManager.shared.isPlaying {
                    await MusicManager.shared.pause()
                } else {
                    await MusicManager.shared.play()
                }
            }
        }
    }

    // MARK: - Helper Methods
    private func startNotchInteractionMonitoring() {
        guard let window = notchWindow else { return }
        (window as? DynamicFocusWindow)?.onMouseUp = { reevaluatePointerInteraction() }

        let monitor = hoverMonitor ?? NotchHoverMonitor()
        hoverMonitor = monitor
        monitor.start(
            window: window,
            handlers: NotchHoverMonitorHandlers(
                onPointerEvent: { refreshNotchInteractionState() },
                onMouseDrag: { isInside, location in
                    handleProbeMouseDrag(isInside: isInside, screenLocation: location)
                },
                onMouseDragEnded: { location in
                    handleProbeMouseDragEnded(at: location)
                },
                onFileDrag: { isTargeted, location in
                    handleProbeFileDrag(isTargeted: isTargeted, screenLocation: location)
                },
                onFileDragEnded: { location, dropWasAccepted in
                    handleProbeFileDragEnded(
                        at: location,
                        dropWasAccepted: dropWasAccepted
                    )
                },
                onFileDrop: { urls, location in
                    handleFileDrop(urls: urls, at: location)
                }
            )
        )
        refreshNotchInteractionState()
    }

    private func stopNotchInteractionMonitoring() {
        hoverMonitor?.stop()
        hoverMonitor = nil
        (notchWindow as? DynamicFocusWindow)?.onMouseUp = nil
        activeSnapZone = nil
        activeDropZone = nil
        notchDragLocationState.update(nil)
        dropZoneFrames = [:]
        snapZoneHitRegions = []
        isFileDropTargeted = false
        isFileDragSessionInProgress = false
        activeFileDragIsFromShelf = false
        routeCompletedFileDropsInOrder(allowUnresolvedTarget: true)
        scratch.isHandlingActiveWindowDrag = false
        scratch.lastSampledMouseLocation = nil
        scratch.lastPublishedInteractiveFrame = .null
    }

    private func handleProbeMouseDrag(isInside: Bool, screenLocation: NSPoint) {
        if isInside {
            scratch.dragEndCollapseTask?.cancel()
            scratch.dragEndCollapseTask = nil
        }
        if windowDrag.isDragging,
           settings.settings.snapOnWindowDragEnabled,
           !shouldSuppressSnapZoneActivation {
            let isOnThisScreen = assignedScreen.map {
                NotchDisplayTargeting.screen(containing: screenLocation)?.displayID == $0.displayID
            } ?? cursorIsOnMyScreen
            if isOnThisScreen, !scratch.isHandlingActiveWindowDrag {
                handleWindowDragDisplayChange(notchDisplayID)
            } else if !isOnThisScreen, scratch.isHandlingActiveWindowDrag {
                handleWindowDragDisplayChange(nil)
            }
        }
        if windowDrag.isDragging, shouldSuppressSnapZoneActivation {
            dragManager.cancelActivation()
            return
        }
        if isInside || scratch.isHandlingActiveWindowDrag || navigationStack.last == .snapZones {
            updateNotchDragLocation(from: screenLocation)
        }
        guard settings.settings.snapDragEnabled else {
            dragManager.cancelActivation()
            return
        }
        dragManager.updateDrag(
            isInsideActivationZone: isInside || isNearNotchForSnapActivation(screenLocation)
        )
    }

    private static let snapActivationOutset = CGSize(width: 140, height: 70)
    private static let snapActivationRetainOutset = CGSize(width: 220, height: 130)

    private func isNearNotchForSnapActivation(_ screenLocation: NSPoint) -> Bool {
        guard let window = notchWindow, let config else { return false }
        if let screen = assignedScreen,
           NotchDisplayTargeting.screen(containing: screenLocation)?.displayID != screen.displayID {
            return false
        }
        let notchFrame = window.convertToScreen(interactiveFrame(for: window, config: config))
        guard !notchFrame.isEmpty else { return false }
        let outset = dragManager.isActivationPending
            ? Self.snapActivationRetainOutset
            : Self.snapActivationOutset
        return notchFrame
            .insetBy(dx: -outset.width, dy: -outset.height)
            .contains(screenLocation)
    }

    private func handleProbeMouseDragEnded(at screenLocation: NSPoint) {
        let finalLocation = updateNotchDragLocation(from: screenLocation)
        let wasShowingSnapZones = navigationStack.last == .snapZones
        let finalSnapZone: SnapZone?
        if !wasShowingSnapZones {
            finalSnapZone = nil
        } else if let finalLocation, !snapZoneHitRegions.isEmpty {
            finalSnapZone = SnapZoneHitTesting.nearest(snapZoneHitRegions, to: finalLocation) { $0.frame }?.zone
        } else {
            finalSnapZone = activeSnapZone
        }

        if let finalSnapZone {
            SnappingManager.snap(zone: finalSnapZone)
        }
        activeSnapZone = nil
        notchDragLocationState.update(nil)
        dragManager.endDrag()

        guard wasShowingSnapZones else { return }
        scratch.dragEndCollapseTask?.cancel()
        scratch.dragEndCollapseTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled,
                  !isPinned,
                  !isFileDropTargeted,
                  !isFileDragSessionInProgress,
                  navigationStack.last == .snapZones else { return }
            noteCollapseReason("direct in handleProbeMouseDragEnded")
            notchState = isLiveActivityActive ? .autoExpanded : .initial
            scratch.dragEndCollapseTask = nil
        }
    }

    private func handleProbeFileDrag(isTargeted: Bool, screenLocation: NSPoint) {
        if isTargeted {
            scratch.dragEndCollapseTask?.cancel()
            scratch.dragEndCollapseTask = nil
        }
        scratch.fileDragExitTask?.cancel()
        scratch.fileDragExitTask = nil
        updateNotchDragLocation(from: screenLocation)
        dragManager.cancelActivation()
        if !isTargeted, isFileDragSessionInProgress {
            scheduleFileDragLandingDismissal()
        }

        if isTargeted, !isFileDragSessionInProgress {
            isFileDragSessionInProgress = true
            activeFileDragIsFromShelf = dragState.isDraggingFromShelf
            displayedFileDragMode = activeFileDragIsFromShelf ? .existingFile : .newFile
            dragState.didJustDrop = false
        }
        if isFileDropTargeted != isTargeted {
            isFileDropTargeted = isTargeted
        }
        if isTargeted {
            presentFileDragLanding()
        }
    }

    private func scheduleFileDragLandingDismissal() {
        scratch.fileDragExitTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled,
                  !isFileDropTargeted,
                  isFileDragSessionInProgress else { return }
            scratch.fileDragExitTask = nil
            isFileDragSessionInProgress = false
            activeDropZone = nil
            notchDragLocationState.update(nil)
            activeFileDragIsFromShelf = false
            guard navigationStack.last == .fileShelfLanding, !isPinned else { return }
            noteCollapseReason("file drag left the landing")
            notchState = isLiveActivityActive ? .autoExpanded : .initial
        }
    }

    private func handleProbeFileDragEnded(
        at screenLocation: NSPoint,
        dropWasAccepted: Bool
    ) {
        scratch.fileDragExitTask?.cancel()
        scratch.fileDragExitTask = nil
        updateNotchDragLocation(from: screenLocation)

        isFileDropTargeted = false
        isFileDragSessionInProgress = false
        activeDropZone = nil
        activeSnapZone = nil
        notchDragLocationState.update(nil)
        dragManager.cancelActivation()
        routeCompletedFileDropsInOrder()
        activeFileDragIsFromShelf = false

        guard !dropWasAccepted,
              navigationStack.last == .fileShelfLanding,
              !isPinned else { return }
        noteCollapseReason("direct in handleProbeFileDragEnded")
        notchState = isLiveActivityActive ? .autoExpanded : .initial
    }

    @discardableResult
    private func updateNotchDragLocation(from screenLocation: NSPoint) -> CGPoint? {
        guard let window = notchWindow, let contentView = window.contentView else { return nil }
        let windowPoint = window.convertPoint(fromScreen: screenLocation)
        let swiftUILocation = (contentView as? NotchStageContainerView)?.stagePoint(fromWindowPoint: windowPoint)
            ?? CGPoint(x: windowPoint.x, y: contentView.bounds.height - windowPoint.y)
        notchDragLocationState.update(swiftUILocation)
        return swiftUILocation
    }

    private func reevaluatePointerInteraction() {
        scratch.lastSampledMouseLocation = nil
        refreshNotchInteractionState()
    }

    private func refreshNotchInteractionState() {
        guard let config = config, let window = notchWindow else { return }

        if isManuallyHidden {
            if isHovered { isHovered = false }
            updateMouseEventHandling(isInteractive: false)
            return
        }

        let mouseLocation = window.mouseLocationOutsideOfEventStream
        let interactiveBounds = interactiveFrame(for: window, config: config)
        let isNear = isMouseNearNotchFrame(interactiveBounds, mouseLocation: mouseLocation)
        if let runtimeStateSource {
            NotchRuntimeState.shared.update(source: runtimeStateSource, isUserNear: isNear)
        }
        let keepsExpandedHover = isHovered && notchState != .initial
        let margin = keepsExpandedHover ? Self.expandedHoverStayMargin : Self.hoverDetectionMargin
        let detectionBounds = interactiveBounds.insetBy(dx: -margin, dy: -margin)
        let isPointerInside = detectionBounds.contains(mouseLocation)

        if !isInteractive, !isNear, scratch.lastSampledMouseLocation == mouseLocation {
            return
        }

        scratch.lastSampledMouseLocation = mouseLocation

        if !isInteractive && !isNear {
            if isHovered {
                receivePointerHover(false)
            }
            updateMouseEventHandling(isInteractive: false)
            return
        }

        if interactiveBounds != scratch.lastPublishedInteractiveFrame {
            scratch.lastPublishedInteractiveFrame = interactiveBounds
        }

        if scratch.suppressHoverAfterReveal, !isPointerInside {
            scratch.suppressHoverAfterReveal = false
        }

        if isPointerInside != isHovered, !dragManager.isDraggingInActivationZone, !windowDrag.isDragging {
            if !isPointerInside, notchState == .clickExpanded, scratch.widgetSwitchProtectionTask != nil {
                return
            }
            receivePointerHover(isPointerInside)
        } else if isPointerInside, scratch.pendingHoverExit != nil {
            scratch.pendingHoverExit?.cancel()
            scratch.pendingHoverExit = nil
        }

        updateMouseEventHandling(isInteractive: isInteractive || isPointerInside)
    }

    private func updateRuntimeExpansionState() {
        guard let runtimeStateSource else { return }
        NotchRuntimeState.shared.update(
            source: runtimeStateSource,
            isExpanded: notchState != .initial && !isManuallyHidden
        )
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

        let contentBounds = (window.contentView as? NotchStageContainerView)?.stageFrame
            ?? window.contentView?.bounds
            ?? .zero
        guard !contentBounds.isEmpty else { return .zero }

        let notchWidth: CGFloat
        let notchHeight: CGFloat
        switch notchState {
        case .initial:
            notchWidth = config.initialSize.width
            notchHeight = config.initialSize.height
        case .hoverExpanded, .autoExpanded, .clickExpanded:
            let drawn = morphEngine.currentFrame.values.size
            notchWidth = max(animatedWidth, drawn.width)
            notchHeight = max(animatedHeight, drawn.height)
        }

        let topInset = config.topInset - config.topBuffer
        let showsSatellites = notchState != .clickExpanded && !animatedSatellites.isEmpty
        let layout = satelliteLayout(config: config)
        let satelliteReach = showsSatellites ? layout.reach(count: animatedSatellites.count) : 0
        let frame = CGRect(
            x: contentBounds.midX - (notchWidth / 2) - satelliteReach,
            y: contentBounds.maxY - notchHeight - topInset,
            width: notchWidth + 2 * satelliteReach,
            height: max(notchHeight, showsSatellites ? layout.centerY + layout.diameter / 2 : 0)
        ).integral

        return frame.insetBy(dx: -1, dy: -1)
    }

    private func toRestorableMenu(mode: NotchWidgetMode) -> RestorableNotchMenu? {
        switch mode {
        case .defaultWidgets: return .defaultWidgets
        case .musicPlayer: return .musicPlayer
        case .musicQueueAndPlaylists: return .musicQueueAndPlaylists
        case .musicDevices: return .musicDevices
        case .nearbyTransfer: return .nearbyTransfer
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
                .multiAudioDeviceAdjust, .multiAudioAppEQ, .multiAudioApp8D, .multiAudioAppSurround, .multiAudioEQ, .earbudControls, .dragActivated,
                .agentS, .blipHub, .circleToSearch, .updateAvailable, .focusSessionDetailView, .batteryDetailView,
                .storageDetailView, .continuityDetail, .continuityActivityDetail,
                .fileProgressDetail, .appActivityDetail, .devDashboard, .devActivityDetail:
            return nil
        }
    }

    private func islandCornerRadius(for state: NotchState, config: ResolvedNotchConfiguration) -> CGFloat {
        let pillRadius = config.initialSize.height / 2
        switch state {
        case .clickExpanded:
            guard currentMode == .defaultWidgets else { return config.floatingIslandCornerRadius }
            return max(config.floatingIslandCornerRadius, MusicWidgetView.artworkCornerRadius + config.contentTopPadding)
        case .initial:
            return pillRadius
        case .hoverExpanded:
            return pillRadius * config.scaleFactor
        case .autoExpanded:
            return pillRadius
        }
    }

    private func updateRadiiForCurrentState(state: NotchState) {
        guard let config = config else { return }
        if config.isFloatingIsland {
            let radius = islandCornerRadius(for: state, config: config)
            animatedCornerRadius = radius
            animatedBottomCornerRadius = radius
            return
        }
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

    private func updateAutoContentSize() {
        guard let config = config, notchState == .autoExpanded || (notchState == .hoverExpanded && isLiveActivityActive) else { return }
        let scale = activeScaleFactor
        let targetSize = NotchDisplayMetrics.snappedSize(
            atLeast: NotchSizing.expandedContentSize(
                contentSize: measuredAutoContentSize,
                minimumSize: config.initialSize,
                scale: scale
            ),
            scale: config.displayScale
        )
        let targetWidth = targetSize.width
        let targetHeight = targetSize.height
        let epsilon: CGFloat = 0.5

        guard targetWidth > 0 && targetHeight > 0,
              (abs(targetWidth - animatedWidth) > epsilon || abs(targetHeight - animatedHeight) > epsilon) else { return }

        let currentActivityType = liveActivityManager.currentActivity
        let isExemptFromBlur = reduceMotion
            || currentActivityType == .music || currentActivityType == .systemHUD
            || Date() < scratch.activitySwitchBlurWindowEnd

        if !isExemptFromBlur {
            effects.update(.notchMorphTiming(.easeIn, duration: config.activityBlurUpdateDelay)) { $0.activityBlurRadius = 15 }
        }

        withAnimation(config.activityToActivityAnimation) {
            animatedWidth = targetWidth
            animatedHeight = targetHeight
        }

        if !isExemptFromBlur {
            scratch.blurRemovalTask?.cancel()
            scratch.blurRemovalTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(config.autoContentRenderDelay))
                guard !Task.isCancelled else { return }
                self.effects.update(config.blurRemovalAnimation) { $0.activityBlurRadius = 0 }
            }
        } else if Date() >= scratch.activitySwitchBlurWindowEnd {
            scratch.blurRemovalTask?.cancel()
            scratch.blurRemovalTask = nil
            effects.update { $0.activityBlurRadius = 0 }
        }
    }

    private func updateMouseEventHandling(isInteractive: Bool) {
        guard let window = notchWindow else { return }

        if isManuallyHidden {
            if let dynamicWindow = window as? DynamicFocusWindow {
                dynamicWindow.setMouseEventHandlingEnabled()
            } else {
                window.ignoresMouseEvents = true
            }
            hoverMonitor?.update(hoverRect: .null, pointerIsInside: false)
            return
        }

        let pointerIsInInteractionBounds: Bool
        if let config {
            let frame = interactiveFrame(for: window, config: config)
                .insetBy(dx: -Self.hoverDetectionMargin, dy: -Self.hoverDetectionMargin)
            pointerIsInInteractionBounds = frame.contains(window.mouseLocationOutsideOfEventStream)
        } else {
            pointerIsInInteractionBounds = false
        }
        let shouldReceiveMouseEvents = isInteractive
            && isPointerInteractionActive
            && (pointerIsInInteractionBounds || isPointerCaptureActive)
        if let dynamicWindow = window as? DynamicFocusWindow {
            dynamicWindow.setMouseEventHandlingEnabled(shouldReceiveMouseEvents)
        } else if window.contentView != nil {
            window.ignoresMouseEvents = !shouldReceiveMouseEvents
        }

        if let config {
            let frame = interactiveFrame(for: window, config: config)
            hoverMonitor?.update(
                hoverRect: frame.insetBy(dx: -Self.hoverDetectionMargin, dy: -Self.hoverDetectionMargin),
                pointerIsInside: isHovered
            )
        }
    }

    private func updateWindowSharingBehavior(shouldBeHidden: Bool) {
        guard let window = notchWindow else { return }
        let desired: NSWindow.SharingType = shouldBeHidden ? .none : .readOnly
        if window.sharingType != desired {
            window.sharingType = desired
        }
    }

    private var hostWindowExtent: NotchHostWindowExtent {
        let isFull = (!isManuallyHidden && (dragManager.isDraggingInActivationZone || windowDrag.isDragging))
            || isFileDragSessionInProgress
            || isFileDropTargeted
            || (notchState == .clickExpanded && navigationStack.last == .snapZones)
        return NotchHostWindowExtent(
            isFull: isFull,
            notchSize: CGSize(width: animatedWidth, height: animatedHeight),
            notchTopOffset: (config?.topInset ?? 0) - (config?.topBuffer ?? 0),
            collapsedHeight: config?.initialSize.height ?? 0,
            fullBandInset: (config?.topInset ?? 0) + (config?.topBuffer ?? 0),
            margin: hostWindowMargin
        )
    }

    private var hostWindowMargin: CGFloat {
        guard notchState == .clickExpanded, let config else { return NotchHostWindowSizer.fittedMargin }
        let shadowReach = 2 * max(0, config.expandedShadowRadius) + abs(config.expandedShadowOffsetY)
        return max(NotchHostWindowSizer.fittedMargin, ceil(shadowReach))
    }

    private func syncHostWindowExtent() {
        guard config != nil else { return }
        (notchWindow as? DynamicFocusWindow)?.hostSizer.update(hostWindowExtent)
    }

    private func handleClickExpandedHoverOut(config: ResolvedNotchConfiguration) {
        guard !isPinned else { return }
        guard scratch.widgetSwitchProtectionTask == nil else { return }
        scheduleCollapse(after: 0)
    }

    private func startWidgetSwitchProtection() {
        scratch.widgetSwitchProtectionTask?.cancel()
        scratch.widgetSwitchSettleTask?.cancel()
        scratch.widgetSwitchProtectionGeneration &+= 1
        let generation = scratch.widgetSwitchProtectionGeneration

        scratch.widgetSwitchProtectionTask = Task { @MainActor in
            defer {
                if generation == self.scratch.widgetSwitchProtectionGeneration {
                    self.scratch.widgetSwitchProtectionTask = nil
                }
            }
            try? await Task.sleep(for: .seconds(Self.widgetSwitchProtectionDuration))
            guard !Task.isCancelled else { return }
            guard generation == self.scratch.widgetSwitchProtectionGeneration else { return }
            self.evaluateCollapseIfCursorOutsideHoverZone()
        }
        scheduleWidgetSwitchSettledCheck()
    }

    private func scheduleWidgetSwitchSettledCheck() {
        guard scratch.widgetSwitchProtectionTask != nil else { return }
        scratch.widgetSwitchSettleTask?.cancel()
        let generation = scratch.widgetSwitchProtectionGeneration
        scratch.widgetSwitchSettleTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled,
                  generation == self.scratch.widgetSwitchProtectionGeneration,
                  let window = self.notchWindow,
                  let config = self.config else { return }
            let hoverBounds = self.interactiveFrame(for: window, config: config)
                .insetBy(dx: -Self.hoverCollapseMargin, dy: -Self.hoverCollapseMargin)
            guard hoverBounds.contains(window.mouseLocationOutsideOfEventStream) else { return }
            self.scratch.widgetSwitchProtectionTask?.cancel()
            self.scratch.widgetSwitchProtectionTask = nil
            self.scratch.widgetSwitchSettleTask = nil
        }
    }

    private func cancelWidgetSwitchProtection() {
        scratch.widgetSwitchProtectionGeneration &+= 1
        scratch.widgetSwitchProtectionTask?.cancel()
        scratch.widgetSwitchProtectionTask = nil
        scratch.widgetSwitchSettleTask?.cancel()
        scratch.widgetSwitchSettleTask = nil
    }

    private func evaluateCollapseIfCursorOutsideHoverZone() {
        guard let window = notchWindow, let config = config, !isPinned else { return }
        let mouseLocation = window.mouseLocationOutsideOfEventStream
        let interactiveBounds = interactiveFrame(for: window, config: config)
        let hoverBounds = notchState == .initial
            ? interactiveBounds
            : interactiveBounds.insetBy(dx: -Self.hoverCollapseMargin, dy: -Self.hoverCollapseMargin)
        guard !hoverBounds.contains(mouseLocation) else { return }
        guard !dragManager.isDraggingInActivationZone && !windowDrag.isDragging else { return }
        scheduleCollapse(after: 0)
    }

    private func noteCollapseReason(_ reason: String) {
        #if DEBUG
        let mouse = notchWindow?.mouseLocationOutsideOfEventStream ?? .zero
        let frame = notchWindow.flatMap { window in config.map { interactiveFrame(for: window, config: $0) } } ?? .zero
        scratch.lastCollapseReason = "\(reason) mouse=\(Int(mouse.x)),\(Int(mouse.y)) frame=\(frame.integral) target=\(Int(animatedWidth))x\(Int(animatedHeight)) measured=\(measuredClickContentSize) mode=\(currentMode) hovered=\(isHovered) protect=\(scratch.widgetSwitchProtectionTask != nil)"
        notchLog.notice("collapse-trace note: \(self.scratch.lastCollapseReason, privacy: .public)")
        #endif
    }

    private func traceCollapseIfNeeded(from oldState: NotchState, to newState: NotchState) {
        #if DEBUG
        guard oldState != .initial, newState == .initial || (oldState == .clickExpanded && newState != .clickExpanded) else { return }
        notchLog.notice("collapse-trace COLLAPSED \(String(describing: oldState), privacy: .public) -> \(String(describing: newState), privacy: .public); last reason: \(self.scratch.lastCollapseReason, privacy: .public)")
        #endif
    }

    private func scheduleCollapse(after delay: TimeInterval, caller: String = #function, line: Int = #line) {
        noteCollapseReason("scheduleCollapse from \(caller):\(line) [prev: \(scratch.lastCollapseReason)]")
        scratch.collapseTask?.cancel()
        scratch.collapseTask = nil
        guard !isPinned,
              !isFileDropTargeted,
              !isFileDragSessionInProgress,
              !scratch.awaitingDropCompletion else {
            scratch.isCollapseTimerActive = false
            return
        }
        scratch.isCollapseTimerActive = true
        scratch.collapseTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(Int(delay * 1000)))
                guard !Task.isCancelled else { return }
                if !self.isHovered
                    && !self.dragManager.isDraggingInActivationZone
                    && !self.windowDrag.isDragging
                    && !self.isFileDropTargeted
                    && !self.isFileDragSessionInProgress
                    && !self.scratch.awaitingDropCompletion {
                    self.notchState = isLiveActivityActive ? .autoExpanded : .initial
                    self.releaseInactiveHideOverrideIfIdle()
                }
                self.scratch.isCollapseTimerActive = false
            } catch {
                self.scratch.isCollapseTimerActive = false
            }
        }
    }

    private func cancelHoverExpandTask() {
        scratch.hoverExpandTask?.cancel()
        scratch.hoverExpandTask = nil
    }
}

private struct NotchHUDOverlayContent: View {
    @ObservedObject private var hudManager = SystemHUDManager.shared
    @ObservedSettings private var settings: SettingsObserver

    let config: ResolvedNotchConfiguration
    let animatedWidth: CGFloat

    var body: some View {
        if let hud = hudManager.currentHUD {
            let trailingPadding = config.defaultModeIconsHorizontalPadding
            let availableWidth = max(0, animatedWidth - trailingPadding)
            HStack(spacing: 8) {
                SystemHUDSlimActivityView.left(type: hud, settings: settings)
                SystemHUDSlimActivityView.right(
                    type: hud,
                    settings: settings,
                    availableWidth: availableWidth
                )
            }
            .padding(.trailing, trailingPadding)
            .frame(height: config.initialSize.height)
        }
    }
}

enum MusicBottomContentKind: Equatable {
    case none, peek, lyrics, upNext

    init(_ contentType: MusicBottomContentType) {
        switch contentType {
        case .none: self = .none
        case .peek: self = .peek
        case .lyrics: self = .lyrics
        case .upNext: self = .upNext
        }
    }
}

enum LiveActivityAnimationKey: Equatable {
    case none
    case full(AnyHashable)
    case music(MusicBottomContentKind)
    case standard(AnyHashable)
}

enum NotchShapeSignature: Equatable {
    case none
    case full(bottomCornerRadius: CGFloat?)
    case music(MusicBottomContentKind)
    case standard
}

extension LiveActivityManager {
    var activityAnimationKey: LiveActivityAnimationKey {
        switch activityContent {
        case .none:
            return .none
        case .full(_, let id, _):
            return .full(id)
        case .standard(let data, let id):
            if case .music(let bottomContentType) = data {
                return .music(MusicBottomContentKind(bottomContentType))
            }
            return .standard(id)
        }
    }

    var notchShapeSignature: NotchShapeSignature {
        switch activityContent {
        case .none:
            return .none
        case .full(_, _, let bottomCornerRadius):
            return .full(bottomCornerRadius: bottomCornerRadius)
        case .standard(let data, _):
            if case .music(let bottomContentType) = data {
                return .music(MusicBottomContentKind(bottomContentType))
            }
            return .standard
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
}

private struct LiveActivityContentUpdateObserver: View {
    let liveActivityManager: LiveActivityManager
    let onUpdate: () -> Void

    var body: some View {
        Color.clear
            .allowsHitTesting(false)
            .onChange(of: liveActivityManager.contentUpdateID) { onUpdate() }
    }
}

private struct NotchLiveActivityContent: View {
    private final class LastShown {
        var content: LiveActivityContent = .none
        var activity: ActivityType?
    }

    let liveActivityManager: LiveActivityManager
    let config: ResolvedNotchConfiguration
    let horizontalPadding: CGFloat
    let screen: NSScreen?
    @Binding var measuredSize: CGSize
    @Binding var showLyrics: Bool
    @State private var lastShown = LastShown()

    var body: some View {
        let live = liveActivityManager.activityContent
        let isLive: Bool = { if case .none = live { return false }; return true }()
        if isLive {
            lastShown.content = live
            lastShown.activity = liveActivityManager.currentActivity
        }
        return NotchActivityContentView(
            content: isLive ? live : lastShown.content,
            config: config,
            horizontalPadding: horizontalPadding,
            screen: screen,
            measuredSize: $measuredSize,
            showLyrics: $showLyrics
        )
            .geometryGroup()
            .transition(.identity)
            .id(isLive ? liveActivityManager.currentActivity : (lastShown.activity ?? liveActivityManager.currentActivity))
    }
}