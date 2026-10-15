//
//  SettingsStorageTests.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-10-08

import Combine
import CoreGraphics
import Foundation
import Testing
@testable import Sapphire

// MARK: - Publish ordering

private final class OrderingProbe: ObservableObject {
    private(set) var mirror = 0
    @StoredThenPublished var value = 0 {
        willSet { mirror = newValue }
    }
}

@Suite("Settings publish ordering")
struct SettingsPublishOrderingTests {
    @Test func subscriberReadsTheStoredValue() {
        let probe = OrderingProbe()
        var seen: [(published: Int, stored: Int, mirror: Int)] = []
        let cancellable = probe.$value.dropFirst().sink { published in
            seen.append((published, probe.value, probe.mirror))
        }
        probe.value = 7
        probe.value = 9
        cancellable.cancel()

        #expect(seen.map(\.published) == [7, 9])
        #expect(seen.map(\.stored) == [7, 9])
        #expect(seen.map(\.mirror) == [7, 9])
    }

    @Test func publisherReplaysCurrentValueAndSendsObjectWillChangeOncePerWrite() {
        let probe = OrderingProbe()
        probe.value = 3
        var replayed: [Int] = []
        var invalidations = 0
        let replay = probe.$value.sink { replayed.append($0) }
        let invalidation = probe.objectWillChange.sink { invalidations += 1 }
        probe.value = 4
        replay.cancel()
        invalidation.cancel()

        #expect(replayed == [3, 4])
        #expect(invalidations == 1)
    }

    @Test func reentrantWriteFromSubscriberIsDelivered() {
        let probe = OrderingProbe()
        var seen: [Int] = []
        let cancellable = probe.$value.dropFirst().sink { value in
            seen.append(value)
            if value == 1 { probe.value = 2 }
        }
        probe.value = 1
        cancellable.cancel()

        #expect(seen == [1, 2])
        #expect(probe.value == 2)
    }

    @MainActor
    @Test func settingsSinkSeesNewValueThroughCurrentAndSettings() {
        let model = SettingsModel.shared
        let original = model.settings
        defer {
            model.settings = original
            model.flushPendingSave()
        }
        let target = original.menuBarOpacity == 0.42 ? 0.43 : 0.42
        let revisionBefore = model.revision
        var observed: [(published: Double, current: Double, stored: Double, revision: UInt64)] = []
        let cancellable = model.$settings
            .map(\.menuBarOpacity)
            .dropFirst()
            .removeDuplicates()
            .sink { published in
                observed.append((published, model.current.menuBarOpacity, model.settings.menuBarOpacity, model.revision))
            }
        model.settings.menuBarOpacity = target
        cancellable.cancel()

        #expect(observed.count == 1)
        #expect(observed.first?.published == target)
        #expect(observed.first?.current == target)
        #expect(observed.first?.stored == target)
        #expect((observed.first?.revision ?? 0) > revisionBefore)
    }
}

// MARK: - Colour encoding

@Suite("CodableColor encoding")
struct CodableColorEncodingTests {
    private func roundTrip(_ color: CodableColor) throws -> CodableColor {
        try JSONDecoder().decode(CodableColor.self, from: JSONEncoder().encode(color))
    }

    @Test func namedSpaceRoundTripsExactly() throws {
        for name in [CGColorSpace.sRGB, CGColorSpace.displayP3, CGColorSpace.extendedSRGB] {
            let space = try #require(CGColorSpace(name: name))
            var components: [CGFloat] = [0.25, 0.5, 0.75, 0.9]
            let cgColor = try #require(CGColor(colorSpace: space, components: &components))
            let original = CodableColor(cgColor: cgColor, location: 0.4)
            let decoded = try roundTrip(original)
            #expect(decoded == original)
            #expect(decoded.cgColor.colorSpace?.name == name)
        }
    }

    @Test func grayRoundTrips() throws {
        let original = CodableColor(cgColor: CGColor(gray: 0.3, alpha: 1))
        #expect(try roundTrip(original).cgColor.components == original.cgColor.components)
    }

    @Test func newFormatIsCompactAndHasNoICCProfile() throws {
        let color = CodableColor(cgColor: CGColor(srgbRed: 0.1, green: 0.2, blue: 0.3, alpha: 1))
        let data = try JSONEncoder().encode(color)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["colorSpace"] == nil)
        #expect(object["colorSpaceName"] as? String == CGColorSpace.sRGB as String)
        #expect(data.count < 200)
    }

    @Test func legacyICCFormatStillDecodes() throws {
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let icc = try #require(space.copyICCData()) as Data
        let legacy: [String: Any] = [
            "components": [0.2, 0.4, 0.6, 1.0],
            "colorSpace": icc.base64EncodedString(),
            "location": 0.5,
        ]
        let data = try JSONSerialization.data(withJSONObject: legacy)
        let decoded = try JSONDecoder().decode(CodableColor.self, from: data)
        #expect(decoded.location == 0.5)
        #expect(decoded.cgColor.components == [0.2, 0.4, 0.6, 1.0])

        let reencoded = try roundTrip(decoded)
        let srgb = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let expected = try #require(decoded.cgColor.converted(to: srgb, intent: .defaultIntent, options: nil)?.components)
        let actual = try #require(reencoded.cgColor.components)
        #expect(zip(expected, actual).allSatisfy { abs($0 - $1) < 0.0001 })
    }

    @Test func unnamedSpaceIsStoredAsSRGBOrExtendedSRGB() throws {
        let icc = try #require(CGColorSpace(name: CGColorSpace.displayP3)?.copyICCData())
        let unnamed = try #require(CGColorSpace(iccData: icc))
        var inGamut: [CGFloat] = [0.5, 0.5, 0.5, 1]
        var outOfGamut: [CGFloat] = [1, 0, 0, 1]
        let gray = try #require(CGColor(colorSpace: unnamed, components: &inGamut))
        let red = try #require(CGColor(colorSpace: unnamed, components: &outOfGamut))

        if unnamed.name == nil {
            #expect(CodableColor.portableRepresentation(of: gray)?.name == CGColorSpace.sRGB as String)
            #expect(CodableColor.portableRepresentation(of: red)?.name == CGColorSpace.extendedSRGB as String)
        }
        #expect(try roundTrip(CodableColor(cgColor: red)).cgColor.components != nil)
    }

    @Test func mismatchedComponentCountIsRejected() throws {
        let bad: [String: Any] = ["components": [0.1, 0.2], "colorSpaceName": CGColorSpace.sRGB as String]
        let data = try JSONSerialization.data(withJSONObject: bad)
        #expect(throws: (any Error).self) { try JSONDecoder().decode(CodableColor.self, from: data) }
    }
}

// MARK: - Payload format, launch policy, backups

@Suite("Settings payload storage")
struct SettingsPayloadStorageTests {
    @Test func stampRoundTripsAndDecodesStrictly() throws {
        let encoded = try SettingsPersistence.encoder.encode(Settings())
        let stamped = SettingsPayloadFormat.stamped(encoded)
        #expect(SettingsPayloadFormat.schemaVersion(of: stamped) == SettingsPayloadFormat.currentSchemaVersion)
        #expect(SettingsPayloadFormat.schemaVersion(of: encoded) == nil)
        let decoded = try #require(SettingsPersistence.decodeFromPayloadReportingTolerance(stamped))
        #expect(decoded.decodedTolerantly == false)
        #expect(try JSONSerialization.jsonObject(with: stamped) is [String: Any])
    }

    @Test func stampHandlesEmptyObjectAndFutureVersions() throws {
        let empty = SettingsPayloadFormat.stamped(Data("{}".utf8), version: 12)
        #expect(String(decoding: empty, as: UTF8.self) == "{\"settingsSchemaVersion\":12}")
        #expect(SettingsPayloadFormat.schemaVersion(of: empty) == 12)
        let elsewhere = Data("{\"a\":1,\"settingsSchemaVersion\":5}".utf8)
        #expect(SettingsPayloadFormat.schemaVersion(of: elsewhere) == 5)
    }

    @Test func tolerantDecodeIsReported() throws {
        var object = try #require(SettingsPersistence.encodeToDictionary(Settings()))
        object["menuBarOpacity"] = "not a number"
        let data = try JSONSerialization.data(withJSONObject: object)
        let decoded = try #require(SettingsPersistence.decodeFromPayloadReportingTolerance(data))
        #expect(decoded.decodedTolerantly)
        #expect(decoded.settings.menuBarOpacity == Settings().menuBarOpacity)
    }

    @Test func launchPlanSkipsWriteForCurrentCleanPayload() {
        let plan = SettingsLaunchPlan.make(for: .init(
            loadedFromPayload: true, storedSchemaVersion: SettingsPayloadFormat.currentSchemaVersion,
            decodedTolerantly: false, migratedOnLoad: false
        ))
        #expect(plan == SettingsLaunchPlan(backUpOriginal: false, persistNow: false, holdUntilUserChange: false))
    }

    @Test func launchPlanBacksUpBeforeUpgradeOrLossyDecode() {
        let upgrade = SettingsLaunchPlan.make(for: .init(
            loadedFromPayload: true, storedSchemaVersion: nil, decodedTolerantly: false, migratedOnLoad: false
        ))
        #expect(upgrade == SettingsLaunchPlan(backUpOriginal: true, persistNow: true, holdUntilUserChange: false))

        let lossy = SettingsLaunchPlan.make(for: .init(
            loadedFromPayload: true, storedSchemaVersion: SettingsPayloadFormat.currentSchemaVersion,
            decodedTolerantly: true, migratedOnLoad: false
        ))
        #expect(lossy == SettingsLaunchPlan(backUpOriginal: true, persistNow: true, holdUntilUserChange: false))

        let migrated = SettingsLaunchPlan.make(for: .init(
            loadedFromPayload: true, storedSchemaVersion: SettingsPayloadFormat.currentSchemaVersion,
            decodedTolerantly: false, migratedOnLoad: true
        ))
        #expect(migrated == SettingsLaunchPlan(backUpOriginal: false, persistNow: true, holdUntilUserChange: false))
    }

    @Test func launchPlanHoldsNewerSchema() {
        let plan = SettingsLaunchPlan.make(
            for: .init(loadedFromPayload: true, storedSchemaVersion: 3, decodedTolerantly: true, migratedOnLoad: true),
            currentSchemaVersion: 2
        )
        #expect(plan == SettingsLaunchPlan(backUpOriginal: true, persistNow: false, holdUntilUserChange: true))
    }

    @Test func launchPlanWritesWhenNothingWasStored() {
        let plan = SettingsLaunchPlan.make(for: .init(
            loadedFromPayload: false, storedSchemaVersion: nil, decodedTolerantly: false, migratedOnLoad: false
        ))
        #expect(plan.persistNow && !plan.backUpOriginal && !plan.holdUntilUserChange)
    }

    @Test func backupsKeepNewestFiveAndDeduplicate() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SettingsBackupsTest-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let start = Date(timeIntervalSince1970: 1_800_000_000)
        for index in 0..<7 {
            let url = try #require(SettingsPayloadBackups.save(
                Data("payload-\(index)".utf8), appVersion: "2.0", date: start.addingTimeInterval(Double(index)), in: directory
            ))
            try FileManager.default.setAttributes(
                [.modificationDate: start.addingTimeInterval(Double(index))], ofItemAtPath: url.path
            )
        }
        var backups = SettingsPayloadBackups.listBackups(in: directory)
        #expect(backups.count == 5)
        let newest = try #require(backups.max { $0.date < $1.date })
        #expect(try Data(contentsOf: newest.url) == Data("payload-6".utf8))

        let deduped = SettingsPayloadBackups.save(Data("payload-6".utf8), appVersion: "2.0", date: start.addingTimeInterval(60), in: directory)
        #expect(deduped == newest.url)
        backups = SettingsPayloadBackups.listBackups(in: directory)
        #expect(backups.count == 5)
    }

    @Test func pruneOrderIsOldestFirst() {
        let base = URL(fileURLWithPath: "/tmp")
        let backups = (0..<7).map { (base.appendingPathComponent("settings-\($0).json"), Date(timeIntervalSince1970: Double($0))) }
        let pruned = SettingsPayloadBackups.backupsToPrune(backups, keeping: 5)
        #expect(Set(pruned.map(\.lastPathComponent)) == ["settings-0.json", "settings-1.json"])
        #expect(SettingsPayloadBackups.backupsToPrune(Array(backups.prefix(3)), keeping: 5).isEmpty)
    }

    @Test func backupFileNameIsFilesystemSafe() {
        let name = SettingsPayloadBackups.fileName(appVersion: "2.1 (beta/3)", date: Date(timeIntervalSince1970: 0))
        #expect(name == "settings-2.1__beta_3_-19700101T000000Z.json")
    }

    @Test func dockPresetMergeKeepsFileAndAddsPayloadOnlyPresets() {
        let shared = DockLayout(name: "Shared")
        let fromOldBuild = DockLayout(name: "Old")
        var renamedInFile = shared
        renamedInFile.name = "Renamed"

        #expect(DockLayoutPresetFile.merged(file: nil, payload: [shared]) == [shared])
        #expect(DockLayoutPresetFile.merged(file: [renamedInFile], payload: [shared, fromOldBuild]) == [renamedInFile, fromOldBuild])
        #expect(DockLayoutPresetFile.merged(file: [], payload: []) == [])
    }

    @Test func unreadablePresetsFileIsMovedAsideNotOverwritten() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DockPresetsTest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent(DockLayoutPresetFile.fileName)
        try Data("{not json".utf8).write(to: url)

        guard case .unreadable = DockLayoutPresetFile.load(from: url) else {
            Issue.record("expected an unreadable file")
            return
        }
        let preset = DockLayout(name: "Work")
        #expect(DockLayoutPresetFile.write([preset], previouslyLoaded: false, to: url))
        guard case .loaded(let presets) = DockLayoutPresetFile.load(from: url) else {
            Issue.record("expected the new file to load")
            return
        }
        #expect(presets == [preset])
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(names.contains { $0.hasPrefix("DockLayoutPresets.unreadable-") })
    }

    @Test func payloadStaysWithinBudget() throws {
        var settings = Settings()
        let color = CodableColor(cgColor: CGColor(srgbRed: 0.2, green: 0.4, blue: 0.6, alpha: 1))
        settings.menuBarGradientColors = Array(repeating: color, count: 8)
        settings.dockLayoutsPresets = []
        let payload = SettingsPayloadFormat.stamped(try SettingsPersistence.encoder.encode(settings))
        #expect(payload.count < 48 * 1024, "settings payload is \(payload.count) bytes")
        #expect(!String(decoding: payload, as: UTF8.self).contains("\"colorSpace\":"))
    }
}

// MARK: - Multiple running copies

@Suite("Settings writer election")
struct SettingsWriterElectionTests {
    private let applications = URL(fileURLWithPath: "/Applications/Sapphire.app")
    private let derivedData = URL(fileURLWithPath: "/Users/x/Library/Developer/Xcode/DerivedData/Sapphire-abc/Build/Products/Debug/Sapphire.app")

    @Test func aloneIsWriter() {
        #expect(SettingsWriterElection.isWriter(bundleURL: derivedData, processIdentifier: 50, peers: []))
    }

    @Test func installedCopyWinsOverBuild() {
        let installed = SapphireInstanceCoordination.Peer(bundleURL: applications, processIdentifier: 900)
        #expect(!SettingsWriterElection.isWriter(bundleURL: derivedData, processIdentifier: 10, peers: [installed]))

        let build = SapphireInstanceCoordination.Peer(bundleURL: derivedData, processIdentifier: 10)
        #expect(SettingsWriterElection.isWriter(bundleURL: applications, processIdentifier: 900, peers: [build]))
    }

    @Test func earliestLaunchedWinsAmongEquals() {
        let other = SapphireInstanceCoordination.Peer(bundleURL: derivedData, processIdentifier: 20)
        #expect(SettingsWriterElection.isWriter(bundleURL: derivedData, processIdentifier: 10, peers: [other]))
        #expect(!SettingsWriterElection.isWriter(bundleURL: derivedData, processIdentifier: 30, peers: [other]))
    }

    @Test func exactlyOneWriter() {
        let copies = [
            SapphireInstanceCoordination.Peer(bundleURL: derivedData, processIdentifier: 11),
            SapphireInstanceCoordination.Peer(bundleURL: applications, processIdentifier: 42),
            SapphireInstanceCoordination.Peer(bundleURL: derivedData, processIdentifier: 7),
        ]
        let writers = copies.filter { copy in
            SettingsWriterElection.isWriter(
                bundleURL: copy.bundleURL,
                processIdentifier: copy.processIdentifier,
                peers: copies.filter { $0 != copy }
            )
        }
        #expect(writers.map(\.processIdentifier) == [42])
    }
}