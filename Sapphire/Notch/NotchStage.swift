//
//  NotchStage.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-10-11
//

import AppKit
import SwiftUI

enum NotchChromeSlot: Hashable, CaseIterable {
    case leadingIcons
    case trailingIcons
    case centerBar
    case header
    case hud
    case islandBar
}

struct NotchChromeFade: Equatable {
    var inDuration: Double
    var outDuration: Double
    var curve: NotchMorphTiming

    static let icons = NotchChromeFade(inDuration: 0.2, outDuration: 0.2, curve: .easeInOut)
    static let hud = NotchChromeFade(inDuration: 0.18, outDuration: 0.18, curve: .easeOut)
}

struct NotchContentKey: Equatable {
    var config: ResolvedNotchConfiguration?
    var numbers: [CGFloat] = []
    var flags: [Bool] = []
    var tags: [String] = []
}

struct NotchChromePiece {
    enum Anchor: Equatable { case leading, trailing, center }
    enum Width: Equatable {
        case fitting
        case outline
    }

    var anchor: Anchor
    var inset: CGFloat = 0
    var top: CGFloat = 0
    var bottom: CGFloat? = nil
    var width: Width = .fitting
    var height: CGFloat? = nil
    var fade: NotchChromeFade = .icons
    var hitTestable = true
    var key: NotchContentKey? = nil
    var view: AnyView
}

struct NotchStageLayout: Equatable {
    var topInset: CGFloat
    var bandHeight: CGFloat
    var displayScale: CGFloat
    var isFloatingIsland: Bool
    var floatingIslandCornerRadius: CGFloat
    var outlineSize: CGSize
    var satelliteLayout: NotchSatelliteLayout = .none
}

struct NotchStageContent {
    var layout: NotchStageLayout
    var surface: NotchSurfaceStyle
    var activity: AnyView?
    var activityRegions: NotchActivityRegions?
    var activityKey: NotchContentKey? = nil
    var activitySize: CGSize = .zero
    var plane: NotchWidgetPlane?
    var planeSize: CGSize = .zero
    var planeEntranceStiffness: CGFloat = 230
    var planeEntranceDamping: CGFloat = 22
    var planeFollowsOutline = false
    var activityFollowsOutline = false
    var activityBehindPanel = false
    var chrome: [NotchChromeSlot: NotchChromePiece] = [:]
    var satellites: [NotchSatelliteSlot: NotchSatellitePiece] = [:]
    var onTap: () -> Void = {}
}

enum NotchStageSignal: Equatable {
    case size(CGSize)
    case radii(corner: CGFloat, bottom: CGFloat)
    case satellites(NotchSatellitePresence)
    case surfaceShadowOpacity(Double)
    case activityOpacity(Double)
    case activityBlur(CGFloat)
    case activityScale(CGFloat)
    case hudOpacity(Double)
    case hudBlur(CGFloat)
}

@MainActor
final class NotchEffects {
    struct Values: Equatable {
        var shadowOpacity: Double = 0
        var activityOpacity: Double = 0
        var activityBlurRadius: CGFloat = 0
        var activityContentScale: CGFloat = 1
        var animatedContentScale: CGFloat = 1
        var hudOpacity: Double = 0
        var hudBlur: CGFloat = 10
    }

    private(set) var values = Values()
    private unowned let coordinator: NotchStageCoordinator

    init(coordinator: NotchStageCoordinator) {
        self.coordinator = coordinator
    }

    func update(_ animation: Animation? = nil, _ body: (inout Values) -> Void) {
        var next = values
        body(&next)
        guard next != values else { return }
        let previous = values
        values = next
        if next.shadowOpacity != previous.shadowOpacity {
            coordinator.receive(.surfaceShadowOpacity(next.shadowOpacity), animation: animation)
        }
        if next.activityOpacity != previous.activityOpacity {
            coordinator.receive(.activityOpacity(next.activityOpacity), animation: animation)
        }
        if next.activityBlurRadius != previous.activityBlurRadius {
            coordinator.receive(.activityBlur(next.activityBlurRadius), animation: animation)
        }
        let scale = next.activityContentScale * next.animatedContentScale
        if scale != previous.activityContentScale * previous.animatedContentScale {
            coordinator.receive(.activityScale(scale), animation: animation)
        }
        if next.hudOpacity != previous.hudOpacity {
            coordinator.receive(.hudOpacity(next.hudOpacity), animation: animation)
        }
        if next.hudBlur != previous.hudBlur {
            coordinator.receive(.hudBlur(next.hudBlur), animation: animation)
        }
    }
}

@MainActor
final class NotchStageCoordinator: ObservableObject {
    let engine = NotchMorphEngine()
    private(set) weak var view: NotchStageView?
    private(set) lazy var effects = NotchEffects(coordinator: self)

    struct Values: Equatable {
        var size: CGSize?
        var radii: (CGFloat, CGFloat)?
        var satellites: NotchSatellitePresence?
        var surfaceShadowOpacity: Double = 0
        var activity = NotchContentEffect.identity
        var hud = NotchContentEffect(opacity: 0, blurRadius: 10, scale: 1)

        static func == (lhs: Values, rhs: Values) -> Bool {
            lhs.size == rhs.size
                && lhs.radii?.0 == rhs.radii?.0 && lhs.radii?.1 == rhs.radii?.1
                && lhs.satellites == rhs.satellites
                && lhs.surfaceShadowOpacity == rhs.surfaceShadowOpacity
                && lhs.activity == rhs.activity
                && lhs.hud == rhs.hud
        }
    }

    private(set) var values = Values()

    func attach(_ view: NotchStageView) {
        self.view = view
        view.applySignals(values, animation: nil)
    }

    func detach(_ view: NotchStageView) {
        guard self.view === view else { return }
        self.view = nil
    }

    func receive(_ signal: NotchStageSignal, animation: Animation?) {
        switch signal {
        case .size(let size):
            guard values.size != size else { return }
            values.size = size
            engine.setTargets(.size, size.width, size.height, animation: animation)
        case .radii(let corner, let bottom):
            guard values.radii?.0 != corner || values.radii?.1 != bottom else { return }
            values.radii = (corner, bottom)
            engine.setTargets(.radii, corner, bottom, animation: animation)
        case .satellites(let presence):
            guard values.satellites != presence else { return }
            values.satellites = presence
            engine.setSatellites(presence, animation: animation)
        case .surfaceShadowOpacity(let opacity):
            guard values.surfaceShadowOpacity != opacity else { return }
            values.surfaceShadowOpacity = opacity
            view?.setSurfaceShadowOpacity(opacity, animation: animation)
        case .activityOpacity(let opacity):
            guard values.activity.opacity != opacity else { return }
            values.activity.opacity = opacity
            view?.setActivityEffect(values.activity, animation: animation)
        case .activityBlur(let radius):
            guard values.activity.blurRadius != radius else { return }
            values.activity.blurRadius = radius
            view?.setActivityEffect(values.activity, animation: animation)
        case .activityScale(let scale):
            guard values.activity.scale != scale else { return }
            values.activity.scale = scale
            view?.setActivityEffect(values.activity, animation: animation)
        case .hudOpacity(let opacity):
            guard values.hud.opacity != opacity else { return }
            values.hud.opacity = opacity
            view?.setHUDEffect(values.hud, animation: animation)
        case .hudBlur(let radius):
            guard values.hud.blurRadius != radius else { return }
            values.hud.blurRadius = radius
            view?.setHUDEffect(values.hud, animation: animation)
        }
    }
}

// MARK: - Representables

struct NotchStage: NSViewRepresentable {
    let coordinator: NotchStageCoordinator
    let content: NotchStageContent

    func makeNSView(context: Context) -> NotchStageView {
        let view = NotchStageView(engine: coordinator.engine)
        coordinator.attach(view)
        view.apply(content)
        return view
    }

    func updateNSView(_ nsView: NotchStageView, context: Context) {
        nsView.apply(content)
    }

    static func dismantleNSView(_ nsView: NotchStageView, coordinator: ()) {
        nsView.tearDown()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NotchStageView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 0, height: proposal.height ?? 0)
    }
}

struct NotchStageSignalBridge: NSViewRepresentable {
    let coordinator: NotchStageCoordinator
    let signal: NotchStageSignal

    func makeNSView(context: Context) -> NotchStageSignalView {
        coordinator.receive(signal, animation: nil)
        return NotchStageSignalView()
    }

    func updateNSView(_ nsView: NotchStageSignalView, context: Context) {
        coordinator.receive(
            signal,
            animation: context.transaction.disablesAnimations ? nil : context.transaction.animation
        )
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NotchStageSignalView, context: Context) -> CGSize? {
        .zero
    }
}

final class NotchStageSignalView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override var intrinsicContentSize: NSSize { .zero }
}