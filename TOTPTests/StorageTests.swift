//
//  StorageTests.swift
//  TOTPTests
//
//  Encrypted persistence, backward compatibility, CloudKit mapping and sync merge.
//

import Testing
import Foundation
import CryptoKit
import CloudKit
@testable import TOTP

@Suite("Encrypted storage")
struct StorageTests {
    let key = SymmetricKey(size: .bits256)
    let secret = Data("12345678901234567890".utf8)

    private func sample(_ algorithm: OtpAlgorithm = .sha1) -> [OtpModel] {
        [
            OtpModel(issuer: "Red Hat", name: "me", prefix: "PIN", entry: .totp(key: secret, digits: 6, interval: 30, algorithm: algorithm), associatedDomains: ["sso.redhat.com"]),
            OtpModel(issuer: "Bank", entry: .hotp(key: Data("other".utf8), digits: 8, counter: 12))
        ]
    }

    @Test("Seal/open is the identity")
    func cryptoRoundTrip() throws {
        let sealed = try AccountCrypto.seal(secret, using: key)
        #expect(sealed != secret)
        #expect(try AccountCrypto.open(sealed, using: key) == secret)
    }

    @Test("Wrong key cannot decrypt")
    func wrongKey() throws {
        let sealed = try AccountCrypto.seal(secret, using: key)
        #expect(throws: (any Error).self) { try AccountCrypto.open(sealed, using: SymmetricKey(size: .bits256)) }
    }

    @Test("Encode → decode keeps every field", arguments: OtpAlgorithm.allCases)
    func storeRoundTrip(algorithm: OtpAlgorithm) throws {
        let accounts = sample(algorithm)
        let data = try AccountStore.encode(accounts, key: key)
        #expect(try AccountStore.decode(data, key: key) == accounts)
    }

    @Test("The stored payload never contains the plaintext secret or the prefix-free code")
    func noPlaintextSecret() throws {
        let data = try AccountStore.encode(sample(), key: key)
        #expect(data.range(of: secret) == nil)
        #expect(data.range(of: Data(secret.base64EncodedString().utf8)) == nil)
    }

    @Test("SHA-1 accounts don't write an algorithm field (format stays compatible with 3.x)")
    func sha1OmitsAlgorithm() throws {
        let data = try AccountStore.encode([sample()[0]], key: key)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(!json.contains("algorithm"))
        let sha256 = try AccountStore.encode(sample(.sha256), key: key)
        #expect(String(data: sha256, encoding: .utf8)!.contains("SHA256"))
    }

    @Test("Legacy 3.x payload (no algorithm / domains) decodes as SHA-1")
    func legacyDecode() throws {
        let encrypted = try AccountCrypto.seal(secret, using: key)
        let legacy: [[String: Any]] = [[
            "id": "6F9619FF-8B86-D011-B42D-00CF4FC964FF",
            "issuer": "Red Hat",
            "name": "me",
            "prefix": "PIN",
            "encryptedKey": encrypted.base64EncodedString(),
            "isHotp": false,
            "digits": 6,
            "interval": 30,
            "counter": 0,
            "createdDate": 700000000,
            "modifiedDate": 700000000
        ]]
        let data = try JSONSerialization.data(withJSONObject: legacy)
        let accounts = try AccountStore.decode(data, key: key)
        #expect(accounts.count == 1)
        #expect(accounts[0].id.uuidString == "6F9619FF-8B86-D011-B42D-00CF4FC964FF")
        #expect(accounts[0].entry == .totp(key: secret, digits: 6, interval: 30, algorithm: .sha1))
        #expect(accounts[0].prefix == "PIN")
        #expect(accounts[0].associatedDomains == nil)
    }

    @Test("Undecryptable records are skipped, not fatal")
    func skipsCorrupt() throws {
        let good = try StoredOtpAccount(model: sample()[0], key: key)
        let bad = try StoredOtpAccount(model: sample()[1], key: SymmetricKey(size: .bits256))
        let data = try JSONEncoder().encode([good, bad])
        let accounts = try AccountStore.decode(data, key: key)
        #expect(accounts.map(\.issuer) == ["Red Hat"])
    }

    @Test("Creation date is preserved across saves")
    func createdDatePreserved() throws {
        let accounts = sample()
        let first = try AccountStore.encode(accounts, key: key, now: Date(timeIntervalSince1970: 1000))
        let previous = try JSONDecoder().decode([StoredOtpAccount].self, from: first)
        let second = try AccountStore.encode(accounts, key: key, previous: previous, now: Date(timeIntervalSince1970: 2000))
        let records = try JSONDecoder().decode([StoredOtpAccount].self, from: second)
        #expect(records.allSatisfy { $0.createdDate == Date(timeIntervalSince1970: 1000) })
        #expect(records.allSatisfy { $0.modifiedDate == Date(timeIntervalSince1970: 2000) })
    }

    @Test("AccountStore.loadAccounts reads what SharedDataManager writes")
    func extensionReadsAppWrites() async throws {
        let suite = "TOTPTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let manager = SharedDataManager(userDefaults: defaults, encryptionKey: key)
        #expect(manager.accounts.isEmpty)
        let accounts = sample()
        accounts.forEach(manager.addAccount)

        #expect(AccountStore.loadAccounts(from: defaults, key: key) == accounts)
        #expect(AccountStore.loadAccounts(from: defaults, key: nil).isEmpty)
    }

    @Test("SharedDataManager update, move and delete persist")
    func managerMutations() async throws {
        let suite = "TOTPTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let manager = SharedDataManager(userDefaults: defaults, encryptionKey: key)
        let accounts = sample()
        accounts.forEach(manager.addAccount)

        var edited = accounts[0]
        edited.prefix = "NEWPIN"
        try await manager.updateAccount(edited)
        manager.moveAccounts(fromOffsets: IndexSet(integer: 1), toOffset: 0)

        let reloaded = SharedDataManager(userDefaults: defaults, encryptionKey: key)
        #expect(reloaded.accounts.map(\.issuer) == ["Bank", "Red Hat"])
        #expect(reloaded.accounts[1].prefix == "NEWPIN")

        manager.deleteAccount(withId: accounts[1].id)
        #expect(SharedDataManager(userDefaults: defaults, encryptionKey: key).accounts.map(\.issuer) == ["Red Hat"])

        let missing = OtpModel(issuer: "Ghost", entry: .totp(key: secret, digits: 6, interval: 30))
        await #expect(throws: SharedDataError.self) { try await manager.updateAccount(missing) }
    }
}

@Suite("CloudKit mapping")
struct CloudKitMappingTests {
    let secret = Data("12345678901234567890".utf8)

    @Test("OtpModel → CKRecord → OtpModel", arguments: OtpAlgorithm.allCases)
    func roundTrip(algorithm: OtpAlgorithm) throws {
        let model = OtpModel(issuer: "Red Hat", name: "me", prefix: "PIN",
                             entry: .totp(key: secret, digits: 8, interval: 60, algorithm: algorithm),
                             associatedDomains: ["sso.redhat.com"])
        let record = try CloudKitOtpModel.from(otpModel: model).toCKRecord()
        #expect((record["encryptedKey"] as? Data) != secret)
        let restored = try #require(CloudKitOtpModel(from: record)).toOtpModel()
        #expect(restored == model)
    }

    @Test("SHA-1 records don't set the algorithm field")
    func sha1NoField() throws {
        let model = OtpModel(issuer: "X", entry: .totp(key: secret, digits: 6, interval: 30))
        let record = try CloudKitOtpModel.from(otpModel: model).toCKRecord()
        #expect(record["algorithm"] == nil)
        #expect(record.allKeys().contains("algorithm") == false)
    }

    @Test("HOTP counter maps both ways")
    func hotpCounter() throws {
        let model = OtpModel(issuer: "Bank", entry: .hotp(key: secret, digits: 6, counter: 99))
        let record = try CloudKitOtpModel.from(otpModel: model).toCKRecord()
        #expect(record["counter"] as? Int64 == 99)
        #expect(try CloudKitOtpModel(from: record)?.toOtpModel().entry.counter == 99)
    }
}

@Suite("Sync merge")
struct SyncMergeTests {
    let secret = Data("12345678901234567890".utf8)

    @Test("Local wins on issuer+name match; cloud-only accounts are added")
    func merge() {
        let local = OtpModel(issuer: "Red Hat", name: "me", prefix: "LOCAL", entry: .totp(key: secret, digits: 6, interval: 30))
        let cloudCopy = OtpModel(issuer: "Red Hat", name: "me", prefix: "CLOUD", entry: .totp(key: secret, digits: 6, interval: 30))
        let cloudOnly = OtpModel(issuer: "GitHub", name: "octo", entry: .totp(key: secret, digits: 6, interval: 30))

        let merged = SyncManager.mergeAccounts(local: [local], cloud: [cloudCopy, cloudOnly])
        #expect(merged.count == 2)
        #expect(merged.first { $0.issuer == "Red Hat" }?.prefix == "LOCAL")
        #expect(merged.contains { $0.id == cloudOnly.id })
    }

    @Test("Service identifier uses first domain, then issuer")
    func serviceIdentifier() {
        let withDomain = OtpModel(issuer: "Red Hat", entry: .totp(key: secret, digits: 6, interval: 30), associatedDomains: ["sso.redhat.com", "redhat.com"])
        #expect(SyncManager.serviceIdentifier(for: withDomain).identifier == "sso.redhat.com")
        let issuerOnly = OtpModel(issuer: "Red Hat", entry: .totp(key: secret, digits: 6, interval: 30))
        #expect(SyncManager.serviceIdentifier(for: issuerOnly).identifier == "redhat")
    }
}

@Suite("Widget timeline & clipboard")
struct TimelineAndClipboardTests {
    let secret = Data("12345678901234567890".utf8)

    @Test("Timeline starts now and then follows period boundaries")
    func refreshDates() {
        let now = Date(timeIntervalSince1970: 1_700_000_007) // 1_700_000_007 % 30 == 27
        let dates = CodeTimeline.refreshDates(for: [.totp(key: secret, digits: 6, interval: 30)], now: now, count: 5)
        #expect(dates.count == 5)
        #expect(dates[0] == now)
        #expect(dates[1] == Date(timeIntervalSince1970: 1_700_000_010))
        for pair in zip(dates.dropFirst(), dates.dropFirst(2)) {
            #expect(pair.1.timeIntervalSince(pair.0) == 30)
        }
        for date in dates.dropFirst() {
            #expect(date.timeIntervalSince1970.truncatingRemainder(dividingBy: 30) == 0)
        }
    }

    @Test("Mixed periods refresh at the shortest one")
    func mixedPeriods() {
        let dates = CodeTimeline.refreshDates(for: [
            .totp(key: secret, digits: 6, interval: 60),
            .totp(key: secret, digits: 6, interval: 15)
        ], now: Date(timeIntervalSince1970: 100), count: 3)
        #expect(dates.map(\.timeIntervalSince1970) == [100, 105, 120])
    }

    @Test("Each timeline entry shows the code valid for that entry")
    func entryCodesMatchDates() {
        let entry = OtpEntry.totp(key: secret, digits: 6, interval: 30)
        let dates = CodeTimeline.refreshDates(for: [entry], now: Date(timeIntervalSince1970: 1_111_111_100), count: 4)
        for date in dates {
            let expiry = entry.nextRefresh(after: date)!
            #expect(entry.code(at: date) == entry.code(at: expiry.addingTimeInterval(-0.001)))
        }
    }

    @Test("Clipboard expiry")
    func clipboardExpiry() {
        let now = Date(timeIntervalSince1970: 1000)
        #expect(ClipboardManager.expirationDate(clearAfter: 0, now: now) == nil)
        #expect(ClipboardManager.expirationDate(clearAfter: 60, now: now) == Date(timeIntervalSince1970: 1060))
        #expect(ClipboardManager.shouldClear(currentChangeCount: 5, copiedChangeCount: 5))
        #expect(!ClipboardManager.shouldClear(currentChangeCount: 6, copiedChangeCount: 5))
    }

    @Test("Clipboard preference defaults to 60 s and persists")
    func clipboardPreference() {
        let original = AppPreferences.defaults.object(forKey: AppPreferences.Keys.clipboardClearSeconds)
        defer { AppPreferences.defaults.set(original, forKey: AppPreferences.Keys.clipboardClearSeconds) }

        AppPreferences.defaults.removeObject(forKey: AppPreferences.Keys.clipboardClearSeconds)
        #expect(AppPreferences.clipboardClearSeconds == 60)
        AppPreferences.clipboardClearSeconds = 0
        #expect(AppPreferences.clipboardClearSeconds == 0)
    }
}

@Suite("App Intents")
struct AppIntentTests {
    @Test("Account entities expose no secret material")
    func entityHasNoSecret() {
        let model = OtpModel(issuer: "Red Hat", name: "me", prefix: "SECRETPIN",
                             entry: .totp(key: Data("12345678901234567890".utf8), digits: 6, interval: 30))
        let entity = AccountEntity(model: model)
        #expect(entity.id == model.id)
        #expect(entity.issuer == "Red Hat")
        #expect(entity.accountName == "me")
        #expect(entity.hasPrefix)
        let mirror = Mirror(reflecting: entity).children.map { String(describing: $0.value) }.joined()
        #expect(!mirror.contains("SECRETPIN"))
    }
}
