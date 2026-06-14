//
//  LidAngleAutomationManager.swift
//  Sapphire
//
//  Created by OpenAI Codex.
//

import AppKit
import Combine
import Foundation

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

        settings.$settings
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateSensorRequirement()
                self?.evaluate()
            }
            .store(in: &cancellables)

        updateSensorRequirement()
    }

    private func evaluate() {
        guard sensor.isAvailable else {
            restoreAllAutomations()
            return
        }

        evaluateMediaAutomation()
        evaluateAudioAutomation()
        evaluateDisplayAutomation()
        evaluateLowPowerAutomation()
    }

    private func evaluateMediaAutomation() {
        let trigger = settings.settings.lidAnglePauseMediaTrigger
        let shouldPause = settings.settings.lidAnglePauseMediaEnabled && sensor.angle <= trigger
        let shouldResume = autoPausedPlayback && sensor.angle > trigger + hysteresis

        if shouldPause, !autoPausedPlayback, musicManager.isPlaying {
            musicManager.pause()
            autoPausedPlayback = true
            return
        }

        if shouldResume {
            musicManager.play()
            autoPausedPlayback = false
        } else if !settings.settings.lidAnglePauseMediaEnabled {
            autoPausedPlayback = false
        }
    }

    private func evaluateAudioAutomation() {
        let trigger = settings.settings.lidAngleMuteAudioTrigger
        let shouldMute = settings.settings.lidAngleMuteAudioEnabled && sensor.angle <= trigger
        let shouldUnmute = autoMutedSystemAudio && sensor.angle > trigger + hysteresis

        if shouldMute, !autoMutedSystemAudio, !SystemControl.isMuted() {
            SystemControl.setMuted(to: true)
            autoMutedSystemAudio = true
            return
        }

        if shouldUnmute {
            SystemControl.setMuted(to: false)
            autoMutedSystemAudio = false
        } else if !settings.settings.lidAngleMuteAudioEnabled {
            autoMutedSystemAudio = false
        }
    }

    private func evaluateDisplayAutomation() {
        let trigger = settings.settings.lidAngleSleepDisplayTrigger
        let shouldSleep = settings.settings.lidAngleSleepDisplayEnabled && sensor.angle <= trigger
        let shouldWake = autoSleptDisplay && sensor.angle > trigger + hysteresis

        if shouldSleep, !autoSleptDisplay {
            (NSApp.delegate as? AppDelegate)?.sleepDisplay()
            autoSleptDisplay = true
            return
        }

        if shouldWake {
            (NSApp.delegate as? AppDelegate)?.wakeDisplay()
            autoSleptDisplay = false
        } else if !settings.settings.lidAngleSleepDisplayEnabled {
            autoSleptDisplay = false
        }
    }

    private func evaluateLowPowerAutomation() {
        let trigger = settings.settings.lidAngleLowPowerModeTrigger
        let shouldEnable = settings.settings.lidAngleLowPowerModeEnabled && sensor.angle <= trigger
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
        } else if !settings.settings.lidAngleLowPowerModeEnabled {
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

    /// Reverts lid-angle automations that changed media, audio, display, or power state.
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

    private func updateSensorRequirement() {
        let settings = settings.settings
        let needsSensor =
            settings.lidAnglePauseMediaEnabled ||
            settings.lidAngleMuteAudioEnabled ||
            settings.lidAngleSleepDisplayEnabled ||
            settings.lidAngleLowPowerModeEnabled

        if needsSensor {
            sensor.acquire(.automationManager)
        } else {
            sensor.release(.automationManager)
        }
    }
}
