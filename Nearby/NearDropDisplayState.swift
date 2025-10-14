//
//  NearDropDisplayState.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-07-02.
//

import Foundation

enum NearDropDisplayState: Equatable {
    case waitingForConsent
    case inProgress
    case finished
    case failed(String)
}

struct NearDropDisplayPayload: Identifiable, Equatable {
    let id: String
    let deviceName: String
    let fileInfo: String
    let pinCode: String?
    var state: NearDropDisplayState = .waitingForConsent
}