//
//  MenuBarItemCatalog.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-27
//

import AppKit
import os

extension Notification.Name {
    static let menuBarItemCatalogDidChange = Notification.Name("com.sapphire.menuBarItemCatalogDidChange")
}

struct MenuBarStatusItem: Identifiable {
    let id: String
    let pid: pid_t
    let frame: CGRect
    let name: String?
    let element: AXUIElement

    let isOnScreen: Bool
}

final class MenuBarItemCatalog: @unchecked Sendable {
    static let shared = MenuBarItemCatalog()

    private let queue = DispatchQueue(label: "com.sapphire.menubar-item-catalog", qos: .userInitiated)
    private let lock = NSLock()

    private var items: [MenuBarStatusItem] = []
    private var lastScan: CFAbsoluteTime = 0
    private var isScanPending = false
    private var pendingCompletions: [@MainActor ([MenuBarStatusItem]) -> Void] = []

    private var knownPIDs = Set<pid_t>()
    private var negativeCache: [pid_t: (misses: Int, retryAfter: CFAbsoluteTime)] = [:]

    private var observers: [NSObjectProtocol] = []
    private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.cshariq.sapphire", category: "MenuBarItemCatalog")
    private let ownPID = ProcessInfo.processInfo.processIdentifier

    private static let missBackoff: [CFTimeInterval] = [5, 30, 120, 600]

    private init() {}

    // MARK: - Lifecycle

    @MainActor
    func start() {
        guard observers.isEmpty else { return }
        let seed = NSWorkspace.shared.runningApplications.map(\.processIdentifier)
        queue.async { [self] in knownPIDs.formUnion(seed) }

        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: nil) { [weak self] note in
            guard let self,
                  let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            let pid = app.processIdentifier
            self.queue.async {
                self.knownPIDs.insert(pid)
                self.negativeCache[pid] = nil
            }
            self.invalidate()
        })
        observers.append(center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: nil) { [weak self] note in
            guard let self,
                  let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            let pid = app.processIdentifier
            self.queue.async {
                self.knownPIDs.remove(pid)
                self.negativeCache[pid] = nil
            }
            self.invalidate()
        })
    }

    // MARK: - Reading

    var cachedItems: [MenuBarStatusItem] {
        lock.lock(); defer { lock.unlock() }
        return items
    }

    func items(maxAge: TimeInterval, completion: @escaping @MainActor ([MenuBarStatusItem]) -> Void) {
        lock.lock()
        if !isScanPending, CFAbsoluteTimeGetCurrent() - lastScan <= maxAge, lastScan > 0 {
            let snapshot = items
            lock.unlock()
            DispatchQueue.main.async { MainActor.assumeIsolated { completion(snapshot) } }
            return
        }
        pendingCompletions.append(completion)
        let needsScan = !isScanPending
        isScanPending = true
        lock.unlock()

        guard needsScan else { return }
        queue.async { [self] in
            let started = CFAbsoluteTimeGetCurrent()
            let scanned = scan()
            lock.lock()
            let changed = !Self.sameLayout(items, scanned)
            if changed {
                let onScreen = scanned.filter(\.isOnScreen).count
                let owners = Set(scanned.map(\.pid)).count
                let elapsed = Int((CFAbsoluteTimeGetCurrent() - started) * 1000)
                log.info("Scan: \(scanned.count) items (\(onScreen) on screen) from \(owners) apps in \(elapsed) ms")
            }
            items = scanned
            lastScan = CFAbsoluteTimeGetCurrent()
            isScanPending = false
            let completions = pendingCompletions
            pendingCompletions.removeAll()
            lock.unlock()

            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    for completion in completions { completion(scanned) }
                    if changed {
                        NotificationCenter.default.post(name: .menuBarItemCatalogDidChange, object: nil)
                    }
                }
            }
        }
    }

    func invalidate() {
        lock.lock()
        lastScan = 0
        lock.unlock()
    }

    // MARK: - Scanning (on `queue`)

    private func scan() -> [MenuBarStatusItem] {
        guard AccessibilityTrustMonitor.isCurrentlyTrusted() else { return [] }

        let now = CFAbsoluteTimeGetCurrent()
        let bands = Self.menuBarBands()
        let drawn = MenuBarAgentHost.isActive ? MenuBarAgentHost.drawnItems() : nil
        let drawnOwners = drawn.map { Set($0.map(\.ownerPID)) }
        let agentPID = drawn == nil ? nil : MenuBarAgentHost.agentPID
        var result: [MenuBarStatusItem] = []

        knownPIDs = knownPIDs.filter { kill($0, 0) == 0 || errno == EPERM }
        negativeCache = negativeCache.filter { knownPIDs.contains($0.key) }

        for pid in knownPIDs where pid != ownPID {
            if let entry = negativeCache[pid], entry.retryAfter > now { continue }

            let app = AX.application(pid: pid)
            AX.setMessagingTimeout(0.1, on: app)
            guard let bar = AX.element("AXExtrasMenuBar", of: app) else {
                let misses = (negativeCache[pid]?.misses ?? 0) + 1
                let backoff = Self.missBackoff[min(misses - 1, Self.missBackoff.count - 1)]
                negativeCache[pid] = (misses, now + backoff)
                continue
            }
            negativeCache[pid] = nil

            for (index, child) in AX.children(of: bar).enumerated() {
                AX.setMessagingTimeout(0.1, on: child)
                guard let frame = AX.frame(of: child), frame.width > 0, frame.height > 0 else { continue }
                let identifier = AX.string("AXIdentifier", of: child)
                let name = [
                    AX.string(kAXDescriptionAttribute as String, of: child),
                    AX.title(of: child),
                    AX.string(kAXHelpAttribute as String, of: child),
                ].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.first { !$0.isEmpty }
                let center = CGPoint(x: frame.midX, y: frame.midY)
                let isOnScreen: Bool
                if let drawn, let drawnOwners {
                    if pid == agentPID {
                        isOnScreen = drawn.contains { item in
                            item.ownerPID == pid && (identifier.map { $0 == item.systemIdentifier } ?? (abs(item.frame.midX - frame.midX) < 4))
                        }
                    } else {
                        isOnScreen = drawnOwners.contains(pid)
                    }
                } else {
                    isOnScreen = bands.contains { $0.contains(center) }
                }
                result.append(MenuBarStatusItem(
                    id: "\(pid):\(identifier ?? String(index))",
                    pid: pid,
                    frame: frame,
                    name: name,
                    element: child,
                    isOnScreen: isOnScreen
                ))
            }
        }

        result.sort { $0.frame.minX < $1.frame.minX }
        return result
    }

    private static func menuBarBands() -> [CGRect] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &displays, &count) == .success else { return [] }
        return displays.prefix(Int(count)).map { display in
            let bounds = CGDisplayBounds(display)
            return CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: 50)
        }
    }

    private static func sameLayout(_ lhs: [MenuBarStatusItem], _ rhs: [MenuBarStatusItem]) -> Bool {
        guard lhs.count == rhs.count else { return false }
        return zip(lhs, rhs).allSatisfy { $0.id == $1.id && $0.frame == $1.frame }
    }
}

// MARK: - Hit testing

enum MenuBarHitTest {
    enum Result {
        case bareBar
        case item
        case ownSurface
        case unknown
    }

    static func classify(axPoint: CGPoint) -> Result {
        guard AccessibilityTrustMonitor.isCurrentlyTrusted(),
              let element = AX.element(atAXPoint: axPoint, timeout: 0.15) else { return .unknown }

        if AX.pid(of: element) == ProcessInfo.processInfo.processIdentifier { return .ownSurface }

        switch AX.role(of: element) {
        case .some(kAXMenuBarItemRole): return .item
        case .some(kAXMenuBarRole): return .bareBar
        default: return .unknown
        }
    }

    @MainActor
    static func isEmptySpace(_ result: Result, axPoint: CGPoint, cocoaPoint: CGPoint) -> Bool {
        switch result {
        case .bareBar:
            return true
        case .item:
            return false
        case .ownSurface:
            let hitsOwnSurface = NSApp.windows.contains {
                $0.isVisible && !$0.ignoresMouseEvents && $0.frame.contains(cocoaPoint)
            }
            if hitsOwnSurface { return false }
            fallthrough
        case .unknown:
            return !MenuBarItemCatalog.shared.cachedItems.contains { $0.isOnScreen && $0.frame.contains(axPoint) }
        }
    }

    static func applicationMenuFrame(pid: pid_t) -> CGRect? {
        guard pid != getpid() else { return nil }
        let app = AX.application(pid: pid)
        AX.setMessagingTimeout(0.15, on: app)
        guard let menuBar = AX.element(kAXMenuBarAttribute as String, of: app) else { return nil }
        var union = CGRect.null
        for item in AX.children(of: menuBar) {
            guard AX.role(of: item) == (kAXMenuBarItemRole as String),
                  let frame = AX.frame(of: item), frame.width > 0 else { continue }
            union = union.union(frame)
        }
        return union.isNull ? nil : union
    }
}