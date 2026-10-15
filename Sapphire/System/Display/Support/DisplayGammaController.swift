//
//  DisplayGammaController.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-10-07
//

import AppKit
import CoreGraphics
import os.log

@MainActor
final class DisplayGammaController {
    static let shared = DisplayGammaController()

    enum Source: Hashable {
        case dimming
        case xdr
    }

    private struct GammaTable {
        var red: [CGGammaValue]
        var green: [CGGammaValue]
        var blue: [CGGammaValue]

        func scaled(by factor: Float) -> GammaTable {
            GammaTable(
                red: DisplayBrightnessMath.scaled(red, by: factor),
                green: DisplayBrightnessMath.scaled(green, by: factor),
                blue: DisplayBrightnessMath.scaled(blue, by: factor)
            )
        }

        func matches(_ other: GammaTable) -> Bool {
            DisplayBrightnessMath.tablesMatch(red, other.red)
                && DisplayBrightnessMath.tablesMatch(green, other.green)
                && DisplayBrightnessMath.tablesMatch(blue, other.blue)
        }
    }

    private struct Entry {
        var original: GammaTable
        var factors: [Source: Float]
        var applied: GammaTable?

        var combinedFactor: Float {
            factors.values.reduce(1, *)
        }
    }

    private let logger = Logger(subsystem: "com.shariq.sapphire", category: "DisplayGamma")
    private var entries: [CGDirectDisplayID: Entry] = [:]
    private var observers: [(center: NotificationCenter, token: NSObjectProtocol)] = []
    private var reapplyWorkItem: DispatchWorkItem?

    private init() {}

    var hasActiveAdjustments: Bool { !entries.isEmpty }

    func factor(for displayID: CGDirectDisplayID, source: Source) -> Float {
        entries[displayID]?.factors[source] ?? 1
    }

    @discardableResult
    func setFactor(_ factor: Float, for displayID: CGDirectDisplayID, source: Source) -> Bool {
        let isIdentity = abs(factor - 1) < 0.0001
        if isIdentity {
            guard var entry = entries[displayID] else { return true }
            entry.factors.removeValue(forKey: source)
            if entry.factors.isEmpty {
                restore(displayID)
                return true
            }
            entries[displayID] = entry
            return apply(displayID)
        }

        if entries[displayID] == nil {
            guard let original = Self.readTable(displayID) else {
                logger.error("Couldn't read gamma table for display \(displayID, privacy: .public)")
                return false
            }
            entries[displayID] = Entry(original: original, factors: [:], applied: nil)
            updateObservers()
        }
        entries[displayID]?.factors[source] = factor
        return apply(displayID)
    }

    func removeFactor(for displayID: CGDirectDisplayID, source: Source) {
        setFactor(1, for: displayID, source: source)
    }

    func restore(_ displayID: CGDirectDisplayID) {
        guard let entry = entries.removeValue(forKey: displayID) else { return }
        if CGDisplayIsOnline(displayID) != 0 {
            Self.writeTable(entry.original, to: displayID)
        }
        updateObservers()
    }

    func restoreAll() {
        for displayID in Array(entries.keys) {
            restore(displayID)
        }
    }

    func reapplyIfReset() {
        for (displayID, entry) in entries {
            guard CGDisplayIsOnline(displayID) != 0 else {
                entries.removeValue(forKey: displayID)
                continue
            }
            guard let current = Self.readTable(displayID) else { continue }
            if let applied = entry.applied, current.matches(applied) { continue }
            if entry.combinedFactor <= 1 {
                entries[displayID]?.original = current
            }
            apply(displayID)
        }
        updateObservers()
    }

    @discardableResult
    private func apply(_ displayID: CGDirectDisplayID) -> Bool {
        guard let entry = entries[displayID] else { return false }
        let table = entry.original.scaled(by: entry.combinedFactor)
        guard Self.writeTable(table, to: displayID) else {
            logger.error("Couldn't write gamma table for display \(displayID, privacy: .public)")
            return false
        }
        entries[displayID]?.applied = table
        return true
    }

    // MARK: - System resets

    private func updateObservers() {
        if entries.isEmpty {
            observers.forEach { $0.center.removeObserver($0.token) }
            observers.removeAll()
            reapplyWorkItem?.cancel()
            reapplyWorkItem = nil
            return
        }
        guard observers.isEmpty else { return }

        let schedule: @Sendable (Notification) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleReapply() }
        }
        let center = NotificationCenter.default
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        observers.append((center, center.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main, using: schedule)))
        observers.append((workspaceCenter, workspaceCenter.addObserver(
            forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main, using: schedule)))
        observers.append((center, center.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.restoreAll() }
            }))
    }

    private func scheduleReapply() {
        reapplyWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.reapplyWorkItem = nil
                self?.reapplyIfReset()
            }
        }
        reapplyWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: item)
    }

    // MARK: - CoreGraphics

    private static func readTable(_ displayID: CGDirectDisplayID) -> GammaTable? {
        let capacity = CGDisplayGammaTableCapacity(displayID)
        guard capacity > 0 else { return nil }
        var red = [CGGammaValue](repeating: 0, count: Int(capacity))
        var green = red
        var blue = red
        var count: UInt32 = 0
        guard CGGetDisplayTransferByTable(displayID, capacity, &red, &green, &blue, &count) == .success,
              count > 0 else { return nil }
        let length = Int(min(count, capacity))
        return GammaTable(red: Array(red.prefix(length)), green: Array(green.prefix(length)), blue: Array(blue.prefix(length)))
    }

    @discardableResult
    private static func writeTable(_ table: GammaTable, to displayID: CGDirectDisplayID) -> Bool {
        let count = min(table.red.count, table.green.count, table.blue.count)
        guard count > 0 else { return false }
        return CGSetDisplayTransferByTable(displayID, UInt32(count), table.red, table.green, table.blue) == .success
    }
}