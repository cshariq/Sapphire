#if !SAPPHIRE_FULL_BUILD
import Foundation
import Combine

final class IntelligenceNotchViewModel: ObservableObject {
    @Published var taskInput = ""
    @Published var isRunning = false
    @Published var statusMessage = "Ready"
    @Published var subtaskProgress: (current: Int, total: Int) = (0, 0)
    @Published var currentActionLabel = ""
}
#endif
