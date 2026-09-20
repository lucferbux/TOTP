//
//  CloudKitDataManager.swift
//  TOTP
//
//  CloudKit sync for TOTP accounts.
//
//  Records live in a dedicated record zone and are read with zone change tokens rather than
//  queries. Queries need QUERYABLE indexes that an auto-created schema doesn't have (the old
//  code failed with "Field 'recordName' is not marked queryable" on every read, so nothing ever
//  came back from iCloud). Change tokens need no indexes, fetch only what changed, and — unlike
//  queries — tell us what was deleted on other devices.
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

    /// Dedicated zone: the default zone doesn't support change tokens.
    static let zoneName = "TOTPAccounts"
    private let zoneID = CKRecordZone.ID(zoneName: CloudKitDataManager.zoneName, ownerName: CKCurrentUserDefaultName)

    @Published public var accounts: [CloudKitOtpModel] = []
    @Published public var isLoading = false
    @Published public var error: CloudKitError?
    @Published public var accountStatus: CKAccountStatus = .couldNotDetermine

    /// Accounts deleted on another device since the last fetch.
    @Published public var deletedAccountIDs: Set<String> = []

    // Sync status
    @Published public var lastSyncDate: Date?
    @Published public var syncInProgress = false

    // Subscription tracking
    private let subscriptionID = "TOTPZoneChanges"
    private var hasRegisteredSubscription = false
    private var hasEnsuredZone = false

    private let changeTokenKey = "cloudkit_zone_change_token"

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
            logger.info("iCloud account status: \(status.rawValue, privacy: .public)")
            if status != .available {
                self.error = CloudKitError.accountNotAvailable
            } else {
                self.error = nil
            }
        } catch {
            logger.error("Account status failed: \(error.localizedDescription, privacy: .public)")
            self.error = CloudKitError.unknown(error)
        }
    }

    // MARK: - Zone & Subscription

    /// Creates the record zone if it doesn't exist yet (idempotent, cheap after the first call).
    private func ensureZone() async throws {
        guard !hasEnsuredZone else { return }
        _ = try await privateDatabase.modifyRecordZones(saving: [CKRecordZone(zoneID: zoneID)], deleting: [])
        hasEnsuredZone = true
    }

    /// Subscribes to zone changes so other devices' edits arrive as silent pushes.
    @MainActor
    public func registerForRemoteNotifications() async {
        guard !hasRegisteredSubscription, accountStatus == .available else { return }
        do {
            try await ensureZone()
            let existing = try await privateDatabase.allSubscriptions()
            if existing.contains(where: { $0.subscriptionID == subscriptionID }) {
                hasRegisteredSubscription = true
                return
            }
            let subscription = CKRecordZoneSubscription(zoneID: zoneID, subscriptionID: subscriptionID)
            let info = CKSubscription.NotificationInfo()
            info.shouldSendContentAvailable = true
            subscription.notificationInfo = info

            _ = try await privateDatabase.modifySubscriptions(saving: [subscription], deleting: [])
            hasRegisteredSubscription = true
            logger.info("Subscribed to zone changes")
        } catch {
            logger.error("Failed to register subscription: \(error.localizedDescription, privacy: .public)")
        }
    }

    @MainActor
    public func handleRemoteNotification(userInfo: [AnyHashable: Any]) async -> Bool {
        guard let info = userInfo as? [String: NSObject],
              CKNotification(fromRemoteNotificationDictionary: info) != nil else {
            return false
        }
        logger.info("Received CloudKit push; fetching changes")
        await loadAccounts()
        return true
    }

    // MARK: - Change token

    private var changeToken: CKServerChangeToken? {
        get {
            guard let data = AppGroup.defaults.data(forKey: changeTokenKey) else { return nil }
            return try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: data)
        }
        set {
            guard let newValue, let data = try? NSKeyedArchiver.archivedData(withRootObject: newValue, requiringSecureCoding: true) else {
                AppGroup.defaults.removeObject(forKey: changeTokenKey)
                return
            }
            AppGroup.defaults.set(data, forKey: changeTokenKey)
        }
    }

    // MARK: - Data Operations

    /// Pulls everything that changed in the zone since the last fetch.
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
            try await ensureZone()
            // A saved token only describes what changed since last time. After a relaunch the
            // in-memory mirror is empty, so fetch the whole zone to rebuild it — otherwise the
            // app would think iCloud is empty and re-upload everything.
            try await fetchChanges(since: accounts.isEmpty ? nil : changeToken)
            self.lastSyncDate = Date()
            self.error = nil
        } catch let error as CKError where error.code == .changeTokenExpired {
            logger.notice("Change token expired; refetching the whole zone")
            changeToken = nil
            accounts = []
            do {
                try await fetchChanges(since: nil)
                self.lastSyncDate = Date()
                self.error = nil
            } catch {
                handle(error)
            }
        } catch let error as CKError where error.code == .zoneNotFound || error.code == .userDeletedZone {
            logger.notice("Zone missing; it will be recreated and local accounts re-uploaded")
            changeToken = nil
            hasEnsuredZone = false
            accounts = []
            self.error = nil
        } catch {
            handle(error)
        }
    }

    @MainActor
    private func fetchChanges(since token: CKServerChangeToken?) async throws {
        var token = token
        var more = true
        var changed: [CKRecord] = []
        var deleted: [CKRecord.ID] = []

        while more {
            let result = try await privateDatabase.recordZoneChanges(inZoneWith: zoneID, since: token)
            for (_, recordResult) in result.modificationResultsByID {
                switch recordResult {
                case .success(let modification):
                    changed.append(modification.record)
                case .failure(let error):
                    logger.error("Change fetch failed for a record: \(error.localizedDescription, privacy: .public)")
                }
            }
            deleted.append(contentsOf: result.deletions.map(\.recordID))
            token = result.changeToken
            more = result.moreComing
        }

        for record in changed {
            guard let model = CloudKitOtpModel(from: record) else { continue }
            if let index = accounts.firstIndex(where: { $0.id == model.id }) {
                accounts[index] = model
            } else {
                accounts.append(model)
            }
        }

        let deletedNames = Set(deleted.map(\.recordName))
        if !deletedNames.isEmpty {
            accounts.removeAll { deletedNames.contains($0.id) }
            deletedAccountIDs.formUnion(deletedNames)
        }

        accounts.sort { $0.createdDate < $1.createdDate }
        changeToken = token
        logger.info("Fetched \(changed.count, privacy: .public) change(s), \(deletedNames.count, privacy: .public) deletion(s); \(self.accounts.count, privacy: .public) record(s) in iCloud")
    }

    /// Moves records written by 3.x into the zone (they were saved in the default zone, where
    /// they can't be fetched incrementally). Records are looked up by ID, so no index is needed.
    @MainActor
    public func migrateDefaultZoneRecords(ids: [String]) async {
        guard accountStatus == .available, !ids.isEmpty else { return }
        let migratedKey = "cloudkit_default_zone_migrated"
        guard !AppGroup.defaults.bool(forKey: migratedKey) else { return }

        do {
            try await ensureZone()
            var migrated = 0
            for id in ids {
                let legacyID = CKRecord.ID(recordName: id)
                guard let legacy = try? await privateDatabase.record(for: legacyID) else { continue }
                let copy = CKRecord(recordType: CloudKitOtpModel.recordType,
                                    recordID: CKRecord.ID(recordName: id, zoneID: zoneID))
                for key in legacy.allKeys() {
                    copy[key] = legacy[key]
                }
                _ = try await privateDatabase.save(copy)
                try? await privateDatabase.deleteRecord(withID: legacyID)
                migrated += 1
            }
            AppGroup.defaults.set(true, forKey: migratedKey)
            if migrated > 0 {
                logger.info("Migrated \(migrated, privacy: .public) record(s) out of the default zone")
                changeToken = nil
                await loadAccounts()
            }
        } catch {
            logger.error("Default-zone migration failed: \(error.localizedDescription, privacy: .public)")
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
            try await ensureZone()
            account.modifiedDate = Date()
            let record = account.toCKRecord(in: zoneID)

            let savedRecord = try await privateDatabase.save(record)
            account.record = savedRecord
            logger.info("Saved a record to iCloud")

            if let index = accounts.firstIndex(where: { $0.id == account.id }) {
                accounts[index] = account
            } else {
                accounts.append(account)
            }

            self.lastSyncDate = Date()
            self.error = nil

        } catch let error as CKError {
            if error.code == .serverRecordChanged && retryOnConflict {
                // Last-write-wins: take the server record and overwrite it
                if let serverRecord = error.userInfo[CKRecordChangedErrorServerRecordKey] as? CKRecord {
                    account.record = serverRecord
                    try await saveAccount(account, retryOnConflict: false)
                    return
                }
            }
            handle(error)
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
            let recordID = account.record?.recordID ?? CKRecord.ID(recordName: account.id, zoneID: zoneID)
            try await privateDatabase.deleteRecord(withID: recordID)
            accounts.removeAll { $0.id == account.id }
            self.lastSyncDate = Date()
            self.error = nil
        } catch let error as CKError {
            if error.code == .unknownItem {
                accounts.removeAll { $0.id == account.id }
                return
            }
            handle(error)
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
        try EncryptionKeyManager.shared.encryptData(data)
    }

    public func decryptData(_ encryptedData: Data) throws -> Data {
        try EncryptionKeyManager.shared.decryptData(encryptedData)
    }

    /// Human-readable environment for the diagnostics UI.
    public var environmentName: String {
        #if DEBUG
        "Development"
        #else
        "Production"
        #endif
    }

    public var containerIdentifier: String {
        container.containerIdentifier ?? "—"
    }

    // MARK: - Error Handling

    @MainActor
    private func handle(_ error: Error) {
        if let ckError = error as? CKError {
            logger.error("CloudKit error \(ckError.errorCode, privacy: .public): \(ckError.localizedDescription, privacy: .public)")
            switch ckError.code {
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
                self.error = CloudKitError.unknown(ckError)
            }
        } else {
            logger.error("CloudKit failure: \(error.localizedDescription, privacy: .public)")
            self.error = CloudKitError.fetchFailed(error)
        }
    }

    // MARK: - Convenience Methods

    /// Decrypted cloud accounts. Records that can't be decrypted with any known key are skipped
    /// instead of failing the whole sync.
    public func getOtpModels() throws -> [OtpModel] {
        accounts.compactMap { record in
            do {
                return try record.toOtpModel()
            } catch {
                logger.error("Skipping a cloud record that could not be decrypted")
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
        if let existingIndex = accounts.firstIndex(where: { $0.id == otpModel.id.uuidString }) {
            let cloudKitModel = accounts[existingIndex]
            try cloudKitModel.apply(otpModel)
            try await saveAccount(cloudKitModel)
        } else {
            try await addOtpModel(otpModel)
        }
    }

    @MainActor
    public func deleteOtpModel(withId id: String) async throws {
        if let account = accounts.first(where: { $0.id == id }) {
            try await deleteAccount(account)
        } else {
            // Not in our cached list (e.g. never fetched): delete by ID anyway
            try? await privateDatabase.deleteRecord(withID: CKRecord.ID(recordName: id, zoneID: zoneID))
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
