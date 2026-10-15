//
//  MenuBarAppearanceManager.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-11-08
//

import Cocoa
import Combine
import SwiftUI
import QuartzCore

fileprivate struct MenuBarAppearanceSettings: Equatable {
    let menuBarTintStyle: String
    let menuBarSolidColor: CodableColor
    let menuBarGradientColors: [CodableColor]
    let menuBarGradientAngle: Double
    let menuBarOpacity: Double
    let menuBarBlur: Bool
    let menuBarLiquidGlass: Bool
    let menuBarLiquidGlassStyle: LiquidGlassMaterial
    let menuBarBorderWidth: CGFloat
    let menuBarBorderColor: CodableColor
    let menuBarShadowEnabled: Bool
    let menuBarShapeStyle: String
    let menuBarCornerRadius: CGFloat
    let menuBarVerticalPadding: CGFloat
    let menuBarAdaptiveTintGradient: Bool

    init(_ settings: Settings) {
        menuBarTintStyle = settings.menuBarTintStyle
        menuBarSolidColor = settings.menuBarSolidColor
        menuBarGradientColors = settings.menuBarGradientColors
        menuBarGradientAngle = settings.menuBarGradientAngle
        menuBarOpacity = settings.menuBarOpacity
        menuBarBlur = settings.menuBarBlur
        menuBarLiquidGlass = settings.menuBarLiquidGlass
        menuBarLiquidGlassStyle = settings.menuBarLiquidGlassStyle
        menuBarBorderWidth = settings.menuBarBorderWidth
        menuBarBorderColor = settings.menuBarBorderColor
        menuBarShadowEnabled = settings.menuBarShadowEnabled
        menuBarShapeStyle = settings.menuBarShapeStyle
        menuBarCornerRadius = settings.menuBarCornerRadius
        menuBarVerticalPadding = settings.menuBarVerticalPadding
        menuBarAdaptiveTintGradient = settings.menuBarAdaptiveTintGradient
    }
}

@MainActor
final class MenuBarAppearanceManager {
    private struct RefreshCoalescer {
        var pending = false
        var lastRequest: CFTimeInterval = 0
    }
    private var coalescer = RefreshCoalescer()

    enum PanelType { case full, left, right }
    private var overlayPanels = [CGDirectDisplayID: [PanelType: MenuBarOverlayPanel]]()
    private var cancellables = Set<AnyCancellable>()
    private var isMissionControlActive = false

    init() {
        print("[AppearanceManager] Initializing.")
        setupObservers()
        NotificationCenter.default.addObserver(self, selector: #selector(scheduleRefresh), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(scheduleRefresh), name: .activeAppDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(scheduleRefresh), name: .menuBarHidingStateDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(scheduleRefresh), name: NSApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(scheduleRefresh), name: NSApplication.didResignActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(catalogDidChange), name: .menuBarItemCatalogDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(scheduleRefresh), name: .menuBarWallpaperTintDidChange, object: nil)
        scheduleRefresh()
    }

    deinit {
        print("[AppearanceManager] Deinitializing.")
        let panelsToClose = overlayPanels.values.flatMap { $0.values }
        overlayPanels.removeAll()
        DispatchQueue.main.async { for panel in panelsToClose { panel.close() } }
        NotificationCenter.default.removeObserver(self)
    }

    private func setupObservers() {
        SettingsModel.shared.changes(of: MenuBarAppearanceSettings.init)
            .debounce(for: .milliseconds(200), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.scheduleRefresh() }
            .store(in: &cancellables)
    }

    @objc private func scheduleRefresh() {
        let now = CACurrentMediaTime()
        if !coalescer.pending {
            coalescer.pending = true
            coalescer.lastRequest = now
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                guard let self = self else { return }
                self.coalescer.pending = false
                self.refreshAppearanceImmediately()
            }
        } else {
            coalescer.lastRequest = now
        }
    }

    @objc private func catalogDidChange() {
        guard SettingsModel.shared.current.menuBarShapeStyle == "roundedSplit" else { return }
        scheduleRefresh()
    }

    @objc private func refreshAppearanceWithDelay() {
        scheduleRefresh()
    }

    private func refreshAppearanceImmediately() {
        let settings = MenuBarAppearanceSettings(SettingsModel.shared.settings)
        guard settings.menuBarShapeStyle == "roundedSplit" else {
            applyAppearance(from: settings, splitGeometry: nil)
            return
        }
        splitGeometryGeneration += 1
        let generation = splitGeometryGeneration
        let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier
        MenuBarItemCatalog.shared.start()
        MenuBarItemCatalog.shared.items(maxAge: 1.0) { [weak self] items in
            let itemFrames = items.filter(\.isOnScreen).map(\.frame)
            DispatchQueue.global(qos: .userInitiated).async {
                let menuFrame = pid.flatMap { MenuBarHitTest.applicationMenuFrame(pid: $0) }
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        guard let self, generation == self.splitGeometryGeneration else { return }
                        self.applyAppearance(
                            from: MenuBarAppearanceSettings(SettingsModel.shared.settings),
                            splitGeometry: SplitGeometry(applicationMenuFrame: menuFrame, statusItemFrames: itemFrames)
                        )
                    }
                }
            }
        }
    }

    private struct SplitGeometry {
        let applicationMenuFrame: CGRect?
        let statusItemFrames: [CGRect]
    }
    private var splitGeometryGeneration = 0

    // MARK: - Appearance Logic

    private func applyAppearance(from settings: MenuBarAppearanceSettings, splitGeometry: SplitGeometry?) {
        if settings.menuBarTintStyle == "adaptive" {
            MenuBarWallpaperTint.shared.start()
        } else {
            MenuBarWallpaperTint.shared.stop()
        }
        let isAnyEffectEnabled = settings.menuBarTintStyle != "none" || settings.menuBarBorderWidth > 0 || settings.menuBarShadowEnabled || settings.menuBarShapeStyle != "none" || settings.menuBarBlur || settings.menuBarLiquidGlass

        if isMissionControlActive { return }

        guard isAnyEffectEnabled else {
            removeAllOverlays(); return
        }

        let screens = NSScreen.screens
        removeOverlays(forDisplaysNotIn: Set(screens.map(\.displayID)))

        let useSplit = settings.menuBarShapeStyle == "roundedSplit"
        for screen in screens {
            let displayID = screen.displayID
            var panelsForScreen = overlayPanels[displayID] ?? [:]
            let adaptiveTint = settings.menuBarTintStyle == "adaptive" ? MenuBarWallpaperTint.shared.tint(for: displayID) : nil

            if useSplit {
                panelsForScreen[.full]?.close(); panelsForScreen.removeValue(forKey: .full)
                let (leftFrame, rightFrame) = framesForSplitMode(on: screen, settings: settings, geometry: splitGeometry)
                panelsForScreen[.left] = createOrUpdatePanel(for: .left, frame: leftFrame, settings: settings, adaptiveTint: adaptiveTint, existingPanel: panelsForScreen[.left])
                panelsForScreen[.right] = createOrUpdatePanel(for: .right, frame: rightFrame, settings: settings, adaptiveTint: adaptiveTint, existingPanel: panelsForScreen[.right])
            } else {
                panelsForScreen[.left]?.close(); panelsForScreen.removeValue(forKey: .left)
                panelsForScreen[.right]?.close(); panelsForScreen.removeValue(forKey: .right)
                let frame = frameForFullMode(on: screen, settings: settings)
                panelsForScreen[.full] = createOrUpdatePanel(for: .full, frame: frame, settings: settings, adaptiveTint: adaptiveTint, existingPanel: panelsForScreen[.full])
            }
            overlayPanels[displayID] = panelsForScreen
        }
    }

    private func removeOverlays(forDisplaysNotIn activeDisplayIDs: Set<CGDirectDisplayID>) {
        let removedDisplayIDs = overlayPanels.keys.filter { !activeDisplayIDs.contains($0) }
        for displayID in removedDisplayIDs {
            overlayPanels.removeValue(forKey: displayID)?.values.forEach { $0.close() }
        }
    }

    private func createOrUpdatePanel(for type: PanelType, frame: CGRect, settings: MenuBarAppearanceSettings, adaptiveTint: MenuBarWallpaperTint.Tint?, existingPanel: MenuBarOverlayPanel?) -> MenuBarOverlayPanel {
        if let panel = existingPanel {
            panel.updateAppearance(with: settings, frame: frame, type: type, adaptiveTint: adaptiveTint, isMissionControlActive: isMissionControlActive)
            return panel
        } else {
            let panel = MenuBarOverlayPanel(settings: settings, frame: frame, type: type, adaptiveTint: adaptiveTint, isMissionControlActive: isMissionControlActive)
            panel.orderFrontRegardless()
            return panel
        }
    }

    private func framesForSplitMode(on screen: NSScreen, settings: MenuBarAppearanceSettings, geometry: SplitGeometry?) -> (CGRect, CGRect) {
        let vPadding = settings.menuBarVerticalPadding
        let hPadding = vPadding > 0 ? max(vPadding, 6.0) : 0
        let totalMenuBarHeight = NotchDisplayMetrics.menuBarGap(frame: screen.frame, visibleFrame: screen.visibleFrame)
        let paddedHeight = max(0, totalMenuBarHeight - (vPadding * 2))
        let yPos = screen.frame.maxY - totalMenuBarHeight + vPadding
        let screenFrame = screen.frame
        let sidePadding: CGFloat = 8.0
        let axScreenFrame = AX.axRect(fromCocoaRect: screenFrame) ?? screenFrame

        var menuWidth: CGFloat = 0
        if let menuFrame = geometry?.applicationMenuFrame {
            let owner = NSScreen.screens.first { $0.frame.minX <= menuFrame.minX && menuFrame.minX < $0.frame.maxX }
            menuWidth = max(0, menuFrame.maxX - (owner?.frame.minX ?? screenFrame.minX))
        }
        let leftWidth = menuWidth + sidePadding

        var rightX: CGFloat = screenFrame.maxX - sidePadding
        if let minX = geometry?.statusItemFrames.filter({ axScreenFrame.intersects($0) }).map(\.minX).min() {
            rightX = minX - sidePadding
        }

        let leftFrame = CGRect(x: screenFrame.minX + hPadding, y: yPos, width: max(0, leftWidth - hPadding), height: paddedHeight)
        let rightFrame = CGRect(x: rightX, y: yPos, width: max(0, (screenFrame.maxX - rightX) - hPadding), height: paddedHeight)

        return (leftFrame, rightFrame)
    }

    private func frameForFullMode(on screen: NSScreen, settings: MenuBarAppearanceSettings) -> CGRect {
        let vPadding = settings.menuBarVerticalPadding
        let hPadding = vPadding > 0 ? 8.0 : 0
        let totalMenuBarHeight = NotchDisplayMetrics.menuBarGap(frame: screen.frame, visibleFrame: screen.visibleFrame)
        let paddedHeight = max(0, totalMenuBarHeight - (vPadding * 2))
        let yPos = screen.frame.maxY - totalMenuBarHeight + vPadding

        return CGRect(x: screen.frame.origin.x + hPadding, y: yPos, width: screen.frame.width - (hPadding * 2), height: paddedHeight)
    }

    private func removeAllOverlays() {
        for screenPanels in overlayPanels.values {
            for panel in screenPanels.values { panel.close() }
        }
        overlayPanels.removeAll()
    }
}

// MARK: - Overlay Panel
fileprivate class MenuBarOverlayPanel: NSPanel {
    private var panelType: MenuBarAppearanceManager.PanelType

    final class AppearanceModel: ObservableObject {
        @Published var settings: MenuBarAppearanceSettings
        @Published var panelType: MenuBarAppearanceManager.PanelType
        @Published var isMissionControlActive: Bool
        @Published var adaptiveTint: MenuBarWallpaperTint.Tint?
        init(settings: MenuBarAppearanceSettings, panelType: MenuBarAppearanceManager.PanelType, adaptiveTint: MenuBarWallpaperTint.Tint?, isMissionControlActive: Bool) {
            self.settings = settings
            self.panelType = panelType
            self.adaptiveTint = adaptiveTint
            self.isMissionControlActive = isMissionControlActive
        }
    }
    private let appearanceModel: AppearanceModel
    private let hostingView: NSHostingView<MenuBarAppearanceView>

    init(settings: MenuBarAppearanceSettings, frame: CGRect, type: MenuBarAppearanceManager.PanelType, adaptiveTint: MenuBarWallpaperTint.Tint?, isMissionControlActive: Bool) {
        self.panelType = type
        let model = AppearanceModel(settings: settings, panelType: type, adaptiveTint: adaptiveTint, isMissionControlActive: isMissionControlActive)
        self.appearanceModel = model
        let root = MenuBarAppearanceView(model: model)
        self.hostingView = NSHostingView(rootView: root)
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        self.level = .statusBar - 1
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.ignoresMouseEvents = true
        self.collectionBehavior = [.canJoinAllSpaces]
        self.animationBehavior = .utilityWindow
        self.contentView = hostingView
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func updateAppearance(with settings: MenuBarAppearanceSettings, frame: CGRect, type: MenuBarAppearanceManager.PanelType, adaptiveTint: MenuBarWallpaperTint.Tint?, isMissionControlActive: Bool) {
        self.panelType = type
        let needsFrameChange = self.frame != frame
        if needsFrameChange {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.15
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                self.animator().setFrame(frame, display: true)
            }
        }
        if appearanceModel.settings != settings { appearanceModel.settings = settings }
        if appearanceModel.panelType != type { appearanceModel.panelType = type }
        if appearanceModel.adaptiveTint != adaptiveTint { appearanceModel.adaptiveTint = adaptiveTint }
        if appearanceModel.isMissionControlActive != isMissionControlActive { appearanceModel.isMissionControlActive = isMissionControlActive }
    }
}

// MARK: - SwiftUI Appearance View
fileprivate struct MenuBarAppearanceView: View {
    @ObservedObject var model: MenuBarOverlayPanel.AppearanceModel

    var body: some View {
        appearanceContent
            .modifier(ConditionalShadow(enabled: model.settings.menuBarShadowEnabled))
            .opacity(model.isMissionControlActive ? 0.0 : model.settings.menuBarOpacity)
            .animation(.easeOut(duration: 0.2), value: model.isMissionControlActive)
    }

    private struct ConditionalShadow: ViewModifier {
        let enabled: Bool
        func body(content: Content) -> some View {
            if enabled {
                content.shadow(color: .black.opacity(0.35), radius: 5, y: -2)
            } else {
                content
            }
        }
    }

    @ViewBuilder
    private var appearanceContent: some View {
        let cornerRadius = model.settings.menuBarCornerRadius

        switch model.settings.menuBarShapeStyle {
        case "rounded", "roundedSplit":
            let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            createInsettableStyledView(for: shape)

        default:
            if model.settings.menuBarLiquidGlass {
                let shape = UnevenRoundedRectangle(bottomLeadingRadius: cornerRadius, bottomTrailingRadius: cornerRadius)
                createStyledView(for: shape)
            } else {
                let shape = Rectangle()
                createInsettableStyledView(for: shape)
            }
        }
    }

    private func createInsettableStyledView<S: InsettableShape>(for shape: S) -> some View {
        shape
            .fill(tint)
            .background(model.settings.menuBarBlur ? shape.fill(.ultraThinMaterial) : nil)
            .overlay(alignment: .center) {
                if model.settings.menuBarLiquidGlass || model.settings.menuBarBorderWidth > 0 {
                    ZStack {
                        if model.settings.menuBarLiquidGlass { liquidGlassOverlay(shape: AnyShape(shape)) }
                        if model.settings.menuBarBorderWidth > 0 {
                            shape.strokeBorder(borderColor, lineWidth: model.settings.menuBarBorderWidth)
                        }
                    }
                }
            }
    }

    private func createStyledView<S: Shape>(for shape: S) -> some View {
        shape
            .fill(tint)
            .background(model.settings.menuBarBlur ? shape.fill(.ultraThinMaterial) : nil)
            .overlay(alignment: .center) {
                if model.settings.menuBarLiquidGlass || model.settings.menuBarBorderWidth > 0 {
                    ZStack {
                        if model.settings.menuBarLiquidGlass { liquidGlassOverlay(shape: AnyShape(shape)) }
                        if model.settings.menuBarBorderWidth > 0 {
                            shape.stroke(borderColor, lineWidth: model.settings.menuBarBorderWidth)
                        }
                    }
                }
            }
    }

    private var tint: AnyShapeStyle {
        switch model.settings.menuBarTintStyle {
        case "solid":
            return AnyShapeStyle(model.settings.menuBarSolidColor.color)
        case "gradient":
            let angle = Angle(degrees: model.settings.menuBarGradientAngle)
            let startPoint = UnitPoint(x: 0.5 + sin(angle.radians) / 2, y: 0.5 - cos(angle.radians) / 2)
            let endPoint = UnitPoint(x: 0.5 - sin(angle.radians) / 2, y: 0.5 + cos(angle.radians) / 2)
            let stops = model.settings.menuBarGradientColors.map { Gradient.Stop(color: $0.color, location: $0.location) }
            return AnyShapeStyle(LinearGradient(stops: stops, startPoint: startPoint, endPoint: endPoint))
        case "adaptive":
            guard let adaptive = model.adaptiveTint else { return AnyShapeStyle(.clear) }
            if model.settings.menuBarAdaptiveTintGradient {
                return AnyShapeStyle(LinearGradient(
                    colors: [Color(nsColor: adaptive.leading), Color(nsColor: adaptive.trailing)],
                    startPoint: .leading,
                    endPoint: .trailing
                ))
            }
            return AnyShapeStyle(Color(nsColor: adaptive.average))
        default:
            return AnyShapeStyle(.clear)
        }
    }

    private var borderColor: Color {
        model.settings.menuBarBorderColor.color
    }

    @ViewBuilder
    private func liquidGlassOverlay(shape: AnyShape) -> some View {
        ZStack {
            LiquidGlassShapeFill(
                material: model.settings.menuBarLiquidGlassStyle,
                shape: shape,
                blendingMode: .behindWindow,
                appearance: .auto,
                shapePathCacheKey: AnyHashable(
                    "menu-bar-\(model.settings.menuBarShapeStyle)-\(model.settings.menuBarCornerRadius)"
                )
            )
            if model.settings.menuBarBlur {
                VisualEffectView(material: .fullScreenUI, blendingMode: .behindWindow)
                    .clipShape(shape)
                VisualEffectView(material: .hudWindow, blendingMode: .withinWindow)
                    .clipShape(shape)
                    .opacity(0.7)
                shape
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.28),
                                Color.white.opacity(0.1)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
        }
    }
}