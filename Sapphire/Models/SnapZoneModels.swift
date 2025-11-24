//
//  SnapZoneModels.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-08-11.
//

import Foundation
import SwiftUI
import AppKit

struct SnapZone: Codable, Equatable, Identifiable, Hashable {
    var id: UUID
    var x: CGFloat
    var y: CGFloat
    var width: CGFloat
    var height: CGFloat

    init(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) {
        self.id = UUID()
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    init(id: UUID, x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) {
        self.id = id
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

struct SnapLayout: Codable, Equatable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var zones: [SnapZone]

    init(name: String, zones: [SnapZone]) {
        self.id = UUID()
        self.name = name
        self.zones = zones
    }

    init(id: UUID, name: String, zones: [SnapZone]) {
        self.id = id
        self.name = name
        self.zones = zones
    }
}

struct KeyboardShortcut: Codable, Equatable, Hashable {
    var key: String
    var modifiers: NSEvent.ModifierFlags

    enum CodingKeys: String, CodingKey {
        case key, modifiers
    }

    init(key: String, modifiers: NSEvent.ModifierFlags) {
        self.key = key
        self.modifiers = modifiers
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = try container.decode(String.self, forKey: .key)
        let rawValue = try container.decode(UInt.self, forKey: .modifiers)
        modifiers = NSEvent.ModifierFlags(rawValue: rawValue)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(key, forKey: .key)
        try container.encode(modifiers.rawValue, forKey: .modifiers)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(key)
        hasher.combine(modifiers.rawValue)
    }
}

struct Plane: Codable, Equatable, Identifiable {
    var id = UUID()
    var name: String
    var layoutID: UUID
    var shortcut: KeyboardShortcut?
    var assignments: [UUID: String] = [:]
}

struct LayoutTemplate {
    static let columns = SnapLayout(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        name: "Columns",
        zones: [
            .init(id: UUID(uuidString: "00000001-0001-0000-0000-000000000001")!, x: 0.0, y: 0.0, width: 1.0 / 3.0, height: 1.0),
            .init(id: UUID(uuidString: "00000001-0002-0000-0000-000000000001")!, x: 1.0 / 3.0, y: 0.0, width: 1.0 / 3.0, height: 1.0),
            .init(id: UUID(uuidString: "00000001-0003-0000-0000-000000000001")!, x: 2.0 / 3.0, y: 0.0, width: 1.0 / 3.0, height: 1.0),
        ]
    )

    static let rows = SnapLayout(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
        name: "Rows",
        zones: [
            .init(id: UUID(uuidString: "00000002-0001-0000-0000-000000000001")!, x: 0.0, y: 0.0, width: 1.0, height: 1.0 / 3.0),
            .init(id: UUID(uuidString: "00000002-0002-0000-0000-000000000001")!, x: 0.0, y: 1.0 / 3.0, width: 1.0, height: 1.0 / 3.0),
            .init(id: UUID(uuidString: "00000002-0003-0000-0000-000000000001")!, x: 0.0, y: 2.0 / 3.0, width: 1.0, height: 1.0 / 3.0),
        ]
    )

    static let focus = SnapLayout(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
        name: "Focus",
        zones: [
            .init(id: UUID(uuidString: "00000003-0001-0000-0000-000000000001")!, x: 0.0, y: 0.0, width: 2.0 / 3.0, height: 1.0),
            .init(id: UUID(uuidString: "00000003-0002-0000-0000-000000000001")!, x: 2.0 / 3.0, y: 0.0, width: 1.0 / 3.0, height: 1.0 / 2.0),
            .init(id: UUID(uuidString: "00000003-0003-0000-0000-000000000001")!, x: 2.0 / 3.0, y: 1.0 / 2.0, width: 1.0 / 3.0, height: 1.0 / 2.0),
        ]
    )

    static let fancy = SnapLayout(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!,
        name: "Fancy",
        zones: [
            .init(id: UUID(uuidString: "00000004-0001-0000-0000-000000000001")!, x: 0.0, y: 0.0, width: 0.3, height: 0.5),
            .init(id: UUID(uuidString: "00000004-0002-0000-0000-000000000001")!, x: 0.3, y: 0.0, width: 0.4, height: 0.5),
            .init(id: UUID(uuidString: "00000004-0003-0000-0000-000000000001")!, x: 0.7, y: 0.0, width: 0.3, height: 0.5),
            .init(id: UUID(uuidString: "00000004-0004-0000-0000-000000000001")!, x: 0.0, y: 0.5, width: 0.5, height: 0.5),
            .init(id: UUID(uuidString: "00000004-0005-0000-0000-000000000001")!, x: 0.5, y: 0.5, width: 0.5, height: 0.5),
        ]
    )

    static let quarters = SnapLayout(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000005")!,
        name: "Quarters",
        zones: [
            .init(id: UUID(uuidString: "00000005-0001-0000-0000-000000000001")!, x: 0.0, y: 0.0, width: 0.5, height: 0.5),
            .init(id: UUID(uuidString: "00000005-0002-0000-0000-000000000001")!, x: 0.0, y: 0.5, width: 0.5, height: 0.5),
            .init(id: UUID(uuidString: "00000005-0003-0000-0000-000000000001")!, x: 0.5, y: 0.5, width: 0.5, height: 0.5),
            .init(id: UUID(uuidString: "00000005-0004-0000-0000-000000000001")!, x: 0.5, y: 0.0, width: 0.5, height: 0.5),
        ]
    )

    static let splitscreen = SnapLayout(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000006")!,
        name: "Split Screen",
        zones: [
            .init(id: UUID(uuidString: "00000006-0001-0000-0000-000000000001")!, x: 0.0, y: 0.0, width: 0.5, height: 1.0),
            .init(id: UUID(uuidString: "00000006-0002-0000-0000-000000000001")!, x: 0.5, y: 0.0, width: 0.5, height: 1.0),
        ]
    )

    static let fullscreen = SnapLayout(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000007")!,
        name: "Full Screen",
        zones: [
            .init(id: UUID(uuidString: "00000007-0001-0000-0000-000000000001")!, x: 0.0, y: 0.0, width: 1.0, height: 1.0),
        ]
    )

    static let allTemplates: [SnapLayout] = [columns, rows, focus, fancy, quarters, splitscreen, fullscreen]
}