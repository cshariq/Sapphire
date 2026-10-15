//
//  SapphireInstanceCoordinationTests.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-28

import FileProvider
import Foundation
import Testing
@testable import Sapphire

@Suite("Sapphire instance coordination")
struct SapphireInstanceCoordinationTests {
    private let applications = URL(fileURLWithPath: "/Applications/Sapphire.app")
    private let derivedData = URL(
        fileURLWithPath: "/Users/shariq/Library/Developer/Xcode/DerivedData/Sapphire-abc/Build/Products/Debug/Sapphire.app"
    )

    @Test("Classifies Applications vs DerivedData bundle URLs")
    func classifiesBundleLocations() {
        #expect(SapphireInstanceCoordination.isApplicationsURL(applications))
        #expect(!SapphireInstanceCoordination.isBuildFolderURL(applications))
        #expect(!SapphireInstanceCoordination.isApplicationsURL(derivedData))
        #expect(SapphireInstanceCoordination.isBuildFolderURL(derivedData))
    }

    @Test("Isolates Firestore for build folders and extra instances")
    func isolatesFirestore() {
        #expect(
            SapphireInstanceCoordination.shouldIsolateFirestorePersistence(
                bundleURL: derivedData,
                otherPeers: []
            )
        )
        #expect(
            !SapphireInstanceCoordination.shouldIsolateFirestorePersistence(
                bundleURL: applications,
                otherPeers: []
            )
        )
        #expect(
            SapphireInstanceCoordination.shouldIsolateFirestorePersistence(
                bundleURL: applications,
                otherPeers: [.init(bundleURL: derivedData, processIdentifier: 99)]
            )
        )
    }

    @Test("Only the installed or lowest-PID process registers File Provider")
    func fileProviderOwnership() {
        #expect(
            SapphireInstanceCoordination.shouldRegisterFileProvider(
                bundleURL: derivedData,
                processIdentifier: 50,
                otherPeers: []
            )
        )
        #expect(
            !SapphireInstanceCoordination.shouldRegisterFileProvider(
                bundleURL: derivedData,
                processIdentifier: 50,
                otherPeers: [.init(bundleURL: applications, processIdentifier: 20)]
            )
        )
        #expect(
            SapphireInstanceCoordination.shouldRegisterFileProvider(
                bundleURL: applications,
                processIdentifier: 20,
                otherPeers: [.init(bundleURL: derivedData, processIdentifier: 50)]
            )
        )
        #expect(
            SapphireInstanceCoordination.shouldRegisterFileProvider(
                bundleURL: derivedData,
                processIdentifier: 10,
                otherPeers: [.init(bundleURL: derivedData, processIdentifier: 40)]
            )
        )
        #expect(
            !SapphireInstanceCoordination.shouldRegisterFileProvider(
                bundleURL: derivedData,
                processIdentifier: 40,
                otherPeers: [.init(bundleURL: derivedData, processIdentifier: 10)]
            )
        )
    }

    @Test("File Provider errors stay non-fatal and mention the running copy")
    func fileProviderHintIsActionable() {
        let error = NSError(
            domain: NSFileProviderErrorDomain,
            code: -2005,
            userInfo: [NSLocalizedDescriptionKey: "The application cannot be used right now."]
        )
        #expect(SapphireInstanceCoordination.isApplicationCannotBeUsed(error))
        let hint = SapphireInstanceCoordination.fileProviderRegistrationHint(
            error: error,
            bundleURL: derivedData
        )
        #expect(hint.contains("DerivedData") || hint.contains("/Users/shariq"))
        #expect(!hint.localizedCaseInsensitiveContains("must be running from /Applications (not a build folder), and its File Provider extension must be signed"))
    }
}