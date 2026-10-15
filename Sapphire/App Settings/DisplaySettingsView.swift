//
//  DisplaySettingsView.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-27

import AppKit
import SwiftUI

struct DisplaySettingsView: View {
    @EditingSettings var settings: SettingsEditingSession
    @ObservedObject private var debugMode = DebugMode.shared
    @ObservedObject private var testDisplay = DebugTestDisplay.shared
    @State private var screensRevision = 0

    private var connectedScreens: [NSScreen] { NSScreen.screens }

    private var usesSelectedActivities: Bool {
        connectedScreens.contains {
            settings.settings.value.resolvedFullScreenBehavior(forDisplayID: $0.displayIdentifier).activityVisibility == .hideSelected
        }
    }

    var body: some View {
        let _ = screensRevision
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Displays").font(.title2.bold())
                    Text("Notch size, hiding and full-screen behaviour for each display.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                if debugMode.isEnabled {
                    Button {
                        testDisplay.toggle()
                    } label: {
                        Label(testDisplay.isActive ? "Remove Test Display" : "Add Test Display", systemImage: "display.2")
                    }
                    .help("Debug: add a notchless 1920×1080 virtual display, shown in a window, to test multi-display and floating island behaviour")
                }
            }

            if debugMode.isEnabled, let error = testDisplay.captureError {
                InfoContainer(text: error, iconName: "exclamationmark.triangle", color: .orange)
            }

            if connectedScreens.count > 1 {
                HStack(spacing: 12) {
                    SettingsRowLabel(
                        title: "Show Notch On",
                        description: "For displays you haven't switched on or off below, including ones you connect later."
                    )
                    Spacer(minLength: 8)
                    Picker("Show Notch On", selection: $settings.settings.notchDisplayTarget) {
                        ForEach(NotchDisplayTarget.allCases) { target in
                            Text(target.displayName).tag(target)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 200)
                }
                .padding()
                .modifier(SettingsContainerModifier())
            }

            if usesSelectedActivities {
                FullScreenSelectedActivitiesCard()
                    .transition(.opacity)
            }

            if connectedScreens.isEmpty {
                Text("No displays detected.")
                    .foregroundColor(.secondary)
                    .padding()
                    .modifier(SettingsContainerModifier())
            } else {
                ForEach(connectedScreens, id: \.displayIdentifier) { screen in
                    PerDisplaySettingsCard(screen: screen, canApplyToAll: connectedScreens.count > 1)
                }
            }
        }
        .animation(.default, value: usesSelectedActivities)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            screensRevision += 1
        }
    }
}

// MARK: - Software dimming

struct SoftwareDimmingRows: View {
    private struct Row: Identifiable, Equatable {
        let id: CGDirectDisplayID
        let name: String
        let prefersSoftware: Bool
    }

    @State private var rows: [Row] = []

    var body: some View {
        VStack(spacing: 0) {
            ForEach(rows) { row in
                Divider().padding(.leading, 20)
                ToggleRow(
                    title: "Always Use Software Dimming on \(row.name)",
                    description: "Dim this monitor in software even if it answers DDC, for monitors whose DDC is slow or unreliable.",
                    isOn: Binding(
                        get: { row.prefersSoftware },
                        set: { newValue in
                            (DisplayManager.shared.display(for: row.id) as? OtherDisplay)?.setPrefersSoftware(newValue)
                            reload()
                        }
                    )
                )
            }
        }
        .onAppear(perform: reload)
        .onReceive(NotificationCenter.default.publisher(for: DisplayManager.brightnessStateDidChange)) { _ in reload() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in reload() }
    }

    private func reload() {
        let newRows = DisplayManager.shared.getOtherDisplays().map {
            Row(id: $0.identifier, name: $0.name, prefersSoftware: $0.prefersSoftware)
        }
        if newRows != rows { rows = newRows }
    }
}

// MARK: - Full screen

private struct FullScreenBehaviorEditor: View {
    @Binding var visibility: FullScreenActivityVisibility
    @Binding var hideNotch: Bool
    @Binding var hideLyrics: Bool

    private var musicCanShow: Bool {
        visibility == .showAll || visibility == .hideSelected
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsRowLabel(title: "In Full Screen", description: visibility.detail)
            Picker("In Full Screen", selection: $visibility) {
                ForEach(FullScreenActivityVisibility.allCases) { visibility in
                    Text(visibility.displayName).tag(visibility)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            HStack(spacing: 12) {
                SettingsRowLabel(title: "Hide Notch", description: hideNotchDescription)
                Spacer(minLength: 8)
                SettingsSwitch(title: "Hide Notch", isOn: $hideNotch)
            }

            if musicCanShow {
                HStack(spacing: 12) {
                    SettingsRowLabel(
                        title: "Hide Lyrics",
                        description: "Hide the lyrics line under the music live activity so it doesn't cover the full-screen app. The song still shows."
                    )
                    Spacer(minLength: 8)
                    SettingsSwitch(title: "Hide Lyrics", isOn: $hideLyrics)
                }
            }
        }
    }

    private var hideNotchDescription: String {
        switch visibility {
        case .hideAll:
            "Hide the notch completely while an app is full screen."
        case .showAll:
            "Hide the notch while nothing is happening. It appears for any live activity."
        case .hidePersistent, .hideSelected:
            "Hide the notch while nothing is happening. It still appears for activities that aren't hidden, like the volume HUD."
        }
    }
}

private struct FullScreenSelectedActivitiesCard: View {
    @EditingSettings var settings: SettingsEditingSession

    var body: some View {
        SettingsCard(title: "Hide Selected", description: "Activities hidden in full screen on displays set to Hide Selected.") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12, alignment: .leading)], alignment: .leading, spacing: 10) {
                ForEach(LiveActivityType.allCases) { type in
                    Toggle(type.displayName, isOn: binding(for: type))
                        .toggleStyle(.checkbox)
                }
            }
            .padding()
        }
    }

    private func binding(for type: LiveActivityType) -> Binding<Bool> {
        Binding(
            get: { settings.settings.hideActivitiesInFullScreen[type.rawValue, default: false] },
            set: { settings.settings.hideActivitiesInFullScreen[type.rawValue] = $0 }
        )
    }
}

// MARK: - Per display

private struct PerDisplaySettingsCard: View {
    @EditingSettings var settings: SettingsEditingSession
    let screen: NSScreen
    let canApplyToAll: Bool
    @State private var showsIslandAdvanced = false

    private var displayID: String { screen.displayIdentifier }
    private var isBuiltIn: Bool { CGDisplayIsBuiltin(screen.displayID) != 0 }
    private var hasSizeOverride: Bool { sizeOverride != nil }
    private var sizeOverride: NotchSizeOverride? {
        DisplaySettingsKey.value(in: settings.settings.value.perDisplayNotchSize, for: displayID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: isBuiltIn ? "laptopcomputer" : "display")
                    .foregroundColor(.secondary)
                Text(screen.displayLabel).font(.headline)
                if isBuiltIn { Text("Built-in").font(.caption).foregroundColor(.secondary) }
                Spacer()
                if canApplyToAll && showsNotch {
                    Button("Apply to All Displays") {
                        settings.settings.value.applyDisplaySettingsToAllDisplays(
                            from: displayID,
                            includeFloatingIsland: !NotchConfiguration.hasHardwareNotch(on: screen)
                        )
                    }
                    .controlSize(.small)
                    .help("Use this display's notch size, hiding and full-screen settings on every display, including ones you connect later")
                }
                SettingsSwitch(title: "Show Notch", isOn: showNotchBinding)
                    .help("Show the notch on this display")
            }
            .padding([.top, .horizontal])

            if showsNotch {
                notchRows
            } else {
                Text("The notch is off on this display.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding()
            }
        }
        .modifier(SettingsContainerModifier())
        .animation(.default, value: showsNotch)
    }

    private var showsNotch: Bool {
        NotchScreens.showsNotch(on: screen, settings: settings.settings.value)
    }

    private var showNotchBinding: Binding<Bool> {
        Binding(
            get: { showsNotch },
            set: { settings.settings.perDisplayShowNotch[displayID] = $0 }
        )
    }

    @ViewBuilder
    private var notchRows: some View {
        sizeRow.padding()
        if !NotchConfiguration.hasHardwareNotch(on: screen) {
            Divider().padding(.leading, 20)
            floatingIslandRows
        }
        Divider().padding(.leading, 20)
        HStack(spacing: 12) {
            SettingsRowLabel(title: "Hide Notch When Inactive", description: "Hide the notch until something is happening.")
            Spacer(minLength: 8)
            SettingsSwitch(title: "Hide Notch When Inactive", isOn: inactiveBinding)
        }
        .padding()
        Divider().padding(.leading, 20)
        FullScreenBehaviorEditor(
            visibility: fullScreenBinding(\.activityVisibility),
            hideNotch: fullScreenBinding(\.hideNotch),
            hideLyrics: fullScreenBinding(\.hideLyrics)
        )
        .padding()
    }

    private var sizeRow: some View {
        let resolved = ResolvedNotchConfiguration(from: settings.settings.value, screen: screen)
        return HStack(spacing: 18) {
            Text("Notch Size")
                .font(.system(size: 14, weight: .medium))
                .lineLimit(1)
                .layoutPriority(-1)
            Spacer(minLength: 8)
            sizeControl(label: "Width", value: sizeBinding(\.width, fallback: resolved.universalWidth), range: 80...400)
            sizeControl(label: "Height", value: sizeBinding(\.height, fallback: resolved.universalHeight), range: 10...80)
            resetButton(visible: hasSizeOverride, help: "Clear this display's custom notch size") {
                DisplaySettingsKey.removeValue(
                    from: &settings.settings.perDisplayNotchSize,
                    for: screen.displayIdentifier,
                    connectedKeys: NSScreen.screens.map(\.displayIdentifier)
                )
            }
        }
    }

    @ViewBuilder
    private var floatingIslandRows: some View {
        let isIsland = settings.settings.value.resolvedFloatingIsland(forDisplayID: displayID)
        HStack(spacing: 12) {
            SettingsRowLabel(
                title: "Floating Island",
                description: "Show a pill that floats below the top edge instead of a notch. This display has no hardware notch."
            )
            Spacer(minLength: 8)
            SettingsSwitch(title: "Floating Island", isOn: floatingIslandBinding)
        }
        .padding()
        if isIsland {
            Button {
                withAnimation(.snappy) { showsIslandAdvanced.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Text("Advanced")
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .rotationEffect(.degrees(showsIslandAdvanced ? 90 : 0))
                    Spacer()
                }
                .foregroundColor(.secondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding([.horizontal, .bottom])
            .accessibilityLabel(showsIslandAdvanced ? "Hide advanced island settings" : "Show advanced island settings")

            if showsIslandAdvanced {
                VStack(spacing: 0) {
                    FloatingIslandPreview(config: ResolvedNotchConfiguration(from: settings.settings.value, screen: screen))
                        .padding(.horizontal)
                        .padding(.bottom)

                    HStack(spacing: 12) {
                        SettingsRowLabel(title: "Island Top Offset", description: "Distance from the top edge.")
                        Spacer(minLength: 8)
                        DeferredValueEditor(value: islandTopOffsetBinding) { draft, onEditingChanged in
                            HStack(spacing: 8) {
                                Slider(value: draft, in: 0...40, step: 1, onEditingChanged: onEditingChanged)
                                    .frame(width: 150)
                                    .accessibilityLabel("Island Top Offset")
                                Text("\(Int(draft.wrappedValue)) pt")
                                    .monospacedDigit()
                                    .frame(width: 42, alignment: .trailing)
                            }
                        }
                    }
                    .padding([.horizontal, .bottom])

                    VStack(spacing: 0) {
                        islandSlider("Side Padding", \.sidePadding, range: FloatingIslandStyle.sidePaddingRange)
                        islandSlider("Center Gap", \.centerGap, range: FloatingIslandStyle.centerGapRange)
                        islandSlider("Open Corner Radius", \.openCornerRadius, range: FloatingIslandStyle.openCornerRadiusRange)
                        islandSlider("Open Padding", \.openPadding, range: FloatingIslandStyle.openPaddingRange)
                    }
                    HStack {
                        Spacer()
                        resetButton(visible: hasIslandStyleOverride, help: "Restore the default island spacing") {
                            DisplaySettingsKey.removeValue(
                                from: &settings.settings.perDisplayFloatingIslandStyle,
                                for: screen.displayIdentifier,
                                connectedKeys: NSScreen.screens.map(\.displayIdentifier)
                            )
                        }
                    }
                    .padding([.horizontal, .bottom])
                }
                .transition(.opacity)
            }
        }
    }

    private var hasIslandStyleOverride: Bool {
        DisplaySettingsKey.value(in: settings.settings.value.perDisplayFloatingIslandStyle, for: displayID) != nil
    }

    private func islandSlider(_ label: String, _ keyPath: WritableKeyPath<FloatingIslandStyle, CGFloat>, range: ClosedRange<CGFloat>) -> some View {
        CustomSliderRowView(
            label: label,
            value: Binding(
                get: { Double(settings.settings.value.resolvedFloatingIslandStyle(forDisplayID: displayID)[keyPath: keyPath]) },
                set: { newValue in
                    var style = settings.settings.value.resolvedFloatingIslandStyle(forDisplayID: displayID)
                    style[keyPath: keyPath] = CGFloat(newValue.rounded())
                    settings.settings.perDisplayFloatingIslandStyle[displayID] = style
                }
            ),
            range: Double(range.lowerBound)...Double(range.upperBound),
            specifier: "%.0f pt"
        )
        .padding(.horizontal)
    }

    private func resetButton(visible: Bool, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label("Reset", systemImage: "arrow.counterclockwise").font(.callout)
        }
        .buttonStyle(.plain)
        .foregroundColor(.accentColor)
        .help(help)
        .fixedSize()
        .opacity(visible ? 1 : 0)
        .disabled(!visible)
        .accessibilityHidden(!visible)
    }

    private var inactiveBinding: Binding<Bool> {
        Binding(
            get: { settings.settings.value.resolvedHideNotchWhenInactive(forDisplayID: displayID) },
            set: { settings.settings.perDisplayHideNotchWhenInactive[displayID] = $0 }
        )
    }

    private var floatingIslandBinding: Binding<Bool> {
        Binding(
            get: { settings.settings.value.resolvedFloatingIsland(forDisplayID: displayID) },
            set: { settings.settings.perDisplayFloatingIsland[displayID] = $0 }
        )
    }

    private var islandTopOffsetBinding: Binding<Double> {
        Binding(
            get: { Double(settings.settings.value.resolvedFloatingIslandTopOffset(forDisplayID: displayID)) },
            set: { settings.settings.perDisplayFloatingIslandTopOffset[displayID] = CGFloat($0) }
        )
    }

    private func fullScreenBinding<Value>(_ keyPath: WritableKeyPath<FullScreenBehavior, Value>) -> Binding<Value> {
        Binding(
            get: { settings.settings.value.resolvedFullScreenBehavior(forDisplayID: displayID)[keyPath: keyPath] },
            set: { newValue in
                var behavior = settings.settings.value.resolvedFullScreenBehavior(forDisplayID: displayID)
                behavior[keyPath: keyPath] = newValue
                settings.settings.perDisplayFullScreenBehavior[displayID] = behavior
            }
        )
    }

    private func sizeBinding(_ keyPath: WritableKeyPath<NotchSizeOverride, CGFloat>, fallback: CGFloat) -> Binding<Double> {
        Binding(
            get: {
                let value: CGFloat = sizeOverride?[keyPath: keyPath] ?? 0
                return Double(value > 0 ? value : fallback)
            },
            set: { newValue in
                var override = sizeOverride ?? NotchSizeOverride()
                override[keyPath: keyPath] = CGFloat(newValue.rounded())
                settings.settings.perDisplayNotchSize[displayID] = override
            }
        )
    }

    private func sizeControl(label: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: true, vertical: false)
                .lineLimit(1)
            TextField(label, value: value, format: .number.precision(.fractionLength(0)))
                .textFieldStyle(.roundedBorder)
                .monospacedDigit()
                .frame(width: 62)
                .multilineTextAlignment(.trailing)
            VStack(spacing: 0) {
                Button {
                    value.wrappedValue = min(range.upperBound, (value.wrappedValue + 1).rounded())
                } label: {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 9, weight: .bold))
                        .frame(width: 16, height: 9)
                }
                .buttonStyle(.plain)
                .help("Increase \(label)")

                Button {
                    value.wrappedValue = max(range.lowerBound, (value.wrappedValue - 1).rounded())
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .frame(width: 16, height: 9)
                }
                .buttonStyle(.plain)
                .help("Decrease \(label)")
            }
            Text("pt")
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .fixedSize()
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}

// MARK: - Floating island preview

private struct FloatingIslandPreview: View {
    let config: ResolvedNotchConfiguration

    private static let openSize = CGSize(width: 620, height: 260)
    private static let openScale: CGFloat = 0.42

    private var islandShape: CustomNotchShape {
        CustomNotchShape(
            cornerRadius: 0,
            bottomCornerRadius: 0,
            isFloatingIsland: true,
            floatingIslandCornerRadius: config.floatingIslandCornerRadius
        )
    }

    var body: some View {
        HStack(alignment: .top, spacing: 28) {
            labelled("Compact") { compact }
            labelled("Open") {
                open
                    .scaleEffect(Self.openScale, anchor: .topLeading)
                    .frame(
                        width: Self.openSize.width * Self.openScale,
                        height: Self.openSize.height * Self.openScale,
                        alignment: .topLeading
                    )
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [Color(white: 0.32), Color(white: 0.18)], startPoint: .top, endPoint: .bottom),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
    }

    private func labelled<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            content()
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private var compact: some View {
        let height = config.universalHeight
        let art = height * 0.62
        let contentWidth = art * 2 + config.activityCenterGap + config.activityDefaultHorizontalPadding * 2
        return HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: art * 0.25, style: .continuous)
                .fill(LinearGradient(colors: [.pink, .orange], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: art, height: art)
            Spacer(minLength: 0)
            HStack(spacing: 2) {
                ForEach([0.5, 0.9, 0.65, 1.0, 0.45], id: \.self) { level in
                    Capsule().fill(.white.opacity(0.85)).frame(width: 2.5, height: art * level)
                }
            }
            .frame(width: art)
        }
        .padding(.horizontal, config.activityDefaultHorizontalPadding)
        .frame(width: max(contentWidth, config.universalWidth), height: height)
        .background(islandShape.fill(.black))
    }

    private var open: some View {
        let padding = config.contentHorizontalPadding
        let barHeight = NotchIslandBar.height
        let card = CGSize(width: Self.openSize.width, height: Self.openSize.height - NotchIslandBar.reservedHeight)
        return VStack(spacing: NotchIslandBar.gap) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white.opacity(0.14))
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white.opacity(0.14))
            }
            .padding(.top, config.contentTopPadding)
            .padding(.bottom, config.contentBottomPadding)
            .padding(.horizontal, padding)
            .frame(width: card.width, height: card.height)
            .clipShape(islandShape)
            .background(islandShape.fill(.black))

            HStack(spacing: 0) {
                ForEach(["house.fill", "tray.full.fill", "note.text", "list.clipboard.fill", "gearshape.fill"], id: \.self) { symbol in
                    Image(systemName: symbol)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(symbol == "house.fill" ? 1 : 0.62))
                        .frame(width: NotchIslandBar.itemWidth - 4, height: barHeight - 8)
                        .background(Capsule().fill(.white.opacity(symbol == "house.fill" ? 0.16 : 0)))
                        .frame(width: NotchIslandBar.itemWidth)
                }
            }
            .padding(.horizontal, NotchIslandBar.padding)
            .frame(height: barHeight)
            .background(Capsule(style: .continuous).fill(.black))
        }
        .frame(width: Self.openSize.width, height: Self.openSize.height, alignment: .top)
    }
}