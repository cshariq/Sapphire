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
        eventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDown, .leftMouseUp, .leftMouseDragged, .scrollWheel, .flagsChanged]
        ) { [weak self, weak window] event in
            guard let self, let window else { return event }
            _ = self.handle(event: event, in: window)
            // Observation must not consume the event. Search, folder contents,
            // buttons, and native SwiftUI gestures still need the same mouse
            // event after Launchpad updates its custom paging/drag state.
            return event
        }
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
        longPressTimer = nil
        mouseDownInfo = nil
        isDraggingItem = false
        dragEnded.send(mouseLocation)
    }

    private func activateDragMode(location: CGPoint) {
        guard !isDraggingItem else { return }
        isDraggingItem = true
        longPressTimer = nil
        longPressOccurred.send(location)
        mouseDownInfo = nil
    }

    func cancelItemDrag() {
        longPressTimer?.invalidate()
        longPressTimer = nil
        mouseDownInfo = nil
        isDraggingItem = false
    }

    private func handle(event: NSEvent, in window: NSWindow) -> Bool {
        let locationInWindow: CGPoint
        if let contentView = window.contentView {
            let converted = contentView.convert(event.locationInWindow, from: nil)
            locationInWindow = contentView.isFlipped
                ? converted
                : CGPoint(x: converted.x, y: contentView.bounds.height - converted.y)
        } else {
            locationInWindow = event.locationInWindow
        }
        if mouseLocation != locationInWindow {
            mouseLocation = locationInWindow
        }

        if event.type == .flagsChanged {
            let optionIsPressed = event.modifierFlags.contains(.option)
            if isOptionKeyPressed != optionIsPressed {
                isOptionKeyPressed = optionIsPressed
            }
            return true
        }

        switch event.type {
        case .scrollWheel:
            if event.phase == .began { isPageSwiping = true; longPressTimer?.invalidate(); mouseDownInfo = nil }
            if isPageSwiping { self.dragOffset += event.scrollingDeltaX * 1.5 }
            if event.phase == .ended || event.phase == .cancelled { isPageSwiping = false }
            return true

        case .leftMouseDown:
            mouseDownInfo = (location: locationInWindow, timestamp: Date())
            longPressTimer?.invalidate()
            let timer = Timer(timeInterval: 0.35, repeats: false) { [weak self] _ in
                guard let self = self, let info = self.mouseDownInfo else { return }
                self.activateDragMode(location: info.location)
            }
            timer.tolerance = 0.03
            longPressTimer = timer
            RunLoop.main.add(timer, forMode: .common)
            return true

        case .leftMouseUp:
            longPressTimer?.invalidate()
            longPressTimer = nil
            if let info = mouseDownInfo, Date().timeIntervalSince(info.timestamp) < 0.35 {
                clickOccurred.send(locationInWindow)
            }
            if isDraggingItem {
                dragEnded.send(locationInWindow)
                isDraggingItem = false
            }
            mouseDownInfo = nil
            return true

        case .leftMouseDragged:
            if !isDraggingItem, let info = mouseDownInfo {
                let distance = locationInWindow.distanceTo(info.location)
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
