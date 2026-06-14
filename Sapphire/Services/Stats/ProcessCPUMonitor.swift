import Foundation
import QuartzCore

@MainActor
final class ProcessCPUMonitor: ObservableObject {
    static let shared = ProcessCPUMonitor()

    struct OperationStats: Identifiable {
        let name: String
        var callCount: Int = 0
        var totalTime: TimeInterval = 0
        var minTime: TimeInterval = .infinity
        var maxTime: TimeInterval = 0
        var averageTime: TimeInterval { callCount > 0 ? totalTime / Double(callCount) : 0 }
        var id: String { name }
    }

    @Published private(set) var operations: [String: OperationStats] = [:]
    @Published private(set) var isEnabled = false

    private let queue = DispatchQueue(label: "com.sapphire.perfmon", qos: .utility)

    func enable() { isEnabled = true }
    func disable() { isEnabled = false }
    func toggle() { isEnabled.toggle() }

    func record(_ name: String, duration: TimeInterval) {
        guard isEnabled else { return }
        queue.sync {
            var stats = operations[name] ?? OperationStats(name: name)
            stats.callCount += 1
            stats.totalTime += duration
            stats.minTime = min(stats.minTime, duration)
            stats.maxTime = max(stats.maxTime, duration)
            operations[name] = stats
        }
    }

    func topConsumers(limit: Int = 10) -> [OperationStats] {
        queue.sync {
            operations.values
                .sorted { $0.totalTime > $1.totalTime }
                .prefix(limit)
                .map { $0 }
        }
    }

    var formattedReport: String {
        let top = topConsumers(limit: 15)
        guard !top.isEmpty else { return "Performance monitor is disabled or no data collected." }
        var report = "=== Top CPU Consumers (by total time) ===\n"
        report += String(format: "%-30s %8s %10s %10s %10s\n", "Operation", "Calls", "Total (s)", "Avg (ms)", "Max (ms)")
        for stat in top {
            report += String(format: "%-30s %8d %10.3f %10.2f %10.2f\n",
                             stat.name.prefix(30) as CVarArg, stat.callCount, stat.totalTime,
                stat.averageTime * 1000, stat.maxTime * 1000)
        }
        return report
    }

    private var reportingTimer: Timer?

    func startPeriodicReporting(interval: TimeInterval = 60) {
        stopPeriodicReporting()
        enable()
        reportingTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self else { return }
            print(self.formattedReport)
            self.reset()
        }
    }

    func stopPeriodicReporting() {
        reportingTimer?.invalidate()
        reportingTimer = nil
    }

    func reset() {
        queue.sync { operations.removeAll() }
    }
}

@MainActor func trace<T>(_ name: String, operation: () throws -> T) rethrows -> T {
    let start = CACurrentMediaTime()
    defer {
        let duration = CACurrentMediaTime() - start
        ProcessCPUMonitor.shared.record(name, duration: duration)
    }
    return try operation()
}

@MainActor func traceAsync<T>(_ name: String, operation: () async throws -> T) async rethrows -> T {
    let start = CACurrentMediaTime()
    defer {
        let duration = CACurrentMediaTime() - start
        ProcessCPUMonitor.shared.record(name, duration: duration)
    }
    return try await operation()
}
