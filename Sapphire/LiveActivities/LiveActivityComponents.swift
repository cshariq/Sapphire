//
//  LiveActivityComponents.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-07-06.
//

import SwiftUI
import AppKit
import Symbols
import EventKit
import AVFoundation

private func foregroundStyle(for state: ManagementState) -> AnyShapeStyle {
    switch state {
    case .inhibited:
        return AnyShapeStyle(Color.blue)
    case .calibrationStarted, .calibrating:
        return AnyShapeStyle(Color.purple)
    case .calibrationDone:
        return AnyShapeStyle(Color.green)
    case .calibrationFailed:
        return AnyShapeStyle(Color.red)
    case .sailing:
        return AnyShapeStyle(Color.orange)
    case .dischargeStarted, .discharging, .dischargeStopped:
        return AnyShapeStyle(Color.cyan)
    case .heatProtectionOn, .heatProtection:
        return AnyShapeStyle(Color.red)
    case .heatProtectionOff:
        return AnyShapeStyle(Color.cyan)
    default:
        return AnyShapeStyle(Color.white.opacity(0.8))
    }
}

struct PersistentBatteryActivityView {
    static func left(for state: BatteryState, timeRemaining: String?, systemState: BatterySystemState) -> some View {
        let managementState = systemState.managementState

        return Group {
            if let timeString = timeRemaining, !timeString.isEmpty {
                Text(timeString)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.8))
                    .transition(.opacity.animation(.easeInOut))
            } else {
                let iconName: String = {
                    switch managementState {
                    case .inhibited: return "pause.fill"
                    case .sailing: return "sailboat.fill"
                    case .heatProtection: return "thermometer.sun.fill"
                    case .discharging: return "arrow.down.to.line.compact"
                    case .calibrating: return "battery.100.bolt"
                    case .charging: return state.isCharging ? "bolt.fill" : "powerplug.fill"
                    default: return "info.circle"
                    }
                }()
                Image(systemName: iconName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(foregroundStyle(for: managementState))
            }
        }
    }

    static func right(for state: BatteryState, systemState: BatterySystemState) -> some View {
        HStack(spacing: 6) {
            Text("\(state.level)%")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
            FilledBatteryIcon(level: state.level, isCharging: state.isCharging, isPluggedIn: state.isPluggedIn, isLowBattery: state.isLow, managementState: systemState.managementState)
        }
    }
}

struct statsLiveActivityView {
    enum DisplayableStat: Identifiable, Hashable {
        case highLevel(StatType)
        case sensor(any Sensor_p)

        var id: String {
            switch self {
            case .highLevel(let type): return type.rawValue
            case .sensor(let sensor): return sensor.key
            }
        }

        static func == (lhs: statsLiveActivityView.DisplayableStat, rhs: statsLiveActivityView.DisplayableStat) -> Bool {
            lhs.id == rhs.id
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
        }
    }

    static func left(for payload: StatsPayload, selectedStats: [StatType], selectedSensorKeys: [String]) -> some View {
        SideView(seed: payload, selectedStats: selectedStats, selectedSensorKeys: selectedSensorKeys, part: .icon)
    }

    static func right(for payload: StatsPayload, selectedStats: [StatType], selectedSensorKeys: [String]) -> some View {
        SideView(seed: payload, selectedStats: selectedStats, selectedSensorKeys: selectedSensorKeys, part: .value)
    }

    private struct SideView: View {
        let seed: StatsPayload
        let selectedStats: [StatType]
        let selectedSensorKeys: [String]
        let part: SingleStatPart
        @ObservedObject private var statsManager = StatsManager.shared

        private var payload: StatsPayload { statsManager.currentStats ?? seed }

        var body: some View {
            let allItems = getAllDisplayableItems(payload: payload, selectedStats: selectedStats, selectedSensorKeys: selectedSensorKeys)
            Group {
                if allItems.count == 1 {
                    singleStatView(for: allItems[0], payload: payload, part: part)
                } else {
                    let (leftItems, rightItems) = splitItems(allItems)
                    dynamicStatHStack(for: part == .icon ? leftItems : rightItems, payload: payload)
                }
            }
        }
    }

    private static func getAllDisplayableItems(payload: StatsPayload, selectedStats: [StatType], selectedSensorKeys: [String]) -> [DisplayableStat] {
        var items: [DisplayableStat] = []

        for statType in selectedStats {
            items.append(.highLevel(statType))
        }

        let availableSensors = payload.sensors?.sensors ?? []
        let selectedSensors = selectedSensorKeys.compactMap { key in
            availableSensors.first(where: { $0.key == key })
        }.sorted { $0.name < $1.name }

        for sensor in selectedSensors {
            items.append(.sensor(sensor))
        }

        return items
    }

    private static func splitItems(_ items: [DisplayableStat]) -> (left: [DisplayableStat], right: [DisplayableStat]) {
        let count = items.count
        guard count > 0 else { return ([], []) }

        let mid = (count + 1) / 2
        let left = Array(items.prefix(mid))
        let right = Array(items.suffix(from: mid))

        return (left, right)
    }

    @ViewBuilder
    private static func dynamicStatHStack(for items: [DisplayableStat], payload: StatsPayload) -> some View {
        HStack(spacing: 8) {
            ForEach(items) { item in
                statItemView(for: item, payload: payload)
            }
        }
        .foregroundColor(.white.opacity(0.8))
        .animation(.easeInOut(duration: 0.4), value: payload)
    }

    @ViewBuilder
    private static func statItemView(for item: DisplayableStat, payload: StatsPayload) -> some View {
        switch item {
        case .highLevel(let statType):
            Group {
                if statType != .disk {
                    VStack(spacing: 1) {
                        Image(systemName: statType.systemImage)
                            .font(.system(size: 12, weight: .medium))

                        let value: Double = {
                            switch statType {
                            case .cpu: return payload.cpu?.totalUsage ?? 0
                            case .ram: return payload.ram?.usage ?? 0
                            case .gpu: return payload.gpu?.utilization ?? 0
                            case .systemPower: return payload.systemPower ?? 0
                            case .batteryPower: return payload.batteryPower ?? 0
                            default: return 0
                            }
                        }()

                        if statType == .systemPower || statType == .batteryPower {
                            statValueText(String(format: "%.1fW", value))
                        } else {
                            statValueText("\(Int(value.isFinite ? (value * 100) : 0))%")
                        }
                    }
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .frame(width: 45)
                } else {
                    HStack(spacing: 4) {
                        Image(systemName: statType.systemImage)
                            .font(.system(size: 12, weight: .medium))

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 2) {
                                Image(systemName: "arrow.down.to.line.compact")
                                Text(Units(bytes: payload.disk?.activity.read ?? 0).getReadableSpeed(base: .byte))
                            }
                            HStack(spacing: 2) {
                                Image(systemName: "arrow.up.to.line.compact")
                                Text(Units(bytes: payload.disk?.activity.write ?? 0).getReadableSpeed(base: .byte))
                            }
                        }
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                    }
                }
            }

        case .sensor(let sensor):
            VStack(spacing: 1) {
                Text(sensor.name)
                    .font(.system(size: 9, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                statValueText(sensor.formattedValue)
            }
            .frame(width: 55)
        }
    }

    enum SingleStatPart { case icon, value }
    @ViewBuilder
    private static func singleStatView(for item: DisplayableStat, payload: StatsPayload, part: SingleStatPart) -> some View {
        switch part {
        case .icon:
            let systemImage: String = {
                switch item {
                case .highLevel(let statType): return statType.systemImage
                case .sensor(let sensor):
                    switch sensor.type {
                    case .fan: return "fanblades.fill"
                    case .temperature: return "thermometer.medium"
                    case .voltage: return "bolt.circle"
                    case .current: return "bolt.horizontal.circle"
                    case .power, .energy: return "bolt.fill"
                    default: return "gauge.medium"
                    }
                }
            }()
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white.opacity(0.9))
        case .value:
            let valueString: String = {
                switch item {
                case .highLevel(let statType):
                    switch statType {
                    case .cpu:
                        let usage = payload.cpu?.totalUsage ?? 0
                        return "\(Int(usage.isFinite ? usage * 100 : 0))%"
                    case .ram:
                        let usage = payload.ram?.usage ?? 0
                        return "\(Int(usage.isFinite ? usage * 100 : 0))%"
                    case .gpu:
                        let utilization = payload.gpu?.utilization ?? 0
                        return "\(Int(utilization.isFinite ? utilization * 100 : 0))%"
                    case .disk: return "\(Units(bytes: payload.disk?.activity.read ?? 0).getReadableSpeed(base: .byte)) R / \(Units(bytes: payload.disk?.activity.write ?? 0).getReadableSpeed(base: .byte)) W"
                    case .systemPower: return String(format: "%.1f W", payload.systemPower ?? 0)
                    case .batteryPower: return String(format: "%.1f W", payload.batteryPower ?? 0)
                    }
                case .sensor(let sensor):
                    return sensor.formattedValue
                }
            }()
            LayerNumericText(
                text: valueString,
                font: singleValueFont,
                color: TimerActivityView.primaryTextColor,
                duration: 0.4
            )
            .animation(.easeInOut(duration: 0.4), value: valueString)
            .frame(minWidth: 50, alignment: .trailing)
        }
    }

    private static func statValueText(_ text: String) -> some View {
        LayerNumericText(text: text, font: statValueFont, color: statValueColor, duration: 0.4)
    }

    private static let statValueFont = roundedFont(size: 11, weight: .semibold)
    private static let singleValueFont = roundedFont(size: 13, weight: .semibold)
    private static let statValueColor = NSColor.white.withAlphaComponent(0.8)

    private static func roundedFont(size: CGFloat, weight: NSFont.Weight) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        guard let rounded = base.fontDescriptor.withDesign(.rounded) else { return base }
        return NSFont(descriptor: rounded, size: size) ?? base
    }
}

struct FileProgressLiveActivityView {

    static func left(for task: FileTask) -> some View {
        let iconName: String
        switch task {
        case .universalTransfer(let transfer):
            switch transfer.sourceType {
            case .finder: iconName = "arrow.right.arrow.left.circle.fill"
            case .archiveExtraction: iconName = "archivebox.fill"
            case .dmgInstall: iconName = "externaldrive.fill.badge.plus"
            case .continuity: iconName = "iphone"
            case .browserDownload, .manual: iconName = "arrow.down.circle.fill"
            }
        case .airDrop: iconName = "airplayaudio"
        case .incomingTransfer: iconName = "arrow.down.circle.fill"
        case .fileConversion: iconName = "arrow.triangle.2.circlepath"
        case .local: iconName = "doc.fill"
        }

        if case .universalTransfer(let transfer) = task, transfer.app != nil {
            return AnyView(FileProgressAppGlyph(
                app: transfer.app, fallbackSymbol: iconName,
                fraction: transfer.isComplete ? 1 : transfer.progress, size: 22))
        }
        return AnyView(ZStack {
            Image(systemName: iconName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
        }
        .frame(width: 20, height: 20))
    }

    static func right(for task: FileTask) -> some View {
        let progress: Double?
        let fileName: String
        let statusText: String

        switch task {
        case .universalTransfer(let transferTask):
            progress = transferTask.progress
            fileName = transferTask.fileName
            let verb: String
            switch transferTask.sourceType {
            case .finder: verb = String(localized: "Copying...")
            case .archiveExtraction: verb = String(localized: "Extracting...")
            case .dmgInstall: verb = String(localized: "Installing...")
            case .continuity: verb = String(localized: "Continuity…")
            case .browserDownload, .manual: verb = String(localized: "Downloading...")
            }
            if transferTask.app != nil {
                statusText = FileProgressFormat.status(
                    percent: progress, speed: transferTask.speed, remaining: transferTask.timeRemaining,
                    finished: transferTask.isComplete, failed: false, verb: verb)
            } else if transferTask.sourceType == .finder {
                statusText = transferTask.speed > 0 ? TransferMetricsFormatter.speed(transferTask.speed) : verb
            } else if let progress {
                statusText = "\(Int(progress * 100))% • " + (transferTask.speed > 0 ? TransferMetricsFormatter.speed(transferTask.speed) : verb)
            } else {
                statusText = transferTask.speed > 0 ? TransferMetricsFormatter.speed(transferTask.speed) : verb
            }

        case .airDrop(let airDropTask):
            progress = airDropTask.progress
            fileName = airDropTask.fileName
            statusText = airDropTask.isComplete ? String(localized: "Complete") : String(localized: "Receiving...")
        case .incomingTransfer(let info):
            progress = info.progress
            fileName = info.fileDescription
            statusText = String(localized: "Receiving...")
        case .fileConversion(let task):
            progress = task.progress
            fileName = task.fileName
            statusText = String(localized: "Converting...")
        case .local(let item):
            progress = 1.0
            fileName = item.fileName
            statusText = String(localized: "Ready")
        }

        return HStack(spacing: 8) {
            // Capped so a long file name scrolls instead of stretching the notch to its full width.
            VStack(alignment: .leading, spacing: 1) {
                MarqueeText(
                    Text(fileName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                )

                Text(statusText)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.7))
                    .lineLimit(1)
            }
            .frame(maxWidth: 170, alignment: .leading)

            Spacer()

            if let progressValue = progress {
                if progressValue >= 1.0 {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .transition(.opacity.combined(with: .scale(scale: 0.8)))
                } else {
                    FileCircularProgressIndicator(progress: progressValue, size: 12, lineWidth: 3.0)
                        .transition(.opacity.combined(with: .scale(scale: 0.8)))
                }
            } else {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .frame(width: 18, height: 18)
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
        }
    }

}

struct IntelligenceAgentActivityView {
    static func left() -> some View {
        Image(systemName: "sparkle")
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(Color(red: 0.36, green: 0.90, blue: 0.76))
    }

    static func right(status: String, stepTitle: String, current: Int, total: Int) -> some View {
        let progress = total > 0 ? Double(current) / Double(total) : 0
        let label = stepTitle.isEmpty ? status : stepTitle

        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .lineLimit(1)

                if total > 0 {
                    Text("Step \(current) of \(total)")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.55))
                        .contentTransition(.numericText())
                } else if !status.isEmpty && status != label {
                    Text(status)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                }
            }

            if total > 0 {
                BlipStepProgressRing(progress: progress, current: current, total: total, size: 20, lineWidth: 5)
            }
        }
        .foregroundColor(.white.opacity(0.92))
    }
}

struct BlipStepProgressRing: View {
    let progress: Double
    let current: Int
    let total: Int
    let size: CGFloat
    let lineWidth: CGFloat

    var body: some View {
        ZStack {
            ProgressRingView(
                progress: progress,
                lineWidth: lineWidth,
                active: AngularGradient(
                    colors: [
                        Color(red: 0.36, green: 0.90, blue: 0.76),
                        Color(red: 0.18, green: 0.62, blue: 0.55),
                        Color(red: 0.36, green: 0.90, blue: 0.76)
                    ],
                    center: .center
                )
            )
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: progress)

            if total > 0 {
                Text("\(current)")
                    .font(.system(size: size * 0.38, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.92))
                    .contentTransition(.numericText())
            }
        }
        .frame(width: size, height: size)
    }
}

struct FileCircularProgressIndicator: View {
    let progress: Double
    let size: CGFloat
    let lineWidth: CGFloat

    var body: some View {
        ProgressRingView(
            progress: progress,
            lineWidth: lineWidth,
            track: AnyShapeStyle(Color.accentColor.opacity(0.3)),
            active: Color.accentColor,
            rotation: .degrees(270)
        )
        .frame(width: size, height: size)
        .animation(.linear(duration: 0.2), value: progress)
    }
}

struct AlbumArtView: View {
    var musicWidget: MusicManager { .shared }

    var body: some View {
        MusicArtworkImage(image: musicWidget.artwork, size: 20)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .id(musicWidget.currentTrackArtworkToken)
            .animation(nil, value: musicWidget.currentTrackArtworkToken)
            .onHover { isHovering in
                musicWidget.setAlbumArtHovered(isHovering)
            }
    }
}

struct QuickPeekView: View {
    let title: String
    let artist: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title + " · " + artist!)
                .font(.system(size: 10, weight: .regular, design: .rounded))
                .lineLimit(1)
                .truncationMode(.tail)
                .opacity(0.6)
        }
        .frame(maxWidth: 200)
        .transition(.opacity.animation(.easeInOut(duration: 0.3)))
    }
}

struct MusicUpNextView: View {
    let title: String
    let artist: String?
    let artworkURL: URL?

    private var musicWidget: MusicManager { .shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(String(localized: "music.up-next", defaultValue: "UP NEXT"))
                .font(.system(size: 7.5, weight: .heavy, design: .rounded))
                .kerning(1.3)
                .foregroundColor(.gray.opacity(0.9))

            HStack(spacing: 7) {
                Group {
                    if let artworkURL {
                        CachedAsyncImage(url: artworkURL) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } placeholder: {
                            placeholderArtwork
                        }
                    } else {
                        placeholderArtwork
                    }
                }
                .frame(width: 20, height: 20)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))

                VStack(alignment: .leading, spacing: 1) {
                    Text(title.isEmpty ? String(localized: "Unknown track") : title)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(.white.opacity(0.95))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if let artist, !artist.isEmpty {
                        Text(artist)
                            .font(.system(size: 9, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.6))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: 6)

                LayerProgressRing(motion: ringMotion, lineWidth: 2.5, activeColor: .white)
                    .frame(width: 16, height: 16)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 0)
        .transition(.opacity.animation(.easeInOut(duration: 0.3)))
    }

    private var ringMotion: LinearProgressMotion {
        let now = Date()
        let trajectory = musicWidget.playbackTrajectory
        let progress = ringProgress(at: now)
        guard trajectory.isAdvancing, musicWidget.totalDuration > 0, progress < 1 else {
            return LinearProgressMotion(progress: progress, date: now)
        }
        return LinearProgressMotion(progress: progress, date: now, rate: trajectory.rate / 10)
    }

    private func ringProgress(at date: Date) -> Double {
        guard musicWidget.totalDuration > 0 else { return 0.2 }
        let remaining = musicWidget.totalDuration - musicWidget.elapsedTime(at: date)
        guard remaining.isFinite && remaining >= 0 else { return 0 }
        let p = (10.0 - remaining) / 10.0
        return max(0.03, min(1.0, p))
    }

    private var placeholderArtwork: some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(Color.white.opacity(0.12))
            .overlay(Image(systemName: "music.note")
                .font(.system(size: 8, weight: .semibold))
                .foregroundColor(.white.opacity(0.5)))
    }
}

struct MusicLyricsView: View {
    var musicWidget: MusicManager { .shared }
    @Binding var showLyrics: Bool

    @State private var lyricText: String?
    @State private var lyricID: UUID?

    init(_ showLyrics: Binding<Bool>) {
        self._showLyrics = showLyrics
    }

    var body: some View {
        Group {
            if let text = lyricText, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(text)
                    .font(.system(size: 10, weight: .regular, design: .rounded))
                    .foregroundColor(musicWidget.accentColor.opacity(0.9))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 200)
                    .transition(.opacity.animation(.easeInOut(duration: 0.3)))
                    .id("lyric-\(lyricID?.uuidString ?? "")")
                    .onTapGesture {
                        showLyrics = true
                    }
            } else {
                EmptyView()
            }
        }
        .onAppear {
            let current = musicWidget.currentLyric
            self.lyricText = current?.translatedText ?? current?.text
            self.lyricID = current?.id
        }
        .onReceive(musicWidget.currentLyricPublisher) { newLyric in
            self.lyricText = newLyric?.translatedText ?? newLyric?.text
            self.lyricID = newLyric?.id
        }
    }
}

struct NowPlayingTextView: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: 200)
            .transition(.opacity.animation(.easeInOut(duration: 0.3)))
            .opacity(1)
    }
}

// MARK: - Activity View Components

struct AudioSwitchActivityView {
    static func left(for event: AudioSwitchEvent) -> some View {
        Image(systemName: "arrow.uturn.backward.circle.fill")
            .font(.system(size: 18, weight: .semibold))
            .foregroundColor(.white)
            .symbolRenderingMode(.hierarchical)
    }

    static func right(for event: AudioSwitchEvent) -> some View {
        let targetDeviceIcon = event.direction == .switchedToMac ? "desktopcomputer" : "iphone"
        let targetDeviceName = event.direction == .switchedToMac ? "Mac" : "iPhone"

        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(event.deviceName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.9))
                    .lineLimit(1)
                Text("Connected to \(targetDeviceName)")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.7))
                    .lineLimit(1)
            }
            Image(systemName: targetDeviceIcon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
        }
    }
}

struct CompactBatteryActivityView {
    static func left(for state: BatteryState, systemState: BatterySystemState) -> some View {
        let managementState = systemState.managementState

        let iconName: String = {
            switch managementState {
            case .inhibited: return "pause.fill"
            case .sailing: return "sailboat.fill"
            case .heatProtection, .heatProtectionOn: return "thermometer.sun.fill"
            case .heatProtectionOff: return "snowflake"
            case .discharging, .dischargeStarted: return "arrow.down.to.line.compact"
            case .dischargeStopped: return "checkmark"
            case .calibrating, .calibrationStarted: return "battery.100.bolt"
            case .calibrationDone: return "checkmark.seal.fill"
            case .calibrationFailed: return "exclamationmark.triangle.fill"
            case .charging:
                if state.isPluggedIn && !state.isCharging { return "powerplug.fill" }
                return state.isLow ? "battery.25" : "bolt.fill"
            }
        }()

        return Image(systemName: iconName)
            .frame(width: 20, height: 20)
            .foregroundStyle(foregroundStyle(for: managementState))
    }

    static func right(for state: BatteryState) -> some View {
        Text("\(state.level)%")
            .font(.system(size: 13, weight: .semibold))
    }
}

struct DefaultBatteryActivityView {
    static func left(for state: BatteryState, systemState: BatterySystemState) -> some View {
        let managementState = systemState.managementState

        let iconName: String
        let text: String
        let style: AnyShapeStyle

        switch managementState {
        case .charging where state.isPluggedIn && !state.isCharging:
            iconName = "powerplug.fill"; text = String(localized: "Plugged In"); style = AnyShapeStyle(Color.white.opacity(0.9))
        case .charging:
            iconName = "bolt.fill"; text = String(localized: "Charging"); style = AnyShapeStyle(Color.green)
        case .inhibited:
            iconName = "pause.fill"; text = String(localized: "Charging Paused"); style = foregroundStyle(for: .inhibited)
        case .sailing:
            iconName = "sailboat.fill"; text = String(localized: "Sailing by \(String(state.level))%"); style = foregroundStyle(for: .sailing)
        case .heatProtectionOn:
            iconName = "thermometer.sun.fill"; text = String(localized: "Heat Protection On"); style = foregroundStyle(for: .heatProtectionOn)
        case .heatProtectionOff:
            iconName = "snowflake"; text = String(localized: "Heat Protection Off"); style = AnyShapeStyle(Color.cyan)
        case .heatProtection:
            iconName = "thermometer.sun.fill"; text = String(localized: "Heat Protection"); style = foregroundStyle(for: .heatProtection)
        case .dischargeStarted:
            iconName = "arrow.down.to.line.compact"; text = String(localized: "Discharge Started"); style = foregroundStyle(for: .dischargeStarted)
        case .dischargeStopped:
            iconName = "checkmark"; text = String(localized: "Discharge Stopped"); style = foregroundStyle(for: .dischargeStopped)
        case .discharging:
            iconName = "arrow.down.to.line.compact"; text = String(localized: "Discharging"); style = foregroundStyle(for: .discharging)
        case .calibrationStarted:
            iconName = "battery.100.bolt"; text = String(localized: "Calibration Started"); style = foregroundStyle(for: .calibrationStarted)
        case .calibrating:
            iconName = "battery.100.bolt"; text = String(localized: "Calibrating"); style = foregroundStyle(for: .calibrating)
        case .calibrationDone:
            iconName = "checkmark.seal.fill"; text = String(localized: "Calibration Complete"); style = foregroundStyle(for: .calibrationDone)
        case .calibrationFailed:
            iconName = "exclamationmark.triangle.fill"; text = String(localized: "Calibration Failed"); style = foregroundStyle(for: .calibrationFailed)
        }

        return AnyView(
            HStack(spacing: 6) {
                Image(systemName: iconName)
                Text(text)
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(style)
        )
    }

    static func right(for state: BatteryState, timeRemaining: String?, systemState: BatterySystemState) -> some View {
        HStack(spacing: 6) {
            if SettingsModel.shared.settings.showEstimatedBatteryTime, let timeString = timeRemaining, !timeString.isEmpty {
                 Text(timeString)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.8))
                    .transition(.opacity)
            }
            Text("\(state.level)%")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
            FilledBatteryIcon(level: state.level, isCharging: state.isCharging, isPluggedIn: state.isPluggedIn, isLowBattery: state.isLow, managementState: systemState.managementState)
        }
    }
}

struct ReminderProximityActivityView {
    static func left() -> some View {
        Image(systemName: "checklist")
            .font(.system(size: 18, weight: .semibold))
            .foregroundColor(.orange)
            .symbolRenderingMode(.hierarchical)
    }

    static func right(reminder: EKReminder) -> some View {
        let dueDate = reminder.dueDateComponents?.date
        return TimelineView(.periodic(from: .now, by: 1.0)) { context in
            let remaining = dueDate?.timeIntervalSinceNow ?? 0
            Text(remaining.asRemainingClockOrNow)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundColor(.white.opacity(0.9))
        }
    }
}

struct FilledBatteryIcon: View {
    let level: Int
    let isCharging: Bool
    let isPluggedIn: Bool
    let isLowBattery: Bool
    let managementState: ManagementState

    private let iconSize: CGFloat = 26
    private let iconWeight: Font.Weight = .regular

    private var iconName: String {
        if isCharging {
            switch managementState {
            case .calibrating, .calibrationStarted, .charging:
                return "battery.100.bolt"
            default:
                break
            }
        }

        switch level {
        case 96...100: return "battery.100"
        case 71...95:  return "battery.75"
        case 46...70:  return "battery.50"
        case 11...45:  return "battery.25"
        default:       return "battery.0"
        }
    }

    private var iconStyle: AnyShapeStyle {
        switch managementState {
        case .sailing:
            return AnyShapeStyle(Color.orange)
        case .heatProtection, .heatProtectionOn:
            return AnyShapeStyle(Color.red)
        case .discharging, .dischargeStarted:
            return AnyShapeStyle(Color.cyan)
        case .calibrating, .calibrationStarted:
            return AnyShapeStyle(Color.purple)
        case .inhibited:
            return AnyShapeStyle(Color.blue)
        case .calibrationDone:
            return AnyShapeStyle(Color.green)
        case .calibrationFailed:
            return AnyShapeStyle(Color.red)
        default:
            if isCharging { return AnyShapeStyle(Color.green) }
            if isLowBattery { return AnyShapeStyle(Color.red) }
            return AnyShapeStyle(Color.white)
        }
    }

    var body: some View {
        Image(systemName: iconName)
            .dimmedBatteryCase(iconName != "battery.100")
            .font(.system(size: iconSize, weight: iconWeight))
            .foregroundStyle(iconStyle)
            .frame(width: iconSize + 4, height: iconSize / 2 + 4)
            .animation(.easeInOut(duration: 0.3), value: iconName)
            .animation(.easeInOut(duration: 0.3), value: managementState)
            .padding(.leading, 4)
            .padding(.trailing, 7)
    }
}

extension View {
    /// Draws a battery symbol's case one level dimmer than its charge, like the macOS menu bar.
    /// Pass false for single-layer symbols (a full battery, a leaf), which would otherwise dim entirely.
    func dimmedBatteryCase(_ isEnabled: Bool = true) -> some View {
        symbolRenderingMode(.palette)
            .foregroundStyle(isEnabled ? HierarchicalShapeStyle.secondary : .primary, .primary)
    }
}

struct BatteryRingView: View {
    let level: Int
    var color: Color?

    private var setColor: Color {
        if let unwrappedColor = color {
            return unwrappedColor
        } else {
            if level <= 10 {
                return .red
            } else if level <= 25 {
                return .yellow
            }
            return .green
        }
    }

    var body: some View {
        ProgressRingView(
            progress: Double(level) / 100.0,
            lineWidth: 3,
            track: AnyShapeStyle(Color.accentColor.opacity(0.3)),
            active: setColor
        )
        .animation(.easeOut, value: level)
        .frame(width: 14, height: 14)
        .padding(3)
    }
}

private extension BluetoothDeviceState {
    var liveActivityIconName: String {
        guard !iconName.isEmpty,
              NSImage(systemSymbolName: iconName, accessibilityDescription: nil) != nil else {
            return "bluetooth"
        }
        return iconName
    }
}

struct BluetoothConnectedPeripheralView {
    static func left(for device: BluetoothDeviceState) -> some View {
        Image(systemName: device.liveActivityIconName)
            .font(.system(size: 18, weight: .semibold))
            .foregroundColor(.white)
            .symbolRenderingMode(.hierarchical)
    }

    @ViewBuilder
    static func right(for device: BluetoothDeviceState) -> some View {
        if SettingsModel.shared.settings.showBluetoothDeviceName {
            HStack(spacing: 8) {
                Text(device.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.9))
                    .lineLimit(1)

                if let level = device.batteryLevel {
                    BatteryRingView(level: level)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.green)
                }
            }
        } else {
            if let level = device.batteryLevel {
                BatteryRingView(level: level)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.green)
            }
        }
    }
}

struct BluetoothConnectedContinuityView {
    static func left(for device: BluetoothDeviceState) -> some View {
        Image(systemName: device.liveActivityIconName)
            .font(.system(size: 18, weight: .semibold))
            .foregroundColor(.blue)
            .symbolRenderingMode(.hierarchical)
    }

    static func right(for device: BluetoothDeviceState) -> some View {
        HStack(spacing: 6) {
            Text(device.name)
                 .font(.system(size: 13, weight: .semibold))
                 .foregroundColor(.white.opacity(0.9))
                 .lineLimit(1)
            Image(systemName: "link.circle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.blue)
        }
    }
}

struct BluetoothDisconnectedView {
    static func left(for device: BluetoothDeviceState) -> some View {
        Image(systemName: device.liveActivityIconName)
            .font(.system(size: 18, weight: .semibold))
            .foregroundColor(.white.opacity(0.5))
            .symbolRenderingMode(.hierarchical)
    }

    static func right(for device: BluetoothDeviceState) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(device.name)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white.opacity(0.9))
                .lineLimit(1)
            Text("Disconnected")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.6))
        }
    }
}

struct BluetoothBatteryLowView {
    static func left(for device: BluetoothDeviceState) -> some View {
        Image(systemName: device.liveActivityIconName)
            .font(.system(size: 18, weight: .semibold))
            .foregroundColor(.white)
            .symbolRenderingMode(.hierarchical)
    }

    static func right(for device: BluetoothDeviceState) -> some View {
        HStack(spacing: 8) {
            if let level = device.batteryLevel {
                BatteryRingView(level: level)
                Text("\(level)%")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(.red)
            } else {
                Text("Low Battery")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.red)
            }
        }
    }
}

struct CalendarProximityActivityView {
    static func left() -> some View {
        Image(systemName: "calendar")
            .font(.system(size: 18, weight: .semibold))
            .foregroundColor(.blue)
            .symbolRenderingMode(.hierarchical)
    }

    static func right(event: EKEvent) -> some View {
        TimelineView(.periodic(from: .now, by: 1.0)) { context in
            let remaining = event.startDate.timeIntervalSinceNow
            Text(remaining.asRemainingClockOrNow)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundColor(.white.opacity(0.9))
        }
    }
}

struct DesktopActivityView {
    static func left(for number: Int) -> some View {
        Image(systemName: "rectangle.on.rectangle")
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(.white.opacity(0.9))
    }

    static func right(for number: Int) -> some View {
        Text("\(number)")
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(.white.opacity(0.9))
    }
}

struct EyeBreakFullActivityView: View {
    @Environment(\.notchBandHeight) private var notchBandHeight
    @EnvironmentObject var eyeBreakManager: EyeBreakManager
    @ObservedSettings var settings: SettingsObserver
    @Environment(LiveActivityManager.self) var liveActivityManager

    @State private var isShowing = false
    @State private var skipHovered = false
    @State private var doneHovered = false

    private var breakDuration: TimeInterval {
        TimeInterval(settings.settings.eyeBreakBreakDuration)
    }

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                ProgressRingView(
                    progress: 1 - (eyeBreakManager.timeRemainingInBreak / breakDuration),
                    lineWidth: 6,
                    track: AnyShapeStyle(Color.white.opacity(0.15)),
                    active: Color.cyan
                )
                .animation(.linear(duration: 0.3), value: eyeBreakManager.timeRemainingInBreak)

                Image(systemName: "eye.fill")
                    .font(.system(size: 32, weight: .light))
                    .foregroundColor(.cyan)
            }
            .frame(width: 70, height: 70)

            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Look Away")
                        .font(.system(size: 22, weight: .bold, design: .rounded))

                    Text("Look at something 20 feet away.")
                        .font(.callout)
                        .foregroundColor(.secondary)
                }

                HStack(spacing: 12) {
                    Button {
                        eyeBreakManager.dismissBreak()
                        liveActivityManager.dismissCurrentActivity()
                    } label: {
                        Text("Skip")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(EyeBreakPillButtonStyle(isProminent: false, isHovered: skipHovered))
                    .onHover { hovering in
                        withAnimation(.easeInOut(duration: 0.2)) {
                            skipHovered = hovering
                        }
                    }

                    Button {
                        eyeBreakManager.completeBreak()
                        liveActivityManager.dismissCurrentActivity()
                    } label: {
                        HStack(spacing: 6) {
                            Text("Done")
                            Text(String(format: "(%02d)", Int(eyeBreakManager.timeRemainingInBreak)))
                                .font(.system(.body, design: .monospaced))
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(EyeBreakPillButtonStyle(isProminent: true, isHovered: doneHovered))
                    .disabled(!eyeBreakManager.isDoneButtonEnabled)
                    .opacity(eyeBreakManager.isDoneButtonEnabled ? 1.0 : 0.7)
                    .animation(.easeInOut(duration: 0.3), value: eyeBreakManager.isDoneButtonEnabled)
                    .onHover { hovering in
                        withAnimation(.easeInOut(duration: 0.2)) {
                            doneHovered = hovering && eyeBreakManager.isDoneButtonEnabled
                        }
                    }
                }
            }
        }
        .padding(.vertical, 15)
        .padding(.horizontal, 25)
        .padding(.top, notchBandHeight)
        .frame(width: 380)
        .scaleEffect(isShowing ? 1 : 0.95)
        .opacity(isShowing ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.75, blendDuration: 0.2)) {
                isShowing = true
            }
        }
    }
}

struct EyeBreakPillButtonStyle: ButtonStyle {
    var isProminent: Bool
    var isHovered: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .padding(.vertical, 10)
            .background(backgroundColor(for: configuration))
            .foregroundColor(foregroundColor())
            .clipShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.97 : isHovered ? 1.02 : 1.0)
            .animation(.interpolatingSpring(stiffness: 300, damping: 15),
                       value: configuration.isPressed)
            .animation(.easeOut(duration: 0.2), value: isHovered)
    }

    private func backgroundColor(for configuration: Configuration) -> Color {
        if isProminent {
            let baseColor: Color = .cyan
            if configuration.isPressed { return baseColor.opacity(0.6) }
            else if isHovered { return baseColor.opacity(0.9) }
            return baseColor
        }

        if configuration.isPressed { return .white.opacity(0.15) }
        else if isHovered { return .white.opacity(0.13) }
        return .white.opacity(0.1)
    }

    private func foregroundColor() -> Color {
        if isProminent { return .black }
        return .white
    }
}

struct UpdateAvailableActivityView {
    static func left() -> some View {
        Image(systemName: "square.and.arrow.down.badge.clock")
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(.cyan)
    }

    static func right(version: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("Update Available")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white.opacity(0.9))
            Text("Version \(version)")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.7))
        }
    }
}

struct UpdateAvailableWidgetView: View {
    @ObservedObject private var updateChecker = UpdateChecker.shared

    private var availableVersion: String? {
        if case .available(let version, _) = updateChecker.status {
            return version
        }
        return nil
    }

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "square.and.arrow.down.badge.clock")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(.cyan)

            VStack(spacing: 3) {
                Text("Update Available")
                    .font(.title3.bold())
                    .foregroundColor(.white.opacity(0.95))
                if let availableVersion {
                    Text("Version \(availableVersion) is ready to install.")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.6))
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("How to update")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white.opacity(0.9))
                stepRow(number: 1, text: "Open the About page in Settings")
                stepRow(number: 2, text: "Click \"Download Update\"")
                stepRow(number: 3, text: "Click \"Install and Relaunch\"")
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            Button(action: openAboutSettings) {
                HStack(spacing: 8) {
                    Image(systemName: "gearshape.fill")
                    Text("Open About in Settings")
                        .fontWeight(.semibold)
                }
                .foregroundColor(.black)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(Color.cyan)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            Text("Updates are installed from the About page in Sapphire's settings.")
                .font(.caption)
                .foregroundColor(.white.opacity(0.45))
                .multilineTextAlignment(.center)
        }
        .padding(20)
        .frame(width: 380)
        .foregroundColor(.white)
    }

    private func stepRow(number: Int, text: String) -> some View {
        HStack(spacing: 10) {
            Text("\(number)")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.black)
                .frame(width: 20, height: 20)
                .background(Color.cyan)
                .clipShape(Circle())
            Text(text)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.85))
        }
    }

    private func openAboutSettings() {
        (NSApp.delegate as? AppDelegate)?.openSettingsWindow()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            NotificationCenter.default.post(
                name: NSNotification.Name("SapphireSelectSection"),
                object: SettingsSection.about.rawValue
            )
        }
    }
}

struct FocusModeActivityView {

    private static let colorMap: [String: Color] = [
        "systemIndigoColor": .indigo,
        "systemPurpleColor": .purple,
        "systemTealColor": .teal,
        "systemBlueColor": .blue,
        "systemGreenColor": .green,
        "systemRedColor": .red,
        "systemOrangeColor": .orange,
        "systemYellowColor": .yellow,
        "systemPinkColor": .pink,
        "systemCyanColor": .cyan,
        "systemMintColor": .mint,
        "systemGrayColor": .gray
    ]

    private static let customImageAssetNames: Set<String> = [
        "rocket.fill",
        "apple.mindfulness",
        "person.lanyardcard.fill"
    ]

    private static func focusForegroundStyle(for mode: FocusModeInfo) -> AnyShapeStyle {
        if let gradientColorNames = mode.tintColorNames, gradientColorNames.count >= 2 {
            let gradientColors = gradientColorNames.compactMap { colorMap[$0] }
            if gradientColors.count >= 2 {
                return AnyShapeStyle(LinearGradient(gradient: Gradient(colors: gradientColors), startPoint: .topLeading, endPoint: .bottomTrailing))
            }
        }

        if let singleColorName = mode.tintColorName, let color = colorMap[singleColorName] {
            return AnyShapeStyle(color)
        }

        return AnyShapeStyle(Color.purple)
    }

    @ViewBuilder
    static func left(for mode: FocusModeInfo) -> some View {
        if mode.identifier == "com.apple.focus.reduce-interruptions" {
            Image(systemName: "apple.intelligence")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(focusForegroundStyle(for: mode))

        } else if customImageAssetNames.contains(mode.symbolName) {
            Image(mode.symbolName)
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 14, height: 14)
                .foregroundStyle(focusForegroundStyle(for: mode))
                .opacity(mode.isActive ? 1.0 : 0.7)

        } else {
            let finalSymbolName = NSImage(systemSymbolName: mode.symbolName, accessibilityDescription: nil) != nil ? mode.symbolName : "questionmark.circle.fill"

            Image(systemName: finalSymbolName)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(focusForegroundStyle(for: mode))
        }
    }

    static func right(for mode: FocusModeInfo, displayMode: FocusDisplayMode) -> some View {
        let text: String

        if !mode.isActive {
            text = String(localized: "Off")
        } else {
            switch displayMode {
            case .full:
                text = mode.name
            case .compact:
                text = String(localized: "On")
            }
        }

        return Text(text)
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(.white.opacity(mode.isActive ? 0.9 : 0.7))
            .lineLimit(1)
    }
}

struct TimerActivityView {
    static func left(timerManager: TimerManager) -> some View {
        Image(systemName: timerManager.activeTimer == .stopwatch ? "stopwatch" : "timer")
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(timerManager.activeTimer == .stopwatch ? .green : .orange)
            .frame(width: 25, height: 25)
    }

    static func right(timerManager: TimerManager) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            LayerNumericText(
                text: timerManager.displayTime.asStopwatchClock,
                font: clockFont,
                color: primaryTextColor
            )
            .textBaseline()
        }
    }

    private static let clockFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .semibold)

    static let primaryTextColor: NSColor = {
        var color = NSColor.white
        NSAppearance(named: .darkAqua)?.performAsCurrentDrawingAppearance {
            color = NSColor.labelColor.usingColorSpace(.sRGB) ?? .white
        }
        return color
    }()
}

struct TimerFinishedActivityView: View {
    @Environment(\.notchBandHeight) private var notchBandHeight
    @ObservedObject var timerManager: TimerManager
    let timerID: String

    private var timer: SapphireTimer? {
        timerManager.ringingTimers.first { $0.id == timerID }
    }

    var body: some View {
        VStack(spacing: 0) {
            Color.clear
                .frame(height: notchBandHeight)

            if let timer {
                VStack(spacing: 14) {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(Color.orange.opacity(0.18))
                            Image(systemName: "timer")
                                .font(.system(size: 21, weight: .semibold))
                                .foregroundStyle(.orange)
                        }
                        .frame(width: 46, height: 46)

                        Image(systemName: "timer")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.primary)

                        Spacer(minLength: 18)

                        Text("00:00")
                            .font(.system(size: 19, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.orange)
                    }

                    Button {
                        timerManager.dismissRingingTimer(id: timer.id)
                    } label: {
                        Label("Stop", systemImage: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .foregroundStyle(.white)
                            .background(Color.orange.opacity(0.9))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .help("Dismiss timer")
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
                .frame(width: 360)
            }
        }
    }
}

struct WeatherActivityView {
    static func left(for data: ProcessedWeatherData) -> some View {
        Image(systemName: WeatherIconMapper.map(from: data.iconCode))
            .font(.title3)
            .symbolRenderingMode(.multicolor)
    }

    static func right(for data: ProcessedWeatherData) -> some View {
        RightView(data: data)
    }

    private struct RightView: View {
        let data: ProcessedWeatherData

        var body: some View {
            let temp = SettingsModel.shared.settings.weatherUseCelsius ? data.temperatureMetric : data.temperature
            Text("\(temp)°")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
        }
    }
}

struct ModernNotificationButtonStyle: ButtonStyle {
    var isPrimary: Bool = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.body, design: .rounded).weight(.semibold))
            .padding(.horizontal, 16).padding(.vertical, 0)
            .foregroundStyle(isPrimary ? .white : .primary.opacity(0.9))
            .clipShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.5), value: configuration.isPressed)
    }
}

struct NotificationLiveActivityView: View {
    @Environment(\.notchBandHeight) private var notchBandHeight
    let payload: NotificationPayload

    @Binding var isHovered: Bool

    @EnvironmentObject var notificationManager: NotificationManager
    @ObservedSettings var settings: SettingsObserver
    @State private var replyText = ""
    @FocusState private var isTextFieldFocused: Bool

    @State private var contactImage: NSImage? = nil

    @State private var attachment: MessageAttachment? = nil
    @State private var isFetchingAttachment = false
    @State private var audioPlaybackState: AudioPlaybackState = .idle
    public enum AudioPlaybackState { case idle, playing, finished }

    @State private var didCopyCode = false

    private let iMessageManager = iMessageActionManager.shared

    private var isIMessage: Bool {
        return payload.appIdentifier == "com.apple.MobileSMS" || payload.appIdentifier == "com.apple.iChat"
    }

    var body: some View {
        VStack(spacing: 0) {
            Color.clear
                .frame(height: notchBandHeight)

            if isIMessage {
                iMessageView
            } else {
                standardNotificationView
            }
        }
    }

    @ViewBuilder
    private var iMessageView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                ZStack(alignment: .bottomTrailing) {
                    if let image = contactImage {
                        Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                            .frame(width: 44, height: 44).clipShape(Circle())
                    } else {
                        Image(systemName: "person.circle.fill").font(.system(size: 44))
                            .foregroundStyle(.gray.opacity(0.5))
                    }
                    Image(systemName: "message.fill").font(.system(size: 10)).foregroundColor(.white)
                        .padding(4).background(Color.green).clipShape(Circle())
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(payload.title).font(.headline).fontWeight(.bold)
                        Spacer()
                        Text("now").font(.caption).foregroundStyle(.secondary)
                    }
                    if !payload.hasAudioAttachment && !payload.hasImageAttachment {
                        Text(payload.body).font(.subheadline).foregroundStyle(.secondary)
                            .lineLimit(3).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxHeight: 80)
            }
            .onTapGesture {
                NSWorkspace.shared.launchApplication(withBundleIdentifier: payload.appIdentifier, options: [], additionalEventParamDescriptor: nil, launchIdentifier: nil)
                notificationManager.dismissLatestNotification()
            }

            if isFetchingAttachment {
                ProgressView().frame(maxWidth: .infinity, alignment: .center)
            } else if let attachment = attachment {
                switch attachment.type {
                case .image:
                    CachedAsyncImage(url: attachment.localURL) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Color.clear
                    }
                    .frame(maxHeight: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                case .audio:
                    AudioMessageView(attachment: attachment, playbackState: $audioPlaybackState)
                case .other:
                    Text("Attachment: \(attachment.localURL.lastPathComponent)")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            if isHovered {
                replyBox.transition(.opacity.combined(with: .move(edge: .top)))
            } else {
                actionButtons
            }
        }
        .padding(.horizontal, 13)
        .padding(.bottom, 12)
        .frame(width: 400)
        .frame(minHeight: 120)
        .task(id: payload.id) {
            self.contactImage = await iMessageManager.fetchContactImage(forName: payload.title)
            attachment = nil; isFetchingAttachment = false; audioPlaybackState = .idle
            guard payload.hasAudioAttachment || payload.hasImageAttachment else { return }
            isFetchingAttachment = true
            self.attachment = await iMessageManager.fetchAndCopyLatestAttachment(for: payload.title)
            isFetchingAttachment = false
        }
        .onHover { hovering in
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { self.isHovered = hovering }
        }
        .onChange(of: isHovered) { _, newIsHovered in if !newIsHovered { isTextFieldFocused = false } }
        .onChange(of: isTextFieldFocused) { _, isFocused in
            if let appDelegate = NSApp.delegate as? AppDelegate {
                if isFocused { appDelegate.makeNotchWindowFocusable() } else { appDelegate.revertNotchWindowFocus() }
            }
        }
        .onDisappear { isHovered = false }
    }

    @ViewBuilder
    private var replyBox: some View {
        HStack(spacing: 8) {
            TextField("Reply...", text: $replyText)
                .textFieldStyle(.plain).onSubmit(sendIMessage).focused($isTextFieldFocused)
            Button(action: sendIMessage) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title3).symbolRenderingMode(.palette)
                    .foregroundStyle(replyText.isEmpty ? Color.secondary : Color.white, replyText.isEmpty ? Color.clear : Color.accentColor)
            }
            .buttonStyle(.plain).disabled(replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 16).frame(height: 40).background(.ultraThinMaterial).clipShape(Capsule())
    }

    @ViewBuilder
    private var standardNotificationView: some View {
        VStack(spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                if let icon = payload.appIcon {
                    Image(nsImage: icon).resizable().aspectRatio(contentMode: .fit)
                        .frame(width: 50, height: 50).clipShape(RoundedRectangle(cornerRadius: 12))
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(payload.appName).font(.headline).fontWeight(.bold)
                    Text(payload.title + " - " + payload.body).font(.subheadline).foregroundStyle(.secondary)
                        .lineLimit(4).fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxHeight: 100)
                Spacer()
            }
            .onTapGesture {
                NSWorkspace.shared.launchApplication(withBundleIdentifier: payload.appIdentifier, options: [], additionalEventParamDescriptor: nil, launchIdentifier: nil)
                notificationManager.dismissLatestNotification()
            }

            actionButtons
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .frame(minWidth: 350, maxWidth: 420)
        .frame(minHeight: 120)
    }

    @ViewBuilder
    private var actionButtons: some View {
        HStack {
            standardActionButton(title: String(localized: "Dismiss"), systemName: "xmark") {
                notificationManager.dismissLatestNotification()
            }

            Spacer()

            if let code = payload.verificationCode, settings.settings.showCopyButtonForVerificationCodes {
                Button(action: {
                    NSPasteboard.general.copyString(code)
                    withAnimation(.spring) { didCopyCode = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        withAnimation(.spring) { didCopyCode = false }
                        notificationManager.dismissLatestNotification()
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        notificationManager.dismissLatestNotification()
                    }
                }) {
                    Label(
                        didCopyCode ? String(localized: "Copied") : code,
                        systemImage: didCopyCode ? "checkmark" : "doc.on.doc"
                    )
                    .font(.system(size: 13, weight: .medium, design: didCopyCode ? .default : .monospaced))
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .contentTransition(.numericText())
                }
                .buttonStyle(.plain)
                .background(didCopyCode ? Color.green.opacity(0.25) : Color.primary.opacity(0.15))
                .foregroundStyle(didCopyCode ? .green : .primary)
                .clipShape(Capsule())
                .animation(.spring, value: didCopyCode)
            }

            if payload.appIdentifier == "com.apple.sharingd" {
                standardActionButton(title: String(localized: "Show"), systemName: "folder", isPrimary: true) {
                    if let url = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first { NSWorkspace.shared.open(url) }
                    notificationManager.dismissLatestNotification()
                }
            } else {
                standardActionButton(title: String(localized: "Open"), systemName: "arrow.up.forward.app", isPrimary: true) {
                    NSWorkspace.shared.launchApplication(withBundleIdentifier: payload.appIdentifier, options: [], additionalEventParamDescriptor: nil, launchIdentifier: nil)
                    notificationManager.dismissLatestNotification()
                }
            }
        }
    }

    private func sendIMessage() {
        let msg = replyText.trimmingCharacters(in: .whitespacesAndNewlines); guard !msg.isEmpty else { return }
        iMessageManager.sendMessage(msg, to: payload.title)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            replyText = ""; isTextFieldFocused = false; notificationManager.dismissLatestNotification()
        }
    }

    private func standardActionButton(title: String, systemName: String, isPrimary: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemName)
                .font(.system(size: 13, weight: .medium))
                .padding(.horizontal, 12).padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .background(isPrimary ? Color.accentColor.opacity(0.8) : Color.primary.opacity(0.15))
        .foregroundStyle(isPrimary ? .white : .primary)
        .clipShape(Capsule())
    }
}

struct AudioMessageView: View {
    let attachment: MessageAttachment
    @Binding var playbackState: NotificationLiveActivityView.AudioPlaybackState
    private var buttonLabel: String { switch playbackState { case .idle: "Play Audio Message"; case .playing: "Playing..."; case .finished: "Playback Finished" } }
    private var buttonIcon: String { switch playbackState { case .idle: "play.circle.fill"; case .playing: "stop.circle.fill"; case .finished: "checkmark.circle.fill" } }
    var body: some View {
        Button(action: { if playbackState == .idle { iMessageActionManager.shared.playAudio(at: attachment.localURL); playbackState = .playing } }) {
            HStack {
                Image(systemName: buttonIcon).font(.title2).symbolRenderingMode(.palette).foregroundStyle(.white, Color.accentColor).contentTransition(.symbolEffect(.replace))
                Text(buttonLabel).font(.headline).fontWeight(.medium).foregroundStyle(.primary).contentTransition(.interpolate)
            }
            .padding(.horizontal, 16).frame(height: 50).frame(maxWidth: .infinity).background(.regularMaterial).clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain).disabled(playbackState != .idle).animation(.spring, value: playbackState)
    }
}

// MARK: - Lock Screen Auth Activity
private struct AnimatedLockIcon: View {
    @EnvironmentObject var lockScreenState: LockScreenState

    private var lockTint: Color {
        if lockScreenState.isUnlocked { return .white.opacity(0.8) }
        if lockScreenState.faceIDAwaitingConfirmation { return .green }
        if lockScreenState.faceIDRequiresPassword { return .orange }
        return .white.opacity(0.8)
    }

    private var looksOpen: Bool {
        lockScreenState.isUnlocked || lockScreenState.faceIDAwaitingConfirmation
    }

    var body: some View {
        Image(systemName: looksOpen ? "lock.open.fill" : "lock.fill")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(lockTint)
            .contentTransition(.symbolEffect(.replace.downUp.byLayer))
            .animation(.easeInOut(duration: 0.3), value: lockScreenState.faceIDRequiresPassword)
            .animation(.easeInOut(duration: 0.3), value: lockScreenState.faceIDAwaitingConfirmation)
            .help(lockScreenState.faceIDRequiresPassword ? "Face ID locked — unlock with your password" : "")
    }
}

private struct LockScreenStatusIndicatorView: View {
    @EnvironmentObject var lockScreenState: LockScreenState

    var body: some View {
        let state = lockScreenState
        ZStack {
            if state.isUnlocked {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.green)
                    .transition(.opacity.combined(with: .scale))
            } else {
                HStack(spacing: 8) {
                    if state.isCaffeineActive {
                        Image(systemName: "cup.and.heat.waves.fill")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.white.opacity(0.7))
                            .transition(.opacity)
                    }

                    else if state.faceIDAwaitingConfirmation {
                        // Recognized; a key press unlocks.
                        Image(systemName: "return")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.green)
                            .transition(.opacity.combined(with: .scale))
                            .help("Face recognized. Press Return or any key to unlock.")
                    }

                    else if state.isAuthenticating, !state.faceIDRequiresPassword {
                        if state.isFaceIDEnabled {
                            Image(systemName: "faceid")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(.green)
                                .transition(.opacity)
                        }
                        else if state.isBluetoothUnlockEnabled {
                            Image(systemName: "key.sensor.tag.radiowaves.left.and.right.fill")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(.white.opacity(0.7))
                                .transition(.opacity)
                        }
                    }
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.4), value: state.isUnlocked)
        .animation(.easeInOut(duration: 0.3), value: state.faceIDRequiresPassword)
        .animation(.easeInOut(duration: 0.3), value: state.faceIDAwaitingConfirmation)
    }
}

struct LockScreenLiveActivityView {
    static func left() -> some View {
        AnimatedLockIcon()
    }

    static func right() -> some View {
        LockScreenStatusIndicatorView()
    }
}

private let capsLockBlue = NSColor(srgbRed: 0.36, green: 0.64, blue: 1.0, alpha: 1)

private struct CapsLockAnimationView: View {
    /// Target state: caps on = locked, caps off = unlocked.
    let isOn: Bool
    @State private var isLocked: Bool

    init(isOn: Bool) {
        self.isOn = isOn
        // Start from the opposite state so the transition reads as locking/unlocking.
        _isLocked = State(initialValue: !isOn)
    }

    var body: some View {
        CapsLockSymbolView(isLocked: isLocked)
            .task(id: isOn) {
                // onAppear fires before the notch finishes expanding, so the transition
                // would run off-screen; wait until the island is visible.
                try? await Task.sleep(for: .milliseconds(260))
                isLocked = isOn
            }
    }
}

/// Hosts the layer-drawn padlock; nothing here lays out or draws per frame.
private struct CapsLockSymbolView: NSViewRepresentable {
    let isLocked: Bool

    final class Container: NSView {
        let glyph: LockGlyphLayer

        init(isLocked: Bool) {
            glyph = LockGlyphLayer(isLocked: isLocked)
            super.init(frame: CGRect(origin: .zero, size: LockGlyphLayer.glyphSize))
            wantsLayer = true
            layer?.addSublayer(glyph)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override var intrinsicContentSize: NSSize { LockGlyphLayer.glyphSize }

        override func layout() {
            super.layout()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            glyph.position = CGPoint(x: LockGlyphLayer.glyphSize.width / 2, y: bounds.midY)
            CATransaction.commit()
        }
    }

    func makeNSView(context: Context) -> Container {
        Container(isLocked: isLocked)
    }

    func updateNSView(_ view: Container, context: Context) {
        view.glyph.setLocked(isLocked)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: Container, context: Context) -> CGSize? {
        LockGlyphLayer.glyphSize
    }
}

/// Padlock glyph drawn with plain layers so locking and unlocking animate on the render
/// server. The SF Symbols Magic Replace it stands in for is rendered in-process (RenderBox
/// and Metal at display rate for ~0.6 s), which was most of the CPU cost of a Caps Lock
/// toggle. The closed shackle is cut out of `lock.fill` and swung about its fixed leg, the
/// way a real shackle turns, then seats onto the `lock.open.fill` artwork.
private final class LockGlyphLayer: CALayer {
    private struct Art {
        let size: CGSize
        let closedBody: (image: CGImage, frame: CGRect)
        let openBody: (image: CGImage, frame: CGRect)
        let closedShackle: (image: CGImage, frame: CGRect)
        let openShackle: (image: CGImage, frame: CGRect)
        /// The tip of the open shackle's free leg, which hangs below the top of the body.
        let openTail: (image: CGImage, frame: CGRect)?
        let pivotLeg: (image: CGImage, frame: CGRect)?
        let pivotX: CGFloat
    }

    static let glyphSize: CGSize = art?.size ?? CGSize(width: 20, height: 18)

    private static let art: Art? = {
        let configuration = NSImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        guard let closed = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: nil)?.withSymbolConfiguration(configuration),
              let open = NSImage(systemSymbolName: "lock.open.fill", accessibilityDescription: nil)?.withSymbolConfiguration(configuration)
        else { return nil }
        // Both glyphs share one box so the pill never resizes; the body stays at the
        // leading edge and the open shackle swings into the spare width.
        let size = CGSize(width: ceil(max(closed.size.width, open.size.width)), height: ceil(max(closed.size.height, open.size.height)))
        let scale = max(2, NSScreen.screens.map(\.backingScaleFactor).max() ?? 2)
        let width = Int(size.width * scale), height = Int(size.height * scale)

        func raster(_ image: NSImage) -> (CGImage, [UInt8])? {
            var data = [UInt8](repeating: 0, count: width * height * 4)
            let made: CGImage? = data.withUnsafeMutableBytes { buffer in
                guard let context = CGContext(
                    data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                ) else { return nil }
                context.scaleBy(x: scale, y: scale)
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
                image.draw(in: CGRect(x: 0, y: (size.height - image.size.height) / 2, width: image.size.width, height: image.size.height))
                NSGraphicsContext.restoreGraphicsState()
                return context.makeImage()
            }
            guard let made else { return nil }
            return (made, (0..<(width * height)).map { data[$0 * 4 + 3] })
        }
        guard let (closedImage, closedAlpha) = raster(closed), let (openImage, _) = raster(open) else { return nil }

        // Opaque runs of one pixel row of the closed glyph (row 0 is the top).
        func runs(_ row: Int) -> [Range<Int>] {
            var found: [Range<Int>] = []
            var start: Int?
            for x in 0...width {
                let solid = x < width && closedAlpha[row * width + x] > 96
                if solid, start == nil { start = x }
                if !solid, let begin = start { found.append(begin..<x); start = nil }
            }
            return found
        }
        let rowRuns = (0..<height).map(runs)
        let widest = rowRuns.map { $0.map(\.count).max() ?? 0 }.max() ?? 0
        // The body starts at the first row that is one run nearly as wide as the glyph.
        guard widest > 0,
              let bodyTop = rowRuns.firstIndex(where: { $0.count == 1 && $0[0].count * 10 >= widest * 8 }),
              bodyTop > 0, bodyTop < height
        else { return nil }
        // Rows where the shackle is two separate legs; the right one is the hinge.
        let legRows = (0..<bodyTop).filter { rowRuns[$0].count == 2 }
        guard let legTop = legRows.first, let hinge = rowRuns[bodyTop - 1].last ?? rowRuns[legTop].last else { return nil }
        let pivotColumn = (hinge.lowerBound + hinge.upperBound) / 2

        func piece(_ image: CGImage, columns: Range<Int>, rows: Range<Int>) -> (image: CGImage, frame: CGRect)? {
            let pixels = CGRect(x: columns.lowerBound, y: rows.lowerBound, width: columns.count, height: rows.count)
            guard let cropped = image.cropping(to: pixels) else { return nil }
            let frame = CGRect(
                x: CGFloat(columns.lowerBound) / scale, y: CGFloat(height - rows.upperBound) / scale,
                width: CGFloat(columns.count) / scale, height: CGFloat(rows.count) / scale
            )
            return (cropped, frame)
        }
        // The open body is a hair wider than the closed one; past that is the free leg's tip.
        let bodyEnd = min(width, rowRuns[bodyTop][0].upperBound + Int(scale))
        guard let closedBody = piece(closedImage, columns: 0..<width, rows: bodyTop..<height),
              let openBody = piece(openImage, columns: 0..<bodyEnd, rows: bodyTop..<height),
              let closedShackle = piece(closedImage, columns: 0..<width, rows: 0..<bodyTop),
              let openShackle = piece(openImage, columns: 0..<width, rows: 0..<bodyTop)
        else { return nil }
        let margin = 1
        let legColumns = max(0, hinge.lowerBound - margin)..<min(width, hinge.upperBound + margin)
        return Art(
            size: size, closedBody: closedBody, openBody: openBody, closedShackle: closedShackle, openShackle: openShackle,
            openTail: bodyEnd < width ? piece(openImage, columns: bodyEnd..<width, rows: bodyTop..<height) : nil,
            pivotLeg: piece(closedImage, columns: legColumns, rows: legTop..<bodyTop),
            pivotX: CGFloat(pivotColumn) / scale
        )
    }()

    static let restingColor = NSColor.white.withAlphaComponent(0.85).cgColor
    static let lockedColor = capsLockBlue.cgColor
    static let swingDuration: CFTimeInterval = 0.42

    private let glyph = CALayer()
    private let closedBody = CALayer()
    private let openBody = CALayer()
    private let openGroup = CALayer()
    private let swingGroup = CALayer()
    private let swing = CALayer()
    private(set) var isLocked = false

    init(isLocked: Bool) {
        super.init()
        build()
        apply(isLocked: isLocked)
    }

    override init(layer: Any) { super.init(layer: layer) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func build() {
        let bounds = CGRect(origin: .zero, size: Self.glyphSize)
        frame = bounds
        glyph.frame = bounds
        swingGroup.frame = bounds
        openGroup.frame = bounds
        guard let art = Self.art else { return }
        func set(_ layer: CALayer, _ part: (image: CGImage, frame: CGRect)) {
            layer.contents = part.image
            layer.contentsGravity = .resize
            layer.frame = part.frame
        }
        set(closedBody, art.closedBody)
        set(openBody, art.openBody)
        for part in [art.openShackle, art.openTail].compactMap({ $0 }) {
            let layer = CALayer()
            set(layer, part)
            openGroup.addSublayer(layer)
        }
        // Anchor the swinging shackle on its hinge leg so scaling x turns it about that leg.
        swing.contents = art.closedShackle.image
        swing.contentsGravity = .resize
        swing.bounds = CGRect(origin: .zero, size: art.closedShackle.frame.size)
        swing.anchorPoint = CGPoint(x: (art.pivotX - art.closedShackle.frame.minX) / art.closedShackle.frame.width, y: 0.5)
        swing.position = CGPoint(x: art.pivotX, y: art.closedShackle.frame.midY)
        swingGroup.addSublayer(swing)
        if let leg = art.pivotLeg {
            // The hinge leg itself stays solid while the rest of the shackle turns edge-on.
            let legLayer = CALayer()
            set(legLayer, leg)
            swingGroup.addSublayer(legLayer)
        }
        for layer in [closedBody, openBody, openGroup, swingGroup] { glyph.addSublayer(layer) }
        mask = glyph
    }

    /// Sets the resting look for `isLocked` with no animation.
    func apply(isLocked: Bool) {
        self.isLocked = isLocked
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for layer in [self, closedBody, openBody, openGroup, swingGroup, swing] { layer.removeAllAnimations() }
        setResting(isLocked: isLocked)
        CATransaction.commit()
    }

    private func setResting(isLocked: Bool) {
        backgroundColor = isLocked ? Self.lockedColor : Self.restingColor
        closedBody.opacity = isLocked ? 1 : 0
        openBody.opacity = isLocked ? 0 : 1
        openGroup.opacity = isLocked ? 0 : 1
        swingGroup.opacity = isLocked ? 1 : 0
        swing.setValue(isLocked ? 1 : -1, forKeyPath: "transform.scale.x")
    }

    /// The swing's turn about the hinge at `progress` 0...1 of an unlock, as an x scale.
    static func swingScale(at progress: Double) -> Double {
        let eased = progress * progress * (3 - 2 * progress)
        return cos(eased * .pi)
    }

    /// How much of the swung closed shackle (versus the open artwork) shows at `progress` of an unlock.
    static func swingPresence(at progress: Double) -> Double {
        let t = min(1, max(0, (progress - 0.68) / 0.32))
        return 1 - t * t * (3 - 2 * t)
    }

    /// Animates to `isLocked`; the tint follows as the shackle seats (locking) or lifts (unlocking).
    func setLocked(_ isLocked: Bool) {
        guard isLocked != self.isLocked else { return }
        self.isLocked = isLocked
        let shownColor = presentation()?.backgroundColor ?? backgroundColor
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        setResting(isLocked: isLocked)

        let steps = 28
        // Unlocking runs progress 0 -> 1; locking plays the same motion backwards.
        let progress = (0...steps).map { index -> Double in
            let t = Double(index) / Double(steps)
            return isLocked ? 1 - t : t
        }
        func keyframes(_ keyPath: String, _ values: [Double]) -> CAKeyframeAnimation {
            let animation = CAKeyframeAnimation(keyPath: keyPath)
            animation.values = values
            animation.calculationMode = .linear
            animation.duration = Self.swingDuration
            return animation
        }
        let presence = progress.map(Self.swingPresence)
        swing.add(keyframes("transform.scale.x", progress.map(Self.swingScale)), forKey: "lock.swing")
        swingGroup.add(keyframes("opacity", presence), forKey: "lock.presence")
        openGroup.add(keyframes("opacity", presence.map { 1 - $0 }), forKey: "lock.presence")
        // The bodies are near identical; the one being left fades under the one arriving.
        let leaving = isLocked ? openBody : closedBody
        leaving.add(keyframes("opacity", (0...steps).map { 1 - Double($0) / Double(steps) }), forKey: "lock.body")

        let tint = CABasicAnimation(keyPath: "backgroundColor")
        tint.fromValue = shownColor
        tint.toValue = backgroundColor
        // Locking: blue arrives as the shackle seats. Unlocking: blue leaves as it lifts.
        tint.beginTime = CACurrentMediaTime() + (isLocked ? 0.12 : 0)
        tint.duration = isLocked ? 0.32 : 0.24
        tint.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        tint.fillMode = .backwards
        add(tint, forKey: "lock.tint")
        CATransaction.commit()
    }
}

struct NotchSymbolView: NSViewRepresentable {
    let systemName: String
    let pointSize: CGFloat
    var weight: NSFont.Weight = .regular
    var color: NSColor = .white
    var replacesAnimated = false
    var variableColor = false

    final class Coordinator {
        var systemName = ""
        var variableColor = false
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSImageView {
        let view = NSImageView()
        view.imageScaling = .scaleNone
        view.setContentCompressionResistancePriority(.required, for: .horizontal)
        view.setContentCompressionResistancePriority(.required, for: .vertical)
        view.contentTintColor = color
        view.image = image(named: systemName)
        context.coordinator.systemName = systemName
        if variableColor {
            view.addSymbolEffect(.variableColor.iterative, options: .repeating)
            context.coordinator.variableColor = true
        }
        return view
    }

    func updateNSView(_ view: NSImageView, context: Context) {
        if view.contentTintColor != color { view.contentTintColor = color }
        let coordinator = context.coordinator
        if coordinator.systemName != systemName, let image = image(named: systemName) {
            coordinator.systemName = systemName
            if replacesAnimated {
                view.setSymbolImage(image, contentTransition: .replace.downUp.byLayer)
            } else {
                view.image = image
            }
        }
        if coordinator.variableColor != variableColor {
            coordinator.variableColor = variableColor
            if variableColor {
                view.addSymbolEffect(.variableColor.iterative, options: .repeating)
            } else {
                view.removeAllSymbolEffects()
            }
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSImageView, context: Context) -> CGSize? {
        nsView.intrinsicContentSize
    }

    private func image(named name: String) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight))
    }
}

struct CapsLockLiveActivityView {
    static func left(isOn: Bool) -> some View {
        CapsLockAnimationView(isOn: isOn)
    }

    static func right(isOn: Bool) -> some View {
        Image(systemName: isOn ? "capslock.fill" : "capslock")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(isOn ? Color(nsColor: capsLockBlue) : .white.opacity(0.6))
    }
}

/// Shown while a window is dragged and Snap Zones only open from the notch.
struct SnapDragHintActivityView {
    static func left() -> some View {
        SnapDragHintGlyph()
    }

    static func right() -> some View {
        Text("Drag up to snap")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.white.opacity(0.62))
            .lineLimit(1)
    }
}

/// A window outline easing up into a notch pill.
private struct SnapDragHintGlyph: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .top) {
            Capsule()
                .fill(.white.opacity(0.9))
                .frame(width: 10, height: 3)
            if reduceMotion {
                window.offset(y: 6)
            } else {
                window.phaseAnimator([false, true]) { view, raised in
                    view
                        .offset(y: raised ? 5 : 10)
                        .opacity(raised ? 1 : 0.55)
                } animation: { raised in
                    raised ? .easeOut(duration: 0.7) : .easeIn(duration: 0.5).delay(0.35)
                }
            }
        }
        .frame(width: 18, height: 20, alignment: .top)
        .accessibilityHidden(true)
    }

    private var window: some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .strokeBorder(.white.opacity(0.85), lineWidth: 1.3)
            .frame(width: 14, height: 9)
    }
}

struct PowerStateActivityView {
    static func left(for state: BatterySystemState) -> some View {
        let iconName: String
        let color: Color
        switch state.managementState {
        case .sailing:
            iconName = "sailboat.fill"
            color = .cyan
        case .heatProtection:
            iconName = "thermometer.sun.fill"
            color = .orange
        case .discharging:
            iconName = "arrow.down.to.line.compact"
            color = .yellow
        default:
            iconName = "info.circle.fill"
            color = .secondary
        }
        return Image(systemName: iconName)
            .font(.system(size: 18, weight: .semibold))
            .foregroundColor(color)
            .symbolRenderingMode(.hierarchical)
    }

    static func right(for state: BatterySystemState, batteryLevel: Int) -> some View {
        HStack(spacing: 6) {
            Text(state.managementState.displayName)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)

            HStack(spacing: 2) {
                Image(systemName: "battery.100")
                    .font(.caption)
                Text("\(batteryLevel)%")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
            }
        }
        .foregroundColor(.white.opacity(0.9))
    }
}

struct CalibrationActivityView: View {
    @Environment(\.notchBandHeight) private var notchBandHeight
    @EnvironmentObject var calibrationManager: CalibrationManager
    @Environment(LiveActivityManager.self) var liveActivityManager
    @State private var isShowing = false

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "battery.100.bolt")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.cyan)

                Text("Battery Calibration")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
            }

            Text(calibrationManager.state.description)
                .font(.callout)
                .foregroundColor(.secondary)
                .contentTransition(.interpolate)
                .animation(.easeInOut, value: calibrationManager.state)

            ProgressView(value: calibrationManager.progress)
                .progressViewStyle(LinearProgressViewStyle(tint: .cyan))
                .padding(.horizontal)
                .animation(.easeInOut, value: calibrationManager.progress)

            Button(action: {
                calibrationManager.cancel()
                liveActivityManager.dismissCurrentActivity()
            }) {
                Text("Cancel")
                    .font(.subheadline.weight(.semibold))
                    .padding(.vertical, 8)
                    .padding(.horizontal, 16)
                    .background(.white.opacity(0.1))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 15)
        .padding(.horizontal, 25)
        .padding(.top, notchBandHeight)
        .frame(width: 380)
        .scaleEffect(isShowing ? 1 : 0.95)
        .opacity(isShowing ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.75, blendDuration: 0.2)) {
                isShowing = true
            }
        }
    }
}

// MARK: - OTP / Parcel smart inbox live activities

struct OTPLiveActivityView: View {
    @Environment(\.notchBandHeight) private var notchBandHeight
    let event: OTPEvent
    var fromNotification: Bool = false

    @ObservedSettings var settings: SettingsObserver
    @Environment(LiveActivityManager.self) var liveActivityManager
    @State private var didCopy = false
    @State private var isShowing = false

    private var seedColor: Color { Color(red: 0.22, green: 0.68, blue: 0.58) }

    private var digits: [String] {
        Array(event.code).map(String.init)
    }

    private var cellWidth: CGFloat {
        let available: CGFloat = 300
        let spacing: CGFloat = 8
        let totalSpacing = spacing * CGFloat(max(digits.count - 1, 0))
        return min(44, max(30, (available - totalSpacing) / CGFloat(digits.count)))
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(seedColor.opacity(0.2))
                        .frame(width: 34, height: 34)
                    Image(systemName: "key.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(seedColor)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text("Verification code")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                    Text(event.title.isEmpty ? event.source : event.title)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Button {
                    liveActivityManager.dismissCurrentActivity()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 26, height: 26)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .roundedCard(fill: Color.white.opacity(0.06), cornerRadius: 16, stroke: Color.white.opacity(0.06))

            HStack(spacing: 8) {
                ForEach(Array(digits.enumerated()), id: \.offset) { _, digit in
                    Text(digit)
                        .font(.system(size: 26, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .frame(width: cellWidth, height: 52)
                        .background(
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .fill(seedColor)
                        )
                }
            }
            .scaleEffect(isShowing ? 1 : 0.85)
            .opacity(isShowing ? 1 : 0)

            if settings.settings.showCopyButtonForVerificationCodes {
                Button {
                    NSPasteboard.general.copyString(event.code)
                    withAnimation(.spring) { didCopy = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                        SmartInboxMonitor.shared.dismissOTP()
                        liveActivityManager.dismissCurrentActivity()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                        Text(didCopy ? "Copied" : "Copy code")
                    }
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                }
                .buttonStyle(.plain)
                .background(didCopy ? seedColor.opacity(0.35) : Color.white.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(didCopy ? seedColor.opacity(0.5) : Color.white.opacity(0.08), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .padding(.top, notchBandHeight)
        .frame(minWidth: 340, maxWidth: 400)
        .onAppear {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.72, blendDuration: 0.25)) {
                isShowing = true
            }
            if settings.settings.autoCopyVerificationCodes {
                NSPasteboard.general.copyString(event.code)
                didCopy = true
            }
        }
    }
}

struct ParcelLiveActivityView: View {
    @Environment(\.notchBandHeight) private var notchBandHeight
    let parcel: ParcelShipment

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(parcel.carrier.displayName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(parcel.title)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                }
                Spacer()
                Text(parcel.status)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(parcel.isDelivered ? .green : .primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.primary.opacity(0.1))
                    .clipShape(Capsule())
            }

            HStack {
                Text(parcel.trackingNumber)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                if let url = parcel.trackingURL {
                    Button("Track") {
                        NSWorkspace.shared.open(url)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Color.orange.opacity(0.2))
                    .clipShape(Capsule())
                }
            }

            if !parcel.detail.isEmpty {
                Text(parcel.detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .padding(.top, notchBandHeight)
        .frame(minWidth: 340, maxWidth: 440)
    }
}