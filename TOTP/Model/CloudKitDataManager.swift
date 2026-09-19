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
import os

private let logger = Logger(subsystem: "com.lucferbux.TOTP", category: "CloudKit")

public class CloudKitDataManager: ObservableObject {
    public static let shared = CloudKitDataManager()
    
    private let container: CKContainer
    private let privateDatabase: CKDatabase
    
    @Published public var accounts: [CloudKitOtpModel] = []
    @Published public var isLoading = false
    @Published public var error: CloudKitError?
    @Published public var accountStatus: CKAccountStatus = .couldNotDetermine
    
    // Sync status
    @Published public var lastSyncDate: Date?
    @Published public var syncInProgress = false
    
    // Subscription tracking
    private let subscriptionID = "TOTPAccountChanges"
    private var hasRegisteredSubscription = false
    
    private init() {
        self.container = CKContainer.default()
        self.privateDatabase = container.privateCloudDatabase
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
    
    // MARK: - Subscription Management
    
    /// Registers a CloudKit subscription to receive push notifications when records change
    @MainActor
    public func registerForRemoteNotifications() async {
        guard accountStatus == .available else { return }
        guard !hasRegisteredSubscription else { return }
        
        do {
            // First check if subscription already exists
            let existingSubscriptions = try await privateDatabase.allSubscriptions()
            let subscriptionExists = existingSubscriptions.contains { $0.subscriptionID == subscriptionID }
            
            if !subscriptionExists {
                // Create a database subscription for all record changes
                let subscription = CKDatabaseSubscription(subscriptionID: subscriptionID)
                
                let notificationInfo = CKSubscription.NotificationInfo()
                notificationInfo.shouldSendContentAvailable = true // Silent push
                subscription.notificationInfo = notificationInfo
                
                try await privateDatabase.save(subscription)
                logger.info("Registered for remote notifications")
            }
            
            hasRegisteredSubscription = true
        } catch {
            logger.error("Failed to register subscription: \(error.localizedDescription, privacy: .public)")
        }
    }
    
    /// Handles a remote notification from CloudKit
    /// Returns true if the notification was handled
    @MainActor
    public func handleRemoteNotification(userInfo: [AnyHashable: Any]) async -> Bool {
        guard let notification = CKNotification(fromRemoteNotificationDictionary: userInfo as! [String: NSObject]) else {
            return false
        }
        
        if notification.subscriptionID == subscriptionID {
            logger.info("Received remote notification, fetching changes")
            await loadAccounts()
            return true
        }
        
        return false
    }
    
    // MARK: - Data Operations
    
    @MainActor
    public func loadAccounts() async {
        guard accountStatus == .available else {
            self.error = CloudKitError.accountNotAvailable
            return
        }
        
        isLoading = true
        syncInProgress = true
        defer { 
            isLoading = false
            syncInProgress = false
        }
        
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
                    logger.error("Failed to load record: \(error.localizedDescription, privacy: .public)")
                }
            }
            
            self.accounts = loadedAccounts
            self.lastSyncDate = Date()
            self.error = nil
            
        } catch let error as CKError {
            handleCloudKitError(error)
        } catch {
            self.error = CloudKitError.fetchFailed(error)
        }
    }
    
    @MainActor
    public func saveAccount(_ account: CloudKitOtpModel) async throws {
        try await saveAccount(account, retryOnConflict: true)
    }
    
    @MainActor
    private func saveAccount(_ account: CloudKitOtpModel, retryOnConflict: Bool) async throws {
        guard accountStatus == .available else {
            throw CloudKitError.accountNotAvailable
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
            self.error = nil
            
        } catch let error as CKError {
            // Handle server record changed conflict
            if error.code == .serverRecordChanged && retryOnConflict {
                // Last-write-wins: force overwrite
                if let serverRecord = error.userInfo[CKRecordChangedErrorServerRecordKey] as? CKRecord {
                    account.record = serverRecord
                    try await saveAccount(account, retryOnConflict: false)
                    return
                }
            }
            handleCloudKitError(error)
            throw CloudKitError.saveFailed(error)
        } catch {
            self.error = CloudKitError.saveFailed(error)
            throw CloudKitError.saveFailed(error)
        }
    }
    
    @MainActor
    public func deleteAccount(_ account: CloudKitOtpModel) async throws {
        guard accountStatus == .available else {
            throw CloudKitError.accountNotAvailable
        }
        
        syncInProgress = true
        defer { syncInProgress = false }
        
        do {
            let recordID = account.record?.recordID ?? CKRecord.ID(recordName: account.id)
            try await privateDatabase.deleteRecord(withID: recordID)
            
            // Remove from local array
            accounts.removeAll { $0.id == account.id }
            self.lastSyncDate = Date()
            self.error = nil
            
        } catch let error as CKError {
            // If record doesn't exist, still remove locally
            if error.code == .unknownItem {
                accounts.removeAll { $0.id == account.id }
                return
            }
            handleCloudKitError(error)
            throw CloudKitError.deleteFailed(error)
        } catch {
            self.error = CloudKitError.deleteFailed(error)
            throw CloudKitError.deleteFailed(error)
        }
    }
    
    @MainActor
    public func syncAccounts() async {
        await loadAccounts()
    }
    
    // MARK: - Encryption (using shared EncryptionKeyManager)
    
    public func encryptData(_ data: Data) throws -> Data {
        return try EncryptionKeyManager.shared.encryptData(data)
    }
    
    public func decryptData(_ encryptedData: Data) throws -> Data {
        return try EncryptionKeyManager.shared.decryptData(encryptedData)
    }
    
    // MARK: - Error Handling
    
    private func handleCloudKitError(_ error: CKError) {
        switch error.code {
        case .networkUnavailable, .networkFailure:
            self.error = CloudKitError.networkError
        case .notAuthenticated:
            self.accountStatus = .noAccount
            self.error = CloudKitError.accountNotAvailable
        case .quotaExceeded:
            self.error = CloudKitError.quotaExceeded
        case .serverResponseLost:
            self.error = CloudKitError.serverError
        default:
            self.error = CloudKitError.unknown(error)
        }
    }
    
    // MARK: - Convenience Methods
    
    /// Decrypted cloud accounts. Records that can't be decrypted with this device's key are skipped
    /// instead of failing the whole sync.
    public func getOtpModels() throws -> [OtpModel] {
        accounts.compactMap { record in
            do {
                return try record.toOtpModel()
            } catch {
                logger.error("Skipping cloud record that could not be decrypted")
                return nil
            }
        }
    }
    
    @MainActor
    public func addOtpModel(_ otpModel: OtpModel) async throws {
        let cloudKitModel = try CloudKitOtpModel.from(otpModel: otpModel)
        try await saveAccount(cloudKitModel)
    }
    
    @MainActor
    public func updateOtpModel(_ otpModel: OtpModel) async throws {
        // Find existing account or create new
        if let existingIndex = accounts.firstIndex(where: { $0.id == otpModel.id.uuidString }) {
            let cloudKitModel = accounts[existingIndex]
            try cloudKitModel.apply(otpModel)
            
            try await saveAccount(cloudKitModel)
        } else {
            // Create new
            try await addOtpModel(otpModel)
        }
    }
    
    @MainActor
    public func deleteOtpModel(withId id: String) async throws {
        if let account = accounts.first(where: { $0.id == id }) {
            try await deleteAccount(account)
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
    case networkError
    case quotaExceeded
    case serverError
    case unknown(Error)
    
    public var id: String {
        switch self {
        case .accountNotAvailable: return "accountNotAvailable"
        case .fetchFailed: return "fetchFailed"
        case .saveFailed: return "saveFailed"
        case .deleteFailed: return "deleteFailed"
        case .encryptionFailed: return "encryptionFailed"
        case .decryptionFailed: return "decryptionFailed"
        case .networkError: return "networkError"
        case .quotaExceeded: return "quotaExceeded"
        case .serverError: return "serverError"
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
        case .networkError:
            return "Network connection unavailable. Changes will sync when connected."
        case .quotaExceeded:
            return "iCloud storage quota exceeded. Please free up space."
        case .serverError:
            return "iCloud server error. Please try again later."
        case .unknown(let error):
            return "An unknown error occurred: \(error.localizedDescription)"
        }
    }
    
    public var isTransient: Bool {
        switch self {
        case .networkError, .serverError:
            return true
        default:
            return false
        }
    }
}
