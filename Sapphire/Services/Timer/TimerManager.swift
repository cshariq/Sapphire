//
//  TimerManager.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-09-27
//

import Foundation
import Combine

// MARK: - Main TimerManager Class

enum ActiveTimerType {
    case none, stopwatch, system
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
    @Published var isRunning: Bool = false
    @Published private(set) var displayTime: TimeInterval = 0
    @Published private(set) var activeTimer: ActiveTimerType = .none

    private var internalTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var logStreamProcess: Process?
    private var pipe: Pipe?
    private var primaryTimerID: String?
    private var displayedTimerID: String?
    private var syncGeneration = 0
    private var plistSyncWorkItem: DispatchWorkItem?
    private var logSyncPending = false

    init() {
        Publishers.CombineLatest($activeTimers, $activeStopwatches)
            .map { !$0.filter { $0.state == .system }.isEmpty || !$1.filter { $0.state == .stopwatch }.isEmpty }
            .receive(on: DispatchQueue.main)
            .assign(to: &$isRunning)
        syncStateWithPlist()
        startSystemTimerMonitoring()
    }

    deinit {
        stopSystemTimerMonitoring()
        internalTimer?.invalidate()
    }

    func pauseTimer(id: String) {
        print("[TimerManager] Timer control is temporarily disabled for stability.")
    }

    func resumeTimer(id: String) {
        print("[TimerManager] Timer control is temporarily disabled for stability.")
    }

    func stopTimer(id: String) {
        print("[TimerManager] Timer control is temporarily disabled for stability.")
    }

    private struct PlistTimerEvent {
        let id: String
        let stateInt: Int
        let timeValue: TimeInterval
    }

    private func syncStateWithPlist() {
        plistSyncWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.performPlistSync()
        }
        plistSyncWorkItem = work
        DispatchQueue.global(qos: .utility).async(execute: work)
    }

    private func performPlistSync() {
        syncGeneration += 1
        let generation = syncGeneration
        DispatchQueue.global(qos: .utility).async { [weak self] in
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
        guard logStreamProcess == nil else { return }
        pipe = Pipe()
        logStreamProcess = Process()
        logStreamProcess?.executableURL = URL(fileURLWithPath: "/usr/bin/log")
        logStreamProcess?.arguments = ["stream", "--predicate", "subsystem == \"com.apple.mobiletimer.logging\" AND (process == \"Clock\" OR process == \"timed\")", "--style", "ndjson"]
        logStreamProcess?.standardOutput = pipe
        pipe?.fileHandleForReading.readabilityHandler = { [weak self] fileHandle in
            self?.parseLogOutput(from: fileHandle.availableData)
        }
        logStreamProcess?.terminationHandler = { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { self?.startSystemTimerMonitoring() }
        }
        DispatchQueue.global(qos: .utility).async {
            do { try self.logStreamProcess?.run() } catch { print("[TimerManager] Failed to start log stream: \(error)") }
        }
    }

    private func stopSystemTimerMonitoring() {
        logStreamProcess?.terminationHandler = nil
        logStreamProcess?.terminate()
        pipe?.fileHandleForReading.readabilityHandler = nil
        logStreamProcess = nil
        pipe = nil
    }

    private func parseLogOutput(from data: Data) {
        data.split(separator: UInt8(ascii: "\n")).forEach { lineData in
            guard let entry = try? JSONDecoder().decode(LogEntry.self, from: Data(lineData)), let message = entry.eventMessage else { return }
            DispatchQueue.main.async { self.handleLogMessage(message) }
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
        let runningSystemTimers = activeTimers.filter { $0.state == .system }
        var newTimerID: String? = nil
        var newActiveTimerType: ActiveTimerType = .none
        if let timerWithLeastTime = runningSystemTimers.min(by: { $0.remainingTime < $1.remainingTime }) {
            newTimerID = timerWithLeastTime.id
            newActiveTimerType = .system
        } else if let runningStopwatch = activeStopwatches.first(where: { $0.state == .stopwatch }) {
            newTimerID = runningStopwatch.id
            newActiveTimerType = .stopwatch
        }
        self.displayedTimerID = newTimerID
        self.activeTimer = newActiveTimerType
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

    private func startInternalTimer() {
        guard internalTimer == nil || !(internalTimer!.isValid) else { return }
        let interval: TimeInterval = activeTimer == .stopwatch ? 0.25 : 1.0
        internalTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
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