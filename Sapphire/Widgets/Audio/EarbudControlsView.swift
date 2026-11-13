//
//  EarbudControlsView.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-21

import SwiftUI

struct EarbudControlsView: View {
    var device: AudioDevice? = nil
    @ObservedObject private var manager = EarbudControlManager.shared
    @State private var finding = false

    private var snap: EarbudControlSnapshot { manager.snapshot }

    private var bandCount: Int { snap.vendor == .sony ? 5 : 9 }

    private var frequencies: [Double] {
        snap.vendor == .sony
            ? [400, 1_000, 2_500, 6_300, 16_000]
            : [60, 150, 300, 600, 1_000, 2_500, 4_000, 6_000, 8_000]
    }

    private var eqPresets: [(String, String)] {
        snap.vendor == .sony
            ? [
                (String(localized: "Off"), "off"), (String(localized: "Bright"), "bright"), (String(localized: "Excited"), "excited"),
                (String(localized: "Mellow"), "mellow"), (String(localized: "Relaxed"), "relaxed"), (String(localized: "Vocal"), "vocal"),
                (String(localized: "Bass Boost"), "bassBoost"), (String(localized: "Treble Boost"), "trebleBoost"),
                (String(localized: "Speech"), "speech"), (String(localized: "Manual"), "custom")
            ]
            : [
                (String(localized: "Normal"), "off"), (String(localized: "Bass Boost"), "bassBoost"), (String(localized: "Soft"), "soft"),
                (String(localized: "Dynamic"), "dynamic"), (String(localized: "Clear"), "clear"), (String(localized: "Treble Boost"), "trebleBoost"),
                (String(localized: "Custom"), "custom")
            ]
    }

    private var noiseModes: [(String, String, String)] {
        var modes: [(String, String, String)] = [
            (String(localized: "Off"), "off", "speaker.slash.fill"),
            (String(localized: "ANC"), "anc", "ear.badge.waveform"),
            (String(localized: "Ambient"), "ambient", "ear")
        ]
        if snap.supportsAdaptive {
            modes.append((String(localized: "Adaptive"), "adaptive", "waveform.path"))
        }
        return modes
    }

    private var eqGainsBinding: Binding<[Double]> {
        Binding(
            get: {
                let raw = snap.customEQBands
                return (0..<bandCount).map { Double(raw.indices.contains($0) ? raw[$0] : 0) }
            },
            set: { values in
                manager.setCustomEQ(values.map { Int($0.rounded()) })
            }
        )
    }

    private var bassBinding: Binding<Double> {
        Binding(
            get: { Double(snap.bassGain) },
            set: { manager.setBass(Int($0.rounded())) }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 10)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    if snap.supportsANC {
                        noiseSection
                    }
                    if snap.supportsEQ {
                        eqSection
                    }
                    extrasSection
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }
        }
        .frame(width: 600, height: 446)
        .background(Color.black)
        .clipShape(Rectangle())
        .animation(.spring(response: 0.25, dampingFraction: 0.85), value: snap.noiseMode)
        .animation(.spring(response: 0.25, dampingFraction: 0.85), value: snap.eqPreset)
        .onAppear {
            if let device {
                manager.present(for: device)
            } else {
                manager.presentCurrent()
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: snap.vendor == .sony ? String(localized: "SONY HEADPHONES") : "GALAXY BUDS")
                    .font(.system(size: 10, weight: .black))
                    .foregroundStyle(.white.opacity(0.4))
                    .tracking(1.2)
                Text(snap.name.isEmpty ? (device?.name ?? snap.vendor.displayName) : snap.name)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 6) {
                HStack(spacing: 6) {
                    statusPill
                    Image(systemName: snap.vendor == .sony ? "headphones" : "earbuds")
                        .font(.title3)
                        .foregroundStyle(snap.connected ? Color.accentColor : .white.opacity(0.35))
                }
                batteryRow
            }
        }
    }

    private var statusPill: some View {
        Text(statusLabel)
            .font(.system(size: 10, weight: .bold))
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background(Capsule().fill(snap.connected ? Color.green.opacity(0.22) : Color.white.opacity(0.08)))
            .foregroundStyle(snap.connected ? Color.green : .secondary)
    }

    private var statusLabel: String {
        if snap.connected {
            return snap.ownedLocally ? String(localized: "This Mac") : String(localized: "On Phone")
        }
        return String(localized: "Idle")
    }

    @ViewBuilder
    private var batteryRow: some View {
        HStack(spacing: 5) {
            if snap.batteryLeft > 0 || snap.batteryRight > 0 {
                batteryBadge("L", snap.batteryLeft)
                batteryBadge("R", snap.batteryRight)
                if snap.batteryCase > 0 { batteryBadge("Case", snap.batteryCase) }
            } else if snap.batteryMain > 0 {
                batteryBadge("Batt", snap.batteryMain)
            }
        }
    }

    private func batteryBadge(_ label: LocalizedStringKey, _ percent: Int) -> some View {
        HStack(spacing: 3) {
            Text(label)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)
            Text(verbatim: ChineseFormatting.isActive ? (Double(percent) / 100).formatted(.percent.precision(.fractionLength(0))) : "\(percent)%")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(percent <= 15 ? Color.orange : .white.opacity(0.85))
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(Capsule().fill(Color.white.opacity(0.06)))
    }

    // MARK: - Noise

    private var noiseSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Noise Control")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(noiseModes, id: \.1) { title, wire, icon in
                        Button {
                            manager.setNoise(wire)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: icon)
                                    .font(.system(size: 11, weight: .semibold))
                                Text(title)
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(snap.noiseMode == wire ? Color.accentColor : Color.white.opacity(0.1))
                            .foregroundColor(snap.noiseMode == wire ? .white : .primary)
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if snap.noiseMode == "anc", snap.vendor == .galaxy {
                HStack(spacing: 8) {
                    Text("ANC Strength")
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                    ModernChip(title: String(localized: "Low"), isSelected: !snap.ancHigh) { manager.setAncHigh(false) }
                    ModernChip(title: String(localized: "High"), isSelected: snap.ancHigh) { manager.setAncHigh(true) }
                }
            } else if snap.noiseMode == "ambient" {
                EarbudAmbientSlider(
                    level: Binding(
                        get: { Double(snap.ambientLevel) },
                        set: { manager.setAmbientLevel(Int($0.rounded())) }
                    ),
                    range: snap.vendor == .sony ? 1...20 : 0...4
                )
            }
        }
    }

    // MARK: - EQ

    private var eqSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Equalizer")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(eqPresets, id: \.1) { title, wire in
                        ModernChip(title: title, isSelected: snap.eqPreset == wire) {
                            manager.setEQ(wire)
                        }
                    }
                }
            }

            VStack(spacing: 6) {
                WaveformEQView(gains: eqGainsBinding, range: -10...10)
                    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: snap.customEQBands)
                    .frame(height: 110)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(.black.opacity(0.2))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(.white.opacity(0.1), lineWidth: 1)
                            )
                    )

                EQFrequencyAxis(frequencies: frequencies)

                if snap.vendor == .sony {
                    EQBassControl(bassGain: bassBinding, bandGains: eqGainsBinding.wrappedValue)
                }
            }
        }
    }

    // MARK: - Extras (compact, matches EQ chrome)

    private var extrasSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("earbud.extras")

            VStack(spacing: 0) {
                if snap.supportsDSEE {
                    compactToggle(
                        title: "DSEE Extreme",
                        detail: "Upscale compressed audio",
                        symbol: "waveform.badge.plus",
                        isOn: Binding(get: { snap.dsee }, set: { manager.setDsee($0) })
                    )
                }
                if snap.supportsSeamless {
                    if snap.supportsDSEE { extrasDivider }
                    compactToggle(
                        title: "Seamless Connection",
                        detail: "Stay linked to Mac and phone",
                        symbol: "antenna.radiowaves.left.and.right",
                        isOn: Binding(get: { snap.seamless }, set: { manager.setSeamless($0) })
                    )
                }
                if snap.vendor == .galaxy {
                    if snap.supportsDSEE || snap.supportsSeamless {
                        extrasDivider
                    }
                    if snap.supportsDetectConversations {
                        compactToggle(
                            title: "Detect Conversations",
                            detail: "Ambient when you start talking",
                            symbol: "person.wave.2.fill",
                            isOn: Binding(get: { snap.detectConversations }, set: { manager.setDetectConversations($0) })
                        )
                        if snap.detectConversations {
                            extrasDivider
                            HStack(spacing: 8) {
                                Text("Resume after")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                ForEach([(0, String(localized: "5s")), (1, String(localized: "10s")), (2, String(localized: "15s"))], id: \.0) { item in
                                    Button(item.1) {
                                        manager.setDetectConversationsDuration(item.0)
                                    }
                                    .buttonStyle(.bordered)
                                    .tint(snap.detectConversationsDuration == item.0 ? .accentColor : .secondary)
                                    .controlSize(.small)
                                }
                            }
                            .padding(.vertical, 6)
                        }
                    }
                    if snap.supportsGaming {
                        if snap.supportsDetectConversations { extrasDivider }
                        compactToggle(
                            title: "Gaming Mode",
                            detail: "Lower latency for games and video",
                            symbol: "gamecontroller.fill",
                            isOn: Binding(get: { snap.gamingMode }, set: { manager.setGamingMode($0) })
                        )
                    }
                    if snap.supportsSpatial {
                        extrasDivider
                        compactToggle(
                            title: "Spatial Audio",
                            detail: "Immersive spatial sound on the buds",
                            symbol: "dot.radiowaves.left.and.right",
                            isOn: Binding(get: { snap.spatialAudio }, set: { manager.setSpatialAudio($0) })
                        )
                    }
                    if snap.supportsTouchLock {
                        extrasDivider
                        compactToggle(
                            title: "Lock Touchpad",
                            detail: "Ignore accidental touches",
                            symbol: "lock.fill",
                            isOn: Binding(get: { snap.touchpadLocked }, set: { manager.setTouchpadLock($0) })
                        )
                        if snap.supportsOutsideDoubleTap {
                            extrasDivider
                            compactToggle(
                                title: "Outside Double Tap",
                                detail: "Double-tap the outside for volume",
                                symbol: "hand.tap.fill",
                                isOn: Binding(get: { snap.outsideDoubleTap }, set: { manager.setOutsideDoubleTap($0) })
                            )
                        }
                        extrasDivider
                        touchOptionRow(title: "Touch · Left", selected: snap.touchLeft) {
                            manager.setTouchLeft($0)
                        }
                        extrasDivider
                        touchOptionRow(title: "Touch · Right", selected: snap.touchRight) {
                            manager.setTouchRight($0)
                        }
                    }
                    if snap.supportsPassthrough {
                        extrasDivider
                        compactToggle(
                            title: "Passthrough",
                            detail: "Relieve ambient pressure (Buds Live)",
                            symbol: "wind",
                            isOn: Binding(get: { snap.passthrough }, set: { manager.setPassthrough($0) })
                        )
                    }
                    if snap.supportsAmbientExtras {
                        extrasDivider
                        compactToggle(
                            title: "Sidetone",
                            detail: "Hear your own voice while talking",
                            symbol: "mic.fill",
                            isOn: Binding(get: { snap.sidetone }, set: { manager.setSidetone($0) })
                        )
                        extrasDivider
                        compactToggle(
                            title: "Extra High Ambient",
                            detail: "Louder ambient / passthrough",
                            symbol: "speaker.wave.3.fill",
                            isOn: Binding(get: { snap.extraHighAmbient }, set: { manager.setExtraHighAmbient($0) })
                        )
                        extrasDivider
                        compactToggle(
                            title: "Amplify Ambient",
                            detail: "Boost ambient pickup",
                            symbol: "waveform.badge.plus",
                            isOn: Binding(get: { snap.amplifyAmbient }, set: { manager.setAmplifyAmbient($0) })
                        )
                        extrasDivider
                        compactToggle(
                            title: "Speak Seamlessly",
                            detail: "Keep ANC while talking",
                            symbol: "mouth.fill",
                            isOn: Binding(get: { snap.speakSeamlessly }, set: { manager.setSpeakSeamlessly($0) })
                        )
                    }
                    if snap.supportsANC {
                        extrasDivider
                        compactToggle(
                            title: "ANC with One Earbud",
                            detail: "Keep noise cancelling on a single bud",
                            symbol: "ear",
                            isOn: Binding(get: { snap.ancOneEarbud }, set: { manager.setAncOneEarbud($0) })
                        )
                    }
                    extrasDivider
                    compactToggle(
                        title: "Auto Switch Audio",
                        detail: "Follow playback between devices",
                        symbol: "arrow.left.arrow.right",
                        isOn: Binding(get: { snap.autoSwitchAudio }, set: { manager.setAutoSwitchAudio($0) })
                    )
                    extrasDivider
                    compactToggle(
                        title: "Pause When One Bud Removed",
                        detail: "Pause media if you take one out",
                        symbol: "pause.circle",
                        isOn: Binding(get: { snap.pauseOnOneBudRemoved }, set: { manager.setPauseOnOneBud($0) })
                    )
                    if snap.supportsCallExtras {
                        extrasDivider
                        compactToggle(
                            title: "In-Band Ringtone",
                            detail: "Hear the call ring in the buds",
                            symbol: "bell.fill",
                            isOn: Binding(get: { snap.inBandRingtone }, set: { manager.setInBandRingtone($0) })
                        )
                        extrasDivider
                        compactToggle(
                            title: "Calls Through Buds",
                            detail: "Route phone calls to the earbuds",
                            symbol: "phone.fill",
                            isOn: Binding(get: { snap.callPathControl }, set: { manager.setCallPathControl($0) })
                        )
                        extrasDivider
                        compactToggle(
                            title: "Ambient During Calls",
                            detail: "Hear surroundings on calls",
                            symbol: "ear.badge.waveform",
                            isOn: Binding(get: { snap.ambientDuringCall }, set: { manager.setAmbientDuringCall($0) })
                        )
                        if snap.supportsExtraClearCall {
                            extrasDivider
                            compactToggle(
                                title: "Extra Clear Call Sound",
                                detail: "Boost voice clarity on calls",
                                symbol: "waveform",
                                isOn: Binding(get: { snap.extraClearCall }, set: { manager.setExtraClearCall($0) })
                            )
                        }
                    }
                    if snap.supportsFitTest {
                        extrasDivider
                        Button {
                            manager.startFitTest()
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "ear.fill")
                                    .foregroundStyle(.cyan)
                                    .frame(width: 22)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(verbatim: snap.fitTesting ? String(localized: "Testing fit…") : String(localized: "Earbud Fit Test"))
                                        .font(.system(size: 13, weight: .semibold))
                                    Text(verbatim: fitTestDetail)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                    }
                    extrasDivider
                    Button {
                        manager.enterPairingMode()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "link.badge.plus")
                                .foregroundStyle(.cyan)
                                .frame(width: 22)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Enter Pairing Mode")
                                    .font(.system(size: 13, weight: .semibold))
                                Text("Make the buds discoverable for a new device")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                }
                if snap.supportsFind || snap.vendor == .galaxy {
                    extrasDivider
                    findRow
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
            )
        }
    }

    private var fitTestDetail: String {
        if snap.fitTesting { return String(localized: "Keep still while the buds play tones") }
        guard snap.fitLeftGood || snap.fitRightGood else {
            return String(localized: "Check seal for best ANC and bass")
        }
        let left = snap.fitLeftGood ? String(localized: "Good") : String(localized: "Adjust")
        let right = snap.fitRightGood ? String(localized: "Good") : String(localized: "Adjust")
        return String(localized: "L \(left) · R \(right)", comment: "Left and right earbud fit-test results")
    }

    private var extrasDivider: some View {
        Divider().opacity(0.2).padding(.leading, 34)
    }

    private func touchOptionRow(
        title: LocalizedStringKey,
        selected: GalaxyTouchOption,
        onSelect: @escaping (GalaxyTouchOption) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                ForEach(GalaxyTouchOption.allCases) { option in
                    Button(option.displayName) {
                        onSelect(option)
                    }
                    .buttonStyle(.bordered)
                    .tint(selected == option ? .accentColor : .secondary)
                    .controlSize(.small)
                }
            }
            .padding(.bottom, 4)
        }
        .padding(.vertical, 4)
    }

    private func compactToggle(
        title: LocalizedStringKey,
        detail: LocalizedStringKey,
        symbol: String,
        isOn: Binding<Bool>
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isOn.wrappedValue ? Color.accentColor : .secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            SettingsSwitch(isOn: isOn)
        }
        .padding(.vertical, 8)
    }

    private var findRow: some View {
        HStack(spacing: 10) {
            Image(systemName: finding ? "speaker.wave.3.fill" : "location.magnifyingglass")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(finding ? Color.orange : Color.accentColor)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: finding ? String(localized: "Ringing…") : String(localized: "Find Earbuds"))
                    .font(.system(size: 13, weight: .semibold))
                Text(verbatim: finding ? String(localized: "Playing a tone on both buds") : String(localized: "Ring them if you set them down"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Button {
                finding.toggle()
                manager.find(finding)
            } label: {
                Text(verbatim: finding ? String(localized: "Stop") : String(localized: "Ring"))
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(finding ? Color.orange.opacity(0.28) : Color.accentColor.opacity(0.28))
                    .foregroundStyle(finding ? Color.orange : Color.accentColor)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 8)
    }

    private func sectionLabel(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .textCase(.uppercase)
            .font(.system(size: 10, weight: .black))
            .foregroundStyle(.secondary)
            .tracking(1.1)
    }
}

private struct EarbudAmbientSlider: View {
    @Binding var level: Double
    var range: ClosedRange<Double>

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Ambient Level", systemImage: "ear")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Text("\(Int(level))")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.accentColor)
            }
            Slider(value: $level, in: range, step: 1)
                .tint(.accentColor)
        }
    }
}
