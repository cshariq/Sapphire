//
//  FileConversionManager.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-08-12.
//

import Foundation
import Combine
import AppKit
import ImageIO
import UniformTypeIdentifiers
import AVFoundation
import UserNotifications

struct ConversionFormat: Identifiable, Hashable {
    let id: String
    let displayName: String
    let iconName: String
    let targetUTType: UTType
}

enum FileConversionError: LocalizedError {
    case unreadableSource(String)
    case cannotCreateOutput
    case unsupported(String)
    case exportFailed(String)

    var errorDescription: String? {
        switch self {
        case .unreadableSource(let name): return "Couldn't read \(name)."
        case .cannotCreateOutput: return "Couldn't create the converted file."
        case .unsupported(let detail): return detail
        case .exportFailed(let detail): return detail
        }
    }
}

@MainActor
class FileConversionManager {
    static let shared = FileConversionManager()

    let progressPublisher = PassthroughSubject<(UUID, Double), Never>()
    let completionPublisher = PassthroughSubject<(UUID, Result<URL, Error>), Never>()

    func availableFormats(for fileURL: URL) -> [ConversionFormat] {
        guard let type = try? fileURL.resourceValues(forKeys: [.contentTypeKey]).contentType else {
            return []
        }

        let hasAdvancedConversion = SubscriptionManager.shared.isFeatureEnabled(.advancedFileConversion)
        var formats: [ConversionFormat] = []

        if type.conforms(to: .image) {
            formats.append(contentsOf: [
                .init(id: "png", displayName: "PNG", iconName: "photo", targetUTType: .png),
                .init(id: "jpeg", displayName: "JPEG", iconName: "photo", targetUTType: .jpeg),
                .init(id: "heic", displayName: "HEIC", iconName: "photo", targetUTType: .heic),
                .init(id: "tiff", displayName: "TIFF", iconName: "photo", targetUTType: .tiff),
                .init(id: "bmp", displayName: "BMP", iconName: "photo", targetUTType: .bmp)
            ])
        }

        if type.conforms(to: .movie), hasAdvancedConversion {
            formats.append(contentsOf: [
                .init(id: "mov", displayName: "MOV", iconName: "video.fill", targetUTType: .quickTimeMovie),
                .init(id: "mp4", displayName: "MP4", iconName: "video.fill", targetUTType: .mpeg4Movie),
                .init(id: "m4v", displayName: "M4V", iconName: "video.fill", targetUTType: UTType("com.apple.m4v-video") ?? .mpeg4Movie)
            ])
        }

        if type.conforms(to: .compositeContent) || type.conforms(to: .text) {
            if hasAdvancedConversion {
                formats.append(contentsOf: [
                    .init(id: "pdf", displayName: "PDF", iconName: "doc.richtext.fill", targetUTType: .pdf),
                    .init(id: "rtf", displayName: "RTF", iconName: "doc.richtext", targetUTType: .rtf)
                ])
            }
            formats.append(.init(id: "txt", displayName: "TXT", iconName: "doc.text", targetUTType: .plainText))
        }

        if type.conforms(to: .audio), hasAdvancedConversion {
            formats.append(contentsOf: [
                .init(id: "m4a", displayName: "M4A", iconName: "music.note", targetUTType: .mpeg4Audio)
            ])
        }

        return formats.filter { $0.targetUTType != type }
    }

    func convert(taskID: UUID, from sourceURL: URL, to format: ConversionFormat) {
        let progress = progressPublisher
        let completion = completionPublisher
        Task.detached(priority: .userInitiated) {
            let staging = FileManager.default.temporaryDirectory
                .appendingPathComponent("SapphireConversion-\(UUID().uuidString)", isDirectory: true)
            let ext = Self.fileExtension(for: format)
            let stagedURL = staging.appendingPathComponent("output").appendingPathExtension(ext)
            defer { try? FileManager.default.removeItem(at: staging) }

            do {
                try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
                let report: @Sendable (Double) -> Void = { value in
                    DispatchQueue.main.async { progress.send((taskID, min(0.99, value))) }
                }
                let target = format.targetUTType
                if target.conforms(to: .image) {
                    try Self.convertImage(from: sourceURL, to: stagedURL, as: target)
                } else if target.conforms(to: .audiovisualContent), !target.conforms(to: .audio) {
                    try await Self.export(from: sourceURL, to: stagedURL, fileType: Self.avFileType(for: format), audioOnly: false, progress: report)
                } else if target.conforms(to: .audio) {
                    try await Self.export(from: sourceURL, to: stagedURL, fileType: .m4a, audioOnly: true, progress: report)
                } else if target == .pdf || target.conforms(to: .text) {
                    try await Self.convertTextDocument(from: sourceURL, to: stagedURL, as: target)
                } else {
                    throw FileConversionError.unsupported("Converting to \(format.displayName) isn't supported.")
                }

                let finalURL = try Self.publish(stagedURL, source: sourceURL, ext: ext)
                await MainActor.run {
                    progress.send((taskID, 1.0))
                    completion.send((taskID, .success(finalURL)))
                    NSWorkspace.shared.activateFileViewerSelecting([finalURL])
                }
            } catch {
                print("[FileConversionManager] Conversion failed: \(error)")
                await MainActor.run {
                    completion.send((taskID, .failure(error)))
                }
                await Self.notifyFailure(fileName: sourceURL.lastPathComponent, format: format.displayName, error: error)
            }
        }
    }

    // MARK: - Output placement

    nonisolated static func fileExtension(for format: ConversionFormat) -> String {
        switch format.id {
        case "jpeg": return "jpg"
        case "tiff": return "tiff"
        case "mov", "mp4", "m4v", "m4a", "png", "heic", "bmp", "pdf", "rtf", "txt": return format.id
        default: return format.targetUTType.preferredFilenameExtension ?? format.id
        }
    }

    nonisolated static func avFileType(for format: ConversionFormat) -> AVFileType {
        switch format.id {
        case "mov": return .mov
        case "m4v": return .m4v
        case "m4a": return .m4a
        default: return .mp4
        }
    }

    private nonisolated static func publish(_ stagedURL: URL, source: URL, ext: String) throws -> URL {
        let fileManager = FileManager.default
        let sourceFolder = source.deletingLastPathComponent()
        let directory: URL
        if !FileShelfManager.isVolatileLocation(source),
           !source.path.contains("/com.shariq.Sapphire.FileShelf/"),
           fileManager.isWritableFile(atPath: sourceFolder.path) {
            directory = sourceFolder
        } else {
            directory = fileManager.urls(for: .downloadsDirectory, in: .userDomainMask).first ?? sourceFolder
        }
        let base = source.deletingPathExtension().lastPathComponent
        for _ in 0..<5 {
            let destination = UniqueFileName.url(in: directory, base: base, pathExtension: ext)
            do {
                try fileManager.moveItem(at: stagedURL, to: destination)
                return destination
            } catch CocoaError.fileWriteFileExists {
                continue
            }
        }
        throw FileConversionError.cannotCreateOutput
    }

    // MARK: - Images

    private nonisolated static func convertImage(from sourceURL: URL, to destinationURL: URL, as type: UTType) throws {
        guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil), CGImageSourceGetCount(source) > 0 else {
            throw FileConversionError.unreadableSource(sourceURL.lastPathComponent)
        }
        guard let destination = CGImageDestinationCreateWithURL(destinationURL as CFURL, type.identifier as CFString, 1, nil) else {
            throw FileConversionError.cannotCreateOutput
        }
        var properties = (CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]) ?? [:]
        if type == .jpeg || type == .heic {
            properties[kCGImageDestinationLossyCompressionQuality] = 0.92
        }

        let hasAlpha = (properties[kCGImagePropertyHasAlpha] as? Bool) ?? false
        if hasAlpha, type == .jpeg || type == .bmp {
            guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
                  let flattened = flattenedOnWhite(image) else {
                throw FileConversionError.unreadableSource(sourceURL.lastPathComponent)
            }
            properties[kCGImagePropertyHasAlpha] = false
            CGImageDestinationAddImage(destination, flattened, properties as CFDictionary)
        } else {
            CGImageDestinationAddImageFromSource(destination, source, 0, properties as CFDictionary)
        }
        guard CGImageDestinationFinalize(destination) else {
            throw FileConversionError.exportFailed("Couldn't write the \(type.preferredFilenameExtension?.uppercased() ?? "image") file.")
        }
    }

    private nonisolated static func flattenedOnWhite(_ image: CGImage) -> CGImage? {
        let colorSpace = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(
            data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace.model == .rgb ? colorSpace : CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return context.makeImage()
    }

    // MARK: - Audio / video

    private nonisolated static func export(
        from sourceURL: URL,
        to destinationURL: URL,
        fileType: AVFileType,
        audioOnly: Bool,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        let asset = AVURLAsset(url: sourceURL)
        guard try await asset.load(.isExportable) else {
            throw FileConversionError.unsupported("\(sourceURL.lastPathComponent) can't be exported (it may be protected).")
        }
        let presets = audioOnly
            ? [AVAssetExportPresetAppleM4A]
            : [AVAssetExportPresetPassthrough, AVAssetExportPresetHighestQuality]
        var lastError: Error = FileConversionError.unsupported("No export preset can write this file type.")
        for preset in presets {
            guard let session = AVAssetExportSession(asset: asset, presetName: preset) else { continue }
            let supported = await session.compatibleFileTypes
            guard supported.contains(fileType) else { continue }
            try? FileManager.default.removeItem(at: destinationURL)
            session.outputURL = destinationURL
            session.outputFileType = fileType
            do {
                try await run(session, progress: progress)
                return
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    private nonisolated static func run(_ session: AVAssetExportSession, progress: @escaping @Sendable (Double) -> Void) async throws {
        let box = ExportSessionBox(session)
        let poller = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        poller.schedule(deadline: .now() + 0.2, repeating: 0.2)
        poller.setEventHandler { progress(Double(box.session.progress)) }
        poller.resume()
        defer { poller.cancel() }

        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                box.session.exportAsynchronously { continuation.resume() }
            }
        } onCancel: {
            box.session.cancelExport()
        }
        switch session.status {
        case .completed:
            return
        case .cancelled:
            throw CancellationError()
        default:
            throw session.error ?? FileConversionError.exportFailed("Export failed.")
        }
    }

    // MARK: - Documents

    private nonisolated static func convertTextDocument(from sourceURL: URL, to destinationURL: URL, as type: UTType) async throws {
        let sourceType = (try? sourceURL.resourceValues(forKeys: [.contentTypeKey]))?.contentType
        let attributedString: NSAttributedString
        if sourceType?.conforms(to: .html) == true {
            attributedString = try await MainActor.run {
                try NSAttributedString(url: sourceURL, options: [:], documentAttributes: nil)
            }
        } else {
            attributedString = try NSAttributedString(url: sourceURL, options: [:], documentAttributes: nil)
        }

        let data: Data
        switch type {
        case .pdf:
            data = try paginatedPDF(attributedString)
        case .rtf:
            data = try attributedString.data(
                from: NSRange(location: 0, length: attributedString.length),
                documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
            )
        case .plainText:
            data = Data(attributedString.string.utf8)
        default:
            throw FileConversionError.unsupported("Unsupported document type.")
        }
        try data.write(to: destinationURL, options: .atomic)
    }

    private nonisolated static func paginatedPDF(_ attributed: NSAttributedString) throws -> Data {
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
        let textRect = pageRect.insetBy(dx: 54, dy: 54)
        let pdfData = NSMutableData()
        var mediaBox = pageRect
        guard let consumer = CGDataConsumer(data: pdfData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw FileConversionError.cannotCreateOutput
        }
        let text = attributed.length > 0 ? attributed : NSAttributedString(string: " ")
        let framesetter = CTFramesetterCreateWithAttributedString(text)
        let path = CGPath(rect: textRect, transform: nil)
        var location = 0
        repeat {
            context.beginPDFPage(nil)
            let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: location, length: 0), path, nil)
            CTFrameDraw(frame, context)
            context.endPDFPage()
            let visible = CTFrameGetVisibleStringRange(frame)
            guard visible.length > 0 else { break }
            location += visible.length
        } while location < text.length
        context.closePDF()
        return pdfData as Data
    }

    // MARK: - Failure feedback

    private nonisolated static func notifyFailure(fileName: String, format: String, error: Error) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
        let content = UNMutableNotificationContent()
        content.title = "Couldn't convert \(fileName) to \(format)"
        content.body = error.localizedDescription
        try? await center.add(UNNotificationRequest(identifier: "file-conversion-\(UUID().uuidString)", content: content, trigger: nil))
    }
}

private final class ExportSessionBox: @unchecked Sendable {
    let session: AVAssetExportSession
    init(_ session: AVAssetExportSession) { self.session = session }
}