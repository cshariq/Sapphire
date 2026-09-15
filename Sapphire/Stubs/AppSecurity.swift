//
//  AppSecurity.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-15

#if !SAPPHIRE_FULL_BUILD
import Foundation

struct AppCodeSignatureIdentity: Equatable {
    let signingIdentifier: String
    let teamIdentifier: String?
    let bundleIdentifier: String
}

enum AppSecurityValidationError: LocalizedError {
    case notAnApplication
    case bundleIdentifierMismatch(expected: String, actual: String)

    var errorDescription: String? {
        switch self {
        case .notAnApplication:
            "The downloaded item is not a valid application bundle."
        case .bundleIdentifierMismatch(let expected, let actual):
            "The update is for \(actual), not \(expected)."
        }
    }
}

enum AppSecurityValidator {
    static func identity(at bundleURL: URL, requireValidSignature: Bool = true) throws -> AppCodeSignatureIdentity {
        guard bundleURL.pathExtension.caseInsensitiveCompare("app") == .orderedSame,
              let bundleIdentifier = Bundle(url: bundleURL)?.bundleIdentifier else {
            throw AppSecurityValidationError.notAnApplication
        }
        return AppCodeSignatureIdentity(
            signingIdentifier: bundleIdentifier,
            teamIdentifier: nil,
            bundleIdentifier: bundleIdentifier
        )
    }

    static func validateReplacement(candidate: URL, replacing installed: URL) throws {
        let candidateID = try identity(at: candidate).bundleIdentifier
        let installedID = try identity(at: installed).bundleIdentifier
        guard candidateID == installedID else {
            throw AppSecurityValidationError.bundleIdentifierMismatch(expected: installedID, actual: candidateID)
        }
    }

    static func applicationGroups(at bundleURL: URL) -> Set<String> { [] }

    static func isSafeIdentifier(_ identifier: String) -> Bool {
        !identifier.isEmpty
            && identifier != "."
            && identifier != ".."
            && !identifier.contains("/")
            && !identifier.contains("\\")
    }
}
#endif