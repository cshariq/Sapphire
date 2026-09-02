//
//  ClaudeChatSession.swift
//  Sapphire
//
//  Conversation state for the in-notch Claude chat panel.
//

import Foundation

@MainActor
final class ClaudeChatSession: ObservableObject {
    @Published private(set) var messages: [ClaudeChatMessage] = []
    @Published private(set) var isSending = false
    @Published var errorMessage: String?

    private var streamTask: Task<Void, Never>?

    func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isSending else { return }

        errorMessage = nil
        let userMessage = ClaudeChatMessage(role: .user, content: trimmed)
        messages.append(userMessage)

        let assistantMessageID = UUID()
        messages.append(ClaudeChatMessage(id: assistantMessageID, role: .assistant, content: ""))

        isSending = true
        let historySnapshot = messages
        streamTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await ClaudeAPI.shared.streamReply(for: historySnapshot) { [weak self] delta in
                    self?.appendDelta(delta, toMessageID: assistantMessageID)
                }
            } catch {
                self.errorMessage = error.localizedDescription
                self.removeMessageIfEmpty(assistantMessageID)
            }
            self.isSending = false
        }
    }

    func cancel() {
        streamTask?.cancel()
        streamTask = nil
        isSending = false
    }

    func clear() {
        cancel()
        messages.removeAll()
        errorMessage = nil
    }

    private func appendDelta(_ delta: String, toMessageID id: UUID) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index].content += delta
    }

    private func removeMessageIfEmpty(_ id: UUID) {
        guard let index = messages.firstIndex(where: { $0.id == id }), messages[index].content.isEmpty else { return }
        messages.remove(at: index)
    }
}
