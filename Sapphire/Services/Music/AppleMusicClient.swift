//
//  AppleMusicClient.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-09-22
//

import AppKit
import ScriptingBridge

// MARK: MusicEKnd
@objc public enum MusicEKnd : AEKeyword {
    case trackListing = 0x6b54726b, albumListing = 0x6b416c62, cdInsert = 0x6b434469
}
@objc public enum MusicEnum : AEKeyword {
    case standard = 0x6c777374, detailed = 0x6c776474
}
@objc public enum MusicEPlS : AEKeyword {
    case stopped = 0x6b505353, playing = 0x6b505350, paused = 0x6b505370, fastForwarding = 0x6b505346, rewinding = 0x6b505352
}
@objc public enum MusicERpt : AEKeyword {
    case off = 0x6b52704f, one = 0x6b527031, all = 0x6b416c6c
}
@objc public enum MusicEShM : AEKeyword {
    case songs = 0x6b536853, albums = 0x6b536841, groupings = 0x6b536847
}
@objc public enum MusicEAPD : AEKeyword {
    case computer = 0x6b415043, airPortExpress = 0x6b415058, appleTV = 0x6b415054, airPlayDevice = 0x6b41504f, bluetoothDevice = 0x6b415042, homePod = 0x6b415048, unknown = 0x6b415055
}

@objc public protocol SBObjectProtocol: NSObjectProtocol {
    func get() -> Any!
}
@objc public protocol SBApplicationProtocol: SBObjectProtocol {
    func activate()
    var isRunning: Bool { get }
}

@objc public protocol MusicItem: SBObjectProtocol {
    @objc optional var name: String { get }
    @objc optional var persistentID: String { get }
    @objc optional func reveal()
}
extension SBObject: MusicItem {}

@objc public protocol MusicTrack: MusicItem {
    @objc optional var artist: String { get }
    @objc optional var album: String { get }
    @objc optional var duration: Double { get }
    @objc optional var loved: Bool { get }
    @objc optional func setLoved(_ loved: Bool)
}
extension SBObject: MusicTrack {}

@objc public protocol MusicPlaylist: MusicItem {
    @objc optional func tracks() -> SBElementArray
}
extension SBObject: MusicPlaylist {}

@objc public protocol MusicUserPlaylist: MusicPlaylist {}
extension SBObject: MusicUserPlaylist {}

@objc public protocol MusicAirPlayDevice: MusicItem {
    @objc optional var active: Bool { get }
    @objc optional var available: Bool { get }
    @objc optional var kind: MusicEAPD { get }
    @objc optional var selected: Bool { get }
    @objc optional var soundVolume: Int { get }
    @objc optional func setSelected(_ selected: Bool)
    @objc optional func setSoundVolume(_ soundVolume: Int)
}
extension SBObject: MusicAirPlayDevice {}

@objc public protocol MusicApplication: SBApplicationProtocol {
    @objc optional func AirPlayDevices() -> SBElementArray
    @objc optional func userPlaylists() -> SBElementArray
    @objc optional var currentAirPlayDevices: [MusicAirPlayDevice] { get }
    @objc optional var currentTrack: MusicTrack { get }
    @objc optional var playerState: MusicEPlS { get }
    @objc optional var shuffleEnabled: Bool { get }
    @objc optional var songRepeat: MusicERpt { get }
    @objc optional func setCurrentAirPlayDevices(_ currentAirPlayDevices: [MusicAirPlayDevice]!)
    @objc optional func setShuffleEnabled(_ shuffleEnabled: Bool)
    @objc optional func setSongRepeat(_ songRepeat: MusicERpt)
    @objc optional func play(_: SBObject!)
}
extension SBApplication: MusicApplication {}