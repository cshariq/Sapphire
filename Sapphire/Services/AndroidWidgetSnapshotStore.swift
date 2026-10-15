//
//  AndroidWidgetSnapshotStore.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-15
//

import Foundation
import CoreGraphics

struct AndroidWidgetProviderRecord: Codable, Hashable, Identifiable, Sendable {
    let provider: String
    let label: String
    let minWidth: Int
    let minHeight: Int
    var appLabel: String? = nil
    var widgetLabel: String? = nil
    var detail: String? = nil
    var cellWidth: Int? = nil
    var cellHeight: Int? = nil

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
    var widthDp: Int? = nil
    var heightDp: Int? = nil

    var id: String { String(instanceID) }
}

enum AndroidWidgetFamily: String, Codable, Sendable, CaseIterable {
    case small, medium, large

    var nominalSize: CGSize {
        switch self {
        case .small: return CGSize(width: 170, height: 170)
        case .medium: return CGSize(width: 364, height: 170)
        case .large: return CGSize(width: 364, height: 382)
        }
    }

    static func suggested(cellWidth: Int?, cellHeight: Int?, minWidth: Int, minHeight: Int) -> AndroidWidgetFamily {
        let w = Double(cellWidth ?? max(1, (minWidth + 30) / 70))
        let h = Double(cellHeight ?? max(1, (minHeight + 30) / 70))
        if w >= 3, h >= 3 { return .large }
        if w / max(h, 1) >= 1.6 { return .medium }
        return .small
    }
}

struct AndroidWidgetBinding: Codable, Hashable, Sendable {
    let provider: String
    let family: AndroidWidgetFamily
    let instanceID: Int
}

struct AndroidWidgetPendingAdd: Codable, Hashable, Sendable {
    let provider: String
    var family: AndroidWidgetFamily? = nil
    var widthPt: Int? = nil
    var heightPt: Int? = nil
    var requestedAt: Date? = nil

    var key: String { "\(provider)|\(family?.rawValue ?? "-")" }
}

struct AndroidWidgetDisplay: Codable, Hashable, Sendable {
    let instanceID: Int
    let family: AndroidWidgetFamily
    let widthPt: Int
    let heightPt: Int
    let seenAt: Date
}

struct AndroidWidgetSlotInfo: Hashable, Sendable {
    let slot: Int
    let instanceID: Int
    let label: String
    let detail: String
    let families: [AndroidWidgetFamily]
}

struct AndroidWidgetCatalog: Codable, Sendable {
    var providers: [AndroidWidgetProviderRecord] = []
    var snapshots: [AndroidWidgetSnapshotRecord] = []
    var bindings: [AndroidWidgetBinding] = []
    var providersUpdatedAt: Date?
    var slotAssignments: [String: Int] = [:]
    var slotReleasedAt: [String: Date] = [:]

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        providers = (try? c.decodeIfPresent([AndroidWidgetProviderRecord].self, forKey: .providers)) ?? []
        snapshots = (try? c.decodeIfPresent([AndroidWidgetSnapshotRecord].self, forKey: .snapshots)) ?? []
        bindings = (try? c.decodeIfPresent([AndroidWidgetBinding].self, forKey: .bindings)) ?? []
        providersUpdatedAt = try? c.decodeIfPresent(Date.self, forKey: .providersUpdatedAt)
        slotAssignments = (try? c.decodeIfPresent([String: Int].self, forKey: .slotAssignments)) ?? [:]
        slotReleasedAt = (try? c.decodeIfPresent([String: Date].self, forKey: .slotReleasedAt)) ?? [:]
    }

    // MARK: Gallery slots

    func instance(forSlot slot: Int) -> Int? {
        slotAssignments[String(slot)]
    }

    func slot(forInstance instanceID: Int) -> Int? {
        slotAssignments.first { $0.value == instanceID }.flatMap { Int($0.key) }
    }

    func slotInfo(_ slot: Int) -> AndroidWidgetSlotInfo? {
        guard let id = instance(forSlot: slot), let snapshot = snapshot(instanceID: id) else { return nil }
        let record = provider(snapshot.provider)
        return AndroidWidgetSlotInfo(
            slot: slot,
            instanceID: id,
            label: galleryLabel(for: snapshot),
            detail: record?.detail.flatMap { $0.isEmpty ? nil : $0 } ?? "Live widget from your Android phone.",
            families: Self.galleryFamilies(for: snapshot))
    }

    var assignedSlots: [AndroidWidgetSlotInfo] {
        (0..<AndroidWidgetSnapshotStore.slotCount).compactMap(slotInfo)
    }

    var snapshotsInSlotOrder: [AndroidWidgetSnapshotRecord] {
        snapshots.sorted {
            let a = slot(forInstance: $0.instanceID) ?? Int.max
            let b = slot(forInstance: $1.instanceID) ?? Int.max
            return a == b ? $0.instanceID < $1.instanceID : a < b
        }
    }

    func galleryLabel(for snapshot: AndroidWidgetSnapshotRecord) -> String {
        let record = provider(snapshot.provider)
        if let app = record?.appLabel, !app.isEmpty {
            if let widget = record?.widgetLabel, !widget.isEmpty, widget != app { return "\(app) · \(widget)" }
            return app
        }
        return Self.stripCellSize(record?.label ?? snapshot.label)
    }

    func appLabel(for snapshot: AndroidWidgetSnapshotRecord) -> String {
        if let app = provider(snapshot.provider)?.appLabel, !app.isEmpty { return app }
        let label = Self.stripCellSize(provider(snapshot.provider)?.label ?? snapshot.label)
        return label.components(separatedBy: " · ").first ?? label
    }

    static func stripCellSize(_ label: String) -> String {
        var label = label
        if let dash = label.range(of: " — ") { label = String(label[..<dash.lowerBound]) }
        if let open = label.range(of: " (", options: .backwards), label.hasSuffix(")") {
            let inner = label[open.upperBound..<label.index(before: label.endIndex)]
            if inner.range(of: #"^\d+\s*[×x]\s*\d+$"#, options: .regularExpression) != nil {
                label = String(label[..<open.lowerBound])
            }
        }
        return label.trimmingCharacters(in: .whitespaces)
    }

    static func galleryFamilies(for snapshot: AndroidWidgetSnapshotRecord) -> [AndroidWidgetFamily] {
        let w = Double(snapshot.widthDp ?? max(snapshot.width, 1))
        let h = Double(snapshot.heightDp ?? max(snapshot.height, 1))
        let aspect = w / max(h, 1)
        let big = snapshot.heightDp.map { $0 >= 250 } ?? false
        if aspect >= 1.6 { return big ? [.medium, .large] : [.medium] }
        return [.small, .large]
    }

    mutating func assignSlot(to instanceID: Int) -> Int? {
        guard slot(forInstance: instanceID) == nil else { return nil }
        let free = (0..<AndroidWidgetSnapshotStore.slotCount).filter { instance(forSlot: $0) == nil }
        guard let chosen = free.min(by: {
            (slotReleasedAt[String($0)] ?? .distantPast, $0) < (slotReleasedAt[String($1)] ?? .distantPast, $1)
        }) else { return nil }
        slotAssignments[String(chosen)] = instanceID
        return chosen
    }

    @discardableResult
    mutating func releaseSlot(of instanceID: Int) -> Int? {
        guard let slot = slot(forInstance: instanceID) else { return nil }
        slotAssignments.removeValue(forKey: String(slot))
        slotReleasedAt[String(slot)] = Date()
        return slot
    }

    var gallerySignature: String {
        assignedSlots.map { "\($0.slot)=\($0.instanceID)|\($0.label)|\($0.families.map(\.rawValue).joined(separator: ","))" }
            .joined(separator: ";")
    }

    func provider(_ provider: String) -> AndroidWidgetProviderRecord? {
        providers.first { $0.provider == provider }
    }

    func snapshot(instanceID: Int) -> AndroidWidgetSnapshotRecord? {
        snapshots.first { $0.instanceID == instanceID }
    }

    func boundInstance(provider: String, family: AndroidWidgetFamily) -> Int? {
        bindings.first { $0.provider == provider && $0.family == family }?.instanceID
    }

    func displayLabel(for provider: String) -> String {
        self.provider(provider)?.label ?? AndroidWidgetSnapshotStore.readableProviderName(provider)
    }
}

enum AndroidWidgetSnapshotStore {
    static let appGroupIdentifier = "group.com.cshariq.sapphire"
    static let widgetKind = "com.cshariq.sapphire.android-widget"
    static let slotKindPrefix = "com.cshariq.sapphire.android-widget.slot."
    static let slotCount = 12
    static let combinedKind = "com.cshariq.sapphire.android-widgets.all"

    static func slotKind(_ slot: Int) -> String { slotKindPrefix + String(slot) }
    static let requestNotification = "com.cshariq.sapphire.android-widgets.request"

    private static let directoryName = "AndroidWidgets"
    private static let catalogFilename = "catalog.json"
    private static let pendingFilename = "pending-adds.json"
    private static let displaysFilename = "displays.json"

    // MARK: Catalog (app-owned)

    static func loadCatalog(fileManager: FileManager = .default) -> AndroidWidgetCatalog {
        guard let url = fileURL(catalogFilename, fileManager: fileManager),
              let data = try? Data(contentsOf: url),
              let catalog = try? JSONDecoder().decode(AndroidWidgetCatalog.self, from: data)
        else { return AndroidWidgetCatalog() }
        return catalog
    }

    @discardableResult
    static func updateCatalog(
        fileManager: FileManager = .default,
        _ mutate: (inout AndroidWidgetCatalog) -> Void
    ) -> Bool {
        var catalog = loadCatalog(fileManager: fileManager)
        mutate(&catalog)
        return saveCatalog(catalog, fileManager: fileManager)
    }

    static func imageData(
        for snapshot: AndroidWidgetSnapshotRecord,
        fileManager: FileManager = .default
    ) -> Data? {
        guard let directory = sharedDirectory(fileManager: fileManager) else { return nil }
        return try? Data(contentsOf: directory.appendingPathComponent(snapshot.imageFilename))
    }

    @discardableResult
    static func replaceProviders(
        _ providers: [AndroidWidgetProviderRecord],
        placedInstances: Set<Int>?,
        fileManager: FileManager = .default
    ) -> [Int] {
        var pruned: [Int] = []
        updateCatalog(fileManager: fileManager) { catalog in
            catalog.providers = providers.sorted {
                $0.label.localizedStandardCompare($1.label) == .orderedAscending
            }
            catalog.providersUpdatedAt = Date()
            guard let placed = placedInstances else { return }
            pruned = catalog.snapshots.map(\.instanceID).filter { !placed.contains($0) }
            catalog.snapshots.removeAll { !placed.contains($0.instanceID) }
            catalog.bindings.removeAll { !placed.contains($0.instanceID) }
            for id in pruned { catalog.releaseSlot(of: id) }
            let known = Set(catalog.snapshots.map(\.instanceID))
            for (_, id) in catalog.slotAssignments where !known.contains(id) { catalog.releaseSlot(of: id) }
        }
        if let directory = sharedDirectory(fileManager: fileManager) {
            for id in pruned {
                try? fileManager.removeItem(at: directory.appendingPathComponent("widget-\(id).image"))
            }
        }
        return pruned
    }

    struct SaveOutcome: Sendable {
        let assignedSlot: Int?
    }

    @discardableResult
    static func saveSnapshot(
        instanceID: Int,
        provider: String,
        width: Int,
        height: Int,
        widthDp: Int? = nil,
        heightDp: Int? = nil,
        imageData: Data,
        fileManager: FileManager = .default
    ) -> SaveOutcome? {
        guard let directory = sharedDirectory(fileManager: fileManager) else { return nil }
        let filename = "widget-\(instanceID).image"
        let imageURL = directory.appendingPathComponent(filename)
        do {
            try imageData.write(to: imageURL, options: .atomic)
        } catch {
            return nil
        }
        var assigned: Int?
        let saved = updateCatalog(fileManager: fileManager) { catalog in
            defer { assigned = catalog.assignSlot(to: instanceID) }
            let previous = catalog.snapshot(instanceID: instanceID)
            let resolvedProvider = provider.isEmpty ? (previous?.provider ?? "") : provider
            let snapshot = AndroidWidgetSnapshotRecord(
                instanceID: instanceID,
                provider: resolvedProvider,
                label: catalog.displayLabel(for: resolvedProvider),
                width: width,
                height: height,
                imageFilename: filename,
                updatedAt: Date(),
                widthDp: widthDp ?? previous?.widthDp,
                heightDp: heightDp ?? previous?.heightDp
            )
            catalog.snapshots.removeAll { $0.instanceID == instanceID }
            catalog.snapshots.append(snapshot)
            catalog.snapshots.sort {
                if $0.label == $1.label { return $0.instanceID < $1.instanceID }
                return $0.label.localizedStandardCompare($1.label) == .orderedAscending
            }
        }
        return saved ? SaveOutcome(assignedSlot: assigned) : nil
    }

    @discardableResult
    static func assignMissingSlots(fileManager: FileManager = .default) -> [(slot: Int, instanceID: Int)] {
        let current = loadCatalog(fileManager: fileManager)
        guard current.snapshots.contains(where: { current.slot(forInstance: $0.instanceID) == nil }) else { return [] }
        var assigned: [(slot: Int, instanceID: Int)] = []
        updateCatalog(fileManager: fileManager) { catalog in
            for snapshot in catalog.snapshots.sorted(by: { $0.instanceID < $1.instanceID }) {
                if let slot = catalog.assignSlot(to: snapshot.instanceID) {
                    assigned.append((slot, snapshot.instanceID))
                }
            }
        }
        return assigned
    }

    static func bind(provider: String, family: AndroidWidgetFamily, instanceID: Int, fileManager: FileManager = .default) {
        updateCatalog(fileManager: fileManager) { catalog in
            catalog.bindings.removeAll { $0.provider == provider && $0.family == family }
            catalog.bindings.append(AndroidWidgetBinding(provider: provider, family: family, instanceID: instanceID))
        }
    }

    @discardableResult
    static func removeSnapshot(instanceID: Int, fileManager: FileManager = .default) -> Int? {
        var filename: String?
        var released: Int?
        updateCatalog(fileManager: fileManager) { catalog in
            filename = catalog.snapshot(instanceID: instanceID)?.imageFilename
            catalog.snapshots.removeAll { $0.instanceID == instanceID }
            catalog.bindings.removeAll { $0.instanceID == instanceID }
            released = catalog.releaseSlot(of: instanceID)
        }
        if let filename, let directory = sharedDirectory(fileManager: fileManager) {
            try? fileManager.removeItem(at: directory.appendingPathComponent(filename))
        }
        return released
    }

    // MARK: Pending adds (extension → app)

    static func requestProvider(
        _ provider: String,
        family: AndroidWidgetFamily? = nil,
        size: CGSize? = nil,
        fileManager: FileManager = .default
    ) {
        guard !provider.isEmpty else { return }
        var pending = loadPendingAdds(fileManager: fileManager)
        let add = AndroidWidgetPendingAdd(
            provider: provider,
            family: family,
            widthPt: size.map { Int($0.width.rounded()) },
            heightPt: size.map { Int($0.height.rounded()) },
            requestedAt: Date())
        guard !pending.contains(where: { $0.key == add.key }) else { return }
        pending.append(add)
        savePendingAdds(pending, fileManager: fileManager)
        postRequestNotification()
    }

    static func consumePendingAdds(fileManager: FileManager = .default) -> [AndroidWidgetPendingAdd] {
        let pending = loadPendingAdds(fileManager: fileManager)
        guard !pending.isEmpty else { return [] }
        let taken = Set(pending.map(\.key))
        let remaining = loadPendingAdds(fileManager: fileManager).filter { !taken.contains($0.key) }
        savePendingAdds(remaining, fileManager: fileManager)
        return pending
    }

    // MARK: Display sizes (extension → app)

    static func recordDisplay(
        instanceID: Int,
        family: AndroidWidgetFamily,
        size: CGSize,
        fileManager: FileManager = .default
    ) {
        var displays = loadDisplays(fileManager: fileManager)
        let w = Int(size.width.rounded()), h = Int(size.height.rounded())
        guard w > 0, h > 0 else { return }
        if let existing = displays.first(where: { $0.instanceID == instanceID && $0.family == family }),
           existing.widthPt == w, existing.heightPt == h,
           Date().timeIntervalSince(existing.seenAt) < 6 * 3600 {
            return
        }
        displays.removeAll { $0.instanceID == instanceID && $0.family == family }
        displays.removeAll { Date().timeIntervalSince($0.seenAt) > 7 * 86_400 }
        displays.append(AndroidWidgetDisplay(instanceID: instanceID, family: family, widthPt: w, heightPt: h, seenAt: Date()))
        guard let url = fileURL(displaysFilename, fileManager: fileManager),
              let data = try? JSONEncoder().encode(displays) else { return }
        try? data.write(to: url, options: .atomic)
        postRequestNotification()
    }

    static func loadDisplays(fileManager: FileManager = .default) -> [AndroidWidgetDisplay] {
        guard let url = fileURL(displaysFilename, fileManager: fileManager),
              let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([AndroidWidgetDisplay].self, from: data)
        else { return [] }
        return list
    }

    static func targetSize(for instanceID: Int, displays: [AndroidWidgetDisplay]) -> CGSize? {
        displays
            .filter { $0.instanceID == instanceID && Date().timeIntervalSince($0.seenAt) < 7 * 86_400 }
            .max { $0.widthPt * $0.heightPt < $1.widthPt * $1.heightPt }
            .map { CGSize(width: $0.widthPt, height: $0.heightPt) }
    }

    // MARK: Notification

    static func postRequestNotification() {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(requestNotification as CFString),
            nil, nil, true)
    }

    // MARK: Files

    private static func sharedDirectory(fileManager: FileManager) -> URL? {
        guard let container = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) else { return nil }
        let directory = container.appendingPathComponent(directoryName, isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func fileURL(_ name: String, fileManager: FileManager) -> URL? {
        sharedDirectory(fileManager: fileManager)?.appendingPathComponent(name)
    }

    private static func loadPendingAdds(fileManager: FileManager) -> [AndroidWidgetPendingAdd] {
        guard let url = fileURL(pendingFilename, fileManager: fileManager),
              let data = try? Data(contentsOf: url)
        else { return [] }
        if let list = try? JSONDecoder().decode([AndroidWidgetPendingAdd].self, from: data) { return list }
        if let legacy = try? JSONDecoder().decode([String].self, from: data) {
            return legacy.map { AndroidWidgetPendingAdd(provider: $0) }
        }
        return []
    }

    private static func savePendingAdds(_ adds: [AndroidWidgetPendingAdd], fileManager: FileManager) {
        guard let url = fileURL(pendingFilename, fileManager: fileManager),
              let data = try? JSONEncoder().encode(adds)
        else { return }
        try? data.write(to: url, options: .atomic)
    }

    private static func saveCatalog(
        _ catalog: AndroidWidgetCatalog,
        fileManager: FileManager
    ) -> Bool {
        guard let url = fileURL(catalogFilename, fileManager: fileManager),
              let data = try? JSONEncoder().encode(catalog)
        else { return false }
        do {
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    static func readableProviderName(_ provider: String) -> String {
        let component = provider.split(separator: "/").last.map(String.init) ?? provider
        return component.split(separator: ".").last.map(String.init) ?? component
    }
}