//
//  AppEQView.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-08-13.
//

import SwiftUI

struct AppEQView: View {
    let bundleID: String
    let appName: String

    @StateObject private var perAppCtrl = PerAppVolumeStoreForEQ()
    @StateObject private var audioManager = MultiAudioManager.shared

    private var eqPresetBinding: Binding<EQPreset?> {
        Binding(
            get: {
                let currentGains = perAppCtrl.eqGains(for: bundleID)
                return EQPreset.allCases.filter { $0 != .custom }.first { $0.gainValues == currentGains }
            },
            set: { newPreset in
                guard let preset = newPreset else { return }
                perAppCtrl.setEQGains(preset.gainValues, for: bundleID)
            }
        )
    }

    private var customEQGainsBinding: Binding<[Double]> {
        Binding(
            get: { perAppCtrl.eqGains(for: bundleID) },
            set: { perAppCtrl.setEQGains($0, for: bundleID) }
        )
    }
    
    private var appVolumeBinding: Binding<Double> {
        Binding(
            get: { perAppCtrl.volume(for: bundleID) },
            set: { perAppCtrl.setVolume($0, for: bundleID) }
        )
    }

    private var allDevices: [AudioDevice] {
        let merged = audioManager.availableOutputDevices + audioManager.availableInputDevices
        var seen = Set<String>()
        return merged.filter { device in
            if seen.contains(device.uid) { return false }
            seen.insert(device.uid)
            return true
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var selectedUIDs: Set<String>? {
        perAppCtrl.targetDeviceUIDs(for: bundleID)
    }

    private let eqFrequencies = ["32", "64", "125", "250", "500", "1k", "2k", "4k", "8k", "16k"]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Equalizer & Mix")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.secondary)
                    Text(appName)
                        .font(.system(size: 20, weight: .bold))
                }
                Spacer()
                Image(systemName: "f_curve.curve.curve.right_filled")
                    .font(.title)
            }
            .padding(.horizontal, 24)
            .padding(.top, 0)
            .padding(.bottom, 12)
            
            // App Master Volume directly injected
            ModernGlassSlider(
                label: "App Volume",
                value: appVolumeBinding,
                range: 0...1.0,
                formatDisplay: { "\(Int($0 * 100))%" }
            )
            .padding(.horizontal, 24)
            .padding(.bottom, 12)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(EQPreset.allCases.filter { $0 != .custom }) { preset in
                        ModernChip(
                            title: preset.displayName,
                            isSelected: eqPresetBinding.wrappedValue == preset
                        ) {
                            eqPresetBinding.wrappedValue = preset
                        }
                    }
                }
                .padding(.horizontal, 24)
            }
            .padding(.bottom, 12)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ModernChip(title: "All Devices", isSelected: selectedUIDs == nil) {
                        perAppCtrl.setTargetDeviceUIDs(nil, for: bundleID)
                    }
                    ForEach(allDevices, id: \.uid) { device in
                        let isSelected = selectedUIDs?.contains(device.uid) == true
                        ModernChip(title: device.name, isSelected: isSelected) {
                            perAppCtrl.toggleTargetDeviceUID(device.uid, for: bundleID)
                        }
                    }
                }
                .padding(.horizontal, 24)
            }
            .padding(.bottom, 14)

            VStack(spacing: 12) {
                WaveformEQView(
                    gains: customEQGainsBinding,
                    range: -12.0...12.0
                )
                .frame(height: 140)

                HStack {
                    ForEach(eqFrequencies, id: \.self) { freq in
                        Text(freq)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .padding(.horizontal, 24)
        }
        .frame(width: 600, height: 400)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: customEQGainsBinding.wrappedValue)
        .animation(.spring(response: 0.25, dampingFraction: 0.85), value: selectedUIDs?.sorted() ?? ["all"])
    }
}

// MARK: - Reusable Slider adapted for glass backgrounds
fileprivate struct ModernGlassSlider: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let formatDisplay: (Double) -> String

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let normalized = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
            let progress = Swift.max(0, Swift.min(normalized, 1))
            let progressWidth = width * progress

            let textView = HStack {
                Text(label)
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(formatDisplay(value))
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
            }
            .padding(.horizontal, 16)

            ZStack(alignment: .leading) {
                // Background Track
                Capsule().fill(Color.black.opacity(0.15))
                
                // Background Text
                textView.foregroundColor(.primary.opacity(0.6))

                // Progress Track
                ZStack {
                    Capsule().fill(Color.accentColor)
                    
                    // Foreground Text
                    textView.foregroundColor(.white)
                }
                .mask(
                    Rectangle()
                        .frame(width: progressWidth)
                        .frame(maxWidth: .infinity, alignment: .leading)
                )
            }
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.1), lineWidth: 1))
            .contentShape(Capsule())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let percentage = Swift.max(0, Swift.min(gesture.location.x / width, 1))
                        let newValue = (range.upperBound - range.lowerBound) * Double(percentage) + range.lowerBound
                        self.value = Swift.max(range.lowerBound, Swift.min(newValue, range.upperBound))
                    }
            )
        }
        .frame(height: 38)
    }
}

@MainActor
fileprivate final class PerAppVolumeStoreForEQ: ObservableObject {
    func volume(for bundleID: String) -> Double {
        PerAppAudioController.shared.volume(for: bundleID)
    }
    
    func setVolume(_ vol: Double, for bundleID: String) {
        objectWillChange.send()
        PerAppAudioController.shared.setVolume(vol, for: bundleID)
    }

    func eqGains(for bundleID: String) -> [Double] {
        PerAppAudioController.shared.eqGains(for: bundleID)
    }

    func setEQGains(_ gains: [Double], for bundleID: String) {
        objectWillChange.send()
        PerAppAudioController.shared.setEQGains(gains, for: bundleID)
    }

    func targetDeviceUIDs(for bundleID: String) -> Set<String>? {
        PerAppAudioController.shared.targetDeviceUIDs(for: bundleID)
    }

    func setTargetDeviceUIDs(_ uids: Set<String>?, for bundleID: String) {
        objectWillChange.send()
        PerAppAudioController.shared.setEQTargetDeviceUIDs(uids, for: bundleID)
    }

    func toggleTargetDeviceUID(_ uid: String, for bundleID: String) {
        var updated = targetDeviceUIDs(for: bundleID) ?? []
        if updated.contains(uid) {
            updated.remove(uid)
        } else {
            updated.insert(uid)
        }
        setTargetDeviceUIDs(updated.isEmpty ? nil : updated, for: bundleID)
    }
}
