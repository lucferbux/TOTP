//
//  ModelTests.swift
//  TOTPTests
//
//  OtpModel, Base32, otpauth:// parsing and AutoFill matching.
//

import Testing
import Foundation
@testable import TOTP

@Suite("OtpModel")
struct OtpModelTests {
    let secret = Data("12345678901234567890".utf8)

    @Test("AutoFill value is prefix + zero-padded code (regression: leading zeros were dropped)")
    func autoFillValueKeepsZeros() {
        let account = OtpModel(issuer: "Example Corp", name: "user", prefix: "PIN!",
                               entry: .totp(key: secret, digits: 8, interval: 30))
        let date = Date(timeIntervalSince1970: 1111111109) // SHA-1 code 07081804
        #expect(account.autoFillValue(at: date) == "PIN!07081804")
    }

    @Test("No prefix means just the code")
    func autoFillWithoutPrefix() {
        let account = OtpModel(issuer: "GitHub", entry: .hotp(key: secret, digits: 6, counter: 0))
        #expect(account.autoFillValue() == "755224")
        #expect(!account.hasPrefix)
    }

    @Test("Empty prefix behaves like no prefix")
    func emptyPrefix() {
        let account = OtpModel(prefix: "", entry: .hotp(key: secret, digits: 6, counter: 0))
        #expect(account.autoFillValue() == "755224")
        #expect(!account.hasPrefix)
    }

    @Test("Equality and hashing agree")
    func equalityHashing() {
        let id = UUID()
        let a = OtpModel(id: id, issuer: "A", entry: .totp(key: secret, digits: 6, interval: 30))
        var b = a
        #expect(a == b)
        #expect(a.hashValue == b.hashValue)
        b.issuer = "B"
        #expect(a != b)
        #expect(Set([a, b]).count == 2)
    }

    @Test("Display title falls back to name")
    func displayTitle() {
        #expect(OtpModel(issuer: "Issuer", name: "me", entry: .totp(key: secret, digits: 6, interval: 30)).displayTitle == "Issuer")
        let nameOnly = OtpModel(name: "me", entry: .totp(key: secret, digits: 6, interval: 30))
        #expect(nameOnly.displayTitle == "me")
        #expect(nameOnly.displaySubtitle == nil)
    }

    @Test("Search matches issuer and name, case-insensitively")
    func search() {
        let account = OtpModel(issuer: "Example Corp", name: "user@example.net", entry: .totp(key: secret, digits: 6, interval: 30))
        #expect(account.matches(search: ""))
        #expect(account.matches(search: "corp"))
        #expect(account.matches(search: "EXAMPLE"))
        #expect(!account.matches(search: "github"))
    }

    @Test("AutoFill domain matching", arguments: [
        (["sso.example.com"], ["https://sso.example.com/auth/realms"], true),
        (["example.com"], ["sso.example.com"], true),
        (["sso.example.com"], ["example.com"], true),
        (["www.github.com"], ["github.com"], true),
        (["github.com"], ["notgithub.com"], false),
        (["example.org"], ["example.com"], false)
    ])
    func domainMatching(domains: [String], identifiers: [String], expected: Bool) {
        let account = OtpModel(issuer: "X", entry: .totp(key: secret, digits: 6, interval: 30), associatedDomains: domains)
        #expect(account.matchesAutoFill(serviceIdentifiers: identifiers) == expected)
    }

    @Test("Issuer is used as a pseudo-domain when no domains are set")
    func issuerFallback() {
        // The issuer is normalised ("Example Corp" → "examplecorp") and matched against host segments
        let account = OtpModel(issuer: "Example", entry: .totp(key: secret, digits: 6, interval: 30))
        #expect(account.matchesAutoFill(serviceIdentifiers: ["sso.example.com"]))
        #expect(!account.matchesAutoFill(serviceIdentifiers: ["github.com"]))
        #expect(!account.matchesAutoFill(serviceIdentifiers: []))

        // A multi-word issuer only matches a host segment spelled the same way
        let twoWords = OtpModel(issuer: "Example Corp", entry: .totp(key: secret, digits: 6, interval: 30))
        #expect(twoWords.matchesAutoFill(serviceIdentifiers: ["sso.examplecorp.com"]))
        #expect(!twoWords.matchesAutoFill(serviceIdentifiers: ["sso.example.com"]))
    }
}

@Suite("Base32")
struct Base32Tests {
    // RFC 4648 §10 (unpadded)
    @Test("RFC 4648 vectors", arguments: [
        ("f", "MY"), ("fo", "MZXQ"), ("foo", "MZXW6"), ("foob", "MZXW6YQ"),
        ("fooba", "MZXW6YTB"), ("foobar", "MZXW6YTBOI")
    ])
    func vectors(plain: String, encoded: String) {
        #expect(Data(plain.utf8).base32EncodedString() == encoded)
        #expect(Data(base32Encoded: encoded) == Data(plain.utf8))
    }

    @Test("Decoding ignores case, spaces, dashes and padding")
    func lenientDecoding() {
        let expected = Data("foobar".utf8)
        #expect(Data(base32Encoded: "mzxw6ytboi") == expected)
        #expect(Data(base32Encoded: "MZXW 6YTB OI") == expected)
        #expect(Data(base32Encoded: "MZXW-6YTB-OI") == expected)
        #expect(Data(base32Encoded: "MZXW6YTBOI======") == expected)
    }

    @Test("Invalid input is rejected", arguments: ["", "M", "MZX", "MZXW6Y!", "12345678", "ÄÖÜ"])
    func invalid(input: String) {
        #expect(Data(base32Encoded: input) == nil)
    }

    @Test("Round trip of random data")
    func roundTrip() {
        for length in 1...64 {
            let data = Data((0..<length).map { _ in UInt8.random(in: .min ... .max) })
            #expect(Data(base32Encoded: data.base32EncodedString()) == data)
        }
    }
}

@Suite("otpauth:// URLs")
struct OtpAuthURLTests {
    @Test("Full TOTP URL")
    func fullTOTP() throws {
        let url = try OtpAuthURL(string: "otpauth://totp/ACME%20Co:john.doe@email.com?secret=HXDMVJECJJWSRB3HWIZR4IFUGFTMXBOZ&issuer=ACME%20Co&algorithm=SHA256&digits=8&period=60")
        #expect(url.issuer == "ACME Co")
        #expect(url.name == "john.doe@email.com")
        #expect(url.entry.algorithm == .sha256)
        #expect(url.entry.digits == 8)
        #expect(url.entry.interval == 60)
        #expect(url.entry.key == Data(base32Encoded: "HXDMVJECJJWSRB3HWIZR4IFUGFTMXBOZ"))
    }

    @Test("Defaults: SHA-1, 6 digits, 30 s")
    func defaults() throws {
        let url = try OtpAuthURL(string: "otpauth://totp/alice?secret=JBSWY3DPEHPK3PXP")
        #expect(url.issuer == nil)
        #expect(url.name == "alice")
        #expect(url.entry == .totp(key: Data(base32Encoded: "JBSWY3DPEHPK3PXP")!, digits: 6, interval: 30, algorithm: .sha1))
    }

    @Test("Issuer comes from the label when the parameter is missing")
    func labelIssuer() throws {
        let url = try OtpAuthURL(string: "otpauth://totp/Example%20Corp:user?secret=JBSWY3DPEHPK3PXP")
        #expect(url.issuer == "Example Corp")
        #expect(url.name == "user")
    }

    @Test("HOTP needs a counter")
    func hotp() throws {
        let url = try OtpAuthURL(string: "otpauth://hotp/Bank:me?secret=JBSWY3DPEHPK3PXP&counter=42")
        #expect(url.entry.counter == 42)
        #expect(throws: OtpAuthURL.ParseError.invalidParameter("counter")) {
            try OtpAuthURL(string: "otpauth://hotp/Bank:me?secret=JBSWY3DPEHPK3PXP")
        }
    }

    @Test("Errors", arguments: [
        ("https://example.com", OtpAuthURL.ParseError.notOtpAuth),
        ("otpauth://steam/x?secret=JBSWY3DPEHPK3PXP", .unsupportedType),
        ("otpauth://totp/x", .missingSecret),
        ("otpauth://totp/x?secret=not-base32!", .invalidSecret),
        ("otpauth://totp/x?secret=JBSWY3DPEHPK3PXP&digits=4", .invalidParameter("digits")),
        ("otpauth://totp/x?secret=JBSWY3DPEHPK3PXP&algorithm=MD5", .invalidParameter("algorithm")),
        ("otpauth://totp/x?secret=JBSWY3DPEHPK3PXP&period=0", .invalidParameter("period"))
    ])
    func errors(input: String, expected: OtpAuthURL.ParseError) {
        #expect(throws: expected) { try OtpAuthURL(string: input) }
    }

    @Test("Round trip through url")
    func roundTrip() throws {
        let original = OtpAuthURL(issuer: "Example Corp", name: "user@example.com",
                                  entry: .totp(key: Data("12345678901234567890".utf8), digits: 8, interval: 45, algorithm: .sha512))
        #expect(try OtpAuthURL(url: original.url) == original)

        let hotp = OtpAuthURL(issuer: nil, name: "me", entry: .hotp(key: Data("abc".utf8), digits: 6, counter: 7, algorithm: .sha1))
        #expect(try OtpAuthURL(url: hotp.url) == hotp)
    }

    @Test("makeModel carries prefix and domains")
    func makeModel() throws {
        let parsed = try OtpAuthURL(string: "otpauth://totp/Example%20Corp:me?secret=JBSWY3DPEHPK3PXP")
        let model = parsed.makeModel(prefix: "1234", associatedDomains: ["sso.example.com"])
        #expect(model.prefix == "1234")
        #expect(model.issuer == "Example Corp")
        #expect(model.associatedDomains == ["sso.example.com"])
    }
}
