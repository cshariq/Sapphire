//
//  MLModelManager.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-10-17.
//

import CoreML
import Vision

final class MLModelManager {
    private let queue = DispatchQueue(label: "MLModelManager.queue", attributes: .concurrent)
    static let shared = MLModelManager()

    private var depthModel: VNCoreMLModel?
    private var faceModel: ArcFace?

    func getDepthModel() throws -> VNCoreMLModel {
        if let existing = queue.sync(execute: { depthModel }) {
            return existing
        }

        var result: VNCoreMLModel?
        var thrownError: Error?

        queue.sync(flags: .barrier) {
            if let cached = depthModel {
                result = cached
                return
            }
            do {
                print("LOG (ML): Loading DepthAnythingV2 model...")
                let model = try VNCoreMLModel(for: DepthAnythingV2().model)
                depthModel = model
                result = model
            } catch {
                thrownError = error
            }
        }

        if let error = thrownError { throw error }
        return result!
    }

    func getFaceModel() throws -> ArcFace {
        if let existing = queue.sync(execute: { faceModel }) {
            return existing
        }

        var result: ArcFace?
        var thrownError: Error?

        queue.sync(flags: .barrier) {
            if let cached = faceModel {
                result = cached
                return
            }
            do {
                print("LOG (ML): Loading ArcFace model...")
                let model = try ArcFace()
                faceModel = model
                result = model
            } catch {
                thrownError = error
            }
        }

        if let error = thrownError { throw error }
        return result!
    }

    func unloadModels() {
        queue.sync(flags: .barrier) {
            autoreleasepool {
                depthModel = nil
                faceModel = nil
            }
            print("LOG (ML): Unloaded Core ML models from memory.")
        }
    }
}