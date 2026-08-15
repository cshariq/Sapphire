//
//  MemoryTrimSupport.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-10

import AppKit
import Darwin

enum MemoryTrimSupport {
    @MainActor
    static func releaseSettingsPaneCaches() {
        SystemAppFetcher.shared.releaseCachedApps()
        AppIconLoader.releaseCache()
    }

    @MainActor
    static func trimAfterNotchCollapse(musicManager: MusicManager) {
//        musicManager.trimExpandedUIMemory()
        Task { await FileImageCache.shared.trimMemoryCache() }
        NSImage.trimEdgeColorCache()
    }

    @MainActor
    static func trimAfterUserWindowClose(musicManager: MusicManager) {
        SettingsModel.shared.flushPendingSave()
        releaseSettingsPaneCaches()
//        musicManager.trimExpandedUIMemory()
        Task { await FileImageCache.shared.trimMemoryCache() }
        NSImage.trimEdgeColorCache()
        URLCache.shared.removeAllCachedResponses()
        NotificationCenter.default.post(name: .sapphireTrimSettingsMemory, object: nil)

        DispatchQueue.global(qos: .utility).async {
            autoreleasepool {
                _ = malloc_zone_pressure_relief(nil, 0)
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            releaseSettingsPaneCaches()
            URLCache.shared.removeAllCachedResponses()
            DispatchQueue.global(qos: .utility).async {
                autoreleasepool {
                    _ = malloc_zone_pressure_relief(nil, 0)
                }
            }
        }
    }

    @MainActor
    static func trimUnderMemoryPressure(musicManager: MusicManager) {
        trimAfterNotchCollapse(musicManager: musicManager)
        FileShelfManager.shared.trimCache()
        releaseSettingsPaneCaches()
        URLCache.shared.removeAllCachedResponses()
    }
}
