//
//  BatteryWidgetView.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-01

import SwiftUI

struct BatteryWidgetView: View {
    @EnvironmentObject private var settings: SettingsModel
    @Environment(\.navigationStack) private var navigationStack
    @StateObject private var stats = BatteryStatsViewModel()
    @State private var statsPollingRequester = "BatteryWidget-\(UUID().uuidString)"

    // MARK: - System Power hero (mirrors the hero card in BatteryDetailView)

    private var power: SystemPowerReading {
        SystemPowerReading(
            systemLoad: stats.systemPower,
            adapterPower: stats.adapterPower,
            adapterConnected: (stats.powerAdapterInfo?.maxPower ?? 0) > 0,
            isCharging: stats.isCharging
        )
    }

    private var temperatureText: String {
        stats.temperature > 0 ? String(format: "%.1f°", stats.temperature) : "--"
    }

    var body: some View {
        let power = self.power
        let wattsText = power.heroWatts > 0 ? String(format: "%.2f", power.heroWatts) : "--"

        Button {
            Task {
                try? await Task.sleep(for: .seconds(NotchConfiguration.primaryWidgetSwitchDelay))
                navigationStack.wrappedValue.append(NotchWidgetMode.batteryDetailView)
            }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                MaterialMetricHeader(
                    title: "System Power",
                    status: power.statusLabel,
                    color: power.statusColor
                )
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text(wattsText)
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .animation(.easeInOut(duration: 0.3), value: wattsText)
                    if power.heroWatts > 0 {
                        Text("W")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundColor(.white.opacity(0.7))
                    }
                    Spacer(minLength: 0)
                    Image(systemName: power.adapterConnected ? "powerplug.fill" : "battery.100")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(power.statusColor.opacity(0.85))
                }
                PowerSplitBar(reading: power)
                    .frame(height: 5)
                HStack(spacing: 8) {
                    MaterialMetricChip(icon: "thermometer.medium", text: temperatureText, color: .orange)
                    MaterialMetricChip(icon: "heart.fill", text: "\(stats.maxCapacityPercentage)%", color: .pink)
                }
                .padding(.top, 5)
            }

        }
        .buttonStyle(.plain)
        .frame(minWidth: 210, minHeight: 90)
        .fixedSize()
        .foregroundColor(.white)
        .preferredColorScheme(.dark)
        .contentShape(Rectangle())
        .help("Click for the full battery & power overview")
        .onAppear {
            stats.start()
            StatsManager.shared.setPolling(for: statsPollingRequester, requiredStats: [.systemPower, .batteryPower])
        }
        .onDisappear {
            stats.stop()
            StatsManager.shared.setPolling(for: statsPollingRequester, requiredStats: [])
        }
    }
}