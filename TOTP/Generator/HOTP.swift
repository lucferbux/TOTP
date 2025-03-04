import Foundation
import Combine
import CryptoKit

public func hotpCode(key: Data, digits: Int = 6, counter: UInt64) -> UInt64 {
    let counterBytes = (0..<8).reversed().map { UInt8(counter >> (8 * $0) & 0xff) }
    let hash = HMAC<Insecure.SHA1>.authenticationCode(for: counterBytes, using: SymmetricKey(data: key))
    let offset = Int(hash.suffix(1)[0] & 0x0f)
    let hash32 = hash
        .dropFirst(offset)
        .prefix(4)
        .reduce(0, { ($0 << 8) | UInt32($1) })
    let hash31 = hash32 & 0x7FFF_FFFF
    let pad = String(repeating: "0", count: digits)
    return UInt64(String((pad + String(hash31)).suffix(digits)))!
}
