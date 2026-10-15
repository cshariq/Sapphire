//
//  NotchMorphEngine.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-10-08
//

import AppKit
import QuartzCore
import SwiftUI
import os

struct NotchMorphValues: Equatable {
    var width: CGFloat
    var height: CGFloat
    var cornerRadius: CGFloat
    var bottomCornerRadius: CGFloat
    var satellites = NotchSatellitePresence.none

    static let zero = NotchMorphValues(width: 0, height: 0, cornerRadius: 0, bottomCornerRadius: 0)

    var size: CGSize { CGSize(width: width, height: height) }
}

struct NotchMorphChannel {
    private struct SpringRun {
        let stepper: NotchMorphSpringStepper
        let origin: CFTimeInterval
        let initialPosition: Double
        let initialVelocity: Double
        var steps = 0
        var position: Double
        var velocity: Double
        var finishedAtStep: Int?
        var settleBound: Int = 0

        init(stepper: NotchMorphSpringStepper, origin: CFTimeInterval, position: Double, velocity: Double) {
            self.stepper = stepper
            self.origin = origin
            self.initialPosition = position
            self.initialVelocity = velocity
            self.position = position
            self.velocity = velocity
        }

        mutating func state(after count: Int, target: (Int) -> Double) -> (position: Double, velocity: Double) {
            if count < steps {
                steps = 0
                position = initialPosition
                velocity = initialVelocity
            }
            while steps < count {
                stepper.advance(position: &position, velocity: &velocity, target: target(steps))
                steps += 1
            }
            return (position, velocity)
        }
    }

    private enum Kind {
        case spring(SpringRun)
        case timing(curve: UnitCurve, duration: Double, start: CFTimeInterval)
    }

    private struct Entry {
        var target: Double
        var kind: Kind
    }

    private static let maximumSpringSteps = Int(10 * NotchMorphSpringStepper.stepsPerSecond)

    private(set) var target: Double
    private var base: Double
    private var entries: [Entry] = []

    init(value: Double) {
        target = value
        base = value
    }

    var isIdle: Bool { entries.isEmpty }

    mutating func setTarget(_ newTarget: Double, curve: NotchMorphCurve?, at now: CFTimeInterval) {
        guard newTarget.isFinite else { return }
        guard abs(newTarget - target) > 1e-9 else { return }
        prune(at: now)
        defer { target = newTarget }

        guard let curve else {
            entries.removeAll()
            base = newTarget
            return
        }

        switch curve {
        case .spring(let response, let dampingFraction):
            let stepper = NotchMorphSpringStepper(response: response, dampingFraction: dampingFraction)
            guard let last = entries.indices.last else {
                base = target
                let relativeTarget = newTarget - base
                var run = SpringRun(stepper: stepper, origin: now, position: 0, velocity: 0)
                run.settleBound = Self.settleBound(of: run, target: { _ in relativeTarget })
                entries = [Entry(target: newTarget, kind: .spring(run))]
                return
            }
            let carried = relativeState(ofEntry: last, at: now)
            var run = SpringRun(stepper: stepper, origin: now, position: carried.position, velocity: carried.velocity)
            entries[last] = Entry(target: newTarget, kind: .spring(run))
            if last == 0 {
                let relativeTarget = newTarget - base
                run.settleBound = Self.settleBound(of: run, target: { _ in relativeTarget })
            } else {
                run.settleBound = settleBound(ofEntry: last, run: run)
            }
            entries[last] = Entry(target: newTarget, kind: .spring(run))

        case .timing(let timing, let duration):
            if entries.isEmpty { base = target }
            entries.append(Entry(
                target: newTarget,
                kind: .timing(curve: timing.unitCurve, duration: max(0, duration), start: now)
            ))
        }
    }

    mutating func value(at time: CFTimeInterval) -> Double {
        presented(upTo: entries.count, at: time)
    }

    var endTime: CFTimeInterval? {
        entries.compactMap { entry -> CFTimeInterval? in
            switch entry.kind {
            case .spring(let run):
                let steps = run.finishedAtStep ?? run.settleBound
                return run.origin + Double(steps) * NotchMorphSpringStepper.step
            case .timing(_, let duration, let start):
                return start + duration
            }
        }.max()
    }

    mutating func prune(at time: CFTimeInterval) {
        while let first = entries.first, isFinished(first, at: time) {
            base = first.target
            entries.removeFirst()
        }
        if entries.isEmpty { base = target }
    }

    // MARK: Composition

    private mutating func presented(upTo count: Int, at time: CFTimeInterval) -> Double {
        var presented = base
        for index in 0..<min(count, entries.count) {
            presented = presentedValue(ofEntry: index, below: presented, at: time)
        }
        return presented
    }

    private mutating func presentedValue(ofEntry index: Int, below: Double, at time: CFTimeInterval) -> Double {
        let entry = entries[index]
        if isFinished(entry, at: time) { return entry.target }
        let value = entry.target - below
        switch entry.kind {
        case .timing(let curve, let duration, let start):
            let progress = duration > 0 ? min(1, max(0, (time - start) / duration)) : 1
            return below + value * curve.value(at: progress)
        case .spring(var run):
            let count = NotchMorphSpringStepper.steps(at: time - run.origin)
            let state: (position: Double, velocity: Double)
            if index == 0 {
                state = run.state(after: count, target: { _ in value })
            } else {
                let origin = run.origin
                let target = entry.target
                state = run.state(after: count, target: { step in
                    target - self.presented(upTo: index, at: origin + Double(step) * NotchMorphSpringStepper.step)
                })
            }
            let settled = run.stepper.isSettled(position: state.position, velocity: state.velocity, target: value)
            if settled { run.finishedAtStep = min(run.finishedAtStep ?? count, count) }
            entries[index].kind = .spring(run)
            return settled ? entry.target : below + state.position
        }
    }

    private mutating func relativeState(ofEntry index: Int, at time: CFTimeInterval) -> (position: Double, velocity: Double) {
        let below = presented(upTo: index, at: time)
        let entry = entries[index]
        let value = entry.target - below
        switch entry.kind {
        case .timing(let curve, let duration, let start):
            guard duration > 0 else { return (value, 0) }
            let progress = min(1, max(0, (time - start) / duration))
            return (value * curve.value(at: progress), 0)
        case .spring(var run):
            if isFinished(entry, at: time) { return (value, 0) }
            let count = NotchMorphSpringStepper.mergeSteps(at: time - run.origin)
            let state: (position: Double, velocity: Double)
            if index == 0 {
                state = run.state(after: count, target: { _ in value })
            } else {
                let origin = run.origin
                let target = entry.target
                state = run.state(after: count, target: { step in
                    target - self.presented(upTo: index, at: origin + Double(step) * NotchMorphSpringStepper.step)
                })
            }
            entries[index].kind = .spring(run)
            return state
        }
    }

    private func isFinished(_ entry: Entry, at time: CFTimeInterval) -> Bool {
        switch entry.kind {
        case .spring(let run):
            let steps = NotchMorphSpringStepper.steps(at: time - run.origin)
            if let finished = run.finishedAtStep, steps >= finished { return true }
            return steps >= run.settleBound
        case .timing(_, let duration, let start):
            return time - start >= duration
        }
    }

    private static let settledRun = 60

    private static func settleBound(of run: SpringRun, target: (Int) -> Double) -> Int {
        var position = run.initialPosition
        var velocity = run.initialVelocity
        var runStart: Int?
        for step in 0..<maximumSpringSteps {
            let goal = target(step)
            if run.stepper.isSettled(position: position, velocity: velocity, target: goal) {
                let start = runStart ?? step
                runStart = start
                if step - start >= settledRun { return start }
            } else {
                runStart = nil
            }
            run.stepper.advance(position: &position, velocity: &velocity, target: goal)
        }
        return maximumSpringSteps
    }

    private mutating func settleBound(ofEntry index: Int, run: SpringRun) -> Int {
        let origin = run.origin
        let target = entries[index].target
        return Self.settleBound(of: run, target: { step in
            target - self.presented(upTo: index, at: origin + Double(step) * NotchMorphSpringStepper.step)
        })
    }
}

struct NotchMorphFrame: Equatable {
    var time: CFTimeInterval
    var values: NotchMorphValues
    var isMoving: Bool
}

struct NotchMorphTimeline {
    static let step: CFTimeInterval = 1.0 / 120

    let begin: CFTimeInterval
    let frames: [NotchMorphFrame]
    let keyTimes: [NSNumber]

    init(begin: CFTimeInterval, frames: [NotchMorphFrame]) {
        self.begin = begin
        self.frames = frames
        let last = max(1, frames.count - 1)
        keyTimes = frames.indices.map { NSNumber(value: Double($0) / Double(last)) }
    }

    var duration: CFTimeInterval { Self.step * Double(max(1, frames.count - 1)) }
    var end: CFTimeInterval { begin + duration }
    var first: NotchMorphValues { frames.first?.values ?? .zero }
    var last: NotchMorphValues { frames.last?.values ?? .zero }

    func animation(_ keyPath: String, values: [Any], on layer: CALayer, discrete: Bool = false) -> CAKeyframeAnimation {
        let animation = CAKeyframeAnimation(keyPath: keyPath)
        if discrete, values.count > 1 {
            animation.values = Array(values.dropLast())
            animation.keyTimes = keyTimes
            animation.calculationMode = .discrete
        } else {
            animation.values = values
            animation.keyTimes = keyTimes
            animation.calculationMode = .linear
        }
        animation.duration = duration
        animation.beginTime = layer.convertTime(begin, from: nil)
        animation.fillMode = .backwards
        return animation
    }
}

@MainActor
final class NotchMorphEngine: ObservableObject {
    enum Group { case size, radii, satellites }

    enum Event {
        case retarget
        case settle
    }

    private var width = NotchMorphChannel(value: 0)
    private var height = NotchMorphChannel(value: 0)
    private var cornerRadius = NotchMorphChannel(value: 0)
    private var bottomCornerRadius = NotchMorphChannel(value: 0)
    private var satelliteChannels = [NotchMorphChannel](repeating: NotchMorphChannel(value: 0), count: NotchSatelliteSlot.count)
    private(set) var hasTarget = false
    private(set) var generation: UInt64 = 0

    private(set) var currentFrame = NotchMorphFrame(time: 0, values: .zero, isMoving: false)

    private struct PendingTarget {
        let group: Group
        let values: [CGFloat]
        let curve: NotchMorphCurve?
    }
    private var pending: [PendingTarget] = []

    private struct Observer {
        weak var owner: AnyObject?
        let handler: @MainActor (Event) -> Void
    }
    private var observers: [ObjectIdentifier: Observer] = [:]

    private struct Renderer {
        weak var owner: AnyObject?
        let render: @MainActor (NotchMorphFrame) -> Void
        let animate: (@MainActor (NotchMorphTimeline) -> Void)?
    }
    private var renderers: [ObjectIdentifier: Renderer] = [:]

    private let driver = NotchMorphFrameDriver()

    private(set) var activeTimeline: NotchMorphTimeline?
    private var flushScheduled = false
    private var settleWork: DispatchWorkItem?

    private var usesTimelines: Bool {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "notchMorphForceDisplayLink") { return false }
        #endif
        let live = renderers.values.filter { $0.owner != nil }
        return !live.isEmpty && live.allSatisfy { $0.animate != nil }
    }

    #if DEBUG
    private var loggedUnknownAnimation = false
    #endif

    init() {
        driver.onFrame = { [weak self] time in self?.tick(at: time) ?? false }
    }

    var target: NotchMorphValues {
        NotchMorphValues(
            width: width.target,
            height: height.target,
            cornerRadius: cornerRadius.target,
            bottomCornerRadius: bottomCornerRadius.target,
            satellites: satellitePresence { $0.target }
        )
    }

    // MARK: Input

    func setTargets(_ group: Group, _ first: CGFloat, _ second: CGFloat, animation: Animation?) {
        setTargets(group, values: [first, second], animation: animation)
    }

    func setSatellites(_ presence: NotchSatellitePresence, animation: Animation?) {
        setTargets(.satellites, values: NotchSatelliteSlot.allCases.map { presence[$0] }, animation: animation)
    }

    private func setTargets(_ group: Group, values: [CGFloat], animation: Animation?) {
        let curve = curve(for: animation)
        guard hasTarget || group == .size else {
            setTargets(group, values: values, curve: nil, at: CACurrentMediaTime())
            return
        }
        guard hasTarget else {
            setTargets(group, values: values, curve: nil, at: CACurrentMediaTime())
            renderNow()
            return
        }
        let queued = pending.last { $0.group == group }
        let current = queued?.values ?? currentTargets(of: group)
        guard zip(values, current).contains(where: { abs($0 - $1) > 1e-9 }) else { return }
        pending.append(PendingTarget(group: group, values: values, curve: curve))
        if usesTimelines {
            scheduleTimelineFlush()
        } else if !driver.start() {
            applyPending(at: CACurrentMediaTime())
            renderNow()
        }
    }

    // MARK: Timelines

    private func scheduleTimelineFlush() {
        guard !flushScheduled else { return }
        flushScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.flushScheduled = false
            self.flushTimeline()
        }
    }

    private func flushTimeline() {
        guard !pending.isEmpty else { return }
        guard usesTimelines else {
            if !driver.start() {
                applyPending(at: CACurrentMediaTime())
                renderNow()
            }
            return
        }
        driver.stop()
        let now = CACurrentMediaTime()
        applyPending(at: now)
        settleWork?.cancel()
        settleWork = nil
        let settled = NotchMorphFrame(time: now, values: target, isMoving: false)
        guard let end = endTime, end > now else {
            activeTimeline = nil
            currentFrame = settled
            prune(at: now)
            render(settled)
            notify(.settle)
            return
        }

        let step = NotchMorphTimeline.step
        let count = min(Int(((end - now) / step).rounded(.up)), Int(4 / step))
        var frames: [NotchMorphFrame] = []
        frames.reserveCapacity(count + 1)
        for index in 0..<count {
            let time = now + Double(index) * step
            frames.append(NotchMorphFrame(time: time, values: sample(at: time), isMoving: true))
        }
        frames.append(NotchMorphFrame(time: now + Double(count) * step, values: target, isMoving: false))
        let timeline = NotchMorphTimeline(begin: now, frames: frames)
        activeTimeline = timeline
        currentFrame = settled
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for renderer in Array(renderers.values) where renderer.owner != nil {
            renderer.render(settled)
            renderer.animate?(timeline)
        }
        CATransaction.commit()

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.settleWork = nil
            self.activeTimeline = nil
            let time = CACurrentMediaTime()
            self.prune(at: time)
            self.currentFrame = NotchMorphFrame(time: time, values: self.target, isMoving: false)
            self.render(self.currentFrame)
            self.notify(.settle)
        }
        settleWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + timeline.duration + 0.02, execute: work)
    }

    func setTargets(_ group: Group, _ first: CGFloat, _ second: CGFloat, curve: NotchMorphCurve?, at now: CFTimeInterval) {
        setTargets(group, values: [first, second], curve: curve, at: now)
    }

    private func setTargets(_ group: Group, values: [CGFloat], curve: NotchMorphCurve?, at now: CFTimeInterval) {
        let jump = curve == nil || !hasTarget
        let first = values.first ?? 0
        let second = values.count > 1 ? values[1] : 0
        switch group {
        case .size:
            let changed = abs(Double(first) - width.target) > 1e-9 || abs(Double(second) - height.target) > 1e-9
            guard changed || !hasTarget else { return }
            width.setTarget(Double(first), curve: jump ? nil : curve, at: now)
            height.setTarget(Double(second), curve: jump ? nil : curve, at: now)
            hasTarget = true
        case .radii:
            let changed = abs(Double(first) - cornerRadius.target) > 1e-9
                || abs(Double(second) - bottomCornerRadius.target) > 1e-9
            guard changed else { return }
            cornerRadius.setTarget(Double(first), curve: hasTarget ? curve : nil, at: now)
            bottomCornerRadius.setTarget(Double(second), curve: hasTarget ? curve : nil, at: now)
        case .satellites:
            let changed = zip(values, satelliteChannels).contains { abs(Double($0) - $1.target) > 1e-9 }
            guard changed else { return }
            for (index, value) in values.enumerated() where index < satelliteChannels.count {
                satelliteChannels[index].setTarget(Double(value), curve: hasTarget ? curve : nil, at: now)
            }
        }
        generation &+= 1
        notify(.retarget)
    }

    private func curve(for animation: Animation?) -> NotchMorphCurve? {
        guard let animation else { return nil }
        if let morph = animation.notchMorphCurve { return morph }
        #if DEBUG
        if !loggedUnknownAnimation {
            loggedUnknownAnimation = true
            Logger(subsystem: Bundle.main.bundleIdentifier ?? "Sapphire", category: "NotchMorph")
                .debug("Notch outline changed under a non-morph animation; using the default spring")
        }
        #endif
        return .fallback
    }

    private func currentTargets(of group: Group) -> [CGFloat] {
        switch group {
        case .size: return [CGFloat(width.target), CGFloat(height.target)]
        case .radii: return [CGFloat(cornerRadius.target), CGFloat(bottomCornerRadius.target)]
        case .satellites: return satelliteChannels.map { CGFloat($0.target) }
        }
    }

    private func sampleSatellites(at time: CFTimeInterval) -> NotchSatellitePresence {
        var presence = NotchSatellitePresence.none
        for slot in NotchSatelliteSlot.allCases {
            presence[slot] = CGFloat(satelliteChannels[slot.index].value(at: time))
        }
        return presence
    }

    private func satellitePresence(_ value: (NotchMorphChannel) -> Double) -> NotchSatellitePresence {
        var presence = NotchSatellitePresence.none
        for slot in NotchSatelliteSlot.allCases { presence[slot] = CGFloat(value(satelliteChannels[slot.index])) }
        return presence
    }

    private func applyPending(at time: CFTimeInterval) {
        let changes = pending
        pending.removeAll()
        for change in changes {
            setTargets(change.group, values: change.values, curve: change.curve, at: time)
        }
    }

    // MARK: Clock

    func setLinkHost(_ view: NSView) {
        driver.setHost(view)
        if usesTimelines {
            if !pending.isEmpty { scheduleTimelineFlush() }
            return
        }
        if !pending.isEmpty || isAnimating(at: CACurrentMediaTime()) {
            if !driver.start() {
                applyPending(at: CACurrentMediaTime())
                renderNow()
            }
        }
    }

    func linkHostDidLeaveWindow(_ view: NSView) {
        guard driver.isHost(view) else { return }
        driver.stop()
        applyPending(at: CACurrentMediaTime())
        renderNow()
    }

    private func tick(at time: CFTimeInterval) -> Bool {
        if !pending.isEmpty { applyPending(at: time) }
        let moving = isAnimating(at: time)
        currentFrame = NotchMorphFrame(time: time, values: moving ? sample(at: time) : target, isMoving: moving)
        render(currentFrame)
        guard moving else {
            prune(at: time)
            notify(.settle)
            return false
        }
        return true
    }

    private func renderNow() {
        let now = CACurrentMediaTime()
        if !driver.isRunning || !isAnimating(at: now) {
            currentFrame = NotchMorphFrame(time: now, values: target, isMoving: false)
        }
        render(currentFrame)
    }

    private func prune(at time: CFTimeInterval) {
        width.prune(at: time)
        height.prune(at: time)
        cornerRadius.prune(at: time)
        bottomCornerRadius.prune(at: time)
        for index in satelliteChannels.indices { satelliteChannels[index].prune(at: time) }
    }

    // MARK: Output

    func sample(at time: CFTimeInterval) -> NotchMorphValues {
        NotchMorphValues(
            width: CGFloat(width.value(at: time)),
            height: CGFloat(height.value(at: time)),
            cornerRadius: CGFloat(cornerRadius.value(at: time)),
            bottomCornerRadius: CGFloat(bottomCornerRadius.value(at: time)),
            satellites: sampleSatellites(at: time)
        )
    }

    var endTime: CFTimeInterval? {
        ([width.endTime, height.endTime, cornerRadius.endTime, bottomCornerRadius.endTime]
         + satelliteChannels.map(\.endTime)).compactMap { $0 }.max()
    }

    func isAnimating(at time: CFTimeInterval) -> Bool {
        guard let endTime else { return false }
        return endTime > time
    }

    func peakSize(from start: CFTimeInterval) -> CGSize {
        var peak = target.size
        guard let end = endTime, end > start else { return peak }
        var time = start
        let step = 1.0 / 120
        while time < end {
            peak.width = max(peak.width, CGFloat(width.value(at: time)))
            peak.height = max(peak.height, CGFloat(height.value(at: time)))
            time += step
        }
        return peak
    }

    // MARK: Consumers

    func addRenderer(
        _ owner: AnyObject,
        render: @escaping @MainActor (NotchMorphFrame) -> Void,
        animate: (@MainActor (NotchMorphTimeline) -> Void)? = nil
    ) {
        renderers = renderers.filter { $0.value.owner != nil }
        renderers[ObjectIdentifier(owner)] = Renderer(owner: owner, render: render, animate: animate)
    }

    func removeRenderer(_ owner: AnyObject) {
        renderers[ObjectIdentifier(owner)] = nil
    }

    func addObserver(_ owner: AnyObject, handler: @escaping @MainActor (Event) -> Void) {
        observers = observers.filter { $0.value.owner != nil }
        observers[ObjectIdentifier(owner)] = Observer(owner: owner, handler: handler)
    }

    func removeObserver(_ owner: AnyObject) {
        observers[ObjectIdentifier(owner)] = nil
    }

    private func render(_ frame: NotchMorphFrame) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for renderer in Array(renderers.values) where renderer.owner != nil {
            renderer.render(frame)
        }
        CATransaction.commit()
    }

    private func notify(_ event: Event) {
        for observer in Array(observers.values) where observer.owner != nil {
            observer.handler(event)
        }
    }
}

enum NotchMorphGeometry {
    static func rect(size: CGSize, canvasWidth: CGFloat) -> CGRect {
        let width = max(0, size.width.isFinite ? size.width : 0)
        let height = max(0, size.height.isFinite ? size.height : 0)
        return CGRect(x: (canvasWidth - width) / 2, y: 0, width: width, height: height)
    }

    static func cropRect(containerSize: CGSize, outline: CGSize) -> CGRect {
        rect(size: outline, canvasWidth: containerSize.width)
    }

    static func layerRect(_ rect: CGRect, canvasHeight: CGFloat, topDown: Bool) -> CGRect {
        guard !topDown else { return rect }
        var flipped = rect
        flipped.origin.y = canvasHeight - rect.maxY
        return flipped
    }

    static func pixelAligned(_ rect: CGRect, scale: CGFloat) -> CGRect {
        let s = scale > 0 && scale.isFinite ? scale : 2
        let minX = (rect.minX * s).rounded() / s
        let maxX = (rect.maxX * s).rounded() / s
        let minY = (rect.minY * s).rounded() / s
        let maxY = (rect.maxY * s).rounded() / s
        return CGRect(x: minX, y: minY, width: max(0, maxX - minX), height: max(0, maxY - minY))
    }

    @MainActor
    static func restAligned(_ rect: CGRect, in view: NSView) -> CGRect {
        guard let window = view.window else { return pixelAligned(rect, scale: 2) }
        let inWindow = view.convert(rect, to: nil)
        return view.convert(pixelAligned(inWindow, scale: window.backingScaleFactor), from: nil)
    }

    @MainActor
    static func outlineRect(for frame: NotchMorphFrame, in view: NSView) -> CGRect {
        let rect = rect(size: frame.values.size, canvasWidth: view.bounds.width)
        return frame.isMoving ? rect : restAligned(rect, in: view)
    }

    static func shape(_ style: CustomNotchShape, values: NotchMorphValues) -> CustomNotchShape {
        var shape = style
        shape.cornerRadius = values.cornerRadius
        shape.bottomCornerRadius = values.bottomCornerRadius
        shape.satellites = values.satellites
        return shape
    }

    static func pathsInterpolate(_ paths: [Any]) -> Bool {
        var reference: [CGPathElementType]?
        for value in paths {
            guard CFGetTypeID(value as CFTypeRef) == CGPath.typeID else { return false }
            let path = value as! CGPath
            var elements: [CGPathElementType] = []
            elements.reserveCapacity(reference?.count ?? 16)
            path.applyWithBlock { elements.append($0.pointee.type) }
            if let reference {
                if elements != reference { return false }
            } else {
                reference = elements
            }
        }
        return true
    }

    static func path(_ style: CustomNotchShape, values: NotchMorphValues, in rect: CGRect) -> CGPath? {
        guard rect.width > 0, rect.height > 0,
              rect.width.isFinite, rect.height.isFinite else { return nil }
        return shape(style, values: values).path(in: rect).cgPath
    }
}

@MainActor
final class NotchMorphFrameDriver: NSObject {
    var onFrame: ((CFTimeInterval) -> Bool)?
    private weak var host: NSView?
    private var link: CADisplayLink?

    var isRunning: Bool { link != nil }

    func setHost(_ view: NSView) {
        guard host !== view else { return }
        if host?.window != nil, view.window == nil { return }
        let wasRunning = isRunning
        stop()
        host = view
        if wasRunning { start() }
    }

    func isHost(_ view: NSView) -> Bool { host === view }

    @discardableResult
    func start() -> Bool {
        guard link == nil else { return true }
        guard let host, host.window != nil else { return false }
        let link = host.displayLink(target: self, selector: #selector(tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        self.link = link
        return true
    }

    func stop() {
        link?.invalidate()
        link = nil
    }

    @objc private func tick(_ link: CADisplayLink) {
        guard let onFrame, onFrame(link.targetTimestamp) else {
            stop()
            return
        }
    }
}