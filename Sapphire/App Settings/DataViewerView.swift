//
//  DataViewerView.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-06.
//

import SwiftUI

struct DataViewerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var summary: DataSummary?
    @State private var isLoading = true
    @State private var errorMessage: String?

    private let memoryManager = MemorySystemManager.shared

    var body: some View {
        NavigationView {
            Group {
                if isLoading {
                    loadingView
                } else if let error = errorMessage {
                    errorView(error)
                } else if let summary = summary {
                    summaryView(summary)
                } else {
                    emptyView
                }
            }
            .navigationTitle("Collected Data")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button {
                        loadData()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(isLoading)
                }
            }
        }
        .frame(minWidth: 600, minHeight: 500)
        .onAppear {
            loadData()
        }
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Loading data summary...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Error View

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.orange)

            Text("Failed to Load Data")
                .font(.title2.bold())

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)

            Button("Try Again") {
                loadData()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Empty View

    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "tray")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("No Data Collected Yet")
                .font(.title2.bold())

            Text("Enable monitoring to start collecting profiling data")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Summary View

    private func summaryView(_ summary: DataSummary) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                overviewSection(summary)

                if !summary.countsByMonitorType.isEmpty {
                    byMonitorTypeSection(summary)
                }

                if summary.oldestEntry != nil || summary.newestEntry != nil {
                    dateRangeSection(summary)
                }

                storageSection(summary)
            }
            .padding()
        }
    }

    private func overviewSection(_ summary: DataSummary) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Overview")
                .font(.headline)

            HStack(spacing: 20) {
                StatCard(
                    icon: "chart.bar.fill",
                    title: "Total Data Points",
                    value: "\(summary.totalDataPoints)",
                    color: .blue
                )

                StatCard(
                    icon: "externaldrive.fill",
                    title: "Database Size",
                    value: String(format: "%.2f MB", summary.databaseSizeMB),
                    color: .purple
                )

                StatCard(
                    icon: "checkmark.circle.fill",
                    title: "Active Monitors",
                    value: "\(summary.countsByMonitorType.count)",
                    color: .green
                )
            }
        }
        .modifier(SettingsContainerModifier())
    }

    private func byMonitorTypeSection(_ summary: DataSummary) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Data Points by Monitor Type")
                .font(.headline)

            LazyVStack(spacing: 12) {
                ForEach(summary.countsByMonitorType.sorted(by: { $0.value > $1.value }), id: \.key) { type, count in
                    if let monitorType = MonitorType(rawValue: type) {
                        MonitorTypeDataRow(monitorType: monitorType, count: count, total: summary.totalDataPoints)
                    }
                }
            }
        }
        .modifier(SettingsContainerModifier())
    }

    private func dateRangeSection(_ summary: DataSummary) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Data Range")
                .font(.headline)

            VStack(spacing: 12) {
                if let oldest = summary.oldestEntry {
                    DataRangeRow(
                        icon: "calendar.badge.clock",
                        title: "Oldest Entry",
                        date: oldest
                    )
                }

                if let newest = summary.newestEntry {
                    DataRangeRow(
                        icon: "calendar.badge.checkmark",
                        title: "Newest Entry",
                        date: newest
                    )
                }

                if let oldest = summary.oldestEntry, let newest = summary.newestEntry {
                    let days = Calendar.current.dateComponents([.day], from: oldest, to: newest).day ?? 0
                    HStack {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .foregroundStyle(.blue)
                        Text("Span:")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("\(days) days")
                            .font(.subheadline.weight(.medium))
                        Spacer()
                    }
                    .padding()
                    .background(Color.blue.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .modifier(SettingsContainerModifier())
    }

    private func storageSection(_ summary: DataSummary) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Storage Details")
                .font(.headline)

            VStack(spacing: 12) {
                HStack {
                    Image(systemName: "lock.shield.fill")
                        .foregroundStyle(.purple)
                    Text("All data is AES-256 encrypted")
                        .font(.subheadline)
                    Spacer()
                }
                .padding()
                .background(Color.purple.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 8))

                HStack {
                    Image(systemName: "externaldrive.badge.checkmark")
                        .foregroundStyle(.green)
                    Text("Stored locally on your device")
                        .font(.subheadline)
                    Spacer()
                }
                .padding()
                .background(Color.green.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .modifier(SettingsContainerModifier())
    }

    // MARK: - Actions

    private func loadData() {
        isLoading = true
        errorMessage = nil

        Task.detached(priority: .userInitiated) {
            do {
                let loadedSummary = try await PerformanceMonitor.shared.measureAsync("DataViewer.loadData") {
                    try MemorySystemManager.shared.getDataSummary()
                }

                await MainActor.run {
                    self.summary = loadedSummary
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }
}

// MARK: - Supporting Views

struct StatCard: View {
    let icon: String
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title)
                .foregroundStyle(color)

            Text(value)
                .font(.title2.bold())

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct MonitorTypeDataRow: View {
    let monitorType: MonitorType
    let count: Int
    let total: Int

    private var percentage: Double {
        guard total > 0 else { return 0 }
        return Double(count) / Double(total) * 100
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: monitorType.icon)
                    .foregroundStyle(.blue)

                Text(monitorType.displayName)
                    .font(.subheadline)

                Spacer()

                Text("\(count) points")
                    .font(.subheadline.weight(.medium))

                Text("(\(String(format: "%.1f", percentage))%)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))

                    Rectangle()
                        .fill(Color.blue)
                        .frame(width: geometry.size.width * (percentage / 100))
                }
            }
            .frame(height: 6)
            .clipShape(Capsule())
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct DataRangeRow: View {
    let icon: String
    let title: String
    let date: Date

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(.blue)
            Text(title + ":")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(formattedDate)
                .font(.subheadline.weight(.medium))
            Spacer()
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Preview

struct DataViewerView_Previews: PreviewProvider {
    static var previews: some View {
        DataViewerView()
    }
}