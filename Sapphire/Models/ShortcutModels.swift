//
//  ShortcutModels.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-08-11.
//
//

import Foundation
import SwiftUI

struct CodableColor: Codable, Equatable, Hashable, Identifiable {
    let id = UUID()
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double
    var location: Double = 0.0 // Location for gradient stops (0.0 to 1.0)

    init(color: Color, location: Double = 0.0) {
        let resolved = color.resolve(in: .init())
        self.red = Double(resolved.red)
        self.green = Double(resolved.green)
        self.blue = Double(resolved.blue)
        self.alpha = Double(resolved.opacity)
        self.location = location
    }

    var color: Color {
        get {
            Color(red: red, green: green, blue: blue, opacity: alpha)
        }
        set {
            let resolved = newValue.resolve(in: .init())
            self.red = Double(resolved.red)
            self.green = Double(resolved.green)
            self.blue = Double(resolved.blue)
            self.alpha = Double(resolved.opacity)
        }
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    private enum CodingKeys: String, CodingKey {
        case red, green, blue, alpha, location
    }
}

struct ShortcutInfo: Codable, Equatable, Identifiable, Hashable {
    let id: String // The UUID of the shortcut
    let name: String
    var systemImageName: String?
    var backgroundColor: CodableColor?
    var iconColor: CodableColor?
}