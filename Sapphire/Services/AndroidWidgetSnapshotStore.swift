//
//  AndroidWidgetSnapshotStore.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-15

import Foundation

struct AndroidWidgetProviderRecord: Codable, Hashable, Identifiable, Sendable {
    let provider: String
    let label: String
    let minWidth: Int
    let minHeight: Int

    var id: String { provider }
}

struct AndroidWidgetSnapshotRecord: Codable, Hashable, Identifiable, Sendable {
    let instanceID: Int
    let provider: String
    let label: String
    let width: Int
    let height: Int
    let imageFilename: String
    let updatedAt: Date

    var id: String { String(instanceID) }
}

struct AndroidWidgetCatalog: Codable, Sendable {
    var providers: [AndroidWidgetProviderRecord] = []
    var snapshots: [AndroidWidgetSnapshotRecord] = []
}

enum AndroidWidgetSnapshotStore {
    static let appGroupIdentifier = "group.com.cshariq.sapphire"
    static let widgetKind = "com.cshariq.sapphire.android-widget"

    private static let directoryName = "AndroidWidgets"
    private static let catalogFilename = "catalog.json"

    static func loadCatalog(fileManager: FileManager = .default) -> AndroidWidgetCatalog {
        guard let url = catalogURL(fileManager: fileManager),
              let data = try? Data(contentsOf: url),
              let catalog = try? JSONDecoder().decode(AndroidWidgetCatalog.self, from: data)
        else { return AndroidWidgetCatalog() }
        return catalog
    }

    static func imageData(
        for snapshot: AndroidWidgetSnapshotRecord,
        fileManager: FileManager = .default
    ) -> Data? {
        guard let directory = sharedDirectory(fileManager: fileManager) else { return nil }
        return try? Data(contentsOf: directory.appendingPathComponent(snapshot.imageFilename))
    }

    @discardableResult
    static func saveProviders(
        _ providers: [AndroidWidgetProviderRecord],
        fileManager: FileManager = .default
    ) -> Bool {
        var catalog = loadCatalog(fileManager: fileManager)
        catalog.providers = providers.sorted {
            $0.label.localizedStandardCompare($1.label) == .orderedAscending
        }
        return saveCatalog(catalog, fileManager: fileManager)
    }

    @discardableResult
    static func saveSnapshot(
        instanceID: Int,
        provider: String,
        width: Int,
        height: Int,
        imageData: Data,
        fileManager: FileManager = .default
    ) -> Bool {
        guard let directory = sharedDirectory(fileManager: fileManager) else { return false }
        let filename = "widget-\(instanceID).image"
        let imageURL = directory.appendingPathComponent(filename)
        do {
            try imageData.write(to: imageURL, options: .atomic)
        } catch {
            return false
        }

        var catalog = loadCatalog(fileManager: fileManager)
        let label = catalog.providers.first(where: { $0.provider == provider })?.label
            ?? readableProviderName(provider)
        let snapshot = AndroidWidgetSnapshotRecord(
            instanceID: instanceID,
            provider: provider,
            label: label,
            width: width,
            height: height,
            imageFilename: filename,
            updatedAt: Date()
        )
        catalog.snapshots.removeAll { $0.instanceID == instanceID }
        catalog.snapshots.append(snapshot)
        catalog.snapshots.sort {
            if $0.label == $1.label { return $0.instanceID < $1.instanceID }
            return $0.label.localizedStandardCompare($1.label) == .orderedAscending
        }
        return saveCatalog(catalog, fileManager: fileManager)
    }

    static func removeSnapshot(instanceID: Int, fileManager: FileManager = .default) {
        var catalog = loadCatalog(fileManager: fileManager)
        guard let snapshot = catalog.snapshots.first(where: { $0.instanceID == instanceID }) else { return }
        catalog.snapshots.removeAll { $0.instanceID == instanceID }
        if let directory = sharedDirectory(fileManager: fileManager) {
            try? fileManager.removeItem(at: directory.appendingPathComponent(snapshot.imageFilename))
        }
        _ = saveCatalog(catalog, fileManager: fileManager)
    }

    private static func sharedDirectory(fileManager: FileManager) -> URL? {
        guard let container = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) else { return nil }
        let directory = container.appendingPathComponent(directoryName, isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func catalogURL(fileManager: FileManager) -> URL? {
        sharedDirectory(fileManager: fileManager)?.appendingPathComponent(catalogFilename)
    }

    private static func saveCatalog(
        _ catalog: AndroidWidgetCatalog,
        fileManager: FileManager
    ) -> Bool {
        guard let url = catalogURL(fileManager: fileManager),
              let data = try? JSONEncoder().encode(catalog)
        else { return false }
        do {
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    private static func readableProviderName(_ provider: String) -> String {
        let component = provider.split(separator: "/").last.map(String.init) ?? provider
        return component.split(separator: ".").last.map(String.init) ?? component
    }
}