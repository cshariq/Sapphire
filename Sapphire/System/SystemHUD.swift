//
//  SystemHUD.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-07-06.
//

import SwiftUI
import AppKit
import Combine

fileprivate func eventTapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    if type.rawValue == NX_SYSDEFINED {
        if SystemHUDManager.shared.handleMediaKeyEvent(event) {
            return nil
        }
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
    case brightness(level: Float, subzeroLevel: Float, displayName: String?)
    case keyboardBrightness(level: Float)
    case externalDeviceVolume(deviceName: String, deviceIcon: String, deviceVolume: Float, systemVolume: Float, isControllingExternal: Bool, canControlVolume: Bool)

    func hash(into hasher: inout Hasher) {
        hasher.combine(self.caseIdentifier)
        switch self {
        case .volume(let level, let device):
            hasher.combine(level)
            hasher.combine(device)
        case .brightness(let level, let subzeroLevel, let displayName):
            hasher.combine(level)
            hasher.combine(subzeroLevel)
            hasher.combine(displayName)
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

    private let displayController = DisplayController.shared
    private let settings = SettingsModel.shared
    private let musicManager = MusicManager.shared

    private var eventTap: CFMachPort?
    private var hudDismissalTimer: Timer?
    private var keyRepeatTimer: Timer?
    private var currentAction: MediaKeyAction?
    private var verificationTimer: Timer?

    private let keyRepeatDelay: TimeInterval = 0.25
    private let keyRepeatInterval: TimeInterval = 0.03

    private var isInitialKeyPress = true

    private var spotifyStateForAction: ActiveSpotifyDeviceState?
    private var lastKnownSpotifyState: ActiveSpotifyDeviceState?
    private var currentSpotifyVolumeForAction: Float?
    private var lastCommittedSpotifyVolume: Float?
    private var isFetchingSpotifyState = false
    private var isControllingSpotify = false

    private init() {

        setupEventTap()
        verificationTimer = Timer.scheduledTimer(
            timeInterval: 5.0,
            target: self,
            selector: #selector(verifyAndReinstateEventTap),
            userInfo: nil,
            repeats: true
        )
    }

    private func setupEventTap() {
        if let existingTap = eventTap {
            CGEvent.tapEnable(tap: existingTap, enable: false)
        }
        eventTap = nil

        let eventsToMonitor: CGEventMask = (1 << NX_SYSDEFINED)
        let selfAsUnsafeMutableRawPointer = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventsToMonitor,
            callback: eventTapCallback,
            userInfo: selfAsUnsafeMutableRawPointer
        )

        guard let eventTap = eventTap else {
            print("[SystemHUDManager] FATAL ERROR: Failed to create CGEvent tap. Check Accessibility Permissions.")
            return
        }

        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)

        if CGEvent.tapIsEnabled(tap: eventTap) {
            print("[SystemHUDManager] Event tap successfully created and enabled.")
        } else {
            print("[SystemHUDManager] Event tap created but failed to enable.")
        }
    }

    @objc func verifyAndReinstateEventTap() {
        guard let tap = self.eventTap, CGEvent.tapIsEnabled(tap: tap) else {
            print("[SystemHUDManager] Event tap is not active or missing. Attempting to reinstate...")
            DispatchQueue.main.async {
                self.setupEventTap()
            }
            return
        }
    }

    fileprivate func handleMediaKeyEvent(_ cgEvent: CGEvent) -> Bool {
        guard let nsEvent = NSEvent(cgEvent: cgEvent),
              nsEvent.type == .systemDefined,
              nsEvent.subtype.rawValue == 8 else {
            return false
        }

        let rawData = nsEvent.data1
        let keyCode = Int32((rawData & 0xFFFF0000) >> 16)
        let keyFlags = (rawData & 0xFF00) >> 8
        let isKeyDown = (keyFlags == 0x0A)
        let isKeyUp = (keyFlags == 0x0B)

        switch keyCode {
        case NX_KEYTYPE_PLAY, NX_KEYTYPE_FAST, NX_KEYTYPE_REWIND:
            if isKeyDown {
                switch keyCode {
                case NX_KEYTYPE_PLAY: NotificationCenter.default.post(name: .mediaKeyPlayPausePressed, object: nil)
                case NX_KEYTYPE_FAST: NotificationCenter.default.post(name: .mediaKeyNextPressed, object: nil)
                case NX_KEYTYPE_REWIND: NotificationCenter.default.post(name: .mediaKeyPreviousPressed, object: nil)
                default: break
                }
            }
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

        DispatchQueue.main.async {
            if isKeyDown {
                if self.currentAction == nil {
                    self.startContinuousChange(for: validAction)
                }
            } else if isKeyUp {
                if validAction == self.currentAction {
                    self.stopContinuousChange()
                }
            }
        }

        return true
    }

    private func handleMute() {
        stopContinuousChange()
        let wasMuted = SystemControl.isMuted()
        SystemControl.setMuted(to: !wasMuted)

        let level = wasMuted ? SystemControl.getVolume() : 0.0
        let device = AudioDeviceManager().getCurrentOutputDevice()
        showHUD(for: .volume(level: level, device: device))
    }

    @MainActor private func startContinuousChange(for action: MediaKeyAction) {
        currentAction = action
        isInitialKeyPress = true
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

    private func stopContinuousChange() {
        if let lastAction = currentAction, (lastAction == .volumeUp || lastAction == .volumeDown) {
            if isControllingSpotify,
               let finalVolume = self.currentSpotifyVolumeForAction,
               let lastCommitted = self.lastCommittedSpotifyVolume,
               Int(finalVolume.rounded()) != Int(lastCommitted.rounded()) {

                let finalVolumeInt = Int(finalVolume.rounded())
                Task {
                    _ = await self.musicManager.setSpotifyVolume(percent: finalVolumeInt)
                }
            }
        }

        keyRepeatTimer?.invalidate()
        keyRepeatTimer = nil
        currentAction = nil

        withAnimation(.spring()) {
            glowIntensity = 0.0
        }
    }

    @objc private func startRepeatingChange() {
        keyRepeatTimer?.invalidate()
        keyRepeatTimer = Timer.scheduledTimer(
            timeInterval: keyRepeatInterval,
            target: self,
            selector: #selector(performChange),
            userInfo: nil,
            repeats: true
        )
    }

    @MainActor @objc private func performChange() {
        guard let action = currentAction else {
            stopContinuousChange()
            return
        }

        if !isInitialKeyPress {
            withAnimation(.spring()) {
                glowIntensity = min(1.0, glowIntensity + 0.05)
            }
        }

        let currentModifiers = NSEvent.modifierFlags

        switch action {
        case .volumeUp, .volumeDown:
            let isSystemFineTune = currentModifiers.contains([.option, .shift]) && !currentModifiers.contains(.command)
            let isSpotifyModifierPressed = currentModifiers.contains(.option) || currentModifiers.contains(.command)
            let isSpotifyControlAttempt = settings.settings.showSpotifyVolumeHUD && isSpotifyModifierPressed && !isSystemFineTune

            if isSpotifyControlAttempt {
                if let spotifyState = self.spotifyStateForAction, spotifyState.canControlVolume {
                    self.isControllingSpotify = true

                    if self.currentSpotifyVolumeForAction == nil {
                        self.currentSpotifyVolumeForAction = Float(spotifyState.volumePercent ?? 0)
                        self.lastCommittedSpotifyVolume = self.currentSpotifyVolumeForAction
                    }
                    let isFineTuningForSpotify = currentModifiers.contains(.option) || currentModifiers.contains(.shift)
                    performSpotifyVolumeChange(action: action, isFineTuning: isFineTuningForSpotify)

                } else if isFetchingSpotifyState {
                    return
                } else {
                    self.isControllingSpotify = false
                    self.changeSystemVolume(action: action, isFineTuning: isSystemFineTune)
                }
            } else {
                self.isControllingSpotify = false
                self.changeSystemVolume(action: action, isFineTuning: isSystemFineTune)
            }

            self.updateVolumeHUD()

        case .brightnessUp, .brightnessDown:
             if currentModifiers.contains(.option) {
                let changeDirection: Float = action == .brightnessUp ? 1 : -1
                let percentageStep = Float(settings.settings.brightnessliderstep)
                let coarseStep = (percentageStep / 100.0).clamped(to: 0.01...1.0)
                let fineStep: Float = 0.01

                let step = currentModifiers.contains(.shift) ? fineStep : coarseStep
                let currentKB = SystemControl.getKeyboardBrightness()
                let newKB = (currentKB + (step * changeDirection)).clamped(to: 0...1)

                SystemControl.setKeyboardBrightness(to: newKB)
                showHUD(for: .keyboardBrightness(level: newKB))
            } else {
                changeMonitorBrightness(action: action)
            }
        }

        if isInitialKeyPress {
            isInitialKeyPress = false
        }
    }

    @MainActor private func changeMonitorBrightness(action: MediaKeyAction) {
        let isFineTune = NSEvent.modifierFlags.contains([.shift, .option])
        let coarseStep: Float = (Float(settings.settings.brightnessliderstep) / 100.0).clamped(to: 0.01...1.0)
        let fineStep: Float = 0.01

        let direction: Float = (action == .brightnessUp) ? 1.0 : -1.0
        let step = isFineTune ? fineStep : coarseStep

        guard let display = displayController.getCursorDisplay(), !display.isBuiltin else {
            let currentBrightness = SystemControl.getBrightness()
            let newLevel = (currentBrightness + (step * direction)).clamped(to: 0...1)
            SystemControl.setBrightness(to: newLevel)
            showHUD(for: .brightness(level: newLevel, subzeroLevel: 1.0, displayName: "Built-in Display"))
            return
        }

        let hardwareBrightness = display.brightness
        let softwareBrightness = display.softwareBrightness

        if direction > 0 {
            if softwareBrightness < 1.0 {
                let newSoftwareLevel = (softwareBrightness + step).clamped(to: 0...1)
                display.softwareBrightness = newSoftwareLevel
            } else {
                let oldValue = hardwareBrightness
                let currentStepNum = round(oldValue / (coarseStep * 100))
                let nextStepNum = currentStepNum + direction
                let newHardwareLevel = (nextStepNum * (coarseStep * 100)).clamped(to: 0...100)

                if display.control?.setBrightness(newHardwareLevel, oldValue: oldValue) == true {
                    display.brightness = newHardwareLevel
                }
            }
        } else {
            if hardwareBrightness > 0 {
                let oldValue = hardwareBrightness
                let currentStepNum = round(oldValue / (coarseStep * 100))
                let nextStepNum = currentStepNum + direction
                let newHardwareLevel = (nextStepNum * (coarseStep * 100)).clamped(to: 0...100)

                if display.control?.setBrightness(newHardwareLevel, oldValue: oldValue) == true {
                    display.brightness = newHardwareLevel
                }
            } else {
                let newSoftwareLevel = (softwareBrightness + (step * direction)).clamped(to: 0...1)
                display.softwareBrightness = newSoftwareLevel
            }
        }

        showHUD(for: .brightness(level: display.brightness / 100.0, subzeroLevel: display.softwareBrightness, displayName: display.name))
    }

    @MainActor private func performSpotifyVolumeChange(action: MediaKeyAction, isFineTuning: Bool) {
        guard let currentVolume = self.currentSpotifyVolumeForAction else { return }

        let changeDirection: Float = action == .volumeUp ? 1 : -1
        let step: Float = isFineTuning ? 1.0 : Float(settings.settings.volumesliderstep)

        let newSpotifyVolume = (currentVolume + (step * changeDirection)).clamped(to: 0...100)
        self.currentSpotifyVolumeForAction = newSpotifyVolume

        let lastCommitted = self.lastCommittedSpotifyVolume ?? newSpotifyVolume
        let commitThreshold: Float = isFineTuning ? 5 : 15
        let oldZone = Int(lastCommitted / commitThreshold)
        let newZone = Int(newSpotifyVolume / commitThreshold)

        if oldZone != newZone {
            let volumeToSend = Int(newSpotifyVolume.rounded())
            Task {
                _ = await self.musicManager.setSpotifyVolume(percent: volumeToSend)
            }
            self.lastCommittedSpotifyVolume = newSpotifyVolume
        }
    }

    @MainActor
    private func changeSystemVolume(action: MediaKeyAction, isFineTuning: Bool) {
        let changeDirection: Float = action == .volumeUp ? 1 : -1
        let percentageStep = Float(settings.settings.volumesliderstep)
        let coarseStep = (percentageStep / 100.0).clamped(to: 0.01...1.0)
        let fineStep: Float = 0.01

        let currentVolume = SystemControl.getVolume()
        let newVolume: Float
        if isFineTuning {
            newVolume = (currentVolume + (fineStep * changeDirection)).clamped(to: 0...1)
        } else {
            let currentStepNum = round(currentVolume / coarseStep)
            let nextStepNum = currentStepNum + changeDirection
            newVolume = (nextStepNum * coarseStep).clamped(to: 0...1)
        }

        SystemControl.setVolume(to: newVolume)

        if newVolume == 0.0 {
            SystemControl.setMuted(to: true)
        } else {
            SystemControl.setMuted(to: false)
        }
    }

    @MainActor
    private func updateVolumeHUD() {
        let systemVolume = SystemControl.getVolume()

        if settings.settings.showSpotifyVolumeHUD, let spotifyState = self.spotifyStateForAction {
            let spotifyVolumePercent = self.currentSpotifyVolumeForAction ?? Float(spotifyState.volumePercent ?? 75)
            let hud = HUDType.externalDeviceVolume(
                deviceName: spotifyState.name,
                deviceIcon: spotifyState.iconName,
                deviceVolume: spotifyVolumePercent / 100.0,
                systemVolume: systemVolume,
                isControllingExternal: isControllingSpotify,
                canControlVolume: spotifyState.canControlVolume
            )
            showHUD(for: hud)
        } else {
            let device = AudioDeviceManager().getCurrentOutputDevice()
            showHUD(for: .volume(level: systemVolume, device: device))
        }
    }

    private func showHUD(for hudType: HUDType) {
        DispatchQueue.main.async {
            self.currentHUD = hudType
            self.hudDismissalTimer?.invalidate()
            self.hudDismissalTimer = Timer.scheduledTimer(withTimeInterval: self.settings.settings.hudDuration, repeats: false) { [weak self] _ in
                self?.currentHUD = nil
                self?.spotifyStateForAction = nil
                self?.currentSpotifyVolumeForAction = nil
                self?.lastCommittedSpotifyVolume = nil
                self?.isControllingSpotify = false
            }
        }
    }

    @MainActor
    func updateCurrentHUD(to newHUD: HUDType) {
        self.currentHUD = newHUD
        self.hudDismissalTimer?.invalidate()
        self.hudDismissalTimer = Timer.scheduledTimer(withTimeInterval: self.settings.settings.hudDuration, repeats: false) { [weak self] _ in
            self?.currentHUD = nil
            self?.spotifyStateForAction = nil
            self?.currentSpotifyVolumeForAction = nil
            self?.lastCommittedSpotifyVolume = nil
            self?.isControllingSpotify = false
        }
    }
}

struct SystemHUDView: View {
    @EnvironmentObject var hudManager: SystemHUDManager
    @EnvironmentObject var settings: SettingsModel

    var body: some View {
        if let type = hudManager.currentHUD {
            VStack(spacing: 8) {
                switch type {
                case .volume(let level, let device):
                    systemVolumeContent(level: level, device: device)
                case .brightness(let level, let subzeroLevel, let displayName):
                    brightnessContent(level: level, subzeroLevel: subzeroLevel, displayName: displayName)
                case .keyboardBrightness(let level):
                    keyboardBrightnessContent(level: level)
                case .externalDeviceVolume(let deviceName, let deviceIcon, let deviceVolume, let systemVolume, let isControllingExternal, let canControlVolume):
                    let systemDevice = AudioDeviceManager().getCurrentOutputDevice()
                    systemVolumeContent(level: systemVolume, device: systemDevice, isControllingExternal: isControllingExternal)
                    ExternalDeviceIndicatorHUD(level: deviceVolume, deviceName: deviceName, deviceIcon: deviceIcon, canControlVolume: canControlVolume)
                        .transition(.opacity.combined(with: .offset(y: 5)))
                }
            }
            .id(type)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(width: 280)
            .shadow(color: .black.opacity(0.3), radius: 15, y: 5)
            .padding(.top, 30)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: type)
        }
    }

    private func volumeIconName(for level: Float) -> String {
        if level == 0 { return "speaker.slash.fill" }
        if level < 0.33 { return "speaker.wave.1.fill" }
        if level < 0.66 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }

    @ViewBuilder
    private func systemVolumeContent(level: Float, device: AudioDevice?, isControllingExternal: Bool = false) -> some View {
        HStack(spacing: 12) {
            let icon: String = {
                if settings.settings.volumeHUDShowDeviceIcon, let dev = device {
                    if settings.settings.excludeBuiltInSpeakersFromHUDIcon && dev.name.lowercased().contains("macbook") {
                        return volumeIconName(for: level)
                    }
                    return IconMapper.icon(for: dev)
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
                    if newLevel == 0.0 { SystemControl.setMuted(to: true) } else { SystemControl.setMuted(to: false) }
                    if isControllingExternal {
                        if case .externalDeviceVolume(let deviceName, let deviceIcon, let deviceVolume, _, let isControlling, let canControl) = hudManager.currentHUD {
                            hudManager.updateCurrentHUD(to: .externalDeviceVolume(deviceName: deviceName, deviceIcon: deviceIcon, deviceVolume: deviceVolume, systemVolume: newLevel, isControllingExternal: isControlling, canControlVolume: canControl))
                        }
                    } else {
                        hudManager.updateCurrentHUD(to: .volume(level: newLevel, device: device))
                    }
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
    private func brightnessContent(level: Float, subzeroLevel: Float, displayName: String?) -> some View {
        let isSubzero = subzeroLevel < 1.0
        let percentageText = "\(Int(roundf(level * 100)))%"

        VStack(alignment: .center, spacing: 8) {
            if let name = displayName {
                Text(name)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)
            }

            HStack(spacing: 12) {
                Image(systemName: isSubzero ? "moon.fill" : "sun.max.fill")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(isSubzero ? .purple.opacity(0.8) : .white.opacity(0.8))
                    .frame(width: 40, alignment: .center)

                DynamicSliderIndicator(
                    level: level,
                    onChanged: { newLevel in
                        if let name = displayName, let display = DisplayController.shared.displays.first(where: { $0.name == name }) {
                            if display.control?.setBrightness(newLevel * 100, oldValue: display.brightness) == true {
                                display.brightness = newLevel * 100
                                if display.softwareBrightness < 1.0 { display.softwareBrightness = 1.0 }
                                hudManager.updateCurrentHUD(to: .brightness(level: newLevel, subzeroLevel: 1.0, displayName: name))
                            }
                        } else {
                            SystemControl.setBrightness(to: newLevel)
                            hudManager.updateCurrentHUD(to: .brightness(level: newLevel, subzeroLevel: 1.0, displayName: displayName))
                        }
                    }
                ).frame(height: 14)

                if settings.settings.hudShowPercentage {
                    Text(percentageText)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.6))
                        .frame(width: 40)
                }
            }

            if isSubzero {
                HStack(spacing: 12) {
                    Image(systemName: "moon.stars.fill")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.purple.opacity(0.6))
                        .frame(width: 40, alignment: .center)

                    DynamicSliderIndicator(
                        level: subzeroLevel,
                        isSubzero: true,
                        onChanged: { newLevel in
                            if let name = displayName, let display = DisplayController.shared.displays.first(where: { $0.name == name }) {
                                display.softwareBrightness = newLevel
                                hudManager.updateCurrentHUD(to: .brightness(level: display.brightness / 100, subzeroLevel: newLevel, displayName: name))
                            }
                        }
                    ).frame(height: 10)

                    if settings.settings.hudShowPercentage {
                         Text("\(Int(subzeroLevel * 100))%")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.5))
                            .frame(width: 40)
                    }
                }
                .transition(.opacity.combined(with: .offset(y: 5)))
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
                    hudManager.updateCurrentHUD(to: .keyboardBrightness(level: newLevel))
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

    private let sliderDebouncer = Debouncer(delay: 0.2)

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: deviceIcon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.green)
                    .frame(width: 40, alignment: .center)

                VStack(alignment: .leading, spacing: 4) {
                    Text(deviceName)
                        .font(.system(size: 12, weight: .bold))
                        .lineLimit(1)

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

                if canControlVolume {
                    Text("\(Int(level * 100))%")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.6))
                        .frame(width: 40)
                }
            }
        }
        .onChange(of: level) { _, newValue in
            guard canControlVolume else { return }
            sliderDebouncer.debounce {
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
    @EnvironmentObject var settings: SettingsModel
    @StateObject private var hudManager = SystemHUDManager.shared
    let isSubzero: Bool

    init(level: Float, isSubzero: Bool = false, onChanged: ((Float) -> Void)? = nil) {
        self.externalLevel = level
        self._level = State(initialValue: level)
        self.onChanged = onChanged
        self.isSubzero = isSubzero
    }

    @ViewBuilder
    private func sliderFill() -> some View {
        if isSubzero {
            LinearGradient(gradient: Gradient(colors: [.purple, .blue]), startPoint: .leading, endPoint: .trailing)
        } else {
            indicatorColor
        }
    }

    private var indicatorColor: Color {
        .white
    }

    private var shadowColor: Color {
        if isSubzero { return .blue }
        return indicatorColor
    }

    private var glowRadius: CGFloat {
        hudManager.glowIntensity * 10
    }

    var body: some View {
        GeometryReader { geometry in
            let totalWidth = geometry.size.width

            ZStack(alignment: .leading) {
                Capsule().fill(.gray.opacity(0.3))
                sliderFill()
                    .frame(width: totalWidth * CGFloat(level))
                    .clipShape(Capsule())
            }
            .clipShape(Capsule())
            .contentShape(Rectangle())
            .shadow(color: shadowColor.opacity(0.9), radius: glowRadius)
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                let newLevel = Float(value.location.x / totalWidth).clamped(to: 0...1)
                self.level = newLevel
                onChanged?(newLevel)
            })
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: level)
            .animation(.easeInOut(duration: 0.2), value: indicatorColor)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: glowRadius)
        }
        .onChange(of: externalLevel) { _, newLevel in self.level = newLevel }
    }
}

struct SystemHUDSlimActivityView {
    private static func volumeIconName(for level: Float) -> String {
        if level == 0 { return "speaker.slash.fill" }
        if level < 0.33 { return "speaker.wave.1.fill" }
        if level < 0.66 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }

    @ViewBuilder
    static func left(type: HUDType, settings: SettingsModel) -> some View {
        switch type {
        case .volume(let level, let device):
            if settings.settings.volumeHUDShowDeviceIcon, let dev = device {
                if settings.settings.excludeBuiltInSpeakersFromHUDIcon && dev.name.lowercased().contains("macbook") {
                    Image(systemName: volumeIconName(for: level))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 20, height: 20)
                } else {
                    Image(systemName: IconMapper.icon(for: dev))
                }
            } else {
                Image(systemName: volumeIconName(for: level))
            }
        case .brightness(let level, let subzeroLevel, _):
            if subzeroLevel < 1.0 {
                Image(systemName: "moon.stars.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.purple)
            } else {
                Image(systemName: "sun.max.fill")
            }
        case .keyboardBrightness:
            Image(systemName: "keyboard.fill")
        case .externalDeviceVolume(_, let deviceIcon, _, let systemVolume, let controllingExternal, _):
            if controllingExternal {
                Image(systemName: deviceIcon)
            } else {
                Image(systemName: volumeIconName(for: systemVolume))
            }
        }
    }

    static func right(type: HUDType, settings: SettingsModel) -> some View {
        let (level, isExternalControl, isSubzero) = { () -> (Float, Bool, Bool) in
            switch type {
            case .volume(let l, _): return (l, false, false)
            case .brightness(let l, let sl, _): return (sl < 1.0 ? sl : l, false, sl < 1.0)
            case .keyboardBrightness(let l): return (l, false, false)
            case .externalDeviceVolume(_, _, let d, let s, let c, _): return (c ? d : s, c, false)
            }
        }()

        let percentageText = "\(Int(level * 100))%"

        return HStack(spacing: 6) {
            DynamicSliderIndicator(level: level, isSubzero: isSubzero)
                .frame(width: settings.settings.hudShowPercentage ? 70 : 100, height: 6)
            if settings.settings.hudShowPercentage {
                Text(percentageText)
            }
        }
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
                Capsule().fill(Color.green).frame(width: progressWidth)
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