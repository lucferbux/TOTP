//
//  EncryptionKeyManager.swift
//  Shared (app, widget, AutoFill)
//
//  Single owner of the symmetric key that seals OTP secrets at rest (local store and CloudKit).
//
//  The key lives in two places:
//    1. iCloud Keychain (synchronizable) — shared by all of the user's devices, so a record
//       uploaded by one device can be decrypted by another. Every key ever created has its own
//       item (`key-<milliseconds>-<uuid>`): two devices that each create one before iCloud Keychain
//       has synced never overwrite each other. The oldest — by the name, which syncs, not by an
//       attribute that might not — is the primary key on every device, so all of them converge on
//       it, and the others stay readable.
//    2. App Group container file — mirror of (1) so the widget and AutoFill extensions, which
//       must never mint a key, can read it without Keychain round-trips.
//  Keys written by older versions (plain Keychain items) are still read, and data sealed with them
//  is re-sealed with the primary key on the next save.
//
//  ⚠️ The most dangerous thing this type can do is mint a key when one already exists but is
//  temporarily unreadable (device locked, Keychain busy): that orphans every existing record and,
//  because the shared item syncs, can propagate to other devices. Every lookup therefore reports
//  `absent` and `unavailable` separately, and a key is minted **only** when every source is
//  positively absent — and only to seal something (`primaryKey`). Reading (`allKeys`) never mints:
//  on a new device the first sync reads iCloud records before iCloud Keychain has delivered the
//  shared key, and minting there would race that key.
//
//  A key is never discarded either. When a different shared key replaces the mirror file, the old
//  one moves to a "retired" file and stays in `allKeys`, so anything still sealed with it opens.
//

import Foundation
import CryptoKit
import os

/// Supplies the keys used to seal and open account secrets.
public protocol KeyProviding: Sendable {
    /// The key new data is sealed with; `nil` when key storage can't be read right now.
    var primaryKey: SymmetricKey? { get }
    /// Every key that may have sealed existing data, primary first.
    var allKeys: [SymmetricKey] { get }
}

public final class EncryptionKeyManager: KeyProviding, @unchecked Sendable {
    public static let shared = EncryptionKeyManager()

    private static let keyFileName = ".totp-encryption-key"
    private static let retiredKeysFileName = ".totp-encryption-keys-retired"
    private static let sharedService = "TOTP-Shared-Encryption"
    /// The single item earlier builds wrote; always the oldest key when present.
    private static let legacySharedAccount = "shared-key"
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
    /// When a read last found no key. Reads within `missBackoff` of it don't query storage again:
    /// a body that asks twice per render would otherwise run six Keychain queries each time.
    private var lastMiss: Date?
    private static let missBackoff: TimeInterval = 2

    private init() {}

    // MARK: - KeyProviding

    /// The key to seal with. The only accessor that may create one, on a genuine first run.
    public var primaryKey: SymmetricKey? { resolve(creatingIfAbsent: true)?.primary }
    /// Every key that can open existing data. Never creates a key.
    public var allKeys: [SymmetricKey] { resolve(creatingIfAbsent: false)?.all ?? [] }

    /// True when the primary key is shared through iCloud Keychain (so other devices can read our records).
    public var usesSharedKey: Bool { resolve(creatingIfAbsent: false)?.isShared ?? false }

    /// True when key storage couldn't be read; the UI can tell the user instead of showing "no accounts".
    public var isKeyUnavailable: Bool { resolve(creatingIfAbsent: false) == nil }

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

    /// Every key an extension can decrypt with, primary first.
    public static func existingKeys() -> [SymmetricKey] {
        var keys = loadKeychainKeys(service: sharedService, synchronizable: true) ?? []
        if case let .found(file) = loadFromSharedFile() {
            keys.append(file)
        }
        keys.append(contentsOf: loadRetiredKeys())
        return dedupe(keys)
    }

    // MARK: - Key resolution

    /// Returns the key set, resolving it once — and creating one only when asked to and provably necessary.
    private func resolve(creatingIfAbsent: Bool) -> KeySet? {
        lock.lock()
        defer { lock.unlock() }
        if let cached { return cached }
        if !creatingIfAbsent, let lastMiss, Date.now.timeIntervalSince(lastMiss) < Self.missBackoff {
            return nil
        }
        let resolved = Self.resolveKeys(creatingIfAbsent: creatingIfAbsent)
        cached = resolved          // stays nil when unavailable, so a later call retries
        lastMiss = resolved == nil ? .now : nil
        return resolved
    }

    /// Forgets the cached key set; the next access re-reads storage.
    /// Call after protected data becomes available following a locked-device launch.
    public func invalidateCache() {
        lock.lock()
        cached = nil
        lastMiss = nil
        lock.unlock()
    }

    static func resolveKeys(creatingIfAbsent: Bool = true) -> KeySet? {
        let shared = loadKeychainKeys(service: sharedService, synchronizable: true)
        let file = loadFromSharedFile()
        let legacy = legacyKeychainKeys()
        let retired = loadRetiredKeys()

        // Any source that might hold a key but can't be read means we must not write anything.
        let anyUnavailable = shared == nil || file == .unavailable
        var known: [SymmetricKey] = []
        if case let .found(key) = file { known.append(key) }
        known.append(contentsOf: legacy)
        known = dedupe(known)

        // 1. The oldest key in iCloud Keychain wins on every device — that's what makes sync work.
        if let shared, let sharedKey = shared.first {
            if case let .found(fileKey) = file, data(of: fileKey) == data(of: sharedKey) {
                // Mirror already matches
            } else {
                // Mirror it so the widget and AutoFill can read it without the Keychain — but keep
                // the key it replaces: records not yet re-sealed (offline, partly unreadable store)
                // still need it, and this mirror may be its only copy.
                var keptReplacedKey = true
                if case let .found(fileKey) = file {
                    keptReplacedKey = retire(fileKey)
                }
                // If it couldn't be kept, leave the mirror alone rather than lose the old key
                if keptReplacedKey {
                    saveToSharedFile(sharedKey, overwriteExisting: true)
                }
            }
            return KeySet(primary: sharedKey, all: dedupe(shared + known + retired), isShared: true)
        }

        if anyUnavailable {
            logger.notice("Key storage is temporarily unreadable; not creating a key")
            return nil
        }

        // 2. This device has a key but it isn't shared yet — publish it, don't replace it.
        if let local = known.first {
            let published = addToKeychain(local, service: sharedService)
            saveToSharedFile(local, overwriteExisting: false)
            if !published {
                logger.notice("iCloud Keychain unavailable; using the device-local key")
            }
            return KeySet(primary: local, all: dedupe(known + retired), isShared: published)
        }

        // 3. Every source positively reported "absent" — this really is a first run. Only something
        // that is about to seal data may create the key; a read just reports that there is none yet.
        guard creatingIfAbsent else { return nil }
        let created = SymmetricKey(size: .bits256)
        let published = addToKeychain(created, service: sharedService)
        saveToSharedFile(created, overwriteExisting: false)
        logger.info("Created a new encryption key")
        return KeySet(primary: created, all: dedupe([created] + retired), isShared: published)
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
        writeKeyFile(data(of: key), to: url)
    }

    @discardableResult
    private static func writeKeyFile(_ data: Data, to url: URL) -> Bool {
        do {
            try data.write(to: url, options: [.atomic])
            var attributes: [FileAttributeKey: Any] = [.posixPermissions: 0o600]
            #if os(iOS)
            // Widget / AutoFill must still read it after first unlock
            attributes[.protectionKey] = FileProtectionType.completeUntilFirstUserAuthentication
            #endif
            try FileManager.default.setAttributes(attributes, ofItemAtPath: url.path)
            hardenKeyFile(at: url)
            return true
        } catch {
            logger.error("Failed to persist encryption key: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    // MARK: - Retired keys

    private static var retiredKeysURL: URL? {
        AppGroup.containerURL?.appendingPathComponent(retiredKeysFileName)
    }

    /// Keys that used to be the primary key, oldest first: 32 bytes each, back to back.
    static func loadRetiredKeys() -> [SymmetricKey] {
        guard let url = retiredKeysURL, let data = try? Data(contentsOf: url), data.count % 32 == 0 else { return [] }
        return stride(from: 0, to: data.count, by: 32).map { offset in
            SymmetricKey(data: data.subdata(in: offset..<(offset + 32)))
        }
    }

    /// Adds `key` to the retired keys; nothing is ever removed from that file. Returns whether the
    /// key is now safely stored there.
    private static func retire(_ key: SymmetricKey) -> Bool {
        guard let url = retiredKeysURL else { return false }
        let retired = loadRetiredKeys()
        if retired.contains(where: { data(of: $0) == data(of: key) }) { return true }
        if FileManager.default.fileExists(atPath: url.path), retired.isEmpty {
            // Exists but unreadable (protected, or not a whole number of keys): don't clobber it
            logger.error("Retired key file is unreadable; not retiring the replaced key")
            return false
        }
        let combined = (retired + [key]).reduce(into: Data()) { $0.append(data(of: $1)) }
        guard writeKeyFile(combined, to: url) else { return false }
        logger.notice("Kept the replaced encryption key as a retired key")
        return true
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

    /// Every key stored under `service`, primary (oldest) first; `[]` when there is none and `nil`
    /// when the Keychain can't be read right now.
    static func loadKeychainKeys(service: String, synchronizable: Bool) -> [SymmetricKey]? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll
        ]
        if synchronizable { query[kSecAttrSynchronizable as String] = kCFBooleanTrue }
        #if os(macOS)
        query[kSecUseDataProtectionKeychain as String] = true
        #endif

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let items = result as? [[String: Any]] else { return nil }
            return orderedKeys(items.compactMap { item in
                guard let account = item[kSecAttrAccount as String] as? String,
                      let data = item[kSecValueData as String] as? Data else { return nil }
                return (account, data)
            })
        case errSecItemNotFound:
            return []
        default:
            // errSecInteractionNotAllowed (locked device), errSecMissingEntitlement, daemon errors…
            logger.notice("Keychain read failed with status \(status, privacy: .public)")
            return nil
        }
    }

    /// Orders stored keys so every device picks the same primary: the legacy single item first
    /// (it predates the rest), then by name, which starts with the creation time in milliseconds.
    /// Entries that aren't 32-byte keys are ignored.
    static func orderedKeys(_ items: [(account: String, data: Data)]) -> [SymmetricKey] {
        items
            .filter { $0.data.count == 32 }
            .sorted { lhs, rhs in
                if (lhs.account == legacySharedAccount) != (rhs.account == legacySharedAccount) {
                    return lhs.account == legacySharedAccount
                }
                return lhs.account < rhs.account
            }
            .map { SymmetricKey(data: $0.data) }
    }

    /// Name for a new key's item: creation time (fixed width, so names sort by it), then a UUID so
    /// two devices can never pick the same one.
    static func newKeyAccount(now: Date = .now) -> String {
        let milliseconds = UInt64(max(0, now.timeIntervalSince1970) * 1000)
        return "key-" + String(format: "%016llu", milliseconds) + "-" + UUID().uuidString
    }

    /// Adds `key` as a new synchronizable item. Never updates or deletes one: deleting a
    /// synchronizable item removes it from every device, and overwriting one loses a key.
    @discardableResult
    private static func addToKeychain(_ key: SymmetricKey, service: String) -> Bool {
        var attributes = baseQuery(service: service, account: newKeyAccount(), synchronizable: true)
        attributes[kSecValueData as String] = data(of: key)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(attributes as CFDictionary, nil)
        if status != errSecSuccess {
            logger.error("Keychain write failed with status \(status, privacy: .public)")
        }
        return status == errSecSuccess
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
