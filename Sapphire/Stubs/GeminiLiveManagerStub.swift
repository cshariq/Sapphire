//
//  GeminiLiveManagerStub.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-15

#if !SAPPHIRE_FULL_BUILD
import Combine
import Foundation
import ScreenCaptureKit
import SwiftUI

struct GeminiActiveActivityView {
    static func left() -> some View {
        Image(systemName: "sparkle")
    }

    static func right(isMuted: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: isMuted ? "mic.slash.fill" : "mic.fill")
        }
        .buttonStyle(.plain)
    }
}

@MainActor
final class GeminiLiveManager: NSObject, ObservableObject {
    @Published var isSessionRunning = false
    @Published var isMicMuted = true
    @Published var currentAudioLevel: Float = 0
    @Published var inputTranscript = ""
    @Published var outputTranscript = ""
    @Published var lastError: String?

    let sessionDidEndPublisher = PassthroughSubject<Void, Never>()

    func startSession(with filter: SCContentFilter) {
        _ = filter
        lastError = premiumDefaultMessage(for: .geminiLive)
    }

    func toggleMicrophone() {}

    func stopSession() {
        isSessionRunning = false
        isMicMuted = true
        sessionDidEndPublisher.send()
    }
}
#endif