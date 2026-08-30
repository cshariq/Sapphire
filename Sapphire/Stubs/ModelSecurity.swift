#if !SAPPHIRE_FULL_BUILD
import Foundation
import CryptoKit

enum ModelSecurity {
    /// Placeholder key — real Face ID model decryption requires the private package.
    static var encryptionKey: SymmetricKey {
        SymmetricKey(size: .bits256)
    }
}
#endif
