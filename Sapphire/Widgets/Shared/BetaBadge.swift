//
//  BetaBadge.swift
//  Sapphire
//
//  A small "Beta" tag for marking newly-added, still-stabilizing features so
//  they're easy to tell apart from the app's established functionality.
//

import SwiftUI

struct BetaBadge: View {
    enum Style {
        /// Full "BETA" pill — for settings section headers, feature rows, list items.
        case pill
        /// Tiny corner dot — for icons/buttons with no room for text.
        case dot
    }

    var style: Style = .pill

    private var gradient: LinearGradient {
        LinearGradient(colors: [Color.orange, Color.pink], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var body: some View {
        switch style {
        case .pill:
            Text("BETA")
                .font(.system(size: 9, weight: .heavy, design: .rounded))
                .kerning(0.4)
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(gradient))
                .accessibilityLabel("Beta feature")
        case .dot:
            Circle()
                .fill(gradient)
                .frame(width: 7, height: 7)
                .overlay(Circle().stroke(Color.black.opacity(0.25), lineWidth: 0.5))
                .accessibilityLabel("Beta feature")
        }
    }
}

extension View {
    /// Overlays a small Beta indicator dot in the top-trailing corner of this view.
    func betaDot() -> some View {
        overlay(alignment: .topTrailing) {
            BetaBadge(style: .dot)
                .offset(x: 4, y: -4)
        }
    }

    /// Appends an inline "BETA" pill after this view (e.g. next to a settings row's title).
    func withBetaBadge() -> some View {
        HStack(spacing: 6) {
            self
            BetaBadge(style: .pill)
        }
    }
}
