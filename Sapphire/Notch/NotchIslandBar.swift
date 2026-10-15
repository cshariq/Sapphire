//
//  NotchIslandBar.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-10-15
//

import SwiftUI
import AppKit

enum NotchIslandBar {
    static let height: CGFloat = 38
    static let gap: CGFloat = 8
    static let itemWidth: CGFloat = 36
    static let padding: CGFloat = 4
    static let separatorWidth: CGFloat = 13

    enum Item: Hashable {
        case back
        case home
        case button(NotchButtonType)
        case separator
    }

    static func showsBar(for mode: NotchWidgetMode) -> Bool {
        NotchExpandedChrome.showsHeader(for: mode)
    }

    static func items(settings: Settings, navigationDepth: Int, maxWidth: CGFloat) -> [Item] {
        var items: [Item] = navigationDepth > 2 ? [.back, .home] : [.home]
        for button in settings.notchButtonOrder {
            if button == .spacer {
                items.append(.separator)
            } else if isShown(button, settings: settings) {
                items.append(.button(button))
            }
        }
        items = tidySeparators(items)
        for button in dropOrder where width(of: items) > maxWidth {
            items.removeAll { $0 == .button(button) }
            items = tidySeparators(items)
        }
        return items
    }

    static func width(of items: [Item]) -> CGFloat {
        padding * 2 + items.reduce(0) { $0 + ($1 == .separator ? separatorWidth : itemWidth) }
    }

    static func size(of items: [Item]) -> CGSize {
        CGSize(width: width(of: items), height: height)
    }

    static var reservedHeight: CGFloat { gap + height }

    static func selection(for stack: [NotchWidgetMode]) -> Item {
        guard stack.count > 1 else { return .home }
        switch stack[1] {
        case .fileShelf, .fileActionPreview: return .button(.fileShelf)
        case .notesPlayer: return .button(.notes)
        case .clipboardPlayer: return .button(.clipboard)
        case .focusSessionDetailView: return .button(.focusSession)
        case .multiAudio: return .button(.multiAudio)
        case .continuityDetail: return .button(.continuity)
        case .batteryDetailView: return .button(.battery)
        case .blipHub, .agentS: return .button(.intelligence)
        default: return .home
        }
    }

    static func destination(of button: NotchButtonType) -> NotchWidgetMode? {
        switch button {
        case .fileShelf: return .fileShelf
        case .notes: return .notesPlayer
        case .clipboard: return .clipboardPlayer
        case .focusSession: return .focusSessionDetailView
        case .multiAudio: return .multiAudio
        case .continuity: return .continuityDetail
        case .battery: return .batteryDetailView
        default: return nil
        }
    }

    static func isShown(_ button: NotchButtonType, settings: Settings) -> Bool {
        switch button {
        case .settings: return true
        case .fileShelf: return settings.fileShelfIconEnabled
        case .notes: return settings.notesIconEnabled
        case .clipboard: return settings.clipboardIconEnabled
        case .intelligence: return settings.intelligenceEnabled
        case .intelligenceLive, .spacer: return false
        case .focusSession: return settings.focusSessionIconEnabled
        case .caffeine: return settings.caffeinateEnabled
        case .battery: return settings.batteryEstimatorEnabled
        case .continuity: return settings.continuityEnabled && settings.continuityShowPhoneBattery
        case .multiAudio: return settings.showMultiAudioIcon
        case .pin: return settings.pinEnabled
        }
    }

    private static let dropOrder: [NotchButtonType] = [
        .pin, .caffeine, .battery, .continuity, .settings, .intelligence,
        .multiAudio, .focusSession, .clipboard, .notes, .fileShelf,
    ]

    private static func tidySeparators(_ items: [Item]) -> [Item] {
        var tidy: [Item] = []
        for item in items {
            if item == .separator, tidy.last == .separator || tidy.isEmpty { continue }
            tidy.append(item)
        }
        while tidy.last == .separator { tidy.removeLast() }
        if let firstButton = tidy.firstIndex(where: { if case .button = $0 { return true } else { return false } }),
           firstButton > 0, tidy[firstButton - 1] != .separator {
            tidy.insert(.separator, at: firstButton)
        }
        return tidy
    }
}

// MARK: - View

struct NotchIslandBarView: View {
    let items: [NotchIslandBar.Item]
    let context: NotchExpandedChrome.Context

    @ObservedSettings private var settings: SettingsObserver
    @ObservedObject private var hudManager = SystemHUDManager.shared

    private var selection: NotchIslandBar.Item {
        NotchIslandBar.selection(for: context.navigationStack.wrappedValue)
    }

    var body: some View {
        let size = NotchIslandBar.size(of: items)
        let hud = context.showRightHUDOverlay ? hudManager.currentHUD : nil
        ZStack {
            HStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    itemView(item)
                }
            }
            .opacity(hud == nil ? 1 : 0)

            if let hud {
                HStack(spacing: 8) {
                    SystemHUDSlimActivityView.left(type: hud, settings: settings)
                    SystemHUDSlimActivityView.right(
                        type: hud,
                        settings: settings,
                        availableWidth: max(0, size.width - 72)
                    )
                }
                .padding(.horizontal, 14)
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: hud == nil)
        .padding(.horizontal, NotchIslandBar.padding)
        .frame(width: size.width, height: size.height)
    }

    @ViewBuilder
    private func itemView(_ item: NotchIslandBar.Item) -> some View {
        switch item {
        case .separator:
            Capsule()
                .fill(Color.white.opacity(0.14))
                .frame(width: 1, height: 16)
                .frame(width: NotchIslandBar.separatorWidth)
        case .back:
            NotchIslandBarButton(systemName: "chevron.left", isSelected: false, help: "Back") {
                if NotchBackRouter.shared.handleBack() { return }
                if context.navigationStack.wrappedValue.count > 1 {
                    context.navigationStack.wrappedValue.removeLast()
                }
            }
        case .home:
            NotchIslandBarButton(systemName: "house.fill", isSelected: selection == .home, help: "Home") {
                context.navigationStack.wrappedValue = [.defaultWidgets]
            }
        case .button(let type):
            NotchIslandBarTypeButton(type: type, isSelected: selection == item, context: context)
        }
    }
}

struct NotchIslandBarButton<Label: View>: View {
    let isSelected: Bool
    var activeTint: Color? = nil
    let help: String
    let action: () -> Void
    let label: Label

    @State private var isHovering = false

    init(isSelected: Bool, activeTint: Color? = nil, help: String, action: @escaping () -> Void, @ViewBuilder label: () -> Label) {
        self.isSelected = isSelected
        self.activeTint = activeTint
        self.help = help
        self.action = action
        self.label = label()
    }

    private var foreground: Color {
        if let activeTint { return activeTint }
        return Color.white.opacity(isSelected ? 1 : (isHovering ? 0.95 : 0.62))
    }

    var body: some View {
        Button(action: action) {
            label
                .foregroundStyle(foreground)
                .frame(width: NotchIslandBar.itemWidth - 4, height: NotchIslandBar.height - 8)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(isSelected ? 0.16 : (isHovering ? 0.07 : 0)))
                )
                .frame(width: NotchIslandBar.itemWidth, height: NotchIslandBar.height)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .help(help)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { isHovering = hovering }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.86), value: isSelected)
    }
}

extension NotchIslandBarButton where Label == NotchIslandBarIcon {
    init(systemName: String, isSelected: Bool, activeTint: Color? = nil, help: String, action: @escaping () -> Void) {
        self.init(isSelected: isSelected, activeTint: activeTint, help: help, action: action) {
            NotchIslandBarIcon(systemName: systemName)
        }
    }
}

struct NotchIslandBarIcon: View {
    let systemName: String

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 14, weight: .semibold))
            .symbolRenderingMode(.hierarchical)
    }
}

private struct NotchIslandBarTypeButton: View {
    let type: NotchButtonType
    let isSelected: Bool
    let context: NotchExpandedChrome.Context

    @ObservedObject private var caffeineManager = CaffeineManager.shared
    @EnvironmentObject private var batteryEstimator: BatteryEstimator

    var body: some View {
        switch type {
        case .settings:
            NotchIslandBarButton(systemName: "gearshape.fill", isSelected: false, help: "Settings") {
                (NSApp.delegate as? AppDelegate)?.openSettingsWindow()
            }
        case .intelligence:
            NotchIslandBarButton(isSelected: isSelected, help: "Blip", action: context.onOpenBlipHub) {
                Image(systemName: "sparkle")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(LinearGradient(colors: [.purple, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing))
            }
            .simultaneousGesture(TapGesture(count: 2).onEnded(context.onOpenAgentS))
        case .caffeine:
            NotchIslandBarButton(
                systemName: caffeineManager.isActive ? "cup.and.heat.waves.fill" : "cup.and.heat.waves",
                isSelected: false,
                activeTint: caffeineManager.isActive ? Color.orange : nil,
                help: caffeineManager.isActive ? "Keep Awake: On" : "Keep Awake"
            ) {
                caffeineManager.toggle()
            }
            .contextMenu { NotchCaffeinateMenu(caffeineManager: caffeineManager) }
        case .pin:
            NotchIslandBarButton(
                systemName: context.isPinned.wrappedValue ? "pin.fill" : "pin",
                isSelected: false,
                activeTint: context.isPinned.wrappedValue ? Color.white : nil,
                help: context.isPinned.wrappedValue ? "Unpin" : "Pin Open"
            ) {
                context.isPinned.wrappedValue.toggle()
                context.onPin(context.isPinned.wrappedValue)
            }
        case .battery:
            NotchIslandBarButton(systemName: batterySymbol, isSelected: isSelected, help: batteryHelp) {
                open(.battery)
            }
        case .continuity:
            NotchIslandBarButton(systemName: "iphone", isSelected: isSelected, help: "Phone") {
                open(.continuity)
            }
        default:
            NotchIslandBarButton(systemName: symbol, isSelected: isSelected, help: type.displayName) {
                open(type)
            }
        }
    }

    private var symbol: String {
        switch type {
        case .fileShelf: return "tray.full.fill"
        case .notes: return "note.text"
        case .clipboard: return "list.clipboard.fill"
        case .focusSession: return "moon.fill"
        case .multiAudio: return "hifispeaker.2.fill"
        default: return "circle"
        }
    }

    private var batterySymbol: String {
        if batteryEstimator.isCharging { return "battery.100percent.bolt" }
        switch batteryEstimator.batteryLevel {
        case ..<13: return "battery.0percent"
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }

    private var batteryHelp: String {
        let level = "\(batteryEstimator.batteryLevel)%"
        guard let remaining = batteryEstimator.estimatedTimeRemaining else { return level }
        return "\(level), \(remaining)"
    }

    private func open(_ button: NotchButtonType) {
        guard let mode = NotchIslandBar.destination(of: button), !isSelected else { return }
        context.navigationStack.wrappedValue = [.defaultWidgets, mode]
    }
}