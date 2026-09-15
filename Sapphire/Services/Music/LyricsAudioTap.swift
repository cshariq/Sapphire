//
//  LyricsAudioTap.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-15

import AVFoundation
import CoreAudio
import Foundation

final class LyricsAudioTap {
    enum TapError: LocalizedError {
        case processNotFound(pid_t)
        case coreAudio(String, OSStatus)
        case unsupportedFormat

        var errorDescription: String? {
            switch self {
            case .processNotFound(let pid): return "no Core Audio process for pid \(pid)"
            case .coreAudio(let step, let status): return "\(step) failed (OSStatus \(status))"
            case .unsupportedFormat: return "tap format is not readable"
            }
        }
    }

    private let queue = DispatchQueue(label: "com.shariq.sapphire.lyrics-audio-tap", qos: .userInitiated)
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?

    func start(processID: pid_t, onBuffer: @escaping (AVAudioPCMBuffer) -> Void) throws {
        stop()

        let description = CATapDescription(stereoMixdownOfProcesses: [try Self.processObject(for: processID)])
        description.uuid = UUID()
        description.muteBehavior = .unmuted
        description.isPrivate = true

        var newTap = AudioObjectID(kAudioObjectUnknown)
        try Self.check("create process tap", AudioHardwareCreateProcessTap(description, &newTap))
        tapID = newTap

        var streamDescription = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var formatAddress = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        try Self.check("read tap format", AudioObjectGetPropertyData(tapID, &formatAddress, 0, nil, &size, &streamDescription))
        guard let format = AVAudioFormat(streamDescription: &streamDescription) else {
            stop()
            throw TapError.unsupportedFormat
        }

        let aggregateDescription: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Sapphire Lyrics Timing",
            kAudioAggregateDeviceUIDKey: "com.shariq.sapphire.lyrics-tap.\(UUID().uuidString)",
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceTapListKey: [
                [kAudioSubTapUIDKey: description.uuid.uuidString, kAudioSubTapDriftCompensationKey: true],
            ],
        ]
        var newAggregate = AudioObjectID(kAudioObjectUnknown)
        do {
            try Self.check("create aggregate device", AudioHardwareCreateAggregateDevice(aggregateDescription as CFDictionary, &newAggregate))
            aggregateID = newAggregate

            var newProc: AudioDeviceIOProcID?
            try Self.check("create IO proc", AudioDeviceCreateIOProcIDWithBlock(&newProc, aggregateID, queue) { _, inputData, _, _, _ in
                guard let buffer = AVAudioPCMBuffer(pcmFormat: format, bufferListNoCopy: inputData, deallocator: nil) else { return }
                onBuffer(buffer)
            })
            ioProcID = newProc
            try Self.check("start aggregate device", AudioDeviceStart(aggregateID, newProc))
        } catch {
            stop()
            throw error
        }
    }

    func stop() {
        if aggregateID != kAudioObjectUnknown {
            if let ioProcID {
                AudioDeviceStop(aggregateID, ioProcID)
                AudioDeviceDestroyIOProcID(aggregateID, ioProcID)
            }
            AudioHardwareDestroyAggregateDevice(aggregateID)
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
        }
        ioProcID = nil
        aggregateID = AudioObjectID(kAudioObjectUnknown)
        tapID = AudioObjectID(kAudioObjectUnknown)
    }

    deinit {
        stop()
    }

    private static func processObject(for pid: pid_t) throws -> AudioObjectID {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var processID = pid
        var object = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            UInt32(MemoryLayout<pid_t>.size),
            &processID,
            &size,
            &object
        )
        guard status == noErr, object != kAudioObjectUnknown else { throw TapError.processNotFound(pid) }
        return object
    }

    private static func check(_ step: String, _ status: OSStatus) throws {
        guard status == noErr else { throw TapError.coreAudio(step, status) }
    }
}