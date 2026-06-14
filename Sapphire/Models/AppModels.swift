//
//  AppModels.swift
//  Sapphire
//
//  Created by Shariq Charolia on 205-07-06.
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
    case calendarPlayer
    case sportsPlayer
    case financePlayer

    case musicQueueAndPlaylists
    case musicDevices
    case musicLyrics
    case musicPlaylistDetail(SpotifyPlaylist)

    case nearDrop
    case fileShelf
    case fileShelfLanding
    case fileActionPreview

    case multiAudio
    case multiAudioDeviceAdjust(AudioDevice)
    case multiAudioEQ(AudioDevice)
    case multiAudioAppEQ(bundleID: String, appName: String)
    case musicApiKeysMissing
    case geminiApiKeysMissing
    case musicLoginPrompt
    case timerDetailView
    case agentS
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
        case .calendarPlayer:
            hasher.combine(5)
        case .sportsPlayer:
            hasher.combine(23)
        case .financePlayer:
            hasher.combine(24)
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
        case .multiAudioAppEQ:
            hasher.combine(21)
        case .agentS:
            hasher.combine(22)
        }
    }
}

enum LiveActivityContent: Equatable {
    case none
    case full(view: AnyView, id: AnyHashable, bottomCornerRadius: CGFloat? = nil)
    case standard(data: StandardActivityData, id: AnyHashable)

    static func == (lhs: LiveActivityContent, rhs: LiveActivityContent) -> Bool {
        switch (lhs, rhs) {
        case (.none, .none):
            return true
        case let (.full(_, lhsId, _), .full(_, rhsId, _)):
            return lhsId == rhsId
        case let (.standard(data: lhsData, id: lhsId), .standard(data: rhsData, id: rhsId)):
            return lhsId == rhsId && lhsData == rhsData
        default:
            return false
        }
    }
}

enum MusicBottomContentType: Equatable {
    case none
    case peek(title: String, artist: String?)
    case lyrics(text: String, id: UUID)
}

enum SportsBottomContentType: Equatable {
    case none
    case commentary(text: String, id: String)
}

public struct StatsPayload: Equatable, Hashable {
    public var cpu: CPU_Load?
    public var ram: RAM_Usage?
    public var disk: drive?
    public var gpu: GPU_Info?
    public var sensors: Sensors_List?
    public var battery: Battery_Usage?

    public var systemPower: Double? {
        sensors?.sensors.first(where: { $0.key == "PSTR" })?.value
    }

    public var batteryPower: Double? {
        guard let b = battery else { return nil }
        return abs(b.powerDraw)
    }

    public static func == (lhs: StatsPayload, rhs: StatsPayload) -> Bool {
        lhs.cpu?.totalUsage == rhs.cpu?.totalUsage &&
        lhs.ram?.usage == rhs.ram?.usage &&
        lhs.disk?.uuid == rhs.disk?.uuid && lhs.disk?.activity.read == rhs.disk?.activity.read && lhs.disk?.activity.write == rhs.disk?.activity.write &&
        lhs.gpu?.id == rhs.gpu?.id && lhs.gpu?.utilization == rhs.gpu?.utilization &&
        lhs.battery?.level == rhs.battery?.level &&
        lhs.systemPower == rhs.systemPower &&
        lhs.batteryPower == rhs.batteryPower
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(cpu?.totalUsage)
        hasher.combine(ram?.usage)
        hasher.combine(disk?.uuid)
        hasher.combine(disk?.activity.read)
        hasher.combine(disk?.activity.write)
        hasher.combine(gpu?.id)
        hasher.combine(gpu?.utilization)
        hasher.combine(battery?.level)
        hasher.combine(systemPower)
        hasher.combine(batteryPower)
    }
}

enum StandardActivityData: Equatable {
    case music(bottom: MusicBottomContentType)
    case intelligenceAgent(status: String, current: Int, total: Int)
    case weather(data: ProcessedWeatherData)
    case calendar(event: EKEvent)
    case battery(state: BatteryState, style: BatteryNotificationStyle, timeRemaining: String?, systemState: BatterySystemState)
    case timer
    case desktop(number: Int)
    case focus(mode: FocusModeInfo)
    case fileShelf(count: Int)
    case fileProgress(task: FileTask)
    case bluetooth(device: BluetoothDeviceState)
    case audioSwitch(event: AudioSwitchEvent)
    case geminiLive(payload: GeminiPayload)
    case microphone(payload: MicrophonePayload)
    case nearDrop(payload: NearDropPayload)
    case hud(type: HUDType)
    case reminder(reminder: EKReminder)
    case lockScreen
    case unlocked
    case updateAvailable(version: String)
    case stats(payload: StatsPayload)
    case sports(payload: SportsPayload, bottom: SportsBottomContentType = .none)
    case finance(payload: FinancePayload)

    static func == (lhs: StandardActivityData, rhs: StandardActivityData) -> Bool {
        switch (lhs, rhs) {
        case let (.music(a), .music(b)): return a == b
        case let (.weather(a), .weather(b)): return a == b
        case let (.calendar(a), .calendar(b)): return a == b
        case let (.reminder(a), .reminder(b)): return a == b
        case (.timer, .timer): return true
        case let (.battery(s1, st1, t1, sy1), .battery(s2, st2, t2, sy2)):
                    return s1 == s2 && st1 == st2 && t1 == t2 && sy1 == sy2
        case let (.desktop(a), .desktop(b)): return a == b
        case let (.focus(a), .focus(b)): return a == b
        case let (.fileShelf(a), .fileShelf(b)): return a == b
        case let (.fileProgress(a), .fileProgress(b)): return a == b
        case let (.bluetooth(a), .bluetooth(b)): return a == b
        case let (.audioSwitch(a), .audioSwitch(b)): return a == b
        case let (.geminiLive(a), .geminiLive(b)): return a == b
        case let (.microphone(a), .microphone(b)): return a == b
        case let (.nearDrop(a), .nearDrop(b)): return a == b
        case let (.hud(a), .hud(b)): return a == b
        case (.lockScreen, .lockScreen): return true
        case (.unlocked, .unlocked): return true
        case let (.updateAvailable(a), .updateAvailable(b)): return a == b
        case let (.stats(a), .stats(b)): return a == b
        case let (.sports(a, bottomA), .sports(b, bottomB)): return a == b && bottomA == bottomB
        case let (.finance(a), .finance(b)): return a == b
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

struct MicrophonePayload: Identifiable, Equatable, Hashable {
    let id = UUID()
    var isMuted: Bool
    var audioLevel: Float
}

struct LyricLine: Identifiable, Hashable {
    let id = UUID(); let text: String; let timestamp: TimeInterval; var translatedText: String?
}

struct BatteryState: Equatable, Hashable {
    let level: Int, isCharging: Bool, isPluggedIn: Bool
    var isLow: Bool { level <= 20 && !isCharging }
}

struct SportsPayload: Equatable, Hashable {
    let league: String  // NFL, NBA, MLB, NHL, etc.
    let homeTeam: String
    let awayTeam: String
    let homeScore: Int
    let awayScore: Int
    let status: String  // "Live", "Final", "Scheduled", etc.
    let time: String    // Current time or game time
    let league_logo: String?  // URL or system image name
}

struct ESPNLeagueRoute: Hashable, Codable {
    let sport: String
    let league: String
    let displayName: String
    let shortName: String?

    init(sport: String, league: String, displayName: String, shortName: String? = nil) {
        self.sport = sport
        self.league = league
        self.displayName = displayName
        self.shortName = shortName
    }
}

struct LiveSportsEvent: Equatable {
    let eventId: String
    let homeTeam: String
    let awayTeam: String
    let homeScore: Int
    let awayScore: Int
    let homeScoreDisplay: String
    let awayScoreDisplay: String
    let status: String
    let clock: String
    let homeLogoURL: URL?
    let awayLogoURL: URL?
    let leagueRoute: ESPNLeagueRoute
    let isLive: Bool
    let dataSource: String

    init(
        eventId: String,
        homeTeam: String,
        awayTeam: String,
        homeScore: Int,
        awayScore: Int,
        homeScoreDisplay: String? = nil,
        awayScoreDisplay: String? = nil,
        status: String,
        clock: String,
        homeLogoURL: URL?,
        awayLogoURL: URL?,
        leagueRoute: ESPNLeagueRoute,
        isLive: Bool,
        dataSource: String = "ESPN"
    ) {
        self.eventId = eventId
        self.homeTeam = homeTeam
        self.awayTeam = awayTeam
        self.homeScore = homeScore
        self.awayScore = awayScore
        self.homeScoreDisplay = homeScoreDisplay ?? String(homeScore)
        self.awayScoreDisplay = awayScoreDisplay ?? String(awayScore)
        self.status = status
        self.clock = clock
        self.homeLogoURL = homeLogoURL
        self.awayLogoURL = awayLogoURL
        self.leagueRoute = leagueRoute
        self.isLive = isLive
        self.dataSource = dataSource
    }
}

struct SportsComment: Identifiable, Equatable {
    let id: String
    let text: String
    let clock: String?
    let period: String?
}

struct FinancePayload: Equatable, Hashable {
    let symbol: String  // AAPL, BTC/USD, etc.
    let price: String
    let change: String  // "+1.25" or "-2.30"
    let changePercent: String  // "+1.2%" or "-2.3%"
    let isPositive: Bool
    let name: String    // "Apple Inc." etc.
    let isAfterHours: Bool
    let closingPrice: String?  // Last regular-session close when after hours

    var unitPrice: Double {
        Double(price.replacingOccurrences(of: "$", with: "")) ?? 0
    }

    var changeValue: Double {
        Double(change.replacingOccurrences(of: "+", with: "")) ?? 0
    }
}

struct PortfolioPositionStats: Equatable {
    let invested: String?
    let current: String?
    let totalPL: String?
    let dailyPL: String?
    let openPL: String?
    let holdingPeriod: String?
    let isTotalPLPositive: Bool
    let isDailyPLPositive: Bool
    let isOpenPLPositive: Bool
}

enum SportLayoutKind: CaseIterable {
    case football, basketball, hockey, baseball, soccer
    case cricket, tennis, racing, combat, golf, rugby
    case volleyball, lacrosse, olympics, esports, australianFootball, fieldSports
    case generic

    static func from(league: String) -> SportLayoutKind {
        SportLayoutRegistry.resolve(league: league)
    }
}
