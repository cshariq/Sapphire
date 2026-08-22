//
//  BatteryDebugMenu.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-20.
//

import SwiftUI
import ServiceManagement

@MainActor
struct BatteryDebugMenu: View {
    @ObservedObject private var helperManager = HelperManager.shared
    @ObservedObject private var debugMode = DebugMode.shared
    @ObservedObject private var batteryStatus = BatteryStatusManager.shared
    @ObservedObject private var powerModeManager = PowerModeManager.shared
    @ObservedObject private var fanManager = FanManager.shared

    @State private var log: [String] = []
    @State private var protocolVersion: Int?
    @State private var chargeControlMode: ChargeControlMode?
    @State private var batteryTemp: Double?
    @State private var hardwarePercent: Int?
    @State private var adapter: PowerAdapterInfo?
    @State private var smcKeys: [String] = []
    @State private var fanCount: Int?
    @State private var limitInput = 80
    @State private var isBusy = false

    private var battery: BatteryState? { BatteryMonitor.shared.currentState }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            helperCard
            batteryStateCard
            chargingTestCard
            onDemandDataCard
            logCard
        }
        .padding(.bottom, 8)
        .task { await refreshEverything() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "hammer.fill")
                .foregroundStyle(.orange)
            Text("Debug Menu")
                .font(.title3.bold())
            Spacer()
            Button("Refresh All") {
                Task { await refreshEverything() }
            }
            .buttonStyle(.bordered)
            Button(debugMode.isEnabled ? "Disable Debug Mode" : "Enable Debug Mode") {
                debugMode.isEnabled.toggle()
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
        }
        .padding(.top, 8)
    }

    // MARK: - Helper

    private var helperCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Helper", systemImage: "gearshape.2.fill", color: .blue)

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                gridRow("SMAppService status", helperManager.status.description)
                gridRow("Running", helperManager.isRunning ? "Yes" : "No")
                gridRow("Issue", helperManager.lastIssue?.code ?? "None")
                gridRow("Protocol version", protocolVersion.map(String.init) ?? "—")
                gridRow("Charge-control mode", chargeControlMode.map { String(describing: $0) } ?? "—")
            }
            .font(.caption.monospaced())

            HStack(spacing: 8) {
                Button("Refresh Status") {
                    helperManager.updateStatus()
                    helperManager.checkIfRunning()
                }
                Button("Ping") {
                    Task { await pingHelper() }
                }
                Button("Install / Activate") {
                    helperManager.beginInstallation()
                }
                Button("Reinstall") {
                    helperManager.reactivateHelper()
                }
                Button("Reset Background Activity") {
                    helperManager.resetOwnBackgroundActivity()
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .debugCard()
    }

    // MARK: - Battery state

    private var batteryStateCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Battery State", systemImage: "battery.100percent", color: .green)

            let state = battery
            let management = batteryStatus.currentState.managementState.rawValue
            let derived = derivedBatteryState

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                gridRow("Level", state.map { "\($0.level)%" } ?? "—")
                gridRow("Charging", state.map { $0.isCharging ? "Yes" : "No" } ?? "—")
                gridRow("Plugged in", state.map { $0.isPluggedIn ? "Yes" : "No" } ?? "—")
                gridRow("Management state", management)
                gridRow("Derived state", derived)
                gridRow("LED color", "\(batteryStatus.currentState.ledColor)")
                gridRow("Sleeping", batteryStatus.currentState.isSleeping ? "Yes" : "No")
                gridRow("Low power mode", powerModeManager.isLowPowerModeActive ? "On" : "Off")
                gridRow("Temperature", batteryTemp.map { String(format: "%.1f °C", $0) } ?? "—")
                gridRow("Hardware %", hardwarePercent.map(String.init) ?? "—")
            }
            .font(.caption.monospaced())

            if let adapter {
                Text("Adapter: \(adapter.name) · \(adapter.power)W · \(adapter.voltage)mV · \(adapter.current)mA")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
        .debugCard()
    }

    private var derivedBatteryState: String {
        guard let state = battery else { return "Unknown" }
        let management = batteryStatus.currentState.managementState
        switch management {
        case .inhibited, .sailing, .heatProtection, .discharging, .calibrating:
            return management.rawValue
        default:
            if state.isCharging { return "Charging" }
            if state.isPluggedIn { return "Plugged in (not charging)" }
            return "On battery"
        }
    }

    // MARK: - Charging tests

    private var chargingTestCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Charging Controls", systemImage: "bolt.fill", color: .yellow)

            HStack(spacing: 8) {
                Button("Pause Charging") {
                    Task { await pauseCharging() }
                }
                Button("Resume Charging") {
                    BatteryManager.shared.enableCharging(true)
                    BatteryManager.shared.setChargeLimit(100)
                    appendLog("enableCharging(true) + setChargeLimit(100)")
                }
                Button("Start Discharge") {
                    BatteryManager.shared.setDischarge(discharging: true)
                    appendLog("setDischarge(true)")
                }
                Button("Stop Discharge") {
                    BatteryManager.shared.setDischarge(discharging: false)
                    appendLog("setDischarge(false)")
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            HStack(spacing: 8) {
                Text("Limit:")
                TextField("80", value: $limitInput, formatter: NumberFormatter())
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 60)
                Button("Set Charge Limit") {
                    BatteryManager.shared.setChargeLimit(limitInput)
                    appendLog("setChargeLimit(\(limitInput))")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            HStack(spacing: 8) {
                Button("MagSafe Green") {
                    BatteryManager.shared.setMagSafeLED(color: 3)
                    appendLog("setMagSafeLED(green)")
                }
                Button("MagSafe Amber") {
                    BatteryManager.shared.setMagSafeLED(color: 4)
                    appendLog("setMagSafeLED(amber)")
                }
                Button("MagSafe Off") {
                    BatteryManager.shared.setMagSafeLED(color: 1)
                    appendLog("setMagSafeLED(off)")
                }
                Button(powerModeManager.isLowPowerModeActive ? "Low Power: Off" : "Low Power: On") {
                    if powerModeManager.isLowPowerModeActive {
                        powerModeManager.disableLowPowerMode()
                    } else {
                        powerModeManager.enableLowPowerMode()
                    }
                    appendLog("toggled low power mode")
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .debugCard()
    }

    // MARK: - On-demand data

    private var onDemandDataCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("On-Demand Data", systemImage: "list.bullet.rectangle", color: .purple)

            HStack(spacing: 8) {
                Button("Load SMC Keys") {
                    Task { await loadSMCKeys() }
                }
                Button("Load Fans") {
                    Task { await loadFanInfo() }
                }
                Button("Load Adapter") {
                    Task { await loadAdapter() }
                }
                Button("Load Temperature") {
                    Task { await loadTemperature() }
                }
                Button("Load Hardware %") {
                    Task { await loadHardwarePercent() }
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            if !smcKeys.isEmpty {
                Text("SMC keys (\(smcKeys.count)): \(smcKeys.joined(separator: ", "))")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            if let fanCount {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Fan count: \(fanCount)")
                    ForEach(fanManager.fans, id: \.id) { fan in
                        Text("Fan \(fan.id) · \(fan.name) · \(fan.currentRPM) RPM · min \(fan.minRPM) · max \(fan.maxRPM)")
                    }
                }
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
            }
        }
        .debugCard()
    }

    // MARK: - Log

    private var logCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Action Log", systemImage: "terminal.fill", color: .gray)
            if log.isEmpty {
                Text("No actions yet.")
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
            } else {
                Text(log.joined(separator: "\n"))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button("Clear Log") { log.removeAll() }
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .debugCard()
    }

    // MARK: - Helpers

    private func sectionTitle(_ title: String, systemImage: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage).foregroundStyle(color)
            Text(title).font(.headline)
        }
    }

    private func gridRow(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value).textSelection(.enabled)
        }
    }

    private func appendLog(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        log.append("[\(formatter.string(from: Date()))] \(message)")
        if log.count > 200 { log.removeFirst(log.count - 200) }
    }

    // MARK: - Actions

    private func refreshEverything() async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }

        helperManager.updateStatus()
        helperManager.checkIfRunning()
        await pingHelper()
        await loadTemperature()
        await loadHardwarePercent()
        await loadAdapter()
        appendLog("refreshed helper + battery snapshot")
    }

    private func pingHelper() async {
        let running = await XPCClient.shared.ping(timeout: 3)
        protocolVersion = await XPCClient.shared.helperProtocolVersion(timeout: 3)
        chargeControlMode = await BatteryManager.shared.currentChargeControlMode()
        appendLog("ping: \(running ? "reachable" : "unreachable"), protocol v\(protocolVersion.map(String.init) ?? "?"), mode \(String(describing: chargeControlMode ?? .legacy))")
    }

    private func pauseCharging() async {
        let mode = await BatteryManager.shared.currentChargeControlMode()
        if mode == .firmware {
            BatteryManager.shared.setChargeLimit(limitInput)
            appendLog("firmware pause: setChargeLimit(\(limitInput))")
        } else {
            BatteryManager.shared.enableCharging(false)
            appendLog("legacy pause: enableCharging(false)")
        }
    }

    private func loadSMCKeys() async {
        guard let helper = BatteryManager.shared.getHelper() else {
            appendLog("SMC keys failed: no helper proxy")
            return
        }
        smcKeys = (await helper.getAllSMCKeys()).sorted()
        appendLog("loaded \(smcKeys.count) SMC keys")
    }

    private func loadFanInfo() async {
        guard let helper = BatteryManager.shared.getHelper() else {
            appendLog("fan info failed: no helper proxy")
            return
        }
        fanCount = await helper.getFanCount()
        await fanManager.refreshHardwareState(forceRediscovery: true)
        appendLog("fan count: \(fanCount ?? 0)")
    }

    private func loadAdapter() async {
        adapter = await BatteryManager.shared.getPowerAdapterInfo()
        appendLog("adapter: \(adapter?.name ?? "N/A") \(adapter?.power ?? 0)W")
    }

    private func loadTemperature() async {
        batteryTemp = await BatteryManager.shared.getBatteryTemperature()
        appendLog("battery temp: \(batteryTemp.map { String(format: "%.1f", $0) } ?? "—") °C")
    }

    private func loadHardwarePercent() async {
        hardwarePercent = await BatteryManager.shared.getHardwareBatteryPercentage()
        appendLog("hardware percent: \(hardwarePercent.map(String.init) ?? "—")")
    }
}

private struct BatteryDebugCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.orange.opacity(0.25), lineWidth: 1)
            )
    }
}

private extension View {
    func debugCard() -> some View {
        modifier(BatteryDebugCardModifier())
    }
}