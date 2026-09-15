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

struct SapphireTimer: Equatable, Identifiable {
    let id: String
    var label: String
    var state: ActiveTimerType
    var remainingTimeOnLastUpdate: TimeInterval
    var fireDate: Date?

    var remainingTime: TimeInterval {
        guard state == .system, let fireDate else {
            return max(0, remainingTimeOnLastUpdate)
        }
        return max(0, fireDate.timeIntervalSinceNow)
    }

    var isRunning: Bool { state == .system }
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
        SapphireTimer(
            id: id,
            label: label,
            state: stateRaw == 3 ? .system : .none,
            remainingTimeOnLastUpdate: remaining,
            fireDate: fireDate
        )
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
    @Published private(set) var displayTime: TimeInterval = 0
    @Published private(set) var activeTimer: ActiveTimerType = .none

    var ringingTimer: SapphireTimer? { ringingTimers.first }
    var hasRingingTimer: Bool { !ringingTimers.isEmpty }

    private var internalTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var logStreamProcess: Process?
    private var pipe: Pipe?
    private var primaryTimerID: String?
    private var displayedTimerID: String?
    private var syncGeneration = 0
    private var plistSyncWorkItem: DispatchWorkItem?
    private var logReadBuffer = Data()
    private let maxLogRecordBytes = 1_048_576
    private var logSyncPending = false
    private var alarmSound: NSSound?
    private var sapphireTimerSaveURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Sapphire", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("sapphire-timers.json")
    }

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
        startSystemTimerMonitoring()
    }

    deinit {
        plistSyncWorkItem?.cancel()
        stopSystemTimerMonitoring()
        internalTimer?.invalidate()
        alarmSound?.stop()
        alarmSound?.loops = false
    }

    // MARK: - Sapphire-Owned Timers

    @discardableResult
    func startSapphireTimer(duration: TimeInterval, label: String? = nil) -> String? {
        guard duration > 0 else { return nil }
        let timer = SapphireTimer(
            id: UUID().uuidString,
            label: label ?? "Timer",
            state: .system,
            remainingTimeOnLastUpdate: duration,
            fireDate: Date().addingTimeInterval(duration)
        )
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
        sapphireTimers[index].remainingTimeOnLastUpdate = remaining
        sapphireTimers[index].fireDate = nil
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
        sapphireTimers[index].fireDate = Date().addingTimeInterval(sapphireTimers[index].remainingTimeOnLastUpdate)
        scheduleCompletionNotification(for: sapphireTimers[index])
        persistSapphireTimers()
        selectTimerToDisplay()
    }

    func addOneMinuteToSapphireTimer(id: String) {
        guard let index = sapphireTimers.firstIndex(where: { $0.id == id }) else { return }
        let extendedRemaining = sapphireTimers[index].remainingTime + 60
        sapphireTimers[index].remainingTimeOnLastUpdate = extendedRemaining
        if sapphireTimers[index].state == .system {
            sapphireTimers[index].fireDate = Date().addingTimeInterval(extendedRemaining)
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

    private func startSystemTimerMonitoring() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.startSystemTimerMonitoring() }
            return
        }
        guard logStreamProcess == nil else { return }
        logReadBuffer.removeAll(keepingCapacity: true)

        let newPipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/log")
        process.arguments = ["stream", "--predicate", "subsystem == \"com.apple.mobiletimer.logging\" AND (process == \"Clock\" OR process == \"timed\")", "--style", "ndjson"]
        process.standardOutput = newPipe
        newPipe.fileHandleForReading.readabilityHandler = { [weak self, weak process] fileHandle in
            let data = fileHandle.availableData
            guard !data.isEmpty else { return }
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
        logStreamProcess = process

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
        let process = logStreamProcess
        process?.terminationHandler = nil
        pipe?.fileHandleForReading.readabilityHandler = nil
        logStreamProcess = nil
        pipe = nil
        logReadBuffer.removeAll(keepingCapacity: false)
        if process?.isRunning == true {
            process?.terminate()
        }
    }

    private func handleLogStreamExit(_ process: Process) {
        guard logStreamProcess === process else { return }
        pipe?.fileHandleForReading.readabilityHandler = nil
        logStreamProcess = nil
        pipe = nil
        logReadBuffer.removeAll(keepingCapacity: true)

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.startSystemTimerMonitoring()
        }
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
        updateDisplayedTime()
        stopInternalTimer()
        if newTimerID != nil { startInternalTimer() }
    }

    @objc private func updateDisplayedTime() {
        guard let currentID = displayedTimerID else {
            if activeTimer != .none { activeTimer = .none; displayTime = 0 }
            stopInternalTimer()
            return
        }
        if activeTimer == .system {
            if let sapphire = sapphireTimers.first(where: { $0.id == currentID }) {
                self.displayTime = sapphire.remainingTime
                checkSapphireTimerCompletion()
                return
            }
            guard let timer = activeTimers.first(where: { $0.id == currentID }), timer.state == .system else {
                selectTimerToDisplay()
                return
            }
            self.displayTime = timer.remainingTime
        } else if activeTimer == .stopwatch {
            guard let stopwatch = activeStopwatches.first(where: { $0.id == currentID }), stopwatch.state == .stopwatch else {
                selectTimerToDisplay()
                return
            }
            self.displayTime = stopwatch.elapsedTime
        }
    }

    // MARK: - Sapphire Timer Completion

    private func checkSapphireTimerCompletion() {
        var didFinishTimer = false
        for index in sapphireTimers.indices {
            guard sapphireTimers[index].state == .system,
                  sapphireTimers[index].remainingTime <= 0 else { continue }
            sapphireTimers[index].state = .none
            sapphireTimers[index].remainingTimeOnLastUpdate = 0
            sapphireTimers[index].fireDate = nil
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

    private func startInternalTimer() {
        guard internalTimer == nil || !(internalTimer!.isValid) else { return }
        let interval: TimeInterval = activeTimer == .stopwatch ? 0.25 : 1.0
        internalTimer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.updateDisplayedTime()
        }
        if let internalTimer {
            RunLoop.main.add(internalTimer, forMode: .common)
        }
    }

    private func stopInternalTimer() {
        internalTimer?.invalidate()
        internalTimer = nil
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