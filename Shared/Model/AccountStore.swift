//
//  AccountStore.swift
//  Shared (app, widget, AutoFill)
//
//  Encrypted App Group persistence format shared by every target.
//  The app writes through SharedDataManager; extensions read with `AccountStore.loadAccounts()`.
//

import Foundation
import CryptoKit

public enum AppGroup {
    public static let identifier = "group.com.lucferbux.TOTP"

    /// App Group defaults (falls back to `.standard` when the group isn't provisioned, e.g. unsigned builds).
    public static var defaults: UserDefaults {
        UserDefaults(suiteName: identifier) ?? .standard
    }

    public static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }
}

// MARK: - Storage Model

/// On-disk representation. `encryptedKey` and `encryptedPrefix` hold secret material and are
/// always ChaChaPoly-sealed; everything else (issuer, account name, digits…) is metadata.
public struct StoredOtpAccount: Codable, Equatable, Sendable {
    public let id: String
    public let issuer: String?
    public let name: String?
    public let prefix: String?
    public let encryptedKey: Data
    public let isHotp: Bool
    public let digits: Int
    public let interval: Double
    public let counter: Int64
    public let createdDate: Date
    public let modifiedDate: Date
    public let associatedDomains: [String]?
    /// Added in 4.0 — absent in older payloads, meaning SHA-1.
    public let algorithm: String?
    /// Added in 4.4: the fixed prefix (PIN) sealed with the same key as the secret.
    /// Older payloads carry it in the plaintext `prefix` field instead; those are re-sealed on save.
    public let encryptedPrefix: Data?

    public init(id: String, issuer: String?, name: String?, prefix: String?, encryptedKey: Data, isHotp: Bool, digits: Int, interval: Double, counter: Int64, createdDate: Date, modifiedDate: Date, associatedDomains: [String]? = nil, algorithm: String? = nil, encryptedPrefix: Data? = nil) {
        self.id = id
        self.issuer = issuer
        self.name = name
        self.prefix = prefix
        self.encryptedKey = encryptedKey
        self.isHotp = isHotp
        self.digits = digits
        self.interval = interval
        self.counter = counter
        self.createdDate = createdDate
        self.modifiedDate = modifiedDate
        self.associatedDomains = associatedDomains
        self.algorithm = algorithm
        self.encryptedPrefix = encryptedPrefix
    }

    // Codable conformance with backward compatibility
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        issuer = try container.decodeIfPresent(String.self, forKey: .issuer)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        prefix = try container.decodeIfPresent(String.self, forKey: .prefix)
        encryptedKey = try container.decode(Data.self, forKey: .encryptedKey)
        isHotp = try container.decode(Bool.self, forKey: .isHotp)
        digits = try container.decode(Int.self, forKey: .digits)
        interval = try container.decode(Double.self, forKey: .interval)
        counter = try container.decode(Int64.self, forKey: .counter)
        createdDate = try container.decodeIfPresent(Date.self, forKey: .createdDate) ?? .distantPast
        modifiedDate = try container.decodeIfPresent(Date.self, forKey: .modifiedDate) ?? .distantPast
        associatedDomains = try container.decodeIfPresent([String].self, forKey: .associatedDomains)
        algorithm = try container.decodeIfPresent(String.self, forKey: .algorithm)
        encryptedPrefix = try container.decodeIfPresent(Data.self, forKey: .encryptedPrefix)
    }

    public init(model: OtpModel, key: SymmetricKey, createdDate: Date = .now, modifiedDate: Date = .now) throws {
        let entry = model.entry
        let sealedPrefix = try model.prefix.flatMap { prefix -> Data? in
            prefix.isEmpty ? nil : try AccountCrypto.seal(Data(prefix.utf8), using: key)
        }
        self.init(
            id: model.id.uuidString,
            issuer: model.issuer,
            name: model.name,
            prefix: nil,   // never written in the clear from 4.4 on
            encryptedKey: try AccountCrypto.seal(entry.key, using: key),
            isHotp: entry.isHotp,
            digits: entry.digits,
            interval: entry.interval ?? 30,
            counter: Int64(clamping: entry.counter ?? 0),
            createdDate: createdDate,
            modifiedDate: modifiedDate,
            associatedDomains: model.associatedDomains,
            algorithm: entry.algorithm == .sha1 ? nil : entry.algorithm.rawValue,
            encryptedPrefix: sealedPrefix
        )
    }

    public func model(key: SymmetricKey) throws -> OtpModel {
        try model(keys: [key])
    }

    /// Opens the secret with the first key that works, so data sealed by an older key
    /// (or by another device before the shared key existed) is still readable.
    public func model(keys: [SymmetricKey]) throws -> OtpModel {
        let secret = try AccountCrypto.open(encryptedKey, usingAny: keys)
        // 4.4+ seals the prefix; older payloads still carry it in the clear.
        let resolvedPrefix: String?
        if let encryptedPrefix {
            resolvedPrefix = String(data: try AccountCrypto.open(encryptedPrefix, usingAny: keys), encoding: .utf8)
        } else {
            resolvedPrefix = prefix
        }
        let algorithm = algorithm.flatMap(OtpAlgorithm.init(lenient:)) ?? .sha1
        let entry: OtpEntry = isHotp
            ? .hotp(key: secret, digits: digits, counter: UInt64(max(0, counter)), algorithm: algorithm)
            : .totp(key: secret, digits: digits, interval: interval, algorithm: algorithm)
        return OtpModel(
            id: UUID(uuidString: id) ?? UUID(),
            issuer: issuer,
            name: name,
            prefix: resolvedPrefix,
            entry: entry,
            associatedDomains: associatedDomains
        )
    }

    /// True when this record still needs re-sealing with the current primary key.
    public func needsResealing(with key: SymmetricKey) -> Bool {
        if prefix != nil { return true }                                  // plaintext prefix from ≤4.3
        if (try? AccountCrypto.open(encryptedKey, using: key)) == nil { return true }
        if let encryptedPrefix, (try? AccountCrypto.open(encryptedPrefix, using: key)) == nil { return true }
        return false
    }
}

// MARK: - Crypto

public enum AccountCrypto {
    public static func seal(_ data: Data, using key: SymmetricKey) throws -> Data {
        try ChaChaPoly.seal(data, using: key).combined
    }

    public static func open(_ data: Data, using key: SymmetricKey) throws -> Data {
        try ChaChaPoly.open(ChaChaPoly.SealedBox(combined: data), using: key)
    }

    /// Tries every key in order; throws the last failure when none works.
    public static func open(_ data: Data, usingAny keys: [SymmetricKey]) throws -> Data {
        guard !keys.isEmpty else { throw CryptoKitError.authenticationFailure }
        var lastError: Error = CryptoKitError.authenticationFailure
        for key in keys {
            do {
                return try open(data, using: key)
            } catch {
                lastError = error
            }
        }
        throw lastError
    }
}

// MARK: - Store

public enum AccountStore {
    public static let accountsKey = "stored_totp_accounts"

    /// What a stored payload decoded to: the accounts we could open, and the raw records we could
    /// not. The unreadable ones must be written back untouched — dropping them destroys secrets we
    /// may be able to read again once the right key is available.
    public struct Decoded {
        public var accounts: [OtpModel]
        public var unreadable: [StoredOtpAccount]

        public var isComplete: Bool { unreadable.isEmpty }
    }

    /// Decodes a stored payload; accounts that fail to decrypt are skipped.
    public static func decode(_ data: Data, key: SymmetricKey) throws -> [OtpModel] {
        try decode(data, keys: [key])
    }

    public static func decode(_ data: Data, keys: [SymmetricKey]) throws -> [OtpModel] {
        try decodeAll(data, keys: keys).accounts
    }

    public static func decodeAll(_ data: Data, keys: [SymmetricKey]) throws -> Decoded {
        let stored = try JSONDecoder().decode([StoredOtpAccount].self, from: data)
        var accounts: [OtpModel] = []
        var unreadable: [StoredOtpAccount] = []
        for record in stored {
            if let model = try? record.model(keys: keys) {
                accounts.append(model)
            } else {
                unreadable.append(record)
            }
        }
        return Decoded(accounts: accounts, unreadable: unreadable)
    }

    /// Encodes accounts, keeping the original creation date of accounts already present in `previous`.
    /// `preserving` records are written back byte-for-byte — use it for records that couldn't be
    /// decrypted, so a save can never erase them.
    public static func encode(_ accounts: [OtpModel], key: SymmetricKey, previous: [StoredOtpAccount] = [], preserving: [StoredOtpAccount] = [], now: Date = .now) throws -> Data {
        let created = Dictionary(previous.map { ($0.id, $0.createdDate) }, uniquingKeysWith: { first, _ in first })
        let stored = try accounts.map { account in
            try StoredOtpAccount(model: account, key: key, createdDate: created[account.id.uuidString] ?? now, modifiedDate: now)
        }
        return try JSONEncoder().encode(stored + preserving)
    }

    /// Raw stored records (no decryption).
    public static func storedRecords(in defaults: UserDefaults = AppGroup.defaults) -> [StoredOtpAccount] {
        guard let data = defaults.data(forKey: accountsKey) else { return [] }
        return (try? JSONDecoder().decode([StoredOtpAccount].self, from: data)) ?? []
    }

    /// Read-only loader used by the widget, AutoFill and App Intents.
    public static func loadAccounts(from defaults: UserDefaults = AppGroup.defaults, key: SymmetricKey? = nil) -> [OtpModel] {
        let keys = key.map { [$0] } ?? EncryptionKeyManager.existingKeys()
        guard !keys.isEmpty, let data = defaults.data(forKey: accountsKey) else { return [] }
        return (try? decode(data, keys: keys)) ?? []
    }
}
