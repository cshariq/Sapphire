//
//  FocusTriggerEngine.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-21

import Foundation
import Combine

@MainActor
final class FocusTriggerEngine {
    static let shared = FocusTriggerEngine()

    private var cancellables = Set<AnyCancellable>()
    private var lastTriggeredProfileID: UUID?
    private var suppressing = false
    private var suppressUntil = Date.distantPast

    private init() {}

    private var isSuppressed: Bool {
        suppressing
            || Date() < suppressUntil
            || ContinuityManager.shared.focusModeManager.isApplyingRemoteFocus
    }

    func start() {
        guard cancellables.isEmpty else { return }

        FocusModeManager.shared.$currentStatus
            .removeDuplicates()
            .sink { [weak self] status in
                self?.handleSystemFocus(status)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .focusProfilesDidChange)
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.handleSystemFocus(FocusModeManager.shared.currentStatus)
            }
            .store(in: &cancellables)
    }

    func stop() {
        cancellables.removeAll()
    }

    func handlePeerSystemFocus(active: Bool) {
        guard !isSuppressed else { return }
        let store = FocusProfileStore.shared
        let matches = store.profiles.filter { $0.triggers.syncPeerSystemFocus }
        guard !matches.isEmpty else { return }
        let profile = matches.first(where: { $0.id == store.activeProfileID })
            ?? matches.sorted(by: { $0.name < $1.name }).first!
        if active {
            activate(profile, reason: "peer-system-focus")
        } else if FocusSessionManager.shared.isSessionActive,
                  store.activeProfileID == profile.id,
                  lastTriggeredProfileID == profile.id {
            deactivate(reason: "peer-system-focus-off")
        }
    }

    private func handleSystemFocus(_ status: FocusStatus) {
        guard !isSuppressed else { return }
        let store = FocusProfileStore.shared

        if status.isActive {
            let match = store.profiles.first { profile in
                let ids = Set(profile.triggers.macOSFocusModeIDs)
                let names = Set(profile.triggers.macOSFocusModeNames.map { $0.lowercased() })
                if !ids.isEmpty, ids.contains(status.identifier) { return true }
                if !names.isEmpty, names.contains(status.name.lowercased()) { return true }
                return false
            }
            if let match {
                activate(match, reason: "macos-focus:\(status.name)")
            }
        } else if let last = lastTriggeredProfileID,
                  store.activeProfileID == last,
                  FocusSessionManager.shared.isSessionActive {
            deactivate(reason: "macos-focus-off")
            lastTriggeredProfileID = nil
        }
    }

    private func activate(_ profile: FocusProfile, reason: String) {
        let store = FocusProfileStore.shared
        let session = FocusSessionManager.shared
        if store.activeProfileID != profile.id {
            store.select(profile.id)
        }
        guard !session.isSessionActive else { return }
        lastTriggeredProfileID = profile.id
        session.startFocusSession(duration: TimeInterval(max(60, profile.durationSeconds)))
        NSLog("[FocusTrigger] started profile '\(profile.name)' via \(reason)")
    }

    private func deactivate(reason: String) {
        guard FocusSessionManager.shared.isSessionActive else { return }
        FocusSessionManager.shared.stopSessionFromSync()
        NSLog("[FocusTrigger] stopped via \(reason)")
    }

    func withSuppressed(_ body: () -> Void) {
        suppressing = true
        suppressUntil = Date().addingTimeInterval(1.5)
        defer {
            suppressing = false
            suppressUntil = Date().addingTimeInterval(1.2)
        }
        body()
    }
}