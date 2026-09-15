//
//  EventTapRunLoop.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-13

import Foundation

final class EventTapRunLoop {
    static let shared = EventTapRunLoop()

    private let condition = NSCondition()
    private var runLoop: CFRunLoop?

    private init() {
        let thread = Thread { [self] in
            let loop = CFRunLoopGetCurrent()

            condition.lock()
            runLoop = loop
            condition.signal()
            condition.unlock()

            var context = CFRunLoopSourceContext()
            context.perform = { _ in }
            if let keepAlive = CFRunLoopSourceCreate(kCFAllocatorDefault, 0, &context) {
                CFRunLoopAddSource(loop, keepAlive, .commonModes)
            }

            while true {
                _ = autoreleasepool {
                    CFRunLoopRunInMode(.defaultMode, 1.0, false)
                }
            }
        }
        thread.name = "com.sapphire.event-tap-runloop"
        thread.qualityOfService = .userInteractive
        thread.stackSize = 512 * 1024
        thread.start()
    }

    private func waitForRunLoop() -> CFRunLoop {
        condition.lock()
        while runLoop == nil { condition.wait() }
        let loop = runLoop!
        condition.unlock()
        return loop
    }

    func add(_ source: CFRunLoopSource) {
        let loop = waitForRunLoop()
        CFRunLoopAddSource(loop, source, .commonModes)
        CFRunLoopWakeUp(loop)
    }

    func remove(_ source: CFRunLoopSource) {
        let loop = waitForRunLoop()
        CFRunLoopRemoveSource(loop, source, .commonModes)
        CFRunLoopWakeUp(loop)
    }
}