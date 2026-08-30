#if !SAPPHIRE_FULL_BUILD
import Foundation
import SwiftUI

enum MonitorType: String, Codable, CaseIterable {
    case screen, audio, location, calendar, contacts

    var displayName: String { rawValue.capitalized }
    var icon: String { "circle.dashed" }
}

struct DataSummary {
    var totalDataPoints: Int = 0
    var countsByMonitorType: [String: Int] = [:]
    var oldestEntry: Date?
    var newestEntry: Date?
    var databaseSizeMB: Double = 0
}

final class MemorySystemManager {
    static let shared = MemorySystemManager()
    private init() {}

    func getDataSummary() throws -> DataSummary { DataSummary() }
}

struct IntelligenceSettingsView: View {
    var body: some View {
        Text("Intelligence features are not included in this build.")
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
#endif
