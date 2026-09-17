//
//  SettingsChanges.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-13

import AppKit
import Combine
import Foundation

private final class SettingsModelUpdateSequence: @unchecked Sendable {
    struct Token {
        let sequence: UInt64
        let isSessionCommit: Bool
    }

    private let lock = NSLock()
    private var value: UInt64 = 0
    private var sessionCommitDepth = 0

    func next() -> Token {
        lock.lock()
        value &+= 1
        let token = Token(sequence: value, isSessionCommit: sessionCommitDepth > 0)
        lock.unlock()
        return token
    }

    func performSessionCommit(_ action: () -> Void) {
        lock.lock()
        sessionCommitDepth += 1
        lock.unlock()
        defer {
            lock.lock()
            sessionCommitDepth = max(0, sessionCommitDepth - 1)
            lock.unlock()
        }
        action()
    }

    var current: UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

extension SettingsModel {
    func changes<Value: Equatable>(of value: @escaping (Settings) -> Value) -> AnyPublisher<Value, Never> {
        $settings
            .map(value)
            .removeDuplicates()
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }
}

@MainActor
final class SettingsEditingSession: ObservableObject {
    @Published var settings: Settings {
        didSet {
            guard !isApplyingModelUpdate else { return }
            isDirty = true
            pendingCommit.send()
        }
    }

    private let model: SettingsModel
    private let modelUpdateSequence = SettingsModelUpdateSequence()
    private let pendingCommit = PassthroughSubject<Void, Never>()
    private var cancellables = Set<AnyCancellable>()
    private var baseline: Settings
    private var isApplyingModelUpdate = false
    private var isDirty = false

    init(model: SettingsModel = .shared) {
        self.model = model
        self.settings = model.settings
        self.baseline = model.settings

        pendingCommit
            .debounce(for: .milliseconds(100), scheduler: RunLoop.main)
            .sink { [weak self] in
                self?.commitNow()
            }
            .store(in: &cancellables)

        let updateSequence = modelUpdateSequence
        model.$settings
            .dropFirst()
            .map { (token: updateSequence.next(), settings: $0) }
            .receive(on: RunLoop.main)
            .sink { [weak self] update in
                self?.applyModelUpdate(
                    update.settings,
                    token: update.token,
                    latestSequence: updateSequence.current
                )
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)
            .sink { [weak self] _ in
                self?.flushPendingSave()
            }
            .store(in: &cancellables)
    }

    func commitNow() {
        guard isDirty else { return }
        guard settings != baseline else {
            isDirty = false
            return
        }
        let localSettings = settings
        let currentModelSettings = model.settings
        let committedSettings: Settings

        if currentModelSettings == baseline {
            committedSettings = localSettings
        } else {
            committedSettings = Self.rebaseLocalChanges(
                from: baseline,
                local: localSettings,
                onto: currentModelSettings
            )
        }

        isDirty = false
        applyToEditor(committedSettings)

        modelUpdateSequence.performSessionCommit {
            model.settings = committedSettings
        }

        let normalizedSettings = model.settings
        baseline = normalizedSettings
        if normalizedSettings != committedSettings {
            applyToEditor(normalizedSettings)
        }
    }

    func flushPendingSave() {
        commitNow()
        model.flushPendingSave()
    }

    func makeBackupDocument() -> SettingsBackupDocument {
        commitNow()
        return model.makeBackupDocument()
    }

    func importSettings(from url: URL) throws {
        commitNow()
        try model.importSettings(from: url)
        applyExternalModelUpdate(model.settings)
    }

    func resetAllSettings() {
        commitNow()
        model.resetAllSettings()
        applyExternalModelUpdate(model.settings)
    }

    private func applyModelUpdate(
        _ updated: Settings,
        token: SettingsModelUpdateSequence.Token,
        latestSequence: UInt64
    ) {
        guard token.sequence == latestSequence else { return }
        guard !token.isSessionCommit else { return }
        applyExternalModelUpdate(updated)
    }

    private func applyExternalModelUpdate(_ updated: Settings) {
        if isDirty {
            let rebased = Self.rebaseLocalChanges(
                from: baseline,
                local: settings,
                onto: updated
            )
            baseline = updated
            applyToEditor(rebased)
            isDirty = rebased != updated
            return
        }

        baseline = updated
        applyToEditor(updated)
        isDirty = false
    }

    private func applyToEditor(_ updated: Settings) {
        guard updated != settings else { return }
        isApplyingModelUpdate = true
        settings = updated
        isApplyingModelUpdate = false
    }

    private static func rebaseLocalChanges(
        from baseline: Settings,
        local: Settings,
        onto external: Settings
    ) -> Settings {
        guard let baselineValues = SettingsPersistence.encodeToDictionary(baseline),
              let localValues = SettingsPersistence.encodeToDictionary(local),
              var mergedValues = SettingsPersistence.encodeToDictionary(external) else {
            return local
        }

        for key in Set(baselineValues.keys).union(localValues.keys) {
            guard !jsonValuesAreEqual(baselineValues[key], localValues[key]) else { continue }
            if let localValue = localValues[key] {
                mergedValues[key] = localValue
            } else {
                mergedValues.removeValue(forKey: key)
            }
        }

        return SettingsPersistence.decodeFromDictionary(mergedValues) ?? local
    }

    private static func jsonValuesAreEqual(_ lhs: Any?, _ rhs: Any?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil):
            return true
        case (nil, _), (_, nil):
            return false
        case let (lhs?, rhs?):
            return NSDictionary(dictionary: ["value": lhs])
                .isEqual(to: ["value": rhs])
        }
    }
}