//
//  AudioSettingsView.swift
//  Sapphire
//

import SwiftUI

struct AudioSettingsView: View {
    @EnvironmentObject var settings: SettingsModel
    @ObservedObject private var audioManager = MultiAudioManager.shared
    @ObservedObject private var permissionsManager = PermissionsManager.shared
    @State private var showResetAppConfirmation = false
    @State private var showResetDeviceConfirmation = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Audio")
                    .font(.largeTitle.bold())
                    .padding(.bottom, 4)

                VStack(alignment: .leading, spacing: 0) {
                    Text("Notch")
                        .font(.headline)
                        .padding([.top, .horizontal])

                    AudioCompactToggleRow(
                        title: "Multi-Audio in Notch",
                        description: "Show the per-app mixer in the expanded notch.",
                        isOn: Binding(
                            get: { settings.settings.notchButtonOrder.contains(.multiAudio) },
                            set: { enabled in
                                if enabled && !settings.settings.notchButtonOrder.contains(.multiAudio) {
                                    settings.settings.notchButtonOrder.append(.multiAudio)
                                } else if !enabled {
                                    settings.settings.notchButtonOrder.removeAll { $0 == .multiAudio }
                                }
                            }
                        )
                    )
                    .disabled(permissionsManager.screenRecordingStatus != .granted)
                    Divider().padding(.leading, 20)
                    AudioCompactToggleRow(
                        title: "Haptic Feedback",
                        description: "Subtle vibration when adjusting audio controls.",
                        isOn: $settings.settings.hapticFeedbackEnabled
                    )
                }
                .modifier(SettingsContainerModifier())

                if !audioManager.availableOutputDevices.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Output Devices")
                            .font(.headline)
                            .padding([.top, .horizontal])

                        ForEach(audioManager.availableOutputDevices, id: \.id) { device in
                            AudioDeviceRow(device: device)
                            if device.id != audioManager.availableOutputDevices.last?.id {
                                Divider().padding(.leading, 56)
                            }
                        }
                    }
                    .modifier(SettingsContainerModifier())
                }

                VStack(alignment: .leading, spacing: 0) {
                    Text("Reset")
                        .font(.headline)
                        .padding([.top, .horizontal])

                    AudioResetRow(
                        title: "Reset Per-App Adjustments",
                        subtitle: "Clears custom volumes, mutes, and EQ for all apps.",
                        buttonTitle: "Reset Apps",
                        buttonColor: .red
                    ) {
                        showResetAppConfirmation = true
                    }
                    .alert("Reset Per-App Settings?", isPresented: $showResetAppConfirmation) {
                        Button("Cancel", role: .cancel) { }
                        Button("Reset", role: .destructive) { resetAllAppSettings() }
                    } message: {
                        Text("This restores default volume and flat EQ for every application.")
                    }

                    Divider().padding(.leading, 20)

                    AudioResetRow(
                        title: "Reset Device Settings",
                        subtitle: "Clears master volume, balance, delay, and EQ for all devices.",
                        buttonTitle: "Reset Devices",
                        buttonColor: .red
                    ) {
                        showResetDeviceConfirmation = true
                    }
                    .alert("Reset Device Settings?", isPresented: $showResetDeviceConfirmation) {
                        Button("Cancel", role: .cancel) { }
                        Button("Reset", role: .destructive) { resetAllDeviceSettings() }
                    } message: {
                        Text("This reverts all connected output devices to their default state.")
                    }
                }
                .modifier(SettingsContainerModifier())

                RequiredPermissionsView(section: .audio)
            }
            .padding(25)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onChange(of: permissionsManager.screenRecordingStatus) { _, newStatus in
            if newStatus == .granted, !settings.settings.notchButtonOrder.contains(.multiAudio) {
                settings.settings.notchButtonOrder.append(.multiAudio)
            }
        }
    }

    private func resetAllAppSettings() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "SapphirePerAppVolumeMap")
        defaults.removeObject(forKey: "SapphirePerAppMuteMap")
        defaults.removeObject(forKey: "SapphirePerAppEQMap")
        defaults.removeObject(forKey: "SapphirePerAppEQDeviceScopeMap")

        NotificationCenter.default.post(name: .perAppAudioSettingsDidChange, object: nil)

        Task { @MainActor in
            MultiAudioManager.shared.activeTaps.values.forEach { tapMap in
                tapMap.values.forEach { $0.invalidate() }
            }
            MultiAudioManager.shared.notifyAdjustmentMade(for: "ResetAll")
        }
    }

    private func resetAllDeviceSettings() {
        Task { @MainActor in
            MultiAudioManager.shared.deviceSettings.removeAll()
            MultiAudioManager.shared.notifyAdjustmentMade(for: "ResetAll")
        }
    }
}

// MARK: - Rows

private struct AudioCompactToggleRow: View {
    let title: String
    let description: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                if !description.isEmpty {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
    }
}

fileprivate struct AudioDeviceRow: View {
    let device: AudioDevice
    @ObservedObject private var audioManager = MultiAudioManager.shared

    private var deviceSettings: AudioDeviceSettings {
        audioManager.deviceSettings[device.id] ?? AudioDeviceSettings()
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: deviceIconName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 28)

            Text(device.name)
                .font(.system(size: 13, weight: .medium))

            Spacer()

            Text("\(Int(deviceSettings.volume * 100))%")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var deviceIconName: String {
        let name = device.name.lowercased()
        if name.contains("airpods") { return "airpodspro" }
        if name.contains("headphone") || name.contains("headset") { return "headphones" }
        if name.contains("speaker") { return "hifispeaker.fill" }
        if name.contains("display") || name.contains("monitor") { return "display" }
        return "speaker.wave.2.fill"
    }
}

private struct AudioResetRow: View {
    let title: String
    let subtitle: String
    let buttonTitle: String
    let buttonColor: Color
    let action: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button(buttonTitle, action: action)
                .buttonStyle(.bordered)
                .tint(buttonColor)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}
