//
//  NotchBarSpacerPolicy.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-23
//

import CoreGraphics

enum NotchBarSpacerPolicy {

    static let automaticWidth: CGFloat = 0

    static let widthRange: ClosedRange<CGFloat> = 0...1000

    static func sanitizedWidth(_ raw: CGFloat) -> CGFloat {
        guard raw.isFinite, raw > 0 else { return automaticWidth }
        return min(raw, widthRange.upperBound)
    }

    static func hasFixedWidth(_ raw: CGFloat) -> Bool {
        sanitizedWidth(raw) > automaticWidth
    }

    static func symmetricItemsWidth(leading: CGFloat, trailing: CGFloat, inset: CGFloat) -> CGFloat {
        let safeLeading = max(0, leading.isFinite ? leading : 0)
        let safeTrailing = max(0, trailing.isFinite ? trailing : 0)
        let safeInset = max(0, inset.isFinite ? inset : 0)
        return max(safeLeading, safeTrailing) * 2 + safeInset * 2
    }

    static func minimumBarWidth(
        configuredWidth: CGFloat,
        itemsWidth: CGFloat,
        minimumSpacerWidth: CGFloat = 0
    ) -> CGFloat {
        let fixed = sanitizedWidth(configuredWidth)
        let safeItems = max(0, itemsWidth.isFinite ? itemsWidth : 0)
        let floor = sanitizedMinimumSpacer(minimumSpacerWidth)
        let spacer = hasFixedWidth(fixed) ? max(fixed, floor) : floor
        return safeItems + spacer
    }

    static func resolvedSpacerWidth(
        configuredWidth: CGFloat,
        barWidth: CGFloat,
        itemsWidth: CGFloat,
        minimumSpacerWidth: CGFloat = 0
    ) -> CGFloat {
        let fixed = sanitizedWidth(configuredWidth)
        let floor = sanitizedMinimumSpacer(minimumSpacerWidth)
        let safeBar = max(0, barWidth.isFinite ? barWidth : 0)
        let safeItems = max(0, itemsWidth.isFinite ? itemsWidth : 0)
        let available = max(0, safeBar - safeItems)
        if hasFixedWidth(fixed) {
            return max(floor, min(fixed, available))
        }
        return max(floor, available)
    }

    private static func sanitizedMinimumSpacer(_ raw: CGFloat) -> CGFloat {
        guard raw.isFinite, raw > 0 else { return 0 }
        return raw
    }
}