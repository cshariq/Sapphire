//
//  GlobalDragManager.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-08-12.
//

import AppKit
import Combine
import QuartzCore
import os.log

private let dragLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Sapphire", category: "GlobalDragManager")

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
    private let dragThrottleInterval: TimeInterval = 0.05

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
        let zoneWidth: CGFloat = 290
        let zoneHeight: CGFloat = 43

        guard let screenWithCursor = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) else {
            dragLog.info("processDrag: no screen contains mouse=\(mouseLocation.x),\(mouseLocation.y); screens=\(NSScreen.screens.map { "\($0.frame.minX),\($0.frame.minY)-\($0.frame.maxX),\($0.frame.maxY)" })")
            isInsideActivationRect = false
            activationTimer?.invalidate()
            activationTimer = nil
            return
        }

        let notchWindowOnScreen = CursorPosition.visibleNotchWindows.first { window in
            window.screen?.displayID == screenWithCursor.displayID
        }
        let activationRect: CGRect
        if let notchWindow = notchWindowOnScreen {
            let frame = notchWindow.frame
            let width = min(frame.width + 40, frame.width + 120)
            let height = min(56, frame.height * 0.35) + 12
            activationRect = CGRect(
                x: frame.midX - width / 2,
                y: frame.maxY - height,
                width: width,
                height: height
            )
        } else {
            let visibleMaxY = screenWithCursor.visibleFrame.maxY
            activationRect = CGRect(
                x: screenWithCursor.visibleFrame.midX - (zoneWidth / 2),
                y: visibleMaxY - zoneHeight,
                width: zoneWidth,
                height: zoneHeight
            )
        }

        let screen = screenWithCursor
        let screenFrame = screen.frame
        let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? 0
        let menuBarHeight = max(0, screen.frame.height - screen.visibleFrame.height)

        if activationRect.contains(mouseLocation) {
            if !isInsideActivationRect {
                dragLog.info("drag activation zone entered on displayID=\(displayID) mouse=\(mouseLocation.x),\(mouseLocation.y) screenFrame=\(screenFrame.minX),\(screenFrame.minY)-\(screenFrame.maxX),\(screenFrame.maxY) visibleFrame=\(screen.visibleFrame.minX),\(screen.visibleFrame.minY)-\(screen.visibleFrame.maxX),\(screen.visibleFrame.maxY) menuBarHeight=\(menuBarHeight) activationRect=\(activationRect.minX),\(activationRect.minY)-\(activationRect.maxX),\(activationRect.maxY)")
                isInsideActivationRect = true
                activationTimer?.invalidate()
                let delay = max(0.05, SettingsModel.shared.settings.snapActivationDelay)
                activationTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
                    guard let self = self else { return }
                    let currentLocation = NSEvent.mouseLocation

                    if activationRect.contains(currentLocation) && !self.isDraggingInActivationZone {
                        dragLog.info("drag activation zone engaged on displayID=\(displayID)")
                        self.isDraggingInActivationZone = true
                        self.startMouseUpMonitoring()
                    }
                }
            }
            return
        } else {
            dragLog.info("processDrag: mouse NOT in activation rect on displayID=\(displayID) mouse=\(mouseLocation.x),\(mouseLocation.y) activationRect=\(activationRect.minX),\(activationRect.minY)-\(activationRect.maxX),\(activationRect.maxY) menuBarHeight=\(menuBarHeight) visibleFrameMaxY=\(screen.visibleFrame.maxY)")
        }

        isInsideActivationRect = false
        activationTimer?.invalidate()
        activationTimer = nil
    }
}