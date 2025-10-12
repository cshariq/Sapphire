//
//  WaveformView.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-07-10.
//
//
//
//
//
//

import SwiftUI
import Combine

struct CoreAnimationWaveformView: NSViewRepresentable {
    var isPlaying: Bool
    var barCount: Int
    var volumeScale: CGFloat
    var barThickness: CGFloat
    var leftGradientColor: Color
    var rightGradientColor: Color

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.frame = CGRect(x: 0, y: 0, width: 22, height: 22)
        context.coordinator.setupLayers(in: view.layer!, with: context)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.update(isPlaying: isPlaying, with: context)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator {
        var parent: CoreAnimationWaveformView
        var maskLayers: [CAShapeLayer] = []

        init(_ parent: CoreAnimationWaveformView) {
            self.parent = parent
        }

        func setupLayers(in parentLayer: CALayer, with context: Context) {
            let totalSpacing = CGFloat(parent.barCount - 1) * 3.0
            let totalWidth = CGFloat(parent.barCount) * parent.barThickness + totalSpacing
            var xOffset = (parentLayer.bounds.width - totalWidth) / 2.0

            for _ in 0..<parent.barCount {
                let barContainerLayer = CALayer()
                barContainerLayer.frame = CGRect(x: xOffset, y: 0, width: parent.barThickness, height: parentLayer.bounds.height)

                let gradientLayer = CAGradientLayer()
                gradientLayer.frame = barContainerLayer.bounds
                gradientLayer.colors = [
                    NSColor(parent.leftGradientColor).cgColor,
                    NSColor(parent.rightGradientColor).cgColor
                ]
                gradientLayer.startPoint = CGPoint(x: 0.5, y: 0.0)
                gradientLayer.endPoint = CGPoint(x: 0.5, y: 1.0)

                let maskLayer = CAShapeLayer()
                maskLayer.frame = barContainerLayer.bounds

                gradientLayer.mask = maskLayer
                barContainerLayer.addSublayer(gradientLayer)
                parentLayer.addSublayer(barContainerLayer)

                maskLayers.append(maskLayer)

                xOffset += parent.barThickness + 3.0
            }
        }

        func update(isPlaying: Bool, with context: Context) {
            self.parent = context.environment.coreAnimationWaveformView

            let minHeight = parent.barThickness

            for (index, maskLayer) in maskLayers.enumerated() {
                let animationKey = "pathAnimation"

                if let gradient = (maskLayer.superlayer as? CAGradientLayer) {
                     gradient.colors = [
                        NSColor(parent.leftGradientColor).cgColor,
                        NSColor(parent.rightGradientColor).cgColor
                    ]
                }

                if isPlaying && maskLayer.animation(forKey: animationKey) == nil {
                    let animation = CABasicAnimation(keyPath: "path")
                    let highValues = [0.5, 0.8, 0.65, 0.7, 0.9, 0.6]
                    let speeds = [1.8, 1.2, 1.4, 1.6, 1.0, 1.7]

                    let maxHeight = 22.0
                    let targetHeight = minHeight + (maxHeight - minHeight) * (highValues[index] * parent.volumeScale)

                    let fromY = (maskLayer.bounds.height - minHeight) / 2.0
                    let toY = (maskLayer.bounds.height - targetHeight) / 2.0

                    let fromPath = CGPath(roundedRect: CGRect(x: 0, y: fromY, width: parent.barThickness, height: minHeight),
                                         cornerWidth: parent.barThickness / 2,
                                         cornerHeight: parent.barThickness / 2,
                                         transform: nil)

                    let toPath = CGPath(roundedRect: CGRect(x: 0, y: toY, width: parent.barThickness, height: targetHeight),
                                       cornerWidth: parent.barThickness / 2,
                                       cornerHeight: parent.barThickness / 2,
                                       transform: nil)

                    maskLayer.path = fromPath

                    animation.fromValue = fromPath
                    animation.toValue = toPath
                    animation.duration = 1.5 / speeds[index]
                    animation.autoreverses = true
                    animation.repeatCount = .infinity
                    animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

                    maskLayer.add(animation, forKey: animationKey)

                } else if !isPlaying {
                    maskLayer.removeAllAnimations()
                    let finalY = (maskLayer.bounds.height - minHeight) / 2.0
                    let finalPath = CGPath(roundedRect: CGRect(x: 0, y: finalY, width: parent.barThickness, height: minHeight),
                                         cornerWidth: parent.barThickness / 2,
                                         cornerHeight: parent.barThickness / 2,
                                         transform: nil)
                    maskLayer.path = finalPath
                }
            }
        }
    }
}

private struct CoreAnimationWaveformViewKey: EnvironmentKey {
    static let defaultValue: CoreAnimationWaveformView = CoreAnimationWaveformView(isPlaying: false, barCount: 0, volumeScale: 0, barThickness: 0, leftGradientColor: .white, rightGradientColor: .white)
}

extension EnvironmentValues {
    var coreAnimationWaveformView: CoreAnimationWaveformView {
        get { self[CoreAnimationWaveformViewKey.self] }
        set { self[CoreAnimationWaveformViewKey.self] = newValue }
    }
}

struct WaveformView: View {
    @EnvironmentObject var musicManager: MusicManager
    @EnvironmentObject var settingsModel: SettingsModel

    @State private var isHovering = false
    @State private var volumeScale: CGFloat = 0.7

    enum TransientIcon: Equatable {
        case paused, played, skippedForward, skippedBackward

        var systemName: String {
            switch self {
            case .paused: return "pause.fill"
            case .played: return "play"
            case .skippedForward: return "forward.end.fill"
            case .skippedBackward: return "backward.end.fill"
            }
        }
    }

    private var barCount: Int {
        min(max(settingsModel.settings.waveformBarCount, 1), 6)
    }

    private var minHeight: CGFloat {
        settingsModel.settings.waveformBarThickness
    }

    private var waveformGradient: LinearGradient {
        LinearGradient(
            gradient: Gradient(colors: [musicManager.leftGradientColor, musicManager.rightGradientColor]),
            startPoint: .top,
            endPoint: .bottom
        )
    }

    var body: some View {
        ZStack {
            if isHovering {
                Button(action: {
                    if musicManager.isPlaying {
                        musicManager.pause()
                    } else {
                        musicManager.play()
                    }
                }) {
                    Image(systemName: musicManager.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(musicManager.accentColor)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .transition(.opacity.combined(with: .scale(scale: 0.8)))

            } else if let icon = musicManager.transientIcon {
                iconBody(systemName: icon.systemName)

            } else if musicManager.isPlaying && !settingsModel.settings.useStaticWaveform {
                animatedWaveformBody

            } else {
                staticWaveformBody
            }
        }
        .frame(width: 22, height: 22, alignment: .center)
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: musicManager.isPlaying)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovering)
        .animation(.default, value: musicManager.transientIcon)
        .onHover { hovering in
            self.isHovering = hovering
        }
        .onAppear(perform: setupInitialState)
        .onReceive(musicManager.volumePublisher.receive(on: RunLoop.main)) { newVolume in
            if settingsModel.settings.musicWaveformIsVolumeSensitive {
                self.volumeScale = CGFloat(newVolume)
            }
        }
        .onChange(of: settingsModel.settings.musicWaveformIsVolumeSensitive) { _, isSensitive in
            if !isSensitive {
                self.volumeScale = 0.7
            } else {
                self.volumeScale = CGFloat(musicManager.systemVolume)
            }
        }
    }

    private func setupInitialState() {
        if settingsModel.settings.musicWaveformIsVolumeSensitive {
            volumeScale = CGFloat(musicManager.systemVolume)
        } else {
            volumeScale = 0.7
        }
    }

    private var animatedWaveformBody: some View {
        let view = CoreAnimationWaveformView(
            isPlaying: musicManager.isPlaying,
            barCount: barCount,
            volumeScale: volumeScale,
            barThickness: settingsModel.settings.waveformBarThickness,
            leftGradientColor: musicManager.leftGradientColor,
            rightGradientColor: musicManager.rightGradientColor
        )
        return view.environment(\.coreAnimationWaveformView, view)
    }

    private var staticWaveformBody: some View {
        HStack(spacing: 3) {
            ForEach(0..<barCount, id: \.self) { _ in
                let barFill = settingsModel.settings.waveformUseGradient ?
                    AnyShapeStyle(waveformGradient) :
                    AnyShapeStyle(musicManager.accentColor)

                Capsule()
                    .fill(barFill)
                    .frame(width: settingsModel.settings.waveformBarThickness, height: minHeight)
            }
        }
        .frame(width: 18, height: 22)
        .transition(.opacity)
    }

    private func iconBody(systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(musicManager.accentColor)
            .transition(.opacity.animation(.easeOut(duration: 0.2)))
    }
}