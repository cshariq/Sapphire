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
        Task { await FileImageCache.shared.trimMemoryCache() }
        NSImage.trimEdgeColorCache()
    }

    @MainActor
    static func trimAfterUserWindowClose(musicManager: MusicManager) {
        SettingsModel.shared.flushPendingSave()
        releaseSettingsPaneCaches()
        Task { await FileImageCache.shared.trimMemoryCache() }
        NSImage.trimEdgeColorCache()
        URLCache.shared.removeAllCachedResponses()
        NotificationCenter.default.post(name: .sapphireTrimSettingsMemory, object: nil)

        DispatchQueue.global(qos: .utility).async {
            autoreleasepool {
                SapphireMemoryFlushAllMallocZones()
                SapphireMemoryDrainAutoreleasePools()
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            releaseSettingsPaneCaches()
            URLCache.shared.removeAllCachedResponses()
            DispatchQueue.global(qos: .utility).async {
                autoreleasepool {
                    SapphireMemoryFlushAllMallocZones()
                    SapphireMemoryDrainAutoreleasePools()
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