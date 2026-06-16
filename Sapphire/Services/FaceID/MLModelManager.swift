//
//  MLModelManager.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-10-17.
//

import CoreML
import os

final class MLModelManager {
    private let queue = DispatchQueue(label: "com.sapphire.MLModelManager.queue", attributes: .concurrent)
    static let shared = MLModelManager()

    private var modernFaceModel: MLModel?
    private var livenessModel: MLModel?
    
    private let logger = Logger(subsystem: "com.sapphire.app", category: "FaceID.MLModelManager")

    private init() {}

    /// Pre-warms both models asynchronously on initial application launch to load weights into Neural Engine caches.
    func prewarm() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            self.logger.debug("Pre-warming face biometrics and liveness pipelines...")
            do {
                let dummyFace = try MLMultiArray(shape: [1, 3, 112, 112], dataType: .float32)
                let dummyLiveness = try MLMultiArray(shape: [1, 3, 128, 128], dataType: .float32)
                
                _ = try? self.predictEmbedding(from: dummyFace)
                _ = try? self.predictLiveness(from: dummyLiveness)
                
                self.logger.info("✅ Biometric & Liveness models pre-warmed on ANE successfully.")
            } catch {
                self.logger.warning("Pre-warm completed with status: \(error.localizedDescription)")
            }
        }
    }

    /// Generates a 512-dimensional face embedding using the native EdgeFace model.
    func predictEmbedding(from mlArray: MLMultiArray) throws -> [Float] {
        if modernFaceModel == nil { try loadModel(name: "ModernFace", into: &modernFaceModel) }
        guard let model = modernFaceModel else {
            throw NSError(domain: "MLModelManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "ModernFace model not loaded"])
        }
        
        let provider = try MLDictionaryFeatureProvider(dictionary: ["input": MLFeatureValue(multiArray: mlArray)])
        let result = try model.prediction(from: provider)
        
        if let out = result.featureNames.compactMap({ result.featureValue(for: $0)?.multiArrayValue }).first {
            return l2Normalize(floatVector(from: out))
        }
        throw NSError(domain: "MLModelManager", code: -2, userInfo: [NSLocalizedDescriptionKey: "Empty output tensor"])
    }

    /// Evaluates the 128x128 facial crop using the MiniFASNet V2 SE model.
    /// Returns a real face probability (0.0 to 1.0) using a numerically stable Softmax implementation.
    func predictLiveness(from mlArray: MLMultiArray) throws -> Float {
        if livenessModel == nil { try loadModel(name: "MiniFAS", into: &livenessModel) }
        guard let model = livenessModel else {
            throw NSError(domain: "MLModelManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "MiniFAS liveness model not loaded"])
        }
        
        let provider = try MLDictionaryFeatureProvider(dictionary: ["input": MLFeatureValue(multiArray: mlArray)])
        let result = try model.prediction(from: provider)
        
        if let out = result.featureNames.compactMap({ result.featureValue(for: $0)?.multiArrayValue }).first {
            // MiniFAS outputs 2 classes of raw logits: [RealLogit, SpoofLogit]
            // where Index 0 is Real, and Index 1 is Spoof.
            let realLogit = out[0].floatValue
            let spoofLogit = out[1].floatValue
            
            // Apply Softmax with dynamic shift to prevent numerical exp() overflow
            let maxLogit = max(spoofLogit, realLogit)
            let expReal = exp(realLogit - maxLogit)
            let expSpoof = exp(spoofLogit - maxLogit)
            
            let realProbability = expReal / (expReal + expSpoof)
            
            logger.debug("Liveness Output - Logits: [Real: \(realLogit), Spoof: \(spoofLogit)] → Real Probability: \(realProbability * 100)%")
            return realProbability
        }
        throw NSError(domain: "MLModelManager", code: -2, userInfo: [NSLocalizedDescriptionKey: "Empty liveness output"])
    }

    /// Releases loaded models from system memory to conserve ANE and GPU resources.
    func unloadModels() {
        queue.sync(flags: .barrier) {
            autoreleasepool {
                modernFaceModel = nil
                livenessModel = nil
            }
            logger.info("Unloaded Core ML models from memory.")
        }
    }

    // MARK: - Core Helpers
    
    private func loadModel(name: String, into target: inout MLModel?) throws {
        try queue.sync(flags: .barrier) {
            if target != nil { return }
            let urls = [
                Bundle.main.url(forResource: name, withExtension: "mlpackage"),
                Bundle.main.url(forResource: name, withExtension: "mlmodelc")
            ].compactMap { $0 }
            
            for url in urls {
                let config = MLModelConfiguration()
                config.computeUnits = .all // Target CPU, GPU, and Apple Neural Engine
                if let ml = try? MLModel(contentsOf: url, configuration: config) {
                    target = ml
                    return
                }
            }
            throw NSError(domain: "MLModelManager", code: -3, userInfo: [NSLocalizedDescriptionKey: "Failed to locate \(name)"])
        }
    }

    private func floatVector(from array: MLMultiArray) -> [Float] {
        return (0..<array.count).map { array[$0].floatValue }
    }

    private func l2Normalize(_ vector: [Float]) -> [Float] {
        let norm = sqrt(vector.reduce(0) { $0 + $1 * $1 })
        return norm > 0 ? vector.map { $0 / norm } : vector
    }
}
