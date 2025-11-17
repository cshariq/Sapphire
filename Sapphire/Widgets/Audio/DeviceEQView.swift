//
//  DeviceEQView.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-08-13.
//

import SwiftUI

struct DeviceEQView: View {
    let device: AudioDevice

    @StateObject private var audioManager = MultiAudioManager.shared

    private var eqPresetBinding: Binding<EQPreset> {
        Binding(
            get: { audioManager.deviceSettings[device.id]?.equalizer ?? .flat },
            set: { newPreset in
                var settings = audioManager.deviceSettings[device.id] ?? AudioDeviceSettings()
                settings.equalizer = newPreset
                if newPreset != .custom {
                    settings.customEQGains = newPreset.gainValues
                }
                audioManager.updateSettings(for: device.id, settings: settings)
            }
        )
    }

    private var customEQGainsBinding: Binding<[Double]> {
        Binding(
            get: { audioManager.deviceSettings[device.id]?.customEQGains ?? EQPreset.flat.gainValues },
            set: { newGains in
                var settings = audioManager.deviceSettings[device.id] ?? AudioDeviceSettings()
                settings.customEQGains = newGains
                if settings.equalizer != .custom {
                    settings.equalizer = .custom
                }
                audioManager.updateSettings(for: device.id, settings: settings)
            }
        )
    }

    private let eqFrequencies = ["32", "64", "125", "250", "500", "1k", "2k", "4k", "8k", "16k"]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {

            // MARK: - Preset Selector List
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(EQPreset.allCases) { preset in
                        PresetButton(
                            title: preset.displayName,
                            isSelected: eqPresetBinding.wrappedValue == preset
                        ) {
                            eqPresetBinding.wrappedValue = preset
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
            .padding(.horizontal, -20)

            // MARK: - Waveform Equalizer
            VStack {
                WaveformEQView(
                    gains: customEQGainsBinding,
                    range: -12.0...12.0
                )
                .frame(height: 160)
                .padding(.top, 20)
                .padding([.horizontal, .bottom])
                .background(Color.gray.opacity(0.15))
                .cornerRadius(12)

                HStack {
                    ForEach(eqFrequencies, id: \.self) { freq in
                        Text(freq)
                            .font(.caption)
                            .fontWeight(.medium)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
                .padding(.horizontal, 5)
            }
            .padding(.top)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
        .frame(width: 600, height: 300)
        .fixedSize(horizontal: false, vertical: true)
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: customEQGainsBinding.wrappedValue)
    }
}

// MARK: - WaveformEQView
struct WaveformEQView: View {
    @Binding var gains: [Double]
    let range: ClosedRange<Double>

    @State private var activeIndex: Int? = nil

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let points = gainsToPoints(size: size)

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
                        .frame(width: 16, height: 16)
                        .scaleEffect(activeIndex == index ? 1.2 : 1.0)
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
                        let (index, _) = closestPoint(to: value.location, in: points)
                        let newGain = gainValue(for: value.location.y, in: size)

                        gains[index] = newGain
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

    private func closestPoint(to location: CGPoint, in points: [CGPoint]) -> (Int, CGFloat) {
        points.enumerated().map { (index, point) in
            (index, point.distance(to: location))
        }
        .min(by: { $0.1 < $1.1 }) ?? (0, .infinity)
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

fileprivate extension CGPoint {
    func distance(to point: CGPoint) -> CGFloat {
        return sqrt(pow(x - point.x, 2) + pow(y - point.y, 2))
    }
}

struct PresetButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .fontWeight(isSelected ? .bold : .regular)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(isSelected ? Color.accentColor : Color.gray.opacity(0.15))
                .foregroundColor(isSelected ? .white : .primary)
                .cornerRadius(10)
        }
        .buttonStyle(.plain)
        .scaleEffect(isSelected ? 1.05 : 1.0)
    }
}