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

    private let minAcceptableScore: Double = 0.45
    private let initialCalibrationFrames = 3
    private var isCalibrated = false
    private var calibrationSamples = 0

    private var depthRequest: VNCoreMLRequest?

    func reset() {
        registeredDepthMaps.removeAll()
        isCalibrated = false
        calibrationSamples = 0
        depthRequest = nil
        print("LOG (Depth): Reset depth detector")
    }

    func register(pixelBuffer: CVPixelBuffer) {
        print("LOG (Depth): Generating and storing registration depth map...")
        if let depthMap = generateDepthMap(for: pixelBuffer) {
            registeredDepthMaps.append(depthMap)
            print("LOG (Depth): Successfully added depth map. Total maps: \(registeredDepthMaps.count)")
        } else {
            print("LOG (Depth): Failed to generate depth map for registration")
        }
    }

    func getDepthSimilarity(for pixelBuffer: CVPixelBuffer) async -> Double {
        if !isCalibrated && registeredDepthMaps.isEmpty {
            if calibrationSamples < initialCalibrationFrames {
                if let depthMap = generateDepthMap(for: pixelBuffer) {
                    registeredDepthMaps.append(depthMap)
                    calibrationSamples += 1
                    print("LOG (Depth): Added calibration frame \(calibrationSamples)/\(initialCalibrationFrames)")

                    if calibrationSamples >= initialCalibrationFrames {
                        isCalibrated = true
                        print("LOG (Depth): Initial calibration complete")
                    }
                }
                return 0.95
            }
        }

        guard !registeredDepthMaps.isEmpty else {
            print("LOG (Depth): No registered depth maps for comparison.")
            return 0.0
        }

        let depthMapTask = Task.detached(priority: .userInitiated) {
            return self.generateDepthMap(for: pixelBuffer)
        }

        guard let currentMap = await depthMapTask.value else {
            print("LOG (Depth): Failed to generate current depth map for comparison.")
            return 0.0
        }

        var bestSimilarity = 0.0

        let similarities = await Task.detached(priority: .userInitiated) { () -> [Double] in
            var results = [Double]()
            for registeredMap in self.registeredDepthMaps {
                let similarity = self.calculateSSIM(between: registeredMap, and: currentMap)
                results.append(similarity)
            }
            return results
        }.value

        bestSimilarity = similarities.max() ?? 0.0

        print("LOG (Depth): Best similarity score: \(bestSimilarity), Threshold: \(minAcceptableScore)")

        if bestSimilarity > minAcceptableScore && bestSimilarity < 0.7 {
            registeredDepthMaps.append(currentMap)
            if registeredDepthMaps.count > 10 {
                registeredDepthMaps.removeFirst()
            }
            print("LOG (Depth): Added new depth map for future reference")
        }

        return bestSimilarity
    }

    func hasEnoughDepthData() -> Bool {
        return isCalibrated || !registeredDepthMaps.isEmpty
    }

    func serializeDepthMaps() -> [Data] {
        return registeredDepthMaps.compactMap { pixelBuffer in
            return serializeDepthMap(pixelBuffer)
        }
    }

    func loadDepthMaps(from serializedMaps: [Data]) {
        reset()
        for mapData in serializedMaps {
            if let pixelBuffer = deserializeDepthMap(mapData) {
                registeredDepthMaps.append(pixelBuffer)
            }
        }
        isCalibrated = !registeredDepthMaps.isEmpty
        print("LOG (Depth): Loaded \(registeredDepthMaps.count) depth maps from storage")
    }

    private func generateDepthMap(for pixelBuffer: CVPixelBuffer) -> CVPixelBuffer? {
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])

        do {
            if self.depthRequest == nil {
                print("LOG (Depth): Creating and caching VNCoreMLRequest for depth model.")
                let model = try MLModelManager.shared.getDepthModel()
                self.depthRequest = VNCoreMLRequest(model: model)
            }

            guard let request = self.depthRequest else {
                print("Error: Depth request is nil after attempting creation.")
                return nil
            }

            try handler.perform([request])
            guard let results = request.results as? [VNPixelBufferObservation],
                  let firstResult = results.first else {
                return nil
            }
            return firstResult.pixelBuffer
        } catch {
            print("Error performing depth analysis: \(error)")
            self.depthRequest = nil
            return nil
        }
    }

    private func calculateSSIM(between bufferA: CVPixelBuffer, and bufferB: CVPixelBuffer) -> Double {
        CVPixelBufferLockBaseAddress(bufferA, .readOnly); defer { CVPixelBufferUnlockBaseAddress(bufferA, .readOnly) }
        CVPixelBufferLockBaseAddress(bufferB, .readOnly); defer { CVPixelBufferUnlockBaseAddress(bufferB, .readOnly) }

        guard let baseAddressA = CVPixelBufferGetBaseAddress(bufferA),
              let baseAddressB = CVPixelBufferGetBaseAddress(bufferB) else { return 0.0 }

        let width = min(CVPixelBufferGetWidth(bufferA), CVPixelBufferGetWidth(bufferB))
        let height = min(CVPixelBufferGetHeight(bufferA), CVPixelBufferGetHeight(bufferB))
        let bytesPerRowA = CVPixelBufferGetBytesPerRow(bufferA)
        let bytesPerRowB = CVPixelBufferGetBytesPerRow(bufferB)

        let centerX = width / 2
        let centerY = height / 2
        let regionSize = min(width, height) / 3

        let startX = max(0, centerX - regionSize)
        let startY = max(0, centerY - regionSize)
        let endX = min(width, centerX + regionSize)
        let endY = min(height, centerY + regionSize)

        var valuesA: [Float] = []
        var valuesB: [Float] = []
        valuesA.reserveCapacity((endX - startX) * (endY - startY))
        valuesB.reserveCapacity((endX - startX) * (endY - startY))

        for y in startY..<endY {
            let rowPointerA = baseAddressA.advanced(by: y * bytesPerRowA)
            let rowPointerB = baseAddressB.advanced(by: y * bytesPerRowB)

            for x in startX..<endX {
                let valueA: Float
                let valueB: Float

                valueA = rowPointerA.load(fromByteOffset: x * 4, as: Float32.self)
                valueB = rowPointerB.load(fromByteOffset: x * 4, as: Float32.self)

                valuesA.append(valueA)
                valuesB.append(valueB)
            }
        }

        let count = Float(valuesA.count)
        guard count > 0 else { return 0.0 }

        let meanA = valuesA.reduce(0, +) / count
        let meanB = valuesB.reduce(0, +) / count

        let varA = valuesA.map { pow($0 - meanA, 2) }.reduce(0, +) / count
        let varB = valuesB.map { pow($0 - meanB, 2) }.reduce(0, +) / count

        var covariance: Float = 0.0
        for i in 0..<Int(count) {
            covariance += (valuesA[i] - meanA) * (valuesB[i] - meanB)
        }
        covariance /= count

        let k1: Float = 0.01, k2: Float = 0.03
        let L: Float = 1.0
        let c1 = (k1 * L) * (k1 * L)
        let c2 = (k2 * L) * (k2 * L)

        let ssim = ((2 * meanA * meanB + c1) * (2 * covariance + c2)) / ((meanA * meanA + meanB * meanB + c1) * (varA + varB + c2))

        return Double(ssim)
    }

    private func serializeDepthMap(_ pixelBuffer: CVPixelBuffer) -> Data? {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }

        var header = DepthMapHeader(width: Int32(width), height: Int32(height), bytesPerRow: Int32(bytesPerRow))

        var data = Data(bytes: &header, count: MemoryLayout<DepthMapHeader>.size)

        data.append(Data(bytes: baseAddress, count: bytesPerRow * height))

        return data
    }

    private func deserializeDepthMap(_ data: Data) -> CVPixelBuffer? {
        guard data.count > MemoryLayout<DepthMapHeader>.size else { return nil }

        let header = data.withUnsafeBytes { $0.load(as: DepthMapHeader.self) }
        let width = Int(header.width)
        let height = Int(header.height)
        let bytesPerRow = Int(header.bytesPerRow)

        var pixelBuffer: CVPixelBuffer?
        let attrs = [
            kCVPixelBufferIOSurfacePropertiesKey: [:],
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true
        ] as CFDictionary

        let status = CVPixelBufferCreate(kCFAllocatorDefault,
                                        width,
                                        height,
                                        kCVPixelFormatType_32BGRA,
                                        attrs,
                                        &pixelBuffer)

        guard status == kCVReturnSuccess, let pixelBuffer = pixelBuffer else { return nil }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }

        let pixelDataOffset = MemoryLayout<DepthMapHeader>.size
        data.withUnsafeBytes { rawPtr in
            let sourcePtr = rawPtr.baseAddress! + pixelDataOffset
            memcpy(baseAddress, sourcePtr, data.count - pixelDataOffset)
        }

        return pixelBuffer
    }
}

struct DepthMapHeader {
    let width: Int32
    let height: Int32
    let bytesPerRow: Int32
}