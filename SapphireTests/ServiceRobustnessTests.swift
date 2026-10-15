//
//  ServiceRobustnessTests.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-10-07

import Foundation
import Testing
@testable import Sapphire

struct ServiceRobustnessTests {

    // MARK: - Bluetooth: continuations and single-flight

    @Test func oneShotContinuationResumesOnlyOnce() async {
        let value: Int = await withCheckedContinuation { continuation in
            let once = OneShotContinuation(continuation)
            #expect(once.resume(returning: 1))
            #expect(!once.resume(returning: 2), "a late timeout/cancel must be a no-op")
        }
        #expect(value == 1)
    }

    @MainActor
    @Test func singleFlightSharesOneRunBetweenOverlappingCallers() async {
        let flight = SingleFlight<Int>()
        let counter = Counter()

        async let first = flight.run {
            await counter.increment()
            try? await Task.sleep(for: .milliseconds(50))
            return 7
        }
        async let second = flight.run {
            await counter.increment()
            return 99
        }
        let values = await [first, second]

        #expect(values == [7, 7])
        #expect(await counter.value == 1)
        #expect(!flight.isRunning)

        let third = await flight.run {
            await counter.increment()
            return 3
        }
        #expect(third == 3)
        #expect(await counter.value == 2)
    }

    private actor Counter {
        private(set) var value = 0
        func increment() { value += 1 }
    }

    @Test func batteryRefreshFreshnessWindow() {
        let now = Date()
        #expect(!BluetoothBatteryReader.isFresh(lastRefresh: nil, now: now, maxAge: 300))
        #expect(BluetoothBatteryReader.isFresh(lastRefresh: now.addingTimeInterval(-10), now: now, maxAge: 300))
        #expect(!BluetoothBatteryReader.isFresh(lastRefresh: now.addingTimeInterval(-301), now: now, maxAge: 300))
        #expect(!BluetoothBatteryReader.isFresh(lastRefresh: now.addingTimeInterval(60), now: now, maxAge: 300))
    }

    @Test func systemProfilerParserReadsNameKeyedDevices() {
        let json = """
        {"SPBluetoothDataType":[{"controller_properties":{},
          "device_connected":[
            {"Magic Mouse":{"device_address":"aa-bb-cc-dd-ee-ff","device_minorType":"Mouse","device_batteryLevelMain":"55%"}},
            {"Pods":{"device_address":"11:22:33:44:55:66","device_minorType":"Headphones",
                     "device_batteryLevelLeft":"80%","device_batteryLevelRight":"90%","device_batteryLevelCase":"0%"}},
            {"Speaker":{"device_address":"77:88:99:AA:BB:CC","device_minorType":"Speaker"}}
          ],
          "device_not_connected":[{"Old Mouse":{"device_batteryLevelMain":"20%"}}]
        }]}
        """
        let results = BluetoothBatteryReader.parseSystemProfilerBatteries(Data(json.utf8))
        let byName = Dictionary(uniqueKeysWithValues: results.map { ($0.name, $0) })

        #expect(byName["Magic Mouse"]?.level == 55)
        #expect(byName["Magic Mouse"]?.address == "AA:BB:CC:DD:EE:FF")
        #expect(byName["Pods (Left)"]?.level == 80)
        #expect(byName["Pods (Right)"]?.baseName == "Pods")
        #expect(byName["Pods (Case)"] == nil, "0% is not a reading")
        #expect(byName["Old Mouse"] == nil, "only connected devices count")
        #expect(results.count == 3)
    }

    // MARK: - Calendar

    @Test func recurringOccurrencesHaveDistinctMilestoneKeys() {
        let today = Date(timeIntervalSince1970: 1_800_000_000)
        let tomorrow = today.addingTimeInterval(86_400)
        let first = CalendarOccurrenceKey(eventIdentifier: "standup", occurrenceStart: today)
        let second = CalendarOccurrenceKey(eventIdentifier: "standup", occurrenceStart: tomorrow)
        #expect(first != nil && second != nil)
        #expect(first != second)
        #expect(CalendarOccurrenceKey(eventIdentifier: "", occurrenceStart: today) == nil)
        #expect(CalendarOccurrenceKey(eventIdentifier: nil, occurrenceStart: today) == nil)
    }

    @Test func milestonePruningDropsStartedOccurrences() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let old = try #require(CalendarOccurrenceKey(eventIdentifier: "a", occurrenceStart: now.addingTimeInterval(-7_200)))
        let recent = try #require(CalendarOccurrenceKey(eventIdentifier: "a", occurrenceStart: now.addingTimeInterval(-600)))
        let upcoming = try #require(CalendarOccurrenceKey(eventIdentifier: "b", occurrenceStart: now.addingTimeInterval(3_600)))
        let pruned = CalendarSchedule.prune([old: 1, recent: 2, upcoming: 3], now: now)
        #expect(Set(pruned.keys) == [recent, upcoming])
    }

    @Test func nextRefreshBoundaryPicksEarliestMilestone() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let start = now.addingTimeInterval(45 * 60)
        let boundary = CalendarSchedule.nextRefreshBoundary(
            now: now,
            events: [(start: start, end: start.addingTimeInterval(3_600))]
        )
        #expect(boundary == start.addingTimeInterval(-30 * 60))

        let ongoing = CalendarSchedule.nextRefreshBoundary(
            now: now,
            events: [(start: now.addingTimeInterval(-600), end: now.addingTimeInterval(900))]
        )
        #expect(ongoing == now.addingTimeInterval(900))

        let empty = CalendarSchedule.nextRefreshBoundary(now: now, events: [], maxDelay: 3_600)
        #expect(empty == now.addingTimeInterval(3_600))
    }

    // MARK: - Timers

    @Test func timerDueDuringSleepIsImmediatelyDueOnWake() {
        let armedAt: TimeInterval = 1_000
        let deadline = armedAt + 60
        #expect(TimerDeadlineClock.delayUntilNext([deadline], now: armedAt + 120) == 0)
        #expect(TimerDeadlineClock.remaining(until: deadline, now: armedAt + 120) == 0)
        #expect(TimerDeadlineClock.delayUntilNext([deadline, deadline + 30], now: armedAt + 10) == 50)
        #expect(TimerDeadlineClock.delayUntilNext([], now: armedAt) == nil)
    }

    @Test func armedTimerCountsDownOnContinuousClock() {
        var timer = SapphireTimer(
            id: "t", label: "Tea", state: .system,
            remainingTimeOnLastUpdate: 0, fireDate: nil, deadline: nil
        )
        timer.arm(remaining: 300)
        #expect(timer.deadline != nil)
        #expect(timer.fireDate != nil)
        #expect(timer.remainingTime > 299 && timer.remainingTime <= 300)
        timer.disarm(remaining: 42)
        #expect(timer.deadline == nil && timer.fireDate == nil)
    }

    @Test func logStreamRunsOnlyWhileNeededWithBackoff() {
        #expect(!TimerManager.needsLogStream(clockAppRunning: false, hasRunningSystemTimer: false, hasRunningStopwatch: false))
        #expect(TimerManager.needsLogStream(clockAppRunning: true, hasRunningSystemTimer: false, hasRunningStopwatch: false))
        #expect(TimerManager.needsLogStream(clockAppRunning: false, hasRunningSystemTimer: true, hasRunningStopwatch: false))
        #expect(TimerManager.logStreamRestartDelay(attempt: 0) == 1)
        #expect(TimerManager.logStreamRestartDelay(attempt: 3) == 8)
        #expect(TimerManager.logStreamRestartDelay(attempt: 50) == 60)
    }

    // MARK: - Dev activity

    @Test func claudeProjectSlugReplacesEveryNonAlphanumeric() {
        #expect(DevAgentSessionActivity.projectSlug(for: "/Users/me/Github/Sapphire") == "-Users-me-Github-Sapphire")
        #expect(DevAgentSessionActivity.projectSlug(for: "/Users/me/My Project/a.b_c+d") == "-Users-me-My-Project-a-b-c-d")
        #expect(DevAgentSessionActivity.projectSlug(for: "/tmp/café") == "-tmp-caf-")
        #expect(DevAgentSessionActivity.projectSlug(for: "/x/\u{1F600}") == "-x---")
        #expect(DevAgentSessionActivity.projectSlug(for: "relative/path") == nil)
    }

    // MARK: - Line assembly

    @Test func lineAssemblerCarriesPartialLinesAndUTF8() {
        var assembler = LineChunkAssembler()
        let text = "first line\nsecond é line\r\nthird"
        let bytes = Array(text.utf8)
        let eAccent = bytes.firstIndex(of: 0xC3)!
        var lines = assembler.append(Data(bytes[..<(eAccent + 1)]))
        #expect(lines == ["first line"])
        lines = assembler.append(Data(bytes[(eAccent + 1)...]))
        #expect(lines == ["second é line"])
        #expect(assembler.finish() == ["third"])
        #expect(assembler.finish().isEmpty)
    }

    // MARK: - Notifications

    @Test func notificationQueueKeepsOrderAndDropsOldestBeyondCapacity() {
        func payload(_ id: Int) -> NotificationPayload {
            NotificationPayload(id: "\(id)", appIdentifier: "com.example", title: "", body: "", date: Date(), appIcon: nil)
        }
        var queue = NotificationDisplayQueue(capacity: 3)
        queue.enqueue([payload(1), payload(2)], current: payload(0))
        queue.enqueue([payload(2), payload(0), payload(3), payload(4)], current: payload(0))
        #expect(queue.pending.map(\.id) == ["2", "3", "4"])
        #expect(queue.next()?.id == "2")
        #expect(queue.next()?.id == "3")
        #expect(queue.next()?.id == "4")
        #expect(queue.next() == nil)
    }

    // MARK: - Battery log

    @MainActor
    @Test func batteryLogPruneKeepsOnlyRecentEntries() throws {
        let cutoff = Date(timeIntervalSince1970: 1_800_000_000)
        func entry(_ offset: TimeInterval) -> BatteryLogEntry {
            BatteryLogEntry(
                timestamp: cutoff.addingTimeInterval(offset), charge: 50, isCharging: false,
                isPluggedIn: false, isScreenOn: true, isLowPowerMode: false, temperature: 30,
                managementState: .discharging, ledColor: 0, hardwareCharge: 50, isSleeping: false,
                maxCapacity: 100, cycleCount: 1, powerConsumption: 5, timeRemainingMinutes: 60
            )
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var payload = Data()
        for item in [entry(-86_400), entry(60), entry(120)] {
            payload.append(try encoder.encode(item))
            payload.append(0x0A)
        }
        payload.append(Data("not json\n".utf8))

        let result = BatteryDataLogger.pruneLog(payload, cutoff: cutoff)
        #expect(result.entries.count == 2)
        #expect(result.removedLineCount == 1)
        #expect(String(decoding: result.keptData, as: UTF8.self).hasSuffix("not json\n"))
        #expect(BatteryDataLogger.pruneLog(result.keptData, cutoff: cutoff).removedLineCount == 0)
    }

    // MARK: - Weather

    @Test func weatherRefetchesOnResumeOnlyWhenStale() {
        let now = Date()
        #expect(WeatherViewModel.shouldRefreshOnResume(lastUpdated: nil, now: now))
        #expect(!WeatherViewModel.shouldRefreshOnResume(lastUpdated: now.addingTimeInterval(-60), now: now, interval: 600))
        #expect(WeatherViewModel.shouldRefreshOnResume(lastUpdated: now.addingTimeInterval(-601), now: now, interval: 600))
    }

    // MARK: - ProcessRunner

    @Test func processRunnerCollectsOutputLargerThanPipeBuffer() async {
        let result = await ProcessRunner.runCapturing(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "head -c 200000 /dev/zero | tr '\\0' 'a'; printf 'tail'"],
            timeout: 10
        )
        #expect(!result.timedOut)
        #expect(result.standardOutput.count == 200_004)
        #expect(result.standardOutput.hasSuffix("tail"))
    }
}