//
//  CaptchaPresenting.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-08-18.
//

import SwiftUI
import Foundation

public struct LoginChallengeDetails: Identifiable {
    public let id = UUID()

    public init() {
    }
}

public protocol CaptchaPresenting {
    func loginView(onComplete: @escaping ([[String: Any]]) -> Void, onCancel: @escaping () -> Void) -> AnyView
}