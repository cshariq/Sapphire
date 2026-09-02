//
//  LaunchpadGestureManager.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-09-16.
//

import AppKit
import Combine
import SwiftUI

@MainActor
class LaunchpadGestureManager: ObservableObject {
    @Published private(set) var mouseLocation: CGPoint = .zero
    @Published private(set) var dragOffset: CGFloat = 0
    @Published private(set) var isPageSwiping: Bool = false
    @Published private(set) var isOptionKeyPressed: Bool = false

    let clickOccurred = PassthroughSubject<CGPoint, Never>()
    let longPressOccurred = PassthroughSubject<CGPoint, Never>()
    let dragEnded = PassthroughSubject<CGPoint, Never>()

    private var eventMonitor: Any?
    private var mouseDownInfo: (location: CGPoint, timestamp: Date)?
    private var longPressTimer: Timer?
    private(set) var isDraggingItem: Bool = false

    private var lastDragPosition: CGPoint = .zero
    private var dragStartTime: Date?

    private let dragActivationThreshold: CGFloat = 5.0

    init() {}

    deinit {
        longPressTimer?.invalidate()
    }

    func resetDragOffset() {
        self.dragOffset = 0
    }

    func startMonitoring(for window: NSWindow) {
        guard eventMonitor == nil else { return }
        print("[GestureManager] Starting event monitoring.")
//        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown, .leftMouseUp, .leftMouseDragged, .scrollWheel, .flagsChanged]) { [weak self] event in
//            guard let self = self else { return event }
//            return self.handle(event: event, in: window) ? nil : event
//        }
    }

    func stopMonitoring() {
        guard eventMonitor != nil else { return }
        print("[GestureManager] Stopping event monitoring.")
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        dragOffset = 0
        isPageSwiping = false
        longPressTimer?.invalidate()
        mouseDownInfo = nil
        isDraggingItem = false
        dragEnded.send(mouseLocation)
    }

    private func activateDragMode(location: CGPoint) {
        guard !isDraggingItem else { return }
        isDraggingItem = true
        longPressOccurred.send(location)
        mouseDownInfo = nil
    }

    private func handle(event: NSEvent, in window: NSWindow) -> Bool {
        let screenFrame = NSScreen.main?.frame ?? .zero
        var locationInGlobal = event.locationInWindow
        locationInGlobal.y = screenFrame.height - locationInGlobal.y
        self.mouseLocation = locationInGlobal

        if event.type == .flagsChanged {
            self.isOptionKeyPressed = event.modifierFlags.contains(.option)
            return true
        }

        switch event.type {
        case .scrollWheel:
            if event.phase == .began { isPageSwiping = true; longPressTimer?.invalidate(); mouseDownInfo = nil }
            if isPageSwiping { self.dragOffset += event.scrollingDeltaX * 1.5 }
            if event.phase == .ended || event.phase == .cancelled { isPageSwiping = false }
            return true

        case .leftMouseDown:
            mouseDownInfo = (location: locationInGlobal, timestamp: Date())
            dragStartTime = Date()
            lastDragPosition = locationInGlobal
            longPressTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: false) { [weak self] _ in
                guard let self = self, let info = self.mouseDownInfo else { return }
                self.activateDragMode(location: info.location)
            }
            return true

        case .leftMouseUp:
            longPressTimer?.invalidate()
            if let info = mouseDownInfo, Date().timeIntervalSince(info.timestamp) < 0.35 {
                clickOccurred.send(locationInGlobal)
            }
            if isDraggingItem {
                dragEnded.send(locationInGlobal)
                isDraggingItem = false
            }
            mouseDownInfo = nil
            dragStartTime = nil
            return true

        case .leftMouseDragged:
            if isDraggingItem {
                lastDragPosition = locationInGlobal
            } else if let info = mouseDownInfo {
                let distance = locationInGlobal.distanceTo(info.location)
                if distance > dragActivationThreshold {
                    activateDragMode(location: info.location)
                }
            }
            return isDraggingItem

        default:
            return false
        }
    }
}
