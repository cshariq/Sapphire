//
//  FocusModeManager.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-10-07
//

import Foundation
import Combine
import AppKit

// MARK: - 1. Public-Facing Data Models & Conversion Logic

public struct FocusStatus: Equatable {
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
    @Published private(set) var currentStatus: FocusStatus = .notActive

    private var cancellables = Set<AnyCancellable>()
    private var lastKnownModeIdentifier: String?
    private var directoryMonitor: DirectoryMonitor?

    private let assertionsURL: URL
    private let modesURL: URL
    private let monitorDirectoryURL: URL

    override init() {
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
        self.assertionsURL = homeDirectory.appendingPathComponent("Library/DoNotDisturb/DB/Assertions.json")
        self.modesURL = homeDirectory.appendingPathComponent("Library/DoNotDisturb/DB/ModeConfigurations.json")
        self.monitorDirectoryURL = homeDirectory.appendingPathComponent("Library/DoNotDisturb/DB")
        super.init()
        loadInitialFocusStatus()
        setupFocusMonitoring()
    }

    private func setupFocusMonitoring() {
        let monitor = DirectoryMonitor(url: monitorDirectoryURL)
        directoryMonitor = monitor

        monitor.fileDidChangePublisher
            .sink { [weak self] _ in
                self?.checkFocusFilesForChange()
            }
            .store(in: &cancellables)

        monitor.start()
    }

    private func loadInitialFocusStatus() {
        do {
            let assertionsData = try Data(contentsOf: assertionsURL)
            let assertions = try JSONDecoder().decode(Assertions.self, from: assertionsData)
            let latestAssertion = assertions.data.first?.storeAssertionRecords.max(by: { $0.assertionStartDateTimestamp < $1.assertionStartDateTimestamp })
            let activeModeIdentifier = latestAssertion?.assertionDetails.assertionDetailsModeIdentifier

            self.lastKnownModeIdentifier = activeModeIdentifier

            if let activeIdentifier = activeModeIdentifier {
                do {
                    let modesData = try Data(contentsOf: modesURL)
                    let modeConfigs = try JSONDecoder().decode(ModeConfigurations.self, from: modesData)

                    if let allModes = modeConfigs.data.first?.modeConfigurations,
                       let activeModeConfig = allModes[activeIdentifier] {

                        let mode = activeModeConfig.mode
                        let symbolName = mode.symbolImageName ?? "questionmark.circle"
                        let newStatus = FocusStatus(
                            name: mode.name,
                            symbolName: symbolName,
                            isActive: true,
                            identifier: mode.modeIdentifier,
                            tintColorName: mode.tintColorName,
                            tintColorNames: mode.symbolDescriptorTintColorNames
                        )

                        self.currentStatus = newStatus
                    } else {
                        self.currentStatus = .notActive
                    }
                } catch {
                    self.currentStatus = .notActive
                }
            } else {
                self.currentStatus = .notActive
            }
        } catch {
            self.lastKnownModeIdentifier = nil
            self.currentStatus = .notActive
        }
    }

    private func checkFocusFilesForChange() {
        do {
            let assertionsData = try Data(contentsOf: assertionsURL)
            let assertions = try JSONDecoder().decode(Assertions.self, from: assertionsData)
            let latestAssertion = assertions.data.first?.storeAssertionRecords.max(by: { $0.assertionStartDateTimestamp < $1.assertionStartDateTimestamp })
            let activeModeIdentifier = latestAssertion?.assertionDetails.assertionDetailsModeIdentifier

            if activeModeIdentifier != self.lastKnownModeIdentifier {
                self.lastKnownModeIdentifier = activeModeIdentifier
                updateFocusStatus(with: activeModeIdentifier)
            }
        } catch {
            if self.lastKnownModeIdentifier != nil {
                self.lastKnownModeIdentifier = nil
                updateFocusStatus(with: nil)
            }
        }
    }

    private func updateFocusStatus(with modeIdentifier: String?) {
        guard let activeIdentifier = modeIdentifier else {
            self.currentStatus = .notActive
            return
        }

        do {
            let modesData = try Data(contentsOf: modesURL)
            let modeConfigs = try JSONDecoder().decode(ModeConfigurations.self, from: modesData)

            if let allModes = modeConfigs.data.first?.modeConfigurations,
               let activeModeConfig = allModes[activeIdentifier] {

                let mode = activeModeConfig.mode
                let symbolName = mode.symbolImageName ?? "questionmark.circle"
                let newStatus = FocusStatus(
                    name: mode.name,
                    symbolName: symbolName,
                    isActive: true,
                    identifier: mode.modeIdentifier,
                    tintColorName: mode.tintColorName,
                    tintColorNames: mode.symbolDescriptorTintColorNames
                )

                self.currentStatus = newStatus
            }
        } catch {
            print("[FocusManager] ERROR: Failed to read ModeConfigurations file: \(error)")
        }
    }

    deinit {
        directoryMonitor?.stop()
        cancellables.forEach { $0.cancel() }
        cancellables.removeAll()
    }
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
