//
//  SpotifyLoginChallenge.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-08-18.
//

import Foundation

/// Posted by SpotifyPrivateAPIManager when a web-based login sheet should appear.
struct LoginChallengeDetails: Identifiable {
    let id = UUID()
}
