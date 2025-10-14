//
//  CaptchaLoaderError.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-08-18.
//

import Foundation
import CaptchaSolverInterface

typealias PresenterFactory = @convention(c) () -> UnsafeMutableRawPointer

enum CaptchaLoaderError: Error, LocalizedError {
    case frameworkNotFound
    case couldNotLoadFramework
    case factoryFunctionNotFound

    var errorDescription: String? {
        switch self {
        case .frameworkNotFound:
            return "CaptchaSolver.framework could not be found in the app bundle."
        case .couldNotLoadFramework:
            return "The CaptchaSolver.framework binary could not be loaded into memory."
        case .factoryFunctionNotFound:
            return "Could not find the 'createCaptchaPresenter' factory function in the framework."
        }
    }
}

final class CaptchaLoader {
    static let shared = CaptchaLoader()
    private var presenter: CaptchaPresenting?

    private init() {}

    func loadPresenter() throws -> CaptchaPresenting {
        if let presenter = self.presenter {
            return presenter
        }

        guard let frameworkURL = Bundle.main.privateFrameworksURL?.appendingPathComponent("CaptchaSolver.framework"),
              let bundle = Bundle(url: frameworkURL) else {
            throw CaptchaLoaderError.frameworkNotFound
        }

        let handle = dlopen(bundle.executablePath, RTLD_LAZY)
        if handle == nil {
            throw CaptchaLoaderError.couldNotLoadFramework
        }

        let symbolName = "createCaptchaPresenter"
        guard let symbol = dlsym(handle, symbolName) else {
            throw CaptchaLoaderError.factoryFunctionNotFound
        }

        let factory = unsafeBitCast(symbol, to: PresenterFactory.self)
        let presenterObject = Unmanaged<AnyObject>.fromOpaque(factory()).takeRetainedValue()

        guard let presenter = presenterObject as? CaptchaPresenting else {
            fatalError("Factory function returned an object that does not conform to CaptchaPresenting.")
        }

        self.presenter = presenter
        return presenter
    }
}