//
//  PremiumFeatureViews.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-15

#if !SAPPHIRE_FULL_BUILD
import SwiftUI

struct SystemPowerReading {
    let systemLoad: Double
    let adapterPower: Double
    let adapterConnected: Bool
    let isCharging: Bool

    var heroWatts: Double { adapterConnected ? max(adapterPower, systemLoad) : systemLoad }
    var adapterDisplayWatts: Double { adapterPower > 0 ? adapterPower : heroWatts }
    var statusLabel: String { isCharging ? "Charging" : (adapterConnected ? "On AC Power" : "On Battery") }
    var statusColor: Color { isCharging ? .green : (adapterConnected ? .cyan : .orange) }
}

struct PowerSplitBar: View {
    let reading: SystemPowerReading
    var body: some View { Capsule().fill(reading.statusColor) }
}

extension StatsManager {
    var adapterSensorPower: Double { 0 }
}

private struct PremiumUnavailableView: View {
    let title: String

    var body: some View {
        Text("\(title) is not included in this build.")
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct KeyboardShortcutsSettingsView: View { var body: some View { PremiumUnavailableView(title: "Keyboard Shortcuts") } }
struct ContinuitySettingsView: View { var body: some View { PremiumUnavailableView(title: "Continuity") } }
struct EmojiSettingsView: View { var body: some View { PremiumUnavailableView(title: "Emoji") } }
struct MouseSettingsView: View { var body: some View { PremiumUnavailableView(title: "Mouse") } }
struct MonitoringSettingsView: View { var body: some View { PremiumUnavailableView(title: "Monitoring") } }
struct ArchivesAndDMGInstallerSettingsView: View { var body: some View { PremiumUnavailableView(title: "Archives") } }
struct AppLockSettingsView: View { var body: some View { PremiumUnavailableView(title: "App Lock") } }
struct DockLayoutsSettingsView: View { var body: some View { PremiumUnavailableView(title: "Dock Layouts") } }
struct MediaOptimizerSettingsView: View { var body: some View { PremiumUnavailableView(title: "Media Optimizer") } }

struct StorageWorkspaceView: View {
    @ObservedObject var model: StorageViewModel
    var body: some View { PremiumUnavailableView(title: "Storage Workspace") }
}

struct EightDAudioView: View {
    let bundleID: String
    let appName: String
    var body: some View { PremiumUnavailableView(title: "8D Audio") }
}

struct SurroundAudioView: View {
    let bundleID: String
    let appName: String
    var body: some View { PremiumUnavailableView(title: "Surround Audio") }
}

struct StorageDetailView: View {
    var body: some View { PremiumUnavailableView(title: "Storage") }
}

struct StorageWidgetView: View {
    var body: some View { EmptyView() }
}

struct ClipboardItemThumbnailView: View {
    let item: ClipboardItem
    var size: CGFloat = 24
    var cornerRadius: CGFloat = 7
    var fallbackSystemImage = "photo"
    var fallbackTint: Color = .purple
    var strokeColor: Color?

    var body: some View {
        Image(systemName: fallbackSystemImage)
            .foregroundStyle(fallbackTint)
            .frame(width: size, height: size)
    }
}
#endif