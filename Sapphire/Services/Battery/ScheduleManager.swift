//
//  ScheduleManager.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-07-19.
//

import Foundation
import Combine

enum TaskAction: String, Codable, CaseIterable, Identifiable {
    case setChargeLimit, topUp, dischargeTo, startCalibration

    case setFanAuto, setFanConstant, setFanSensorBased

    var id: String { self.rawValue }

    var displayName: String {
        switch self {
        case .setChargeLimit: "Set Charge Limit"
        case .topUp: "Top Up (Charge to 100%)"
        case .dischargeTo: "Discharge To"
        case .startCalibration: "Start Calibration"
        case .setFanAuto: "Set Fans to Automatic"
        case .setFanConstant: "Set Fans to Constant RPM"
        case .setFanSensorBased: "Set Fans to Sensor-based"
        }
    }
}

struct ScheduledTask: Codable, Equatable, Identifiable {
    var id = UUID()
    var action: TaskAction = .setChargeLimit
    var repeatInterval: RepeatInterval = .never
    var startTime: Date = Date()
    var chargeLimit: Int = 80
    var fanSpeed: Int = 2500
    var sensorKey: String = ""
    var minTemp: Int = 40
    var maxTemp: Int = 75
    var isActive: Bool = true
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

@MainActor
class ScheduleManager: ObservableObject {
    static let shared = ScheduleManager()

    // MARK: - Dependencies
    private let settings = SettingsModel.shared
    private let powerStateController = PowerStateController()
    private let caffeineManager = CaffeineManager.shared
    private let fanManager = FanManager.shared

    // MARK: - Properties
    private var timer: Timer?
    private let lastCalibrationDateKey = "lastAutomaticCalibrationDate"

    @Published var taskHistory: [TaskHistoryEvent] = []

    private init() {
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.checkScheduledTasks()
        }
    }

    private func checkScheduledTasks() {
        let now = Date()
        let calendar = Calendar.current

        if settings.settings.enableBiweeklyCalibration {
            let lastCalibrationDate = UserDefaults.standard.object(forKey: lastCalibrationDateKey) as? Date
            let twoWeeksAgo = calendar.date(byAdding: .day, value: -14, to: now)!

            if lastCalibrationDate == nil || lastCalibrationDate! < twoWeeksAgo {
                print("[ScheduleManager] Bi-weekly calibration is due. Executing.")
                executeTask(ScheduledTask(action: .startCalibration))
                UserDefaults.standard.set(now, forKey: lastCalibrationDateKey)
            }
        }

        for task in settings.settings.scheduledTasks where task.isActive {
            let scheduledTime = calendar.dateComponents([.hour, .minute], from: task.startTime)
            let nowTime = calendar.dateComponents([.hour, .minute], from: now)

            guard scheduledTime.hour == nowTime.hour && scheduledTime.minute == nowTime.minute else {
                continue
            }

            var shouldRun = false
            switch task.repeatInterval {
            case .never:
                let lastRun = taskHistory.first(where: { $0.taskDescription.contains(task.action.displayName) })?.timestamp
                if lastRun == nil || !calendar.isDateInToday(lastRun!) {
                    shouldRun = true
                }
            case .daily:
                shouldRun = true
            case .weekdays:
                let weekday = calendar.component(.weekday, from: now)
                shouldRun = (weekday >= 2 && weekday <= 6)
            case .weekly:
                shouldRun = calendar.component(.weekday, from: now) == calendar.component(.weekday, from: task.startTime)
            case .biweekly:
                 let weeksSinceStart = calendar.dateComponents([.weekOfYear], from: task.startTime, to: now).weekOfYear ?? 0
                 if weeksSinceStart % 2 == 0 {
                     shouldRun = calendar.component(.weekday, from: now) == calendar.component(.weekday, from: task.startTime)
                 }
            case .monthly:
                shouldRun = calendar.component(.day, from: now) == calendar.component(.day, from: task.startTime)
            }

            if shouldRun {
                executeTask(task)
            }
        }
    }

    private func executeTask(_ task: ScheduledTask) {
        logTaskExecution(task)

        switch task.action {
        case .setChargeLimit:
            settings.settings.batteryChargeLimit = task.chargeLimit
        case .startCalibration:
            if settings.settings.preventSleepDuringCalibration {
                caffeineManager.start(forcePreventSleepInClamshell: true)
            }
            CalibrationManager.shared.start()
        case .topUp:
            BatteryManager.shared.setChargeLimit(100)
            BatteryManager.shared.enableCharging(true)
        case .dischargeTo:
            self.settings.settings.batteryChargeLimit = task.chargeLimit
            self.settings.settings.dischargeToLimitEnabled = true

        case .setFanAuto:
            print("[ScheduleManager] Executing task: Set Fans to Automatic.")
            for i in 0..<fanManager.fans.count {
                fanManager.setFanMode(for: i, to: .auto)
            }
        case .setFanConstant:
            print("[ScheduleManager] Executing task: Set Fans to \(task.fanSpeed) RPM.")
            for i in 0..<fanManager.fans.count {
                fanManager.setFanMode(for: i, to: .constant(rpm: task.fanSpeed))
            }
        case .setFanSensorBased:
            print("[ScheduleManager] Executing task: Set Fans to Sensor-based (\(task.sensorKey), \(task.minTemp)°C-\(task.maxTemp)°C).")
            for i in 0..<fanManager.fans.count {
                fanManager.setFanMode(for: i, to: .sensor(sensorKey: task.sensorKey, minTemp: task.minTemp, maxTemp: task.maxTemp))
            }
        }
    }

    private func logTaskExecution(_ task: ScheduledTask) {
        let event = TaskHistoryEvent(timestamp: Date(), taskDescription: "Executed: \(task.action.displayName)")
        DispatchQueue.main.async {
            self.taskHistory.insert(event, at: 0)
        }
    }
}