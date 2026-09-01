//
//  ProgressScrubChrome.swift
//  Sapphire
//

import AppKit
import SwiftUI

struct ProgressScrubThumb: View {
    var diameter: CGFloat
    var color: Color

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: diameter, height: diameter)
            .shadow(color: .black.opacity(0.28), radius: 1.5, y: 1)
            .allowsHitTesting(false)
    }
}

struct ProgressScrubTooltip: View {
    var text: String
    var intensity: Double = 0.65

    var body: some View {
        let shape = Capsule()
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundStyle(.white.opacity(0.92))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background {
                ZStack {
                    if #available(macOS 26.0, *), LiquidGlassView.isSystemGlassAvailable {
                        LiquidGlassShapeFill(
                            material: .tooltip,
                            shape: shape,
                            intensity: intensity,
                            blendingMode: .behindWindow,
                            appearance: .dark,
                            interaction: .hovered
                        )
                    } else {
                        VisualEffectView(material: .toolTip, blendingMode: .behindWindow)
                            .clipShape(shape)
                        shape.stroke(
                            LinearGradient(
                                colors: [.white.opacity(0.35), .white.opacity(0.12)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1
                        )
                    }
                }
            }
            .allowsHitTesting(false)
    }
}

/// AppKit hover tracking for the notch window, where SwiftUI hover can miss a stationary pointer.
struct ScrubHoverTracker: NSViewRepresentable {
    var onHoverChange: (Bool, CGFloat) -> Void

    func makeNSView(context: Context) -> TrackerView {
        let view = TrackerView()
        view.onHoverChange = onHoverChange
        return view
    }

    func updateNSView(_ nsView: TrackerView, context: Context) {
        nsView.onHoverChange = onHoverChange
        nsView.scheduleSyncHover()
    }

    final class TrackerView: NSView {
        var onHoverChange: ((Bool, CGFloat) -> Void)?
        private var isInside = false
        private var lastDeliveredX: CGFloat = -.infinity
        private var syncScheduled = false

        func scheduleSyncHover() {
            guard !syncScheduled else { return }
            syncScheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.syncScheduled = false
                self.syncHoverWithPointerIfNeeded()
            }
        }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            for area in trackingAreas {
                removeTrackingArea(area)
            }
            addTrackingArea(NSTrackingArea(
                rect: bounds,
                options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved],
                owner: self,
                userInfo: nil
            ))
            scheduleSyncHover()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            scheduleSyncHover()
        }

        override func layout() {
            super.layout()
            scheduleSyncHover()
        }

        override func mouseEntered(with event: NSEvent) {
            reportHover(at: convert(event.locationInWindow, from: nil), force: true)
        }

        override func mouseMoved(with event: NSEvent) {
            reportHover(at: convert(event.locationInWindow, from: nil), force: false)
        }

        override func mouseExited(with event: NSEvent) {
            guard isInside else { return }
            isInside = false
            lastDeliveredX = -.infinity
            deliverHoverChange(inside: false, x: 0)
        }

        func syncHoverWithPointerIfNeeded() {
            guard bounds.width > 0, bounds.height > 0, let window else { return }
            let local = convert(window.mouseLocationOutsideOfEventStream, from: nil)
            let inside = bounds.contains(local)
            if inside {
                let entering = !isInside
                isInside = true
                if entering || abs(local.x - lastDeliveredX) > 0.5 {
                    deliverHoverChange(inside: true, x: local.x)
                }
            } else if isInside {
                isInside = false
                lastDeliveredX = -.infinity
                deliverHoverChange(inside: false, x: 0)
            }
        }

        private func reportHover(at local: NSPoint, force: Bool) {
            isInside = true
            if force || abs(local.x - lastDeliveredX) > 0.5 {
                deliverHoverChange(inside: true, x: local.x)
            }
        }

        private func deliverHoverChange(inside: Bool, x: CGFloat) {
            lastDeliveredX = inside ? x : -.infinity
            let callback = onHoverChange
            DispatchQueue.main.async {
                callback?(inside, x)
            }
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
