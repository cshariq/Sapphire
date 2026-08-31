//
//  IntelligenceNotchViewModel.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-30

#if !SAPPHIRE_FULL_BUILD
import Foundation
import Combine

final class IntelligenceNotchViewModel: ObservableObject {
    struct LogEntry: Identifiable {
        let id = UUID()
        var text: String
        var isError: Bool
        var isSubtask: Bool
    }

    @Published var taskInput = ""
    @Published var isRunning = false
    @Published var statusMessage = "Ready"
    @Published var subtaskProgress: (current: Int, total: Int) = (0, 0)
    @Published var currentActionLabel = ""
    @Published var currentStepTitle = ""
    @Published var displayStepIndex = 0
    @Published var displayStepTotal = 0
    @Published var logEntries: [LogEntry] = []
    struct RunResult {
        var success = false
        var subtasksCompleted = 0
        var subtasksTotal = 0
        var actionsTaken = 0
        var duration = 0.0
    }

    @Published var lastResult: RunResult?

    func run(apiKey: String, backend: LLMBackend, geminiSpeedMode: GeminiSpeedMode) {}
    func stop() {}
}
#endif