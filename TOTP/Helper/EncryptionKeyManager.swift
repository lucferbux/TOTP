//
//  EncryptionKeyManager.swift
//  TOTP
//
//  Unified encryption key management for both local storage and CloudKit sync
//

import Foundation
import CryptoKit

/// Manages encryption keys for TOTP account data
/// Uses a shared file in App Group container for widget compatibility
public final class EncryptionKeyManager {
    public static let shared = EncryptionKeyManager()
    
    private static let keyFileName = ".totp-encryption-key"
    private static let appGroupIdentifier = "group.com.lucferbux.TOTP"
    
    /// The shared encryption key used for all data encryption
    public let encryptionKey: SymmetricKey
    
    private init() {
        self.encryptionKey = Self.getOrCreateEncryptionKey()
    }
    
    // MARK: - Public Encryption Methods
    
    /// Encrypts data using ChaChaPoly
    /// - Parameter data: The data to encrypt
    /// - Returns: The encrypted data (nonce + ciphertext + tag combined)
    /// - Throws: CryptoKit errors if encryption fails
    public func encryptData(_ data: Data) throws -> Data {
        return try ChaChaPoly.seal(data, using: encryptionKey).combined
    }
    
    /// Decrypts data using ChaChaPoly
    /// - Parameter encryptedData: The encrypted data to decrypt
    /// - Returns: The decrypted data
    /// - Throws: CryptoKit errors if decryption fails
    public func decryptData(_ encryptedData: Data) throws -> Data {
        let sealedBox = try ChaChaPoly.SealedBox(combined: encryptedData)
        return try ChaChaPoly.open(sealedBox, using: encryptionKey)
    }
    
    // MARK: - Static Methods for Widget Access
    
    /// Gets the shared encryption key for widget access
    /// - Returns: The encryption key if available, nil otherwise
    public static func getSharedEncryptionKey() -> SymmetricKey? {
        return loadKeyFromSharedFile()
    }
    
    // MARK: - Private Key Management
    
    private static func getSharedContainerURL() -> URL? {
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
    }
    
    private static func getKeyFileURL() -> URL? {
        return getSharedContainerURL()?.appendingPathComponent(keyFileName)
    }
    
    private static func getOrCreateEncryptionKey() -> SymmetricKey {
        // First try to load from shared file (for widget compatibility)
        if let key = loadKeyFromSharedFile() {
            return key
        }
        
        // Try Keychain as fallback (for migration from older versions)
        if let key = loadKeyFromKeychain() {
            // Migrate to shared file for widget access
            saveKeyToSharedFile(key)
            return key
        }
        
        // Generate new key and save to shared file
        let newKey = SymmetricKey(size: .bits256)
        saveKeyToSharedFile(newKey)
        
        return newKey
    }
    
    private static func loadKeyFromSharedFile() -> SymmetricKey? {
        guard let keyFileURL = getKeyFileURL() else { return nil }
        
        do {
            let keyData = try Data(contentsOf: keyFileURL)
            return SymmetricKey(data: keyData)
        } catch {
            return nil
        }
    }
    
    private static func saveKeyToSharedFile(_ key: SymmetricKey) {
        guard let keyFileURL = getKeyFileURL() else { return }
        
        let keyData = key.withUnsafeBytes { Data($0) }
        
        do {
            // Write file without complete protection so widget can access it
            try keyData.write(to: keyFileURL, options: [.atomic])
            #if os(iOS)
            // Set file protection to allow access after first unlock (widget compatible)
            try FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: keyFileURL.path
            )
            #endif
        } catch {
            print("EncryptionKeyManager: Failed to save key to shared file: \(error)")
        }
    }
    
    private static func loadKeyFromKeychain() -> SymmetricKey? {
        // Try both old service names for migration
        let serviceNames = ["TOTP-SharedData-Encryption", "TOTP-CloudKit-Encryption"]
        
        for service in serviceNames {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: "master-key",
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne
            ]
            
            var result: AnyObject?
            let status = SecItemCopyMatching(query as CFDictionary, &result)
            
            if status == errSecSuccess,
               let keyData = result as? Data {
                return SymmetricKey(data: keyData)
            }
        }
        
        return nil
    }
}
