//
//  FileConversionManager.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-08-12.
//

import Foundation
import Combine
import AppKit
import UniformTypeIdentifiers
import AVFoundation

struct ConversionFormat: Identifiable, Hashable {
    let id: String
    let displayName: String
    let iconName: String
    let targetUTType: UTType
}

@MainActor
class FileConversionManager {
    static let shared = FileConversionManager()

    let progressPublisher = PassthroughSubject<(UUID, Double), Never>()

    func availableFormats(for fileURL: URL) -> [ConversionFormat] {
        guard let type = try? fileURL.resourceValues(forKeys: [.contentTypeKey]).contentType else {
            return []
        }

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

        if type.conforms(to: .movie) {
             formats.append(contentsOf: [
                .init(id: "mov", displayName: "MOV", iconName: "video.fill", targetUTType: .quickTimeMovie),
                .init(id: "mp4", displayName: "MP4", iconName: "video.fill", targetUTType: .mpeg4Movie)
            ])
        }

        if type.conforms(to: .compositeContent) || type.conforms(to: .text) {
            formats.append(contentsOf: [
                .init(id: "pdf", displayName: "PDF", iconName: "doc.richtext.fill", targetUTType: .pdf),
                .init(id: "rtf", displayName: "RTF", iconName: "doc.richtext", targetUTType: .rtf),
                .init(id: "txt", displayName: "TXT", iconName: "doc.text", targetUTType: .plainText)
            ])
        }

        if type.conforms(to: .audio) {
            formats.append(contentsOf: [
                .init(id: "m4a", displayName: "M4A", iconName: "music.note", targetUTType: .mpeg4Audio)
            ])
        }

        return formats.filter { $0.targetUTType != type }
    }

    func convert(taskID: UUID, from sourceURL: URL, to format: ConversionFormat) {
        Task.detached(priority: .userInitiated) {
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(for: format.targetUTType)

            let finalBaseName = sourceURL.deletingPathExtension().lastPathComponent.components(separatedBy: "_").last ?? "ConvertedFile"

            do {
                if format.targetUTType.conforms(to: .image) {
                    try await self.convertImage(from: sourceURL, to: tempURL, as: format.targetUTType)
                } else if format.targetUTType.conforms(to: .movie) {
                    try await self.convertVideo(taskID: taskID, from: sourceURL, to: tempURL)
                } else if format.targetUTType.conforms(to: .audio) {
                    try await self.convertAudio(taskID: taskID, from: sourceURL, to: tempURL)
                } else if format.targetUTType == .pdf || format.targetUTType.conforms(to: .text) {
                    try await self.convertTextDocument(from: sourceURL, to: tempURL, as: format.targetUTType)
                }

                await MainActor.run {
                    self.progressPublisher.send((taskID, 1.0))
                    self.promptToSave(fileAt: tempURL, desiredName: finalBaseName, allowedType: format.targetUTType)
                }
            } catch {
                print("[FileConversionManager] Conversion failed: \(error)")
                try? FileManager.default.removeItem(at: tempURL)
            }
        }
    }

    private func promptToSave(fileAt tempURL: URL, desiredName: String, allowedType: UTType) {
        let savePanel = NSSavePanel()
        savePanel.nameFieldStringValue = desiredName
        savePanel.allowedContentTypes = [allowedType]

        savePanel.begin { response in
            if response == .OK, let finalURL = savePanel.url {
                do {
                    if FileManager.default.fileExists(atPath: finalURL.path) {
                        try FileManager.default.removeItem(at: finalURL)
                    }
                    try FileManager.default.moveItem(at: tempURL, to: finalURL)
                    NSWorkspace.shared.activateFileViewerSelecting([finalURL])
                } catch {
                    print("[FileConversionManager] Failed to move converted file: \(error)")
                }
            } else {
                try? FileManager.default.removeItem(at: tempURL)
            }
        }
    }

    private func convertImage(from sourceURL: URL, to destinationURL: URL, as type: UTType) throws {
        guard let image = NSImage(contentsOf: sourceURL),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let destination = CGImageDestinationCreateWithURL(destinationURL as CFURL, type.identifier as CFString, 1, nil)
        else {
            throw NSError(domain: "FileConversionError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not read source image or create destination."])
        }

        CGImageDestinationAddImage(destination, cgImage, nil)
        if !CGImageDestinationFinalize(destination) {
            throw NSError(domain: "FileConversionError", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to write image to destination."])
        }
    }

    private func convertVideo(taskID: UUID, from sourceURL: URL, to destinationURL: URL) async throws {
        let asset = AVAsset(url: sourceURL)
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
            throw NSError(domain: "FileConversionError", code: 3, userInfo: [NSLocalizedDescriptionKey: "Could not create AVAssetExportSession for video."])
        }

        exportSession.outputURL = destinationURL
        exportSession.outputFileType = AVFileType(destinationURL.pathExtension)

        try await monitorExportProgress(for: exportSession, taskID: taskID)
    }

    private func convertAudio(taskID: UUID, from sourceURL: URL, to destinationURL: URL) async throws {
        let asset = AVAsset(url: sourceURL)
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw NSError(domain: "FileConversionError", code: 4, userInfo: [NSLocalizedDescriptionKey: "Could not create AVAssetExportSession for audio."])
        }

        exportSession.outputURL = destinationURL
        exportSession.outputFileType = .m4a

        try await monitorExportProgress(for: exportSession, taskID: taskID)
    }

    private func convertTextDocument(from sourceURL: URL, to destinationURL: URL, as type: UTType) throws {
        let attributedString = try NSAttributedString(url: sourceURL, options: [:], documentAttributes: nil)

        let data: Data
        switch type {
        case .pdf:
            let pdfData = NSMutableData()
            guard let consumer = CGDataConsumer(data: pdfData),
                  let context = CGContext(consumer: consumer, mediaBox: nil, nil) else {
                throw NSError(domain: "FileConversionError", code: 5, userInfo: [NSLocalizedDescriptionKey: "Could not create PDF context."])
            }
            let frameSetter = CTFramesetterCreateWithAttributedString(attributedString)
            let path = CGPath(rect: CGRect(x: 0, y: 0, width: 595, height: 842), transform: nil)
            let frame = CTFramesetterCreateFrame(frameSetter, CFRangeMake(0, attributedString.length), path, nil)
            context.beginPDFPage(nil)
            CTFrameDraw(frame, context)
            context.endPDFPage()
            context.closePDF()
            data = pdfData as Data

        case .rtf:
            data = try attributedString.data(from: .init(location: 0, length: attributedString.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
        case .plainText:
            data = attributedString.string.data(using: .utf8) ?? Data()
        default:
            throw NSError(domain: "FileConversionError", code: 6, userInfo: [NSLocalizedDescriptionKey: "Unsupported text document type."])
        }

        try data.write(to: destinationURL)
    }

    private func monitorExportProgress(for session: AVAssetExportSession, taskID: UUID) async throws {
        let timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()
        let observationTask = Task {
            for await _ in timer.values {
                if session.status == .exporting {
                    let progress = session.progress
                    await MainActor.run {
                        self.progressPublisher.send((taskID, Double(progress)))
                    }
                } else {
                    break
                }
            }
        }

        await session.export()
        observationTask.cancel()

        if let error = session.error {
            throw error
        }
    }
}