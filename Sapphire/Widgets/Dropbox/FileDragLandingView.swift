//
//  FileDragLandingView.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-08-12.
//
//
//
//
//

import SwiftUI
import UniformTypeIdentifiers
import os.log

extension Notification.Name { static let fileDropFlowCompleted = Notification.Name("fileDropFlowCompleted") }

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "FileDrop")

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

    @State private var isShelfTargeted: Bool = false
    @State private var isAirdropTargeted: Bool = false

    private var currentTarget: DropZone? {
        if isShelfTargeted { return .shelf }
        if isAirdropTargeted { return .airdrop }
        return nil
    }

    var body: some View {
        ZStack {
            HStack(spacing: 15) {
                if mode == .newFile {
                    DropZoneView(
                        zone: .shelf,
                        icon: "tray.and.arrow.down.fill",
                        text: "Add to Shelf",
                        isTargeted: $isShelfTargeted
                    )
                    .onDrop(of: [UTType.data], isTargeted: $isShelfTargeted) { providers in
                        logger.info("[Step 1] .onDrop triggered for Shelf zone.")
                        handleDrop(providers: providers, for: .shelf)
                        return true
                    }
                    .id(DropZone.shelf)
                }

                DropZoneView(
                    zone: .airdrop,
                    icon: "airplayaudio",
                    text: "AirDrop",
                    isTargeted: $isAirdropTargeted
                )
                .onDrop(of: [UTType.data], isTargeted: $isAirdropTargeted) { providers in
                        logger.info("[Step 1] .onDrop triggered for AirDrop zone.")
                        handleDrop(providers: providers, for: .airdrop)
                    return true
                }
                .id(DropZone.airdrop)
            }
        }
        .padding(15)
        .frame(width: mode == .newFile ? 550 : 250, height: 140)
        .onChange(of: currentTarget) { _, newTarget in
            activeZone = newTarget
        }
    }

    private func handleDrop(providers: [NSItemProvider], for zone: DropZone) {
        logger.info("[Step 2] handleDrop called for \(String(describing: zone)). Starting async Task.")
        Task {
            do {
                logger.info("[Step 3] Awaiting file URL conversion from \(providers.count) providers.")
                let urls = try await providers.interfaceConvert()
                logger.info("[Step 4] Successfully converted \(urls.count) items. URLs: \(urls.map { $0.lastPathComponent })")

                await MainActor.run {
                    logger.info("[Step 5] Updating UI on MainActor for zone: \(String(describing: zone)).")
                    self.dragState.didJustDrop = true

                    switch zone {
                    case .shelf:
                        FileShelfManager.shared.addFiles(from: urls)
                        self.navigationStack.wrappedValue = [.fileShelf]

                    case .airdrop:
                        SharingManager.shared.share(items: urls, via: .sendViaAirDrop)
                        self.navigationStack.wrappedValue = []
                    }

                    NotificationCenter.default.post(name: .fileDropFlowCompleted, object: nil)
                    logger.info("[Step 6] UI update complete.")
                }
            } catch {
                logger.error(" [ERROR] Processing dropped files failed: \(error.localizedDescription)")
                await MainActor.run {
                     let alert = NSAlert()
                     alert.messageText = "Drop Failed"
                     alert.informativeText = "Could not process the dropped items. Please try again.\n\nDetails: \(error.localizedDescription)"
                     alert.alertStyle = .warning
                     alert.runModal()
                }
            }
        }
    }
}

private struct DropZoneView: View {
    let zone: DropZone
    let icon: String
    let text: String
    @Binding var isTargeted: Bool
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