//
//  SymmetricKey+Extensions.swift
//  Sapphire
//
//  Created by Shariq Charolia on 06.08.2025.
//

import Foundation
import CryptoKit

extension SymmetricKey{
	func data() -> Data{
		return withUnsafeBytes({return Data(bytes: $0.baseAddress!, count: $0.count)})
	}
}