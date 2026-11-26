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
        case .timer: return 150
        case .agent: return 0
        case .focusSession: return 190
        case .storage: return 210
        case .dev: return 200
        }
    }

    static func capacityWidth(for widget: WidgetType) -> CGFloat {
        widget == .music ? 0 : estimatedWidth(for: widget)
    }

    static func availableBarWidth(for screen: NSScreen? = nil) -> CGFloat {
        let targetScreen = screen ?? CursorPosition.targetNotchScreen() ?? NSScreen.main
        return availableBarWidth(forScreenWidth: targetScreen?.frame.width ?? 1440)
    }

    static func availableBarWidth(forScreenWidth screenWidth: CGFloat) -> CGFloat {
        max(360, screenWidth * 0.72 - headerIconReserve)
    }

    static func availableBarWidth(notchDisplayWidth: CGFloat) -> CGFloat {
        notchDisplayWidth > 0 ? availableBarWidth(forScreenWidth: notchDisplayWidth) : availableBarWidth()
    }

    static func availableBarWidthForSettings(settings: Settings, screens: [NSScreen] = NSScreen.screens) -> CGFloat {
        let notchScreens = NotchScreens.screens(for: settings, among: screens)
        guard let widest = notchScreens.map(\.frame.width).max() else { return availableBarWidth() }
        return availableBarWidth(forScreenWidth: widest)
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

    // MARK: Optical insets (floating island)

    /// Side padding a widget carries inside its own frame. The island trims it at a row's ends so the card's
    /// left and right margins match its top and bottom ones.
    static func builtInSidePadding(for widget: WidgetType) -> CGFloat {
        switch widget {
        case .weather, .focusSession, .timer: return 10
        default: return 0
        }
    }

    /// Empty space a widget usually leaves above and below its content (minimum-height frames, centred content).
    /// These are measured estimates; widgets not listed are treated as filling their frame.
    static func builtInVerticalSlack(for widget: WidgetType) -> CGFloat {
        switch widget {
        case .battery, .storage, .weather, .timer: return 6
        case .calendar, .focusSession: return 8
        default: return 0
        }
    }

    static func rowVerticalSlack(for widgets: [WidgetType]) -> CGFloat {
        widgets.map(builtInVerticalSlack(for:)).min() ?? 0
    }

    // MARK: Rows (floating island)

    static let islandRowWidthLimit: CGFloat = 640

    /// A single-row island keeps to about half the display, so it reads as an island rather than a second menu bar.
    static let islandSingleRowDisplayFraction: CGFloat = 0.55
    static let islandSingleRowMaximumAspect: CGFloat = 7
    static let islandSingleRowBaseHeight: CGFloat = 110
    static let islandSingleRowMaximumExtraPadding: CGFloat = 14

    static func islandSingleRowWidth(notchDisplayWidth: CGFloat) -> CGFloat {
        let width = notchDisplayWidth > 0 ? notchDisplayWidth : (NSScreen.main?.frame.width ?? 1440)
        return max(360, width * islandSingleRowDisplayFraction)
    }

    /// Extra vertical padding that keeps a long single row from looking like a thin ribbon.
    static func islandSingleRowExtraPadding(for widgets: [WidgetType], showDividers: Bool) -> CGFloat {
        let width = totalWidth(for: widgets, showDividers: showDividers)
        let wanted = (width / islandSingleRowMaximumAspect - islandSingleRowBaseHeight) / 2
        return min(islandSingleRowMaximumExtraPadding, max(0, wanted)).rounded()
    }
    static let rowSpacing: CGFloat = 14
    static let maximumRows = 3

    /// Splits the widgets into rows of similar width, keeping their order. A menu that fits the limit stays one row.
    static func rows(for widgets: [WidgetType], maxRowWidth: CGFloat, showDividers: Bool) -> [[WidgetType]] {
        guard maxRowWidth > 0, widgets.count > 1 else { return widgets.isEmpty ? [] : [widgets] }
        let total = totalWidth(for: widgets, showDividers: showDividers)
        guard total > maxRowWidth else { return [widgets] }
        let count = min(maximumRows, widgets.count, Int((total / maxRowWidth).rounded(.up)))

        var best: [[WidgetType]] = [widgets]
        var bestWidth = CGFloat.greatestFiniteMagnitude
        func split(from start: Int, rowsLeft: Int, rows: [[WidgetType]], widest: CGFloat) {
            guard widest < bestWidth else { return }
            if rowsLeft == 1 {
                let row = Array(widgets[start...])
                let width = max(widest, totalWidth(for: row, showDividers: showDividers))
                if width < bestWidth {
                    bestWidth = width
                    best = rows + [row]
                }
                return
            }
            for end in (start + 1)...(widgets.count - rowsLeft + 1) {
                let row = Array(widgets[start..<end])
                split(
                    from: end, rowsLeft: rowsLeft - 1, rows: rows + [row],
                    widest: max(widest, totalWidth(for: row, showDividers: showDividers))
                )
            }
        }
        split(from: 0, rowsLeft: count, rows: [], widest: 0)
        return best
    }

    static func fittingWidgets(
        from ordered: [WidgetType],
        availableWidth: CGFloat,
        showDividers: Bool,
        bypassSpaceLimit: Bool = false,
        countsMusic: Bool = false
    ) -> [WidgetType] {
        if bypassSpaceLimit {
            return ordered.filter { $0 != .agent }
        }

        var used: CGFloat = 0
        var result: [WidgetType] = []

        for widget in ordered where widget != .agent {
            let width = countsMusic ? estimatedWidth(for: widget) : capacityWidth(for: widget)

            let spacing: CGFloat
            if result.isEmpty {
                spacing = 0
            } else {
                spacing = interWidgetSpacing + (showDividers ? dividerWidth : 0)
            }

            if result.isEmpty || used + spacing + width <= availableWidth {
                used += spacing + width
                result.append(widget)
            }
        }

        return result
    }

    static func canFit(
        _ widget: WidgetType,
        in orderedEnabled: [WidgetType],
        availableWidth: CGFloat,
        showDividers: Bool,
        bypassSpaceLimit: Bool = false
    ) -> Bool {
        guard widget != .agent else { return false }
        if bypassSpaceLimit { return true }
        var candidates = orderedEnabled.filter { $0 != .agent }
        if !candidates.contains(widget) {
            candidates.append(widget)
        }
        return fittingWidgets(from: candidates, availableWidth: availableWidth, showDividers: showDividers).contains(widget)
    }
}