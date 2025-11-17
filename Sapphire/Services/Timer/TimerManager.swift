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

    private func readPlistUsingDefaults() -> [String: Any]? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        process.arguments = ["export", "com.apple.mobiletimerd", "-"]
        process.standardOutput = pipe
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            if process.terminationStatus != 0 { return nil }
            return try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
        } catch {
            print("[TimerManager Plist Read]: CRITICAL FAILURE running `defaults export` command. Error: \(error)")
            return nil
        }
    }

    private func syncStateWithPlist() {
        guard let plist = readPlistUsingDefaults(),
              let timersDict = plist["MTTimers"] as? [String: Any],
              let timersArray = timersDict["MTTimers"] as? [[String: Any]]
        else {
            print("[TimerManager Plist Sync]: Failed to read or parse plist structure.")
            return
        }
        var validPlistTimerIDs = Set<String>()
        for timerDict in timersArray {
            guard let timerData = timerDict["$MTTimer"] as? [String: Any],
                  let timerID = timerData["MTTimerID"] as? String,
                  let timerStateInt = timerData["MTTimerState"] as? Int,
                  timerStateInt != 1
            else { continue }
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
            if let index = activeTimers.firstIndex(where: { $0.id == timerID }) {
                var timer = activeTimers[index]
                timer.state = plistState
                if plistState == .none {
                    timer.remainingTimeOnLastUpdate = timeValueFromPlist
                    timer.dateOfLastUpdate = Date()
                }
                activeTimers[index] = timer
            } else {
                activeTimers.append(SystemTimerInfo(id: timerID, state: plistState, remainingTimeOnLastUpdate: timeValueFromPlist, dateOfLastUpdate: Date()))
            }
        }
        activeTimers.removeAll { !validPlistTimerIDs.contains($0.id) }
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
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { self.syncStateWithPlist() }
            return
        }
        if message.contains("addTimer:") || message.contains("Pausing a timer:") || message.contains("Stopping a timer:") || message.contains("updateTimer:") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { self.syncStateWithPlist() }
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
        if newTimerID != nil { startInternalTimer() } else { stopInternalTimer() }
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
        internalTimer = Timer.scheduledTimer(timeInterval: 0.1, target: self, selector: #selector(updateDisplayedTime), userInfo: nil, repeats: true)
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