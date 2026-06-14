//
//  ReleaseChannelPolicy.swift
//  Sapphire
//

import Foundation

enum ReleaseChannelPolicy {
    /// Channel implied by the running app binary.
    static var runningBuildChannel: ReleaseChannel {
        BetaEntitlementRuntime.isBetaBuild ? .beta : .stable
    }

    /// Stored user preference, clamped by subscription entitlement.
    static func preferredChannel(from settings: Settings) -> ReleaseChannel {
        guard SubscriptionAccess.hasAccess(to: .betaSoftwareUpdates) else {
            return .stable
        }
        return settings.releaseChannel
    }

    /// What the settings UI and update checks should treat as active.
    /// Beta binaries always report the beta channel; stable binaries follow preference.
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
