//
//  Data+Base32.swift
//  Shared
//
//  RFC 4648 Base32 (the encoding used by OTP secrets).
//

import Foundation

extension Data {
    private static let base32Alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")

    /// Encodes the data as unpadded Base32 (RFC 4648 §6).
    public func base32EncodedString() -> String {
        guard !isEmpty else { return "" }
        var result = ""
        var buffer: UInt64 = 0
        var bitsInBuffer = 0
        for byte in self {
            buffer = (buffer << 8) | UInt64(byte)
            bitsInBuffer += 8
            while bitsInBuffer >= 5 {
                bitsInBuffer -= 5
                result.append(Self.base32Alphabet[Int((buffer >> UInt64(bitsInBuffer)) & 0x1F)])
            }
        }
        if bitsInBuffer > 0 {
            result.append(Self.base32Alphabet[Int((buffer << UInt64(5 - bitsInBuffer)) & 0x1F)])
        }
        return result
    }

    /// Decodes Base32, ignoring case, padding, spaces and dashes (secrets are often shown grouped).
    /// Returns `nil` for invalid characters, impossible lengths, or empty input.
    public init?(base32Encoded base32String: String) {
        let cleaned = base32String
            .uppercased()
            .filter { !$0.isWhitespace && $0 != "-" && $0 != "=" }
        guard !cleaned.isEmpty, [0, 2, 4, 5, 7].contains(cleaned.count % 8) else { return nil }

        var result = Data()
        var buffer: UInt64 = 0
        var bitsInBuffer = 0
        for scalar in cleaned.unicodeScalars {
            let value: UInt8
            switch scalar {
            case "A"..."Z": value = UInt8(scalar.value - UnicodeScalar("A").value)
            case "2"..."7": value = UInt8(scalar.value - UnicodeScalar("2").value) + 26
            default: return nil
            }
            buffer = (buffer << 5) | UInt64(value)
            bitsInBuffer += 5
            if bitsInBuffer >= 8 {
                bitsInBuffer -= 8
                result.append(UInt8((buffer >> UInt64(bitsInBuffer)) & 0xFF))
            }
        }
        guard !result.isEmpty else { return nil }
        self = result
    }
}
