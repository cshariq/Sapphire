//
//  FaceprintDatabase.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-09-15
//
//
//
//
//

import Vision
import CoreML
import AppKit
import Combine

struct FaceprintDatabase: Codable {
    var individualPrints: [[Float]] = []
    var globalAverage: [Float] = []
    var learnedPrints: [[Float]] = []
    var serializedDepthMaps: [Data] = []
    var facialMetrics: [FacialMetricSet] = []
}

typealias Faceprint = [Float]

class FaceDataStore {

    private static let model = try! ArcFace()
    private var profiles: [String: FaceprintDatabase] = [:]

    private var depthDetector = DepthDetector()
    private var cancellables = Set<AnyCancellable>()

    private let maxLearnedPrints = 100
    private let secureFileURL: URL

    init() {
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
    }

    func hasRegisteredFaceprints() -> Bool {
        return !profiles.isEmpty
    }

    func reset() {
        profiles.removeAll()
        depthDetector.reset()
        try? FileManager.default.removeItem(at: secureFileURL)
        print("️ All face recognition data has been reset.")
        DispatchQueue.main.async {
            SettingsModel.shared.settings.hasRegisteredFaceID = false
        }
    }

    func register(faceSamples: [(observation: VNFaceObservation, buffer: CVPixelBuffer)], forProfile name: String) {
        var newDatabase = FaceprintDatabase()

        let allPrints = faceSamples.compactMap { generateEmbedding(for: $0.observation, from: $0.buffer) }
        newDatabase.individualPrints = allPrints
        newDatabase.facialMetrics = faceSamples.compactMap { FacialMetricsCalculator.calculateMetrics(from: $0.observation) }

        depthDetector.reset()
        let sampleCount = min(faceSamples.count, 5)
        if sampleCount > 0 {
            for i in 0..<sampleCount {
                let index = (faceSamples.count / sampleCount) * i
                depthDetector.register(pixelBuffer: faceSamples[index].buffer)
            }
        }
        newDatabase.serializedDepthMaps = depthDetector.serializeDepthMaps()

        if let globalAvg = average(faceprints: allPrints) {
            newDatabase.globalAverage = globalAvg
        }

        profiles[name] = newDatabase // Save the new database to the dictionary
        saveToSecureStorage()

        DispatchQueue.main.async {
            SettingsModel.shared.settings.hasRegisteredFaceID = true
        }

        print(" Registration successful for profile: \(name)")
    }

    func getSimilarityScore(for faceImage: NSImage) -> Double {
        guard let currentEmbedding = generateEmbedding(for: faceImage) else { return -1.0 }

        var maxSimilarity: Float = -1.0

        for (_, database) in profiles {
            var allTemplates: [[Float]] = []
            if !database.globalAverage.isEmpty { allTemplates.append(database.globalAverage) }
            allTemplates.append(contentsOf: database.learnedPrints)
            allTemplates.append(contentsOf: database.individualPrints)

            for template in allTemplates {
                let similarity = cosineSimilarity(template, currentEmbedding)
                if similarity > maxSimilarity { maxSimilarity = similarity }
            }
        }

        return Double(maxSimilarity)
    }

    func getMetricsSimilarity(for metrics: FacialMetricSet) -> Double {
        var bestScore = 0.0
        for (_, database) in profiles {
            for storedMetrics in database.facialMetrics {
                bestScore = max(bestScore, metrics.similarityScore(with: storedMetrics))
            }
        }
        return bestScore
    }

    func getDepthSimilarity(for pixelBuffer: CVPixelBuffer) async -> Double {
        return await depthDetector.getDepthSimilarity(for: pixelBuffer)
    }

    func learnNewFaceprint(faceImage: NSImage) {
        guard let profileName = profiles.keys.first, var database = profiles[profileName] else { return }
        guard let newEmbedding = generateEmbedding(for: faceImage) else { return }

        database.learnedPrints.insert(newEmbedding, at: 0)
        if database.learnedPrints.count > maxLearnedPrints {
            database.learnedPrints = Array(database.learnedPrints.prefix(maxLearnedPrints))
        }

        profiles[profileName] = database // Write the updated database back
        saveToSecureStorage()
    }

    private func saveToSecureStorage() {
        do {
            let jsonData = try JSONEncoder().encode(profiles)
            guard let encryptedData = CryptoManager.shared.encrypt(data: jsonData) else { return }
            try encryptedData.write(to: secureFileURL, options: .atomic)
        } catch {
            print(" Failed to save profiles to secure storage: \(error)")
        }
    }

    private func loadFromSecureStorage() {
        guard FileManager.default.fileExists(atPath: secureFileURL.path) else { return }
        do {
            let encryptedData = try Data(contentsOf: secureFileURL)
            guard let decryptedData = CryptoManager.shared.decrypt(data: encryptedData) else { return }
            profiles = try JSONDecoder().decode([String: FaceprintDatabase].self, from: decryptedData)

            if let firstDb = profiles.values.first {
                depthDetector.loadDepthMaps(from: firstDb.serializedDepthMaps)
            }
            print(" Secure faceprint profiles loaded successfully.")
        } catch {
            print(" Error loading secure profiles: \(error)")
        }
    }

    private func generateEmbedding(for observation: VNFaceObservation, from pixelBuffer: CVPixelBuffer) -> [Float]? {
        guard let preparedImage = FaceProcessor.shared.prepareImage(from: pixelBuffer, faceObservation: observation) else { return nil }
        return generateEmbedding(for: preparedImage)
    }

    private func generateEmbedding(for image: NSImage) -> [Float]? {
        guard let mlArray = preprocess(image: image) else { return nil }

        do {
            let modelInput = ArcFaceInput(x_1: mlArray)
            let output = try FaceDataStore.model.prediction(input: modelInput)
            let embeddingMultiArray = output.var_657
            let vector = (0..<embeddingMultiArray.count).map { embeddingMultiArray[$0].floatValue }
            return l2Normalize(vector)
        } catch {
            print(" Failed to get prediction from ArcFace model: \(error)")
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
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let pixelData = context.data else { return nil }
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

    private func l2Normalize(_ vector: [Float]) -> [Float] {
        let norm = sqrt(vector.map { $0 * $0 }.reduce(0, +))
        guard norm > 0 else { return vector }
        return vector.map { $0 / norm }
    }

    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        let dotProduct = zip(a, b).map(*).reduce(0, +)
        return dotProduct
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
        return l2Normalize(avg.map { $0 / count })
    }
}