//
//  CalibrationManager.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-10-23
//

import Foundation
import Combine

@MainActor
class CalibrationManager: ObservableObject {
    static let shared = CalibrationManager()

    enum State: CustomStringConvertible, Equatable {
        case idle
        case chargingToFull
        case holdingAtFull(timeRemaining: TimeInterval)
        case dischargingToLow
        case finalChargeToLimit
        case done
        case error(String)

        var description: String {
            switch self {
            case .idle: return "Idle"
            case .chargingToFull: return "Step 1: Charging to 100%"
            case .holdingAtFull(let time): return "Step 2: Holding at 100% (\(time.formattedInterval()))"
            case .dischargingToLow: return "Step 3: Discharging to 10%"
            case .finalChargeToLimit: return "Step 4: Recharging to original limit"
            case .done: return "Calibration Complete"
            case .error(let msg): return "Error: \(msg)"
            }
        }

        static func == (lhs: State, rhs: State) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle): return true
            case (.chargingToFull, .chargingToFull): return true
            case (.holdingAtFull, .holdingAtFull): return true
            case (.dischargingToLow, .dischargingToLow): return true
            case (.finalChargeToLimit, .finalChargeToLimit): return true
            case (.done, .done): return true
            case (.error(let a), .error(let b)): return a == b
            default: return false
            }
        }
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var progress: Double = 0.0

    var isActive: Bool { state != .idle && state != .done }

    private let batteryManager = BatteryManager.shared
    private let batteryMonitor = BatteryMonitor.shared
    private let caffeineManager = CaffeineManager.shared
    private let settings = SettingsModel.shared

    private var cancellables = Set<AnyCancellable>()
    private var holdTimer: Timer?
    private var originalChargeLimit: Int = 80

    private init() {}

    func start() {
        guard !isActive else {
            print("[CalibrationManager] Calibration is already active.")
            return
        }

        print("[CalibrationManager] Starting calibration cycle.")
        originalChargeLimit = settings.settings.batteryChargeLimit

        if settings.settings.preventSleepDuringCalibration {
            caffeineManager.start()
        }

        batteryMonitor.$currentState
            .sink { [weak self] _ in self?.evaluateNextStep() }
            .store(in: &cancellables)

        transition(to: .chargingToFull)
    }

    func cancel() {
        print("[CalibrationManager] Calibration cancelled by user.")
        transition(to: .idle)
    }

    private func transition(to newState: State) {
        self.state = newState
        print("[CalibrationManager] Transitioning to state: \(newState.description)")

        switch newState {
        case .idle, .error, .done:
            resetToIdle()

        case .chargingToFull:
            progress = 0.0
            batteryManager.setDischarge(false)
            batteryManager.enableCharging(true)
            batteryManager.setChargeLimit(100)

        case .holdingAtFull:
            holdTimer?.invalidate()
            holdTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                self?.updateHoldTime()
            }

        case .dischargingToLow:
            batteryManager.enableCharging(false)
            batteryManager.setDischarge(true)

        case .finalChargeToLimit:
            batteryManager.setDischarge(false)
            batteryManager.enableCharging(true)
        }
    }

    private func evaluateNextStep() {
        guard let battery = batteryMonitor.currentState else { return }

        switch state {
        case .chargingToFull:
            progress = Double(battery.level) / 100.0
            if battery.level >= 100 && !battery.isCharging {
                transition(to: .holdingAtFull(timeRemaining: 2 * 60 * 60))
            }

        case .dischargingToLow:
            progress = 1.0 - (Double(battery.level - 10) / 90.0)
            if battery.level <= 10 {
                transition(to: .finalChargeToLimit)
            }

        case .finalChargeToLimit:
            progress = Double(battery.level) / Double(originalChargeLimit)
            if battery.level >= originalChargeLimit {
                transition(to: .done)
            }

        default:
            break
        }
    }

    private func updateHoldTime() {
        if case .holdingAtFull(let timeRemaining) = state {
            let newTime = timeRemaining - 1
            if newTime <= 0 {
                holdTimer?.invalidate()
                transition(to: .dischargingToLow)
            } else {
                state = .holdingAtFull(timeRemaining: newTime)
                progress = 1.0 - (newTime / (2 * 60 * 60))
            }
        }
    }

    private func resetToIdle() {
        cancellables.removeAll()
        holdTimer?.invalidate()
        holdTimer = nil

        if caffeineManager.isActive {
            caffeineManager.stop()
        }

        batteryManager.setChargeLimit(originalChargeLimit)
        batteryManager.setDischarge(false)
        batteryManager.enableCharging(true)

        if state != .done && state != .idle {
            state = .idle
        }
        progress = 0.0
    }
}

fileprivate extension TimeInterval {
    func formattedInterval() -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .positional
        formatter.zeroFormattingBehavior = .pad
        return formatter.string(from: self) ?? "00:00:00"
    }
}