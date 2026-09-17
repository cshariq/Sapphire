//
//  AudioObjectID+Readiness.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-21

import AudioToolbox
import Dispatch

// MARK: - Device Readiness

extension AudioObjectID {
    func isDeviceAlive() -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsAlive,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var isAlive: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(self, &address, 0, nil, &size, &isAlive)
        return status == noErr && isAlive != 0
    }

    func waitUntilReady(timeout: TimeInterval = 1.0) -> Bool {
        guard !isDeviceAlive() else { return true }

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsAlive,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let signal = DispatchSemaphore(value: 0)
        let listenerQueue = DispatchQueue(label: "com.sapphire.audio-device-readiness")
        let listener: AudioObjectPropertyListenerBlock = { _, _ in signal.signal() }

        guard AudioObjectAddPropertyListenerBlock(self, &address, listenerQueue, listener) == noErr else {
            return isDeviceAlive()
        }
        defer {
            AudioObjectRemovePropertyListenerBlock(self, &address, listenerQueue, listener)
        }

        guard !isDeviceAlive() else { return true }
        _ = signal.wait(timeout: .now() + timeout)
        return isDeviceAlive()
    }
}