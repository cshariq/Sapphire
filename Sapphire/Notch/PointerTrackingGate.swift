//
//  PointerTrackingGate.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-10-05

import AppKit

@MainActor
final class PointerTrackingGate {
    private unowned let view: NSView
    private var parked: [NSTrackingArea] = []
    private(set) var isOpen = true

    init(view: NSView) {
        self.view = view
    }

    func shouldInstall(_ area: NSTrackingArea) -> Bool {
        guard !isOpen else { return true }
        if !parked.contains(where: { $0 === area }) { parked.append(area) }
        return false
    }

    func didRemove(_ area: NSTrackingArea) {
        parked.removeAll { $0 === area }
    }

    func setOpen(_ open: Bool, install: (NSTrackingArea) -> Void) {
        guard open != isOpen else { return }
        isOpen = open
        if open {
            let areas = parked
            parked = []
            areas.forEach(install)
        } else {
            let areas = view.trackingAreas
            areas.forEach(view.removeTrackingArea)
            parked = areas
        }
    }
}

@MainActor
protocol PointerTrackingGated: NSView {
    func setPointerTrackingEnabled(_ enabled: Bool)
}