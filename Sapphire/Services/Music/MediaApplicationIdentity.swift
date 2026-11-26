//
//  MediaApplicationIdentity.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-13

enum MediaApplicationIdentity {
    static func canonicalBundleID(_ bundleID: String?) -> String? {
        guard let bundleID else { return nil }
        switch bundleID {
        case "com.apple.WebKit.GPU", "com.apple.WebKit.WebContent":
            return "com.apple.Safari"
        case let id where id == AppleMusicPlaybackIdentity.hostBundleID && AppleMusicPlaybackIdentity.isInAppPlaybackActive:
            return "com.apple.Music"
        default:
            // Chromium browsers and Electron apps (Qobuz, ...) play from "<app id>.helper[.Type]" processes,
            // which aren't listed as running apps.
            let parts = bundleID.split(separator: ".")
            if let helper = parts.lastIndex(where: { $0.caseInsensitiveCompare("helper") == .orderedSame }),
               helper > 1, helper >= parts.count - 2 {
                return parts[..<helper].joined(separator: ".")
            }
            return bundleID
        }
    }
}