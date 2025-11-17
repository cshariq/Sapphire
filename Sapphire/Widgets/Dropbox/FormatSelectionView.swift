//
//  FormatSelectionView.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-08-12.
//

import SwiftUI

struct FormatSelectionView: View {
    let sourceURL: URL
    let availableFormats: [ConversionFormat]
    var onFormatSelected: (ConversionFormat) -> Void
    var onDismiss: () -> Void

    @State private var isShowing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Convert \"\(sourceURL.lastPathComponent)\" to:")
                .font(.headline)
                .padding([.top, .horizontal])

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 15) {
                    ForEach(availableFormats) { format in
                        FormatButton(format: format) {
                            onFormatSelected(format)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
        }
        .frame(minWidth: 300, maxWidth: 450)
        .background(
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        )
        .overlay(
             RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .overlay(alignment: .topTrailing) {
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.plain)
            .font(.title2)
            .foregroundStyle(.secondary, .tertiary)
            .padding()
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

private struct FormatButton: View {
    let format: ConversionFormat
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack {
                Image(systemName: format.iconName)
                    .font(.largeTitle)
                    .foregroundStyle(.white)
                Text(format.displayName)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white.opacity(0.8))
            }
            .frame(width: 80, height: 80)
            .background(Color.white.opacity(isHovering ? 0.2 : 0.1))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovering ? 1.05 : 1.0)
        .onHover { hovering in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isHovering = hovering
            }
        }
    }
}