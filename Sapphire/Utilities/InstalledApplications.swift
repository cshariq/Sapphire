//
//  InstalledApplications.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-13

import Foundation

enum InstalledApplications {
    static func namesAndBundleIDs() -> [(name: String, bundleID: String)] {
        let dirs = [
            "/Applications",
            "/System/Applications",
            "/System/Applications/Utilities",
            NSHomeDirectory() + "/Applications",
        ]
        var seen = Set<String>()
        var result: [(name: String, bundleID: String)] = []
        let fm = FileManager.default
        for dir in dirs {
            guard let items = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for item in items where item.hasSuffix(".app") {
                let path = dir + "/" + item
                guard let bundle = Bundle(path: path),
                      let bundleID = bundle.bundleIdentifier, !bundleID.isEmpty,
                      !seen.contains(bundleID) else { continue }
                seen.insert(bundleID)
                let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                    ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
                    ?? (item as NSString).deletingPathExtension
                result.append((name, bundleID))
            }
        }
        return result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}