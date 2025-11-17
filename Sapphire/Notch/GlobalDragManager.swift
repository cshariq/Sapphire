//
//  GlobalDragManager.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-08-12.
//

import AppKit
import Combine

@MainActor
class GlobalDragManager: ObservableObject {
    static let shared = GlobalDragManager()

    @Published private(set) var isDraggingInActivationZone: Bool = false

    private var eventMonitor: Any?
    private var activationTimer: Timer?
    private var isInsideActivationRect: Bool = false
    @MainActor private let dragState = DragStateManager.shared

    private init() {}

    func startMonitoring() {
        guard eventMonitor == nil else { return }

        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged, .leftMouseUp]) { [weak self] event in
            DispatchQueue.main.async {
                self?.handle(event: event)
            }
        }
    }

    func stopMonitoring() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
            activationTimer?.invalidate()
            activationTimer = nil
            isInsideActivationRect = false
        }
    }

    func endDrag() {
        if isDraggingInActivationZone {
            isDraggingInActivationZone = false
        }
        dragState.isDraggingFromShelf = false
        activationTimer?.invalidate()
        activationTimer = nil
        isInsideActivationRect = false
    }

    private func handle(event: NSEvent) {
        if event.type == .leftMouseUp {
            endDrag()
            return
        }

        if event.type == .leftMouseDragged {
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
                        }
                    }
                }
            } else {
                isInsideActivationRect = false
                activationTimer?.invalidate()
                activationTimer = nil
            }
            return
        }
    }
}