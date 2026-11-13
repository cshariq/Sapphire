#if PUBLIC_BUILD
import Darwin
import Foundation
import OSLog

/// Preserves download quarantine when the public archive extractor places its output.
enum QuarantineAttribute {
    private static let name = "com.apple.quarantine"
    private static let logger = Logger(subsystem: "com.cshariq.sapphire", category: "ArchiveQuarantine")

    static func copy(from sources: [URL], to destination: URL, recursively: Bool) {
        guard let value = sources.lazy.compactMap({ read(from: $0) }).first else { return }
        write(value, to: destination)
        guard recursively,
              let root = try? destination.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
              root.isDirectory == true, root.isSymbolicLink != true,
              let entries = FileManager.default.enumerator(
                at: destination,
                includingPropertiesForKeys: [.isSymbolicLinkKey],
                options: [],
                errorHandler: { _, error in
                    logger.error("Cannot enumerate extracted item: \(error.localizedDescription, privacy: .private)")
                    return true
                }
              ) else { return }

        for case let item as URL in entries {
            if (try? item.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true {
                entries.skipDescendants()
            }
            write(value, to: item)
        }
    }

    private static func read(from url: URL) -> Data? {
        url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return nil }
            // Extraction opens the source target, so inherit that target's quarantine.
            let length = getxattr(path, name, nil, 0, 0, 0)
            guard length >= 0 else {
                if errno != ENOATTR {
                    logger.error("Cannot read archive quarantine: errno \(errno)")
                }
                return nil
            }
            var value = Data(count: length)
            let count = value.withUnsafeMutableBytes { bytes in
                getxattr(path, name, bytes.baseAddress, bytes.count, 0, 0)
            }
            guard count >= 0 else {
                logger.error("Cannot read archive quarantine: errno \(errno)")
                return nil
            }
            value.count = count
            return value
        }
    }

    private static func write(_ value: Data, to url: URL) {
        url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return }
            let result = value.withUnsafeBytes { bytes in
                // A link inside an archive must never change the linked file's attributes.
                setxattr(path, name, bytes.baseAddress, bytes.count, 0, XATTR_NOFOLLOW)
            }
            if result != 0 {
                logger.error("Cannot preserve archive quarantine: errno \(errno)")
            }
        }
    }
}
#endif
