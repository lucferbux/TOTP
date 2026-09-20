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
    public static let isUITesting = ProcessInfo.processInfo.arguments.contains("-UITestMode")
}

public final class SharedDataManager: ObservableObject, @unchecked Sendable {
    public static let shared = SharedDataManager()

    private static let logger = Logger(subsystem: "com.lucferbux.TOTP", category: "Storage")

    private let userDefaults: UserDefaults
    /// Key used to seal data we write.
    private let encryptionKey: SymmetricKey
    /// Every key that may have sealed existing data (shared, local, legacy).
    private let decryptionKeys: [SymmetricKey]

    @Published public var accounts: [OtpModel] = []
    @Published public var isLoading = false
    @Published public var error: SharedDataError?

    private init() {
        if AppEnvironment.isUITesting {
            let suite = "com.lucferbux.TOTP.uitests"
            let defaults = UserDefaults(suiteName: suite) ?? .standard
            defaults.removePersistentDomain(forName: suite)
            self.userDefaults = defaults
            let testKey = SymmetricKey(size: .bits256)
            self.encryptionKey = testKey
            self.decryptionKeys = [testKey]
            self.accounts = Self.uiTestSeed
            persist()
        } else {
            self.userDefaults = AppGroup.defaults
            self.encryptionKey = EncryptionKeyManager.shared.encryptionKey
            self.decryptionKeys = EncryptionKeyManager.shared.decryptionKeys
            loadAccounts()
            // Re-seal anything that was encrypted with an older key so every device converges
            // on the shared key.
            if !accounts.isEmpty && storedUsesLegacyKey {
                persist()
            }
        }
    }

    /// Designated initialiser for unit tests.
    init(userDefaults: UserDefaults, encryptionKey: SymmetricKey, decryptionKeys: [SymmetricKey]? = nil) {
        self.userDefaults = userDefaults
        self.encryptionKey = encryptionKey
        self.decryptionKeys = decryptionKeys ?? [encryptionKey]
        loadAccounts()
    }

    /// True when any stored record can't be opened with the primary key (so it needs re-sealing).
    var storedUsesLegacyKey: Bool {
        AccountStore.storedRecords(in: userDefaults).contains { record in
            (try? AccountCrypto.open(record.encryptedKey, using: encryptionKey)) == nil
        }
    }

    // MARK: - Data Operations

    public func loadAccounts() {
        isLoading = true
        defer { isLoading = false }

        guard let data = userDefaults.data(forKey: AccountStore.accountsKey) else {
            accounts = []
            return
        }
        do {
            accounts = try AccountStore.decode(data, keys: decryptionKeys)
        } catch {
            Self.logger.error("Failed to load accounts: \(error.localizedDescription, privacy: .public)")
            self.error = .loadFailed(error)
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
        try AccountCrypto.seal(data, using: encryptionKey)
    }

    public func decryptData(_ encryptedData: Data) throws -> Data {
        try AccountCrypto.open(encryptedData, using: encryptionKey)
    }

    public static func getSharedEncryptionKey() -> SymmetricKey? {
        EncryptionKeyManager.existingKey()
    }

    // MARK: - Private

    @discardableResult
    private func persist() -> Bool {
        do {
            let previous = AccountStore.storedRecords(in: userDefaults)
            let data = try AccountStore.encode(accounts, key: encryptionKey, previous: previous)
            userDefaults.set(data, forKey: AccountStore.accountsKey)
            error = nil
            return true
        } catch {
            Self.logger.error("Failed to save accounts: \(error.localizedDescription, privacy: .public)")
            self.error = .saveFailed(error)
            return false
        }
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

public enum SharedDataError: LocalizedError, Identifiable {
    case loadFailed(Error)
    case saveFailed(Error)
    case accountNotFound
    case encryptionFailed
    case decryptionFailed
    case unknown(Error)

    public var id: String {
        switch self {
        case .loadFailed: "loadFailed"
        case .saveFailed: "saveFailed"
        case .accountNotFound: "accountNotFound"
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
        case .encryptionFailed:
            String(localized: "Failed to encrypt account data")
        case .decryptionFailed:
            String(localized: "Failed to decrypt account data")
        case .unknown(let error):
            String(localized: "An unknown error occurred: \(error.localizedDescription)")
        }
    }
}
