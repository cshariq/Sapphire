//
//  OrphanedTapCleanup.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-21

import AudioToolbox
import os

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.cshariq.sapphire", category: "OrphanedTapCleanup")

enum OrphanedTapCleanup {
    static func destroyOrphanedDevices() {
        let devices: [AudioDeviceID]
        do {
            devices = try AudioObjectID.readDeviceList()
        } catch {
            logger.error("[CLEANUP] Failed to read device list: \(error.localizedDescription)")
            return
        }

        var destroyedCount = 0

        for device in devices {
            let transportType = device.readTransportType()
            guard transportType == .aggregate else { continue }

            guard let name = try? device.readDeviceName(),
                  name.hasPrefix("Sapphire-") else { continue }

            let err = AudioHardwareDestroyAggregateDevice(device)
            if err == noErr {
                destroyedCount += 1
                logger.info("[CLEANUP] Destroyed orphaned aggregate device: \(name) (ID \(device))")
            } else {
                logger.error("[CLEANUP] Failed to destroy \(name) (ID \(device)): OSStatus \(err)")
            }
        }

        if destroyedCount == 0 {
            logger.info("[CLEANUP] No orphaned Sapphire devices found")
        } else {
            logger.info("[CLEANUP] Destroyed \(destroyedCount) orphaned device(s)")
        }
    }
}