//
//  ContinuityShareViewController.swift
//  SapphireShare (public placeholder)
//
//  The "Send with Continuity" share extension is part of the private Continuity feature.
//  A public checkout builds this placeholder, which tells the user the feature isn't available
//  and closes the share sheet. A full checkout builds SapphireShare/ instead (see Extensions.xcconfig).
//

import Cocoa

final class ContinuityShareViewController: NSViewController {
    override var nibName: NSNib.Name? { nil }

    override func loadView() {
        let label = NSTextField(wrappingLabelWithString: String(localized: "Continuity sharing isn't available in this build of Sapphire."))
        label.alignment = .center
        let close = NSButton(title: String(localized: "Close"), target: self, action: #selector(closeSheet))
        close.keyEquivalent = "\r"
        let stack = NSStackView(views: [label, close])
        stack.orientation = .vertical
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        stack.frame = NSRect(x: 0, y: 0, width: 320, height: 110)
        view = stack
    }

    @objc private func closeSheet() {
        let error = NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError)
        extensionContext?.cancelRequest(withError: error)
    }
}
