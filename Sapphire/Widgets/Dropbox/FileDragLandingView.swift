//
//  FileDragLandingView.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-08-12.
//

import SwiftUI
import UniformTypeIdentifiers
import os.log

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
    case shelf, airdrop
}

enum FileDragMode {
    case newFile
    case existingFile
}

struct FileDragLandingView: View {
    let mode: FileDragMode
    @Binding var activeZone: DropZone?

    @Environment(\.navigationStack) private var navigationStack
    @EnvironmentObject private var dragState: DragStateManager

    var body: some View {
        ZStack {
            HStack(spacing: 15) {
                if mode == .newFile {
                    GeometryReader { geometry in
                        DropZoneView(
                            zone: .shelf,
                            icon: "tray.and.arrow.down.fill",
                            text: "Add to Shelf",
                            isTargeted: activeZone == .shelf
                        )
                        .preference(
                            key: DropZonePreferenceKey.self,
                            value: [.shelf: geometry.frame(in: .global)]
                        )
                    }
                    .id(DropZone.shelf)
                }

                GeometryReader { geometry in
                    DropZoneView(
                        zone: .airdrop,
                        icon: "airplayaudio",
                        text: "AirDrop",
                        isTargeted: activeZone == .airdrop
                    )
                    .preference(
                        key: DropZonePreferenceKey.self,
                        value: [.airdrop: geometry.frame(in: .global)]
                    )
                }
                .id(DropZone.airdrop)
            }
        }
        .padding(15)
        .frame(width: mode == .newFile ? 550 : 250, height: 140)
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
            Image(systemName: icon).font(.system(size: 28, weight: .light))
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