//
//  NotchMorphAnimation.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-10-08
//

import SwiftUI

enum NotchMorphTiming: Hashable, Sendable {
    case linear
    case easeIn
    case easeOut
    case easeInOut
    case bezier(x1: Double, y1: Double, x2: Double, y2: Double)

    var unitCurve: UnitCurve {
        switch self {
        case .linear: return .linear
        case .easeIn: return .easeIn
        case .easeOut: return .easeOut
        case .easeInOut: return .easeInOut
        case .bezier(let x1, let y1, let x2, let y2):
            return .bezier(startControlPoint: UnitPoint(x: x1, y: y1), endControlPoint: UnitPoint(x: x2, y: y2))
        }
    }

    func animation(duration: Double) -> Animation {
        switch self {
        case .linear: return .linear(duration: duration)
        case .easeIn: return .easeIn(duration: duration)
        case .easeOut: return .easeOut(duration: duration)
        case .easeInOut: return .easeInOut(duration: duration)
        case .bezier(let x1, let y1, let x2, let y2): return .timingCurve(x1, y1, x2, y2, duration: duration)
        }
    }
}

enum NotchMorphCurve: Hashable, Sendable {
    case spring(response: Double, dampingFraction: Double)
    case timing(NotchMorphTiming, duration: Double)

    var swiftUIAnimation: Animation {
        switch self {
        case .spring(let response, let dampingFraction):
            return .spring(response: response, dampingFraction: dampingFraction, blendDuration: 0)
        case .timing(let timing, let duration):
            return timing.animation(duration: duration)
        }
    }

    static let fallback = NotchMorphCurve.spring(response: 0.5, dampingFraction: 0.825)
}

// MARK: - Spring

struct NotchMorphSpringStepper: Hashable, Sendable {
    static let stepsPerSecond: Double = 300
    static let step: Double = 1 / stepsPerSecond

    let stiffness: Double
    let damping: Double

    init(response: Double, dampingFraction: Double) {
        let safeResponse = max(response, 0.0001)
        stiffness = pow(2 * .pi / safeResponse, 2)
        damping = 4 * .pi * dampingFraction / safeResponse
    }

    @inline(__always)
    func advance(position: inout Double, velocity: inout Double, target: Double) {
        let acceleration = -stiffness * (position - target) - damping * velocity
        velocity += acceleration * Self.step
        position += velocity * Self.step
    }

    static func steps(at elapsed: Double) -> Int {
        guard elapsed > 0, elapsed.isFinite else { return 0 }
        return Int((elapsed * stepsPerSecond + 1e-9).rounded(.down))
    }

    static func mergeSteps(at elapsed: Double) -> Int {
        guard elapsed >= 0, elapsed.isFinite else { return 0 }
        return Int((elapsed * stepsPerSecond + 1e-9).rounded(.down)) + 1
    }

    func isSettled(position: Double, velocity: Double, target: Double) -> Bool {
        let acceleration = -stiffness * (position - target) - damping * velocity
        if abs(acceleration) < Self.settleThreshold && abs(velocity) < Self.settleThreshold { return true }
        return isVisuallySettled(position: position, velocity: velocity, target: target)
    }

    static let settleThreshold: Double = 0.06

    static let visualSettleFraction: Double = 1.0 / 2000

    var angularFrequency: Double { stiffness.squareRoot() }

    func isVisuallySettled(position: Double, velocity: Double, target: Double) -> Bool {
        let limit = abs(target) * Self.visualSettleFraction
        let offset = position - target
        let carry = velocity / angularFrequency
        return offset * offset + carry * carry <= limit * limit
    }
}

// MARK: - SwiftUI side

struct NotchMorphAnimation: CustomAnimation {
    let curve: NotchMorphCurve

    private var base: Animation { curve.swiftUIAnimation }

    func animate<V: VectorArithmetic>(value: V, time: TimeInterval, context: inout AnimationContext<V>) -> V? {
        guard let current = base.animate(value: value, time: time, context: &context) else { return nil }
        if case .spring(let response, let dampingFraction) = curve,
           let velocity = base.velocity(value: value, time: time, context: context) {
            let stepper = NotchMorphSpringStepper(response: response, dampingFraction: dampingFraction)
            var remaining = value
            remaining -= current
            let swing = remaining.magnitudeSquared + velocity.magnitudeSquared / stepper.stiffness
            let limit = value.magnitudeSquared * NotchMorphSpringStepper.visualSettleFraction
                * NotchMorphSpringStepper.visualSettleFraction
            if swing <= limit { return nil }
        }
        return current
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
        let unwrapped = (previous.base as? NotchMorphAnimation)?.base ?? previous
        return base.shouldMerge(previous: unwrapped, value: value, time: time, context: &context)
    }

    static func == (lhs: NotchMorphAnimation, rhs: NotchMorphAnimation) -> Bool { lhs.curve == rhs.curve }
    func hash(into hasher: inout Hasher) { hasher.combine(curve) }
}

extension Animation {
    static func notchMorph(_ curve: NotchMorphCurve) -> Animation {
        Animation(NotchMorphAnimation(curve: curve))
    }

    static func notchMorphSpring(response: Double, dampingFraction: Double) -> Animation {
        .notchMorph(.spring(response: response, dampingFraction: dampingFraction))
    }

    static func notchMorphTiming(_ timing: NotchMorphTiming, duration: Double) -> Animation {
        .notchMorph(.timing(timing, duration: duration))
    }

    var notchMorphCurve: NotchMorphCurve? {
        (base as? NotchMorphAnimation)?.curve
    }
}