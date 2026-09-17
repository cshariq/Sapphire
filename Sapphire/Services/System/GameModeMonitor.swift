//
//  GameModeMonitor.swift
//  Sapphire
//
//  Created by Ahmet Yıldız on 2025-09-17.
//

import AppKit
import ApplicationServices
import Combine

/// Heuristic Game Mode detection. macOS has no public API to read whether Game Mode is active;
/// it turns on when a recognized game (LSApplicationCategoryType = games) enters native full screen.
enum GameModeDetection {
    static let gamesCategory = "public.app-category.games"

    static func isGamesCategory(_ category: String?) -> Bool {
        guard let category else { return false }
        return category == gamesCategory || category.hasSuffix(".games")
    }

    static func isGamesApplication(bundleID: String) -> Bool {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
              let bundle = Bundle(url: appURL) else {
            return false
        }
        let category = bundle.infoDictionary?["LSApplicationCategoryType"] as? String
        return isGamesCategory(category)
    }

    static func isFrontmostGameFullScreen(
        frontmostPID: pid_t?,
        evaluation: FullScreenDetector.Evaluation
    ) -> Bool {
        guard let frontmostPID else { return false }
        return evaluation.displays.contains { $0.pid == frontmostPID && $0.isFullScreen }
    }
}

@MainActor
final class GameModeMonitor: ObservableObject {
    static let shared = GameModeMonitor()

    @Published private(set) var isGameModeLikelyActive = false

    private let activeAppMonitor = ActiveAppMonitor.shared
    private var cancellables = Set<AnyCancellable>()
    private var evaluationGeneration = 0

    private init() {
        Publishers.CombineLatest(
            activeAppMonitor.$activeAppBundleID,
            activeAppMonitor.$fullScreenDisplayIDs
        )
        .debounce(for: .milliseconds(250), scheduler: DispatchQueue.main)
        .sink { [weak self] _, _ in self?.reevaluate() }
        .store(in: &cancellables)

        reevaluate()
    }

    private func reevaluate() {
        guard let bundleID = activeAppMonitor.activeAppBundleID,
              GameModeDetection.isGamesApplication(bundleID: bundleID) else {
            updateActive(false)
            return
        }

        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        evaluationGeneration += 1
        let generation = evaluationGeneration
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let isAccessibilityTrusted = AXIsProcessTrusted()

        DispatchQueue.global(qos: .userInitiated).async {
            let evaluation = FullScreenDetector.evaluate(
                ownPID: ownPID,
                isAccessibilityTrusted: isAccessibilityTrusted
            )
            DispatchQueue.main.async {
                guard generation == self.evaluationGeneration else { return }
                let isActive = GameModeDetection.isFrontmostGameFullScreen(
                    frontmostPID: frontmostPID,
                    evaluation: evaluation
                )
                self.updateActive(isActive)
            }
        }
    }

    private func updateActive(_ active: Bool) {
        guard isGameModeLikelyActive != active else { return }
        isGameModeLikelyActive = active
    }
}
