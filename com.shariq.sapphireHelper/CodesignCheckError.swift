//
//  CodesignCheckError.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-11-08.
//

import Foundation
import Security
import Darwin

enum CodesignCheckError: Error {
    case message(String)
}

struct CodesignCheck {
    private static let sapphireSigningIdentifier = "com.cshariq.sapphire"
    private static let helperSigningIdentifier = "com.shariq.sapphireHelper"

    private static let adHocSignatureFlag: UInt32 = 0x0002

    private struct SigningIdentity {
        let signingIdentifier: String?
        let bundleIdentifier: String?
        let teamIdentifier: String?
        let certificateData: [Data]
        let isAdHoc: Bool
    }

    static func isSapphireClient(auditToken: audit_token_t) throws -> Bool {
        let helperStaticCode = try requireSelfStaticCode()
        let clientCode = try requireCode(forAuditToken: auditToken)
        let clientStaticCode = try requireStaticCode(forCode: clientCode)

        let helperIdentity = try signingIdentity(forStaticCode: helperStaticCode)
        let clientIdentity = try signingIdentity(forStaticCode: clientStaticCode)
        let helperBundleMatches = helperIdentity.bundleIdentifier == helperSigningIdentifier
            || (geteuid() != 0
                && helperIdentity.isAdHoc
                && helperIdentity.bundleIdentifier == nil)

        guard helperIdentity.signingIdentifier == helperSigningIdentifier,
              helperBundleMatches,
              clientIdentity.signingIdentifier == sapphireSigningIdentifier,
              clientIdentity.bundleIdentifier == sapphireSigningIdentifier,
              trustedSignerMatches(helperIdentity, clientIdentity) else {
            return false
        }

        var designatedRequirement: SecRequirement?
        try executeSecFunction {
            SecCodeCopyDesignatedRequirement(clientStaticCode, [], &designatedRequirement)
        }
        guard let designatedRequirement else {
            throw CodesignCheckError.message("Client has no designated code-signing requirement")
        }
        try executeSecFunction {
            SecCodeCheckValidity(clientCode, [], designatedRequirement)
        }

        return true
    }

    private static func trustedSignerMatches(
        _ helper: SigningIdentity,
        _ client: SigningIdentity
    ) -> Bool {
        if let helperTeam = helper.teamIdentifier,
           let clientTeam = client.teamIdentifier,
           !helperTeam.isEmpty,
           !clientTeam.isEmpty {
            return helperTeam == clientTeam
        }

        if !helper.certificateData.isEmpty || !client.certificateData.isEmpty {
            return !helper.certificateData.isEmpty
                && helper.certificateData == client.certificateData
        }

        return geteuid() != 0 && helper.isAdHoc && client.isAdHoc
    }

    private static func signingIdentity(forStaticCode staticCode: SecStaticCode) throws -> SigningIdentity {
        try validateStrictly(staticCode: staticCode)

        var information: CFDictionary?
        try executeSecFunction {
            SecCodeCopySigningInformation(
                staticCode,
                SecCSFlags(rawValue: kSecCSSigningInformation),
                &information
            )
        }
        guard let information = information as? [String: Any] else {
            throw CodesignCheckError.message("Code signing information was empty")
        }

        let securedInfoPlist = information[kSecCodeInfoPList as String] as? [String: Any]
        let certificates = information[kSecCodeInfoCertificates as String] as? [SecCertificate] ?? []
        let flags = (information[kSecCodeInfoFlags as String] as? NSNumber)?.uint32Value ?? 0

        return SigningIdentity(
            signingIdentifier: information[kSecCodeInfoIdentifier as String] as? String,
            bundleIdentifier: securedInfoPlist?["CFBundleIdentifier"] as? String,
            teamIdentifier: information[kSecCodeInfoTeamIdentifier as String] as? String,
            certificateData: certificates.map { SecCertificateCopyData($0) as Data },
            isAdHoc: flags & adHocSignatureFlag != 0
        )
    }

    private static func validateStrictly(staticCode: SecStaticCode) throws {
        let flags = SecCSFlags(
            rawValue: kSecCSCheckAllArchitectures
                | kSecCSCheckNestedCode
                | kSecCSStrictValidate
        )
        try executeSecFunction {
            SecStaticCodeCheckValidity(staticCode, flags, nil)
        }
    }

    private static func requireSelfStaticCode() throws -> SecStaticCode {
        var code: SecCode?
        try executeSecFunction { SecCodeCopySelf([], &code) }
        guard let code else {
            throw CodesignCheckError.message("SecCode returned empty from SecCodeCopySelf")
        }
        return try requireStaticCode(forCode: code)
    }

    private static func requireCode(forAuditToken auditToken: audit_token_t) throws -> SecCode {
        var token = auditToken
        let tokenData = Data(bytes: &token, count: MemoryLayout<audit_token_t>.size)
        var code: SecCode?
        try executeSecFunction {
            SecCodeCopyGuestWithAttributes(
                nil,
                [kSecGuestAttributeAudit: tokenData] as CFDictionary,
                [],
                &code
            )
        }
        guard let code else {
            throw CodesignCheckError.message("SecCode returned empty for client audit token")
        }
        return code
    }

    private static func requireStaticCode(forCode code: SecCode) throws -> SecStaticCode {
        var staticCode: SecStaticCode?
        try executeSecFunction {
            SecCodeCopyStaticCode(
                code,
                SecCSFlags(rawValue: kSecCSUseAllArchitectures),
                &staticCode
            )
        }
        guard let staticCode else {
            throw CodesignCheckError.message("SecStaticCode returned empty from SecCodeCopyStaticCode")
        }
        return staticCode
    }

    private static func executeSecFunction(_ function: () -> OSStatus) throws {
        let status = function()
        guard status == errSecSuccess else {
            if let errorString = SecCopyErrorMessageString(status, nil) {
                throw CodesignCheckError.message(String(errorString))
            }
            throw CodesignCheckError.message("Unknown security error: \(status)")
        }
    }
}