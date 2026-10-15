//
//  SapphireVMIntegrationTests.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-28

import Foundation
import XCTest
@testable import Sapphire

@MainActor
final class SapphireVMIntegrationTests: XCTestCase {
    func testDeepLinkForwarderCanonicalizesAllowlistedRoutes() throws {
        let id = UUID()
        let open = try XCTUnwrap(URL(string: "sapphire://vm/open"))
        XCTAssertEqual(
            SandboxIntegration.validatedDestinationURL(for: open)?.absoluteString,
            "sandbox://open"
        )

        for action in ["start", "pause", "resume", "graceful-stop"] {
            let source = try XCTUnwrap(
                URL(string: "SAPPHIRE://VM/\(action.uppercased())?vm=\(id.uuidString.lowercased())")
            )
            let destination = try XCTUnwrap(
                SandboxIntegration.validatedDestinationURL(for: source)
            )
            let components = try XCTUnwrap(
                URLComponents(url: destination, resolvingAgainstBaseURL: false)
            )

            XCTAssertEqual(components.scheme, "sandbox")
            XCTAssertEqual(components.host, action)
            XCTAssertEqual(components.queryItems, [
                URLQueryItem(name: "vm", value: id.uuidString),
            ])
        }
    }

    func testDeepLinkForwarderRejectsInjectedAndUntargetedActions() throws {
        let id = UUID().uuidString
        let rejected = [
            "https://vm/open",
            "sapphire://user@vm/open",
            "sapphire://vm/open/extra",
            "sapphire://vm/open#fragment",
            "sapphire://vm/open?unexpected=\(id)",
            "sapphire://vm/open?vm=not-a-uuid",
            "sapphire://vm/open?vm",
            "sapphire://vm/start",
            "sapphire://vm/stop?vm=\(id)",
        ]

        for rawURL in rejected {
            let source = try XCTUnwrap(URL(string: rawURL))
            XCTAssertNil(
                SandboxIntegration.validatedDestinationURL(for: source),
                rawURL
            )
        }
    }

    func testDeepLinkForwarderReportsRejectedRouteWithoutLaunching() throws {
        let source = try XCTUnwrap(URL(string: "sapphire://vm/start"))

        XCTAssertFalse(
            SandboxIntegration.shared.forwardValidatedDeepLink(source)
        )
    }

    func testNewestValidLifecycleSnapshotWinsAcrossCandidates() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let staleURL = directory.appendingPathComponent("stale.json")
        let olderURL = directory.appendingPathComponent("older.json")
        let newestURL = directory.appendingPathComponent("newest.json")
        try writeSnapshot(at: staleURL, occurredAt: now.addingTimeInterval(-601))
        try writeSnapshot(at: olderURL, occurredAt: now.addingTimeInterval(-2))
        let newestID = UUID()
        try writeSnapshot(
            at: newestURL,
            eventID: newestID,
            occurredAt: now.addingTimeInterval(-1)
        )

        let result = SandboxIntegration.loadLatestSnapshot(
            from: [staleURL, olderURL, newestURL],
            at: now
        )

        XCTAssertEqual(result?.eventID, newestID)
    }

    func testLifecycleLoaderRejectsSymlinksAndOversizedFiles() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let targetURL = directory.appendingPathComponent("target.json")
        let symlinkURL = directory.appendingPathComponent("link.json")
        try writeSnapshot(at: targetURL, occurredAt: now)
        try FileManager.default.createSymbolicLink(
            at: symlinkURL,
            withDestinationURL: targetURL
        )

        let oversizedURL = directory.appendingPathComponent("oversized.json")
        try Data(repeating: 0x41, count: 32 * 1_024 + 1).write(to: oversizedURL)

        XCTAssertNil(SandboxIntegration.loadLatestSnapshot(
            from: [symlinkURL, oversizedURL],
            at: now
        ))
    }

    func testAppGroupSnapshotExcludesUserWritableFallback() throws {
        let groupContainer = URL(fileURLWithPath: "/group-container", isDirectory: true)
        let applicationSupport = URL(
            fileURLWithPath: "/user-application-support",
            isDirectory: true
        )

        let productionCandidates = SandboxIntegration.candidateSnapshotURLs(
            groupContainer: groupContainer,
            applicationSupport: applicationSupport
        )
        XCTAssertEqual(productionCandidates, [
            groupContainer
                .appendingPathComponent("SandboxIntegration", isDirectory: true)
                .appendingPathComponent("latest-lifecycle-v1.json"),
        ])

        let developmentCandidates = SandboxIntegration.candidateSnapshotURLs(
            groupContainer: nil,
            applicationSupport: applicationSupport
        )
        XCTAssertEqual(developmentCandidates, [
            applicationSupport
                .appendingPathComponent("Sapphire", isDirectory: true)
                .appendingPathComponent("SandboxIntegration", isDirectory: true)
                .appendingPathComponent("latest-lifecycle-v1.json"),
        ])
    }

    func testSapphireSchemeIsRegisteredByHostApp() throws {
        guard Bundle.main.bundleIdentifier == "com.cshariq.sapphire" else {
            throw XCTSkip("This contract test requires Sapphire.app as the test host.")
        }
        let registrations = try XCTUnwrap(
            Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes")
                as? [[String: Any]]
        )
        let schemes = registrations.flatMap {
            $0["CFBundleURLSchemes"] as? [String] ?? []
        }

        XCTAssertTrue(schemes.contains("sapphire"))
    }

    private func writeSnapshot(
        at url: URL,
        eventID: UUID = UUID(),
        occurredAt: Date
    ) throws {
        let snapshot = SapphireVMLifecycleSnapshot(
            schemaVersion: 1,
            writerBundleIdentifier: "com.cshariq.sandbox",
            eventID: eventID,
            virtualMachineID: UUID(),
            virtualMachineName: "Test VM",
            state: .running,
            detail: nil,
            occurredAt: occurredAt
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        try encoder.encode(snapshot).write(to: url)
    }
}