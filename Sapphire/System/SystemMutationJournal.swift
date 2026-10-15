//
//  SystemMutationJournal.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-10-08

import CoreAudio
import Foundation
import os

enum SystemMutationKind: String, Codable, CaseIterable {
    case lowPowerMode
    case lidAutoMute
}

struct SystemMutationRecord: Codable, Equatable {
    let kind: SystemMutationKind
    let appliedValue: Bool
    let target: String?
    let recordedAt: Date
}

enum SystemMutationRestorePolicy {
    static func shouldRestore(_ record: SystemMutationRecord, currentValue: Bool?, currentTarget: String?) -> Bool {
        guard let currentValue, currentValue == record.appliedValue else { return false }
        if let target = record.target { return target == currentTarget }
        return true
    }
}

final class SystemMutationJournal: @unchecked Sendable {
    static let shared = SystemMutationJournal(fileURL: SystemMutationJournal.defaultURL)

    private let fileURL: URL?
    private let lock = NSLock()
    private var records: [SystemMutationKind: SystemMutationRecord]

    init(fileURL: URL?) {
        self.fileURL = fileURL
        if let fileURL, let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([SystemMutationRecord].self, from: data) {
            records = Dictionary(decoded.map { ($0.kind, $0) }, uniquingKeysWith: { _, latest in latest })
        } else {
            records = [:]
        }
    }

    private static var defaultURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Sapphire", isDirectory: true)
            .appendingPathComponent("SystemState", isDirectory: true)
            .appendingPathComponent("system-mutations.json", isDirectory: false)
    }

    var pending: [SystemMutationRecord] {
        lock.lock()
        defer { lock.unlock() }
        return records.values.sorted { $0.recordedAt < $1.recordedAt }
    }

    func record(_ record: SystemMutationRecord) {
        lock.lock()
        records[record.kind] = record
        let snapshot = Array(records.values)
        lock.unlock()
        persist(snapshot)
    }

    func clear(_ kind: SystemMutationKind) {
        lock.lock()
        guard records.removeValue(forKey: kind) != nil else {
            lock.unlock()
            return
        }
        let snapshot = Array(records.values)
        lock.unlock()
        persist(snapshot)
    }

    private func persist(_ snapshot: [SystemMutationRecord]) {
        guard let fileURL else { return }
        if snapshot.isEmpty {
            try? FileManager.default.removeItem(at: fileURL)
            return
        }
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.cshariq.sapphire", category: "SystemMutationJournal")
                .error("Could not write the system-mutation journal: \(error.localizedDescription, privacy: .public)")
        }
    }
}

// MARK: - Launch recovery

@MainActor
enum SystemMutationRecovery {
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.cshariq.sapphire", category: "SystemMutationRecovery")

    static func restoreAfterUnexpectedExit(journal: SystemMutationJournal = .shared) {
        for record in journal.pending {
            switch record.kind {
            case .lowPowerMode:
                restoreLowPowerMode(record, journal: journal)
            case .lidAutoMute:
                let current = SystemControl.isMuted()
                if SystemMutationRestorePolicy.shouldRestore(record, currentValue: current, currentTarget: defaultOutputDeviceUID()) {
                    SystemControl.setMuted(to: !record.appliedValue)
                    log.info("Unmuted the output device left muted by lid automation before an unexpected exit.")
                }
                journal.clear(.lidAutoMute)
            }
        }
    }

    private static func restoreLowPowerMode(_ record: SystemMutationRecord, journal: SystemMutationJournal) {
        let current = ProcessInfo.processInfo.isLowPowerModeEnabled
        guard SystemMutationRestorePolicy.shouldRestore(record, currentValue: current, currentTarget: nil) else {
            journal.clear(.lowPowerMode)
            return
        }
        guard let helper = BatteryManager.shared.getHelper() else { return }
        let reply: (Error?) -> Void = { error in
            DispatchQueue.main.async {
                if let error {
                    log.error("Could not restore Low Power Mode after an unexpected exit: \(error.localizedDescription, privacy: .public)")
                } else {
                    journal.clear(.lowPowerMode)
                    log.info("Turned off Low Power Mode left on by lid automation before an unexpected exit.")
                }
            }
        }
        if record.appliedValue {
            helper.disableLowPowerMode(reply: reply)
        } else {
            helper.enableLowPowerMode(reply: reply)
        }
    }

    nonisolated static func defaultOutputDeviceUID() -> String? {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID) == noErr,
              deviceID != kAudioObjectUnknown else { return nil }
        return CoreAudioDevices.uid(of: deviceID)
    }
}