//
//  CaffeinateManager.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-08-17.
//
//
//
//
//
//

import Foundation
import Combine

@MainActor
class CaffeineManager: ObservableObject {
    static let shared = CaffeineManager()

    @Published private(set) var isActive = false
    private var caffeineTask: Process?

    private init() {}

    func toggle() {
        if isActive {
            stop()
        } else {
            start()
        }
    }

    private func start() {
        guard !isActive else { return }

        caffeineTask = Process()
        caffeineTask?.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
        caffeineTask?.arguments = ["-d", "-i", "-s"]

        do {
            try caffeineTask?.run()
            isActive = true
            print("[CaffeineManager] Caffeinate process started.")
        } catch {
            print("[CaffeineManager] Failed to start caffeinate process: \(error)")
            caffeineTask = nil
            isActive = false
        }
    }

    private func stop() {
        guard isActive, let task = caffeineTask else { return }
        task.terminate()
        caffeineTask = nil
        isActive = false
        print("[CaffeineManager] Caffeinate process terminated.")
    }
}