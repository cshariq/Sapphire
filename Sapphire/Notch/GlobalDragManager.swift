//
//  GlobalDragManager.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-08-12.
//

import AppKit
import Combine
import QuartzCore

@MainActor
class GlobalDragManager: ObservableObject {
    static let shared = GlobalDragManager()

    @Published private(set) var isDraggingInActivationZone: Bool = false

    private var dragMonitor: Any?
    private var upMonitor: Any?
    private var activationTimer: Timer?
    private var isInsideActivationRect: Bool = false
    @MainActor private let dragState = DragStateManager.shared

    private var lastDragProcessTime: TimeInterval = 0
    private let dragThrottleInterval: TimeInterval = 0.032

    private init() {}

    func startMonitoring() {
        guard dragMonitor == nil else { return }

        dragMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged) { [weak self] event in
            self?.handleDrag(event: event)
        }
    }

    func stopMonitoring() {
        if let monitor = dragMonitor {
            NSEvent.removeMonitor(monitor)
            dragMonitor = nil
        }
        stopMouseUpMonitoring()

        activationTimer?.invalidate()
        activationTimer = nil
        isInsideActivationRect = false
    }

    private func startMouseUpMonitoring() {
        guard upMonitor == nil else { return }

        upMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in
            DispatchQueue.main.async {
                self?.endDrag()
            }
        }
    }

    private func stopMouseUpMonitoring() {
        if let monitor = upMonitor {
            NSEvent.removeMonitor(monitor)
            upMonitor = nil
        }
    }

    func endDrag() {
        if isDraggingInActivationZone {
            isDraggingInActivationZone = false
        }

        stopMouseUpMonitoring()

        dragState.isDraggingFromShelf = false
        activationTimer?.invalidate()
        activationTimer = nil
        isInsideActivationRect = false
    }

    private func handleDrag(event: NSEvent) {
        let now = CACurrentMediaTime()
        if now - lastDragProcessTime < dragThrottleInterval {
            return
        }
        lastDragProcessTime = now

        DispatchQueue.main.async {
            self.processDrag()
        }
    }

    private func processDrag() {
        guard !dragState.isDraggingFromShelf else { return }
        guard !isDraggingInActivationZone else { return }

        let mouseLocation = NSEvent.mouseLocation
        guard let screenFrame = NSScreen.main?.frame else { return }
        let zoneWidth: CGFloat = 290
        let zoneHeight: CGFloat = 43
        let activationRect = CGRect(
            x: screenFrame.midX - (zoneWidth / 2),
            y: screenFrame.maxY - zoneHeight,
            width: zoneWidth,
            height: zoneHeight
        )

        if activationRect.contains(mouseLocation) {
            if !isInsideActivationRect {
                isInsideActivationRect = true
                activationTimer?.invalidate()
                activationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: false) { [weak self] _ in
                    guard let self = self else { return }
                    let currentLocation = NSEvent.mouseLocation

                    if activationRect.contains(currentLocation) && !self.isDraggingInActivationZone {
                        self.isDraggingInActivationZone = true
                        self.startMouseUpMonitoring()
                    }
                }
            }
        } else {
            isInsideActivationRect = false
            activationTimer?.invalidate()
            activationTimer = nil
        }
    }
}