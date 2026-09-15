//
//  BatteryLowPowerView.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-08-17.
//

import SwiftUI

struct BatteryLowPowerView: View {
    let state: BatteryState
    let onToggle: () -> Void
    let onDismiss: () -> Void

    @ObservedObject private var powerMode = PowerModeManager.shared

    @State private var isShowing = false
    @State private var isPressed = false

    private var isLowPowerActive: Bool { powerMode.isLowPowerModeActive }
    private var accentColor: Color { isLowPowerActive ? .green : .red }

    var body: some View {
        ZStack(alignment: .topTrailing) {

            Button(action: {
                guard !isPressed else { return }

                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    isPressed = true
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    onToggle()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                        isPressed = false
                    }
                }
            }) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(state.level)% Battery")
                            .font(.system(.title3, design: .rounded).bold())
                            .foregroundColor(isPressed ? accentColor : .primary)

                        Text(isLowPowerActive ? "Tap to turn off Low Power Mode" : "Tap to turn on Low Power Mode")
                            .font(.body)
                            .foregroundColor(.secondary)
                    }

                    Spacer(minLength: 106)

                    ZStack {
                        Capsule()
                            .fill(accentColor.opacity(isPressed ? 0.35 : 0.2))
                            .frame(width: 80, height: 45)

                        Image(systemName: isLowPowerActive ? "leaf.fill" : "battery.25")
                            .font(.system(size: 32, weight: .light))
                            .foregroundColor(accentColor)
                    }
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 10)
            .padding(12)
            .padding(.top, (NotchConfiguration.universalHeight - 15))

            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundColor(.secondary.opacity(0.6))
                    .symbolRenderingMode(.hierarchical)
            }
            .buttonStyle(.plain)
            .padding(.top, 6)
            .padding(.trailing, 6)

        }
        .scaleEffect(isShowing ? 1 : 0.95)
        .opacity(isShowing ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                isShowing = true
            }
        }
    }
}