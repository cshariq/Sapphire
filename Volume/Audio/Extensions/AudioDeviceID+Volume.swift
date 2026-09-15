//
//  AudioDeviceID+Volume.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-21

import AudioToolbox

extension AudioDeviceID {
    private func propertyAddress(
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope,
        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: element
        )
    }

    private func readValue<Value>(
        at address: AudioObjectPropertyAddress,
        defaultValue: Value
    ) -> Value? {
        var address = address
        guard AudioObjectHasProperty(self, &address) else { return nil }

        var value = defaultValue
        var size = UInt32(MemoryLayout<Value>.size)
        guard AudioObjectGetPropertyData(self, &address, 0, nil, &size, &value) == noErr else {
            return nil
        }
        return value
    }

    private func writeValue<Value>(_ value: Value, at address: AudioObjectPropertyAddress) -> Bool {
        var address = address
        guard AudioObjectHasProperty(self, &address) else { return false }

        var value = value
        let size = UInt32(MemoryLayout<Value>.size)
        return AudioObjectSetPropertyData(self, &address, 0, nil, size, &value) == noErr
    }

    private func readVolumeScalar(scope: AudioObjectPropertyScope) -> Float {
        let candidates: [(AudioObjectPropertySelector, AudioObjectPropertyElement)] = [
            (kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioObjectPropertyElementMain),
            (kAudioDevicePropertyVolumeScalar, kAudioObjectPropertyElementMain),
            (kAudioDevicePropertyVolumeScalar, 1),
        ]

        for (selector, element) in candidates {
            let address = propertyAddress(selector: selector, scope: scope, element: element)
            if let volume: Float32 = readValue(at: address, defaultValue: 1.0) {
                return volume
            }
        }
        return 1.0
    }

    private func setVolumeScalar(_ volume: Float, scope: AudioObjectPropertyScope) -> Bool {
        let address = propertyAddress(
            selector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            scope: scope
        )
        let clampedVolume = Swift.max(0.0, Swift.min(1.0, volume))
        return writeValue(Float32(clampedVolume), at: address)
    }

    private func readMuteState(scope: AudioObjectPropertyScope) -> Bool {
        let address = propertyAddress(selector: kAudioDevicePropertyMute, scope: scope)
        let value: UInt32? = readValue(at: address, defaultValue: 0)
        return value.map { $0 != 0 } ?? false
    }

    private func setMuteState(_ muted: Bool, scope: AudioObjectPropertyScope) -> Bool {
        let address = propertyAddress(selector: kAudioDevicePropertyMute, scope: scope)
        return writeValue(UInt32(muted ? 1 : 0), at: address)
    }

    func hasOutputVolumeControl() -> Bool {
        var address = propertyAddress(
            selector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            scope: kAudioObjectPropertyScopeOutput
        )
        guard AudioObjectHasProperty(self, &address) else { return false }

        var settable: DarwinBoolean = false
        return AudioObjectIsPropertySettable(self, &address, &settable) == noErr && settable.boolValue
    }

    func readOutputVolumeScalar() -> Float {
        readVolumeScalar(scope: kAudioObjectPropertyScopeOutput)
    }

    func setOutputVolumeScalar(_ volume: Float) -> Bool {
        setVolumeScalar(volume, scope: kAudioObjectPropertyScopeOutput)
    }

    func readMuteState() -> Bool {
        readMuteState(scope: kAudioObjectPropertyScopeOutput)
    }

    func setMuteState(_ muted: Bool) -> Bool {
        setMuteState(muted, scope: kAudioObjectPropertyScopeOutput)
    }

    func readInputVolumeScalar() -> Float {
        readVolumeScalar(scope: kAudioObjectPropertyScopeInput)
    }

    func setInputVolumeScalar(_ volume: Float) -> Bool {
        setVolumeScalar(volume, scope: kAudioObjectPropertyScopeInput)
    }

    func readInputMuteState() -> Bool {
        readMuteState(scope: kAudioObjectPropertyScopeInput)
    }

    func setInputMuteState(_ muted: Bool) -> Bool {
        setMuteState(muted, scope: kAudioObjectPropertyScopeInput)
    }
}