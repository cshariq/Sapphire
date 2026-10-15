//
//  MenuBarSectionStore.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-10-12
//

import AppKit

extension Notification.Name {
    static let menuBarSectionsDidChange = Notification.Name("com.sapphire.menuBarSectionsDidChange")
}

enum MenuBarSectionKind: String, CaseIterable, Codable, Identifiable {
    case shown
    case hidden
    case alwaysHidden

    var id: String { rawValue }

    var title: String {
        switch self {
        case .shown: return "Shown"
        case .hidden: return "Hidden"
        case .alwaysHidden: return "Always Hidden"
        }
    }

    fileprivate var visibilityRank: Int {
        switch self {
        case .shown: return 2
        case .hidden: return 1
        case .alwaysHidden: return 0
        }
    }
}

enum MenuBarSystemItem: Int, CaseIterable, Identifiable {
    case battery = 0
    case bluetooth = 1
    case clock = 2
    case displays = 3
    case keyboard = 4
    case volume = 5
    case wifi = 6
    case screenMirroring = 7
    case controlCenter = 8

    var id: Int { rawValue }

    var key: String { "system:\(rawValue)" }

    var title: String {
        switch self {
        case .battery: return "Battery"
        case .bluetooth: return "Bluetooth"
        case .clock: return "Clock"
        case .displays: return "Displays"
        case .keyboard: return "Keyboard"
        case .volume: return "Sound"
        case .wifi: return "Wi-Fi"
        case .screenMirroring: return "Screen Mirroring"
        case .controlCenter: return "Control Center"
        }
    }

    var symbolName: String {
        switch self {
        case .battery: return "battery.75percent"
        case .bluetooth: return "wave.3.right"
        case .clock: return "clock"
        case .displays: return "sun.max"
        case .keyboard: return "keyboard"
        case .volume: return "speaker.wave.2"
        case .wifi: return "wifi"
        case .screenMirroring: return "rectangle.on.rectangle"
        case .controlCenter: return "switch.2"
        }
    }

    init?(menuExtraIdentifier identifier: String) {
        let name = identifier.lowercased().replacingOccurrences(of: "com.apple.menuextra.", with: "")
        switch name {
        case "battery": self = .battery
        case "bluetooth": self = .bluetooth
        case "clock": self = .clock
        case "display", "displays": self = .displays
        case "textinput", "keyboard", "keyboardbrightness": self = .keyboard
        case "sound", "volume": self = .volume
        case "wifi", "airport": self = .wifi
        case "screenmirroring", "airplay": self = .screenMirroring
        case "controlcenter": self = .controlCenter
        default: return nil
        }
    }
}

@MainActor
final class MenuBarSectionStore {
    static let shared = MenuBarSectionStore()

    private static let assignmentsKey = "SapphireMenuBarSections"
    private static let namesKey = "SapphireMenuBarSectionNames"

    private(set) var assignments: [String: MenuBarSectionKind]
    private(set) var names: [String: String]

    private init() {
        let raw = UserDefaults.standard.dictionary(forKey: Self.assignmentsKey) as? [String: String] ?? [:]
        assignments = raw.compactMapValues(MenuBarSectionKind.init(rawValue:))
        names = UserDefaults.standard.dictionary(forKey: Self.namesKey) as? [String: String] ?? [:]
    }

    var hasLearnedLayout: Bool { !assignments.isEmpty }

    func section(for key: String) -> MenuBarSectionKind {
        assignments[key] ?? .shown
    }

    func keys(in section: MenuBarSectionKind) -> Set<String> {
        Set(assignments.filter { $0.value == section }.map(\.key))
    }

    func set(_ section: MenuBarSectionKind, for key: String, name: String? = nil) {
        merge([key: section], names: name.map { [key: $0] } ?? [:])
    }

    func merge(_ learned: [String: MenuBarSectionKind], names learnedNames: [String: String] = [:]) {
        var changed = false
        for (key, section) in learned where assignments[key] != section {
            assignments[key] = section
            changed = true
        }
        for (key, name) in learnedNames where names[key] != name {
            names[key] = name
        }
        persist()
        if changed {
            NotificationCenter.default.post(name: .menuBarSectionsDidChange, object: nil)
        }
    }

    func reset() {
        assignments.removeAll()
        persist()
        NotificationCenter.default.post(name: .menuBarSectionsDidChange, object: nil)
    }

    private func persist() {
        UserDefaults.standard.set(assignments.mapValues(\.rawValue), forKey: Self.assignmentsKey)
        UserDefaults.standard.set(names, forKey: Self.namesKey)
    }

    // MARK: - Keys

    nonisolated static func key(for app: NSRunningApplication?) -> String? {
        app?.bundleIdentifier
    }
}

// MARK: - Learning sections from the bar

enum MenuBarSectionClassifier {
    struct Placement: Equatable {
        let key: String
        let midX: CGFloat
    }

    nonisolated static func classify(
        _ placements: [Placement],
        hiddenDividerMidX: CGFloat?,
        alwaysHiddenDividerMidX: CGFloat?
    ) -> [String: MenuBarSectionKind] {
        guard let hiddenDividerMidX else { return [:] }
        var result: [String: MenuBarSectionKind] = [:]
        for placement in placements {
            let section: MenuBarSectionKind
            if let alwaysHiddenDividerMidX, placement.midX < alwaysHiddenDividerMidX {
                section = .alwaysHidden
            } else if placement.midX < hiddenDividerMidX {
                section = .hidden
            } else {
                section = .shown
            }
            if let existing = result[placement.key], existing.visibilityRank >= section.visibilityRank { continue }
            result[placement.key] = section
        }
        return result
    }
}