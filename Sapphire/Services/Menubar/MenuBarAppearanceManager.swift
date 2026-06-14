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

@MainActor
final class MenuBarAppearanceManager {
    // Coalescer to batch frequent refresh requests and avoid redundant work
    private struct RefreshCoalescer {
        var pending = false
        var lastRequest: CFTimeInterval = 0
    }
    private var coalescer = RefreshCoalescer()
    // Removed: private let refreshQueue = DispatchQueue(label: "MenuBarAppearanceManager.refresh", qos: .userInitiated)
    
    enum PanelType { case full, left, right }
    private var overlayPanels = [NSScreen: [PanelType: MenuBarOverlayPanel]]()
    private var cancellables = Set<AnyCancellable>()
    private var isMissionControlActive = false

    // Cache last applied frames per screen and panel type to skip no-op updates
    private var lastFrames = [NSScreen: [PanelType: CGRect]]()

    init() {
        print("[AppearanceManager] Initializing.")
        setupObservers()
        NotificationCenter.default.addObserver(self, selector: #selector(scheduleRefresh), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(scheduleRefresh), name: .activeAppDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(scheduleRefresh), name: .menuBarHidingStateDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(scheduleRefresh), name: NSApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(scheduleRefresh), name: NSApplication.didResignActiveNotification, object: nil)
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
        SettingsModel.shared.$settings
            .debounce(for: .milliseconds(200), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.scheduleRefresh() }
            .store(in: &cancellables)
    }

    @objc private func scheduleRefresh() {
        let now = CACurrentMediaTime()
        // Mark that a refresh is pending; we batch events within 150ms window
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

    @objc private func refreshAppearanceWithDelay() {
        scheduleRefresh()
    }
    
    private func refreshAppearanceImmediately() {
        self.applyAppearance(from: SettingsModel.shared.settings)
    }

    // MARK: - Appearance Logic

    private func applyAppearance(from settings: Settings) {
        let isAnyEffectEnabled = settings.menuBarTintStyle != "none" || settings.menuBarBorderWidth > 0 || settings.menuBarShadowEnabled || settings.menuBarShapeStyle != "none" || settings.menuBarBlur || settings.menuBarLiquidGlass
        
        // Avoid heavy updates while Mission Control is active; panels will update when it ends
        if isMissionControlActive { return }

        guard isAnyEffectEnabled else {
            removeAllOverlays(); return
        }

        let useSplit = settings.menuBarShapeStyle == "roundedSplit"
        for screen in NSScreen.screens {
            var panelsForScreen = overlayPanels[screen] ?? [:]

            if useSplit {
                panelsForScreen[.full]?.close(); panelsForScreen.removeValue(forKey: .full)
                let (leftFrame, rightFrame) = framesForSplitMode(on: screen, settings: settings)
                let cached = lastFrames[screen] ?? [:]
                if cached[.left] != leftFrame {
                    panelsForScreen[.left] = createOrUpdatePanel(for: .left, frame: leftFrame, settings: settings, existingPanel: panelsForScreen[.left])
                }
                if cached[.right] != rightFrame {
                    panelsForScreen[.right] = createOrUpdatePanel(for: .right, frame: rightFrame, settings: settings, existingPanel: panelsForScreen[.right])
                }
                var updated = cached
                updated[.left] = leftFrame
                updated[.right] = rightFrame
                lastFrames[screen] = updated
            } else {
                panelsForScreen[.left]?.close(); panelsForScreen.removeValue(forKey: .left)
                panelsForScreen[.right]?.close(); panelsForScreen.removeValue(forKey: .right)
                let frame = frameForFullMode(on: screen, settings: settings)
                let cached = lastFrames[screen] ?? [:]
                if cached[.full] != frame {
                    panelsForScreen[.full] = createOrUpdatePanel(for: .full, frame: frame, settings: settings, existingPanel: panelsForScreen[.full])
                }
                var updated = cached
                updated[.full] = frame
                lastFrames[screen] = updated
            }
            overlayPanels[screen] = panelsForScreen
        }
    }

    private func createOrUpdatePanel(for type: PanelType, frame: CGRect, settings: Settings, existingPanel: MenuBarOverlayPanel?) -> MenuBarOverlayPanel {
        if let panel = existingPanel {
            panel.updateAppearance(with: settings, frame: frame, type: type, isMissionControlActive: isMissionControlActive)
            return panel
        } else {
            let panel = MenuBarOverlayPanel(settings: settings, frame: frame, type: type, isMissionControlActive: isMissionControlActive)
            panel.orderFrontRegardless()
            return panel
        }
    }

    private func framesForSplitMode(on screen: NSScreen, settings: Settings) -> (CGRect, CGRect) {
        let vPadding = settings.menuBarVerticalPadding
        let hPadding = vPadding > 0 ? max(vPadding, 6.0) : 0
        let totalMenuBarHeight = screen.frame.height - screen.visibleFrame.height
        let paddedHeight = max(0, totalMenuBarHeight - (vPadding * 2))
        let yPos = screen.frame.maxY - totalMenuBarHeight + vPadding
        let screenFrame = screen.frame
        let sidePadding: CGFloat = 8.0

        let leftWidth = (WindowInfo.getApplicationMenuFrame(for: screen.displayID)?.width ?? 0) + sidePadding

        // Compute rightX lazily; only detect items if we don't have a cached minX
        var rightX: CGFloat = screenFrame.maxX - sidePadding
        do {
            let allItems = MenuBarItemDetector.detectItemsWithInfo().filter { screenFrame.intersects($0.frame) }
            if let minX = allItems.first(where: { $0.bundleIdentifier?.hasPrefix("com.apple.") ?? false })?.frame.minX {
                rightX = minX - sidePadding
            }
        }

        let leftFrame = CGRect(x: screenFrame.minX + hPadding, y: yPos, width: max(0, leftWidth - hPadding), height: paddedHeight)
        let rightFrame = CGRect(x: rightX, y: yPos, width: max(0, (screenFrame.maxX - rightX) - hPadding), height: paddedHeight)

        return (leftFrame, rightFrame)
    }

    private func frameForFullMode(on screen: NSScreen, settings: Settings) -> CGRect {
        let vPadding = settings.menuBarVerticalPadding
        let hPadding = vPadding > 0 ? 8.0 : 0
        let totalMenuBarHeight = screen.frame.height - screen.visibleFrame.height
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
        @Published var settings: Settings
        @Published var panelType: MenuBarAppearanceManager.PanelType
        @Published var isMissionControlActive: Bool
        init(settings: Settings, panelType: MenuBarAppearanceManager.PanelType, isMissionControlActive: Bool) {
            self.settings = settings
            self.panelType = panelType
            self.isMissionControlActive = isMissionControlActive
        }
    }
    private let appearanceModel: AppearanceModel
    private let hostingView: NSHostingView<MenuBarAppearanceView>

    init(settings: Settings, frame: CGRect, type: MenuBarAppearanceManager.PanelType, isMissionControlActive: Bool) {
        self.panelType = type
        let model = AppearanceModel(settings: settings, panelType: type, isMissionControlActive: isMissionControlActive)
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

    func updateAppearance(with settings: Settings, frame: CGRect, type: MenuBarAppearanceManager.PanelType, isMissionControlActive: Bool) {
        self.panelType = type
        let needsFrameChange = self.frame != frame
        if needsFrameChange {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.15
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                self.animator().setFrame(frame, display: true)
            }
        }
        // Update the SwiftUI root view efficiently by updating the model only
        if appearanceModel.settings != settings { appearanceModel.settings = settings }
        if appearanceModel.panelType != type { appearanceModel.panelType = type }
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
        default:
            return AnyShapeStyle(.clear)
        }
    }

    private var borderColor: Color {
        model.settings.menuBarBorderColor.color
    }

    @ViewBuilder
    private func liquidGlassOverlay(shape: AnyShape) -> some View {
        if #available(macOS 26.0, *) {
            shape.fill(.clear).glassEffect()
        } else {
            LinearGradient(colors: [.white.opacity(0.25), .clear], startPoint: .top, endPoint: .bottom)
                .blendMode(.overlay)
                .blur(radius: 2)
        }
    }
}

