//
//  TimerManager.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-09-27
//

import Foundation
import Combine
import AppKit
import UserNotifications

// MARK: - Main TimerManager Class

enum ActiveTimerType {
    case none, stopwatch, system
}

enum TimerDeadlineClock {
    static func now() -> TimeInterval {
        TimeInterval(clock_gettime_nsec_np(CLOCK_MONOTONIC)) / 1_000_000_000
    }

    static func remaining(until deadline: TimeInterval, now: TimeInterval) -> TimeInterval {
        max(0, deadline - now)
    }

    static func delayUntilNext(_ deadlines: [TimeInterval], now: TimeInterval) -> TimeInterval? {
        deadlines.min().map { max(0, $0 - now) }
    }
}

struct SapphireTimer: Equatable, Identifiable {
    let id: String
    var label: String
    var state: ActiveTimerType
    var remainingTimeOnLastUpdate: TimeInterval
    var fireDate: Date?
    var deadline: TimeInterval?

    var remainingTime: TimeInterval {
        guard state == .system else { return max(0, remainingTimeOnLastUpdate) }
        if let deadline {
            return TimerDeadlineClock.remaining(until: deadline, now: TimerDeadlineClock.now())
        }
        guard let fireDate else { return max(0, remainingTimeOnLastUpdate) }
        return max(0, fireDate.timeIntervalSinceNow)
    }

    var isRunning: Bool { state == .system }

    mutating func arm(remaining: TimeInterval) {
        remainingTimeOnLastUpdate = remaining
        fireDate = Date().addingTimeInterval(remaining)
        deadline = TimerDeadlineClock.now() + remaining
    }

    mutating func disarm(remaining: TimeInterval) {
        remainingTimeOnLastUpdate = remaining
        fireDate = nil
        deadline = nil
    }
}

private struct StoredSapphireTimer: Codable {
    var id: String
    var label: String
    var stateRaw: Int
    var remaining: TimeInterval
    var fireDate: Date?

    init(_ timer: SapphireTimer) {
        id = timer.id
        label = timer.label
        stateRaw = timer.isRunning ? 3 : 2
        remaining = timer.remainingTimeOnLastUpdate
        fireDate = timer.fireDate
    }

    var asSapphireTimer: SapphireTimer {
        var timer = SapphireTimer(
            id: id,
            label: label,
            state: stateRaw == 3 ? .system : .none,
            remainingTimeOnLastUpdate: remaining,
            fireDate: fireDate,
            deadline: nil
        )
        if timer.isRunning, let fireDate {
            timer.deadline = TimerDeadlineClock.now() + fireDate.timeIntervalSinceNow
        }
        return timer
    }
}

struct SystemTimerInfo: Equatable, Identifiable {
    let id: String
    var state: ActiveTimerType
    var remainingTimeOnLastUpdate: TimeInterval
    var dateOfLastUpdate: Date
    var remainingTime: TimeInterval {
        if state == .system {
            let elapsed = Date().timeIntervalSince(dateOfLastUpdate)
            return max(0, remainingTimeOnLastUpdate - elapsed)
        } else {
            return max(0, remainingTimeOnLastUpdate)
        }
    }
}

struct SystemStopwatchInfo: Equatable, Identifiable {
    let id: String
    var state: ActiveTimerType
    var startTime: Date
    var pausedOffset: TimeInterval
    var laps: [TimeInterval]
    var elapsedTime: TimeInterval {
        if state == .stopwatch {
            return pausedOffset + Date().timeIntervalSince(startTime)
        } else {
            return pausedOffset
        }
    }
}

private struct LogEntry: Decodable {
    let eventMessage: String?
    enum CodingKeys: String, CodingKey { case eventMessage = "eventMessage" }
}

class TimerManager: ObservableObject {
    @Published private(set) var activeTimers: [SystemTimerInfo] = []
    @Published private(set) var activeStopwatches: [SystemStopwatchInfo] = []
    @Published private(set) var sapphireTimers: [SapphireTimer] = []
    @Published private(set) var ringingTimers: [SapphireTimer] = []
    @Published var isRunning: Bool = false
    @Published private(set) var activeTimer: ActiveTimerType = .none

    var ringingTimer: SapphireTimer? { ringingTimers.first }
    var hasRingingTimer: Bool { !ringingTimers.isEmpty }
    var displayTime: TimeInterval {
        guard let currentID = displayedTimerID else { return 0 }
        switch activeTimer {
        case .system:
            if let sapphire = sapphireTimers.first(where: { $0.id == currentID }) {
                return sapphire.remainingTime
            }
            return activeTimers.first(where: { $0.id == currentID })?.remainingTime ?? 0
        case .stopwatch:
            return activeStopwatches.first(where: { $0.id == currentID })?.elapsedTime ?? 0
        case .none:
            return 0
        }
    }

    private var completionTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var logStreamProcess: Process?
    private var pipe: Pipe?
    private var logStreamStdin: Pipe?
    private var logStreamStartedAt: TimeInterval = 0
    private var logStreamRestartAttempts = 0
    private var logStreamRestartWorkItem: DispatchWorkItem?
    private var isClockAppRunning = false
    private var systemObservers: [(NotificationCenter, NSObjectProtocol)] = []
    private static let clockBundleIdentifier = "com.apple.clock"
    private static var didReapOrphanedLogStreams = false
    private var primaryTimerID: String?
    private var displayedTimerID: String?
    private var syncGeneration = 0
    private var plistSyncWorkItem: DispatchWorkItem?
    private var logReadBuffer = Data()
    private let maxLogRecordBytes = 1_048_576
    private var logSyncPending = false
    private var alarmSound: NSSound?
    private lazy var sapphireTimerSaveURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Sapphire", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("sapphire-timers.json")
    }()

    init() {
        Publishers.CombineLatest3($activeTimers, $activeStopwatches, $sapphireTimers)
            .map { timers, stopwatches, sapphire in
                !timers.filter { $0.state == .system }.isEmpty
                    || !stopwatches.filter { $0.state == .stopwatch }.isEmpty
                    || !sapphire.filter { $0.state == .system }.isEmpty
            }
            .receive(on: DispatchQueue.main)
            .assign(to: &$isRunning)

        loadSapphireTimers()
        syncStateWithPlist()
        installSystemObservers()
        refreshClockAppRunningState()
    }

    deinit {
        plistSyncWorkItem?.cancel()
        logStreamRestartWorkItem?.cancel()
        for (center, token) in systemObservers { center.removeObserver(token) }
        stopSystemTimerMonitoring()
        completionTimer?.invalidate()
        alarmSound?.stop()
        alarmSound?.loops = false
    }

    // MARK: - Sapphire-Owned Timers

    @discardableResult
    func startSapphireTimer(duration: TimeInterval, label: String? = nil) -> String? {
        guard duration > 0 else { return nil }
        var timer = SapphireTimer(
            id: UUID().uuidString,
            label: label ?? "Timer",
            state: .system,
            remainingTimeOnLastUpdate: duration,
            fireDate: nil,
            deadline: nil
        )
        timer.arm(remaining: duration)
        sapphireTimers.append(timer)
        persistSapphireTimers()
        scheduleCompletionNotification(for: timer)
        selectTimerToDisplay()
        return timer.id
    }

    func pauseSapphireTimer(id: String) {
        guard let index = sapphireTimers.firstIndex(where: { $0.id == id }) else { return }
        let remaining = sapphireTimers[index].remainingTime
        sapphireTimers[index].state = .none
        sapphireTimers[index].disarm(remaining: remaining)
        removeCompletionNotification(for: id)
        persistSapphireTimers()
        selectTimerToDisplay()
    }

    func resumeSapphireTimer(id: String) {
        guard let index = sapphireTimers.firstIndex(where: { $0.id == id }) else { return }
        guard sapphireTimers[index].remainingTimeOnLastUpdate > 0 else {
            removeSapphireTimer(id: id)
            return
        }
        sapphireTimers[index].state = .system
        sapphireTimers[index].arm(remaining: sapphireTimers[index].remainingTimeOnLastUpdate)
        scheduleCompletionNotification(for: sapphireTimers[index])
        persistSapphireTimers()
        selectTimerToDisplay()
    }

    func addOneMinuteToSapphireTimer(id: String) {
        guard let index = sapphireTimers.firstIndex(where: { $0.id == id }) else { return }
        let extendedRemaining = sapphireTimers[index].remainingTime + 60
        sapphireTimers[index].remainingTimeOnLastUpdate = extendedRemaining
        if sapphireTimers[index].state == .system {
            sapphireTimers[index].arm(remaining: extendedRemaining)
            scheduleCompletionNotification(for: sapphireTimers[index])
        }
        persistSapphireTimers()
        selectTimerToDisplay()
    }

    func removeSapphireTimer(id: String) {
        sapphireTimers.removeAll { $0.id == id }
        ringingTimers.removeAll { $0.id == id }
        removeCompletionNotification(for: id)
        stopAlarmSoundIfIdle()
        persistSapphireTimers()
        selectTimerToDisplay()
    }

    func dismissRingingTimer(id: String) {
        guard ringingTimers.contains(where: { $0.id == id }) else { return }
        ringingTimers.removeAll { $0.id == id }
        sapphireTimers.removeAll { $0.id == id }
        removeCompletionNotification(for: id)
        stopAlarmSoundIfIdle()
        persistSapphireTimers()
        selectTimerToDisplay()
    }

    func dismissAllRingingTimers() {
        let ringingIDs = Set(ringingTimers.map(\.id))
        guard !ringingIDs.isEmpty else { return }
        ringingTimers.removeAll()
        sapphireTimers.removeAll { ringingIDs.contains($0.id) }
        for id in ringingIDs {
            removeCompletionNotification(for: id)
        }
        stopAlarmSoundIfIdle()
        persistSapphireTimers()
        selectTimerToDisplay()
    }

    func clearFinishedSapphireTimers() {
        let hadFinished = sapphireTimers.contains { $0.remainingTime <= 0 }
        let finishedIDs = Set(sapphireTimers.lazy.filter { $0.remainingTime <= 0 }.map(\.id))
        sapphireTimers.removeAll { $0.remainingTime <= 0 }
        ringingTimers.removeAll { finishedIDs.contains($0.id) }
        if hadFinished {
            for id in finishedIDs {
                removeCompletionNotification(for: id)
            }
            stopAlarmSoundIfIdle()
            persistSapphireTimers()
            selectTimerToDisplay()
        }
    }

    private func persistSapphireTimers() {
        let stored = sapphireTimers.map(StoredSapphireTimer.init)
        guard let data = try? JSONEncoder().encode(stored) else { return }
        try? data.write(to: sapphireTimerSaveURL, options: .atomic)
    }

    private func loadSapphireTimers() {
        guard let data = try? Data(contentsOf: sapphireTimerSaveURL),
              let stored = try? JSONDecoder().decode([StoredSapphireTimer].self, from: data) else {
            return
        }
        sapphireTimers = stored
            .map(\.asSapphireTimer)
            .filter { $0.remainingTime > 0 }
        for timer in sapphireTimers where timer.isRunning {
            scheduleCompletionNotification(for: timer)
        }
    }

    func pauseTimer(id: String) {
        pauseSapphireTimer(id: id)
    }

    func resumeTimer(id: String) {
        resumeSapphireTimer(id: id)
    }

    func stopTimer(id: String) {
        removeSapphireTimer(id: id)
    }

    private struct PlistTimerEvent {
        let id: String
        let stateInt: Int
        let timeValue: TimeInterval
    }

    private func syncStateWithPlist() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.syncStateWithPlist() }
            return
        }

        plistSyncWorkItem?.cancel()
        syncGeneration &+= 1
        let generation = syncGeneration
        let work = DispatchWorkItem { [weak self] in
            guard let result = ProcessRunner.runSync(
                executablePath: "/usr/bin/defaults",
                arguments: ["export", "com.apple.mobiletimerd", "-"],
                timeout: 10
            ), result.succeeded,
               let plist = (try? PropertyListSerialization.propertyList(
                   from: result.stdoutData, options: [], format: nil)) as? [String: Any],
               let parsed = Self.parseTimerEvents(from: plist)
            else {
                print("[TimerManager Plist Sync]: Failed to read or parse plist structure.")
                return
            }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.syncGeneration == generation else { return }
                self.applyPlistTimerEvents(validIDs: parsed.validIDs, entries: parsed.entries)
            }
        }
        plistSyncWorkItem = work
        DispatchQueue.global(qos: .utility).async(execute: work)
    }

    private static func parseTimerEvents(from plist: [String: Any]) -> (validIDs: Set<String>, entries: [PlistTimerEvent])? {
        guard let timersDict = plist["MTTimers"] as? [String: Any],
              let timersArray = timersDict["MTTimers"] as? [[String: Any]] else { return nil }
        var validPlistTimerIDs = Set<String>()
        var entries: [PlistTimerEvent] = []
        for timerDict in timersArray {
            guard let timerData = timerDict["$MTTimer"] as? [String: Any],
                  let timerID = timerData["MTTimerID"] as? String,
                  let timerStateInt = timerData["MTTimerState"] as? Int,
                  timerStateInt != 1 else { continue }
            validPlistTimerIDs.insert(timerID)
            let plistState: ActiveTimerType = (timerStateInt == 3) ? .system : .none
            var timeValueFromPlist: TimeInterval
            if plistState == .none,
               let fireTimeDict = timerData["MTTimerFireTime"] as? [String: Any],
               let intervalWrapper = fireTimeDict["$MTTimerTimeInterval"] as? [String: Any],
               let interval = intervalWrapper["MTTimerTimeInterval"] as? TimeInterval {
                timeValueFromPlist = interval
            } else {
                timeValueFromPlist = timerData["MTTimerDuration"] as? TimeInterval ?? 0
            }
            entries.append(PlistTimerEvent(id: timerID, stateInt: timerStateInt, timeValue: timeValueFromPlist))
        }
        return (validIDs: validPlistTimerIDs, entries: entries)
    }

    private func applyPlistTimerEvents(validIDs: Set<String>, entries: [PlistTimerEvent]) {
        for event in entries {
            let plistState: ActiveTimerType = (event.stateInt == 3) ? .system : .none
            if let index = activeTimers.firstIndex(where: { $0.id == event.id }) {
                var timer = activeTimers[index]
                timer.state = plistState
                if plistState == .none {
                    timer.remainingTimeOnLastUpdate = event.timeValue
                    timer.dateOfLastUpdate = Date()
                }
                activeTimers[index] = timer
            } else {
                activeTimers.append(SystemTimerInfo(id: event.id, state: plistState, remainingTimeOnLastUpdate: event.timeValue, dateOfLastUpdate: Date()))
            }
        }
        activeTimers.removeAll { !validIDs.contains($0.id) }
        selectTimerToDisplay()
    }

    // MARK: - System (Clock app) monitoring

    private static let logStreamWrapperScript = """
    stream_pid=$$
    exec 3<&0
    ( while read -r line <&3; do :; done; kill -TERM "$stream_pid" 2>/dev/null ) >/dev/null 2>&1 &
    exec /usr/bin/log stream --predicate "$1" --style ndjson </dev/null 3<&-
    """
    private static let logStreamPredicate = "subsystem == \"com.apple.mobiletimer.logging\" AND (process == \"Clock\" OR process == \"timed\")"

    static func needsLogStream(clockAppRunning: Bool, hasRunningSystemTimer: Bool, hasRunningStopwatch: Bool) -> Bool {
        clockAppRunning || hasRunningSystemTimer || hasRunningStopwatch
    }

    static func logStreamRestartDelay(attempt: Int) -> TimeInterval {
        min(60, pow(2, Double(max(0, min(attempt, 6)))))
    }

    private func updateLogStreamDemand() {
        let needed = Self.needsLogStream(
            clockAppRunning: isClockAppRunning,
            hasRunningSystemTimer: activeTimers.contains { $0.state == .system },
            hasRunningStopwatch: activeStopwatches.contains { $0.state == .stopwatch }
        )
        if needed {
            if logStreamProcess == nil, logStreamRestartWorkItem == nil {
                startSystemTimerMonitoring()
            }
        } else {
            logStreamRestartWorkItem?.cancel()
            logStreamRestartWorkItem = nil
            logStreamRestartAttempts = 0
            stopSystemTimerMonitoring()
        }
    }

    private func installSystemObservers() {
        let workspace = NSWorkspace.shared.notificationCenter

        func observe(_ center: NotificationCenter, _ name: Notification.Name, _ handler: @escaping (TimerManager, Notification) -> Void) {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                guard let self else { return }
                handler(self, note)
            }
            systemObservers.append((center, token))
        }

        observe(workspace, NSWorkspace.didWakeNotification) { manager, _ in
            manager.scheduleNextCompletionTimer()
        }
        observe(NotificationCenter.default, .NSSystemClockDidChange) { manager, _ in
            manager.realignWallClockFireDates()
        }
        observe(workspace, NSWorkspace.didLaunchApplicationNotification) { manager, note in
            guard Self.isClockApp(note) else { return }
            manager.isClockAppRunning = true
            manager.syncStateWithPlist()
            manager.updateLogStreamDemand()
        }
        observe(workspace, NSWorkspace.didTerminateApplicationNotification) { manager, note in
            guard Self.isClockApp(note) else { return }
            manager.isClockAppRunning = false
            manager.syncStateWithPlist()
            manager.updateLogStreamDemand()
        }
    }

    private static func isClockApp(_ note: Notification) -> Bool {
        (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier == clockBundleIdentifier
    }

    private func refreshClockAppRunningState() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let running = !NSRunningApplication.runningApplications(withBundleIdentifier: Self.clockBundleIdentifier).isEmpty
            DispatchQueue.main.async {
                guard let self else { return }
                self.isClockAppRunning = running
                self.updateLogStreamDemand()
            }
        }
    }

    private func realignWallClockFireDates() {
        var changed = false
        for index in sapphireTimers.indices where sapphireTimers[index].isRunning {
            let remaining = sapphireTimers[index].remainingTime
            sapphireTimers[index].fireDate = Date().addingTimeInterval(remaining)
            scheduleCompletionNotification(for: sapphireTimers[index])
            changed = true
        }
        if changed { persistSapphireTimers() }
        scheduleNextCompletionTimer()
    }

    private static func reapOrphanedLogStreamsOnce() {
        guard !didReapOrphanedLogStreams else { return }
        didReapOrphanedLogStreams = true
        DispatchQueue.global(qos: .utility).async {
            guard let result = ProcessRunner.runSync(
                executablePath: "/bin/ps",
                arguments: ["-axo", "pid=,ppid=,uid=,command="],
                timeout: 5
            ), result.succeeded else { return }
            let uid = getuid()
            for line in result.stdout.split(separator: "\n") {
                let fields = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
                guard fields.count == 4,
                      let pid = pid_t(fields[0]), fields[1] == "1",
                      uid_t(fields[2]) == uid,
                      fields[3].hasPrefix("/usr/bin/log stream"),
                      fields[3].contains("com.apple.mobiletimer.logging") else { continue }
                kill(pid, SIGTERM)
            }
        }
    }

    private func startSystemTimerMonitoring() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.startSystemTimerMonitoring() }
            return
        }
        guard logStreamProcess == nil else { return }
        Self.reapOrphanedLogStreamsOnce()
        logStreamRestartWorkItem = nil
        logReadBuffer.removeAll(keepingCapacity: true)

        let newPipe = Pipe()
        let stdinPipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", Self.logStreamWrapperScript, "sapphire-timer-log", Self.logStreamPredicate]
        process.standardOutput = newPipe
        process.standardError = FileHandle.nullDevice
        process.standardInput = stdinPipe
        newPipe.fileHandleForReading.readabilityHandler = { [weak self, weak process] fileHandle in
            let data = fileHandle.availableData
            guard !data.isEmpty else {
                fileHandle.readabilityHandler = nil
                return
            }
            DispatchQueue.main.async {
                guard let self, let process, self.logStreamProcess === process else { return }
                self.parseLogOutput(from: data)
            }
        }
        process.terminationHandler = { [weak self] terminatedProcess in
            DispatchQueue.main.async {
                self?.handleLogStreamExit(terminatedProcess)
            }
        }

        pipe = newPipe
        logStreamStdin = stdinPipe
        logStreamProcess = process
        logStreamStartedAt = TimerDeadlineClock.now()

        DispatchQueue.global(qos: .utility).async { [weak self, weak process] in
            guard let process else { return }
            do {
                try process.run()
            } catch {
                DispatchQueue.main.async {
                    guard let self, self.logStreamProcess === process else { return }
                    print("[TimerManager] Failed to start log stream: \(error)")
                    self.handleLogStreamExit(process)
                }
            }
        }
    }

    private func stopSystemTimerMonitoring() {
        guard let process = logStreamProcess else { return }
        process.terminationHandler = nil
        pipe?.fileHandleForReading.readabilityHandler = nil
        try? logStreamStdin?.fileHandleForWriting.close()
        logStreamProcess = nil
        pipe = nil
        logStreamStdin = nil
        logReadBuffer.removeAll(keepingCapacity: false)
        Self.terminate(process)
    }

    private static func terminate(_ process: Process) {
        DispatchQueue.global(qos: .utility).async {
            guard process.isRunning else { return }
            let pid = process.processIdentifier
            process.terminate()
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2) {
                guard process.isRunning else { return }
                kill(pid, SIGKILL)
            }
        }
    }

    private func handleLogStreamExit(_ process: Process) {
        guard logStreamProcess === process else { return }
        pipe?.fileHandleForReading.readabilityHandler = nil
        try? logStreamStdin?.fileHandleForWriting.close()
        logStreamProcess = nil
        pipe = nil
        logStreamStdin = nil
        logReadBuffer.removeAll(keepingCapacity: true)

        if TimerDeadlineClock.now() - logStreamStartedAt > 30 {
            logStreamRestartAttempts = 0
        }
        let delay = Self.logStreamRestartDelay(attempt: logStreamRestartAttempts)
        logStreamRestartAttempts += 1

        logStreamRestartWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.logStreamRestartWorkItem = nil
            self.updateLogStreamDemand()
        }
        logStreamRestartWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func parseLogOutput(from data: Data) {
        logReadBuffer.append(data)

        let records = logReadBuffer.split(
            separator: UInt8(ascii: "\n"),
            omittingEmptySubsequences: false
        )
        guard records.count > 1 else {
            if logReadBuffer.count > maxLogRecordBytes {
                print("[TimerManager] Discarding oversized unterminated log record")
                logReadBuffer.removeAll(keepingCapacity: true)
            }
            return
        }

        logReadBuffer = Data(records.last ?? Data.SubSequence())
        for lineData in records.dropLast() where !lineData.isEmpty {
            guard let entry = try? JSONDecoder().decode(LogEntry.self, from: Data(lineData)),
                  let message = entry.eventMessage else { continue }
            handleLogMessage(message)
        }
    }

    private func handleLogMessage(_ message: String) {
        if message.contains("notifying observers for timer update") || message.contains("notifying observers for next timer change") {
            schedulePlistSync(after: 0.1)
            return
        }
        if message.contains("addTimer:") || message.contains("Pausing a timer:") || message.contains("Stopping a timer:") || message.contains("updateTimer:") {
            schedulePlistSync(after: 0.2)
            return
        }
        if let timerID = extractID(from: message, after: "notified next timer changed: ") {
            self.primaryTimerID = (timerID == "(null)") ? nil : timerID
        } else if let range = message.range(of: "remainingTime: ") {
            let remainingTimeString = message[range.upperBound...]
            if let time = TimeInterval(remainingTimeString.split(separator: " ").first ?? "") {
                if let primaryID = primaryTimerID, let index = activeTimers.firstIndex(where: { $0.id == primaryID }) {
                    var timer = activeTimers[index]
                    timer.remainingTimeOnLastUpdate = time
                    timer.dateOfLastUpdate = Date()
                    activeTimers[index] = timer
                }
            }
        } else if let stopwatchID = extractID(from: message, after: "for: ") {
            if message.contains("didStartLapTimerForStopwatch") {
                if let index = activeStopwatches.firstIndex(where: { $0.id == stopwatchID }) {
                    var stopwatch = activeStopwatches[index]
                    stopwatch.state = .stopwatch
                    stopwatch.startTime = Date()
                    activeStopwatches[index] = stopwatch
                } else {
                    activeStopwatches.append(SystemStopwatchInfo(id: stopwatchID, state: .stopwatch, startTime: Date(), pausedOffset: 0, laps: []))
                }
                selectTimerToDisplay()
            } else if message.contains("didPauseLapTimerForStopwatch") {
                if let index = activeStopwatches.firstIndex(where: { $0.id == stopwatchID }) {
                    var stopwatch = activeStopwatches[index]
                    stopwatch.pausedOffset = stopwatch.elapsedTime
                    stopwatch.state = .none
                    activeStopwatches[index] = stopwatch
                    selectTimerToDisplay()
                }
            } else if message.contains("didResetLapTimerForStopwatch") {
                activeStopwatches.removeAll(where: { $0.id == stopwatchID })
                selectTimerToDisplay()
            }
        } else if message.contains("adding stopwatch lap:"), let lapTime = extractLapTime(from: message) {
            if let index = activeStopwatches.firstIndex(where: { $0.state == .stopwatch }) {
                var stopwatch = activeStopwatches[index]
                stopwatch.laps.insert(lapTime, at: 0)
                activeStopwatches[index] = stopwatch
            }
        }
    }

    private func schedulePlistSync(after delay: TimeInterval) {
        guard !logSyncPending else { return }
        logSyncPending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            self.logSyncPending = false
            self.syncStateWithPlist()
        }
    }

    private func selectTimerToDisplay() {
        let runningSapphireTimers = sapphireTimers.filter { $0.state == .system }
        let runningSystemTimers = activeTimers.filter { $0.state == .system }
        var newTimerID: String? = nil
        var newActiveTimerType: ActiveTimerType = .none
        if let timerWithLeastTime = runningSapphireTimers.min(by: { $0.remainingTime < $1.remainingTime }) {
            newTimerID = timerWithLeastTime.id
            newActiveTimerType = .system
        } else if let timerWithLeastTime = runningSystemTimers.min(by: { $0.remainingTime < $1.remainingTime }) {
            newTimerID = timerWithLeastTime.id
            newActiveTimerType = .system
        } else if let runningStopwatch = activeStopwatches.first(where: { $0.state == .stopwatch }) {
            newTimerID = runningStopwatch.id
            newActiveTimerType = .stopwatch
        }
        self.displayedTimerID = newTimerID
        self.activeTimer = newTimerID != nil ? newActiveTimerType : .none
        scheduleNextCompletionTimer()
        updateLogStreamDemand()
    }

    // MARK: - Sapphire Timer Completion

    private func checkSapphireTimerCompletion() {
        var didFinishTimer = false
        for index in sapphireTimers.indices {
            guard sapphireTimers[index].state == .system,
                  sapphireTimers[index].remainingTime <= 0 else { continue }
            sapphireTimers[index].state = .none
            sapphireTimers[index].disarm(remaining: 0)
            didFinishTimer = true
            beginRinging(for: sapphireTimers[index])
        }
        if didFinishTimer {
            persistSapphireTimers()
            selectTimerToDisplay()
        }
    }

    private func beginRinging(for timer: SapphireTimer) {
        if !ringingTimers.contains(where: { $0.id == timer.id }) {
            ringingTimers.append(timer)
        }
        startAlarmSoundIfNeeded()
    }

    private func startAlarmSoundIfNeeded() {
        if let alarmSound {
            if !alarmSound.isPlaying { alarmSound.play() }
            return
        }

        let soundNames = ["Glass", "Ping", "Funk"]
        guard let sound = soundNames.lazy.compactMap({ NSSound(named: NSSound.Name($0)) }).first else {
            NSSound.beep()
            return
        }
        sound.loops = true
        sound.volume = 1
        alarmSound = sound
        if !sound.play() {
            alarmSound = nil
            NSSound.beep()
        }
    }

    private func stopAlarmSoundIfIdle() {
        guard ringingTimers.isEmpty else { return }
        alarmSound?.stop()
        alarmSound?.loops = false
        alarmSound = nil
    }

    private func completionNotificationIdentifier(for id: String) -> String {
        "sapphire-timer-\(id)"
    }

    private func scheduleCompletionNotification(for timer: SapphireTimer) {
        guard let fireDate = timer.fireDate else { return }
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            DispatchQueue.main.async { [weak self] in
                guard let self,
                      let currentTimer = self.sapphireTimers.first(where: { $0.id == timer.id }),
                      currentTimer.isRunning,
                      currentTimer.fireDate == fireDate else { return }

                switch settings.authorizationStatus {
                case .authorized, .provisional:
                    let content = UNMutableNotificationContent()
                    content.title = "Timer Done"
                    content.body = "\(currentTimer.label) finished."
                    content.sound = .default
                    let delay = max(fireDate.timeIntervalSinceNow, 1)
                    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
                    let request = UNNotificationRequest(
                        identifier: self.completionNotificationIdentifier(for: currentTimer.id),
                        content: content,
                        trigger: trigger
                    )
                    center.add(request)
                default:
                    break
                }
            }
        }
    }

    private func removeCompletionNotification(for id: String) {
        let identifier = completionNotificationIdentifier(for: id)
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
    }

    private func scheduleNextCompletionTimer() {
        completionTimer?.invalidate()
        completionTimer = nil

        let deadlines = sapphireTimers.filter(\.isRunning).compactMap(\.deadline)
        guard let interval = TimerDeadlineClock.delayUntilNext(deadlines, now: TimerDeadlineClock.now()) else {
            return
        }
        guard interval > 0 else {
            checkSapphireTimerCompletion()
            return
        }

        completionTimer = Timer.scheduledCoalescing(
            withTimeInterval: interval,
            repeats: false,
            toleranceFraction: min(0.1, 0.25 / interval)
        ) { [weak self] _ in
            guard let self else { return }
            self.completionTimer = nil
            self.checkSapphireTimerCompletion()
            self.scheduleNextCompletionTimer()
        }
    }

    private func extractID(from message: String, after keyword: String) -> String? {
        if let range = message.range(of: keyword) {
            return String(message[range.upperBound...])
        }
        return nil
    }

    private func extractLapTime(from message: String) -> TimeInterval? {
        if let range = message.range(of: "adding stopwatch lap: ") {
            let timeString = message[range.upperBound...].split(separator: ",").first ?? ""
            return TimeInterval(timeString)
        }
        return nil
    }
}