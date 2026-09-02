//
//  WidgetLayoutPolicy.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-10

import AppKit

enum WidgetLayoutPolicy {
    static let interWidgetSpacing: CGFloat = 20
    static let dividerWidth: CGFloat = 1
    static let headerIconReserve: CGFloat = 140

    static func estimatedWidth(for widget: WidgetType) -> CGFloat {
        switch widget {
        case .music: return 280
        case .weather: return 210
        case .calendar: return 180
        case .shortcuts: return 110
        case .sports: return 190
        case .finance: return 190
        case .shopify: return 190
        case .notes: return 176
        case .clipboard: return 176
        case .mirror: return 140
        case .battery: return 210
        case .agent: return 0
        case .focusSession: return 190
        }
    }

    static func availableBarWidth(for screen: NSScreen? = nil) -> CGFloat {
        let targetScreen = screen ?? CursorPosition.targetNotchScreen() ?? NSScreen.main
        let screenWidth = targetScreen?.frame.width ?? 1440
        let adj = NotchConfiguration.screenWidthAdjustment(for: targetScreen)
        return max(360, screenWidth * 0.72 - headerIconReserve * adj)
    }

    static func totalWidth(for widgets: [WidgetType], showDividers: Bool) -> CGFloat {
        guard !widgets.isEmpty else { return 0 }
        var total = widgets.reduce(0) { $0 + estimatedWidth(for: $1) }
        if widgets.count > 1 {
            total += interWidgetSpacing * CGFloat(widgets.count - 1)
            if showDividers {
                total += dividerWidth * CGFloat(widgets.count - 1)
            }
        }
        return total
    }

    static func fittingWidgets(from ordered: [WidgetType], availableWidth: CGFloat, showDividers: Bool) -> [WidgetType] {
        var used: CGFloat = 0
        var result: [WidgetType] = []

        for widget in ordered where widget != .agent {
            let width = estimatedWidth(for: widget)
            guard width > 0 else { continue }

            let spacing: CGFloat
            if result.isEmpty {
                spacing = 0
            } else {
                spacing = interWidgetSpacing + (showDividers ? dividerWidth : 0)
            }

            if result.isEmpty || used + spacing + width <= availableWidth {
                used += spacing + width
                result.append(widget)
            } else {
                break
            }
        }

        return result
    }

    static func canFit(_ widget: WidgetType, in orderedEnabled: [WidgetType], availableWidth: CGFloat, showDividers: Bool) -> Bool {
        guard widget != .agent else { return false }
        var candidates = orderedEnabled.filter { $0 != .agent }
        if !candidates.contains(widget) {
            candidates.append(widget)
        }
        return fittingWidgets(from: candidates, availableWidth: availableWidth, showDividers: showDividers).contains(widget)
    }
}