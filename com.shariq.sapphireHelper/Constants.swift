//
//  Constants.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-10-23

struct Constant {
    static let helperMachLabel = "com.shariq.sapphireHelper"
    // Root-owned: the helper writes this as root, so it must not live in a folder a user process can swap for a symlink.
    static let sleepBatteryLogPath = "/Library/Application Support/Sapphire/battery_sleep_log.jsonl"
}