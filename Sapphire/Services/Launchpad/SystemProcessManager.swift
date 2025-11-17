//
//  SystemProcessManager.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-09-17.
//

import AppKit

class LaunchInterceptor {
    static let shared = LaunchInterceptor()

    private var isObserving = false

    var interceptNextMissionControlLaunch = false

    private init() {}

    func startObserving() {
        guard !isObserving else { return }
        isObserving = true
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleAppLaunch),
            name: NSWorkspace.willLaunchApplicationNotification,
            object: nil
        )
    }

    func stopObserving() {
        guard isObserving else { return }
        isObserving = false
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    @objc private func handleAppLaunch(notification: Notification) {
        guard interceptNextMissionControlLaunch else { return }

        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
            return
        }

        if app.bundleIdentifier == "com.apple.dock" && app.executableURL?.lastPathComponent == "Dock" {
            if app.bundleURL?.lastPathComponent == "Mission Control.app" {
            }

            print("[LaunchInterceptor] Intercepting Mission Control launch...")

            app.terminate()

            interceptNextMissionControlLaunch = false
        }
    }
}