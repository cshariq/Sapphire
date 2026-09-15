//
//  FullScreenDisplayMonitor.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-15.
//

import AppKit
import Combine
import os.log

private let fullScreenLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Sapphire", category: "FullScreenDisplayMonitor")

// MARK: - Resolver

enum FullScreenDisplayResolver {
    struct Display: Equatable {
        let id: CGDirectDisplayID
        let uuid: String?
        let bounds: CGRect
        let isMain: Bool
    }

    struct Window: Equatable {
        let layer: Int
        let ownerPID: pid_t
        let alpha: Double
        let bounds: CGRect
    }

    static func nativeFullScreenDisplays(
        displays: [Display],
        managedDisplaySpaces: [[String: Any]]
    ) -> Set<CGDirectDisplayID> {
        var entriesByIdentifier: [String: [String: Any]] = [:]
        for entry in managedDisplaySpaces {
            if let identifier = entry["Display Identifier"] as? String {
                entriesByIdentifier[identifier.uppercased()] = entry
            }
        }
        let spanningEntry = entriesByIdentifier.count == 1 ? entriesByIdentifier["MAIN"] : nil

        return Set(displays.compactMap { display in
            let entry = spanningEntry
                ?? display.uuid.flatMap { entriesByIdentifier[$0.uppercased()] }
                ?? (display.isMain ? entriesByIdentifier["MAIN"] : nil)
            guard let entry, currentSpaceType(in: entry) == fullScreenSpaceType else { return nil }
            return display.id
        })
    }

    static func borderlessFullScreenDisplays(
        displays: [Display],
        windows: [Window],
        ownPID: pid_t
    ) -> Set<CGDirectDisplayID> {
        let candidates = windows.filter {
            $0.layer == 0 && $0.ownerPID != ownPID && $0.alpha > minimumVisibleAlpha
        }
        return Set(displays.compactMap { display in
            let displayArea = display.bounds.width * display.bounds.height
            guard displayArea > 0,
                  let front = candidates.first(where: {
                      area(of: $0.bounds.intersection(display.bounds)) >= displayArea * minimumFrontShare
                  }) else {
                return nil
            }
            let overlap = front.bounds.intersection(display.bounds)
            let covers = overlap.width >= display.bounds.width * coverageRatio
                && overlap.height >= display.bounds.height * coverageRatio
            return covers ? display.id : nil
        })
    }

    private static let fullScreenSpaceType = Int(CGSSpaceType.fullscreen.rawValue)
    private static let minimumVisibleAlpha = 0.05
    private static let minimumFrontShare: CGFloat = 0.1
    private static let coverageRatio: CGFloat = 0.99

    private static func area(of rect: CGRect) -> CGFloat {
        rect.isNull ? 0 : rect.width * rect.height
    }

    private static func currentSpaceType(in displayEntry: [String: Any]) -> Int? {
        let current = displayEntry["Current Space"] as? [String: Any]
            ?? (displayEntry["Spaces"] as? [[String: Any]])?.first { ($0["is-current"] as? Bool) == true }
        return (current?["type"] as? NSNumber)?.intValue
    }
}

// MARK: - Monitor

@MainActor
final class FullScreenDisplayMonitor: ObservableObject {
    static let shared = FullScreenDisplayMonitor()

    @Published private(set) var displayIDs: Set<CGDirectDisplayID> = []

    private static let coalesceInterval: TimeInterval = 0.05

    private var cancellables = Set<AnyCancellable>()
    private var isRefreshScheduled = false
    private var generation = 0
    private let snapshotQueue = DispatchQueue(label: "com.sapphire.fullscreen-snapshot", qos: .userInitiated)

    private init() {
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        let workspacePublishers = [
            NSWorkspace.activeSpaceDidChangeNotification,
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.didHideApplicationNotification,
            NSWorkspace.didUnhideApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
            NSWorkspace.didWakeNotification,
            NSWorkspace.screensDidWakeNotification
        ].map { workspaceCenter.publisher(for: $0) }
        let screenPublisher = NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)

        Publishers.MergeMany(workspacePublishers + [screenPublisher])
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.setNeedsRefresh() }
            .store(in: &cancellables)

        WindowServerSpaceEvents.install()
        refreshNow()
    }

    func setNeedsRefresh() {
        guard !isRefreshScheduled else { return }
        isRefreshScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.coalesceInterval) { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.isRefreshScheduled = false
                self.refreshNow()
            }
        }
    }

    private func refreshNow() {
        generation += 1
        let token = generation
        let ownPID = ProcessInfo.processInfo.processIdentifier
        snapshotQueue.async { [weak self] in
            let displayIDs = Self.captureFullScreenDisplays(ownPID: ownPID)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, token == self.generation, self.displayIDs != displayIDs else { return }
                    let ids = displayIDs.sorted().map(String.init).joined(separator: ",")
                    fullScreenLog.info("Full-screen displays changed: displayIDs=[\(ids, privacy: .public)]")
                    self.displayIDs = displayIDs
                }
            }
        }
    }

    // MARK: WindowServer snapshot (snapshot queue)

    nonisolated private static func captureFullScreenDisplays(ownPID: pid_t) -> Set<CGDirectDisplayID> {
        let displays = activeDisplays()
        guard !displays.isEmpty else { return [] }

        let connection = CGSMainConnectionID()
        let managedDisplaySpaces = connection == 0
            ? []
            : (CGSCopyManagedDisplaySpaces(connection) as? [[String: Any]]) ?? []
        let native = FullScreenDisplayResolver.nativeFullScreenDisplays(
            displays: displays,
            managedDisplaySpaces: managedDisplaySpaces
        )

        let remaining = displays.filter { !native.contains($0.id) }
        guard !remaining.isEmpty else { return native }
        return native.union(FullScreenDisplayResolver.borderlessFullScreenDisplays(
            displays: remaining,
            windows: normalLevelOnScreenWindows(),
            ownPID: ownPID
        ))
    }

    nonisolated private static func activeDisplays() -> [FullScreenDisplayResolver.Display] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return [] }

        return ids.prefix(Int(count)).compactMap { id in
            guard CGDisplayMirrorsDisplay(id) == kCGNullDirectDisplay else { return nil }
            let uuid = CGDisplayCreateUUIDFromDisplayID(id).map {
                CFUUIDCreateString(kCFAllocatorDefault, $0.takeRetainedValue()) as String
            }
            return FullScreenDisplayResolver.Display(
                id: id,
                uuid: uuid,
                bounds: CGDisplayBounds(id),
                isMain: CGDisplayIsMain(id) != 0
            )
        }
    }

    nonisolated private static func normalLevelOnScreenWindows() -> [FullScreenDisplayResolver.Window] {
        guard let infos = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return []
        }
        return infos.compactMap { info in
            guard (info[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  let ownerPID = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  let boundsDictionary = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDictionary as CFDictionary) else {
                return nil
            }
            return FullScreenDisplayResolver.Window(
                layer: 0,
                ownerPID: ownerPID,
                alpha: (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1,
                bounds: bounds
            )
        }
    }
}

// MARK: - WindowServer Space events

private typealias CGSNotifyProc = @convention(c) (UInt32, UnsafeMutableRawPointer?, UInt32, UnsafeMutableRawPointer?) -> Void

@_silgen_name("CGSRegisterNotifyProc")
private func CGSRegisterNotifyProc(_ proc: CGSNotifyProc, _ type: UInt32, _ userData: UnsafeMutableRawPointer?) -> Int32

private enum WindowServerSpaceEvents {
    private static let eventTypes: [UInt32] = [1301, 1302, 1401]
    private static var isInstalled = false

    @MainActor
    static func install() {
        guard !isInstalled else { return }
        isInstalled = true
        for eventType in eventTypes {
            let result = CGSRegisterNotifyProc(windowServerSpaceEventCallback, eventType, nil)
            if result != 0 {
                fullScreenLog.error("CGSRegisterNotifyProc(\(eventType)) failed: \(result)")
            }
        }
    }
}

private func windowServerSpaceEventCallback(
    _: UInt32,
    _: UnsafeMutableRawPointer?,
    _: UInt32,
    _: UnsafeMutableRawPointer?
) {
    guard Thread.isMainThread else {
        DispatchQueue.main.async {
            MainActor.assumeIsolated { FullScreenDisplayMonitor.shared.setNeedsRefresh() }
        }
        return
    }
    MainActor.assumeIsolated { FullScreenDisplayMonitor.shared.setNeedsRefresh() }
}