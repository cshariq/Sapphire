//
//  MessagesManager.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-09-26
//

import Foundation
import Combine

@MainActor
class MessagesManager: ObservableObject {
    static let shared = MessagesManager()

    // MARK: - Publishers for UI Updates
    let messagesSubject = PassthroughSubject<[String: Any], Never>()
    let callsSubject = PassthroughSubject<[String: Any], Never>()

    private init() {

    }

    // MARK: - Public API for SwiftUI (Now Disabled)

    func sendMessage(text: String, chatGuid: String) {
        print("[MessagesManager] sendMessage is disabled.")
    }

    func sendReaction(reaction: String, messageGuid: String, chatGuid: String) {
        print("[MessagesManager] sendReaction is disabled.")
    }

    func answerCall(uuid: String) {
        print("[MessagesManager] answerCall is disabled.")
    }

    func hangupCall(uuid: String) {
        print("[MessagesManager] hangupCall is disabled.")
    }
}