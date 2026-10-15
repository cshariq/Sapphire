//
//  LyricsAudioTap.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-15

import AppKit
import AVFoundation
import CoreAudio
import Foundation

@available(macOS 14.2, *)
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

    func start(processID: pid_t, muted: Bool = false, onBuffer: @escaping (AVAudioPCMBuffer) -> Void) throws {
        stop()

        let description = CATapDescription(stereoMixdownOfProcesses: try Self.processObjects(for: processID))
        description.uuid = UUID()
        description.muteBehavior = muted ? .mutedWhenTapped : .unmuted
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
        do {
            try Self.check("read tap format", AudioObjectGetPropertyData(tapID, &formatAddress, 0, nil, &size, &streamDescription))
        } catch {
            stop()
            throw error
        }
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
            Self.requestLargeIOBuffer(on: aggregateID)

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

    static let preferredIOBufferFrames: UInt32 = 4096

    private static func requestLargeIOBuffer(on device: AudioObjectID) {
        var range = AudioValueRange()
        var rangeSize = UInt32(MemoryLayout<AudioValueRange>.size)
        var rangeAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyBufferFrameSizeRange,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var frames = preferredIOBufferFrames
        if AudioObjectGetPropertyData(device, &rangeAddress, 0, nil, &rangeSize, &range) == noErr, range.mMaximum > 0 {
            frames = UInt32(min(max(Double(frames), range.mMinimum), range.mMaximum))
        }
        var sizeAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyBufferFrameSize,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectSetPropertyData(device, &sizeAddress, 0, nil, UInt32(MemoryLayout<UInt32>.size), &frames)
        if status != noErr {
            LyricsLog.info("Word timing: capture buffer size request (\(frames) frames) refused (OSStatus \(status)); using the default")
        }
    }

    private static func processObjects(for pid: pid_t) throws -> [AudioObjectID] {
        if let own = try? processObject(for: pid) { return [own] }
        let bundleID = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier ?? ""
        var prefixes = bundleID.isEmpty ? [] : [bundleID]
        if bundleID.hasPrefix("com.apple.Safari") { prefixes.append("com.apple.WebKit") }
        let helpers = allProcessObjects().filter { object in
            guard isRunningOutput(object), let helperID = string(object, kAudioProcessPropertyBundleID) else { return false }
            return prefixes.contains { helperID.hasPrefix($0) }
        }
        guard !helpers.isEmpty else { throw TapError.processNotFound(pid) }
        return helpers
    }

    private static func allProcessObjects() -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var objects = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &objects) == noErr else { return [] }
        return objects
    }

    private static func isRunningOutput(_ object: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyIsRunningOutput,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var running: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(object, &address, 0, nil, &size, &running) == noErr && running != 0
    }

    private static func string(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value?.takeRetainedValue() as String?
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