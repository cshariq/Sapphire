//
//  TextSnippetManager.swift
//  Sapphire
//
//  BETA: user-defined reusable text snippets ("signatures", addresses, canned
//  replies, etc.) that can be quick-copied from the Clipboard widget.
//

import AppKit

struct TextSnippet: Identifiable, Codable, Equatable, Hashable {
    var id: UUID = UUID()
    var name: String
    var content: String
}

/// Stateless facade over SettingsModel.shared.settings.textSnippets. Not an
/// ObservableObject itself — it holds no storage of its own, so views should
/// observe SettingsModel (already the norm throughout Settings-bound views)
/// and call these methods for mutations, which write through to that
/// @Published settings struct and trigger the same reactivity.
@MainActor
final class TextSnippetManager {
    static let shared = TextSnippetManager()

    var snippets: [TextSnippet] {
        get { SettingsModel.shared.settings.textSnippets }
        set { SettingsModel.shared.settings.textSnippets = newValue }
    }

    private init() {}

    @discardableResult
    func addSnippet(name: String, content: String) -> TextSnippet {
        let snippet = TextSnippet(name: name, content: content)
        snippets.append(snippet)
        return snippet
    }

    func updateSnippet(_ snippet: TextSnippet) {
        guard let index = snippets.firstIndex(where: { $0.id == snippet.id }) else { return }
        snippets[index] = snippet
    }

    func deleteSnippet(id: UUID) {
        snippets.removeAll { $0.id == id }
    }

    func copySnippet(_ snippet: TextSnippet) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(snippet.content, forType: .string)
    }
}
