//
//  IntelligenceNotchView.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-30

#if !SAPPHIRE_FULL_BUILD
import SwiftUI

struct IntelligenceNotchView: View {
    @Binding var navigationStack: [NotchWidgetMode]

    init(navigationStack: Binding<[NotchWidgetMode]>) {
        _navigationStack = navigationStack
    }

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "sparkles").font(.system(size: 22))
            Text("Intelligence unavailable in this build").font(.caption)
        }
        .frame(width: 320)
    }
}
#endif