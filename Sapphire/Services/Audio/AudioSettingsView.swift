//
//  AudioSettingsView.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-10

import SwiftUI

struct AudioSettingsView: View {
    @EditingSettings var settings: SettingsEditingSession
    @ObservedObject private var audioManager = MultiAudioManager.shared
    @ObservedObject private var permissionsManager = PermissionsManager.shared
    @State private var showResetAppConfirmation = false
    @State private var showResetDeviceConfirmation = false
    @State private var mixerNavigationStack: [NotchWidgetMode] = []
    @State private var selectedAdjustment: AudioSettingsAdjustment?
    @AppStorage(AudioEQ.displayedBandCountDefaultsKey) private var displayedBandCount = AudioEQBandLayout.thirtyOne.rawValue

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                Text("Audio")
                    .font(.largeTitle.bold())
                    .padding(.bottom, 4)

                VStack(alignment: .leading, spacing: 0) {
                    Text("Notch")
                        .font(.headline)
                        .padding([.top, .horizontal])

                    CompactToggleRow(
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
                    CompactToggleRow(
                        title: "Haptic Feedback",
                        description: "Subtle vibration when adjusting audio controls.",
                        isOn: $settings.settings.hapticFeedbackEnabled
                    )
                    Divider().padding(.leading, 20)
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Equalizer Bands")
                            Text("Choose the number of frequency controls shown in app and device equalizers.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Picker("Equalizer Bands", selection: $displayedBandCount) {
                            ForEach(AudioEQBandLayout.allCases) { layout in
                                Text(layout.displayName).tag(layout.rawValue)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 110)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                }
                .modifier(SettingsContainerModifier())

                MicrophoneAmplifierSettingsView()
                    .modifier(SettingsContainerModifier())

                AudioSwitchingSettingsView()
                    .modifier(SettingsContainerModifier())

                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("App & Device Mixer")
                            .font(.headline)
                        Text("The same volume, routing, EQ, 8D, surround, balance, and delay controls available in the notch.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 14)

                    SystemAudioPanel(navigationStack: $mixerNavigationStack)
                        .frame(maxWidth: .infinity)
                        .frame(height: 430)
                }
                .modifier(SettingsContainerModifier())

                VStack(alignment: .leading, spacing: 0) {
                    Text("Reset")
                        .font(.headline)
                        .padding([.top, .horizontal])

                    AudioResetRow(
                        title: "Reset Per-App Adjustments",
                        subtitle: "Clears custom volumes, mutes, EQ, and 8D spatial audio for all apps.",
                        buttonTitle: "Reset Apps",
                        buttonColor: .red
                    ) {
                        showResetAppConfirmation = true
                    }
                    .alert("Reset Per-App Settings?", isPresented: $showResetAppConfirmation) {
                        Button("Cancel", role: .cancel) { }
                        Button("Reset", role: .destructive) { resetAllAppSettings() }
                    } message: {
                        Text("This restores default volume, flat EQ, surround, and 8D audio for every application.")
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
        .onChange(of: mixerNavigationStack.count) { _, _ in
            presentLatestMixerAdjustment()
        }
        .sheet(item: $selectedAdjustment) { adjustment in
            AudioSettingsAdjustmentSheet(adjustment: adjustment)
        }
    }

    private func presentLatestMixerAdjustment() {
        guard let destination = mixerNavigationStack.last else { return }
        mixerNavigationStack.removeAll()

        switch destination {
        case .multiAudioDeviceAdjust(let device):
            selectedAdjustment = .deviceAdjust(device)
        case .multiAudioEQ(let device):
            selectedAdjustment = .deviceEQ(device)
        case .earbudControls(let device):
            selectedAdjustment = .earbudControls(device)
        case .multiAudioAppEQ(let bundleID, let appName):
            selectedAdjustment = .appEQ(bundleID: bundleID, appName: appName)
        case .multiAudioApp8D(let bundleID, let appName):
            selectedAdjustment = .app8D(bundleID: bundleID, appName: appName)
        case .multiAudioAppSurround(let bundleID, let appName):
            selectedAdjustment = .appSurround(bundleID: bundleID, appName: appName)
        default:
            break
        }
    }

    private func resetAllAppSettings() {
        Task { @MainActor in
            PerAppAudioController.shared.clearAllPersistedState()
            MultiAudioManager.shared.clearAllEightDAudioSettings()
            MultiAudioManager.shared.resetAllTaps()
        }
    }

    private func resetAllDeviceSettings() {
        Task { @MainActor in
            MultiAudioManager.shared.clearAllDeviceSettings()
        }
    }
}

private enum AudioSettingsAdjustment: Identifiable {
    case deviceAdjust(AudioDevice)
    case deviceEQ(AudioDevice)
    case earbudControls(AudioDevice)
    case appEQ(bundleID: String, appName: String)
    case app8D(bundleID: String, appName: String)
    case appSurround(bundleID: String, appName: String)

    var id: String {
        switch self {
        case .deviceAdjust(let device):
            return "device-adjust-\(device.id)"
        case .deviceEQ(let device):
            return "device-eq-\(device.id)"
        case .earbudControls(let device):
            return "earbuds-\(device.id)"
        case .appEQ(let bundleID, _):
            return "app-eq-\(bundleID)"
        case .app8D(let bundleID, _):
            return "app-8d-\(bundleID)"
        case .appSurround(let bundleID, _):
            return "app-surround-\(bundleID)"
        }
    }
}

private struct AudioSettingsAdjustmentSheet: View {
    let adjustment: AudioSettingsAdjustment
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Audio Adjustment")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .frame(height: 48)

            Divider()

            adjustmentView
        }
        .background(Color.black)
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var adjustmentView: some View {
        switch adjustment {
        case .deviceAdjust(let device):
            DeviceAdjustView(device: device)
        case .deviceEQ(let device):
            DeviceEQView(device: device)
        case .earbudControls(let device):
            EarbudControlsView(device: device)
        case .appEQ(let bundleID, let appName):
            AppEQView(bundleID: bundleID, appName: appName)
        case .app8D(let bundleID, let appName):
            EightDAudioView(bundleID: bundleID, appName: appName)
        case .appSurround(let bundleID, let appName):
            SurroundAudioView(bundleID: bundleID, appName: appName)
        }
    }
}

// MARK: - Microphone gain preview

private struct MicrophoneAmplifierSettingsView: View {
    @ObservedObject private var mic = MicrophoneUsageManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Microphone Gain Preview")
                .font(.headline)
                .padding([.top, .horizontal])

            CompactToggleRow(
                title: "Preview gain",
                description: "Applies gain to Sapphire's live level meter so you can check clipping. Other apps still receive the original microphone signal.",
                isOn: $mic.amplifierEnabled
            )

            Divider().padding(.leading, 20)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Preview gain")
                    Spacer()
                    Text("×\(mic.amplifierGain, specifier: "%.1f")")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Slider(value: $mic.amplifierGain, in: 1...4, step: 0.1)
                    .tint(.orange)
                    .disabled(!mic.amplifierEnabled)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider().padding(.leading, 20)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label(mic.isClipping ? "Clipping detected" : "Live input level", systemImage: mic.isClipping ? "exclamationmark.triangle.fill" : "mic.fill")
                        .foregroundStyle(mic.isClipping ? .red : .primary)
                    Spacer()
                    Text("\(Int(mic.audioLevel * 100))%")
                        .font(.caption.monospacedDigit())
                }
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.secondary.opacity(0.18))
                        Capsule()
                            .fill(mic.isClipping ? Color.red : (mic.audioLevel > 0.85 ? Color.orange : Color.green))
                            .frame(width: proxy.size.width * CGFloat(mic.audioLevel))
                        Rectangle()
                            .fill(Color.red.opacity(0.8))
                            .frame(width: 2)
                            .offset(x: max(0, proxy.size.width - 2))
                    }
                }
                .frame(height: 8)
                Text(mic.isMicInUse ? (mic.isClipping ? "Lower the gain or microphone input level." : "Peak: \(Int(mic.peakLevel * 100))%") : "Start using the microphone to see its level.")
                    .font(.caption)
                    .foregroundStyle(mic.isClipping ? .red : .secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .onAppear { mic.beginMetering() }
        .onDisappear { mic.endMetering() }
    }
}

// MARK: - Rows

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
// MARK: - Output switching & microphone

private struct AudioSwitchingSettingsView: View {
    @ObservedObject private var switcher = AudioOutputSwitcher.shared
    @ObservedObject private var audio = MultiAudioManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Output Switching & Microphone")
                .font(.headline)
                .padding([.top, .horizontal])

            AudioShortcutRow(
                title: "Cycle output device",
                subtitle: "Makes the next output below the system default.",
                identifier: "audioOutputCycleShortcut",
                shortcut: $switcher.cycleShortcut
            )

            if !audio.availableOutputDevices.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Outputs in the cycle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(audio.availableOutputDevices) { device in
                        Toggle(device.name, isOn: cycleBinding(for: device.uid))
                            .toggleStyle(.checkbox)
                            .font(.system(size: 12))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 10)
            }

            Divider().padding(.leading, 20)

            CompactToggleRow(
                title: "Lower volume when headphones disconnect",
                description: "Drops the speakers to a safe level when headphones go away, and puts their volume back when the headphones return.",
                isOn: $switcher.lowerVolumeOnHeadphoneDisconnect
            )
            HStack {
                Text("Speaker level")
                Slider(value: $switcher.headphoneDisconnectLevel, in: 0...0.8, step: 0.05)
                Text("\(Int(switcher.headphoneDisconnectLevel * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 36, alignment: .trailing)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 10)
            .disabled(!switcher.lowerVolumeOnHeadphoneDisconnect)

            Divider().padding(.leading, 20)

            AudioShortcutRow(
                title: "Mute microphone",
                subtitle: "Toggles mute on every input device.",
                identifier: "microphoneMuteShortcut",
                shortcut: $switcher.micMuteShortcut
            )

            Divider().padding(.leading, 20)

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Preferred microphone")
                    Text("Kept as the system input, even when headphones with their own microphone connect.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Picker("Preferred microphone", selection: preferredInputBinding) {
                    Text("System choice").tag(String?.none)
                    ForEach(audio.availableInputDevices) { device in
                        Text(device.name).tag(String?.some(device.uid))
                    }
                    if let preferred = audio.preferredInputUID,
                       !audio.availableInputDevices.contains(where: { $0.uid == preferred }) {
                        Text("Disconnected device").tag(String?.some(preferred))
                    }
                }
                .labelsHidden()
                .frame(width: 200)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
    }

    private func cycleBinding(for uid: String) -> Binding<Bool> {
        Binding(
            get: { switcher.cycleDeviceUIDs.isEmpty || switcher.cycleDeviceUIDs.contains(uid) },
            set: { included in
                var uids = switcher.cycleDeviceUIDs.isEmpty ? audio.availableOutputDevices.map(\.uid) : switcher.cycleDeviceUIDs
                if included {
                    if !uids.contains(uid) { uids.append(uid) }
                } else {
                    uids.removeAll { $0 == uid }
                }
                switcher.cycleDeviceUIDs = uids
            }
        )
    }

    private var preferredInputBinding: Binding<String?> {
        Binding(
            get: { audio.preferredInputUID },
            set: { uid in
                if let uid, let device = audio.availableInputDevices.first(where: { $0.uid == uid }) {
                    audio.selectInputDevice(device)
                } else if uid == nil {
                    audio.clearPreferredInput()
                }
            }
        )
    }
}

private struct AudioShortcutRow: View {
    let title: String
    let subtitle: String
    let identifier: String
    @Binding var shortcut: KeyboardShortcut?
    @ObservedObject private var recorder = GlobalShortcutRecorder.shared

    private var isRecordingThis: Bool {
        recorder.isRecording && recorder.recordingIdentifier == identifier
    }

    private var shortcutText: String {
        guard let shortcut else { return "Not set" }
        var text = ""
        if shortcut.modifiers.contains(.control) { text += "⌃" }
        if shortcut.modifiers.contains(.option) { text += "⌥" }
        if shortcut.modifiers.contains(.shift) { text += "⇧" }
        if shortcut.modifiers.contains(.command) { text += "⌘" }
        return text + shortcut.key
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(isRecordingThis ? "Press keys…" : shortcutText)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(shortcut == nil && !isRecordingThis ? .secondary : .primary)
            Button(isRecordingThis ? "Cancel" : "Record") {
                if isRecordingThis {
                    recorder.stopRecording()
                } else if !recorder.isRecording {
                    recorder.startRecording(identifier: identifier) { key, flags in
                        shortcut = KeyboardShortcut(key: key, modifiers: flags)
                    }
                }
            }
            .buttonStyle(.bordered)
            if shortcut != nil {
                Button("Clear") { shortcut = nil }
                    .buttonStyle(.bordered)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }
}