//
//  MLModelManager.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-10-17.
//

import CoreML
import Vision

class MLModelManager {
    private let queue = DispatchQueue(label: "MLModelManager.queue", attributes: .concurrent)
    static let shared = MLModelManager()

    private var depthModel: VNCoreMLModel?
    private var faceModel: ArcFace?

    func getDepthModel() throws -> VNCoreMLModel {
        return try queue.sync {
            if let model = depthModel {
                return model
            }
            print("LOG (ML): Loading DepthAnythingV2 model...")
            let model = try VNCoreMLModel(for: DepthAnythingV2().model)
            queue.async(flags: .barrier) { [weak self] in
                self?.depthModel = model
            }
            return model
        }
    }

    func getFaceModel() throws -> ArcFace {
        return try queue.sync {
            if let model = faceModel {
                return model
            }
            print("LOG (ML): Loading ArcFace model...")
            let model = try ArcFace()
            queue.async(flags: .barrier) { [weak self] in
                self?.faceModel = model
            }
            return model
        }
    }

    func unloadModels() {
        queue.sync(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            autoreleasepool {
                self.depthModel = nil
                self.faceModel = nil
            }
            print("LOG (ML): Unloaded Core ML models from memory.")
        }
    }
}