//
//  LiveActivityComponents.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-07-06.
//
//

import SwiftUI
import EventKit

struct PersistentBatteryActivityView {
    static func left(for state: BatteryState, timeRemaining: String?) -> some View {
        Group {
            if let timeString = timeRemaining, !timeString.isEmpty {
                Text(timeString)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.8))
                    .transition(.opacity.animation(.easeInOut))
            }
            else if state.isPluggedIn {
                Image(systemName: "bolt")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white.opacity(0.7))
            }
            else if state.isPluggedIn {
                Image(systemName: "powerplug")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white.opacity(0.7))
            } else {
                Image(systemName: "info.triangle")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white.opacity(0.7))

            }
        }
    }

    static func right(for state: BatteryState) -> some View {
        HStack(spacing: 6) {
            FilledBatteryIcon(level: state.level, isCharging: state.isCharging, isPluggedIn: state.isPluggedIn, isLowBattery: state.isLow)
            Text("\(state.level)%")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
        }
    }
}

struct FileProgressLiveActivityView {

    static func left(for task: FileTask) -> some View {
        let iconName: String
        switch task {
        case .universalTransfer(let transfer):
            iconName = transfer.sourceType == .finder ? "arrow.right.arrow.left.circle.fill" : "arrow.down.circle.fill"
        case .airDrop: iconName = "airplayaudio"
        case .incomingTransfer: iconName = "arrow.down.circle.fill"
        case .fileConversion: iconName = "arrow.triangle.2.circlepath"
        case .local: iconName = "doc.fill"
        }

        return ZStack {
            Image(systemName: iconName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
        }
        .frame(width: 20, height: 20)
    }

    static func right(for task: FileTask) -> some View {
        let progress: Double?
        let fileName: String
        let statusText: String

        switch task {
        case .universalTransfer(let transferTask):
            progress = transferTask.progress
            fileName = transferTask.fileName
            if transferTask.sourceType == .finder {
                statusText = transferTask.speed > 0 ? formatSpeed(transferTask.speed) : "Copying..."
            } else {
                statusText = transferTask.speed > 0 ? formatSpeed(transferTask.speed) : "Downloading..."
            }
            print("[LiveActivityView] Rendering Universal Transfer: '\(transferTask.fileName)', Progress: \(progress?.description ?? "nil"), Source: \(transferTask.sourceType)")

        case .airDrop(let airDropTask):
            progress = airDropTask.progress
            fileName = airDropTask.fileName
            statusText = airDropTask.isComplete ? "Complete" : "Receiving..."
        case .incomingTransfer(let info):
            progress = info.progress
            fileName = info.fileDescription
            statusText = "Receiving..."
        case .fileConversion(let task):
            progress = task.progress
            fileName = task.fileName
            statusText = "Converting..."
        case .local(let item):
            progress = 1.0
            fileName = item.fileName
            statusText = "Ready"
        }

        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(fileName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)

                Text(statusText)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.7))
                    .lineLimit(1)
            }

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

    private static func formatSpeed(_ bytesPerSecond: Double) -> String {
        if bytesPerSecond >= 1_000_000 {
            return String(format: "%.1f MB/s", bytesPerSecond / 1_000_000)
        } else if bytesPerSecond >= 1_000 {
            return String(format: "%.1f KB/s", bytesPerSecond / 1_000)
        } else {
            return String(format: "%.0f B/s", bytesPerSecond)
        }
    }
}

struct FileCircularProgressIndicator: View {
    let progress: Double
    let size: CGFloat
    let lineWidth: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .stroke(lineWidth: lineWidth)
                .foregroundColor(.accentColor)
                .opacity(0.3)

            Circle()
                .trim(from: 0.0, to: min(progress, 1.0))
                .stroke(style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                .foregroundColor(.accentColor)
                .rotationEffect(Angle(degrees: 270.0))
        }
        .frame(width: size, height: size)
        .animation(.linear(duration: 0.2), value: progress)
    }
}

struct AlbumArtView: View {
    @EnvironmentObject var musicWidget: MusicManager

    var body: some View {
        Group {
            if let artwork = musicWidget.artwork {
                Image(nsImage: artwork)
                    .resizable()
            } else {
                Image(systemName: "music.note")
                    .foregroundColor(.white.opacity(0.8))
            }
        }
        .aspectRatio(contentMode: .fill)
        .frame(width: 20, height: 20)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .id(musicWidget.artwork?.hash)
        .onHover { isHovering in
            musicWidget.isHoveringAlbumArt = isHovering
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

struct MusicLyricsView: View {
    @EnvironmentObject var musicWidget: MusicManager
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
    static func left(for state: BatteryState) -> some View {
        let iconName = state.isLow ? "battery.25" : (state.isCharging ? "bolt.fill" : "powerplug.fill")
        let iconColor = state.isLow ? Color.red : (state.isCharging ? .green : .white.opacity(0.9))

        return Image(systemName: iconName)
            .frame(width: 20, height: 20)
            .foregroundColor(iconColor)
    }

    static func right(for state: BatteryState) -> some View {
        Text("\(state.level)%")
            .font(.system(size: 13, weight: .semibold))
    }
}

struct DefaultBatteryActivityView {
    static func left(for state: BatteryState) -> some View {
        let iconName: String
        let text: String
        let color: Color

        if state.isCharging {
            iconName = "bolt.fill"
            text = "Charging"
            color = .green
        } else if state.isPluggedIn {
            iconName = "powerplug.fill"
            text = "Plugged In"
            color = .white.opacity(0.8)
        } else if state.isLow {
            iconName = "battery.25"
            text = "Low Battery"
            color = .red
        } else {
            return AnyView(EmptyView())
        }

        return AnyView(
            HStack(spacing: 6) {
                Image(systemName: iconName)
                Text(text)
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(color)
        )
    }

    static func right(for state: BatteryState, timeRemaining: String?) -> some View {
        HStack(spacing: 6) {
            if SettingsModel.shared.settings.showEstimatedBatteryTime, let timeString = timeRemaining, !timeString.isEmpty {
                 Text(timeString)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.8))
                    .transition(.opacity)
            }
            FilledBatteryIcon(level: state.level, isCharging: state.isCharging, isPluggedIn: state.isPluggedIn, isLowBattery: state.isLow )
            Text("\(state.level)%")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
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
            Text(formatRemainingTime(remaining))
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundColor(.white.opacity(0.9))
        }
    }

    private static func formatRemainingTime(_ interval: TimeInterval) -> String {
        if interval <= 0 { return "Now" }
        let minutes = Int(interval) / 60
        let seconds = Int(interval) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

struct FilledBatteryIcon: View {
    let level: Int
    let isCharging: Bool
    let isPluggedIn: Bool
    let isLowBattery: Bool

    private let iconSize: CGFloat = 24
    private let iconWeight: Font.Weight = .light

    private var batteryColor: Color {
        if level <= 20 {
            return .red
        }
        return isCharging ? .green : .white
    }

    var body: some View {
        ZStack(alignment: .center) {
            Image(systemName: "battery.100")
                .font(.system(size: iconSize, weight: iconWeight))
                .foregroundColor(isLowBattery ? .red : .white.opacity(0.4))

            GeometryReader { geo in
                let fillWidth = (geo.size.width - 5.5) * (CGFloat(level) / 100.0)

                Rectangle()
                    .fill(batteryColor)
                    .frame(width: fillWidth)
                    .offset(x: 2.75)
            }
            .padding(.vertical, 2.5)
            .mask {
                Image(systemName: "battery.100")
                    .font(.system(size: iconSize, weight: iconWeight))
            }

            if isCharging || isPluggedIn {
                let iconName = isCharging ? "bolt.fill" : "powerplug.fill"

                Image(systemName: iconName)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.black)
                    .transition(.opacity.combined(with: .scale))
            }
        }
        .frame(width: iconSize + 4, height: iconSize / 2)
        .animation(.easeInOut(duration: 0.3), value: level)
        .animation(.easeInOut(duration: 0.3), value: isCharging)
        .animation(.easeInOut(duration: 0.3), value: isPluggedIn)
    }
}

struct BatteryRingView: View {
    let level: Int

    private var color: Color {
        if level <= 10 { return .red }
        if level <= 25 { return .yellow }
        return .green
    }

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.2), lineWidth: 4)
            Circle()
                .trim(from: 0, to: CGFloat(level) / 100.0)
                .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut, value: level)
        }
        .frame(width: 15, height: 15)
    }
}

struct BluetoothConnectedPeripheralView {
    static func left(for device: BluetoothDeviceState) -> some View {
        Image(systemName: device.iconName)
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
        Image(systemName: device.iconName)
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
        Image(systemName: device.iconName)
            .font(.system(size: 18, weight: .semibold))
            .foregroundColor(.white.opacity(0.5))
            .symbolRenderingMode(.hierarchical)
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.red)
                    .symbolRenderingMode(.hierarchical)
                    .padding(2)
            }
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
        Image(systemName: device.iconName)
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
            Text(formatRemainingTime(remaining))
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundColor(.white.opacity(0.9))
        }
    }

    private static func formatRemainingTime(_ interval: TimeInterval) -> String {
        if interval <= 0 { return "Now" }
        let minutes = Int(interval) / 60
        let seconds = Int(interval) % 60
        return String(format: "%02d:%02d", minutes, seconds)
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
    @EnvironmentObject var eyeBreakManager: EyeBreakManager
    @EnvironmentObject var settings: SettingsModel

    @State private var isShowing = false
    @State private var skipHovered = false
    @State private var doneHovered = false

    private var breakDuration: TimeInterval {
        TimeInterval(settings.settings.eyeBreakBreakDuration)
    }

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.15), lineWidth: 6)

                Circle()
                    .trim(from: 0, to: 1 - (eyeBreakManager.timeRemainingInBreak / breakDuration))
                    .stroke(Color.cyan, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
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

                    Text("Focus 20ft away.")
                        .font(.callout)
                        .foregroundColor(.secondary)
                }

                HStack(spacing: 12) {
                    Button {
                        withAnimation {
                            eyeBreakManager.dismissBreak()
                        }
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
                        withAnimation {
                            eyeBreakManager.completeBreak()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text("Done")
                            Text(String(format: "(%02d)", Int(eyeBreakManager.timeRemainingInBreak)))
                                .font(.system(.body, design: .monospaced))
                                .contentTransition(.numericText(countsDown: true))
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
        .padding(.top, NotchConfiguration.universalHeight)
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
            .shadow(color: isProminent && (isHovered || configuration.isPressed) ? .cyan.opacity(0.2) : .clear,
                    radius: 4, x: 0, y: 0)
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
            text = "Off" // Always show "Off" when inactive
        } else {
            switch displayMode {
            case .full:
                text = mode.name
            case .compact:
                text = "On"
            }
        }

        return Text(text)
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(.white.opacity(mode.isActive ? 0.9 : 0.7)) // Dim the text when off
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
        Text(formatTime(timerManager.displayTime))
            .font(.system(size: 13, design: .monospaced).weight(.semibold))
            .contentTransition(.numericText(countsDown: timerManager.activeTimer == .system))
            .animation(.default, value: timerManager.displayTime)
    }

    private static func formatTime(_ time: TimeInterval) -> String {
        let totalSeconds = Int(time)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
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
        @EnvironmentObject var settings: SettingsModel
        let data: ProcessedWeatherData

        var body: some View {
            let temp = settings.settings.weatherUseCelsius ? data.temperatureMetric : data.temperature
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
            .padding(.horizontal, 16).padding(.vertical, 8)
            .foregroundStyle(isPrimary ? .white : .primary.opacity(0.9))
            .clipShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.5), value: configuration.isPressed)
    }
}

struct NotificationLiveActivityView: View {
    let payload: NotificationPayload

    @EnvironmentObject var notificationManager: NotificationManager

    private let iMessageManager = iMessageActionManager.shared

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                if let icon = payload.appIcon {
                    Image(nsImage: icon)
                        .resizable().aspectRatio(contentMode: .fit)
                        .frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(payload.appName).font(.headline).fontWeight(.semibold)
                        Spacer()
                        Text("now").font(.caption).foregroundStyle(.secondary)
                    }
                    Text(payload.title).font(.subheadline).fontWeight(.bold).lineLimit(1)
                    Text(payload.body).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)

            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    Button("Dismiss") {
                        notificationManager.dismissLatestNotification()
                    }
                    .buttonStyle(ModernNotificationButtonStyle())

                    if payload.appIdentifier == "com.apple.iChat" {
                        Button {
                            iMessageManager.markConversationAsRead(senderName: payload.title)
                            notificationManager.dismissLatestNotification()
                        } label: {
                            Label("Read", systemImage: "checkmark.circle")
                        }
                        .buttonStyle(ModernNotificationButtonStyle())
                    }
                }

                Spacer()

                contextualActionButton
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .padding(.top, NotchConfiguration.initialSize.height)
        .overlay(alignment: .top) {
            Color.clear.frame(width: NotchConfiguration.initialSize.width, height: NotchConfiguration.initialSize.height)
        }
        .frame(maxWidth: 420)
    }

    @ViewBuilder
    private var contextualActionButton: some View {
        if payload.appIdentifier == "com.apple.sharingd" {
            Button(action: {
                if let url = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first {
                    NSWorkspace.shared.open(url)
                }
                notificationManager.dismissLatestNotification()
            }) {
                Label("Show", systemImage: "folder.fill")
            }
            .buttonStyle(ModernNotificationButtonStyle(isPrimary: true))
        }
        else if payload.hasAudioAttachment {
            Button(action: {
                iMessageManager.playLatestAudioMessage()
                notificationManager.dismissLatestNotification()
            }) {
                Label("Play", systemImage: "play.fill")
            }
            .buttonStyle(ModernNotificationButtonStyle(isPrimary: true))
        }
        else if payload.appIdentifier == "com.apple.iChat" {
            Button(action: {
                iMessageManager.replyToLastMessage()
                notificationManager.dismissLatestNotification()
            }) {
                Label("Reply", systemImage: "arrowshape.turn.up.left.fill")
            }
            .buttonStyle(ModernNotificationButtonStyle(isPrimary: true))
        }
        else {
            Button(action: {
                NSWorkspace.shared.launchApplication(withBundleIdentifier: payload.appIdentifier, options: [], additionalEventParamDescriptor: nil, launchIdentifier: nil)
                notificationManager.dismissLatestNotification()
            }) {
                Label("Open", systemImage: "arrow.up.forward.app.fill")
            }
            .buttonStyle(ModernNotificationButtonStyle(isPrimary: true))
        }
    }
}

// MARK: - Lock Screen Auth Activity

private struct AnimatedLockIcon: View {
    @EnvironmentObject var lockScreenState: LockScreenState

    var body: some View {
        Image(systemName: lockScreenState.isUnlocked ? "lock.open.fill" : "lock.fill")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white.opacity(0.8))
            .contentTransition(.symbolEffect(.replace.downUp.byLayer))
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

                    else if state.isAuthenticating {
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