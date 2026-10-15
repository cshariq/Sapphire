//
//  SettingsObservation.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-28

import Foundation
import Observation
import SwiftUI

struct SettingsField {
    let keyPath: PartialKeyPath<Settings>
    let differs: (Settings, Settings) -> Bool

    init<Value: Equatable>(_ keyPath: KeyPath<Settings, Value>) {
        self.keyPath = keyPath
        differs = { $0[keyPath: keyPath] != $1[keyPath: keyPath] }
    }
}

final class SettingsFieldTracker: Observable, @unchecked Sendable {
    private static let fieldIndex: [PartialKeyPath<Settings>: Int] = Dictionary(
        SettingsField.all.enumerated().map { ($0.element.keyPath, $0.offset) },
        uniquingKeysWith: { first, _ in first }
    )
    private static let fieldKeys = SettingsField.all.indices.map { \SettingsFieldTracker.[field: $0] }
    private static let wholeKey = \SettingsFieldTracker.[field: -1]

    private let registrar = ObservationRegistrar()

    subscript(field index: Int) -> Int { index }

    func access<Value>(_ keyPath: KeyPath<Settings, Value>) {
        let key = Self.fieldIndex[keyPath].map { Self.fieldKeys[$0] } ?? Self.wholeKey
        registrar.access(self, keyPath: key)
    }

    func accessAll() {
        registrar.access(self, keyPath: Self.wholeKey)
    }

    func didChange(from old: Settings, to new: Settings) {
        var changedAny = false
        for (index, field) in SettingsField.all.enumerated() where field.differs(old, new) {
            changedAny = true
            registrar.withMutation(of: self, keyPath: Self.fieldKeys[index]) {}
        }
        if changedAny || old != new {
            registrar.withMutation(of: self, keyPath: Self.wholeKey) {}
        }
    }
}

protocol TrackedSettingsSource: AnyObject {
    var fieldTracker: SettingsFieldTracker { get }
    func readSettings<Value>(_ keyPath: KeyPath<Settings, Value>) -> Value
    var settingsSnapshot: Settings { get }
    func writeSettings(_ update: (inout Settings) -> Void)
}

@dynamicMemberLookup
struct TrackedSettings {
    let source: any TrackedSettingsSource

    subscript<Value>(dynamicMember keyPath: WritableKeyPath<Settings, Value>) -> Value {
        get {
            source.fieldTracker.access(keyPath)
            return source.readSettings(keyPath)
        }
        nonmutating set {
            source.writeSettings { $0[keyPath: keyPath] = newValue }
        }
    }

    subscript<Value>(dynamicMember keyPath: KeyPath<Settings, Value>) -> Value {
        source.fieldTracker.access(keyPath)
        return source.readSettings(keyPath)
    }

    subscript<Value>(keyPath keyPath: WritableKeyPath<Settings, Value>) -> Value {
        get { self[dynamicMember: keyPath] }
        nonmutating set { self[dynamicMember: keyPath] = newValue }
    }

    subscript<Value>(keyPath keyPath: KeyPath<Settings, Value>) -> Value {
        self[dynamicMember: keyPath]
    }

    var value: Settings {
        get {
            source.fieldTracker.accessAll()
            return source.settingsSnapshot
        }
        nonmutating set {
            source.writeSettings { $0 = newValue }
        }
    }
}

@dynamicMemberLookup
struct SettingsBindings {
    fileprivate let tracked: TrackedSettings

    subscript<Value>(dynamicMember keyPath: WritableKeyPath<Settings, Value>) -> Binding<Value> {
        let tracked = tracked
        return Binding(
            get: { tracked[dynamicMember: keyPath] },
            set: { tracked[dynamicMember: keyPath] = $0 }
        )
    }
}

// MARK: - App-wide settings

@propertyWrapper
struct ObservedSettings {
    init() {}
    var wrappedValue: SettingsObserver { .shared }
    var projectedValue: SettingsObserver.Bindings { .init() }
}

@dynamicMemberLookup
final class SettingsObserver: TrackedSettingsSource, @unchecked Sendable {
    static let shared = SettingsObserver()
    let fieldTracker = SettingsFieldTracker()

    private init() {}

    var settings: TrackedSettings { TrackedSettings(source: self) }

    subscript<Value>(dynamicMember keyPath: ReferenceWritableKeyPath<SettingsModel, Value>) -> Value {
        get { SettingsModel.shared[keyPath: keyPath] }
        set { SettingsModel.shared[keyPath: keyPath] = newValue }
    }

    subscript<Value>(dynamicMember keyPath: KeyPath<SettingsModel, Value>) -> Value {
        SettingsModel.shared[keyPath: keyPath]
    }

    func readSettings<Value>(_ keyPath: KeyPath<Settings, Value>) -> Value {
        SettingsModel.shared.current[keyPath: keyPath]
    }

    var settingsSnapshot: Settings { SettingsModel.shared.current }

    func writeSettings(_ update: (inout Settings) -> Void) {
        update(&SettingsModel.shared.settings)
    }

    @dynamicMemberLookup
    struct Bindings {
        var settings: SettingsBindings { SettingsBindings(tracked: SettingsObserver.shared.settings) }

        subscript<Value>(dynamicMember keyPath: ReferenceWritableKeyPath<SettingsModel, Value>) -> Binding<Value> {
            Binding(
                get: { SettingsModel.shared[keyPath: keyPath] },
                set: { SettingsModel.shared[keyPath: keyPath] = $0 }
            )
        }
    }
}

// MARK: - Settings window

@propertyWrapper
struct EditingSettings: DynamicProperty {
    @Environment(SettingsEditingSession.self) private var session

    init() {}
    var wrappedValue: SettingsEditingSession { session }
    var projectedValue: EditingSettingsBindings { EditingSettingsBindings(session: session) }
}

struct EditingSettingsBindings {
    fileprivate let session: SettingsEditingSession
    @MainActor var settings: SettingsBindings { SettingsBindings(tracked: session.settings) }
}