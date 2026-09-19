//
//  HOTP.swift
//  Shared (app, widget, AutoFill)
//
//  RFC 4226 HOTP with the RFC 6238 hash variants.
//

import Foundation
import CryptoKit

/// Hash function used for the HMAC step (`algorithm` parameter of otpauth:// URLs).
public enum OtpAlgorithm: String, Codable, CaseIterable, Hashable, Sendable, Identifiable {
    case sha1 = "SHA1"
    case sha256 = "SHA256"
    case sha512 = "SHA512"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .sha1: "SHA-1"
        case .sha256: "SHA-256"
        case .sha512: "SHA-512"
        }
    }

    /// Lenient parser: accepts "SHA1", "sha-256", "SHA512"…
    public init?(lenient value: String) {
        let normalized = value.uppercased().replacingOccurrences(of: "-", with: "")
        self.init(rawValue: normalized)
    }
}

/// Generates an HOTP value (RFC 4226 §5.3) as a zero-padded string of `digits` characters.
///
/// Returning a `String` (not an integer) is deliberate: leading zeros are significant,
/// especially when the code is appended to a fixed PIN prefix.
public func hotpCode(key: Data, digits: Int = 6, counter: UInt64, algorithm: OtpAlgorithm = .sha1) -> String {
    let message = withUnsafeBytes(of: counter.bigEndian) { Data($0) }
    let symmetricKey = SymmetricKey(data: key)

    let hash: [UInt8]
    switch algorithm {
    case .sha1:
        hash = Array(HMAC<Insecure.SHA1>.authenticationCode(for: message, using: symmetricKey))
    case .sha256:
        hash = Array(HMAC<SHA256>.authenticationCode(for: message, using: symmetricKey))
    case .sha512:
        hash = Array(HMAC<SHA512>.authenticationCode(for: message, using: symmetricKey))
    }

    // Dynamic truncation
    let offset = Int(hash[hash.count - 1] & 0x0f)
    let binary = (UInt32(hash[offset] & 0x7f) << 24)
        | (UInt32(hash[offset + 1]) << 16)
        | (UInt32(hash[offset + 2]) << 8)
        | UInt32(hash[offset + 3])

    let digits = min(max(digits, 1), 10)
    var modulus: UInt64 = 1
    for _ in 0..<digits { modulus *= 10 }
    let value = UInt64(binary) % modulus

    let raw = String(value)
    return String(repeating: "0", count: max(0, digits - raw.count)) + raw
}
