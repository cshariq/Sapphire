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

    @ObservedSettings private var settings: SettingsObserver
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
                value: [zone: geometry.frame(in: .notchDrag)]
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
    private var continuity: ContinuityManager { .shared }

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
    private static let maxVisiblePeers = 6
    private static let cardRadius: CGFloat = 24
    private static let inset: CGFloat = 6

    let peers: [ContinuityPeer]
    let activeZone: DropZone?
    let cardWidth: CGFloat
    let cardHeight: CGFloat

    private var visiblePeers: [ContinuityPeer] {
        let usable = peers.filter { $0.linkState.isUsable }
        let unusable = peers.filter { !$0.linkState.isUsable }
        return Array((usable + unusable).prefix(Self.maxVisiblePeers))
    }

    private var isTargeted: Bool {
        guard case .device = activeZone else { return false }
        return true
    }

    var body: some View {
        let peers = visiblePeers
        Group {
            switch peers.count {
            case 0:
                emptyState
            case 1:
                DeviceDropTile(
                    peer: peers[0],
                    style: .card,
                    cornerRadius: Self.cardRadius,
                    isTargeted: activeZone == .device(peers[0].id)
                )
            default:
                tiles(for: peers)
                    .padding(Self.inset)
                    .background(
                        RoundedRectangle(cornerRadius: Self.cardRadius, style: .continuous)
                            .fill(isTargeted ? Color.accentColor.opacity(0.12) : Color.white.opacity(0.05))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Self.cardRadius, style: .continuous)
                            .strokeBorder(isTargeted ? Color.accentColor : Color.white.opacity(0.2), lineWidth: 1.5)
                    )
                    .animation(.spring(response: 0.2, dampingFraction: 0.6), value: isTargeted)
            }
        }
        .frame(width: cardWidth, height: cardHeight)
    }

    @ViewBuilder
    private func tiles(for peers: [ContinuityPeer]) -> some View {
        let radius = Self.cardRadius - Self.inset
        if peers.count <= 3 {
            HStack(spacing: Self.inset) {
                ForEach(peers) { peer in
                    DeviceDropTile(
                        peer: peer,
                        style: .column,
                        cornerRadius: radius,
                        isTargeted: activeZone == .device(peer.id)
                    )
                }
            }
        } else {
            let columns = Array(
                repeating: GridItem(.flexible(), spacing: Self.inset),
                count: Int(ceil(Double(peers.count) / 2))
            )
            LazyVGrid(columns: columns, spacing: Self.inset) {
                ForEach(peers) { peer in
                    DeviceDropTile(
                        peer: peer,
                        style: .compact,
                        cornerRadius: radius - 4,
                        isTargeted: activeZone == .device(peer.id)
                    )
                    .frame(height: (cardHeight - Self.inset * 3) / 2)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "iphone.slash")
                .font(.system(size: 26, weight: .light))
            Text("No Devices")
                .font(.system(.headline, design: .rounded).weight(.medium))
            Text("Pair one in Continuity settings")
                .font(.system(size: 10, design: .rounded))
        }
        .foregroundStyle(.tertiary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: Self.cardRadius, style: .continuous)
                .fill(Color.white.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Self.cardRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1.5)
        )
    }
}

private struct DeviceDropTile: View {
    enum Style { case card, column, compact }

    let peer: ContinuityPeer
    let style: Style
    let cornerRadius: CGFloat
    let isTargeted: Bool

    private var isEnabled: Bool { peer.linkState.isUsable }

    private var status: String {
        if isEnabled { return "Ready" }
        return peer.linkState == .nearby ? "Nearby" : "Offline"
    }

    private var foreground: Color {
        if isTargeted { return .white }
        return isEnabled ? .secondary : .secondary.opacity(0.45)
    }

    var body: some View {
        content
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(isTargeted ? Color.accentColor.opacity(0.8) : Color.white.opacity(fillOpacity))
            )
            .overlay {
                if style == .card {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(isTargeted ? Color.accentColor : Color.white.opacity(0.2), lineWidth: 1.5)
                }
            }
            .background {
                GeometryReader { geometry in
                    Color.clear.preference(
                        key: DropZonePreferenceKey.self,
                        value: isEnabled ? [.device(peer.id): geometry.frame(in: .notchDrag)] : [:]
                    )
                }
            }
            .scaleEffect(isTargeted ? (style == .card ? 1.03 : 1.04) : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: isTargeted)
            .help(isEnabled ? "Send to \(peer.displayName)" : "\(peer.displayName) is \(status.lowercased())")
    }

    private var fillOpacity: Double {
        switch style {
        case .card: 0.05
        case .column, .compact: isEnabled ? 0.07 : 0.03
        }
    }

    @ViewBuilder
    private var content: some View {
        switch style {
        case .card:
            VStack(spacing: 6) {
                Image(systemName: peer.record.deviceType.glyph)
                    .font(.system(size: 28, weight: .light))
                Text(peer.displayName)
                    .font(.system(.headline, design: .rounded).weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                statusLabel(size: 10)
            }
            .padding(.horizontal, 14)
        case .column:
            VStack(spacing: 5) {
                Image(systemName: peer.record.deviceType.glyph)
                    .font(.system(size: 22, weight: .light))
                    .frame(height: 26)
                Text(peer.displayName)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                statusLabel(size: 9)
            }
            .padding(.horizontal, 6)
        case .compact:
            HStack(spacing: 6) {
                Image(systemName: peer.record.deviceType.glyph)
                    .font(.system(size: 15, weight: .regular))
                    .frame(width: 18)
                Text(peer.displayName)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Spacer(minLength: 0)
                statusDot
            }
            .padding(.horizontal, 9)
        }
    }

    private func statusLabel(size: CGFloat) -> some View {
        HStack(spacing: 4) {
            statusDot
            Text(status)
                .font(.system(size: size, weight: .medium, design: .rounded))
        }
        .opacity(isTargeted ? 0.9 : 0.8)
    }

    private var statusDot: some View {
        Circle()
            .fill(isEnabled ? Color.green : Color.secondary.opacity(0.6))
            .frame(width: 5, height: 5)
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