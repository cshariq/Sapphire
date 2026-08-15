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

    private let volumeDefaultsKey = "SapphirePerAppVolumeMap"
    private let muteDefaultsKey = "SapphirePerAppMuteMap"
    private let eqDefaultsKey = "SapphirePerAppEQMap"
    private let eqDeviceScopeDefaultsKey = "SapphirePerAppEQDeviceScopeMap"

    private var volumeMap: [String: Double] = [:]
    private var muteMap: [String: Bool] = [:]
    private var eqMap: [String: [Double]] = [:]
    private var eqDeviceScopeMap: [String: [String]] = [:]

    private init() {
        loadPersistedState()
    }

    func hasAdjustments(for bundleID: String) -> Bool {
        if volumeMap[bundleID] != nil && volumeMap[bundleID] != 1.0 { return true }
        if muteMap[bundleID] == true { return true }
        if let eq = eqMap[bundleID], !eq.allSatisfy({ $0 == 0.0 }) { return true }
        return false
    }

    func volume(for bundleID: String) -> Double {
        volumeMap[bundleID] ?? 1.0
    }

    func setVolume(_ value: Double, for bundleID: String) {
        let clamped = min(max(value, 0.0), 1.0)
        volumeMap[bundleID] = clamped
        persistDoubleMap(volumeMap, forKey: volumeDefaultsKey)

        NotificationCenter.default.post(name: .perAppAudioSettingsDidChange, object: self, userInfo: ["bundleID": bundleID])
        MultiAudioManager.shared.notifyAdjustmentMade(for: bundleID)
        MultiAudioManager.shared.setAppVolume(bundleID: bundleID, volume: Float(clamped))
    }

    func mute(for bundleID: String) -> Bool {
        muteMap[bundleID] ?? false
    }

    func setMute(_ muted: Bool, for bundleID: String) {
        muteMap[bundleID] = muted
        persistBoolMap(muteMap, forKey: muteDefaultsKey)

        NotificationCenter.default.post(name: .perAppAudioSettingsDidChange, object: self, userInfo: ["bundleID": bundleID])
        MultiAudioManager.shared.notifyAdjustmentMade(for: bundleID)
        MultiAudioManager.shared.setAppMute(bundleID: bundleID, isMuted: muted)
    }

    func eqGains(for bundleID: String) -> [Double] {
        eqMap[bundleID] ?? Array(repeating: 0.0, count: 10)
    }

    func setEQGains(_ gains: [Double], for bundleID: String) {
        eqMap[bundleID] = gains
        persistEQMap()

        NotificationCenter.default.post(name: .perAppAudioSettingsDidChange, object: self, userInfo: ["bundleID": bundleID])
        MultiAudioManager.shared.notifyAdjustmentMade(for: bundleID)
        MultiAudioManager.shared.setAppEQ(bundleID: bundleID, gains: gains)
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
        if let uids, !uids.isEmpty {
            eqDeviceScopeMap[bundleID] = Array(uids).sorted()
        } else {
            eqDeviceScopeMap.removeValue(forKey: bundleID)
        }
        persistEQScopeMap()

        NotificationCenter.default.post(name: .perAppAudioSettingsDidChange, object: self, userInfo: ["bundleID": bundleID])
        MultiAudioManager.shared.notifyAdjustmentMade(for: bundleID)
        MultiAudioManager.shared.setAppEQ(bundleID: bundleID, gains: eqGains(for: bundleID))
    }

    func appEQScopeEntries() -> [(bundleID: String, targetDeviceUIDs: Set<String>?)] {
        eqMap.keys.compactMap { bundleID in
            let gains = eqMap[bundleID] ?? []
            guard !gains.allSatisfy({ $0 == 0.0 }) else { return nil }
            return (bundleID: bundleID, targetDeviceUIDs: targetDeviceUIDs(for: bundleID))
        }
    }

    func reset(for bundleID: String) {
        volumeMap.removeValue(forKey: bundleID)
        muteMap.removeValue(forKey: bundleID)
        eqMap.removeValue(forKey: bundleID)
        eqDeviceScopeMap.removeValue(forKey: bundleID)

        persistDoubleMap(volumeMap, forKey: volumeDefaultsKey)
        persistBoolMap(muteMap, forKey: muteDefaultsKey)
        persistEQMap()
        persistEQScopeMap()

        NotificationCenter.default.post(name: .perAppAudioSettingsDidChange, object: self, userInfo: ["bundleID": bundleID])
        MultiAudioManager.shared.notifyAdjustmentMade(for: bundleID)
    }

    func clearAllPersistedState() {
        volumeMap.removeAll()
        muteMap.removeAll()
        eqMap.removeAll()
        eqDeviceScopeMap.removeAll()

        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: volumeDefaultsKey)
        defaults.removeObject(forKey: muteDefaultsKey)
        defaults.removeObject(forKey: eqDefaultsKey)
        defaults.removeObject(forKey: eqDeviceScopeDefaultsKey)

        NotificationCenter.default.post(name: .perAppAudioSettingsDidChange, object: self)
    }

    private func loadPersistedState() {
        volumeMap = loadDoubleMap(forKey: volumeDefaultsKey)
        muteMap = loadBoolMap(forKey: muteDefaultsKey)
        eqMap = loadEQMap(forKey: eqDefaultsKey)
        eqDeviceScopeMap = loadStringArrayMap(forKey: eqDeviceScopeDefaultsKey)
    }

    // MARK: - Persistence helpers

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