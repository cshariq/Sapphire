//
//  MemoryTrimSupport.swift
//  Sapphire
//

import AppKit

enum MemoryTrimSupport {
    @MainActor
    static func trimAfterNotchCollapse(musicManager: MusicManager) {
        musicManager.trimExpandedUIMemory()
        FileImageCache.shared.trimMemoryCache()
        NSImage.trimEdgeColorCache()
    }

    @MainActor
    static func trimAfterUserWindowClose(musicManager: MusicManager) {
        SystemAppFetcher.shared.releaseCachedApps()
        musicManager.trimExpandedUIMemory()
        FileImageCache.shared.trimMemoryCache()
        NSImage.trimEdgeColorCache()
        URLCache.shared.removeAllCachedResponses()
    }

    @MainActor
    static func trimUnderMemoryPressure(musicManager: MusicManager) {
        trimAfterNotchCollapse(musicManager: musicManager)
        FileShelfManager.shared.trimCache()
    }
}
