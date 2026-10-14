import Foundation
import Security

/// System CSPRNG with rejection sampling, so every value below `upperBound` is exactly equally likely.
final class SecureRandomSource: RandomSource {
    func nextInt(upperBound: Int) -> Int {
        precondition(upperBound > 0 && upperBound <= 256)
        let limit = 256 - (256 % upperBound)
        while true {
            var byte: UInt8 = 0
            let status = SecRandomCopyBytes(kSecRandomDefault, 1, &byte)
            if status == errSecSuccess && Int(byte) < limit { return Int(byte) % upperBound }
        }
    }
}
