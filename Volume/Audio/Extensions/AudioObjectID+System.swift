//
//  AudioObjectID+System.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-21

import AudioToolbox

// MARK: - Device List

extension AudioObjectID {
    static func readDeviceList() throws -> [AudioDeviceID] {
        try AudioObjectID.system.readArray(
            kAudioHardwarePropertyDevices,
            defaultValue: AudioDeviceID.unknown
        )
    }

    static func readProcessList() throws -> [AudioObjectID] {
        try AudioObjectID.system.readArray(
            kAudioHardwarePropertyProcessObjectList,
            defaultValue: AudioObjectID.unknown
        )
    }
}

// MARK: - Default Device

extension AudioDeviceID {
    static func readDefaultOutputDevice() throws -> AudioDeviceID {
        try AudioObjectID.system.read(
            kAudioHardwarePropertyDefaultOutputDevice,
            defaultValue: AudioDeviceID.unknown
        )
    }

    static func setDefaultOutputDevice(_ deviceID: AudioDeviceID) throws {
        try AudioObjectID.system.write(deviceID, to: kAudioHardwarePropertyDefaultOutputDevice)
    }
}

// MARK: - System Output Device (for alerts and system sounds)

extension AudioDeviceID {
    static func readSystemOutputDevice() throws -> AudioDeviceID {
        try AudioObjectID.system.read(
            kAudioHardwarePropertyDefaultSystemOutputDevice,
            defaultValue: AudioDeviceID.unknown
        )
    }

    static func setSystemOutputDevice(_ deviceID: AudioDeviceID) throws {
        try AudioObjectID.system.write(deviceID, to: kAudioHardwarePropertyDefaultSystemOutputDevice)
    }
}

// MARK: - Default Input Device

extension AudioDeviceID {
    static func readDefaultInputDevice() throws -> AudioDeviceID {
        try AudioObjectID.system.read(
            kAudioHardwarePropertyDefaultInputDevice,
            defaultValue: AudioDeviceID.unknown
        )
    }

    static func setDefaultInputDevice(_ deviceID: AudioDeviceID) throws {
        try AudioObjectID.system.write(deviceID, to: kAudioHardwarePropertyDefaultInputDevice)
    }
}