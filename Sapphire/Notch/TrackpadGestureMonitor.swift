//
//  TrackpadGestureMonitor.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-08-20.
//

import Foundation
import AppKit
import SwiftUI
import Combine
import QuartzCore

class TrackpadGestureHandler {
    static let shared = TrackpadGestureHandler()

    private var scrollEventMonitor: Any?
    private var rightClickMonitor: Any?
    private var magnifyEventMonitor: Any?
    private var isMonitoring = false
    private var hasProcessedCurrentGesture = false

    private var lastGestureTime: TimeInterval = 0
    private var monitoringStartTime: TimeInterval = 0

    private let gestureDebounceInterval: TimeInterval = 0.7
    private let initialStabilizationPeriod: TimeInterval = 0.3

    var onSwipe: ((CGFloat, CGFloat) -> Void)?
    var onTwoFingerTap: (() -> Void)?
    var onPinch: ((CGFloat) -> Void)?

    private init() {}

    func startMonitoring() {
        guard !isMonitoring else { return }

        monitoringStartTime = CACurrentMediaTime()
        hasProcessedCurrentGesture = false
        isMonitoring = true

        scrollEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel]) { [weak self] event in
            guard let self = self else { return event }

            if event.type != .scrollWheel ||
               event.modifierFlags.contains(.command) ||
               event.modifierFlags.contains(.option) ||
               event.modifierFlags.contains(.control) {
                return event
            }

            let now = CACurrentMediaTime()

            if now - self.monitoringStartTime < self.initialStabilizationPeriod {
                return event
            }

            if event.phase == .began || event.momentumPhase == .began {
                self.hasProcessedCurrentGesture = false
            }

            if !self.hasProcessedCurrentGesture &&
               (now - self.lastGestureTime > self.gestureDebounceInterval) {

                if abs(event.scrollingDeltaX) > 10 || abs(event.scrollingDeltaY) > 10 {
                    self.hasProcessedCurrentGesture = true
                    self.lastGestureTime = now

                    let dx = event.scrollingDeltaX
                    let dy = event.scrollingDeltaY

                    DispatchQueue.main.async {
                        self.onSwipe?(dx, dy)
                    }

                    return nil
                }
            }

            if event.phase == .ended || event.phase == .cancelled ||
               event.momentumPhase == .ended || event.momentumPhase == .cancelled {
                self.hasProcessedCurrentGesture = false
            }

            return event
        }

        rightClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown]) { [weak self] event in
            guard let self = self else { return event }

            let now = CACurrentMediaTime()
            if now - self.monitoringStartTime < self.initialStabilizationPeriod {
                return event
            }

            if event.clickCount == 1 && !event.modifierFlags.contains(.control) {
                if now - self.lastGestureTime > self.gestureDebounceInterval {
                    self.lastGestureTime = now

                    DispatchQueue.main.async {
                        self.onTwoFingerTap?()
                    }

                    return nil
                }
            }
            return event
        }

        magnifyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.magnify]) { [weak self] event in
            guard let self = self else { return event }

            let now = CACurrentMediaTime()
            if now - self.monitoringStartTime < self.initialStabilizationPeriod {
                return event
            }

            if event.phase == .began {
                self.hasProcessedCurrentGesture = false
            }

            if !self.hasProcessedCurrentGesture && (now - self.lastGestureTime > self.gestureDebounceInterval) {

                if abs(event.magnification) > 0.1 {
                    self.hasProcessedCurrentGesture = true
                    self.lastGestureTime = now

                    let mag = event.magnification
                    DispatchQueue.main.async {
                        self.onPinch?(mag)
                    }

                    return nil
                }
            }

            if event.phase == .ended || event.phase == .cancelled {
                self.hasProcessedCurrentGesture = false
            }

            return event
        }
    }

    func stopMonitoring() {
        if let scrollMonitor = scrollEventMonitor {
            NSEvent.removeMonitor(scrollMonitor)
            scrollEventMonitor = nil
        }

        if let tapMonitor = rightClickMonitor {
            NSEvent.removeMonitor(tapMonitor)
            rightClickMonitor = nil
        }

        if let magnifyMonitor = magnifyEventMonitor {
            NSEvent.removeMonitor(magnifyMonitor)
            magnifyEventMonitor = nil
        }

        isMonitoring = false
        hasProcessedCurrentGesture = false
    }
}