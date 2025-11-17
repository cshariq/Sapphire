//
//  DeviceAdjustView.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-08-13.
//

import SwiftUI

struct DeviceAdjustView: View {
    let device: AudioDevice

    @StateObject private var audioManager = MultiAudioManager.shared

    @State private var settings: AudioDeviceSettings

    init(device: AudioDevice) {
        self.device = device
        _settings = State(initialValue: MultiAudioManager.shared.deviceSettings[device.id] ?? AudioDeviceSettings())
    }

    private var delayInMilliseconds: Binding<Double> {
        Binding(
            get: { settings.delay * 1000 },
            set: { settings.delay = $0 / 1000 }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {

            ScrollView {
                VStack(spacing: 40) {
                    BoldPillSlider(label: "Volume", value: $settings.volume, range: 0...1, specifier: "%.0f %%")
                    BoldPillSlider(label: "Delay", value: delayInMilliseconds, range: 0...500, specifier: "%.0f ms")
                    BoldPillSlider(label: "Balance", value: $settings.balance, range: 0...1, specifier: "%.1f")
                }
                .padding(.top, 20)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
        .frame(width: 600)
        .fixedSize(horizontal: false, vertical: true)
        .onChange(of: settings) { _, newSettings in
            audioManager.updateSettings(for: device.id, settings: newSettings)
        }
    }
}

// MARK: - BoldPillSlider (Corrected Version)
fileprivate struct BoldPillSlider: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let specifier: String

    private var displayValue: String {
        let finalValue: Double
        if label == "Volume" {
            finalValue = value * 100
        } else {
            finalValue = value
        }
        return String(format: specifier, finalValue)
    }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let progress = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
            let progressWidth = width * progress

            let textView = HStack {
                Text(label)
                    .fontWeight(.bold)
                Spacer()
                Text(displayValue)
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.bold)
            }
            .font(.system(size: 16))
            .padding(.horizontal, 20)

            ZStack(alignment: .leading) {
                Capsule().fill(Color.gray.opacity(0.25))
                textView.foregroundColor(.primary.opacity(0.8))

                ZStack {
                    Capsule().fill(Color.accentColor)
                    textView.foregroundColor(.white)
                }
                .mask(
                    Rectangle()
                        .frame(width: progressWidth)
                        .frame(maxWidth: .infinity, alignment: .leading)
                )
            }
            .clipShape(Capsule())
            .contentShape(Capsule())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let percentage = (gesture.location.x / width).clamped(to: 0...1)
                        let newValue = (range.upperBound - range.lowerBound) * Double(percentage) + range.lowerBound
                        self.value = newValue.clamped(to: range)
                    }
            )
        }
        .frame(height: 44)
    }
}