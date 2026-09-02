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
    @ObservedObject private var statsManager = StatsManager.shared

    // MARK: - System Power hero (mirrors the hero card in BatteryDetailView)

    private static func finite(_ v: Double) -> Double {
        guard v.isFinite else { return 0 }
        return max(0, v)
    }
    private var systemLoad: Double { Self.finite(stats.systemPower) }
    private var adapterPower: Double {
        Self.finite(statsManager.currentStats?.sensors?.sensors.first { ["PDTR"].contains($0.key) }?.value ?? 0)
    }
    private var adapterConnected: Bool { (stats.powerAdapterInfo?.maxPower ?? 0) > 0 }
    private var heroWatts: Double { adapterConnected ? max(adapterPower, systemLoad) : systemLoad }
    private var wattsText: String {
        heroWatts > 0 ? String(format: "%.2f", heroWatts) : "--"
    }
    private var powerStatusLabel: String {
        if stats.isCharging { return "Charging" }
        if adapterConnected { return "On AC Power" }
        return "On Battery"
    }
    private var powerStatusColor: Color {
        if stats.isCharging { return MaterialChartPalette.tertiary }
        if adapterConnected { return MaterialChartPalette.primary }
        return MaterialChartPalette.warning
    }

    private var temperatureText: String {
        stats.temperature > 0 ? String(format: "%.1f°", stats.temperature) : "--"
    }

    var body: some View {
        Button {
            Task {
                try? await Task.sleep(for: .seconds(NotchConfiguration.primaryWidgetSwitchDelay))
                navigationStack.wrappedValue.append(NotchWidgetMode.batteryDetailView)
            }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                header
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text(wattsText)
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .animation(.easeInOut(duration: 0.3), value: wattsText)
                    if heroWatts > 0 {
                        Text("W")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundColor(.white.opacity(0.7))
                    }
                    Spacer(minLength: 0)
                    Image(systemName: adapterConnected ? "powerplug.fill" : "battery.100")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(powerStatusColor.opacity(0.85))
                }
                powerBar
                HStack(spacing: 8) {
                    metaChip(icon: "thermometer.medium", text: temperatureText, color: .orange)
                    metaChip(icon: "heart.fill", text: "\(stats.maxCapacityPercentage)%", color: .pink)
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
            statsManager.setPolling(for: "BatteryWidget", requiredStats: [.systemPower, .batteryPower])
        }
        .onDisappear {
            stats.stop()
            statsManager.setPolling(for: "BatteryWidget", requiredStats: [])
        }
    }

    // MARK: - Sections

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("System Power")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.72))
            Spacer()
            HStack(spacing: 4) {
                Circle()
                    .fill(powerStatusColor)
                    .frame(width: 5, height: 5)
                Text(powerStatusLabel)
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundColor(powerStatusColor)
            }
        }
    }

    private var powerBar: some View {
        GeometryReader { geo in
            let adapter = adapterPower > 0 ? adapterPower : heroWatts
            let total = max(adapter + systemLoad, 0.001)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.10))
                HStack(spacing: 0) {
                    if adapterConnected {
                        Capsule()
                            .fill(MaterialChartPalette.primary)
                            .frame(width: max(3, geo.size.width * CGFloat(adapter / total)))
                    }
                    Capsule()
                        .fill(MaterialChartPalette.warning)
                        .frame(width: max(3, geo.size.width * CGFloat(systemLoad / total)))
                }
            }
        }
        .frame(height: 5)
    }

    private func metaChip(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(color)
            Text(text)
                .font(.system(size: 9.5, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.92))
                .monospacedDigit()
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .frame(height: 20)
        .background(Color.white.opacity(0.08), in: Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
    }
}