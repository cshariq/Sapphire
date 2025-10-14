//
//  MLModelManager.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-10-14.
//

import Foundation
import CoreML
import Vision

class MLModelManager {
    static let shared = MLModelManager()

    private(set) var arcFaceModel: ArcFace?
    private(set) var depthAnythingModel: DepthAnythingV2?

    private(set) var depthVisionModel: VNCoreMLModel?

    private init() {}

    func loadModels() {
        let cpuOnlyConfig = MLModelConfiguration()
        cpuOnlyConfig.computeUnits = .cpuOnly

        print("LOG (ML): Using CPU-Only configuration to ensure memory is released.")

        if arcFaceModel == nil {
            do {
                print("LOG (ML): Loading ArcFace model...")
                arcFaceModel = try ArcFace(configuration: cpuOnlyConfig)
                print("LOG (ML): ArcFace model loaded.")
            } catch {
                print("ERROR (ML): Failed to load ArcFace model: \(error)")
            }
        }

        if depthAnythingModel == nil {
            do {
                print("LOG (ML): Loading DepthAnythingV2 model...")
                let model = try DepthAnythingV2(configuration: cpuOnlyConfig)
                self.depthAnythingModel = model
                print("LOG (ML): DepthAnythingV2 model loaded.")

                print("LOG (ML): Creating and caching Vision wrapper for depth model...")
                self.depthVisionModel = try VNCoreMLModel(for: model.model)
                print("LOG (ML): Vision wrapper cached.")

            } catch {
                print("ERROR (ML): Failed to load or create Vision wrapper for DepthAnythingV2 model: \(error)")
            }
        }
    }

    func unloadModels() {
        print("LOG (ML): Unloading Core ML models and Vision wrappers to conserve memory.")
        arcFaceModel = nil
        depthAnythingModel = nil
        depthVisionModel = nil
    }
}