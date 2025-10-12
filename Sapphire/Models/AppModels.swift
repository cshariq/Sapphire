//
//  AppModels.swift
//  Sapphire
//
//  Created by Shariq Charolia on 205-07-06.
//
//
//
//
//
//

import SwiftUI
import NearbyShare
import EventKit

struct LockScreenActivityState: Equatable, Hashable {
    var isUnlocked: Bool
    var isAuthenticating: Bool
    var isCaffeineActive: Bool
    var isFaceIDEnabled: Bool
    var isBluetoothUnlockEnabled: Bool
}

enum NotchWidgetMode: Hashable {
    case defaultWidgets
    case snapZones
    case dragActivated

    case musicPlayer
    case weatherPlayer
    case calendarPlayer // <<< NEW

    case musicQueueAndPlaylists
    case musicDevices
    case musicLyrics
    case musicPlaylistDetail(SpotifyPlaylist) // Assuming SpotifyPlaylist is Hashable

    case nearDrop
    case fileShelf
    case fileShelfLanding
    case fileActionPreview

    case multiAudio
    case multiAudioDeviceAdjust(AudioDevice) // Assuming AudioDevice is Hashable
    case multiAudioEQ(AudioDevice)           // Assuming AudioDevice is Hashable

    case musicApiKeysMissing
    case geminiApiKeysMissing
    case musicLoginPrompt
    case timerDetailView
    func hash(into hasher: inout Hasher) {
        switch self {
        case .defaultWidgets:
            hasher.combine(0)
        case .snapZones:
            hasher.combine(1)
        case .dragActivated:
            hasher.combine(2)
        case .musicPlayer:
            hasher.combine(3)
        case .weatherPlayer:
            hasher.combine(4)
        case .calendarPlayer: // <<< NEW HASH LOGIC
            hasher.combine(5)
        case .musicQueueAndPlaylists:
            hasher.combine(6)
        case .musicDevices:
            hasher.combine(7)
        case .musicLyrics:
            hasher.combine(8)
        case .musicPlaylistDetail(let playlist):
            hasher.combine(9)
            hasher.combine(playlist)
        case .nearDrop:
            hasher.combine(10)
        case .fileShelf:
            hasher.combine(11)
        case .fileShelfLanding:
            hasher.combine(12)
        case .fileActionPreview:
            hasher.combine(13)
        case .multiAudio:
            hasher.combine(14)
        case .multiAudioDeviceAdjust(let device):
            hasher.combine(15)
            hasher.combine(device)
        case .multiAudioEQ(let device):
            hasher.combine(16)
            hasher.combine(device)
        case .musicApiKeysMissing:
            hasher.combine(17)
        case .geminiApiKeysMissing:
            hasher.combine(18)
        case .musicLoginPrompt:
            hasher.combine(19)
        case .timerDetailView:
            hasher.combine(20)
        }
    }
}

enum LiveActivityContent: Equatable {
    case none
    case full(view: AnyView, id: AnyHashable, bottomCornerRadius: CGFloat? = nil)
    case standard(data: StandardActivityData, id: AnyHashable)

    static func == (lhs: LiveActivityContent, rhs: LiveActivityContent) -> Bool {
        switch (lhs, rhs) {
        case (.none, .none): return true
        case let (.full(_, lhsId, _), .full(_, rhsId, _)): return lhsId == rhsId
        case let (.standard(_, lhsId), .standard(_, rhsId)): return lhsId == rhsId
        default: return false
        }
    }
}

enum MusicBottomContentType: Equatable {
    case none
    case peek(title: String, artist: String?)
    case lyrics(text: String, id: UUID)
}

enum StandardActivityData: Equatable {
    case music(bottom: MusicBottomContentType)
    case weather(data: ProcessedWeatherData)
    case calendar(event: EKEvent)
    case battery(state: BatteryState, style: BatteryNotificationStyle, timeRemaining: String?)
    case timer
    case desktop(number: Int)
    case focus(mode: FocusModeInfo)
    case fileShelf(count: Int)
    case fileProgress(task: FileTask)
    case bluetooth(device: BluetoothDeviceState)
    case audioSwitch(event: AudioSwitchEvent)
    case geminiLive(payload: GeminiPayload)
    case nearDrop(payload: NearDropPayload)
    case hud(type: HUDType)
    case reminder(reminder: EKReminder)
    case lockScreen
    case updateAvailable(version: String)

    static func == (lhs: StandardActivityData, rhs: StandardActivityData) -> Bool {
        switch (lhs, rhs) {
        case let (.music(a), .music(b)): return a == b
        case let (.weather(a), .weather(b)): return a == b
        case let (.calendar(a), .calendar(b)): return a == b
        case let (.reminder(a), .reminder(b)): return a == b
        case (.timer, .timer): return true
        case let (.battery(a, b, c), .battery(d, e, f)): return a == d && b == e && c == f
        case let (.desktop(a), .desktop(b)): return a == b
        case let (.focus(a), .focus(b)): return a == b
        case let (.fileShelf(a), .fileShelf(b)): return a == b
        case let (.fileProgress(a), .fileProgress(b)): return a == b
        case let (.bluetooth(a), .bluetooth(b)): return a == b
        case let (.audioSwitch(a), .audioSwitch(b)): return a == b
        case let (.geminiLive(a), .geminiLive(b)): return a == b
        case let (.nearDrop(a), .nearDrop(b)): return a == b
        case let (.hud(a), .hud(b)): return a == b
        case (.lockScreen, .lockScreen): return true
        case let (.updateAvailable(a), .updateAvailable(b)): return a == b
        default: return false
        }
    }
}

enum NearDropTransferState: Equatable, Hashable { case waitingForConsent, inProgress, finished, failed(String) }
struct NearDropPayload: Identifiable, Hashable {
    let id: String, device: RemoteDeviceInfo, transfer: TransferMetadata, destinationURLs: [URL]
    var state: NearDropTransferState = .waitingForConsent; var progress: Double?
    static func == (lhs: NearDropPayload, rhs: NearDropPayload) -> Bool { lhs.id == rhs.id && lhs.state == rhs.state && lhs.progress == rhs.progress }
    func hash(into hasher: inout Hasher) { hasher.combine(id); hasher.combine(state); hasher.combine(progress) }
}

enum GeminiLiveState: Equatable, Hashable { case active }
struct GeminiPayload: Identifiable, Hashable {
    let id = UUID(); var state: GeminiLiveState = .active; var isMicMuted: Bool = true
}

struct LyricLine: Identifiable, Hashable {
    let id = UUID(); let text: String; let timestamp: TimeInterval; var translatedText: String?
}

struct BatteryState: Equatable, Hashable {
    let level: Int, isCharging: Bool, isPluggedIn: Bool
    var isLow: Bool { level <= 20 && !isCharging }
}