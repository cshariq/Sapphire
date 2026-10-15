//
//  MenuBarFittedDivider.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-10-12
//

import AppKit

@MainActor
final class MenuBarFittedDivider {
    private enum Fit {
        static let initialMenuGap: CGFloat = 8
        static let menuGapStep: CGFloat = 16
        static let maxAttempts = 10
        static let settleDelay: TimeInterval = 0.3
        static let tolerance: CGFloat = 3
    }

    private let minimumLength: CGFloat
    private let target: () -> NSStatusItem?

    private static let storedLengthsKey = "SapphireFittedDividerLengths"

    private var fittedLengths: [String: CGFloat] = (UserDefaults.standard.dictionary(forKey: storedLengthsKey) as? [String: Double] ?? [:])
        .mapValues { CGFloat($0) }
    private var fitGeneration = 0
    private var observers: [NSObjectProtocol] = []
    private var menuGap: CGFloat = Fit.initialMenuGap
    private(set) var isRunning = false

    init(minimumLength: CGFloat, target: @escaping () -> NSStatusItem?) {
        self.minimumLength = minimumLength
        self.target = target
    }

    func collapsedLength(for item: NSStatusItem) -> CGFloat {
        guard item === target() else { return minimumLength }
        return fittedLengths[item.autosaveName as String] ?? minimumLength
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        let workspace = NSWorkspace.shared.notificationCenter
        observers.append(workspace.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleFit(after: 0.1) }
        })
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.scheduleFit(after: 1.0) }
            })
        }
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.menuGap = Fit.initialMenuGap
                self.scheduleFit(after: 0.5)
            }
        })
        scheduleFit()
    }

    func stop() {
        isRunning = false
        fitGeneration += 1
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0); NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
    }

    func forget(_ item: NSStatusItem) {
        fittedLengths[item.autosaveName as String] = nil
        persistLengths()
    }

    func scheduleFit(after delay: TimeInterval = 0.2) {
        guard isRunning else { return }
        fitGeneration += 1
        let generation = fitGeneration
        guard target() != nil else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.measure(attempt: 0, generation: generation)
        }
    }

    // MARK: - Fitting

    private func measure(attempt: Int, generation: Int) {
        guard generation == fitGeneration, let item = target() else { return }
        let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let length = item.length
        let itemID = ObjectIdentifier(item)
        DispatchQueue.global(qos: .userInitiated).async {
            let menuFrame = pid.flatMap { MenuBarHitTest.applicationMenuFrame(pid: $0) }
            let drawn = MenuBarAgentHost.drawnItems()
            DispatchQueue.main.async {
                MainActor.assumeIsolated { [weak self] in
                    guard let self, generation == self.fitGeneration, let item = self.target(),
                          ObjectIdentifier(item) == itemID, item.length == length else { return }
                    self.adjust(item, menuFrame: menuFrame, drawn: drawn, attempt: attempt, generation: generation)
                }
            }
        }
    }

    private var drawnBound: CGFloat?
    private var droppedBound: CGFloat?

    private func adjust(_ item: NSStatusItem, menuFrame: CGRect?, drawn: [MenuBarAgentHost.DrawnItem]?, attempt: Int, generation: Int) {
        if attempt == 0 {
            drawnBound = nil
            droppedBound = nil
        }
        guard let drawn else {
            retry(attempt: attempt, generation: generation)
            return
        }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        guard let chevron = drawn.last(where: { $0.ownerPID == ownPID }),
              let screen = NSScreen.screens.first(where: { $0.frame.minX <= chevron.frame.midX && chevron.frame.midX < $0.frame.maxX }) else {
            retry(attempt: attempt, generation: generation)
            return
        }

        let notchMinX = screen.auxiliaryTopLeftArea.map { screen.frame.minX + $0.width }
        let menuRight = menuFrame.map(\.maxX) ?? notchMinX ?? (screen.frame.minX + 400)
        let limit = max(menuRight, notchMinX ?? -.greatestFiniteMagnitude) + menuGap

        let divider = drawn.first { $0.ownerPID == ownPID && $0.frame.width >= max(60, item.length * 0.8) }

        var length: CGFloat
        if let divider {
            drawnBound = max(drawnBound ?? 0, item.length)
            let error = divider.frame.minX - limit
            if abs(error) <= Fit.tolerance || (error > 0 && droppedBound.map { $0 - item.length <= 2 } == true) {
                settle(item, at: item.length)
                return
            }
            length = item.length + error
            if let droppedBound { length = min(length, droppedBound - 1) }
        } else if item.length <= minimumLength + 1 {
            length = chevron.frame.minX - limit - 30
        } else {
            droppedBound = min(droppedBound ?? .greatestFiniteMagnitude, item.length)
            if let drawnBound {
                guard item.length - drawnBound > 2 else {
                    settle(item, at: drawnBound)
                    return
                }
                length = (drawnBound + item.length) / 2
            } else {
                length = min(item.length - Fit.menuGapStep, chevron.frame.minX - limit - 30)
            }
        }
        length = max(minimumLength, length.rounded(.down))
        guard attempt < Fit.maxAttempts else {
            if let drawnBound { settle(item, at: drawnBound) }
            print("[MenuBarFittedDivider] Could not fit the collapsed divider (length \(item.length), gap \(menuGap)).")
            return
        }
        if abs(length - item.length) >= 1 {
            item.length = length
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Fit.settleDelay) { [weak self] in
            self?.measure(attempt: attempt + 1, generation: generation)
        }
    }

    private func settle(_ item: NSStatusItem, at length: CGFloat) {
        if abs(item.length - length) >= 1 { item.length = length }
        fittedLengths[item.autosaveName as String] = length
        persistLengths()
        MenuBarItemCatalog.shared.invalidate()
    }

    private func persistLengths() {
        UserDefaults.standard.set(fittedLengths.mapValues(Double.init), forKey: Self.storedLengthsKey)
    }

    private func retry(attempt: Int, generation: Int) {
        guard attempt < Fit.maxAttempts else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + Fit.settleDelay) { [weak self] in
            self?.measure(attempt: attempt + 1, generation: generation)
        }
    }
}