//
//  InputMonitoringAccess.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-12.
//

import Foundation
import CoreGraphics

enum InputMonitoringAccess {
    static var isGranted: Bool {
        CGPreflightListenEventAccess()
    }

    @discardableResult
    static func request() -> Bool {
        CGRequestListenEventAccess()
    }
}