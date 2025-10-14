//
//  FileShelfActivityView.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-08-12.
//

import SwiftUI

struct FileShelfActivityView {
    static func left() -> some View {
        Image(systemName: "tray.full.fill")
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(.white.opacity(0.8))
            .symbolRenderingMode(.hierarchical)
    }

    static func right(count: Int) -> some View {
        Text("\(count) \(count == 1 ? "File" : "Files")")
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(.white.opacity(0.9))
    }
}