//
//  EncryptionKeyManager.swift
//  Shared (app, widget, AutoFill)
//
//  Single owner of the symmetric key that seals OTP secrets at rest (local store and CloudKit).
//
//  The key lives in three places, in priority order:
//    1. iCloud Keychain (synchronizable) — shared by all of the user's devices, so a record
//       uploaded by one device can be decrypted by another. This is the key we encrypt with.
//    2. App Group container file — mirror of (1) so the widget and AutoFill extensions, which
//       must never mint a key, can read it without Keychain round-trips.
//    3. Legacy local Keychain items — older versions stored the key here.
//
//  Anything written by an older version (or another device before the shared key existed) is still
//  readable: `decryptionKeys` returns every key we know about, and saving re-seals with the primary.
//

import Foundation
import CryptoKit
import os

public final class EncryptionKeyManager: @unchecked Sendable {
    public static let shared = EncryptionKeyManager()

    private static let keyFileName = ".totp-encryption-key"
    private static let sharedService = "TOTP-Shared-Encryption"
    private static let sharedAccount = "shared-key"
    private static let legacyServices = ["TOTP-SharedData-Encryption", "TOTP-CloudKit-Encryption"]
    private static let logger = Logger(subsystem: "com.lucferbux.TOTP", category: "Encryption")

    /// The key new data is encrypted with.
    public private(set) var encryptionKey: SymmetricKey

    /// Every key that may have sealed existing data, newest first. Use for decryption.
    public private(set) var decryptionKeys: [SymmetricKey]

    /// True when the primary key came from (or was published to) iCloud Keychain.
    public private(set) var usesSharedKey: Bool

    private init() {
        let resolved = Self.resolveKeys()
        encryptionKey = resolved.primary
        decryptionKeys = resolved.all
        usesSharedKey = resolved.shared
    }

    // MARK: - Encryption

    public func encryptData(_ data: Data) throws -> Data {
        try AccountCrypto.seal(data, using: encryptionKey)
    }

    /// Tries every known key, so data sealed by an older key (or another device) still opens.
    public func decryptData(_ encryptedData: Data) throws -> Data {
        try AccountCrypto.open(encryptedData, usingAny: decryptionKeys)
    }

    // MARK: - Read-only access (extensions)

    /// Loads the key without creating one. Extensions must never mint a key.
    public static func existingKey() -> SymmetricKey? {
        loadFromSharedFile() ?? loadFromKeychain(service: sharedService, account: sharedAccount, synchronizable: true)
    }

    /// Every key an extension can decrypt with.
    public static func existingKeys() -> [SymmetricKey] {
        var keys: [SymmetricKey] = []
        if let shared = loadFromKeychain(service: sharedService, account: sharedAccount, synchronizable: true) { keys.append(shared) }
        if let file = loadFromSharedFile() { keys.append(file) }
        return dedupe(keys)
    }

    // MARK: - Key resolution

    private static func resolveKeys() -> (primary: SymmetricKey, all: [SymmetricKey], shared: Bool) {
        let fileKey = loadFromSharedFile()
        let legacyKeys = legacyKeychainKeys()
        var known = dedupe([fileKey].compactMap { $0 } + legacyKeys)

        // 1. A key already synced from another device wins — that's what makes sync work.
        if let sharedKey = loadFromKeychain(service: sharedService, account: sharedAccount, synchronizable: true) {
            if fileKey.map({ data(of: $0) != data(of: sharedKey) }) ?? true {
                // Mirror it for the extensions
                saveToSharedFile(sharedKey)
            }
            return (sharedKey, dedupe([sharedKey] + known), true)
        }

        // 2. No shared key yet: promote what this device already uses, or mint one.
        let local = known.first ?? SymmetricKey(size: .bits256)
        if known.isEmpty { known = [local] }
        let published = saveToKeychain(local, service: sharedService, account: sharedAccount, synchronizable: true)
        saveToSharedFile(local)
        if !published {
            logger.notice("iCloud Keychain unavailable; using the device-local key")
        }
        return (local, dedupe([local] + known), published)
    }

    private static func dedupe(_ keys: [SymmetricKey]) -> [SymmetricKey] {
        var seen = Set<Data>()
        return keys.filter { seen.insert(data(of: $0)).inserted }
    }

    private static func data(of key: SymmetricKey) -> Data {
        key.withUnsafeBytes { Data($0) }
    }

    // MARK: - App Group file

    private static var keyFileURL: URL? {
        AppGroup.containerURL?.appendingPathComponent(keyFileName)
    }

    private static func loadFromSharedFile() -> SymmetricKey? {
        guard let url = keyFileURL, let data = try? Data(contentsOf: url), data.count == 32 else { return nil }
        return SymmetricKey(data: data)
    }

    private static func saveToSharedFile(_ key: SymmetricKey) {
        guard let url = keyFileURL else { return }
        do {
            try data(of: key).write(to: url, options: [.atomic])
            #if os(iOS)
            // Widget / AutoFill must be able to read it after first unlock
            try FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: url.path
            )
            #endif
        } catch {
            logger.error("Failed to persist encryption key: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Keychain

    private static func loadFromKeychain(service: String, account: String, synchronizable: Bool, accessGroup: String? = nil) -> SymmetricKey? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        if synchronizable { query[kSecAttrSynchronizable as String] = kCFBooleanTrue }
        if let accessGroup { query[kSecAttrAccessGroup as String] = accessGroup }

        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data, data.count == 32 else { return nil }
        return SymmetricKey(data: data)
    }

    @discardableResult
    private static func saveToKeychain(_ key: SymmetricKey, service: String, account: String, synchronizable: Bool) -> Bool {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        if synchronizable { query[kSecAttrSynchronizable as String] = kCFBooleanTrue }

        SecItemDelete(query as CFDictionary)
        var attributes = query
        attributes[kSecValueData as String] = data(of: key)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(attributes as CFDictionary, nil)
        if status != errSecSuccess {
            logger.error("Keychain write failed: \(status, privacy: .public)")
        }
        return status == errSecSuccess
    }

    private static func legacyKeychainKeys() -> [SymmetricKey] {
        var keys: [SymmetricKey] = []
        for service in legacyServices {
            for accessGroup in [nil, AppGroup.identifier] as [String?] {
                if let key = loadFromKeychain(service: service, account: "master-key", synchronizable: false, accessGroup: accessGroup) {
                    keys.append(key)
                }
            }
        }
        return keys
    }
}
