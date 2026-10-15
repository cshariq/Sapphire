//
//  NotchWidgetPlane.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-10-08
//

import AppKit
import Combine
import os.log
import SwiftUI

struct NotchWidgetPlaneInputs: Equatable {
    var fileDragMode: FileDragMode = .newFile
    var padding = EdgeInsets()
    var notchBandHeight: CGFloat = 0
    var displayScale: CGFloat = 2
    var notchDisplayWidth: CGFloat = 0
    var presentationGeneration = 0
}

@MainActor
final class NotchWidgetPlaneState: ObservableObject {
    let switchGate = NotchWidgetSwitchGate()
    @Published var navigationStack: [NotchWidgetMode] = [.defaultWidgets]
    @Published var activeDropZone: DropZone?
    @Published var isCalendarHovered = false

    var onNavigationStackChange: (([NotchWidgetMode]) -> Void)?
    var onActiveDropZoneChange: ((DropZone?) -> Void)?
    var onCalendarHoverChange: ((Bool) -> Void)?

    func sync(navigationStack: [NotchWidgetMode], activeDropZone: DropZone?, isCalendarHovered: Bool) {
        if self.navigationStack != navigationStack { self.navigationStack = navigationStack }
        if self.activeDropZone != activeDropZone { self.activeDropZone = activeDropZone }
        if self.isCalendarHovered != isCalendarHovered { self.isCalendarHovered = isCalendarHovered }
    }
}

final class NotchWidgetSwitchGate {
    var suppressedUntil: CFTimeInterval = 0
    var isSuppressed: Bool { CACurrentMediaTime() < suppressedUntil }
    var willSwitch: (() -> Void)?
}

private struct NotchWidgetSwitchGateKey: EnvironmentKey {
    static let defaultValue: NotchWidgetSwitchGate? = nil
}

extension EnvironmentValues {
    var notchWidgetSwitchGate: NotchWidgetSwitchGate? {
        get { self[NotchWidgetSwitchGateKey.self] }
        set { self[NotchWidgetSwitchGateKey.self] = newValue }
    }
}

struct NotchWidgetPlaneRoot: View {
    let content: AnyView
    let inputs: NotchWidgetPlaneInputs
    let measuredSize: Binding<CGSize>
    @ObservedObject var state: NotchWidgetPlaneState

    var body: some View {
        content
            .environment(\.navigationStack, Binding(
                get: { state.navigationStack },
                set: { newValue in
                    state.navigationStack = newValue
                    state.onNavigationStackChange?(newValue)
                }
            ))
            .environment(\.activeDropZone, Binding(
                get: { state.activeDropZone },
                set: { newValue in
                    state.activeDropZone = newValue
                    state.onActiveDropZoneChange?(newValue)
                }
            ))
            .environment(\.isCalendarHovered, Binding(
                get: { state.isCalendarHovered },
                set: { newValue in
                    state.isCalendarHovered = newValue
                    state.onCalendarHoverChange?(newValue)
                }
            ))
            .environment(\.fileDragMode, inputs.fileDragMode)
            .environment(\.notchWidgetSwitchGate, state.switchGate)
            .padding(inputs.padding)
            .measureIdealSize(into: measuredSize, reportGeneration: inputs.presentationGeneration)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .coordinateSpace(.notchDrag)
            .environment(\.notchDisplayWidth, inputs.notchDisplayWidth)
            .notchHostEnvironment(bandHeight: inputs.notchBandHeight, displayScale: inputs.displayScale)
            .modifier(NotchWidgetPlaneGraphProbe())
    }
}

private struct NotchWidgetPlaneGraphProbe: ViewModifier {
    #if DEBUG
    @State private var token = String(UUID().uuidString.prefix(8))
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Sapphire", category: "NotchWidgetPlane")

    func body(content: Content) -> some View {
        content.onAppear { [token] in
            Self.log.debug("widget plane appeared, graph token \(token, privacy: .public)")
        }
    }
    #else
    func body(content: Content) -> some View { content }
    #endif
}

@MainActor
final class NotchWidgetPlane: ObservableObject {
    let dragLocation = NotchDragLocationState()
    let state = NotchWidgetPlaneState()

    private(set) var hostingView: NotchWidgetPlaneHostingView?
    let mountView = NotchWidgetPlaneMountView()
    private var content: AnyView?
    private var inputs = NotchWidgetPlaneInputs()
    private var measuredSize: Binding<CGSize> = .constant(.zero)
    private var dragCancellable: AnyCancellable?

    private weak var outerView: NSView?

    private var lastDropZoneFrames: [DropZone: CGRect] = [:]
    private var lastSnapRegions: [SnapZoneHitRegion] = []
    private var forwardDropZoneFrames: (([DropZone: CGRect]) -> Void)?
    private var forwardSnapRegions: (([SnapZoneHitRegion]) -> Void)?
    private var resendScheduled = false

    var isConfigured: Bool { hostingView != nil }

    func configure(
        content makeContent: () -> AnyView,
        inputs: NotchWidgetPlaneInputs,
        measuredSize: Binding<CGSize>,
        outerDragLocation: NotchDragLocationState
    ) {
        guard hostingView == nil else {
            update(inputs: inputs)
            return
        }
        let content = makeContent()
        self.content = content
        self.inputs = inputs
        self.measuredSize = measuredSize
        let host = NotchWidgetPlaneHostingView(rootView: NotchWidgetPlaneRoot(content: content, inputs: inputs, measuredSize: measuredSize, state: state))
        host.sizingOptions = []
        host.autoresizingMask = [.width, .height]
        host.frame = mountView.bounds
        mountView.addSubview(host)
        hostingView = host

        dragCancellable = outerDragLocation.$location
            .sink { [weak self] location in
                guard let self else { return }
                self.dragLocation.update(location.flatMap { self.toPlane($0) })
            }
    }

    func update(inputs newInputs: NotchWidgetPlaneInputs) {
        var newInputs = newInputs
        newInputs.presentationGeneration = inputs.presentationGeneration
        if newInputs.notchDisplayWidth <= 0 { newInputs.notchDisplayWidth = inputs.notchDisplayWidth }
        apply(newInputs)
    }

    func didPresent() {
        var next = inputs
        next.presentationGeneration &+= 1
        apply(next)
    }

    private func apply(_ newInputs: NotchWidgetPlaneInputs) {
        guard newInputs != inputs, let content, let hostingView else { return }
        inputs = newInputs
        hostingView.rootView = NotchWidgetPlaneRoot(content: content, inputs: newInputs, measuredSize: measuredSize, state: state)
    }

    func setOuterView(_ view: NSView?) { outerView = view }

    func setDisplayScale(_ scale: CGFloat) {
        guard scale > 0 else { return }
        var next = inputs
        next.displayScale = scale
        update(inputs: next)
    }

    func setDisplay(of window: NSWindow) {
        let assigned = (window as? DynamicFocusWindow)?.displayID ?? 0
        let screen = NSScreen.screens.first { assigned != 0 && $0.displayID == assigned } ?? window.screen
        guard let width = screen?.frame.width, width > 0 else { return }
        var next = inputs
        next.notchDisplayWidth = width
        update(inputs: next)
    }

    // MARK: Coordinates

    func toOuter(_ rect: CGRect) -> CGRect {
        guard let hostingView, let outerView, hostingView.window != nil, hostingView.window === outerView.window else { return rect }
        return hostingView.convert(rect, to: outerView)
    }

    func toPlane(_ point: CGPoint) -> CGPoint {
        guard let hostingView, let outerView, hostingView.window != nil, hostingView.window === outerView.window else { return point }
        return outerView.convert(point, to: hostingView)
    }

    func dropZoneFramesHandler(_ forward: @escaping ([DropZone: CGRect]) -> Void) -> ([DropZone: CGRect]) -> Void {
        forwardDropZoneFrames = forward
        return { [weak self] frames in
            guard let self else { return forward(frames) }
            self.lastDropZoneFrames = frames
            forward(frames.mapValues { self.toOuter($0) })
        }
    }

    func snapRegionsHandler(_ forward: @escaping ([SnapZoneHitRegion]) -> Void) -> ([SnapZoneHitRegion]) -> Void {
        forwardSnapRegions = forward
        return { [weak self] regions in
            guard let self else { return forward(regions) }
            self.lastSnapRegions = regions
            forward(regions.map { SnapZoneHitRegion(frame: self.toOuter($0.frame), zone: $0.zone) })
        }
    }

    func planeDidMove() {
        guard !lastDropZoneFrames.isEmpty || !lastSnapRegions.isEmpty, !resendScheduled else { return }
        resendScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.resendScheduled = false
            if !self.lastDropZoneFrames.isEmpty {
                self.forwardDropZoneFrames?(self.lastDropZoneFrames.mapValues { self.toOuter($0) })
            }
            if !self.lastSnapRegions.isEmpty {
                self.forwardSnapRegions?(self.lastSnapRegions.map { SnapZoneHitRegion(frame: self.toOuter($0.frame), zone: $0.zone) })
            }
        }
    }

    func clearReportedFrames() {
        lastDropZoneFrames = [:]
        lastSnapRegions = []
    }
}

final class NotchWidgetPlaneContainer: NSView {
    let plane: NotchWidgetPlane
    var entranceStiffness: CGFloat = 230
    var entranceDamping: CGFloat = 22
    var followsOutline = false {
        didSet {
            guard followsOutline != oldValue else { return }
            if followsOutline {
                cancelEntrance()
            } else {
                resetOutlineFollowing()
            }
        }
    }

    private static let blurFilterName = "entranceBlur"
    private static let initialScale: CGFloat = 0.7
    private static let initialOffsetY: CGFloat = -50
    private static let initialBlurRadius: CGFloat = 20
    private static let entranceDelay: CFTimeInterval = 0.1
    private static let blurDuration: CFTimeInterval = 0.6

    private var entranceGeneration = 0
    private var entranceBeginTime: CFTimeInterval?

    init(plane: NotchWidgetPlane) {
        self.plane = plane
        super.init(frame: .zero)
        wantsLayer = true
        layerUsesCoreImageFilters = true
        layer?.actions = NotchLayerSurfaceView.noActions
        plane.state.switchGate.willSwitch = { [weak self] in self?.runSwitch() }
    }

    // MARK: Switching

    private static let switchDelay: CFTimeInterval = 0.02

    private func runSwitch() {
        guard window != nil, plane.mountView.superview === self else { return }
        runEntrance(delay: Self.switchDelay)
    }

    private static func makeBlurFilter(named name: String) -> NSObject? {
        if let cls = NSClassFromString("CAFilter") as? NSObject.Type,
           let filter = cls.perform(NSSelectorFromString("filterWithType:"), with: "gaussianBlur")?.takeUnretainedValue() as? NSObject {
            filter.setValue(name, forKey: "name")
            filter.setValue(0, forKey: "inputRadius")
            return filter
        }
        guard let blur = CIFilter(name: "CIGaussianBlur") else { return nil }
        blur.name = name
        blur.setValue(0, forKey: kCIInputRadiusKey)
        return blur
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }

    override func invalidateIntrinsicContentSize() {}

    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return hit === self ? nil : hit
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window, plane.hostingView != nil else { return }
        plane.setOuterView((window.contentView as? NotchStageContainerView)?.stageView ?? window.contentView)
        plane.setDisplayScale(window.backingScaleFactor)
        plane.setDisplay(of: window)
        let mount = plane.mountView
        if mount.superview !== self {
            mount.removeFromSuperview()
            mount.frame = bounds
            addSubview(mount)
            plane.state.switchGate.suppressedUntil = CACurrentMediaTime() + 0.1
            plane.didPresent()
            if !followsOutline { runEntrance() }
        }
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        guard let window, plane.hostingView != nil else { return }
        plane.setDisplayScale(window.backingScaleFactor)
        plane.setDisplay(of: window)
    }

    override func setFrameOrigin(_ newOrigin: NSPoint) {
        super.setFrameOrigin(newOrigin)
        plane.planeDidMove()
    }

    override func setFrameSize(_ newSize: NSSize) {
        let oldSize = frame.size
        super.setFrameSize(newSize)
        if newSize != oldSize {
            retargetEntranceTransform()
        }
        plane.planeDidMove()
    }

    func detachPlane() {
        entranceGeneration += 1
        entranceBeginTime = nil
        if let layer = entranceLayer {
            layer.removeAllAnimations()
            layer.sublayerTransform = CATransform3DIdentity
            layer.opacity = 1
            layer.filters = nil
        }
        if plane.mountView.superview === self {
            plane.mountView.removeFromSuperview()
        }
        plane.clearReportedFrames()
    }

    // MARK: Following the outline

    private static let followBlurFilterName = "followBlur"
    private static let followBlurRadiusMax: CGFloat = 22
    private var followBlurInstalled = false

    private lazy var follower = NotchOutlineFollower(layer: layer)

    func animateFollow(_ timeline: NotchMorphTimeline, outlines: [CGSize]) {
        guard followsOutline, let layer else { return }
        guard bounds.height > 48 else {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.opacity = 0
            CATransaction.commit()
            return
        }
        follower.animate(timeline, outlines: outlines, layoutSize: bounds.size)
    }

    func followOutline(_ outline: CGRect, isMoving: Bool) {
        guard followsOutline, !follower.isDriving, let layer else { return }
        let size = bounds.size
        guard size.width > 1, size.height > 1 else { return }

        var scale = min(outline.width / size.width, outline.height / size.height)
        if scale > 1 { scale = 1 + (scale - 1) * 0.6 }
        scale = max(0.02, scale)
        let settled = !isMoving && abs(scale - 1) < 0.002
        let measured = size.height > 48

        let opacity: Float = measured ? Float(Self.smoothstep(0.18, 0.5, scale)) : 0
        let radius = settled ? 0 : Self.followBlurRadiusMax * (1 - Self.smoothstep(0.55, 0.9, scale))

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.sublayerTransform = settled ? CATransform3DIdentity : topCentredScale(scale, in: layer)
        layer.opacity = settled ? 1 : opacity
        if radius > 0.05 {
            if !followBlurInstalled, let blur = CIFilter(name: "CIGaussianBlur") {
                blur.name = Self.followBlurFilterName
                layer.filters = [blur]
                followBlurInstalled = true
            }
            layer.setValue(radius, forKeyPath: "filters.\(Self.followBlurFilterName).inputRadius")
        } else if followBlurInstalled {
            layer.filters = nil
            followBlurInstalled = false
        }
        CATransaction.commit()
    }

    private func cancelEntrance() {
        guard let layer = entranceLayer else { return }
        entranceGeneration += 1
        entranceBeginTime = nil
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.removeAllAnimations()
        layer.sublayerTransform = CATransform3DIdentity
        layer.opacity = 1
        layer.filters = nil
        CATransaction.commit()
    }

    private func resetOutlineFollowing() {
        follower.reset()
        guard let layer else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.sublayerTransform = CATransform3DIdentity
        layer.opacity = 1
        if followBlurInstalled {
            layer.filters = nil
            followBlurInstalled = false
        }
        CATransaction.commit()
    }

    private func topCentredScale(_ scale: CGFloat, in layer: CALayer) -> CATransform3D {
        let bounds = layer.bounds
        let anchor = layer.anchorPoint
        let pivotX = bounds.midX - bounds.width * anchor.x
        let topY = (layer.contentsAreFlipped() ? bounds.minY : bounds.maxY) - bounds.height * anchor.y
        var transform = CATransform3DMakeTranslation(pivotX, topY, 0)
        transform = CATransform3DScale(transform, scale, scale, 1)
        return CATransform3DTranslate(transform, -pivotX, -topY, 0)
    }

    private static func smoothstep(_ edge0: CGFloat, _ edge1: CGFloat, _ x: CGFloat) -> CGFloat {
        let t = min(1, max(0, (x - edge0) / (edge1 - edge0)))
        return t * t * (3 - 2 * t)
    }

    // MARK: Entrance

    private var entranceLayer: CALayer? { plane.mountView.layer }

    private func runEntrance(delay: CFTimeInterval = entranceDelay) {
        guard let layer = entranceLayer else { return }
        entranceGeneration += 1
        let generation = entranceGeneration
        let start = startTransform(in: layer)
        let begin = CACurrentMediaTime() + delay

        let blur = Self.makeBlurFilter(named: Self.blurFilterName)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.removeAllAnimations()
        layer.filters = blur.map { [$0] }
        layer.sublayerTransform = CATransform3DIdentity
        layer.opacity = 1

        entranceBeginTime = begin
        layer.add(entranceTransformAnimation(from: start, begin: begin), forKey: Self.entranceTransformKey)

        let fade = CASpringAnimation(keyPath: "opacity")
        fade.mass = 1
        fade.stiffness = entranceStiffness
        fade.damping = entranceDamping
        fade.initialVelocity = 0
        fade.fromValue = 0
        fade.toValue = 1
        fade.duration = fade.settlingDuration
        fade.beginTime = begin
        fade.fillMode = .backwards
        layer.add(fade, forKey: "entranceFade")

        if blur != nil {
            let unblur = CABasicAnimation(keyPath: "filters.\(Self.blurFilterName).inputRadius")
            unblur.fromValue = Self.initialBlurRadius
            unblur.toValue = 0
            unblur.duration = Self.blurDuration
            unblur.timingFunction = CAMediaTimingFunction(name: .easeOut)
            unblur.beginTime = begin
            unblur.fillMode = .backwards
            layer.add(unblur, forKey: "entranceBlur")
        }
        CATransaction.commit()

        DispatchQueue.main.asyncAfter(deadline: .now() + delay + Self.blurDuration + 0.05) { [weak self] in
            guard let self, self.entranceGeneration == generation, let layer = self.entranceLayer else { return }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.filters = nil
            CATransaction.commit()
        }
    }

    private static let entranceTransformKey = "entranceTransform"

    private func entranceTransformAnimation(from start: CATransform3D, begin: CFTimeInterval) -> CAAnimation {
        let transform = CASpringAnimation(keyPath: "sublayerTransform")
        transform.mass = 1
        transform.stiffness = entranceStiffness
        transform.damping = entranceDamping
        transform.initialVelocity = 0
        transform.fromValue = NSValue(caTransform3D: start)
        transform.toValue = NSValue(caTransform3D: CATransform3DIdentity)
        transform.duration = transform.settlingDuration
        transform.beginTime = begin
        transform.fillMode = .backwards
        return transform
    }

    private func retargetEntranceTransform() {
        guard let layer = entranceLayer, let begin = entranceBeginTime,
              layer.animation(forKey: Self.entranceTransformKey) != nil else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.add(entranceTransformAnimation(from: startTransform(in: layer), begin: begin), forKey: Self.entranceTransformKey)
        CATransaction.commit()
    }

    private func startTransform(in layer: CALayer) -> CATransform3D {
        let bounds = layer.bounds
        let anchor = layer.anchorPoint
        let pivotX = bounds.midX - bounds.width * anchor.x
        let topY = (layer.contentsAreFlipped() ? bounds.minY : bounds.maxY) - bounds.height * anchor.y
        let offsetY = layer.contentsAreFlipped() ? Self.initialOffsetY : -Self.initialOffsetY
        var transform = CATransform3DMakeTranslation(pivotX, topY + offsetY, 0)
        transform = CATransform3DScale(transform, Self.initialScale, Self.initialScale, 1)
        transform = CATransform3DTranslate(transform, -pivotX, -topY, 0)
        return transform
    }
}

final class NotchWidgetPlaneMountView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        autoresizingMask = [.width, .height]
        wantsLayer = true
        layerUsesCoreImageFilters = true
        layer?.actions = NotchLayerSurfaceView.noActions
    }

    override var isFlipped: Bool { true }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }

    override func invalidateIntrinsicContentSize() {}
}

final class NotchWidgetPlaneHostingView: NSHostingView<NotchWidgetPlaneRoot>, PointerTrackingGated {
    private lazy var trackingGate = PointerTrackingGate(view: self)

    required init(rootView: NotchWidgetPlaneRoot) {
        super.init(rootView: rootView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        (window as? DynamicFocusWindow)?.unregisterPointerTrackingClient(self)
        super.viewWillMove(toWindow: newWindow)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window = window as? DynamicFocusWindow {
            window.registerPointerTrackingClient(self)
        } else {
            setPointerTrackingEnabled(true)
        }
    }

    override func addTrackingArea(_ trackingArea: NSTrackingArea) {
        guard trackingGate.shouldInstall(trackingArea) else { return }
        super.addTrackingArea(trackingArea)
    }

    override func removeTrackingArea(_ trackingArea: NSTrackingArea) {
        trackingGate.didRemove(trackingArea)
        super.removeTrackingArea(trackingArea)
    }

    func setPointerTrackingEnabled(_ enabled: Bool) {
        trackingGate.setOpen(enabled) { super.addTrackingArea($0) }
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }

    override func invalidateIntrinsicContentSize() {}
}