//
//  SharedDataManager.swift
//  TOTP
//
//  Encrypted local store for TOTP accounts (App Group UserDefaults), shared with the
//  widget and AutoFill extensions through `AccountStore`.
//

import Foundation
import Combine
import CryptoKit
import os

/// Launch-time environment switches.
public enum AppEnvironment {
    /// `-UITestMode`: in-memory seeded data, no CloudKit, no app lock, no AutoFill identity writes.
    /// Debug-only: a release build must never let a launch argument disable the lock or swap the store.
    public static let isUITesting: Bool = {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-UITestMode")
            || ProcessInfo.processInfo.arguments.contains("-ScreenshotMode")
        #else
        return false
        #endif
    }()

    /// `-ScreenshotMode`: like UI-test mode, but seeded with a fuller, better-looking set of
    /// accounts for App Store screenshots.
    public static let isTakingScreenshots: Bool = {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-ScreenshotMode")
        #else
        return false
        #endif
    }()
}

public final class SharedDataManager: ObservableObject, @unchecked Sendable {
    public static let shared = SharedDataManager()

    private static let logger = Logger(subsystem: "com.lucferbux.TOTP", category: "Storage")

    private let userDefaults: UserDefaults
    /// Supplies the key we seal with and every key we can open with.
    private let keys: KeyProviding

    /// Records we couldn't decrypt (wrong/unavailable key). Written back untouched on every save so
    /// a save can never destroy secrets we might read again later.
    private var unreadableRecords: [StoredOtpAccount] = []

    @Published public var accounts: [OtpModel] = []
    @Published public var isLoading = false
    @Published public var error: SharedDataError?

    private init() {
        if AppEnvironment.isUITesting {
            let suite = "com.lucferbux.TOTP.uitests"
            let defaults = UserDefaults(suiteName: suite) ?? .standard
            defaults.removePersistentDomain(forName: suite)
            self.userDefaults = defaults
            self.keys = FixedKeys(primaryKey: SymmetricKey(size: .bits256))
            self.accounts = AppEnvironment.isTakingScreenshots ? Self.screenshotSeed : Self.uiTestSeed
            persist()
        } else {
            self.userDefaults = AppGroup.defaults
            self.keys = EncryptionKeyManager.shared
            loadAccounts()
            resealIfNeeded()
        }
    }

    /// Designated initialiser for unit tests. Mirrors the production path, including the
    /// re-seal migration, so tests exercise what ships.
    init(userDefaults: UserDefaults, encryptionKey: SymmetricKey?, decryptionKeys: [SymmetricKey]? = nil) {
        self.userDefaults = userDefaults
        self.keys = FixedKeys(primaryKey: encryptionKey, allKeys: decryptionKeys)
        loadAccounts()
        resealIfNeeded()
    }

    init(userDefaults: UserDefaults, keys: KeyProviding) {
        self.userDefaults = userDefaults
        self.keys = keys
        loadAccounts()
        resealIfNeeded()
    }

    /// True when any stored record still needs re-sealing with the current primary key
    /// (older key, or a prefix left in the clear by ≤4.3).
    var storedUsesLegacyKey: Bool {
        guard let key = keys.primaryKey else { return false }
        return AccountStore.storedRecords(in: userDefaults).contains { $0.needsResealing(with: key) }
    }

    /// Re-seals stored records with the current primary key, but only when every record was readable
    /// — re-writing a partially readable store would drop the records we couldn't open.
    private func resealIfNeeded() {
        guard !accounts.isEmpty, unreadableRecords.isEmpty, storedUsesLegacyKey else { return }
        persist()
    }

    // MARK: - Data Operations

    public func loadAccounts() {
        isLoading = true
        defer { isLoading = false }

        guard let data = userDefaults.data(forKey: AccountStore.accountsKey) else {
            accounts = []
            unreadableRecords = []
            return
        }
        let candidates = keys.allKeys
        guard !candidates.isEmpty else {
            // Key storage is temporarily unreadable (locked device). Keep the ciphertext and say so
            // rather than showing an empty, writable list.
            Self.logger.notice("Encryption key unavailable; leaving stored accounts untouched")
            accounts = []
            unreadableRecords = AccountStore.storedRecords(in: userDefaults)
            error = .keyUnavailable
            return
        }
        do {
            let decoded = try AccountStore.decodeAll(data, keys: candidates)
            accounts = decoded.accounts
            unreadableRecords = decoded.unreadable
            if !decoded.isComplete {
                Self.logger.error("\(decoded.unreadable.count, privacy: .public) stored record(s) could not be decrypted; keeping them untouched")
                error = .someAccountsUnreadable(decoded.unreadable.count)
            }
        } catch {
            Self.logger.error("Failed to load accounts: \(error.localizedDescription, privacy: .public)")
            self.error = .loadFailed(error)
            unreadableRecords = AccountStore.storedRecords(in: userDefaults)
        }
    }

    /// Writes the current `accounts` array. Returns `false` (and sets `error`) on failure.
    @discardableResult
    public func saveAccounts() -> Bool {
        persist()
    }

    public func addAccount(_ account: OtpModel) {
        accounts.append(account)
        persist()
    }

    public func saveAccount(_ account: OtpModel) async throws {
        accounts.append(account)
        if !persist(), let error { throw error }
    }

    public func updateAccount(_ account: OtpModel) async throws {
        guard let index = accounts.firstIndex(where: { $0.id == account.id }) else {
            throw SharedDataError.accountNotFound
        }
        accounts[index] = account
        if !persist(), let error { throw error }
    }

    public func deleteAccount(_ account: OtpModel) {
        deleteAccount(withId: account.id)
    }

    public func deleteAccount(withId id: UUID) {
        accounts.removeAll { $0.id == id }
        persist()
    }

    /// Removes several accounts in one write (batch delete from select mode).
    public func deleteAccounts(withIds ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        accounts.removeAll { ids.contains($0.id) }
        persist()
    }

    /// Reorders accounts (drag to reorder); the order is persisted locally.
    public func moveAccounts(fromOffsets source: IndexSet, toOffset destination: Int) {
        accounts.move(fromOffsets: source, toOffset: destination)
        persist()
    }

    // MARK: - Encryption

    public func encryptData(_ data: Data) throws -> Data {
        guard let key = keys.primaryKey else { throw EncryptionKeyError.keyUnavailable }
        return try AccountCrypto.seal(data, using: key)
    }

    public func decryptData(_ encryptedData: Data) throws -> Data {
        try AccountCrypto.open(encryptedData, usingAny: keys.allKeys)
    }

    /// Re-reads key storage and the account list. Call when the device unlocks after a launch that
    /// happened while protected data was unavailable.
    public func reloadAfterUnlock() {
        EncryptionKeyManager.shared.invalidateCache()
        loadAccounts()
        resealIfNeeded()
    }

    public static func getSharedEncryptionKey() -> SymmetricKey? {
        EncryptionKeyManager.existingKey()
    }

    // MARK: - Private

    @discardableResult
    private func persist() -> Bool {
        guard let key = keys.primaryKey else {
            Self.logger.error("Refusing to save: encryption key unavailable")
            error = .keyUnavailable
            return false
        }
        do {
            let previous = AccountStore.storedRecords(in: userDefaults)
            let data = try AccountStore.encode(accounts, key: key, previous: previous, preserving: unreadableRecords)
            userDefaults.set(data, forKey: AccountStore.accountsKey)
            error = nil
            return true
        } catch {
            Self.logger.error("Failed to save accounts: \(error.localizedDescription, privacy: .public)")
            self.error = .saveFailed(error)
            return false
        }
    }

    /// Accounts shown in App Store screenshots. Fictional names only: real service names and logos
    /// belong to their owners and don't belong in our marketing images (App Review 5.2.2).
    static var screenshotSeed: [OtpModel] {
        // A distinct secret per account, so the screenshots don't show five identical codes.
        func account(_ issuer: String, _ name: String, secret: String, prefix: String? = nil, domain: String? = nil) -> OtpModel {
            OtpModel(issuer: issuer, name: name, prefix: prefix,
                     entry: .totp(key: Data(secret.utf8), digits: 6, interval: 30),
                     associatedDomains: domain.map { [$0] })
        }
        return [
            account("Northwind Corp", "you@northwind.example", secret: "12345678901234567890", prefix: "1234", domain: "sso.northwind.example"),
            account("Contoso Cloud", "admin@contoso.example", secret: "abcdefghij1234567890", domain: "login.contoso.example"),
            account("Fabrikam Mail", "you@fabrikam.example", secret: "qrstuvwxyz0987654321"),
            account("Acme Bank", "personal", secret: "0987654321zyxwvutsrq"),
            account("Tailspin Dev", "deploy-bot", secret: "mnopqrstuv5647382910")
        ]
    }

    /// Deterministic accounts for UI tests (RFC 6238 test secret; no real credentials).
    static var uiTestSeed: [OtpModel] {
        let rfcSecret = Data("12345678901234567890".utf8)
        return [
            OtpModel(issuer: "Example Corp", name: "user@example.com", prefix: "1234",
                     entry: .totp(key: rfcSecret, digits: 6, interval: 30), associatedDomains: ["sso.example.com"]),
            OtpModel(issuer: "GitHub", name: "octocat", entry: .totp(key: rfcSecret, digits: 6, interval: 30)),
            OtpModel(issuer: "Counter Bank", name: "hotp", entry: .hotp(key: rfcSecret, digits: 6, counter: 0))
        ]
    }
}

// MARK: - Error Types

/// Fixed keys, for tests and UI-test mode.
struct FixedKeys: KeyProviding {
    let primaryKey: SymmetricKey?
    let allKeys: [SymmetricKey]

    init(primaryKey: SymmetricKey?, allKeys: [SymmetricKey]? = nil) {
        self.primaryKey = primaryKey
        self.allKeys = allKeys ?? [primaryKey].compactMap { $0 }
    }
}

public enum SharedDataError: LocalizedError, Identifiable {
    case loadFailed(Error)
    case saveFailed(Error)
    case accountNotFound
    case keyUnavailable
    case someAccountsUnreadable(Int)
    case encryptionFailed
    case decryptionFailed
    case unknown(Error)

    public var id: String {
        switch self {
        case .loadFailed: "loadFailed"
        case .saveFailed: "saveFailed"
        case .accountNotFound: "accountNotFound"
        case .keyUnavailable: "keyUnavailable"
        case .someAccountsUnreadable: "someAccountsUnreadable"
        case .encryptionFailed: "encryptionFailed"
        case .decryptionFailed: "decryptionFailed"
        case .unknown: "unknown"
        }
    }

    public var errorDescription: String? {
        switch self {
        case .loadFailed(let error):
            String(localized: "Failed to load accounts: \(error.localizedDescription)")
        case .saveFailed(let error):
            String(localized: "Failed to save accounts: \(error.localizedDescription)")
        case .accountNotFound:
            String(localized: "The account no longer exists.")
        case .keyUnavailable:
            String(localized: "Your encryption key isn't available yet. Unlock this device and try again — your accounts are safe.")
        case .someAccountsUnreadable(let count):
            String(localized: "\(count) account(s) couldn't be decrypted on this device. They're kept untouched; signing in to the same iCloud account should restore access.")
        case .encryptionFailed:
            String(localized: "Failed to encrypt account data")
        case .decryptionFailed:
            String(localized: "Failed to decrypt account data")
        case .unknown(let error):
            String(localized: "An unknown error occurred: \(error.localizedDescription)")
        }
    }
}
