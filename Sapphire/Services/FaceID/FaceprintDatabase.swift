//
//  FaceprintDatabase.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-09-15
//

import Vision
import CoreML
import AppKit
import Combine
import os // Import os for Logger

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
    private let logger = Logger(subsystem: "com.sapphire.app", category: "FaceID.FaceprintDatabase") // Initialize logger

    private let maxLearnedPrints = 50
    private let secureFileURL: URL

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
        logger.info("   Stored \(highQualityPrints.count) individual prints")
        if !highQualityPrints.isEmpty {
            logger.info("   Embedding dimension: \(highQualityPrints[0].count)")
        }
    }

    private func rejectOutliers(from faceprints: [Faceprint]) -> [Faceprint] {
        guard faceprints.count > 10 else { return faceprints }

        guard let medianPrint = average(faceprints: faceprints) else { return faceprints }

        // Use Euclidean distance instead of cosine similarity
        let distances = faceprints.map { euclideanDistance($0, medianPrint) }

        let averageDistance = distances.reduce(0, +) / Float(distances.count)
        let sumOfSquaredDiffs = distances.map { pow($0 - averageDistance, 2) }.reduce(0, +)
        let stdDev = sqrt(sumOfSquaredDiffs / Float(distances.count))

        let cutoffDistance = averageDistance + (stdDev * 1.5) // Keep samples within 1.5 std dev

        var filteredPrints: [Faceprint] = []
        for (index, distance) in distances.enumerated() {
            if distance <= cutoffDistance {
                filteredPrints.append(faceprints[index])
            }
        }

        return filteredPrints
    }

    func getSimilarityScore(for faceImage: NSImage) -> Double {
        guard let currentEmbedding = generateEmbedding(for: faceImage) else {
            logger.error("Failed to generate embedding for similarity score.")
            return 0.0
        }

        var bestDistance: Float = Float.greatestFiniteMagnitude

        for (_, database) in profiles {
            let profileDistance = averageTopMatchDistance(in: database, for: currentEmbedding)
            bestDistance = min(bestDistance, profileDistance)
        }

        let similarityScore = distanceToSimilarity(distance: Double(bestDistance))

        logger.debug("Face Match - Distance: \(String(format: "%.3f", bestDistance), privacy: .public) → Similarity: \(String(format: "%.1f%%", similarityScore * 100), privacy: .public)")

        return similarityScore
    }

    /// Uses the average of the best three distances for a more stable match score.
    private func averageTopMatchDistance(in database: FaceprintDatabase, for embedding: [Float]) -> Float {
        var distances: [Float] = []

        if !database.globalAverage.isEmpty {
            distances.append(euclideanDistance(embedding, database.globalAverage))
        }

        for print in database.individualPrints {
            distances.append(euclideanDistance(embedding, print))
        }

        for print in database.learnedPrints {
            distances.append(euclideanDistance(embedding, print))
        }

        guard !distances.isEmpty else { return Float.greatestFiniteMagnitude }

        let topMatches = distances.sorted().prefix(3)
        return topMatches.reduce(0, +) / Float(topMatches.count)
    }

    private func distanceToSimilarity(distance: Double) -> Double {
        // Calibrated for L2-normalized ModernFace embeddings using top-3 average distance.
        if distance < 0.36 {
            return 1.0 - (distance / 0.36) * 0.04  // 96-100%
        } else if distance < 0.52 {
            return 0.96 - ((distance - 0.36) / 0.16) * 0.08  // 88-96%
        } else if distance < 0.68 {
            return 0.88 - ((distance - 0.52) / 0.16) * 0.13  // 75-88%
        } else if distance < 0.88 {
            return 0.75 - ((distance - 0.68) / 0.20) * 0.20  // 55-75%
        } else {
            return max(0.0, 0.55 - (distance - 0.88) * 0.30)
        }
    }

    func learnNewFaceprint(faceImage: NSImage) {
        guard let profileName = profiles.keys.first, var database = profiles[profileName] else { return }
        guard let newEmbedding = generateEmbedding(for: faceImage) else { return }

        // Only learn if it's not too similar to existing prints (avoid duplicates)
        var shouldLearn = true
        for existingPrint in database.learnedPrints {
            let distance = euclideanDistance(newEmbedding, existingPrint)
            if distance < 0.1 { // Too similar
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
            logger.info("🎓 Learned new face vintelligencetion (total learned: \(database.learnedPrints.count, privacy: .public))")
        }
    }

    private func saveToSecureStorage() {
        do {
            let jsonData = try JSONEncoder().encode(profiles)
            guard let encryptedData = CryptoManager.shared.encrypt(data: jsonData) else { return }
            try encryptedData.write(to: secureFileURL, options: .atomic)
        } catch {
            print("Failed to save face id profiles: \(error)")
        }
    }

    private func loadFromSecureStorage() {
        guard FileManager.default.fileExists(atPath: secureFileURL.path) else { return }
        do {
            let encryptedData = try Data(contentsOf: secureFileURL)
            guard let decryptedData = CryptoManager.shared.decrypt(data: encryptedData) else { return }
            profiles = try JSONDecoder().decode([String: FaceprintDatabase].self, from: decryptedData)
        } catch {
            print("Failed to load face id profiles: \(error)")
        }
    }

    // MARK: - Face Embedding Generation

    public func generateEmbedding(for observation: VNFaceObservation, from pixelBuffer: CVPixelBuffer) -> [Float]? {
        guard let preparedImage = FaceProcessor.shared.prepareImage(from: pixelBuffer, faceObservation: observation) else {
            logger.error("Failed to prepare image for embedding generation from pixel buffer.")
            return nil
        }
        return generateEmbedding(for: preparedImage)
    }

    private func generateEmbedding(for image: NSImage) -> [Float]? {
        guard let mlArray = preprocess(image: image) else {
            logger.error("Failed to preprocess image for embedding generation.")
            return nil
        }

        do {
            // Use centralized MLModelManager which may run the modern model if enabled
            let embedding = try MLModelManager.shared.predictEmbedding(from: mlArray)
            return embedding
        } catch {
            logger.error("Failed to get prediction from face model: \(error.localizedDescription)")
            return nil
        }
    }

    private func preprocess(image: NSImage) -> MLMultiArray? {
        let targetSize = CGSize(width: 112, height: 112)
        guard let cgImage = image.cgImage else { return nil }
        
        let resizedImage = NSImage(size: targetSize)
        resizedImage.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        let targetRect = CGRect(origin: .zero, size: targetSize)
        if let ctx = NSGraphicsContext.current?.cgContext {
            ctx.draw(cgImage, in: targetRect)
        }
        resizedImage.unlockFocus()
        
        guard let resizedCGImage = resizedImage.cgImage else { return nil }
        let width = Int(targetSize.width), height = Int(targetSize.height)
        
        guard let array = try? MLMultiArray(shape: [1, 3, NSNumber(value: height), NSNumber(value: width)], dataType: .float32) else { return nil }
        
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let pixelData = context.data else { return nil }
        
        context.draw(resizedCGImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        let ptr = pixelData.bindMemory(to: UInt8.self, capacity: width * height * 4)
        
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                let r = (Float(ptr[offset]) - 127.5) / 128.0
                let g = (Float(ptr[offset+1]) - 127.5) / 128.0
                let b = (Float(ptr[offset+2]) - 127.5) / 128.0
                
                array[[0, 0, NSNumber(value: y), NSNumber(value: x)]] = NSNumber(value: r)
                array[[0, 1, NSNumber(value: y), NSNumber(value: x)]] = NSNumber(value: g)
                array[[0, 2, NSNumber(value: y), NSNumber(value: x)]] = NSNumber(value: b)
            }
        }
        
        return array
    }

    // MARK: - Distance Calculations (Euclidean, not Cosine!)

    private func euclideanDistance(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return Float.greatestFiniteMagnitude }
        
        var sumSquaredDiff: Float = 0.0
        for i in 0..<a.count {
            let diff = a[i] - b[i]
            sumSquaredDiff += diff * diff
        }
        
        return sqrt(sumSquaredDiff)
    }

    private func average(faceprints: [[Float]]) -> [Float]? {
        guard let first = faceprints.first, !first.isEmpty else { return nil }
        
        var avg = [Float](repeating: 0.0, count: first.count)
        for print in faceprints {
            for i in 0..<first.count {
                avg[i] += print[i]
            }
        }
        
        let count = Float(faceprints.count)
        let averaged = avg.map { $0 / count }
        
        return l2Normalize(averaged)
    }

    private func l2Normalize(_ vector: [Float]) -> [Float] {
        var sumSquares: Float = 0.0
        for value in vector {
            sumSquares += value * value
        }
        let norm = sqrt(sumSquares)
        guard norm > 0 else { return vector }
        return vector.map { $0 / norm }
    }
}
