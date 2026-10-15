//
//  MirrorCameraSelection.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-10-07.
//

import Foundation

struct MirrorCameraOption: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let isBuiltIn: Bool
    let isFrontFacing: Bool
}

enum MirrorCameraSelection {
    static func resolve(rememberedID: String?, options: [MirrorCameraOption], systemDefaultID: String?) -> String? {
        if let rememberedID, options.contains(where: { $0.id == rememberedID }) {
            return rememberedID
        }
        if let builtInFront = options.first(where: { $0.isBuiltIn && $0.isFrontFacing }) {
            return builtInFront.id
        }
        if let builtIn = options.first(where: \.isBuiltIn) {
            return builtIn.id
        }
        if let systemDefaultID, options.contains(where: { $0.id == systemDefaultID }) {
            return systemDefaultID
        }
        return options.first?.id
    }

    static func shouldReconfigure(activeID: String?, resolvedID: String?) -> Bool {
        activeID != resolvedID
    }
}