//
//  SettingsAssistant.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-26

import Combine
import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

@MainActor
final class SettingsAssistant: ObservableObject {
    struct Message: Identifiable, Equatable {
        enum Role { case user, assistant }

        let id = UUID()
        let role: Role
        var text: String
        var changes: [SettingsIndex.Change] = []
        var suggestions: [SettingsIndex.Entry] = []
        var isError = false
    }

    @Published private(set) var messages: [Message] = []
    @Published private(set) var isResponding = false
    @Published private(set) var undoneChangeIDs: Set<UUID> = []

    private weak var editingSession: SettingsEditingSession?
    private var turnChanges: [SettingsIndex.Change] = []
    private var turnSuggestions: [SettingsIndex.Entry] = []
    private var responseTask: Task<Void, Never>?
    #if canImport(FoundationModels)
    private var storedSession: AnyObject?
    #endif

    nonisolated static var isSupported: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 27, *) { return true }
        #endif
        return false
    }

    var unavailableReason: String? {
        #if canImport(FoundationModels)
        if #available(macOS 27, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return nil
            case .unavailable(.appleIntelligenceNotEnabled):
                return String(localized: "Turn on Apple Intelligence in System Settings to ask about settings.")
            case .unavailable(.modelNotReady):
                return String(localized: "Apple Intelligence is still getting ready. Try again in a little while.")
            case .unavailable(.deviceNotEligible):
                return String(localized: "This Mac doesn't support Apple Intelligence.")
            case .unavailable:
                return String(localized: "Apple Intelligence isn't available right now.")
            }
        }
        #endif
        return String(localized: "The settings assistant needs macOS 27.")
    }

    func attach(_ session: SettingsEditingSession) {
        editingSession = session
    }

    func clearConversation() {
        responseTask?.cancel()
        messages = []
        undoneChangeIDs = []
        isResponding = false
        #if canImport(FoundationModels)
        storedSession = nil
        #endif
    }

    func send(_ text: String) {
        let prompt = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !isResponding else { return }
        messages.append(Message(role: .user, text: prompt))
        guard unavailableReason == nil else {
            messages.append(Message(role: .assistant, text: unavailableReason ?? "", isError: true))
            return
        }
        isResponding = true
        turnChanges = []
        turnSuggestions = []
        responseTask = Task { [weak self] in
            await self?.respond(to: prompt)
        }
    }

    private func respond(to prompt: String) async {
        #if canImport(FoundationModels)
        if #available(macOS 27, *) {
            let grounded = groundedPrompt(prompt)
            var outcome = "Nothing was changed."
            if !Self.isQuestion(prompt), let decision = try? await requestedChange(in: grounded) {
                var value = decision.value
                if let entry = SettingsIndex.byKey[decision.key],
                   case .bool? = SettingsIndex.value(of: entry.key, in: currentSettings),
                   let on = Self.impliedToggle(in: prompt, title: entry.englishTitle) {
                    value = on ? "on" : "off"
                }
                outcome = change(key: decision.key, to: value)
            }
            guard !Task.isCancelled else { return }
            let turn = grounded + "\n\nWhat Sapphire did: " + outcome
            var reply: String
            var failed = false
            do {
                reply = try await languageSession().respond(to: turn).content
            } catch let error as LanguageModelSession.GenerationError {
                if case .exceededContextWindowSize = error {
                    storedSession = nil
                    reply = (try? await languageSession().respond(to: turn).content)
                        ?? String(localized: "That conversation got too long. Ask again and I'll start fresh.")
                } else {
                    reply = error.localizedDescription
                    failed = true
                }
            } catch {
                reply = error.localizedDescription
                failed = true
            }
            guard !Task.isCancelled else { return }
            let changedKeys = Set(turnChanges.map(\.entry.key))
            let suggestions = turnSuggestions.filter { !changedKeys.contains($0.key) }
            messages.append(Message(
                role: .assistant,
                text: reply.trimmingCharacters(in: .whitespacesAndNewlines),
                changes: turnChanges,
                suggestions: Array(suggestions.prefix(4)),
                isError: failed
            ))
            isResponding = false
            return
        }
        #endif
        isResponding = false
    }

    nonisolated static func isQuestion(_ text: String) -> Bool {
        let lowered = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let requests = ["can you ", "could you ", "would you ", "will you ", "please "]
        if requests.contains(where: lowered.hasPrefix) { return false }
        let questions = ["can i ", "could i ", "how ", "is ", "are ", "does ", "do ", "what ", "where ", "which ", "why ", "should ", "am i "]
        return lowered.hasSuffix("?") || lowered.hasSuffix("？") || questions.contains(where: lowered.hasPrefix)
    }

    nonisolated static func impliedToggle(in message: String, title: String) -> Bool? {
        let text = " " + message.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).joined(separator: " ") + " "
        let titled = title.lowercased()
        var on = [" turn on ", " switch on ", " enable ", " activate ", " start "].contains(where: text.contains)
        var off = [" turn off ", " switch off ", " disable ", " deactivate ", " stop "].contains(where: text.contains)
        let hide = text.contains(" hide ")
        let show = text.contains(" show ") || text.contains(" unhide ")
        if titled.hasPrefix("hide") {
            on = on || hide
            off = off || show
        } else if titled.hasPrefix("show") {
            on = on || show
            off = off || hide
        }
        return on == off ? nil : on
    }

    #if canImport(FoundationModels)
    @available(macOS 27, *)
    private func languageSession() -> LanguageModelSession {
        if let session = storedSession as? LanguageModelSession { return session }
        let session = LanguageModelSession(
            tools: [FindSettingsTool(assistant: self)],
            instructions: Self.instructions
        )
        storedSession = session
        return session
    }

    @available(macOS 27, *)
    private func requestedChange(in grounded: String) async throws -> (key: String, value: String)? {
        let session = LanguageModelSession(instructions: Self.decisionInstructions)
        let decision = try await session.respond(to: grounded, generating: ChangeDecision.self).content
        guard decision.kind == .change, !decision.key.isEmpty else { return nil }
        return (decision.key, decision.value)
    }

    private static let decisionInstructions = """
    You decide whether a message to the Sapphire settings assistant is an instruction to change a \
    setting, and which one. Questions never change anything. Only use keys from the listed settings. \
    For a setting whose title starts with Hide, on means hidden.
    """

    private static let instructions = """
    You are the settings assistant inside Sapphire, a Mac app that adds a Dynamic Island style notch, \
    live activities, widgets, a music player and system utilities.
    Answer questions about what Sapphire can do and how to adjust it. Each question comes with the \
    settings that matched it. Answer from those. If none of them fit, call findSettings with other \
    words, such as the feature's name or the pane it would be in, before saying Sapphire can't do it. \
    Never invent settings or panes.
    Sapphire's settings panes:
    \(paneCatalog)
    Each message ends with what Sapphire did. Report changes and failures truthfully, and never say \
    you changed something that wasn't changed. When they ask whether something is possible or want \
    ideas, describe the matching settings and where they are; Sapphire only changes settings when told to.
    When asked for suggestions, look up a few relevant settings and recommend specific values with a \
    one-line reason each.
    Keep answers short: two to four sentences. Mention the pane a setting is in. When a setting does \
    what they asked, say yes and name it; don't hedge. Say plainly when no setting does what they want.
    """

    #endif

    static let paneCatalog = SettingsSection.allCases
        .filter { $0 != .overview && $0 != .about }
        .map { "- \($0.englishLabel): \($0.englishShortDescription)" }
        .joined(separator: "\n")

    private func groundedPrompt(_ prompt: String) -> String {
        var query = prompt
        if SettingsIndex.search(prompt, limit: 1).isEmpty,
           let previous = messages.dropLast().last(where: { $0.role == .user }) {
            query = previous.text + " " + prompt
        }
        return """
        \(prompt)

        Settings that matched this message:
        \(find(query, limit: 8))
        """
    }

    // MARK: - Tool actions

    func find(_ query: String, limit: Int = 6) -> String {
        let matches = SettingsIndex.search(query, limit: limit)
        guard !matches.isEmpty else {
            return "No settings match \"\(query)\". Try other words."
        }
        let settings = currentSettings
        for entry in matches where !turnSuggestions.contains(entry) {
            turnSuggestions.append(entry)
        }
        let lockedSections = Set(matches.compactMap(\.section).filter(\.isPremiumLocked))
        return Self.formatMatches(matches, settings: settings, lockedSections: lockedSections)
    }

    static func formatMatches(
        _ matches: [SettingsIndex.Entry],
        settings: Settings,
        lockedSections: Set<SettingsSection>
    ) -> String {
        return matches.map { entry in
            var line = "key=\(entry.key) | \"\(entry.englishTitle)\""
            if let section = entry.section { line += " | pane: \(section.englishLabel)" }
            if let value = SettingsIndex.value(of: entry.key, in: settings) { line += " | now: \(value.description)" }
            if let allowed = SettingsIndex.rangeDescription(entry) {
                line += " | allowed: \(allowed)"
            } else if case .bool? = SettingsIndex.value(of: entry.key, in: settings) {
                line += " | allowed: on / off"
            }
            if let section = entry.section, lockedSections.contains(section) {
                line += " | needs a Sapphire subscription"
            }
            if let detail = entry.detail { line += " | " + String(detail.prefix(110)) }
            return line
        }.joined(separator: "\n")
    }

    func change(key: String, to rawValue: String) -> String {
        let current = currentSettings
        switch SettingsIndex.applying(key: key, rawValue: rawValue, to: current) {
        case .failure(let error):
            return "Not changed: \(error.description)"
        case .success(let (updated, change)):
            if change.oldValue == change.newValue {
                return "\"\(change.entry.englishTitle)\" was already \(change.newValue.description); nothing changed."
            }
            commit(updated)
            turnChanges.append(change)
            return "Changed \"\(change.entry.englishTitle)\" from \(change.oldValue.description) to \(change.newValue.description)."
        }
    }

    func undo(_ change: SettingsIndex.Change) {
        let current = currentSettings
        guard case .success(let (updated, _)) = SettingsIndex.applying(
            key: change.entry.key,
            rawValue: change.oldValue.description,
            to: current
        ) else { return }
        commit(updated)
        undoneChangeIDs.insert(change.id)
    }

    private var currentSettings: Settings {
        editingSession?.settings.value ?? SettingsModel.shared.settings
    }

    private func commit(_ settings: Settings) {
        if let editingSession {
            editingSession.settings.value = settings
        } else {
            SettingsModel.shared.settings = settings
        }
    }
}

#if canImport(FoundationModels)
@available(macOS 27, *)
private struct FindSettingsTool: Tool {
    let name = "findSettings"
    let description = "Searches Sapphire's settings by keywords and returns matching settings with their key, title, pane, current value and allowed values."

    @Generable
    struct Arguments {
        @Guide(description: "A few keywords describing the setting, like \"hide notch full screen\" or \"music waveform bars\".")
        var query: String
    }

    let assistant: SettingsAssistant

    func call(arguments: Arguments) async throws -> String {
        await assistant.find(arguments.query)
    }
}

@available(macOS 27, *)
@Generable
private enum RequestKind {
    case change, question
}

@available(macOS 27, *)
@Generable
private struct ChangeDecision {
    @Guide(description: "change only for an instruction such as \"turn off X\", \"enable X\", \"set X to 5\" or \"hide X\". question for anything asked as a question (\"can I…?\", \"how do I…?\", \"is there…?\") or a request for ideas.")
    var kind: RequestKind
    @Guide(description: "For a change: the exact key of the listed setting to change. Otherwise empty.")
    var key: String
    @Guide(description: "For a change: the new value from that setting's allowed values. on when they say turn on, enable, show or start; off when they say turn off, disable, stop or remove. A number or an option name for other settings. Otherwise empty.")
    var value: String
}
#endif
