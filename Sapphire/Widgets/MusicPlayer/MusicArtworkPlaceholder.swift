//
//  MusicArtworkPlaceholder.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-10-15
//

import AppKit
import SwiftUI

struct MusicArtworkPlaceholder: View {
    var size: CGFloat

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(white: 0.26), Color(white: 0.15)],
                startPoint: .top,
                endPoint: .bottom
            )
            Image(systemName: "music.note")
                .font(.system(size: size * 0.42, weight: .medium))
                .foregroundStyle(Color(white: 0.55))
        }
        .frame(width: size, height: size)
    }
}

struct MusicArtworkImage: View {
    let image: NSImage?
    var size: CGFloat
    var contentMode: ContentMode = .fill

    var body: some View {
        if let image {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: contentMode)
                .frame(width: size, height: size)
        } else {
            MusicArtworkPlaceholder(size: size)
        }
    }
}