//
//  DevActivityMonitor.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-12
//

import Combine
import Foundation
import SwiftUI
import os.log

struct DevTask: Identifiable, Equatable {
    let id: String
    let pid: pid_t
    let tool: DevTool
    let kind: DevTaskKind
    let title: String
    let detail: String
    let startedAt: Date
    let cpuPercent: Double

    var elapsed: TimeInterval { max(0, Date().timeIntervalSince(startedAt)) }

    static func == (lhs: DevTask, rhs: DevTask) -> Bool {
        lhs.id == rhs.id
            && lhs.title == rhs.title
            && lhs.detail == rhs.detail
            && lhs.startedAt == rhs.startedAt
    }
}

@MainActor
final class DevActivityMonitor: ObservableObject {
    static let shared = DevActivityMonitor()

    @Published private(set) var tasks: [DevTask] = []
    @Published private(set) var isBusy: Bool = false

    private let settings = SettingsModel.shared
    private let logger = Logger(subsystem: "com.shariq.sapphire", category: "DevActivity")
    private let engine = DevActivityScanEngine()
    private let scanQueue = DispatchQueue(label: "com.shariq.sapphire.devactivity", qos: .utility)

    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var isScanning = false
    private var scanGeneration: UInt = 0
    private var hasStarted = false

    private struct TaskState {
        var startedAt: Date
        var lastBusy: Date
        var cachedDetail: String?
    }

    private var taskStates: [String: TaskState] = [:]

    private var idsByPID: [pid_t: String] = [:]

    private let busyGracePeriod: TimeInterval = 8

    private static let scanInterval: TimeInterval = 2.5
    private static let idleScanInterval: TimeInterval = 10
    private static let idleScansBeforeBackOff = 5
    private var idleScans = 0

    private var environmentObservers: [(NotificationCenter, NSObjectProtocol)] = []
    private var displaysAsleep = false
    private var screenLocked = false
    private var systemSleeping = false

    private var isEnvironmentSuspended: Bool {
        if systemSleeping { return true }
        guard !settings.current.caffeinateAutoDuringTasks else { return false }
        return displaysAsleep || screenLocked
    }

    private init() {
        settings.$settings
            .map {
                (
                    $0.devActivityEnabled,
                    $0.devActivityKinds,
                    $0.devActivitySensitivity,
                    $0.caffeinateAutoDuringTasks,
                    $0.devWidgetEnabled
                )
            }
            .removeDuplicates { $0 == $1 }
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.applySettings() }
            .store(in: &cancellables)

        installEnvironmentObservers()
    }

    // MARK: - Environment

    private func installEnvironmentObservers() {
        let workspace = NSWorkspace.shared.notificationCenter
        observe(workspace, NSWorkspace.screensDidSleepNotification) { $0.displaysAsleep = true }
        observe(workspace, NSWorkspace.screensDidWakeNotification) { $0.displaysAsleep = false }
        observe(workspace, NSWorkspace.willSleepNotification) { $0.systemSleeping = true }
        observe(workspace, NSWorkspace.didWakeNotification) { $0.systemSleeping = false }

        let distributed = DistributedNotificationCenter.default()
        observe(distributed, Notification.Name("com.apple.screenIsLocked")) { $0.screenLocked = true }
        observe(distributed, Notification.Name("com.apple.screenIsUnlocked")) { $0.screenLocked = false }
    }

    private func observe(
        _ center: NotificationCenter,
        _ name: Notification.Name,
        handler: @escaping @MainActor (DevActivityMonitor) -> Void
    ) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                handler(self)
                self.applySettings()
            }
        }
        environmentObservers.append((center, token))
    }

    private var isShownInNotch: Bool {
        settings.current.devActivityEnabled || settings.current.devWidgetEnabled
    }

    private var isWanted: Bool {
        isShownInNotch || settings.current.caffeinateAutoDuringTasks
    }

    // MARK: - Lifecycle

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        applySettings()
    }

    func stop() {
        hasStarted = false
        suspendScanning()
    }

    private func suspendScanning() {
        timer?.invalidate()
        timer = nil
        scanGeneration &+= 1
        if !tasks.isEmpty { tasks = [] }
        if isBusy { isBusy = false }
        taskStates.removeAll()
        idsByPID.removeAll()
        idleScans = 0
    }

    private func applySettings() {
        guard hasStarted else { return }

        let wanted = isWanted
        guard wanted, !isEnvironmentSuspended else {
            suspendScanning()
            return
        }

        guard timer == nil, !isScanning else { return }
        scan()
    }

    func refreshNow() {
        guard hasStarted else { return }
        timer?.invalidate()
        timer = nil
        idleScans = 0
        scan()
    }

    private func scheduleNextScan() {
        timer?.invalidate()
        let shouldBackOff = NotchRuntimeState.shared.shouldReduceBackgroundWork
            && !settings.current.caffeinateAutoDuringTasks
        var interval = shouldBackOff ? Self.scanInterval * 2 : Self.scanInterval
        if idleScans >= Self.idleScansBeforeBackOff || !isShownInNotch {
            interval = max(interval, Self.idleScanInterval)
        }
        timer = Timer.scheduledCoalescing(
            withTimeInterval: interval,
            repeats: false,
            toleranceFraction: 0.15
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.timer = nil
                self.scan()
            }
        }
    }

    // MARK: - Scanning

    private func scan() {
        guard hasStarted else { return }
        let wanted = isWanted
        guard wanted else { return }
        guard !isScanning else { return }
        isScanning = true
        let generation = scanGeneration

        let enabledKinds = settings.current.devActivityKinds
        let sensitivity = settings.current.devActivitySensitivity
        let includeIDEAgents = settings.current.devActivityDetectIDEAgents

        let configuration = DevActivityScanEngine.Configuration(
            enabledKinds: enabledKinds,
            sensitivity: sensitivity,
            includeIDEAgents: includeIDEAgents
        )
        let engine = engine

        scanQueue.async { [weak self, engine] in
            let found = engine.collect(configuration)
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isScanning = false
                guard self.scanGeneration == generation else {
                    self.applySettings()
                    return
                }
                self.idleScans = found.sawDevProcess ? 0 : self.idleScans + 1
                self.publish(found.tasks)
                self.scheduleNextScan()
            }
        }
    }

    // MARK: - Publishing

    private func publish(_ scanned: [DevActivityScanEngine.RawTask]) {
        let now = Date()
        var states = taskStates
        let raw = pinIdentities(of: scanned)

        for task in raw {
            if var existing = states[task.id] {
                existing.lastBusy = now
                if existing.cachedDetail == nil, !task.detail.isEmpty {
                    existing.cachedDetail = task.detail
                }
                states[task.id] = existing
            } else {
                states[task.id] = TaskState(
                    startedAt: now,
                    lastBusy: now,
                    cachedDetail: task.detail.isEmpty ? nil : task.detail
                )
            }
        }

        let liveIDs = Set(raw.map(\.id))
        states = states.filter { id, state in
            liveIDs.contains(id) || now.timeIntervalSince(state.lastBusy) < busyGracePeriod
        }
        taskStates = states
        idsByPID = idsByPID.filter { states[$0.value] != nil }

        var built: [DevTask] = raw.map { task in
            let state = states[task.id]
            let startedAt = task.usesActivitySignal
                ? (state?.startedAt ?? task.processStart)
                : task.processStart

            return DevTask(
                id: task.id,
                pid: task.pid,
                tool: task.tool,
                kind: task.kind,
                title: task.title,
                detail: task.detail.isEmpty ? (state?.cachedDetail ?? "") : task.detail,
                startedAt: startedAt,
                cpuPercent: task.cpuPercent
            )
        }

        let shownIDs = Set(built.map(\.id))
        for task in tasks where !shownIDs.contains(task.id) {
            guard let state = states[task.id], now.timeIntervalSince(state.lastBusy) < busyGracePeriod else { continue }
            built.append(task)
        }

        built.sort { lhs, rhs in
            if lhs.kind != rhs.kind { return lhs.kind.priority < rhs.kind.priority }
            return lhs.startedAt > rhs.startedAt
        }

        if built != tasks { tasks = built }

        let busy = !built.isEmpty
        if busy != isBusy {
            isBusy = busy
            logger.debug("dev activity: \(busy ? "busy" : "idle") (\(built.count) task(s))")
        }
    }

    private func pinIdentities(of scanned: [DevActivityScanEngine.RawTask]) -> [DevActivityScanEngine.RawTask] {
        var ids = Set(scanned.map(\.id))
        var pinned = scanned
        for index in pinned.indices {
            let task = pinned[index]
            if let known = idsByPID[task.pid], known != task.id, !ids.contains(known) {
                ids.remove(task.id)
                ids.insert(known)
                pinned[index].id = known
            }
            idsByPID[task.pid] = pinned[index].id
        }
        return pinned
    }
}

private extension DevTaskKind {
    var priority: Int {
        switch self {
        case .ai: return 0
        case .build: return 1
        case .command: return 2
        }
    }
}