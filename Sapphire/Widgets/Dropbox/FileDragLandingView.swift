//
//  FileDragLandingView.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-08-12.
//

import SwiftUI
import UniformTypeIdentifiers
import AppKit

extension Notification.Name { static let fileDropFlowCompleted = Notification.Name("fileDropFlowCompleted") }

struct DropZonePreferenceKey: PreferenceKey {
    typealias Value = [DropZone: CGRect]
    static var defaultValue: Value = [:]
    static func reduce(value: inout Value, nextValue: () -> Value) {
        value.merge(nextValue()) { $1 }
    }
}

// MARK: - View Definitions

enum DropZone: Hashable {
    case shelf
    case airdrop
    case device(String)
}

enum FileDragMode {
    case newFile
    case existingFile
}

struct FileDragLandingView: View {
    private static let cardWidth: CGFloat = 237.5
    private static let cardHeight: CGFloat = 120
    private static let cardSpacing: CGFloat = 15

    let mode: FileDragMode
    @Binding var activeZone: DropZone?
    let onZoneFramesChange: ([DropZone: CGRect]) -> Void

    @ObservedObject private var settings = SettingsModel.shared
    @State private var zoneFrames: [DropZone: CGRect] = [:]

    var body: some View {
        HStack(spacing: Self.cardSpacing) {
            if mode == .newFile {
                standardCard(
                    zone: .shelf,
                    icon: "tray.and.arrow.down.fill",
                    text: "Add to Shelf"
                )
            }

            if settings.settings.fileShelfAirDropDestinationEnabled {
                standardCard(
                    zone: .airdrop,
                    icon: "airplayaudio",
                    text: "AirDrop"
                )
            }

            if settings.settings.fileShelfDeviceDestinationsEnabled {
                ContinuityDeviceDropZone(
                    activeZone: activeZone,
                    cardWidth: Self.cardWidth,
                    cardHeight: Self.cardHeight
                )
            }

            if destinationCardCount == 0 {
                EmptyDropZoneView()
                    .frame(width: Self.cardWidth, height: Self.cardHeight)
            }
        }
        .padding(15)
        .frame(width: landingWidth, height: 150)
        .background {
            FileDropHitTestObserver(
                zoneFrames: zoneFrames,
                onActiveZoneChange: { zone in
                    if activeZone != zone { activeZone = zone }
                }
            )
        }
        .onPreferenceChange(DropZonePreferenceKey.self) { frames in
            guard zoneFrames != frames else { return }
            zoneFrames = frames
            onZoneFramesChange(frames)
        }
        .onAppear {
            onZoneFramesChange(zoneFrames)
        }
        .onDisappear {
            activeZone = nil
            onZoneFramesChange([:])
        }
    }

    private var destinationCardCount: Int {
        (mode == .newFile ? 1 : 0)
            + (settings.settings.fileShelfAirDropDestinationEnabled ? 1 : 0)
            + (settings.settings.fileShelfDeviceDestinationsEnabled ? 1 : 0)
    }

    private var landingWidth: CGFloat {
        let visibleCards = max(destinationCardCount, 1)
        let contentWidth = CGFloat(visibleCards) * Self.cardWidth
            + CGFloat(max(visibleCards - 1, 0)) * Self.cardSpacing
            + 30
        return contentWidth
    }

    private func standardCard(zone: DropZone, icon: String, text: String) -> some View {
        GeometryReader { geometry in
            DropZoneView(
                zone: zone,
                icon: icon,
                text: text,
                isTargeted: activeZone == zone
            )
            .preference(
                key: DropZonePreferenceKey.self,
                value: [zone: geometry.frame(in: .global)]
            )
        }
        .frame(width: Self.cardWidth, height: Self.cardHeight)
        .id(zone)
    }

}

private struct FileDropHitTestObserver: View {
    @EnvironmentObject private var dragLocation: NotchDragLocationState

    let zoneFrames: [DropZone: CGRect]
    let onActiveZoneChange: (DropZone?) -> Void

    @State private var lastZone: DropZone?

    var body: some View {
        Color.clear
            .onAppear { updateActiveState(at: dragLocation.location) }
            .onChange(of: dragLocation.location) { _, location in
                updateActiveState(at: location)
            }
            .onChange(of: zoneFrames) { _, _ in
                updateActiveState(at: dragLocation.location)
            }
            .onDisappear { publish(nil) }
    }

    private func updateActiveState(at point: CGPoint?) {
        guard let point, !zoneFrames.isEmpty else {
            publish(nil)
            return
        }

        let totalFrame = zoneFrames.values.reduce(CGRect.null) { $0.union($1) }
        guard totalFrame.insetBy(dx: -50, dy: -50).contains(point) else {
            publish(nil)
            return
        }

        let candidates = zoneFrames.map { (zone: $0.key, frame: $0.value) }
        publish(SnapZoneHitTesting.nearest(candidates, to: point) { $0.frame }?.zone)
    }

    private func publish(_ zone: DropZone?) {
        guard lastZone != zone else { return }
        lastZone = zone
        onActiveZoneChange(zone)
    }
}

private struct ContinuityDeviceDropZone: View {
    @ObservedObject private var continuity = ContinuityManager.shared

    let activeZone: DropZone?
    let cardWidth: CGFloat
    let cardHeight: CGFloat

    var body: some View {
        DeviceDropZoneView(
            peers: continuity.peers.filter { $0.supports(.files) },
            activeZone: activeZone,
            cardWidth: cardWidth,
            cardHeight: cardHeight
        )
    }
}

private struct DeviceDropZoneView: View {
    let peers: [ContinuityPeer]
    let activeZone: DropZone?
    let cardWidth: CGFloat
    let cardHeight: CGFloat

    private var isTargeted: Bool {
        guard case .device = activeZone else { return false }
        return true
    }

    private var columns: [GridItem] {
        let count: Int
        switch peers.count {
        case 0, 1: count = 1
        case 2, 3: count = peers.count
        default: count = min(4, Int(ceil(Double(peers.count) / 2.0)))
        }
        return Array(repeating: GridItem(.flexible(), spacing: 6), count: count)
    }

    var body: some View {
        VStack(spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: "rectangle.connected.to.line.below")
                Text("Share to Devices")
                    .lineLimit(1)
            }
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(isTargeted ? .white : .secondary)

            if peers.isEmpty {
                VStack(spacing: 3) {
                    Image(systemName: "iphone.slash")
                        .font(.system(size: 20, weight: .light))
                    Text("No paired devices")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                }
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical) {
                    LazyVGrid(columns: columns, spacing: 6) {
                        ForEach(peers) { peer in
                            DeviceDropCell(
                                peer: peer,
                                isTargeted: activeZone == .device(peer.id)
                            )
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
        .padding(10)
        .frame(width: cardWidth, height: cardHeight)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(isTargeted ? Color.accentColor.opacity(0.28) : Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(isTargeted ? Color.accentColor : Color.white.opacity(0.2), lineWidth: 1.5)
        )
        .scaleEffect(isTargeted ? 1.03 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.6), value: isTargeted)
    }
}

private struct DeviceDropCell: View {
    @ObservedObject var peer: ContinuityPeer
    let isTargeted: Bool

    private var zone: DropZone { .device(peer.id) }
    private var isEnabled: Bool { peer.linkState.isUsable }

    var body: some View {
        VStack(spacing: 2) {
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: peer.record.deviceType.glyph)
                    .font(.system(size: 16, weight: .medium))
                Circle()
                    .fill(isEnabled ? Color.green : Color.secondary)
                    .frame(width: 5, height: 5)
                    .overlay(Circle().stroke(Color.black.opacity(0.6), lineWidth: 1))
            }
            Text(peer.displayName)
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .foregroundStyle(isTargeted ? Color.white : (isEnabled ? Color.secondary : Color.secondary.opacity(0.45)))
        .frame(maxWidth: .infinity, minHeight: 42)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isTargeted ? Color.accentColor.opacity(0.85) : Color.white.opacity(isEnabled ? 0.06 : 0.025))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(isTargeted ? Color.white.opacity(0.6) : Color.clear, lineWidth: 1)
        )
        .background {
            GeometryReader { geometry in
                Color.clear.preference(
                    key: DropZonePreferenceKey.self,
                    value: isEnabled ? [zone: geometry.frame(in: .global)] : [:]
                )
            }
        }
        .scaleEffect(isTargeted ? 1.04 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.65), value: isTargeted)
        .help(isEnabled ? "Send to \(peer.displayName)" : "\(peer.displayName) is offline")
    }
}

private struct EmptyDropZoneView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 25, weight: .light))
            Text("No destinations enabled")
                .font(.system(.headline, design: .rounded).weight(.medium))
            Text("Choose destinations in File Shelf settings")
                .font(.system(size: 10, design: .rounded))
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.white.opacity(0.15), lineWidth: 1.5)
        )
    }
}

private struct DropZoneView: View {
    let zone: DropZone
    let icon: String
    let text: String
    let isTargeted: Bool
    private var isDashed: Bool { zone == .shelf }

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 28, weight: .light))
            Text(text).font(.system(.headline, design: .rounded).weight(.medium))
        }
        .foregroundColor(isTargeted ? .white : .secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            ZStack {
                if isDashed {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(isTargeted ? Color.white.opacity(0.1) : .clear)
                } else {
                     RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(isTargeted ? Color.accentColor.opacity(0.8) : Color.white.opacity(0.05))
                }
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: isDashed ? [8] : []), antialiased: true)
                .foregroundColor(isTargeted ? .accentColor : .white.opacity(0.2))
        )
        .scaleEffect(isTargeted ? 1.03 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.6), value: isTargeted)
    }
}

// MARK: - File Provider Conversion Logic

fileprivate let temporaryDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent(Bundle.main.bundleIdentifier ?? "com.shariq.Sapphire")

enum FileProviderError: Error, LocalizedError {
    case loadingFailed, noValidURLFound, duplicationFailed(Error)
    var errorDescription: String? {
        switch self {
        case .loadingFailed: return "Failed to load data from the item provider."
        case .noValidURLFound: return "Could not retrieve a valid file URL from the dropped item."
        case .duplicationFailed(let e): return "Failed to copy the file: \(e.localizedDescription)"
        }
    }
}

extension NSItemProvider {
    private func loadURL() async throws -> URL {
        try await withCheckedThrowingContinuation { c in
            _ = self.loadObject(ofClass: URL.self) { url, err in
                if let e = err { c.resume(throwing: e) }
                else if let u = url { c.resume(returning: u) }
                else { c.resume(throwing: FileProviderError.loadingFailed) }
            }
        }
    }
    private func loadInPlaceFile() async throws -> URL {
        try await withCheckedThrowingContinuation { c in
            self.loadInPlaceFileRepresentation(forTypeIdentifier: UTType.data.identifier) { url, _, err in
                if let e = err { c.resume(throwing: e) }
                else if let u = url { c.resume(returning: u) }
                else { c.resume(throwing: FileProviderError.loadingFailed) }
            }
        }
    }
    private func duplicateToTempStorage(_ url: URL) throws -> URL {
        let tempSubdir = temporaryDirectory.appendingPathComponent("TemporaryDrop").appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempSubdir, withIntermediateDirectories: true)
        let destination = tempSubdir.appendingPathComponent(url.lastPathComponent)
        try FileManager.default.copyItem(at: url, to: destination)
        return destination
    }
    func convertToAccessibleURL() async throws -> URL {
        var sourceURL: URL?
        if let url = try? await self.loadURL() { sourceURL = url }
        else if let url = try? await self.loadInPlaceFile() { sourceURL = url }
        guard let finalURL = sourceURL else { throw FileProviderError.noValidURLFound }
        do { return try duplicateToTempStorage(finalURL) }
        catch { throw FileProviderError.duplicationFailed(error) }
    }
}

extension [NSItemProvider] {
    func interfaceConvert() async throws -> [URL] {
        let urls = try await withThrowingTaskGroup(of: URL.self, returning: [URL].self) { group in
            for provider in self {
                group.addTask { try await provider.convertToAccessibleURL() }
            }
            var collectedURLs: [URL] = []
            for try await url in group { collectedURLs.append(url) }
            return collectedURLs
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 5.0) {
             try? FileManager.default.removeItem(at: temporaryDirectory.appendingPathComponent("TemporaryDrop"))
        }
        return urls
    }
}