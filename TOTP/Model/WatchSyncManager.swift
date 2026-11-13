//
//  WatchSyncManager.swift
//  TOTP (iOS only)
//
//  Sends the TOTP accounts to the paired Apple Watch through WatchConnectivity.
//
//  Security model:
//    • Only what a code needs travels: issuer, name, secret, digits, period, algorithm and order.
//      Never the prefix (PIN), never associated domains, never HOTP accounts.
//    • With the app lock on, nothing is sent but the "locked" flag — the watch wipes its copy.
//    • The application context is delivered over the paired devices' encrypted channel; the watch
//      seals it with its own device-only key before storing it.
//    • Nothing here logs account data.
//

#if os(iOS)
import Foundation
import WatchConnectivity
import os

@MainActor
public final class WatchSyncManager: NSObject {
    public static let shared = WatchSyncManager()

    nonisolated private static let logger = Logger(subsystem: "com.lucferbux.TOTP", category: "Watch")

    /// Where the accounts come from; `SyncManager` sets it when it starts the session.
    private var accountsProvider: (@MainActor () -> [OtpModel])?
    private var session: WCSession? { WCSession.isSupported() ? WCSession.default : nil }

    private override init() {
        super.init()
    }

    /// Starts the session. Safe to call more than once; does nothing in UI-test mode or on devices
    /// without WatchConnectivity (iPad).
    public func activate(accounts: @escaping @MainActor () -> [OtpModel]) {
        guard !AppEnvironment.isUITesting, let session else { return }
        accountsProvider = accounts
        guard session.delegate == nil else { return }
        session.delegate = self
        session.activate()
    }

    /// Pushes the current accounts and lock state. Call after every change to either.
    public func update() {
        guard let accountsProvider else { return }
        update(accounts: accountsProvider(), isLocked: AppPreferences.appLockEnabled)
    }

    private func update(accounts: [OtpModel], isLocked: Bool) {
        guard let session, session.activationState == .activated,
              session.isPaired, session.isWatchAppInstalled else { return }
        do {
            let payload = WatchPayload(accounts: accounts, isLocked: isLocked)
            try session.updateApplicationContext(payload.applicationContext())
        } catch {
            Self.logger.error("Couldn't update the watch: \(error.localizedDescription, privacy: .public)")
        }
    }
}

extension WatchSyncManager: WCSessionDelegate {
    nonisolated public func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error {
            Self.logger.error("Watch session activation failed: \(error.localizedDescription, privacy: .public)")
        }
        Task { @MainActor in self.update() }
    }

    nonisolated public func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated public func sessionDidDeactivate(_ session: WCSession) {
        // Switching to another watch: activate again so the new one gets the accounts.
        session.activate()
    }

    nonisolated public func sessionWatchStateDidChange(_ session: WCSession) {
        // Paired, unpaired, or the watch app was just installed.
        Task { @MainActor in self.update() }
    }

    nonisolated public func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in self.update() }
    }
}
#endif
