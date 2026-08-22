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
        preferredChannel(from: settings)
    }

    static func canChangePreferredChannel() -> Bool {
        true
    }

    static func shouldOfferStableDowngrade(for settings: Settings) -> Bool {
        runningBuildChannel == .beta && preferredChannel(from: settings) == .stable
    }

    static func reconcileStoredPreference(_ settings: inout Settings) {
        _ = settings
    }
}