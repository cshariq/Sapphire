//
//  LaunchAtLoginPolicy.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-10-08

import Foundation
import ServiceManagement

enum LaunchAtLoginPolicy {
    enum ServiceState: Equatable {
        case enabled
        case requiresApproval
        case notRegistered
        case notFound

        init(_ status: SMAppService.Status) {
            switch status {
            case .enabled: self = .enabled
            case .requiresApproval: self = .requiresApproval
            case .notRegistered: self = .notRegistered
            case .notFound: self = .notFound
            @unknown default: self = .notFound
            }
        }

        var isOn: Bool { self == .enabled || self == .requiresApproval }
    }

    enum Action: Equatable {
        case none
        case register
        case unregister
        case adoptSystemState(Bool)
    }

    static func action(
        wanted: Bool,
        state: ServiceState,
        lastApplied: Bool?,
        isUserChange: Bool,
        onboardingComplete: Bool
    ) -> Action {
        guard onboardingComplete else { return .none }
        if state.isOn == wanted { return .none }
        if isUserChange {
            return wanted ? .register : .unregister
        }
        if lastApplied == nil || lastApplied == wanted {
            return .adoptSystemState(state.isOn)
        }
        return wanted ? .register : .unregister
    }
}

enum LaunchAtLoginReconciler {
    private static let lastAppliedKey = "launchAtLoginLastApplied"
    private static let queue = DispatchQueue(label: "com.sapphire.launch-at-login", qos: .utility)

    static func reconcile(wanted: Bool, isUserChange: Bool, adopt: @escaping @MainActor (Bool) -> Void) {
        let onboardingComplete = !OnboardingLaunchPolicy.shouldShowOnboarding
        queue.async {
            let service = SMAppService.mainApp
            let defaults = UserDefaults.standard
            let lastApplied = defaults.object(forKey: lastAppliedKey) as? Bool
            let action = LaunchAtLoginPolicy.action(
                wanted: wanted,
                state: .init(service.status),
                lastApplied: lastApplied,
                isUserChange: isUserChange,
                onboardingComplete: onboardingComplete
            )
            do {
                switch action {
                case .none:
                    if onboardingComplete { defaults.set(wanted, forKey: lastAppliedKey) }
                case .register:
                    try service.register()
                    defaults.set(true, forKey: lastAppliedKey)
                case .unregister:
                    try service.unregister()
                    defaults.set(false, forKey: lastAppliedKey)
                case .adoptSystemState(let isOn):
                    defaults.set(isOn, forKey: lastAppliedKey)
                    DispatchQueue.main.async { MainActor.assumeIsolated { adopt(isOn) } }
                }
            } catch {
                print("[LaunchAtLogin] Failed to update launch at login status: \(error)")
            }
        }
    }
}