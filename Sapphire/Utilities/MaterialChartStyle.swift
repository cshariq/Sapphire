//
//  MaterialChartStyle.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-10

import SwiftUI
import Charts

enum MaterialChartPalette {
    static let primary = Color(red: 0.42, green: 0.67, blue: 1.0)
    static let secondary = Color(red: 0.78, green: 0.55, blue: 0.98)
    static let tertiary = Color(red: 0.45, green: 0.85, blue: 0.72)
    static let error = Color(red: 1.0, green: 0.45, blue: 0.42)
    static let warning = Color(red: 1.0, green: 0.72, blue: 0.35)
    static let surface = Color.white.opacity(0.07)
    static let surfaceContainer = Color.white.opacity(0.045)
    static let surfaceVariant = Color.white.opacity(0.035)
    static let outline = Color.white.opacity(0.10)
    static let outlineStrong = Color.white.opacity(0.16)
    static let onSurfaceVariant = Color.white.opacity(0.62)

    static func tonalGradient(for color: Color) -> LinearGradient {
        LinearGradient(
            colors: [color.opacity(0.34), color.opacity(0.10), .clear],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    static func lineGradient(for color: Color) -> LinearGradient {
        LinearGradient(
            colors: [color.opacity(1.0), color.opacity(0.72)],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    static func cardGradient(for color: Color) -> LinearGradient {
        LinearGradient(
            colors: [color.opacity(0.14), color.opacity(0.03)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

struct MaterialChartCardModifier: ViewModifier {
    var height: CGFloat?
    var minHeight: CGFloat?
    var accent: Color?

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(MaterialChartPalette.surface)
                if let accent {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(MaterialChartPalette.cardGradient(for: accent))
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(MaterialChartPalette.outlineStrong, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .frame(minHeight: minHeight)
            .frame(height: height)
    }
}

struct MaterialSelectionPill: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(color.opacity(0.18))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(color.opacity(0.35), lineWidth: 1))
    }
}

struct MaterialStatChip: View {
    let label: String
    let value: String
    let color: Color
    let icon: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 24, height: 24)
                .background(color.opacity(0.15), in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(MaterialChartPalette.onSurfaceVariant)
                    .lineLimit(1)
                Text(value)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .background(MaterialChartPalette.surfaceContainer, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

extension View {
    func materialChartCard(height: CGFloat? = nil, minHeight: CGFloat? = nil, accent: Color? = nil) -> some View {
        modifier(MaterialChartCardModifier(height: height, minHeight: minHeight, accent: accent))
    }

    func materialChartPlotStyle() -> some View {
        self
            .chartPlotStyle { plotArea in
                plotArea
                    .background(MaterialChartPalette.surfaceVariant)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        .foregroundStyle(MaterialChartPalette.outline)
                    AxisValueLabel()
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(MaterialChartPalette.onSurfaceVariant)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
                        .foregroundStyle(MaterialChartPalette.outline.opacity(0.7))
                    AxisValueLabel()
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(MaterialChartPalette.onSurfaceVariant)
                }
            }
    }

    func materialWidgetTile(accent: Color, maxHeight: CGFloat = 112) -> some View {
        self
            .padding(10)
            .frame(maxHeight: maxHeight, alignment: .top)
            .background {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(MaterialChartPalette.surface)
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(MaterialChartPalette.cardGradient(for: accent))
            }
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(MaterialChartPalette.outline, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}