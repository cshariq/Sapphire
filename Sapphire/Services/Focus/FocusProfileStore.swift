//
//  FocusProfileStore.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-21

import Foundation
import Combine

@MainActor
final class FocusProfileStore: ObservableObject {
    static let shared = FocusProfileStore()

    @Published private(set) var profiles: [FocusProfile] = []
    @Published var activeProfileID: UUID {
        didSet { persist(); pushActiveIntoSettings() }
    }

    var activeProfile: FocusProfile {
        profiles.first(where: { $0.id == activeProfileID })
            ?? profiles.first
            ?? FocusProfile.makeDefault()
    }

    private let url: URL
    private var cancellables = Set<AnyCancellable>()
    private var suppressingSettingsMirror = false
    private var remoteMutationDepth = 0
    private var suppressNotifyUntil = Date.distantPast

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Sapphire", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        url = base.appendingPathComponent("focus-profiles.json")
        activeProfileID = UUID()
        loadOrMigrate()
        SettingsModel.shared.$settings
            .dropFirst()
            .debounce(for: .milliseconds(400), scheduler: RunLoop.main)
            .sink { [weak self] settings in
                self?.pullFromSettingsIfLegacy(settings)
            }
            .store(in: &cancellables)
    }

    // MARK: - CRUD

    func profile(id: UUID) -> FocusProfile? {
        profiles.first(where: { $0.id == id })
    }

    func upsert(_ profile: FocusProfile) {
        var next = profile
        next.updatedAt = Date()
        if let idx = profiles.firstIndex(where: { $0.id == next.id }) {
            profiles[idx] = next
        } else {
            profiles.append(next)
        }
        persist()
        if next.id == activeProfileID { pushActiveIntoSettings() }
        notifyProfilesChanged()
    }

    func delete(id: UUID) {
        guard profiles.count > 1 else { return }
        profiles.removeAll { $0.id == id }
        if activeProfileID == id {
            activeProfileID = profiles[0].id
        }
        persist()
        notifyProfilesChanged()
    }

    func select(_ id: UUID) {
        guard profiles.contains(where: { $0.id == id }) else { return }
        activeProfileID = id
        notifyProfilesChanged()
    }

    func updateActive(_ mutate: (inout FocusProfile) -> Void) {
        guard let idx = profiles.firstIndex(where: { $0.id == activeProfileID }) else { return }
        var p = profiles[idx]
        mutate(&p)
        p.updatedAt = Date()
        profiles[idx] = p
        persist()
        pushActiveIntoSettings()
        notifyProfilesChanged()
    }

    func replaceAll(_ list: [FocusProfile], activeID: UUID?) {
        guard !list.isEmpty else { return }
        profiles = list
        if let activeID, list.contains(where: { $0.id == activeID }) {
            activeProfileID = activeID
        } else {
            activeProfileID = list[0].id
        }
        persist()
        pushActiveIntoSettings()
        notifyProfilesChanged()
    }

    func beginRemoteMutation() {
        remoteMutationDepth += 1
        suppressingSettingsMirror = true
        suppressNotifyUntil = Date().addingTimeInterval(1.5)
    }

    func endRemoteMutation() {
        remoteMutationDepth = max(0, remoteMutationDepth - 1)
        suppressNotifyUntil = Date().addingTimeInterval(1.5)
        DispatchQueue.main.async { [weak self] in
            guard let self, self.remoteMutationDepth == 0 else { return }
            self.suppressingSettingsMirror = false
        }
    }

    private func notifyProfilesChanged() {
        guard remoteMutationDepth == 0, Date() >= suppressNotifyUntil else { return }
        NotificationCenter.default.post(name: .focusProfilesDidChange, object: nil)
    }

    // MARK: - Persist

    private struct DiskPayload: Codable {
        var profiles: [FocusProfile]
        var activeProfileID: UUID
    }

    private func persist() {
        let payload = DiskPayload(profiles: profiles, activeProfileID: activeProfileID)
        guard let data = try? JSONEncoder().encode(payload) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private func loadOrMigrate() {
        if let data = try? Data(contentsOf: url),
           let payload = try? JSONDecoder().decode(DiskPayload.self, from: data),
           !payload.profiles.isEmpty {
            profiles = payload.profiles
            activeProfileID = payload.profiles.contains(where: { $0.id == payload.activeProfileID })
                ? payload.activeProfileID
                : payload.profiles[0].id
            pushActiveIntoSettings()
            return
        }

        var seeded = FocusProfile.presets()
        let settings = SettingsModel.shared.settings
        seeded[0].durationSeconds = Int(settings.focusSessionDuration)
        seeded[0].breakEnabled = settings.focusBreakEnabled
        seeded[0].breakSeconds = Int(settings.focusBreakDuration)
        seeded[0].intensity = settings.focusIntensity
        seeded[0].blockingMode = settings.focusBlockingMode
        seeded[0].blockingEnabled = settings.focusBlockingEnabled
        seeded[0].blockDuringBreaks = settings.focusBlockingDuringBreaks
        seeded[0].blockedMacApps = settings.focusBlockedApps
        seeded[0].allowedMacApps = settings.focusAllowedApps
        seeded[0].blockedWebsites = settings.focusBlockedWebsites
        profiles = seeded
        activeProfileID = seeded[0].id
        persist()
        pushActiveIntoSettings()
    }

    func pushActiveIntoSettings() {
        suppressingSettingsMirror = true
        let p = activeProfile
        var s = SettingsModel.shared.settings
        s.focusSessionDuration = TimeInterval(p.durationSeconds)
        s.focusBreakEnabled = p.breakEnabled
        s.focusBreakDuration = TimeInterval(p.breakSeconds)
        s.focusIntensity = p.intensity
        s.focusBlockingMode = p.blockingMode
        s.focusBlockingEnabled = p.blockingEnabled
        s.focusBlockingDuringBreaks = p.blockDuringBreaks
        s.focusBlockedApps = p.blockedMacApps
        s.focusAllowedApps = p.allowedMacApps
        s.focusBlockedWebsites = p.blockedWebsites.union(p.social.resolvedWebsiteDomains())
        if s != SettingsModel.shared.settings {
            SettingsModel.shared.settings = s
        }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.remoteMutationDepth == 0 else { return }
            self.suppressingSettingsMirror = false
        }
    }

    private func pullFromSettingsIfLegacy(_ settings: Settings) {
        guard !suppressingSettingsMirror, remoteMutationDepth == 0 else { return }
        guard let idx = profiles.firstIndex(where: { $0.id == activeProfileID }) else { return }
        var p = profiles[idx]
        let socialDomains = p.social.resolvedWebsiteDomains()
        let nextWebsites = settings.focusBlockedWebsites.subtracting(socialDomains)
        guard p.durationSeconds != Int(settings.focusSessionDuration)
            || p.breakEnabled != settings.focusBreakEnabled
            || p.breakSeconds != Int(settings.focusBreakDuration)
            || p.intensity != settings.focusIntensity
            || p.blockingMode != settings.focusBlockingMode
            || p.blockingEnabled != settings.focusBlockingEnabled
            || p.blockDuringBreaks != settings.focusBlockingDuringBreaks
            || p.blockedMacApps != settings.focusBlockedApps
            || p.allowedMacApps != settings.focusAllowedApps
            || p.blockedWebsites != nextWebsites
        else { return }

        p.durationSeconds = Int(settings.focusSessionDuration)
        p.breakEnabled = settings.focusBreakEnabled
        p.breakSeconds = Int(settings.focusBreakDuration)
        p.intensity = settings.focusIntensity
        p.blockingMode = settings.focusBlockingMode
        p.blockingEnabled = settings.focusBlockingEnabled
        p.blockDuringBreaks = settings.focusBlockingDuringBreaks
        p.blockedMacApps = settings.focusBlockedApps
        p.allowedMacApps = settings.focusAllowedApps
        p.blockedWebsites = nextWebsites
        p.updatedAt = Date()
        profiles[idx] = p
        persist()
    }
}

extension Notification.Name {
    static let focusProfilesDidChange = Notification.Name("SapphireFocusProfilesDidChange")
}