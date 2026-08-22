//
//  MediaKeyStatus.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-21

import Foundation

@Observable
@MainActor
final class MediaKeyStatus {
    var isOffline: Bool = false
    var suppressionDegraded: Bool = false
}