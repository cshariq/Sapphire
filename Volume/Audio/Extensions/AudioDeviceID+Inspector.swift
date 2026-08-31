//
//  AudioDeviceID+Inspector.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-21

import AudioToolbox
import Foundation
import os

private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.cshariq.sapphire",
    category: "AudioDeviceID+Inspector"
)

// MARK: - Inspector Errors

extension AudioDeviceID {
    enum InspectorError: Error {
        case writeFailed(OSStatus)
    }
}

// MARK: - Physical Format

extension AudioDeviceID {
    func readPhysicalFormat(
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeOutput
    ) -> AudioStreamBasicDescription? {
        var streamsAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )

        var size: UInt32 = 0
        let sizeErr = AudioObjectGetPropertyDataSize(self, &streamsAddress, 0, nil, &size)
        guard sizeErr == noErr, size >= UInt32(MemoryLayout<AudioObjectID>.size) else {
            return nil
        }

        let count = Int(size) / MemoryLayout<AudioObjectID>.size
        var streams = [AudioObjectID](repeating: AudioObjectID(kAudioObjectUnknown), count: count)
        let streamsErr = AudioObjectGetPropertyData(self, &streamsAddress, 0, nil, &size, &streams)
        guard streamsErr == noErr,
              let firstStream = streams.first,
              firstStream != AudioObjectID(kAudioObjectUnknown) else {
            return nil
        }

        var formatAddress = AudioObjectPropertyAddress(
            mSelector: kAudioStreamPropertyPhysicalFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var asbd = AudioStreamBasicDescription()
        var asbdSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        let formatErr = AudioObjectGetPropertyData(firstStream, &formatAddress, 0, nil, &asbdSize, &asbd)
        guard formatErr == noErr else {
            return nil
        }
        return asbd
    }
}

// MARK: - Available Sample Rates

extension AudioDeviceID {
    func readAvailableSampleRates(
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> [Double] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyAvailableNominalSampleRates,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )

        var size: UInt32 = 0
        let sizeErr = AudioObjectGetPropertyDataSize(self, &address, 0, nil, &size)
        guard sizeErr == noErr, size > 0 else {
            return []
        }

        let count = Int(size) / MemoryLayout<AudioValueRange>.size
        var ranges = [AudioValueRange](repeating: AudioValueRange(), count: count)
        let dataErr = AudioObjectGetPropertyData(self, &address, 0, nil, &size, &ranges)
        guard dataErr == noErr else {
            return []
        }

        var rates: [Double] = []
        rates.reserveCapacity(count)
        for range in ranges {
            if range.mMinimum == range.mMaximum {
                rates.append(range.mMinimum)
            } else {
                rates.append(range.mMinimum)
                rates.append(range.mMaximum)
            }
        }
        return rates
    }
}

// MARK: - Hog Mode

extension AudioDeviceID {
    func readHogModeOwner() -> pid_t {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyHogMode,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var owner: pid_t = -1
        var size = UInt32(MemoryLayout<pid_t>.size)
        let err = AudioObjectGetPropertyData(self, &address, 0, nil, &size, &owner)
        guard err == noErr else {
            return -1
        }
        return owner
    }
}

// MARK: - Nominal Sample Rate Write

extension AudioDeviceID {
    func writeNominalSampleRate(
        _ rate: Double,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) throws {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )

        var value = Float64(rate)
        let size = UInt32(MemoryLayout<Float64>.size)
        let err = AudioObjectSetPropertyData(self, &address, 0, nil, size, &value)
        guard err == noErr else {
            logger.debug("writeNominalSampleRate(\(rate)) failed with OSStatus \(err)")
            throw InspectorError.writeFailed(err)
        }
    }
}

// MARK: - Settability

extension AudioDeviceID {
    func isPropertySettable(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeOutput
    ) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(self, &address) else { return false }

        var settable: DarwinBoolean = false
        let err = AudioObjectIsPropertySettable(self, &address, &settable)
        return err == noErr && settable.boolValue
    }
}