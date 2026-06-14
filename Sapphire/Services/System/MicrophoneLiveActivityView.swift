// MicrophoneLiveActivityView.swift
// Sapphire
//
// Created by automated assistant

import SwiftUI

struct MicrophoneLiveActivityViewLeft: View {
    @ObservedObject private var mic = MicrophoneUsageManager.shared
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: mic.isMuted ? "mic.slash.fill" : "mic.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(mic.isMuted ? Color.red : Color.orange)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(mic.isMuted ? "Unmute microphone" : "Mute microphone")
    }
}

struct MicrophoneLiveActivityViewRight: View {
    @ObservedObject private var mic = MicrophoneUsageManager.shared
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(mic.isMuted ? "Muted" : "Active")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(mic.isMuted ? Color.red : Color.orange)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(mic.isMuted ? "Unmute microphone" : "Mute microphone")
    }
}

struct MicrophoneLiveActivityView {
    static func left(action: @escaping () -> Void) -> some View {
        MicrophoneLiveActivityViewLeft(action: action)
    }

    static func right(action: @escaping () -> Void) -> some View {
        MicrophoneLiveActivityViewRight(action: action)
    }
}
