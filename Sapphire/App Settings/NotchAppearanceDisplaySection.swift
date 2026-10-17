//
//  NotchAppearanceDisplaySection.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-10-15
//

import AppKit
import SwiftUI

struct NotchAppearanceDisplaySection: View {
    @EditingSettings var settings: SettingsEditingSession
    @State private var selectedDisplay: String?
    @State private var screensRevision = 0

    private var screens: [NSScreen] { NSScreen.screens }

    var body: some View {
        let _ = screensRevision
        VStack(alignment: .leading, spacing: 20) {
            if screens.count > 1 {
                displayPicker
            }
            NotchAppearanceEditorView(appearance: widgetBinding, title: String(localized: "Expanded Notch Appearance"))
            NotchAppearanceEditorView(appearance: liveActivityBinding, title: String(localized: "Collapsed Notch Appearance"))
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            screensRevision += 1
            if let selectedDisplay, !screens.contains(where: { $0.displayIdentifier == selectedDisplay }) {
                self.selectedDisplay = nil
            }
        }
    }

    // MARK: Picker

    private var displayPicker: some View {
        let current = settings.settings.value
        let hasOverride = selectedDisplay.map { current.hasAppearanceOverride(forDisplayID: $0) } ?? false
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                SettingsRowLabel(title: Text("Appearance For"), description: Text(verbatim: pickerDescription(hasOverride: hasOverride)))
                Spacer(minLength: 8)
                Picker("Appearance For", selection: $selectedDisplay) {
                    Text("All Displays").tag(String?.none)
                    ForEach(screens, id: \.displayIdentifier) { screen in
                        let custom = current.hasAppearanceOverride(forDisplayID: screen.displayIdentifier)
                        Text(verbatim: custom ? String(localized: "\(screen.displayLabel) (Custom)") : screen.displayLabel)
                            .tag(Optional(screen.displayIdentifier))
                    }
                }
                .labelsHidden()
                .frame(width: 240)
            }
            if let key = selectedDisplay, hasOverride {
                HStack(spacing: 16) {
                    Spacer()
                    Button {
                        settings.settings.value.applyAppearanceToAllDisplays(from: key)
                        selectedDisplay = nil
                    } label: {
                        Label("Use for All Displays", systemImage: "rectangle.on.rectangle")
                    }
                    .help("Make this display's appearance the default and clear every display's own appearance")
                    Button {
                        resetOverride(for: key)
                    } label: {
                        Label("Reset to Default", systemImage: "arrow.counterclockwise")
                    }
                    .help("This display goes back to the appearance every display uses")
                }
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)
                .font(.callout)
            }
        }
        .padding()
        .modifier(SettingsContainerModifier())
    }

    private func pickerDescription(hasOverride: Bool) -> String {
        guard let selectedDisplay else {
            return String(localized: "Changes apply to every display that has no appearance of its own.")
        }
        let name = screens.first { $0.displayIdentifier == selectedDisplay }?.displayLabel ?? String(localized: "This display")
        return hasOverride
            ? String(localized: "\(name) has its own appearance.")
            : String(localized: "\(name) uses the default. Changing anything below gives it its own appearance.")
    }

    private func resetOverride(for key: String) {
        let connected = screens.map(\.displayIdentifier)
        DisplaySettingsKey.removeValue(from: &settings.settings.perDisplayNotchWidgetAppearance, for: key, connectedKeys: connected)
        DisplaySettingsKey.removeValue(from: &settings.settings.perDisplayNotchLiveActivityAppearance, for: key, connectedKeys: connected)
    }

    // MARK: Bindings

    private var widgetBinding: Binding<NotchAppearanceSettings> {
        guard let key = selectedDisplay else { return $settings.settings.notchWidgetAppearance }
        return Binding(
            get: { settings.settings.value.resolvedNotchWidgetAppearance(forDisplayID: key) },
            set: { newValue in
                adoptOverride(for: key)
                settings.settings.perDisplayNotchWidgetAppearance[key] = newValue
            }
        )
    }

    private var liveActivityBinding: Binding<NotchAppearanceSettings> {
        guard let key = selectedDisplay else { return $settings.settings.notchLiveActivityAppearance }
        return Binding(
            get: { settings.settings.value.resolvedNotchLiveActivityAppearance(forDisplayID: key) },
            set: { newValue in
                adoptOverride(for: key)
                settings.settings.perDisplayNotchLiveActivityAppearance[key] = newValue
            }
        )
    }

    private func adoptOverride(for key: String) {
        let current = settings.settings.value
        if DisplaySettingsKey.value(in: current.perDisplayNotchWidgetAppearance, for: key) == nil {
            settings.settings.perDisplayNotchWidgetAppearance[key] = current.notchWidgetAppearance
        }
        if DisplaySettingsKey.value(in: current.perDisplayNotchLiveActivityAppearance, for: key) == nil {
            settings.settings.perDisplayNotchLiveActivityAppearance[key] = current.notchLiveActivityAppearance
        }
    }
}