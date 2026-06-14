//
//  PerAppAudioController.swift
//  Sapphire
//
//  Created by Codex on 2026-05-09.
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
    // bundleID -> target device UIDs. Missing or empty means "all devices".
    private var eqDeviceScopeMap: [String: [String]] = [:]

    private init() {
        loadPersistedState()
    }

    /// The key to Lazy Tapping. Returns true if the user has changed anything from default.
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
        UserDefaults.standard.set(volumeMap, forKey: volumeDefaultsKey)

        NotificationCenter.default.post(name: .perAppAudioSettingsDidChange, object: self, userInfo: ["bundleID": bundleID])
        MultiAudioManager.shared.notifyAdjustmentMade(for: bundleID)
        MultiAudioManager.shared.setAppVolume(bundleID: bundleID, volume: Float(clamped))
    }

    func mute(for bundleID: String) -> Bool {
        muteMap[bundleID] ?? false
    }

    func setMute(_ muted: Bool, for bundleID: String) {
        muteMap[bundleID] = muted
        UserDefaults.standard.set(muteMap, forKey: muteDefaultsKey)

        NotificationCenter.default.post(name: .perAppAudioSettingsDidChange, object: self, userInfo: ["bundleID": bundleID])
        MultiAudioManager.shared.notifyAdjustmentMade(for: bundleID)
        MultiAudioManager.shared.setAppMute(bundleID: bundleID, isMuted: muted)
    }

    func eqGains(for bundleID: String) -> [Double] {
        eqMap[bundleID] ?? Array(repeating: 0.0, count: 10)
    }

    func setEQGains(_ gains: [Double], for bundleID: String) {
        eqMap[bundleID] = gains
        UserDefaults.standard.set(eqMap, forKey: eqDefaultsKey)

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
        UserDefaults.standard.set(eqDeviceScopeMap, forKey: eqDeviceScopeDefaultsKey)

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

        UserDefaults.standard.set(volumeMap, forKey: volumeDefaultsKey)
        UserDefaults.standard.set(muteMap, forKey: muteDefaultsKey)
        UserDefaults.standard.set(eqMap, forKey: eqDefaultsKey)
        UserDefaults.standard.set(eqDeviceScopeMap, forKey: eqDeviceScopeDefaultsKey)

        NotificationCenter.default.post(name: .perAppAudioSettingsDidChange, object: self, userInfo: ["bundleID": bundleID])
        MultiAudioManager.shared.notifyAdjustmentMade(for: bundleID)
    }

    private func loadPersistedState() {
        volumeMap = UserDefaults.standard.dictionary(forKey: volumeDefaultsKey) as? [String: Double] ?? [:]
        muteMap = UserDefaults.standard.dictionary(forKey: muteDefaultsKey) as? [String: Bool] ?? [:]
        eqMap = UserDefaults.standard.dictionary(forKey: eqDefaultsKey) as? [String: [Double]] ?? [:]
        eqDeviceScopeMap = UserDefaults.standard.dictionary(forKey: eqDeviceScopeDefaultsKey) as? [String: [String]] ?? [:]
    }
}
