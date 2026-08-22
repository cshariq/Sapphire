//
//  UserEQPreset.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-21

import Foundation

struct UserEQPreset: Codable, Equatable, Identifiable {
    let id: UUID

    var name: String

    var settings: EQSettings

    let createdAt: Date

    init(id: UUID = UUID(), name: String, settings: EQSettings, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.settings = settings
        self.createdAt = createdAt
    }
}