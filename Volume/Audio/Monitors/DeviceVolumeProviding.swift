//
//  DeviceVolumeProviding.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-21

import AudioToolbox

enum VolumeControlTier: String, Codable, Equatable {
    case hardware
    case ddc
    case software
}

@MainActor
protocol DeviceVolumeProviding: AnyObject {
    var defaultDeviceID: AudioDeviceID { get }
    var defaultDeviceUID: String? { get }
    var defaultInputDeviceUID: String? { get }
    var volumes: [AudioDeviceID: Float] { get }
    var muteStates: [AudioDeviceID: Bool] { get }

    var onVolumeChanged: ((AudioDeviceID, Float) -> Void)? { get set }
    var onMuteChanged: ((AudioDeviceID, Bool) -> Void)? { get set }
    var onDefaultDeviceChanged: ((String) -> Void)? { get set }
    var onDefaultInputDeviceChanged: ((String) -> Void)? { get set }

    @discardableResult
    func setDefaultDevice(_ deviceID: AudioDeviceID) -> Bool
    @discardableResult
    func setDefaultInputDevice(_ deviceID: AudioDeviceID) -> Bool

    func setVolume(for deviceID: AudioDeviceID, to volume: Float)

    func setMute(for deviceID: AudioDeviceID, to muted: Bool)

    func outputVolumeBackend(for deviceID: AudioDeviceID) -> VolumeControlTier

    func autoDetectedOutputVolumeBackend(for deviceID: AudioDeviceID) -> VolumeControlTier

    func outputProcessingGain(for deviceID: AudioDeviceID) -> Float
    func refreshOutputDeviceStates()

    func applyTierOverrideChange(for deviceID: AudioDeviceID)

    func start()
    func stop()

    func refreshAfterDDCProbe()
}

extension DeviceVolumeProviding {
    func outputProcessingGain(for deviceID: AudioDeviceID) -> Float {
        1.0
    }

    func refreshOutputDeviceStates() {}

    func applyTierOverrideChange(for deviceID: AudioDeviceID) {}

    func autoDetectedOutputVolumeBackend(for deviceID: AudioDeviceID) -> VolumeControlTier {
        outputVolumeBackend(for: deviceID)
    }

    func refreshAfterDDCProbe() {}
}