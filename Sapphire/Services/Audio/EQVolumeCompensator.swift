//
//  EQVolumeCompensator.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-10-28
//

import Foundation
import CoreAudio

/// Raise Output Volume: the EQ pre-cuts every app on an output by a shared trim, and this raises that
/// output's own volume by the same number of dB so nothing ends up quieter. It only ever moves a volume by
/// the change in trim and remembers what it has added (across launches), so the user's own volume changes
/// stick, and switching the mode off, quitting or relaunching after a crash takes back exactly that much.
@MainActor
final class EQVolumeCompensator {
    static let shared = EQVolumeCompensator()

    private static let appliedDefaultsKey = "SapphireEQVolumeCompensationDB"

    private var targets: [String: Double] = [:]
    private var applied: [String: Double]

    private init() {
        applied = UserDefaults.standard.dictionary(forKey: Self.appliedDefaultsKey) as? [String: Double] ?? [:]
    }

    func setTargets(_ trims: [String: Double]) {
        targets = trims
        reconcile()
    }

    func removeAll() {
        targets = [:]
        reconcile()
    }

    /// Moves every connected output toward its target; unplugged ones catch up when they come back.
    func reconcile() {
        for uid in Set(targets.keys).union(applied.keys) {
            guard let deviceID = MixerEngine.deviceID(forUID: uid) else { continue }
            let target = targets[uid] ?? 0
            let current = applied[uid] ?? 0
            guard abs(target - current) > 0.05 else { continue }
            let reached = current + Self.adjustOutputVolume(of: deviceID, byDB: target - current)
            // When taking compensation back, one attempt is enough: an output the user has since turned
            // all the way down shouldn't be lowered again later.
            applied[uid] = target == 0 || abs(reached) < 0.05 ? nil : reached
        }
        UserDefaults.standard.set(applied, forKey: Self.appliedDefaultsKey)
    }

    // MARK: CoreAudio

    /// Moves the output volume by `delta` dB within the device's range and returns how far it moved.
    /// Uses the main volume control, or each stereo channel when the device only has per-channel ones.
    private static func adjustOutputVolume(of deviceID: AudioDeviceID, byDB delta: Double) -> Double {
        let elements: [AudioObjectPropertyElement] = isSettable(deviceID, element: kAudioObjectPropertyElementMain)
            ? [kAudioObjectPropertyElementMain]
            : [1, 2].filter { isSettable(deviceID, element: $0) }
        var moved: Double?
        for element in elements {
            guard let currentDB = decibels(of: deviceID, element: element),
                  let range = decibelRange(of: deviceID, element: element) else { continue }
            let newDB = min(max(currentDB + delta, range.mMinimum), range.mMaximum)
            guard setDecibels(newDB, of: deviceID, element: element) else { continue }
            let step = (decibels(of: deviceID, element: element) ?? newDB) - currentDB
            moved = moved.map { delta > 0 ? min($0, step) : max($0, step) } ?? step
        }
        return moved ?? 0
    }

    private static func volumeAddress(_ selector: AudioObjectPropertySelector, _ element: AudioObjectPropertyElement) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeOutput, mElement: element)
    }

    private static func isSettable(_ deviceID: AudioDeviceID, element: AudioObjectPropertyElement) -> Bool {
        var address = volumeAddress(kAudioDevicePropertyVolumeDecibels, element)
        guard AudioObjectHasProperty(deviceID, &address) else { return false }
        var settable: DarwinBoolean = false
        return AudioObjectIsPropertySettable(deviceID, &address, &settable) == noErr && settable.boolValue
    }

    private static func decibels(of deviceID: AudioDeviceID, element: AudioObjectPropertyElement) -> Double? {
        var address = volumeAddress(kAudioDevicePropertyVolumeDecibels, element)
        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &value) == noErr else { return nil }
        return Double(value)
    }

    private static func decibelRange(of deviceID: AudioDeviceID, element: AudioObjectPropertyElement) -> AudioValueRange? {
        var address = volumeAddress(kAudioDevicePropertyVolumeRangeDecibels, element)
        var range = AudioValueRange()
        var size = UInt32(MemoryLayout<AudioValueRange>.size)
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &range) == noErr else { return nil }
        return range
    }

    private static func setDecibels(_ value: Double, of deviceID: AudioDeviceID, element: AudioObjectPropertyElement) -> Bool {
        var address = volumeAddress(kAudioDevicePropertyVolumeDecibels, element)
        var newValue = Float32(value)
        return AudioObjectSetPropertyData(deviceID, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &newValue) == noErr
    }
}
