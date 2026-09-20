//
//  EncryptionKeyManager.swift
//  Shared (app, widget, AutoFill)
//
//  Single owner of the symmetric key that seals OTP secrets at rest (local store and CloudKit).
//
//  The key lives in two places:
//    1. iCloud Keychain (synchronizable) — shared by all of the user's devices, so a record
//       uploaded by one device can be decrypted by another. This is the key we encrypt with.
//    2. App Group container file — mirror of (1) so the widget and AutoFill extensions, which
//       must never mint a key, can read it without Keychain round-trips.
//  Keys written by older versions (plain Keychain items) are still read, and data sealed with them
//  is re-sealed with the primary key on the next save.
//
//  ⚠️ The most dangerous thing this type can do is mint a key when one already exists but is
//  temporarily unreadable (device locked, Keychain busy): that orphans every existing record and,
//  because the shared item syncs, can propagate to other devices. Every lookup therefore reports
//  `absent` and `unavailable` separately, and a key is minted **only** when every source is
//  positively absent.
//

import Foundation
import CryptoKit
import os

/// Supplies the keys used to seal and open account secrets.
public protocol KeyProviding: Sendable {
    /// The key new data is sealed with; `nil` when key storage can't be read right now.
    var primaryKey: SymmetricKey? { get }
    /// Every key that may have sealed existing data, newest first.
    var allKeys: [SymmetricKey] { get }
}

public final class EncryptionKeyManager: KeyProviding, @unchecked Sendable {
    public static let shared = EncryptionKeyManager()

    private static let keyFileName = ".totp-encryption-key"
    private static let sharedService = "TOTP-Shared-Encryption"
    private static let sharedAccount = "shared-key"
    private static let legacyServices = ["TOTP-SharedData-Encryption", "TOTP-CloudKit-Encryption"]
    private static let logger = Logger(subsystem: "com.lucferbux.TOTP", category: "Encryption")

    /// Result of looking for a key in one place.
    enum Lookup: Equatable {
        /// A key is there and was read.
        case found(SymmetricKey)
        /// There is definitely no key here (and writing one is safe).
        case absent
        /// A key may exist but can't be read right now — never overwrite on this.
        case unavailable
    }

    struct KeySet {
        let primary: SymmetricKey
        let all: [SymmetricKey]
        let isShared: Bool
    }

    private let lock = NSLock()
    private var cached: KeySet?

    private init() {}

    // MARK: - KeyProviding

    public var primaryKey: SymmetricKey? { resolve()?.primary }
    public var allKeys: [SymmetricKey] { resolve()?.all ?? [] }

    /// True when the primary key is shared through iCloud Keychain (so other devices can read our records).
    public var usesSharedKey: Bool { resolve()?.isShared ?? false }

    /// True when key storage couldn't be read; the UI can tell the user instead of showing "no accounts".
    public var isKeyUnavailable: Bool { resolve() == nil }

    // MARK: - Encryption

    public func encryptData(_ data: Data) throws -> Data {
        guard let key = primaryKey else { throw EncryptionKeyError.keyUnavailable }
        return try AccountCrypto.seal(data, using: key)
    }

    /// Tries every known key, so data sealed by an older key (or another device) still opens.
    public func decryptData(_ encryptedData: Data) throws -> Data {
        let keys = allKeys
        guard !keys.isEmpty else { throw EncryptionKeyError.keyUnavailable }
        return try AccountCrypto.open(encryptedData, usingAny: keys)
    }

    // MARK: - Read-only access (extensions)

    /// Loads the key without ever creating one. Extensions must never mint a key.
    public static func existingKey() -> SymmetricKey? {
        existingKeys().first
    }

    /// Every key an extension can decrypt with, newest first.
    public static func existingKeys() -> [SymmetricKey] {
        var keys: [SymmetricKey] = []
        if case let .found(shared) = loadFromKeychain(service: sharedService, account: sharedAccount, synchronizable: true) {
            keys.append(shared)
        }
        if case let .found(file) = loadFromSharedFile() {
            keys.append(file)
        }
        return dedupe(keys)
    }

    // MARK: - Key resolution

    /// Returns the key set, resolving (and only if provably necessary, creating) it once.
    private func resolve() -> KeySet? {
        lock.lock()
        defer { lock.unlock() }
        if let cached { return cached }
        let resolved = Self.resolveKeys()
        cached = resolved          // stays nil when unavailable, so the next call retries
        return resolved
    }

    /// Forgets the cached key set; the next access re-reads storage.
    /// Call after protected data becomes available following a locked-device launch.
    public func invalidateCache() {
        lock.lock()
        cached = nil
        lock.unlock()
    }

    static func resolveKeys() -> KeySet? {
        let shared = loadFromKeychain(service: sharedService, account: sharedAccount, synchronizable: true)
        let file = loadFromSharedFile()
        let legacy = legacyKeychainKeys()

        // Any source that might hold a key but can't be read means we must not write anything.
        let anyUnavailable = shared == .unavailable || file == .unavailable
        var known: [SymmetricKey] = []
        if case let .found(key) = file { known.append(key) }
        known.append(contentsOf: legacy)
        known = dedupe(known)

        // 1. A key synced from another device wins — that's what makes sync work.
        if case let .found(sharedKey) = shared {
            if case let .found(fileKey) = file, data(of: fileKey) == data(of: sharedKey) {
                // Mirror already matches
            } else {
                // Mirror it so the widget and AutoFill can read it without the Keychain
                saveToSharedFile(sharedKey, overwriteExisting: true)
            }
            return KeySet(primary: sharedKey, all: dedupe([sharedKey] + known), isShared: true)
        }

        if anyUnavailable {
            logger.notice("Key storage is temporarily unreadable; not creating a key")
            return nil
        }

        // 2. This device has a key but it isn't shared yet — publish it, don't replace it.
        if let local = known.first {
            let published = saveToKeychain(local, service: sharedService, account: sharedAccount, synchronizable: true)
            saveToSharedFile(local, overwriteExisting: false)
            if !published {
                logger.notice("iCloud Keychain unavailable; using the device-local key")
            }
            return KeySet(primary: local, all: known, isShared: published)
        }

        // 3. Every source positively reported "absent" — this really is a first run.
        let created = SymmetricKey(size: .bits256)
        let published = saveToKeychain(created, service: sharedService, account: sharedAccount, synchronizable: true)
        saveToSharedFile(created, overwriteExisting: false)
        logger.info("Created a new encryption key")
        return KeySet(primary: created, all: [created], isShared: published)
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

    static func loadFromSharedFile() -> Lookup {
        guard let url = keyFileURL else { return .unavailable }   // group container not ready
        if !FileManager.default.fileExists(atPath: url.path) { return .absent }
        do {
            let data = try Data(contentsOf: url)
            guard data.count == 32 else { return .unavailable }   // don't clobber something unexpected
            hardenKeyFile(at: url)   // keys written by ≤4.3 were world-readable and backed up
            return .found(SymmetricKey(data: data))
        } catch {
            // Exists but unreadable: almost always file protection before first unlock
            logger.notice("Key file exists but could not be read")
            return .unavailable
        }
    }

    /// Writes the key mirror. Never replaces an existing file unless explicitly told to.
    private static func saveToSharedFile(_ key: SymmetricKey, overwriteExisting: Bool) {
        guard let url = keyFileURL else { return }
        if !overwriteExisting && FileManager.default.fileExists(atPath: url.path) { return }
        do {
            try data(of: key).write(to: url, options: [.atomic])
            var attributes: [FileAttributeKey: Any] = [.posixPermissions: 0o600]
            #if os(iOS)
            // Widget / AutoFill must still read it after first unlock
            attributes[.protectionKey] = FileProtectionType.completeUntilFirstUserAuthentication
            #endif
            try FileManager.default.setAttributes(attributes, ofItemAtPath: url.path)
            hardenKeyFile(at: url)
        } catch {
            logger.error("Failed to persist encryption key: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Owner-only, and out of backups — the key is recoverable from iCloud Keychain, so there's no
    /// reason for it to sit next to the ciphertext in an unencrypted device backup.
    private static func hardenKeyFile(at url: URL) {
        let current = (try? FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber)??.intValue
        if current != 0o600 {
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
        if (try? url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup) != true {
            var url = url
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? url.setResourceValues(values)
        }
    }

    // MARK: - Keychain

    private static func baseQuery(service: String, account: String, synchronizable: Bool, accessGroup: String? = nil) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        if synchronizable { query[kSecAttrSynchronizable as String] = kCFBooleanTrue }
        if let accessGroup { query[kSecAttrAccessGroup as String] = accessGroup }
        #if os(macOS)
        // Without this macOS uses the legacy file keychain, where accessibility and
        // synchronizable behave inconsistently.
        query[kSecUseDataProtectionKeychain as String] = true
        #endif
        return query
    }

    static func loadFromKeychain(service: String, account: String, synchronizable: Bool, accessGroup: String? = nil) -> Lookup {
        var query = baseQuery(service: service, account: account, synchronizable: synchronizable, accessGroup: accessGroup)
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
            // errSecInteractionNotAllowed (locked device), errSecMissingEntitlement, daemon errors…
            logger.notice("Keychain read failed with status \(status, privacy: .public)")
            return .unavailable
        }
    }

    /// Updates the item in place, adding it only when it's positively missing.
    /// Never deletes: deleting a synchronizable item removes it from every device.
    @discardableResult
    private static func saveToKeychain(_ key: SymmetricKey, service: String, account: String, synchronizable: Bool) -> Bool {
        let query = baseQuery(service: service, account: account, synchronizable: synchronizable)
        let updateStatus = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data(of: key)] as CFDictionary)
        if updateStatus == errSecSuccess { return true }

        guard updateStatus == errSecItemNotFound else {
            logger.error("Keychain update failed with status \(updateStatus, privacy: .public)")
            return false
        }

        var attributes = query
        attributes[kSecValueData as String] = data(of: key)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let addStatus = SecItemAdd(attributes as CFDictionary, nil)
        if addStatus != errSecSuccess {
            logger.error("Keychain write failed with status \(addStatus, privacy: .public)")
        }
        return addStatus == errSecSuccess
    }

    private static func legacyKeychainKeys() -> [SymmetricKey] {
        var keys: [SymmetricKey] = []
        for service in legacyServices {
            for accessGroup in [nil, AppGroup.identifier] as [String?] {
                if case let .found(key) = loadFromKeychain(service: service, account: "master-key", synchronizable: false, accessGroup: accessGroup) {
                    keys.append(key)
                }
            }
        }
        return keys
    }
}

public enum EncryptionKeyError: LocalizedError {
    case keyUnavailable

    public var errorDescription: String? {
        String(localized: "Your encryption key isn't available yet. Unlock the device and try again.")
    }
}
