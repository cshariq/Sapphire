//
//  SystemHUD.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-07-06.
//
//

import SwiftUI
import AppKit
import Combine

fileprivate class Throttler {
    private let interval: TimeInterval
    private let queue: DispatchQueue
    private var isThrottling = false

    init(interval: TimeInterval, queue: DispatchQueue = .main) {
        self.interval = interval
        self.queue = queue
    }

    func throttle(_ block: @escaping () -> Void) {
        guard !isThrottling else { return }
        block()
        isThrottling = true
        queue.asyncAfter(deadline: .now() + interval) { [weak self] in
            self?.isThrottling = false
        }
    }
}

fileprivate func eventTapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard type.rawValue == NX_SYSDEFINED else {
        return Unmanaged.passRetained(event)
    }
    if SystemHUDManager.shared.handleMediaKeyEvent(event) {
        return nil
    }
    return Unmanaged.passRetained(event)
}

extension Notification.Name {
    static let mediaKeyPlayPausePressed = Notification.Name("mediaKeyPlayPausePressed")
    static let mediaKeyNextPressed = Notification.Name("mediaKeyNextPressed")
    static let mediaKeyPreviousPressed = Notification.Name("mediaKeyPreviousPressed")
}

enum HUDType: Hashable {
    case volume(level: Float, device: AudioDevice?)
    case brightness(level: Float)
    case keyboardBrightness(level: Float)
    case externalDeviceVolume(deviceName: String, deviceIcon: String, deviceVolume: Float, systemVolume: Float, isControllingExternal: Bool, canControlVolume: Bool)

    func hash(into hasher: inout Hasher) {
        hasher.combine(self.caseIdentifier)
        switch self {
        case .volume(let level, let device):
            hasher.combine(level)
            hasher.combine(device)
        case .brightness(let level):
            hasher.combine(level)
        case .keyboardBrightness(let level):
            hasher.combine(level)
        case .externalDeviceVolume(let deviceName, let deviceIcon, let deviceVolume, let systemVolume, let isControllingExternal, let canControlVolume):
            hasher.combine(deviceName)
            hasher.combine(deviceIcon)
            hasher.combine(deviceVolume)
            hasher.combine(systemVolume)
            hasher.combine(isControllingExternal)
            hasher.combine(canControlVolume)
        }
    }

    var caseIdentifier: CaseIdentifier {
        switch self {
        case .volume: return .volume
        case .brightness: return .brightness
        case .keyboardBrightness: return .keyboardBrightness
        case .externalDeviceVolume: return .externalDeviceVolume
        }
    }
    enum CaseIdentifier { case volume, brightness, keyboardBrightness, externalDeviceVolume }
}

private enum MediaKeyAction {
    case volumeUp, volumeDown
    case brightnessUp, brightnessDown
}

class SystemHUDManager: ObservableObject {
    static let shared = SystemHUDManager()

    @Published private(set) var currentHUD: HUDType?
    @Published private(set) var glowIntensity: Double = 0.0

    private let settings = SettingsModel.shared
    private let musicManager = MusicManager.shared

    private var eventTap: CFMachPort?
    private var hudDismissalTimer: Timer?

    private var keyRepeatTimer: Timer?
    private var currentAction: MediaKeyAction?
    private var isFineTuning: Bool = false
    private let keyRepeatDelay: TimeInterval = 0.25
    private let keyRepeatInterval: TimeInterval = 0.03

    private var wasControllingSystemVolume: Bool = true

    private let spotifyVolumeThrottler = Throttler(interval: 0.15)
    private var lastSpotifyVolume: Float?
    private var cachedSpotifyState: ActiveSpotifyDeviceState?

    private init() {
        setupEventTap()
    }

    private func setupEventTap() {
        let eventsToMonitor: CGEventMask = (1 << NX_SYSDEFINED)
        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventsToMonitor,
            callback: eventTapCallback,
            userInfo: nil
        )
        guard let eventTap = eventTap else {
             print("[SystemHUDManager] FATAL ERROR: Failed to create CGEvent tap. Check Accessibility Permissions.")
            return
        }
        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }

    fileprivate func handleMediaKeyEvent(_ cgEvent: CGEvent) -> Bool {
        guard let nsEvent = NSEvent(cgEvent: cgEvent),
              nsEvent.type == .systemDefined,
              nsEvent.subtype.rawValue == 8 else {
            return false
        }

        let keyCode = Int32((nsEvent.data1 & 0xFFFF0000) >> 16)
        let keyState = (nsEvent.data1 & 0xFF00) >> 8
        let isKeyDown = (keyState == 0x0A)
        let isKeyUp = (keyState == 0x0B)

        switch keyCode {
        case NX_KEYTYPE_PLAY, NX_KEYTYPE_FAST, NX_KEYTYPE_REWIND:
            return false
        default:
            break
        }

        let action: MediaKeyAction?
        switch keyCode {
        case NX_KEYTYPE_SOUND_UP: action = .volumeUp
        case NX_KEYTYPE_SOUND_DOWN: action = .volumeDown
        case NX_KEYTYPE_BRIGHTNESS_UP: action = .brightnessUp
        case NX_KEYTYPE_BRIGHTNESS_DOWN: action = .brightnessDown
        case NX_KEYTYPE_MUTE:
            if isKeyDown { DispatchQueue.main.async { self.handleMute() } }
            return true
        default:
            return false
        }

        guard let validAction = action else { return false }

        if isKeyDown {
            if self.currentAction == nil {
                Task {
                    await self.startContinuousChange(for: validAction, with: nsEvent.modifierFlags)
                }
            }
        } else if isKeyUp {
            if validAction == self.currentAction {
                self.stopContinuousChange()
            }
        }

        return true
    }

    @MainActor
    private func handleMute() {
        stopContinuousChange()
        let wasMuted = SystemControl.isMuted()
        SystemControl.setMuted(to: !wasMuted)

        let level = wasMuted ? SystemControl.getVolume() : 0.0
        let device = AudioDeviceManager().getCurrentOutputDevice()
        showHUD(for: .volume(level: level, device: device))
    }

    @MainActor
    private func startContinuousChange(for action: MediaKeyAction, with modifiers: NSEvent.ModifierFlags) async {
        currentAction = action
        isFineTuning = modifiers.contains([.shift, .option])

        if action == .volumeUp || action == .volumeDown {
            self.cachedSpotifyState = await musicManager.fetchActiveSpotifyDeviceState()
        }

        performChange()

        withAnimation(.spring()) {
             glowIntensity = 0.2
        }

        keyRepeatTimer?.invalidate()
        keyRepeatTimer = Timer.scheduledTimer(
            timeInterval: keyRepeatDelay,
            target: self,
            selector: #selector(startRepeatingChange),
            userInfo: nil,
            repeats: false
        )
    }

    @objc private func startRepeatingChange() {
        keyRepeatTimer?.invalidate()
        keyRepeatTimer = Timer.scheduledTimer(
            timeInterval: keyRepeatInterval,
            target: self,
            selector: #selector(performChangeWrapper),
            userInfo: nil,
            repeats: true
        )
    }

    @objc private func performChangeWrapper() {
        Task { @MainActor in
            performChange()
        }
    }

    private func stopContinuousChange() {
        keyRepeatTimer?.invalidate()
        keyRepeatTimer = nil

        if wasControllingSystemVolume && (currentAction == .volumeUp || currentAction == .volumeDown) && settings.settings.volumeHUDSoundEnabled {
             if let soundURL = Bundle.main.url(forResource: "Media Keys", withExtension: "aif") {
                 NSSound(contentsOf: soundURL, byReference: true)?.play()
             } else {
                 NSSound(named: "Tink")?.play()
             }
        }

        currentAction = nil

        if let finalVolume = lastSpotifyVolume {
            Task {
                _ = await musicManager.setSpotifyVolume(percent: Int(finalVolume * 100))
            }
        }

        lastSpotifyVolume = nil
        cachedSpotifyState = nil
        wasControllingSystemVolume = true

        withAnimation(.spring()) {
            glowIntensity = 0.0
        }
    }

    @MainActor
    private func performChange() {
        guard let action = currentAction else {
            stopContinuousChange()
            return
        }

        withAnimation(.spring()) {
            glowIntensity = min(1.0, glowIntensity + 0.05)
        }

        let direction: Float = (action == .volumeUp || action == .brightnessUp) ? 1.0 : -1.0

        switch action {
        case .volumeUp, .volumeDown:
            let percentageStep = Float(settings.settings.volumesliderstep)
            let coarseStep = (percentageStep / 100.0).clamped(to: 0.01...1.0)
            let fineStep: Float = 0.01

            let getNextLevel = { (currentLevel: Float) -> Float in
                if self.isFineTuning {
                    return (currentLevel + (fineStep * direction)).clamped(to: 0...1)
                } else {
                    let currentStepNum = round(currentLevel / coarseStep)
                    let nextStepNum = currentStepNum + direction
                    return (nextStepNum * coarseStep).clamped(to: 0...1)
                }
            }

            let isOptionPressed = NSEvent.modifierFlags.contains(.option)

            if settings.settings.showSpotifyVolumeHUD,
               let device = self.cachedSpotifyState,
               isOptionPressed && device.canControlVolume {

                self.wasControllingSystemVolume = false // *** FIX: Set flag
                let currentSpotifyVolume = self.lastSpotifyVolume ?? (Float(device.volumePercent ?? 75) / 100.0)
                let newSpotifyVolume = getNextLevel(currentSpotifyVolume)
                self.lastSpotifyVolume = newSpotifyVolume

                spotifyVolumeThrottler.throttle {
                    Task {
                        _ = await self.musicManager.setSpotifyVolume(percent: Int(newSpotifyVolume * 100))
                    }
                }

                let hud = HUDType.externalDeviceVolume(deviceName: device.name, deviceIcon: device.iconName, deviceVolume: newSpotifyVolume, systemVolume: SystemControl.getVolume(), isControllingExternal: true, canControlVolume: device.canControlVolume)
                showHUD(for: hud)

            } else {
                self.wasControllingSystemVolume = true // *** FIX: Set flag
                let newVolume = getNextLevel(SystemControl.getVolume())
                SystemControl.setVolume(to: newVolume)
                SystemControl.setMuted(to: false)

                if settings.settings.showSpotifyVolumeHUD, let device = self.cachedSpotifyState {
                     let hud = HUDType.externalDeviceVolume(deviceName: device.name, deviceIcon: device.iconName, deviceVolume: Float(device.volumePercent ?? 75) / 100.0, systemVolume: newVolume, isControllingExternal: false, canControlVolume: device.canControlVolume)
                    showHUD(for: hud)
                } else {
                    let audioDevice = AudioDeviceManager().getCurrentOutputDevice()
                    showHUD(for: .volume(level: newVolume, device: audioDevice))
                }
            }

        case .brightnessUp, .brightnessDown:
            let percentageStep = Float(settings.settings.brightnessliderstep)
            let coarseStep = (percentageStep / 100.0).clamped(to: 0.01...1.0)
            let fineStep: Float = 0.01

            let getNextLevel = { (currentLevel: Float) -> Float in
                if self.isFineTuning {
                    return (currentLevel + (fineStep * direction)).clamped(to: 0...1)
                } else {
                    let currentStepNum = round(currentLevel / coarseStep)
                    let nextStepNum = currentStepNum + direction
                    return (nextStepNum * coarseStep).clamped(to: 0...1)
                }
            }

            let currentModifiers = NSEvent.modifierFlags
            if currentModifiers.contains(.option) {
                let newLevel = getNextLevel(SystemControl.getKeyboardBrightness())
                SystemControl.setKeyboardBrightness(to: newLevel)
                showHUD(for: .keyboardBrightness(level: newLevel))
            } else {
                let newLevel = getNextLevel(SystemControl.getBrightness())
                SystemControl.setBrightness(to: newLevel)
                showHUD(for: .brightness(level: newLevel))
            }
        }
    }

    private func showHUD(for hudType: HUDType) {
        self.currentHUD = hudType
        hudDismissalTimer?.invalidate()
        hudDismissalTimer = Timer.scheduledTimer(withTimeInterval: settings.settings.hudDuration, repeats: false) { [weak self] _ in
            self?.currentHUD = nil
        }
    }
}

// MARK: - Redesigned HUD Views (No changes below this line)

struct SystemHUDView: View {
    let type: HUDType
    @EnvironmentObject var settings: SettingsModel

    var body: some View {
        VStack(spacing: 8) {
            switch type {
            case .volume(let level, let device):
                systemVolumeContent(level: level, device: device)
            case .brightness(let level):
                brightnessContent(level: level)
            case .keyboardBrightness(let level):
                keyboardBrightnessContent(level: level)
            case .externalDeviceVolume(let deviceName, let deviceIcon, let deviceVolume, let systemVolume, _, let canControlVolume):
                systemVolumeContent(level: systemVolume, device: nil)
                ExternalDeviceIndicatorHUD(level: deviceVolume, deviceName: deviceName, deviceIcon: deviceIcon, canControlVolume: canControlVolume)
                    .transition(.opacity.combined(with: .offset(y: 5)))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(width: 280)
        .shadow(color: .black.opacity(0.3), radius: 15, y: 5)
        .padding(.top, 30)
        .transition(.opacity.combined(with: .move(edge: .bottom)))
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: type)
    }

    private func volumeIconName(for level: Float) -> String {
        if level == 0 { return "speaker.slash.fill" }
        if level < 0.33 { return "speaker.wave.1.fill" }
        if level < 0.66 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }

    @ViewBuilder
    private func systemVolumeContent(level: Float, device: AudioDevice?) -> some View {
        HStack(spacing: 12) {
            let icon: String = {
                if settings.settings.volumeHUDShowDeviceIcon, let device = device {
                    if settings.settings.excludeBuiltInSpeakersFromHUDIcon && device.name.lowercased().contains("macbook") {
                        return volumeIconName(for: level)
                    }
                    return IconMapper.icon(for: device)
                }
                return volumeIconName(for: level)
            }()

            Image(systemName: icon)
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(.white.opacity(0.8))
                .frame(width: 40, alignment: .center)

            DynamicSliderIndicator(
                level: level,
                onChanged: { newLevel in
                    SystemControl.setVolume(to: newLevel)
                }
            )
            .frame(height: 14)

            if settings.settings.hudShowPercentage {
                Text("\(Int(level * 100))%")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.6))
                    .frame(width: 40)
            }
        }
    }

    @ViewBuilder
    private func brightnessContent(level: Float) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "sun.max.fill")
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(.white.opacity(0.8))
                .frame(width: 40, alignment: .center)

            DynamicSliderIndicator(
                level: level,
                onChanged: { newLevel in
                    SystemControl.setBrightness(to: newLevel)
                }
            )
            .frame(height: 14)

            if settings.settings.hudShowPercentage {
                Text("\(Int(level * 100))%")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.6))
                    .frame(width: 40)
            }
        }
    }

    @ViewBuilder
    private func keyboardBrightnessContent(level: Float) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "keyboard.fill")
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(.white.opacity(0.8))
                .frame(width: 40, alignment: .center)

            DynamicSliderIndicator(
                level: level,
                onChanged: { newLevel in
                    SystemControl.setKeyboardBrightness(to: newLevel)
                }
            )
            .frame(height: 14)

            if settings.settings.hudShowPercentage {
                Text("\(Int(level * 100))%")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.6))
                    .frame(width: 40)
            }
        }
    }
}

struct ExternalDeviceIndicatorHUD: View {
    @State var level: Float
    let deviceName: String
    let deviceIcon: String
    let canControlVolume: Bool
    private let debouncer = Debouncer(delay: 0.05)

    var body: some View {
        VStack(spacing: 8) {
            Divider().opacity(0.5)
            HStack(spacing: 12) {
                Image(systemName: deviceIcon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.green)
                    .frame(width: 40, alignment: .center)

                VStack(alignment: .leading, spacing: 4) {
                    Text(deviceName)
                        .font(.system(size: 12, weight: .bold))

                    if canControlVolume {
                        BoldPillSlider(
                            value: Binding(
                                get: { Double(level) },
                                set: { level = Float($0) }
                            ),
                            range: 0...1
                        )
                        .frame(height: 14)
                    } else {
                        Capsule()
                            .fill(Color.gray.opacity(0.25))
                            .frame(height: 14)
                            .overlay(Text("Volume Not Adjustable").font(.caption2).foregroundColor(.secondary))
                    }
                }

                Text("\(Int(level * 100))%")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.6))
                    .frame(width: 40)
            }
        }
        .onChange(of: level) { _, newValue in
            guard canControlVolume else { return }
            debouncer.debounce {
                Task {
                    _ = await MusicManager.shared.setSpotifyVolume(percent: Int((newValue * 100).rounded(.toNearestOrAwayFromZero)))
                }
            }
        }
    }
}

struct DynamicSliderIndicator: View {
    @State private var level: Float
    let externalLevel: Float
    var onChanged: ((Float) -> Void)?
    private let debouncer = Debouncer(delay: 0.05)
    @EnvironmentObject var settings: SettingsModel
    @StateObject private var hudManager = SystemHUDManager.shared

    init(level: Float, onChanged: ((Float) -> Void)? = nil) {
        self.externalLevel = level
        self._level = State(initialValue: level)
        self.onChanged = onChanged
    }

    private var indicatorColor: Color {
        switch settings.settings.hudVisualStyle {
        case .white:
            return .white.opacity(0.7)
        case .color:
            return settings.settings.hudCustomColor?.color ?? .accentColor
        case .adaptive:
            if level >= 0.9 { return .red }
            if level > 0.6 { return .yellow }
            return .white
        }
    }

    private var glowRadius: CGFloat {
        if settings.settings.hudVisualStyle == .adaptive {
            return CGFloat(level * 10)
        } else {
            return hudManager.glowIntensity * 10
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let totalWidth = geometry.size.width

            ZStack(alignment: .leading) {
                Capsule().fill(.gray.opacity(0.3))
                Capsule()
                    .fill(indicatorColor)
                    .frame(width: totalWidth * CGFloat(level))
            }
            .clipShape(Capsule())
            .contentShape(Rectangle())
            .shadow(color: indicatorColor.opacity(0.9), radius: glowRadius)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let newLevel = Float(value.location.x / totalWidth).clamped(to: 0...1)
                        self.level = newLevel
                        debouncer.debounce {
                            onChanged?(newLevel)
                        }
                    }
            )
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: level)
            .animation(.easeInOut(duration: 0.2), value: indicatorColor)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: glowRadius)
        }
        .onChange(of: externalLevel) { _, newLevel in
            self.level = newLevel
        }
    }
}

struct SystemHUDSlimActivityView {
    static func left(type: HUDType) -> some View {
        let iconName: String = {
            switch type {
            case .volume(let level, _):
                if level == 0 { return "speaker.slash.fill" }
                if level < 0.33 { return "speaker.wave.1.fill" }
                if level < 0.66 { return "speaker.wave.2.fill" }
                return "speaker.wave.3.fill"
            case .brightness: return "sun.max.fill"
            case .keyboardBrightness: return "keyboard.fill"
            case .externalDeviceVolume(_, let deviceIcon, _, let systemVolume, let isControllingExternal, _):
                if isControllingExternal {
                    return deviceIcon
                } else {
                    if systemVolume == 0 { return "speaker.slash.fill" }
                    if systemVolume < 0.33 { return "speaker.wave.1.fill" }
                    if systemVolume < 0.66 { return "speaker.wave.2.fill" }
                    return "speaker.wave.3.fill"
                }
            }
        }()

        return ZStack {
            Image(systemName: iconName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
                .animation(nil, value: type)
        }
        .frame(width: 20, height: 20)
        .animation(.default, value: type.caseIdentifier)
    }

    static func right(type: HUDType, settings: SettingsModel) -> some View {
        let level: Float = {
            switch type {
            case .volume(let level, _): return level
            case .brightness(let level): return level
            case .keyboardBrightness(let level): return level
            case .externalDeviceVolume(_, _, let deviceVolume, let systemVolume, let isControllingExternal, _):
                return isControllingExternal ? deviceVolume : systemVolume
            }
        }()

        return HStack(spacing: 6) {
            DynamicSliderIndicator(level: level, onChanged: nil)
                .frame(width: settings.settings.hudShowPercentage ? 70 : 100, height: 6)
                .fixedSize()

            if settings.settings.hudShowPercentage {
                Text("\(Int(level * 100))%")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.6))
                    .frame(width: 30, alignment: .leading)
                    .transition(.opacity.combined(with: .offset(x: -5)))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: settings.settings.hudShowPercentage)
    }
}

fileprivate struct BoldPillSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var onCommit: (() -> Void)?

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let progress = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
            let progressWidth = width * progress

            ZStack(alignment: .leading) {
                Capsule().fill(Color.gray.opacity(0.25))
                Capsule().fill(Color.green)
                    .frame(width: progressWidth)
            }
            .clipShape(Capsule())
            .contentShape(Capsule())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let percentage = (gesture.location.x / width).clamped(to: 0...1)
                        let newValue = (range.upperBound - range.lowerBound) * percentage + range.lowerBound
                        self.value = newValue.clamped(to: range)
                    }
                    .onEnded { _ in onCommit?() }
            )
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: value)
        }
    }
}

extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        return min(max(self, limits.lowerBound), limits.upperBound)
    }
}