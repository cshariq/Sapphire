//
//  MenuBarAppearanceManager.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-11-08
//

import Cocoa
import Combine
import SwiftUI

@MainActor
final class MenuBarAppearanceManager {
    enum PanelType { case full, left, right }
    private var overlayPanels = [NSScreen: [PanelType: MenuBarOverlayPanel]]()
    private var cancellables = Set<AnyCancellable>()
    private var isMissionControlActive = false

    init() {
        print("[AppearanceManager] Initializing.")
        setupObservers()
        NotificationCenter.default.addObserver(self, selector: #selector(refreshAppearanceWithDelay), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(refreshAppearanceWithDelay), name: .activeAppDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(refreshAppearanceWithDelay), name: .menuBarHidingStateDidChange, object: nil)
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
            .debounce(for: .milliseconds(100), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshAppearanceWithDelay() }
            .store(in: &cancellables)
    }

    @objc private func refreshAppearanceWithDelay() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            self.applyAppearance(from: SettingsModel.shared.settings)
        }
    }

    private func refreshAppearanceImmediately() {
        self.applyAppearance(from: SettingsModel.shared.settings)
    }

    // MARK: - Appearance Logic

    private func applyAppearance(from settings: Settings) {
        let isAnyEffectEnabled = settings.menuBarTintStyle != "none" || settings.menuBarBorderWidth > 0 || settings.menuBarShadowEnabled || settings.menuBarShapeStyle != "none" || settings.menuBarBlur || settings.menuBarLiquidGlass

        guard isAnyEffectEnabled else {
            removeAllOverlays(); return
        }

        for screen in NSScreen.screens {
            var panelsForScreen = overlayPanels[screen] ?? [:]

            if settings.menuBarShapeStyle == "roundedSplit" {
                panelsForScreen[.full]?.close(); panelsForScreen.removeValue(forKey: .full)
                let (leftFrame, rightFrame) = framesForSplitMode(on: screen, settings: settings)
                panelsForScreen[.left] = createOrUpdatePanel(for: .left, frame: leftFrame, settings: settings, existingPanel: panelsForScreen[.left])
                panelsForScreen[.right] = createOrUpdatePanel(for: .right, frame: rightFrame, settings: settings, existingPanel: panelsForScreen[.right])
            } else {
                panelsForScreen[.left]?.close(); panelsForScreen.removeValue(forKey: .left)
                panelsForScreen[.right]?.close(); panelsForScreen.removeValue(forKey: .right)
                let frame = frameForFullMode(on: screen, settings: settings)
                panelsForScreen[.full] = createOrUpdatePanel(for: .full, frame: frame, settings: settings, existingPanel: panelsForScreen[.full])
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

        let allItems = MenuBarItemDetector.detectItemsWithInfo().filter { screenFrame.intersects($0.frame) }
        let systemItems = allItems.filter { $0.bundleIdentifier?.hasPrefix("com.apple.") ?? false }
        let rightX = (systemItems.map(\.frame.minX).min() ?? screenFrame.maxX) - sidePadding

        let leftFrame = CGRect(x: screenFrame.minX + hPadding, y: yPos, width: leftWidth - hPadding, height: paddedHeight)
        let rightFrame = CGRect(x: rightX, y: yPos, width: (screenFrame.maxX - rightX) - hPadding, height: paddedHeight)

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

    init(settings: Settings, frame: CGRect, type: MenuBarAppearanceManager.PanelType, isMissionControlActive: Bool) {
        self.panelType = type
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        self.level = .statusBar - 1
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.ignoresMouseEvents = true
        self.collectionBehavior = [.canJoinAllSpaces]
        self.animationBehavior = .utilityWindow
        updateAppearance(with: settings, frame: frame, type: type, isMissionControlActive: isMissionControlActive)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func updateAppearance(with settings: Settings, frame: CGRect, type: MenuBarAppearanceManager.PanelType, isMissionControlActive: Bool) {
        self.panelType = type
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.animator().setFrame(frame, display: true)
        }
        self.contentView = NSHostingView(rootView: MenuBarAppearanceView(settings: settings, panelType: type, isMissionControlActive: isMissionControlActive))
    }
}

// MARK: - SwiftUI Appearance View
fileprivate struct MenuBarAppearanceView: View {
    let settings: Settings
    let panelType: MenuBarAppearanceManager.PanelType
    let isMissionControlActive: Bool

    var body: some View {
        appearanceContent
            .shadow(
                color: .black.opacity(settings.menuBarShadowEnabled ? 0.35 : 0),
                radius: 5,
                y: -2
            )
            .opacity(isMissionControlActive ? 0.0 : settings.menuBarOpacity)
            .animation(.easeOut(duration: 0.2), value: isMissionControlActive)
    }

    @ViewBuilder
    private var appearanceContent: some View {
        let cornerRadius = settings.menuBarCornerRadius

        switch settings.menuBarShapeStyle {
        case "rounded", "roundedSplit":
            let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            createInsettableStyledView(for: shape)

        default:
            if settings.menuBarLiquidGlass {
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
            .background(settings.menuBarBlur ? shape.fill(.ultraThinMaterial) : nil)
            .overlay {
                ZStack {
                    if settings.menuBarLiquidGlass { liquidGlassOverlay(shape: AnyShape(shape)) }
                    if settings.menuBarBorderWidth > 0 {
                        shape.strokeBorder(borderColor, lineWidth: settings.menuBarBorderWidth)
                    }
                }
            }
    }

    private func createStyledView<S: Shape>(for shape: S) -> some View {
        shape
            .fill(tint)
            .background(settings.menuBarBlur ? shape.fill(.ultraThinMaterial) : nil)
            .overlay {
                ZStack {
                    if settings.menuBarLiquidGlass { liquidGlassOverlay(shape: AnyShape(shape)) }
                    if settings.menuBarBorderWidth > 0 {
                        shape.stroke(borderColor, lineWidth: settings.menuBarBorderWidth)
                    }
                }
            }
    }

    private var tint: AnyShapeStyle {
        switch settings.menuBarTintStyle {
        case "solid":
            return AnyShapeStyle(settings.menuBarSolidColor.color)
        case "gradient":
            let angle = Angle(degrees: settings.menuBarGradientAngle)
            let startPoint = UnitPoint(x: 0.5 + sin(angle.radians) / 2, y: 0.5 - cos(angle.radians) / 2)
            let endPoint = UnitPoint(x: 0.5 - sin(angle.radians) / 2, y: 0.5 + cos(angle.radians) / 2)
            let stops = settings.menuBarGradientColors.map { Gradient.Stop(color: $0.color, location: $0.location) }
            return AnyShapeStyle(LinearGradient(stops: stops, startPoint: startPoint, endPoint: endPoint))
        default:
            return AnyShapeStyle(.clear)
        }
    }

    private var borderColor: Color {
        settings.menuBarBorderColor.color
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