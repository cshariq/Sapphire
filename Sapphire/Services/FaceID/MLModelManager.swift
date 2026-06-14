//
//  MLModelManager.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-10-17.
//

import CoreML
import os // Import os for Logger

final class MLModelManager {
    private let queue = DispatchQueue(label:  "MLModelManager. queue", attributes: .concurrent)
    static let shared = MLModelManager()

    private var modernModel: MLModel?
    private let logger = Logger(subsystem: "com.sapphire.app", category: "FaceID.MLModelManager") // Initialize logger

    private init() {}

    /// Produce a normalized embedding vector for a preprocessed image represented
    /// as an `MLMultiArray`. This method uses the modern Core ML model named
    /// `ModernFace` when `SettingsModel.shared.settings.useModernFaceModel` is
    /// enabled.
    func predictEmbedding(from mlArray: MLMultiArray) throws -> [Float] {
        if SettingsModel.shared.settings.useModernFaceModel {
            if let modernEmbedding = try? predictWithModernModel(from: mlArray) {
                return modernEmbedding
            }

            logger.error("ModernFace requested but unavailable or incompatible.")
            throw NSError(
                domain: "MLModelManager",
                code: -3,
                userInfo: [NSLocalizedDescriptionKey: "ModernFace model could not be loaded or predicted successfully"]
            )
        }

        logger.error("ModernFace model is disabled in settings.")
        throw NSError(
            domain: "MLModelManager",
            code: -4,
            userInfo: [NSLocalizedDescriptionKey: "ModernFace model is disabled in settings"]
        )
    }

    private func predictWithModernModel(from mlArray: MLMultiArray) throws -> [Float] {
        if let cached = queue.sync(execute: { modernModel }) {
            do {
                let start = DispatchTime.now()
                let embedding = try runGenericModel(cached, with: mlArray)
                let end = DispatchTime.now()
                let elapsed = Double(end.uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000.0
                logger.debug("Prediction time: \(elapsed, privacy: .public) ms")
                logger.debug("Embedding (first 8 dims): \(embedding.prefix(8).map { String(format: "%.4f", $0) }.joined(separator: ", "), privacy: .public) norm=\(self.l2Norm(embedding), privacy: .public)")
                return embedding
            } catch {
                logger.error("Cached ModernFace prediction failed: \(error.localizedDescription)")
                queue.sync(flags: .barrier) {
                    if modernModel === cached {
                        modernModel = nil
                    }
                }
            }
        }

        // Attempt to load the packaged model from the app bundle.
        // Prefer `.mlpackage` because that is the packaged format produced by conversion.
        let candidateURLs: [URL] = [
            Bundle.main.url(forResource: "ModernFace", withExtension: "mlpackage"),
            Bundle.main.url(forResource: "ModernFace", withExtension: "mlmodelc"),
            Bundle.main.url(forResource: "ModernFace", withExtension: "mlmodel")
        ].compactMap { $0 }

        for url in candidateURLs {
            do {
                let ml = try MLModel(contentsOf: url, configuration: modernModelConfiguration())
//                logger.info("ModernFace loaded successfully from \(url.lastPathComponent, privacy: .public), modelVersion=\(ml.modelDescription.metadata[.creatorDefinedKey] ?? "unknown", privacy: .public)")
                queue.sync(flags: .barrier) { modernModel = ml }
                let start = DispatchTime.now()
                let embedding = try runGenericModel(ml, with: mlArray)
                let end = DispatchTime.now()
                let elapsed = Double(end.uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000.0
                logger.debug("✅ ModernFace model used for embedding. Prediction time: \(elapsed, privacy: .public) ms")
                logger.debug("Embedding (first 8 dims): \(embedding.prefix(8).map { String(format: "%.4f", $0) }.joined(separator: ", "), privacy: .public) norm=\(self.l2Norm(embedding), privacy: .public)")
                return embedding
            } catch {
                logger.error("Failed to use ModernFace at \(url.lastPathComponent, privacy: .public): \(error.localizedDescription)")
            }
        }

        throw NSError(
            domain: "MLModelManager",
            code: -2,
            userInfo: [NSLocalizedDescriptionKey: "ModernFace model could not be loaded or predicted successfully"]
        )
    }

    private func runGenericModel(_ ml: MLModel, with mlArray: MLMultiArray) throws -> [Float] {
        let inputName = ml.modelDescription.inputDescriptionsByName.first(where: { $0.value.multiArrayConstraint != nil })?.key
            ?? ml.modelDescription.inputDescriptionsByName.keys.first
            ?? "input"
        let provider = try MLDictionaryFeatureProvider(dictionary: [inputName: MLFeatureValue(multiArray: mlArray)])
        let result = try ml.prediction(from: provider)

        if let outputFeature = result.featureNames.compactMap({ result.featureValue(for: $0) }).first(where: { $0.multiArrayValue != nil }),
           let outArray = outputFeature.multiArrayValue {
            return l2Normalize(floatVector(from: outArray))
        }

        throw NSError(domain: "MLModelManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "No valid multi-array output from model"])
    }

    private func floatVector(from array: MLMultiArray) -> [Float] {
        let count = array.count
        var vector = [Float](repeating: 0, count: count)
        for i in 0..<count {
            vector[i] = array[i].floatValue
        }
        return vector
    }

    private func modernModelConfiguration() -> MLModelConfiguration {
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .all
        return configuration
    }

    private func l2Normalize(_ vector: [Float]) -> [Float] {
        var sumSquares: Float = 0.0
        for v in vector { sumSquares += v * v }
        let norm = sqrt(sumSquares)
        guard norm > 0 else { return vector }
        return vector.map { $0 / norm }
    }

    private func l2Norm(_ vector: [Float]) -> Float {
        var sumSquares: Float = 0.0
        for v in vector { sumSquares += v * v }
        return sqrt(sumSquares)
    }

    func unloadModels() {
        queue.sync(flags: .barrier) {
            autoreleasepool {
                modernModel = nil
            }
        }
    }
}
