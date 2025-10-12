//
//  ScheduleManager.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-07-19.
//
//
//
//
//
//

import Foundation
import Combine

struct ScheduledTask: Codable, Equatable, Identifiable {
    var id = UUID()
    var action: TaskAction = .setChargeLimit
    var repeatInterval: RepeatInterval = .never
    var startTime: Date = Date()
    var chargeLimit: Int = 80
    var isActive: Bool = true
}

enum TaskAction: String, Codable, CaseIterable, Identifiable {
    case setChargeLimit, startCalibration, topUp, pauseCharging, dischargeTo
    var id: String { self.rawValue }
    var displayName: String {
        switch self {
        case .setChargeLimit: "Set Charge Limit"
        case .startCalibration: "Start Calibration"
        case .topUp: "Top Up"
        case .pauseCharging: "Pause Charging"
        case .dischargeTo: "Discharge To"
        }
    }
}

enum RepeatInterval: String, Codable, CaseIterable, Identifiable {
    case never, daily, weekdays, weekly, biweekly, monthly
    var id: String { self.rawValue }
    var displayName: String { self.rawValue.capitalized }
}

struct TaskHistoryEvent: Identifiable, Codable {
    let id = UUID()
    let timestamp: Date
    let taskDescription: String
}

class ScheduleManager: ObservableObject {
    static let shared = ScheduleManager()
    private let settings = SettingsModel.shared
    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()

    @Published var taskHistory: [TaskHistoryEvent] = []

    private init() {

        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.checkScheduledTasks()
        }

        settings.objectWillChange.sink { [weak self] in
        }.store(in: &cancellables)
    }

    func checkScheduledTasks() {
        let now = Date()
        let calendar = Calendar.current

        if settings.settings.enableBiweeklyCalibration {
        }

        for task in settings.settings.scheduledTasks where task.isActive {
            let scheduledTime = calendar.dateComponents([.hour, .minute], from: task.startTime)
            let nowTime = calendar.dateComponents([.hour, .minute], from: now)

            if scheduledTime.hour == nowTime.hour && scheduledTime.minute == nowTime.minute {
                var shouldRun = false
                switch task.repeatInterval {
                case .daily:
                    shouldRun = true
                case .weekdays:
                    let weekday = calendar.component(.weekday, from: now)
                    shouldRun = (weekday >= 2 && weekday <= 6) // Mon-Fri
                case .weekly:
                    shouldRun = calendar.component(.weekday, from: now) == calendar.component(.weekday, from: task.startTime)
                default:
                    if task.repeatInterval == .never {
                    }
                    break
                }

                if shouldRun {
                    executeTask(task)
                }
            }
        }
    }

    private func executeTask(_ task: ScheduledTask) {
        logTaskExecution(task)

        switch task.action {
        case .setChargeLimit:
            BatteryManager.shared.setChargeLimit(task.chargeLimit)
        case .startCalibration:
            BatteryManager.shared.startCalibration()
        case .topUp:
            BatteryManager.shared.setChargeLimit(100)
        case .pauseCharging:
            break
        case .dischargeTo:
            BatteryManager.shared.setChargeLimit(task.chargeLimit)
            BatteryManager.shared.setDischarge(true)
        }
    }

    private func logTaskExecution(_ task: ScheduledTask) {
        let event = TaskHistoryEvent(timestamp: Date(), taskDescription: "Executed: \(task.action.displayName)")
        taskHistory.insert(event, at: 0)
    }
}