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

// MARK: - Data Structures for Multi-Display HUD
struct DisplayBrightnessInfo: Hashable, Identifiable {
    let id: CGDirectDisplayID
    let name: String
    var level: Float
    let isPrimary: Bool
}

enum HUDType: Hashable {
    case volume(level: Float, device: AudioDevice?)
    case brightness(level: Float)
    case multiDisplayBrightness(displays: [DisplayBrightnessInfo])
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
        case .multiDisplayBrightness(let displays):
            hasher.combine(displays)
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
        case .multiDisplayBrightness: return .multiDisplayBrightness
        case .keyboardBrightness: return .keyboardBrightness
        case .externalDeviceVolume: return .externalDeviceVolume
        }
    }
    enum CaseIdentifier { case volume, brightness, multiDisplayBrightness, keyboardBrightness, externalDeviceVolume }
}

private enum MediaKeyAction {
    case volumeUp, volumeDown
    case brightnessUp, brightnessDown
}

class SystemHUDManager: ObservableObject {
    static let shared = SystemHUDManager()

    @Published private(set) var currentHUD: HUDType?
    @Published private(set) var glowIntensity: Double = 0.0
    @Published var isXDREnabled = false

    private let brightnessManager = BrightnessManager.shared
    private let settings = SettingsModel.shared
    private let musicManager = MusicManager.shared
    private let displayManager = DisplayManager.shared

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

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        reconfigureDisplays()
    }

    @objc private func screenParametersChanged() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            self.reconfigureDisplays()
        }
    }

    private func reconfigureDisplays() {
        displayManager.configureDisplays()
        displayManager.addDisplayCounterSuffixes()
        if Arm64DDC.isArm64 {
            displayManager.updateArm64AVServices()
        }
        displayManager.setupOtherDisplays(firstrun: true)
    }

    private func setupEventTap() {
        if let existingTap = eventTap {
            CGEvent.tapEnable(tap: existingTap, enable: false)
        }
        eventTap = nil

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

        if action == .volumeUp || action == .volumeDown {
            if settings.settings.showSpotifyVolumeHUD, let cachedState = self.lastKnownSpotifyState {
                self.spotifyStateForAction = cachedState
                self.updateVolumeHUD()
            }

            if settings.settings.showSpotifyVolumeHUD && !isFetchingSpotifyState {
                isFetchingSpotifyState = true
                Task { @MainActor in
                    defer { self.isFetchingSpotifyState = false }
                    if let freshState = await musicManager.fetchActiveSpotifyDeviceState() {
                        self.spotifyStateForAction = freshState
                        self.lastKnownSpotifyState = freshState
                        if self.currentHUD != nil {
                            self.updateVolumeHUD()
                        }
                    } else {
                        self.spotifyStateForAction = nil
                        self.lastKnownSpotifyState = nil
                    }
                }
            }
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

            if settings.settings.volumeHUDSoundEnabled {
                if let soundURL = Bundle.main.url(forResource: "Media Keys", withExtension: "aif") {
                    NSSound(contentsOf: soundURL, byReference: true)?.play()
                } else {
                    NSSound(named: "Tink")?.play()
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
            if currentModifiers.contains(.option) && !currentModifiers.contains(.shift) {
                let changeDirection: Float = action == .brightnessUp ? 1 : -1
                let percentageStep = Float(settings.settings.brightnessliderstep)
                let coarseStep = (percentageStep / 100.0).clamped(to: 0.01...1.0)
                let fineStep: Float = 0.01

                let snapAndChange = { (currentLevel: Float) -> Float in
                    if NSEvent.modifierFlags.contains([.shift, .option]) {
                        return (currentLevel + (fineStep * changeDirection)).clamped(to: 0...1)
                    } else {
                        let currentStepNum = round(currentLevel / coarseStep)
                        let nextStepNum = currentStepNum + changeDirection
                        return (nextStepNum * coarseStep).clamped(to: 0...1)
                    }
                }

                let newKeyboardBrightness = snapAndChange(SystemControl.getKeyboardBrightness())
                SystemControl.setKeyboardBrightness(to: newKeyboardBrightness)
                showHUD(for: .keyboardBrightness(level: newKeyboardBrightness))
            } else {
                let isXDRLocked = settings.settings.xdrBrightnessLock && !currentModifiers.contains(.command)
                let currentBrightness = self.settings.settings.brightness

                if action == .brightnessUp && isXDRLocked && currentBrightness >= 1.0 {
                    let allDisplays = displayManager.getAllDisplays()
                    if allDisplays.count <= 1 {
                        showHUD(for: .brightness(level: currentBrightness))
                        return
                    }
                }

                let direction: Float = action == .brightnessUp ? 1 : -1
                changeBrightnessMulti(direction: direction)
            }
        }

        if isInitialKeyPress {
            isInitialKeyPress = false
        }
    }

    @MainActor private func changeBrightnessMulti(direction: Float) {
        let allDisplays = displayManager.getAllDisplays()
        let modifiers = NSEvent.modifierFlags

        let primaryDisplay = displayManager.getCurrentDisplay()
        var orderedDisplays: [Display] = []
        if let primary = primaryDisplay {
            orderedDisplays.append(primary)
            orderedDisplays.append(contentsOf: allDisplays.filter { $0.identifier != primary.identifier })
        } else {
            orderedDisplays = allDisplays
        }

        var targetDisplay: Display?
        if modifiers.contains(.shift) {
            targetDisplay = orderedDisplays.count > 1 ? orderedDisplays[1] : nil
        } else if modifiers.contains(.function) {
            targetDisplay = orderedDisplays.count > 2 ? orderedDisplays[2] : nil
        } else {
            targetDisplay = orderedDisplays.first
        }

        var changedBuiltInLevel: Float?
        if let displayToChange = targetDisplay {
            if displayToChange.isBuiltIn() {
                changedBuiltInLevel = _changeBuiltInDisplayBrightness(direction: direction)
            } else {
                let isFineTuning = modifiers.contains([.shift, .option])
                displayToChange.stepBrightness(isUp: direction > 0, isSmallIncrement: isFineTuning)
            }
        }

        if allDisplays.count > 1 {
            var displayInfos: [DisplayBrightnessInfo] = []
            for display in allDisplays {
                var currentLevel: Float
                if display.isBuiltIn(), let newLevel = changedBuiltInLevel {
                    currentLevel = newLevel
                } else {
                    currentLevel = display.getBrightness()
                }

                displayInfos.append(DisplayBrightnessInfo(
                    id: display.identifier,
                    name: display.name,
                    level: currentLevel,
                    isPrimary: display.identifier == primaryDisplay?.identifier
                ))
            }
            showHUD(for: .multiDisplayBrightness(displays: displayInfos))
        } else if let singleDisplay = allDisplays.first {
            let levelForHUD = changedBuiltInLevel ?? singleDisplay.getBrightness()
            showHUD(for: .brightness(level: levelForHUD))
        }
    }

    @MainActor private func _changeBuiltInDisplayBrightness(direction: Float) -> Float {
        let xdrBrightness = self.settings.settings.brightness
        let maxBrightness = self.settings.settings.xdrBrightnessLevel
        let systemBrightness = SystemControl.getBrightness()
        var finalLevel: Float = systemBrightness
        if direction > 0 {
            if isXDREnabled {
                let newXDRLevel = min(maxBrightness, xdrBrightness + Float(settings.settings.brightnessliderstep) / 100.0)
                self.settings.settings.brightness = newXDRLevel
                finalLevel = newXDRLevel
            } else if systemBrightness >= 1.0 && self.settings.settings.enableXDRBrightness {
                isXDREnabled = true
                brightnessManager.activate()
                let initialXDRLevel: Float = (1.00 + Float(settings.settings.brightnessliderstep) / 100.0)
                self.settings.settings.brightness = initialXDRLevel
                finalLevel = initialXDRLevel
            } else {
                let newLevel = calculateNewStandardBrightness(currentLevel: systemBrightness, direction: 1)
                SystemControl.setBrightness(to: newLevel)
                self.settings.settings.brightness = newLevel
                finalLevel = newLevel
            }
        } else {
            if isXDREnabled {
                let newXDRLevel = xdrBrightness - Float(settings.settings.brightnessliderstep) / 100.0
                if newXDRLevel <= 1.0 {
                    isXDREnabled = false
                    brightnessManager.deactivate()
                    SystemControl.setBrightness(to: 1.0)
                    self.settings.settings.brightness = 1.0
                    finalLevel = 1.0
                } else {
                    self.settings.settings.brightness = newXDRLevel
                    finalLevel = newXDRLevel
                }
            } else {
                let newLevel = calculateNewStandardBrightness(currentLevel: systemBrightness, direction: -1)
                SystemControl.setBrightness(to: newLevel)
                self.settings.settings.brightness = newLevel
                finalLevel = newLevel
            }
        }
        return finalLevel
    }

    private func calculateNewStandardBrightness(currentLevel: Float, direction: Float) -> Float {
        let percentageStep = Float(settings.settings.brightnessliderstep)
        let coarseStep = (percentageStep / 100.0).clamped(to: 0.01...1.0)
        let fineStep: Float = 0.01

        if NSEvent.modifierFlags.contains([.shift, .option]) {
            return (currentLevel + (fineStep * direction)).clamped(to: 0...1)
        } else {
            let currentStepNum = round(Double(currentLevel) / Double(coarseStep))
            let nextStepNum = currentStepNum + Double(direction)
            return Float(nextStepNum * Double(coarseStep)).clamped(to: 0...1)
        }
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
                case .brightness(let level):
                    brightnessContent(level: level)
                case .multiDisplayBrightness(let displays):
                    multiDisplayBrightnessContent(displays: displays)
                case .keyboardBrightness(let level):
                    keyboardBrightnessContent(level: level)
                case .externalDeviceVolume(let deviceName, let deviceIcon, let deviceVolume, let systemVolume, let isControllingExternal, let canControlVolume):
                    let systemDevice = AudioDeviceManager().getCurrentOutputDevice()
                    systemVolumeContent(
                        level: systemVolume,
                        device: systemDevice,
                        isControllingExternal: isControllingExternal
                    )
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
    private func systemVolumeContent(
        level: Float,
        device: AudioDevice?,
        isControllingExternal: Bool = false
    ) -> some View {
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
                    if newLevel == 0.0 {
                        SystemControl.setMuted(to: true)
                    } else {
                        SystemControl.setMuted(to: false)
                    }
                    if isControllingExternal {
                        if case .externalDeviceVolume(let deviceName, let deviceIcon, let deviceVolume, _, let isControlling, let canControl) = hudManager.currentHUD {
                            hudManager.updateCurrentHUD(to: .externalDeviceVolume(
                                deviceName: deviceName,
                                deviceIcon: deviceIcon,
                                deviceVolume: deviceVolume,
                                systemVolume: newLevel,
                                isControllingExternal: isControlling,
                                canControlVolume: canControl
                            ))
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
    private func multiDisplayBrightnessContent(displays: [DisplayBrightnessInfo]) -> some View {
        let displayCount = displays.count
        let sortedDisplays = displays.sorted { $0.isPrimary && !$1.isPrimary }

        if let primaryDisplay = sortedDisplays.first {
            brightnessContent(
                level: primaryDisplay.level,
                displayName: displayCount > 2 ? primaryDisplay.name : nil
            )
        }

        ForEach(sortedDisplays.dropFirst()) { display in
            ExternalDeviceIndicatorHUD(
                level: display.level,
                deviceName: display.name,
                deviceIcon: "display",
                canControlVolume: true,
                isBrightness: true,
                showName: displayCount > 2
            )
            .transition(.opacity.combined(with: .offset(y: 5)))
        }
    }

    @ViewBuilder
    private func brightnessContent(level: Float, displayName: String? = nil) -> some View {
        let isXDR = level > 1.0
        let currentDisplayScaleMax = hudManager.isXDREnabled ? settings.settings.xdrBrightnessLevel : 1.0
        let normalizedDisplayLevel = level / currentDisplayScaleMax
        let percentageText = "\(Int(roundf(level * 100)))%"

        VStack(alignment: .leading, spacing: 4) {
             if let name = displayName {
                Text(name)
                    .font(.system(size: 12, weight: .bold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.leading, 52)
            }
            HStack(spacing: 12) {
                Image(systemName: isXDR ? "sun.max.trianglebadge.exclamationmark.fill" : "sun.max.fill")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(isXDR ? .orange : .white.opacity(0.8))
                    .frame(width: 40, alignment: .center)

                DynamicSliderIndicator(
                    level: normalizedDisplayLevel,
                    isXDR: isXDR,
                    onChanged: { normalizedNewLevel in
                        let deNormalizedLevel = normalizedNewLevel * currentDisplayScaleMax
                        if deNormalizedLevel > 1.0 {
                            if !hudManager.isXDREnabled {
                                hudManager.isXDREnabled = true
                                BrightnessManager.shared.activate()
                            }
                            SettingsModel.shared.settings.brightness = deNormalizedLevel
                        } else {
                            if hudManager.isXDREnabled {
                                hudManager.isXDREnabled = false
                                BrightnessManager.shared.deactivate()
                            }
                            SystemControl.setBrightness(to: deNormalizedLevel)
                            SettingsModel.shared.settings.brightness = deNormalizedLevel
                        }
                        hudManager.updateCurrentHUD(to: .brightness(level: deNormalizedLevel))
                    }
                ).frame(height: 14)

                if settings.settings.hudShowPercentage {
                    Text(percentageText)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.6))
                        .frame(width: 40)
                }
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
    var canControlVolume: Bool = true
    var isBrightness: Bool = false
    var showName: Bool = true

    private let sliderDebouncer = Debouncer(delay: 0.2)

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: deviceIcon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(isBrightness ? .white.opacity(0.8) : .green)
                    .frame(width: 40, alignment: .center)

                VStack(alignment: .leading, spacing: 4) {
                    if showName {
                        Text(deviceName)
                            .font(.system(size: 12, weight: .bold))
                            .lineLimit(1)
                    }

                    if canControlVolume {
                        BoldPillSlider(
                            value: Binding(
                                get: { Double(level) },
                                set: { level = Float($0) }
                            ),
                            range: 0...1,
                            isBrightness: isBrightness
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
            guard canControlVolume, !isBrightness else { return }
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

    let forceGreen: Bool
    let isXDR: Bool
    let showInternalXDRText: Bool

    init(level: Float, forceGreen: Bool = false, isXDR: Bool = false, showInternalXDRText: Bool = true, onChanged: ((Float) -> Void)? = nil) {
        self.externalLevel = level
        self._level = State(initialValue: level)
        self.onChanged = onChanged
        self.forceGreen = forceGreen
        self.isXDR = isXDR
        self.showInternalXDRText = showInternalXDRText
    }

    @ViewBuilder
    private func sliderFill() -> some View {
        if isXDR {
            LinearGradient(
                gradient: Gradient(colors: [.purple, .blue]),
                startPoint: .leading,
                endPoint: .trailing
            )
        } else {
            indicatorColor
        }
    }

    private var indicatorColor: Color {
        if forceGreen { return .green }
        switch settings.settings.hudVisualStyle {
        case .white: return .white.opacity(0.7)
        case .color: return settings.settings.hudCustomColor?.color ?? .accentColor
        case .adaptive:
            if level >= 0.9 { return .red }
            if level > 0.6 { return .yellow }
            return .white
        }
    }

    private var shadowColor: Color {
        if isXDR { return .blue }
        return indicatorColor
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

                sliderFill()
                    .frame(width: totalWidth * CGFloat(level))
                    .clipShape(Capsule())

                if isXDR && showInternalXDRText {
                    Text("XDR")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(Color.orange)
                        .padding(.leading, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
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

fileprivate struct BoldPillSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var onCommit: (() -> Void)?
    var isBrightness: Bool = false

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let progress = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
            let progressWidth = width * progress

            ZStack(alignment: .leading) {
                Capsule().fill(Color.gray.opacity(0.25))
                Capsule().fill(isBrightness ? Color.white.opacity(0.7) : Color.green)
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
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 20, height: 20)
                }
            } else {
                Image(systemName: volumeIconName(for: level))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 20, height: 20)
            }
        case .brightness(let level):
            if level > 1.0 {
                HStack(spacing: 4) {
                    Image(systemName: "sun.max.trianglebadge.exclamationmark.fill")
                        .font(.system(size: 14, weight: .semibold))
                    Text("XDR")
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                }
                .foregroundColor(.orange)
                .frame(height: 20)
            } else {
                Image(systemName: "sun.max.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 20, height: 20)
            }

        case .multiDisplayBrightness:
            Image(systemName: "display.2")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 20, height: 20)

        case .keyboardBrightness:
            Image(systemName: "keyboard.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 20, height: 20)

        case .externalDeviceVolume(_, let deviceIcon, _, let systemVolume, let controllingExternal, _):
            if controllingExternal {
                Image(systemName: deviceIcon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.green)
                    .frame(width: 20, height: 20)
            } else {
                let systemDevice = AudioDeviceManager().getCurrentOutputDevice()
                if settings.settings.volumeHUDShowDeviceIcon, let dev = systemDevice {
                     if settings.settings.excludeBuiltInSpeakersFromHUDIcon && dev.name.lowercased().contains("macbook") {
                        Image(systemName: volumeIconName(for: systemVolume))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 20, height: 20)
                    } else {
                        Image(systemName: IconMapper.icon(for: dev))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 20, height: 20)
                    }
                } else {
                    Image(systemName: volumeIconName(for: systemVolume))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 20, height: 20)
                }
            }
        }
    }

    static func right(type: HUDType, settings: SettingsModel) -> some View {
        let level: Float
        let isExternalControl: Bool
        let isXDR: Bool

        switch type {
        case .volume(let l, _):
            level = l; isExternalControl = false; isXDR = false
        case .brightness(let l):
            level = l; isExternalControl = false; isXDR = l > 1.0
        case .multiDisplayBrightness(let displays):
            level = displays.first(where: { $0.isPrimary })?.level ?? displays.first?.level ?? 0
            isExternalControl = false; isXDR = false
        case .keyboardBrightness(let l):
            level = l; isExternalControl = false; isXDR = false
        case .externalDeviceVolume(_, _, let deviceVolume, let systemVolume, let controllingExternal, _):
            level = controllingExternal ? deviceVolume : systemVolume
            isExternalControl = controllingExternal
            isXDR = false
        }

        let displayLevel: Float
        let percentageText: String
        let percentageFrameWidth: CGFloat

        if isXDR {
            let maxLevel = settings.settings.xdrBrightnessLevel
            displayLevel = level / maxLevel
            percentageText = "\(Int(roundf(level * 100)))%"
            percentageFrameWidth = 40
        } else {
            displayLevel = level
            percentageText = "\(Int(level * 100))%"
            percentageFrameWidth = 30
        }

        return HStack(spacing: 6) {
            DynamicSliderIndicator(
                level: displayLevel,
                forceGreen: isExternalControl,
                isXDR: isXDR,
                showInternalXDRText: false,
                onChanged: nil
            )
            .frame(width: settings.settings.hudShowPercentage ? 70 : 100, height: 6)
            .fixedSize()

            if settings.settings.hudShowPercentage {
                Text(percentageText)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.6))
                    .frame(width: percentageFrameWidth, alignment: .leading)
                    .transition(.opacity.combined(with: .offset(x: -5)))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: settings.settings.hudShowPercentage)
    }
}

extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        return min(max(self, limits.lowerBound), limits.upperBound)
    }
}