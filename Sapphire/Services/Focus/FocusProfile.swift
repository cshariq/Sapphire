//
//  FocusProfile.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-21

import Foundation
import SwiftUI

// MARK: - Social filters

struct FocusSocialFilters: Codable, Equatable, Hashable {
    var blockInstagramReels: Bool = false
    var blockInstagramExplore: Bool = false
    var instagramFollowingOnly: Bool = false
    var blockYouTubeShorts: Bool = false
    var blockFacebookReels: Bool = false
    var blockTikTok: Bool = false
    var blockSnapchatSpotlight: Bool = false
    var blockRedditVideo: Bool = false
    var blockXExplore: Bool = false
    var blockShortFormWeb: Bool = false

    var isEmpty: Bool {
        !(blockInstagramReels || blockInstagramExplore || instagramFollowingOnly
            || blockYouTubeShorts || blockFacebookReels || blockTikTok
            || blockSnapchatSpotlight || blockRedditVideo || blockXExplore
            || blockShortFormWeb)
    }

    func resolvedWebsiteDomains() -> Set<String> {
        var domains = Set<String>()
        if blockInstagramReels || blockInstagramExplore || instagramFollowingOnly || blockShortFormWeb {
            domains.insert("instagram.com")
        }
        if blockYouTubeShorts || blockShortFormWeb {
            domains.formUnion(["youtube.com", "youtu.be", "m.youtube.com"])
        }
        if blockFacebookReels || blockShortFormWeb {
            domains.formUnion(["facebook.com", "fb.com", "fb.watch", "m.facebook.com"])
        }
        if blockTikTok || blockShortFormWeb {
            domains.formUnion(["tiktok.com", "vm.tiktok.com"])
        }
        if blockSnapchatSpotlight {
            domains.insert("snapchat.com")
        }
        if blockRedditVideo || blockShortFormWeb {
            domains.formUnion(["reddit.com", "redd.it"])
        }
        if blockXExplore || blockShortFormWeb {
            domains.formUnion(["x.com", "twitter.com", "t.co"])
        }
        return domains
    }

    func pathBlockPatterns() -> [String] {
        var paths: [String] = []
        if blockInstagramReels || instagramFollowingOnly { paths += ["/reels", "/reel/"] }
        if blockInstagramExplore || instagramFollowingOnly { paths += ["/explore"] }
        if blockYouTubeShorts { paths += ["/shorts"] }
        if blockFacebookReels { paths += ["/reel/", "/reels", "/watch/"] }
        if blockSnapchatSpotlight { paths += ["/spotlight"] }
        if blockRedditVideo { paths += ["/r/", "/video/"] }
        if blockXExplore { paths += ["/explore", "/i/communities"] }
        return paths
    }

    func resolvedPhonePackages() -> Set<String> {
        var pkgs = Set<String>()
        if blockTikTok {
            pkgs.formUnion([
                "com.zhiliaoapp.musically",
                "com.ss.android.ugc.trill",
            ])
        }
        if blockInstagramReels || blockInstagramExplore || instagramFollowingOnly {
            if blockInstagramReels && blockInstagramExplore {
                pkgs.insert("com.instagram.android")
            }
        }
        if blockYouTubeShorts && blockShortFormWeb {
            pkgs.insert("com.google.android.youtube")
        }
        if blockFacebookReels && blockShortFormWeb {
            pkgs.formUnion(["com.facebook.katana", "com.facebook.lite"])
        }
        if blockSnapchatSpotlight {
            pkgs.insert("com.snapchat.android")
        }
        return pkgs
    }
}

// MARK: - Triggers

struct FocusProfileTriggers: Codable, Equatable, Hashable {
    var macOSFocusModeIDs: [String] = []
    var macOSFocusModeNames: [String] = []
    var androidDND: Bool = false
    var syncPeerSystemFocus: Bool = false

    var hasAny: Bool {
        !macOSFocusModeIDs.isEmpty || !macOSFocusModeNames.isEmpty || androidDND || syncPeerSystemFocus
    }
}

// MARK: - Profile

struct FocusProfile: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    var name: String
    var symbolName: String
    var accentHex: String

    var durationSeconds: Int
    var breakEnabled: Bool
    var breakSeconds: Int
    var intensity: FocusIntensity
    var blockingMode: FocusBlockingMode
    var blockingEnabled: Bool
    var blockDuringBreaks: Bool

    var blockedMacApps: Set<String>
    var allowedMacApps: Set<String>
    var blockedWebsites: Set<String>
    var blockedPhoneApps: Set<String>

    var social: FocusSocialFilters
    var triggers: FocusProfileTriggers

    var syncActivation: Bool
    var syncSettings: Bool

    var updatedAt: Date

    static func makeDefault(name: String = String(localized: "Deep Work"), symbol: String = "moon.fill") -> FocusProfile {
        FocusProfile(
            id: UUID(),
            name: name,
            symbolName: symbol,
            accentHex: "7C5CFF",
            durationSeconds: 90 * 60,
            breakEnabled: true,
            breakSeconds: 10 * 60,
            intensity: .standard,
            blockingMode: .blocklist,
            blockingEnabled: true,
            blockDuringBreaks: false,
            blockedMacApps: [],
            allowedMacApps: [],
            blockedWebsites: [],
            blockedPhoneApps: [],
            social: FocusSocialFilters(),
            triggers: FocusProfileTriggers(),
            syncActivation: true,
            syncSettings: false,
            updatedAt: Date()
        )
    }

    static func presets() -> [FocusProfile] {
        var deep = makeDefault(name: String(localized: "Deep Work"), symbol: "brain.head.profile")
        deep.intensity = .strict
        deep.social.blockYouTubeShorts = true
        deep.social.blockInstagramReels = true
        deep.social.blockTikTok = true
        deep.social.blockShortFormWeb = true

        var study = makeDefault(name: String(localized: "Study"), symbol: "book.fill")
        study.durationSeconds = 50 * 60
        study.breakSeconds = 10 * 60
        study.intensity = .standard
        study.social.blockYouTubeShorts = true
        study.social.blockInstagramReels = true

        var windDown = makeDefault(name: String(localized: "Wind Down"), symbol: "bed.double.fill")
        windDown.durationSeconds = 30 * 60
        windDown.intensity = .gentle
        windDown.breakEnabled = false
        windDown.social.blockInstagramReels = true
        windDown.social.blockTikTok = true
        windDown.social.instagramFollowingOnly = true

        var meeting = makeDefault(name: String(localized: "Meetings"), symbol: "person.3.fill")
        meeting.durationSeconds = 60 * 60
        meeting.intensity = .minimal
        meeting.blockingEnabled = false

        return [deep, study, windDown, meeting]
    }

    func effectiveWebsites() -> Set<String> {
        blockedWebsites.union(social.resolvedWebsiteDomains())
    }

    func effectivePhoneApps() -> Set<String> {
        blockedPhoneApps.union(social.resolvedPhonePackages())
    }

    var accentColor: Color {
        Color(focusHex: accentHex) ?? Color.purple
    }
}

private extension Color {
    init?(focusHex: String) {
        var s = focusHex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let value = UInt64(s, radix: 16) else { return nil }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}