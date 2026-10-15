//
//  AppleMusicSystemQueue.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-26
//

import Foundation
import os

@MainActor
final class AppleMusicSystemQueue {
    static let shared = AppleMusicSystemQueue()

    struct Entry: Decodable, Equatable {
        let id: String
        let title: String
        let artist: String
        let album: String
        let duration: Double
        let storeID: String
    }

    struct Snapshot: Equatable {
        let location: Int
        let items: [Entry]

        var current: Entry? { items.indices.contains(location) ? items[location] : nil }
        var upNext: [Entry] { location + 1 < items.count ? Array(items[(location + 1)...]) : [] }
    }

    enum Position: Int {
        case next = 0
        case later = 1
    }

    private struct QueueResponse: Decodable {
        let ok: Bool
        let location: Int?
        let items: [Entry]?
    }

    private struct StatusResponse: Decodable {
        let ok: Bool
    }

    private let log = Logger(subsystem: "com.cshariq.sapphire", category: "AppleMusicQueue")

    private init() {}

    nonisolated private static let paths: (script: String, framework: String)? = {
        guard let resources = Bundle.main.resourcePath else { return nil }
        let script = (resources as NSString).appendingPathComponent("mediaremote-queue.pl")
        let framework = (resources as NSString).appendingPathComponent("SapphireMediaQueue.framework")
        let fm = FileManager.default
        guard fm.fileExists(atPath: script), fm.fileExists(atPath: framework) else { return nil }
        return (script, framework)
    }()

    var isAvailable: Bool { Self.paths != nil }

    // MARK: - Reads

    func snapshot(limit: Int = 60) async -> Snapshot? {
        guard let data = await run("queue", environment: ["SMQ_LIMIT": String(limit)]),
              let response = try? JSONDecoder().decode(QueueResponse.self, from: data),
              response.ok, let items = response.items else { return nil }
        return Snapshot(location: response.location ?? 0, items: items)
    }

    // MARK: - Queue edits

    func playItem(id: String) async -> Bool {
        await status("play_item", environment: ["SMQ_ITEM": id])
    }

    func removeItem(id: String) async -> Bool {
        await status("remove_item", environment: ["SMQ_ITEM": id])
    }

    func clearUpNext() async -> Bool {
        await status("clear_up_next", environment: [:])
    }

    func insert(storeIDs: [String], position: Position) async -> Bool {
        let ids = storeIDs.filter(Self.isCatalogID)
        guard !ids.isEmpty else { return false }
        return await status("insert", environment: [
            "SMQ_IDS": ids.joined(separator: ","),
            "SMQ_POSITION": String(position.rawValue)
        ])
    }

    func playNow(storeIDs: [String]) async -> Bool {
        let ids = storeIDs.filter(Self.isCatalogID)
        guard let first = ids.first else { return false }
        guard await status("play_now", environment: ["SMQ_IDS": ids.joined(separator: ",")]) else { return false }
        for _ in 0..<6 {
            if let current = await snapshot(limit: 2)?.current, current.storeID == first { return true }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        log.error("play_now: Music.app didn't switch to \(first, privacy: .public)")
        return false
    }

    nonisolated static func isCatalogID(_ id: String) -> Bool {
        !id.isEmpty && id.allSatisfy(\.isNumber)
    }

    // MARK: - Plumbing

    private func status(_ function: String, environment: [String: String]) async -> Bool {
        guard let data = await run(function, environment: environment),
              let response = try? JSONDecoder().decode(StatusResponse.self, from: data) else { return false }
        return response.ok
    }

    private func run(_ function: String, environment: [String: String]) async -> Data? {
        guard let paths = Self.paths else {
            log.error("SapphireMediaQueue helper missing from the app bundle")
            return nil
        }
        let log = self.log
        return await Task.detached(priority: .userInitiated) { () -> Data? in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
            process.arguments = [paths.script, paths.framework, function]
            var env = ProcessInfo.processInfo.environment
            for (key, value) in environment { env[key] = value }
            process.environment = env
            let stdout = Pipe()
            process.standardOutput = stdout
            process.standardError = FileHandle.nullDevice
            process.standardInput = FileHandle.nullDevice
            do {
                try process.run()
            } catch {
                log.error("perl launch failed: \(error.localizedDescription, privacy: .public)")
                return nil
            }
            let watchdog = DispatchWorkItem { if process.isRunning { process.terminate() } }
            DispatchQueue.global().asyncAfter(deadline: .now() + 10, execute: watchdog)
            let data = stdout.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            watchdog.cancel()
            return data.isEmpty ? nil : data
        }.value
    }
}