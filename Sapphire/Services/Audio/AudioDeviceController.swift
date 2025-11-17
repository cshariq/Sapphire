//
//  AudioDeviceController.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-08-13.
//

import Foundation
import CoreAudio
import os.log

struct AudioDeviceController {
    static let shared = AudioDeviceController()
    private let logger = Logger(subsystem: "com.shariq.sapphire", category: "AudioDeviceController")

    func createAggregateDevice(outputDevices: [AudioDevice], masterDeviceUID: String) -> AudioDeviceID? {
        let subDeviceUIDs = outputDevices.map { $0.uid as CFString }

        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Sapphire Multi-Output",
            kAudioAggregateDeviceUIDKey: "com.shariq.sapphire.multi-output-device",
            kAudioAggregateDeviceSubDeviceListKey: subDeviceUIDs,
            kAudioAggregateDeviceMasterSubDeviceKey: masterDeviceUID as CFString,
            kAudioAggregateDeviceIsStackedKey: true
        ]

        var deviceID: AudioDeviceID = 0
        let status = AudioHardwareCreateAggregateDevice(description as CFDictionary, &deviceID)

        if status == noErr {
            logger.info("Successfully created aggregate device with ID: \(deviceID)")
            return deviceID
        } else {
            logger.error("Failed to create aggregate device. Status: \(status)")
            return nil
        }
    }

    func destroyAggregateDevice(id: AudioDeviceID) {
        let status = AudioHardwareDestroyAggregateDevice(id)
        if status == noErr {
            logger.info("Successfully destroyed aggregate device with ID: \(id)")
        } else {
            logger.error("Failed to destroy aggregate device \(id). Status: \(status)")
        }
    }
}