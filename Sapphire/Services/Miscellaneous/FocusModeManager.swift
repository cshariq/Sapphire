//
//  FocusModeManager.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-10-07
//

import Foundation
import Combine
import AppKit
import Intents

// MARK: - 1. Public-Facing Data Models & Conversion Logic

public struct FocusStatus: Equatable, Sendable {
    public let name: String
    public let symbolName: String
    public let isActive: Bool
    public let identifier: String
    public let tintColorName: String?
    public let tintColorNames: [String]?

    public static let notActive = FocusStatus(
        name: "None",
        symbolName: "moon.zzz.fill",
        isActive: false,
        identifier: "com.apple.focus.none",
        tintColorName: nil,
        tintColorNames: nil
    )
}

struct FocusModeInfo: Equatable, Hashable, Identifiable {
    public let name: String
    public let identifier: String
    public let symbolName: String
    public let tintColorName: String?
    public let tintColorNames: [String]?
    public var isActive: Bool

    public var id: String { identifier }
}

extension FocusStatus {
    func toFocusModeInfo(isActive: Bool) -> FocusModeInfo {
        return FocusModeInfo(
            name: self.name,
            identifier: self.identifier,
            symbolName: self.symbolName,
            tintColorName: self.tintColorName,
            tintColorNames: self.tintColorNames,
            isActive: isActive
        )
    }
}

// MARK: - 2. The Focus Mode Manager (Continuous File Polling)

@MainActor
class FocusModeManager: NSObject, ObservableObject {
    static let shared = FocusModeManager()

    @Published private(set) var currentStatus: FocusStatus = .notActive

    private var cancellables = Set<AnyCancellable>()
    private var directoryMonitor: DirectoryMonitor?
    private var focusStatusObserver: NSObjectProtocol?
    private var refreshTask: Task<Void, Never>?
    private var refreshGeneration: UInt = 0

    private let assertionsURL: URL
    private let modesURL: URL
    private let monitorDirectoryURL: URL

    override init() {
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
        self.assertionsURL = homeDirectory.appendingPathComponent("Library/DoNotDisturb/DB/Assertions.json")
        self.modesURL = homeDirectory.appendingPathComponent("Library/DoNotDisturb/DB/ModeConfigurations.json")
        self.monitorDirectoryURL = homeDirectory.appendingPathComponent("Library/DoNotDisturb/DB")
        super.init()
        setupFocusMonitoring()
        scheduleFocusRefresh(debounce: false)
    }

    private func setupFocusMonitoring() {
        let monitor = DirectoryMonitor(url: monitorDirectoryURL)
        directoryMonitor = monitor

        monitor.fileDidChangePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.scheduleFocusRefresh()
            }
            .store(in: &cancellables)

        monitor.start()

        focusStatusObserver = NotificationCenter.default.addObserver(
            forName: .sapphireFocusStatusDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.scheduleFocusRefresh(debounce: false)
        }
    }

    func refreshNow() {
        scheduleFocusRefresh(debounce: false)
    }

    private func scheduleFocusRefresh(debounce: Bool = true) {
        refreshGeneration &+= 1
        let generation = refreshGeneration
        let assertionsURL = assertionsURL
        let modesURL = modesURL
        refreshTask?.cancel()

        refreshTask = Task { @MainActor [weak self] in
            if debounce {
                do {
                    try await Task.sleep(for: .milliseconds(120))
                } catch {
                    return
                }
            }

            let snapshot = await Task.detached(priority: .utility) {
                try? Self.readFocusSnapshot(assertionsURL: assertionsURL, modesURL: modesURL)
            }.value

            guard let self, !Task.isCancelled, self.refreshGeneration == generation else { return }
            self.refreshTask = nil
            self.applyResolvedStatus(fileStatus: snapshot?.status)
        }
    }

    nonisolated private static func readFocusSnapshot(
        assertionsURL: URL,
        modesURL: URL
    ) throws -> FocusFileSnapshot {
        let assertionsData = try Data(contentsOf: assertionsURL, options: .mappedIfSafe)
        let assertions = try JSONDecoder().decode(Assertions.self, from: assertionsData)
        let activeIdentifier = assertions.data.first?.storeAssertionRecords
            .max(by: { $0.assertionStartDateTimestamp < $1.assertionStartDateTimestamp })?
            .assertionDetails.assertionDetailsModeIdentifier

        guard let activeIdentifier else {
            return FocusFileSnapshot(status: .notActive)
        }

        let modesData = try Data(contentsOf: modesURL, options: .mappedIfSafe)
        let configurations = try JSONDecoder().decode(ModeConfigurations.self, from: modesData)
        guard let mode = configurations.data.first?.modeConfigurations[activeIdentifier]?.mode else {
            return FocusFileSnapshot(status: .notActive)
        }

        return FocusFileSnapshot(
            status: FocusStatus(
                name: mode.name,
                symbolName: mode.symbolImageName ?? "questionmark.circle",
                isActive: true,
                identifier: mode.modeIdentifier,
                tintColorName: mode.tintColorName,
                tintColorNames: mode.symbolDescriptorTintColorNames
            )
        )
    }

    private func applyResolvedStatus(fileStatus: FocusStatus?) {
        let intentFocused: Bool? = {
            guard INFocusStatusCenter.default.authorizationStatus == .authorized else { return nil }
            return INFocusStatusCenter.default.focusStatus.isFocused
        }()

        let resolved: FocusStatus
        if let fileStatus, fileStatus.isActive {
            resolved = fileStatus
        } else if intentFocused == true {
            resolved = FocusStatus(
                name: fileStatus?.name == "None" || fileStatus == nil ? "Focus" : (fileStatus?.name ?? "Focus"),
                symbolName: fileStatus?.symbolName ?? "moon.fill",
                isActive: true,
                identifier: fileStatus?.identifier ?? "com.apple.focus.active",
                tintColorName: fileStatus?.tintColorName,
                tintColorNames: fileStatus?.tintColorNames
            )
        } else if let fileStatus {
            resolved = fileStatus
        } else if intentFocused == false {
            resolved = .notActive
        } else {
            return
        }

        if currentStatus != resolved {
            currentStatus = resolved
        }
    }

    deinit {
        refreshTask?.cancel()
        directoryMonitor?.stop()
        if let focusStatusObserver {
            NotificationCenter.default.removeObserver(focusStatusObserver)
        }
        cancellables.forEach { $0.cancel() }
        cancellables.removeAll()
    }
}

private struct FocusFileSnapshot: Sendable {
    let status: FocusStatus
}

// MARK: - 3. Private Data Models for JSON Parsing

private struct ModeConfigurations: Decodable {
    let data: [ModeConfigurationsData]
}

private struct ModeConfigurationsData: Decodable {
    let modeConfigurations: [String: ModeConfiguration]
}

private struct ModeConfiguration: Decodable {
    let mode: Mode
}

private struct Mode: Decodable {
    let name: String
    let modeIdentifier: String
    let symbolImageName: String?
    let tintColorName: String?
    let symbolDescriptorTintColorNames: [String]?
}

private struct Assertions: Decodable {
    let data: [AssertionData]
}

private struct AssertionData: Decodable {
    let storeAssertionRecords: [StoreAssertionRecord]
}

private struct StoreAssertionRecord: Decodable {
    let assertionDetails: AssertionDetails
    let assertionStartDateTimestamp: Double
}

private struct AssertionDetails: Decodable {
    let assertionDetailsModeIdentifier: String
}

extension Notification.Name {
    static let sapphireFocusStatusDidChange = Notification.Name("INFocusStatusDidChangeNotification")
}