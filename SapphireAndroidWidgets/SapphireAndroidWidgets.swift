//
//  SapphireAndroidWidgets.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-15

import AppIntents
import AppKit
import SwiftUI
import WidgetKit

// MARK: - Configuration entity

struct AndroidWidgetChoice: AppEntity, Identifiable {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Android Widget")
    static let defaultQuery = AndroidWidgetChoiceQuery()

    static let providerPrefix = "provider:"

    let id: String
    let label: String
    let subtitle: String
    let provider: String
    let thumbnail: Data?

    var instanceID: Int? { id.hasPrefix(Self.providerPrefix) ? nil : Int(id) }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(label)",
            subtitle: "\(subtitle)",
            image: thumbnail.map { DisplayRepresentation.Image(data: $0) })
    }

    init(snapshot: AndroidWidgetSnapshotRecord, catalog: AndroidWidgetCatalog, withThumbnail: Bool = false) {
        id = snapshot.id
        label = catalog.provider(snapshot.provider)?.label ?? snapshot.label
        subtitle = String(localized: "On your Mac")
        provider = snapshot.provider
        thumbnail = withThumbnail ? AndroidWidgetSnapshotStore.imageData(for: snapshot) : nil
    }

    init(providerRecord: AndroidWidgetProviderRecord) {
        id = Self.providerPrefix + providerRecord.provider
        label = providerRecord.label
        subtitle = providerRecord.detail ?? String(localized: "Add from your phone")
        provider = providerRecord.provider
        thumbnail = nil
    }

    init(providerID: String) {
        let provider = String(providerID.dropFirst(Self.providerPrefix.count))
        id = providerID
        label = AndroidWidgetSnapshotStore.readableProviderName(provider)
        subtitle = String(localized: "Android widget")
        self.provider = provider
        thumbnail = nil
    }
}

struct AndroidWidgetChoiceQuery: EntityStringQuery {
    func entities(for identifiers: [AndroidWidgetChoice.ID]) async throws -> [AndroidWidgetChoice] {
        let catalog = AndroidWidgetSnapshotStore.loadCatalog()
        return identifiers.compactMap { id in
            if id.hasPrefix(AndroidWidgetChoice.providerPrefix) {
                let provider = String(id.dropFirst(AndroidWidgetChoice.providerPrefix.count))
                if let record = catalog.provider(provider) { return AndroidWidgetChoice(providerRecord: record) }
                return AndroidWidgetChoice(providerID: id)
            }
            guard let instance = Int(id), let snapshot = catalog.snapshot(instanceID: instance) else { return nil }
            return AndroidWidgetChoice(snapshot: snapshot, catalog: catalog)
        }
    }

    func entities(matching string: String) async throws -> IntentItemCollection<AndroidWidgetChoice> {
        let query = string.trimmingCharacters(in: .whitespaces)
        return collection { choice in
            query.isEmpty || choice.label.localizedCaseInsensitiveContains(query)
                || choice.provider.localizedCaseInsensitiveContains(query)
        }
    }

    func suggestedEntities() async throws -> IntentItemCollection<AndroidWidgetChoice> {
        collection { _ in true }
    }

    private func collection(_ include: (AndroidWidgetChoice) -> Bool) -> IntentItemCollection<AndroidWidgetChoice> {
        let catalog = AndroidWidgetSnapshotStore.loadCatalog()
        let placed = catalog.snapshots
            .map { AndroidWidgetChoice(snapshot: $0, catalog: catalog, withThumbnail: true) }
            .filter(include)
        let available = catalog.providers.map(AndroidWidgetChoice.init(providerRecord:)).filter(include)
        var sections: [IntentItemSection<AndroidWidgetChoice>] = []
        if !placed.isEmpty {
            sections.append(IntentItemSection("On your Mac", items: placed.map { IntentItem($0) }))
        }
        if !available.isEmpty {
            sections.append(IntentItemSection("Add from your phone", items: available.map { IntentItem($0) }))
        }
        return IntentItemCollection(sections: sections)
    }

    func defaultResult() async -> AndroidWidgetChoice? {
        let catalog = AndroidWidgetSnapshotStore.loadCatalog()
        return catalog.snapshots.first.map { AndroidWidgetChoice(snapshot: $0, catalog: catalog) }
    }
}

struct AndroidWidgetConfigurationIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Android Widget"
    static let description = IntentDescription("Choose a widget mirrored from your paired Android phone.")

    @Parameter(title: "Widget")
    var widget: AndroidWidgetChoice?
}

// MARK: - Timeline

struct AndroidWidgetEntry: TimelineEntry {
    enum Status { case empty, adding, waiting, removed, ready }

    let date: Date
    let snapshot: AndroidWidgetSnapshotRecord?
    let imageData: Data?
    let displaySize: CGSize
    let status: Status
    let title: String?
}

struct AndroidWidgetTimelineProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> AndroidWidgetEntry {
        AndroidWidgetEntry(date: Date(), snapshot: nil, imageData: nil,
                           displaySize: context.displaySize, status: .empty, title: nil)
    }

    func snapshot(
        for configuration: AndroidWidgetConfigurationIntent,
        in context: Context
    ) async -> AndroidWidgetEntry {
        entry(for: configuration, in: context)
    }

    func timeline(
        for configuration: AndroidWidgetConfigurationIntent,
        in context: Context
    ) async -> Timeline<AndroidWidgetEntry> {
        let entry = entry(for: configuration, in: context)
        return Timeline(entries: [entry], policy: .after(entry.nextRefresh))
    }

    private func entry(for configuration: AndroidWidgetConfigurationIntent, in context: Context) -> AndroidWidgetEntry {
        let catalog = AndroidWidgetSnapshotStore.loadCatalog()
        let family = AndroidWidgetFamily(context.family)
        let size = context.displaySize.width > 0 ? context.displaySize : family.nominalSize
        var snapshot: AndroidWidgetSnapshotRecord?
        var status: AndroidWidgetEntry.Status = .ready
        var title: String?

        if let selected = configuration.widget {
            title = selected.label
            if let instance = selected.instanceID {
                snapshot = catalog.snapshot(instanceID: instance)
                if snapshot == nil { status = .removed }
            } else if let bound = catalog.boundInstance(provider: selected.provider, family: family),
                      let found = catalog.snapshot(instanceID: bound) {
                snapshot = found
            } else {
                if !context.isPreview {
                    AndroidWidgetSnapshotStore.requestProvider(selected.provider, family: family, size: size)
                }
                snapshot = catalog.snapshots.first { $0.provider == selected.provider }
                status = snapshot == nil ? .adding : .ready
            }
        } else {
            snapshot = catalog.snapshots.first
            if snapshot == nil { status = .empty }
        }

        return AndroidWidgetEntry.make(snapshot: snapshot, status: status, title: title ?? snapshot?.label,
                                       family: family, size: size, isPreview: context.isPreview)
    }
}

extension AndroidWidgetFamily {
    init(_ family: WidgetFamily) {
        switch family {
        case .systemMedium: self = .medium
        case .systemLarge, .systemExtraLarge: self = .large
        default: self = .small
        }
    }

    var widgetFamily: WidgetFamily {
        switch self {
        case .small: return .systemSmall
        case .medium: return .systemMedium
        case .large: return .systemLarge
        }
    }
}

extension AndroidWidgetEntry {
    static func make(
        snapshot: AndroidWidgetSnapshotRecord?,
        status: Status,
        title: String?,
        family: AndroidWidgetFamily,
        size: CGSize,
        isPreview: Bool
    ) -> AndroidWidgetEntry {
        var status = status
        if let snapshot, !isPreview {
            AndroidWidgetSnapshotStore.recordDisplay(instanceID: snapshot.instanceID, family: family, size: size)
        }
        let data = snapshot.flatMap { AndroidWidgetSnapshotStore.imageData(for: $0) }
        if snapshot != nil, data == nil { status = .waiting }
        return AndroidWidgetEntry(date: Date(), snapshot: snapshot, imageData: data,
                                  displaySize: size, status: status, title: title)
    }

    var nextRefresh: Date {
        Date().addingTimeInterval(status == .ready ? 15 * 60 : 60)
    }
}

// MARK: - View

struct AndroidWidgetEntryView: View {
    let entry: AndroidWidgetTimelineProvider.Entry

    var body: some View {
        Group {
            if let data = entry.imageData, let image = NSImage(data: data) {
                frameImage(image)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "iphone.gen3.radiowaves.left.and.right")
                        .font(.system(size: 26, weight: .medium))
                        .foregroundStyle(.secondary)
                    if let title = entry.title {
                        Text(title)
                            .font(.caption.weight(.semibold))
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                    }
                    Text(message)
                        .font(.caption2)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
                .padding()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerBackground(.fill.tertiary, for: .widget)
        .widgetURL(url)
    }

    @ViewBuilder
    private func frameImage(_ image: NSImage) -> some View {
        let pixel = image.representations.first.map { CGSize(width: $0.pixelsWide, height: $0.pixelsHigh) } ?? image.size
        let imageAspect = pixel.height > 0 ? pixel.width / pixel.height : 1
        let displayAspect = entry.displaySize.height > 0 ? entry.displaySize.width / entry.displaySize.height : 1
        let matches = abs(imageAspect - displayAspect) / max(displayAspect, 0.01) < 0.15
        Image(nsImage: image)
            .resizable()
            .interpolation(.high)
            .antialiased(true)
            .aspectRatio(contentMode: matches ? .fill : .fit)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
    }

    private var message: String {
        switch entry.status {
        case .adding: return String(localized: "Adding from your phone — allow it there if asked")
        case .waiting: return String(localized: "Waiting for your phone")
        case .removed: return String(localized: "This widget was removed from your phone")
        case .empty, .ready: return String(localized: "Edit this widget to choose one from your phone")
        }
    }

    private var url: URL? {
        if let id = entry.snapshot?.instanceID {
            return URL(string: "sapphire://android-widgets?id=\(id)")
        }
        return URL(string: "sapphire://android-widgets")
    }
}

struct SapphireAndroidWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: AndroidWidgetSnapshotStore.widgetKind,
            intent: AndroidWidgetConfigurationIntent.self,
            provider: AndroidWidgetTimelineProvider()
        ) { entry in
            AndroidWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Android Widget (choose)")
        .description("Pick any widget from your paired Android phone — choosing one that isn't on your Mac yet adds it from the phone.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

// MARK: - Gallery slots (one widget per placed instance)

protocol AndroidWidgetSlotIndex { static var index: Int { get } }
enum AndroidSlot0: AndroidWidgetSlotIndex { static let index = 0 }
enum AndroidSlot1: AndroidWidgetSlotIndex { static let index = 1 }
enum AndroidSlot2: AndroidWidgetSlotIndex { static let index = 2 }
enum AndroidSlot3: AndroidWidgetSlotIndex { static let index = 3 }
enum AndroidSlot4: AndroidWidgetSlotIndex { static let index = 4 }
enum AndroidSlot5: AndroidWidgetSlotIndex { static let index = 5 }
enum AndroidSlot6: AndroidWidgetSlotIndex { static let index = 6 }
enum AndroidSlot7: AndroidWidgetSlotIndex { static let index = 7 }
enum AndroidSlot8: AndroidWidgetSlotIndex { static let index = 8 }
enum AndroidSlot9: AndroidWidgetSlotIndex { static let index = 9 }
enum AndroidSlot10: AndroidWidgetSlotIndex { static let index = 10 }
enum AndroidSlot11: AndroidWidgetSlotIndex { static let index = 11 }

struct AndroidSlotTimelineProvider: TimelineProvider {
    let slot: Int

    func placeholder(in context: Context) -> AndroidWidgetEntry {
        entry(in: context, isPreview: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (AndroidWidgetEntry) -> Void) {
        completion(entry(in: context, isPreview: context.isPreview))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<AndroidWidgetEntry>) -> Void) {
        let entry = entry(in: context, isPreview: false)
        completion(Timeline(entries: [entry], policy: .after(entry.nextRefresh)))
    }

    private func entry(in context: Context, isPreview: Bool) -> AndroidWidgetEntry {
        let catalog = AndroidWidgetSnapshotStore.loadCatalog()
        let family = AndroidWidgetFamily(context.family)
        let size = context.displaySize.width > 0 ? context.displaySize : family.nominalSize
        let snapshot = catalog.instance(forSlot: slot).flatMap { catalog.snapshot(instanceID: $0) }
        return AndroidWidgetEntry.make(
            snapshot: snapshot,
            status: snapshot == nil ? .removed : .ready,
            title: snapshot.map { catalog.galleryLabel(for: $0) },
            family: family, size: size, isPreview: isPreview)
    }
}

struct AndroidSlotWidget<Slot: AndroidWidgetSlotIndex>: Widget {
    var body: some WidgetConfiguration {
        let info = AndroidWidgetSnapshotStore.loadCatalog().slotInfo(Slot.index)
        return StaticConfiguration(
            kind: AndroidWidgetSnapshotStore.slotKind(Slot.index),
            provider: AndroidSlotTimelineProvider(slot: Slot.index)
        ) { entry in
            AndroidWidgetEntryView(entry: entry)
        }
        .configurationDisplayName(Text(info?.label ?? String(localized: "Android Widget")))
        .description(Text(info?.detail ?? String(localized: "Live widget from your Android phone.")))
        .supportedFamilies((info?.families ?? []).map(\.widgetFamily))
        .contentMarginsDisabled()
    }
}

@MainActor
private func androidSlot<Slot: AndroidWidgetSlotIndex>(_: Slot.Type, in assigned: Set<Int>) -> some Widget {
    WidgetBundleBuilder.buildOptional(
        assigned.contains(Slot.index)
            ? WidgetBundleBuilder.buildLimitedAvailability(AndroidSlotWidget<Slot>())
            : nil)
}

// MARK: - Combined widget

struct AndroidCombinedEntry: TimelineEntry {
    struct Tile: Identifiable {
        let instanceID: Int
        let label: String
        let imageData: Data?
        let aspect: CGFloat
        var id: Int { instanceID }
    }

    let date: Date
    let tiles: [Tile]
    let hiddenCount: Int
}

struct AndroidCombinedTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> AndroidCombinedEntry { entry(in: context) }

    func getSnapshot(in context: Context, completion: @escaping (AndroidCombinedEntry) -> Void) {
        completion(entry(in: context))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<AndroidCombinedEntry>) -> Void) {
        let entry = entry(in: context)
        let next: TimeInterval = entry.tiles.isEmpty ? 5 * 60 : 15 * 60
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(next))))
    }

    private func entry(in context: Context) -> AndroidCombinedEntry {
        let catalog = AndroidWidgetSnapshotStore.loadCatalog()
        let cap: Int
        switch context.family {
        case .systemMedium: cap = 4
        case .systemLarge: cap = 9
        default: cap = 16
        }
        let all = catalog.snapshotsInSlotOrder
        let tiles = all.prefix(cap).map { snapshot -> AndroidCombinedEntry.Tile in
            let w = CGFloat(snapshot.widthDp ?? max(snapshot.width, 1))
            let h = CGFloat(snapshot.heightDp ?? max(snapshot.height, 1))
            return AndroidCombinedEntry.Tile(
                instanceID: snapshot.instanceID,
                label: catalog.appLabel(for: snapshot),
                imageData: AndroidWidgetSnapshotStore.imageData(for: snapshot),
                aspect: min(max(w / max(h, 1), 0.4), 3.5))
        }
        return AndroidCombinedEntry(date: Date(), tiles: Array(tiles), hiddenCount: max(0, all.count - cap))
    }
}

enum AndroidCombinedLayout {
    struct Row { let range: Range<Int>; let height: CGFloat }
    struct Result { let rows: [Row]; let scale: CGFloat }

    static func layout(aspects: [CGFloat], in size: CGSize, spacing: CGFloat) -> Result {
        guard !aspects.isEmpty, size.width > 0, size.height > 0 else { return Result(rows: [], scale: 1) }
        var best: Result?
        var bestArea: CGFloat = -1
        for rowCount in 1...min(aspects.count, 5) {
            let rows = partition(aspects, rows: rowCount).map { range -> Row in
                let sum = aspects[range].reduce(0, +)
                let width = size.width - spacing * CGFloat(range.count - 1)
                return Row(range: range, height: width / max(sum, 0.01))
            }
            let total = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(rows.count - 1)
            let scale = min(1, size.height / max(total, 1))
            let area = rows.reduce(CGFloat(0)) { acc, row in
                acc + row.height * row.height * aspects[row.range].reduce(0, +)
            } * scale * scale
            if area > bestArea { bestArea = area; best = Result(rows: rows, scale: scale) }
        }
        return best ?? Result(rows: [], scale: 1)
    }

    private static func partition(_ aspects: [CGFloat], rows: Int) -> [Range<Int>] {
        let target = aspects.reduce(0, +) / CGFloat(rows)
        var ranges: [Range<Int>] = []
        var start = 0, sum: CGFloat = 0
        for (i, a) in aspects.enumerated() {
            let remainingRows = rows - ranges.count
            let remainingItems = aspects.count - i
            if i > start, ranges.count < rows - 1,
               (sum + a / 2 > target || remainingItems < remainingRows) {
                ranges.append(start..<i); start = i; sum = 0
            }
            sum += a
        }
        ranges.append(start..<aspects.count)
        return ranges
    }
}

struct AndroidCombinedEntryView: View {
    let entry: AndroidCombinedEntry
    private let spacing: CGFloat = 6

    var body: some View {
        Group {
            if entry.tiles.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "square.grid.2x2")
                        .font(.system(size: 26, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text("Add widgets from your phone")
                        .font(.callout.weight(.semibold))
                    Text("Use “Android Widget (choose)” here, or Widgets on your Mac in the Sapphire phone app.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal)
            } else {
                GeometryReader { proxy in
                    grid(in: proxy.size)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .topTrailing) {
            if entry.hiddenCount > 0 {
                Text("+\(entry.hiddenCount)")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(.black.opacity(0.45)))
                    .foregroundStyle(.white)
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
        .widgetURL(URL(string: "sapphire://android-widgets"))
    }

    @ViewBuilder
    private func grid(in size: CGSize) -> some View {
        let tiles = entry.tiles
        let result = AndroidCombinedLayout.layout(aspects: tiles.map(\.aspect), in: size, spacing: spacing)
        VStack(spacing: spacing * result.scale) {
            ForEach(Array(result.rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: spacing * result.scale) {
                    ForEach(tiles[row.range]) { tile in
                        let height = row.height * result.scale
                        tileView(tile, size: CGSize(width: height * tile.aspect, height: height))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func tileView(_ tile: AndroidCombinedEntry.Tile, size: CGSize) -> some View {
        let shape = RoundedRectangle(cornerRadius: min(12, min(size.width, size.height) / 5), style: .continuous)
        Link(destination: URL(string: "sapphire://android-widgets?id=\(tile.instanceID)")!) {
            ZStack(alignment: .bottomLeading) {
                if let data = tile.imageData, let image = NSImage(data: data) {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fill)
                        .frame(width: size.width, height: size.height)
                        .clipped()
                } else {
                    shape.fill(.quaternary)
                        .overlay {
                            Image(systemName: "iphone.gen3.radiowaves.left.and.right")
                                .foregroundStyle(.secondary)
                        }
                }
                if size.height >= 48, size.width >= 60 {
                    Text(tile.label)
                        .font(.system(size: 9, weight: .semibold))
                        .lineLimit(1)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(Capsule().fill(.black.opacity(0.45)))
                        .foregroundStyle(.white)
                        .padding(5)
                }
            }
            .frame(width: size.width, height: size.height)
            .clipShape(shape)
            .overlay(shape.strokeBorder(.primary.opacity(0.08), lineWidth: 0.5))
        }
    }
}

struct SapphireAndroidWidgetsCombined: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: AndroidWidgetSnapshotStore.combinedKind,
            provider: AndroidCombinedTimelineProvider()
        ) { entry in
            AndroidCombinedEntryView(entry: entry)
        }
        .configurationDisplayName("Android Widgets")
        .description("All the widgets from your Android phone that are on your Mac, together.")
        .supportedFamilies([.systemMedium, .systemLarge, .systemExtraLarge])
    }
}

// MARK: - Bundle

@main
struct SapphireAndroidWidgetBundle: WidgetBundle {
    var body: some Widget {
        let assigned = Set(AndroidWidgetSnapshotStore.loadCatalog().assignedSlots.map(\.slot))
        SapphireAndroidWidgetsCombined()
        SapphireAndroidWidget()
        androidSlot(AndroidSlot0.self, in: assigned)
        androidSlot(AndroidSlot1.self, in: assigned)
        androidSlot(AndroidSlot2.self, in: assigned)
        androidSlot(AndroidSlot3.self, in: assigned)
        androidSlot(AndroidSlot4.self, in: assigned)
        androidSlot(AndroidSlot5.self, in: assigned)
        androidSlot(AndroidSlot6.self, in: assigned)
        androidSlot(AndroidSlot7.self, in: assigned)
        androidSlot(AndroidSlot8.self, in: assigned)
        androidSlot(AndroidSlot9.self, in: assigned)
        androidSlot(AndroidSlot10.self, in: assigned)
        androidSlot(AndroidSlot11.self, in: assigned)
    }
}
