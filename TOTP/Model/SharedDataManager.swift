//
//  SharedDataManager.swift
//  TOTP
//
//  Shared data manager for TOTP accounts using App Groups
//

import Foundation
import Combine
import CryptoKit

public class SharedDataManager: ObservableObject {
    public static let shared = SharedDataManager()
    
    private let suiteName = "group.com.lucferbux.TOTP"
    private let userDefaults: UserDefaults
    private let accountsKey = "stored_totp_accounts"
    
    @Published public var accounts: [OtpModel] = []
    @Published public var isLoading = false
    @Published public var error: SharedDataError?
    
    // Encryption key for sensitive data
    private let encryptionKey: SymmetricKey
    
    private init() {
        // Use App Group UserDefaults for widget sharing
        self.userDefaults = UserDefaults(suiteName: suiteName) ?? UserDefaults.standard
        
        // Generate or retrieve encryption key from shared file
        self.encryptionKey = Self.getOrCreateEncryptionKey()
        
        loadAccounts()
    }
    
    // MARK: - Data Operations
    
    public func loadAccounts() {
        isLoading = true
        defer { isLoading = false }
        
        do {
            guard let data = userDefaults.data(forKey: accountsKey) else {
                self.accounts = []
                return
            }
            
            let decoder = JSONDecoder()
            let storedAccounts = try decoder.decode([StoredOtpAccount].self, from: data)
            
            var loadedAccounts: [OtpModel] = []
            
            for storedAccount in storedAccounts {
                do {
                    let decryptedKey = try decryptData(storedAccount.encryptedKey)
                    
                    let entry: OtpEntry
                    if storedAccount.isHotp {
                        entry = .hotp(key: decryptedKey, digits: storedAccount.digits, counter: UInt64(max(0, storedAccount.counter)))
                    } else {
                        entry = .totp(key: decryptedKey, digits: storedAccount.digits, interval: storedAccount.interval)
                    }
                    
                    let otpModel = OtpModel(
                        issuer: storedAccount.issuer,
                        name: storedAccount.name,
                        prefix: storedAccount.prefix,
                        entry: entry
                    )
                    
                    loadedAccounts.append(otpModel)
                } catch {
                    print("Failed to decrypt account: \(error)")
                    // Skip corrupted accounts
                }
            }
            
            DispatchQueue.main.async {
                self.accounts = loadedAccounts
            }
            
        } catch {
            DispatchQueue.main.async {
                self.error = .loadFailed(error)
            }
        }
    }
    
    public func saveAccounts() {
        do {
            var storedAccounts: [StoredOtpAccount] = []
            
            for account in accounts {
                var key: Data
                var isHotp: Bool
                var digits: Int
                var interval: Double = 30.0
                var counter: Int64 = 0
                
                switch account.entry {
                case let .hotp(k, d, c):
                    key = k
                    isHotp = true
                    digits = d
                    counter = Int64(c)
                case let .totp(k, d, i):
                    key = k
                    isHotp = false
                    digits = d
                    interval = i
                }
                
                let encryptedKey = try encryptData(key)
                
                let storedAccount = StoredOtpAccount(
                    id: account.id.uuidString,
                    issuer: account.issuer,
                    name: account.name,
                    prefix: account.prefix,
                    encryptedKey: encryptedKey,
                    isHotp: isHotp,
                    digits: digits,
                    interval: interval,
                    counter: counter,
                    createdDate: Date(),
                    modifiedDate: Date()
                )
                
                storedAccounts.append(storedAccount)
            }
            
            let encoder = JSONEncoder()
            let data = try encoder.encode(storedAccounts)
            userDefaults.set(data, forKey: accountsKey)
            userDefaults.synchronize()
            
        } catch {
            DispatchQueue.main.async {
                self.error = .saveFailed(error)
            }
        }
    }
    
    public func addAccount(_ account: OtpModel) {
        DispatchQueue.main.async {
            self.accounts.append(account)
            self.saveAccounts()
        }
    }
    
    public func saveAccount(_ account: OtpModel) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.main.async {
                self.accounts.append(account)
                self.saveAccounts()
                
                // Check if save was successful by monitoring error state
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    if let error = self.error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            }
        }
    }
    
    public func deleteAccount(_ account: OtpModel) {
        DispatchQueue.main.async {
            self.accounts.removeAll { $0.id == account.id }
            self.saveAccounts()
        }
    }
    
    public func deleteAccount(withId id: UUID) {
        DispatchQueue.main.async {
            self.accounts.removeAll { $0.id == id }
            self.saveAccounts()
        }
    }
    
    // MARK: - Encryption
    
    public func encryptData(_ data: Data) throws -> Data {
        return try ChaChaPoly.seal(data, using: encryptionKey).combined
    }
    
    public func decryptData(_ encryptedData: Data) throws -> Data {
        let sealedBox = try ChaChaPoly.SealedBox(combined: encryptedData)
        return try ChaChaPoly.open(sealedBox, using: encryptionKey)
    }
    
    // MARK: - Shared File-based Key Management
    
    private static let keyFileName = ".totp-encryption-key"
    
    private static func getSharedContainerURL() -> URL? {
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.lucferbux.TOTP")
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
            // Set file protection to allow access after first unlock (widget compatible)
            try FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: keyFileURL.path
            )
        } catch {
            // Silently fail - encryption will still work, just won't persist
        }
    }
    
    private static func loadKeyFromKeychain() -> SymmetricKey? {
        let service = "TOTP-SharedData-Encryption"
        let account = "master-key"
        
        // Try to load existing key from Keychain (without access group first)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        var status = SecItemCopyMatching(query as CFDictionary, &result)
        
        if status == errSecSuccess,
           let keyData = result as? Data {
            return SymmetricKey(data: keyData)
        }
        
        // Try with access group (for keys created with older versions)
        let queryWithGroup: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessGroup as String: "group.com.lucferbux.TOTP",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        status = SecItemCopyMatching(queryWithGroup as CFDictionary, &result)
        
        if status == errSecSuccess,
           let keyData = result as? Data {
            return SymmetricKey(data: keyData)
        }
        
        return nil
    }
    
    // Public method for widget access - uses shared file
    public static func getSharedEncryptionKey() -> SymmetricKey? {
        return loadKeyFromSharedFile()
    }
}

// MARK: - Storage Model

private struct StoredOtpAccount: Codable {
    let id: String
    let issuer: String?
    let name: String?
    let prefix: String?
    let encryptedKey: Data
    let isHotp: Bool
    let digits: Int
    let interval: Double
    let counter: Int64
    let createdDate: Date
    let modifiedDate: Date
}

// MARK: - Error Types

public enum SharedDataError: LocalizedError, Identifiable {
    case loadFailed(Error)
    case saveFailed(Error)
    case encryptionFailed
    case decryptionFailed
    case unknown(Error)
    
    public var id: String {
        switch self {
        case .loadFailed: return "loadFailed"
        case .saveFailed: return "saveFailed"
        case .encryptionFailed: return "encryptionFailed"
        case .decryptionFailed: return "decryptionFailed"
        case .unknown: return "unknown"
        }
    }
    
    public var errorDescription: String? {
        switch self {
        case .loadFailed(let error):
            return "Failed to load accounts: \(error.localizedDescription)"
        case .saveFailed(let error):
            return "Failed to save accounts: \(error.localizedDescription)"
        case .encryptionFailed:
            return "Failed to encrypt account data"
        case .decryptionFailed:
            return "Failed to decrypt account data"
        case .unknown(let error):
            return "An unknown error occurred: \(error.localizedDescription)"
        }
    }
}
