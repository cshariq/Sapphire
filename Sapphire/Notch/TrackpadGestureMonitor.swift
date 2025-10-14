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

class TrackpadGestureHandler {
    static let shared = TrackpadGestureHandler()

    private var scrollEventMonitor: Any?
    private var rightClickMonitor: Any?
    private var magnifyEventMonitor: Any?
    private var isMonitoring = false
    private var hasProcessedCurrentGesture = false
    private var lastGestureTime: Date = .distantPast
    private var gestureDebounceInterval: TimeInterval = 0.7
    private var monitoringStartTime: Date = .distantPast
    private var initialStabilizationPeriod: TimeInterval = 0.3

    var onSwipe: ((CGFloat, CGFloat) -> Void)?
    var onTwoFingerTap: (() -> Void)?
    var onPinch: ((CGFloat) -> Void)?

    private init() {}

    func startMonitoring() {
        guard !isMonitoring else { return }

        monitoringStartTime = Date()
        hasProcessedCurrentGesture = false
        isMonitoring = true

        scrollEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel]) { event in
            if event.type == .scrollWheel && !event.modifierFlags.contains(.command) &&
               !event.modifierFlags.contains(.option) && !event.modifierFlags.contains(.control) {

                let now = Date()
                if now.timeIntervalSince(self.monitoringStartTime) < self.initialStabilizationPeriod {
                    return event
                }

                if event.phase == .began || event.momentumPhase == .began {
                    self.hasProcessedCurrentGesture = false
                }

                if !self.hasProcessedCurrentGesture &&
                   now.timeIntervalSince(self.lastGestureTime) > self.gestureDebounceInterval {

                    if abs(event.scrollingDeltaX) > 10 || abs(event.scrollingDeltaY) > 10 {
                        self.hasProcessedCurrentGesture = true
                        self.lastGestureTime = now

                        DispatchQueue.main.async {
                            self.onSwipe?(event.scrollingDeltaX, event.scrollingDeltaY)
                        }

                        return nil
                    }
                }

                if event.phase == .ended || event.phase == .cancelled ||
                   event.momentumPhase == .ended || event.momentumPhase == .cancelled {
                    self.hasProcessedCurrentGesture = false
                }
            }
            return event
        }

        rightClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown]) { event in
            let now = Date()
            if now.timeIntervalSince(self.monitoringStartTime) < self.initialStabilizationPeriod {
                return event
            }

            if event.clickCount == 1 && !event.modifierFlags.contains(.control) {
                if now.timeIntervalSince(self.lastGestureTime) > self.gestureDebounceInterval {
                    self.lastGestureTime = now

                    DispatchQueue.main.async {
                        self.onTwoFingerTap?()
                    }

                    return nil
                }
            }
            return event
        }

        magnifyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.magnify]) { event in
            let now = Date()
            if now.timeIntervalSince(self.monitoringStartTime) < self.initialStabilizationPeriod {
                return event
            }

            if event.phase == .began {
                self.hasProcessedCurrentGesture = false
            }

            if !self.hasProcessedCurrentGesture && now.timeIntervalSince(self.lastGestureTime) > self.gestureDebounceInterval {

                if abs(event.magnification) > 0.1 {
                    self.hasProcessedCurrentGesture = true
                    self.lastGestureTime = now

                    DispatchQueue.main.async {
                        self.onPinch?(event.magnification)
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