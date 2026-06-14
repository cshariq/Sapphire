//
//  DefaultMusicManager.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-09-22
//
//  System-level media control manager providing access to all native playback controls
//  and multi-source media tracking via NativeMediaController.

import Foundation

@MainActor
class DefaultMusicManager {
    static let shared = DefaultMusicManager()
    private let mediaController = NativeMediaController()

    private init() {}

    // MARK: - Basic Playback Controls
    
    func play() { mediaController.play() }
    func pause() { mediaController.pause() }
    func togglePlayPause() { mediaController.togglePlayPause() }
    func stopPlayback() { mediaController.stopPlayback() }
    
    func nextTrack() { mediaController.nextTrack() }
    func previousTrack() { mediaController.previousTrack() }
    
    // MARK: - Seeking Controls
    
    func seek(to seconds: Double) {
        mediaController.setTime(seconds: seconds)
    }
    
    func beginForwardSeek() { mediaController.beginForwardSeek() }
    func endForwardSeek() { mediaController.endForwardSeek() }
    
    func beginBackwardSeek() { mediaController.beginBackwardSeek() }
    func endBackwardSeek() { mediaController.endBackwardSeek() }
    
    func skipBack15Seconds() { mediaController.skipBack15Seconds() }
    func skipForward15Seconds() { mediaController.skipForward15Seconds() }
    
    // MARK: - Playback Mode Controls
    
    func toggleShuffle() { mediaController.toggleShuffle() }
    func toggleRepeat() { mediaController.toggleRepeat() }
    
    // MARK: - Track Interaction
    
    func likeTrack(trackID: String? = nil, stationID: String? = nil, stationHash: String? = nil) {
        mediaController.likeTrack(trackID: trackID, stationID: stationID, stationHash: stationHash)
    }
}
