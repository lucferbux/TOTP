//
//  WatchPayloadTests.swift
//  TOTPTests
//
//  What the iPhone sends the Apple Watch, and how the watch stores it.
//

import Testing
import Foundation
import CryptoKit
@testable import TOTP

@Suite("Watch payload")
struct WatchPayloadTests {
    let secret = Data("12345678901234567890".utf8)
    /// Built once, so every use sees the same account IDs.
    let sample: [OtpModel]

    init() {
        let secret = Data("12345678901234567890".utf8)
        sample = [
            OtpModel(issuer: "Example Corp", name: "user@example.com", prefix: "1234",
                     entry: .totp(key: secret, digits: 6, interval: 30), associatedDomains: ["sso.example.com"]),
            OtpModel(issuer: "Counter Bank", name: "hotp", entry: .hotp(key: secret, digits: 6, counter: 7)),
            OtpModel(issuer: "Fabrikam", name: "admin", entry: .totp(key: Data("other secret".utf8), digits: 8, interval: 60, algorithm: .sha256))
        ]
    }

    @Test("HOTP accounts are never sent")
    func excludesHotp() {
        let payload = WatchPayload(accounts: sample, isLocked: false)
        #expect(payload.accounts.map(\.issuer) == ["Example Corp", "Fabrikam"])
        #expect(payload.models().allSatisfy { !$0.entry.isHotp })
    }

    @Test("Prefix and associated domains stay on the iPhone")
    func stripsPrefixAndDomains() throws {
        let payload = WatchPayload(accounts: sample, isLocked: false)
        for model in payload.models() {
            #expect(model.prefix == nil)
            #expect(model.associatedDomains == nil)
        }
        // Not even in the encoded bytes
        let json = try #require(String(data: payload.encoded(), encoding: .utf8))
        #expect(!json.contains("1234"))
        #expect(!json.contains("sso.example.com"))
        #expect(!json.contains("prefix"))
    }

    @Test("With the app lock on, no account is sent")
    func lockSendsNothing() throws {
        let payload = WatchPayload(accounts: sample, isLocked: true)
        #expect(payload.isLocked)
        #expect(payload.accounts.isEmpty)
        #expect(payload.models().isEmpty)
        let decoded = try WatchPayload.decode(applicationContext: payload.applicationContext())
        #expect(decoded.isLocked)
        #expect(decoded.accounts.isEmpty)
        // A locked payload stays empty even if built from accounts directly
        let forced = WatchPayload(isLocked: true, accounts: payload.accounts + WatchPayload(accounts: sample, isLocked: false).accounts)
        #expect(forced.accounts.isEmpty)
    }

    @Test("Round trip keeps order and produces the same codes")
    func roundTrip() throws {
        let payload = WatchPayload(accounts: sample, isLocked: false)
        let decoded = try WatchPayload.decode(applicationContext: payload.applicationContext())
        #expect(decoded == payload)

        let expected = sample.filter { !$0.entry.isHotp }
        let models = decoded.models()
        #expect(models.map(\.id) == expected.map(\.id))
        #expect(models.map(\.issuer) == expected.map(\.issuer))
        #expect(models.map(\.name) == expected.map(\.name))
        let dates = [Date(timeIntervalSince1970: 59), Date(timeIntervalSince1970: 1_111_111_109), .now]
        for (model, original) in zip(models, expected) {
            #expect(model.entry.algorithm == original.entry.algorithm)
            #expect(model.entry.digits == original.entry.digits)
            #expect(model.entry.interval == original.entry.interval)
            for date in dates {
                #expect(model.code(at: date) == original.code(at: date))
            }
        }
    }

    @Test("RFC 6238 vector survives the trip")
    func rfcVector() throws {
        let account = OtpModel(issuer: "Example Corp", entry: .totp(key: secret, digits: 8, interval: 30))
        let data = try WatchPayload(accounts: [account], isLocked: false).encoded()
        let model = try #require(WatchPayload.decode(data).models().first)
        #expect(model.code(at: Date(timeIntervalSince1970: 59)) == "94287082")
    }

    @Test("A payload from a newer format is rejected")
    func rejectsNewerVersion() throws {
        let newer = WatchPayload(version: WatchPayload.currentVersion + 1, isLocked: false, accounts: [])
        #expect(throws: (any Error).self) { try WatchPayload.decode(newer.encoded()) }
        #expect(throws: (any Error).self) { try WatchPayload.decode(applicationContext: [:]) }
    }

    @Test("The watch cache is sealed, and a lock wipes it")
    func cacheIsSealedAndWipedOnLock() throws {
        let suite = "WatchPayloadTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let key = SymmetricKey(size: .bits256)

        #expect(WatchAccountCache.load(key: key, from: defaults) == .neverSynced)

        try WatchAccountCache.store(WatchPayload(accounts: sample, isLocked: false), key: key, in: defaults)
        let stored = try #require(defaults.data(forKey: AccountStore.accountsKey))
        #expect(stored.range(of: secret) == nil)
        guard case let .ready(accounts) = WatchAccountCache.load(key: key, from: defaults) else {
            Issue.record("Expected stored accounts"); return
        }
        #expect(accounts.map(\.issuer) == ["Example Corp", "Fabrikam"])
        #expect(accounts.first?.code(at: Date(timeIntervalSince1970: 59)) == sample[0].code(at: Date(timeIntervalSince1970: 59)))
        // Another key opens nothing
        #expect(WatchAccountCache.load(key: SymmetricKey(size: .bits256), from: defaults) == .ready([]))

        try WatchAccountCache.store(WatchPayload(accounts: sample, isLocked: true), key: key, in: defaults)
        #expect(defaults.data(forKey: AccountStore.accountsKey) == nil)
        #expect(WatchAccountCache.load(key: key, from: defaults) == .locked)
    }

    @Test("Screenshot seeds are fictional and the watch shows only their TOTP accounts")
    func screenshotSeeds() {
        let seeds = SampleAccounts.screenshot
        #expect(!seeds.isEmpty)
        #expect(seeds.allSatisfy { ($0.name ?? "").contains("@") ? ($0.name ?? "").hasSuffix(".example") : true })
        #expect(WatchPayload(accounts: seeds, isLocked: false).models().count == seeds.filter { !$0.entry.isHotp }.count)
    }
}
