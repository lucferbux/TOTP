//
//  OTPGeneratorTests.swift
//  TOTPTests
//
//  RFC 4226 (HOTP) and RFC 6238 (TOTP) test vectors.
//

import Testing
import Foundation
@testable import TOTP

@Suite("OTP generation")
struct OTPGeneratorTests {
    static let sha1Seed = Data("12345678901234567890".utf8)
    static let sha256Seed = Data("12345678901234567890123456789012".utf8)
    static let sha512Seed = Data("1234567890123456789012345678901234567890123456789012345678901234".utf8)

    // RFC 4226 Appendix D
    @Test("RFC 4226 HOTP vectors", arguments: zip(
        0...9,
        ["755224", "287082", "359152", "969429", "338314", "254676", "287922", "162583", "399871", "520489"]
    ))
    func rfc4226(counter: Int, expected: String) {
        #expect(hotpCode(key: Self.sha1Seed, digits: 6, counter: UInt64(counter)) == expected)
    }

    // RFC 6238 Appendix B
    struct TOTPVector: Sendable, CustomTestStringConvertible {
        let time: TimeInterval
        let sha1: String
        let sha256: String
        let sha512: String
        var testDescription: String { "T=\(Int(time))" }
    }

    static let rfc6238Vectors = [
        TOTPVector(time: 59, sha1: "94287082", sha256: "46119246", sha512: "90693936"),
        TOTPVector(time: 1111111109, sha1: "07081804", sha256: "68084774", sha512: "25091201"),
        TOTPVector(time: 1111111111, sha1: "14050471", sha256: "67062674", sha512: "99943326"),
        TOTPVector(time: 1234567890, sha1: "89005924", sha256: "91819424", sha512: "93441116"),
        TOTPVector(time: 2000000000, sha1: "69279037", sha256: "90698825", sha512: "38618901"),
        TOTPVector(time: 20000000000, sha1: "65353130", sha256: "77737706", sha512: "47863826")
    ]

    @Test("RFC 6238 TOTP vectors", arguments: rfc6238Vectors)
    func rfc6238(vector: TOTPVector) {
        let date = Date(timeIntervalSince1970: vector.time)
        #expect(OtpEntry.totp(key: Self.sha1Seed, digits: 8, interval: 30, algorithm: .sha1).code(at: date) == vector.sha1)
        #expect(OtpEntry.totp(key: Self.sha256Seed, digits: 8, interval: 30, algorithm: .sha256).code(at: date) == vector.sha256)
        #expect(OtpEntry.totp(key: Self.sha512Seed, digits: 8, interval: 30, algorithm: .sha512).code(at: date) == vector.sha512)
    }

    @Test("Codes keep leading zeros")
    func leadingZeros() {
        // RFC 6238 T=1111111109 SHA-1 is "07081804": the leading zero must survive
        let date = Date(timeIntervalSince1970: 1111111109)
        let code = OtpEntry.totp(key: Self.sha1Seed, digits: 8, interval: 30).code(at: date)
        #expect(code == "07081804")
        #expect(code.count == 8)
    }

    @Test("Output length always equals digits", arguments: 6...10)
    func length(digits: Int) {
        for counter in 0..<50 {
            #expect(hotpCode(key: Self.sha1Seed, digits: digits, counter: UInt64(counter)).count == digits)
        }
    }

    @Test("HOTP code is stable until advanced")
    func hotpAdvance() {
        let entry = OtpEntry.hotp(key: Self.sha1Seed, digits: 6, counter: 0)
        #expect(entry.code() == "755224")
        #expect(entry.code() == "755224")
        let next = entry.advanced()
        #expect(next.counter == 1)
        #expect(next.code() == "287082")
    }

    @Test("TOTP is unaffected by advanced()")
    func totpAdvanceNoop() {
        let entry = OtpEntry.totp(key: Self.sha1Seed, digits: 6, interval: 30)
        #expect(entry.advanced() == entry)
    }

    @Test("Countdown helpers")
    func countdown() {
        let entry = OtpEntry.totp(key: Self.sha1Seed, digits: 6, interval: 30)
        // 1_000_000_010 = 30 × 33_333_333 + 20
        #expect(entry.periodStart(containing: Date(timeIntervalSince1970: 1_000_000_010)) == Date(timeIntervalSince1970: 999_999_990))
        #expect(entry.secondsRemaining(at: Date(timeIntervalSince1970: 60)) == 30)
        #expect(entry.secondsRemaining(at: Date(timeIntervalSince1970: 61)) == 29)
        #expect(entry.secondsRemaining(at: Date(timeIntervalSince1970: 89.5)) == 1)
        #expect(abs(entry.remainingFraction(at: Date(timeIntervalSince1970: 75)) - 0.5) < 0.0001)
        #expect(entry.nextRefresh(after: Date(timeIntervalSince1970: 61)) == Date(timeIntervalSince1970: 90))

        let hotp = OtpEntry.hotp(key: Self.sha1Seed, digits: 6, counter: 0)
        #expect(hotp.secondsRemaining() == 0)
        #expect(hotp.nextRefresh(after: .now) == nil)
    }

    @Test("Same code throughout a period, new code in the next")
    func periodBoundaries() {
        let entry = OtpEntry.totp(key: Self.sha1Seed, digits: 6, interval: 30)
        let start = Date(timeIntervalSince1970: 1_700_000_010)
        let periodStart = entry.periodStart(containing: start)!
        #expect(entry.code(at: periodStart) == entry.code(at: periodStart.addingTimeInterval(29.999)))
        #expect(entry.code(at: periodStart) != entry.code(at: periodStart.addingTimeInterval(30)))
    }

    @Test("Code grouping", arguments: [
        ("123456", "123 456"),
        ("12345678", "1234 5678"),
        ("1234567", "1234 567"),
        ("1234567890", "12345 67890"),
        ("12", "12")
    ])
    func grouping(raw: String, grouped: String) {
        #expect(raw.groupedOTP == grouped)
    }

    @Test("Algorithm parsing is lenient")
    func algorithmParsing() {
        #expect(OtpAlgorithm(lenient: "sha1") == .sha1)
        #expect(OtpAlgorithm(lenient: "SHA-256") == .sha256)
        #expect(OtpAlgorithm(lenient: "sha512") == .sha512)
        #expect(OtpAlgorithm(lenient: "md5") == nil)
    }
}
