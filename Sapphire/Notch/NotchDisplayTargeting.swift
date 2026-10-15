//
//  NotchDisplayTargeting.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-10-08

import AppKit

enum NotchDisplayTargeting {
    static func display(
        requested: CGDirectDisplayID?,
        pointer: CGDirectDisplayID?,
        notchDisplays: [CGDirectDisplayID]
    ) -> CGDirectDisplayID? {
        if let requested, requested != 0, notchDisplays.contains(requested) { return requested }
        if let pointer, pointer != 0, notchDisplays.contains(pointer) { return pointer }
        return notchDisplays.first
    }

    static func display(containing point: CGPoint, in frames: [(id: CGDirectDisplayID, frame: CGRect)]) -> CGDirectDisplayID? {
        if let owner = frames.first(where: { owns(point, $0.frame) }) { return owner.id }
        return frames.first { entry in
            point.x >= entry.frame.minX && point.x <= entry.frame.maxX
                && point.y >= entry.frame.minY && point.y <= entry.frame.maxY
        }?.id
    }

    private static func owns(_ point: CGPoint, _ frame: CGRect) -> Bool {
        point.x >= frame.minX && point.x < frame.maxX
            && point.y > frame.minY && point.y <= frame.maxY
    }

    static func screen(containing point: CGPoint, among screens: [NSScreen] = NSScreen.screens) -> NSScreen? {
        guard let id = display(containing: point, in: screens.map { ($0.displayID, $0.frame) }) else { return nil }
        return screens.first { $0.displayID == id }
    }

    @MainActor
    static var pointerDisplayID: CGDirectDisplayID? {
        display(containing: NSEvent.mouseLocation, in: NSScreen.screens.map { ($0.displayID, $0.frame) })
    }
}

enum TrackpadGestureRouting {
    static func route<ID: Hashable>(
        active: [(id: ID, displayID: CGDirectDisplayID?)],
        pointerDisplay: CGDirectDisplayID?
    ) -> ID? {
        if let pointerDisplay, let match = active.last(where: { $0.displayID == pointerDisplay }) {
            return match.id
        }
        return active.last?.id
    }
}