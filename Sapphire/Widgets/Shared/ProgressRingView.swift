//
//  ProgressRingView.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-13

import SwiftUI

struct ProgressRingView: View {
    var progress: Double
    var lineWidth: CGFloat
    var trackLineWidth: CGFloat?
    var track: AnyShapeStyle = AnyShapeStyle(Color.white.opacity(0.18))
    var active: AnyShapeStyle
    var lineCap: CGLineCap = .round
    var rotation: Angle = .degrees(-90)
    var clampsProgress: Bool = true
    var activeShadow: (color: Color, radius: CGFloat)?

    init(
        progress: Double,
        lineWidth: CGFloat,
        trackLineWidth: CGFloat? = nil,
        track: AnyShapeStyle = AnyShapeStyle(Color.white.opacity(0.18)),
        active: some ShapeStyle,
        lineCap: CGLineCap = .round,
        rotation: Angle = .degrees(-90),
        clampsProgress: Bool = true,
        activeShadow: (color: Color, radius: CGFloat)? = nil
    ) {
        self.progress = progress
        self.lineWidth = lineWidth
        self.trackLineWidth = trackLineWidth
        self.track = track
        self.active = AnyShapeStyle(active)
        self.lineCap = lineCap
        self.rotation = rotation
        self.clampsProgress = clampsProgress
        self.activeShadow = activeShadow
    }

    private var trimmedProgress: CGFloat {
        let p = CGFloat(progress)
        return clampsProgress ? min(max(p, 0), 1) : p
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(track, lineWidth: trackLineWidth ?? lineWidth)
            Circle()
                .trim(from: 0, to: trimmedProgress)
                .stroke(active, style: StrokeStyle(lineWidth: lineWidth, lineCap: lineCap))
                .rotationEffect(rotation)
                .shadow(color: activeShadow?.color ?? .clear, radius: activeShadow?.radius ?? 0)
        }
    }
}