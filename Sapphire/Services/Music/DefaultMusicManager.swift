//
//  DefaultMusicManager.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-09-22
//

import Foundation
import MediaRemoteAdapter

class DefaultMusicManager {
    static let shared = DefaultMusicManager()
    private let mediaController = MediaController()

    private init() {}

    func play() { mediaController.play() }
    func pause() { mediaController.pause() }
    func nextTrack() { mediaController.nextTrack() }
    func previousTrack() { mediaController.previousTrack() }

    func seek(to seconds: Double) {
        mediaController.setTime(seconds: seconds)
    }
}