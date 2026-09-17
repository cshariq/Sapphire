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

    private var workInterval: TimeInterval { TimeInterval(settingsModel.settings.eyeBreakWorkInterval * 60) }
    private var breakInterval: TimeInterval { TimeInterval(settingsModel.settings.eyeBreakBreakDuration) }
    private var soundAlertsEnabled: Bool { settingsModel.settings.eyeBreakSoundAlerts }

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
    @Published private(set) var isPausedForGameMode = false

    private var timer: Timer?
    private var autoAdvanceTimer: Timer?
    private var currentWorkSessionStartDate: Date?
    private var workDeadline: Date?
    private var breakDeadline: Date?
    private var pausedWasBreakTime = false
    private var pausedWorkRemaining: TimeInterval = 0
    private var pausedBreakRemaining: TimeInterval = 0
    private var gameModeLikelyActive = false
    private var gameModeCancellables = Set<AnyCancellable>()

    private let autoAdvanceGracePeriod: TimeInterval = 45

    private var shouldPauseForGameMode: Bool {
        settingsModel.settings.eyeBreakPauseDuringGameMode &&
        settingsModel.settings.eyeBreakLiveActivityEnabled
    }

    init() {
        self.timeUntilNextBreak = TimeInterval(settingsModel.settings.eyeBreakWorkInterval * 60)

        loadHistory()
        calculateDailySummaries()

        startWorkTimer()
        observeGameMode()

        let dnc = DistributedNotificationCenter.default()
        dnc.addObserver(self, selector: #selector(handleScreenLocked), name: .init("com.apple.screenIsLocked"), object: nil)
        dnc.addObserver(self, selector: #selector(handleScreenUnlocked), name: .init("com.apple.screenIsUnlocked"), object: nil)
    }

    deinit {
        timer?.invalidate()
        autoAdvanceTimer?.invalidate()
        DistributedNotificationCenter.default().removeObserver(self)
    }

    private func startWorkTimer() {
        isPausedForGameMode = false
        isBreakTime = false
        isDoneButtonEnabled = false
        timeRemainingInBreak = 0
        currentWorkSessionStartDate = nil
        workDeadline = nil
        breakDeadline = nil
        timer?.invalidate()
        autoAdvanceTimer?.invalidate()
        autoAdvanceTimer = nil
        if settingsModel.settings.eyeBreakLiveActivityEnabled {
            timeUntilNextBreak = workInterval
            currentWorkSessionStartDate = Date()
            workDeadline = Date().addingTimeInterval(workInterval)

            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                guard let self, let deadline = self.workDeadline else { return }

                self.timeUntilNextBreak = max(0, deadline.timeIntervalSinceNow)
                if self.timeUntilNextBreak <= 0 {
                    self.recordWorkSession()
                    self.startBreakTimer()
                }
            }
            pauseForGameModeIfNeeded()
        }
    }

    private func startBreakTimer() {
        if shouldPauseForGameMode && gameModeLikelyActive {
            isBreakTime = true
            isDoneButtonEnabled = false
            timeRemainingInBreak = breakInterval
            pauseForGameModeIfNeeded()
            return
        }

        timer?.invalidate()
        autoAdvanceTimer?.invalidate()
        autoAdvanceTimer = nil

        if soundAlertsEnabled {
            NSSound(named: "Blow")?.play()
        }

        isBreakTime = true
        isDoneButtonEnabled = false
        timeRemainingInBreak = breakInterval
        workDeadline = nil
        breakDeadline = Date().addingTimeInterval(breakInterval)

        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, let deadline = self.breakDeadline else { return }

            self.timeRemainingInBreak = max(0, deadline.timeIntervalSinceNow)
            if self.timeRemainingInBreak <= 0 {
                self.isDoneButtonEnabled = true
                if self.soundAlertsEnabled {
                    NSSound(named: "Glass")?.play()
                }
                self.timer?.invalidate()
                self.scheduleAutoAdvance()
            }
        }
        pauseForGameModeIfNeeded()
    }

    private func scheduleAutoAdvance() {
        autoAdvanceTimer?.invalidate()
        autoAdvanceTimer = Timer.scheduledTimer(withTimeInterval: autoAdvanceGracePeriod, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            self.autoAdvanceTimer = nil
            guard self.isBreakTime else { return }
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
        if !isBreakTime {
            recordWorkSession()
        }
        timer?.invalidate()
        timer = nil
        autoAdvanceTimer?.invalidate()
        autoAdvanceTimer = nil
        workDeadline = nil
        breakDeadline = nil
    }

    @objc private func handleScreenUnlocked() {
        resetAndStartWork()
    }

    private func observeGameMode() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            GameModeMonitor.shared.$isGameModeLikelyActive
                .removeDuplicates()
                .sink { [weak self] isActive in
                    self?.handleGameModeChange(isActive: isActive)
                }
                .store(in: &self.gameModeCancellables)

            SettingsModel.shared.$settings
                .map { ($0.eyeBreakPauseDuringGameMode, $0.eyeBreakLiveActivityEnabled) }
                .removeDuplicates { $0 == $1 }
                .sink { [weak self] _ in
                    guard let self else { return }
                    if self.shouldPauseForGameMode && self.gameModeLikelyActive {
                        self.pauseForGameModeIfNeeded()
                    } else if self.isPausedForGameMode {
                        self.resumeFromGameModePause()
                    }
                }
                .store(in: &self.gameModeCancellables)
        }
    }

    private func handleGameModeChange(isActive: Bool) {
        gameModeLikelyActive = isActive
        guard shouldPauseForGameMode else {
            if isPausedForGameMode {
                resumeFromGameModePause()
            }
            return
        }
        if isActive {
            pauseForGameModeIfNeeded()
        } else {
            resumeFromGameModePause()
        }
    }

    private func pauseForGameModeIfNeeded() {
        guard shouldPauseForGameMode, gameModeLikelyActive, !isPausedForGameMode else { return }
        guard settingsModel.settings.eyeBreakLiveActivityEnabled else { return }

        isPausedForGameMode = true
        timer?.invalidate()
        timer = nil
        autoAdvanceTimer?.invalidate()
        autoAdvanceTimer = nil

        pausedWasBreakTime = isBreakTime
        if isBreakTime {
            pausedBreakRemaining = timeRemainingInBreak
        } else {
            pausedWorkRemaining = timeUntilNextBreak
        }
        workDeadline = nil
        breakDeadline = nil
    }

    private func resumeFromGameModePause() {
        guard isPausedForGameMode else { return }
        isPausedForGameMode = false

        guard settingsModel.settings.eyeBreakLiveActivityEnabled else { return }

        if pausedWasBreakTime {
            resumeBreakTimer(remaining: pausedBreakRemaining)
        } else {
            resumeWorkTimer(remaining: pausedWorkRemaining)
        }
    }

    private func resumeWorkTimer(remaining: TimeInterval) {
        isBreakTime = false
        isDoneButtonEnabled = false
        timeRemainingInBreak = 0
        timeUntilNextBreak = remaining
        workDeadline = Date().addingTimeInterval(remaining)
        if currentWorkSessionStartDate == nil {
            currentWorkSessionStartDate = Date().addingTimeInterval(-(workInterval - remaining))
        }

        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, let deadline = self.workDeadline else { return }

            self.timeUntilNextBreak = max(0, deadline.timeIntervalSinceNow)
            if self.timeUntilNextBreak <= 0 {
                self.recordWorkSession()
                self.startBreakTimer()
            }
        }
    }

    private func resumeBreakTimer(remaining: TimeInterval) {
        isBreakTime = true
        isDoneButtonEnabled = remaining <= 0
        timeRemainingInBreak = remaining
        breakDeadline = Date().addingTimeInterval(remaining)

        if remaining <= 0 {
            scheduleAutoAdvance()
            return
        }

        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, let deadline = self.breakDeadline else { return }

            self.timeRemainingInBreak = max(0, deadline.timeIntervalSinceNow)
            if self.timeRemainingInBreak <= 0 {
                self.isDoneButtonEnabled = true
                if self.soundAlertsEnabled {
                    NSSound(named: "Glass")?.play()
                }
                self.timer?.invalidate()
                self.scheduleAutoAdvance()
            }
        }
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