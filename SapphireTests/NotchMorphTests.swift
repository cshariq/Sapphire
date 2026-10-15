//
//  NotchMorphTests.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-10-08

import SwiftUI
import XCTest
@testable import Sapphire

@MainActor
final class NotchMorphTests: XCTestCase {
    func testSpringMatchesSwiftUI() {
        var channel = NotchMorphChannel(value: 0)
        channel.setTarget(100, curve: .spring(response: 0.5, dampingFraction: 0.6), at: 0)
        XCTAssertEqual(channel.value(at: 0.033410916665161494), 8.202430317581712, accuracy: 1e-9)
        XCTAssertEqual(channel.value(at: 0.09170066667138599), 40.3331069557289, accuracy: 1e-9)
    }

    func testSpringInterruptedBySpringMatchesSwiftUIMerge() {
        var channel = NotchMorphChannel(value: 0)
        channel.setTarget(100, curve: .spring(response: 0.5, dampingFraction: 0.6), at: 0)
        channel.setTarget(40, curve: .spring(response: 0.3, dampingFraction: 0.9), at: 0.199979875003919)
        XCTAssertEqual(channel.value(at: 0.2083842916690628), 96.03037097382122, accuracy: 1e-9)
        XCTAssertEqual(channel.value(at: 0.2834559166658437), 67.68509028870461, accuracy: 1e-9)
        XCTAssertEqual(channel.value(at: 0.44997200000216253), 40.95045136547514, accuracy: 1e-9)
        let end = try? XCTUnwrap(channel.endTime)
        XCTAssertEqual(channel.value(at: (end ?? 0) + 0.01), 40)
    }

    func testTimingCurveInterruptedBySpringMatchesSwiftUIMerge() {
        var channel = NotchMorphChannel(value: 0)
        channel.setTarget(100, curve: .timing(.easeInOut, duration: 0.4), at: 0)
        XCTAssertEqual(channel.value(at: 0.0750015416633687), 7.151222229003906, accuracy: 1e-6)
        channel.setTarget(40, curve: .spring(response: 0.3, dampingFraction: 0.9), at: 0.20000645833351882)
        XCTAssertEqual(channel.value(at: 0.20832474999770056), 49.862872858754315, accuracy: 1e-6)
        XCTAssertEqual(channel.value(at: 0.31667220833332976), 42.58274972576277, accuracy: 1e-6)
    }

    func testTimingCurveAfterSpringBlendsFromItsPresentedValue() {
        var channel = NotchMorphChannel(value: 0)
        channel.setTarget(100, curve: .spring(response: 0.5, dampingFraction: 0.6), at: 0)
        let interruption = 0.1916961250026361
        channel.setTarget(40, curve: .timing(.easeInOut, duration: 0.3), at: interruption)
        XCTAssertEqual(
            channel.value(at: interruption + 0.041654708329588175),
            103.092496915570706 - 2.4344658138313204,
            accuracy: 1e-6
        )
    }

    func testJumpDropsRunningAnimation() {
        var channel = NotchMorphChannel(value: 10)
        channel.setTarget(100, curve: .spring(response: 0.4, dampingFraction: 0.55), at: 0)
        channel.setTarget(50, curve: nil, at: 0.1)
        XCTAssertEqual(channel.value(at: 0.15), 50)
        XCTAssertNil(channel.endTime)
    }

    func testEngineSettlesAtTargetAndReportsOvershoot() {
        let engine = NotchMorphEngine()
        engine.setTargets(.size, 200, 32, curve: nil, at: 0)
        engine.setTargets(.size, 600, 200, curve: .spring(response: 0.4, dampingFraction: 0.55), at: 1)
        XCTAssertEqual(engine.sample(at: 1).width, 200, accuracy: 1e-9)
        XCTAssertTrue(engine.isAnimating(at: 1.1))
        XCTAssertGreaterThan(engine.peakSize(from: 1).width, 600, "the underdamped open spring overshoots")
        let end = engine.endTime ?? 0
        XCTAssertFalse(engine.isAnimating(at: end))
        XCTAssertEqual(engine.sample(at: end).width, 600, accuracy: 0.01)
    }

    func testMorphAnimationRunsTheBuiltInSpring() {
        let wrapped = Animation.notchMorphSpring(response: 0.4, dampingFraction: 0.55)
        XCTAssertEqual(wrapped.notchMorphCurve, .spring(response: 0.4, dampingFraction: 0.55))
        XCTAssertEqual(
            NotchMorphCurve.spring(response: 0.4, dampingFraction: 0.55).swiftUIAnimation,
            Animation.spring(response: 0.4, dampingFraction: 0.55, blendDuration: 0)
        )
        XCTAssertNil(Animation.spring(response: 0.4, dampingFraction: 0.55).notchMorphCurve)
    }

    func testEngineMatchesSwiftUIRunningTheMorphAnimation() throws {
        let model = MorphProbeModel()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 40, height: 40),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: MorphProbeRoot(model: model))
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }
        pump(0.2)

        let first = MorphRecording()
        let second = MorphRecording()
        withAnimation(Animation(MorphRecorder(base: .notchMorphSpring(response: 0.5, dampingFraction: 0.6), recording: first))) {
            model.value = 100
        }
        pump(0.2)
        withAnimation(Animation(MorphRecorder(base: .notchMorphSpring(response: 0.3, dampingFraction: 0.9), recording: second))) {
            model.value = 40
        }
        pump(1.2)

        try XCTSkipIf(first.samples.count < 3 || second.samples.isEmpty, "no frames were rendered")
        let mergeTime = try XCTUnwrap(second.mergeTime, "SwiftUI merges a spring into a running spring")

        var channel = NotchMorphChannel(value: 0)
        channel.setTarget(100, curve: .spring(response: 0.5, dampingFraction: 0.6), at: 0)
        for sample in first.samples where sample.time <= mergeTime {
            XCTAssertEqual(channel.value(at: sample.time), sample.value, accuracy: 1e-6)
        }
        channel.setTarget(40, curve: .spring(response: 0.3, dampingFraction: 0.9), at: mergeTime)
        for sample in second.samples {
            XCTAssertEqual(channel.value(at: sample.time), sample.value, accuracy: 1e-6)
        }
    }

    private func pump(_ seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    // MARK: Geometry

    func testOutlineRectIsCentredAtTheTop() {
        let rect = NotchMorphGeometry.rect(size: CGSize(width: 537.3, height: 179.1), canvasWidth: 1001)
        XCTAssertEqual(rect.minX, (1001 - 537.3) / 2, accuracy: 1e-9)
        XCTAssertEqual(rect.minY, 0)
        XCTAssertEqual(rect.width, 537.3, accuracy: 1e-9)
        XCTAssertEqual(rect.height, 179.1, accuracy: 1e-9)
    }

    func testRestAlignmentMatchesSwiftUISettledFrame() {
        let rect = NotchMorphGeometry.rect(size: CGSize(width: 537.3, height: 179.1), canvasWidth: 1001)
        XCTAssertEqual(NotchMorphGeometry.pixelAligned(rect, scale: 2), CGRect(x: 232, y: 0, width: 537, height: 179))
    }

    func testLayerRectFlipsForBottomUpLayers() {
        let rect = CGRect(x: 10, y: 0, width: 100, height: 30)
        XCTAssertEqual(NotchMorphGeometry.layerRect(rect, canvasHeight: 500, topDown: true), rect)
        XCTAssertEqual(
            NotchMorphGeometry.layerRect(rect, canvasHeight: 500, topDown: false),
            CGRect(x: 10, y: 470, width: 100, height: 30)
        )
    }

    func testCropIsTheOutlineTopCentredOnThePlane() {
        let crop = NotchMorphGeometry.cropRect(
            containerSize: CGSize(width: 600, height: 240),
            outline: CGSize(width: 400, height: 120)
        )
        XCTAssertEqual(crop, CGRect(x: 100, y: 0, width: 400, height: 120))
        let overshoot = NotchMorphGeometry.cropRect(
            containerSize: CGSize(width: 600, height: 240),
            outline: CGSize(width: 640, height: 260)
        )
        XCTAssertEqual(overshoot, CGRect(x: -20, y: 0, width: 640, height: 260))
    }
}

// MARK: - SwiftUI probe

private final class MorphProbeModel: ObservableObject {
    @Published var value: Double = 0
}

private struct MorphProbeView: View, Animatable {
    var value: Double
    var animatableData: Double {
        get { value }
        set { value = newValue }
    }
    var body: some View { Color.clear.frame(width: 10, height: 10) }
}

private struct MorphProbeRoot: View {
    @ObservedObject var model: MorphProbeModel
    var body: some View { MorphProbeView(value: model.value) }
}

private final class MorphRecording: @unchecked Sendable {
    struct Sample {
        let time: TimeInterval
        let value: Double
    }
    var samples: [Sample] = []
    var mergeTime: TimeInterval?
}

private struct MorphRecorder: CustomAnimation {
    let base: Animation
    let recording: MorphRecording

    func animate<V: VectorArithmetic>(value: V, time: TimeInterval, context: inout AnimationContext<V>) -> V? {
        let result = base.animate(value: value, time: time, context: &context)
        if let result = result as? Double {
            recording.samples.append(.init(time: time, value: result))
        }
        return result
    }

    func velocity<V: VectorArithmetic>(value: V, time: TimeInterval, context: AnimationContext<V>) -> V? {
        base.velocity(value: value, time: time, context: context)
    }

    func shouldMerge<V: VectorArithmetic>(
        previous: Animation,
        value: V,
        time: TimeInterval,
        context: inout AnimationContext<V>
    ) -> Bool {
        let unwrapped = (previous.base as? MorphRecorder)?.base ?? previous
        let merges = base.shouldMerge(previous: unwrapped, value: value, time: time, context: &context)
        if merges { recording.mergeTime = time }
        return merges
    }

    static func == (lhs: MorphRecorder, rhs: MorphRecorder) -> Bool {
        lhs.base == rhs.base && lhs.recording === rhs.recording
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(base)
        hasher.combine(ObjectIdentifier(recording))
    }
}