//
//  GlobalDragManager.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-08-12.
//
//
//
//
//

import AppKit
import Combine

@MainActor
class GlobalDragManager: ObservableObject {
    static let shared = GlobalDragManager()

    @Published private(set) var isDraggingInActivationZone: Bool = false

    private var eventMonitor: Any?
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
        }
    }

    private func handle(event: NSEvent) {
        if event.type == .leftMouseUp {
            if isDraggingInActivationZone {
                isDraggingInActivationZone = false
            }
            dragState.isDraggingFromShelf = false
            return
        }

        if event.type == .leftMouseDragged {
            guard !dragState.isDraggingFromShelf else { return }

            guard !isDraggingInActivationZone else { return }

            let mouseLocation = NSEvent.mouseLocation
            guard let screenFrame = NSScreen.main?.frame else { return }
            let activationRect = CGRect(x: screenFrame.midX - 200, y: screenFrame.maxY - 50, width: 400, height: 50)

            if activationRect.contains(mouseLocation) {
                isDraggingInActivationZone = true
            }
        }
    }
}