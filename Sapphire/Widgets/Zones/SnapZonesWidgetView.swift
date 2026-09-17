//
//  SnapZonesWidgetView.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-08-14
//

import AppKit
import Combine
import SwiftUI

struct SnapZoneHitRegion: Equatable {
    let frame: CGRect
    let zone: SnapZone
}

fileprivate struct LayoutFramePreferenceKey: PreferenceKey {
    typealias Value = [UUID: CGRect]
    static var defaultValue: Value = [:]
    static func reduce(value: inout Value, nextValue: () -> Value) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

fileprivate struct HoverState: Equatable {
    let layoutID: UUID
    let zoneID: UUID
}

fileprivate struct SnapZoneViewConfiguration: Equatable {
    let layouts: [SnapLayout]
    let isSingleMode: Bool
}

fileprivate struct SnapZoneViewMetrics {
    let itemWidth: CGFloat
    let itemHeight: CGFloat
    let spacing: CGFloat
    let labelHeight: CGFloat = 20

    init(isSingleMode: Bool) {
        itemWidth = isSingleMode ? 220 : 120
        itemHeight = itemWidth * (9 / 16)
        spacing = isSingleMode ? 0 : 12
    }

    func totalWidth(itemCount: Int) -> CGFloat {
        let count = CGFloat(itemCount)
        return (itemWidth * count) + (spacing * max(0, count - 1)) + 40
    }

    var totalHeight: CGFloat { itemHeight + labelHeight }
}

struct SnapZonesWidgetView: View {
    let onActiveZoneChange: (SnapZone?) -> Void
    let onHitRegionsChange: ([SnapZoneHitRegion]) -> Void
    @EnvironmentObject var settings: SettingsModel
    @State private var activeHover: HoverState?
    @State private var layoutFrames: [UUID: CGRect] = [:]
    @State private var previewUpdateTask: Task<Void, Never>?
    @State private var frontmostBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier

    private var viewConfiguration: SnapZoneViewConfiguration {
        let current = settings.settings
        let allAvailableLayouts = LayoutTemplate.allTemplates + current.customSnapLayouts
        let layoutsByID = allAvailableLayouts.reduce(into: [UUID: SnapLayout]()) { result, layout in
            result[layout.id] = layout
        }
        if let bundleID = frontmostBundleID,
           bundleID != Bundle.main.bundleIdentifier,
           let appConfig = current.appSpecificLayoutConfigurations[bundleID] {
            switch appConfig {
            case .useGlobalDefault:
                break
            case .single(let layoutID):
                if let layout = layoutsByID[layoutID] {
                    return SnapZoneViewConfiguration(layouts: [layout], isSingleMode: true)
                }
            case .multi(let layoutIDs):
                let layouts = layoutIDs.compactMap { layoutsByID[$0] }
                let finalLayouts = layouts.isEmpty ? [current.defaultSnapLayout] : layouts
                return SnapZoneViewConfiguration(layouts: finalLayouts, isSingleMode: finalLayouts.count == 1)
            }
        }

        switch current.snapZoneViewMode {
        case .multi:
            let multiLayouts = current.snapZoneLayoutOptions.compactMap { layoutsByID[$0] }
            let finalLayouts = multiLayouts.isEmpty ? [current.defaultSnapLayout] : multiLayouts
            return SnapZoneViewConfiguration(layouts: finalLayouts, isSingleMode: finalLayouts.count == 1)
        case .single:
            return SnapZoneViewConfiguration(layouts: [current.defaultSnapLayout], isSingleMode: true)
        }
    }

    var body: some View {
        let configuration = viewConfiguration
        let metrics = SnapZoneViewMetrics(isSingleMode: configuration.isSingleMode)

        HStack(spacing: metrics.spacing) {
            ForEach(configuration.layouts) { layout in
                GeometryReader { geometry in
                    SnapLayoutItemView(
                        layout: layout,
                        activeZoneID: activeHover?.layoutID == layout.id ? activeHover?.zoneID : nil,
                        itemWidth: metrics.itemWidth,
                        itemHeight: metrics.itemHeight
                    )
                    .frame(width: metrics.itemWidth, height: metrics.itemHeight + metrics.labelHeight)
                    .preference(
                        key: LayoutFramePreferenceKey.self,
                        value: [layout.id: geometry.frame(in: .global)]
                    )
                }
                .frame(width: metrics.itemWidth, height: metrics.itemHeight + metrics.labelHeight)
            }
        }
        .padding(.horizontal, 20)
        .frame(
            width: metrics.totalWidth(itemCount: configuration.layouts.count),
            height: metrics.totalHeight
        )
        .background(Color.clear)
        .background {
            SnapZoneHitTestObserver(
                configuration: configuration,
                layoutFrames: layoutFrames,
                onHoverChange: { hover in
                    if activeHover != hover { activeHover = hover }
                }
            )
        }
        .fixedSize(horizontal: true, vertical: true)
        .onPreferenceChange(LayoutFramePreferenceKey.self) { frames in
            guard layoutFrames != frames else { return }
            layoutFrames = frames
            publishHitRegions(configuration: configuration, metrics: metrics)
        }
        .onAppear {
            publishHitRegions(configuration: configuration, metrics: metrics)
        }
        .onDisappear(perform: resetInteractionState)
        .onChange(of: activeHover) { _, newHover in
            previewUpdateTask?.cancel()
            let zone = newHover.flatMap { hover in
                configuration.layouts
                    .first(where: { $0.id == hover.layoutID })?
                    .zones.first(where: { $0.id == hover.zoneID })
            }
            onActiveZoneChange(zone)
            previewUpdateTask = Task {
                do {
                    try await Task.sleep(for: .milliseconds(50))

                    guard !Task.isCancelled else { return }

                    if let zone {
                        SnapPreviewManager.shared.showPreview(for: zone)
                    } else {
                        SnapPreviewManager.shared.hidePreview()
                    }
                } catch {}
            }
        }
        .onChange(of: configuration) { _, _ in
            publishHitRegions(configuration: configuration, metrics: metrics)
        }
        .onReceive(
            NSWorkspace.shared.notificationCenter
                .publisher(for: NSWorkspace.didActivateApplicationNotification)
                .compactMap { notification in
                    (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?
                        .bundleIdentifier
                }
                .removeDuplicates()
        ) { bundleID in
            if frontmostBundleID != bundleID { frontmostBundleID = bundleID }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: configuration.layouts)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: configuration.isSingleMode)
    }

    private func resetInteractionState() {
        previewUpdateTask?.cancel()
        previewUpdateTask = nil
        SnapPreviewManager.shared.hidePreview()
        onActiveZoneChange(nil)
        onHitRegionsChange([])
        activeHover = nil
    }

    private func publishHitRegions(
        configuration: SnapZoneViewConfiguration,
        metrics: SnapZoneViewMetrics
    ) {
        let regions = configuration.layouts.flatMap { layout -> [SnapZoneHitRegion] in
            guard let layoutFrame = layoutFrames[layout.id] else { return [] }
            return layout.zones.map { zone in
                SnapZoneHitRegion(
                    frame: CGRect(
                        x: layoutFrame.minX + metrics.itemWidth * zone.x,
                        y: layoutFrame.minY + metrics.itemHeight * zone.y,
                        width: metrics.itemWidth * zone.width,
                        height: metrics.itemHeight * zone.height
                    ),
                    zone: zone
                )
            }
        }
        onHitRegionsChange(regions)
    }

}

private struct SnapZoneHitTestObserver: View {
    @EnvironmentObject private var dragLocation: NotchDragLocationState

    let configuration: SnapZoneViewConfiguration
    let layoutFrames: [UUID: CGRect]
    let onHoverChange: (HoverState?) -> Void

    @State private var lastHover: HoverState?

    var body: some View {
        Color.clear
            .onAppear { updateActiveState(at: dragLocation.location) }
            .onChange(of: dragLocation.location) { _, location in
                updateActiveState(at: location)
            }
            .onChange(of: layoutFrames) { _, _ in
                updateActiveState(at: dragLocation.location)
            }
            .onChange(of: configuration) { _, _ in
                updateActiveState(at: dragLocation.location)
            }
            .onDisappear { publish(nil) }
    }

    private func updateActiveState(at point: CGPoint?) {
        guard let point, !layoutFrames.isEmpty else {
            publish(nil)
            return
        }

        let totalFrame = layoutFrames.values.reduce(CGRect.null) { $0.union($1) }
        guard totalFrame.insetBy(dx: -50, dy: -50).contains(point) else {
            publish(nil)
            return
        }

        let metrics = SnapZoneViewMetrics(isSingleMode: configuration.isSingleMode)
        var candidates: [(hover: HoverState, frame: CGRect)] = []
        for (layoutID, frame) in layoutFrames {
            guard let layout = configuration.layouts.first(where: { $0.id == layoutID }) else { continue }
            for zone in layout.zones {
                candidates.append((
                    hover: HoverState(layoutID: layoutID, zoneID: zone.id),
                    frame: CGRect(
                        x: frame.minX + metrics.itemWidth * zone.x,
                        y: frame.minY + metrics.itemHeight * zone.y,
                        width: metrics.itemWidth * zone.width,
                        height: metrics.itemHeight * zone.height
                    )
                ))
            }
        }
        publish(SnapZoneHitTesting.nearest(candidates, to: point) { $0.frame }?.hover)
    }

    private func publish(_ hover: HoverState?) {
        guard lastHover != hover else { return }
        lastHover = hover
        onHoverChange(hover)
    }
}

fileprivate struct SnapLayoutItemView: View {
    let layout: SnapLayout
    let activeZoneID: UUID?
    let itemWidth: CGFloat
    let itemHeight: CGFloat

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.05))
                    .shadow(color: .black.opacity(0.2), radius: 3, y: 1)

                ForEach(layout.zones) { zone in
                    SnapZoneItemView(isActive: zone.id == activeZoneID)
                        .frame(
                            width: (itemWidth * zone.width),
                            height: (itemHeight * zone.height)
                        )
                        .position(
                            x: (itemWidth * (zone.x + zone.width / 2)),
                            y: (itemHeight * (zone.y + zone.height / 2))
                        )
                }
            }

            Text(layout.name)
                .font(.system(size: 10))
                .fontWeight(.medium)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .padding(.horizontal, 2)
        }
    }
}

fileprivate struct SnapZoneItemView: View {
    let isActive: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(isActive ? Color.accentColor.opacity(0.7) : Color.white.opacity(0.1))
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(isActive ? Color.white.opacity(0.8) : Color.clear, lineWidth: 1.5)
            )
            .padding(1.5)
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isActive)
    }
}