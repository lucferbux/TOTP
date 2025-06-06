//
//  CloudKitDataManager.swift
//  TOTP
//
//  CloudKit data manager for TOTP accounts synchronization
//

import Foundation
import CloudKit
import CryptoKit
import Combine

public class CloudKitDataManager: ObservableObject {
    public static let shared = CloudKitDataManager()
    
    private let container: CKContainer
    private let privateDatabase: CKDatabase
    
    @Published public var accounts: [CloudKitOtpModel] = []
    @Published public var isLoading = false
    @Published public var error: CloudKitError?
    @Published public var accountStatus: CKAccountStatus = .couldNotDetermine
    
    // Encryption key for sensitive data
    private let encryptionKey: SymmetricKey
    
    // Sync status
    @Published public var lastSyncDate: Date?
    @Published public var syncInProgress = false
    
    private init() {
        self.container = CKContainer.default()
        self.privateDatabase = container.privateCloudDatabase
        
        // Generate or retrieve encryption key from Keychain
        self.encryptionKey = Self.getOrCreateEncryptionKey()
        
        Task {
            await checkAccountStatus()
            if accountStatus == .available {
                await loadAccounts()
            }
        }
    }
    
    // MARK: - Account Status
    
    @MainActor
    public func checkAccountStatus() async {
        do {
            let status = try await container.accountStatus()
            self.accountStatus = status
            
            if status != .available {
                self.error = CloudKitError.accountNotAvailable
            }
        } catch {
            self.error = CloudKitError.unknown(error)
        }
    }
    
    // MARK: - Data Operations
    
    @MainActor
    public func loadAccounts() async {
        guard accountStatus == .available else {
            self.error = CloudKitError.accountNotAvailable
            return
        }
        
        isLoading = true
        defer { isLoading = false }
        
        do {
            let query = CKQuery(recordType: CloudKitOtpModel.recordType, predicate: NSPredicate(value: true))
            query.sortDescriptors = [NSSortDescriptor(key: "createdDate", ascending: true)]
            
            let (records, _) = try await privateDatabase.records(matching: query)
            
            var loadedAccounts: [CloudKitOtpModel] = []
            
            for (_, result) in records {
                switch result {
                case .success(let record):
                    if let model = CloudKitOtpModel(from: record) {
                        loadedAccounts.append(model)
                    }
                case .failure(let error):
                    print("Failed to load record: \(error)")
                }
            }
            
            self.accounts = loadedAccounts
            self.lastSyncDate = Date()
            
        } catch {
            self.error = CloudKitError.fetchFailed(error)
        }
    }
    
    @MainActor
    public func saveAccount(_ account: CloudKitOtpModel) async {
        guard accountStatus == .available else {
            self.error = CloudKitError.accountNotAvailable
            return
        }
        
        syncInProgress = true
        defer { syncInProgress = false }
        
        do {
            account.modifiedDate = Date()
            let record = account.toCKRecord()
            
            let savedRecord = try await privateDatabase.save(record)
            account.record = savedRecord
            
            // Update local array
            if let index = accounts.firstIndex(where: { $0.id == account.id }) {
                accounts[index] = account
            } else {
                accounts.append(account)
            }
            
            self.lastSyncDate = Date()
            
        } catch {
            self.error = CloudKitError.saveFailed(error)
        }
    }
    
    @MainActor
    public func deleteAccount(_ account: CloudKitOtpModel) async {
        guard accountStatus == .available else {
            self.error = CloudKitError.accountNotAvailable
            return
        }
        
        syncInProgress = true
        defer { syncInProgress = false }
        
        do {
            if let record = account.record {
                try await privateDatabase.deleteRecord(withID: record.recordID)
            }
            
            // Remove from local array
            accounts.removeAll { $0.id == account.id }
            self.lastSyncDate = Date()
            
        } catch {
            self.error = CloudKitError.deleteFailed(error)
        }
    }
    
    @MainActor
    public func syncAccounts() async {
        await loadAccounts()
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
        let service = "TOTP-CloudKit-Encryption"
        let account = "master-key"
        
        // Try to load existing key from Keychain
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
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
        
        // Save to Keychain
        let saveQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: keyData,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        
        SecItemAdd(saveQuery as CFDictionary, nil)
        
        return newKey
    }
    
    // MARK: - Convenience Methods
    
    public func getOtpModels() throws -> [OtpModel] {
        return try accounts.compactMap { try $0.toOtpModel() }
    }
    
    @MainActor
    public func addOtpModel(_ otpModel: OtpModel) async throws {
        let cloudKitModel = try CloudKitOtpModel.from(otpModel: otpModel)
        await saveAccount(cloudKitModel)
    }
    
    @MainActor
    public func deleteOtpModel(withId id: String) async {
        if let account = accounts.first(where: { $0.id == id }) {
            await deleteAccount(account)
        }
    }
}

// MARK: - Error Types

public enum CloudKitError: LocalizedError, Identifiable {
    case accountNotAvailable
    case fetchFailed(Error)
    case saveFailed(Error)
    case deleteFailed(Error)
    case encryptionFailed
    case decryptionFailed
    case unknown(Error)
    
    public var id: String {
        switch self {
        case .accountNotAvailable: return "accountNotAvailable"
        case .fetchFailed: return "fetchFailed"
        case .saveFailed: return "saveFailed"
        case .deleteFailed: return "deleteFailed"
        case .encryptionFailed: return "encryptionFailed"
        case .decryptionFailed: return "decryptionFailed"
        case .unknown: return "unknown"
        }
    }
    
    public var errorDescription: String? {
        switch self {
        case .accountNotAvailable:
            return "iCloud account is not available. Please sign in to iCloud in Settings."
        case .fetchFailed(let error):
            return "Failed to fetch accounts from iCloud: \(error.localizedDescription)"
        case .saveFailed(let error):
            return "Failed to save account to iCloud: \(error.localizedDescription)"
        case .deleteFailed(let error):
            return "Failed to delete account from iCloud: \(error.localizedDescription)"
        case .encryptionFailed:
            return "Failed to encrypt account data"
        case .decryptionFailed:
            return "Failed to decrypt account data"
        case .unknown(let error):
            return "An unknown error occurred: \(error.localizedDescription)"
        }
    }
}
