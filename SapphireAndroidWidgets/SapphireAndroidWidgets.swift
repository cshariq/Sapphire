//
//  SapphireAndroidWidgets.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-15

import AppIntents
import AppKit
import SwiftUI
import WidgetKit

struct AndroidWidgetChoice: AppEntity, Identifiable {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Android Widget")
    static let defaultQuery = AndroidWidgetChoiceQuery()

    let id: String
    let label: String
    let provider: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(label)", subtitle: "Android widget")
    }

    init(snapshot: AndroidWidgetSnapshotRecord) {
        id = snapshot.id
        label = snapshot.label
        provider = snapshot.provider
    }
}

struct AndroidWidgetChoiceQuery: EntityQuery {
    func entities(for identifiers: [AndroidWidgetChoice.ID]) async throws -> [AndroidWidgetChoice] {
        let requested = Set(identifiers)
        return AndroidWidgetSnapshotStore.loadCatalog().snapshots
            .filter { requested.contains($0.id) }
            .map(AndroidWidgetChoice.init)
    }

    func suggestedEntities() async throws -> [AndroidWidgetChoice] {
        AndroidWidgetSnapshotStore.loadCatalog().snapshots.map(AndroidWidgetChoice.init)
    }

    func defaultResult() async -> AndroidWidgetChoice? {
        AndroidWidgetSnapshotStore.loadCatalog().snapshots.first.map(AndroidWidgetChoice.init)
    }
}

struct AndroidWidgetConfigurationIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Android Widget"
    static let description = IntentDescription("Choose a widget mirrored from your paired Android phone.")

    @Parameter(title: "Widget")
    var widget: AndroidWidgetChoice?
}

struct AndroidWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: AndroidWidgetSnapshotRecord?
    let imageData: Data?
}

struct AndroidWidgetTimelineProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> AndroidWidgetEntry {
        AndroidWidgetEntry(date: Date(), snapshot: nil, imageData: nil)
    }

    func snapshot(
        for configuration: AndroidWidgetConfigurationIntent,
        in context: Context
    ) async -> AndroidWidgetEntry {
        entry(for: configuration)
    }

    func timeline(
        for configuration: AndroidWidgetConfigurationIntent,
        in context: Context
    ) async -> Timeline<AndroidWidgetEntry> {
        Timeline(entries: [entry(for: configuration)], policy: .never)
    }

    private func entry(for configuration: AndroidWidgetConfigurationIntent) -> AndroidWidgetEntry {
        let catalog = AndroidWidgetSnapshotStore.loadCatalog()
        let snapshot: AndroidWidgetSnapshotRecord?
        if let selectedID = configuration.widget?.id {
            snapshot = catalog.snapshots.first { $0.id == selectedID }
        } else {
            snapshot = catalog.snapshots.first
        }
        return AndroidWidgetEntry(
            date: Date(),
            snapshot: snapshot,
            imageData: snapshot.flatMap { AndroidWidgetSnapshotStore.imageData(for: $0) }
        )
    }
}

struct AndroidWidgetEntryView: View {
    let entry: AndroidWidgetTimelineProvider.Entry

    var body: some View {
        Group {
            if let data = entry.imageData, let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "iphone.gen3.radiowaves.left.and.right")
                        .font(.system(size: 30, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(entry.snapshot == nil ? "Add an Android widget in Sapphire" : "Waiting for your phone")
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
                .padding()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerBackground(.fill.tertiary, for: .widget)
        .widgetURL(URL(string: "sapphire://android-widgets"))
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
        .configurationDisplayName("Android Widget")
        .description("Place a live widget from your paired Android phone on the Mac desktop or in Notification Center.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

@main
struct SapphireAndroidWidgetBundle: WidgetBundle {
    var body: some Widget {
        SapphireAndroidWidget()
    }
}