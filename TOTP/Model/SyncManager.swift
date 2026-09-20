//
//  SyncManager.swift
//  TOTP
//
//  Unified sync manager that orchestrates local storage and CloudKit synchronization
//

import Foundation
import CloudKit
import Combine
import WidgetKit
import AuthenticationServices
import CoreSpotlight
import os

private let logger = Logger(subsystem: "com.lucferbux.TOTP", category: "Sync")

/// Sync state for UI display
public enum SyncState: Equatable {
    case idle
    case syncing
    case synced(Date)
    case offline
    case error(String)
    case iCloudDisabled
    
    public var description: String {
        switch self {
        case .idle:
            return "Ready"
        case .syncing:
            return "Syncing..."
        case .synced(let date):
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .abbreviated
            return "Synced \(formatter.localizedString(for: date, relativeTo: Date()))"
        case .offline:
            return "Offline"
        case .error(let message):
            return message
        case .iCloudDisabled:
            return "iCloud Disabled"
        }
    }
    
    public var systemImage: String {
        switch self {
        case .idle:
            return "checkmark.icloud"
        case .syncing:
            return "arrow.triangle.2.circlepath.icloud"
        case .synced:
            return "checkmark.icloud.fill"
        case .offline:
            return "icloud.slash"
        case .error:
            return "exclamationmark.icloud"
        case .iCloudDisabled:
            return "icloud.slash"
        }
    }
    
    public var isError: Bool {
        switch self {
        case .error, .iCloudDisabled:
            return true
        default:
            return false
        }
    }
}

/// Manages synchronization between local storage (SharedDataManager) and CloudKit
public class SyncManager: ObservableObject {
    public static let shared = SyncManager()
    
    // Data managers
    private let localManager = SharedDataManager.shared
    private let cloudManager = CloudKitDataManager.shared
    
    // Published state
    @Published public var syncState: SyncState = .idle
    @Published public var accounts: [OtpModel] = []
    @Published public var isLoading = false
    @Published public var error: SyncError?
    
    // iCloud account status
    @Published public var iCloudAvailable = false
    
    // Cancellables for Combine subscriptions
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        setupObservers()
    }
    
    // MARK: - Setup
    
    private func setupObservers() {
        // Observe local account changes
        localManager.$accounts
            .receive(on: DispatchQueue.main)
            .sink { [weak self] accounts in
                self?.accounts = accounts
            }
            .store(in: &cancellables)
        
        // Observe local loading state
        localManager.$isLoading
            .receive(on: DispatchQueue.main)
            .sink { [weak self] loading in
                if loading {
                    self?.isLoading = true
                }
            }
            .store(in: &cancellables)
        
        // Observe CloudKit sync state
        cloudManager.$syncInProgress
            .receive(on: DispatchQueue.main)
            .sink { [weak self] syncing in
                guard let self = self else { return }
                if syncing {
                    self.syncState = .syncing
                }
            }
            .store(in: &cancellables)
        
        // Observe CloudKit last sync date
        cloudManager.$lastSyncDate
            .receive(on: DispatchQueue.main)
            .compactMap { $0 }
            .sink { [weak self] date in
                guard let self = self else { return }
                if !self.cloudManager.syncInProgress {
                    self.syncState = .synced(date)
                }
            }
            .store(in: &cancellables)
        
        // Observe CloudKit errors
        cloudManager.$error
            .receive(on: DispatchQueue.main)
            .compactMap { $0 }
            .sink { [weak self] error in
                guard let self = self else { return }
                if error.isTransient {
                    self.syncState = .offline
                } else {
                    self.syncState = .error(error.localizedDescription)
                }
            }
            .store(in: &cancellables)
        
        // Observe CloudKit account status
        cloudManager.$accountStatus
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                self?.iCloudAvailable = (status == .available)
                if status != .available && status != .couldNotDetermine {
                    self?.syncState = .iCloudDisabled
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Initialization
    
    /// Initializes sync on app launch
    @MainActor
    public func initializeSync() async {
        if AppEnvironment.isUITesting {
            accounts = localManager.accounts
            syncState = .idle
            return
        }
        
        isLoading = true
        syncState = .syncing
        
        // Load local accounts first (fast)
        localManager.loadAccounts()
        accounts = localManager.accounts
        await indexForSpotlight()
        
        // Check iCloud status
        await cloudManager.checkAccountStatus()
        
        if cloudManager.accountStatus == .available {
            iCloudAvailable = true
            
            // Register for remote notifications
            await cloudManager.registerForRemoteNotifications()
            
            // Perform initial sync
            await performSync()
        } else {
            iCloudAvailable = false
            syncState = .iCloudDisabled
        }
        
        isLoading = false
    }
    
    // MARK: - Sync Operations
    
    /// Performs a full sync between local and cloud storage
    @MainActor
    public func performSync() async {
        guard iCloudAvailable else {
            syncState = .iCloudDisabled
            return
        }
        
        syncState = .syncing
        
        do {
            // Load cloud accounts
            await cloudManager.loadAccounts()
            
            // Get both account sets
            let localAccounts = localManager.accounts
            let cloudAccounts = try cloudManager.getOtpModels()
            
            // Merge using last-write-wins strategy
            let mergedAccounts = Self.mergeAccounts(local: localAccounts, cloud: cloudAccounts)
            
            // Update local storage with merged result
            await updateLocalStorage(with: mergedAccounts)
            
            // Upload any local-only accounts to cloud
            await uploadLocalOnlyAccounts(localAccounts: localAccounts, cloudAccounts: cloudAccounts)
            
            await afterMutation()
            
            syncState = .synced(Date())
            
        } catch {
            logger.error("Sync failed: \(error.localizedDescription, privacy: .public)")
            syncState = .error(error.localizedDescription)
        }
    }
    
    /// Merges local and cloud accounts. Accounts are matched by issuer + name and the local copy wins;
    /// cloud-only accounts are added.
    static func mergeAccounts(local: [OtpModel], cloud: [OtpModel]) -> [OtpModel] {
        var merged: [UUID: OtpModel] = [:]
        
        // Add all local accounts
        for account in local {
            merged[account.id] = account
        }
        
        // Merge cloud accounts (cloud wins if it has the same ID - assuming cloud is newer)
        // In a real scenario, you'd compare modifiedDate timestamps
        for cloudAccount in cloud {
            // Cloud accounts come from CloudKitOtpModel which doesn't preserve UUID
            // so we need to match by issuer+name or create new
            if let existingAccount = local.first(where: {
                $0.issuer == cloudAccount.issuer && $0.name == cloudAccount.name
            }) {
                // Keep the existing local account's ID but update data if needed
                merged[existingAccount.id] = existingAccount
            } else {
                // New account from cloud
                merged[cloudAccount.id] = cloudAccount
            }
        }
        
        return Array(merged.values).sorted { 
            ($0.issuer ?? "") < ($1.issuer ?? "") 
        }
    }
    
    /// Updates local storage with merged accounts
    @MainActor
    private func updateLocalStorage(with accounts: [OtpModel]) async {
        // Update local manager's accounts
        for account in accounts {
            if !localManager.accounts.contains(where: { $0.id == account.id }) {
                localManager.addAccount(account)
            }
        }
        
        self.accounts = localManager.accounts
    }
    
    /// Uploads local-only accounts to CloudKit
    @MainActor
    private func uploadLocalOnlyAccounts(localAccounts: [OtpModel], cloudAccounts: [OtpModel]) async {
        for localAccount in localAccounts {
            // Check if this account exists in cloud
            let existsInCloud = cloudAccounts.contains { cloudAccount in
                cloudAccount.issuer == localAccount.issuer && 
                cloudAccount.name == localAccount.name
            }
            
            if !existsInCloud {
                do {
                    try await cloudManager.addOtpModel(localAccount)
                } catch {
                    logger.error("Failed to upload account: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }
    
    // MARK: - Account Operations (synced)
    
    /// Adds a new account and syncs to cloud
    @MainActor
    public func addAccount(_ account: OtpModel) async {
        // Add locally first (fast)
        localManager.addAccount(account)
        accounts = localManager.accounts
        
        // Sync to cloud if available
        if iCloudAvailable {
            do {
                try await cloudManager.addOtpModel(account)
                syncState = .synced(Date())
            } catch {
                logger.error("Failed to sync new account to cloud: \(error.localizedDescription, privacy: .public)")
                // Local save succeeded, so don't fail completely
            }
        }
        
        await afterMutation()
    }
    
    /// Updates an existing account and syncs to cloud
    @MainActor
    public func updateAccount(_ account: OtpModel) async throws {
        // Update locally first
        try await localManager.updateAccount(account)
        accounts = localManager.accounts
        
        // Sync to cloud if available
        if iCloudAvailable {
            do {
                try await cloudManager.updateOtpModel(account)
                syncState = .synced(Date())
            } catch {
                logger.error("Failed to sync account update to cloud: \(error.localizedDescription, privacy: .public)")
            }
        }
        
        await afterMutation()
    }
    
    /// Deletes an account and syncs to cloud
    @MainActor
    public func deleteAccount(_ account: OtpModel) async {
        // Delete locally first
        localManager.deleteAccount(account)
        accounts = localManager.accounts
        
        // Sync to cloud if available
        if iCloudAvailable {
            do {
                try await cloudManager.deleteOtpModel(withId: account.id.uuidString)
                syncState = .synced(Date())
            } catch {
                logger.error("Failed to sync account deletion to cloud: \(error.localizedDescription, privacy: .public)")
            }
        }
        
        await afterMutation()
    }
    
    /// Deletes several accounts at once, syncing each removal to CloudKit.
    @MainActor
    public func deleteAccounts(withIds ids: Set<UUID>) async {
        guard !ids.isEmpty else { return }
        localManager.deleteAccounts(withIds: ids)
        accounts = localManager.accounts

        if iCloudAvailable {
            for id in ids {
                do {
                    try await cloudManager.deleteOtpModel(withId: id.uuidString)
                } catch {
                    logger.error("Failed to sync account deletion to cloud: \(error.localizedDescription, privacy: .public)")
                }
            }
            syncState = .synced(Date())
        }

        await afterMutation()
    }

    /// Persists a new order (drag to reorder).
    @MainActor
    public func moveAccounts(fromOffsets source: IndexSet, toOffset destination: Int) {
        localManager.moveAccounts(fromOffsets: source, toOffset: destination)
        accounts = localManager.accounts
        WidgetCenter.shared.reloadAllTimelines()
    }
    
    /// Returns the value to copy (prefix + code) and, for HOTP, advances and saves the counter
    /// so the same code is never produced twice.
    @MainActor
    public func useCode(for account: OtpModel) async -> String {
        let current = accounts.first { $0.id == account.id } ?? account
        let value = current.autoFillValue()
        if current.entry.isHotp {
            var updated = current
            updated.entry = current.entry.advanced()
            try? await updateAccount(updated)
        }
        return value
    }
    
    /// Keeps widgets, AutoFill and Spotlight consistent after any change.
    @MainActor
    private func afterMutation() async {
        WidgetCenter.shared.reloadAllTimelines()
        await syncCredentialIdentities()
        await indexForSpotlight()
    }
    
    // MARK: - Spotlight
    
    /// Donates account names (never secrets) to Spotlight so "Copy code for …" is searchable.
    @MainActor
    public func indexForSpotlight() async {
        guard !AppEnvironment.isUITesting else { return }
        let entities = accounts.filter { !$0.entry.isHotp }.map(AccountEntity.init(model:))
        do {
            try await CSSearchableIndex.default().deleteAppEntities(ofType: AccountEntity.self)
            try await CSSearchableIndex.default().indexAppEntities(entities)
        } catch {
            logger.error("Spotlight indexing failed: \(error.localizedDescription, privacy: .public)")
        }
    }
    
    // MARK: - Manual Sync
    
    /// Triggers a manual sync (pull-to-refresh)
    @MainActor
    public func refresh() async {
        if iCloudAvailable {
            await performSync()
        } else {
            localManager.loadAccounts()
            accounts = localManager.accounts
        }
    }
    
    // MARK: - Remote Notification Handling
    
    /// Handles a remote notification from CloudKit
    @MainActor
    public func handleRemoteNotification(userInfo: [AnyHashable: Any]) async -> Bool {
        guard iCloudAvailable else { return false }
        
        let handled = await cloudManager.handleRemoteNotification(userInfo: userInfo)
        
        if handled {
            await performSync()
        }
        
        return handled
    }
    
    // MARK: - Credential Identity Sync (AutoFill)
    
    /// Syncs credential identities to ASCredentialIdentityStore for AutoFill
    @MainActor
    public func syncCredentialIdentities() async {
        guard !AppEnvironment.isUITesting else { return }
        let store = ASCredentialIdentityStore.shared
        
        // Check if store is enabled
        let state = await store.state()
        guard state.isEnabled else { return }
        
        // Create identities for all accounts
        var identities: [ASCredentialIdentity] = []
        
        for account in accounts {
            let serviceIdentifier = createServiceIdentifier(for: account)
            let displayName = [account.issuer, account.name]
                .compactMap { $0 }
                .joined(separator: " - ")
            
            // Create OTP identity (iOS 18+)
            let otpIdentity = ASOneTimeCodeCredentialIdentity(
                serviceIdentifier: serviceIdentifier,
                label: displayName,
                recordIdentifier: account.recordIdentifier
            )
            identities.append(otpIdentity)
            
            // If account has prefix, also create password identity
            if let prefix = account.prefix, !prefix.isEmpty {
                let userName = account.name ?? account.issuer ?? "Account"
                let passwordIdentity = ASPasswordCredentialIdentity(
                    serviceIdentifier: serviceIdentifier,
                    user: userName,
                    recordIdentifier: account.recordIdentifier
                )
                identities.append(passwordIdentity)
            }
        }
        
        // Replace all identities in the store
        do {
            try await store.replaceCredentialIdentities(identities)
        } catch {
            logger.error("Failed to sync credential identities: \(error.localizedDescription, privacy: .public)")
        }
    }
    
    /// Creates a service identifier for an account
    static func serviceIdentifier(for account: OtpModel) -> ASCredentialServiceIdentifier {
        if let domains = account.associatedDomains, let firstDomain = domains.first {
            return ASCredentialServiceIdentifier(identifier: firstDomain, type: .domain)
        }
        // Fallback to issuer as a pseudo-domain
        let identifier = account.issuer?.lowercased().replacingOccurrences(of: " ", with: "") ?? "unknown"
        return ASCredentialServiceIdentifier(identifier: identifier, type: .domain)
    }
    
    private func createServiceIdentifier(for account: OtpModel) -> ASCredentialServiceIdentifier {
        Self.serviceIdentifier(for: account)
    }
}

// MARK: - Error Types

public enum SyncError: LocalizedError, Identifiable {
    case localSaveFailed(Error)
    case cloudSyncFailed(Error)
    case mergeConflict
    case unknown(Error)
    
    public var id: String {
        switch self {
        case .localSaveFailed: return "localSaveFailed"
        case .cloudSyncFailed: return "cloudSyncFailed"
        case .mergeConflict: return "mergeConflict"
        case .unknown: return "unknown"
        }
    }
    
    public var errorDescription: String? {
        switch self {
        case .localSaveFailed(let error):
            return "Failed to save locally: \(error.localizedDescription)"
        case .cloudSyncFailed(let error):
            return "Failed to sync to cloud: \(error.localizedDescription)"
        case .mergeConflict:
            return "Conflict detected during sync"
        case .unknown(let error):
            return "An error occurred: \(error.localizedDescription)"
        }
    }
}
