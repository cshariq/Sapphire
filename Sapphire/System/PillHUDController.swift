//
//  PillHUDController.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-31.
//

import SwiftUI
import AppKit
import Combine

final class PillHUDController: ObservableObject {
    static let shared = PillHUDController()

    private let settings = SettingsModel.shared
    private let hudManager = SystemHUDManager.shared
    private var panel: NSPanel?
    private var hostingView: NSView?
    private var cancellables = Set<AnyCancellable>()
    private var hideWorkItem: DispatchWorkItem?
    private var panelAnimationID = UUID()

    private let edgeMargin: CGFloat = 20

    private init() {
        hudManager.$currentHUD
            .receive(on: DispatchQueue.main)
            .sink { [weak self] hud in
                self?.handleHUDChange(hud)
            }
            .store(in: &cancellables)

        settings.$settings
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, self.isVisible else { return }
                self.positionPanel()
            }
            .store(in: &cancellables)
    }

    private var activeStyleIsPill: Bool {
        guard let hud = hudManager.currentHUD else { return false }
        switch hud {
        case .volume, .externalDeviceVolume, .appVolume:
            return settings.settings.effectiveVolumeHUDStyle == .pill
        case .brightness, .keyboardBrightness, .multiDisplayBrightness:
            return settings.settings.effectiveBrightnessHUDStyle == .pill
        }
    }

    var isVisible: Bool { panel?.isVisible == true }

    // MARK: - Lifecycle

    private func handleHUDChange(_ hud: HUDType?) {
        guard hud != nil, activeStyleIsPill else {
            hidePill()
            return
        }
        showPill()
    }

    private func showPill() {
        hideWorkItem?.cancel()
        panelAnimationID = UUID()
        guard let screen = targetScreen() else { return }
        let panel = ensurePanel()
        let wasVisible = panel.isVisible
        let position = settings.settings.hudPillPosition
        let frame = pillFrame(for: position, screen: screen)

        if wasVisible {
            panel.alphaValue = 1
            panel.setFrame(frame, display: true)
        } else {
            let entranceFrame = frame.offsetBy(dx: position == .right ? 16 : position == .left ? -16 : 0,
                                               dy: position == .bottom ? -16 : 0)
            panel.setFrame(entranceFrame, display: false)
            hostingView?.frame = NSRect(origin: .zero, size: frame.size)
            panel.alphaValue = 0
            panel.orderFrontRegardless()

            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.3
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrame(frame, display: true)
                panel.animator().alphaValue = 1
            }
        }

        hostingView?.frame = NSRect(origin: .zero, size: frame.size)

        let hideIn = settings.settings.hudDuration
        let work = DispatchWorkItem { [weak self] in self?.hidePill() }
        hideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + hideIn, execute: work)
    }

    private func hidePill() {
        hideWorkItem?.cancel()
        guard let panel = panel, panel.isVisible else { return }

        let animationID = UUID()
        panelAnimationID = animationID
        let position = settings.settings.hudPillPosition
        let exitFrame = panel.frame.offsetBy(dx: position == .right ? 16 : position == .left ? -16 : 0,
                                             dy: position == .bottom ? -16 : 0)

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrame(exitFrame, display: true)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self, weak panel] in
            guard let self, self.panelAnimationID == animationID, let panel else { return }
            panel.orderOut(nil)
            panel.alphaValue = 1
        })
    }

    // MARK: - Window

    private func ensurePanel() -> NSPanel {
        if let panel = panel { return panel }
        let p = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.level = .statusBar
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        p.ignoresMouseEvents = true
        p.isReleasedWhenClosed = false
        p.hidesOnDeactivate = false
        p.sharingType = settings.settings.hideFromScreenSharing ? .none : .readOnly

        let view = PillHUDView()
            .environmentObject(settings)
            .environmentObject(hudManager)
        let hosting = NSHostingView(rootView: view)
        hosting.autoresizingMask = [.width, .height]
        hosting.sizingOptions = []
        hosting.wantsLayer = true
        p.contentView = hosting

        panel = p
        hostingView = hosting
        return p
    }

    private func targetScreen() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        if let screen = CursorPosition.screen(containing: mouseLocation) {
            return screen
        }
        return CursorPosition.targetNotchScreen() ?? NSScreen.main
    }

    private func pillFrame(for position: PillHUDPosition, screen: NSScreen) -> CGRect {
        let length = CGFloat(settings.settings.hudPillLength)
        let configuredThickness = CGFloat(settings.settings.hudPillThickness)
        let thickness = settings.settings.hudPillStyle == .bare
            ? max(40, configuredThickness - 10)
            : configuredThickness
        let s = screen.frame

        switch position {
        case .left:
            return CGRect(
                x: s.minX + edgeMargin,
                y: s.midY - length / 2,
                width: thickness,
                height: length
            )
        case .right:
            return CGRect(
                x: s.maxX - edgeMargin - thickness,
                y: s.midY - length / 2,
                width: thickness,
                height: length
            )
        case .bottom:
            return CGRect(
                x: s.midX - length / 2,
                y: s.minY + edgeMargin,
                width: length,
                height: thickness
            )
        }
    }

    private func positionPanel() {
        guard let panel = panel else { return }
        guard let screen = targetScreen() else { return }
        let frame = pillFrame(for: settings.settings.hudPillPosition, screen: screen)
        panel.setFrame(frame, display: true)
        hostingView?.frame = NSRect(origin: .zero, size: frame.size)
    }
}

struct PillHUDView: View {
    @EnvironmentObject var settings: SettingsModel
    @EnvironmentObject var hudManager: SystemHUDManager

    var body: some View {
        if let type = hudManager.currentHUD {
            let vertical = settings.settings.hudPillPosition != .bottom
            Group {
                if settings.settings.hudPillStyle == .bare {
                    barePill(vertical: vertical)
                } else {
                    containedPill(vertical: vertical)
                }
            }
            .id(type.caseIdentifier)
            .animation(.spring(response: 0.36, dampingFraction: 0.82), value: clampedLevel)
            .animation(.easeInOut(duration: 0.22), value: iconName)
            .animation(.easeInOut(duration: 0.2), value: fillColor)
            .animation(.easeOut(duration: 0.18), value: hudManager.glowIntensity)
        }
    }

    @ViewBuilder
    private func containedPill(vertical: Bool) -> some View {
        Group {
            if vertical {
                VStack(spacing: 10) {
                    icon(with: fillColor)
                    VerticalPillTrack(level: clampedLevel, color: fillColor)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    if settings.settings.hudShowPercentage {
                        percentageText
                    }
                }
                .padding(10)
            } else {
                HStack(spacing: 12) {
                    icon(with: fillColor)
                    HorizontalPillTrack(level: clampedLevel, color: fillColor)
                        .frame(maxWidth: .infinity)
                    if settings.settings.hudShowPercentage {
                        percentageText
                    }
                }
                .padding(14)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Capsule().fill(Material.ultraThin))
        .overlay(Capsule().stroke(Color.white.opacity(0.16), lineWidth: 1))
        .shadow(
            color: fillColor.opacity(0.18 + hudManager.glowIntensity * 0.22),
            radius: 5 + CGFloat(hudManager.glowIntensity * 8)
        )
    }

    private func barePill(vertical: Bool) -> some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            ZStack(alignment: vertical ? .bottom : .leading) {
                Capsule().fill(Color.black.opacity(0.3))
                    .frame(width: width, height: height)
                Capsule().fill(fillColor)
                    .frame(
                        width: vertical ? width : max(0, width * CGFloat(clampedLevel)),
                        height: vertical ? max(0, height * CGFloat(clampedLevel)) : height
                    )
            }
            .clipShape(Capsule())
            .contentShape(Capsule())
            .shadow(
                color: fillColor.opacity(0.2 + hudManager.glowIntensity * 0.25),
                radius: 4 + CGFloat(hudManager.glowIntensity * 8)
            )
        }
        .overlay {
            Group {
                if vertical {
                    VStack(spacing: 4) {
                        withinIcon
                        Spacer(minLength: 0)
                        if settings.settings.hudShowPercentage { withinPercent }
                    }
                    .padding(.vertical, 6)
                } else {
                    HStack(spacing: 8) {
                        withinIcon
                        Spacer(minLength: 0)
                        if settings.settings.hudShowPercentage { withinPercent }
                    }
                    .padding(.horizontal, 12)
                }
            }
        }
    }

    private var isXDRBrightnessHUD: Bool {
        guard settings.settings.enableXDRBrightness else { return false }
        switch hudManager.currentHUD {
        case .brightness(let level):
            return level > 1.0
        case .multiDisplayBrightness(let displays):
            return displays.contains { $0.level > 1.0 }
        default:
            return false
        }
    }

    private var hudRange: Float {
        isXDRBrightnessHUD ? max(1.0, settings.settings.xdrBrightnessLevel) : 1.0
    }

    private var clampedLevel: Float {
        let level = hudManager.currentHUD?.primaryLevel ?? 0
        return min(max(level / hudRange, 0), 1)
    }

    private var displayedPercentage: Int {
        let level = hudManager.currentHUD?.primaryLevel ?? 0
        return Int(min(max(level, 0), hudRange) * 100)
    }

    private var withinIcon: some View {
        icon(with: .white)
            .shadow(color: .black.opacity(0.5), radius: 1, y: 1)
    }

    private var withinPercent: some View {
        Text("\(displayedPercentage)%")
            .font(.system(size: 11, weight: .bold, design: .monospaced))
            .foregroundColor(.white)
            .shadow(color: .black.opacity(0.5), radius: 1, y: 1)
    }

    private func icon(with color: Color) -> some View {
        Image(systemName: iconName)
            .font(.system(size: 18, weight: .semibold))
            .foregroundColor(color)
            .frame(width: 22, height: 22)
            .id(iconName)
            .transition(.asymmetric(
                insertion: .scale(scale: 0.7).combined(with: .opacity),
                removal: .scale(scale: 1.25).combined(with: .opacity)
            ))
    }

    private var percentageText: some View {
        Text("\(displayedPercentage)%")
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundColor(Color.white.opacity(0.7))
    }

    private var iconName: String {
        guard let type = hudManager.currentHUD else { return "speaker.wave.3.fill" }
        switch type {
        case .volume(let level, _):
            if level == 0 { return "speaker.slash.fill" }
            if level < 0.33 { return "speaker.wave.1.fill" }
            if level < 0.66 { return "speaker.wave.2.fill" }
            return "speaker.wave.3.fill"
        case .externalDeviceVolume(_, let deviceIcon, _, _, _, _):
            return deviceIcon.isEmpty ? "speaker.wave.2.fill" : deviceIcon
        case .appVolume: return "app.fill"
        case .brightness, .multiDisplayBrightness:
            return isXDR ? "sun.max.trianglebadge.exclamationmark.fill" : "sun.max.fill"
        case .keyboardBrightness: return "keyboard.fill"
        }
    }

    private var isXDR: Bool { isXDRBrightnessHUD }

    private var fillColor: Color {
        switch settings.settings.hudVisualStyle {
        case .white: return Color.white.opacity(0.85)
        case .color: return settings.settings.hudCustomColor?.color ?? .accentColor
        case .adaptive:
            if isXDRBrightnessHUD { return .orange }
            if clampedLevel >= 0.9 { return .red }
            if clampedLevel > 0.6 { return .yellow }
            return .white
        }
    }
}

private struct VerticalPillTrack: View {
    let level: Float
    let color: Color

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                Capsule().fill(Color.white.opacity(0.14))
                Capsule().fill(color)
                    .frame(height: max(0, geometry.size.height * CGFloat(level)))
                    .animation(.interactiveSpring(response: 0.38, dampingFraction: 0.82), value: level)
            }
            .clipShape(Capsule())
        }
    }
}

private struct HorizontalPillTrack: View {
    let level: Float
    let color: Color

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.14))
                Capsule().fill(color)
                    .frame(width: max(0, geometry.size.width * CGFloat(level)))
                    .animation(.interactiveSpring(response: 0.38, dampingFraction: 0.82), value: level)
            }
            .clipShape(Capsule())
        }
    }
}