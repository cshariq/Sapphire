//
//  PairedBluetoothDevice.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-21

import AppKit

struct PairedBluetoothDevice: Identifiable, Hashable {
    let id: String
    let name: String
    let icon: NSImage?

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
}