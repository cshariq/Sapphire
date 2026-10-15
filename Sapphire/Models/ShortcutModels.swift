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

// MARK: - Codable Conformance
extension CodableColor: Codable {
    private enum CodingKeys: String, CodingKey {
        case components
        case colorSpaceName
        case colorSpace
        case location
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        var components = try container.decode([CGFloat].self, forKey: .components)
        self.location = try container.decodeIfPresent(CGFloat.self, forKey: .location) ?? 0.0

        let colorSpace: CGColorSpace
        if let name = try container.decodeIfPresent(String.self, forKey: .colorSpaceName) {
            guard let named = CGColorSpace(name: name as CFString) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .colorSpaceName,
                    in: container,
                    debugDescription: "Unknown color space \(name)"
                )
            }
            colorSpace = named
        } else {
            let iccData = try container.decode(Data.self, forKey: .colorSpace) as CFData
            guard let profiled = CGColorSpace(iccData: iccData) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .colorSpace,
                    in: container,
                    debugDescription: "Invalid ICC profile data"
                )
            }
            colorSpace = profiled
        }
        guard components.count == colorSpace.numberOfComponents + 1,
              let cgColor = CGColor(colorSpace: colorSpace, components: &components) else {
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
        guard let (name, components) = Self.portableRepresentation(of: cgColor) else {
            throw EncodingError.invalidValue(
                cgColor,
                EncodingError.Context(
                    codingPath: encoder.codingPath,
                    debugDescription: "Color has no components in a named color space"
                )
            )
        }
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(components, forKey: .components)
        try container.encode(name, forKey: .colorSpaceName)
        try container.encode(location, forKey: .location)
    }

    static func portableRepresentation(of color: CGColor) -> (name: String, components: [CGFloat])? {
        if let name = color.colorSpace?.name,
           CGColorSpace(name: name) != nil,
           let components = color.components {
            return (name as String, components)
        }
        guard let extended = CGColorSpace(name: CGColorSpace.extendedSRGB),
              let converted = color.converted(to: extended, intent: .defaultIntent, options: nil),
              let components = converted.components else {
            return nil
        }
        let inGamut = components.dropLast().allSatisfy { (0...1).contains($0) }
        return ((inGamut ? CGColorSpace.sRGB : CGColorSpace.extendedSRGB) as String, components)
    }
}

struct ShortcutInfo: Codable, Equatable, Identifiable, Hashable {
    let id: String
    let name: String
    var systemImageName: String?
    var backgroundColor: CodableColor?
    var iconColor: CodableColor?
}