//
//  LoginPromptView.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-06-27.
//

import SwiftUI

struct LoginPromptView: View {
    @Binding var navigationStack: [NotchWidgetMode]

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundColor(.yellow)

            Text("Login Required")
                .font(.title2).bold()

            Text("Please log in to Spotify via the Music section in Sapphire's settings to use this feature.")
                .font(.subheadline).foregroundColor(.secondary).multilineTextAlignment(.center)

            Text("Use the back control in the notch to return.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(30)
        .frame(width: 400)
    }
}

struct ApiKeysMissingView: View {
    @Binding var navigationStack: [NotchWidgetMode]

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "key.viewfinder")
                .font(.system(size: 40))
                .foregroundColor(.yellow)

            Text("Spotify API Keys Missing")
                .font(.title2).bold()

            Text("To enable Spotify integration, please add your API credentials in Sapphire's settings.")
                .font(.subheadline).foregroundColor(.secondary).multilineTextAlignment(.center)

            Text("Use the back control in the notch to return.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(30)
        .frame(width: 400)
    }
}

struct GeminiApiKeysMissingView: View {
    @Binding var navigationStack: [NotchWidgetMode]

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "key.viewfinder")
                .font(.system(size: 40))
                .symbolRenderingMode(.multicolor)

            Text("Gemini API Key Missing")
                .font(.title2).bold()

            Text("To use Gemini Live, please add your Google AI Studio API key in Sapphire's settings.")
                .font(.subheadline).foregroundColor(.secondary).multilineTextAlignment(.center)

            Text("Use the back control in the notch to return.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(30)
        .frame(width: 400)
    }
}
