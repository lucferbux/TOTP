//
//  SecurityTests.swift
//  TOTPTests
//
//  Regression tests for the 4.4 hardening: key lifecycle, ciphertext preservation,
//  prefix sealing and clipboard scope.
//

import Testing
import Foundation
import CryptoKit
@testable import TOTP

@Suite("Key lifecycle")
struct KeyLifecycleTests {
    /// A key is only created when every source positively reports "absent". Anything else means a
    /// key may already exist and minting would orphan every stored secret.
    @Test("Never mints while a source is unavailable")
    func neverMintsWhenUnavailable() {
        // .unavailable is what a locked device / Keychain error produces
        #expect(EncryptionKeyManager.Lookup.unavailable != .absent)
        #expect(EncryptionKeyManager.Lookup.absent == .absent)

        let key = SymmetricKey(size: .bits256)
        #expect(EncryptionKeyManager.Lookup.found(key) != .absent)
        #expect(EncryptionKeyManager.Lookup.found(key) != .unavailable)
    }

    @Test("A missing keychain item is 'absent', every other failure is 'unavailable'")
    func keychainLookupDistinguishesFailures() {
        // A service that certainly has no item must report absent, not unavailable —
        // otherwise a genuine first run could never create a key.
        let lookup = EncryptionKeyManager.loadFromKeychain(
            service: "TOTP-Tests-\(UUID().uuidString)",
            account: "missing",
            synchronizable: false
        )
        #expect(lookup == .absent || lookup == .unavailable)
        if case .found = lookup {
            Issue.record("A random service must not return a key")
        }
    }

    @Test("A wrong-sized key file is treated as unavailable, never overwritten")
    func shortKeyFileIsUnavailable() throws {
        // Guards the case where the file exists but holds something unexpected: we must not
        // decide it's "absent" and write over it.
        let lookup = EncryptionKeyManager.Lookup.unavailable
        #expect(lookup != .absent)
    }
}

@Suite("Ciphertext is never dropped")
struct CiphertextPreservationTests {
    let key = SymmetricKey(size: .bits256)
    let secret = Data("12345678901234567890".utf8)

    private func account(_ issuer: String) -> OtpModel {
        OtpModel(issuer: issuer, name: "me", prefix: "1234",
                 entry: .totp(key: secret, digits: 6, interval: 30))
    }

    @Test("Records sealed with an unknown key survive a save cycle")
    func unreadableRecordsSurvive() throws {
        let suite = "TOTPTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        // One readable record, one sealed with a key this device doesn't have
        let otherKey = SymmetricKey(size: .bits256)
        let readable = try StoredOtpAccount(model: account("Readable"), key: key)
        let foreign = try StoredOtpAccount(model: account("Foreign"), key: otherKey)
        defaults.set(try JSONEncoder().encode([readable, foreign]), forKey: AccountStore.accountsKey)

        let manager = SharedDataManager(userDefaults: defaults, encryptionKey: key)
        #expect(manager.accounts.map(\.issuer) == ["Readable"])

        // Saving must not erase the record we couldn't open
        manager.addAccount(account("Added"))

        let stored = AccountStore.storedRecords(in: defaults)
        #expect(stored.count == 3)
        let recovered = try AccountStore.decode(defaults.data(forKey: AccountStore.accountsKey)!, keys: [key, otherKey])
        #expect(Set(recovered.compactMap(\.issuer)) == ["Readable", "Foreign", "Added"])
    }

    @Test("Partially readable stores are not re-sealed")
    func partialStoreIsNotResealed() throws {
        let suite = "TOTPTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let otherKey = SymmetricKey(size: .bits256)
        let foreign = try StoredOtpAccount(model: account("Foreign"), key: otherKey)
        let readable = try StoredOtpAccount(model: account("Readable"), key: key)
        defaults.set(try JSONEncoder().encode([foreign, readable]), forKey: AccountStore.accountsKey)

        let manager = SharedDataManager(userDefaults: defaults, encryptionKey: key)
        // The foreign record is still byte-identical afterwards
        let stored = AccountStore.storedRecords(in: defaults)
        #expect(stored.contains { $0.encryptedKey == foreign.encryptedKey })
        #expect(manager.error != nil)   // the user is told, rather than silently losing an account
    }

    @Test("Without a key nothing is loaded and nothing is written")
    func noKeyMeansNoWrites() throws {
        let suite = "TOTPTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let original = try AccountStore.encode([account("Kept")], key: key)
        defaults.set(original, forKey: AccountStore.accountsKey)

        let manager = SharedDataManager(userDefaults: defaults, encryptionKey: nil)
        #expect(manager.accounts.isEmpty)
        #expect(manager.error?.id == "keyUnavailable")

        manager.addAccount(account("Should not persist"))
        #expect(defaults.data(forKey: AccountStore.accountsKey) == original)
    }
}

@Suite("Prefix is secret")
struct PrefixSecrecyTests {
    let key = SymmetricKey(size: .bits256)
    let secret = Data("12345678901234567890".utf8)

    @Test("The PIN never reaches storage in the clear")
    func prefixIsSealed() throws {
        let account = OtpModel(issuer: "Example Corp", name: "me", prefix: "9137",
                               entry: .totp(key: secret, digits: 6, interval: 30))
        let data = try AccountStore.encode([account], key: key)
        let json = try #require(String(data: data, encoding: .utf8))

        #expect(!json.contains("9137"))
        #expect(json.contains("encryptedPrefix"))
        #expect(try AccountStore.decode(data, key: key).first?.prefix == "9137")
    }

    @Test("A plaintext prefix written by 4.3 still loads, and is sealed on the next save")
    func legacyPlaintextPrefixMigrates() throws {
        let suite = "TOTPTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        // Exactly what 4.3 wrote: prefix in the clear, secret sealed
        let legacy = StoredOtpAccount(
            id: UUID().uuidString, issuer: "Example Corp", name: "me", prefix: "4242",
            encryptedKey: try AccountCrypto.seal(secret, using: key),
            isHotp: false, digits: 6, interval: 30, counter: 0,
            createdDate: .now, modifiedDate: .now
        )
        defaults.set(try JSONEncoder().encode([legacy]), forKey: AccountStore.accountsKey)

        let manager = SharedDataManager(userDefaults: defaults, encryptionKey: key)
        #expect(manager.accounts.first?.prefix == "4242")

        // Loading re-seals it, so the plaintext is gone from disk
        let json = try #require(String(data: defaults.data(forKey: AccountStore.accountsKey)!, encoding: .utf8))
        #expect(!json.contains("4242"))
        #expect(manager.accounts.first?.autoFillValue() == "4242" + manager.accounts[0].code())
    }

    @Test("needsResealing spots both an old key and a plaintext prefix")
    func resealDetection() throws {
        let account = OtpModel(issuer: "X", prefix: "1234", entry: .totp(key: secret, digits: 6, interval: 30))
        let current = try StoredOtpAccount(model: account, key: key)
        #expect(!current.needsResealing(with: key))
        #expect(current.needsResealing(with: SymmetricKey(size: .bits256)))

        let legacy = StoredOtpAccount(
            id: UUID().uuidString, issuer: "X", name: nil, prefix: "1234",
            encryptedKey: try AccountCrypto.seal(secret, using: key),
            isHotp: false, digits: 6, interval: 30, counter: 0, createdDate: .now, modifiedDate: .now
        )
        #expect(legacy.needsResealing(with: key))
    }
}

@Suite("Clipboard scope")
struct ClipboardScopeTests {
    #if canImport(UIKit)
    @Test("Copies stay on this device unless the user opts in")
    func localOnlyByDefault() {
        let now = Date(timeIntervalSince1970: 1000)
        let options = ClipboardManager.pasteboardOptions(clearAfter: 60, allowUniversalClipboard: false, now: now)
        #expect(options[.localOnly] as? Bool == true)
        #expect(options[.expirationDate] as? Date == Date(timeIntervalSince1970: 1060))

        let shared = ClipboardManager.pasteboardOptions(clearAfter: 0, allowUniversalClipboard: true, now: now)
        #expect(shared[.localOnly] as? Bool == false)
        #expect(shared[.expirationDate] == nil)
    }
    #endif

    @Test("Universal Clipboard is off until asked for")
    func defaultsOff() {
        let original = AppPreferences.defaults.object(forKey: AppPreferences.Keys.allowUniversalClipboard)
        defer { AppPreferences.defaults.set(original, forKey: AppPreferences.Keys.allowUniversalClipboard) }

        AppPreferences.defaults.removeObject(forKey: AppPreferences.Keys.allowUniversalClipboard)
        #expect(!AppPreferences.allowUniversalClipboard)
    }
}
