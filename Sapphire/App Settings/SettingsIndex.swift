//
//  SettingsIndex.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-26

import Foundation

enum SettingsIndex {
    struct Entry: Identifiable, Hashable {
        let key: String
        let title: String?
        let detail: String?
        let section: SettingsSection?
        let range: ClosedRange<Double>?
        let options: [String]?

        var id: String { key }

        var displayTitle: String { title ?? SettingsIndex.humanized(key) }
    }

    enum Value: Equatable {
        case bool(Bool)
        case number(Double)
        case text(String)

        var description: String {
            switch self {
            case .bool(let on): return on ? "on" : "off"
            case .number(let value):
                return value.rounded() == value ? String(Int(value)) : String(format: "%.2f", value)
            case .text(let text): return text
            }
        }
    }

    struct Change: Identifiable, Equatable {
        let id = UUID()
        let entry: Entry
        let oldValue: Value
        let newValue: Value
    }

    enum ChangeError: Error, CustomStringConvertible {
        case unknownSetting(String)
        case invalidValue(key: String, expected: String)

        var description: String {
            switch self {
            case .unknownSetting(let key):
                return "There is no setting named \(key). Search for it first."
            case .invalidValue(let key, let expected):
                return "\(key) can't take that value. Expected \(expected)."
            }
        }
    }

    static let entries: [Entry] = generatedEntries
    static let byKey: [String: Entry] = Dictionary(entries.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })

    // MARK: - Search

    static func search(_ query: String, limit: Int = 6) -> [Entry] {
        let typed = query.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 1 && !stopWords.contains($0) }
        guard !typed.isEmpty else { return [] }
        var stems = Set(typed.map(stem))
        for word in typed { synonyms[word]?.forEach { stems.insert(stem($0)) } }

        let weights = Dictionary(uniqueKeysWithValues: stems.map { word -> (String, Double) in
            let hits = searchText.filter { $0.matches(word) }.count
            return (word, log(Double(entries.count + 1) / Double(hits + 1)))
        })

        let scored: [(Entry, Double)] = zip(entries, searchText).compactMap { entry, text in
            var score = 0.0
            var matched = 0
            for word in stems {
                var hit = 0.0
                if text.title.contains(where: { matches($0, word) }) { hit += 4 }
                if text.key.contains(where: { matches($0, word) }) || text.rawKey.hasPrefix(word) { hit += 3 }
                if text.detail.contains(where: { matches($0, word) }) { hit += 1 }
                if text.pane.contains(where: { matches($0, word) }) { hit += 1 }
                if hit > 0 { matched += 1 }
                score += hit * (weights[word] ?? 0)
            }
            guard matched > 0 else { return nil }
            score *= 1 + Double(matched - 1) * 0.5
            if entry.title != nil { score *= 1.1 }
            return (entry, score)
        }
        let ranked = scored.sorted { $0.1 == $1.1 ? $0.0.displayTitle < $1.0.displayTitle : $0.1 > $1.1 }
        guard let best = ranked.first?.1 else { return [] }
        return ranked
            .prefix(limit)
            .filter { $0.1 >= best * 0.3 }
            .map(\.0)
    }

    private struct SearchText {
        let title: [String]
        let key: [String]
        let rawKey: String
        let detail: [String]
        let pane: [String]

        func matches(_ word: String) -> Bool {
            rawKey.hasPrefix(word) || [title, key, detail, pane].contains { $0.contains { SettingsIndex.matches($0, word) } }
        }
    }

    private static let endings: Set<Substring> = ["", "s", "es", "d", "ed", "ing", "r", "er", "ers", "ion", "ions", "ly"]

    private static func matches(_ indexed: String, _ word: String) -> Bool {
        indexed.hasPrefix(word) && endings.contains(indexed.dropFirst(word.count))
    }

    private static let searchText: [SearchText] = entries.map { entry in
        SearchText(
            title: words(entry.displayTitle),
            key: words(humanized(entry.key)),
            rawKey: entry.key.lowercased(),
            detail: words(entry.detail ?? ""),
            pane: words(entry.section.map { ([$0.label] + $0.searchTokens).joined(separator: " ") } ?? "")
        )
    }

    private static func words(_ text: String) -> [String] {
        text.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
    }

    private static func stem(_ word: String) -> String {
        word.count > 3 && word.hasSuffix("s") && !word.hasSuffix("ss") ? String(word.dropLast()) : word
    }

    private static let synonyms: [String: [String]] = [
        "smaller": ["width", "height", "size"], "bigger": ["width", "height", "size"], "larger": ["width", "height", "size"],
        "wider": ["width"], "narrower": ["width"], "taller": ["height"], "shorter": ["height"], "size": ["width", "height"],
        "dark": ["theme", "appearance"], "light": ["theme", "appearance"], "colour": ["color"],
        "login": ["launch"], "startup": ["launch", "login"], "boot": ["launch", "login"],
        "fahrenheit": ["temperature", "celsius", "unit"], "celsius": ["temperature", "unit"], "metric": ["unit"],
        "pomodoro": ["focus", "session"], "cpu": ["stats", "monitor"], "ram": ["memory", "stats"],
        "fullscreen": ["full", "screen"], "playing": ["music", "playback"], "song": ["music"], "songs": ["music"],
        "lyric": ["lyrics"], "sound": ["sound", "audio"], "noise": ["sound"], "hidden": ["hide"], "haptics": ["haptic"],
        "popup": ["hud"], "popups": ["hud"], "overlay": ["hud"],
        "unzip": ["extract", "archive"], "zip": ["archive", "extract"], "extract": ["archive"],
        "sleep": ["caffeinate", "awake"], "sleeping": ["caffeinate", "awake"], "awake": ["caffeinate"],
        "kept": ["limit", "history"], "many": ["limit"], "save": ["power"],
        "dynamic": ["notch", "island"], "island": ["notch", "island"], "copy": ["clipboard"], "copied": ["clipboard"],
    ]

    private static let stopWords: Set<String> = [
        "the", "a", "an", "to", "of", "in", "on", "off", "is", "it", "can", "i", "my", "me", "how", "do",
        "does", "and", "or", "for", "when", "with", "turn", "set", "make", "change", "enable", "disable",
        "want", "please", "could", "would", "should", "sapphire", "setting", "settings", "option", "there",
        "what", "which", "where", "some", "any", "suggest", "suggestion", "suggestions", "idea", "ideas",
        "recommend", "tips", "help", "you", "your", "im", "get", "use", "using", "way", "ways"
    ]

    // MARK: - Values

    static func value(of key: String, in settings: Settings) -> Value? {
        guard let dictionary = SettingsPersistence.encodeToDictionary(settings) else { return nil }
        return value(from: dictionary[key])
    }

    private static func value(from raw: Any?) -> Value? {
        if let number = raw as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return .bool(number.boolValue) }
            return .number(number.doubleValue)
        }
        if let text = raw as? String { return .text(text) }
        return nil
    }

    static func applying(key: String, rawValue: String, to settings: Settings) -> Result<(Settings, Change), ChangeError> {
        guard let entry = byKey[key] else { return .failure(.unknownSetting(key)) }
        guard var dictionary = SettingsPersistence.encodeToDictionary(settings),
              let current = value(from: dictionary[key]) else {
            return .failure(.unknownSetting(key))
        }

        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let newValue: Value
        switch current {
        case .bool:
            guard let on = parseBool(trimmed) else { return .failure(.invalidValue(key: key, expected: "on or off")) }
            newValue = .bool(on)
        case .number:
            guard var number = Double(trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "%ptsx "))) else {
                return .failure(.invalidValue(key: key, expected: rangeDescription(entry) ?? "a number"))
            }
            if let range = entry.range { number = min(max(number, range.lowerBound), range.upperBound) }
            newValue = .number(number)
        case .text:
            if let options = entry.options {
                let normalized = trimmed.lowercased().replacingOccurrences(of: " ", with: "")
                guard let match = options.first(where: { $0.lowercased().replacingOccurrences(of: " ", with: "") == normalized }) else {
                    return .failure(.invalidValue(key: key, expected: "one of " + options.joined(separator: ", ")))
                }
                newValue = .text(match)
            } else {
                newValue = .text(trimmed)
            }
        }

        var candidates = [newValue]
        if case .number(let number) = newValue, number.rounded() != number { candidates.append(.number(number.rounded())) }
        for candidate in candidates {
            switch candidate {
            case .bool(let on): dictionary[key] = on
            case .number(let number): dictionary[key] = number
            case .text(let text): dictionary[key] = text
            }
            if var updated = SettingsPersistence.decodeStrictly(dictionary),
               let stored = value(of: key, in: updated), stored == candidate || numericallyEqual(stored, candidate) {
                updated.applyDisplayDefaultToAllDisplays(key)
                return .success((updated, Change(entry: entry, oldValue: current, newValue: stored)))
            }
        }
        return .failure(.invalidValue(key: key, expected: rangeDescription(entry) ?? "a valid value"))
    }

    static func rangeDescription(_ entry: Entry) -> String? {
        if let options = entry.options { return options.joined(separator: " / ") }
        guard let range = entry.range else { return nil }
        return "\(Value.number(range.lowerBound).description)–\(Value.number(range.upperBound).description)"
    }

    private static func numericallyEqual(_ lhs: Value, _ rhs: Value) -> Bool {
        if case .number(let a) = lhs, case .number(let b) = rhs { return abs(a - b) < 0.0001 }
        return false
    }

    private static func parseBool(_ text: String) -> Bool? {
        switch text.lowercased() {
        case "true", "on", "yes", "1", "enable", "enabled", "show", "shown": return true
        case "false", "off", "no", "0", "disable", "disabled", "hide", "hidden": return false
        default: return nil
        }
    }

    static func humanized(_ key: String) -> String {
        var words: [String] = []
        var current = ""
        for character in key {
            if character.isUppercase, !current.isEmpty, !(current.last?.isUppercase ?? false) {
                words.append(current)
                current = ""
            }
            current.append(character)
        }
        if !current.isEmpty { words.append(current) }
        let sentence = words.map { $0.count > 1 && $0 == $0.uppercased() ? $0 : $0.lowercased() }.joined(separator: " ")
        return sentence.prefix(1).uppercased() + sentence.dropFirst()
    }
}