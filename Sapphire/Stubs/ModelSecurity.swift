#if !SAPPHIRE_FULL_BUILD
import Foundation
import CryptoKit

enum ModelSecurity {
    // Placeholder key: bundled encrypted models can't be decrypted in community builds.
    static let encryptionKey = SymmetricKey(data: Data(count: 32))
}
#endif
