//
//  SnapZonesWidgetView.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-08-14
//

import SwiftUI
import UniformTypeIdentifiers

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

fileprivate struct HandleItemDropKey: EnvironmentKey {
    static let defaultValue: ([NSItemProvider]) -> Bool = { _ in false }
}

extension EnvironmentValues {
    var handleItemDrop: ([NSItemProvider]) -> Bool {
        get { self[HandleItemDropKey.self] }
        set { self[HandleItemDropKey.self] = newValue }
    }
}

struct SnapZonesWidgetView: View {
    let onDragEnd: () -> Void
    @EnvironmentObject var settings: SettingsModel
    @Environment(\.handleItemDrop) private var handleItemDrop: ([NSItemProvider]) -> Bool

    @State private var activeHover: HoverState?
    @State private var layoutFrames: [UUID: CGRect] = [:]
    @State private var pollingTimer: Timer?
    @State private var mouseUpMonitor: Any?
    @State private var previewUpdateTask: Task<Void, Never>?
    @Environment(\.isFileDropTargeted) private var isFileDropTargeted: Binding<Bool>

    private var viewConfiguration: (layouts: [SnapLayout], isSingleMode: Bool) {
        let allAvailableLayouts = LayoutTemplate.allTemplates + settings.settings.customSnapLayouts
        let frontmostApp = NSWorkspace.shared.runningApplications.first { $0.isActive && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
        if let bundleID = frontmostApp?.bundleIdentifier,
           let appConfig = settings.settings.appSpecificLayoutConfigurations[bundleID] {
            switch appConfig {
            case .useGlobalDefault:
                break
            case .single(let layoutID):
                if let layout = allAvailableLayouts.first(where: { $0.id == layoutID }) {
                    return ([layout], true)
                }
            case .multi(let layoutIDs):
                let layouts = layoutIDs.compactMap { id in allAvailableLayouts.first { $0.id == id } }
                let finalLayouts = layouts.isEmpty ? [settings.settings.defaultSnapLayout] : layouts
                return (finalLayouts, finalLayouts.count == 1)
            }
        }

        switch settings.settings.snapZoneViewMode {
        case .multi:
            let multiLayouts = settings.settings.snapZoneLayoutOptions.compactMap { id in
                allAvailableLayouts.first { $0.id == id }
            }
            let finalLayouts = multiLayouts.isEmpty ? [settings.settings.defaultSnapLayout] : multiLayouts
            return (finalLayouts, finalLayouts.count == 1)
        case .single:
            return ([settings.settings.defaultSnapLayout], true)
        }
    }

    private var itemWidth: CGFloat { viewConfiguration.isSingleMode ? 220 : 120 }
    private var itemHeight: CGFloat { viewConfiguration.isSingleMode ? 220 * (9 / 16) : 120 * (9 / 16) }
    private var spacing: CGFloat { viewConfiguration.isSingleMode ? 0 : 12 }
    private var verticalPadding: CGFloat { 0 }
    private var labelHeight: CGFloat { 20 }

    private var totalWidgetWidth: CGFloat {
        let itemCount = CGFloat(viewConfiguration.layouts.count)
        let horizontalPadding: CGFloat = 20
        return (itemWidth * itemCount) + (spacing * max(0, itemCount - 1)) + (horizontalPadding * 2)
    }

    private var totalWidgetHeight: CGFloat {
        itemHeight + labelHeight + (verticalPadding * 2)
    }

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(viewConfiguration.layouts) { layout in
                GeometryReader { geometry in
                    SnapLayoutItemView(
                        layout: layout,
                        activeZoneID: activeHover?.layoutID == layout.id ? activeHover?.zoneID : nil,
                        itemWidth: self.itemWidth,
                        itemHeight: self.itemHeight
                    )
                    .frame(width: itemWidth, height: itemHeight + labelHeight)
                    .preference(
                        key: LayoutFramePreferenceKey.self,
                        value: [layout.id: geometry.frame(in: .global)]
                    )
                }
                .frame(width: itemWidth, height: itemHeight + labelHeight)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, verticalPadding)
        .frame(width: totalWidgetWidth, height: totalWidgetHeight)
        .background(Color.clear)
        .fixedSize(horizontal: true, vertical: true)
        .onPreferenceChange(LayoutFramePreferenceKey.self) { frames in
            self.layoutFrames = frames
        }
        .onDrop(of: [UTType.fileURL, .plainText], isTargeted: isFileDropTargeted, perform: handleItemDrop)
        .onAppear(perform: startMonitoring)
        .onDisappear(perform: stopMonitoring)
        .onChange(of: activeHover) { _, newHover in
            previewUpdateTask?.cancel()
            previewUpdateTask = Task {
                do {
                    try await Task.sleep(for: .milliseconds(50))

                    guard !Task.isCancelled else { return }

                    if let hover = newHover,
                       let layout = viewConfiguration.layouts.first(where: { $0.id == hover.layoutID }),
                       let zone = layout.zones.first(where: { $0.id == hover.zoneID }) {
                        SnapPreviewManager.shared.showPreview(for: zone)
                    } else {
                        SnapPreviewManager.shared.hidePreview()
                    }
                } catch {}
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: viewConfiguration.layouts)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: viewConfiguration.isSingleMode)
    }

    private func startMonitoring() {
        stopMonitoring()

        mouseUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [self] _ in
            if let hover = self.activeHover,
               let layout = self.viewConfiguration.layouts.first(where: { $0.id == hover.layoutID }),
               let zone = layout.zones.first(where: { $0.id == hover.zoneID }) {
                SnappingManager.snap(zone: zone)
            }
            self.onDragEnd()
            self.stopMonitoring()
        }

        pollingTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { _ in
            self.updateActiveState()
        }
    }

    private func stopMonitoring() {
        pollingTimer?.invalidate()
        pollingTimer = nil

        if let monitor = mouseUpMonitor {
            NSEvent.removeMonitor(monitor)
            mouseUpMonitor = nil
        }

        previewUpdateTask?.cancel()

        SnapPreviewManager.shared.hidePreview()

        activeHover = nil
    }

    private func updateActiveState() {
        guard let screen = NSScreen.main else { return }

        let mouseLocation = NSEvent.mouseLocation
        let globalMousePoint = CGPoint(x: mouseLocation.x, y: screen.frame.height - mouseLocation.y)

        if !layoutFrames.isEmpty {
            let totalWidgetFrame = layoutFrames.values.reduce(CGRect.null) { $0.union($1) }
            if !totalWidgetFrame.insetBy(dx: -50, dy: -50).contains(globalMousePoint) {
                if activeHover != nil { activeHover = nil }
                return
            }
        }

        var newHover: HoverState? = nil

        var closestZone: (layoutID: UUID, zoneID: UUID, distance: CGFloat)? = nil

        for (layoutID, frame) in layoutFrames {
            if frame.contains(globalMousePoint) {
                if let layout = viewConfiguration.layouts.first(where: { $0.id == layoutID }) {
                    let localPoint = CGPoint(x: globalMousePoint.x - frame.minX, y: globalMousePoint.y - frame.minY)

                    for zone in layout.zones {
                        let zoneFrame = CGRect(
                            x: itemWidth * zone.x,
                            y: itemHeight * zone.y,
                            width: itemWidth * zone.width,
                            height: itemHeight * zone.height
                        )
                        let zoneCenter = CGPoint(x: zoneFrame.midX, y: zoneFrame.midY)

                        let distanceSquared = pow(localPoint.x - zoneCenter.x, 2) + pow(localPoint.y - zoneCenter.y, 2)

                        if closestZone == nil || distanceSquared < closestZone!.distance {
                            closestZone = (layoutID: layoutID, zoneID: zone.id, distance: distanceSquared)
                        }
                    }
                }
            }
        }

        if let foundZone = closestZone {
            newHover = HoverState(layoutID: foundZone.layoutID, zoneID: foundZone.zoneID)
        }

        guard activeHover != newHover else { return }

        activeHover = newHover
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