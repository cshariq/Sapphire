//
//  ReleaseChannelPolicy.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-10

import Foundation

enum ReleaseChannelPolicy {
    static var runningBuildChannel: ReleaseChannel {
        BetaEntitlementRuntime.isBetaBuild ? .beta : .stable
    }

    static func preferredChannel(from settings: Settings) -> ReleaseChannel {
        guard SubscriptionAccess.hasAccess(to: .betaSoftwareUpdates) else {
            return .stable
        }
        return settings.releaseChannel
    }

    static func displayedChannel(for settings: Settings) -> ReleaseChannel {
        if runningBuildChannel == .beta {
            return .beta
        }
        return preferredChannel(from: settings)
    }

    static func canChangePreferredChannel() -> Bool {
        runningBuildChannel != .beta
    }

    static func reconcileStoredPreference(_ settings: inout Settings) {
        if !SubscriptionAccess.hasAccess(to: .betaSoftwareUpdates) {
            settings.releaseChannel = .stable
        }
    }
}