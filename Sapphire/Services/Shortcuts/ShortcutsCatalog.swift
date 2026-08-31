//
//  ShortcutsCatalog.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-30

import Foundation
import Combine

@MainActor
final class ShortcutsCatalog: ObservableObject {
    static let shared = ShortcutsCatalog()

    @Published private(set) var installedNames: [String] = []

    private var cache: Set<String> = []
    private var lastRefreshDate: Date?
    private var refreshTask: Task<Set<String>, Never>?

    private init() {}

    func requestRefresh(force: Bool = false) {
        if !force, let last = lastRefreshDate, Date().timeIntervalSince(last) < 120 { return }
        if refreshTask != nil { return }
        startRefresh()
    }

    private func startRefresh() {
        let task = Task.detached(priority: .utility) { [weak self] () -> Set<String> in
            defer {
                Task { @MainActor [weak self] in self?.refreshTask = nil }
            }
            guard let result = ProcessRunner.runSync(
                executablePath: "/usr/bin/shortcuts",
                arguments: ["list"],
                timeout: 8
            ), result.succeeded else { return [] }

            let names = Set(
                result.stdout.split(separator: "\n")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
            )
            await MainActor.run { [weak self] in self?.apply(names) }
            return names
        }
        refreshTask = task
    }

    private func apply(_ names: Set<String>) {
        guard !names.isEmpty else { return }
        cache = names
        lastRefreshDate = Date()
        let sorted = names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        if installedNames != sorted { installedNames = sorted }
    }

    func names(maxAge: TimeInterval = 600) async -> Set<String> {
        if !cache.isEmpty, let last = lastRefreshDate, Date().timeIntervalSince(last) < maxAge {
            return cache
        }
        if refreshTask == nil { startRefresh() }
        guard let task = refreshTask else { return cache }
        let fresh = await task.value
        return fresh.isEmpty ? cache : fresh
    }

    nonisolated static func run(name: String, argument: String? = nil) {
        var arguments = ["run", name]
        if let argument {
            arguments += ["-i", argument]
        }
        ProcessRunner.runDetached(executablePath: "/usr/bin/shortcuts", arguments: arguments)
    }
}