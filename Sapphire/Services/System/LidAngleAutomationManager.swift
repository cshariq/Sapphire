//
//  LidAngleAutomationManager.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-10

import AppKit
import Combine
import Foundation

private struct LidAngleAutomationSettings: Equatable {
    let pauseMediaEnabled: Bool
    let pauseMediaTrigger: Double
    let muteAudioEnabled: Bool
    let muteAudioTrigger: Double
    let sleepDisplayEnabled: Bool
    let sleepDisplayTrigger: Double
    let lowPowerModeEnabled: Bool
    let lowPowerModeTrigger: Double

    init(_ settings: Settings) {
        pauseMediaEnabled = settings.lidAnglePauseMediaEnabled
        pauseMediaTrigger = settings.lidAnglePauseMediaTrigger
        muteAudioEnabled = settings.lidAngleMuteAudioEnabled
        muteAudioTrigger = settings.lidAngleMuteAudioTrigger
        sleepDisplayEnabled = settings.lidAngleSleepDisplayEnabled
        sleepDisplayTrigger = settings.lidAngleSleepDisplayTrigger
        lowPowerModeEnabled = settings.lidAngleLowPowerModeEnabled
        lowPowerModeTrigger = settings.lidAngleLowPowerModeTrigger
    }
}

@MainActor
final class LidAngleAutomationManager: ObservableObject {
    static let shared = LidAngleAutomationManager()

    private let sensor = LidAngleSensor.shared
    private let settings = SettingsModel.shared
    private let musicManager = MusicManager.shared
    private let powerModeManager = PowerModeManager.shared

    private var cancellables = Set<AnyCancellable>()
    private let hysteresis = 6.0

    private var autoPausedPlayback = false
    private var autoMutedSystemAudio = false
    private var autoSleptDisplay = false
    private var forcedLowPowerMode = false
    private var lowPowerModeWasAlreadyEnabled = false

    private init() {
        sensor.$angle
            .combineLatest(sensor.$isAvailable)
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _ in
                self?.evaluate()
            }
            .store(in: &cancellables)

        settings.changes(of: LidAngleAutomationSettings.init)
            .sink { [weak self] configuration in
                self?.updateSensorRequirement(configuration)
                self?.evaluate(configuration)
            }
            .store(in: &cancellables)

        let initialConfiguration = LidAngleAutomationSettings(settings.settings)
        updateSensorRequirement(initialConfiguration)
        evaluate(initialConfiguration)
    }

    private func evaluate() {
        evaluate(LidAngleAutomationSettings(settings.settings))
    }

    private func evaluate(_ configuration: LidAngleAutomationSettings) {
        guard sensor.isAvailable else {
            restoreAllAutomations()
            return
        }

        evaluateMediaAutomation(configuration)
        evaluateAudioAutomation(configuration)
        evaluateDisplayAutomation(configuration)
        evaluateLowPowerAutomation(configuration)
    }

    private func evaluateMediaAutomation(_ configuration: LidAngleAutomationSettings) {
        let trigger = configuration.pauseMediaTrigger
        let shouldPause = configuration.pauseMediaEnabled && sensor.angle <= trigger
        let shouldResume = autoPausedPlayback && sensor.angle > trigger + hysteresis

        if shouldPause, !autoPausedPlayback, musicManager.isPlaying {
            Task { await musicManager.pause() }
            autoPausedPlayback = true
            return
        }

        if shouldResume {
            Task { await musicManager.play() }
            autoPausedPlayback = false
        } else if !configuration.pauseMediaEnabled {
            autoPausedPlayback = false
        }
    }

    private func evaluateAudioAutomation(_ configuration: LidAngleAutomationSettings) {
        let trigger = configuration.muteAudioTrigger
        let shouldMute = configuration.muteAudioEnabled && sensor.angle <= trigger
        let shouldUnmute = autoMutedSystemAudio && sensor.angle > trigger + hysteresis

        if shouldMute, !autoMutedSystemAudio, !SystemControl.isMuted() {
            SystemControl.setMuted(to: true)
            autoMutedSystemAudio = true
            return
        }

        if shouldUnmute {
            SystemControl.setMuted(to: false)
            autoMutedSystemAudio = false
        } else if !configuration.muteAudioEnabled {
            autoMutedSystemAudio = false
        }
    }

    private func evaluateDisplayAutomation(_ configuration: LidAngleAutomationSettings) {
        let trigger = configuration.sleepDisplayTrigger
        let shouldSleep = configuration.sleepDisplayEnabled && sensor.angle <= trigger
        let shouldWake = autoSleptDisplay && sensor.angle > trigger + hysteresis

        if shouldSleep, !autoSleptDisplay {
            (NSApp.delegate as? AppDelegate)?.sleepDisplay()
            autoSleptDisplay = true
            return
        }

        if shouldWake {
            (NSApp.delegate as? AppDelegate)?.wakeDisplay()
            autoSleptDisplay = false
        } else if !configuration.sleepDisplayEnabled {
            autoSleptDisplay = false
        }
    }

    private func evaluateLowPowerAutomation(_ configuration: LidAngleAutomationSettings) {
        let trigger = configuration.lowPowerModeTrigger
        let shouldEnable = configuration.lowPowerModeEnabled && sensor.angle <= trigger
        let shouldRestore = forcedLowPowerMode && sensor.angle > trigger + hysteresis

        if shouldEnable, !forcedLowPowerMode {
            lowPowerModeWasAlreadyEnabled = powerModeManager.isLowPowerModeEnabled()
            if !lowPowerModeWasAlreadyEnabled {
                powerModeManager.enableLowPowerMode()
            }
            forcedLowPowerMode = true
            return
        }

        if shouldRestore {
            if !lowPowerModeWasAlreadyEnabled {
                powerModeManager.disableLowPowerMode()
            }
            forcedLowPowerMode = false
            lowPowerModeWasAlreadyEnabled = false
        } else if !configuration.lowPowerModeEnabled {
            if forcedLowPowerMode, !lowPowerModeWasAlreadyEnabled {
                powerModeManager.disableLowPowerMode()
            }
            forcedLowPowerMode = false
            lowPowerModeWasAlreadyEnabled = false
        }
    }

    private func restoreAllAutomations() {
        releaseForcedSystemChanges()
    }

    func releaseForcedSystemChanges() {
        autoPausedPlayback = false

        if autoMutedSystemAudio {
            SystemControl.setMuted(to: false)
            autoMutedSystemAudio = false
        }

        if autoSleptDisplay {
            (NSApp.delegate as? AppDelegate)?.wakeDisplay()
            autoSleptDisplay = false
        }

        if forcedLowPowerMode, !lowPowerModeWasAlreadyEnabled {
            powerModeManager.disableLowPowerMode()
        }
        forcedLowPowerMode = false
        lowPowerModeWasAlreadyEnabled = false
    }

    private func updateSensorRequirement(_ settings: LidAngleAutomationSettings) {
        let needsSensor =
            settings.pauseMediaEnabled ||
            settings.muteAudioEnabled ||
            settings.sleepDisplayEnabled ||
            settings.lowPowerModeEnabled

        if needsSensor {
            sensor.acquire(.automationManager)
        } else {
            sensor.release(.automationManager)
        }
    }
}