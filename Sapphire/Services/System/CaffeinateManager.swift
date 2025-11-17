//
//  CaffeinateManager.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-08-17.
//

import Foundation
import Combine
import os.log

@MainActor
class CaffeineManager: ObservableObject {
    static let shared = CaffeineManager()
    private let settings = SettingsModel.shared
    @Published private(set) var isActive = false

    private var caffeineTask: Process?
    private var isUsingClamshellMode = false

    private init() {}

    func toggle() {
        if isActive {
            stop()
        } else {
            start()
        }
    }

    func start(forcePreventSleepInClamshell: Bool = false) {
        guard !isActive else { return }

        if forcePreventSleepInClamshell || settings.settings.sleepInClamshell {
            // MARK: Clamshell Mode (XPC Method)
            guard let helper = BatteryManager.shared.getHelper() else {
                os_log("CaffeineManager: Could not connect to helper tool.")
                return
            }

            helper.preventSystemSleep { [weak self] error in
                if let error = error {
                    os_log("CaffeineManager: Helper failed to prevent sleep: %{public}@", error.localizedDescription)
                    self?.isActive = false
                } else {
                    self?.isUsingClamshellMode = true
                    self?.isActive = true
                    print("[CaffeineManager] System sleep prevented via helper for clamshell mode.")
                }
            }
        } else {
            // MARK: Default Mode (Caffeinate Command)
            caffeineTask = Process()
            caffeineTask?.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
            caffeineTask?.arguments = ["-d", "-i", "-s"]

            do {
                try caffeineTask?.run()
                isUsingClamshellMode = false
                isActive = true
                print("[CaffeineManager] Caffeinate process started.")
            } catch {
                print("[CaffeineManager] Failed to start caffeinate process: \(error)")
                caffeineTask = nil
                isActive = false
            }
        }
    }

    func stop() {
        guard isActive else { return }

        if isUsingClamshellMode {
            // MARK: Restore Sleep via XPC
            guard let helper = BatteryManager.shared.getHelper() else {
                os_log("CaffeineManager: Could not connect to helper tool to restore sleep.")
                return
            }
            helper.allowSystemSleep { error in
                if let error = error {
                    os_log("CaffeineManager: Helper failed to restore sleep: %{public}@", error.localizedDescription)
                } else {
                    print("[CaffeineManager] System sleep restored via helper.")
                }
            }
        } else if let task = caffeineTask {
            // MARK: Terminate Caffeinate Process
            task.terminate()
            caffeineTask = nil
            print("[CaffeineManager] Caffeinate process terminated.")
        }

        isActive = false
        isUsingClamshellMode = false
    }
}