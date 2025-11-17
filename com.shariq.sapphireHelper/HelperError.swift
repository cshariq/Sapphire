//
//  HelperError.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-10-02
//

import Foundation

public let HelperErrorDomain = "com.shariq.sapphireHelper.ErrorDomain"

public enum HelperErrorCode: Int {
    case smcOpenFailed = 1
    case smcWriteFailed = 2
    case generalError = 3
}

func makeError(code: HelperErrorCode, description: String) -> NSError {
    let userInfo = [NSLocalizedDescriptionKey: description]
    return NSError(domain: HelperErrorDomain, code: code.rawValue, userInfo: userInfo)
}