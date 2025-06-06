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
        // Try to use App Group UserDefaults, fall back to standard if not available
        self.userDefaults = UserDefaults(suiteName: suiteName) ?? UserDefaults.standard
        
        // Generate or retrieve encryption key from Keychain
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
    
    // MARK: - Keychain Management
    
    private static func getOrCreateEncryptionKey() -> SymmetricKey {
        let service = "TOTP-SharedData-Encryption"
        let account = "master-key"
        let accessGroup = "group.com.lucferbux.TOTP"
        
        // Try to load existing key from Keychain
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessGroup as String: accessGroup,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        if status == errSecSuccess,
           let keyData = result as? Data {
            return SymmetricKey(data: keyData)
        }
        
        // Generate new key
        let newKey = SymmetricKey(size: .bits256)
        let keyData = newKey.withUnsafeBytes { Data($0) }
        
        // Save to Keychain with App Group access
        let saveQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessGroup as String: accessGroup,
            kSecValueData as String: keyData,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        
        SecItemAdd(saveQuery as CFDictionary, nil)
        
        return newKey
    }
    
    // Public method for widget access
    public static func getSharedEncryptionKey() -> SymmetricKey? {
        let service = "TOTP-SharedData-Encryption"
        let account = "master-key"
        let accessGroup = "group.com.lucferbux.TOTP"
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessGroup as String: accessGroup,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        if status == errSecSuccess,
           let keyData = result as? Data {
            return SymmetricKey(data: keyData)
        }
        
        return nil
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
