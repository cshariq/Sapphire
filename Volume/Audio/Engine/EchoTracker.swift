//
//  EchoTracker.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-21

import Foundation
import os

@MainActor
final class EchoTracker {

    var onTimeout: ((_ uid: String) -> Void)?

    private let label: String
    private let logger: Logger
    private let timeoutDuration: TimeInterval

    private var activeTimeouts: [String: Set<Int>] = [:]
    private var nextToken: Int = 0

    init(label: String, timeoutDuration: TimeInterval = 2.0,
         logger: Logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.cshariq.sapphire", category: "EchoTracker")) {
        self.label = label
        self.timeoutDuration = timeoutDuration
        self.logger = logger
    }

    func increment(_ uid: String) {
        let token = nextToken
        nextToken += 1
        activeTimeouts[uid, default: []].insert(token)
        let duration = timeoutDuration
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard let self, !Task.isCancelled else { return }
            guard self.activeTimeouts[uid]?.remove(token) != nil else { return }
            if self.activeTimeouts[uid]?.isEmpty == true {
                self.activeTimeouts.removeValue(forKey: uid)
            }
            self.logger.warning("\(self.label) echo for \(uid) timed out")
            self.onTimeout?(uid)
        }
    }

    func consume(_ uid: String) -> Bool {
        guard let token = activeTimeouts[uid]?.min() else { return false }
        activeTimeouts[uid]?.remove(token)
        if activeTimeouts[uid]?.isEmpty == true {
            activeTimeouts.removeValue(forKey: uid)
        }
        return true
    }

    var hasPending: Bool {
        !activeTimeouts.isEmpty
    }
}