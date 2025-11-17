//
//  ShortcutModels.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-08-11.
//

import Foundation
import SwiftUI

struct CodableColor: Identifiable {
    let id = UUID()
    var cgColor: CGColor
    var location: CGFloat = 0.0

    init(cgColor: CGColor, location: CGFloat = 0.0) {
        self.cgColor = cgColor
        self.location = location
    }

    init(color: Color, location: CGFloat = 0.0) {
        self.cgColor = NSColor(color).cgColor
        self.location = location
    }

    var color: Color {
        get {
            Color(cgColor: cgColor)
        }
        set {
            self.cgColor = NSColor(newValue).cgColor
        }
    }
}

// MARK: - Core Conformances
extension CodableColor: Equatable {
    static func == (lhs: CodableColor, rhs: CodableColor) -> Bool {
        return lhs.cgColor == rhs.cgColor && lhs.location == rhs.location
    }
}

extension CodableColor: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(location)
        if let components = cgColor.components {
            hasher.combine(components)
        }
        if let colorSpaceName = cgColor.colorSpace?.name {
            hasher.combine(colorSpaceName)
        }
    }
}

// MARK: - Codable Conformance (from Ice)
extension CodableColor: Codable {
    private enum CodingKeys: String, CodingKey {
        case components
        case colorSpace
        case location
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        var components = try container.decode([CGFloat].self, forKey: .components)
        let iccData = try container.decode(Data.self, forKey: .colorSpace) as CFData

        self.location = try container.decodeIfPresent(CGFloat.self, forKey: .location) ?? 0.0

        guard let colorSpace = CGColorSpace(iccData: iccData) else {
            throw DecodingError.dataCorruptedError(
                forKey: .colorSpace,
                in: container,
                debugDescription: "Invalid ICC profile data"
            )
        }
        guard let cgColor = CGColor(colorSpace: colorSpace, components: &components) else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Invalid color space or components"
                )
            )
        }
        self.cgColor = cgColor
    }

    func encode(to encoder: Encoder) throws {
        guard let components = cgColor.components else {
            throw EncodingError.invalidValue(
                cgColor,
                EncodingError.Context(
                    codingPath: encoder.codingPath,
                    debugDescription: "Missing color components"
                )
            )
        }
        guard let colorSpace = cgColor.colorSpace else {
            throw EncodingError.invalidValue(
                cgColor,
                EncodingError.Context(
                    codingPath: encoder.codingPath,
                    debugDescription: "Missing color space"
                )
            )
        }
        guard let iccData = colorSpace.copyICCData() else {
            throw EncodingError.invalidValue(
                colorSpace,
                EncodingError.Context(
                    codingPath: encoder.codingPath,
                    debugDescription: "Missing ICC profile data"
                )
            )
        }
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(components, forKey: .components)
        try container.encode(iccData as Data, forKey: .colorSpace)
        try container.encode(location, forKey: .location)
    }
}

struct ShortcutInfo: Codable, Equatable, Identifiable, Hashable {
    let id: String
    let name: String
    var systemImageName: String?
    var backgroundColor: CodableColor?
    var iconColor: CodableColor?
}