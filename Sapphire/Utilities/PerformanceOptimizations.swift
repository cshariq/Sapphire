//
//  PerformanceOptimizations.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-10

import Foundation
import SwiftUI
import Combine

// MARK: - Debounced Publisher

extension Publisher where Failure == Never {
    func adaptiveDebounce(
        baseInterval: RunLoop.SchedulerTimeType.Stride,
        scheduler: RunLoop
    ) -> AnyPublisher<Output, Failure> {
        self
            .debounce(for: baseInterval, scheduler: scheduler)
            .eraseToAnyPublisher()
    }
}

// MARK: - Throttled Updates

class ThrottledPublisher<T: Equatable>: ObservableObject {
    @Published private(set) var value: T
    private var pendingValue: T?
    private var timer: Timer?
    private let interval: TimeInterval

    init(initialValue: T, interval: TimeInterval = 0.3) {
        self.value = initialValue
        self.interval = interval
    }

    func update(_ newValue: T) {
        pendingValue = newValue

        if timer == nil {
            scheduleUpdate()
        }
    }

    private func scheduleUpdate() {
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            guard let self = self, let pending = self.pendingValue else { return }

            if self.value != pending {
                self.value = pending
            }

            self.pendingValue = nil
            self.timer = nil
        }
    }

    deinit {
        timer?.invalidate()
    }
}

// MARK: - Lazy File I/O

actor AsyncFileCache {
    private var cache: [String: Data] = [:]
    private let maxCacheSize = 50 * 1024 * 1024
    private var currentSize = 0

    func read(path: String) async throws -> Data {
        if let cached = cache[path] {
            return cached
        }

        let url = URL(fileURLWithPath: path)
        let data = try Data(contentsOf: url)

        if currentSize + data.count < maxCacheSize {
            cache[path] = data
            currentSize += data.count
        }

        return data
    }

    func write(path: String, data: Data) async throws {
        let url = URL(fileURLWithPath: path)
        try data.write(to: url, options: .atomic)

        if let existing = cache[path] {
            currentSize -= existing.count
        }

        if currentSize + data.count < maxCacheSize {
            cache[path] = data
            currentSize += data.count
        }
    }

    func clearCache() {
        cache.removeAll()
        currentSize = 0
    }
}

// MARK: - View Debouncing

struct DebouncedView<Content: View>: View {
    let content: Content
    let delay: Double

    @State private var isVisible = false

    init(delay: Double = 0.1, @ViewBuilder content: () -> Content) {
        self.delay = delay
        self.content = content()
    }

    var body: some View {
        Group {
            if isVisible {
                content
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                withAnimation {
                    isVisible = true
                }
            }
        }
    }
}

// MARK: - Memory-Efficient Lists

struct LazyLoadingList<Item: Identifiable, Content: View>: View {
    let items: [Item]
    let pageSize: Int
    let content: (Item) -> Content

    @State private var visibleCount: Int

    init(items: [Item], pageSize: Int = 50, @ViewBuilder content: @escaping (Item) -> Content) {
        self.items = items
        self.pageSize = pageSize
        self.content = content
        self._visibleCount = State(initialValue: min(pageSize, items.count))
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(Array(items.prefix(visibleCount))) { item in
                    content(item)
                        .onAppear {
                            if items.last?.id == item.id && visibleCount < items.count {
                                loadMore()
                            }
                        }
                }

                if visibleCount < items.count {
                    ProgressView()
                        .onAppear {
                            loadMore()
                        }
                }
            }
        }
    }

    private func loadMore() {
        let newCount = min(visibleCount + pageSize, items.count)
        if newCount > visibleCount {
            visibleCount = newCount
        }
    }
}

// MARK: - Coalesced Updates

class CoalescedUpdater {
    private var pendingWork: DispatchWorkItem?
    private let queue: DispatchQueue
    private let delay: TimeInterval

    init(queue: DispatchQueue = .main, delay: TimeInterval = 0.3) {
        self.queue = queue
        self.delay = delay
    }

    func schedule(_ work: @escaping () -> Void) {
        pendingWork?.cancel()

        let workItem = DispatchWorkItem(block: work)
        pendingWork = workItem

        queue.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    func executeNow() {
        pendingWork?.perform()
        pendingWork?.cancel()
        pendingWork = nil
    }
}

// MARK: - Batch Operations

class BatchProcessor<T> {
    typealias ProcessBatch = ([T]) async throws -> Void

    private var batch: [T] = []
    private let maxBatchSize: Int
    private let maxWaitTime: TimeInterval
    private let processor: ProcessBatch
    private var timer: Timer?
    private let queue = DispatchQueue(label: "com.sapphire.batch", qos: .utility)

    init(maxBatchSize: Int = 100, maxWaitTime: TimeInterval = 5.0, processor: @escaping ProcessBatch) {
        self.maxBatchSize = maxBatchSize
        self.maxWaitTime = maxWaitTime
        self.processor = processor
    }

    func add(_ item: T) {
        queue.async { [weak self] in
            guard let self = self else { return }

            self.batch.append(item)

            if self.batch.count >= self.maxBatchSize {
                Task {
                    await self.flush()
                }
            } else if self.timer == nil {
                self.scheduleFlush()
            }
        }
    }

    private func scheduleFlush() {
        timer = Timer.scheduledTimer(withTimeInterval: maxWaitTime, repeats: false) { [weak self] _ in
            Task {
                await self?.flush()
            }
        }
    }

    func flush() async {
        timer?.invalidate()
        timer = nil

        let itemsToProcess = queue.sync { () -> [T] in
            let items = batch
            batch.removeAll()
            return items
        }

        guard !itemsToProcess.isEmpty else { return }

        do {
            try await processor(itemsToProcess)
        } catch {
            print(" Batch processing failed: \(error)")
        }
    }

    deinit {
        timer?.invalidate()
    }
}

// MARK: - Smart Caching

class ExpiringCache<Key: Hashable, Value> {
    private struct CacheEntry {
        let value: Value
        let expiry: Date
    }

    private var cache: [Key: CacheEntry] = [:]
    private let lock = NSLock()
    private let ttl: TimeInterval
    private let maxSize: Int

    init(ttl: TimeInterval = 300, maxSize: Int = 1000) {
        self.ttl = ttl
        self.maxSize = maxSize
    }

    func get(_ key: Key) -> Value? {
        lock.lock()
        defer { lock.unlock() }

        guard let entry = cache[key] else { return nil }

        if entry.expiry < Date() {
            cache.removeValue(forKey: key)
            return nil
        }

        return entry.value
    }

    func set(_ key: Key, value: Value) {
        lock.lock()
        defer { lock.unlock() }

        let entry = CacheEntry(value: value, expiry: Date().addingTimeInterval(ttl))
        cache[key] = entry

        if cache.count > maxSize {
            let sortedKeys = cache.sorted { $0.value.expiry < $1.value.expiry }
            let keysToRemove = sortedKeys.prefix(cache.count - maxSize).map { $0.key }
            keysToRemove.forEach { cache.removeValue(forKey: $0) }
        }
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        cache.removeAll()
    }

    func removeExpired() {
        lock.lock()
        defer { lock.unlock() }

        let now = Date()
        cache = cache.filter { $0.value.expiry >= now }
    }
}

// MARK: - Background Task Manager

@MainActor
class BackgroundTaskManager {
    static let shared = BackgroundTaskManager()

    private var tasks: [String: Task<Void, Never>] = [:]

    private init() {}

    func schedule(id: String, priority: _Concurrency.TaskPriority = .background, operation: @escaping @Sendable () async -> Void) {
        tasks[id]?.cancel()

        let task = Task(priority: priority) {
            await operation()
        }

        tasks[id] = task
    }

    func cancel(id: String) {
        tasks[id]?.cancel()
        tasks.removeValue(forKey: id)
    }

    func cancelAll() {
        tasks.values.forEach { $0.cancel() }
        tasks.removeAll()
    }
}

// MARK: - Performance Monitor

class PerformanceMonitor {
    static let shared = PerformanceMonitor()

    private var measurements: [String: [TimeInterval]] = [:]
    private let lock = NSLock()

    func measure<T>(_ name: String, operation: () throws -> T) rethrows -> T {
        let start = CFAbsoluteTimeGetCurrent()
        defer {
            let duration = CFAbsoluteTimeGetCurrent() - start
            recordMeasurement(name, duration: duration)
        }
        return try operation()
    }

    func measureAsync<T>(_ name: String, operation: () async throws -> T) async rethrows -> T {
        let start = CFAbsoluteTimeGetCurrent()
        defer {
            let duration = CFAbsoluteTimeGetCurrent() - start
            recordMeasurement(name, duration: duration)
        }
        return try await operation()
    }

    private func recordMeasurement(_ name: String, duration: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }

        if measurements[name] == nil {
            measurements[name] = []
        }
        measurements[name]?.append(duration)

        if let count = measurements[name]?.count, count > 100 {
            measurements[name]?.removeFirst()
        }

        if duration > 0.5 {
            print("️ Slow operation '\(name)': \(String(format: "%.2f", duration * 1000))ms")
        }
    }

    func getStats(_ name: String) -> (avg: TimeInterval, max: TimeInterval, count: Int)? {
        lock.lock()
        defer { lock.unlock() }

        guard let durations = measurements[name], !durations.isEmpty else { return nil }

        let avg = durations.reduce(0, +) / Double(durations.count)
        let max = durations.max() ?? 0

        return (avg, max, durations.count)
    }

    func printAllStats() {
        lock.lock()
        defer { lock.unlock() }

        print("\n=== Performance Stats ===")
        for (name, durations) in measurements.sorted(by: { $0.key < $1.key }) {
            let avg = durations.reduce(0, +) / Double(durations.count)
            let max = durations.max() ?? 0
            print("\(name): avg=\(String(format: "%.2f", avg * 1000))ms, max=\(String(format: "%.2f", max * 1000))ms, count=\(durations.count)")
        }
        print("========================\n")
    }
}