//
//  SettingsPanes.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-07-10.
//

import SwiftUI
import Charts
import CaptchaSolverInterface
import CoreBluetooth

struct SettingsDetailView: View {
    var selectedSection: SettingsSection?

    var body: some View {
        VStack {
            switch selectedSection {
            case .general: GeneralSettingsView()
            case .widgets: WidgetsSettingsView()
            case .liveActivities: LiveActivitiesSettingsView()
            case .appearance: AppearanceSettingsView()
            case .lockScreen: LockScreenSettingsView()
            case .bluetoothUnlock: ProximityUnlockSettingsView()
            case .shortcuts: ShortcutsSettingsView()
            case .snapZones: SnapZonesSettingsView()
            case .battery: BatterySettingsView()
            case .bluetooth: BluetoothSettingsView()
            case .hud: HUDSettingsView()
            case .notifications: NotificationsSettingsView()
            case .neardrop: NeardropSettingsView()
            case .fileShelf: FileShelfSettingsView()
            case .music: MusicSettingsView()
            case .weather: WeatherSettingsView()
            case .calendar: CalendarSettingsView()
            case .eyeBreak: EyeBreakSettingsView()
            case .gemini: GeminiSettingsView()
            case .about: AboutSettingsView()
            case nil:
                VStack {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 50))
                        .foregroundStyle(.tertiary)
                    Text("Select a category")
                        .font(.title)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .animation(.easeOut(duration: 0.15), value: selectedSection)
    }
}

struct RequiredPermissionsView: View {
    @ObservedObject private var permissionsManager = PermissionsManager.shared
    let section: SettingsSection
    private var requiredPermissions: [PermissionItem] { permissionsManager.allPermissions.filter { section.requiredPermissions.contains($0.type) } }
    var body: some View {
        if !requiredPermissions.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text("Required Permissions").font(.headline).padding([.horizontal, .top])
                ForEach(requiredPermissions) { permission in
                    PermissionStatusRowView(permission: permission)
                    if permission.id != requiredPermissions.last?.id { Divider().padding(.leading, 60) }
                }
            }.modifier(SettingsContainerModifier()).onAppear(perform: permissionsManager.checkAllPermissions)
        }
    }
}

struct PermissionStatusRowView: View {
    let permission: PermissionItem
    @ObservedObject private var permissionsManager = PermissionsManager.shared
    var body: some View {
        HStack(spacing: 15) {
            Image(systemName: permission.iconName).font(.system(size: 18, weight: .medium)).foregroundColor(permission.iconColor).frame(width: 36, height: 36).background(permission.iconColor.opacity(0.15)).clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(permission.title).font(.system(size: 14, weight: .medium))
                Text(permission.description).font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            let status = permissionsManager.status(for: permission.type)
            switch status {
            case .granted: Image(systemName: "checkmark.circle.fill").font(.title2).foregroundColor(.green)
            case .denied: Image(systemName: "xmark.circle.fill").font(.title2).foregroundColor(.red)
            case .notRequested: Button("Request") { permissionsManager.requestPermission(permission.type) }.buttonStyle(.bordered).tint(.accentColor)
            }
        }.padding(EdgeInsets(top: 12, leading: 20, bottom: 12, trailing: 20))
    }
}

struct NotchAppearanceEditorView: View {
    @Binding var appearance: NotchAppearanceSettings
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !title.isEmpty {
                Text(title).font(.headline).padding([.top, .horizontal])
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            ToggleRow(title: "Liquid Glass Look", description: "Apply a shiny, glass-like effect to the notch background.", isOn: $appearance.liquidGlassLook)
            Divider().padding(.leading, 20)

            HStack {
                Text("Background Style")
                Spacer()
                Picker("", selection: $appearance.backgroundStyle) {
                    ForEach(NotchBackgroundStyle.allCases) { style in
                        Text(style.displayName).tag(style)
                    }
                }.labelsHidden().frame(width: 150)
            }.padding()

            if appearance.backgroundStyle == .solid {
                solidColorPicker
            } else {
                gradientColorEditor
            }

            Divider().padding(.leading, 20)

            let opacityBinding = Binding<Double>(
                get: { appearance.opacity * 100 },
                set: { appearance.opacity = $0 / 100 }
            )
            CustomSliderRowView(label: "Master Opacity", value: opacityBinding, range: 0...100, specifier: "%.0f%%")

            Divider().padding(.leading, 20)
            ToggleRow(title: "Enable Transparency Blur", description: "Apply a frosted glass effect to the notch background.", isOn: $appearance.enableTransparencyBlur)
        }
        .modifier(SettingsContainerModifier())
        .animation(.default, value: appearance.backgroundStyle)
    }

    @ViewBuilder
    private var solidColorPicker: some View {
        ColorPicker("Color", selection: $appearance.solidColor.color, supportsOpacity: true)
        .padding()
        .transition(.opacity)
    }

    @ViewBuilder
    private var gradientColorEditor: some View {
        VStack(alignment: .leading) {
            if appearance.backgroundStyle == .gradient {
                CustomSliderRowView(label: "Angle", value: $appearance.gradientAngle, range: 0...360, specifier: "%.0f°")
                    .padding(.horizontal)
            }

            Text("Gradient Colors").font(.subheadline).padding(.horizontal)

            ForEach($appearance.gradientColors) { $color in
                VStack(spacing: 8) {
                    HStack {
                        ColorPicker("Color Stop", selection: $color.color, supportsOpacity: true)
                        Spacer()
                        Button(action: {
                            if appearance.gradientColors.count > 1 {
                                appearance.gradientColors.removeAll { $0.id == color.id }
                            }
                        }) {
                            Image(systemName: "minus.circle.fill").foregroundColor(.red)
                        }
                        .buttonStyle(.plain)
                        .disabled(appearance.gradientColors.count <= 1)
                    }
                    Slider(value: $color.location, in: 0...1) {
                        Text("Location")
                    } minimumValueLabel: {
                        Text("0%")
                    } maximumValueLabel: {
                        Text("100%")
                    }
                }.padding(.horizontal)
            }

            Button(action: {
                var updatedColors = appearance.gradientColors
                if let lastColor = updatedColors.last {
                    let newLocation = min(1.0, lastColor.location + 0.2)
                    let newColorStop = CodableColor(color: lastColor.color, location: newLocation)
                    updatedColors.append(newColorStop)
                } else {
                    let newColorStop = CodableColor(color: .black, location: 0.0)
                    updatedColors.append(newColorStop)
                }
                appearance.gradientColors = updatedColors.sorted { $0.location < $1.location }
            }) {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text("Add Color Stop")
                }
            }
            .buttonStyle(.plain)
            .tint(.accentColor)
            .padding(.top, 5)
            .padding(.horizontal)
        }
        .padding(.vertical)
        .transition(.opacity)
    }
}

struct GeneralSettingsView: View {
    @EnvironmentObject var settings: SettingsModel
    @State private var showingCustomConfig = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("General")
                    .font(.largeTitle.bold())
                    .padding(.bottom)

                VStack(alignment: .leading, spacing: 0) {
                    Text("Behavior").font(.headline).padding([.top, .horizontal])
                        .frame(maxWidth: .infinity, alignment: .leading)
                    ForEach(GeneralSettingType.allCases) { setting in
                        GeneralSettingToggleRowView(setting: setting, isEnabled: binding(for: setting))
                        if setting != GeneralSettingType.allCases.last {
                            Divider().padding(.leading, 60)
                        }
                    }
                }.modifier(SettingsContainerModifier())

                VStack(alignment: .leading, spacing: 0) {
                    Text("System").font(.headline).padding([.top, .horizontal])
                        .frame(maxWidth: .infinity, alignment: .leading)

                    ToggleRow(title: "Launch at Login", description: "Start Sapphire automatically when you log in to your Mac.", isOn: $settings.settings.launchAtLogin)
                    Divider().padding(.leading, 20)

                    ToggleRow(title: "Enable Haptic Feedback", description: "Provide tactile feedback for certain interactions.", isOn: $settings.settings.hapticFeedbackEnabled)
                    Divider().padding(.leading, 20)

                    ToggleRow(title: "Hide from Screen Sharing", description: "Prevent the notch UI from appearing in screenshots or screen recordings.", isOn: $settings.settings.hideFromScreenSharing)
                    Divider().padding(.leading, 20)

                    ToggleRow(title: "Hide notch when no content is being displayed", description: "Prevent the notch UI from being visible in screenshots or screen recordings when no content is displayed.", isOn: $settings.settings.hideNotchWhenInactive)
                    Divider().padding(.leading, 20)

                    HStack {
                        Text("Show Notch On")
                        Spacer()
                        Picker("", selection: $settings.settings.notchDisplayTarget) {
                            ForEach(NotchDisplayTarget.allCases) { target in
                                Text(target.displayName).tag(target)
                            }
                        }.labelsHidden().frame(width: 200)
                    }.padding()

                }
                .modifier(SettingsContainerModifier())

                VStack(alignment: .leading, spacing: 0) {
                    Text("Widget Transitions")
                        .font(.headline)
                        .padding([.top, .horizontal])
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text("Control the visual effects when switching between widgets inside the expanded notch.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                        .padding(.bottom, 5)

                    Toggle("Enable Fade Effect", isOn: $settings.settings.enableWidgetSwitchFade)
                        .padding()
                    Divider().padding(.leading, 20)
                    Toggle("Enable Slide Effect", isOn: $settings.settings.enableWidgetSwitchSlide)
                        .padding()
                    Divider().padding(.leading, 20)
                    Toggle("Enable Bounce Effect", isOn: $settings.settings.enableWidgetSwitchBounce)
                        .padding()
                }
                .modifier(SettingsContainerModifier())

                VStack(alignment: .leading, spacing: 10) {
                    Text("Animation Profile")
                        .font(.headline)
                        .padding([.horizontal, .top])

                    Text(descriptionForCurrentProfile())
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                        .padding(.bottom, 5)

                    Picker("Animation Profile", selection: $settings.settings.animationProfile) {
                        ForEach(AnimationProfile.allCases) { profile in
                            Text(profile.displayName).tag(profile)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .padding(.bottom)

                    if settings.settings.animationProfile == .custom {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Custom Animation Values")
                                    .font(.subheadline.bold())
                                Spacer()
                                Button("Reset to Defaults") {
                                    withAnimation {
                                        settings.settings.customAnimationConfiguration = .init()
                                    }
                                }
                                .buttonStyle(.plain)
                                .foregroundColor(.accentColor)
                                .help("Reset all custom animation values to the 'Snappy' defaults.")
                            }

                            Text("Response: How long the animation takes (lower is faster).\nDamping: How much bounce (1.0 is no bounce).")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.bottom, 5)

                            Group {
                                Text("Main Transitions").font(.caption.bold()).foregroundColor(.secondary)
                                AnimationSliderRow(title: "Expand Response", description: "Opening the main widget view.", value: $settings.settings.customAnimationConfiguration.expandResponse, range: 0.1...1.0)
                                AnimationSliderRow(title: "Expand Damping", description: "", value: $settings.settings.customAnimationConfiguration.expandDamping, range: 0.4...1.0)
                                Divider()
                                AnimationSliderRow(title: "Collapse Response", description: "Closing the main widget view.", value: $settings.settings.customAnimationConfiguration.collapseResponse, range: 0.1...1.0)
                                AnimationSliderRow(title: "Collapse Damping", description: "", value: $settings.settings.customAnimationConfiguration.collapseDamping, range: 0.4...1.0)
                                Divider()
                                AnimationSliderRow(title: "Swipe Open Response", description: "Opening the widget with a trackpad swipe.", value: $settings.settings.customAnimationConfiguration.swipeOpenResponse, range: 0.1...1.0)
                                AnimationSliderRow(title: "Swipe Open Damping", description: "", value: $settings.settings.customAnimationConfiguration.swipeOpenDamping, range: 0.4...1.0)
                            }

                            Group {
                                Text("Dynamic States").font(.caption.bold()).foregroundColor(.secondary).padding(.top)
                                AnimationSliderRow(title: "Hover Response", description: "The small expansion when hovering over the notch.", value: $settings.settings.customAnimationConfiguration.hoverResponse, range: 0.1...1.0)
                                AnimationSliderRow(title: "Hover Damping", description: "", value: $settings.settings.customAnimationConfiguration.hoverDamping, range: 0.4...1.0)
                                Divider()
                                AnimationSliderRow(title: "Auto-Expand Response", description: "When a Live Activity appears automatically.", value: $settings.settings.customAnimationConfiguration.autoExpandResponse, range: 0.1...1.0)
                                AnimationSliderRow(title: "Auto-Expand Damping", description: "", value: $settings.settings.customAnimationConfiguration.autoExpandDamping, range: 0.4...1.0)
                            }

                            Group {
                                Text("Content & Activities").font(.caption.bold()).foregroundColor(.secondary).padding(.top)
                                AnimationSliderRow(title: "Content Transition Response", description: "How widgets appear inside the expanded view.", value: $settings.settings.customAnimationConfiguration.contentTransitionResponse, range: 0.1...1.0)
                                AnimationSliderRow(title: "Content Transition Damping", description: "", value: $settings.settings.customAnimationConfiguration.contentTransitionDamping, range: 0.4...1.0)
                                Divider()
                                AnimationSliderRow(title: "Activity Switch Response", description: "Transitioning between different Live Activities.", value: $settings.settings.customAnimationConfiguration.activityToActivityResponse, range: 0.1...1.0)
                                AnimationSliderRow(title: "Activity Switch Damping", description: "", value: $settings.settings.customAnimationConfiguration.activityToActivityDamping, range: 0.4...1.0)
                                Divider()
                                AnimationSliderRow(title: "Activity Morph Response", description: "Smoothly changing the shape of a Live Activity.", value: $settings.settings.customAnimationConfiguration.activityMorphResponse, range: 0.1...1.0)
                                AnimationSliderRow(title: "Activity Morph Damping", description: "", value: $settings.settings.customAnimationConfiguration.activityMorphDamping, range: 0.4...1.0)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.bottom)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .modifier(SettingsContainerModifier())
                .animation(.default, value: settings.settings.animationProfile)

                VStack(alignment: .leading, spacing: 0) {
                    Text("Advanced Customization").font(.headline).padding([.top, .horizontal])
                    ToggleRow(title: "Enable Custom Notch Configuration", description: "Override default appearance and animation values. This may lead to unexpected behavior.", isOn: $settings.settings.useCustomNotchConfiguration)

                    if settings.settings.useCustomNotchConfiguration {
                        Button("Edit Custom Configuration") {
                            showingCustomConfig = true
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                    }
                }
                .modifier(SettingsContainerModifier())
                .animation(.default, value: settings.settings.useCustomNotchConfiguration)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Notch Bar Items").font(.headline).padding([.horizontal, .top])
                    Text("Enable, disable, and reorder the icons that appear when you expand the notch.").font(.caption).foregroundColor(.secondary).padding(.horizontal).padding(.bottom, 5)
                    ReorderableVStack(items: $settings.settings.notchButtonOrder) { buttonType in
                        NotchButtonRowView(buttonType: buttonType)
                    }

                    ToggleRow(title: "Keep display on while caffinated", description: "Prevent the laptop to go to sleep wihle caffinated and in clamshell mode", isOn: $settings.settings.sleepInClamshell)
                    Divider().padding(.leading, 20)
                }
                .modifier(SettingsContainerModifier())

            }
            .padding(25)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .sheet(isPresented: $showingCustomConfig) {
            CustomNotchConfigView(config: $settings.settings.customNotchConfiguration)
        }
    }

    private func binding(for setting: GeneralSettingType) -> Binding<Bool> {
        switch setting {
        case .expandOnHover: return $settings.settings.expandOnHover
        case .swipeToSwitchWidgets: return $settings.settings.swipeToSwitchWidgets
        case .enableOpeningBounce: return $settings.settings.enableOpeningBounce
        }
    }

    private func descriptionForCurrentProfile() -> String {
        switch settings.settings.animationProfile {
        case .snappy:
            return "The default. A quick and responsive feel with minimal bounce."
        case .bouncy:
            return "A playful and energetic animation with noticeable bounce."
        case .calm:
            return "A slower, more graceful animation with a very gentle ease."
        case .custom:
            return "Fine-tune every animation parameter to your exact liking."
        }
    }
}

fileprivate struct AnimationSliderRow: View {
    let title: String
    let description: String
    @Binding var value: Double
    let range: ClosedRange<Double>

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                VStack(alignment: .leading) {
                    Text(title)
                    if !description.isEmpty {
                        Text(description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                Text(String(format: "%.2f", value))
                    .font(.body.monospacedDigit())
                    .foregroundColor(.secondary)
            }
            Slider(value: $value, in: range)
        }
        .padding(.vertical, 8)
    }
}

struct CustomNotchConfigView: View {
    @Binding var config: CustomizableNotchConfiguration
    @Environment(\.dismiss) var dismiss

    @State private var universalWidth: Double
    @State private var universalHeight: Double
    @State private var initialCornerRadius: Double
    @State private var topBuffer: Double
    @State private var scaleFactor: Double
    @State private var hoverExpandedCornerRadius: Double
    @State private var autoExpandedCornerRadius: Double
    @State private var autoExpandedTallHeight: Double
    @State private var autoExpandedContentVerticalPadding: Double
    @State private var clickExpandedCornerRadius: Double
    @State private var liveActivityBottomCornerRadius: Double
    @State private var collapseAnimationDelay: Double
    @State private var initialOpenCollapseDelay: Double
    @State private var widgetSwitchCollapseDelay: Double
    @State private var dragActivationCollapseDelay: Double
    @State private var expandAnimationResponse: Double
    @State private var expandAnimationDamping: Double
    @State private var swipeOpenAnimationResponse: Double
    @State private var swipeOpenAnimationDamping: Double
    @State private var collapseAnimationResponse: Double
    @State private var collapseAnimationDamping: Double
    @State private var widgetBlurRadiusMax: Double
    @State private var activityBlurRadiusMax: Double
    @State private var expandedShadowRadius: Double
    @State private var expandedShadowOffsetY: Double
    @State private var contentTopPadding: Double
    @State private var contentBottomPadding: Double
    @State private var contentHorizontalPadding: Double

    init(config: Binding<CustomizableNotchConfiguration>) {
        self._config = config
        let wrapped = config.wrappedValue

        _universalWidth = State(initialValue: Double(wrapped.universalWidth))
        _universalHeight = State(initialValue: Double(wrapped.universalHeight))
        _initialCornerRadius = State(initialValue: Double(wrapped.initialCornerRadius))
        _topBuffer = State(initialValue: Double(wrapped.topBuffer))
        _scaleFactor = State(initialValue: Double(wrapped.scaleFactor))
        _hoverExpandedCornerRadius = State(initialValue: Double(wrapped.hoverExpandedCornerRadius))
        _autoExpandedCornerRadius = State(initialValue: Double(wrapped.autoExpandedCornerRadius))
        _autoExpandedTallHeight = State(initialValue: Double(wrapped.autoExpandedTallHeight))
        _autoExpandedContentVerticalPadding = State(initialValue: Double(wrapped.autoExpandedContentVerticalPadding))
        _clickExpandedCornerRadius = State(initialValue: Double(wrapped.clickExpandedCornerRadius))
        _liveActivityBottomCornerRadius = State(initialValue: Double(wrapped.liveActivityBottomCornerRadius))
        _collapseAnimationDelay = State(initialValue: wrapped.collapseAnimationDelay)
        _initialOpenCollapseDelay = State(initialValue: wrapped.initialOpenCollapseDelay)
        _widgetSwitchCollapseDelay = State(initialValue: wrapped.widgetSwitchCollapseDelay)
        _dragActivationCollapseDelay = State(initialValue: wrapped.dragActivationCollapseDelay)
        _expandAnimationResponse = State(initialValue: wrapped.expandAnimationResponse)
        _expandAnimationDamping = State(initialValue: wrapped.expandAnimationDamping)
        _swipeOpenAnimationResponse = State(initialValue: wrapped.swipeOpenAnimationResponse)
        _swipeOpenAnimationDamping = State(initialValue: wrapped.swipeOpenAnimationDamping)
        _collapseAnimationResponse = State(initialValue: wrapped.collapseAnimationResponse)
        _collapseAnimationDamping = State(initialValue: wrapped.collapseAnimationDamping)
        _widgetBlurRadiusMax = State(initialValue: Double(wrapped.widgetBlurRadiusMax))
        _activityBlurRadiusMax = State(initialValue: Double(wrapped.activityBlurRadiusMax))
        _expandedShadowRadius = State(initialValue: Double(wrapped.expandedShadowRadius))
        _expandedShadowOffsetY = State(initialValue: Double(wrapped.expandedShadowOffsetY))
        _contentTopPadding = State(initialValue: Double(wrapped.contentTopPadding))
        _contentBottomPadding = State(initialValue: Double(wrapped.contentBottomPadding))
        _contentHorizontalPadding = State(initialValue: Double(wrapped.contentHorizontalPadding))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Custom Notch Configuration")
                    .font(.title2.bold())
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(spacing: 25) {
                    Section(header: Text("Sizing & Position").font(.headline)) {
                        CustomSliderRowView(label: "Universal Width", value: $universalWidth, range: 100...400, specifier: "%.1f")
                        CustomSliderRowView(label: "Universal Height", value: $universalHeight, range: 20...60, specifier: "%.1f")
                        CustomSliderRowView(label: "Auto-Expanded Height", value: $autoExpandedTallHeight, range: 50...150, specifier: "%.1f")
                        CustomSliderRowView(label: "Top Buffer", value: $topBuffer, range: 0...20, specifier: "%.1f")
                    }

                    Section(header: Text("Hover State").font(.headline)) {
                        CustomSliderRowView(label: "Hover Scale Factor", value: $scaleFactor, range: 1.0...1.5, specifier: "%.2f x")
                    }

                    Section(header: Text("Corner Radii").font(.headline)) {
                        CustomSliderRowView(label: "Initial", value: $initialCornerRadius, range: 5...50, specifier: "%.1f")
                        CustomSliderRowView(label: "Hover-Expanded", value: $hoverExpandedCornerRadius, range: 10...60, specifier: "%.1f")
                        CustomSliderRowView(label: "Auto-Expanded", value: $autoExpandedCornerRadius, range: 10...60, specifier: "%.1f")
                        CustomSliderRowView(label: "Click-Expanded", value: $clickExpandedCornerRadius, range: 10...60, specifier: "%.1f")
                        CustomSliderRowView(label: "Live Activity Bottom", value: $liveActivityBottomCornerRadius, range: 10...60, specifier: "%.1f")
                    }

                    Section(header: Text("Animation (Springs)").font(.headline)) {
                        CustomSliderRowView(label: "Expand Response", value: $expandAnimationResponse, range: 0.1...1.0, specifier: "%.2f")
                        CustomSliderRowView(label: "Expand Damping", value: $expandAnimationDamping, range: 0.1...1.0, specifier: "%.2f")
                        CustomSliderRowView(label: "Swipe Open Response", value: $swipeOpenAnimationResponse, range: 0.1...1.0, specifier: "%.2f")
                        CustomSliderRowView(label: "Swipe Open Damping", value: $swipeOpenAnimationDamping, range: 0.1...1.0, specifier: "%.2f")
                        CustomSliderRowView(label: "Collapse Response", value: $collapseAnimationResponse, range: 0.1...1.0, specifier: "%.2f")
                        CustomSliderRowView(label: "Collapse Damping", value: $collapseAnimationDamping, range: 0.1...1.0, specifier: "%.2f")
                    }

                    Section(header: Text("Delays").font(.headline)) {
                        CustomSliderRowView(label: "Collapse Animation Delay", value: $collapseAnimationDelay, range: 0.0...1.0, specifier: "%.2f s")
                        CustomSliderRowView(label: "Initial Open Collapse Delay", value: $initialOpenCollapseDelay, range: 0.5...5.0, specifier: "%.2f s")
                        CustomSliderRowView(label: "Widget Switch Collapse Delay", value: $widgetSwitchCollapseDelay, range: 1.0...10.0, specifier: "%.2f s")
                        CustomSliderRowView(label: "Drag Activation Collapse Delay", value: $dragActivationCollapseDelay, range: 0.0...1.0, specifier: "%.2f s")
                    }

                    Section(header: Text("Padding").font(.headline)) {
                        CustomSliderRowView(label: "Content Top Padding", value: $contentTopPadding, range: 0...50, specifier: "%.1f")
                        CustomSliderRowView(label: "Content Bottom Padding", value: $contentBottomPadding, range: 0...50, specifier: "%.1f")
                        CustomSliderRowView(label: "Content Horizontal Padding", value: $contentHorizontalPadding, range: 0...100, specifier: "%.1f")
                        CustomSliderRowView(label: "Auto-Expanded Vertical Padding", value: $autoExpandedContentVerticalPadding, range: 0...50, specifier: "%.1f")
                    }

                    Section(header: Text("Blur & Shadow").font(.headline)) {
                        CustomSliderRowView(label: "Widget Blur Radius Max", value: $widgetBlurRadiusMax, range: 0...100, specifier: "%.1f")
                        CustomSliderRowView(label: "Activity Blur Radius Max", value: $activityBlurRadiusMax, range: 0...100, specifier: "%.1f")
                        CustomSliderRowView(label: "Expanded Shadow Radius", value: $expandedShadowRadius, range: 0...50, specifier: "%.1f")
                        CustomSliderRowView(label: "Expanded Shadow Offset Y", value: $expandedShadowOffsetY, range: 0...30, specifier: "%.1f")
                    }
                }
                .padding()
            }

            Divider()

            HStack {
                Button("Reset to Defaults") {
                    let defaultConfig = CustomizableNotchConfiguration()
                    syncState(from: defaultConfig)
                }
                Spacer()
                Button("Done") {
                    syncConfig()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(minWidth: 550, idealWidth: 600, minHeight: 400, idealHeight: 750)
    }

    private func syncState(from sourceConfig: CustomizableNotchConfiguration) {
        universalWidth = Double(sourceConfig.universalWidth)
        universalHeight = Double(sourceConfig.universalHeight)
        initialCornerRadius = Double(sourceConfig.initialCornerRadius)
        topBuffer = Double(sourceConfig.topBuffer)
        scaleFactor = Double(sourceConfig.scaleFactor)
        hoverExpandedCornerRadius = Double(sourceConfig.hoverExpandedCornerRadius)
        autoExpandedCornerRadius = Double(sourceConfig.autoExpandedCornerRadius)
        autoExpandedTallHeight = Double(sourceConfig.autoExpandedTallHeight)
        autoExpandedContentVerticalPadding = Double(sourceConfig.autoExpandedContentVerticalPadding)
        clickExpandedCornerRadius = Double(sourceConfig.clickExpandedCornerRadius)
        liveActivityBottomCornerRadius = Double(sourceConfig.liveActivityBottomCornerRadius)
        collapseAnimationDelay = sourceConfig.collapseAnimationDelay
        initialOpenCollapseDelay = sourceConfig.initialOpenCollapseDelay
        widgetSwitchCollapseDelay = sourceConfig.widgetSwitchCollapseDelay
        dragActivationCollapseDelay = sourceConfig.dragActivationCollapseDelay
        expandAnimationResponse = sourceConfig.expandAnimationResponse
        expandAnimationDamping = sourceConfig.expandAnimationDamping
        swipeOpenAnimationResponse = sourceConfig.swipeOpenAnimationResponse
        swipeOpenAnimationDamping = sourceConfig.swipeOpenAnimationDamping
        collapseAnimationResponse = sourceConfig.collapseAnimationResponse
        collapseAnimationDamping = sourceConfig.collapseAnimationDamping
        widgetBlurRadiusMax = Double(sourceConfig.widgetBlurRadiusMax)
        activityBlurRadiusMax = Double(sourceConfig.activityBlurRadiusMax)
        expandedShadowRadius = Double(sourceConfig.expandedShadowRadius)
        expandedShadowOffsetY = Double(sourceConfig.expandedShadowOffsetY)
        contentTopPadding = Double(sourceConfig.contentTopPadding)
        contentBottomPadding = Double(sourceConfig.contentBottomPadding)
        contentHorizontalPadding = Double(sourceConfig.contentHorizontalPadding)
    }

    private func syncConfig() {
        config.universalWidth = CGFloat(universalWidth)
        config.universalHeight = CGFloat(universalHeight)
        config.initialCornerRadius = CGFloat(initialCornerRadius)
        config.topBuffer = CGFloat(topBuffer)
        config.scaleFactor = CGFloat(scaleFactor)
        config.hoverExpandedCornerRadius = CGFloat(hoverExpandedCornerRadius)
        config.autoExpandedCornerRadius = CGFloat(autoExpandedCornerRadius)
        config.autoExpandedTallHeight = CGFloat(autoExpandedTallHeight)
        config.autoExpandedContentVerticalPadding = CGFloat(autoExpandedContentVerticalPadding)
        config.clickExpandedCornerRadius = CGFloat(clickExpandedCornerRadius)
        config.liveActivityBottomCornerRadius = CGFloat(liveActivityBottomCornerRadius)
        config.collapseAnimationDelay = collapseAnimationDelay
        config.initialOpenCollapseDelay = initialOpenCollapseDelay
        config.widgetSwitchCollapseDelay = widgetSwitchCollapseDelay
        config.dragActivationCollapseDelay = dragActivationCollapseDelay
        config.expandAnimationResponse = expandAnimationResponse
        config.expandAnimationDamping = expandAnimationDamping
        config.swipeOpenAnimationResponse = swipeOpenAnimationResponse
        config.swipeOpenAnimationDamping = swipeOpenAnimationDamping
        config.collapseAnimationResponse = collapseAnimationResponse
        config.collapseAnimationDamping = collapseAnimationDamping
        config.widgetBlurRadiusMax = CGFloat(widgetBlurRadiusMax)
        config.activityBlurRadiusMax = CGFloat(activityBlurRadiusMax)
        config.expandedShadowRadius = CGFloat(expandedShadowRadius)
        config.expandedShadowOffsetY = CGFloat(expandedShadowOffsetY)
        config.contentTopPadding = CGFloat(contentTopPadding)
        config.contentBottomPadding = CGFloat(contentBottomPadding)
        config.contentHorizontalPadding = CGFloat(contentHorizontalPadding)
    }
}

struct FileShelfSettingsView: View {
    @EnvironmentObject var settings: SettingsModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("File Shelf")
                    .font(.largeTitle.bold())
                    .padding(.bottom)

                VStack(alignment: .leading, spacing: 0) {
                    ToggleRow(
                        title: "Expand Shelf on Hover",
                        description: "Automatically expand the full File Shelf by hovering over its live activity.",
                        isOn: $settings.settings.hoverToOpenFileShelf
                    )

                    Divider().padding(.leading, 20)

                    ToggleRow(
                        title: "Open Shelf on Live Activity Click",
                        description: "Clicking the File Shelf live activity opens the shelf instead of the default widgets.",
                        isOn: $settings.settings.clickToOpenFileShelf
                    )
                }
                .modifier(SettingsContainerModifier())
            }
            .padding(25)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }
}

struct WidgetsSettingsView: View {
    @EnvironmentObject var settings: SettingsModel

    private var enabledWidgetCount: Int {
        var count = 0
        if settings.settings.musicWidgetEnabled { count += 1 }
        if settings.settings.weatherWidgetEnabled { count += 1 }
        if settings.settings.calendarWidgetEnabled { count += 1 }
        if settings.settings.shortcutsWidgetEnabled { count += 1 }
        return count
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Widgets").font(.largeTitle.bold()).padding(.bottom)

                VStack(alignment: .leading, spacing: 0) {
                    Text("Behavior").font(.headline).padding([.top, .horizontal])
                    ToggleRow(
                        title: "Remember Last Open Menu",
                        description: "When re-opening the notch, it will return to the last menu you had open.",
                        isOn: $settings.settings.rememberLastMenu
                    )
                    Divider().padding(.leading, 20)
                    ToggleRow(title: "Hide Music Widget", description: "Hide music widget if no media is playing", isOn: $settings.settings.hideMusicWidgetWhenNotPlaying)
                }
                .modifier(SettingsContainerModifier())

                VStack(alignment: .leading, spacing: 0) {
                    Text("Appearance").font(.headline).padding([.top, .horizontal])
                    ToggleRow(title: "Show Dividers Between Widgets", description: "Display a subtle line separating each widget.", isOn: $settings.settings.showDividersBetweenWidgets)
                }
                .modifier(SettingsContainerModifier())

                VStack(alignment: .leading, spacing: 10) {
                    Text("Widget Visibility & Order").font(.headline).padding([.horizontal, .top])
                    Text("Enable, disable, and reorder the widgets that appear in the notch.").font(.caption).foregroundColor(.secondary).padding(.horizontal).padding(.bottom, 5)
                    ReorderableVStack(items: $settings.settings.widgetOrder) { widget in
                        WidgetRowView(widgetType: widget, enabledWidgetCount: enabledWidgetCount)
                    }
                    .modifier(SettingsContainerModifier())
                }
            }
            .padding(25)
        }
    }
}

struct LiveActivitiesSettingsView: View {
    @EnvironmentObject var settings: SettingsModel
    @StateObject private var statsManager = StatsManager.shared
    @ObservedObject private var eyeBreakManager = EyeBreakManager.shared

    private enum PersistentActivitySelection: String, CaseIterable, Identifiable {
        case none = "None"
        case stats = "Stats"
        case battery = "Battery"
        case weather = "Weather"
        var id: String { self.rawValue }
    }

    private var persistentActivityBinding: Binding<PersistentActivitySelection> {
        Binding(
            get: {
                if settings.settings.showPersistentStatsLiveActivity {
                    return .stats
                } else if settings.settings.showPersistentBatteryLiveActivity {
                    return .battery
                } else if settings.settings.showPersistentWeatherLiveActivity {
                    return .weather
                } else {
                    return .none
                }
            },
            set: { newValue in
                settings.settings.showPersistentStatsLiveActivity = (newValue == .stats)
                settings.settings.showPersistentBatteryLiveActivity = (newValue == .battery)
                settings.settings.showPersistentWeatherLiveActivity = (newValue == .weather)
            }
        )
    }

    private func hideInFullScreenBinding(for type: LiveActivityType) -> Binding<Bool> {
        return Binding(
            get: { settings.settings.hideActivitiesInFullScreen[type.rawValue, default: false] },
            set: { settings.settings.hideActivitiesInFullScreen[type.rawValue] = $0 }
        )
    }

    private func binding(for statType: StatType) -> Binding<StatThreshold> {
        return Binding(
            get: { settings.settings.statThresholds[statType, default: StatThreshold()] },
            set: { settings.settings.statThresholds[statType] = $0 }
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Live Activities").font(.largeTitle.bold()).padding(.bottom)
                VStack(alignment: .leading, spacing: 0) {
                    Text("General Behavior").font(.headline).padding([.top, .horizontal])
                    ToggleRow(
                          title: "Show compact focus live activity text",
                          description: "Instead of showing the full focus name, only on/off.",
                          isOn: Binding(
                              get: { settings.settings.focusDisplayMode == .compact },
                              set: { settings.settings.focusDisplayMode = $0 ? .compact : .full }
                          )
                      )

                    ToggleRow(
                          title: "Show compact battery live activity",
                          description: "Instead of showing the full state, only show icon.",
                          isOn: Binding(
                            get: { settings.settings.batteryNotificationStyle == .compact },
                            set: { settings.settings.batteryNotificationStyle = $0 ? .compact : .default }
                          )
                      )
                    ToggleRow(title: "Swipe to Dismiss", description: "Swipe down on a live activity to dismiss it.", isOn: $settings.settings.swipeToDismissLiveActivity)
                    Divider().padding(.leading, 20)
                    ToggleRow(
                        title: "Hide When Source App is Active",
                        description: "Automatically hide the music live activity when Spotify or Music is the frontmost app.",
                        isOn: $settings.settings.hideLiveActivityWhenSourceActive
                    )
                    Divider().padding(.leading, 20)
                    ToggleRow(title: "Hide All in Full Screen", description: "Automatically hide all live activities when an app is in full screen.", isOn: $settings.settings.hideLiveActivityInFullScreen)

                    DisclosureGroup("Advanced: Hide Specific Activities in Full Screen") {
                        VStack(spacing: 0) {
                            ForEach(LiveActivityType.allCases) { activityType in
                                Toggle(activityType.displayName, isOn: hideInFullScreenBinding(for: activityType))
                                    .padding(.vertical, 8)
                            }
                        }
                        .padding(.top, 10)
                    }
                    .padding()
                    .disabled(settings.settings.hideLiveActivityInFullScreen)
                    .opacity(settings.settings.hideLiveActivityInFullScreen ? 0.5 : 1.0)

                }
                .modifier(SettingsContainerModifier())
                .animation(.default, value: settings.settings.hideLiveActivityInFullScreen)

                VStack(alignment: .leading, spacing: 0) {
                    Text("Persistent Activity").font(.headline).padding([.top, .horizontal])

                    InfoContainer(
                        text: "Choose one activity to be displayed persistently when no other higher-priority activity is active.",
                        iconName: "pin.circle.fill",
                        color: .blue
                    ).padding()

                    HStack {
                        Text("Persistent Activity")
                        Spacer()
                        Picker("Persistent Activity", selection: persistentActivityBinding) {
                            ForEach(PersistentActivitySelection.allCases) { option in
                                Text(option.rawValue).tag(option)
                            }
                        }
                        .labelsHidden()
                    }
                    .padding()

                    if persistentActivityBinding.wrappedValue == .stats && !settings.settings.statsLiveActivityEnabled {
                        InfoContainer(text: "Enable the 'Stats' live activity below to select it as persistent.", iconName: "info.circle", color: .yellow)
                            .padding([.horizontal, .bottom])
                    } else if persistentActivityBinding.wrappedValue == .weather && !settings.settings.weatherLiveActivityEnabled {
                        InfoContainer(text: "Enable the 'Weather' live activity below to select it as persistent.", iconName: "info.circle", color: .yellow)
                            .padding([.horizontal, .bottom])
                    } else if persistentActivityBinding.wrappedValue == .battery && !settings.settings.batteryLiveActivityEnabled {
                        InfoContainer(text: "Enable the 'Weather' live activity below to select it as persistent.", iconName: "info.circle", color: .yellow)
                            .padding([.horizontal, .bottom])
                    }

                    Divider().padding(.leading, 20)

                    HStack {
                        Text("Weather Live Activity Popup Interval")
                        Spacer()
                        Picker("", selection: $settings.settings.weatherLiveActivityInterval) {
                            Text("5 min").tag(5); Text("10 min").tag(10); Text("15 min").tag(15); Text("30 min").tag(30)
                        }.labelsHidden()
                    }
                    .padding()
                    .disabled(persistentActivityBinding.wrappedValue == .weather)
                    .opacity(persistentActivityBinding.wrappedValue == .weather ? 0.5 : 1.0)
                }
                .modifier(SettingsContainerModifier())
                .animation(.default, value: persistentActivityBinding.wrappedValue)

                if settings.settings.statsLiveActivityEnabled {
                    SensorSelectionView(
                        selectedStats: $settings.settings.selectedStats,
                        selectedSensorKeys: $settings.settings.selectedSensorKeys,
                        allSensors: statsManager.allSensors
                    )
                    .transition(.opacity.combined(with: .move(edge: .top)))

                    VStack(alignment: .leading, spacing: 12) {
                        Toggle(isOn: $settings.settings.statsLiveActivityThresholdEnabled) {
                            Text("Only Show When Usage is High")
                                .font(.headline)
                        }
                        .padding()
                        .toggleStyle(.switch)

                        if settings.settings.statsLiveActivityThresholdEnabled {
                            VStack(alignment: .leading, spacing: 15) {
                                StatThresholdRow(label: "CPU", threshold: binding(for: .cpu))
                                StatThresholdRow(label: "RAM", threshold: binding(for: .ram))
                                StatThresholdRow(label: "GPU", threshold: binding(for: .gpu))
                            }
                            .padding()
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                    .padding()
                    .modifier(SettingsContainerModifier())
                    .animation(.easeInOut, value: settings.settings.statsLiveActivityThresholdEnabled)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Activity Visibility & Order").font(.headline).padding([.horizontal, .top])
                    Text("Enable, disable, and reorder all available Live Activities.").font(.caption).foregroundColor(.secondary).padding(.horizontal).padding(.bottom, 5)
                    if settings.settings.statsLiveActivityEnabled {
                        InfoContainer(text: "Enabling stats will increase the app's cpu and power consumption.", iconName: "info.circle", color: .yellow)
                    }
                    ReorderableVStack(items: $settings.settings.liveActivityOrder) { activity in
                        LiveActivityRowView(activityType: activity)
                    }
                    .modifier(SettingsContainerModifier())
                }
                .onChange(of: settings.settings.eyeBreakLiveActivityEnabled) {
                    eyeBreakManager.dismissBreak()
                }

                RequiredPermissionsView(section: .liveActivities)
            }
            .padding(25)
            .animation(.default, value: settings.settings.statsLiveActivityEnabled)
        }
    }
}

struct StatThresholdRow: View {
    let label: String
    @Binding var threshold: StatThreshold

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: $threshold.isEnabled) {
                Text(label)
            }
            .toggleStyle(.switch)

            if threshold.isEnabled {
                HStack {
                    Text("Threshold")
                        .foregroundColor(.secondary)
                    Spacer()
                    Stepper(
                        "\(threshold.value)%",
                        value: $threshold.value,
                        in: 1...100,
                        step: 5
                    )
                }
                .padding(.leading, 20)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: threshold.isEnabled)
    }
}

fileprivate struct SensorSelectionView: View {
    @Binding var selectedStats: [StatType]
    @Binding var selectedSensorKeys: [String]
    let allSensors: [Sensor_p]

    private var groupedSensors: [SensorGroup: [Sensor_p]] {
        Dictionary(grouping: allSensors, by: { $0.group })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Stats Configuration").font(.headline).padding([.top, .horizontal])

            DisclosureGroup("Select high-level stats") {
                VStack(spacing: 0) {
                    ForEach(StatType.allCases) { statType in
                        Toggle(statType.displayName, isOn: Binding<Bool>(
                            get: { selectedStats.contains(statType) },
                            set: { isSelected in
                                if isSelected {
                                    if !selectedStats.contains(statType) {
                                        selectedStats.append(statType)
                                    }
                                } else {
                                    selectedStats.removeAll { $0 == statType }
                                }
                            }
                        ))
                        .padding(.vertical, 8)
                    }
                }
                .padding(.top, 10)
            }
            .padding()

            Divider().padding(.horizontal)

            DisclosureGroup("Select individual sensors") {
                if allSensors.isEmpty {
                    VStack {
                        ProgressView()
                        Text("Loading sensors...")
                            .foregroundColor(.secondary)
                            .padding(.top, 8)
                    }
                    .frame(height: 300)
                    .frame(maxWidth: .infinity)
                } else {
                    List {
                        ForEach(SensorGroup.allCases, id: \.self) { group in
                            if let groupSensors = groupedSensors[group], !groupSensors.isEmpty {
                                Section(header: Text(group.rawValue).font(.headline)) {
                                    ForEach(groupSensors, id: \.key) { sensor in
                                        Toggle(sensor.name, isOn: Binding<Bool>(
                                            get: { selectedSensorKeys.contains(sensor.key) },
                                            set: { isSelected in
                                                if isSelected {
                                                    if !selectedSensorKeys.contains(sensor.key) {
                                                        selectedSensorKeys.append(sensor.key)
                                                    }
                                                } else {
                                                    selectedSensorKeys.removeAll { $0 == sensor.key }
                                                }
                                            }
                                        ))
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(.sidebar)
                    .frame(height: 300)
                }
            }
            .padding()
        }
        .modifier(SettingsContainerModifier())
    }
}

struct ShortcutsSettingsView: View {
    @EnvironmentObject var settings: SettingsModel
    @StateObject private var fetcher = ShortcutsFetcher()
    @State private var searchText: String = ""

    private var filteredAvailableShortcuts: [ShortcutInfo] {
        let selectedIDs = Set(settings.settings.selectedShortcuts.map { $0.id })
        let available = fetcher.allShortcuts.filter { !selectedIDs.contains($0.id) }

        if searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            return available
        }

        return available.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Shortcuts Widget")
                    .font(.largeTitle.bold())
                    .padding(.bottom)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Added to Widget")
                        .font(.headline)
                        .padding(.horizontal)

                    VStack {
                        if settings.settings.selectedShortcuts.isEmpty {
                            Text("No shortcuts added.")
                                .font(.caption).foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, minHeight: 60, alignment: .center)
                        } else {
                            let rowHeight: CGFloat = 44
                            List {
                                ForEach($settings.settings.selectedShortcuts) { $shortcut in
                                    AddedShortcutRow(shortcut: $shortcut, onRemove: {
                                        removeShortcut(shortcut)
                                    })
                                }
                                .listRowBackground(Color.clear)
                            }
                            .listStyle(.plain)
                            .scrollContentBackground(.hidden)
                            .frame(height: CGFloat(settings.settings.selectedShortcuts.count) * rowHeight)
                        }
                    }
                }
                .padding(.vertical)
                .modifier(SettingsContainerModifier())

                VStack(alignment: .leading, spacing: 10) {
                    Text("Available Shortcuts")
                        .font(.headline).padding(.horizontal)

                    TextField("Search Shortcuts", text: $searchText)
                        .textFieldStyle(.plain).padding(8)
                        .background(Color.black.opacity(0.2)).clipShape(RoundedRectangle(cornerRadius: 8))
                        .padding(.horizontal)

                    if fetcher.isLoading {
                        ProgressView().frame(maxWidth: .infinity, minHeight: 200)
                    } else if let error = fetcher.accessError {
                         InfoContainer(text: error, iconName: "exclamationmark.triangle.fill", color: .yellow)
                            .padding(.horizontal)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                if filteredAvailableShortcuts.isEmpty {
                                    Text(searchText.isEmpty ? "No shortcuts found." : "No shortcuts match your search.")
                                        .font(.caption).foregroundColor(.secondary).padding()
                                } else {
                                    ForEach(filteredAvailableShortcuts) { shortcut in
                                        AvailableShortcutRow(shortcut: shortcut, onAdd: { addShortcut(shortcut) })
                                    }
                                }
                            }
                        }
                        .frame(maxHeight: 350)
                    }
                }
                .padding(.vertical)
                .modifier(SettingsContainerModifier())
            }
            .padding(25)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .onAppear(perform: fetcher.fetchAllShortcuts)
        }
    }

    private func addShortcut(_ shortcut: ShortcutInfo) {
        if !settings.settings.selectedShortcuts.contains(where: { $0.id == shortcut.id }) {
            settings.settings.selectedShortcuts.append(shortcut)
        }
    }

    private func removeShortcut(_ shortcutToRemove: ShortcutInfo) {
        settings.settings.selectedShortcuts.removeAll { $0.id == shortcutToRemove.id }
    }
}

fileprivate struct AddedShortcutRow: View {
    @Binding var shortcut: ShortcutInfo
    let onRemove: () -> Void
    @State private var isShowingEditor = false

    var body: some View {
        HStack(spacing: 12) {
            Button(action: { isShowingEditor = true }) {
                Image(nsImage: ShortcutsManager.shared.getIcon(for: shortcut))
                    .resizable().frame(width: 28, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .id(shortcut)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $isShowingEditor, arrowEdge: .leading) {
                ShortcutEditorView(shortcut: $shortcut)
            }

            Text(shortcut.name)
            Spacer()

            Button(action: onRemove) {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.red.opacity(0.8))
            }
            .buttonStyle(.plain)
        }
        .padding(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
    }
}

fileprivate struct AvailableShortcutRow: View {
    let shortcut: ShortcutInfo
    let onAdd: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: onAdd) {
            HStack(spacing: 12) {
                Image(nsImage: ShortcutsManager.shared.getIcon(for: shortcut))
                    .resizable().frame(width: 28, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                Text(shortcut.name)
                    .foregroundColor(isEnabled ? .primary : .secondary)
                Spacer()
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(isEnabled ? .green.opacity(0.8) : .secondary)
            }
        }
        .buttonStyle(.plain)
        .padding(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
    }
}

fileprivate struct ShortcutEditorView: View {
    @Binding var shortcut: ShortcutInfo
    @State private var isShowingIconPicker = false

    private var backgroundColorBinding: Binding<Color> {
        Binding(
            get: { shortcut.backgroundColor?.color ?? .gray },
            set: { shortcut.backgroundColor = CodableColor(color: $0) }
        )
    }

    private var iconColorBinding: Binding<Color> {
        Binding(
            get: { shortcut.iconColor?.color ?? .white },
            set: { shortcut.iconColor = CodableColor(color: $0) }
        )
    }

    var body: some View {
        VStack(spacing: 15) {
            Text("Edit Shortcut")
                .font(.headline)

            Image(nsImage: ShortcutsManager.shared.getIcon(for: shortcut))
                .resizable()
                .frame(width: 80, height: 80)
                .clipShape(RoundedRectangle(cornerRadius: 18))

            VStack(spacing: 10) {
                ColorPicker("Background Color", selection: backgroundColorBinding, supportsOpacity: false)
                ColorPicker("Icon Color", selection: iconColorBinding, supportsOpacity: false)

                Button("Change Icon") {
                    isShowingIconPicker = true
                }
            }
        }
        .padding()
        .frame(width: 250)
        .background(.ultraThinMaterial)
        .sheet(isPresented: $isShowingIconPicker) {
            IconPickerView { selectedSymbol in
                shortcut.systemImageName = selectedSymbol
            }
        }
    }
}

fileprivate struct IconPickerView: View {
    let onSelect: (String) -> Void
    @Environment(\.dismiss) var dismiss

    @State private var searchText = ""
    @State private var isSearchVisible = false

    struct IconSection: Identifiable {
        let id = UUID()
        let title: String
        let symbols: [String]
    }

    static let iconSections: [IconSection] = [
        IconSection(title: "Interface & General", symbols: [
            "house.fill", "house", "gearshape.fill", "gearshape", "gearshape.2.fill", "gearshape.2",
            "slider.horizontal.3", "slider.vertical.3", "ellipsis", "ellipsis.circle.fill", "ellipsis.circle",
            "plus", "plus.circle.fill", "plus.circle", "minus", "minus.circle.fill", "minus.circle",
            "xmark", "xmark.circle.fill", "xmark.circle", "checkmark", "checkmark.circle.fill", "checkmark.circle",
            "questionmark.circle.fill", "questionmark.circle", "info.circle.fill", "info.circle",
            "magnifyingglass", "link", "link.circle.fill", "link.circle", "lock.fill", "lock.open.fill",
            "key.fill", "key", "bell.fill", "bell", "bell.slash.fill", "bell.slash",
            "lightbulb.fill", "lightbulb", "flag.fill", "flag", "bookmark.fill", "bookmark",
            "tag.fill", "tag", "pin.fill", "pin", "archivebox.fill", "archivebox",
            "square.and.arrow.up", "square.and.arrow.down", "arrow.clockwise", "arrow.counterclockwise",
            "gobackward", "goforward", "eject.fill", "eject", "power", "power.circle.fill", "power.circle",
            "app.fill", "app", "window.vertical.closed", "macwindow", "sidebar.left", "sidebar.right",
            "dock.rectangle", "ruler.fill", "ruler", "screwdriver.fill", "screwdriver", "hammer.fill", "hammer",
            "wrench.and.screwdriver.fill", "wrench.and.screwdriver", "eyedropper", "eyedropper.halffull",
            "paintpalette.fill", "paintpalette", "crop", "rotate.right.fill", "rotate.left.fill",
            "sparkle", "sparkles", "star.fill", "star", "heart.fill", "heart",
            "eye.fill", "eye", "eye.slash.fill", "eye.slash", "viewfinder",
            "camera.macro.circle.fill", "camera.macro.circle", "camera.macro",
            "trash.fill", "trash", "square.grid.2x2.fill", "square.grid.2x2", "list.bullet", "list.number",
            "list.dash", "list.clipboard.fill", "list.clipboard"
        ]),

        IconSection(title: "Files & Documents", symbols: [
            "folder.fill", "folder", "folder.circle.fill", "folder.circle", "folder.badge.plus",
            "folder.badge.minus", "folder.badge.person.crop", "folder.badge.questionmark",
            "doc.fill", "doc", "doc.text.fill", "doc.text", "doc.plaintext.fill", "doc.plaintext",
            "doc.richtext.fill", "doc.richtext", "doc.on.doc.fill", "doc.on.doc",
            "doc.on.clipboard.fill", "doc.on.clipboard", "doc.badge.plus", "doc.badge.gearshape.fill",
            "doc.badge.gearshape", "doc.badge.clock.fill", "doc.badge.clock",
            "doc.badge.ellipsis",
            "archivebox.fill", "archivebox", "paperclip", "note.text",
            "note.text.badge.plus", "newspaper.fill", "newspaper", "book.fill", "book", "books.vertical.fill",
            "books.vertical", "scroll.fill", "scroll", "receipt.fill", "receipt",
            "list.bullet.rectangle.portrait.fill", "list.bullet.rectangle.portrait", "text.magnifyingglass",
            "signature", "square.and.pencil", "square.and.pencil.circle.fill", "square.and.pencil.circle",
            "photo.stack.fill", "photo.stack", "square.stack.3d.up.fill", "square.stack.3d.up",
            "square.stack.3d.down.right.fill", "square.stack.3d.down.right",
            "square.stack.3d.up.slash.fill", "square.stack.3d.up.slash",
            "doc.questionmark", "doc.questionmark.fill", "doc.append", "doc.fill.badge.plus",
            "doc.text.image.fill", "doc.text.image", "doc.badge.arrow.up.fill", "doc.badge.arrow.up"
        ]),

        IconSection(title: "Text & Editing", symbols: [
            "pencil", "pencil.circle", "pencil.circle.fill", "eraser.fill", "eraser", "highlighter", "scissors",
            "textformat", "textformat.size", "textformat.abc", "textformat.123",
            "bold", "italic", "underline", "strikethrough", "paragraphsign",
            "text.alignleft", "text.aligncenter", "text.alignright", "text.justify",
            "increase.indent", "decrease.indent", "list.bullet.indent", "quotelevel", "text.bubble.fill",
            "text.bubble", "return", "line.diagonal", "curlybraces",
            "point.topleft.down.curvedto.point.bottomright.up.fill",
            "a.circle.fill", "a.circle", "b.circle.fill", "b.circle", "c.circle.fill", "c.circle",
            "d.circle.fill", "d.circle", "e.circle.fill", "e.circle", "f.circle.fill", "f.circle",
            "g.circle.fill", "g.circle", "h.circle.fill", "h.circle", "i.circle.fill", "i.circle",
            "j.circle.fill", "j.circle", "k.circle.fill", "k.circle", "l.circle.fill", "l.circle",
            "m.circle.fill", "m.circle", "n.circle.fill", "n.circle", "o.circle.fill", "o.circle",
            "p.circle.fill", "p.circle", "q.circle.fill", "q.circle", "r.circle.fill", "r.circle",
            "s.circle.fill", "s.circle", "t.circle.fill", "t.circle", "u.circle.fill", "u.circle",
            "v.circle.fill", "v.circle", "w.circle.fill", "w.circle", "x.circle.fill", "x.circle",
            "y.circle.fill", "y.circle", "z.circle.fill", "z.circle",
            "0.circle.fill", "0.circle", "1.circle.fill", "1.circle", "2.circle.fill", "2.circle",
            "3.circle.fill", "3.circle", "4.circle.fill", "4.circle", "5.circle.fill", "5.circle",
            "6.circle.fill", "6.circle", "7.circle.fill", "7.circle", "8.circle.fill", "8.circle",
            "9.circle.fill", "9.circle",
            "number", "at", "textformat.alt",
            "asterisk", "questionmark", "exclamationmark", "percent",
            "plusminus", "divide", "equal", "dollarsign", "eurosign", "yensign", "coloncurrencysign",
            "bitcoinsign", "point.3.connected.trianglepath.dotted"
        ]),

        IconSection(title: "Media & Audio", symbols: [
            "play.fill", "play", "pause.fill", "pause", "stop.fill", "stop", "record.circle.fill", "record.circle",
            "forward.fill", "forward", "backward.fill", "backward",
            "gobackward.10", "goforward.10", "gobackward.15", "goforward.15", "gobackward.30", "goforward.30",
            "gobackward.45", "goforward.45", "gobackward.60", "goforward.60", "gobackward.75", "goforward.75",
            "gobackward.90", "goforward.90",
            "shuffle", "repeat", "repeat.1", "music.note", "music.note.list", "mic.fill", "mic",
            "mic.slash.fill", "mic.slash", "speaker.wave.3.fill", "speaker.wave.3", "speaker.slash.fill",
            "speaker.slash", "hifispeaker.fill", "hifispeaker", "waveform", "waveform.path", "waveform.path.ecg",
            "waveform.path.ecg.rectangle.fill", "waveform.path.ecg.rectangle", "earpods", "headphones",
            "airpods.chargingcase",
            "airpods", "airpodsmax", "hifispeaker.and.homepodmini.fill",
            "photo.fill", "photo", "camera.fill", "camera", "video.fill", "video", "film.fill", "film",
            "photo.on.rectangle.angled.fill", "photo.on.rectangle.angled",
            "video.badge.plus", "video.badge.waveform.fill", "video.badge.waveform", "airplayvideo", "airplayaudio",
            "captions.bubble.fill", "captions.bubble", "tv.fill", "tv", "tv.and.hifispeaker.fill",
            "opticaldisc.fill", "opticaldisc", "amplifier",
            "metronome.fill", "metronome", "guitars.fill", "guitars", "tuningfork", "square.and.arrow.up.trianglebadge.exclamationmark",
            "music.mic",
            "play.rectangle.fill", "play.rectangle"
        ]),

        IconSection(title: "Time & Date", symbols: [
            "clock.fill", "clock", "alarm.fill", "alarm", "timer", "stopwatch.fill", "stopwatch",
            "calendar", "calendar.circle.fill", "calendar.circle", "calendar.badge.plus",
            "calendar.badge.clock", "hourglass", "hourglass.tophalf.fill", "hourglass.bottomhalf.fill",
            "sunrise.fill", "sunrise", "sunset.fill", "sunset", "moon.stars.fill", "moon.stars",
            "moon.fill", "moon", "timelapse", "rays", "deskclock.fill", "deskclock"
        ]),

        IconSection(title: "Connectivity & Devices", symbols: [
            "wifi", "wifi.slash", "dot.radiowaves.left.and.right", "network", "globe", "globe.americas.fill",
            "globe.europe.africa.fill", "personalhotspot", "antenna.radiowaves.left.and.right",
            "wave.3.right.circle.fill",
            "bolt.fill", "bolt", "bolt.slash.fill", "bolt.slash", "battery.100",
            "battery.25", "battery.0", "battery.100.bolt",
            "bolt.batteryblock.fill", "bolt.batteryblock",
            "iphone", "iphone.landscape", "ipad", "ipad.landscape",
            "applewatch", "applewatch.radiowaves.left.and.right", "applewatch.slash",
            "applewatch.side.right", "macbook", "macbook.gen1", "desktopcomputer",
            "display", "tv.fill", "tv", "keyboard.fill", "keyboard", "magicmouse.fill", "computermouse.fill",
            "computermouse", "printer.fill", "printer", "externaldrive.fill", "externaldrive",
            "externaldrive.fill.badge.plus", "externaldrive.fill.badge.minus",
            "externaldrive.fill.badge.checkmark", "externaldrive.connected.to.line.below",
            "airtag.fill", "airtag", "ipodtouch.landscape", "ipodtouch", "ipod",
            "applepencil", "homepod.fill", "homepod", "homepodmini.fill", "homepodmini", "appletv.fill",
            "airpods.chargingcase.fill", "airpods.chargingcase", "airpods.chargingcase.wireless.fill",
            "airpods.chargingcase.wireless", "bonjour",
            "apple.terminal.fill", "apple.terminal", "laptopcomputer.and.arrow.down",
            "laptopcomputer"
        ]),

        IconSection(title: "Communication", symbols: [
            "envelope.fill", "envelope", "envelope.open.fill", "envelope.open", "tray.fill", "tray",
            "tray.and.arrow.up.fill", "tray.and.arrow.up", "tray.and.arrow.down.fill", "tray.and.arrow.down",
            "paperplane.fill", "paperplane", "message.fill", "message", "bubble.left.fill", "bubble.left",
            "bubble.right.fill", "bubble.right", "bubble.left.and.bubble.right.fill",
            "bubble.left.and.bubble.right", "phone.fill", "phone", "phone.fill.badge.plus", "phone.badge.plus",
            "phone.down.fill", "phone.down.circle.fill",
            "video.fill", "video", "video.badge.plus", "video.badge.waveform.fill", "video.badge.waveform",
            "airplayvideo", "airplayaudio", "mic.circle.fill", "mic.circle",
            "arrowshape.turn.up.left.fill", "arrowshape.turn.up.left",
            "arrowshape.turn.up.left.2.fill", "arrowshape.turn.up.left.2",
            "arrowshape.turn.up.right.fill", "arrowshape.turn.up.right",
            "bell.badge.fill", "bell.badge", "hand.raised.square.fill", "hand.raised.square",
            "phone.arrow.up.right.fill", "phone.arrow.up.right", "phone.arrow.down.left.fill", "phone.arrow.down.left"
        ]),

        IconSection(title: "People & Account", symbols: [
            "person.fill", "person", "person.circle.fill", "person.circle", "person.badge.plus.fill",
            "person.badge.plus", "person.badge.minus.fill", "person.badge.minus",
            "person.crop.circle.fill", "person.crop.circle", "person.crop.circle.badge.plus.fill",
            "person.crop.circle.badge.plus", "person.crop.circle.badge.minus.fill",
            "person.crop.circle.badge.minus", "person.2.fill", "person.2", "person.3.fill", "person.3",
            "figure.walk", "figure.run", "figure.dance", "hand.raised.fill", "hand.raised",
            "hand.thumbsup.fill", "hand.thumbsup", "hand.thumbsdown.fill", "hand.thumbsdown",
            "face.smiling.fill", "face.smiling", "face.dashed.fill", "face.dashed",
            "person.fill.checkmark", "person.crop.circle.badge.checkmark",
            "person.fill.xmark", "person.crop.circle.badge.xmark",
            "person.text.rectangle.fill", "person.text.rectangle", "person.badge.key.fill", "person.badge.key",
            "person.crop.square.fill", "person.crop.square", "person.crop.rectangle.fill", "person.crop.rectangle",
            "figure.seated.side", "figure.stairs", "figure.disc.sports", "figure.baseball", "figure.tennis",
            "figure.basketball", "figure.soccer", "figure.pool.swim", "figure.golf", "figure.climbing",
            "person.and.background.dotted", "person.wave.2.fill", "person.wave.2"
        ]),

        IconSection(title: "Health & Wellness", symbols: [
            "heart.fill", "heart", "heart.circle.fill", "heart.circle", "heart.text.square.fill",
            "staroflife.fill", "staroflife", "cross.case.fill", "cross.case", "pills.fill", "pills",
            "bandage.fill", "bandage", "lungs.fill", "lungs", "brain.head.profile", "brain",
            "waveform.path.ecg.rectangle.fill", "waveform.path.ecg.rectangle", "drop.fill", "drop",
            "thermometer",
            "stethoscope",
            "bed.double.fill", "bed.double", "figure.walk.circle.fill", "figure.walk.circle",
            "figure.strengthtraining.traditional", "figure.yoga", "figure.cooldown",
            "figure.highintensity.intervaltraining", "figure.socialdance",
            "figure.flexibility", "figure.mind.and.body", "figure.cross.training", "figure.barre",
            "figure.stairs", "allergens.fill", "allergens", "thermometer.snowflake",
            "syringe.fill", "syringe", "medical.thermometer.fill", "medical.thermometer"
        ]),

        IconSection(title: "Weather & Environment", symbols: [
            "sun.max.fill", "sun.max", "moon.fill", "moon", "cloud.fill", "cloud", "cloud.sun.fill",
            "cloud.sun", "cloud.rain.fill", "cloud.rain", "cloud.bolt.fill", "cloud.bolt",
            "cloud.bolt.rain.fill", "cloud.bolt.rain", "cloud.snow.fill", "cloud.snow", "cloud.fog.fill",
            "cloud.fog", "tornado", "hurricane", "wind", "wind.circle.fill", "wind.circle",
            "snowflake", "thermometer.sun.fill", "thermometer.sun", "thermometer.snowflake",
            "tree.fill", "tree", "leaf.fill", "leaf", "flame.fill", "flame",
            "drop.fill", "drop", "water.waves",
            "mountain.2.fill", "mountain.2", "sun.haze.fill", "sun.haze", "moon.haze.fill", "moon.haze",
            "smoke.fill", "smoke", "sparkle", "star.leadinghalf.filled"
        ]),

        IconSection(title: "Location & Navigation", symbols: [
            "map.fill", "map", "mappin", "mappin.and.ellipse",
            "location.fill", "location", "location.circle.fill", "location.circle", "location.north.fill",
            "location.north", "location.north.line.fill", "location.north.line", "road.lanes",
            "road.lanes.curved.right", "road.lanes.curved.left", "car.fill", "car", "car.side",
            "bus.fill", "bus", "tram.fill", "tram", "train.side.front.car", "train.side.middle.car",
            "train.side.rear.car", "airplane", "airplane.departure", "airplane.arrival", "bicycle",
            "figure.walk", "ferry.fill", "ferry", "scooter", "truck.box.fill", "truck.box",
            "shippingbox.fill", "shippingbox", "fuelpump.fill", "fuelpump", "bus.doubledecker.fill",
            "bicycle.circle.fill", "bicycle.circle", "figure.walk.circle.fill", "figure.walk.circle",
            "car.front.waves.up.fill", "car.rear.waves.up.fill", "bolt.car.fill", "bus.doubledecker",
            "point.fill.topleft.down.curvedto.point.fill.bottomright.up",
            "compass.drawing", "parkingsign"
        ]),

        IconSection(title: "Sports & Games", symbols: [
            "gamecontroller.fill", "gamecontroller", "dpad.fill", "dpad", "dice.fill", "dice",
            "sportscourt.fill", "sportscourt", "trophy.fill", "trophy", "medal.fill", "medal",
            "figure.tennis", "figure.baseball", "figure.basketball", "figure.soccer", "figure.pool.swim",
            "figure.disc.sports", "figure.golf", "flag.checkered.2.crossed", "target", "scope",
            "circles.hexagongrid.fill", "circles.hexagongrid", "bell.badge.fill", "bell.badge"
        ]),

        IconSection(title: "Accessibility", symbols: [
            "figure.walk.circle.fill", "figure.walk.circle", "figure.roll", "ear.and.waveform", "ear.fill",
            "hand.raised.fingers.spread.fill", "hand.raised.fingers.spread",
            "character.cursor.ibeam",
            "eye.fill", "eye.slash.fill", "mic.fill", "speaker.wave.3.fill", "square.text.square.fill",
            "square.text.square", "waveform.and.magnifyingglass", "questionmark.bubble.fill",
            "accessibility", "accessibility.fill"
        ]),

        IconSection(title: "Shapes & Geometry", symbols: [
            "circle.fill", "circle", "square.fill", "square", "triangle.fill", "triangle",
            "diamond.fill", "diamond", "octagon.fill", "octagon", "hexagon.fill", "hexagon",
            "capsule.fill", "capsule", "oval.fill", "oval", "cube.fill", "cube", "cylinder.fill", "cylinder",
            "cone.fill", "cone", "pyramid.fill", "pyramid", "gearshape.fill", "gearshape",
            "bell.fill", "bell", "lightbulb.fill", "lightbulb", "star.fill", "star", "heart.fill", "heart",
            "bolt.fill", "bolt", "drop.fill", "drop", "water.waves", "sparkle", "sparkles",
            "circle.grid.2x2.fill", "circle.grid.2x2", "rectangle.grid.2x2.fill", "rectangle.grid.2x2",
            "rectangle.grid.3x2.fill", "rectangle.grid.3x2", "square.on.square.dashed",
            "flowchart.fill", "flowchart", "circle.square.fill", "circle.square"
        ])
    ]

    private var filteredIconSections: [IconSection] {
        if searchText.isEmpty {
            return Self.iconSections
        }
        var filteredSections: [IconSection] = []
        let lowercasedSearchText = searchText.lowercased()
        for section in Self.iconSections {
            let matchingSymbols = section.symbols.filter { $0.lowercased().contains(lowercasedSearchText) }
            if !matchingSymbols.isEmpty {
                filteredSections.append(IconSection(title: section.title, symbols: matchingSymbols))
            }
        }
        return filteredSections
    }

    private let columns = [GridItem(.adaptive(minimum: 50))]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Select Icon")
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()

                Button(action: {
                    withAnimation(.spring()) {
                        isSearchVisible.toggle()
                    }
                }) {
                    Image(systemName: "magnifyingglass")
                        .font(.title3)
                        .foregroundColor(isSearchVisible ? .accentColor : .white)
                        .padding(5)
                }
                .buttonStyle(.plain)

                Button(action: {
                    dismiss()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.gray)
                        .padding(5)
                }
                .buttonStyle(.plain)
            }
            .padding([.horizontal, .top])
            .padding(.bottom, 8)

            if isSearchVisible {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.gray)
                    TextField("Search icons...", text: $searchText)
                        .foregroundColor(.white)
                }
                .padding(8)
                .background(Color.white.opacity(0.1))
                .cornerRadius(10)
                .padding(.horizontal)
                .padding(.bottom, 10)
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if filteredIconSections.isEmpty {
                        Text("No icons found for \"\(searchText)\"")
                            .foregroundColor(.gray)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .center)
                    } else {
                        ForEach(filteredIconSections) { section in
                            Text(section.title)
                                .font(.headline)
                                .fontWeight(.bold)
                                .foregroundColor(.white.opacity(0.8))
                                .padding(.leading, 5)

                            LazyVGrid(columns: columns, spacing: 15) {
                                ForEach(section.symbols, id: \.self) { symbolName in
                                    Button(action: {
                                        onSelect(symbolName)
                                        dismiss()
                                    }) {
                                        Image(systemName: symbolName)
                                            .font(.system(size: 24, weight: .bold))
                                            .frame(width: 50, height: 50)
                                            .background(Color.white.opacity(0.1))
                                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                            .foregroundColor(.white)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
                .padding()
            }
        }
        .frame(width: 350, height: 700)
        .background(Color(red: 0.18, green: 0.18, blue: 0.28))
    }
}

struct WeatherInfoSettingsView: View {
    @Binding var selectedInfo: [WeatherInfoType]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Visible Weather Info")
                .font(.caption.weight(.medium))
                .foregroundColor(.secondary)
                .padding(.top, 8)

            ForEach(WeatherInfoType.selectableCases) { infoType in
                let isSelectedBinding = Binding<Bool>(
                    get: { selectedInfo.contains(infoType) },
                    set: { isSelected in
                        if isSelected {
                            if !selectedInfo.contains(infoType) {
                                selectedInfo.append(infoType)
                            }
                        } else {
                            selectedInfo.removeAll { $0 == infoType }
                        }
                    }
                )

                Toggle(infoType.displayName, isOn: isSelectedBinding)
            }
        }
        .padding(.horizontal)
        .padding(.bottom)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
}

struct BatteryInfoSettingsView: View {
    @Binding var selectedInfo: [BatteryInfoType]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Visible Battery Info")
                .font(.caption.weight(.medium))
                .foregroundColor(.secondary)
                .padding(.top, 8)

            ForEach(BatteryInfoType.allCases) { infoType in
                let isSelectedBinding = Binding<Bool>(
                    get: { selectedInfo.contains(infoType) },
                    set: { isSelected in
                        if isSelected {
                            if !selectedInfo.contains(infoType) {
                                selectedInfo.append(infoType)
                            }
                        } else {
                            selectedInfo.removeAll { $0 == infoType }
                        }
                    }
                )

                Toggle(infoType.displayName, isOn: isSelectedBinding)
            }
        }
        .padding(.horizontal)
        .padding(.bottom)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
}

struct LockScreenSettingsView: View {
    @EnvironmentObject var settings: SettingsModel
    @State private var notchsettingsHaveChanged: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Lock Screen")
                    .font(.largeTitle.bold())
                    .padding(.bottom)

                VStack(alignment: .leading, spacing: 0) {
                    Text("Top Info Widget").font(.headline).padding([.top, .horizontal])

                    ToggleRow(
                        title: "Show Info Widget(s)",
                        description: "Display small, informational widgets below the clock.",
                        isOn: $settings.settings.lockScreenShowInfoWidget
                    )

                    if settings.settings.lockScreenShowInfoWidget {
                        Divider().padding(.leading, 20)

                        ToggleRow(
                            title: "Hide When Inactive",
                            description: "Only show widgets like Music, Calendar, or Focus when they are active.",
                            isOn: $settings.settings.lockScreenHideInactiveInfoWidgets
                        )

                        Divider().padding(.leading, 20)

                        VStack(alignment: .leading, spacing: 12) {
                            Text("Visible Widgets")
                                .font(.caption.weight(.medium))
                                .foregroundColor(.secondary)
                                .padding(.top, 8)

                            ForEach(LockScreenWidgetType.selectableCases) { widgetType in
                                let isSelectedBinding = Binding<Bool>(
                                    get: { settings.settings.lockScreenWidgets.contains(widgetType) },
                                    set: { isSelected in
                                        if isSelected {
                                            if !settings.settings.lockScreenWidgets.contains(widgetType) {
                                                settings.settings.lockScreenWidgets.append(widgetType)
                                            }
                                        } else {
                                            settings.settings.lockScreenWidgets.removeAll { $0 == widgetType }
                                        }
                                    }
                                )
                                Toggle(widgetType.displayName, isOn: isSelectedBinding)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.bottom)

                        if settings.settings.lockScreenWidgets.contains(.weather) {
                            Divider().padding(.horizontal)
                            WeatherInfoSettingsView(selectedInfo: $settings.settings.lockScreenWeatherInfo)
                        }

                        if settings.settings.lockScreenWidgets.contains(.battery) {
                            Divider().padding(.horizontal)
                            BatteryInfoSettingsView(selectedInfo: $settings.settings.lockScreenBatteryInfo)
                        }
                    }
                }
                .modifier(SettingsContainerModifier())
                .animation(.default, value: settings.settings.lockScreenShowInfoWidget)
                .animation(.default, value: settings.settings.lockScreenWidgets.contains(.weather))
                .animation(.default, value: settings.settings.lockScreenWidgets.contains(.battery))

                VStack(alignment: .leading, spacing: 0) {
                    Text("Main Widget(s)").font(.headline).padding([.top, .horizontal])

                    ToggleRow(
                        title: "Show Main Widget(s)",
                        description: "Display larger, interactive widgets in the middle of the screen.",
                        isOn: $settings.settings.lockScreenShowMainWidget
                    )

                    if settings.settings.lockScreenShowMainWidget {
                        Divider().padding(.leading, 20)

                        VStack(alignment: .leading, spacing: 12) {
                            Text("Visible Main Widgets")
                                .font(.caption.weight(.medium))
                                .foregroundColor(.secondary)
                                .padding(.top, 8)

                            ForEach(LockScreenMainWidgetType.selectableCases) { widgetType in
                                let isSelectedBinding = Binding<Bool>(
                                    get: { settings.settings.lockScreenMainWidgets.contains(widgetType) },
                                    set: { isSelected in
                                        if isSelected {
                                            if !settings.settings.lockScreenMainWidgets.contains(widgetType) {
                                                settings.settings.lockScreenMainWidgets.append(widgetType)
                                            }
                                        } else {
                                            settings.settings.lockScreenMainWidgets.removeAll { $0 == widgetType }
                                        }
                                    }
                                )
                                Toggle(widgetType.displayName, isOn: isSelectedBinding)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.bottom)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .modifier(SettingsContainerModifier())
                .animation(.default, value: settings.settings.lockScreenShowMainWidget)

                VStack(alignment: .leading, spacing: 0) {
                    Text("Mini Widgets").font(.headline).padding([.top, .horizontal])

                    ToggleRow(
                        title: "Show Mini Widget(s)",
                        description: "Display compact widgets below the main widget area.",
                        isOn: $settings.settings.lockScreenShowMiniWidgets
                    )

                    if settings.settings.lockScreenShowMiniWidgets {
                        Divider().padding(.leading, 20)

                        VStack(alignment: .leading, spacing: 12) {
                            Text("Visible Mini Widgets")
                                .font(.caption.weight(.medium))
                                .foregroundColor(.secondary)
                                .padding(.top, 8)

                            ForEach(LockScreenMiniWidgetType.selectableCases) { widgetType in
                                let isSelectedBinding = Binding<Bool>(
                                    get: { settings.settings.lockScreenMiniWidgets.contains(widgetType) },
                                    set: { isSelected in
                                        if isSelected {
                                            if !settings.settings.lockScreenMiniWidgets.contains(widgetType) {
                                                settings.settings.lockScreenMiniWidgets.append(widgetType)
                                            }
                                        } else {
                                            settings.settings.lockScreenMiniWidgets.removeAll { $0 == widgetType }
                                        }
                                    }
                                )
                                Toggle(widgetType.displayName, isOn: isSelectedBinding)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.bottom)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .modifier(SettingsContainerModifier())
                .animation(.default, value: settings.settings.lockScreenShowMiniWidgets)

                VStack(alignment: .leading, spacing: 0) {
                    Text("Appearance").font(.headline).padding([.top, .horizontal])

                    ToggleRow(
                        title: "Liquid Glass Effect",
                        description: "Apply a liquid glass effect to the widgets.",
                        isOn: $settings.settings.lockScreenLiquidGlassLook
                    )
                }
                .modifier(SettingsContainerModifier())

                VStack(alignment: .leading, spacing: 0) {
                    Text("Notch Bar").font(.headline).padding([.top, .horizontal])

                    ToggleRow(
                        title: "Show Notch on Lock Screen",
                        description: "Keep the Sapphire notch bar visible at the top of the lock screen.",
                        isOn: $settings.settings.lockScreenShowNotch
                    )

                    Divider().padding(.leading, 20)

                    ToggleRow(
                        title: "Show Lock Screen Live Activity",
                        description: "Display an authentication status activity in the notch on the lock screen.",
                        isOn: $settings.settings.lockScreenLiveActivityEnabled
                    )
                }
                .modifier(SettingsContainerModifier())
            }
            .padding(25)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .onChange(of: settings.settings.lockScreenShowNotch) {notchsettingsHaveChanged = true}
        }
    }
}

struct SnapZonesSettingsView: View {
    @EnvironmentObject var settings: SettingsModel
    @ObservedObject private var appFetcher = SystemAppFetcher.shared

    @State private var layoutToEdit: SnapLayout?
    @State private var planeToEdit: Plane?
    @State private var isShowingAppPicker = false

    @State private var appToConfigureMultiLayout: String?
    @State private var multiLayoutIDsForSheet: [UUID] = []

    private var allLayouts: [SnapLayout] {
        LayoutTemplate.allTemplates + settings.settings.customSnapLayouts
    }

    private var viewModeDescription: String {
        switch settings.settings.snapZoneViewMode {
        case .single:
            return "Show one layout at a time, determined by your default or app-specific settings."
        case .multi:
            return "Show a user-defined list of layouts side-by-side in the widget for quick selection."
        }
    }

    private var isShowingMultiLayoutPicker: Binding<Bool> {
        Binding(
            get: { appToConfigureMultiLayout != nil },
            set: { isShowing in
                if !isShowing {
                    appToConfigureMultiLayout = nil
                }
            }
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 25) {
                Text("Snap Zones & Planes")
                    .font(.system(size: 32, weight: .bold))
                    .padding(.bottom, 5)

                VStack(alignment: .leading, spacing: 0) {
                    ToggleRow(
                        title: "Activate on Drag",
                        description: "Show Snap Zones when dragging near the notch.",
                        isOn: $settings.settings.snapOnWindowDragEnabled
                    )
                }
                .modifier(SettingsContainerModifier())

                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("Global Widget Style").font(.headline)
                        Spacer()
                        Picker("Widget View Style", selection: $settings.settings.snapZoneViewMode) {
                            ForEach(SnapZoneViewMode.allCases) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 150)
                    }.padding()

                    Text(viewModeDescription)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                        .padding(.bottom)

                }.modifier(SettingsContainerModifier())

                if settings.settings.snapZoneViewMode == .single {
                    singleLayoutsManagementSection
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                } else {
                    multiLayoutsManagementSection
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                }

                appSpecificLayoutsSection
                customLayoutsSection
                planesManagementSection
                RequiredPermissionsView(section: .snapZones)
            }
            .padding(25)
            .animation(.easeInOut(duration: 0.2), value: settings.settings.snapZoneViewMode)
        }
        .onAppear(perform: appFetcher.fetchApps)
        .sheet(item: $layoutToEdit) { layout in
            LayoutEditorView(layout: Binding(
                get: { layout },
                set: { updatedLayout in layoutToEdit = updatedLayout }
            ), onSave: saveLayout)
        }
        .sheet(isPresented: isShowingMultiLayoutPicker) {
            if let bundleId = appToConfigureMultiLayout {
                MultiLayoutPickerView(
                    appName: appName(for: bundleId),
                    allLayouts: allLayouts,
                    initialLayoutIDs: multiLayoutIDsForSheet,
                    onSave: { newIDs in
                        modifySettings { $0.appSpecificLayoutConfigurations[bundleId] = .multi(layoutIDs: newIDs) }
                    }
                )
            }
        }
        .sheet(item: $planeToEdit) { plane in
            PlaneEditorView(plane: Binding(
                get: { plane },
                set: { updatedPlane in planeToEdit = updatedPlane }
            ), allLayouts: allLayouts, allApps: appFetcher.apps, onSave: savePlane)
        }
        .popover(isPresented: $isShowingAppPicker, arrowEdge: .bottom) {
            AppPickerView(apps: appFetcher.apps, onSelect: addAppSpecificLayout)
        }
    }

    @ViewBuilder
    private var singleLayoutsManagementSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Global Default Layout").font(.headline)
                Spacer()
                ModernMenuPicker(selection: $settings.settings.defaultSnapLayout, options: allLayouts, titleKeyPath: \.name)
            }.padding(.horizontal, 20).padding(.vertical, 12)
        }.modifier(SettingsContainerModifier())
    }

    @ViewBuilder
    private var multiLayoutsManagementSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Global Multi-View Layouts").font(.headline)
                Spacer()
                Menu {
                    let alreadyAddedIDs = Set(settings.settings.snapZoneLayoutOptions)
                    let availableLayouts = allLayouts.filter { !alreadyAddedIDs.contains($0.id) }

                    if availableLayouts.isEmpty { Text("All layouts added") }
                    else {
                        ForEach(availableLayouts) { layout in
                            Button(layout.name) { addLayoutOption(layout.id) }
                        }
                    }
                } label: {
                    HStack { Image(systemName: "plus"); Text("Add Layout") }
                }
                .buttonStyle(.borderless).tint(.accentColor)
                .disabled(allLayouts.count == settings.settings.snapZoneLayoutOptions.count)

            }.padding([.horizontal, .top]).padding(.bottom, 8)

            Text("Add and reorder the layouts that appear in the Multi-View widget by default.").font(.caption).foregroundColor(.secondary).padding(.horizontal).padding(.bottom)
            Divider()

            if settings.settings.snapZoneLayoutOptions.isEmpty {
                 Text("Click 'Add Layout' to build your global multi-view widget.")
                     .foregroundColor(.secondary).frame(maxWidth: .infinity, minHeight: 60, alignment: .center)
            } else {
                List {
                    ForEach(settings.settings.snapZoneLayoutOptions.indices, id: \.self) { index in
                        let layoutID = settings.settings.snapZoneLayoutOptions[index]
                        if let layout = allLayouts.first(where: { $0.id == layoutID }) {
                            HStack {
                                Image(systemName: "line.3.horizontal").foregroundStyle(.secondary)
                                Text(layout.name)
                                Spacer()
                                Button {
                                    deleteLayoutOption(at: IndexSet(integer: index))
                                } label: {
                                    Image(systemName: "trash")
                                        .foregroundColor(.red)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .onMove(perform: moveLayoutOption)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
                .listStyle(.plain).scrollContentBackground(.hidden)
                .frame(height: CGFloat(settings.settings.snapZoneLayoutOptions.count) * 28)
            }
        }.modifier(SettingsContainerModifier())
    }

    @ViewBuilder
    private var appSpecificLayoutsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("App-Specific Overrides").font(.headline)
                Spacer()
                Button("Add App") { isShowingAppPicker = true }.buttonStyle(.borderless).tint(.accentColor)
            }.padding([.horizontal, .top]).padding(.bottom, 8)
            Text("Force a specific layout mode (Single or Multi) when dragging a particular app.").font(.caption).foregroundColor(.secondary).padding(.horizontal).padding(.bottom)
            Divider()
            if settings.settings.appSpecificLayoutConfigurations.isEmpty {
                 Text("No app-specific overrides configured.").foregroundColor(.secondary).frame(maxWidth: .infinity, minHeight: 60, alignment: .center)
            } else {
                ForEach(settings.settings.appSpecificLayoutConfigurations.keys.sorted(), id: \.self) { bundleId in
                    AppSpecificLayoutConfigRow(
                        appIcon: app(for: bundleId)?.icon,
                        appName: appName(for: bundleId),
                        allLayouts: allLayouts,
                        configuration: bindingForAppConfig(bundleId),
                        onEditMulti: {
                            if case .multi(let layoutIDs) = settings.settings.appSpecificLayoutConfigurations[bundleId] {
                                self.multiLayoutIDsForSheet = layoutIDs
                            } else {
                                self.multiLayoutIDsForSheet = []
                            }
                            self.appToConfigureMultiLayout = bundleId
                        },
                        onDelete: {
                            modifySettings { $0.appSpecificLayoutConfigurations.removeValue(forKey: bundleId) }
                        }
                    )
                    Divider().padding(.leading, 60)
                }
            }
        }.modifier(SettingsContainerModifier())
    }

    @ViewBuilder
    private var customLayoutsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("My Custom Layouts").font(.headline)
                Spacer()
                Button("New Layout") { layoutToEdit = SnapLayout(name: "New Custom Layout", zones: []) }.buttonStyle(.borderless).tint(.accentColor)
            }.padding()
            Divider()
            if settings.settings.customSnapLayouts.isEmpty {
                Text("No custom layouts created yet.").foregroundColor(.secondary).frame(maxWidth: .infinity, minHeight: 60, alignment: .center)
            } else {
                ForEach(settings.settings.customSnapLayouts) { layout in
                    CustomLayoutRow(layout: layout, onEdit: { layoutToEdit = layout }, onDelete: { deleteLayout(layout) })
                    Divider().padding(.leading, 20)
                }
            }
        }.modifier(SettingsContainerModifier())
    }

    @ViewBuilder
    private var planesManagementSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Planes").font(.title2.bold())
                Spacer()
                Button("New Plane") {
                    guard let firstLayout = allLayouts.first else { return }
                    planeToEdit = Plane(name: "New Plane", layoutID: firstLayout.id)
                }.buttonStyle(.borderless).tint(.accentColor)
            }.padding([.horizontal, .top]).padding(.bottom, 8)
            Text("Trigger layouts with keyboard shortcuts to arrange windows instantly.").font(.caption).foregroundColor(.secondary).padding(.horizontal).padding(.bottom)
            Divider()
            if settings.settings.planes.isEmpty {
                Text("No Planes created yet.").foregroundColor(.secondary).frame(maxWidth: .infinity, minHeight: 60, alignment: .center)
            } else {
                ForEach($settings.settings.planes) { $plane in
                    PlaneRow(plane: $plane, onEdit: { planeToEdit = $plane.wrappedValue }, onDelete: { deletePlane(withId: $plane.id) })
                    Divider().padding(.leading, 20)
                }
            }
        }.modifier(SettingsContainerModifier())
    }

    // MARK: - Helper Functions
    private func modifySettings(_ modification: (inout Settings) -> Void) {
        var newSettings = settings.settings
        modification(&newSettings)
        settings.settings = newSettings
    }

    private func saveLayout(_ savedLayout: SnapLayout) { modifySettings { settings in if let index = settings.customSnapLayouts.firstIndex(where: { $0.id == savedLayout.id }) { settings.customSnapLayouts[index] = savedLayout } else { settings.customSnapLayouts.append(savedLayout) } } }
    private func savePlane(_ savedPlane: Plane) { modifySettings { settings in if let index = settings.planes.firstIndex(where: { $0.id == savedPlane.id }) { settings.planes[index] = savedPlane } else { settings.planes.append(savedPlane) } } }

    private func deleteLayout(_ layoutToDelete: SnapLayout) {
        modifySettings { settings in
            settings.customSnapLayouts.removeAll { $0.id == layoutToDelete.id }
            if settings.defaultSnapLayout.id == layoutToDelete.id {
                settings.defaultSnapLayout = LayoutTemplate.columns
            }
            for (bundleID, config) in settings.appSpecificLayoutConfigurations {
                switch config {
                case .single(let layoutID) where layoutID == layoutToDelete.id:
                    settings.appSpecificLayoutConfigurations.removeValue(forKey: bundleID)
                case .multi(var layoutIDs):
                    layoutIDs.removeAll { $0 == layoutToDelete.id }
                    settings.appSpecificLayoutConfigurations[bundleID] = .multi(layoutIDs: layoutIDs)
                default:
                    break
                }
            }
            settings.planes.removeAll { $0.layoutID == layoutToDelete.id }
        }
    }

    private func deletePlane(withId planeId: UUID) { modifySettings { settings in settings.planes.removeAll { $0.id == planeId } } }

    private func addAppSpecificLayout(_ appBundleId: String) {
        modifySettings { settings in
            if settings.appSpecificLayoutConfigurations[appBundleId] == nil {
                let firstLayoutID = allLayouts.first?.id ?? LayoutTemplate.columns.id
                settings.appSpecificLayoutConfigurations[appBundleId] = .single(layoutID: firstLayoutID)
            }
        }
        isShowingAppPicker = false
    }

    private func app(for bundleId: String) -> SystemApp? { appFetcher.apps.first { $0.id == bundleId } }
    private func appName(for bundleId: String) -> String { app(for: bundleId)?.name ?? bundleId }

    private func bindingForAppConfig(_ bundleId: String) -> Binding<AppSnapLayoutConfiguration> {
        Binding(
            get: { settings.settings.appSpecificLayoutConfigurations[bundleId] ?? .useGlobalDefault },
            set: { newConfig in modifySettings { $0.appSpecificLayoutConfigurations[bundleId] = newConfig } }
        )
    }

    private func addLayoutOption(_ layoutID: UUID) { modifySettings { $0.snapZoneLayoutOptions.append(layoutID) } }
    private func moveLayoutOption(from source: IndexSet, to destination: Int) { modifySettings { $0.snapZoneLayoutOptions.move(fromOffsets: source, toOffset: destination) } }
    private func deleteLayoutOption(at offsets: IndexSet) { modifySettings { $0.snapZoneLayoutOptions.remove(atOffsets: offsets) } }
}

fileprivate struct AppSpecificLayoutConfigRow: View {
    let appIcon: NSImage?
    let appName: String
    let allLayouts: [SnapLayout]
    @Binding var configuration: AppSnapLayoutConfiguration
    let onEditMulti: () -> Void
    let onDelete: () -> Void

    private enum ConfigType: Int, Identifiable {
        case useDefault = 0, single, multi
        var id: Int { self.rawValue }
    }

    private var configTypeBinding: Binding<ConfigType> {
        Binding(
            get: {
                switch configuration {
                case .useGlobalDefault: return .single
                case .single: return .single
                case .multi: return .multi
                }
            },
            set: { newType in
                switch newType {
                case .single:
                    if case .single = configuration { return }
                    let firstLayoutID = allLayouts.first?.id ?? LayoutTemplate.columns.id
                    configuration = .single(layoutID: firstLayoutID)
                case .multi:
                    if case .multi = configuration { return }
                    configuration = .multi(layoutIDs: [])
                case .useDefault:
                    break
                }
            }
        )
    }

    var body: some View {
        HStack(spacing: 12) {
            if let icon = appIcon {
                Image(nsImage: icon).resizable().frame(width: 28, height: 28).clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                Image(systemName: "app.dashed").font(.title2).frame(width: 28)
            }

            Text(appName).lineLimit(1)
            Spacer()

            Picker("Mode", selection: configTypeBinding) {
                Text("Single").tag(ConfigType.single)
                Text("Multi").tag(ConfigType.multi)
            }
            .labelsHidden().frame(width: 180)

            switch configuration {
            case .single(let layoutID):
                let binding = Binding(
                    get: { layoutID },
                    set: { newID in configuration = .single(layoutID: newID) }
                )
                ModernMenuPickerWithID(selection: binding, options: allLayouts, titleKeyPath: \.name)
                    .frame(width: 150)
            case .multi:
                Button("Edit", action: onEditMulti).buttonStyle(.borderless).tint(.accentColor)
            case .useGlobalDefault:
                EmptyView().frame(width: 150, height: 1)
            }

            Button(action: onDelete) {
                Image(systemName: "xmark.circle.fill").font(.body).foregroundColor(.secondary.opacity(0.7))
            }
            .buttonStyle(.plain).padding(.leading, 8)
        }
        .padding(.vertical, 8).padding(.horizontal, 20)
    }
}

fileprivate struct MultiLayoutPickerView: View {
    @Environment(\.dismiss) var dismiss
    let appName: String
    let allLayouts: [SnapLayout]
    let onSave: ([UUID]) -> Void

    @State private var editedLayoutIDs: [UUID]

    init(appName: String, allLayouts: [SnapLayout], initialLayoutIDs: [UUID], onSave: @escaping ([UUID]) -> Void) {
        self.appName = appName
        self.allLayouts = allLayouts
        self.onSave = onSave
        self._editedLayoutIDs = State(initialValue: initialLayoutIDs)
    }

    private var availableLayouts: [SnapLayout] {
        allLayouts.filter { !editedLayoutIDs.contains($0.id) }
    }

    private func layout(for id: UUID) -> SnapLayout? {
        allLayouts.first { $0.id == id }
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("Edit Multi-View for \(appName)").font(.title2.bold()).padding()
            Divider()

            HSplitView {
                VStack(alignment: .leading) {
                    Text("Available Layouts").font(.headline).padding([.top, .horizontal])
                    List(availableLayouts) { layout in
                        Button(action: { editedLayoutIDs.append(layout.id) }) {
                            HStack { Text(layout.name); Spacer(); Image(systemName: "plus.circle.fill").foregroundColor(.green) }
                        }.buttonStyle(.plain)
                    }.listStyle(.sidebar)
                }
                .frame(minWidth: 220)

                VStack(alignment: .leading) {
                    Text("Selected Layouts (Drag to Reorder)").font(.headline).padding([.top, .horizontal])
                    List {
                        ForEach(editedLayoutIDs.indices, id: \.self) { index in
                            if let layout = layout(for: editedLayoutIDs[index]) {
                                HStack {
                                    Text(layout.name)
                                    Spacer()
                                    Button {
                                        delete(at: IndexSet(integer: index))
                                    } label: {
                                        Image(systemName: "minus.circle.fill")
                                            .foregroundColor(.red)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .onMove(perform: move)
                    }.listStyle(.sidebar)
                }
                .frame(minWidth: 220)
            }

            Divider()
            HStack {
                Button("Cancel", role: .cancel) { dismiss() }
                Spacer()
                Button("Save") {
                    onSave(editedLayoutIDs)
                    dismiss()
                }.buttonStyle(.borderedProminent)
            }.padding()
        }
        .frame(width: 550, height: 450)
    }

    private func move(from source: IndexSet, to destination: Int) {
        editedLayoutIDs.move(fromOffsets: source, toOffset: destination)
    }

    private func delete(at offsets: IndexSet) {
        editedLayoutIDs.remove(atOffsets: offsets)
    }
}

fileprivate struct ModernMenuPicker<T: Identifiable & Hashable>: View {
    @Binding var selection: T
    let options: [T]
    let titleKeyPath: KeyPath<T, String>

    private var selectedOptionName: String {
        return options.first { $0.id == selection.id }?[keyPath: titleKeyPath] ?? "Select"
    }

    var body: some View {
        Menu {
            ForEach(options) { option in
                Button(option[keyPath: titleKeyPath]) {
                    selection = option
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(selectedOptionName)
                Image(systemName: "chevron.down").font(.caption.bold())
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Color.white.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .foregroundColor(.primary)
        }
        .buttonStyle(.plain)
    }
}

fileprivate struct CustomLayoutRow: View {
    let layout: SnapLayout
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack {
            Image(systemName: "rectangle.3.group")
                .font(.title2)
                .frame(width: 30)
                .foregroundColor(.accentColor)
            Text(layout.name).font(.headline)
            Spacer()
            Button(action: onEdit) {
                Image(systemName: "pencil")
            }
            .buttonStyle(.plain)
            .tint(.secondary)

            Button(action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
            .tint(.red)
            .padding(.leading, 8)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}

fileprivate struct AppSpecificLayoutRow: View {
    let appIcon: NSImage?
    let appName: String
    @Binding var selection: UUID
    let options: [SnapLayout]
    let defaultID: UUID
    let onDelete: () -> Void

    var body: some View {
        HStack {
            if let icon = appIcon {
                Image(nsImage: icon)
                    .resizable().frame(width: 28, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                Image(systemName: "app.dashed")
                    .font(.title2).frame(width: 28)
            }

            Text(appName).lineLimit(1)
            Spacer()
            ModernMenuPickerWithID(
                selection: $selection,
                options: options,
                titleKeyPath: \.name,
                defaultID: defaultID
            )

            Button(action: onDelete) {
                Image(systemName: "xmark.circle.fill")
                    .font(.body)
                    .foregroundColor(.secondary.opacity(0.7))
            }
            .buttonStyle(.plain)
            .padding(.leading, 8)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 20)
    }
}

fileprivate struct ModernMenuPickerWithID<T: Identifiable & Hashable>: View where T.ID == UUID {
    @Binding var selection: T.ID
    let options: [T]
    let titleKeyPath: KeyPath<T, String>
    var defaultID: T.ID? = nil
    var defaultTitle: String = "Default"

    private var selectedOptionName: String {
        if let defaultID = defaultID, selection == defaultID {
            return defaultTitle
        }
        return options.first { $0.id == selection }?[keyPath: titleKeyPath] ?? "Select"
    }

    var body: some View {
        Menu {
            if let defaultID = defaultID {
                Button(defaultTitle) { selection = defaultID }
                Divider()
            }
            ForEach(options) { option in
                Button(option[keyPath: titleKeyPath]) { selection = option.id }
            }
        } label: {
            HStack(spacing: 4) {
                Text(selectedOptionName)
                Image(systemName: "chevron.down").font(.caption.bold())
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Color.white.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .foregroundColor(.primary)
        }
        .buttonStyle(.plain)
    }
}

fileprivate struct PlaneRow: View {
    @Binding var plane: Plane
    let onEdit: () -> Void
    let onDelete: () -> Void

    private var shortcutDescription: String {
        guard let shortcut = plane.shortcut else { return "No shortcut set" }
        return "\(KeyboardShortcutHelper.description(for: shortcut.modifiers)) \(shortcut.key)"
    }

    var body: some View {
        HStack {
            Image(systemName: "keyboard")
                .font(.title2)
                .frame(width: 30)
                .foregroundColor(.accentColor)
                .onTapGesture(perform: onEdit)

            VStack(alignment: .leading) {
                Text(plane.name).font(.headline)
                Text(shortcutDescription)
                    .font(.caption).foregroundColor(.secondary)
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onEdit)

            Spacer()

            Button(action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
            .tint(.red)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}

fileprivate struct AppPickerView: View {
    let apps: [SystemApp]
    let onSelect: (String) -> Void
    @State private var searchText = ""

    private var filteredApps: [SystemApp] {
        if searchText.isEmpty {
            return apps
        }
        return apps.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField("Search Apps", text: $searchText)
                .textFieldStyle(.plain)
                .padding()
                .background(Color.black.opacity(0.1))

            List(filteredApps) { app in
                Button(action: { onSelect(app.id) }) {
                    HStack {
                        Image(nsImage: app.icon)
                            .resizable().frame(width: 24, height: 24)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                        Text(app.name)
                    }
                }
                .buttonStyle(.plain)
                .listRowSeparator(.hidden)
            }
            .listStyle(.plain)
        }
        .frame(width: 300, height: 400)
        .background(.ultraThinMaterial)
    }
}

struct NotificationsSettingsView: View {
    @ObservedObject private var appFetcher = SystemAppFetcher.shared
    @EnvironmentObject var settings: SettingsModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Notifications")
                    .font(.largeTitle.bold())
                    .padding(.bottom)

                InfoContainer(text: "All notifications and focus features are in development.", iconName: "info.circle.fill", color: .yellow)

                VStack(spacing: 0) {
                    HStack {
                        Text("Enable Notifications")
                            .font(.system(size: 14, weight: .medium))
                        Spacer()
                        Toggle("", isOn: $settings.settings.masterNotificationsEnabled)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .animation(.default, value: settings.settings.masterNotificationsEnabled)
                    }
                    .padding(EdgeInsets(top: 12, leading: 20, bottom: 12, trailing: 20))
                }
                .modifier(SettingsContainerModifier())

                VStack(spacing: 20) {

                    VStack(alignment: .leading, spacing: 0) {
                        Text("Verification Codes")
                            .font(.headline)
                            .padding([.top, .horizontal])

                        ToggleRow(
                            title: "Only show notifications with verification codes",
                            description: "Filter notifications to only display when a code (OTP) is detected.",
                            isOn: $settings.settings.onlyShowVerificationCodeNotifications
                        )

                        Divider().padding(.leading, 20)

                        ToggleRow(
                            title: "Show copy button for detected codes",
                            description: "Add a quick action to copy the code from supported notifications.",
                            isOn: $settings.settings.showCopyButtonForVerificationCodes
                        )
                    }
                    .modifier(SettingsContainerModifier())
                    .disabled(!settings.settings.masterNotificationsEnabled)
                    .opacity(settings.settings.masterNotificationsEnabled ? 1.0 : 0.5)
                    .animation(.easeInOut, value: settings.settings.masterNotificationsEnabled)

                    VStack(spacing: 0) {
                        ForEach(NotificationSource.allCases) { source in
                            NotificationToggleRowView(source: source)
                            if source != NotificationSource.allCases.last {
                                Rectangle()
                                    .fill(Color.white.opacity(0.2))
                                    .frame(height: 1)
                                    .padding(.leading, 60)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("System Notifications")
                                .font(.system(size: 14, weight: .medium))
                            Spacer()
                            Toggle("", isOn: $settings.settings.systemNotificationsEnabled)
                                .labelsHidden()
                                .toggleStyle(.switch)
                                .animation(.default, value: settings.settings.systemNotificationsEnabled)
                        }
                        .padding(EdgeInsets(top: 12, leading: 20, bottom: 12, trailing: 20))

                        Rectangle().fill(Color.white.opacity(0.2)).frame(height: 1).padding(.leading, 60)

                        Text("Allow Notifications From:")
                            .font(.headline)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .disabled(!settings.settings.systemNotificationsEnabled)
                            .opacity(settings.settings.systemNotificationsEnabled ? 1.0 : 0.5)

                        ScrollView {
                            VStack(spacing: 0) {
                                ForEach(appFetcher.apps) { app in
                                    SystemAppRowView(app: app, isEnabled: binding(for: app))
                                    if app.id != appFetcher.apps.last?.id {
                                        Rectangle()
                                            .fill(Color.white.opacity(0.2))
                                            .frame(height: 1)
                                            .padding(.leading, 50)
                                    }
                                }
                            }
                        }
                        .frame(maxHeight: 360)
                        .disabled(!settings.settings.systemNotificationsEnabled)
                        .opacity(settings.settings.systemNotificationsEnabled ? 1.0 : 0.5)
                    }
                }
                .modifier(SettingsContainerModifier())
                .disabled(!settings.settings.masterNotificationsEnabled)
                .opacity(settings.settings.masterNotificationsEnabled ? 1.0 : 0.5)
                .animation(.easeInOut, value: settings.settings.masterNotificationsEnabled)

                RequiredPermissionsView(section: .notifications)
            }
            .padding(25)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .onAppear {
                appFetcher.fetchApps()
            }
        }
    }

    private func binding(for app: SystemApp) -> Binding<Bool> {
        return .init(
            get: { settings.settings.appNotificationStates[app.id, default: true] },
            set: { settings.settings.appNotificationStates[app.id] = $0 }
        )
    }
}

struct ProximityUnlockSettingsView: View {
    @EnvironmentObject var settings: SettingsModel
    @ObservedObject private var authManager = AuthenticationManager.shared

    @State private var showPasswordPrompt = false
    @State private var showUnnamedDevices = false
    @State private var isFindingByDistance = false
    @State private var isCalibratingRSSI = false

    private let deviceRowHeight: CGFloat = 38
    private let maxDeviceListHeight: CGFloat = 228

    private var isBluetoothEnabled: Binding<Bool> {
        Binding<Bool>(
            get: { settings.settings.bluetoothUnlockEnabled },
            set: { newValue in
                if newValue {
                    if !authManager.isPasswordSet { showPasswordPrompt = true }
                    else { settings.settings.bluetoothUnlockEnabled = true }
                } else {
                    settings.settings.bluetoothUnlockEnabled = false
                }
            }
        )
    }

    private var isFaceIDEnabled: Binding<Bool> {
        Binding<Bool>(
            get: { settings.settings.faceIDUnlockEnabled },
            set: { newValue in
                if newValue {
                    if !authManager.isPasswordSet {
                        showPasswordPrompt = true
                    } else {
                        settings.settings.faceIDUnlockEnabled = true
                    }
                } else {
                    settings.settings.faceIDUnlockEnabled = false
                }
            }
        )
    }

    private var selectedDevice: Device? {
        guard let selectedIDString = authManager.selectedDeviceID,
              let selectedID = UUID(uuidString: selectedIDString) else { return nil }
        return authManager.scannedDevices.first { $0.id == selectedID } ?? authManager.ble.devices[selectedID]
    }

    private var filteredScannedDevices: [Device] {
        return showUnnamedDevices ? authManager.scannedDevices : authManager.scannedDevices.filter { $0.displayName != "Unnamed Device" }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                InfoContainer(text: "WARNING: All these features are in development and may not work as expected. They might cause unexpected unlocks on your mac. Use at your own risk.", iconName: "exclamationmark.triangle.fill", color: .red)
                if settings.settings.faceIDUnlockEnabled {
                    InfoContainer(text: "Enabling face ID will increase the app's ram usage.", iconName: "info.circle", color: .yellow)
                }
                authenticationSection
                faceIDSection
                bluetoothUnlockSection
                actionsSection
            }
            .padding(25)
        }
        .sheet(isPresented: $showPasswordPrompt) {
            PasswordPromptView(isPresented: $showPasswordPrompt) { password in
                if authManager.verifyAndSavePassword(password) {
                    showPasswordPrompt = false
                }
            }
        }
        .sheet(item: $authManager.faceRegistrationController, onDismiss: {
            authManager.completeFaceRegistration()
        }) { controller in
            FaceIDRegistrationView(
                cameraController: controller,
                profileName: authManager.profileNameToRegister
            )
        }
        .sheet(isPresented: $isFindingByDistance) {
            FindDeviceByDistanceWizard()
        }
        .sheet(isPresented: $isCalibratingRSSI) {
            CalibrateRSSIView().environmentObject(settings)
        }
    }

    private var header: some View {
        VStack(alignment: .leading) {
            Text("Proximity & Face Unlock").font(.largeTitle.bold())
            HStack {
                Button("Lock Screen Now") { authManager.manualLock() }
                    .disabled(!settings.settings.bluetoothUnlockEnabled && !settings.settings.faceIDUnlockEnabled)
                Spacer()
                Text(authManager.status).font(.caption).foregroundColor(.secondary)
            }.padding(.top, 2)
        }
    }

    @ViewBuilder
    private var authenticationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Authentication").font(.headline).padding([.horizontal, .top])
            if authManager.isPasswordSet {
                HStack {
                    Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                    Text("Your Mac's password is securely stored in the Keychain.")
                    Spacer()
                    Button("Change") { showPasswordPrompt = true }
                    Button("Remove", role: .destructive) {
                        authManager.removePassword()
                        settings.settings.bluetoothUnlockEnabled = false
                        settings.settings.faceIDUnlockEnabled = false
                    }
                }.padding([.horizontal, .bottom])
            } else {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.yellow)
                    Text("To enable Face ID or Bluetooth Unlock, you must first provide your Mac's login password.")
                    Spacer()
                    Button("Set Password") { showPasswordPrompt = true }
                }.padding([.horizontal, .bottom])
            }
        }.modifier(SettingsContainerModifier())
    }

    @ViewBuilder
    private var faceIDSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            ToggleRow(title: "Enable Face ID Unlock", description: "Unlock your Mac using facial recognition when you wake the screen.", isOn: isFaceIDEnabled)
                .disabled(!authManager.isPasswordSet)

            if settings.settings.faceIDUnlockEnabled {
                Divider().padding(.leading, 20)

                let registeredFaces = authManager.registeredFaceProfiles
                if registeredFaces.isEmpty {
                    Text("No faces registered. Add a face to begin using Face ID.")
                        .font(.caption).foregroundColor(.secondary).padding()
                } else {
                    ForEach(registeredFaces, id: \.self) { profileName in
                        HStack {
                            Image(systemName: "faceid").font(.title2).foregroundColor(.accentColor)
                            Text(profileName)
                            Spacer()
                            Button("Re-Register") {
                                authManager.beginFaceRegistration(profileName: profileName)
                            }
                            Button("Delete", role: .destructive) {
                                authManager.deleteFaceProfile(name: profileName)
                            }
                        }.padding()
                    }
                }

                if registeredFaces.count < 2 {
                    HStack {
                        Spacer()
                        Button(action: {
                            let profileName = registeredFaces.isEmpty ? "Primary Face" : "Secondary Face"
                            authManager.beginFaceRegistration(profileName: profileName)
                        }) { Label("Add Face", systemImage: "plus.circle.fill") }
                        .buttonStyle(.borderedProminent)
                        Spacer()
                    }.padding(.bottom)
                }
            }
        }
        .modifier(SettingsContainerModifier())
        .opacity(authManager.isPasswordSet ? 1.0 : 0.6)
    }

    @ViewBuilder
    private var bluetoothUnlockSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            ToggleRow(title: "Enable Bluetooth Unlock", description: "Automatically lock and unlock your Mac using a trusted Bluetooth device.", isOn: isBluetoothEnabled)
                .disabled(!authManager.isPasswordSet)
            Group {
                if settings.settings.bluetoothUnlockEnabled {
                    Divider().padding(.leading, 20)
                    deviceSelectionSection
                    Divider().padding(.horizontal)
                    sensitivitySection
                    Divider().padding(.horizontal)
                    advancedSection
                }
            }.transition(.opacity.combined(with: .move(edge: .top)))
        }
        .modifier(SettingsContainerModifier())
        .opacity(authManager.isPasswordSet ? 1.0 : 0.6)
        .animation(.default, value: settings.settings.bluetoothUnlockEnabled)
    }

    @ViewBuilder
    private var deviceSelectionSection: some View {
        let listHeight = min(maxDeviceListHeight, CGFloat(filteredScannedDevices.count) * deviceRowHeight)
        VStack(alignment: .leading, spacing: 10) {
            Text("Trusted Device").font(.subheadline).bold().padding(.horizontal)
            if let device = selectedDevice {
                DeviceRowView(device: device, isSelected: true) {}.padding(.horizontal)
                HStack {
                    pairingStatusView
                    Spacer()
                    Button("Calibrate Range") { isCalibratingRSSI = true }
                    Button("Forget Device", role: .destructive) { authManager.forgetDevice() }
                }.padding(.horizontal)
            } else {
                VStack(spacing: 12) {
                    HStack {
                        Button(authManager.isScanning ? "Stop Scanning" : "Scan for Devices") {
                            if authManager.isScanning { authManager.stopScan() } else { authManager.startScan(includeUnnamed: showUnnamedDevices) }
                        }
                        if authManager.isScanning { ProgressView().scaleEffect(0.8).padding(.leading) }
                    }
                    Toggle(isOn: $showUnnamedDevices) { Text("Show unnamed devices") }
                        .onChange(of: showUnnamedDevices) { _, newValue in authManager.updateScanFilter(includeUnnamed: newValue) }
                    if showUnnamedDevices && authManager.isScanning {
                        Button("Find by Distance...") { isFindingByDistance = true }.font(.caption).padding(.top, 5).transition(.opacity)
                    }
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            if authManager.scannedDevices.isEmpty && authManager.isScanning {
                                Text("Scanning...").font(.caption).foregroundColor(.secondary).frame(minHeight: 80)
                            } else if filteredScannedDevices.isEmpty {
                                 Text(showUnnamedDevices ? "No devices found. Ensure device is nearby and discoverable." : "No named devices found. Try enabling 'Show unnamed devices'.")
                                     .font(.caption).foregroundColor(.secondary).frame(minHeight: 80).padding(.horizontal).multilineTextAlignment(.center)
                            } else {
                                ForEach(filteredScannedDevices) { device in
                                    DeviceRowView(device: device) { authManager.selectDevice(uuid: device.id) }
                                    if device.id != filteredScannedDevices.last?.id { Divider().padding(.leading, 50) }
                                }
                            }
                        }
                    }
                    .frame(height: listHeight)
                    .background(Color.black.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .animation(.spring(), value: listHeight)
                }.padding(.horizontal).animation(.default, value: showUnnamedDevices)
            }
        }.padding(.vertical)
    }

    @ViewBuilder
    private var sensitivitySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Sensitivity").font(.subheadline).bold()
                if authManager.selectedDeviceID != nil {
                    Spacer()
                    let rssiString = authManager.lastRSSI.map { "\($0) dBm" } ?? "N/A"
                    Text("Current Signal: \(rssiString)").font(.caption).foregroundColor(.secondary)
                }
            }.padding(.horizontal)
            VStack(spacing: 0) {
                CustomSliderRowView(label: "Unlock RSSI", value: Binding(get: { Double(settings.settings.bluetoothUnlockUnlockRSSI) }, set: { settings.settings.bluetoothUnlockUnlockRSSI = Int($0) }), range: -100...0, specifier: "%.0f dBm")
                Divider().padding(.leading, 20)
                CustomSliderRowView(label: "Lock RSSI", value: Binding(get: { Double(settings.settings.bluetoothUnlockLockRSSI) }, set: { settings.settings.bluetoothUnlockLockRSSI = Int($0) }), range: -100...0, specifier: "%.0f dBm")
            }.padding(.top, 5)
        }.padding(.vertical)
    }

    @ViewBuilder
    private var advancedSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Advanced").font(.subheadline).bold().padding(.horizontal)
            CustomSliderRowView(label: "Delay to Lock", value: $settings.settings.bluetoothUnlockTimeout, range: 1...60, specifier: "%.0f sec")
            Divider().padding(.leading, 20)
            CustomSliderRowView(label: "No-Signal Timeout", value: $settings.settings.bluetoothUnlockNoSignalTimeout, range: 10...300, specifier: "%.0f sec")
            Divider().padding(.leading, 20)
            ToggleRow(title: "Passive Mode", description: "Uses less energy but may be slightly slower to react.", isOn: $settings.settings.bluetoothUnlockPassiveMode)
            Divider().padding(.leading, 20)
            CustomSliderRowView(label: "Minimum Scan RSSI", value: Binding(get: { Double(settings.settings.bluetoothUnlockMinScanRSSI) }, set: { settings.settings.bluetoothUnlockMinScanRSSI = Int($0) }), range: -100 ... -30, specifier: "%.0f dBm")
        }.padding(.vertical)
    }

    @ViewBuilder
    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Lock & Unlock Actions").font(.headline).padding([.top, .horizontal])
            ToggleRow(title: "Wake on Proximity", description: "Wake the screen when your device comes into range.", isOn: $settings.settings.bluetoothUnlockWakeOnProximity)
            Divider().padding(.leading, 20)
            ToggleRow(title: "Wake without Unlocking", description: "Only wake the screen, do not enter the password.", isOn: $settings.settings.bluetoothUnlockWakeWithoutUnlocking)
            Divider().padding(.leading, 20)
            ToggleRow(title: "Pause \"Now Playing\" while Locked", description: "Automatically pauses music or videos when the screen locks.", isOn: $settings.settings.bluetoothUnlockPauseMusicOnLock)
            Divider().padding(.leading, 20)
            ToggleRow(title: "Use Screensaver to Lock", description: "Starts the screensaver instead of showing the lock screen.", isOn: $settings.settings.bluetoothUnlockUseScreensaver)
            Divider().padding(.leading, 20)
            ToggleRow(title: "Turn Off Screen on Lock", description: "Puts the display to sleep when locking.", isOn: $settings.settings.bluetoothUnlockTurnOffScreenOnLock)
        }.modifier(SettingsContainerModifier())
    }

    @ViewBuilder
    private var pairingStatusView: some View {
        HStack(spacing: 4) {
            switch authManager.monitoredPeripheralState {
            case .connected: Image(systemName: "checkmark.shield.fill").foregroundColor(.green); Text("Paired & Monitoring")
            case .connecting: ProgressView().scaleEffect(0.5); Text("Connecting...")
            case .disconnecting: Image(systemName: "xmark.shield.fill").foregroundColor(.gray); Text("Disconnecting...")
            case .disconnected: Image(systemName: "xmark.shield.fill").foregroundColor(.red); Text("Out of Range")
            @unknown default: Image(systemName: "questionmark.circle.fill").foregroundColor(.gray); Text("Unknown State")
            }
        }
        .font(.caption)
        .foregroundColor(.secondary)
    }
}

fileprivate struct DeviceRowView: View {
    let device: Device
    var isSelected: Bool = false
    let action: () -> Void

    private var truncatedUUID: String {
        let fullUUID = device.id.uuidString
        return "\(fullUUID.prefix(8))...\(fullUUID.suffix(4))"
    }

    private func iconForDevice() -> String {
        if let name = device.peripheral?.name, let icon = IconMapper.icon(forName: name) {
            return icon
        }
        return "wave.3.right.circle"
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: iconForDevice())
                    .font(.system(size: 20))
                    .foregroundColor(isSelected ? .accentColor : .secondary)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 1) {
                    Text(device.displayName)
                        .fontWeight(isSelected ? .semibold : .medium)
                        .foregroundColor(isSelected ? .accentColor : .primary)
                        .lineLimit(1)

                    Text(truncatedUUID)
                        .font(.caption2.monospaced())
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Text("\(device.rssi) dBm")
                    .font(.caption.monospaced())
                    .foregroundColor(isSelected ? .accentColor : .secondary)
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
            .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        }
        .buttonStyle(.plain)
    }
}

fileprivate struct FindDeviceByDistanceWizard: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject private var authManager = AuthenticationManager.shared

    @State private var wizardStep = 1
    @State private var closeReadings: [UUID: Int] = [:]
    @State private var countdown = 30
    @State private var timer: Timer?
    @State private var results: [DetectionResult] = []

    struct DetectionResult: Identifiable {
        let id: UUID
        let device: Device
        let score: Double
        let label: String
    }

    var body: some View {
        VStack(spacing: 20) {
            Text("Find Device by Distance").font(.largeTitle.bold())

            switch wizardStep {
            case 1: step1
            case 2: step2
            case 3: step3
            default: Text("An error occurred.")
            }
        }
        .frame(width: 450, height: 400)
        .padding()
        .onAppear { authManager.startScan(includeUnnamed: true) }
        .onDisappear {
            timer?.invalidate()
            authManager.stopScan()
        }
    }

    @ViewBuilder
    private var step1: some View {
        Image(systemName: "arrow.down.to.line.compact").font(.system(size: 40)).foregroundColor(.accentColor)
        Text("Step 1: Bring Device Close").font(.title2)
        Text("Bring your desired device as close as possible to your Mac, then press Next.").multilineTextAlignment(.center).foregroundColor(.secondary)

        let strongestDevice = authManager.scannedDevices.max(by: { $0.rssi < $1.rssi })
        Text("Strongest Signal: \(strongestDevice?.displayName ?? "None") at \(strongestDevice?.rssi ?? -100) dBm")
            .font(.body.bold()).padding()

        Button("Next") {
            self.closeReadings = Dictionary(uniqueKeysWithValues: authManager.scannedDevices.map { ($0.id, $0.rssi) })
            self.wizardStep = 2
            startCountdown()
        }.buttonStyle(.borderedProminent)
    }

    @ViewBuilder
    private var step2: some View {
        Image(systemName: "arrow.up.right.and.arrow.down.left.rectangle").font(.system(size: 40)).foregroundColor(.accentColor)
        Text("Step 2: Move Device Far Away").font(.title2)
        Text("Now, move the device about 3 meters (10 feet) away. The scan will complete automatically.").multilineTextAlignment(.center).foregroundColor(.secondary)

        Text("Time remaining: \(countdown)s")
            .font(.title3.bold().monospacedDigit()).padding()
        ProgressView(value: Double(30 - countdown), total: 30).frame(width: 200)
    }

    @ViewBuilder
    private var step3: some View {
        Image(systemName: "checkmark.shield.fill").font(.system(size: 40)).foregroundColor(.green)
        Text("Step 3: Select Your Device").font(.title2)
        Text("Based on signal change, here are the most likely candidates.").multilineTextAlignment(.center).foregroundColor(.secondary)

        if results.isEmpty {
            Text("No devices showed a significant change in distance.").foregroundColor(.secondary).padding()
        } else {
            List(results) { result in
                Button(action: {
                    authManager.selectDevice(uuid: result.id)
                    dismiss()
                }) {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(result.device.displayName)
                            Text(result.label)
                                .font(.caption)
                                .foregroundColor(labelColor(for: result.label))
                        }
                        Spacer()
                        Text(String(format: "%.0f", result.score))
                            .font(.caption.monospaced())
                            .foregroundColor(.secondary)
                    }
                }.buttonStyle(.plain)
            }
        }

        Button("Done") { dismiss() }.padding(.top)
    }

    private func startCountdown() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            if self.countdown > 0 {
                self.countdown -= 1
            } else {
                self.timer?.invalidate()
                self.calculateResults()
                self.wizardStep = 3
            }
        }
    }

    private func calculateResults() {
        let farReadings = Dictionary(uniqueKeysWithValues: authManager.scannedDevices.map { ($0.id, $0.rssi) })
        var calculatedResults: [DetectionResult] = []

        for (id, closeRSSI) in closeReadings {
            guard let farRSSI = farReadings[id], let device = authManager.scannedDevices.first(where: { $0.id == id }) else { continue }

            let delta = Double(closeRSSI - farRSSI)
            let closeQuality = max(0, min(1, Double(closeRSSI + 85) / 30.0))

            if delta > 5 && closeQuality > 0.2 {
                let score = (delta * 0.7) + (closeQuality * 30 * 0.3)

                let label: String
                if score > 40 { label = "Highly Likely" }
                else if score > 25 { label = "Likely" }
                else { label = "Low Chance" }

                calculatedResults.append(DetectionResult(id: id, device: device, score: score, label: label))
            }
        }

        self.results = calculatedResults.sorted { $0.score > $1.score }
    }

    private func labelColor(for label: String) -> Color {
        switch label {
        case "Highly Likely": return .green
        case "Likely": return .orange
        default: return .secondary
        }
    }
}

fileprivate struct CalibrateRSSIView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var settings: SettingsModel
    @ObservedObject private var authManager = AuthenticationManager.shared

    @State private var wizardStep = 1
    @State private var countdown = 5
    @State private var timer: Timer?
    @State private var rssiReadings: [Int] = []

    @State private var nearRSSI: Int?
    @State private var farRSSI: Int?

    @State private var isMeasuring = false

    @State private var calibratingDevice: Device?

    private var currentDeviceRSSI: Int? {
        if let device = calibratingDevice,
           let updatedDevice = authManager.scannedDevices.first(where: { $0.id == device.id }) {
            return updatedDevice.rssi
        }
        return calibratingDevice?.rssi
    }

    var body: some View {
        VStack(spacing: 20) {
            Text("Calibrate RSSI Range").font(.largeTitle.bold())

            switch wizardStep {
            case 1: step1Near
            case 2: step2Far
            case 3: step3Results
            default: Text("An error occurred.")
            }
        }
        .frame(width: 450, height: 400)
        .padding()
        .onAppear {
            if let selectedIDString = authManager.selectedDeviceID,
               let selectedID = UUID(uuidString: selectedIDString) {
                self.calibratingDevice = authManager.scannedDevices.first { $0.id == selectedID }
            }
        }
        .onDisappear {
            timer?.invalidate()
        }
    }

    @ViewBuilder
    private var step1Near: some View {
        Image(systemName: "arrow.down.to.line.compact").font(.system(size: 40)).foregroundColor(.accentColor)
        Text("Step 1: Calibrate 'Near' Distance").font(.title2)
        Text("Hold your device where you would normally use it when your Mac is unlocked (e.g., next to the trackpad).").multilineTextAlignment(.center).foregroundColor(.secondary)

        let rssiString = currentDeviceRSSI.map { "\($0) dBm" } ?? "Waiting for signal..."

        if isMeasuring {
            VStack {
                ProgressView("Measuring...", value: Double(5 - countdown), total: 5)
                Text("Current Signal: \(rssiString)")
                    .font(.body.bold().monospacedDigit()).padding()
            }
        } else {
             Text("Current Signal: \(rssiString)")
                .font(.body.bold().monospacedDigit()).padding()
        }

        Button(isMeasuring ? "Measuring..." : "Start Near Calibration") {
            startMeasurement { avgRSSI in
                self.nearRSSI = avgRSSI
                self.wizardStep = 2
            }
        }
        .buttonStyle(.borderedProminent)
        .disabled(isMeasuring || calibratingDevice == nil)
    }

    @ViewBuilder
    private var step2Far: some View {
        Image(systemName: "arrow.up.right.and.arrow.down.left.rectangle").font(.system(size: 40)).foregroundColor(.accentColor)
        Text("Step 2: Calibrate 'Far' Distance").font(.title2)
        Text("Now, move the device to the distance where you want your Mac to lock automatically.").multilineTextAlignment(.center).foregroundColor(.secondary)

        let rssiString = currentDeviceRSSI.map { "\($0) dBm" } ?? "Waiting for signal..."

        if isMeasuring {
            VStack {
                ProgressView("Measuring...", value: Double(5 - countdown), total: 5)
                Text("Current Signal: \(rssiString)")
                    .font(.body.bold().monospacedDigit()).padding()
            }
        } else {
             Text("Current Signal: \(rssiString)")
                .font(.body.bold().monospacedDigit()).padding()
        }

        Button(isMeasuring ? "Measuring..." : "Start Far Calibration") {
            startMeasurement { avgRSSI in
                self.farRSSI = avgRSSI
                self.wizardStep = 3
            }
        }
        .buttonStyle(.borderedProminent)
        .disabled(isMeasuring || calibratingDevice == nil)
    }

    @ViewBuilder
    private var step3Results: some View {
        Image(systemName: "checkmark.shield.fill").font(.system(size: 40)).foregroundColor(.green)
        Text("Calibration Complete").font(.title2)
        Text("Here are the suggested settings based on your measurements.").multilineTextAlignment(.center).foregroundColor(.secondary)

        if let near = nearRSSI, let far = farRSSI {
            let suggestedUnlock = min(-10, near + 5)
            let suggestedLock = max(-100, far - 5)

            VStack(alignment: .leading, spacing: 15) {
                Text("Measured Average 'Near' Signal: **\(near) dBm**")
                Text("Measured Average 'Far' Signal: **\(far) dBm**")
                Divider()
                Text("Suggested Unlock RSSI: **\(suggestedUnlock) dBm**")
                    .foregroundColor(.green)
                Text("Suggested Lock RSSI: **\(suggestedLock) dBm**")
                    .foregroundColor(.red)
            }
            .padding()
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(8)

            HStack {
                Button("Done") { dismiss() }

                Spacer()

                Button("Apply Settings") {
                    settings.settings.bluetoothUnlockUnlockRSSI = suggestedUnlock
                    settings.settings.bluetoothUnlockLockRSSI = suggestedLock
                    dismiss()
                }.buttonStyle(.borderedProminent)
            }
            .padding(.top)

        } else {
            Text("Measurement data is missing. Please try again.")
                .foregroundColor(.red)
            Button("Restart") {
                wizardStep = 1
            }
        }
    }

    private func startMeasurement(completion: @escaping (Int) -> Void) {
        isMeasuring = true
        rssiReadings.removeAll()
        countdown = 5

        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            if let rssi = self.currentDeviceRSSI {
                rssiReadings.append(rssi)
            }

            if self.countdown > 1 {
                self.countdown -= 1
            } else {
                self.timer?.invalidate()
                self.isMeasuring = false

                if !rssiReadings.isEmpty {
                    let average = rssiReadings.reduce(0, +) / rssiReadings.count
                    completion(average)
                } else {
                    completion(self.currentDeviceRSSI ?? -75)
                }
            }
        }
    }
}

struct FanControlSectionView: View {
    @ObservedObject private var fanManager = FanManager.shared
    @State private var fanToEditID: Int?

    private var isSheetPresented: Binding<Bool> {
        Binding<Bool>(
            get: { self.fanToEditID != nil },
            set: { isShowing in
                if !isShowing {
                    self.fanToEditID = nil
                }
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Fan Control").font(.headline).padding([.top, .horizontal])

            InfoContainer(text: "Fan control is in beta and may not work if the current fan speed is 0 rpm.", iconName: "fanblades.fill", color: .red)
                .padding()

            if fanManager.fans.isEmpty {
                Text("No fans detected on this system.")
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                ForEach($fanManager.fans) { $fan in
                    FanRowView(fan: $fan, onCustomize: { fanToEditID = fan.id })
                    if fan.id != fanManager.fans.last?.id {
                        Divider().padding(.leading, 20)
                    }
                }
            }
        }
        .modifier(SettingsContainerModifier())
        .sheet(isPresented: isSheetPresented) {
            if let id = fanToEditID, let fanIndex = fanManager.fans.firstIndex(where: { $0.id == id }) {
                FanControlSheetView(fan: $fanManager.fans[fanIndex], availableSensors: fanManager.sensors)
                    .environmentObject(fanManager)
            }
        }
        .environmentObject(fanManager)
    }
}

struct FanRowView: View {
    @Binding var fan: FanInfo
    let onCustomize: () -> Void
    @EnvironmentObject var fanManager: FanManager

    private var modeString: String {
        switch fanManager.fanModes[fan.id] {
        case .auto: return "Auto"
        case .constant(let rpm): return "Constant \(rpm) RPM"
        case .sensor(let key, _, _):
            let name = SensorNameMap.name(for: key)
            return "Sensor: \(name)"
        case nil: return "Auto"
        }
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(fan.name.contains("Fan") ? "Fan \(fan.id + 1)" : fan.name)
                    .font(.headline)

                Text("Min: \(fan.minRPM) | Current: \(fan.currentRPM) | Max: \(fan.maxRPM) RPM")
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)

                Text(modeString)
                    .font(.caption)
                    .foregroundColor(.accentColor)
            }
            Spacer()
            Button("Custom...") { onCustomize() }
        }
        .padding()
    }
}

struct FanControlSheetView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var fanManager: FanManager
    @Binding var fan: FanInfo
    let availableSensors: [TemperatureSensor]

    @State private var selectedMode: Int
    @State private var constantRPM: Double
    @State private var sensorKey: String
    @State private var minTemp: Double
    @State private var maxTemp: Double

    init(fan: Binding<FanInfo>, availableSensors: [TemperatureSensor]) {
        self._fan = fan
        self.availableSensors = availableSensors

        let initialMode = FanManager.shared.fanModes[fan.wrappedValue.id] ?? .auto

        switch initialMode {
        case .auto:
            _selectedMode = State(initialValue: 0)
            _constantRPM = State(initialValue: Double(fan.wrappedValue.minRPM))
            _sensorKey = State(initialValue: availableSensors.first?.key ?? "")
            _minTemp = State(initialValue: 40)
            _maxTemp = State(initialValue: 75)
        case .constant(let rpm):
            _selectedMode = State(initialValue: 1)
            _constantRPM = State(initialValue: Double(rpm))
            _sensorKey = State(initialValue: availableSensors.first?.key ?? "")
            _minTemp = State(initialValue: 40)
            _maxTemp = State(initialValue: 75)
        case .sensor(let key, let minT, let maxT):
            _selectedMode = State(initialValue: 2)
            _constantRPM = State(initialValue: Double(fan.wrappedValue.minRPM))
            _sensorKey = State(initialValue: key)
            _minTemp = State(initialValue: Double(minT))
            _maxTemp = State(initialValue: Double(maxT))
        }
    }

    private var selectedSensorValueString: String {
        if let sensor = availableSensors.first(where: { $0.key == sensorKey }) {
            return String(format: "%.1f°C", sensor.value)
        }
        return "N/A"
    }

    var body: some View {
        VStack(spacing: 20) {
            Text("Change Fan Control for '\(fan.name.contains("Fan") ? "Fan \(fan.id + 1)" : fan.name)'")
                .font(.title2.bold())

            Picker("Control Mode", selection: $selectedMode) {
                Text("Automatic").tag(0)
                Text("Constant RPM").tag(1)
                Text("Sensor-based").tag(2)
            }
            .pickerStyle(.segmented)
            .padding(.bottom)

            if selectedMode == 1 {
                VStack {
                    CustomSliderRowView(label: "Fan Speed", value: $constantRPM, range: Double(fan.minRPM)...Double(fan.maxRPM), specifier: "%.0f RPM")
                }
            } else if selectedMode == 2 {
                VStack(spacing: 15) {
                    HStack {
                        Text("Based on Sensor:")
                        Spacer()
                        Picker("Sensor", selection: $sensorKey) {
                            ForEach(availableSensors) { sensor in
                                HStack {
                                    Text(sensor.name)
                                    Spacer()
                                    Text(String(format: "%.1f°C", sensor.value))
                                        .foregroundColor(.secondary)
                                }.tag(sensor.key)
                            }
                        }
                        Text(selectedSensorValueString)
                            .font(.body.monospacedDigit())
                            .foregroundColor(.secondary)
                            .frame(width: 60, alignment: .trailing)
                    }

                    CustomSliderRowView(label: "Start increasing from:", value: $minTemp, range: 20...100, specifier: "%.0f °C")
                        .onChange(of: minTemp) {
                            if minTemp > maxTemp {
                                maxTemp = minTemp
                            }
                        }

                    CustomSliderRowView(label: "Maximum temperature:", value: $maxTemp, range: 20...100, specifier: "%.0f °C")
                        .onChange(of: maxTemp) {
                            if maxTemp < minTemp {
                                minTemp = maxTemp
                            }
                        }
                }
            } else {
                Text("The fan will be controlled automatically by macOS.")
                    .foregroundColor(.secondary)
                    .frame(minHeight: 150, alignment: .center)
            }

            Spacer()

            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("OK") {
                    saveAndDismiss()
                }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
        }
        .padding(30)
        .frame(width: 550)
        .frame(minHeight: 350)
    }

    private func saveAndDismiss() {
        let newMode: FanControlMode
        switch selectedMode {
        case 1:
            newMode = .constant(rpm: Int(constantRPM))
        case 2:
            newMode = .sensor(sensorKey: sensorKey, minTemp: Int(minTemp), maxTemp: Int(maxTemp))
        default:
            newMode = .auto
        }
        fanManager.setFanMode(for: fan.id, to: newMode)
        dismiss()
    }
}

struct CalibrationView: View {
    @StateObject private var calibrationManager = CalibrationManager.shared
    @StateObject private var batteryMonitor = BatteryMonitor.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Battery Calibration").font(.headline).padding([.top, .horizontal])
            InfoContainer(
                text: "Calibrating your battery helps macOS get a more accurate reading of its health and time remaining. This process can take several hours and involves a full charge and discharge cycle. Sleeping will be disabled during calibration.",
                iconName: "gauge.high",
                color: .purple
            ).padding()

            VStack(spacing: 15) {
                if calibrationManager.isActive {
                    VStack(spacing: 8) {
                        Text(calibrationManager.state.description)
                            .font(.headline)
                            .foregroundColor(.secondary)

                        ProgressView(value: calibrationManager.progress)
                            .progressViewStyle(.linear)

                        Text(String(format: "%.1f%% complete", calibrationManager.progress * 100))
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Button("Cancel Calibration", role: .destructive) {
                            calibrationManager.cancel()
                        }
                        .padding(.top, 5)
                    }

                } else {
                    VStack(spacing: 12) {
                        if calibrationManager.state == .done {
                             Text("Calibration completed successfully.")
                                .foregroundColor(.green)
                        } else if case .error(let message) = calibrationManager.state {
                            Text(message)
                                .foregroundColor(.red)
                        }

                        Text("Ensure your Mac is plugged in before starting. Do not unplug or put your Mac to sleep during the process.")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Button(action: {
                            calibrationManager.start()
                        }) {
                            Text("Start Calibration")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.purple)
                        .disabled(batteryMonitor.currentState?.isPluggedIn == false)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .modifier(SettingsContainerModifier())
    }
}

struct BatterySettingsView: View {
    @State private var selectedTab: String = "Statistics"

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading) {
                Text("Battery").font(.largeTitle.bold()).padding(.bottom, 10)
                ModernSegmentedPicker(
                    selection: $selectedTab,
                    options: ["Statistics", "Configuration"]
                )
                .padding(.bottom, 5)

            }
            .padding(.horizontal, 25).padding(.top, 25)

            Spacer()

            if selectedTab == "Statistics" {
                ModernBatteryStatsView()
            } else {
                BatteryConfigurationView()
            }
        }
        .animation(.easeInOut(duration: 0.2), value: selectedTab)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

struct DateRangePickerView: View {
    @Binding var selection: TimeRange

    @State private var showCustomPicker = false

    @State private var customStartDate: Date
    @State private var customEndDate: Date

    @Namespace private var datePickerNamespace

    init(selection: Binding<TimeRange>) {
        self._selection = selection

        if case .custom(let start, let end) = selection.wrappedValue {
            _customStartDate = State(initialValue: start)
            _customEndDate = State(initialValue: end)
        } else {
            _customStartDate = State(initialValue: Date())
            _customEndDate = State(initialValue: Date())
        }
    }

    private var isCustomSelected: Bool {
        if case .custom = selection {
            return true
        }
        return false
    }

    var body: some View {
        HStack(spacing: 8) {

            PickerButton(label: "24h", isSelected: selection == .last24Hours, namespace: datePickerNamespace) {
                updateSelection(.last24Hours)
            }
            PickerButton(label: "7d", isSelected: selection == .last7Days, namespace: datePickerNamespace) {
                updateSelection(.last7Days)
            }
            PickerButton(label: "Month", isSelected: selection == .lastMonth, namespace: datePickerNamespace) {
                updateSelection(.lastMonth)
            }
            PickerButton(label: "Year", isSelected: selection == .lastYear, namespace: datePickerNamespace) {
                updateSelection(.lastYear)
            }

            PickerButton(label: "Custom", isSelected: isCustomSelected, namespace: datePickerNamespace) {
                showCustomPicker = true
            }
            .popover(isPresented: $showCustomPicker, attachmentAnchor: .point(.bottom)) {
                customDatePickerView
            }
        }
        .padding(5)
        .background(Color.black.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func updateSelection(_ newSelection: TimeRange) {
        withAnimation(.interactiveSpring(response: 0.35, dampingFraction: 0.7)) {
            selection = newSelection
        }
    }

    private var customDatePickerView: some View {
        VStack(spacing: 15) {
            Text("Select Custom Range")
                .font(.headline)

            DatePicker("Start Date", selection: $customStartDate, in: ...customEndDate, displayedComponents: .date)
            DatePicker("End Date", selection: $customEndDate, in: ...Date(), displayedComponents: .date)

            Button("Apply") {
                withAnimation(.interactiveSpring(response: 0.35, dampingFraction: 0.7)) {
                    selection = .custom(customStartDate, customEndDate)
                }
                showCustomPicker = false
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity)
        }
        .padding()
        .frame(minWidth: 250)
    }
}

fileprivate struct PickerButton: View {
    let label: String
    let isSelected: Bool
    let namespace: Namespace.ID
    let action: () -> Void

    var body: some View {
        Text(label)
            .font(.subheadline.weight(.bold))
            .padding(.vertical, 8)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
            .background(
                ZStack {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(.ultraThinMaterial)
                            .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                            .matchedGeometryEffect(id: "datePickerPill", in: namespace)
                    }
                }
            )
            .foregroundColor(isSelected ? .primary : .secondary)
            .contentShape(Rectangle())
            .onTapGesture(perform: action)
    }
}

struct HeroMetricsView: View {
    @ObservedObject var viewModel: BatteryStatsViewModel
    private var statusColor: Color {
        if viewModel.isCharging { return .green }
        if viewModel.batteryLevel < 20 { return .red }
        if viewModel.batteryLevel < 50 { return .orange }
        return .blue
    }

    var body: some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(viewModel.batteryLevel)").font(.system(size: 72, weight: .bold, design: .rounded)).foregroundColor(statusColor)
                    Text("%").font(.system(size: 36, weight: .semibold, design: .rounded)).foregroundColor(statusColor.opacity(0.7))
                }
                HStack(spacing: 8) {
                    Image(systemName: viewModel.isCharging ? "bolt.fill" : "battery.100").font(.headline).foregroundColor(statusColor)
                    Text(viewModel.isCharging ? "Charging" : "Discharging").font(.headline).foregroundColor(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 16) {
                HStack(spacing: 12) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Time Remaining").font(.caption).foregroundColor(.secondary)
                        Text(viewModel.timeRemaining).font(.system(.body, design: .rounded).weight(.semibold))
                    }
                    Image(systemName: "clock.fill").font(.title3).foregroundColor(.cyan).frame(width: 28)
                }
                HStack(spacing: 12) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Health").font(.caption).foregroundColor(.secondary)
                        Text("\(viewModel.maxCapacityPercentage)%").font(.system(.body, design: .rounded).weight(.semibold))
                    }
                    Image(systemName: "heart.fill").font(.title3).foregroundColor(.pink).frame(width: 28)
                }
                HStack(spacing: 12) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Cycles").font(.caption).foregroundColor(.secondary)
                        Text("\(viewModel.cycleCount)").font(.system(.body, design: .rounded).weight(.semibold))
                    }
                    Image(systemName: "arrow.triangle.2.circlepath").font(.title3).foregroundColor(.purple).frame(width: 28)
                }
            }
        }
        .padding(24).modifier(SettingsContainerModifier())
    }
}

struct SpecRow: View {
    let label: String, value: String, percentage: String?
    init(label: String, value: String, percentage: String? = nil) {
        self.label = label; self.value = value; self.percentage = percentage
    }
    var body: some View {
        HStack {
            Text(label).foregroundColor(.secondary)
            Spacer()
            Text(value).fontWeight(.medium).lineLimit(1).truncationMode(.middle)
            if let percentage {
                Text(percentage).fontWeight(.medium).frame(width: 50, alignment: .trailing)
            }
        }.font(.system(size: 12))
    }
}

struct ComponentPowerBreakdownView: View {
    @ObservedObject var viewModel: BatteryStatsViewModel
    @ObservedObject private var statsManager = StatsManager.shared

    private var systemLoad: Double { statsManager.currentStats?.systemPower ?? abs(viewModel.powerConsumption) }
    private var batteryPower: Double { statsManager.currentStats?.batteryPower ?? viewModel.powerConsumption }
    private var chargingPower: Double { (viewModel.isCharging && batteryPower < 0) ? abs(batteryPower) : 0 }
    private var adapterPower: Double { statsManager.currentStats?.sensors?.sensors.first { ["PDTR"].contains($0.key) }?.value ?? 0 }
    private var cpuPower: Double { statsManager.currentStats?.sensors?.sensors.first { ["PCPC", "PCTR", "PC0C"].contains($0.key) }?.value ?? 0 }
    private var gpuPower: Double { statsManager.currentStats?.sensors?.sensors.first { ["PGTR", "PG0C", "PCGC"].contains($0.key) }?.value ?? 0 }
    private var displayPower: Double { max(0, systemLoad - (cpuPower + gpuPower)) * 0.4 }
    private var otherPower: Double { max(0, systemLoad - (cpuPower + gpuPower + displayPower)) }
    private var isCharging: Bool { viewModel.isCharging }
    private var adapterConnected: Bool { (viewModel.powerAdapterInfo?.maxPower ?? 0) > 0 }

    var body: some View {
        VStack(spacing: 16) {
            powerFlowDiagram
            powerBreakdownCards
        }
        .onAppear {
            statsManager.setPolling(for: "ComponentBreakdown", requiredStats: [.systemPower, .batteryPower, .cpu, .gpu])
        }
        .onDisappear {
            statsManager.setPolling(for: "ComponentBreakdown", requiredStats: [])
        }
    }

    private var powerFlowDiagram: some View {
        HStack(spacing: 0) {
            powerSourceIcon
            powerFlowCenter
            laptopIcon
        }
        .padding(20)
        .modifier(SettingsContainerModifier())
    }

    private var powerBreakdownCards: some View {
        HStack(spacing: 12) {
            if isCharging && chargingPower > 0 {
                PowerBreakdownCard(icon: "battery.100.bolt", title: "Charging", power: chargingPower, color: .green)
            }
            if cpuPower > 0.5 {
                PowerBreakdownCard(icon: "cpu", title: "CPU", power: cpuPower, color: .cyan)
            }
            if gpuPower > 0.5 {
                PowerBreakdownCard(icon: "cube.fill", title: "GPU", power: gpuPower, color: .purple)
            }
            if displayPower > 0.5 {
                PowerBreakdownCard(icon: "display", title: "Display", power: displayPower, color: .orange)
            }
            if otherPower > 0.5 {
                PowerBreakdownCard(icon: "ellipsis.circle.fill", title: "Other", power: otherPower, color: .gray)
            }
        }
    }

    private var powerSourceIcon: some View {
        ZStack {
            Circle().fill(adapterConnected ? Color.gray.opacity(0.15) : Color.gray.opacity(0.05)).frame(width: 60, height: 60)
            Image(systemName: "powerplug.fill").font(.system(size: 24)).foregroundColor(adapterConnected ? .gray : .gray.opacity(0.3))
        }.frame(width: 80)
    }

    private var powerFlowCenter: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12).fill(Color.gray.opacity(0.1)).frame(height: 80)
            if adapterConnected { AnimatedFlowGradient(isCharging: isCharging) }
            VStack(spacing: 4) {
                Text(String(format: "%.2f W", adapterConnected ? adapterPower : systemLoad))
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                powerStatusText
            }
        }.frame(maxWidth: .infinity)
    }

    @ViewBuilder private var powerStatusText: some View {
        if isCharging {
            HStack(spacing: 4) {
                Image(systemName: "bolt.fill").font(.caption).foregroundColor(.green)
                Text("Charging").font(.caption).foregroundColor(.green)
            }
        } else if adapterConnected { Text("On AC Power").font(.caption).foregroundColor(.blue) }
        else { Text("On Battery").font(.caption).foregroundColor(.orange) }
    }

    private var laptopIcon: some View {
        ZStack {
            Circle().fill(Color.gray.opacity(0.15)).frame(width: 60, height: 60)
            Image(systemName: "laptopcomputer").font(.system(size: 24)).foregroundColor(.gray)
        }.frame(width: 80)
    }
}

struct AnimatedFlowGradient: View {
    let isCharging: Bool

    @State private var isAnimating: Bool = false

    private let animationDuration: Double = 2.5
    private let highlightOpacity: Double = 0.35

    var body: some View {
        ZStack {
            let backgroundColors: [Color] = isCharging ? [
                Color.green.opacity(0.7),
                Color.cyan.opacity(0.6),
                Color.blue.opacity(0.7)
            ] : [
                Color.blue.opacity(0.7),
                Color.cyan.opacity(0.6),
                Color.green.opacity(0.7)
            ]

            LinearGradient(
                colors: backgroundColors,
                startPoint: .leading,
                endPoint: .trailing
            )

            GeometryReader { geometry in
                let highlightGradient = LinearGradient(
                    gradient: Gradient(colors: [
                        .clear,
                        .white.opacity(highlightOpacity),
                        .clear
                    ]),
                    startPoint: .leading,
                    endPoint: .trailing
                )

                highlightGradient
                    .frame(width: geometry.size.width)
                    .offset(x: isAnimating ? geometry.size.width : -geometry.size.width)
            }
        }
        .frame(height: 80)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onAppear {
            withAnimation(
                .linear(duration: animationDuration)
                .repeatForever(autoreverses: false)
            ) {
                isAnimating.toggle()
            }
        }
    }
}

struct PowerBreakdownCard: View {
    let icon: String
    let title: String
    let power: Double
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(color)

            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)

            Text(String(format: "%.2f W", power))
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundColor(.primary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .modifier(SettingsContainerModifier())
    }
}

struct ModernBatteryStatsView: View {
    @StateObject private var viewModel = BatteryStatsViewModel()
    @StateObject private var historyViewModel = BatteryHistoryViewModel()
    @StateObject private var energyViewModel = EnergyViewModel()
    @StateObject private var helperManager = HelperManager.shared
    @State private var selectedTimeRange: TimeRange = .last24Hours

    private let mainGridLayout = [GridItem(.flexible(), spacing: 20), GridItem(.flexible(), spacing: 20)]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Spacer()
                    DateRangePickerView(selection: $selectedTimeRange)
                }

                HStack(spacing: 15) {
                    switch helperManager.status {
                    case .enabled:
                        Image(systemName: "checkmark.circle.fill").font(.title2).foregroundColor(.green)
                        Text("Helper Installed Successfully")
                            .font(.headline)
                    case .requiresApproval:
                        Image(systemName: "exclamationmark.triangle.fill").font(.title2).foregroundColor(.yellow)
                        VStack(alignment: .leading) {
                            Text("Approval Required")
                                .font(.headline)
                            Text("Please enable in System Settings > Login Items.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    default:
                        Image(systemName: "xmark.circle.fill").font(.title2).foregroundColor(.red)
                        Text("Helper Not Installed")
                            .font(.headline)
                    }

                    Spacer()

                    if helperManager.status != .enabled {
                        Button("Install") {
                            helperManager.installIfNeeded()
                        }
                        .buttonStyle(.bordered)
                        .tint(.accentColor)
                    }
                }
                .padding()
                .background(.black.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color.white.opacity(0.1), lineWidth: 1))

                HeroMetricsView(viewModel: viewModel)

                ComponentPowerBreakdownView(viewModel: viewModel)

                BatteryHistoryView(historyViewModel: historyViewModel)

                LazyVGrid(columns: mainGridLayout, spacing: 20) {
                    MaxCapacityGraphCard(viewModel: viewModel, historyViewModel: historyViewModel, selectedTimeRange: $selectedTimeRange)
                    CycleCountGraphCard(viewModel: viewModel, historyViewModel: historyViewModel, selectedTimeRange: $selectedTimeRange)
                    TemperatureGraphCard(viewModel: viewModel, historyViewModel: historyViewModel, selectedTimeRange: $selectedTimeRange)
                    PowerTimeHistoryGraphView(historyViewModel: historyViewModel, selectedTimeRange: $selectedTimeRange)
                    BatteryHealthCard(viewModel: viewModel)
                    BatterySpecsCard(viewModel: viewModel)
                    PowerAdapterSpecsCard(viewModel: viewModel)
                    SignificantEnergyUsersView(viewModel: energyViewModel)
                }
            }
            .padding(.horizontal, 25)
            .padding(.bottom, 25)
        }
        .onAppear {
            historyViewModel.fetchHistory()
            energyViewModel.start()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                historyViewModel.filterData(for: selectedTimeRange)
            }
        }
        .onDisappear {
            energyViewModel.stop()
        }
        .onChange(of: selectedTimeRange) { _, newRange in
            historyViewModel.filterData(for: newRange)
        }
    }
}

struct PowerStatCard: View {
    let icon: String
    let iconColor: Color
    let title: String
    let value: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(iconColor)
                    .font(.system(size: 16))
                Spacer()
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text(value)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .lineLimit(1)

                Text(subtitle)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .modifier(SettingsContainerModifier())
        .frame(height: 100)
    }
}

struct BatterySpecsCard: View {
    @ObservedObject var viewModel: BatteryStatsViewModel
    @ObservedObject private var statsManager = StatsManager.shared
    @ObservedObject private var powerModeManager = PowerModeManager.shared

    private var systemLoad: Double {
        statsManager.currentStats?.systemPower ?? abs(viewModel.powerConsumption)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "bolt.fill").foregroundColor(.yellow)
                Text("Battery Specs").font(.headline)
            }
            Spacer()
            SpecRow(label: "Current", value: String(format: "%.1f A", Double(abs(viewModel.amperage)) / 1000.0))
            SpecRow(label: "Voltage", value: String(format: "%.1f V", viewModel.voltage / 1000.0))
            SpecRow(label: "Power", value: String(format: "%.0f W", abs(viewModel.powerConsumption)))
            SpecRow(label: "System Load", value: String(format: "%.2f W", systemLoad))

            HStack {
                Text("Low Power Mode").font(.system(size: 12)).foregroundColor(.secondary)
                Spacer()
                Button(action: {
                    if powerModeManager.isLowPowerModeActive {
                        powerModeManager.disableLowPowerMode()
                    } else {
                        powerModeManager.enableLowPowerMode()
                    }
                }) {
                    Text(powerModeManager.isLowPowerModeActive ? "Enabled" : "Disabled")
                        .font(.system(size: 12)).fontWeight(.medium)
                        .foregroundColor(powerModeManager.isLowPowerModeActive ? .green : .primary)
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding()
        .frame(height: 180)
        .modifier(SettingsContainerModifier())
        .onAppear {
            statsManager.setPolling(for: "BatterySettings", requiredStats: [.systemPower, .batteryPower])
            _ = powerModeManager.isLowPowerModeEnabled()
        }
        .onDisappear {
            statsManager.setPolling(for: "BatterySettings", requiredStats: [])
        }
    }
}

struct MaxCapacityGraphCard: View {
    @ObservedObject var viewModel: BatteryStatsViewModel
    @ObservedObject var historyViewModel: BatteryHistoryViewModel
    @Binding var selectedTimeRange: TimeRange
    @State private var isHovered = false
    @State private var selectedDate: Date?

    var body: some View {
        let chartData = historyViewModel.chartData.filter({ $0.maxCapacity > 0 })
        let capacities = chartData.map { $0.maxCapacity }
        let yDomainMin = (capacities.min() ?? 0) - 50
        let yDomainMax = (capacities.max() ?? 8000) + 50

        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Max Capacity").font(.headline)
                Spacer()
                Text("\(viewModel.maxCapacityPercentage)%").font(.subheadline.weight(.semibold)).foregroundColor(.cyan)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)

            Spacer()

            if chartData.isEmpty {
                EmptyStatsView(height: 120)
                    .padding(.horizontal, 16)
            } else {
                Chart {
                    ForEach(chartData) { entry in
                        LineMark(x: .value("Time", entry.timestamp), y: .value("Capacity", entry.maxCapacity))
                            .foregroundStyle(.cyan)
                            .interpolationMethod(.catmullRom)
                        AreaMark(x: .value("Time", entry.timestamp), y: .value("Capacity", entry.maxCapacity))
                            .foregroundStyle(LinearGradient(colors: [.cyan.opacity(0.3), .clear], startPoint: .top, endPoint: .bottom))
                            .interpolationMethod(.catmullRom)
                    }

                    if let selectedDate, let entry = findClosest(to: selectedDate, in: chartData) {
                        PointMark(x: .value("Time", entry.timestamp), y: .value("Capacity", entry.maxCapacity))
                            .foregroundStyle(.cyan)
                            .symbolSize(100)

                        RuleMark(x: .value("Selected", selectedDate))
                            .foregroundStyle(.white.opacity(0.2))
                            .annotation(position: .top, alignment: .center) {
                                Text("\(entry.maxCapacity) mAh")
                                    .font(.caption)
                                    .padding(4)
                                    .background(.background)
                                    .cornerRadius(4)
                            }
                    }
                }
                .chartYScale(domain: yDomainMin...yDomainMax)
                .dynamicXAxis(for: selectedTimeRange, isVisible: isHovered)
                .chartYAxis { if isHovered { AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) } }
                .chartOverlay { proxy in chartInteraction(proxy: proxy, chartData: chartData) }
                .frame(height: 120)
            }

            Spacer()
        }
        .frame(height: 180)
        .modifier(SettingsContainerModifier())
        .onHover { hovering in withAnimation(.easeInOut) { self.isHovered = hovering } }
    }

    private func chartInteraction(proxy: ChartProxy, chartData: [BatteryLogEntry]) -> some View {
        GeometryReader { geometry in
            Rectangle().fill(.clear).contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location):
                        let plotAreaStart = geometry.size.width * 0.05
                        let plotAreaWidth = geometry.size.width * 0.90

                        guard location.x >= plotAreaStart && location.x <= plotAreaStart + plotAreaWidth else {
                            self.selectedDate = nil
                            return
                        }

                        if let date: Date = proxy.value(atX: location.x) {
                            self.selectedDate = date
                        }
                    case .ended:
                        self.selectedDate = nil
                    }
                }
        }
    }

    private func findClosest(to date: Date, in data: [BatteryLogEntry]) -> BatteryLogEntry? {
        data.min(by: { abs($0.timestamp.timeIntervalSince(date)) < abs($1.timestamp.timeIntervalSince(date)) })
    }
}

struct CycleCountGraphCard: View {
    @ObservedObject var viewModel: BatteryStatsViewModel
    @ObservedObject var historyViewModel: BatteryHistoryViewModel
    @Binding var selectedTimeRange: TimeRange
    @State private var isHovered = false
    @State private var selectedDate: Date?

    var body: some View {
        let chartData = historyViewModel.chartData.filter({ $0.cycleCount > 0 })
        let cycles = chartData.map { $0.cycleCount }
        let yDomainMin = (cycles.min() ?? 0) - 10
        let yDomainMax = (cycles.max() ?? 1000) + 10

        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Cycle Count").font(.headline)
                Spacer()
                Text("\(viewModel.cycleCount)").font(.subheadline.weight(.semibold)).foregroundColor(.purple)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)

            Spacer()

            if chartData.isEmpty {
                EmptyStatsView(height: 120)
                    .padding(.horizontal, 16)
            } else {
                Chart {
                    ForEach(chartData) { entry in
                        LineMark(x: .value("Time", entry.timestamp), y: .value("Cycles", entry.cycleCount))
                            .foregroundStyle(.purple)
                            .interpolationMethod(.stepStart)
                        AreaMark(x: .value("Time", entry.timestamp), y: .value("Cycles", entry.cycleCount))
                            .foregroundStyle(LinearGradient(colors: [.purple.opacity(0.3), .clear], startPoint: .top, endPoint: .bottom))
                            .interpolationMethod(.stepStart)
                    }

                    if let selectedDate, let entry = findClosest(to: selectedDate, in: chartData) {
                        PointMark(x: .value("Time", entry.timestamp), y: .value("Cycles", entry.cycleCount))
                            .foregroundStyle(.purple)
                            .symbolSize(100)

                        RuleMark(x: .value("Selected", selectedDate))
                            .foregroundStyle(.white.opacity(0.2))
                            .annotation(position: .top, alignment: .center) {
                                Text("\(entry.cycleCount) cycles")
                                    .font(.caption)
                                    .padding(4)
                                    .background(.background)
                                    .cornerRadius(4)
                            }
                    }
                }
                .chartYScale(domain: yDomainMin...yDomainMax)
                .dynamicXAxis(for: selectedTimeRange, isVisible: isHovered)
                .chartYAxis { if isHovered { AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) } }
                .chartOverlay { proxy in chartInteraction(proxy: proxy, chartData: chartData) }
                .frame(height: 120)
            }

            Spacer()
        }
        .frame(height: 180)
        .modifier(SettingsContainerModifier())
        .onHover { hovering in withAnimation(.easeInOut) { self.isHovered = hovering } }
    }

    private func chartInteraction(proxy: ChartProxy, chartData: [BatteryLogEntry]) -> some View {
        GeometryReader { geometry in
            Rectangle().fill(.clear).contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location):
                        let plotAreaStart = geometry.size.width * 0.05
                        let plotAreaWidth = geometry.size.width * 0.90

                        guard location.x >= plotAreaStart && location.x <= plotAreaStart + plotAreaWidth else {
                            self.selectedDate = nil
                            return
                        }

                        if let date: Date = proxy.value(atX: location.x) {
                            self.selectedDate = date
                        }
                    case .ended:
                        self.selectedDate = nil
                    }
                }
        }
    }

    private func findClosest(to date: Date, in data: [BatteryLogEntry]) -> BatteryLogEntry? {
        data.min(by: { abs($0.timestamp.timeIntervalSince(date)) < abs($1.timestamp.timeIntervalSince(date)) })
    }
}

struct TemperatureGraphCard: View {
    @ObservedObject var viewModel: BatteryStatsViewModel
    @ObservedObject var historyViewModel: BatteryHistoryViewModel
    @Binding var selectedTimeRange: TimeRange
    @State private var isHovered = false
    @State private var selectedDate: Date?

    var body: some View {
        let chartData = historyViewModel.chartData.filter({ $0.temperature > 0 })

        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Temperature").font(.headline)
                Spacer()
                Text(String(format: "%.1f °C", viewModel.temperature)).font(.subheadline.weight(.semibold)).foregroundColor(.orange)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)

            Spacer()

            if chartData.isEmpty {
                EmptyStatsView(height: 120)
                    .padding(.horizontal, 16)
            } else {
                Chart {
                    ForEach(chartData) { entry in
                        LineMark(x: .value("Time", entry.timestamp), y: .value("Temp", entry.temperature))
                            .foregroundStyle(.orange)
                            .interpolationMethod(.catmullRom)
                    }

                    if let selectedDate, let entry = findClosest(to: selectedDate, in: chartData) {
                        PointMark(x: .value("Time", entry.timestamp), y: .value("Temp", entry.temperature))
                            .foregroundStyle(.orange)
                            .symbolSize(100)

                        RuleMark(x: .value("Selected", selectedDate))
                            .foregroundStyle(.white.opacity(0.2))
                            .annotation(position: .top, alignment: .center) {
                                Text(String(format: "%.1f °C", entry.temperature))
                                    .font(.caption)
                                    .padding(4)
                                    .background(.background)
                                    .cornerRadius(4)
                            }
                    }
                }
                .chartYScale(domain: 20...55)
                .dynamicXAxis(for: selectedTimeRange, isVisible: isHovered)
                .chartYAxis { if isHovered { AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) } }
                .chartOverlay { proxy in chartInteraction(proxy: proxy, chartData: chartData) }
                .frame(height: 120)
            }

            Spacer()
        }
        .frame(height: 180)
        .modifier(SettingsContainerModifier())
        .onHover { hovering in withAnimation(.easeInOut) { self.isHovered = hovering } }
    }

    private func chartInteraction(proxy: ChartProxy, chartData: [BatteryLogEntry]) -> some View {
        GeometryReader { geometry in
            Rectangle().fill(.clear).contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location):
                        let plotAreaStart = geometry.size.width * 0.05
                        let plotAreaWidth = geometry.size.width * 0.90

                        guard location.x >= plotAreaStart && location.x <= plotAreaStart + plotAreaWidth else {
                            self.selectedDate = nil
                            return
                        }

                        if let date: Date = proxy.value(atX: location.x) {
                            self.selectedDate = date
                        }
                    case .ended:
                        self.selectedDate = nil
                    }
                }
        }
    }

    private func findClosest(to date: Date, in data: [BatteryLogEntry]) -> BatteryLogEntry? {
        data.min(by: { abs($0.timestamp.timeIntervalSince(date)) < abs($1.timestamp.timeIntervalSince(date)) })
    }
}

struct PowerTimeHistoryGraphView: View {
    @ObservedObject var historyViewModel: BatteryHistoryViewModel
    @Binding var selectedTimeRange: TimeRange
    @State private var isHovered = false
    @State private var selectedDate: Date?

    var body: some View {
        let powerData = historyViewModel.chartData.filter { $0.powerConsumption > 0 }
        let timeData = historyViewModel.chartData.filter { $0.timeRemainingMinutes > 0 }

        VStack(alignment: .leading, spacing: 0) {
            Text("Power & Time").font(.headline)
                .padding(.horizontal, 16)
                .padding(.top, 16)

            Spacer()

            if powerData.isEmpty && timeData.isEmpty {
                EmptyStatsView(height: 120)
                    .padding(.horizontal, 16)
            } else {
                Chart {
                    ForEach(powerData) { entry in
                        LineMark(x: .value("Time", entry.timestamp), y: .value("Power", entry.powerConsumption))
                            .foregroundStyle(by: .value("Metric", "Power (W)"))
                    }
                    ForEach(timeData) { entry in
                        LineMark(x: .value("Time", entry.timestamp), y: .value("Time", Double(entry.timeRemainingMinutes) / 60.0))
                            .foregroundStyle(by: .value("Metric", "Time (h)"))
                    }

                    if let selectedDate {
                        if let powerEntry = findClosest(to: selectedDate, in: powerData) {
                            PointMark(x: .value("Time", powerEntry.timestamp), y: .value("Power", powerEntry.powerConsumption))
                                .foregroundStyle(.yellow)
                                .symbolSize(100)
                        }
                        if let timeEntry = findClosest(to: selectedDate, in: timeData) {
                            PointMark(x: .value("Time", timeEntry.timestamp), y: .value("Time", Double(timeEntry.timeRemainingMinutes) / 60.0))
                                .foregroundStyle(.mint)
                                .symbolSize(100)
                        }

                        RuleMark(x: .value("Selected", selectedDate))
                            .foregroundStyle(.white.opacity(0.2))
                            .annotation(position: .top, alignment: .center) {
                                annotationView(for: selectedDate, powerData: powerData, timeData: timeData)
                            }
                    }
                }
                .chartForegroundStyleScale(["Power (W)": .yellow, "Time (h)": .mint])
                .dynamicXAxis(for: selectedTimeRange, isVisible: isHovered)
                .chartYAxis { if isHovered { AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) } }
                .frame(height: 120)
            }

            Spacer()
        }
        .frame(height: 180)
        .modifier(SettingsContainerModifier())
        .onHover { hovering in withAnimation(.easeInOut) { self.isHovered = hovering } }
    }

    @ViewBuilder
    private func annotationView(for date: Date, powerData: [BatteryLogEntry], timeData: [BatteryLogEntry]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if let powerEntry = findClosest(to: date, in: powerData) {
                Text(String(format: "%.2f W", powerEntry.powerConsumption))
                    .font(.caption)
                    .foregroundColor(.yellow)
            }
            if let timeEntry = findClosest(to: date, in: timeData) {
                Text(String(format: "%.1f h", Double(timeEntry.timeRemainingMinutes) / 60.0))
                    .font(.caption)
                    .foregroundColor(.mint)
            }
        }
        .padding(4)
        .background(.background)
        .cornerRadius(4)
    }

    private func chartInteraction(proxy: ChartProxy, chartData: [BatteryLogEntry]) -> some View {
        GeometryReader { geometry in
            Rectangle().fill(.clear).contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location):
                        let plotAreaStart = geometry.size.width * 0.05
                        let plotAreaWidth = geometry.size.width * 0.90

                        guard location.x >= plotAreaStart && location.x <= plotAreaStart + plotAreaWidth else {
                            self.selectedDate = nil
                            return
                        }

                        if let date: Date = proxy.value(atX: location.x) {
                            self.selectedDate = date
                        }
                    case .ended:
                        self.selectedDate = nil
                    }
                }
        }
    }

    private func findClosest(to date: Date, in data: [BatteryLogEntry]) -> BatteryLogEntry? {
        data.min(by: { abs($0.timestamp.timeIntervalSince(date)) < abs($1.timestamp.timeIntervalSince(date)) })
    }
}

fileprivate struct BatteryStateSegment: Identifiable {
    let id = UUID()
    var state: State
    var startDate: Date
    var endDate: Date

    enum State {
        case charging, inhibited, lowBattery, normal

        var color: Color {
            switch self {
            case .charging: .green
            case .inhibited: .blue
            case .lowBattery: .red
            case .normal: .clear
            }
        }
    }
}

struct BatteryHistoryView: View {
    @ObservedObject var historyViewModel: BatteryHistoryViewModel
    @State private var selectedEntry: BatteryLogEntry?
    @State private var hoveredEntry: BatteryLogEntry?
    @State private var showDetailPopover = false

    @State private var popoverAnchor: CGPoint = .zero
    @State private var hoverAnchor: CGPoint = .zero

    private var stateSegments: [BatteryStateSegment] {
        guard !historyViewModel.chartData.isEmpty else { return [] }

        var segments: [BatteryStateSegment] = []
        var currentSegment: BatteryStateSegment?

        for i in 0..<historyViewModel.chartData.count {
            let entry = historyViewModel.chartData[i]
            let currentState: BatteryStateSegment.State

            if entry.isCharging && entry.isPluggedIn {
                currentState = .charging
            } else if entry.isPluggedIn && !entry.isCharging {
                currentState = .inhibited
            } else if entry.charge <= 20 && !entry.isPluggedIn {
                currentState = .lowBattery
            } else {
                currentState = .normal
            }

            if var segment = currentSegment {
                if segment.state == currentState {
                    let nextDate = (i + 1 < historyViewModel.chartData.count) ? historyViewModel.chartData[i+1].timestamp : entry.timestamp
                    currentSegment?.endDate = nextDate
                } else {
                    segments.append(segment)
                    currentSegment = BatteryStateSegment(state: currentState, startDate: entry.timestamp, endDate: entry.timestamp)
                }
            } else {
                currentSegment = BatteryStateSegment(state: currentState, startDate: entry.timestamp, endDate: entry.timestamp)
            }
        }

        if let segment = currentSegment {
            segments.append(segment)
        }

        return segments
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Battery Usage History")
                        .font(.system(size: 24, weight: .bold, design: .rounded))

                    if !historyViewModel.chartData.isEmpty {
                        Text("\(historyViewModel.chartData.count) data points")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                if let minCharge = historyViewModel.chartData.map({ $0.charge }).min(),
                   let maxCharge = historyViewModel.chartData.map({ $0.charge }).max() {
                    HStack(spacing: 16) {
                        StatPill(label: "Min", value: "\(minCharge)%", color: .orange)
                        StatPill(label: "Max", value: "\(maxCharge)%", color: .green)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 16)

            if historyViewModel.isLoading {
                ProgressView()
                    .frame(height: 280, alignment: .center)
                    .frame(maxWidth: .infinity)
            } else if historyViewModel.chartData.isEmpty {
                EmptyHistoryView()
            } else {
                ZStack {
                    chartView
                        .frame(height: 280)

                    if let entry = hoveredEntry, selectedEntry == nil {
                        HoverAnnotationView(entry: entry)
                            .position(x: hoverAnchor.x, y: hoverAnchor.y - 25)
                            .allowsHitTesting(false)
                    }
                }
                .popover(isPresented: $showDetailPopover, attachmentAnchor: .point(.top), arrowEdge: .top) {
                    if let entry = selectedEntry {
                        DataPointDetailView(entry: entry, onDismiss: {
                            showDetailPopover = false
                            selectedEntry = nil
                        })
                    }
                }
            }
        }
        .modifier(SettingsContainerModifier())
    }

    private func findClosestEntry(to date: Date, in data: [BatteryLogEntry]) -> BatteryLogEntry? {
        guard !data.isEmpty else { return nil }

        return data.min { entry1, entry2 in
            abs(entry1.timestamp.timeIntervalSince(date)) < abs(entry2.timestamp.timeIntervalSince(date))
        }
    }

    private var chartView: some View {
        Chart {
            ForEach(stateSegments) { segment in
                if segment.state != .normal {
                    RectangleMark(
                        xStart: .value("Start", segment.startDate),
                        xEnd: .value("End", segment.endDate),
                        yStart: .value("Bottom", 0),
                        yEnd: .value("Top", 100)
                    )
                    .foregroundStyle(segment.state.color.opacity(0.15))
                }
            }

            ForEach(historyViewModel.chartData) { entry in
                AreaMark(
                    x: .value("Time", entry.timestamp),
                    y: .value("Charge", entry.charge)
                )
                .foregroundStyle(LinearGradient(colors: [.cyan.opacity(0.2), .clear], startPoint: .top, endPoint: .bottom))

                LineMark(
                    x: .value("Time", entry.timestamp),
                    y: .value("Charge", entry.charge)
                )
                .foregroundStyle(Color.cyan)
                .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            }

            if let entry = hoveredEntry, selectedEntry == nil {
                PointMark(
                    x: .value("Time", entry.timestamp),
                    y: .value("Charge", entry.charge)
                )
                .foregroundStyle(entry.isCharging ? Color.green : Color.cyan)
                .symbolSize(100)
                .annotation(position: .overlay) {
                    Circle().stroke(Color.white.opacity(0.5), lineWidth: 2).frame(width: 15, height: 15)
                }
            }

            if let entry = selectedEntry {
                PointMark(
                    x: .value("Time", entry.timestamp),
                    y: .value("Charge", entry.charge)
                )
                .foregroundStyle(Color.white)
                .symbolSize(150)
                .annotation(position: .overlay) {
                    Circle().stroke(Color.cyan, lineWidth: 3).frame(width: 20, height: 20)
                }
            }
        }
        .chartYScale(domain: 0...100)
        .chartYAxis {
            AxisMarks(position: .leading, values: [0, 25, 50, 75, 100]) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4, 4])).foregroundStyle(.white.opacity(0.15))
                AxisValueLabel {
                    if let intValue = value.as(Int.self) { Text("\(intValue)%").font(.system(size: 12, weight: .semibold)).foregroundColor(.secondary) }
                }
            }
        }
        .chartXAxis {
            AxisMarks(position: .bottom, values: .automatic(desiredCount: 6)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(.white.opacity(0.08))
                AxisValueLabel {
                    if let date = value.as(Date.self) { Text(date, style: .time).font(.system(size: 11, weight: .medium)).foregroundColor(.secondary) }
                }
            }
        }
        .chartOverlay { proxy in
            chartInteraction(proxy: proxy)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
    }

    private func chartInteraction(proxy: ChartProxy) -> some View {
        GeometryReader { geometry in
            Rectangle()
                .fill(.clear)
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location):
                        let plotAreaFrame = geometry[proxy.plotAreaFrame]
                        if plotAreaFrame.contains(location) {
                            let translatedX = location.x - plotAreaFrame.minX
                            if let date: Date = proxy.value(atX: translatedX),
                               let entry = findClosestEntry(to: date, in: historyViewModel.chartData) {
                                hoveredEntry = entry
                                if let xPos = proxy.position(forX: entry.timestamp), let yPos = proxy.position(forY: entry.charge) {
                                    hoverAnchor = CGPoint(x: plotAreaFrame.minX + xPos, y: plotAreaFrame.minY + yPos)
                                }
                            }
                        } else {
                            if selectedEntry == nil { hoveredEntry = nil }
                        }
                    case .ended:
                        if selectedEntry == nil { hoveredEntry = nil }
                    }
                }
                .onTapGesture { location in
                    let plotAreaFrame = geometry[proxy.plotAreaFrame]
                    if plotAreaFrame.contains(location) {
                        let translatedX = location.x - plotAreaFrame.minX
                        if let date: Date = proxy.value(atX: translatedX),
                           let entry = findClosestEntry(to: date, in: historyViewModel.chartData) {
                            selectedEntry = entry
                            hoveredEntry = nil
                            showDetailPopover = true
                        }
                    }
                }
        }
    }
}
struct HoverAnnotationView: View {
    let entry: BatteryLogEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.timestamp, style: .time)
                .font(.caption.bold())

            HStack(spacing: 4) {
                Image(systemName: entry.isCharging ? "bolt.fill" : "battery.100")
                    .foregroundColor(entry.isCharging ? .green : .cyan)
                    .font(.caption2)

                Text("\(entry.charge)%")
                    .font(.headline.bold())
            }

            if entry.powerConsumption > 0 {
                Text(String(format: "%.1f W", entry.powerConsumption))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.2), radius: 5, y: 2)
        )
    }
}

struct StatPill: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)

            Text(value)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(color)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(color.opacity(0.15))
        .cornerRadius(12)
    }
}

struct EmptyHistoryView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.line.downtrend.xyaxis")
                .font(.system(size: 48))
                .foregroundColor(.secondary.opacity(0.5))

            Text("No History Data")
                .font(.headline)
                .foregroundColor(.secondary)

            Text("Battery usage data will appear here once collected")
                .font(.caption)
                .foregroundColor(.secondary.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .frame(height: 280)
        .frame(maxWidth: .infinity)
    }
}

struct DataPointDetailView: View {
    let entry: BatteryLogEntry
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.timestamp, style: .date)
                        .font(.system(size: 14, weight: .semibold))
                    Text(entry.timestamp, style: .time)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: 20))
                }
                .buttonStyle(.plain)
            }
            .padding(16)
            .background(Color.primary.opacity(0.03))

            ScrollView {
                VStack(spacing: 16) {
                    DetailSection(title: "Battery Status") {
                        DetailRow(
                            icon: "battery.100",
                            label: "Charge Level",
                            value: "\(entry.charge)%",
                            color: entry.charge > 20 ? .green : .orange
                        )

                        DetailRow(
                            icon: "battery.100",
                            label: "Hardware Charge",
                            value: "\(entry.hardwareCharge)%",
                            color: entry.hardwareCharge > 20 ? .green : .orange
                        )

                        DetailRow(
                            icon: entry.isCharging ? "bolt.fill" : "powerplug",
                            label: "Charging Status",
                            value: entry.isCharging ? "Charging" : "Discharging",
                            color: entry.isCharging ? .green : .blue
                        )

                        DetailRow(
                            icon: "powerplug.fill",
                            label: "Power Adapter",
                            value: entry.isPluggedIn ? "Connected" : "Disconnected",
                            color: entry.isPluggedIn ? .green : .gray
                        )

                        if entry.timeRemainingMinutes > 0 {
                            let hours = entry.timeRemainingMinutes / 60
                            let minutes = entry.timeRemainingMinutes % 60
                            DetailRow(
                                icon: "clock",
                                label: entry.isCharging ? "Time to Full" : "Time Remaining",
                                value: hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m",
                                color: .cyan
                            )
                        }
                    }

                    DetailSection(title: "Power Information") {
                        if entry.powerConsumption > 0 {
                            DetailRow(
                                icon: "bolt.circle",
                                label: "Power Consumption",
                                value: String(format: "%.2f W", entry.powerConsumption),
                                color: .yellow
                            )
                        }

                        DetailRow(
                            icon: "gauge.with.dots.needle.bottom.50percent",
                            label: "Management State",
                            value: managementStateString(entry.managementState),
                            color: managementStateColor(entry.managementState)
                        )

                        DetailRow(
                            icon: "lightbulb.fill",
                            label: "LED Color",
                            value: ledColorString(entry.ledColor),
                            color: ledColorSwiftUI(entry.ledColor)
                        )
                    }

                    DetailSection(title: "Battery Health") {
                        DetailRow(
                            icon: "heart.fill",
                            label: "Max Capacity",
                            value: "\(entry.maxCapacity) mAh",
                            color: .pink
                        )

                        DetailRow(
                            icon: "arrow.clockwise",
                            label: "Cycle Count",
                            value: "\(entry.cycleCount)",
                            color: .cyan
                        )

                        DetailRow(
                            icon: "thermometer.medium",
                            label: "Temperature",
                            value: String(format: "%.1f °C", entry.temperature),
                            color: entry.temperature > 40 ? .red : (entry.temperature > 35 ? .orange : .green)
                        )
                    }

                    DetailSection(title: "System State") {
                        DetailRow(
                            icon: entry.isScreenOn ? "display" : "display.slash",
                            label: "Screen",
                            value: entry.isScreenOn ? "On" : "Off",
                            color: entry.isScreenOn ? .green : .gray
                        )

                        DetailRow(
                            icon: entry.isSleeping ? "moon.fill" : "sun.max.fill",
                            label: "System",
                            value: entry.isSleeping ? "Sleeping" : "Awake",
                            color: entry.isSleeping ? .purple : .yellow
                        )

                        DetailRow(
                            icon: "leaf.fill",
                            label: "Low Power Mode",
                            value: entry.isLowPowerMode ? "Enabled" : "Disabled",
                            color: entry.isLowPowerMode ? .green : .gray
                        )
                    }
                }
                .padding(16)
            }
        }
        .frame(width: 340, height: 550)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(12)
    }

    private func managementStateString(_ state: ManagementState) -> String {
        switch state {
        case .heatProtection: return "Heat Protection"
        case .sailing: return "Sailing"
        case .calibrating: return "Calibrating"
        case .discharging: return "Force Discharging"
        case .inhibited: return "Charging Paused"
        default: return "None"
        }
    }

    private func managementStateColor(_ state: ManagementState) -> Color {
        switch state {
        case .heatProtection: return .red
        case .sailing: return .blue
        case .calibrating: return .purple
        case .discharging: return .orange
        case .inhibited: return .cyan
        default: return .green
        }
    }

    private func ledColorString(_ color: Int) -> String {
        switch color {
        case 0: return "Off"
        case 1: return "Green"
        case 2: return "Amber"
        case 3: return "Orange"
        default: return "Unknown"
        }
    }

    private func ledColorSwiftUI(_ color: Int) -> Color {
        switch color {
        case 0: return .gray
        case 1: return .green
        case 2: return .yellow
        case 3: return .orange
        default: return .gray
        }
    }
}

struct DetailSection<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.secondary)
                .textCase(.uppercase)

            VStack(spacing: 8) {
                content
            }
            .padding(12)
            .background(Color.primary.opacity(0.03))
            .cornerRadius(8)
        }
    }
}

struct DetailRow: View {
    let icon: String
    let label: String
    let value: String
    let color: Color

    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(color)
                .frame(width: 24)

            Text(label)
                .font(.system(size: 13))
                .foregroundColor(.secondary)

            Spacer()

            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(.primary)
        }
    }
}

struct BatteryHealthCard: View {
    @ObservedObject var viewModel: BatteryStatsViewModel
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack { Image(systemName: "heart.fill"); Text("Battery Health") }.font(.headline)
            Spacer()
            SpecRow(label: "Design Capacity", value: "\(viewModel.designCapacity) mAh", percentage: "100%")
            SpecRow(label: "Maximum Capacity", value: "\(viewModel.maxCapacity) mAh", percentage: "\(viewModel.maxCapacityPercentage)%")
            SpecRow(label: "macOS Capacity", value: "\(viewModel.appleMaxCapacity) mAh", percentage: "\(viewModel.appleMaxCapacityPercentage)%")
            SpecRow(label: "macOS Condition", value: viewModel.health)
            SpecRow(label: "Cycle Count", value: "\(viewModel.cycleCount)")
            Spacer()
        }
        .padding().frame(height: 180).modifier(SettingsContainerModifier())
    }
}

struct PowerAdapterSpecsCard: View {
    @ObservedObject var viewModel: BatteryStatsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "powerplug.fill")
                    .foregroundColor(.gray)
                Text("Power Adapter Specs")
                    .font(.headline)
            }

            Spacer()

            if let info = viewModel.powerAdapterInfo, info.maxPower > 0 {
                if info.current > 0 || info.maxCurrent > 0 {
                    PowerAdapterSpecRow(
                        label: "Current",
                        currentValue: info.current > 0 ? "\(Double(info.current) / 1000.0, default: "%.2f") A" : "0.0 A",
                        maxValue: info.maxCurrent > 0 ? "\(Double(info.maxCurrent) / 1000.0, default: "%.1f") A" : "N/A"
                    )
                }

                if info.voltage > 0 || info.maxVoltage > 0 {
                    PowerAdapterSpecRow(
                        label: "Voltage",
                        currentValue: info.voltage > 0 ? "\(Double(info.voltage) / 1000.0, default: "%.1f") V" : "0.0 V",
                        maxValue: info.maxVoltage > 0 ? "\(Double(info.maxVoltage) / 1000.0, default: "%.1f") V" : "N/A"
                    )
                }

                PowerAdapterSpecRow(
                    label: "Power",
                    currentValue: "\(Double(info.power), default: "%.1f") W",
                    maxValue: "\(info.maxPower) W"
                )

                if !info.name.isEmpty && info.name != "N/A" {
                    SpecRow(label: "Name", value: info.name)
                }

                if !info.manufacturer.isEmpty && info.manufacturer != "N/A" {
                    SpecRow(label: "Manufacturer", value: info.manufacturer)
                }

                if !info.serialNumber.isEmpty && info.serialNumber != "N/A" {
                    SpecRow(label: "Serial Number", value: info.serialNumber)
                }
            } else {
                Text("Not Connected")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }

            Spacer()
        }
        .padding()
        .frame(height: 180)
        .modifier(SettingsContainerModifier())
    }
}

fileprivate struct PowerAdapterSpecRow: View {
    let label: String
    let currentValue: String
    let maxValue: String

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            Spacer()
            HStack(spacing: 4) {
                Text(currentValue)
                    .font(.system(size: 12))
                    .fontWeight(.medium)
                    .lineLimit(1)
                Text("of")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Text(maxValue)
                    .font(.system(size: 12))
                    .fontWeight(.medium)
                    .lineLimit(1)
            }
        }
    }
}

struct SignificantEnergyUsersView: View {
    @ObservedObject var viewModel: EnergyViewModel
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Significant Energy Users").font(.subheadline.bold())
            Spacer()
            if viewModel.topProcesses.isEmpty {
                Text("No Apps Using Significant Energy")
                    .font(.caption).foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                ForEach(viewModel.topProcesses) { process in
                    HStack {
                        Text(process.name).font(.caption)
                        Spacer()
                        Text(String(format: "%.2f%%", process.usage)).font(.caption.weight(.semibold))
                    }
                }
            }
            Spacer()
        }
        .padding().frame(height: 180).modifier(SettingsContainerModifier())
    }
}
struct EmptyStatsView: View {
    var height: CGFloat
    var body: some View {
        VStack {
            Image(systemName: "chart.bar.xaxis").font(.largeTitle).foregroundColor(.secondary.opacity(0.3))
            Text("No History Yet").font(.caption).foregroundColor(.secondary)
        }
        .frame(height: height).frame(maxWidth: .infinity)
    }
}

struct ModernBatteryHealthCard: View {
    @ObservedObject var viewModel: BatteryStatsViewModel
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "heart.fill").foregroundColor(.pink)
                Text("Battery Health").font(.headline)
            }
            Spacer()
            HealthStatRow(label: "Design Capacity", value: "\(viewModel.designCapacity) mAh", percentage: 100)
            HealthStatRow(label: "Maximum Capacity", value: "\(viewModel.maxCapacity) mAh", percentage: viewModel.maxCapacityPercentage)
            HealthStatRow(label: "macOS Capacity", value: "\(viewModel.appleMaxCapacity) mAh", percentage: viewModel.appleMaxCapacityPercentage)
            SimpleHealthStatRow(label: "Condition", value: viewModel.health)
            Spacer()
        }
        .padding(16).frame(height: 180).modifier(SettingsContainerModifier())
    }
}

struct HealthStatRow: View {
    let label: String, value: String, percentage: Int
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(.caption).foregroundColor(.secondary)
            Spacer()
            Text(value).font(.caption.weight(.semibold)).multilineTextAlignment(.trailing)
            Text("\(percentage)%").font(.caption.weight(.semibold)).frame(width: 35, alignment: .trailing)
        }
    }
}
struct SimpleHealthStatRow: View {
    let label: String, value: String
    var body: some View {
        HStack {
            Text(label).font(.caption).foregroundColor(.secondary)
            Spacer()
            Text(value).font(.caption.weight(.semibold))
        }
    }
}

struct ModernPowerAdapterCard: View {
    @ObservedObject var viewModel: BatteryStatsViewModel
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "powerplug.fill").foregroundColor(.gray)
                Text("Power Adapter").font(.headline)
            }
            Spacer()
            if let adapterInfo = viewModel.powerAdapterInfo, adapterInfo.power > 0 {
                HStack {
                    Text("Connected:").font(.caption).foregroundColor(.secondary)
                    Spacer()
                    Text("\(adapterInfo.power) W").font(.caption.weight(.semibold))
                }
            } else {
                Text("Not Connected").font(.caption).foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(16).frame(height: 180).modifier(SettingsContainerModifier())
    }
}

struct ModernLivePowerCard: View {
    @ObservedObject var viewModel: BatteryStatsViewModel
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "bolt.fill").foregroundColor(.yellow)
                Text("Live Power").font(.headline)
            }
            Spacer()
            PowerRow(label: "Status", value: viewModel.isCharging ? "Charging" : "Discharging", color: viewModel.isCharging ? .green : .orange)
            PowerRow(label: "Time Remaining", value: viewModel.timeRemaining, color: .cyan)
            PowerRow(label: "Power Usage", value: String(format: "%.2f W", abs(viewModel.powerConsumption)), color: .yellow)
            Spacer()
        }
        .padding(16).frame(height: 180).modifier(SettingsContainerModifier())
    }
}

struct PowerRow: View {
    let label: String, value: String, color: Color?
    var body: some View {
        HStack {
            Text(label).font(.caption).foregroundColor(.secondary)
            Spacer()
            Text(value).font(.caption.weight(.semibold)).foregroundColor(color ?? .primary)
        }
    }
}

struct BatteryConfigurationView: View {
    @EnvironmentObject var settings: SettingsModel
    @EnvironmentObject var powerStateController: PowerStateController
    @StateObject private var helperManager = HelperManager.shared
    @ObservedObject private var calibrationManager = CalibrationManager.shared
    @State private var showingScheduleSheet = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 15) {
                    switch helperManager.status {
                    case .enabled:
                        Image(systemName: "checkmark.circle.fill").font(.title2).foregroundColor(.green)
                        Text("Helper Installed Successfully")
                            .font(.headline)
                    case .requiresApproval:
                        Image(systemName: "exclamationmark.triangle.fill").font(.title2).foregroundColor(.yellow)
                        VStack(alignment: .leading) {
                            Text("Approval Required")
                                .font(.headline)
                            Text("Please enable in System Settings > Login Items.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    default:
                        Image(systemName: "xmark.circle.fill").font(.title2).foregroundColor(.red)
                        Text("Helper Not Installed")
                            .font(.headline)
                    }

                    Spacer()

                    if helperManager.status != .enabled {
                        Button("Install") {
                            helperManager.installIfNeeded()
                        }
                        .buttonStyle(.bordered)
                        .tint(.accentColor)
                    }
                }
                .padding()
                .background(.black.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color.white.opacity(0.1), lineWidth: 1))

                notificationsSection
                coreFeaturesSection
                automaticDischargeSection
                OneTimeDischargeView()
                chargingAndSleepSection
                schedulingSection
                CalibrationView()
                advancedSection
                FanControlSectionView()
            }
            .padding(.horizontal, 25).padding(.bottom, 25)
        }
        .sheet(isPresented: $showingScheduleSheet) {
            ScheduleView().environmentObject(settings)
        }
    }

    @ViewBuilder private var notificationsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Notifications & Live Activity").font(.headline).padding([.top, .horizontal])
            InfoContainer(text: "Configure alerts for important battery events and customize what's shown in the persistent battery live activity.", iconName: "bell.badge.fill", color: .purple).padding()
            CustomSliderRowView(label: "Notify when battery is below", value: Binding(get: { Double(settings.settings.lowBatteryNotificationPercentage) }, set: { settings.settings.lowBatteryNotificationPercentage = Int($0) }), range: 10...50, specifier: "%.0f %%")
            Divider().padding(.leading, 20)
            ToggleRow(title: "Play Sound for Low Battery Alert", description: "Get an audible alert when your battery is running low.", isOn: $settings.settings.lowBatteryNotificationSoundEnabled)
            Divider().padding(.leading, 20)
            ToggleRow(title: "Prompt to Turn on Low Power Mode", description: "Show a convenient button to enable Low Power Mode when your battery gets low.", isOn: $settings.settings.promptForLowPowerMode)
            Divider().padding(.leading, 20)
            ToggleRow(title: "Show Estimated Time Remaining", description: "Display the estimated time to full (when charging) or time to empty (when on battery) in the live activity.", isOn: $settings.settings.showEstimatedBatteryTime)
        }.modifier(SettingsContainerModifier())
    }

    @ViewBuilder private var coreFeaturesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Battery Management Features").font(.headline).padding([.top, .horizontal])
            CustomSliderRowView(label: "Charge Limit", value: Binding(get: { Double(settings.settings.batteryChargeLimit) }, set: { settings.settings.batteryChargeLimit = Int($0) }), range: 50...100, specifier: "%.0f %%")
            Divider().padding(.leading, 20)
            ToggleRow(title: "Sailing Mode", description: "Prevents battery wear from constant micro-charging cycles when plugged in for long periods. Charging will pause at the limit and only resume when the battery drops by a set amount.", isOn: $settings.settings.sailingModeEnabled)
            if settings.settings.sailingModeEnabled {
                 CustomSliderRowView(label: "Resume charging below", value: Binding(get: { Double(settings.settings.sailingModeLowerLimit) }, set: { settings.settings.sailingModeLowerLimit = Int($0) }), range: 5...20, specifier: "%.0f%% below limit")
            }
            Divider().padding(.leading, 20)
            ToggleRow(title: "Heat Protection", description: "Automatically pauses charging if the battery temperature gets too high to prevent heat-related damage and extend its lifespan.", isOn: $settings.settings.heatProtectionEnabled)
            if settings.settings.heatProtectionEnabled {
                 CustomSliderRowView(label: "Pause charging above", value: $settings.settings.heatProtectionThreshold, range: 35...50, specifier: "%.0f °C")
            }
        }
        .modifier(SettingsContainerModifier()).animation(.default, value: settings.settings.sailingModeEnabled || settings.settings.heatProtectionEnabled)
    }

    @ViewBuilder private var automaticDischargeSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Automatic Discharge").font(.headline).padding([.top, .horizontal])
            ToggleRow(
                title: "Enable Automatic Discharge",
                description: "When enabled, your Mac will stop using AC power and run from its battery until the battery limit is reached.",
                isOn: $settings.settings.dischargeToLimitEnabled
            )
        }.modifier(SettingsContainerModifier())
    }

    @ViewBuilder private var chargingAndSleepSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Charging & Sleep").font(.headline).padding([.top, .horizontal])
            InfoContainer(text: "Although functionality is in place to keep the battery management functinal even when the device is sleeping it may not always work. Use these settings if you want to be certain of the behaviour when the device is sleeping.", iconName: "info.circle", color: .yellow).padding()
            ToggleRow(title: "Stop charging when sleeping", description: "Prevents your Mac from sitting at 100% charge overnight, which can degrade the battery over time. Charging resumes on wake.", isOn: $settings.settings.stopChargingWhenSleeping)
            Divider().padding(.leading, 20)
            ToggleRow(title: "Stop charging when app closed", description: "The helper tool ensures your charging rules are still applied even if the Sapphire app isn't running.", isOn: .constant(true)).disabled(true)
            Divider().padding(.leading, 20)
            ToggleRow(title: "Disable Sleep until Charge Limit", description: "Keeps your Mac awake to ensure it reaches the charge limit, useful for 'top-up' schedules before you need to leave.", isOn: $settings.settings.disableSleepUntilChargeLimit)
        }.modifier(SettingsContainerModifier())
    }

    @ViewBuilder private var schedulingSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Scheduling").font(.headline).padding([.top, .horizontal])
            InfoContainer(text: "Automate charging behaviors and perform manual or scheduled calibrations to keep your battery's readings accurate.", iconName: "calendar.badge.clock", color: .cyan).padding()
            Divider().padding(.horizontal)
            HStack {
                Text("Manage Schedule").font(.subheadline.bold())
                Spacer()
                Button("Open Scheduler") { showingScheduleSheet = true }.buttonStyle(.bordered)
            }.padding()
        }.modifier(SettingsContainerModifier())
    }

    @ViewBuilder private var advancedSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Advanced").font(.headline).padding([.top, .horizontal])
            ToggleRow(title: "Use Hardware Battery Percentage", description: "Reads the 'true' charge from the battery controller, which can be more accurate but may differ from what macOS shows.", isOn: $settings.settings.useHardwareBatteryPercentage)
        }.modifier(SettingsContainerModifier())
    }
}

struct OneTimeDischargeView: View {
    @StateObject private var settings = SettingsModel.shared
    @StateObject private var batteryMonitor = BatteryMonitor.shared

    private var dischargeProgress: Double {
        guard let currentCharge = batteryMonitor.currentState?.level else { return 0 }

        let targetCharge = Double(settings.settings.oneTimeDischargeTarget)
        let initialCharge = 100.0

        let totalRange = initialCharge - targetCharge
        guard totalRange > 0 else { return 1.0 }

        let dischargedAmount = initialCharge - Double(currentCharge)
        let progress = dischargedAmount / totalRange

        return max(0.0, min(1.0, progress))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("One-Time Discharge").font(.headline).padding([.top, .horizontal])
            InfoContainer(
                text: "Temporarily discharge to a specific percentage. This will not affect your main charge limit or automatic discharge settings.",
                iconName: "target",
                color: .blue
            ).padding()

            if settings.settings.oneTimeDischargeEnabled {
                VStack(spacing: 12) {
                    Text("Discharging to \(settings.settings.oneTimeDischargeTarget)%...")
                        .font(.headline)
                        .foregroundColor(.secondary)

                    ProgressView(value: dischargeProgress)
                        .progressViewStyle(.linear)
                        .tint(.blue)

                    if let currentCharge = batteryMonitor.currentState?.level {
                        Text("Current: \(currentCharge)%")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Button("Stop", role: .destructive) {
                        settings.settings.oneTimeDischargeEnabled = false
                    }
                    .buttonStyle(.bordered)
                    .padding(.top, 5)
                }
                .padding(.horizontal)
                .padding(.bottom)
                .frame(minHeight: 120)

            } else {
                VStack(spacing: 15) {
                    Stepper(
                        "Discharge Target: \(settings.settings.oneTimeDischargeTarget)%",
                        value: $settings.settings.oneTimeDischargeTarget,
                        in: 1...95,
                        step: 5
                    )

                    Button(action: {
                        settings.settings.oneTimeDischargeEnabled = true
                    }) {
                        Text("Start One-Time Discharge")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                }
                .padding(.horizontal)
                .padding(.bottom)
                .frame(minHeight: 120)
            }
        }
        .modifier(SettingsContainerModifier())
    }
}

fileprivate struct StatView: View {
    let value: String, label: String, color: Color
    var body: some View {
        VStack {
            Text(value).font(.system(.title3, design: .rounded).bold()).foregroundColor(color)
            Text(label).font(.caption).foregroundColor(.secondary)
        }.frame(maxWidth: .infinity)
    }
}

fileprivate struct InfoColumn: View {
    let title: String, value: String, color: Color, icon: String
    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(color)
                .frame(width: 15, alignment: .center)

            VStack(alignment: .leading) {
                Text(title).font(.caption2).foregroundColor(.secondary)
                Text(value).font(.subheadline.bold()).foregroundColor(color)
            }
        }
        .frame(minWidth: 100, alignment: .leading)
    }
}

fileprivate extension TimeInterval {
    func formatted() -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: self) ?? "0m"
    }
}

fileprivate struct CalibrationStepView: View {
    let icon: String, label: String
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.title).foregroundColor(.accentColor).symbolRenderingMode(.hierarchical)
            Text(label).font(.caption).multilineTextAlignment(.center).frame(height: 30)
        }.frame(width: 80)
    }
}

struct ScheduleView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var settings: SettingsModel
    @ObservedObject private var scheduleManager = ScheduleManager.shared
    @State private var showingAddTask = false

    var body: some View {
        VStack(spacing: 20) {
            Text("Schedule Automation").font(.largeTitle.bold())

            VStack {
                HStack {
                    Text("Scheduled Tasks").font(.headline)
                    Spacer()
                    Button(action: { showingAddTask = true }) { Image(systemName: "plus") }
                }.padding([.horizontal, .top])

                if settings.settings.scheduledTasks.isEmpty {
                    Text("No tasks scheduled.").foregroundColor(.secondary).padding()
                } else {
                    List {
                        ForEach($settings.settings.scheduledTasks) { $task in
                            TaskRowView(task: $task).listRowBackground(Color.clear)
                        }.onDelete { indexSet in settings.settings.scheduledTasks.remove(atOffsets: indexSet) }
                    }.listStyle(.plain).background(Color.clear)
                }
            }.modifier(SettingsContainerModifier())

            VStack(alignment: .leading) {
                 Text("Task History").font(.headline).padding([.horizontal, .top])
                 List(scheduleManager.taskHistory) { event in
                     HStack {
                         Text(event.taskDescription); Spacer(); Text(event.timestamp, style: .time)
                     }.listRowBackground(Color.clear)
                 }.listStyle(.plain).background(Color.clear)
            }.modifier(SettingsContainerModifier())

            Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
        }
        .padding(30).frame(minWidth: 500, minHeight: 600)
        .sheet(isPresented: $showingAddTask) {
            AddTaskView().environmentObject(settings)
        }
    }
}

struct TaskRowView: View {
    @Binding var task: ScheduledTask

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(task.action.displayName).font(.headline)

                switch task.action {
                case .setChargeLimit, .dischargeTo:
                    Text("Target: \(task.chargeLimit)% | Repeats: \(task.repeatInterval.displayName) at \(task.startTime, style: .time)")
                        .font(.caption).foregroundColor(.secondary)
                case .setFanConstant:
                    Text("Speed: \(task.fanSpeed) RPM | Repeats: \(task.repeatInterval.displayName) at \(task.startTime, style: .time)")
                        .font(.caption).foregroundColor(.secondary)
                case .setFanSensorBased:
                    Text("Sensor: \(SensorNameMap.name(for: task.sensorKey)) (\(task.minTemp)°C-\(task.maxTemp)°C) | Repeats: \(task.repeatInterval.displayName) at \(task.startTime, style: .time)")
                        .font(.caption).foregroundColor(.secondary)
                default:
                    Text("Repeats: \(task.repeatInterval.displayName) at \(task.startTime, style: .time)")
                        .font(.caption).foregroundColor(.secondary)
                }
            }
            Spacer()
            Toggle("", isOn: $task.isActive).labelsHidden()
        }
    }
}

struct AddTaskView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var settings: SettingsModel
    @ObservedObject private var fanManager = FanManager.shared
    @State private var newTask = ScheduledTask()

    private var firstFan: FanInfo? { fanManager.fans.first }

    var body: some View {
        VStack(spacing: 20) {
            Text("New Scheduled Task").font(.title.bold())

            VStack(spacing: 15) {
                Picker("Action:", selection: $newTask.action) {
                    ForEach(TaskAction.allCases) { Text($0.displayName).tag($0) }
                }
                .onChange(of: newTask.action) {
                    if newTask.action == .setFanSensorBased, newTask.sensorKey.isEmpty {
                        newTask.sensorKey = fanManager.sensors.first?.key ?? ""
                    }
                }

                if [.setChargeLimit, .dischargeTo].contains(newTask.action) {
                    CustomSliderRowView(label: "Target Charge", value: Binding(get: { Double(newTask.chargeLimit) }, set: { newTask.chargeLimit = Int($0) }), range: 20...100, specifier: "%.0f%%")
                        .transition(.asymmetric(insertion: .move(edge: .leading).combined(with: .opacity), removal: .move(edge: .trailing).combined(with: .opacity)))
                }

                if newTask.action == .setFanConstant {
                    if let fan = firstFan {
                        CustomSliderRowView(label: "Target Speed", value: Binding(get: { Double(newTask.fanSpeed) }, set: { newTask.fanSpeed = Int($0) }), range: Double(fan.minRPM)...Double(fan.maxRPM), specifier: "%.0f RPM")
                            .transition(.asymmetric(insertion: .move(edge: .leading).combined(with: .opacity), removal: .move(edge: .trailing).combined(with: .opacity)))
                    }
                }

                if newTask.action == .setFanSensorBased {
                    VStack(spacing: 15) {
                        Picker("Based on Sensor:", selection: $newTask.sensorKey) {
                            ForEach(fanManager.sensors) { sensor in
                                Text(sensor.name).tag(sensor.key)
                            }
                        }

                        CustomSliderRowView(label: "Start increasing from:", value: Binding(get: { Double(newTask.minTemp) }, set: { newTask.minTemp = Int($0) }), range: 20...90, specifier: "%.0f °C")

                        CustomSliderRowView(label: "Maximum temperature:", value: Binding(get: { Double(newTask.maxTemp) }, set: { newTask.maxTemp = Int($0) }), range: Double(newTask.minTemp)...100, specifier: "%.0f °C")
                    }
                    .transition(.asymmetric(insertion: .move(edge: .leading).combined(with: .opacity), removal: .move(edge: .trailing).combined(with: .opacity)))
                }

                Picker("Repeat:", selection: $newTask.repeatInterval) {
                    ForEach(RepeatInterval.allCases) { Text($0.displayName).tag($0) }
                }

                DatePicker("Time:", selection: $newTask.startTime, displayedComponents: .hourAndMinute)
            }
            .padding().modifier(SettingsContainerModifier())
            .animation(.default, value: newTask.action)

            HStack {
                Button("Cancel", role: .cancel) { dismiss() }
                Spacer()
                Button("Add Task") {
                    settings.settings.scheduledTasks.append(newTask)
                    dismiss()
                }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(30).frame(width: 450)
    }
}

struct GeminiSettingsView: View {
    @EnvironmentObject var settings: SettingsModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading) {
                Text("Gemini")
                    .font(.largeTitle.bold())
                    .padding(.bottom)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Gemini API Key")
                        .font(.system(size: 14, weight: .medium))

                    SecureField("Enter your API key", text: $settings.settings.geminiApiKey)
                        .textFieldStyle(.plain)
                        .padding(8)
                        .background(Color.black.opacity(0.2))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.2)))
                }
                .padding(25)
                .modifier(SettingsContainerModifier())
            }
            .padding(25)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }
}

struct HUDSettingsView: View {
    @EnvironmentObject var settings: SettingsModel

    private var hudCustomColorBinding: Binding<Color> {
        Binding(
            get: { settings.settings.hudCustomColor?.color ?? .accentColor },
            set: { settings.settings.hudCustomColor = CodableColor(color: $0) }
        )
    }

    private var xdrBrightnessLevelBinding: Binding<Double> {
        Binding(
            get: { Double(settings.settings.xdrBrightnessLevel * 100) },
            set: { settings.settings.xdrBrightnessLevel = Float($0 / 100) }
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("HUD")
                    .font(.largeTitle.bold())
                    .padding(.bottom)

                VStack(spacing: 0) {
                    ToggleRow(
                        title: "Show Spotify Device in HUD",
                        description: "Display a special HUD with the active device name when changing volume while Spotify is active.",
                        isOn: $settings.settings.showSpotifyVolumeHUD
                    )
                    Divider().padding(.leading, 20)
                    ToggleRow(
                        title: "Show Device Icon Instead of Speaker",
                        description: "For devices like HomePods, show a device-specific icon in the volume HUD.",
                        isOn: $settings.settings.volumeHUDShowDeviceIcon
                    )

                    if settings.settings.volumeHUDShowDeviceIcon {
                        ToggleRow(
                            title: "Exclude Built-in Speakers",
                            description: "Only show device icons for external audio devices like AirPods or HomePods.",
                            isOn: $settings.settings.excludeBuiltInSpeakersFromHUDIcon
                        )
                        .padding(.leading, 20)
                        .transition(.opacity)
                    }
                }
                .modifier(SettingsContainerModifier())
                .animation(.default, value: settings.settings.volumeHUDShowDeviceIcon)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Appearance").font(.headline).padding([.horizontal, .top])

                    CustomSliderRowView(label: "HUD Duration", value: $settings.settings.hudDuration, range: 1...10, specifier: "%.1f s")
                    Divider().padding(.horizontal)

                    ToggleRow(title: "Show Percentage", description: "", isOn: $settings.settings.hudShowPercentage)
                    Divider().padding(.horizontal)

                    HStack {
                        Text("HUD Style")
                        Spacer()
                        Picker("", selection: $settings.settings.hudVisualStyle) {
                            ForEach(HUDVisualStyle.allCases) { style in
                                Text(style.id).tag(style)
                            }
                        }
                        .labelsHidden().frame(width: 150)
                    }.padding()

                    if settings.settings.hudVisualStyle == .color {
                        ColorPicker("Custom HUD Color", selection: hudCustomColorBinding)
                            .padding()
                            .transition(.opacity)
                    }
                }
                .modifier(SettingsContainerModifier())
                .animation(.default, value: settings.settings.hudVisualStyle)

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Volume HUD")
                            .font(.headline)
                        Spacer()
                        Toggle("", isOn: $settings.settings.enableVolumeHUD)
                            .labelsHidden().toggleStyle(.switch)
                    }

                    Divider()

                    HStack {
                        Text("View Style")
                        Spacer()
                        Picker("", selection: $settings.settings.volumeHUDStyle) {
                            ForEach(HUDStyle.allCases) { style in
                                Text(style.id).tag(style)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 120)
                    }
                    .disabled(!settings.settings.enableVolumeHUD)
                    .opacity(settings.settings.enableVolumeHUD ? 1.0 : 0.5)

                    Divider()

                    HStack {
                        Text("Sound on Change")
                        Spacer()
                        Toggle("", isOn: $settings.settings.volumeHUDSoundEnabled)
                            .labelsHidden().toggleStyle(.switch)
                    }
                    .disabled(!settings.settings.enableVolumeHUD)
                    .opacity(settings.settings.enableVolumeHUD ? 1.0 : 0.5)

                    Divider()

                    CustomSliderRowView(label: "Slider step", value: Binding(get: { Double(settings.settings.volumesliderstep) }, set: { settings.settings.volumesliderstep = Int($0) }), range: 1...10, specifier: "%.0f")
                        .disabled(!settings.settings.enableVolumeHUD)
                        .opacity(settings.settings.enableVolumeHUD ? 1.0 : 0.5)

                }
                .padding()
                .modifier(SettingsContainerModifier())
                .animation(.easeInOut, value: settings.settings.enableVolumeHUD)

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Brightness HUD")
                            .font(.headline)
                        Spacer()
                        Toggle("", isOn: $settings.settings.enableBrightnessHUD)
                            .labelsHidden().toggleStyle(.switch)
                    }

                    Divider()

                    HStack {
                        Text("View Style")
                        Spacer()
                        Picker("", selection: $settings.settings.brightnessHUDStyle) {
                            ForEach(HUDStyle.allCases) { style in
                                Text(style.id).tag(style)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 120)
                    }
                    .disabled(!settings.settings.enableBrightnessHUD)
                    .opacity(settings.settings.enableBrightnessHUD ? 1.0 : 0.5)

                    Divider()

                    CustomSliderRowView(label: "Slider step", value: Binding(get: { Double(settings.settings.brightnessliderstep) }, set: { settings.settings.brightnessliderstep = Int($0) }), range: 1...10, specifier: "%.0f")
                        .disabled(!settings.settings.enableBrightnessHUD)
                        .opacity(settings.settings.enableBrightnessHUD ? 1.0 : 0.5)

                }
                .padding()
                .modifier(SettingsContainerModifier())
                .animation(.easeInOut, value: settings.settings.enableBrightnessHUD)

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("XDR Brightness")
                            .font(.headline)
                        Spacer()
                        Toggle("", isOn: $settings.settings.enableXDRBrightness)
                            .labelsHidden().toggleStyle(.switch)
                    }

                    Divider()

                    VStack {
                        ToggleRow(
                            title: "XDR Brightness Lock",
                            description: "Require holding the Command (⌘) key to increase the brightness in the XDR range.",
                            isOn: $settings.settings.xdrBrightnessLock
                        )

                        Divider()

                        CustomSliderRowView(
                            label: "Max XDR Brightness",
                            value: xdrBrightnessLevelBinding,
                            range: 100...Double(getDeviceMaxBrightness() * 100),
                            specifier: "%.0f%%"
                        )

                        HStack(alignment: .top) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.yellow)
                                .padding(.top, 4)
                            VStack(alignment: .leading, spacing: 5) {
                                Text("Apple limits brightness to preserve battery life. While this feature is system-controlled and there are no known side-effects, you should use this feature at your own risk.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text("This feature works best on devices with XDR displays (14in and 16in Macbook Pro's and Pro Display XDR). M4 Macbook Pro's already display this behaviour in bright environments like in direct sunlight, this feature will allow you to do it in any type of environment.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.top, 5)
                    }
                    .disabled(!settings.settings.enableXDRBrightness)
                    .opacity(settings.settings.enableXDRBrightness ? 1.0 : 0.5)

                }
                .padding()
                .modifier(SettingsContainerModifier())
                .disabled(!settings.settings.enableBrightnessHUD)
                .opacity(settings.settings.enableBrightnessHUD ? 1.0 : 0.5)
                .animation(.easeInOut, value: settings.settings.enableBrightnessHUD)
                .animation(.easeInOut, value: settings.settings.enableXDRBrightness)

                RequiredPermissionsView(section: .hud)
            }
            .padding(25)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }
}

struct MusicSettingsView: View {
    @EnvironmentObject var settings: SettingsModel
    @ObservedObject var musicManager = MusicManager.shared
    @ObservedObject var spotifyPrivateAPI = SpotifyPrivateAPIManager.shared
    @ObservedObject private var appFetcher = SystemAppFetcher.shared

    @State private var isPrivateApiLoading = false
    @State private var privateApiError: String?

    private var browserApps: [SystemApp] { appFetcher.apps.filter { $0.isBrowser } }
    private var otherApps: [SystemApp] { appFetcher.apps.filter { !$0.isBrowser } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Music").font(.largeTitle.bold()).padding(.bottom)

                VStack(spacing: 0) {
                    HStack {
                        Text("Media Source")
                        Spacer()
                        Picker("", selection: $settings.settings.mediaSource) {
                            ForEach(MediaSource.allCases) { source in Text(source.displayName).tag(source) }
                        }
                        .labelsHidden().frame(width: 180)
                    }.padding()
                    if settings.settings.mediaSource != .system {
                        Divider().padding(.leading, 20)
                        ToggleRow(title: "Prioritize Selected Source", description: "Only show media from your selected source, ignoring others (e.g., web browsers).", isOn: $settings.settings.prioritizeMediaSource)
                    }
                }
                .modifier(SettingsContainerModifier())
                .animation(.default, value: settings.settings.mediaSource)

                VStack(alignment: .leading, spacing: 0) {
                    Text("Gestures").font(.headline).padding([.top, .horizontal])
                    ToggleRow(title: "Swipe Left to Skip", description: "In the music live activity, swipe left on the album art to go to the next track.", isOn: $settings.settings.swipeToSkipMusic)
                    Divider().padding(.leading, 20)
                    ToggleRow(title: "Swipe Right to Rewind", description: "Swipe right on the album art to go to the previous track.", isOn: $settings.settings.swipeToRewindMusic)
                    Divider().padding(.leading, 20)
                    ToggleRow(title: "Invert Swipe Gestures", description: "Swipe right to skip and left to go back.", isOn: $settings.settings.invertMusicGestures)
                    Divider().padding(.leading, 20)
                    ToggleRow(title: "Two-Finger Tap to Play/Pause", description: "Tap the album art with two fingers to toggle playback.", isOn: $settings.settings.twoFingerTapToPauseMusic)
                }
                .modifier(SettingsContainerModifier())

                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("Default Music App")
                        Spacer()
                        Picker("", selection: $settings.settings.defaultMusicPlayer) {
                            Text("Apple Music").tag(DefaultMusicPlayer.appleMusic)
                            Text("Spotify")
                                .tag(DefaultMusicPlayer.spotify)
                                .disabled(!appFetcher.foundBundleIDs.contains("com.spotify.client"))
                        }
                        .labelsHidden()
                        .frame(width: 150)
                    }
                    .padding()
                    Divider().padding(.leading, 20)
                    HStack { Text("Open detailed Music widget on live activity click"); Spacer(); Toggle("", isOn: $settings.settings.musicOpenOnClick).labelsHidden().toggleStyle(.switch) }.padding()
                    Divider().padding(.leading, 20)
                    HStack { Text("Waveform is volume sensitive"); Spacer(); Toggle("", isOn: $settings.settings.musicWaveformIsVolumeSensitive).labelsHidden().toggleStyle(.switch) }.padding()
                    Divider().padding(.leading, 20)
                    Text("Waveform Appearance").font(.headline).padding([.top, .horizontal])
                    ToggleRow(title: "Enable Gradient", description: "Apply a gradient based on the album art to the waveform.", isOn: $settings.settings.waveformUseGradient)
                    Divider().padding(.leading, 20)
                    ToggleRow(title: "Use Static Waveform", description: "Show a non-animating waveform when music is playing.", isOn: $settings.settings.useStaticWaveform)
                    Divider().padding(.leading, 20)
                    CustomSliderRowView(label: "Number of Bars", value: Binding(get: { Double(settings.settings.waveformBarCount) }, set: { settings.settings.waveformBarCount = Int($0) }), range: 3...6, specifier: "%.0f")
                    Divider().padding(.leading, 20)
                    CustomSliderRowView(label: "Bar Thickness", value: $settings.settings.waveformBarThickness, range: 1...5, specifier: "%.0f pt")
                }
                .modifier(SettingsContainerModifier())

                VStack(alignment: .leading, spacing: 10) {
                    Text("Customize Player Buttons").font(.headline).padding([.horizontal, .top])
                    Text("Enable and reorder the buttons that appear in the music player. The first two enabled buttons will appear in the main control bar.").font(.caption).foregroundColor(.secondary).padding(.horizontal).padding(.bottom, 5)
                    ReorderableVStack(items: $settings.settings.musicPlayerButtonOrder) { buttonType in PlayerButtonSettingsRow(buttonType: buttonType) }
                }
                .modifier(SettingsContainerModifier())

                VStack(spacing: 0) {
                    ToggleRow(title: "Enable track info on Hover", description: "Hover over the album art in the live activity to see the song title.", isOn: $settings.settings.enableQuickPeekOnHover)
                    Divider().padding(.leading, 20)
                    ToggleRow(title: "Show track info on Track Change", description: "Briefly show the song title when a new track begins.", isOn: $settings.settings.showQuickPeekOnTrackChange)
                    Divider().padding(.leading, 20)
                    ToggleRow(title: "Show popularity of track in music player", description: "Requires a spotify login", isOn: $settings.settings.showPopularityInMusicPlayer)
                    Divider().padding(.leading, 20)
                    ToggleRow(title: "Prefer airplay over spotify devices", description: "Default to airplay devices when spotify isn't running and spotify is authenticated", isOn: $settings.settings.preferAirPlayOverSpotify)
                }.modifier(SettingsContainerModifier())

                VStack(alignment: .leading, spacing: 10) {
                    Text("Spotify (Private API)").font(.headline).padding([.horizontal, .top])
                    InfoContainer(text: "WARNING: This method uses Spotify’s internal APIs to unlock standard and additional features for both Premium and non-Premium users. Use at your own risk, usage may be subject to Spotify’s Terms of Service.", iconName: "exclamationmark.triangle.fill", color: .yellow).padding(.horizontal)
                    Divider().padding(.horizontal, 20)
                    if musicManager.isPrivateAPIAuthenticated {
                        VStack(spacing: 0) {
                            HStack {
                                Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                                Text("Logged in via Private API")
                                Spacer()
                                Button("Log Out", role: .destructive) { musicManager.spotifyPrivateAPI.logout() }
                            }.padding()

                            Divider().padding(.leading, 20)

                            ToggleRow(title: "Skip Ads", description: "Attempt to automatically skip advertisements. May not always be successful.", isOn: $settings.settings.skipSpotifyAd)
                                .disabled(!musicManager.isPrivateAPIAuthenticated)
                        }
                    } else {
                        VStack(spacing: 12) {
                            if let error = privateApiError {
                                Text(error).font(.caption).foregroundColor(.red)
                            }
                            if isPrivateApiLoading {
                                ProgressView().frame(maxWidth: .infinity, alignment: .center)
                            } else {
                                Button("Log In via Private API") { handlePrivateApiLogin() }
                                    .buttonStyle(.borderedProminent).tint(.accentColor)
                            }
                        }.padding()
                    }
                }
                .modifier(SettingsContainerModifier())
                .animation(.default, value: musicManager.isPrivateAPIAuthenticated)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Spotify (Official API)").font(.headline).padding([.horizontal, .top])
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Spotify API Credentials").font(.system(size: 14, weight: .medium))
                        Text("Register your app at developer.spotify.com and copy these values here. The redirect URI is: sapphire://callback").font(.caption).foregroundColor(.secondary).padding(.bottom, 4)
                        Text("Client ID").font(.system(size: 13, weight: .medium)).foregroundStyle(.white.opacity(0.8))
                        SecureField("Enter your Client ID", text: $settings.settings.spotifyClientId).textFieldStyle(.plain).padding(8).background(Color.black.opacity(0.2)).clipShape(RoundedRectangle(cornerRadius: 8)).overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.2)))
                        Text("Client Secret").font(.system(size: 13, weight: .medium)).foregroundStyle(.white.opacity(0.8)).padding(.top, 5)
                        SecureField("Enter your Client Secret", text: $settings.settings.spotifyClientSecret).textFieldStyle(.plain).padding(8).background(Color.black.opacity(0.2)).clipShape(RoundedRectangle(cornerRadius: 8)).overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.2)))
                    }.padding().padding(.top, 5)
                    Text("Log in here to enable official features like device switching for Premium users. This is the standard, recommended login method.").font(.caption).foregroundColor(.secondary).padding(.horizontal)
                    Divider().padding(.horizontal, 20)
                    HStack {
                        if musicManager.isOfficialAPIAuthenticated, let user = musicManager.spotifyOfficialAPI.userProfile {
                            HStack { Image(systemName: "checkmark.circle.fill").foregroundColor(.green); Text("Logged in as \(user.displayName)") }
                            Spacer()
                            Button("Log Out", role: .destructive) { musicManager.spotifyOfficialAPI.logout() }
                        } else {
                            Text("Not logged in.").foregroundColor(.secondary)
                            Spacer()
                            Button("Log In") { musicManager.spotifyOfficialAPI.login() }
                        }
                    }.padding()
                }
                .modifier(SettingsContainerModifier())

                VStack(alignment: .leading, spacing: 0) {
                    Text("Lyrics").font(.headline).padding([.top, .horizontal])
                    ToggleRow(title: "Show Lyrics in Live Activity", description: "Display synchronized lyrics when available.", isOn: $settings.settings.showLyricsInLiveActivity)
                    if settings.settings.showLyricsInLiveActivity {
                        Divider().padding(.leading, 20)
                        ToggleRow(title: "Enable Translation", description: "Automatically translate non-English lyrics.", isOn: $settings.settings.enableLyricTranslation)
                        HStack {
                            Text("Translate to"); Spacer()
                            Picker("", selection: $settings.settings.lyricTranslationLanguage) { Text("English").tag("en"); Text("Spanish").tag("es"); Text("French").tag("fr") }.labelsHidden().frame(width: 150)
                        }.padding().disabled(!settings.settings.enableLyricTranslation).opacity(settings.settings.enableLyricTranslation ? 1.0 : 0.5)
                    }
                }
                .modifier(SettingsContainerModifier())
                .animation(.default, value: settings.settings.showLyricsInLiveActivity)

                if settings.settings.showLyricsInLiveActivity {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Allow Lyrics From:").font(.headline).padding([.horizontal, .top])
                        ScrollView {
                            VStack(spacing: 0) {
                                Text("Browsers (Disabled by Default)").font(.caption).foregroundStyle(.secondary).padding(.vertical, 5)
                                ForEach(browserApps) { app in SystemAppRowView(app: app, isEnabled: binding(for: app, isBrowser: true)) }
                                Text("Other Apps").font(.caption).foregroundStyle(.secondary).padding(.vertical, 5)
                                ForEach(otherApps) { app in SystemAppRowView(app: app, isEnabled: binding(for: app, isBrowser: false)) }
                            }
                        }.frame(maxHeight: 360)
                    }.modifier(SettingsContainerModifier()).transition(.opacity.combined(with: .move(edge: .top)))
                }

                RequiredPermissionsView(section: .music)
            }
            .padding(25)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .onAppear { appFetcher.fetchApps() }
        }
        .sheet(item: $spotifyPrivateAPI.loginChallenge) { details in
            if let presenter = try? CaptchaLoader.shared.loadPresenter() {
                presenter.loginView(
                    onComplete: { cookieProperties in
                        spotifyPrivateAPI.completeLoginAfterWebViewSuccess(with: cookieProperties)
                        spotifyPrivateAPI.loginChallenge = nil
                        isPrivateApiLoading = false
                    },
                    onCancel: {
                        privateApiError = "Login was cancelled."
                        spotifyPrivateAPI.loginChallenge = nil
                        isPrivateApiLoading = false
                    }
                )
            } else {
                VStack {
                    Text("Error").font(.largeTitle)
                    Text("Could not load the login solver component.").padding()
                    Button("Close") {
                        spotifyPrivateAPI.loginChallenge = nil
                        isPrivateApiLoading = false
                    }
                }.frame(width: 300, height: 200)
            }
        }
    }

    private func handlePrivateApiLogin() {
        isPrivateApiLoading = true
        privateApiError = nil
        spotifyPrivateAPI.login()
    }

    private func binding(for app: SystemApp, isBrowser: Bool) -> Binding<Bool> {
        .init(
            get: { settings.settings.musicAppStates[app.id, default: !isBrowser] },
            set: { settings.settings.musicAppStates[app.id] = $0 }
        )
    }
}

fileprivate struct PlayerButtonSettingsRow: View {
    let buttonType: MusicPlayerButtonType
    @EnvironmentObject var settings: SettingsModel

    private var isEnabledBinding: Binding<Bool> {
        switch buttonType {
        case .like: return $settings.settings.musicLikeButtonEnabled
        case .shuffle: return $settings.settings.musicShuffleButtonEnabled
        case .repeat: return $settings.settings.musicRepeatButtonEnabled
        case .playlists: return $settings.settings.musicPlaylistsButtonEnabled
        case .devices: return $settings.settings.musicDevicesButtonEnabled
        }
    }

    var body: some View {
        HStack {
            Image(systemName: buttonType.systemImage)
                .font(.system(size: 16, weight: .medium))
                .frame(width: 30)

            Text(buttonType.displayName)
                .font(.system(size: 14, weight: .medium))

            Spacer()

            Toggle("", isOn: isEnabledBinding)
                .labelsHidden()
                .toggleStyle(.switch)

            Image(systemName: "line.3.horizontal")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
                .padding(.leading, 8)
        }
        .padding(EdgeInsets(top: 18, leading: 20, bottom: 18, trailing: 20))
    }
}

struct WeatherSettingsView: View {
    @EnvironmentObject var settings: SettingsModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Weather")
                    .font(.largeTitle.bold())
                    .padding(.bottom)

                VStack(spacing: 0) {
                    HStack {
                        Text("Use Celsius")
                        Spacer()
                        Toggle("", isOn: $settings.settings.weatherUseCelsius)
                            .labelsHidden().toggleStyle(.switch)
                    }
                    .padding()

                    Rectangle().fill(Color.white.opacity(0.2)).frame(height: 1).padding(.leading, 20)

                    HStack {
                        Text("Open detailed Weather widget on live activity click")
                        Spacer()
                        Toggle("", isOn: $settings.settings.weatherOpenOnClick)
                            .labelsHidden().toggleStyle(.switch)
                    }
                    .padding()
                }
                .modifier(SettingsContainerModifier())

                RequiredPermissionsView(section: .weather)
            }
            .padding(25)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }
}

struct CalendarSettingsView: View {
    @EnvironmentObject var settings: SettingsModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Calendar & Reminders")
                    .font(.largeTitle.bold())
                    .padding(.bottom)

                VStack(spacing: 0) {
                    HStack {
                        Text("Show All-Day Events")
                        Spacer()
                        Toggle("", isOn: $settings.settings.calendarShowAllDayEvents)
                            .labelsHidden().toggleStyle(.switch)
                    }
                    .padding()

                    Rectangle().fill(Color.white.opacity(0.2)).frame(height: 1).padding(.leading, 20)

                    HStack {
                        Text("Start Week On")
                        Spacer()
                        Picker("", selection: $settings.settings.calendarStartOfWeek) {
                            ForEach(Day.allCases) { day in
                                Text(day.id).tag(day)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 120)
                    }
                    .padding()

                    Rectangle().fill(Color.white.opacity(0.2)).frame(height: 1).padding(.leading, 20)

                    ToggleRow(
                        title: "Open Calendar on Click",
                        description: "Clicking the Calendar live activity will open the expanded calendar view.",
                        isOn: $settings.settings.calendarOpenOnClick
                    )
                }
                .modifier(SettingsContainerModifier())

                RequiredPermissionsView(section: .calendar)
            }
            .padding(25)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }
}
struct EyeBreakRecommendationsView: View {
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("Eye Health Recommendations")
                    .font(.title2.bold())
                Spacer()
                Button {
                    presentationMode.wrappedValue.dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }

            ScrollView {
                VStack(alignment: .center, spacing: 20) {
                    recommendationCard(
                        title: "The 20-20-20 Rule",
                        description: "Every 20 minutes, take a 20-second break to look at something 20 feet away. This helps reduce eye strain and gives eye muscles a break.",
                        icon: "eyes",
                        color: .blue
                    )

                    recommendationCard(
                        title: "Adjust Your Screen",
                        description: "Position your monitor about an arm's length away and adjust the angle of the screen so that the top it is at or slightly below eye level. This reduces strain on your neck and eyes.",
                        icon: "display",
                        color: .green
                    )

                    recommendationCard(
                        title: "Reduce Blue Light",
                        description: "Use Night Shift on your mac to reduce exposure to blue light, especially in dark environments or during late hours when it can interfere with sleep.",
                        icon: "moon.stars.fill",
                        color: .orange
                    )

                    recommendationCard(
                        title: "Optimize Lighting",
                        description: "Ensure your workspace has adequate lighting that doesn't cause glare on your screen. Avoid working in a dark room with just the screen light.",
                        icon: "lightbulb.fill",
                        color: .yellow
                    )

                    recommendationCard(
                        title: "Stay Hydrated",
                        description: "Drink plenty of water throughout the day. Dehydration can contribute to dry eyes and eye strain.",
                        icon: "drop.fill",
                        color: .cyan
                    )
                }
            }

            Button("Got it") {
                presentationMode.wrappedValue.dismiss()
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity)
        }
        .padding()
        .frame(width: 500, height: 600)
    }

    private func recommendationCard(title: String, description: String, icon: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 15) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(color)
                .frame(width: 40, height: 40)
                .background(color.opacity(0.1))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.05))
        .frame(minWidth: 400)
        .cornerRadius(12)
    }
}

struct EyeBreakSettingsView: View {
    @EnvironmentObject var settings: SettingsModel
    @ObservedObject private var eyeBreakManager = EyeBreakManager.shared
    @State private var showingRecommendationsSheet = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Eye Break")
                    .font(.largeTitle.bold())
                    .padding(.bottom)

                VStack(alignment: .leading, spacing: 0) {
                    ToggleRow(
                        title: "Enable Eye Break Reminders",
                        description: "Receive live activities reminding you to take breaks.",
                        isOn: $settings.settings.eyeBreakLiveActivityEnabled
                    )
                    .onChange(of: settings.settings.eyeBreakLiveActivityEnabled) {
                        eyeBreakManager.dismissBreak()
                    }
                }
                .modifier(SettingsContainerModifier())

                Group {
                    currentStatusSection
                    configurationSection
                    statisticsSection
                    resetSection
                }
                .disabled(!settings.settings.eyeBreakLiveActivityEnabled)
                .opacity(settings.settings.eyeBreakLiveActivityEnabled ? 1.0 : 0.6)
                .animation(.easeInOut(duration: 0.2), value: settings.settings.eyeBreakLiveActivityEnabled)
            }
            .padding(25)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .sheet(isPresented: $showingRecommendationsSheet) {
                EyeBreakRecommendationsView()
            }
        }
    }

    private var currentStatusSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Eye Break Status")
                    .font(.headline)
                Spacer()

                if eyeBreakManager.isBreakTime {
                    Text("Break in Progress")
                        .foregroundColor(.blue)
                        .padding(6)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(6)
                } else {
                    Text("\(formatTimeInterval(eyeBreakManager.timeUntilNextBreak)) until next break")
                        .foregroundColor(.secondary)
                }
            }.padding(15)

            if eyeBreakManager.isBreakTime {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Look away from your screen")
                        .font(.subheadline)
                        .foregroundColor(.primary)

                    Text("Focus on an object at least 20 feet away")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    ProgressView(value: 1 - (eyeBreakManager.timeRemainingInBreak / TimeInterval(settings.settings.eyeBreakBreakDuration)))
                        .progressViewStyle(LinearProgressViewStyle(tint: .blue))
                        .padding(.vertical, 4)

                    HStack {
                        Spacer()

                        Button("Skip") {
                            eyeBreakManager.dismissBreak()
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.secondary)
                        .padding(8)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(8)

                        Button("Complete Break") {
                            eyeBreakManager.completeBreak()
                        }
                        .buttonStyle(.borderless)
                        .foregroundColor(.white)
                        .padding(8)
                        .background(Color.blue)
                        .cornerRadius(8)
                    }
                }
                .padding()
                .background(Color.blue.opacity(0.05))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.blue.opacity(0.2), lineWidth: 1)
                )
            } else {
                HStack(spacing: 20) {
                    VStack(alignment: .center) {
                        Text("\(eyeBreakManager.breaksTakenToday)")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.blue)
                        Text("Breaks Taken")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)

                    Divider()

                    VStack(alignment: .center) {
                        Text("\(eyeBreakManager.currentStreak)")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.orange)
                        Text("Day Streak")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)

                    Divider()

                    VStack(alignment: .center) {
                        Text("\(eyeBreakManager.eyeStrainScore)")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(healthColor)
                        Text("Eye Health")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding()
                .background(Color.secondary.opacity(0.05))
                .cornerRadius(12)
            }
        }
        .modifier(SettingsContainerModifier())
    }

    private var configurationSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Configuration").font(.headline).padding([.top, .horizontal])

            HStack {
                VStack(alignment: .leading, spacing: 8) {
                    Text("The 20-20-20 Rule")
                        .font(.subheadline)
                    Text("Every 20 minutes, take a 20-second break to look at something 20 feet away.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Button("Learn More") {
                        showingRecommendationsSheet = true
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundColor(.blue)
                    .padding(.top, 4)
                }
                Spacer()
                Image(systemName: "eyes")
                    .font(.system(size: 24))
                    .foregroundColor(.blue)
                    .padding()
                    .background(Color.blue.opacity(0.1))
                    .clipShape(Circle())
            }
            .padding([.horizontal, .top])

            Divider()
                .padding(.horizontal)
                .padding(.vertical, 10)

            CustomSliderRowView(
                label: "Work Interval",
                value: $settings.settings.eyeBreakWorkInterval,
                range: 5...60,
                specifier: "%.0f min",
                onEditingChanged: { isEditing in
                    if !isEditing {
                        eyeBreakManager.dismissBreak()
                    }
                }
            )

            Divider().padding(.leading, 20)

            CustomSliderRowView(
                label: "Break Duration",
                value: $settings.settings.eyeBreakBreakDuration,
                range: 10...60,
                specifier: "%.0f sec",
                onEditingChanged: { isEditing in
                    if !isEditing {
                        eyeBreakManager.dismissBreak()
                    }
                }
            )

            Divider().padding(.leading, 20)

            ToggleRow(
                title: "Play Sound Alerts",
                description: "Play sounds when breaks begin and end.",
                isOn: $settings.settings.eyeBreakSoundAlerts
            )

            Divider().padding(.leading, 20)

            ToggleRow(
                title: "Show Activity Graph",
                description: "Display a visual graph of your work and break intervals.",
                isOn: $settings.settings.showEyeBreakGraph
            )
        }
        .modifier(SettingsContainerModifier())
        .animation(.default, value: settings.settings.showEyeBreakGraph)
    }

    private var statisticsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Activity Statistics").font(.headline).padding([.top, .horizontal])
            if settings.settings.showEyeBreakGraph {
                EyeBreakGraphView(summaries: eyeBreakManager.dailySummaries)
                    .environmentObject(settings)
                    .padding([.horizontal, .bottom])
                    .transition(.opacity)
            } else {
                Text("Enable the activity graph above to see your eye break statistics.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding()
            }
        }
        .modifier(SettingsContainerModifier())
        .animation(.default, value: settings.settings.showEyeBreakGraph)
    }

    private var resetSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Reset & Data").font(.headline).padding([.top, .horizontal])
            Button(action: {
                eyeBreakManager.dismissBreak()
            }) {
                HStack {
                    Text("Reset Timer")
                    Spacer()
                    Image(systemName: "arrow.clockwise")
                }
                .padding()
            }
            .buttonStyle(.plain)

            Divider().padding(.horizontal)

            Button(action: {
                UserDefaults.standard.removeObject(forKey: "EyeBreakHistory")
                eyeBreakManager.dismissBreak()
            }) {
                HStack {
                    Text("Clear All History")
                        .foregroundColor(.red)
                    Spacer()
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
                .padding()
            }
            .buttonStyle(.plain)
        }
        .modifier(SettingsContainerModifier())
    }

    private var healthColor: Color {
        let score = eyeBreakManager.eyeStrainScore
        if score > 75 { return .green }
        if score > 50 { return .yellow }
        return .red
    }

    private func formatTimeInterval(_ interval: TimeInterval) -> String {
        let minutes = Int(interval) / 60
        let seconds = Int(interval) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

struct EyeBreakGraphView: View {
    let summaries: [EyeBreakDailySummary]
    @State private var selectedSummary: EyeBreakDailySummary?
    @EnvironmentObject var settings: SettingsModel

    private struct ChartableBreakData: Identifiable {
        var id: String { dayName }
        let dayName: String
        let completedBreaks: Int
        let missedBreaks: Int
        let originalSummary: EyeBreakDailySummary
    }

    private var chartData: [ChartableBreakData] {
        summaries.map { summary in
            let workIntervalInSeconds = settings.settings.eyeBreakWorkInterval * 60
            let totalIntervals = workIntervalInSeconds > 0 ? Int(summary.workDuration / workIntervalInSeconds) : 0
            let missed = max(0, totalIntervals - summary.completedBreaks)

            return ChartableBreakData(
                dayName: summary.dayName,
                completedBreaks: summary.completedBreaks,
                missedBreaks: missed,
                originalSummary: summary
            )
        }
    }

    var body: some View {
        VStack(spacing: 20) {
            keyMetricsView

            HStack {
                Text("Weekly Eye Break Activity")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 5)

            barChart
                .frame(height: 180)

            dailySummariesView
        }
    }

    private var keyMetricsView: some View {
        HStack(spacing: 12) {
            MetricCardView(
                title: "Today's Breaks",
                value: "\(summaries.first?.completedBreaks ?? 0)",
                icon: "eyes",
                color: .blue,
                trend: "+\(summaries.first?.completedBreaks ?? 0) today"
            )

            MetricCardView(
                title: "Compliance",
                value: "\(Int((summaries.first?.complianceRate ?? 0) * 100))%",
                icon: "checkmark.circle",
                color: complianceColor,
                trend: complianceTrend
            )

            MetricCardView(
                title: "Current Streak",
                value: "\(EyeBreakManager.shared.currentStreak)",
                icon: "flame",
                color: .orange,
                trend: "days in a row"
            )

            MetricCardView(
                title: "Eye Health",
                value: "\(summaries.first?.eyeStrainScore ?? 100)",
                icon: "heart.text.square",
                color: eyeHealthColor,
                trend: "/100"
            )
        }
    }

    private var barChart: some View {
        Chart(chartData) { dataPoint in
            BarMark(
                x: .value("Day", dataPoint.dayName),
                y: .value("Breaks", dataPoint.completedBreaks)
            )
            .foregroundStyle(by: .value("Type", "Completed"))

            BarMark(
                x: .value("Day", dataPoint.dayName),
                y: .value("Breaks", dataPoint.missedBreaks)
            )
            .foregroundStyle(by: .value("Type", "Missed"))
        }
        .chartForegroundStyleScale([
            "Completed": Color.blue,
            "Missed": Color.red.opacity(0.6)
        ])
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 5)) { value in
                AxisGridLine()
                AxisValueLabel("\(value.as(Int.self) ?? 0)")
            }
        }
        .chartXAxis {
            AxisMarks {
                AxisGridLine()
                AxisValueLabel()
            }
        }
        .chartLegend(position: .top, alignment: .trailing)
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .onTapGesture { location in
                        if let day: String = proxy.value(atX: location.x),
                           let tappedData = chartData.first(where: { $0.dayName == day }) {
                            selectedSummary = tappedData.originalSummary
                        }
                    }
            }
        }
    }

    private var dailySummariesView: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Daily Activity")
                .font(.headline)
                .padding(.horizontal, 5)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(summaries) { summary in
                        DailySummaryCard(summary: summary, isSelected: selectedSummary?.id == summary.id)
                            .onTapGesture {
                                selectedSummary = summary
                            }
                    }
                }
                .padding(10)
                .padding(.horizontal, 0)
            }
        }
    }

    private var complianceColor: Color {
        let rate = summaries.first?.complianceRate ?? 0
        if rate > 0.8 { return .green }
        if rate > 0.5 { return .yellow }
        return .red
    }

    private var complianceTrend: String {
        let current = summaries.first?.complianceRate ?? 0
        let previous = summaries.dropFirst().first?.complianceRate ?? 0

        if current > previous {
            return "↑ Improving"
        } else if current < previous {
            return "↓ Declining"
        }
        return "→ Steady"
    }

    private var eyeHealthColor: Color {
        let score = summaries.first?.eyeStrainScore ?? 100
        if score > 75 { return .green }
        if score > 50 { return .yellow }
        return .red
    }
}

struct MetricCardView: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    let trend: String

    var body: some View {
        VStack(alignment: .center, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                Text(title)
                    .font(.system(size: 10))
            }
            .foregroundColor(.secondary)

            Text(value)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(color)

            Text(trend)
                .font(.system(size: 9))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(8)
        .background(color.opacity(0.1))
        .cornerRadius(10)
    }
}

struct DailySummaryCard: View {
    let summary: EyeBreakDailySummary
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(summary.dayName)
                    .font(.headline)
                Spacer()
                Circle()
                    .fill(healthStatusColor)
                    .frame(width: 10, height: 10)
            }

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Work")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Text(summary.formattedWorkTime)
                        .font(.system(size: 12, weight: .medium))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Breaks")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Text("\(summary.completedBreaks)")
                        .font(.system(size: 12, weight: .medium))
                }
            }

            HStack {
                Text("Compliance:")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)

                ProgressView(value: summary.complianceRate)
                    .progressViewStyle(LinearProgressViewStyle(tint: healthStatusColor))
                    .frame(width: 60)

                Text("\(Int(summary.complianceRate * 100))%")
                    .font(.system(size: 10, weight: .medium))
            }
        }
        .padding(10)
        .frame(width: 200)
        .background(isSelected ? Color.secondary.opacity(0.2) : Color.secondary.opacity(0.05))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
        )
    }

    private var healthStatusColor: Color {
        let score = summary.eyeStrainScore
        if score > 75 { return .green }
        if score > 50 { return .yellow }
        return .red
    }
}

struct BluetoothSettingsView: View {
    @EnvironmentObject var settings: SettingsModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Bluetooth")
                    .font(.largeTitle.bold())
                    .padding(.bottom)

                VStack(spacing: 0) {
                    Text("Notifications").font(.headline).padding([.top, .horizontal])
                    ToggleRow(title: "Notify for Low Battery", description: "Show an alert when a connected device's battery is low.", isOn: $settings.settings.bluetoothNotifyLowBattery)
                    Divider().padding(.leading, 20)
                    ToggleRow(title: "Play Connection Sounds", description: "Play a sound when devices connect or disconnect.", isOn: $settings.settings.bluetoothNotifySound)
                }
                .modifier(SettingsContainerModifier())

                VStack(spacing: 0) {
                    Text("Live Activity").font(.headline).padding([.top, .horizontal])
                    ToggleRow(title: "Show Device Name", description: "Display the device name in the live activity for connection and battery events.", isOn: $settings.settings.showBluetoothDeviceName)
                }
                .modifier(SettingsContainerModifier())

                RequiredPermissionsView(section: .bluetooth)
            }
            .padding(25)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }
}

struct NeardropSettingsView: View {
    @EnvironmentObject var settings: SettingsModel

    @State private var downloadPath: String = ""
    @State private var isPathValid: Bool = true
    @State private var settingsHaveChanged: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 40) {
                // MARK: - Nearby Share Section
                VStack(alignment: .leading, spacing: 20) {
                    Text("Nearby Share")
                        .font(.largeTitle.bold())
                        .padding(.bottom)

                    VStack(spacing: 0) {
                        HStack {
                            Text("Enable Nearby Share")
                                .font(.system(size: 14, weight: .medium))
                            Spacer()
                            Toggle("", isOn: $settings.settings.neardropEnabled)
                                .labelsHidden()
                                .toggleStyle(.switch)
                        }
                        .padding(EdgeInsets(top: 12, leading: 20, bottom: 12, trailing: 20))

                        Rectangle().fill(Color.white.opacity(0.2)).frame(height: 1).padding(.horizontal, 20)

                        InfoContainer(
                            text: "Nearby Share allows you to share files from Android phones to your Mac using Android's native file sharing (Nearby Share / Quick Share). It's recommended to keep this feature enabled for convenient sharing from family and friends.",
                            iconName: "info.circle.fill",
                            color: .blue
                        )
                        .padding()

                        VStack(alignment: .leading, spacing: 15) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Device Display Name")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(.white)

                                TextField("My Mac", text: $settings.settings.neardropDeviceDisplayName)
                                    .textFieldStyle(.plain)
                                    .padding(.vertical, 8)
                                    .padding(.horizontal, 12)
                                    .background(Color.black.opacity(0.2))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.2), lineWidth: 1))
                                    .foregroundStyle(.white)
                                    .font(.system(size: 13))
                                    .disabled(!settings.settings.neardropEnabled)
                            }

                            VStack(alignment: .leading, spacing: 8) {
                                Text("Download Location")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(.white)

                                HStack {
                                    TextField("Path", text: $downloadPath, onCommit: validateAndSavePath)
                                        .textFieldStyle(.plain)
                                        .foregroundStyle(.white)
                                        .font(.system(size: 13))
                                        .disabled(!settings.settings.neardropEnabled)

                                    Image(systemName: isPathValid ? "checkmark.circle.fill" : "xmark.circle.fill")
                                        .foregroundColor(isPathValid ? .green : .red)
                                }
                                .padding(.vertical, 8)
                                .padding(.horizontal, 12)
                                .background(Color.black.opacity(0.2))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(isPathValid ? Color.white.opacity(0.2) : Color.red, lineWidth: 1))

                                if !isPathValid {
                                    Text("A valid directory is required.")
                                        .font(.caption)
                                        .foregroundColor(.red)
                                }
                            }
                        }
                        .padding([.horizontal, .bottom], 20)
                        .opacity(settings.settings.neardropEnabled ? 1.0 : 0.5)

                        Rectangle().fill(Color.white.opacity(0.2)).frame(height: 1).padding(.horizontal, 20)

                        HStack {
                            Text("Open detailed AirDrop widget on live activity click")
                            Spacer()
                            Toggle("", isOn: $settings.settings.neardropOpenOnClick)
                                .labelsHidden().toggleStyle(.switch)
                        }
                        .padding()
                        .disabled(!settings.settings.neardropEnabled)
                        .opacity(settings.settings.neardropEnabled ? 1.0 : 0.5)

                    }
                    .modifier(SettingsContainerModifier())
                    .animation(.easeInOut, value: settings.settings.neardropEnabled)
                }
                OpenBubblesActivationView()

            }
            .padding(25)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .onAppear {
                self.downloadPath = settings.settings.neardropDownloadLocationPath
            }
            .onChange(of: downloadPath) { _, newValue in
                self.isPathValid = validate(path: newValue)
            }
            .onChange(of: settings.settings.neardropEnabled) {
                settingsHaveChanged = true
            }
            .onChange(of: settings.settings.neardropDeviceDisplayName) {
                settingsHaveChanged = true
            }
            .animation(.spring(), value: settingsHaveChanged)
        }

        RequiredPermissionsView(section: .neardrop)
    }

    private func validateAndSavePath() {
        if validate(path: downloadPath) {
            settings.settings.neardropDownloadLocationPath = downloadPath
        }
    }

    private func validate(path: String) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
        return exists && isDirectory.boolValue
    }
}

struct AboutSettingsView: View {
    @ObservedObject private var updateChecker = UpdateChecker.shared
    @ObservedObject private var permissionsManager = PermissionsManager.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("About").font(.largeTitle.bold()).padding(.bottom)

                HStack {
                    Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 100, height: 100).clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous)).padding(.trailing, 10)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Sapphire").font(.largeTitle.weight(.bold))
                        Text("Version \(currentAppVersion)").foregroundStyle(.secondary).textSelection(.enabled)

                        HStack(spacing: 10) {
                            Link(destination: URL(string: "https://cshariq.github.io/Sapphire-Website/")!) {
                                Image(systemName: "link")
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 18, height: 18)
                                    .foregroundColor(.white)
                                    .padding(6)
                                    .background(Color.blue)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                            .buttonStyle(PlainButtonStyle())

                            Link(destination: URL(string: "https://github.com/cshariq/Sapphire")!) {
                                Image("github_logo")
                                    .resizable()
                                    .renderingMode(.template)
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 18, height: 18)
                                    .foregroundColor(.white)
                                    .padding(6)
                                    .background(Color.black)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                            .buttonStyle(PlainButtonStyle())

                            Link(destination: URL(string: "https://discord.gg/TdRjC2kNnU")!) {
                                Image("discord_logo")
                                    .resizable()
                                        .aspectRatio(contentMode: .fit)
                                    .frame(width: 18, height: 18)
                                    .padding(6)
                                    .background(Color(red: 0.35, green: 0.40, blue: 0.95))
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        .padding(.top, 6)
                    }
                    Spacer()
                }

                ModernUpdateStatusView(updateChecker: updateChecker)

                VStack(alignment: .leading, spacing: 0) {
                    Text("Permissions Overview").font(.headline).padding([.horizontal, .top])
                    ForEach(permissionsManager.allPermissions) { permission in
                        PermissionStatusRowView(permission: permission)
                        if permission.id != permissionsManager.allPermissions.last?.id { Divider().padding(.leading, 60) }
                    }
                }.modifier(SettingsContainerModifier()).onAppear(perform: permissionsManager.checkAllPermissions)

                Text("© 2025 Shariq Charolia. All rights reserved.").font(.caption).foregroundStyle(.tertiary).frame(maxWidth: .infinity, alignment: .center).padding(.top, 20)
            }.padding(25).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .onAppear { updateChecker.checkForUpdates() }
        }
    }

    var currentAppVersion: String {
        return Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "N/A"
    }
}

fileprivate struct AboutLinkStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .foregroundColor(.primary)
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
    }
}

struct ModernUpdateStatusView: View {
    @ObservedObject var updateChecker: UpdateChecker
    @State private var upToDateAnimationTrigger = false

    var body: some View {
        ZStack {
            switch updateChecker.status {
            case .checking:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Checking for Updates...").foregroundStyle(.secondary)
                }
            case .upToDate:
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.green)
                        .symbolEffect(.bounce, value: upToDateAnimationTrigger)
                    Text("You are up to date!")
                        .foregroundStyle(.secondary)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
                .onAppear {
                    upToDateAnimationTrigger.toggle()
                }
            case .available(let version, let asset):
                VStack(spacing: 12) {
                    Text("Version \(version) is available!")
                        .font(.system(size: 16, weight: .bold))

                    Button(action: { updateChecker.downloadUpdate(asset: asset) }) {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.down.circle.fill")
                            Text("Download Update")
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Color.accentColor.gradient)
                        .clipShape(Capsule())
                        .shadow(color: .accentColor.opacity(0.4), radius: 8, y: 4)
                    }
                    .buttonStyle(.plain)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            case .downloading(let progress):
                DownloadingView(progress: progress, onCancel: {
                    updateChecker.cancelDownload()
                })
                .transition(.opacity)
            case .downloaded:
                VStack(spacing: 12) {
                    Text("Download Complete!")
                        .font(.system(size: 16, weight: .bold))
                    Button(action: { updateChecker.installAndRelaunch() }) {
                        HStack(spacing: 8) {
                            Image(systemName: "sparkles")
                            Text("Install and Relaunch")
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Color.green.gradient)
                        .clipShape(Capsule())
                        .shadow(color: .green.opacity(0.4), radius: 8, y: 4)
                    }
                    .buttonStyle(.plain)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            case .installing:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Installing... App will relaunch.").foregroundStyle(.secondary)
                }
            case .error(let message):
                HStack(spacing: 8) {
                    Image(systemName: "xmark.octagon.fill").foregroundColor(.red)
                    Text(message).foregroundStyle(.secondary).lineLimit(1)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .modifier(SettingsContainerModifier())
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: updateChecker.status)
    }
}

struct DownloadingView: View {
    let progress: Double
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Downloading Update...")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "%.0f%%", progress * 100))
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
            }

            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.1)).frame(height: 12)
                Capsule()
                    .fill(Color.accentColor.gradient)
                    .frame(width: (300 * progress), height: 12)
                    .animation(.easeOut, value: progress)
            }
            .frame(width: 300)

            Button("Cancel", action: onCancel)
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

fileprivate struct NotchButtonRowView: View {
    let buttonType: NotchButtonType

    @EnvironmentObject var settings: SettingsModel

    private var isEnabledBinding: Binding<Bool> {
        switch buttonType {
        case .settings, .spacer, .multiAudio:
            return .constant(true)
        case .fileShelf: return $settings.settings.fileShelfIconEnabled
        case .gemini: return $settings.settings.geminiEnabled
        case .caffeine: return $settings.settings.caffeinateEnabled
        case .battery: return $settings.settings.batteryEstimatorEnabled
        case .pin: return $settings.settings.pinEnabled
        }
    }

    private var isToggleDisabled: Bool {
        switch buttonType {
        case .settings, .spacer, .multiAudio:
            return true
        default:
            return false
        }
    }

    var body: some View {
        HStack {
            if buttonType == .spacer {
                HStack {
                    Rectangle().fill(.secondary).frame(height: 1)
                    Text("Center Spacer")
                        .font(.caption.bold()).foregroundStyle(.secondary)
                    Rectangle().fill(.secondary).frame(height: 1)
                }
            } else {
                Image(systemName: buttonType.systemImage)
                    .font(.system(size: 16, weight: .medium))
                    .frame(width: 30)

                Text(buttonType.displayName)
                    .font(.system(size: 14, weight: .medium))
            }

            Spacer()

            Toggle("", isOn: isEnabledBinding)
                .labelsHidden()
                .toggleStyle(.switch)
                .disabled(isToggleDisabled)
                .opacity(isToggleDisabled ? 0 : 1)

            Image(systemName: "line.3.horizontal")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
                .padding(.leading, 8)
        }
        .padding(EdgeInsets(top: 18, leading: 20, bottom: 18, trailing: 20))
    }
}

struct AppearanceSettingsView: View {
    @EnvironmentObject var settings: SettingsModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 40) {
                Text("Appearance")
                    .font(.largeTitle.bold())
                NotchAppearanceEditorView(appearance: $settings.settings.notchWidgetAppearance, title: "Expanded Notch Appearance")
                NotchAppearanceEditorView(appearance: $settings.settings.notchLiveActivityAppearance, title: "Collapsed Notch Appearance")
                MenuBarHidingSettingsView()
                MenuBarAppearanceSettingsView()
                MenuBarSpacingSettingsView()
            }
            .padding(25)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }
}

struct MenuBarHidingSettingsView: View {
    @EnvironmentObject var settings: SettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Icon Hiding").font(.title2.bold())
                Text("Hide and show menu bar items using an expandable section.").font(.caption).foregroundColor(.secondary)
            }

            VStack(spacing: 0) {
                ToggleRow(title: "Enable Menu Bar Icon Hiding", description: "", isOn: $settings.settings.menuBarEnabled)
            }.modifier(SettingsContainerModifier())

            if settings.settings.menuBarEnabled {
                VStack(alignment: .leading, spacing: 0) {

                    Text("Control Item Icons").font(.headline).padding([.top, .horizontal])
                    Text("Choose the icon style for the main control item.").font(.caption).foregroundColor(.secondary).padding(.horizontal).padding(.bottom, 10)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(ControlItemIconStyle.allCases) { iconStyle in
                                ControlItemIconPreview(iconStyle: iconStyle, isSelected: settings.settings.controlItemIconStyle == iconStyle) {
                                    withAnimation { settings.settings.controlItemIconStyle = iconStyle }
                                }
                            }
                        }.padding(.horizontal).padding(.bottom, 12)
                    }
                }.modifier(SettingsContainerModifier())

                VStack(alignment: .leading, spacing: 0) {
                    InfoContainer(text: "To customize the shown icons, right click on the menu bar and select 'Customize Menu Bar'. The icons placed in between the dot and expansion icon will always be shown, the icons placed in between the two dots will be hidden when the menu is collapsed, and the icons after the dot will always be hidden.", iconName: "info.circle", color: Color.mint).padding()

                    Image("MenubarDemo")
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 480)
                        .cornerRadius(10)
                        .padding(.horizontal)
                        .padding(.top, 8)

                    Text("Show Hidden Items").font(.headline).padding([.top, .horizontal])
                    ToggleRow(title: "Show on Hover", description: "Show hidden items when hovering over the menu bar", isOn: $settings.settings.showOnHover)
                    if settings.settings.showOnHover { CustomSliderRowView(label: "Hover Delay", value: $settings.settings.showOnHoverDelay, range: 0.0...1.0, specifier: "%.1fs") }
                    Divider().padding(.leading, 20)
                    ToggleRow(title: "Show on Click", description: "Show hidden items when clicking empty menu bar space", isOn: $settings.settings.showOnClick)
                    Divider().padding(.leading, 20)
                    ToggleRow(title: "Show on Scroll", description: "Show hidden items when scrolling in the menu bar", isOn: $settings.settings.showOnScroll)
                }.modifier(SettingsContainerModifier()).animation(.default, value: settings.settings.showOnHover)

                VStack(alignment: .leading, spacing: 0) {
                    Text("Auto-Rehide").font(.headline).padding([.top, .horizontal])
                    ToggleRow(title: "Automatically Rehide Items", description: "Automatically hide items after they're shown", isOn: $settings.settings.autoRehide)
                    if settings.settings.autoRehide {
                        Divider().padding(.leading, 20)
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Rehide Strategy").font(.subheadline).foregroundColor(.secondary)
                            Picker("", selection: $settings.settings.rehideStrategy) {
                                Text("Smart (when mouse leaves)").tag("smart"); Text("Timed").tag("timed")
                            }.pickerStyle(.segmented).padding(.horizontal)
                        }.padding()
                        if settings.settings.rehideStrategy == "timed" {
                            CustomSliderRowView(label: "Hide After", value: $settings.settings.tempShowInterval, range: 1.0...30.0, specifier: "%.1fs")
                        }
                    }
                }.modifier(SettingsContainerModifier()).animation(.default, value: settings.settings.autoRehide || settings.settings.rehideStrategy == "timed")

                VStack(alignment: .leading, spacing: 0) {
                    Text("Hiding Appearance").font(.headline).padding([.top, .horizontal])
                    ToggleRow(title: "Show Section Dividers", description: "", isOn: $settings.settings.showSectionDividers)
                    Divider().padding(.leading, 20)
                    ToggleRow(title: "Enable Always-Hidden Section", description: "", isOn: $settings.settings.enableAlwaysHiddenSection)
                    Divider().padding(.leading, 20)
                    ToggleRow(title: "Hide Main Control Icon", description: "", isOn: $settings.settings.hideMenuBarIcon)
                }.modifier(SettingsContainerModifier())
            }
        }
        .animation(.easeInOut, value: settings.settings.menuBarEnabled)
    }
}

struct MenuBarAppearanceEditor: View {
    @EnvironmentObject var settings: SettingsModel

    private var opacityBinding: Binding<Double> {
        Binding(
            get: { settings.settings.menuBarOpacity * 100 },
            set: { settings.settings.menuBarOpacity = $0 / 100 }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Menu Bar Tint").font(.headline)
                Spacer()
                Button("Reset", action: resetTintSettings)
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
            }
            .padding([.top, .horizontal])

            ToggleRow(title: "Liquid Glass Look", description: "Apply a shiny, glass-like effect to the menu bar background.", isOn: $settings.settings.menuBarLiquidGlass)
            Divider().padding(.leading, 20)

            HStack {
                Text("Background Style")
                Spacer()
                Picker("", selection: $settings.settings.menuBarTintStyle) {
                    Text("None").tag("none"); Text("Solid").tag("solid"); Text("Gradient").tag("gradient")
                }.labelsHidden().frame(width: 200)
            }.padding()

            if settings.settings.menuBarTintStyle == "solid" {
                solidColorPicker
            } else if settings.settings.menuBarTintStyle == "gradient" {
                gradientColorEditor
            }

            Divider().padding(.leading, 20)

            CustomSliderRowView(label: "Master Opacity", value: opacityBinding, range: 0...100, specifier: "%.0f%%")

            Divider().padding(.leading, 20)
            ToggleRow(title: "Enable Transparency Blur", description: "Apply a frosted glass effect to the menu bar background.", isOn: $settings.settings.menuBarBlur)
        }
        .modifier(SettingsContainerModifier())
        .animation(.default, value: settings.settings.menuBarTintStyle)
    }

    @ViewBuilder
    private var solidColorPicker: some View {
        ColorPicker("Color", selection: $settings.settings.menuBarSolidColor.color, supportsOpacity: true)
            .padding()
            .transition(.opacity)
    }

    @ViewBuilder
    private var gradientColorEditor: some View {
        VStack(alignment: .leading) {
            CustomSliderRowView(label: "Angle", value: $settings.settings.menuBarGradientAngle, range: 0...360, specifier: "%.0f°")
                .padding(.horizontal)

            Text("Gradient Colors").font(.subheadline).padding(.horizontal)

            ForEach($settings.settings.menuBarGradientColors) { $color in
                VStack(spacing: 8) {
                    HStack {
                        ColorPicker("Color Stop", selection: $color.color, supportsOpacity: true)
                        Spacer()
                        Button(action: {
                            if settings.settings.menuBarGradientColors.count > 1 {
                                settings.settings.menuBarGradientColors.removeAll { $0.id == color.id }
                            }
                        }) {
                            Image(systemName: "minus.circle.fill").foregroundColor(.red)
                        }.buttonStyle(.plain).disabled(settings.settings.menuBarGradientColors.count <= 1)
                    }
                    Slider(value: $color.location, in: 0...1) { Text("Location") }
                }.padding(.horizontal)
            }

            Button(action: {
                var colors = settings.settings.menuBarGradientColors
                let newStop = CodableColor(color: colors.last?.color ?? .black, location: 1.0)
                colors.append(newStop)
                settings.settings.menuBarGradientColors = colors
            }) {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text("Add Color Stop")
                }
            }.buttonStyle(.plain).tint(.accentColor).padding([.top, .horizontal])
        }
        .padding(.vertical)
        .transition(.opacity)
    }

    private func resetTintSettings() {
        settings.settings.menuBarLiquidGlass = false
        settings.settings.menuBarTintStyle = "none"
        settings.settings.menuBarSolidColor = CodableColor(color: .clear)
        settings.settings.menuBarGradientAngle = 0.0
        settings.settings.menuBarGradientColors = [
            CodableColor(color: .white, location: 0),
            CodableColor(color: .black, location: 1)
        ]
        settings.settings.menuBarOpacity = 1.0
        settings.settings.menuBarBlur = false
    }
}

struct MenuBarAppearanceSettingsView: View {
    @EnvironmentObject var settings: SettingsModel

    private var verticalPaddingBinding: Binding<Double> {
        Binding<Double>(
            get: { Double(settings.settings.menuBarVerticalPadding) },
            set: { settings.settings.menuBarVerticalPadding = CGFloat($0) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Menu Bar Style (Beta)").font(.title2.bold())
                    Text("Customize the look and feel of your Mac's menu bar.").font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                Button("Reset All", action: resetAllAppearanceSettings)
                    .buttonStyle(.plain)
            }

            MenuBarAppearanceEditor()

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Border Thickness"); Spacer()
                    Picker("Border", selection: $settings.settings.menuBarBorderWidth) {
                        Text("No Border").tag(CGFloat(0)); Text("1px").tag(CGFloat(1)); Text("2px").tag(CGFloat(2)); Text("3px").tag(CGFloat(3))
                    }.labelsHidden().frame(width: 120)
                }.padding()
                Divider().padding(.horizontal)
                ColorPicker("Border Color", selection: $settings.settings.menuBarBorderColor.color, supportsOpacity: true).padding()
            }.modifier(SettingsContainerModifier())

            VStack(alignment: .leading, spacing: 0) {
                Toggle(isOn: Binding(
                    get: { settings.settings.menuBarShapeStyle == "rounded" },
                    set: { if $0 { settings.settings.menuBarShapeStyle = "rounded" } else if settings.settings.menuBarShapeStyle == "rounded" { settings.settings.menuBarShapeStyle = "none" } }
                )) {
                    Text("Rounded menu bar")
                }.padding()

                Divider().padding(.horizontal)

                Toggle(isOn: Binding(
                    get: { settings.settings.menuBarShapeStyle == "roundedSplit" },
                    set: { if $0 { settings.settings.menuBarShapeStyle = "roundedSplit" } else if settings.settings.menuBarShapeStyle == "roundedSplit" { settings.settings.menuBarShapeStyle = "none" } }
                )) {
                    Text("Rounded separate sides")
                }.padding()

                Divider().padding(.horizontal)
                CustomSliderRowView(label: "Vertical Padding", value: verticalPaddingBinding, range: 0...10, specifier: "%.0fpx")

            }.modifier(SettingsContainerModifier()).animation(.default, value: settings.settings.menuBarShapeStyle)
        }
    }

    private func resetAllAppearanceSettings() {
        settings.settings.menuBarLiquidGlass = false
        settings.settings.menuBarTintStyle = "none"
        settings.settings.menuBarSolidColor = CodableColor(color: .clear)
        settings.settings.menuBarGradientAngle = 0.0
        settings.settings.menuBarGradientColors = [
            CodableColor(color: .white, location: 0),
            CodableColor(color: .black, location: 1)
        ]
        settings.settings.menuBarOpacity = 1.0
        settings.settings.menuBarBlur = false

        settings.settings.menuBarBorderWidth = 0
        settings.settings.menuBarBorderColor = CodableColor(color: .black)

        settings.settings.menuBarShapeStyle = "none"
        settings.settings.menuBarVerticalPadding = 0
    }
}

struct MenuBarSpacingSettingsView: View {
    @EnvironmentObject var settings: SettingsModel
    private let spacingManager = MenuBarSpacingManager()

    private var spacingBinding: Binding<Double> {
        Binding<Double>(
            get: { Double(settings.settings.menuBarSpacing) },
            set: { settings.settings.menuBarSpacing = Int($0) }
        )
    }

    private var paddingBinding: Binding<Double> {
        Binding<Double>(
            get: { Double(settings.settings.menuBarSelectionPadding) },
            set: { settings.settings.menuBarSelectionPadding = Int($0) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Menu Bar Spacing (Beta)").font(.title2.bold())
                Text("Fine-tune the spacing and padding between all menu bar items. Changes require a menu bar refresh to apply.").font(.caption).foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 0) {
                CustomSliderRowView(label: "Spacing", value: spacingBinding, range: 1...50, specifier: "%.0f")
                Divider().padding(.leading, 20)
                CustomSliderRowView(label: "Padding", value: paddingBinding, range: 1...50, specifier: "%.0f")

                HStack {
                    Button("Reset to System Default") {
                        spacingManager.restoreDefaults()
                    }

                    Spacer()

                    Button("Apply & Refresh Menu Bar") {
                        spacingManager.applyChanges()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()

            }.modifier(SettingsContainerModifier())
        }
    }
}

struct ControlItemIconPreview: View {
    let iconStyle: ControlItemIconStyle
    let isSelected: Bool
    let onSelect: () -> Void

    @State private var isHovered = false

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: iconStyle.previewSymbol)
                .font(.system(size: 22, weight: .medium))
                .foregroundColor(isSelected ? .white : .secondary)
                .frame(width: 60, height: 50)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isSelected ? Color.accentColor : Color.secondary.opacity(isHovered ? 0.15 : 0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(
                            isSelected ? Color.accentColor : Color.clear,
                            lineWidth: 2
                        )
                )

            Text(iconStyle.displayName)
                .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                .foregroundColor(isSelected ? .primary : .secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: 70)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .scaleEffect(isHovered && !isSelected ? 1.05 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
    }
}

extension View {
    @ViewBuilder
    func dynamicXAxis(for range: TimeRange, isVisible: Bool) -> some View {
        if isVisible {
            switch range {
            case .last24Hours:
                self.chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) { _ in AxisValueLabel(format: .dateTime.hour()) } }
            case .last7Days:
                self.chartXAxis { AxisMarks(values: .automatic(desiredCount: 7)) { _ in AxisValueLabel(format: .dateTime.weekday()) } }
            case .lastMonth, .custom:
                self.chartXAxis { AxisMarks(values: .automatic(desiredCount: 5)) { _ in AxisValueLabel(format: .dateTime.day()) } }
            case .lastYear:
                self.chartXAxis { AxisMarks(values: .automatic(desiredCount: 6)) { _ in AxisValueLabel(format: .dateTime.month(.abbreviated)) } }
            }
        } else {
            self.chartXAxis(.hidden)
        }
    }
}

extension View {
    func chartInteractionOverlay<T: Identifiable>(
        proxy: ChartProxy,
        data: [T],
        keyPath: KeyPath<T, Date>,
        selectedItem: Binding<T?>
    ) -> some View {
        GeometryReader { geometry in
            Rectangle()
                .fill(.clear)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if let date: Date = proxy.value(atX: value.location.x) {
                                let closest = data.min {
                                    abs($0[keyPath: keyPath].timeIntervalSince(date)) <
                                    abs($1[keyPath: keyPath].timeIntervalSince(date))
                                }
                                selectedItem.wrappedValue = closest
                            }
                        }
                        .onEnded { _ in
                            selectedItem.wrappedValue = nil
                        }
                )
        }
    }
}

struct ModernSegmentedPicker: View {
    @Binding var selection: String
    let options: [String]

    @Namespace private var pickerNamespace

    var body: some View {
        HStack(spacing: 8) {
            ForEach(options, id: \.self) { option in
                Text(option)
                    .font(.headline.weight(.bold))
                    .padding(.vertical, 10)
                    .padding(.horizontal, 20)
                    .frame(maxWidth: .infinity)
                    .background(
                        ZStack {
                            if selection == option {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(.ultraThinMaterial)
                                    .shadow(color: .black.opacity(0.15), radius: 5, y: 3)
                                    .matchedGeometryEffect(id: "pickerPill", in: pickerNamespace)
                            }
                        }
                    )
                    .foregroundColor(selection == option ? .primary : .secondary)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.interactiveSpring(response: 0.4, dampingFraction: 0.7, blendDuration: 0.7)) {
                            selection = option
                        }
                    }
            }
        }
        .padding(6)
        .background(Color.black.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}