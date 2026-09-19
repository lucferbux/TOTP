//
//  EncryptionKeyManager.swift
//  Shared (app, widget, AutoFill)
//
//  Single owner of the symmetric key that seals OTP secrets at rest (local store and CloudKit).
//

import Foundation
import CryptoKit
import os

public final class EncryptionKeyManager: @unchecked Sendable {
    public static let shared = EncryptionKeyManager()

    private static let keyFileName = ".totp-encryption-key"
    private static let keychainServices = ["TOTP-SharedData-Encryption", "TOTP-CloudKit-Encryption"]
    private static let logger = Logger(subsystem: "com.lucferbux.TOTP", category: "Encryption")

    /// The shared encryption key used for all data encryption
    public let encryptionKey: SymmetricKey

    private init() {
        self.encryptionKey = Self.getOrCreateEncryptionKey()
    }

    // MARK: - Encryption

    public func encryptData(_ data: Data) throws -> Data {
        try AccountCrypto.seal(data, using: encryptionKey)
    }

    public func decryptData(_ encryptedData: Data) throws -> Data {
        try AccountCrypto.open(encryptedData, using: encryptionKey)
    }

    // MARK: - Read-only access (extensions)

    /// Loads the key without creating one. Extensions must never mint a new key.
    public static func existingKey() -> SymmetricKey? {
        loadKeyFromSharedFile()
    }

    // MARK: - Key management

    private static var keyFileURL: URL? {
        AppGroup.containerURL?.appendingPathComponent(keyFileName)
    }

    private static func getOrCreateEncryptionKey() -> SymmetricKey {
        if let key = loadKeyFromSharedFile() {
            return key
        }
        // Migration from versions that stored the key in the Keychain
        if let key = loadKeyFromKeychain() {
            saveKeyToSharedFile(key)
            return key
        }
        let newKey = SymmetricKey(size: .bits256)
        saveKeyToSharedFile(newKey)
        return newKey
    }

    private static func loadKeyFromSharedFile() -> SymmetricKey? {
        guard let url = keyFileURL, let data = try? Data(contentsOf: url), data.count == 32 else { return nil }
        return SymmetricKey(data: data)
    }

    private static func saveKeyToSharedFile(_ key: SymmetricKey) {
        guard let url = keyFileURL else { return }
        let keyData = key.withUnsafeBytes { Data($0) }
        do {
            try keyData.write(to: url, options: [.atomic])
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

    private static func loadKeyFromKeychain() -> SymmetricKey? {
        for service in keychainServices {
            for accessGroup in [nil, AppGroup.identifier] as [String?] {
                var query: [String: Any] = [
                    kSecClass as String: kSecClassGenericPassword,
                    kSecAttrService as String: service,
                    kSecAttrAccount as String: "master-key",
                    kSecReturnData as String: true,
                    kSecMatchLimit as String: kSecMatchLimitOne
                ]
                if let accessGroup { query[kSecAttrAccessGroup as String] = accessGroup }
                var result: AnyObject?
                if SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data {
                    return SymmetricKey(data: data)
                }
            }
        }
        return nil
    }
}
