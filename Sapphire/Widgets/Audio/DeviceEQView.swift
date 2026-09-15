//
//  DeviceEQView.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-08-13.
//

import SwiftUI
import AppKit

struct DeviceEQView: View {
    let device: AudioDevice
    @StateObject private var audioManager = MultiAudioManager.shared
    @StateObject private var perAppStore = PerAppEQScopeStore()
    @AppStorage(AudioEQ.displayedBandCountDefaultsKey) private var displayedBandCount = AudioEQBandLayout.thirtyOne.rawValue

    private var bandLayout: AudioEQBandLayout {
        AudioEQBandLayout.resolved(from: displayedBandCount)
    }

    private var currentGains: [Double] {
        AudioEQ.normalize(audioManager.deviceSettings[device.id]?.customEQGains ?? AudioEQ.flat)
    }

    private var eqPresetBinding: Binding<EQPreset?> {
        Binding(
            get: {
                let gains = currentGains
                return EQPreset.allCases.filter { $0 != .custom }.first { $0.gainValues == gains }
            },
            set: { newPreset in
                guard let preset = newPreset else { return }
                var settings = audioManager.deviceSettings[device.id] ?? AudioDeviceSettings()
                settings.customEQGains = preset.gainValues
                audioManager.updateSettings(for: device.id, settings: settings)
            }
        )
    }

    private var customEQGainsBinding: Binding<[Double]> {
        Binding(
            get: { AudioEQ.displayedGains(from: currentGains, layout: bandLayout) },
            set: { newGains in
                var settings = audioManager.deviceSettings[device.id] ?? AudioDeviceSettings()
                settings.customEQGains = AudioEQ.canonicalGains(from: newGains, layout: bandLayout)
                audioManager.updateSettings(for: device.id, settings: settings)
            }
        )
    }

    private var bassGainBinding: Binding<Double> {
        Binding(
            get: { audioManager.deviceSettings[device.id]?.bassGain ?? 0.0 },
            set: { newValue in
                var settings = audioManager.deviceSettings[device.id] ?? AudioDeviceSettings()
                settings.bassGain = newValue
                audioManager.updateSettings(for: device.id, settings: settings)
            }
        )
    }

    private var applicableAppEQs: [PerAppEQScopeStore.AppEQScopeItem] {
        perAppStore.items(for: device.uid)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Master Equalizer")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.secondary)
                    Text(device.name)
                        .font(.system(size: 20, weight: .bold))
                }
                Spacer()
                EQBandCountPicker(selection: $displayedBandCount)
            }
            .padding(.horizontal, 24)
            .padding(.top, 0)

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
            .padding(.top, 14)
            .padding(.bottom, 10)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if applicableAppEQs.isEmpty {
                        ModernChip(title: "No App Overrides", isSelected: false) {}
                            .disabled(true)
                            .opacity(0.5)
                    } else {
                        ForEach(applicableAppEQs) { item in
                            AppEQScopeChip(item: item)
                        }
                    }
                }
                .padding(.horizontal, 24)
            }
            .padding(.bottom, 10)

            VStack(spacing: 8) {
                WaveformEQView(
                    gains: customEQGainsBinding,
                    range: AudioEQ.gainRange
                )
                .frame(height: 132)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.black.opacity(0.2))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.1), lineWidth: 1))
                )

                EQFrequencyAxis(frequencies: bandLayout.frequencies)

                EQBassControl(bassGain: bassGainBinding, bandGains: currentGains)
                    .padding(.top, 2)
            }
            .padding(.horizontal, 24)

            Spacer(minLength: 0)
        }
        .frame(width: 600, height: 446)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: customEQGainsBinding.wrappedValue)
        .animation(.spring(response: 0.25, dampingFraction: 0.85), value: applicableAppEQs.count)
    }
}

struct EQBandCountPicker: View {
    @Binding var selection: Int

    var body: some View {
        Picker("EQ Bands", selection: $selection) {
            ForEach(AudioEQBandLayout.allCases) { layout in
                Text(layout.displayName).tag(layout.rawValue)
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .fixedSize()
        .help("Choose how many equalizer frequency bands to adjust")
        .accessibilityLabel("Equalizer bands")
    }
}

@MainActor
fileprivate final class PerAppEQScopeStore: ObservableObject {
    struct AppEQScopeItem: Identifiable {
        let bundleID: String
        let appName: String
        let appliesToAllDevices: Bool

        var id: String { bundleID }
    }

    private var observer: NSObjectProtocol?

    init() {
        observer = NotificationCenter.default.addObserver(
            forName: .perAppAudioSettingsDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func items(for deviceUID: String) -> [AppEQScopeItem] {
        let scopeEntries = PerAppAudioController.shared.appEQScopeEntries()
        let appNameByBundleID: [String: String] = Dictionary(
            NSWorkspace.shared.runningApplications.compactMap {
                guard let bundleID = $0.bundleIdentifier else { return nil }
                return (bundleID, $0.localizedName ?? bundleID)
            },
            uniquingKeysWith: { existing, _ in existing }
        )

        return scopeEntries.compactMap { entry in
            if let targets = entry.targetDeviceUIDs, !targets.contains(deviceUID) {
                return nil
            }
            return AppEQScopeItem(
                bundleID: entry.bundleID,
                appName: appNameByBundleID[entry.bundleID] ?? entry.bundleID,
                appliesToAllDevices: entry.targetDeviceUIDs == nil
            )
        }
        .sorted { $0.appName.localizedCaseInsensitiveCompare($1.appName) == .orderedAscending }
    }
}

fileprivate struct AppEQScopeChip: View {
    let item: PerAppEQScopeStore.AppEQScopeItem

    var body: some View {
        Text(item.appName)
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(item.appliesToAllDevices ? Color.orange.opacity(0.22) : Color.accentColor.opacity(0.22))
            .foregroundColor(item.appliesToAllDevices ? .orange : .accentColor)
            .clipShape(Capsule())
    }
}

// MARK: - Reusable UI Components
struct ModernChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(isSelected ? Color.accentColor : Color.white.opacity(0.1))
                .foregroundColor(isSelected ? .white : .primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - WaveformEQView
struct WaveformEQView: View {
    @Binding var gains: [Double]
    let range: ClosedRange<Double>

    @State private var activeIndex: Int? = nil

    private var nodeDiameter: CGFloat { gains.count > 16 ? 8 : 16 }

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let points = gainsToPoints(size: size)
            let node = nodeDiameter

            ZStack {
                drawGrid(size: size, points: points)

                createWavePath(points: points, closed: true, size: size)
                    .fill(LinearGradient(
                        gradient: Gradient(colors: [Color.accentColor.opacity(0.4), Color.accentColor.opacity(0.05)]),
                        startPoint: .top,
                        endPoint: .bottom
                    ))

                createWavePath(points: points, closed: false, size: size)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))

                ForEach(points.indices, id: \.self) { index in
                    Circle()
                        .fill(activeIndex == index ? Color.white : Color.accentColor)
                        .frame(width: node, height: node)
                        .scaleEffect(activeIndex == index ? 1.35 : 1.0)
                        .shadow(color: .black.opacity(0.2), radius: 3, y: 2)
                        .overlay(
                             Circle().stroke(Color.accentColor, lineWidth: activeIndex == index ? 3 : 0)
                        )
                        .position(points[index])
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let count = gains.count
                        guard count > 1, size.width > 0 else { return }
                        let fraction = max(0, min(value.location.x / size.width, 1))
                        let index = Int((fraction * CGFloat(count - 1)).rounded())
                        gains[index] = gainValue(for: value.location.y, in: size)
                        activeIndex = index
                    }
                    .onEnded { _ in activeIndex = nil }
            )
        }
    }

    // MARK: - Helper Methods

    private func drawGrid(size: CGSize, points: [CGPoint]) -> some View {
        Path { path in
            let zeroGainY = gainToY(0, size: size)
            for point in points {
                path.move(to: CGPoint(x: point.x, y: 0))
                path.addLine(to: CGPoint(x: point.x, y: size.height))
            }
            path.move(to: CGPoint(x: 0, y: zeroGainY))
            path.addLine(to: CGPoint(x: size.width, y: zeroGainY))
        }
        .stroke(Color.primary.opacity(0.15), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
    }

    private func gainToY(_ gain: Double, size: CGSize) -> CGFloat {
        let drawingHeight = size.height - 2.0
        let normalizedGain = (gain - range.lowerBound) / (range.upperBound - range.lowerBound)
        let y = drawingHeight * (1 - normalizedGain) + 1.0
        return y.clamped(to: 1.0...(size.height - 1.0))
    }

    private func gainsToPoints(size: CGSize) -> [CGPoint] {
        let count = gains.count
        guard count > 1 else { return [] }
        return (0..<count).map { index in
            let x = size.width * (CGFloat(index) / CGFloat(count - 1))
            let y = gainToY(gains[index], size: size)
            return CGPoint(x: x, y: y)
        }
    }

    private func createWavePath(points: [CGPoint], closed: Bool, size: CGSize) -> Path {
        var path = Path()
        guard points.count > 1 else { return path }

        path.move(to: points[0])
        for i in 0..<(points.count - 1) {
            let p1 = points[i]
            let p2 = points[i+1]

            let control1 = CGPoint(x: (p1.x + p2.x) / 2, y: p1.y)
            let control2 = CGPoint(x: (p1.x + p2.x) / 2, y: p2.y)

            path.addCurve(to: p2, control1: control1, control2: control2)
        }

        if closed {
            path.addLine(to: CGPoint(x: size.width, y: size.height))
            path.addLine(to: CGPoint(x: 0, y: size.height))
            path.closeSubpath()
        }

        return path
    }

    private func gainValue(for y: CGFloat, in size: CGSize) -> Double {
        let drawingHeight = size.height - 2.0
        let clampedY = y.clamped(to: 1.0...(size.height - 1.0))
        let normalizedY = (clampedY - 1.0) / drawingHeight
        let gain = (1 - normalizedY) * (range.upperBound - range.lowerBound) + range.lowerBound
        return gain
    }

}

// MARK: - Shared EQ chrome

struct EQFrequencyAxis: View {
    let frequencies: [Double]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(frequencies.enumerated()), id: \.offset) { index, freq in
                Text(shouldLabel(index) ? AudioEQ.label(for: freq) : " ")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .fixedSize()
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func shouldLabel(_ index: Int) -> Bool {
        frequencies.count <= 15 || index.isMultiple(of: 4) || index == frequencies.count - 1
    }
}

struct EQBassControl: View {
    @Binding var bassGain: Double
    var bandGains: [Double]

    private var lowBandsBoosted: Bool {
        bandGains.prefix(9).contains { $0 > 3.0 }
    }

    private var cautionActive: Bool {
        bassGain > 0 || lowBandsBoosted
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Label("Clear Bass", systemImage: "dial.low.fill")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Text(bassGain == 0 ? "0 dB" : String(format: "%+.0f dB", bassGain))
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(bassGain == 0 ? Color.secondary : Color.accentColor)
                if bassGain != 0 {
                    Button {
                        bassGain = 0
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }

            Slider(value: $bassGain, in: AudioEQ.bassRange, step: 1)
                .tint(.accentColor)

            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                Text("Raising the Clear Bass slider or the low EQ bands adds level below ~150 Hz and can clip into audible distortion. Ease off if it sounds crunchy.")
                    .font(.system(size: 10))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(Color.orange.opacity(cautionActive ? 1.0 : 0.6))
        }
    }
}

// MARK: - Helper Extensions
fileprivate extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        return Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

fileprivate extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        return Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}