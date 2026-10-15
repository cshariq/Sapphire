//
//  InstalledAppUpdatePolicyTests.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-10-07

import XCTest
@testable import Sapphire

final class InstalledAppUpdatePolicyTests: XCTestCase {
    private typealias Policy = InstalledAppUpdatePolicy
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func available(_ version: String) -> InstalledAppUpdateEntry.Status {
        .updateAvailable(latestVersion: version, downloadURL: nil, pageURL: nil, releaseNotes: nil, releaseNotesURL: nil)
    }

    // MARK: Scheduling

    func testCheckIsDueOnlyAfterTheIntervalElapses() {
        XCTAssertTrue(Policy.isCheckDue(lastCheckedAt: nil, now: now, interval: 3_600))
        XCTAssertFalse(Policy.isCheckDue(lastCheckedAt: now.addingTimeInterval(-1_800), now: now, interval: 3_600))
        XCTAssertTrue(Policy.isCheckDue(lastCheckedAt: now.addingTimeInterval(-3_600), now: now, interval: 3_600))
    }

    func testClockMovingBackwardsMakesCheckDue() {
        XCTAssertTrue(Policy.isCheckDue(lastCheckedAt: now.addingTimeInterval(86_400), now: now, interval: 3_600))
    }

    func testLaunchWithRecentCheckOnlyResolvesMissingResults() {
        XCTAssertEqual(
            Policy.backgroundScope(force: false, isDue: false, hasEntries: false, hasUnresolvedEntries: false),
            .unresolved
        )
        XCTAssertEqual(
            Policy.backgroundScope(force: true, isDue: false, hasEntries: false, hasUnresolvedEntries: false),
            .unresolved
        )
        XCTAssertNil(
            Policy.backgroundScope(force: false, isDue: false, hasEntries: true, hasUnresolvedEntries: false)
        )
        XCTAssertEqual(
            Policy.backgroundScope(force: false, isDue: false, hasEntries: true, hasUnresolvedEntries: true),
            .unresolved
        )
    }

    func testDueOrForcedRetryChecksEverything() {
        XCTAssertEqual(
            Policy.backgroundScope(force: false, isDue: true, hasEntries: false, hasUnresolvedEntries: false),
            .all
        )
        XCTAssertEqual(
            Policy.backgroundScope(force: true, isDue: false, hasEntries: true, hasUnresolvedEntries: false),
            .all
        )
    }

    // MARK: Announcements

    func testAlreadyAnnouncedUpdateIsNotAnnouncedAgain() {
        let announced: Set<String> = [Policy.announcementKey(bundleID: "com.a", version: "2.0")]
        let fresh = Policy.updatesToAnnounce(
            [.init(id: "com.a", version: "2.0"), .init(id: "com.b", version: "1.1")],
            alreadyAnnounced: announced
        )
        XCTAssertEqual(fresh, [.init(id: "com.b", version: "1.1")])
    }

    func testNewerVersionOfAnnouncedAppIsAnnounced() {
        let announced: Set<String> = [Policy.announcementKey(bundleID: "com.a", version: "2.0")]
        let fresh = Policy.updatesToAnnounce([.init(id: "com.a", version: "2.1")], alreadyAnnounced: announced)
        XCTAssertEqual(fresh, [.init(id: "com.a", version: "2.1")])
    }

    func testDuplicateCandidatesAnnounceOnce() {
        let fresh = Policy.updatesToAnnounce(
            [.init(id: "com.a", version: "2.0"), .init(id: "com.a", version: "2.0")],
            alreadyAnnounced: []
        )
        XCTAssertEqual(fresh.count, 1)
    }

    func testPruningKeepsAnnouncementsThroughTransientErrors() {
        let announced: Set<String> = [
            Policy.announcementKey(bundleID: "com.error", version: "3.0"),
            Policy.announcementKey(bundleID: "com.updated", version: "1.0"),
            Policy.announcementKey(bundleID: "com.still", version: "4.0"),
            Policy.announcementKey(bundleID: "com.newer", version: "5.0"),
            Policy.announcementKey(bundleID: "com.removed", version: "1.0"),
        ]
        let pruned = Policy.prunedAnnouncements(announced, outcomes: [
            "com.error": .unknown,
            "com.updated": .noUpdate,
            "com.still": .updateAvailable(version: "4.0"),
            "com.newer": .updateAvailable(version: "5.1"),
        ])
        XCTAssertEqual(pruned, [
            Policy.announcementKey(bundleID: "com.error", version: "3.0"),
            Policy.announcementKey(bundleID: "com.still", version: "4.0"),
        ])
    }

    func testOutcomeMapping() {
        XCTAssertEqual(Policy.outcome(for: available("2.0")), .updateAvailable(version: "2.0"))
        XCTAssertEqual(Policy.outcome(for: .upToDate(latestVersion: "2.0")), .noUpdate)
        XCTAssertEqual(Policy.outcome(for: .error("offline")), .unknown)
        XCTAssertEqual(Policy.outcome(for: .checking), .unknown)
    }

    // MARK: Skips

    func testSkipCoversSkippedAndOlderVersionsOnly() {
        XCTAssertTrue(Policy.isSkipped(latestVersion: "2.0", skippedVersion: "2.0"))
        XCTAssertTrue(Policy.isSkipped(latestVersion: "1.9", skippedVersion: "2.0"))
        XCTAssertFalse(Policy.isSkipped(latestVersion: "2.0.1", skippedVersion: "2.0"))
        XCTAssertFalse(Policy.isSkipped(latestVersion: "2.0", skippedVersion: nil))
        XCTAssertFalse(Policy.isSkipped(latestVersion: "Latest", skippedVersion: "Nightly"))
        XCTAssertTrue(Policy.isSkipped(latestVersion: "Latest", skippedVersion: "Latest"))
    }

    func testSkippedUpdateIsPresentedAsCurrentWithLatestVersion() {
        XCTAssertEqual(
            Policy.presentedStatus(available("2.0"), skippedVersion: "2.0"),
            .upToDate(latestVersion: "2.0")
        )
        XCTAssertEqual(Policy.presentedStatus(available("2.1"), skippedVersion: "2.0"), available("2.1"))
        XCTAssertEqual(Policy.presentedStatus(.error("x"), skippedVersion: "2.0"), .error("x"))
    }

    func testSkipsArePrunedWhenAppUpdatedOrRemoved() {
        let skipped = ["com.a": "2.0", "com.b": "3.0", "com.gone": "1.0", "com.c": "5.0"]
        let pruned = Policy.prunedSkips(
            skipped,
            installedVersions: ["com.a": "2.0", "com.b": "2.5", "com.c": "5.1"],
            inventoryIsComplete: true
        )
        XCTAssertEqual(pruned, ["com.b": "3.0"])

        let partial = Policy.prunedSkips(skipped, installedVersions: [:], inventoryIsComplete: false)
        XCTAssertEqual(partial, skipped)
    }

    // MARK: Carried and cached results

    func testRescannedRowKeepsResultOnlyForSameVersion() {
        XCTAssertEqual(
            Policy.carriedStatus(
                scannedVersion: "1.0", scannedBuildVersion: "10",
                priorVersion: "1.0", priorBuildVersion: "10",
                priorStatus: available("2.0")
            ),
            available("2.0")
        )
        XCTAssertNil(
            Policy.carriedStatus(
                scannedVersion: "2.0", scannedBuildVersion: "20",
                priorVersion: "1.0", priorBuildVersion: "10",
                priorStatus: available("2.0")
            )
        )
        XCTAssertNil(
            Policy.carriedStatus(
                scannedVersion: "1.0", scannedBuildVersion: "10",
                priorVersion: "1.0", priorBuildVersion: "10",
                priorStatus: .checking
            )
        )
    }

    func testCacheRecordRoundTripsAndRejectsOtherVersions() throws {
        let status = InstalledAppUpdateEntry.Status.updateAvailable(
            latestVersion: "2.0",
            downloadURL: URL(string: "https://example.test/app.dmg"),
            pageURL: URL(string: "https://example.test"),
            releaseNotes: "Fixes",
            releaseNotesURL: nil
        )
        let record = try XCTUnwrap(
            InstalledAppUpdateCacheRecord(status: status, checkedVersion: "1.0", checkedBuildVersion: "10")
        )
        let decoded = try JSONDecoder().decode(
            InstalledAppUpdateCacheRecord.self,
            from: JSONEncoder().encode(record)
        )
        XCTAssertEqual(decoded.status(forInstalledVersion: "1.0", buildVersion: "10"), status)
        XCTAssertNil(decoded.status(forInstalledVersion: "2.0", buildVersion: "20"))
        XCTAssertNil(InstalledAppUpdateCacheRecord(status: .error("x"), checkedVersion: "1", checkedBuildVersion: "1"))
    }

    // MARK: Batch planning

    func testBatchPlanSplitsSourcesAndDedupes() {
        let plan = InstalledAppBatchUpdatePlanner.plan(for: [
            .init(id: "a", route: .homebrew(token: "alpha", requiresAdministrator: false)),
            .init(id: "b", route: .homebrew(token: "beta", requiresAdministrator: true)),
            .init(id: "a", route: .homebrew(token: "alpha", requiresAdministrator: false)),
            .init(id: "c", route: .homebrew(token: "ALPHA", requiresAdministrator: false)),
            .init(id: "d", route: .homebrew(token: "bad token; rm", requiresAdministrator: false)),
            .init(id: "e", route: .appStore),
            .init(id: "f", route: .perItem),
            .init(id: "g", route: .notUpdatable),
        ])
        XCTAssertEqual(plan.homebrew.map { $0.token }, ["alpha"])
        XCTAssertEqual(plan.homebrewInTerminal.map { $0.token }, ["beta"])
        XCTAssertEqual(plan.appStoreIDs, ["e"])
        XCTAssertEqual(plan.perItemIDs, ["f"])
    }

    // MARK: Homebrew

    func testPkgAndPkgutilCasksNeedAdministrator() {
        XCTAssertTrue(HomebrewCaskPrivilege.requiresAdministrator(artifacts: [["pkg": ["Installer.pkg"]]]))
        XCTAssertTrue(HomebrewCaskPrivilege.requiresAdministrator(artifacts: [
            ["app": ["Foo.app"]],
            ["uninstall": [["pkgutil": "com.example.pkg"]]],
        ]))
        XCTAssertTrue(HomebrewCaskPrivilege.requiresAdministrator(artifacts: [
            ["uninstall": [["delete": ["/Library/PrivilegedHelperTools/com.example.helper"]]]],
        ]))
        XCTAssertTrue(HomebrewCaskPrivilege.requiresAdministrator(artifacts: [
            ["uninstall": [["script": ["executable": "uninstall.sh", "sudo": true]]]],
        ]))
        XCTAssertFalse(HomebrewCaskPrivilege.requiresAdministrator(artifacts: [
            ["app": ["Foo.app"]],
            ["uninstall": [["quit": "com.example.foo", "delete": "/Applications/Foo Helper.app"]]],
            ["zap": [["trash": ["~/Library/Preferences/com.example.foo.plist"]]]],
        ]))
    }

    func testPasswordPromptIsRecognised() {
        XCTAssertTrue(HomebrewCaskPrivilege.outputRequestsAdministrator(
            "==> Running installer for foo\nsudo: a terminal is required to read the password"
        ))
        XCTAssertFalse(HomebrewCaskPrivilege.outputRequestsAdministrator("==> Upgrading foo\n  foo was successfully upgraded!"))
    }

    func testEnvironmentIsCuratedAndDisablesAutoUpdate() {
        let environment = HomebrewCommand.environment(
            inherited: [
                "PATH": "/usr/bin",
                "HOMEBREW_CASK_OPTS": "--no-quarantine",
                "HOMEBREW_AUTO_UPDATE_SECS": "1",
                "SUDO_ASKPASS": "/tmp/askpass",
                "DYLD_INSERT_LIBRARIES": "/tmp/evil.dylib",
                "https_proxy": "http://proxy:8080",
            ],
            home: "/Users/test"
        )
        XCTAssertEqual(environment["HOME"], "/Users/test")
        XCTAssertEqual(environment["HOMEBREW_NO_AUTO_UPDATE"], "1")
        XCTAssertEqual(environment["HOMEBREW_NO_ENV_HINTS"], "1")
        XCTAssertEqual(environment["HOMEBREW_CASK_OPTS"], "--no-quarantine")
        XCTAssertEqual(environment["https_proxy"], "http://proxy:8080")
        XCTAssertNil(environment["HOMEBREW_AUTO_UPDATE_SECS"])
        XCTAssertNil(environment["SUDO_ASKPASS"])
        XCTAssertNil(environment["DYLD_INSERT_LIBRARIES"])
        let path = environment["PATH"] ?? ""
        for directory in ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"] {
            XCTAssertTrue(path.split(separator: ":").contains(Substring(directory)), directory)
        }
    }

    func testTokenValidationRejectsShellMetacharacters() {
        XCTAssertTrue(HomebrewCommand.isSafeToken("visual-studio-code"))
        XCTAssertTrue(HomebrewCommand.isSafeToken("homebrew/cask-versions/firefox@developer-edition"))
        XCTAssertFalse(HomebrewCommand.isSafeToken("foo'; rm -rf ~"))
        XCTAssertFalse(HomebrewCommand.isSafeToken("-flag"))
        XCTAssertFalse(HomebrewCommand.isSafeToken("../etc"))
        XCTAssertFalse(HomebrewCommand.isSafeToken(""))
        XCTAssertNil(HomebrewCommand.upgradeArguments(tokens: ["ok", "not ok"]))
        XCTAssertEqual(HomebrewCommand.upgradeArguments(tokens: ["a", "b"]), ["upgrade", "--cask", "a", "b"])
    }

    func testTerminalScriptQuotesTokens() throws {
        let script = try XCTUnwrap(HomebrewCommand.terminalScript(brewPath: "/opt/homebrew/bin/brew", tokens: ["zoom", "docker"]))
        XCTAssertTrue(script.hasPrefix("#!/bin/zsh"))
        XCTAssertTrue(script.contains("'/opt/homebrew/bin/brew' 'upgrade' '--cask' 'zoom' 'docker'"))
        XCTAssertNil(HomebrewCommand.terminalScript(brewPath: "/opt/homebrew/bin/brew", tokens: ["$(evil)"]))
    }

    func testFailureSummaryPrefersErrorLineAndStripsEscapes() {
        let output = """
        ==> Upgrading 1 outdated package:
        \u{1B}[31mError:\u{1B}[0m Download failed on Cask 'foo' with message: 404
        ==> Purging files
        """
        XCTAssertEqual(
            HomebrewCommand.failureSummary(output),
            "Download failed on Cask 'foo' with message: 404"
        )
        XCTAssertEqual(HomebrewCommand.failureSummary("one\ntwo\n"), "two")
        XCTAssertNil(HomebrewCommand.failureSummary("  \n"))
        XCTAssertEqual(HomebrewCommand.failureSummary(String(repeating: "x", count: 300), limit: 10)?.count, 10)
    }

    func testUpgradeTimeoutScalesAndCaps() {
        XCTAssertEqual(HomebrewCommand.upgradeTimeout(caskCount: 1), 15 * 60)
        XCTAssertEqual(HomebrewCommand.upgradeTimeout(caskCount: 2), 25 * 60)
        XCTAssertEqual(HomebrewCommand.upgradeTimeout(caskCount: 50), 60 * 60)
    }
}