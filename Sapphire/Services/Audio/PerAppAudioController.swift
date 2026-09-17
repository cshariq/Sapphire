//
//  PerAppAudioController.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-05-09.
//

import Foundation
import AppKit

@MainActor
final class PerAppAudioController {
    static let shared = PerAppAudioController()

    enum ChangeKind: String {
        case volume
        case mute
        case equalizer
        case deviceScope
        case reset
    }

    nonisolated static let changeKindUserInfoKey = "kind"

    private let volumeDefaultsKey = "SapphirePerAppVolumeMap"
    private let muteDefaultsKey = "SapphirePerAppMuteMap"
    private let eqDefaultsKey = "SapphirePerAppEQMap"
    private let eqBassDefaultsKey = "SapphirePerAppEQBassMap"
    private let eqDeviceScopeDefaultsKey = "SapphirePerAppEQDeviceScopeMap"

    private var volumeMap: [String: Double] = [:]
    private var muteMap: [String: Bool] = [:]
    private var eqMap: [String: [Double]] = [:]
    private var eqBassMap: [String: Double] = [:]
    private var eqDeviceScopeMap: [String: [String]] = [:]
    private var persistenceTask: Task<Void, Never>?

    private init() {
        loadPersistedState()
    }

    func hasAdjustments(for bundleID: String) -> Bool {
        if volumeMap[bundleID] != nil && volumeMap[bundleID] != 1.0 { return true }
        if muteMap[bundleID] == true { return true }
        if hasEqualizerAdjustment(for: bundleID) { return true }
        return false
    }

    func hasEqualizerAdjustment(for bundleID: String) -> Bool {
        if let eq = eqMap[bundleID], !eq.allSatisfy({ $0 == 0.0 }) { return true }
        return eqBassMap[bundleID] != nil && eqBassMap[bundleID] != 0.0
    }

    func volume(for bundleID: String) -> Double {
        volumeMap[bundleID] ?? 1.0
    }

    func setVolume(_ value: Double, for bundleID: String) {
        let clamped = min(max(value, 0.0), 1.0)
        guard volume(for: bundleID) != clamped else { return }
        let previouslyNeededTap = hasAdjustments(for: bundleID)
        volumeMap[bundleID] = clamped
        schedulePersistence()

        postChange(.volume, bundleID: bundleID)
        reconcileIfTapRequirementChanged(previouslyNeededTap, bundleID: bundleID)
        MultiAudioManager.shared.setAppVolume(bundleID: bundleID, volume: Float(clamped))
    }

    func mute(for bundleID: String) -> Bool {
        muteMap[bundleID] ?? false
    }

    func setMute(_ muted: Bool, for bundleID: String) {
        guard mute(for: bundleID) != muted else { return }
        let previouslyNeededTap = hasAdjustments(for: bundleID)
        muteMap[bundleID] = muted
        persistBoolMap(muteMap, forKey: muteDefaultsKey)

        postChange(.mute, bundleID: bundleID)
        reconcileIfTapRequirementChanged(previouslyNeededTap, bundleID: bundleID)
        MultiAudioManager.shared.setAppMute(bundleID: bundleID, isMuted: muted)
    }

    func eqGains(for bundleID: String) -> [Double] {
        AudioEQ.normalize(eqMap[bundleID] ?? AudioEQ.flat)
    }

    func setEQGains(_ gains: [Double], for bundleID: String) {
        let normalized = AudioEQ.normalize(gains)
        guard eqGains(for: bundleID) != normalized else { return }
        let previouslyNeededTap = hasAdjustments(for: bundleID)
        eqMap[bundleID] = normalized
        schedulePersistence()

        postChange(.equalizer, bundleID: bundleID)
        reconcileIfTapRequirementChanged(previouslyNeededTap, bundleID: bundleID)
        MultiAudioManager.shared.setAppEQ(bundleID: bundleID, gains: normalized, bassGain: eqBass(for: bundleID))
    }

    func eqBass(for bundleID: String) -> Double {
        eqBassMap[bundleID] ?? 0.0
    }

    func setEQBass(_ value: Double, for bundleID: String) {
        let clamped = min(max(value, AudioEQ.bassRange.lowerBound), AudioEQ.bassRange.upperBound)
        guard eqBass(for: bundleID) != clamped else { return }
        let previouslyNeededTap = hasAdjustments(for: bundleID)
        if clamped == 0.0 {
            eqBassMap.removeValue(forKey: bundleID)
        } else {
            eqBassMap[bundleID] = clamped
        }
        schedulePersistence()

        postChange(.equalizer, bundleID: bundleID)
        reconcileIfTapRequirementChanged(previouslyNeededTap, bundleID: bundleID)
        MultiAudioManager.shared.setAppEQ(bundleID: bundleID, gains: eqGains(for: bundleID), bassGain: clamped)
    }

    func targetDeviceUIDs(for bundleID: String) -> Set<String>? {
        guard let uids = eqDeviceScopeMap[bundleID], !uids.isEmpty else { return nil }
        return Set(uids)
    }

    func appliesEQ(for bundleID: String, toDeviceUID deviceUID: String) -> Bool {
        guard let targetUIDs = targetDeviceUIDs(for: bundleID) else { return true }
        return targetUIDs.contains(deviceUID)
    }

    func setEQTargetDeviceUIDs(_ uids: Set<String>?, for bundleID: String) {
        let normalizedUIDs = uids.flatMap { $0.isEmpty ? nil : Set($0) }
        guard targetDeviceUIDs(for: bundleID) != normalizedUIDs else { return }
        if let uids = normalizedUIDs {
            eqDeviceScopeMap[bundleID] = Array(uids).sorted()
        } else {
            eqDeviceScopeMap.removeValue(forKey: bundleID)
        }
        persistEQScopeMap()

        postChange(.deviceScope, bundleID: bundleID)
        MultiAudioManager.shared.setAppEQ(bundleID: bundleID, gains: eqGains(for: bundleID), bassGain: eqBass(for: bundleID))
    }

    func appEQScopeEntries() -> [(bundleID: String, targetDeviceUIDs: Set<String>?)] {
        let bundleIDs = Set(eqMap.keys).union(eqBassMap.keys)
        return bundleIDs.compactMap { bundleID in
            let gains = eqMap[bundleID] ?? []
            let hasBands = !gains.allSatisfy({ $0 == 0.0 }) && !gains.isEmpty
            let hasBass = (eqBassMap[bundleID] ?? 0.0) != 0.0
            guard hasBands || hasBass else { return nil }
            return (bundleID: bundleID, targetDeviceUIDs: targetDeviceUIDs(for: bundleID))
        }
    }

    func reset(for bundleID: String) {
        let previouslyNeededTap = hasAdjustments(for: bundleID)
        volumeMap.removeValue(forKey: bundleID)
        muteMap.removeValue(forKey: bundleID)
        eqMap.removeValue(forKey: bundleID)
        eqBassMap.removeValue(forKey: bundleID)
        eqDeviceScopeMap.removeValue(forKey: bundleID)

        persistDoubleMap(volumeMap, forKey: volumeDefaultsKey)
        persistBoolMap(muteMap, forKey: muteDefaultsKey)
        persistEQMap()
        persistEQBassMap()
        persistEQScopeMap()

        postChange(.reset, bundleID: bundleID)
        MultiAudioManager.shared.setAppVolume(bundleID: bundleID, volume: 1.0)
        MultiAudioManager.shared.setAppMute(bundleID: bundleID, isMuted: false)
        MultiAudioManager.shared.setAppEQ(bundleID: bundleID, gains: AudioEQ.flat, bassGain: 0.0)
        reconcileIfTapRequirementChanged(previouslyNeededTap, bundleID: bundleID)
    }

    func clearAllPersistedState() {
        persistenceTask?.cancel()
        persistenceTask = nil
        let affectedBundleIDs = Set(volumeMap.keys)
            .union(muteMap.keys)
            .union(eqMap.keys)
            .union(eqBassMap.keys)
        volumeMap.removeAll()
        muteMap.removeAll()
        eqMap.removeAll()
        eqBassMap.removeAll()
        eqDeviceScopeMap.removeAll()

        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: volumeDefaultsKey)
        defaults.removeObject(forKey: muteDefaultsKey)
        defaults.removeObject(forKey: eqDefaultsKey)
        defaults.removeObject(forKey: eqBassDefaultsKey)
        defaults.removeObject(forKey: eqDeviceScopeDefaultsKey)

        NotificationCenter.default.post(
            name: .perAppAudioSettingsDidChange,
            object: self,
            userInfo: [Self.changeKindUserInfoKey: ChangeKind.reset.rawValue]
        )
        for bundleID in affectedBundleIDs {
            MultiAudioManager.shared.setAppVolume(bundleID: bundleID, volume: 1.0)
            MultiAudioManager.shared.setAppMute(bundleID: bundleID, isMuted: false)
            MultiAudioManager.shared.setAppEQ(bundleID: bundleID, gains: AudioEQ.flat, bassGain: 0.0)
        }
        MultiAudioManager.shared.notifyAdjustmentMade(for: "ResetAllPerAppAudio")
    }

    private func loadPersistedState() {
        volumeMap = loadDoubleMap(forKey: volumeDefaultsKey)
        muteMap = loadBoolMap(forKey: muteDefaultsKey)
        eqMap = loadEQMap(forKey: eqDefaultsKey).mapValues { AudioEQ.normalize($0) }
        eqBassMap = loadDoubleMap(forKey: eqBassDefaultsKey)
        eqDeviceScopeMap = loadStringArrayMap(forKey: eqDeviceScopeDefaultsKey)
    }

    // MARK: - Persistence helpers

    private func postChange(_ kind: ChangeKind, bundleID: String) {
        NotificationCenter.default.post(
            name: .perAppAudioSettingsDidChange,
            object: self,
            userInfo: [
                "bundleID": bundleID,
                Self.changeKindUserInfoKey: kind.rawValue
            ]
        )
    }

    private func reconcileIfTapRequirementChanged(_ previousValue: Bool, bundleID: String) {
        guard previousValue != hasAdjustments(for: bundleID) else { return }
        MultiAudioManager.shared.notifyAdjustmentMade(for: bundleID)
    }

    private func schedulePersistence() {
        persistenceTask?.cancel()
        persistenceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, let self else { return }
            self.persistenceTask = nil
            self.persistAllMaps()
        }
    }

    private func persistAllMaps() {
        persistDoubleMap(volumeMap, forKey: volumeDefaultsKey)
        persistBoolMap(muteMap, forKey: muteDefaultsKey)
        persistEQMap()
        persistEQBassMap()
        persistEQScopeMap()
    }

    private func persistDoubleMap(_ map: [String: Double], forKey key: String) {
        UserDefaults.standard.set(map, forKey: key)
    }

    private func persistBoolMap(_ map: [String: Bool], forKey key: String) {
        UserDefaults.standard.set(map, forKey: key)
    }

    private func persistEQMap() {
        if let data = try? JSONEncoder().encode(eqMap) {
            UserDefaults.standard.set(data, forKey: eqDefaultsKey)
        }
    }

    private func persistEQBassMap() {
        if let data = try? JSONEncoder().encode(eqBassMap) {
            UserDefaults.standard.set(data, forKey: eqBassDefaultsKey)
        }
    }

    private func persistEQScopeMap() {
        if let data = try? JSONEncoder().encode(eqDeviceScopeMap) {
            UserDefaults.standard.set(data, forKey: eqDeviceScopeDefaultsKey)
        }
    }

    private func loadDoubleMap(forKey key: String) -> [String: Double] {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([String: Double].self, from: data) {
            return decoded
        }
        guard let raw = UserDefaults.standard.dictionary(forKey: key) else { return [:] }
        var result: [String: Double] = [:]
        for (k, v) in raw {
            if let d = v as? Double {
                result[k] = d
            } else if let n = v as? NSNumber {
                result[k] = n.doubleValue
            }
        }
        return result
    }

    private func loadBoolMap(forKey key: String) -> [String: Bool] {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([String: Bool].self, from: data) {
            return decoded
        }
        guard let raw = UserDefaults.standard.dictionary(forKey: key) else { return [:] }
        var result: [String: Bool] = [:]
        for (k, v) in raw {
            if let b = v as? Bool {
                result[k] = b
            } else if let n = v as? NSNumber {
                result[k] = n.boolValue
            }
        }
        return result
    }

    private func loadEQMap(forKey key: String) -> [String: [Double]] {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([String: [Double]].self, from: data) {
            return decoded
        }
        guard let raw = UserDefaults.standard.dictionary(forKey: key) else { return [:] }
        var result: [String: [Double]] = [:]
        for (k, v) in raw {
            if let arr = v as? [Double] {
                result[k] = arr
            } else if let arr = v as? [NSNumber] {
                result[k] = arr.map(\.doubleValue)
            } else if let arr = v as? [Any] {
                result[k] = arr.compactMap { ($0 as? NSNumber)?.doubleValue ?? ($0 as? Double) }
            }
        }
        return result
    }

    private func loadStringArrayMap(forKey key: String) -> [String: [String]] {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([String: [String]].self, from: data) {
            return decoded
        }
        guard let raw = UserDefaults.standard.dictionary(forKey: key) else { return [:] }
        var result: [String: [String]] = [:]
        for (k, v) in raw {
            if let arr = v as? [String] {
                result[k] = arr
            } else if let arr = v as? [Any] {
                result[k] = arr.compactMap { $0 as? String }
            }
        }
        return result
    }
}