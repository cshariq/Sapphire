//
//  BatteryLowPowerView.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-08-17.
//

import SwiftUI

struct BatteryLowPowerView: View {
    let state: BatteryState
    let onEnable: () -> Void
    let onDismiss: () -> Void

    @State private var isShowing = false
    @State private var isPressed = false

    var body: some View {
        ZStack(alignment: .topTrailing) {

            Button(action: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    isPressed = true
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    onEnable()
                }
            }) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(state.level)% Battery")
                            .font(.system(.title3, design: .rounded).bold())
                            .foregroundColor(isPressed ? .yellow : .primary)

                        Text("Tap to turn on Low Power Mode")
                            .font(.body)
                            .foregroundColor(.secondary)
                    }

                    Spacer(minLength: 106)

                    ZStack {
                        Capsule()
                            .fill(isPressed ? Color.yellow.opacity(0.2) : Color.red.opacity(0.2))
                            .frame(width: 80, height: 45)

                        Image(systemName: "battery.25")
                            .font(.system(size: 32, weight: .light))
                            .foregroundColor(isPressed ? .yellow : .red)
                    }
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 10)
            .padding(12)
            .padding(.top, 0)

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