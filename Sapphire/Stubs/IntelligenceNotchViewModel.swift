#if !SAPPHIRE_FULL_BUILD
import Foundation
import Combine

final class IntelligenceNotchViewModel: ObservableObject {
    @Published var taskInput = ""
    @Published var isRunning = false
    @Published var statusMessage = "Ready"
    @Published var subtaskProgress: (current: Int, total: Int) = (0, 0)
    @Published var currentActionLabel = ""
    @Published var currentStepTitle = ""
    @Published var displayStepIndex = 0
    @Published var displayStepTotal = 0
    @Published var lastResult: IntelligenceAgentResult?
    @Published var logEntries: [IntelligenceLogEntry] = []

    func run(apiKey: String, backend: LLMBackend, geminiSpeedMode: GeminiSpeedMode) {
        guard !isRunning else { return }
        isRunning = true
        statusMessage = "Unavailable"
        currentActionLabel = "Intelligence is stubbed in this build"
        currentStepTitle = "Stubbed"
        displayStepIndex = 0
        displayStepTotal = 0
        subtaskProgress = (0, 0)
        logEntries.append(.init(
            text: "Blip/Intelligence is stubbed — no agent run executed (backend: \(backend.rawValue), speed: \(geminiSpeedMode.rawValue), key: \(apiKey.isEmpty ? "missing" : "present")).",
            isError: true,
            isSubtask: false
        ))
        lastResult = IntelligenceAgentResult(
            success: false,
            subtasksCompleted: 0,
            subtasksTotal: 0,
            actionsTaken: 0,
            duration: 0
        )
        isRunning = false
        statusMessage = "Ready"
        currentActionLabel = ""
        currentStepTitle = ""
    }

    func stop() {
        isRunning = false
        statusMessage = "Stopped"
        currentActionLabel = ""
        currentStepTitle = ""
        displayStepIndex = 0
        displayStepTotal = 0
        subtaskProgress = (0, 0)
    }
}
#endif
