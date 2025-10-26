//
//  PropertyListModifier.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2021-10-23

#!/usr/bin/env xcrun --sdk macosx swift

import Foundation
import CryptoKit

enum ScriptError: Error {
    case general(String)
    case wrapped(String, Error)
}

// MARK: helper functions to read environment variables

func readEnvironmentVariable(name: String, description: String, isUserDefined: Bool) throws -> String {
    if let value = ProcessInfo.processInfo.environment[name] {
        return value
    } else {
        var message = "Unable to determine \(description), missing \(name) environment variable."
        if isUserDefined {
            message += " This is a user-defined variable. Please check that the xcconfig files are present and " +
                       "configured in the project settings."
        }
        throw ScriptError.general(message)
    }
}

func readEnvironmentVariableAsURL(name: String, description: String, isUserDefined: Bool) throws -> URL {
    let value = try readEnvironmentVariable(name: name, description: description, isUserDefined: isUserDefined)

    return URL(fileURLWithPath: value)
}

// MARK: property list keys

let SMAuthorizedClientsKey = "SMAuthorizedClients"
let CFBundleIdentifierKey = kCFBundleIdentifierKey as String
let CFBundleVersionKey = kCFBundleVersionKey as String
let BuildHashKey = "BuildHash"

let LabelKey = "Label"
let MachServicesKey = "MachServices"

let SMPrivilegedExecutablesKey = "SMPrivilegedExecutables"

// MARK: code signing requirements

func organizationalUnitRequirement() throws -> String {
    let commonName = ProcessInfo.processInfo.environment["CODE_SIGN_IDENTITY"]
    if commonName == nil || commonName == "-" {
        throw ScriptError.general("Signing Certificate must be Development. Sign to Run Locally is not supported.")
    }

    let developmentTeamId = try readEnvironmentVariable(name: "DEVELOPMENT_TEAM",
                                                        description: "development team for code signing",
                                                        isUserDefined: false)
    guard developmentTeamId.range(of: #"^[A-Z0-9]{10}$"#, options: .regularExpression) != nil else {
        if developmentTeamId == "-" {
            throw ScriptError.general("Development Team for code signing is not set")
        } else {
            throw ScriptError.general("Development Team for code signing is invalid: \(developmentTeamId)")
        }
    }
    let certificateString = "certificate leaf[subject.OU] = \"\(developmentTeamId)\""

    return certificateString
}

let appleGenericRequirement = "anchor apple generic"

func SMAuthorizedClientsEntry() throws -> (key: String, value: [String]) {
    let appIdentifierRequirement = "identifier \"\(try TargetType.app.bundleIdentifier())\""
    let appVersion = try readEnvironmentVariable(name: "APP_VERSION",
                                                 description: "app version",
                                                 isUserDefined: true)
    let appVersionRequirement = "info[\(CFBundleVersionKey)] >= \"\(appVersion)\""
    let requirements = [appleGenericRequirement,
                        appIdentifierRequirement,
                        appVersionRequirement,
                        try organizationalUnitRequirement()]
    let value = [requirements.joined(separator: " and ")]

    return (SMAuthorizedClientsKey, value)
}

func SMPrivilegedExecutablesEntry() throws -> (key: String, value: [String : String]) {
    let helperToolIdentifierRequirement = "identifier \"\(try TargetType.helperTool.bundleIdentifier())\""
    let requirements = [appleGenericRequirement, helperToolIdentifierRequirement, try organizationalUnitRequirement()]
    let value = [try TargetType.helperTool.bundleIdentifier() : requirements.joined(separator: " and ")]

    return (SMPrivilegedExecutablesKey, value)
}

func LabelEntry() throws -> (key: String, value: String) {
    return (key: LabelKey, value: try TargetType.helperTool.bundleIdentifier())
}

// MARK: property list manipulation

func readPropertyList(atPath path: URL) throws -> (entries: NSMutableDictionary,
                                                   format: PropertyListSerialization.PropertyListFormat) {
    let onDiskPlistData: Data
    do {
        onDiskPlistData = try Data(contentsOf: path)
    } catch {
        throw ScriptError.wrapped("Unable to read property list at: \(path)", error)
    }

    do {
        var format = PropertyListSerialization.PropertyListFormat.xml
        let plist = try PropertyListSerialization.propertyList(from: onDiskPlistData,
                                                               options: .mutableContainersAndLeaves,
                                                               format: &format)
        if let entries = plist as? NSMutableDictionary {
            return (entries: entries, format: format)
        }
        else {
            throw ScriptError.general("Unable to cast parsed property list")
        }
    }
    catch {
        throw ScriptError.wrapped("Unable to parse property list", error)
    }
}

func writePropertyList(atPath path: URL,
                       entries: NSDictionary,
                       format: PropertyListSerialization.PropertyListFormat) throws {
    let plistData: Data
    do {
        plistData = try PropertyListSerialization.data(fromPropertyList: entries,
                                                       format: format,
                                                       options: 0)
    } catch {
        throw ScriptError.wrapped("Unable to serialize property list in order to write to path: \(path)", error)
    }

    do {
        try plistData.write(to: path)
    }
    catch {
        throw ScriptError.wrapped("Unable to write property list to path: \(path)", error)
    }
}

func updatePropertyListWithEntries(_ newEntries: [String : AnyHashable], atPath path: URL) throws {
    let (entries, format) : (NSMutableDictionary, PropertyListSerialization.PropertyListFormat)
    if FileManager.default.fileExists(atPath: path.path) {
        (entries, format) = try readPropertyList(atPath: path)
    } else {
        (entries, format) = ([:], PropertyListSerialization.PropertyListFormat.xml)
    }
    for (key, value) in newEntries {
        entries.setValue(value, forKey: key)
    }
    try writePropertyList(atPath: path, entries: entries, format: format)
}

func removePropertyListEntries(forKeys keys: [String], atPath path: URL) throws {
    let (entries, format) = try readPropertyList(atPath: path)
    for key in keys {
        entries.removeObject(forKey: key)
    }

    if entries.count > 0 {
        try writePropertyList(atPath: path, entries: entries, format: format)
    } else {
        try FileManager.default.removeItem(at: path)
    }
}

func infoPropertyListPath() throws -> URL {
    return try readEnvironmentVariableAsURL(name: "INFOPLIST_FILE",
                                            description: "info property list path",
                                            isUserDefined: true)
}

func launchdPropertyListPath() throws -> URL {
    try readEnvironmentVariableAsURL(name: "LAUNCHDPLIST_FILE",
                                     description: "launchd property list path",
                                     isUserDefined: true)
}

// MARK: automatic bundle version updating

func hashSources() throws -> String {
    let sourcePaths: [URL] = [
        try infoPropertyListPath().deletingLastPathComponent(),
        try readEnvironmentVariableAsURL(name: "SHARED_DIRECTORY",
                                         description: "shared source directory path",
                                         isUserDefined: true)
    ]

    var sha256 = SHA256()
    for sourcePath in sourcePaths {
        if let enumerator = FileManager.default.enumerator(at: sourcePath, includingPropertiesForKeys: []) {
            for case let fileURL as URL in enumerator {
                if fileURL.pathExtension == "swift" {
                    do {
                        sha256.update(data: try Data(contentsOf: fileURL))
                    } catch {
                        throw ScriptError.wrapped("Unable to hash \(fileURL)", error)
                    }
                }
            }
        } else {
            throw ScriptError.general("Could not create enumerator for: \(sourcePath)")
        }
    }
    let digestHex = sha256.finalize().compactMap{ String(format: "%02x", $0) }.joined()

    return digestHex
}

enum BundleVersion {
    case major(UInt)
    case majorMinor(UInt, UInt)
    case majorMinorPatch(UInt, UInt, UInt)

    init?(version: String) {
        let versionParts = version.split(separator: ".")
        if versionParts.count == 1,
           let major = UInt(versionParts[0]) {
            self = .major(major)
        }
        else if versionParts.count == 2,
            let major = UInt(versionParts[0]),
            let minor = UInt(versionParts[1]) {
            self = .majorMinor(major, minor)
        }
        else if versionParts.count == 3,
            let major = UInt(versionParts[0]),
            let minor = UInt(versionParts[1]),
            let patch = UInt(versionParts[2]) {
            self = .majorMinorPatch(major, minor, patch)
        }
        else {
            return nil
        }
    }

    var version: String {
        switch self {
            case .major(let major):
                return "\(major)"
            case .majorMinor(let major, let minor):
                return "\(major).\(minor)"
            case .majorMinorPatch(let major, let minor, let patch):
                return "\(major).\(minor).\(patch)"
        }
    }

    func increment() -> BundleVersion {
        switch self {
            case .major(let major):
                return .major(major + 1)
            case .majorMinor(let major, let minor):
                return .majorMinor(major, minor + 1)
            case .majorMinorPatch(let major, let minor, let patch):
                return .majorMinorPatch(major, minor, patch + 1)
        }
    }
}

func readBundleVersion(propertyList: NSMutableDictionary) throws -> BundleVersion {
    if let value = propertyList[CFBundleVersionKey] as? String {
        if let version = BundleVersion(version: value) {
            return version
        } else {
            throw ScriptError.general("Invalid value for \(CFBundleVersionKey) in property list")
        }
    } else {
        throw ScriptError.general("Could not find version, \(CFBundleVersionKey) missing in property list")
    }
}

func readBuildHash(propertyList: NSMutableDictionary) throws -> String? {
    return propertyList[BuildHashKey] as? String
}

func incrementBundleVersionIfNeeded(infoPropertyListPath: URL) throws {
    let propertyList = try readPropertyList(atPath: infoPropertyListPath)
    let previousBuildHash = try readBuildHash(propertyList: propertyList.entries)
    let currentBuildHash = try hashSources()
    if currentBuildHash != previousBuildHash {
        let version = try readBundleVersion(propertyList: propertyList.entries)
        let newVersion = version.increment()

        propertyList.entries[BuildHashKey] = currentBuildHash
        propertyList.entries[CFBundleVersionKey] = newVersion.version

        try writePropertyList(atPath: infoPropertyListPath,
                              entries: propertyList.entries,
                              format: propertyList.format)
    }
}

// MARK: Xcode target

enum TargetType: String {
    case app = "APP_BUNDLE_IDENTIFIER"
    case helperTool = "HELPER_TOOL_BUNDLE_IDENTIFIER"

    func bundleIdentifier() throws -> String {
        return try readEnvironmentVariable(name: self.rawValue,
                                           description: "bundle identifier for \(self)",
                                           isUserDefined: true)
    }
}

func determineTargetType() throws -> TargetType {
    let bundleId = try readEnvironmentVariable(name: "PRODUCT_BUNDLE_IDENTIFIER",
                                               description: "bundle id",
                                               isUserDefined: false)

    let appBundleIdentifier = try TargetType.app.bundleIdentifier()
    let helperToolBundleIdentifier = try TargetType.helperTool.bundleIdentifier()
    if bundleId == appBundleIdentifier {
        return TargetType.app
    } else if bundleId ==  helperToolBundleIdentifier {
        return TargetType.helperTool
    } else {
        throw ScriptError.general("Unexpected bundle id \(bundleId) encountered. This means you need to update the " +
                                  "user defined variables APP_BUNDLE_IDENTIFIER and/or " +
                                  "HELPER_TOOL_BUNDLE_IDENTIFIER in Config.xcconfig.")
    }
}

// MARK: tasks

typealias ScriptTask = () throws -> Void
let scriptTasks: [String : ScriptTask] = [
    "satisfy-job-bless-requirements" : satisfyJobBlessRequirements,
    "cleanup-job-bless-requirements" : cleanupJobBlessRequirements,
    "specify-mach-services" : specifyMachServices,
    "cleanup-mach-services" : cleanupMachServices,
    "auto-increment-version" : autoIncrementVersion
]

func determineScriptTasks() throws -> [ScriptTask] {
    if CommandLine.arguments.count > 1 {
        var matchingTasks = [ScriptTask]()
        for index in 1..<CommandLine.arguments.count {
            let arg = CommandLine.arguments[index]
            if let task = scriptTasks[arg] {
                matchingTasks.append(task)
            } else {
                throw ScriptError.general("Unexpected value provided as argument to script: \(arg)")
            }
        }
        return matchingTasks
    } else {
        throw ScriptError.general("No value(s) provided as argument to script")
    }
}

func satisfyJobBlessRequirements() throws {
    let target = try determineTargetType()
    let infoPropertyList = try infoPropertyListPath()
    switch target {
        case .helperTool:
            let clients = try SMAuthorizedClientsEntry()
            let infoEntries: [String : AnyHashable] = [CFBundleIdentifierKey : try target.bundleIdentifier(),
                                                       clients.key : clients.value]
            try updatePropertyListWithEntries(infoEntries, atPath: infoPropertyList)

            let launchdPropertyList = try launchdPropertyListPath()
            let label = try LabelEntry()
            try updatePropertyListWithEntries([label.key : label.value], atPath: launchdPropertyList)
        case .app:
            let executables = try SMPrivilegedExecutablesEntry()
            try updatePropertyListWithEntries([executables.key : executables.value], atPath: infoPropertyList)
    }
}

func cleanupJobBlessRequirements() throws {
    let target = try determineTargetType()
    let infoPropertyList = try infoPropertyListPath()
    switch target {
        case .helperTool:
            try removePropertyListEntries(forKeys: [SMAuthorizedClientsKey, CFBundleIdentifierKey],
                                          atPath: infoPropertyList)

            let launchdPropertyList = try launchdPropertyListPath()
            try removePropertyListEntries(forKeys: [LabelKey], atPath: launchdPropertyList)
        case .app:
            try removePropertyListEntries(forKeys: [SMPrivilegedExecutablesKey], atPath: infoPropertyList)
    }
}

func specifyMachServices() throws {
    let target = try determineTargetType()
    switch target {
        case .helperTool:
            let services = [MachServicesKey: [try TargetType.helperTool.bundleIdentifier() : true]]
            try updatePropertyListWithEntries(services, atPath: try launchdPropertyListPath())
        case .app:
            throw ScriptError.general("specify-mach-services only available for helper tool")
    }
}

func cleanupMachServices() throws {
    let target = try determineTargetType()
    switch target {
        case .helperTool:
            try removePropertyListEntries(forKeys: [MachServicesKey], atPath: try launchdPropertyListPath())
        case .app:
            throw ScriptError.general("cleanup-mach-services only available for helper tool")
    }
}

func autoIncrementVersion() throws {
    let target = try determineTargetType()
    switch target {
        case .helperTool:
            let infoPropertyList = try infoPropertyListPath()
            try incrementBundleVersionIfNeeded(infoPropertyListPath: infoPropertyList)
        case .app:
            throw ScriptError.general("auto-increment-version only available for helper tool")
    }
}

// MARK: script starts here

do {
    for task in try determineScriptTasks() {
        try task()
    }
}
catch ScriptError.general(let message) {
    print("error: \(message)")
    exit(1)
}
catch ScriptError.wrapped(let message, let wrappedError) {
    print("error: \(message)")
    print("internal error: \(wrappedError)")
    exit(2)
}