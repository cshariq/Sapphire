//
//  SportsPlayerView.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-30

import SwiftUI

struct SportsPlayerView: View {
    @Binding var navigationStack: [NotchWidgetMode]

    init(navigationStack: Binding<[NotchWidgetMode]>) {
        _navigationStack = navigationStack
    }

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "sportscourt.fill").font(.system(size: 22))
            Text("Sports").font(.headline)
        }
        .frame(width: 320)
    }
}