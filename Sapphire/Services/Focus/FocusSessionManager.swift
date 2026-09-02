//
//  FocusSessionManager.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-25
//

import Foundation
import Combine
import AppKit
import UserNotifications

// MARK: - Models

enum FocusPhase: String, Codable, Equatable {
    case idle
    case focusing
    case onBreak
    case finished
}

struct CompletedFocusSession: Codable, Equatable, Identifiable {
    let id: UUID
    let startedAt: Date
    let finishedAt: Date
    let plannedDuration: TimeInterval
    let actualDuration: TimeInterval
    let completedBlocks: Int

    var dateKey: DateComponents {
        let cal = Calendar.current
        return cal.dateComponents([.year, .month, .day], from: finishedAt)
    }
}

struct FocusDayRecord: Codable, Equatable {
    let date: DateComponents
    var totalSeconds: TimeInterval
    var sessionCount: Int
}

struct FocusImmunityDay: Codable, Equatable, Identifiable {
    let id: UUID
    let reportedAt: Date
    let date: DateComponents
}

struct FocusStreakMonth: Codable, Equatable {
    var bought: Int = 0
    var used: Int = 0
}

struct FocusStreakSnapshot: Equatable {
    let streak: Int
    let canRestore: Bool
    let brokenDay: DateComponents?
    let passesAvailableThisMonth: Int
    let passesBaseAllowance: Int
    let passesUsedThisMonth: Int
    let tierName: String
    let upcomingImmunityDays: [DateComponents]
}

enum FocusBlockCompletion {
    case focusFinished
    case breakFinished
    case sessionFinished
}

// MARK: - Main Manager

@MainActor
final class FocusSessionManager: ObservableObject {
    static let shared = FocusSessionManager()

    // MARK: Published state
    @Published private(set) var phase: FocusPhase = .idle
    @Published private(set) var remainingSeconds: TimeInterval = 0
    @Published private(set) var totalSeconds: TimeInterval = 0
    @Published private(set) var isPaused: Bool = false
    @Published private(set) var completedToday: TimeInterval = 0
    @Published private(set) var currentBlockIndex: Int = 0

    @Published private(set) var isFocusBlock: Bool = true

    @Published private(set) var history: [CompletedFocusSession] = []

    var isSessionActive: Bool { phase == .focusing || phase == .onBreak }
    var isRunning: Bool { isSessionActive && !isPaused }

    var blocksCompletedThisSession: Int { sessionCompletedBlocks }

    var isBlockingActive: Bool { blocker.isBlocking }

    func isAppBlocked(_ bundleID: String) -> Bool { blocker.isBlocked(bundleID: bundleID) }

    func requestTemporaryUnlock(bundleID: String) {
        blocker.requestUnblock(bundleID: bundleID, cooldown: 15 * 60)
    }

    func remainingUnlockTime(bundleID: String) -> TimeInterval? {
        blocker.remainingUnblockTime(bundleID: bundleID)
    }

    func hasPendingUnlockRequest(bundleID: String) -> Bool {
        blocker.hasPendingUnblockRequest(bundleID: bundleID)
    }

    var focusIntensity: FocusIntensity { settingsModel.settings.focusIntensity }

    func requestProductiveWebsiteAccess(domain: String) -> Bool {
        blocker.requestProductiveWebsiteAccess(domain: domain)
    }

    var canEndSessionEarly: Bool { settingsModel.settings.focusIntensity.canEndSessionEarly }

    var progress: Double {
        guard totalSeconds > 0 else { return 0 }
        return min(1, max(0, 1 - (remainingSeconds / totalSeconds)))
    }

    var remainingLabel: String {
        Self.format(remainingSeconds)
    }

    var currentBlockEndDate: Date? {
        guard isSessionActive else { return nil }
        if isPaused { return Date().addingTimeInterval(remainingSeconds) }
        guard let startedAt else { return nil }
        return startedAt.addingTimeInterval(accumulatedElapsed)
    }

    static func format(_ time: TimeInterval) -> String {
        let total = Int(time)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    // MARK: Private state
    private var ticker: Timer?

    private func startTickerIfNeeded() {
        guard ticker == nil else { return }
        let timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }
    private var startedAt: Date?
    private var accumulatedElapsed: TimeInterval = 0
    private var blockStartDate: Date?
    private var plannedFocusDuration: TimeInterval = 25 * 60
    private var plannedBreakDuration: TimeInterval = 5 * 60
    private var blockCount = 0
    private var sessionCompletedBlocks = 0

    private let settingsModel = SettingsModel.shared
    private let blocker: FocusBlocker
    private let notificationSuppressor = FocusNotificationSuppressor.shared
    private let environmentManager = FocusEnvironmentManager.shared
    private let websiteBlocker = FocusWebsiteBlocker.shared
    private let ambientManager = FocusAmbientSoundManager.shared
    private var cancellables = Set<AnyCancellable>()
    private var historyURL: URL
    private var dailyURL: URL
    private var streakURL: URL

    // MARK: Streak persistence
    private var immunityDays: [FocusImmunityDay] = []
    private var restoredStreakDayKeys: Set<String> = []
    private var streakMonthBook: [String: FocusStreakMonth] = [:]

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Sapphire", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        historyURL = base.appendingPathComponent("focus-sessions.json")
        dailyURL = base.appendingPathComponent("focus-daily.json")
        streakURL = base.appendingPathComponent("focus-streaks.json")
        blocker = FocusBlocker()

        loadHistory()
        loadDaily()
        loadStreaks()

        settingsModel.$settings
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.syncBlocking()
                self?.syncEnvironment()
                self?.syncAmbientFromSettings()
            }
            .store(in: &cancellables)
        syncBlocking()
        syncEnvironment()
    }

    // MARK: - Control

    func startFocusSession() {
        plannedFocusDuration = settingsModel.settings.focusSessionDuration
        plannedBreakDuration = settingsModel.settings.focusBreakDuration
        beginSession()
    }

    func startFocusSession(duration: TimeInterval) {
        plannedFocusDuration = max(1, duration)
        plannedBreakDuration = settingsModel.settings.focusBreakDuration
        beginSession()
    }

    private func beginSession() {
        guard phase == .idle || phase == .finished else { return }
        phase = .focusing
        isFocusBlock = true
        isPaused = false
        blockCount = 0
        sessionCompletedBlocks = 0
        currentBlockIndex = 0
        blockStartDate = Date()
        totalSeconds = plannedFocusDuration
        remainingSeconds = totalSeconds
        startedAt = Date()
        accumulatedElapsed = totalSeconds
        stopTicker()
        startTickerIfNeeded()
        syncBlocking()
        environmentManager.setEnabled(true)
        startAmbientIfEnabled()
        runStartAutomationShortcut()
        refreshShortcutTimerIfNeeded()
        ensureNotificationAuthorization()
        objectWillChange.send()
    }

    func pauseSession() {
        guard isSessionActive, !isPaused else { return }
        isPaused = true
        accumulatedElapsed = remainingSeconds
        startedAt = nil
        stopTicker()
        objectWillChange.send()
    }

    func resumeSession() {
        guard isSessionActive, isPaused else { return }
        isPaused = false
        startedAt = Date()
        stopTicker()
        startTickerIfNeeded()
        objectWillChange.send()
    }

    func togglePause() {
        if isPaused { resumeSession() } else { pauseSession() }
    }

    func stopSession() {
        guard canEndSessionEarly else { return }
        guard isSessionActive || phase == .finished else { return }
        recordCompletedSessionIfNeeded()
        phase = .idle
        isFocusBlock = true
        isPaused = false
        currentBlockIndex = 0
        stopTicker()
        startedAt = nil
        accumulatedElapsed = 0
        syncBlocking()
        teardownEnvironment()
        stopShortcutTimerIfNeeded()
        objectWillChange.send()
    }

    func postponeBreak(by extra: TimeInterval = 5 * 60) {
        guard isSessionActive, isFocusBlock else { return }
        let added = max(0, extra)
        remainingSeconds += added
        accumulatedElapsed = remainingSeconds
        totalSeconds = remainingSeconds
        if !isPaused { startedAt = Date() }
        objectWillChange.send()
    }

    func skipBlock() {
        guard isSessionActive, !isFocusBlock else { return }
        finishCurrentBlock(completion: .breakFinished)
    }

    // MARK: - Ticking

    private func tick() {
        guard isRunning, let startedAt else { return }
        let elapsed = Date().timeIntervalSince(startedAt)
        let newRemaining = max(0, accumulatedElapsed - elapsed)
        if newRemaining != remainingSeconds {
            remainingSeconds = newRemaining
            objectWillChange.send()
        }
        if newRemaining <= 0 {
            finishCurrentBlock(completion: isFocusBlock ? .focusFinished : .breakFinished)
        }
    }

    private func finishCurrentBlock(completion: FocusBlockCompletion) {
        stopTicker()
        startedAt = nil

        switch completion {
        case .focusFinished:
            sessionCompletedBlocks += 1
            recordCompletedSessionIfNeeded()
            blockCount += 1
            if settingsModel.settings.focusBreakEnabled && plannedBreakDuration > 0 {
                phase = .onBreak
                isFocusBlock = false
                currentBlockIndex = blockCount
                totalSeconds = plannedBreakDuration
                remainingSeconds = totalSeconds
                accumulatedElapsed = totalSeconds
                isPaused = false
                startedAt = Date()
                startTickerIfNeeded()
                syncBlocking()
                NotificationCenter.default.post(name: .focusSessionBlockCompleted, object: nil, userInfo: ["phase": "break"])
                postCompletionNotification(
                    title: "Focus block complete ",
                    body: "Great work! Time for a \(Int(plannedBreakDuration / 60)) minute break."
                )
            } else {
                finishSession()
            }
        case .breakFinished:
            phase = .focusing
            isFocusBlock = true
            currentBlockIndex = blockCount
            totalSeconds = plannedFocusDuration
            remainingSeconds = totalSeconds
            accumulatedElapsed = totalSeconds
            isPaused = false
            startedAt = Date()
            blockStartDate = Date()
            startTickerIfNeeded()
            syncBlocking()
            NotificationCenter.default.post(name: .focusSessionBlockCompleted, object: nil, userInfo: ["phase": "focus"])
            postCompletionNotification(
                title: "Break over ",
                body: "Back to it — new focus block started."
            )
        case .sessionFinished:
            finishSession()
        }
        objectWillChange.send()
    }

    private func finishSession() {
        phase = .finished
        isFocusBlock = true
        isPaused = false
        currentBlockIndex = 0
        stopTicker()
        startedAt = nil
        accumulatedElapsed = 0
        syncBlocking()
        teardownEnvironment()
        stopShortcutTimerIfNeeded()
        NotificationCenter.default.post(name: .focusSessionEnded, object: nil)
        postCompletionNotification(
            title: "Focus session complete ",
            body: "You finished \(sessionCompletedBlocks) block\(sessionCompletedBlocks == 1 ? "" : "s"). Total focus today: \(Self.format(completedToday))."
        )
    }

    // MARK: - Local notifications

    private func ensureNotificationAuthorization() {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        }
    }

    private func postCompletionNotification(title: String, body: String) {
        guard settingsModel.settings.focusNotificationsEnabled else { return }
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            let request = UNNotificationRequest(
                identifier: UUID().uuidString,
                content: content,
                trigger: nil
            )
            center.add(request)
        }
    }

    private func recordCompletedSessionIfNeeded() {
        guard isFocusBlock, let blockStart = blockStartDate else { return }
        let now = Date()
        let actual = now.timeIntervalSince(blockStart)
        guard actual >= 5 else { return }
        let record = CompletedFocusSession(
            id: UUID(),
            startedAt: blockStart,
            finishedAt: now,
            plannedDuration: plannedFocusDuration,
            actualDuration: actual,
            completedBlocks: max(1, sessionCompletedBlocks)
        )
        history.insert(record, at: 0)
        if history.count > 200 { history.removeLast(history.count - 200) }
        saveHistory()

        var total = completedToday + actual
        var count = 1
        if var today = dailyRecords.first(where: { $0.date == record.dateKey }) {
            total = today.totalSeconds + actual
            count = today.sessionCount + 1
            dailyRecords.removeAll { $0.date == today.date }
        }
        dailyRecords.insert(FocusDayRecord(date: record.dateKey, totalSeconds: total, sessionCount: count), at: 0)
        if dailyRecords.count > 366 { dailyRecords.removeLast(dailyRecords.count - 366) }
        saveDaily()
        completedToday = dailyRecords
            .filter { $0.date == Calendar.current.dateComponents([.year, .month, .day], from: Date()) }
            .reduce(0) { $0 + $1.totalSeconds }
    }

    // MARK: - History persistence

    private func loadHistory() {
        guard let data = try? Data(contentsOf: historyURL),
              let decoded = try? JSONDecoder().decode([CompletedFocusSession].self, from: data) else {
            return
        }
        history = decoded
    }

    private func saveHistory() {
        if let data = try? JSONEncoder().encode(history) {
            try? data.write(to: historyURL, options: .atomic)
        }
    }

    func clearAllHistory() {
        history.removeAll()
        dailyRecords.removeAll()
        completedToday = 0
        saveHistory()
        saveDaily()
    }

    private var dailyRecords: [FocusDayRecord] = []

    private func loadDaily() {
        guard let data = try? Data(contentsOf: dailyURL),
              let decoded = try? JSONDecoder().decode([FocusDayRecord].self, from: data) else {
            return
        }
        dailyRecords = decoded
        completedToday = dailyRecords
            .filter { $0.date == Calendar.current.dateComponents([.year, .month, .day], from: Date()) }
            .reduce(0) { $0 + $1.totalSeconds }
    }

    private func saveDaily() {
        if let data = try? JSONEncoder().encode(dailyRecords) {
            try? data.write(to: dailyURL, options: .atomic)
        }
    }

    // MARK: - Computed Stats

    var totalFocusTimeAllTime: TimeInterval {
        dailyRecords.reduce(0) { $0 + $1.totalSeconds }
    }

    var totalSessionCountAllTime: Int {
        dailyRecords.reduce(0) { $0 + $1.sessionCount }
    }

    var averageSessionDuration: TimeInterval {
        guard totalSessionCountAllTime > 0 else { return 0 }
        return totalFocusTimeAllTime / Double(totalSessionCountAllTime)
    }

    // MARK: - Streak (immunity days + streak passes)

    private static let immunityLeadDays = 3

    private static let streakBrokenThresholdDays = 3

    private func dayKey(_ components: DateComponents) -> String {
        "\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)"
    }
    private func dayKey(for date: Date) -> String {
        dayKey(Calendar.current.dateComponents([.year, .month, .day], from: date))
    }

    func isStreakCovered(_ date: Date) -> Bool {
        if restoredStreakDayKeys.contains(dayKey(for: date)) { return true }
        let comps = Calendar.current.dateComponents([.year, .month, .day], from: date)
        if immunityDays.contains(where: { dayKey($0.date) == dayKey(comps) }) { return true }
        return dailyRecords.contains { $0.date == comps }
    }
    func isImmunized(_ date: Date) -> Bool {
        let comps = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return immunityDays.contains { dayKey($0.date) == dayKey(comps) }
    }

    var currentStreak: Int {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        var cursor = today
        var streak = 0
        if !isStreakCovered(today) {
            guard let yesterday = cal.date(byAdding: .day, value: -1, to: today) else { return 0 }
            cursor = yesterday
        }
        while isStreakCovered(cursor) {
            streak += 1
            guard let prev = cal.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = prev
        }
        return streak
    }

    var restorableBreakDate: Date? {
        guard streakPassesAvailableThisMonth > 0 else { return nil }
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        var gap = today
        while isStreakCovered(gap), let prev = cal.date(byAdding: .day, value: -1, to: gap) {
            gap = prev
        }
        guard gap < today else { return nil }
        let age = cal.dateComponents([.day], from: gap, to: today).day ?? 0
        guard age >= Self.streakBrokenThresholdDays else { return nil }
        guard let before = cal.date(byAdding: .day, value: -1, to: gap),
              isStreakCovered(before) else { return nil }
        return gap
    }

    var canRestoreStreak: Bool { restorableBreakDate != nil }

    @discardableResult
    func restoreStreak() -> Bool {
        guard let breakDay = restorableBreakDate else { return false }
        restoredStreakDayKeys.insert(dayKey(for: breakDay))
        recordStreakPassUsed()
        saveStreaks()
        objectWillChange.send()
        return true
    }

    // MARK: Monthly streak pass allowance (by subscription tier)

    var streakPassBaseAllowance: Int {
        switch SubscriptionAccess.resolvedTier() {
        case .ultra: return 4
        case .pro: return 3
        case .basic: return 2
        case .free: return 1
        }
    }

    private var currentMonthKey: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM"
        return f.string(from: Date())
    }

    private var currentStreakMonth: FocusStreakMonth {
        get { streakMonthBook[currentMonthKey] ?? FocusStreakMonth() }
        set { streakMonthBook[currentMonthKey] = newValue }
    }

    var streakPassesUsedThisMonth: Int { currentStreakMonth.used }
    var streakPassesAvailableThisMonth: Int {
        max(0, streakPassBaseAllowance - currentStreakMonth.used)
    }

    private func recordStreakPassUsed() {
        var month = currentStreakMonth
        month.used += 1
        currentStreakMonth = month
    }

    // MARK: Immunity days

    func canScheduleImmunity(on date: Date) -> Bool {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let target = cal.startOfDay(for: date)
        let daysAhead = cal.dateComponents([.day], from: today, to: target).day ?? 0
        return daysAhead >= Self.immunityLeadDays
    }

    @discardableResult
    func scheduleImmunity(on date: Date) -> Bool {
        guard canScheduleImmunity(on: date) else { return false }
        let comps = Calendar.current.dateComponents([.year, .month, .day], from: date)
        guard !immunityDays.contains(where: { dayKey($0.date) == dayKey(comps) }) else { return false }
        immunityDays.append(FocusImmunityDay(id: UUID(), reportedAt: Date(), date: comps))
        saveStreaks()
        objectWillChange.send()
        return true
    }

    func removeImmunityDay(id: UUID) {
        immunityDays.removeAll { $0.id == id }
        saveStreaks()
        objectWillChange.send()
    }

    var allImmunityDays: [FocusImmunityDay] {
        immunityDays.sorted { a, b in
            (a.date.year ?? 0, a.date.month ?? 0, a.date.day ?? 0)
                < (b.date.year ?? 0, b.date.month ?? 0, b.date.day ?? 0)
        }
    }

    var pastImmunityDays: [FocusImmunityDay] {
        let comps = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        let key = dayKey(comps)
        return allImmunityDays.filter { dayKey($0.date) <= key }.reversed()
    }

    var upcomingImmunityDays: [FocusImmunityDay] {
        let comps = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        let key = dayKey(comps)
        return allImmunityDays.filter { dayKey($0.date) >= key }
    }

    var streakSnapshot: FocusStreakSnapshot {
        let cal = Calendar.current
        return FocusStreakSnapshot(
            streak: currentStreak,
            canRestore: canRestoreStreak,
            brokenDay: restorableBreakDate.map { cal.dateComponents([.year, .month, .day], from: $0) },
            passesAvailableThisMonth: streakPassesAvailableThisMonth,
            passesBaseAllowance: streakPassBaseAllowance,
            passesUsedThisMonth: streakPassesUsedThisMonth,
            tierName: SubscriptionFeatureCatalog.tierDisplayName(SubscriptionAccess.resolvedTier()),
            upcomingImmunityDays: upcomingImmunityDays.map { $0.date }
        )
    }

    private func loadStreaks() {
        guard let data = try? Data(contentsOf: streakURL) else { return }
        struct Persisted: Codable {
            var immunityDays: [FocusImmunityDay]
            var restoredStreakDayKeys: Set<String>
            var streakMonthBook: [String: FocusStreakMonth]
        }
        guard let decoded = try? JSONDecoder().decode(Persisted.self, from: data) else { return }
        immunityDays = decoded.immunityDays
        restoredStreakDayKeys = decoded.restoredStreakDayKeys
        streakMonthBook = decoded.streakMonthBook
    }

    private func saveStreaks() {
        struct Persisted: Codable {
            var immunityDays: [FocusImmunityDay]
            var restoredStreakDayKeys: Set<String>
            var streakMonthBook: [String: FocusStreakMonth]
        }
        let payload = Persisted(
            immunityDays: immunityDays,
            restoredStreakDayKeys: restoredStreakDayKeys,
            streakMonthBook: streakMonthBook
        )
        if let data = try? JSONEncoder().encode(payload) {
            try? data.write(to: streakURL, options: .atomic)
        }
    }

    var bestDay: (date: DateComponents, seconds: TimeInterval)? {
        dailyRecords
            .filter { $0.totalSeconds > 0 }
            .max(by: { $0.totalSeconds < $1.totalSeconds })
            .map { (date: $0.date, seconds: $0.totalSeconds) }
    }

    var weeklyData: [(label: String, seconds: TimeInterval)] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        return (0..<7).reversed().map { daysAgo in
            let date = cal.date(byAdding: .day, value: -daysAgo, to: today)!
            let key = cal.dateComponents([.year, .month, .day], from: date)
            let seconds = dailyRecords
                .filter { $0.date == key }
                .reduce(0) { $0 + $1.totalSeconds }
            let label: String = {
                if daysAgo == 0 { return "Today" }
                if daysAgo == 1 { return "Yest" }
                let fmt = DateFormatter(); fmt.dateFormat = "EEE"
                return fmt.string(from: date)
            }()
            return (label, seconds)
        }
    }

    // MARK: - Blocking

    private func syncBlocking() {
        let settings = settingsModel.settings
        let enabled = isSessionActive && (isFocusBlock || settings.focusBlockingDuringBreaks)
        blocker.setBlocking(
            enabled: enabled,
            apps: Array(settings.focusBlockedApps),
            websites: Array(settings.focusBlockedWebsites),
            intensity: settings.focusIntensity,
            strictCooldown: settings.focusStrictUnblockCooldown,
            mode: settings.focusBlockingMode,
            allowedApps: Array(settings.focusAllowedApps)
        )
        websiteBlocker.setEnabled(
            enabled && !settings.focusBlockedWebsites.isEmpty,
            domains: settings.focusBlockedWebsites,
            productiveAccessValidator: { [weak self] domain in
                self?.requestProductiveWebsiteAccess(domain: domain) ?? false
            }
        )
        syncNotificationSuppression(enabled: enabled, settings: settings)
    }

    private func syncEnvironment() {
        let settings = settingsModel.settings
        environmentManager.configure(
            dimInactive: settings.focusDimInactiveApps,
            dimOpacity: settings.focusDimInactiveOpacity,
            disableDimInMissionControl: settings.focusDisableDimInMissionControl,
            hideWallpaper: settings.focusHideWallpaper,
            appLimitEnabled: settings.focusAppLimitEnabled,
            appLimit: settings.focusAppLimit
        )
    }

    private func teardownEnvironment() {
        environmentManager.setEnabled(false)
        websiteBlocker.setEnabled(false, domains: [])
        ambientManager.stop()
        runEndAutomationShortcut()
    }

    // MARK: - Ambient sounds

    private func startAmbientIfEnabled() {
        let settings = settingsModel.settings
        guard settings.focusAmbientSoundEnabled else { return }
        ambientManager.start(type: settings.focusAmbientSoundType, volume: settings.focusAmbientSoundVolume)
    }

    private func syncAmbientFromSettings() {
        let settings = settingsModel.settings
        guard isSessionActive else { return }
        if settings.focusAmbientSoundEnabled {
            if !ambientManager.isPlaying {
                ambientManager.start(type: settings.focusAmbientSoundType, volume: settings.focusAmbientSoundVolume)
            } else {
                ambientManager.setType(settings.focusAmbientSoundType)
                ambientManager.volume = settings.focusAmbientSoundVolume
            }
        } else if ambientManager.isPlaying {
            ambientManager.stop()
        }
    }

    // MARK: - Shortcuts automation (focusedOS-style start/stop hooks)

    private func runStartAutomationShortcut() {
        let name = settingsModel.settings.focusStartShortcutName
        guard !name.isEmpty else { return }
        runShortcut(named: name)
    }

    private func runEndAutomationShortcut() {
        let name = settingsModel.settings.focusEndShortcutName
        guard !name.isEmpty else { return }
        runShortcut(named: name)
    }

    private func runShortcut(named name: String) {
        ShortcutsCatalog.run(name: name)
    }

    static func refreshInstalledShortcuts() {
        ShortcutsCatalog.shared.requestRefresh(force: true)
    }

    private func syncNotificationSuppression(enabled: Bool, settings: Settings) {
        guard enabled, settings.focusIntensity.suppressesNotifications else {
            notificationSuppressor.restoreAll()
            return
        }
        notificationSuppressor.suppress(Array(settings.focusBlockedApps))
    }

    // MARK: - System Clock integration (Shortcuts)

    private static let shortcutNames: [String: String] = [
        "startTimer": "Start Timer",
        "stopTimer": "Stop Timer",
        "startStopwatch": "Start Stopwatch",
        "stopStopwatch": "Stop the Stopwatch",
        "lapStopwatch": "Lap Stopwatch",
        "resetStopwatch": "Reset Stopwatch",
    ]

    func runShortcutCommand(_ command: String, value: TimeInterval? = nil) {
        let settings = settingsModel.settings
        guard settings.focusShortcutsEnabled,
              let name = Self.shortcutNames[command] else { return }

        Task {
            let available = await ShortcutsCatalog.shared.names()
            guard available.contains(name) else { return }
            ShortcutsCatalog.run(name: name, argument: value.map { String(Int($0)) })
        }
    }

    private func refreshShortcutTimerIfNeeded() {
        let settings = settingsModel.settings
        switch settings.focusShortcutSyncMode {
        case .none:
            return
        case .timer:
            runShortcutCommand("startTimer", value: totalSeconds)
        case .stopwatch:
            runShortcutCommand("startStopwatch")
        }
    }

    private func stopShortcutTimerIfNeeded() {
        let settings = settingsModel.settings
        switch settings.focusShortcutSyncMode {
        case .none:
            return
        case .timer:
            runShortcutCommand("stopTimer")
        case .stopwatch:
            runShortcutCommand("stopStopwatch")
        }
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let focusSessionBlockCompleted = Notification.Name("com.sapphire.focusBlockCompleted")
    static let focusSessionEnded = Notification.Name("com.sapphire.focusSessionEnded")
    static let focusRestrictedAppOpened = Notification.Name("com.sapphire.focusRestrictedAppOpened")
}