//
//  WatchKeyStore.swift
//  Watch Shared (watch app + watch complication)
//
//  The key that seals the watch's copy of the accounts.
//
//  It is the watch's own key, never the iPhone's: a Keychain item that is NOT synchronizable and
//  `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, so it never leaves this watch, never goes to
//  iCloud Keychain and isn't restored from a backup. It lives in the keychain access group the watch
//  app and its complication share (the first entry of both targets' `keychain-access-groups`, so a
//  new item lands there without naming the team prefix at runtime). Losing it costs nothing: the
//  iPhone is the source of truth and the next application context re-creates the cache.
//
//  `EncryptionKeyManager` isn't compiled into the watch targets at all, so nothing here can mint or
//  publish the synchronizable key the iPhone, iPad and Mac share.
//
//  Only the app may create the key (`keyForSealing()`); the complication only reads (`existingKey()`).
//  As on the iPhone, a key that exists but can't be read right now is never replaced.
//

import Foundation
import CryptoKit
import Security
import os

enum WatchKeyStore {
    private static let service = "TOTP-Watch-Encryption"
    private static let account = "watch-cache-key"
    private static let logger = Logger(subsystem: "com.lucferbux.TOTP.watchkitapp", category: "Encryption")

    enum Lookup: Equatable {
        case found(SymmetricKey)
        /// Definitely no key: creating one is safe.
        case absent
        /// A key may exist but can't be read now (before first unlock, keychain busy).
        case unavailable
    }

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any
        ]
    }

    static func lookup() -> Lookup {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data, data.count == 32 else { return .unavailable }
            return .found(SymmetricKey(data: data))
        case errSecItemNotFound:
            return .absent
        default:
            logger.notice("Keychain read failed with status \(status, privacy: .public)")
            return .unavailable
        }
    }

    /// Read-only: the complication uses this and never creates a key.
    static func existingKey() -> SymmetricKey? {
        if case let .found(key) = lookup() { return key }
        return nil
    }

    /// The key to seal with, created on first use. `nil` when the keychain can't be read now.
    static func keyForSealing() -> SymmetricKey? {
        switch lookup() {
        case let .found(key):
            return key
        case .unavailable:
            return nil
        case .absent:
            let key = SymmetricKey(size: .bits256)
            var attributes = baseQuery
            attributes[kSecValueData as String] = key.withUnsafeBytes { Data($0) }
            attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let status = SecItemAdd(attributes as CFDictionary, nil)
            switch status {
            case errSecSuccess:
                logger.info("Created the watch cache key")
                return key
            case errSecDuplicateItem:
                // Created concurrently: use that one, never overwrite it.
                return existingKey()
            default:
                logger.error("Keychain write failed with status \(status, privacy: .public)")
                return nil
            }
        }
    }
}
