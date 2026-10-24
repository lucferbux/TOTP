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

#if canImport(UIKit)
import UIKit
#endif

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

/// Manages synchronization between local storage (SharedDataManager) and CloudKit.
///
/// Main-actor isolated: it owns UI state and drives `SharedDataManager`, which is main-actor too.
/// CloudKit calls suspend, so anything read before an `await` may be stale after it — every step
/// below re-reads `localManager.accounts` instead of carrying a snapshot across a suspension.
@MainActor
public final class SyncManager: ObservableObject {
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

    /// Guards against running the initial sync more than once per launch.
    private var hasStarted = false

    /// The sync pass in flight. Launch, pushes, pull-to-refresh and Settings all ask for a sync;
    /// they share one pass instead of racing each other.
    private var syncTask: Task<Void, Never>?
    /// Set when a sync is requested while one is running, so the change that triggered it isn't missed.
    private var syncRequestedAgain = false

    /// CloudKit writes for single accounts run one at a time, in order: two quick HOTP copies must
    /// reach iCloud as counter + 1 then counter + 2, never the other way round.
    private var cloudWriteChain: Task<Void, Never>?

    /// The Spotlight update in flight; each one waits for the previous so the last list wins.
    private var spotlightTask: Task<Void, Never>?

    private static let pendingDeletionsKey = "pending_cloud_deletions"

    private init() {
        setupObservers()
    }

    /// Starts the initial sync exactly once, from whichever surface comes up first.
    /// On macOS the main window is suppressed at launch, so the menu bar (or the app delegate)
    /// has to kick this off — otherwise sync would never run for menu-bar-only users.
    public func startIfNeeded() {
        guard !hasStarted else { return }
        hasStarted = true
        Task { await initializeSync() }
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

        #if canImport(UIKit)
        // A launch before the first unlock (a background push after a restart) can't read the key,
        // so the list comes up empty. Retry once the device is unlocked instead of waiting for a relaunch.
        NotificationCenter.default.publisher(for: UIApplication.protectedDataDidBecomeAvailableNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.reloadAfterUnlockIfNeeded()
            }
            .store(in: &cancellables)
        #endif
    }

    private func reloadAfterUnlockIfNeeded() {
        guard case .keyUnavailable? = localManager.error else { return }
        logger.info("Protected data available; reloading accounts")
        localManager.reloadAfterUnlock()
        accounts = localManager.accounts
        Task { await performSync() }
    }

    // MARK: - Initialization

    /// Initializes sync on app launch
    public func initializeSync() async {
        hasStarted = true
        if AppEnvironment.isUITesting {
            accounts = localManager.accounts
            syncState = .idle
            return
        }

        logger.debug("Initial sync starting")
        isLoading = true
        syncState = .syncing

        // SharedDataManager loaded the store when it was created; just publish it.
        accounts = localManager.accounts
        scheduleSpotlightIndexing()

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
        // Once per launch, even when nothing changed: the system may have dropped our identities.
        await syncCredentialIdentities()
    }

    // MARK: - Sync Operations

    /// Performs a full sync between local and cloud storage. Concurrent callers share the pass in
    /// flight; a request that arrives during a pass gets one more pass once it finishes.
    public func performSync() async {
        if let running = syncTask {
            syncRequestedAgain = true
            await running.value
            return
        }
        let task = Task {
            repeat {
                syncRequestedAgain = false
                await syncPass()
            } while syncRequestedAgain
        }
        syncTask = task
        await task.value
        syncTask = nil
    }

    private func syncPass() async {
        guard iCloudAvailable else {
            logger.notice("Sync skipped: iCloud is not available")
            syncState = .iCloudDisabled
            return
        }

        syncState = .syncing
        // Re-read key storage: iCloud Keychain may have delivered a key since the last pass (the
        // oldest shared key becomes primary), and the local store is then re-sealed with it.
        EncryptionKeyManager.shared.invalidateCache()
        localManager.resealIfNeeded()
        let before = localManager.accounts

        do {
            // Finish deletions that couldn't reach iCloud earlier, so they can't come back below
            await pushPendingCloudDeletions()

            // Load cloud accounts
            await cloudManager.loadAccounts()

            // One-time move of records written by 3.x into the synced zone
            await cloudManager.migrateDefaultZoneRecords(ids: localManager.accounts.map { $0.id.uuidString })

            // Apply deletions made on other devices
            applyCloudDeletions()

            // Re-upload anything the cloud still holds under an old encryption key, so other
            // devices (which now share the key) can read it.
            await reuploadLegacyEncryptedRecords()

            // Read both sides only now: the awaits above let the user add, edit or delete accounts.
            let pending = pendingCloudDeletions
            let cloudAccounts = try cloudManager.getOtpModels().filter { !pending.contains($0.id) }
            let localAccounts = localManager.accounts

            let merged = Self.mergeAccounts(local: localAccounts, cloud: cloudAccounts)
            updateLocalStorage(with: merged)

            // Accounts on both sides: the later edit wins, in whichever direction it lies
            let changes = Self.reconcile(local: localManager.accounts, cloud: cloudAccounts)
            applyCloudChanges(changes.local)

            // Upload local-only accounts and the edits this device made last
            await uploadLocalOnlyAccounts(cloudAccounts: cloudAccounts)
            for account in changes.cloud where localManager.accounts.contains(where: { $0.id == account.id }) {
                do {
                    try await cloudManager.updateOtpModel(account)
                } catch {
                    logger.error("Failed to upload a newer local edit: \(error.localizedDescription, privacy: .public)")
                }
            }

            if localManager.accounts != before {
                await afterMutation()
            }

            logger.info("Sync finished: \(self.accounts.count, privacy: .public) local, \(cloudAccounts.count, privacy: .public) in iCloud")
            syncState = .synced(Date())

        } catch {
            logger.error("Sync failed: \(error.localizedDescription, privacy: .public)")
            syncState = .error(error.localizedDescription)
        }
    }

    /// Removes accounts that were deleted on another device.
    private func applyCloudDeletions() {
        let deleted = cloudManager.deletedAccountIDs
        guard !deleted.isEmpty else { return }
        let ids = Set(deleted.compactMap(UUID.init(uuidString:)))
        let present = localManager.accounts.filter { ids.contains($0.id) }
        if !present.isEmpty {
            logger.info("Removing \(present.count, privacy: .public) account(s) deleted on another device")
            localManager.deleteAccounts(withIds: Set(present.map(\.id)))
            accounts = localManager.accounts
        }
        cloudManager.deletedAccountIDs.removeAll()
    }

    /// Merges local and cloud accounts. The same account is matched by id (records keep their
    /// UUID as the record name) and then by issuer + name; cloud-only accounts are added. Accounts
    /// present on both sides are reconciled by `reconcile`.
    nonisolated static func mergeAccounts(local: [OtpModel], cloud: [OtpModel]) -> [OtpModel] {
        var merged: [UUID: OtpModel] = [:]

        // Add all local accounts
        for account in local {
            merged[account.id] = account
        }

        for cloudAccount in cloud {
            if merged[cloudAccount.id] != nil { continue }
            if let existingAccount = local.first(where: {
                $0.issuer == cloudAccount.issuer && $0.name == cloudAccount.name
            }) {
                // Same account under another ID: keep the local one
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

    /// Accounts present on both sides (same id) whose copies differ, resolved with
    /// `OtpModel.resolved`: the later edit wins and an HOTP counter never moves backwards. `local`
    /// lists the accounts this device must take from iCloud, `cloud` the ones iCloud must take from
    /// this device. Copies that differ only in their modification date need nothing.
    nonisolated static func reconcile(local: [OtpModel], cloud: [OtpModel]) -> (local: [OtpModel], cloud: [OtpModel]) {
        let cloudByID = Dictionary(cloud.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var localUpdates: [OtpModel] = []
        var cloudUpdates: [OtpModel] = []
        for account in local {
            guard let remote = cloudByID[account.id], !account.hasSameContent(as: remote) else { continue }
            let resolved = OtpModel.resolved(account, remote)
            if !resolved.hasSameContent(as: account) { localUpdates.append(resolved) }
            if !resolved.hasSameContent(as: remote) { cloudUpdates.append(resolved) }
        }
        return (localUpdates, cloudUpdates)
    }

    /// Adds merged accounts missing locally. Accounts deleted here are never re-added.
    private func updateLocalStorage(with merged: [OtpModel]) {
        let pending = pendingCloudDeletions
        for account in merged where !pending.contains(account.id) {
            if !localManager.accounts.contains(where: { $0.id == account.id }) {
                localManager.addAccount(account)
            }
        }
        accounts = localManager.accounts
    }

    /// Takes edits made on other devices, keeping their modification dates.
    private func applyCloudChanges(_ updates: [OtpModel]) {
        guard !updates.isEmpty else { return }
        logger.info("Applying \(updates.count, privacy: .public) newer edit(s) from iCloud")
        for account in updates {
            do {
                try localManager.updateAccount(account)
            } catch {
                logger.error("Failed to apply an edit from iCloud: \(error.localizedDescription, privacy: .public)")
            }
        }
        accounts = localManager.accounts
    }

    /// Uploads accounts that exist only on this device. Each one is re-checked right before its
    /// upload, so an account deleted while an earlier upload was in flight isn't sent back up.
    private func uploadLocalOnlyAccounts(cloudAccounts: [OtpModel]) async {
        for localAccount in localManager.accounts {
            let existsInCloud = cloudAccounts.contains { cloudAccount in
                cloudAccount.id == localAccount.id
                || (cloudAccount.issuer == localAccount.issuer && cloudAccount.name == localAccount.name)
            }
            guard !existsInCloud,
                  localManager.accounts.contains(where: { $0.id == localAccount.id }),
                  !pendingCloudDeletions.contains(localAccount.id) else { continue }
            do {
                logger.info("Uploading a local-only account to iCloud")
                try await cloudManager.addOtpModel(localAccount)
            } catch {
                logger.error("Failed to upload account: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // MARK: - Account Operations (synced)

    /// Adds a new account and syncs to cloud
    public func addAccount(_ account: OtpModel) async {
        // Add locally first (fast)
        localManager.addAccount(account)
        accounts = localManager.accounts

        await writeToCloud {
            try await $0.addOtpModel(account)
        }
        await afterMutation()
    }

    /// Updates an existing account and syncs to cloud. This is an edit, so it becomes the newest copy.
    public func updateAccount(_ account: OtpModel) async throws {
        var account = account
        account.modifiedDate = .now
        // Update locally first
        try localManager.updateAccount(account)
        accounts = localManager.accounts

        await writeToCloud {
            try await $0.updateOtpModel(account)
        }
        await afterMutation()
    }

    /// Deletes an account and syncs to cloud
    public func deleteAccount(_ account: OtpModel) async {
        await deleteAccounts(withIds: [account.id])
    }

    /// Deletes several accounts at once. They leave this device — and AutoFill, widgets and
    /// Spotlight — immediately; iCloud follows, and any removal that can't reach it yet is retried
    /// on the next sync rather than letting the account come back.
    public func deleteAccounts(withIds ids: Set<UUID>) async {
        guard !ids.isEmpty else { return }
        if !AppEnvironment.isUITesting {
            pendingCloudDeletions.formUnion(ids)
        }
        localManager.deleteAccounts(withIds: ids)
        accounts = localManager.accounts
        await afterMutation()

        if iCloudAvailable {
            await pushPendingCloudDeletions()
            if pendingCloudDeletions.isEmpty {
                syncState = .synced(Date())
            }
        }
    }

    /// Re-uploads cloud records that were sealed with a previous device-local key.
    private func reuploadLegacyEncryptedRecords() async {
        let pending = Set(pendingCloudDeletions.map(\.uuidString))
        let stale = cloudManager.accounts.filter { !$0.sealedWithPrimaryKey && !pending.contains($0.id) }
        guard !stale.isEmpty else { return }
        logger.info("Re-encrypting \(stale.count, privacy: .public) cloud record(s) with the shared key")
        for record in stale {
            guard let model = try? record.toOtpModel() else { continue }
            do {
                try await cloudManager.updateOtpModel(model)
            } catch {
                logger.error("Failed to re-encrypt cloud record: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Persists a new order (drag to reorder).
    public func moveAccounts(fromOffsets source: IndexSet, toOffset destination: Int) {
        localManager.moveAccounts(fromOffsets: source, toOffset: destination)
        accounts = localManager.accounts
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Returns the value to copy (prefix + code) and, for HOTP, advances and saves the counter
    /// so the same code is never produced twice.
    ///
    /// Synchronous on purpose: the counter is advanced and saved before anything can suspend, so a
    /// second tap while the upload is still in flight sees the new counter instead of the same code.
    public func useCode(for account: OtpModel) -> String {
        let current = localManager.accounts.first { $0.id == account.id } ?? account
        let value = current.autoFillValue()
        guard current.entry.isHotp else { return value }

        var updated = current
        updated.entry = current.entry.advanced()
        updated.modifiedDate = .now
        do {
            try localManager.updateAccount(updated)
        } catch {
            logger.error("Failed to save the HOTP counter: \(error.localizedDescription, privacy: .public)")
        }
        accounts = localManager.accounts
        Task {
            await writeToCloud { try await $0.updateOtpModel(updated) }
            await afterMutation()
        }
        return value
    }

    /// Runs one CloudKit write after the previous one finished. Failures are logged: the local
    /// change already happened, and the next sync uploads it.
    private func writeToCloud(_ write: @escaping (CloudKitDataManager) async throws -> Void) async {
        guard iCloudAvailable else { return }
        let previous = cloudWriteChain
        let cloudManager = cloudManager
        let task = Task {
            await previous?.value
            do {
                try await write(cloudManager)
                syncState = .synced(Date())
            } catch {
                logger.error("Failed to sync a change to iCloud: \(error.localizedDescription, privacy: .public)")
            }
        }
        cloudWriteChain = task
        await task.value
    }

    // MARK: - Pending deletions

    /// Accounts deleted on this device whose iCloud record may still exist: deleted offline, while
    /// signed out of iCloud, or during a sync pass that had already read the cloud. Kept (in the App
    /// Group, so it survives a relaunch) until CloudKit confirms, so no sync can bring them back.
    private var pendingCloudDeletions: Set<UUID> {
        get {
            Set((AppGroup.defaults.stringArray(forKey: Self.pendingDeletionsKey) ?? []).compactMap(UUID.init(uuidString:)))
        }
        set {
            if newValue.isEmpty {
                AppGroup.defaults.removeObject(forKey: Self.pendingDeletionsKey)
            } else {
                AppGroup.defaults.set(newValue.map(\.uuidString), forKey: Self.pendingDeletionsKey)
            }
        }
    }

    private func pushPendingCloudDeletions() async {
        guard iCloudAvailable else { return }
        for id in pendingCloudDeletions {
            do {
                try await cloudManager.deleteOtpModel(withId: id.uuidString)
                pendingCloudDeletions.remove(id)
            } catch {
                logger.error("Failed to sync account deletion to cloud: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Keeps widgets, AutoFill and Spotlight consistent after any change.
    private func afterMutation() async {
        WidgetCenter.shared.reloadAllTimelines()
        await syncCredentialIdentities()
        scheduleSpotlightIndexing()
    }

    // MARK: - Spotlight

    /// Donates account names (never secrets) to Spotlight so "Copy code for …" is searchable.
    /// Deliberately fire-and-forget: Spotlight can take a long time (or never return) and must
    /// never hold up syncing or launch. Updates run in order, so an older list can't land last.
    public func scheduleSpotlightIndexing() {
        guard !AppEnvironment.isUITesting else { return }
        // With the app lock on, issuer and account names must not stay searchable from the
        // Lock Screen — clear the index instead of donating to it.
        let locked = AppPreferences.appLockEnabled
        let entities = locked ? [] : accounts.filter { !$0.entry.isHotp }.map(AccountEntity.init(model:))
        let previous = spotlightTask
        previous?.cancel()
        spotlightTask = Task.detached(priority: .background) {
            await previous?.value
            guard !Task.isCancelled else { return }
            do {
                try await CSSearchableIndex.default().deleteAppEntities(ofType: AccountEntity.self)
                if !entities.isEmpty, !Task.isCancelled {
                    try await CSSearchableIndex.default().indexAppEntities(entities)
                }
                logger.info("Spotlight index updated")
            } catch {
                logger.error("Spotlight indexing failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Re-applies everything the app lock changes outside the app: Spotlight entries and widgets.
    public func appLockDidChange() {
        WidgetCenter.shared.reloadAllTimelines()
        scheduleSpotlightIndexing()
    }

    // MARK: - Manual Sync

    /// Triggers a manual sync (pull-to-refresh)
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
    public func handleRemoteNotification(userInfo: [AnyHashable: Any]) async -> Bool {
        guard iCloudAvailable, cloudManager.isZoneNotification(userInfo) else { return false }
        logger.info("Received CloudKit push; syncing")
        // The sync pass fetches the zone changes itself; fetching here too would read them twice.
        await performSync()
        return true
    }

    // MARK: - Credential Identity Sync (AutoFill)

    /// Syncs credential identities to ASCredentialIdentityStore for AutoFill
    public func syncCredentialIdentities() async {
        guard !AppEnvironment.isUITesting else { return }
        let store = ASCredentialIdentityStore.shared

        // Check if store is enabled
        let state = await store.state()
        guard state.isEnabled else { return }

        // Create identities for all accounts. HOTP is left out: filling one from the extension
        // would hand out a code without advancing (and saving) its counter.
        var identities: [ASCredentialIdentity] = []

        for account in accounts where !account.entry.isHotp {
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
    nonisolated static func serviceIdentifier(for account: OtpModel) -> ASCredentialServiceIdentifier {
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
