//
//  BoldPillSlider.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-13

import SwiftUI

struct BoldPillSlider: View {
    enum Style {
        case compact
        case large

        fileprivate var fontSize: CGFloat { self == .large ? 16 : 13 }
        fileprivate var horizontalPadding: CGFloat { self == .large ? 20 : 16 }
        fileprivate var idleTextOpacity: Double { self == .large ? 0.8 : 0.85 }
        fileprivate var height: CGFloat? { self == .large ? 44 : nil }
    }

    var label: String? = nil
    @Binding var value: Double
    let range: ClosedRange<Double>
    var specifier: String = "%.0f"
    var style: Style = .compact
    var tint: Color = .accentColor
    var animatesExternalChanges = false
    var onCommit: (() -> Void)? = nil

    @State private var transientValue: Double?
    @State private var lastEmittedUptime: TimeInterval = 0

    private static let emitInterval: TimeInterval = 1.0 / 60.0

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let displayedValue = transientValue ?? value
            let progress = min(max(CGFloat((displayedValue - range.lowerBound) / (range.upperBound - range.lowerBound)), 0), 1)

            ZStack(alignment: .leading) {
                Capsule().fill(Color.gray.opacity(0.25))
                if let label {
                    let text = labelRow(label, value: displayedValue)
                    text.foregroundColor(.primary.opacity(style.idleTextOpacity))
                    ZStack {
                        Capsule().fill(tint)
                        text.foregroundColor(.white)
                    }
                    .mask(Rectangle().frame(width: width * progress).frame(maxWidth: .infinity, alignment: .leading))
                } else {
                    Capsule().fill(tint)
                        .frame(width: width * progress)
                }
            }
            .clipShape(Capsule())
            .contentShape(Capsule())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let nextValue = value(at: gesture.location.x, width: width)
                        transientValue = nextValue
                        let now = ProcessInfo.processInfo.systemUptime
                        if now - lastEmittedUptime >= Self.emitInterval {
                            value = nextValue
                            lastEmittedUptime = now
                        }
                    }
                    .onEnded { gesture in
                        value = value(at: gesture.location.x, width: width)
                        transientValue = nil
                        lastEmittedUptime = ProcessInfo.processInfo.systemUptime
                        onCommit?()
                    }
            )
            .animation(animatesExternalChanges && transientValue == nil ? .spring(response: 0.3, dampingFraction: 0.8) : nil, value: value)
        }
        .frame(height: style.height)
    }

    private func labelRow(_ label: String, value: Double) -> some View {
        HStack {
            Text(label).fontWeight(.bold)
            Spacer()
            Text(String(format: specifier, value))
                .font(.system(.body, design: .monospaced))
                .fontWeight(.bold)
        }
        .font(.system(size: style.fontSize))
        .padding(.horizontal, style.horizontalPadding)
    }

    private func value(at xPosition: CGFloat, width: CGFloat) -> Double {
        guard width > 0 else { return value }
        let percentage = min(max(Double(xPosition / width), 0), 1)
        return (range.upperBound - range.lowerBound) * percentage + range.lowerBound
    }
}