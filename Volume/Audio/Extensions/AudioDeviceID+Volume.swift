//
//  AudioDeviceID+Volume.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-21

import AudioToolbox

// MARK: - Volume Control Detection

extension AudioDeviceID {
    func hasOutputVolumeControl() -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(self, &address) else { return false }
        var settable: DarwinBoolean = false
        let err = AudioObjectIsPropertySettable(self, &address, &settable)
        return err == noErr && settable.boolValue
    }
}

// MARK: - Device Volume

extension AudioDeviceID {
    func readOutputVolumeScalar() -> Float {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        if AudioObjectHasProperty(self, &address) {
            var volume: Float32 = 1.0
            var size = UInt32(MemoryLayout<Float32>.size)
            let err = AudioObjectGetPropertyData(self, &address, 0, nil, &size, &volume)
            if err == noErr {
                return volume
            }
        }

        address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        if AudioObjectHasProperty(self, &address) {
            var volume: Float32 = 1.0
            var size = UInt32(MemoryLayout<Float32>.size)
            let err = AudioObjectGetPropertyData(self, &address, 0, nil, &size, &volume)
            if err == noErr {
                return volume
            }
        }

        address.mElement = 1
        if AudioObjectHasProperty(self, &address) {
            var volume: Float32 = 1.0
            var size = UInt32(MemoryLayout<Float32>.size)
            let err = AudioObjectGetPropertyData(self, &address, 0, nil, &size, &volume)
            if err == noErr {
                return volume
            }
        }

        return 1.0
    }

    func setOutputVolumeScalar(_ volume: Float) -> Bool {
        let clampedVolume = Swift.max(0.0, Swift.min(1.0, volume))

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        guard AudioObjectHasProperty(self, &address) else {
            return false
        }

        var volumeValue: Float32 = clampedVolume
        let size = UInt32(MemoryLayout<Float32>.size)
        let err = AudioObjectSetPropertyData(self, &address, 0, nil, size, &volumeValue)
        return err == noErr
    }
}

// MARK: - Device Mute

extension AudioDeviceID {
    func readMuteState() -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        guard AudioObjectHasProperty(self, &address) else {
            return false
        }

        var muted: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let err = AudioObjectGetPropertyData(self, &address, 0, nil, &size, &muted)
        return err == noErr && muted != 0
    }

    func setMuteState(_ muted: Bool) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        guard AudioObjectHasProperty(self, &address) else {
            return false
        }

        var value: UInt32 = muted ? 1 : 0
        let size = UInt32(MemoryLayout<UInt32>.size)
        let err = AudioObjectSetPropertyData(self, &address, 0, nil, size, &value)
        return err == noErr
    }
}

// MARK: - Input Device Volume

extension AudioDeviceID {
    func readInputVolumeScalar() -> Float {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )

        if AudioObjectHasProperty(self, &address) {
            var volume: Float32 = 1.0
            var size = UInt32(MemoryLayout<Float32>.size)
            let err = AudioObjectGetPropertyData(self, &address, 0, nil, &size, &volume)
            if err == noErr {
                return volume
            }
        }

        address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )

        if AudioObjectHasProperty(self, &address) {
            var volume: Float32 = 1.0
            var size = UInt32(MemoryLayout<Float32>.size)
            let err = AudioObjectGetPropertyData(self, &address, 0, nil, &size, &volume)
            if err == noErr {
                return volume
            }
        }

        address.mElement = 1
        if AudioObjectHasProperty(self, &address) {
            var volume: Float32 = 1.0
            var size = UInt32(MemoryLayout<Float32>.size)
            let err = AudioObjectGetPropertyData(self, &address, 0, nil, &size, &volume)
            if err == noErr {
                return volume
            }
        }

        return 1.0
    }

    func setInputVolumeScalar(_ volume: Float) -> Bool {
        let clampedVolume = Swift.max(0.0, Swift.min(1.0, volume))

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )

        guard AudioObjectHasProperty(self, &address) else {
            return false
        }

        var volumeValue: Float32 = clampedVolume
        let size = UInt32(MemoryLayout<Float32>.size)
        let err = AudioObjectSetPropertyData(self, &address, 0, nil, size, &volumeValue)
        return err == noErr
    }
}

// MARK: - Input Device Mute

extension AudioDeviceID {
    func readInputMuteState() -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )

        guard AudioObjectHasProperty(self, &address) else {
            return false
        }

        var muted: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let err = AudioObjectGetPropertyData(self, &address, 0, nil, &size, &muted)
        return err == noErr && muted != 0
    }

    func setInputMuteState(_ muted: Bool) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )

        guard AudioObjectHasProperty(self, &address) else {
            return false
        }

        var value: UInt32 = muted ? 1 : 0
        let size = UInt32(MemoryLayout<UInt32>.size)
        let err = AudioObjectSetPropertyData(self, &address, 0, nil, size, &value)
        return err == noErr
    }
}