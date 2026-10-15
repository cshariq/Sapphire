//
//  NearbyTransferDisplayState.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-07-02.
//

import Foundation

enum NearbyTransferDisplayState: Equatable {
    case waitingForConsent
    case inProgress
    case finished
    case failed(String)
}

struct NearbyTransferDisplayPayload: Identifiable, Equatable {
    let id: String
    let deviceName: String
    let fileInfo: String
    let pinCode: String?
    var state: NearbyTransferDisplayState = .waitingForConsent
}