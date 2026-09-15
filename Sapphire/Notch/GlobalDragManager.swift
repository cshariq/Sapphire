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

    private var activationTimer: Timer?
    private var isInsideActivationRect: Bool = false
    @MainActor private let dragState = DragStateManager.shared

    private var monitoringOwnerCount = 0

    var isActivationPending: Bool {
        isInsideActivationRect && !isDraggingInActivationZone
    }

    init() {}

    func startMonitoring() {
        monitoringOwnerCount += 1
    }

    func stopMonitoring() {
        monitoringOwnerCount = max(0, monitoringOwnerCount - 1)
        guard monitoringOwnerCount == 0 else { return }
        endDrag()
    }

    func updateDrag(isInsideActivationZone: Bool) {
        guard monitoringOwnerCount > 0 else { return }
        guard !dragState.isDraggingFromShelf else {
            cancelActivation()
            return
        }
        guard !isDraggingInActivationZone else { return }

        if !isInsideActivationZone {
            cancelPendingActivation()
            return
        }
        guard !isInsideActivationRect else { return }

        isInsideActivationRect = true
        let delay = max(0.05, SettingsModel.shared.settings.snapActivationDelay)
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self,
                      self.isInsideActivationRect,
                      NSEvent.pressedMouseButtons & 1 != 0,
                      !self.dragState.isDraggingFromShelf else { return }
                self.activationTimer = nil
                self.isDraggingInActivationZone = true
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        activationTimer = timer
    }

    func cancelActivation() {
        cancelPendingActivation()
        if isDraggingInActivationZone {
            isDraggingInActivationZone = false
        }
    }

    func endDrag() {
        if isDraggingInActivationZone {
            isDraggingInActivationZone = false
        }
        dragState.isDraggingFromShelf = false
        cancelPendingActivation()
    }

    private func cancelPendingActivation() {
        isInsideActivationRect = false
        activationTimer?.invalidate()
        activationTimer = nil
    }
}