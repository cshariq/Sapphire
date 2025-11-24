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
    private static var renderCounter: Int = 0

    enum NotchState: Hashable {
        case initial, autoExpanded, hoverExpanded, clickExpanded
    }

    // MARK: - Environment Objects
    @EnvironmentObject var liveActivityManager: LiveActivityManager
    @EnvironmentObject var musicWidget: MusicManager
    @EnvironmentObject var geminiLiveManager: GeminiLiveManager
    @EnvironmentObject var pickerHelper: ContentPickerHelper
    @EnvironmentObject var settings: SettingsModel
    @EnvironmentObject var batteryEstimator: BatteryEstimator
    @EnvironmentObject var timerManager: TimerManager

    // MARK: - State Objects
    @StateObject private var fileShelfState = FileShelfState()
    @StateObject private var dragManager = GlobalDragManager.shared
    @StateObject private var dragState = DragStateManager.shared
    @StateObject private var audioManager = MultiAudioManager.shared
    @StateObject private var caffeineManager = CaffeineManager.shared
    @StateObject private var calendarViewModel = InteractiveCalendarViewModel()

    @ObservedObject private var activeAppMonitor = ActiveAppMonitor.shared

    // MARK: - State Properties
    @State private var config: ResolvedNotchConfiguration?
    @State private var notchState: NotchState = .initial
    @State private var isHovered: Bool = false
    @State private var collapseTask: Task<Void, Never>?
    @State private var isCollapseTimerActive: Bool = false
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

    @State private var dropZoneFrames: [DropZone: CGRect] = [:]
    @State private var hoverDetectionTimer: Timer?
    @State private var isCalendarHovered: Bool = false

    // MARK: - Computed Properties
    private var isLiveActivityActive: Bool { liveActivityManager.currentActivity != .none }
    private var isFullViewActivity: Bool { liveActivityManager.isFullViewActivity }
    private var isGeminiActive: Bool { liveActivityManager.currentActivity == .geminiLive }

    private var isDisplayingMusicLiveActivity: Bool {
        let isMusic = (liveActivityManager.currentActivity == .music)
        let isShowingActivityView = (notchState == .autoExpanded || notchState == .hoverExpanded)
        return isMusic && isShowingActivityView
    }

    private var currentMode: NotchWidgetMode { navigationStack.last ?? .defaultWidgets }

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

    private var isInteractive: Bool {
        notchState == .clickExpanded || isHovered || dragManager.isDraggingInActivationZone || activeAppMonitor.isWindowDragging
    }

    private var shouldHideWindowForSharing: Bool {
        settings.settings.hideFromScreenSharing || (notchState == .initial)
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
            case .shortcuts:
                return settings.settings.shortcutsWidgetEnabled
            }
        }
    }

    private var switchableWidgetModes: [NotchWidgetMode] {
        return enabledAndOrderedWidgets.compactMap { widgetType in
            switch widgetType {
            case .music: return .musicPlayer
            case .weather: return .weatherPlayer
            case .calendar: return .calendarPlayer
            case .shortcuts: return nil
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

    private var showMultiAudioIcon: Bool {
        audioManager.availableOutputDevices.count > 1
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
        self.notchWidget = NotchWidgetView(
            navigationStack: .constant([]),
            activeDropZone: .constant(nil),
            isFileDropTargeted: .constant(false),
            calendarViewModel: InteractiveCalendarViewModel()
        )
    }

    // MARK: - Body
    var body: some View {
        let renderIndex: Int = {
            NotchController.renderCounter += 1
            return NotchController.renderCounter
        }()

        if let config = config {
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

                ZStack(alignment: .top) {
                    let showActivityView = (notchState == .autoExpanded || notchState == .hoverExpanded || isAnimatingActivityOut)
                    if showActivityView && isLiveActivityActive && canRenderAutoContent {
                        autoActivityView
                            .fixedSize(horizontal: true, vertical: false)
                            .blur(radius: activityBlurRadius)
                            .scaleEffect(activityContentScale)
                            .id(liveActivityManager.currentActivity)
                            .animation(liveActivityManager.activityHasBottomContent ?
                                       config.bottomContentTransitionAnimation :
                                        config.activityToActivityAnimation,
                                       value: liveActivityManager.contentUpdateID)
                            .opacity(autoContentOpacity)
                            .scaleEffect(animatedContentScale)
                            .allowsHitTesting(isHovered)
                    } else {
                        contentView
                            .mask(activeShape)
                    }

                    if notchState == .clickExpanded {
                        expandedOverlayIcons
                            .transition(.opacity.animation(.easeInOut(duration: 0.2)))
                            .zIndex(1)
                    }
                }
            }
            // MARK: - SHADOW LOGIC
            .shadow(
                color: isGeminiActive ? .clear : config.expandedShadowColor.opacity(shadowOpacity),
                radius: isGeminiActive ? 0 : (notchState == .clickExpanded ? config.expandedShadowRadius : (notchState == .hoverExpanded ? 12 : 0)),
                y: isGeminiActive ? 0 : (notchState == .clickExpanded ? config.expandedShadowOffsetY : (notchState == .hoverExpanded ? 6 : 0))
            )
            .frame(width: animatedWidth, height: animatedHeight)
            .contentShape(activeShape)
            .onDrop(of: [UTType.fileURL, .plainText], isTargeted: $isFileDropTargeted, perform: handleItemDrop)
            .onHover(perform: handleHover)
            .padding(.top, -config.topBuffer)
            .overlay(measurementOverlay)
            .onAppear(perform: setupMonitors)
            .onDisappear(perform: teardownMonitors)
            .onChange(of: fileShelfState.selectedItemForPreview, perform: handlePreviewItemChange)
            .onChange(of: liveActivityManager.currentActivity, perform: handleActivityChange)
            .onChange(of: liveActivityManager.contentUpdateID) {
                if notchState == .autoExpanded || notchState == .hoverExpanded {
                    handleStateChange(from: notchState, to: notchState)
                }
            }
            .onChange(of: notchState, handleStateChange)
            .onChange(of: navigationStack, handleNavigationStackChange)
            .onChange(of: dragManager.isDraggingInActivationZone) { _, isDragging in
                Task {
                    await handleDragActivationChange(isDragging: isDragging)
                }
            }
            .onChange(of: activeAppMonitor.isWindowDragging) { _, isDragging in
                if settings.settings.snapOnWindowDragEnabled {
                    handleWindowDragChange(isDragging: isDragging)
                }
            }
            .onChange(of: isFileDropTargeted, perform: handleFileDropTargetChange)
            .onChange(of: measuredClickContentSize) { _, newSize in handleSizeChange(newSize, for: .clickExpanded) }
            .onChange(of: measuredAutoContentSize) { _, newSize in handleSizeChange(newSize, for: .autoExpanded) }
            .onReceive(pickerHelper.pickerResultPublisher, perform: handlePickerResult)
            .onChange(of: showLyrics, perform: handleShowLyricsChange)
            .onChange(of: isInteractive) { _, newValue in updateMouseEventHandling(isInteractive: newValue) }
            .onChange(of: shouldHideWindowForSharing) { _, newValue in updateWindowSharingBehavior(shouldBeHidden: newValue) }
            .onChange(of: isInteractive) { _, isNowInteractive in
                if isNowInteractive {
                    MenuBarInteractionManager.shared.stopMonitoring()
                } else {
                    MenuBarInteractionManager.shared.startMonitoring()
                }
            }
            .onChange(of: settings.settings) { _, newSettings in
                let newConfig = ResolvedNotchConfiguration(from: newSettings)
                self.config = newConfig
                self.expansionAnimation = newConfig.expandAnimation
                handleStateChange(from: notchState, to: notchState)
            }
            .onPreferenceChange(DropZonePreferenceKey.self) { value in
                self.dropZoneFrames = value
            }
        } else {
            Color.clear
                .onAppear {
                    let initialConfig = ResolvedNotchConfiguration(from: settings.settings)
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

    // MARK: - Subviews
    @ViewBuilder
    private var notchBackground: some View {
        let appearance = activeAppearanceSettings
        ZStack {
            Color.clear
            if #available(macOS 26.0, *), appearance.liquidGlassLook {
                activeShape
                    .fill(.clear)
                    .glassEffect(.clear, in: activeShape)
            } else {
                if appearance.enableTransparencyBlur {
                    VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                }
                Rectangle()
                    .fill(notchFillMaterial)
                    .opacity(appearance.opacity)
            }
        }
        .contentShape(activeShape)
        .clipShape(activeShape)
        .onTapGesture(perform: handleTap)
    }

    private var notchFillMaterial: AnyShapeStyle {
        let appearance = activeAppearanceSettings
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
    }

    @ViewBuilder
    private func buildStandardActivityView(from data: StandardActivityData) -> some View {
        if let config = config {
            VStack(spacing: 0) {
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
    private var measurementOverlay: some View {
        if let config = config {
            ZStack {
                if notchState == .clickExpanded {
                    notchWidget
                        .environmentObject(fileShelfState)
                        .environment(\.navigationStack, $navigationStack)
                        .environment(\.activeDropZone, $activeDropZone)
                        .environment(\.isFileDropTargeted, $isFileDropTargeted)
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
                        .fixedSize()
                        .background(GeometryReader { geo in
                            Color.clear
                                .onAppear { measuredClickContentSize = geo.size }
                                .onChange(of: geo.size) { _, newSize in measuredClickContentSize = newSize }
                                .onDisappear { measuredClickContentSize = .zero }
                        })
                }
                if isLiveActivityActive {
                    autoActivityView
                        .id(liveActivityManager.contentUpdateID)
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
            .opacity(0)
            .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private var expandedOverlayIcons: some View {
        if currentMode == .defaultWidgets {
            defaultModeIcons
        } else if ![.fileShelfLanding, .snapZones, .dragActivated].contains(currentMode) {
            navigationHeader
        }
    }

    @ViewBuilder
    private var navigationHeader: some View {
        if let config = config {
            ZStack {
                HStack {
                    Button(action: {
                        if navigationStack.count > 1 {
                            navigationStack.removeLast()
                        } else {
                            navigationStack = [.defaultWidgets]
                        }
                    }) {
                        ZStack(alignment: .leading) {
                            Image(systemName: "chevron.left.circle.fill")
                                .font(.title2)
                                .foregroundStyle(.secondary)
                                .symbolRenderingMode(.hierarchical)
                                .padding(.leading, NotchConfiguration.navHeaderLeadingPadding)
                        }
                    }
                    .padding(.top, NotchConfiguration.navHeaderTopPadding)
                    .buttonStyle(.plain)

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
                Spacer()
                HStack(spacing: 0) {
                    ForEach(rightNotchButtons) { buttonType in
                        notchButton(for: buttonType)
                    }
                }
            }
            .padding(.horizontal, NotchConfiguration.defaultModeIconsHorizontalPadding)
            .frame(height: config.initialSize.height)
            .frame(width: animatedWidth)
        }
    }

    @ViewBuilder
    private var geminiButton: some View {
        let isRunning = geminiLiveManager.isSessionRunning
        let baseSize: CGFloat = NotchConfiguration.geminiButtonBaseSize
        let activeGradient = LinearGradient(
            gradient: Gradient(colors: [Color.purple.opacity(0.8), Color.indigo.opacity(0.6)]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        let inactiveGradient = LinearGradient(
            gradient: Gradient(colors: [Color.orange.opacity(0.8), Color.red.opacity(1)]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        Button(action: {
            if isRunning {
                geminiLiveManager.stopSession()
            } else {
                if settings.settings.geminiApiKey.isEmpty {
                    navigationStack.append(.geminiApiKeysMissing)
                } else {
                    pickerHelper.showPicker()
                }
            }
        }) {
            HStack(spacing: 4) {
                Image(systemName: isRunning ? "stop.fill" : "sparkle")
                    .font(.system(size: isGeminiHovered ? NotchConfiguration.geminiButtonActiveIconSize : NotchConfiguration.geminiButtonInactiveIconSize, weight: .medium))
                    .rotationEffect(.degrees(isGeminiHovered ? 90 : 0))
                    .foregroundStyle(
                        isGeminiHovered ?
                        LinearGradient(gradient: Gradient(colors: [Color.white, Color.white.opacity(0.5)]), startPoint: .topLeading, endPoint: .bottomTrailing) :
                        LinearGradient(gradient: Gradient(colors: [Color.blue, Color.pink]), startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .animation(.spring(response: NotchConfiguration.geminiButtonSpringResponse, dampingFraction: NotchConfiguration.geminiButtonSpringDamping), value: isGeminiHovered)

                if isGeminiHovered {
                    Text(isRunning ? "Stop" : "Go live")
                        .font(.system(size: NotchConfiguration.geminiButtonTextFontSize, weight: .semibold))
                        .fixedSize()
                        .foregroundColor(.white)
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                }
            }
            .padding(.horizontal, isGeminiHovered ? NotchConfiguration.geminiButtonActiveHorizontalPadding : 0)
            .frame(width: isGeminiHovered ? nil : baseSize, height: baseSize)
            .background(isGeminiHovered ? (isRunning ? inactiveGradient: activeGradient) : nil)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.spring(response: NotchConfiguration.geminiButtonSpringResponse, dampingFraction: 1)) {
                isGeminiHovered = hovering
            }
        }
    }

    // MARK: - Activity View Builders
    @ViewBuilder
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
            }
        default:
            return nil
        }
    }

    @ViewBuilder
    private func buildLeftView(for data: StandardActivityData) -> some View {
        switch data {
        case .music: AlbumArtView()
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
        case .desktop(let number): DesktopActivityView.left(for: number)
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
        case .nearDrop: NearDropCompactActivityView.left()
        case .hud(let type): SystemHUDSlimActivityView.left(type: type, settings: settings)
        case .lockScreen: LockScreenLiveActivityView.left()
        case .updateAvailable: UpdateAvailableActivityView.left()
        case .unlocked: LockScreenLiveActivityView.left()
        case .stats(let payload): statsLiveActivityView.left(for: payload, selectedStats: settings.settings.selectedStats, selectedSensorKeys: settings.settings.selectedSensorKeys)
        }
    }

    @ViewBuilder
    private func buildRightView(for data: StandardActivityData) -> some View {
        switch data {
        case .music: WaveformView()
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
        case .desktop(let number): DesktopActivityView.right(for: number)
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
        case .geminiLive(let payload): GeminiActiveActivityView.right(isMuted: payload.isMicMuted) { geminiLiveManager.isMicMuted.toggle() }
        case .nearDrop(let payload): NearDropCompactActivityView.right(payload: payload)
        case .hud(let type): SystemHUDSlimActivityView.right(type: type, settings: SettingsModel.shared)
        case .lockScreen: LockScreenLiveActivityView.right()
        case .updateAvailable(let version): UpdateAvailableActivityView.right(version: version)
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
        case .gemini:
            if settings.settings.geminiEnabled {
                geminiButton
            }
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
            if showMultiAudioIcon {
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

        NotificationCenter.default.addObserver(forName: .fileDropFlowCompleted, object: nil, queue: .main) { _ in
            guard let config = self.config else { return }
            self.awaitingDropCompletion = false
            if self.notchState == .clickExpanded && !self.isPinned {
                self.scheduleCollapse(after: config.widgetSwitchCollapseDelay)
            }
        }

        updateMouseEventHandling(isInteractive: isInteractive)
        updateWindowSharingBehavior(shouldBeHidden: shouldHideWindowForSharing)
    }

    private func teardownMonitors() {
        dragManager.stopMonitoring()
        TrackpadGestureHandler.shared.stopMonitoring()
        TrackpadGestureHandler.shared.onSwipe = nil
        TrackpadGestureHandler.shared.onTwoFingerTap = nil
        NotificationCenter.default.removeObserver(self, name: .fileDropFlowCompleted, object: nil)
        collapseTask?.cancel()
        cancellables.removeAll()
        MenuBarInteractionManager.shared.startMonitoring()
    }

    // MARK: - Event Handlers
    private func handleTap() {
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
            if activityType == .calendar, settings.settings.calendarOpenOnClick { initiateWidgetView(.calendarPlayer); return }
            if activityType == .fileShelf, settings.settings.clickToOpenFileShelf { initiateWidgetView(.fileShelf); return }
            if activityType == .timer, settings.settings.clickToShowTimerView { initiateWidgetView(.timerDetailView); return }
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
        guard let config = config else { return }
        self.isHovered = hovering

        if hovering {
            TrackpadGestureHandler.shared.startMonitoring()
        } else {
            TrackpadGestureHandler.shared.stopMonitoring()
        }

        if hovering {
            collapseTask?.cancel()
            isCollapseTimerActive = false
            let activityType = liveActivityManager.currentActivity

            if activityType == .fileShelf, settings.settings.hoverToOpenFileShelf {
                if notchState != .clickExpanded {
                    navigationStack = [.fileShelf]
                    notchState = .clickExpanded
                }
        } else if settings.settings.expandOnHover && !isFullViewActivity {
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
                    notchState = .clickExpanded
                }
            } else {
                if notchState == .initial || notchState == .autoExpanded {
                    notchState = .hoverExpanded
                    haptic()
                }
            }
        } else {
            if !isCollapseTimerActive {
                scheduleCollapse(after: config.collapseAnimationDelay)
            }
        }
    }

    private func handleActivityChange(_ newActivity: ActivityType) {
        guard notchState != .clickExpanded, let config = config else { return }

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

        notchState = newActivity != .none ? .autoExpanded : .initial
        updateFPS()
    }

    private func handleStateChange(from oldState: NotchState, to newState: NotchState) {
        guard let config = config else { return }

        let isContentUpdate = oldState == newState
        let animation: Animation
        if isContentUpdate {
            animation = config.bottomContentAnimation
        } else {
            switch newState {
            case .initial:
                animation = .spring(response: 0.12, dampingFraction: 1.0)
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
        }

        if isContentUpdate { return }

        switch newState {
        case .initial:
            let wasShowingActivity = (oldState == .autoExpanded || oldState == .hoverExpanded)
            if wasShowingActivity { isAnimatingActivityOut = true }
            self.canRenderAutoContent = false
            collapseTask?.cancel(); isCollapseTimerActive = false

            withAnimation(.spring(response: 0.12, dampingFraction: 1.0)) {
                shadowOpacity = 0
                if wasShowingActivity { activityBlurRadius = 20; activityContentScale = 0.9; autoContentOpacity = 0 }
                animatedWidth = config.initialSize.width; animatedHeight = config.initialSize.height
                animatedContentScale = 1.0
                isPinned = false
            }
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
        if oldStack.contains(.snapZones) && !newStack.contains(.snapZones) {
            SnapPreviewManager.shared.hidePreview()
        }

        if notchState == .clickExpanded && oldStack != newStack {
            self.expansionAnimation = config.widgetSwitchAnimation
        }

        if notchState == .clickExpanded {
            if settings.settings.rememberLastMenu {
                let restorableStack = newStack.compactMap { toRestorableMenu(mode: $0) }
                if !restorableStack.isEmpty {
                    settings.settings.lastNotchNavigationStack = restorableStack
                }
            }
        }

        if notchState == .clickExpanded && newStack != [.defaultWidgets] {
            scheduleCollapse(after: config.widgetSwitchCollapseDelay)
        }
    }

    private func handleItemDrop(providers: [NSItemProvider]) -> Bool {
        let capturedDropZone = determineActiveDropZone()
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

            startHoverDetection()

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
            stopHoverDetection()
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
            guard abs(newSize.width - animatedWidth) > 1 || abs(newSize.height - animatedHeight) > 1 else { return }
            withAnimation(self.expansionAnimation) {
                animatedWidth = newSize.width
                animatedHeight = newSize.height
            }
        } else if state == .autoExpanded {
            updateAutoContentSize()
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

        if (notchState == .initial || notchState == .hoverExpanded) {
            let verticalThreshold: CGFloat = 10.0
            if abs(vector.dy) > abs(vector.dx) && abs(vector.dy) > verticalThreshold {
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

            if abs(vector.dx) > abs(vector.dy) && abs(vector.dx) > 10 {
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

                    } else {
                        let switchableModes = self.switchableWidgetModes
                        if !switchableModes.isEmpty, let currentIndex = switchableModes.firstIndex(of: currentMode) {
                            let nextIndex = (currentIndex + 1) % switchableModes.count
                            let nextMode = switchableModes[nextIndex]
                            if !navigationStack.isEmpty {
                                navigationStack[navigationStack.count - 1] = nextMode
                            }
                        }
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
                    musicWidget.nextTrack()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        if musicWidget.transientIcon == .skippedForward { musicWidget.transientIcon = nil }
                    }
                } else if shouldGoBackward && settings.settings.swipeToRewindMusic {
                    haptic()
                    musicWidget.transientIcon = .skippedBackward
                    musicWidget.previousTrack()
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

    private func handleTrackpadTwoFingerTap() {
        guard (notchState == .autoExpanded || notchState == .hoverExpanded) else { return }

        if settings.settings.twoFingerTapToPauseMusic {
            haptic()
            musicWidget.transientIcon = musicWidget.isPlaying ? .paused : .played
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                if musicWidget.transientIcon == .paused || musicWidget.transientIcon == .played {
                    musicWidget.transientIcon = nil
                }
            }
            musicWidget.isPlaying ? musicWidget.pause() : musicWidget.play()
        }
    }

    // MARK: - Helper Methods
    private func startHoverDetection() {
        stopHoverDetection()
        hoverDetectionTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            let newActiveZone = self.determineActiveDropZone()
            if self.activeDropZone != newActiveZone {
                self.activeDropZone = newActiveZone
            }
        }
    }

    private func determineActiveDropZone() -> DropZone? {
        guard let mainScreen = NSScreen.main else { return nil }
        let mouseLocation = NSEvent.mouseLocation
        let globalMousePoint = CGPoint(x: mouseLocation.x, y: mainScreen.frame.height - mouseLocation.y)

        for (zone, frame) in self.dropZoneFrames {
            if frame.contains(globalMousePoint) {
                return zone
            }
        }
        return nil
    }

    private func stopHoverDetection() {
        hoverDetectionTimer?.invalidate()
        hoverDetectionTimer = nil
        if activeDropZone != nil {
            activeDropZone = nil
        }
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
        case .musicApiKeysMissing, .geminiApiKeysMissing, .musicLoginPrompt, .musicLyrics,
                .musicPlaylistDetail, .snapZones, .fileShelfLanding, .fileActionPreview,
                .multiAudioDeviceAdjust, .multiAudioEQ, .dragActivated:
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
        let targetFPS = isLiveActivityActive ? 120 : 30
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
        guard notchWindow?.contentView != nil else { return }
        let shouldIgnore = !isInteractive
        if notchWindow?.ignoresMouseEvents != shouldIgnore {
            notchWindow?.ignoresMouseEvents = shouldIgnore
        }
    }

    private func updateWindowSharingBehavior(shouldBeHidden: Bool) {
        guard let window = notchWindow else { return }
        let desired: NSWindow.SharingType = shouldBeHidden ? .none : .readOnly
        if window.sharingType != desired {
            window.sharingType = desired
        }
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
                }
                self.isCollapseTimerActive = false
            } catch {
                self.isCollapseTimerActive = false
            }
        }
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
    var activityHasBottomContent: Bool {
        switch activityContent {
        case .full:
            return true
        case .standard(let data, _):
            switch data {
            case .music(let bottomContentType):
                return bottomContentType != .none
            default:
                return false
            }
        case .none:
            return false
        }
    }
}
