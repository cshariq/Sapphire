#if PUBLIC_BUILD
import Darwin
import Foundation
import XCTest
@testable import Sapphire

final class PublicArchiveQuarantineTests: XCTestCase {
    func testSourceSymbolicLinkInheritsArchiveTargetQuarantine() throws {
        try withFixture { root in
            let archive = root.appendingPathComponent("download.zip")
            let sourceLink = root.appendingPathComponent("archive-link.zip")
            let destination = root.appendingPathComponent("extracted")
            let child = destination.appendingPathComponent("file.txt")
            try Data().write(to: archive)
            try FileManager.default.createSymbolicLink(at: sourceLink, withDestinationURL: archive)
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            try Data().write(to: child)
            let quarantine = Data("0081;67000000;Sapphire Tests;A94C7F8B-1A23-44AB-8899-142365870AAA".utf8)
            try setAttribute(quarantine, on: archive)
            XCTAssertNil(try attribute(on: sourceLink))

            QuarantineAttribute.copy(from: [sourceLink], to: destination, recursively: true)

            XCTAssertEqual(try attribute(on: destination), quarantine)
            XCTAssertEqual(try attribute(on: child), quarantine)
        }
    }

    func testRecursiveCopyPreservesQuarantineOnNestedHiddenAndPackageContents() throws {
        try withFixture { root in
            let source = root.appendingPathComponent("download.zip")
            let destination = root.appendingPathComponent("extracted")
            let nested = destination.appendingPathComponent("Example.app/Contents/.hidden")
            try Data().write(to: source)
            try FileManager.default.createDirectory(at: nested.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data().write(to: nested)
            let quarantine = Data("0081;67000000;Sapphire Tests;A94C7F8B-1A23-44AB-8899-142365870AAA".utf8)
            try setAttribute(quarantine, on: source)

            QuarantineAttribute.copy(from: [source], to: destination, recursively: true)

            XCTAssertEqual(try attribute(on: destination), quarantine)
            XCTAssertEqual(try attribute(on: nested.deletingLastPathComponent()), quarantine)
            XCTAssertEqual(try attribute(on: nested), quarantine)
        }
    }

    func testNonrecursiveCopyLeavesChildrenUnchangedAndMissingSourceKeepsExistingQuarantine() throws {
        try withFixture { root in
            let source = root.appendingPathComponent("download.zip")
            let cleanSource = root.appendingPathComponent("local.zip")
            let destination = root.appendingPathComponent("extracted")
            let child = destination.appendingPathComponent("file.txt")
            try Data().write(to: source)
            try Data().write(to: cleanSource)
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            try Data().write(to: child)
            let quarantine = Data("0081;67000000;Sapphire Tests;".utf8)
            try setAttribute(quarantine, on: source)

            QuarantineAttribute.copy(from: [source], to: destination, recursively: false)
            XCTAssertEqual(try attribute(on: destination), quarantine)
            XCTAssertNil(try attribute(on: child))

            QuarantineAttribute.copy(from: [cleanSource], to: destination, recursively: true)
            XCTAssertEqual(try attribute(on: destination), quarantine)
            XCTAssertNil(try attribute(on: child))
        }
    }

    func testRecursiveCopyDoesNotFollowFileOrDirectorySymbolicLinks() throws {
        try withFixture { root in
            let source = root.appendingPathComponent("download.zip")
            let destination = root.appendingPathComponent("extracted")
            let external = root.appendingPathComponent("outside")
            let externalFile = external.appendingPathComponent("user-file.txt")
            try Data().write(to: source)
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: external, withIntermediateDirectories: true)
            try Data().write(to: externalFile)
            try FileManager.default.createSymbolicLink(at: destination.appendingPathComponent("linked-file"), withDestinationURL: externalFile)
            try FileManager.default.createSymbolicLink(at: destination.appendingPathComponent("linked-folder"), withDestinationURL: external)
            try setAttribute(Data("0081;67000000;Sapphire Tests;".utf8), on: source)

            QuarantineAttribute.copy(from: [source], to: destination, recursively: true)
            QuarantineAttribute.copy(from: [source], to: destination.appendingPathComponent("linked-folder"), recursively: true)

            XCTAssertNil(try attribute(on: external))
            XCTAssertNil(try attribute(on: externalFile))
        }
    }

    private func withFixture(_ body: (URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try body(root)
    }

    private func setAttribute(_ value: Data, on url: URL) throws {
        let result = value.withUnsafeBytes { bytes in
            setxattr(url.path, "com.apple.quarantine", bytes.baseAddress, bytes.count, 0, XATTR_NOFOLLOW)
        }
        guard result == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
    }

    private func attribute(on url: URL) throws -> Data? {
        let length = getxattr(url.path, "com.apple.quarantine", nil, 0, 0, XATTR_NOFOLLOW)
        if length == -1, errno == ENOATTR { return nil }
        guard length >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        var value = Data(count: length)
        let count = value.withUnsafeMutableBytes { bytes in
            getxattr(url.path, "com.apple.quarantine", bytes.baseAddress, bytes.count, 0, XATTR_NOFOLLOW)
        }
        guard count >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        value.count = count
        return value
    }
}
#endif
