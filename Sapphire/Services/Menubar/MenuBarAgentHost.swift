//
//  MenuBarAgentHost.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-10-12
//

import AppKit
import ApplicationServices

enum MenuBarAgentHost {
    nonisolated static let bundleIdentifier = "com.apple.MenuBarAgent"

    nonisolated static var agentPID: pid_t? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first?.processIdentifier
    }

    nonisolated static var isActive: Bool { agentPID != nil }

    // MARK: - Drawn items

    struct DrawnItem: Equatable {
        let ownerPID: pid_t
        let frame: CGRect
        let systemIdentifier: String?
        var ownIdentifier: String?
        let element: AXUIElement

        static func == (lhs: DrawnItem, rhs: DrawnItem) -> Bool {
            lhs.ownerPID == rhs.ownerPID && lhs.frame == rhs.frame
                && lhs.systemIdentifier == rhs.systemIdentifier && lhs.ownIdentifier == rhs.ownIdentifier
        }
    }

    nonisolated static func drawnItems(timeout: Float = 0.25) -> [DrawnItem]? {
        guard AccessibilityTrustMonitor.isCurrentlyTrusted(), let agentPID else { return nil }
        let agent = AX.application(pid: agentPID)
        AX.setMessagingTimeout(timeout, on: agent)
        guard let window = AX.elements(kAXWindowsAttribute as String, of: agent).first else { return nil }

        var items: [DrawnItem] = []
        for child in AX.children(of: window) {
            guard let frame = AX.frame(of: child), frame.width > 0, frame.height > 0 else { return nil }
            var element = child
            var owner = AX.pid(of: element) ?? agentPID
            while owner == agentPID, let next = AX.children(of: element).first {
                element = next
                owner = AX.pid(of: element) ?? agentPID
            }
            let systemIdentifier = owner == agentPID ? AX.string("AXIdentifier", of: element) : nil
            items.append(DrawnItem(ownerPID: owner, frame: frame, systemIdentifier: systemIdentifier, ownIdentifier: nil, element: element))
        }
        guard !items.isEmpty else { return nil }
        return onBar(items).sorted { $0.frame.minX < $1.frame.minX }
    }

    nonisolated static func onBar(_ items: [DrawnItem]) -> [DrawnItem] {
        items.filter { item in
            !items.contains { other in
                other.frame.width > item.frame.width && other.frame.contains(CGPoint(x: item.frame.midX, y: item.frame.midY))
            }
        }
    }

    nonisolated static func labellingOwnItems(_ items: [DrawnItem], expected: [String]) -> [DrawnItem] {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let ownIndices = items.indices.filter { items[$0].ownerPID == ownPID }
        var labelled = items
        for (index, identifier) in zip(ownIndices.reversed(), expected.reversed()) {
            labelled[index].ownIdentifier = identifier
        }
        return labelled
    }

    // MARK: - Primary action

    @MainActor
    static func attachPrimaryAction(to button: NSStatusBarButton, target: AnyObject, action: Selector) -> Bool {
        let selector = NSSelectorFromString("addTarget:action:forControlEvents:")
        guard button.responds(to: selector),
              let method = class_getInstanceMethod(type(of: button), selector),
              let encoding = method_getTypeEncoding(method).map(String.init(cString:)),
              isSupportedAddTargetEncoding(encoding) else { return false }

        typealias AddTarget = @convention(c) (AnyObject, Selector, AnyObject?, Selector, UInt) -> Void
        let addTarget = unsafeBitCast(button.method(for: selector), to: AddTarget.self)
        addTarget(button, selector, target, action, 1 << 13)
        return true
    }

    nonisolated static func isSupportedAddTargetEncoding(_ encoding: String) -> Bool {
        [("v@:@:", "Q"), ("v40@0:8", "Q32")].contains { encoding.hasPrefix($0.0) && encoding.hasSuffix($0.1) }
    }

    @MainActor
    static func nudgeLayout(of item: NSStatusItem) {
        let baseline = item.length
        let rendered = item.button?.frame.width ?? 0
        guard rendered > 0 else { return }
        item.length = abs(baseline - rendered) <= 0.25 ? rendered + 0.5 : rendered
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.016) {
            item.length = baseline
        }
    }
}