//
//  FaceprintDatabase.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-09-15.
//

import Vision
import CoreML
import AppKit
import Combine
import os
import Accelerate

struct FaceprintDatabase: Codable {
    var individualPrints: [[Float]] = []
    var globalAverage: [Float] = []
    var learnedPrints: [[Float]] = []
}

typealias Faceprint = [Float]

class FaceDataStore {

    static let shared = FaceDataStore()

    private var profiles: [String: FaceprintDatabase] = [:]
    private var cancellables = Set<AnyCancellable>()
    private let logger = Logger(subsystem: "com.sapphire.app", category: "FaceID.FaceprintDatabase")

    private let maxLearnedPrints = 50
    private let secureFileURL: URL
    
    // Dynamic static buffers to achieve zero-heap-allocation during active streaming
    private(set) var faceBuffer112: CVPixelBuffer?
    private(set) var livenessBuffer128: CVPixelBuffer?
    
    // Pre-allocated MLMultiArrays to avoid instantiations inside loop
    private(set) var preallocatedFaceArray112: MLMultiArray?
    private(set) var preallocatedLivenessArray128: MLMultiArray?

    private init() {
        let fileManager = FileManager.default
        let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDirectoryURL = appSupportURL.appendingPathComponent(Bundle.main.bundleIdentifier ?? "FaceIDApp")

        if !fileManager.fileExists(atPath: appDirectoryURL.path) {
            try? fileManager.createDirectory(at: appDirectoryURL, withIntermediateDirectories: true, attributes: nil)
        }

        self.secureFileURL = appDirectoryURL.appendingPathComponent("faceprints_multi.encrypted")

        loadFromSecureStorage()

        if hasRegisteredFaceprints() {
            DispatchQueue.main.async {
                SettingsModel.shared.settings.hasRegisteredFaceID = true
            }
        }

        setupSettingsObserver()
        allocateStaticBuffers()
        MLModelManager.shared.prewarm()
    }

    private func setupSettingsObserver() {
        SettingsModel.shared.$settings
            .map(\.hasRegisteredFaceID)
            .removeDuplicates()
            .sink { [weak self] hasRegistered in
                guard let self = self else { return }
                if !hasRegistered && self.hasRegisteredFaceprints() {
                    DispatchQueue.main.async {
                        SettingsModel.shared.settings.hasRegisteredFaceID = true
                    }
                }
            }
            .store(in: &cancellables)
    }

    /// Dynamically allocates the static frame buffers when authentication is active.
    func allocateStaticBuffers() {
        if self.faceBuffer112 == nil {
            self.faceBuffer112 = createPixelBuffer(width: 112, height: 112)
        }
        if self.livenessBuffer128 == nil {
            self.livenessBuffer128 = createPixelBuffer(width: 128, height: 128)
        }
        if self.preallocatedFaceArray112 == nil {
            self.preallocatedFaceArray112 = try? MLMultiArray(shape: [1, 3, 112, 112], dataType: .float32)
        }
        if self.preallocatedLivenessArray128 == nil {
            self.preallocatedLivenessArray128 = try? MLMultiArray(shape: [1, 3, 128, 128], dataType: .float32)
        }
    }

    /// Clears and deallocates all static buffers to achieve a zero-RAM footprint when idle.
    func deallocateStaticBuffers() {
        self.faceBuffer112 = nil
        self.livenessBuffer128 = nil
        self.preallocatedFaceArray112 = nil
        self.preallocatedLivenessArray128 = nil
        self.logger.info("🧹 Zero-RAM Footprint: Deallocated all static camera buffers and float arrays from memory.")
    }

    private func createPixelBuffer(width: Int, height: Int) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer? = nil
        let attrs = [
            kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue,
            kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary // CRUCIAL: Enables GPU VRAM memory mapping for Metal
        ] as CFDictionary
        let status = CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, attrs, &pixelBuffer)
        return status == kCVReturnSuccess ? pixelBuffer : nil
    }

    func getRegisteredProfileNames() -> [String] {
        return profiles.keys.sorted()
    }

    func deleteProfile(name: String) {
        profiles.removeValue(forKey: name)
        saveToSecureStorage()
        if profiles.isEmpty {
            DispatchQueue.main.async {
                SettingsModel.shared.settings.hasRegisteredFaceID = false
            }
        }
        logger.info("Deleted face profile: \(name, privacy: .public)")
    }

    func hasRegisteredFaceprints() -> Bool {
        return !profiles.isEmpty
    }

    func reset() {
        profiles.removeAll()
        try? FileManager.default.removeItem(at: secureFileURL)
        logger.info("All face recognition data has been reset.")
        DispatchQueue.main.async {
            SettingsModel.shared.settings.hasRegisteredFaceID = false
        }
    }

    func register(faceprints: [Faceprint], forProfile name: String) {
        var newDatabase = FaceprintDatabase()

        let highQualityPrints = rejectOutliers(from: faceprints)
        logger.info("Registration: Started with \(faceprints.count) prints, filtered down to \(highQualityPrints.count) high-quality prints.")

        newDatabase.individualPrints = highQualityPrints

        if let globalAvg = average(faceprints: highQualityPrints) {
            newDatabase.globalAverage = globalAvg
        }

        profiles[name] = newDatabase
        saveToSecureStorage()

        DispatchQueue.main.async {
            SettingsModel.shared.settings.hasRegisteredFaceID = true
        }

        logger.info("✅ Registration successful for profile: \(name, privacy: .public)")
    }

    private func rejectOutliers(from faceprints: [Faceprint]) -> [Faceprint] {
        guard faceprints.count > 10 else { return faceprints }
        guard let averagePrint = average(faceprints: faceprints) else { return faceprints }

        let similarities = faceprints.map { cosineSimilarity($0, averagePrint) }
        let meanSimilarity = similarities.reduce(0, +) / Float(similarities.count)
        let sumOfSquaredDiffs = similarities.map { pow($0 - meanSimilarity, 2) }.reduce(0, +)
        let stdDev = sqrt(sumOfSquaredDiffs / Float(similarities.count))

        let cutoffSimilarity = meanSimilarity - (stdDev * 1.5)

        var filteredPrints: [Faceprint] = []
        for (index, sim) in similarities.enumerated() {
            if sim >= cutoffSimilarity {
                filteredPrints.append(faceprints[index])
            }
        }

        return filteredPrints
    }

    func getSimilarityScore(from currentEmbedding: [Float]) -> Double {
        var maxSimilarity: Float = -1.0

        for (_, database) in profiles {
            if !database.globalAverage.isEmpty {
                let sim = cosineSimilarity(currentEmbedding, database.globalAverage)
                maxSimilarity = max(maxSimilarity, sim)
            }
            for print in database.individualPrints {
                let sim = cosineSimilarity(currentEmbedding, print)
                maxSimilarity = max(maxSimilarity, sim)
            }
            for print in database.learnedPrints {
                let sim = cosineSimilarity(currentEmbedding, print)
                maxSimilarity = max(maxSimilarity, sim)
            }
        }

        let similarityScore = cosineToSimilarity(cosine: Double(maxSimilarity))
        logger.debug("Face Match - Cosine: \(String(format: "%.3f", maxSimilarity), privacy: .public) → Score: \(String(format: "%.1f%%", similarityScore * 100), privacy: .public)")
        return similarityScore
    }

    private func cosineToSimilarity(cosine: Double) -> Double {
        if cosine >= 0.60 {
            return 0.95 + (cosine - 0.60) * 0.125
        } else if cosine >= 0.45 {
            return 0.84 + ((cosine - 0.45) / 0.15) * 0.11
        } else if cosine >= 0.30 {
            return 0.70 + ((cosine - 0.30) / 0.15) * 0.14
        } else if cosine >= 0.20 {
            return 0.50 + ((cosine - 0.20) / 0.10) * 0.20
        } else {
            return max(0.0, (cosine + 0.1) / 0.3 * 0.50)
        }
    }

    func learnNewFaceprint(faceImage: NSImage) {
        guard let profileName = profiles.keys.first, var database = profiles[profileName] else { return }
        guard let newEmbedding = generateEmbedding(for: faceImage) else { return }

        var shouldLearn = true
        for existingPrint in database.learnedPrints {
            let sim = cosineSimilarity(newEmbedding, existingPrint)
            if sim > 0.95 {
                shouldLearn = false
                break
            }
        }

        if shouldLearn {
            database.learnedPrints.insert(newEmbedding, at: 0)
            if database.learnedPrints.count > maxLearnedPrints {
                database.learnedPrints = Array(database.learnedPrints.prefix(maxLearnedPrints))
            }
            profiles[profileName] = database
            saveToSecureStorage()
            logger.info("🎓 Learned new face variations (total: \(database.learnedPrints.count, privacy: .public))")
        }
    }

    private func saveToSecureStorage() {
        do {
            let jsonData = try JSONEncoder().encode(profiles)
            guard let encryptedData = CryptoManager.shared.encrypt(data: jsonData) else { return }
            try encryptedData.write(to: secureFileURL, options: .atomic)
        } catch {
            print("❌ Failed to save profiles: \(error)")
        }
    }

    private func loadFromSecureStorage() {
        guard FileManager.default.fileExists(atPath: secureFileURL.path) else { return }
        do {
            let encryptedData = try Data(contentsOf: secureFileURL)
            guard let decryptedData = CryptoManager.shared.decrypt(data: encryptedData) else { return }
            profiles = try JSONDecoder().decode([String: FaceprintDatabase].self, from: decryptedData)
            print("✅ Secure faceprint profiles loaded successfully.")
        } catch {
            print("❌ Error loading profiles: \(error)")
        }
    }

    // MARK: - Face Embedding Generation

    public func generateEmbedding(for observation: VNFaceObservation, from pixelBuffer: CVPixelBuffer) -> [Float]? {
        allocateStaticBuffers()
        
        guard let preparedCIImage = FaceProcessor.shared.prepareImage(from: pixelBuffer, faceObservation: observation) else {
            logger.error("Failed to prepare CIImage for embedding generation.")
            return nil
        }
        
        guard let array = try? MLMultiArray(shape: [1, 3, 112, 112], dataType: .float32) else { return nil }
        guard let tempBuffer = faceBuffer112 else { return nil }
        
        // EdgeFace expects standard RGB (isBGR: false, isNormalizedTo01: false)
        guard preprocess(ciImage: preparedCIImage, size: 112, targetBuffer: tempBuffer, targetArray: array, isBGR: false, isNormalizedTo01: false) else {
            return nil
        }
        
        do {
            return try MLModelManager.shared.predictEmbedding(from: array)
        } catch {
            logger.error("Failed to get prediction from model: \(error.localizedDescription)")
            return nil
        }
    }

    private func generateEmbedding(for image: NSImage) -> [Float]? {
        guard let mlArray = preprocess(image: image, size: 112) else {
            logger.error("Failed to preprocess image for embedding generation.")
            return nil
        }
        do {
            let embedding = try MLModelManager.shared.predictEmbedding(from: mlArray)
            return embedding
        } catch {
            logger.error("Failed to get prediction from model: \(error.localizedDescription)")
            return nil
        }
    }

    /// Legacy preprocessor fallback for NSImages (used during adaptive learning)
    func preprocess(image: NSImage, size: Int) -> MLMultiArray? {
        let targetSize = CGSize(width: size, height: size)
        guard let cgImage = image.cgImage else { return nil }
        
        guard let array = try? MLMultiArray(
            shape: [1, 3, NSNumber(value: size), NSNumber(value: size)],
            dataType: .float32
        ) else { return nil }
        
        guard let context = CGContext(
            data: nil,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: size * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        
        context.draw(resizedCGImage(cgImage, to: targetSize) ?? cgImage, in: CGRect(x: 0, y: 0, width: size, height: size))
        guard let pixelData = context.data else { return nil }
        let ptr = pixelData.bindMemory(to: UInt8.self, capacity: size * size * 4)
        
        array.withUnsafeMutableBytes { (dataPtr, strides) in
            guard let floatPtr = dataPtr.bindMemory(to: Float.self).baseAddress else { return }
            
            let channelStride = strides[1]
            let rowStride = strides[2]
            let colStride = strides[3]
            
            for y in 0..<size {
                let rowOffset = y * rowStride
                let pixelRowOffset = y * size * 4
                
                for x in 0..<size {
                    let pixelOffset = pixelRowOffset + x * 4
                    let outOffset = rowOffset + x * colStride
                    
                    let r = (Float(ptr[pixelOffset]) - 127.5) / 128.0
                    let g = (Float(ptr[pixelOffset + 1]) - 127.5) / 128.0
                    let b = (Float(ptr[pixelOffset + 2]) - 127.5) / 128.0
                    
                    floatPtr[outOffset] = r
                    floatPtr[outOffset + channelStride] = g
                    floatPtr[outOffset + (2 * channelStride)] = b
                }
            }
        }
        return array
    }

    /// Zero-copy GPU preprocessor rendering directly from CIImage to a static memory CVPixelBuffer, then mapping to MLMultiArray.
    /// Performs GPU scaling and dynamic channel swapping.
    func preprocess(ciImage: CIImage, size: Int, targetBuffer: CVPixelBuffer, targetArray: MLMultiArray, isBGR: Bool = false, isNormalizedTo01: Bool = false) -> Bool {
        // GPU scaling calculation
        let scaleX = CGFloat(size) / ciImage.extent.width
        let scaleY = CGFloat(size) / ciImage.extent.height
        let scaledImage = ciImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
        
        let bounds = CGRect(x: 0, y: 0, width: size, height: size)
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return false }
        
        // Render scaled CIImage (GPU) directly to static CVPixelBuffer
        FaceProcessor.shared.ciContext.render(scaledImage, to: targetBuffer, bounds: bounds, colorSpace: colorSpace)
        
        CVPixelBufferLockBaseAddress(targetBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(targetBuffer, .readOnly) }
        
        guard let baseAddress = CVPixelBufferGetBaseAddress(targetBuffer) else { return false }
        let ptr = baseAddress.bindMemory(to: UInt8.self, capacity: CVPixelBufferGetDataSize(targetBuffer))
        
        // Retrieve the true hardware-aligned row stride (prevents diagonal pixel shearing)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(targetBuffer)
        
        targetArray.withUnsafeMutableBytes { (dataPtr, strides) in
            guard let floatPtr = dataPtr.bindMemory(to: Float.self).baseAddress else { return }
            
            let channelStride = strides[1]
            let rowStride = strides[2]
            let colStride = strides[3]
            
            for y in 0..<size {
                let rowOffset = y * rowStride
                
                // Read rows in standard order (top-to-bottom) because CoreImage's ciContext.render
                // automatically handles the vertical coordinate flip when writing to CVPixelBuffer.
                let pixelRowOffset = y * bytesPerRow
                
                for x in 0..<size {
                    let pixelOffset = pixelRowOffset + x * 4
                    let outOffset = rowOffset + x * colStride
                    
                    // Native BGRA format mappings
                    let b = Float(ptr[pixelOffset])
                    let g = Float(ptr[pixelOffset + 1])
                    let r = Float(ptr[pixelOffset + 2])
                    
                    // Swaps channels dynamically based on model format requirements
                    let c0 = isBGR ? b : r
                    let c1 = g
                    let c2 = isBGR ? r : b
                    
                    if isNormalizedTo01 {
                        // Standard [0.0, 1.0] normalization (used by MiniFASNet V2 SE)
                        floatPtr[outOffset] = c0 / 255.0
                        floatPtr[outOffset + channelStride] = c1 / 255.0
                        floatPtr[outOffset + (2 * channelStride)] = c2 / 255.0
                    } else {
                        // Standard [-0.996, 0.996] normalization (used by EdgeFace)
                        floatPtr[outOffset] = (c0 - 127.5) / 128.0
                        floatPtr[outOffset + channelStride] = (c1 - 127.5) / 128.0
                        floatPtr[outOffset + (2 * channelStride)] = (c2 - 127.5) / 128.0
                    }
                }
            }
        }
        
        // AUTOMATIC TENSOR DIAGNOSTIC: Reconstructs and saves the exact float data
        // inside the MLMultiArray directly to your Desktop.
        let name = (size == 112) ? "Face_Model_Input" : "Liveness_Model_Input"
        self.saveMultiArrayToDisk(targetArray, size: size, name: name, isNormalizedTo01: isNormalizedTo01)
        
        return true
    }

    /// Diagnostic helper to save the exact preprocessed buffer to your Desktop as a PNG.
    func saveBufferToDisk(_ buffer: CVPixelBuffer, name: String) {
        let ciImage = CIImage(cvPixelBuffer: buffer)
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return }
        let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: ciImage.extent.width, height: ciImage.extent.height))
        
        let fileManager = FileManager.default
        guard let desktopURL = fileManager.urls(for: .desktopDirectory, in: .userDomainMask).first else { return }
        let diagnosticsDirectory = desktopURL.appendingPathComponent("Sapphire_Diagnostics")
        
        try? fileManager.createDirectory(at: diagnosticsDirectory, withIntermediateDirectories: true)
        let fileURL = diagnosticsDirectory.appendingPathComponent("\(name).png")
        
        if let tiffData = nsImage.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiffData),
           let pngData = bitmap.representation(using: .png, properties: [:]) {
            try? pngData.write(to: fileURL)
        }
    }
    
    /// Diagnostic helper to reconstruct and save the exact float data inside MLMultiArray to your Desktop.
    func saveMultiArrayToDisk(_ array: MLMultiArray, size: Int, name: String, isNormalizedTo01: Bool) {
        guard let floatPtr = try? UnsafeBufferPointer<Float>(array) else { return }
        
        let width = size
        let height = size
        let channelStride = size * size
        
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        
        for y in 0..<height {
            for x in 0..<width {
                let outOffset = y * width + x
                let pixelOffset = (y * width + x) * 4
                
                // CoreML tensor shape layout: Channel 0 (R), Channel 1 (G), Channel 2 (B)
                let rVal = floatPtr[outOffset]
                let gVal = floatPtr[outOffset + channelStride]
                let bVal = floatPtr[outOffset + (2 * channelStride)]
                
                let rByte: UInt8
                let gByte: UInt8
                let bByte: UInt8
                
                if isNormalizedTo01 {
                    rByte = UInt8(clamping: Int(rVal * 255.0))
                    gByte = UInt8(clamping: Int(gVal * 255.0))
                    bByte = UInt8(clamping: Int(bVal * 255.0))
                } else {
                    rByte = UInt8(clamping: Int(rVal * 128.0 + 127.5))
                    gByte = UInt8(clamping: Int(gVal * 128.0 + 127.5))
                    bByte = UInt8(clamping: Int(bVal * 128.0 + 127.5))
                }
                
                // RGBA output layout
                bytes[pixelOffset] = rByte
                bytes[pixelOffset + 1] = gByte
                bytes[pixelOffset + 2] = bByte
                bytes[pixelOffset + 3] = 255 // Alpha
            }
        }
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        
        guard let context = CGContext(
            data: &bytes,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ), let cgImage = context.makeImage() else {
            return
        }
        
        let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: width, height: height))
        
        let fileManager = FileManager.default
        guard let desktopURL = fileManager.urls(for: .desktopDirectory, in: .userDomainMask).first else { return }
        let diagnosticsDirectory = desktopURL.appendingPathComponent("Sapphire_Diagnostics")
        
        try? fileManager.createDirectory(at: diagnosticsDirectory, withIntermediateDirectories: true)
        let fileURL = diagnosticsDirectory.appendingPathComponent("\(name)_Tensor.png")
        
        if let tiffData = nsImage.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiffData),
           let pngData = bitmap.representation(using: .png, properties: [:]) {
            try? pngData.write(to: fileURL)
        }
    }

    private func resizedCGImage(_ cgImage: CGImage, to size: CGSize) -> CGImage? {
        let resizedImage = NSImage(size: size)
        resizedImage.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        if let ctx = NSGraphicsContext.current?.cgContext {
            ctx.draw(cgImage, in: CGRect(origin: .zero, size: size))
        }
        resizedImage.unlockFocus()
        return resizedImage.cgImage
    }

    // MARK: - CoreMath

    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return -1.0 }
        var result: Float = 0.0
        vDSP_dotpr(a, 1, b, 1, &result, vDSP_Length(a.count))
        return result
    }

    private func average(faceprints: [[Float]]) -> [Float]? {
        guard let first = faceprints.first, !first.isEmpty else { return nil }
        var avg = [Float](repeating: 0.0, count: first.count)
        for print in faceprints {
            for i in 0..<first.count { avg[i] += print[i] }
        }
        let count = Float(faceprints.count)
        let averaged = avg.map { $0 / count }
        return l2Normalize(averaged)
    }

    private func l2Normalize(_ vector: [Float]) -> [Float] {
        var sumSquares: Float = 0.0
        for value in vector { sumSquares += value * value }
        let norm = sqrt(sumSquares)
        guard norm > 0 else { return vector }
        return vector.map { $0 / norm }
    }
}
