//
//  AudioDevice.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-21

import AppKit
import AudioToolbox

struct AudioDevice: Identifiable, Hashable {
    let id: AudioDeviceID
    let uid: String
    let name: String
    let icon: NSImage?
    let supportsAutoEQ: Bool

    func hash(into hasher: inout Hasher) {
        hasher.combine(uid)
    }

    static func == (lhs: AudioDevice, rhs: AudioDevice) -> Bool {
        lhs.uid == rhs.uid
    }
}