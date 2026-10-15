//
//  NotchSatellites.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-10-15
//

import AppKit
import SwiftUI

struct NotchSatellitePiece {
    var view: AnyView
    var key: NotchContentKey?
}

@MainActor
final class NotchSatelliteStage {
    private weak var container: NSView?
    private let wrap: (AnyView) -> AnyView
    private var hosts: [NotchSatelliteSlot: NotchHostedContentView] = [:]
    private var pieces: [NotchSatelliteSlot: NotchSatellitePiece] = [:]
    private(set) var layout = NotchSatelliteLayout.none

    init(container: NSView, wrap: @escaping (AnyView) -> AnyView) {
        self.container = container
        self.wrap = wrap
    }

    func apply(_ newPieces: [NotchSatelliteSlot: NotchSatellitePiece], layout: NotchSatelliteLayout) {
        self.layout = layout
        let size = CGSize(width: layout.diameter, height: layout.diameter)
        for side in NotchSatelliteSlot.allCases {
            guard let piece = newPieces[side], layout.diameter > 0 else {
                pieces[side] = nil
                continue
            }
            let host = hosts[side] ?? makeHost(side)
            if host.frame.size != size { host.setFrameSize(size) }
            host.setRootView(wrap(piece.view), key: piece.key)
            if !host.isPresented { host.present(fadeDuration: 0, curve: .linear) }
            pieces[side] = piece
        }
    }

    func render(_ values: NotchMorphValues, outline: CGRect, final: Bool) {
        for (side, host) in hosts where host.isPresented {
            let presence = Self.presence(side, values)
            if final, presence < 0.01, pieces[side] == nil {
                host.park(keepingContent: true)
                continue
            }
            let bubble = layout.rect(slot: side, presence: presence, outline: outline)
            let origin = CGPoint(x: bubble.midX - layout.diameter / 2, y: bubble.midY - layout.diameter / 2)
            if final { host.settle(at: origin) } else { host.presentOrigin(origin) }
            guard let content = host.followView.layer else { continue }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            content.opacity = Self.opacity(presence)
            content.sublayerTransform = Self.transform(scale: bubble.width / max(layout.diameter, 1), layer: content)
            CATransaction.commit()
        }
    }

    func animate(_ timeline: NotchMorphTimeline, rects: [CGRect]) {
        let diameter = layout.diameter
        guard diameter > 0 else { return }
        for (side, host) in hosts where host.isPresented {
            guard let layer = host.layer, let superlayer = layer.superlayer,
                  let content = host.followView.layer else { continue }
            let topDown = superlayer.contentsAreFlipped()
            let superHeight = superlayer.bounds.height
            var positions: [Any] = []
            var opacities: [Any] = []
            var transforms: [Any] = []
            positions.reserveCapacity(rects.count)
            for (rect, frame) in zip(rects, timeline.frames) {
                let presence = Self.presence(side, frame.values)
                let bubble = layout.rect(slot: side, presence: presence, outline: rect)
                let hostRect = CGRect(x: bubble.midX - diameter / 2, y: bubble.midY - diameter / 2, width: diameter, height: diameter)
                positions.append(NSValue(point: NotchLayerGeometry.position(
                    for: hostRect, anchor: layer.anchorPoint, topDown: topDown, superHeight: superHeight
                )))
                opacities.append(NSNumber(value: Self.opacity(presence)))
                transforms.append(NSValue(caTransform3D: Self.transform(scale: bubble.width / diameter, layer: content)))
            }
            layer.add(timeline.animation("position", values: positions, on: layer), forKey: "satellite.position")
            content.add(timeline.animation("opacity", values: opacities, on: content), forKey: "satellite.opacity")
            content.add(timeline.animation("sublayerTransform", values: transforms, on: content), forKey: "satellite.transform")
        }
    }

    func restingRects(outline: CGRect, values: NotchMorphValues) -> [CGRect] {
        NotchSatelliteSlot.allCases.compactMap { slot in
            Self.presence(slot, values) > 0.5 ? layout.restingRect(slot: slot, outline: outline) : nil
        }
    }

    func tearDown() {
        for host in hosts.values { host.removeFromSuperview() }
        hosts.removeAll()
        pieces.removeAll()
    }

    // MARK: Helpers

    private func makeHost(_ side: NotchSatelliteSlot) -> NotchHostedContentView {
        let host = NotchHostedContentView(rootView: AnyView(EmptyView()), sizing: .fixed)
        container?.addSubview(host, positioned: .above, relativeTo: nil)
        hosts[side] = host
        return host
    }

    static func presence(_ slot: NotchSatelliteSlot, _ values: NotchMorphValues) -> CGFloat {
        values.satellites[slot]
    }

    static func opacity(_ presence: CGFloat) -> Float {
        let t = min(1, max(0, (presence - 0.45) / 0.45))
        return Float(t * t * (3 - 2 * t))
    }

    static func transform(scale: CGFloat, layer: CALayer) -> CATransform3D {
        guard abs(scale - 1) > 1e-4 else { return CATransform3DIdentity }
        let bounds = layer.bounds
        let pivotX = bounds.midX - bounds.width * layer.anchorPoint.x
        let pivotY = bounds.midY - bounds.height * layer.anchorPoint.y
        var transform = CATransform3DMakeTranslation(pivotX, pivotY, 0)
        transform = CATransform3DScale(transform, scale, scale, 1)
        return CATransform3DTranslate(transform, -pivotX, -pivotY, 0)
    }
}