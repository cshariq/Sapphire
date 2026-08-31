//
//  FocusAmbientSoundManager.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-25
//

import Foundation
import Combine
import AVFoundation

@MainActor
final class FocusAmbientSoundManager: ObservableObject {
    static let shared = FocusAmbientSoundManager()

    @Published private(set) var isPlaying = false
    @Published var volume: Double = 0.4 {
        didSet { engine.mainMixerNode.outputVolume = Float(max(0, min(1, volume))) }
    }
    private(set) var type: FocusAmbientSoundType = .rain

    private let engine = AVAudioEngine()
    private var sourceNode: AVAudioSourceNode?
    private var generator: NoiseGenerator?

    private init() {}

    // MARK: - Control

    func start(type: FocusAmbientSoundType? = nil, volume: Double? = nil) {
        if let type { self.type = type }
        if let volume { self.volume = volume }
        guard !isPlaying else { return }
        rebuild()
        do {
            try engine.start()
            isPlaying = true
        } catch {
            print("[FocusAmbientSoundManager] Failed to start engine: \(error)")
        }
    }

    func stop() {
        if engine.isRunning { engine.stop() }
        if let node = sourceNode { engine.detach(node) }
        sourceNode = nil
        generator = nil
        isPlaying = false
    }

    func toggle() {
        isPlaying ? stop() : start()
    }

    func setType(_ newType: FocusAmbientSoundType) {
        guard newType != type else { return }
        type = newType
        if isPlaying { rebuild() }
    }

    private func rebuild() {
        if let node = sourceNode { engine.detach(node) }
        sourceNode = nil
        generator = nil

        let sampleRate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let gen = NoiseGenerator(type: type, sampleRate: sampleRate)
        generator = gen

        let node = AVAudioSourceNode { _, _, frameCount, audioBufferList -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            gen.render(into: buffers, frameCount: Int(frameCount))
            return noErr
        }
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = Float(max(0, min(1, volume)))
        sourceNode = node
    }
}

// MARK: - Procedural generators (runs on the audio render thread)

final class NoiseGenerator {
    private let type: FocusAmbientSoundType
    private let sampleRate: Double

    private var b0 = 0.0, b1 = 0.0, b2 = 0.0, b3 = 0.0, b4 = 0.0, b5 = 0.0, b6 = 0.0
    private var lastBrown = 0.0
    private var lpState = 0.0
    private var dropletTimer = 0.0
    private var droplets: [Droplet] = []

    private struct Droplet {
        var phase: Double
        var frequency: Double
        var envelope: Float
        var decay: Double
    }

    init(type: FocusAmbientSoundType, sampleRate: Double) {
        self.type = type
        self.sampleRate = sampleRate
    }

    func render(into buffers: UnsafeMutableAudioBufferListPointer, frameCount: Int) {
        guard frameCount > 0 else { return }
        for frame in 0..<frameCount {
            let sample: Float
            switch type {
            case .whiteNoise: sample = white()
            case .pinkNoise: sample = pink()
            case .brownNoise: sample = brown()
            case .rain: sample = rain()
            }
            for buffer in buffers {
                guard let ptr = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
                ptr[frame] = sample
            }
        }
    }

    private func white() -> Float {
        Float.random(in: -1...1)
    }

    private func pink() -> Float {
        let w = Double.random(in: -1...1)
        b0 = 0.99886 * b0 + w * 0.0555179
        b1 = 0.99332 * b1 + w * 0.0750759
        b2 = 0.96900 * b2 + w * 0.1538520
        b3 = 0.86650 * b3 + w * 0.3104856
        b4 = 0.55000 * b4 + w * 0.5329522
        b5 = -0.7616 * b5 - w * 0.0168980
        let out = (b0 + b1 + b2 + b3 + b4 + b5 + b6 + w * 0.5362) * 0.11
        b6 = w * 0.115926
        return Float(out)
    }

    private func brown() -> Float {
        let w = Double.random(in: -1...1)
        lastBrown = (lastBrown + 0.02 * w) / 1.02
        return Float(lastBrown * 3.5)
    }

    private func rain() -> Float {
        let alpha = 0.14
        lpState += alpha * (Double.random(in: -1...1) - lpState)
        var sample = Float(lpState * 2.2)

        dropletTimer -= 1.0 / sampleRate
        if dropletTimer <= 0 {
            dropletTimer = Double.random(in: 0.04...0.45)
            if droplets.count < 28 {
                droplets.append(Droplet(
                    phase: Double.random(in: 0...(2 * .pi)),
                    frequency: Double.random(in: 1600...6200),
                    envelope: Float.random(in: 0.12...0.5),
                    decay: Double.random(in: 0.003...0.02)
                ))
            }
        }
        for i in droplets.indices.reversed() {
            var droplet = droplets[i]
            droplet.phase += (droplet.frequency / sampleRate) * 2 * .pi
            droplet.envelope *= max(0, 1 - Float(droplet.decay))
            sample += Float(sin(droplet.phase)) * droplet.envelope
            if droplet.envelope < 0.002 {
                droplets.remove(at: i)
            } else {
                droplets[i] = droplet
            }
        }
        return sample * 0.45
    }
}