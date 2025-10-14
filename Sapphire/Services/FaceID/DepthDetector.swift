//
//  DepthDetector.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-09-14
//

import Vision
import CoreImage
import Accelerate

class DepthDetector {

    private var registeredDepthMaps: [CVPixelBuffer] = []
    private let maxStoredDepthMaps = 5
    private let minAcceptableScore: Double = 0.45
    private let initialCalibrationFrames = 3
    private var isCalibrated = false
    private var calibrationSamples = 0

    func reset() {
        registeredDepthMaps.removeAll()
        isCalibrated = false
        calibrationSamples = 0
        print("LOG (Depth): Reset depth detector")
    }

    private func addRegisteredDepthMap(_ map: CVPixelBuffer) {
        registeredDepthMaps.append(map)
        if registeredDepthMaps.count > maxStoredDepthMaps {
            registeredDepthMaps.removeFirst()
        }
    }

    func register(pixelBuffer: CVPixelBuffer) {
        if let depthMap = generateDepthMap(for: pixelBuffer) {
            addRegisteredDepthMap(depthMap)
        }
    }

    func getDepthSimilarity(for pixelBuffer: CVPixelBuffer) async -> Double {
        if !isCalibrated && registeredDepthMaps.isEmpty {
            if calibrationSamples < initialCalibrationFrames {
                if let depthMap = generateDepthMap(for: pixelBuffer) {
                    addRegisteredDepthMap(depthMap)
                    calibrationSamples += 1
                    if calibrationSamples >= initialCalibrationFrames {
                        isCalibrated = true
                    }
                }
                return 0.95
            }
        }
        guard !registeredDepthMaps.isEmpty else { return 0.0 }
        guard let currentMap = generateDepthMap(for: pixelBuffer) else { return 0.0 }

        var bestSimilarity = 0.0
        let similarities = registeredDepthMaps.map { self.calculateSSIM(between: $0, and: currentMap) }
        bestSimilarity = similarities.max() ?? 0.0

        if bestSimilarity > minAcceptableScore && bestSimilarity < 0.7 {
            addRegisteredDepthMap(currentMap)
        }
        return bestSimilarity
    }

    func hasEnoughDepthData() -> Bool {
        return isCalibrated || !registeredDepthMaps.isEmpty
    }

    func serializeDepthMaps() -> [Data] {
        return registeredDepthMaps.compactMap(serializeDepthMap)
    }

    func loadDepthMaps(from serializedMaps: [Data]) {
        reset()
        for mapData in serializedMaps {
            if let pixelBuffer = deserializeDepthMap(mapData) {
                addRegisteredDepthMap(pixelBuffer)
            }
        }
        isCalibrated = !registeredDepthMaps.isEmpty
        print("LOG (Depth): Loaded \(registeredDepthMaps.count) depth maps from storage")
    }

    private func generateDepthMap(for pixelBuffer: CVPixelBuffer) -> CVPixelBuffer? {
        guard let visionModel = MLModelManager.shared.depthVisionModel else {
            print("ERROR (ML): Depth Vision model is not loaded. Cannot generate depth map.")
            return nil
        }

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])

        let request = VNCoreMLRequest(model: visionModel)

        do {
            try handler.perform([request])
            guard let results = request.results as? [VNPixelBufferObservation],
                  let firstResult = results.first else {
                return nil
            }
            return firstResult.pixelBuffer
        } catch {
            print("Error performing depth analysis: \(error)")
            return nil
        }
    }

    private func calculateSSIM(between bufferA: CVPixelBuffer, and bufferB: CVPixelBuffer) -> Double {
        CVPixelBufferLockBaseAddress(bufferA, .readOnly); defer { CVPixelBufferUnlockBaseAddress(bufferA, .readOnly) }
        CVPixelBufferLockBaseAddress(bufferB, .readOnly); defer { CVPixelBufferUnlockBaseAddress(bufferB, .readOnly) }
        guard let baseAddressA = CVPixelBufferGetBaseAddress(bufferA), let baseAddressB = CVPixelBufferGetBaseAddress(bufferB) else { return 0.0 }
        let width = min(CVPixelBufferGetWidth(bufferA), CVPixelBufferGetWidth(bufferB)), height = min(CVPixelBufferGetHeight(bufferA), CVPixelBufferGetHeight(bufferB))
        let bytesPerRowA = CVPixelBufferGetBytesPerRow(bufferA), bytesPerRowB = CVPixelBufferGetBytesPerRow(bufferB)
        let centerX = width / 2, centerY = height / 2, regionSize = min(width, height) / 3
        let startX = max(0, centerX - regionSize), startY = max(0, centerY - regionSize)
        let endX = min(width, centerX + regionSize), endY = min(height, centerY + regionSize)
        var valuesA: [Float] = [], valuesB: [Float] = []
        valuesA.reserveCapacity((endX - startX) * (endY - startY)); valuesB.reserveCapacity((endX - startX) * (endY - startY))
        for y in startY..<endY {
            let rowPointerA = baseAddressA.advanced(by: y * bytesPerRowA), rowPointerB = baseAddressB.advanced(by: y * bytesPerRowB)
            for x in startX..<endX {
                valuesA.append(rowPointerA.load(fromByteOffset: x * 4, as: Float32.self))
                valuesB.append(rowPointerB.load(fromByteOffset: x * 4, as: Float32.self))
            }
        }
        let count = Float(valuesA.count); guard count > 0 else { return 0.0 }
        let meanA = valuesA.reduce(0, +) / count, meanB = valuesB.reduce(0, +) / count
        let varA = valuesA.map { pow($0 - meanA, 2) }.reduce(0, +) / count, varB = valuesB.map { pow($0 - meanB, 2) }.reduce(0, +) / count
        var covariance: Float = 0.0; for i in 0..<Int(count) { covariance += (valuesA[i] - meanA) * (valuesB[i] - meanB) }; covariance /= count
        let k1: Float = 0.01, k2: Float = 0.03, L: Float = 1.0, c1 = (k1 * L) * (k1 * L), c2 = (k2 * L) * (k2 * L)
        return Double(((2 * meanA * meanB + c1) * (2 * covariance + c2)) / ((meanA * meanA + meanB * meanB + c1) * (varA + varB + c2)))
    }

    private func serializeDepthMap(_ pixelBuffer: CVPixelBuffer) -> Data? {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly); defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        let width = CVPixelBufferGetWidth(pixelBuffer), height = CVPixelBufferGetHeight(pixelBuffer), bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }
        var header = DepthMapHeader(width: Int32(width), height: Int32(height), bytesPerRow: Int32(bytesPerRow))
        var data = Data(bytes: &header, count: MemoryLayout<DepthMapHeader>.size)
        data.append(Data(bytes: baseAddress, count: bytesPerRow * height))
        return data
    }

    private func deserializeDepthMap(_ data: Data) -> CVPixelBuffer? {
        guard data.count > MemoryLayout<DepthMapHeader>.size else { return nil }
        let header = data.withUnsafeBytes { $0.load(as: DepthMapHeader.self) }
        let width = Int(header.width), height = Int(header.height)
        var pixelBuffer: CVPixelBuffer?
        let attrs = [kCVPixelBufferIOSurfacePropertiesKey: [:], kCVPixelBufferCGImageCompatibilityKey: true, kCVPixelBufferCGBitmapContextCompatibilityKey: true] as CFDictionary
        let status = CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, attrs, &pixelBuffer)
        guard status == kCVReturnSuccess, let pbuf = pixelBuffer else { return nil }
        CVPixelBufferLockBaseAddress(pbuf, []); defer { CVPixelBufferUnlockBaseAddress(pbuf, []) }
        guard let baseAddress = CVPixelBufferGetBaseAddress(pbuf) else { return nil }
        let pixelDataOffset = MemoryLayout<DepthMapHeader>.size
        data.withUnsafeBytes { rawPtr in memcpy(baseAddress, rawPtr.baseAddress! + pixelDataOffset, data.count - pixelDataOffset) }
        return pbuf
    }
}

struct DepthMapHeader {
    let width: Int32
    let height: Int32
    let bytesPerRow: Int32
}