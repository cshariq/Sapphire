//
//  EyeBreakManager.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-07-10.
//

import Foundation
import Combine
import AppKit
import SwiftUI

@_silgen_name("notify_register_dispatch")
private func notifyRegisterDispatch(
    _ name: UnsafePointer<CChar>,
    _ outToken: UnsafeMutablePointer<Int32>,
    _ queue: DispatchQueue,
    _ handler: @escaping @convention(block) (Int32) -> Void
) -> UInt32

@_silgen_name("notify_get_state")
private func notifyGetState(_ token: Int32, _ state: UnsafeMutablePointer<UInt64>) -> UInt32

@_silgen_name("notify_cancel")
private func notifyCancel(_ token: Int32) -> UInt32

private final class GameModeMonitor: ObservableObject {
    @Published private(set) var isActive = false

    private var notificationToken: Int32 = -1
    private static let notificationName = "com.apple.system.game_mode_status_changed"

    init() {
        var token: Int32 = -1
        let status = Self.notificationName.withCString { name in
            notifyRegisterDispatch(name, &token, .main) { [weak self] token in
                self?.updateState(for: token)
            }
        }

        guard status == 0 else { return }
        notificationToken = token
        updateState(for: token)
    }

    deinit {
        if notificationToken >= 0 {
            _ = notifyCancel(notificationToken)
        }
    }

    private func updateState(for token: Int32) {
        var state: UInt64 = 0
        guard notifyGetState(token, &state) == 0 else { return }
        isActive = state != 0
    }
}

struct EyeBreakSession: Identifiable, Codable {
    enum SessionType: String, Codable {
        case work, `break`
    }
    var id = UUID()
    var type: SessionType
    var duration: TimeInterval
    var date: Date
    var completed: Bool
}

struct EyeBreakDailySummary: Identifiable {
    private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter
    }()

    let id = UUID()
    let date: Date
    var workDuration: TimeInterval = 0
    var breakDuration: TimeInterval = 0
    var completedBreaks: Int = 0
    var skippedBreaks: Int = 0

    var complianceRate: Double {
        guard completedBreaks + skippedBreaks > 0 else { return 0 }
        return Double(completedBreaks) / Double(completedBreaks + skippedBreaks)
    }

    var eyeStrainScore: Int {
        let idealBreakRatio = 0.05
        let actualBreakRatio = workDuration > 0 ? breakDuration / workDuration : 0
        let ratioScore = min(1.0, actualBreakRatio / idealBreakRatio)

        let score = (complianceRate * 0.7 + ratioScore * 0.3) * 100
        return Int(score)
    }

    var dayName: String {
        Self.weekdayFormatter.string(from: date)
    }

    var formattedWorkTime: String {
        formatDuration(workDuration)
    }

    var formattedBreakTime: String {
        formatDuration(breakDuration)
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
}

class EyeBreakManager: ObservableObject {
    static let shared = EyeBreakManager()
    private let settingsModel = SettingsModel.shared
    private let gameModeMonitor = GameModeMonitor()

    private var workInterval: TimeInterval { TimeInterval(settingsModel.current.eyeBreakWorkInterval * 60) }
    private var breakInterval: TimeInterval { TimeInterval(settingsModel.current.eyeBreakBreakDuration) }
    private var soundAlertsEnabled: Bool { settingsModel.current.eyeBreakSoundAlerts }

    @Published var isBreakTime: Bool = false
    @Published var timeUntilNextBreak: TimeInterval
    @Published var timeRemainingInBreak: TimeInterval = 0
    @Published var isDoneButtonEnabled: Bool = false
    @Published var history: [EyeBreakSession] = []
    @Published var dailySummaries: [EyeBreakDailySummary] = []
    @Published var todaySummary: EyeBreakDailySummary?
    @Published var breaksTakenToday: Int = 0
    @Published var breaksSkippedToday: Int = 0
    @Published var eyeStrainScore: Int = 100
    @Published var currentStreak: Int = 0
    @Published private(set) var isPausedForGameMode: Bool = false

    private var timer: Timer?
    private var autoAdvanceTimer: Timer?
    private var currentWorkSessionStartDate: Date?
    private var workDeadline: Date?
    private var breakDeadline: Date?
    private var autoAdvanceDeadline: Date?
    private var gameModePauseStartDate: Date?
    private var isScreenLocked = false
    private var cancellables = Set<AnyCancellable>()

    private let autoAdvanceGracePeriod: TimeInterval = 45

    init() {
        self.timeUntilNextBreak = TimeInterval(settingsModel.current.eyeBreakWorkInterval * 60)

        loadHistory()
        calculateDailySummaries()

        startWorkTimer()
        observeGameModePause()

        let dnc = DistributedNotificationCenter.default()
        dnc.addObserver(self, selector: #selector(handleScreenLocked), name: .init("com.apple.screenIsLocked"), object: nil)
        dnc.addObserver(self, selector: #selector(handleScreenUnlocked), name: .init("com.apple.screenIsUnlocked"), object: nil)
    }

    deinit {
        timer?.invalidate()
        autoAdvanceTimer?.invalidate()
        DistributedNotificationCenter.default().removeObserver(self)
    }

    private func observeGameModePause() {
        Publishers.CombineLatest(
            gameModeMonitor.$isActive,
            settingsModel.$settings
                .map(\.eyeBreakPauseDuringGameMode)
                .removeDuplicates()
        )
        .map { isGameModeActive, shouldPause in isGameModeActive && shouldPause }
        .removeDuplicates()
        .receive(on: RunLoop.main)
        .sink { [weak self] shouldPause in
            self?.setPausedForGameMode(shouldPause)
        }
        .store(in: &cancellables)
    }

    private func setPausedForGameMode(_ shouldPause: Bool) {
        guard shouldPause != isPausedForGameMode else { return }
        isPausedForGameMode = shouldPause

        if shouldPause {
            pauseForGameMode()
        } else {
            resumeAfterGameMode()
        }
    }

    private func pauseForGameMode() {
        let now = Date()
        gameModePauseStartDate = now

        if let workDeadline {
            timeUntilNextBreak = max(0, workDeadline.timeIntervalSince(now))
        }
        if let breakDeadline {
            timeRemainingInBreak = max(0, breakDeadline.timeIntervalSince(now))
        }

        timer?.invalidate()
        timer = nil
        autoAdvanceTimer?.invalidate()
        autoAdvanceTimer = nil
        NSSound(named: "Blow")?.stop()
        NSSound(named: "Glass")?.stop()
    }

    private func resumeAfterGameMode() {
        guard let pauseStartDate = gameModePauseStartDate else { return }
        let pausedDuration = max(0, Date().timeIntervalSince(pauseStartDate))
        gameModePauseStartDate = nil

        workDeadline = workDeadline?.addingTimeInterval(pausedDuration)
        breakDeadline = breakDeadline?.addingTimeInterval(pausedDuration)
        autoAdvanceDeadline = autoAdvanceDeadline?.addingTimeInterval(pausedDuration)
        currentWorkSessionStartDate = currentWorkSessionStartDate?.addingTimeInterval(pausedDuration)

        guard settingsModel.current.eyeBreakLiveActivityEnabled, !isScreenLocked else { return }

        if isBreakTime {
            if let autoAdvanceDeadline {
                scheduleAutoAdvance(deadline: autoAdvanceDeadline)
            } else if breakDeadline != nil {
                scheduleBreakCountdownTimer()
            }
        } else if workDeadline != nil {
            scheduleWorkCountdownTimer()
        } else {
            startWorkTimer()
        }
    }

    private func startWorkTimer() {
        isBreakTime = false
        isDoneButtonEnabled = false
        timeRemainingInBreak = 0
        currentWorkSessionStartDate = nil
        workDeadline = nil
        breakDeadline = nil
        autoAdvanceDeadline = nil
        timer?.invalidate()
        autoAdvanceTimer?.invalidate()
        autoAdvanceTimer = nil
        if settingsModel.current.eyeBreakLiveActivityEnabled {
            timeUntilNextBreak = workInterval
            guard !isPausedForGameMode, !isScreenLocked else { return }
            currentWorkSessionStartDate = Date()
            workDeadline = Date().addingTimeInterval(workInterval)
            scheduleWorkCountdownTimer()
        }
    }

    var secondsUntilNextBreak: TimeInterval {
        guard !isPausedForGameMode, let workDeadline else { return timeUntilNextBreak }
        return max(0, workDeadline.timeIntervalSinceNow)
    }

    private func scheduleWorkCountdownTimer() {
        timer?.invalidate()
        guard let deadline = workDeadline else { return }
        let timer = Timer(fire: deadline, interval: 0, repeats: false) { [weak self] _ in
            guard let self, !self.isPausedForGameMode, let deadline = self.workDeadline else { return }
            guard deadline.timeIntervalSinceNow <= 0.5 else {
                self.scheduleWorkCountdownTimer()
                return
            }
            self.timeUntilNextBreak = 0
            self.recordWorkSession()
            self.startBreakTimer()
        }
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func startBreakTimer() {
        timer?.invalidate()
        autoAdvanceTimer?.invalidate()
        autoAdvanceTimer = nil
        autoAdvanceDeadline = nil

        if soundAlertsEnabled && !isPausedForGameMode {
            NSSound(named: "Blow")?.play()
        }

        isBreakTime = true
        isDoneButtonEnabled = false
        timeRemainingInBreak = breakInterval
        workDeadline = nil
        breakDeadline = Date().addingTimeInterval(breakInterval)

        guard !isPausedForGameMode, !isScreenLocked else { return }
        scheduleBreakCountdownTimer()
    }

    private func scheduleBreakCountdownTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, !self.isPausedForGameMode, let deadline = self.breakDeadline else { return }

            self.timeRemainingInBreak = max(0, deadline.timeIntervalSinceNow)
            if self.timeRemainingInBreak <= 0 {
                self.isDoneButtonEnabled = true
                self.breakDeadline = nil
                if self.soundAlertsEnabled {
                    NSSound(named: "Glass")?.play()
                }
                self.timer?.invalidate()
                self.timer = nil
                self.scheduleAutoAdvance()
            }
        }
    }

    private func scheduleAutoAdvance(deadline: Date? = nil) {
        autoAdvanceTimer?.invalidate()
        let deadline = deadline ?? Date().addingTimeInterval(autoAdvanceGracePeriod)
        autoAdvanceDeadline = deadline
        let remainingTime = deadline.timeIntervalSinceNow

        guard remainingTime > 0 else {
            autoAdvanceDeadline = nil
            if isBreakTime {
                completeBreak()
            }
            return
        }

        autoAdvanceTimer = Timer.scheduledTimer(withTimeInterval: remainingTime, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            self.autoAdvanceTimer = nil
            self.autoAdvanceDeadline = nil
            guard self.isBreakTime, !self.isPausedForGameMode else { return }
            self.completeBreak()
        }
    }

    func dismissBreak() {
        guard isBreakTime else {
            resetAndStartWork()
            return
        }
        recordBreakSession(completed: false)
        resetAndStartWork()
    }

    func completeBreak() {
        guard isBreakTime else {
            resetAndStartWork()
            return
        }
        recordBreakSession(completed: true)
        resetAndStartWork()
    }

    private func resetAndStartWork() {
        self.startWorkTimer()
    }

    private func recordWorkSession() {
        guard let startDate = currentWorkSessionStartDate else { return }
        currentWorkSessionStartDate = nil
        let duration = Date().timeIntervalSince(startDate)
        let session = EyeBreakSession(type: .work, duration: duration, date: Date(), completed: true)
        history.append(session)
        saveHistory()
        updateDailySummaries()
    }

    private func recordBreakSession(completed: Bool) {
        let session = EyeBreakSession(
            type: .break,
            duration: completed ? breakInterval : max(0, breakInterval - timeRemainingInBreak),
            date: Date(),
            completed: completed
        )
        history.append(session)

        if completed {
            breaksTakenToday += 1
            currentStreak += 1
        } else {
            breaksSkippedToday += 1
            currentStreak = 0
        }

        saveHistory()
        updateDailySummaries()
    }

    @objc private func handleScreenLocked() {
        isScreenLocked = true
        if let pauseStartDate = gameModePauseStartDate,
           let currentWorkSessionStartDate {
            self.currentWorkSessionStartDate = currentWorkSessionStartDate.addingTimeInterval(
                max(0, Date().timeIntervalSince(pauseStartDate))
            )
        }
        if !isBreakTime {
            recordWorkSession()
        }
        timer?.invalidate()
        timer = nil
        autoAdvanceTimer?.invalidate()
        autoAdvanceTimer = nil
        workDeadline = nil
        breakDeadline = nil
        autoAdvanceDeadline = nil
    }

    @objc private func handleScreenUnlocked() {
        isScreenLocked = false
        resetAndStartWork()
    }

    private func saveHistory() {
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        history.removeAll { $0.date < thirtyDaysAgo }

        if let encoded = try? JSONEncoder().encode(history) {
            UserDefaults.standard.set(encoded, forKey: "EyeBreakHistory")
        }
    }

    private func loadHistory() {
        if let data = UserDefaults.standard.data(forKey: "EyeBreakHistory"),
           let decoded = try? JSONDecoder().decode([EyeBreakSession].self, from: data) {
            self.history = decoded
        }
    }

    private func calculateDailySummaries() {
        let calendar = Calendar.current
        var summariesByDate: [Date: EyeBreakDailySummary] = [:]

        let today = calendar.startOfDay(for: Date())
        let dates = (0..<7).compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }

        for date in dates {
            summariesByDate[date] = EyeBreakDailySummary(date: date)
        }

        for session in history {
            let dayDate = calendar.startOfDay(for: session.date)
            if var summary = summariesByDate[dayDate] {
                if session.type == .work {
                    summary.workDuration += session.duration
                } else {
                    summary.breakDuration += session.duration
                    if session.completed {
                        summary.completedBreaks += 1
                    } else {
                        summary.skippedBreaks += 1
                    }
                }
                summariesByDate[dayDate] = summary
            }
        }

        dailySummaries = summariesByDate.values.sorted { $0.date > $1.date }

        todaySummary = summariesByDate[today]
        breaksTakenToday = todaySummary?.completedBreaks ?? 0
        breaksSkippedToday = todaySummary?.skippedBreaks ?? 0
        eyeStrainScore = todaySummary?.eyeStrainScore ?? 100

        calculateStreak()
    }

    private func updateDailySummaries() {
        calculateDailySummaries()
    }

    private func calculateStreak() {
        var streak = 0
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        let breakSessions = history
            .filter { $0.type == .break }
            .sorted { $0.date > $1.date }

        var currentDate = today
        var found = false

        while !found {
            let dayBreaks = breakSessions.filter {
                calendar.isDate(calendar.startOfDay(for: $0.date), inSameDayAs: currentDate)
            }

            if dayBreaks.contains(where: { $0.completed }) {
                streak += 1
                currentDate = calendar.date(byAdding: .day, value: -1, to: currentDate) ?? currentDate
            } else if dayBreaks.contains(where: { !$0.completed }) {
                found = true
            } else if dayBreaks.isEmpty {
                let workSessions = history.filter {
                    $0.type == .work &&
                    calendar.isDate(calendar.startOfDay(for: $0.date), inSameDayAs: currentDate)
                }

                if workSessions.isEmpty {
                    currentDate = calendar.date(byAdding: .day, value: -1, to: currentDate) ?? currentDate
                } else {
                    found = true
                }
            }

            if calendar.dateComponents([.day], from: currentDate, to: today).day ?? 0 > 30 {
                found = true
            }
        }

        currentStreak = streak
    }
}