//
//  WatchAccountsModel.swift
//  TOTP Watch
//
//  Receives the accounts from the iPhone (WatchConnectivity application context), keeps a sealed
//  copy for the complication, and publishes what the list should show. Read-only: the watch never
//  adds, edits or deletes an account, and never sees HOTP accounts or prefixes.
//

import Foundation
import WatchConnectivity
import WidgetKit
import WatchKit
import os

/// Launch-time switches. Debug-only, like the iPhone's `AppEnvironment`.
enum WatchEnvironment {
    /// `-ScreenshotMode`: fictional in-memory accounts, no session, nothing stored.
    static let isTakingScreenshots: Bool = {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-ScreenshotMode")
        #else
        return false
        #endif
    }()

    /// `-ScreenshotScene <name>`; `detail` opens the first account.
    static let screenshotScene: String? = {
        #if DEBUG
        guard isTakingScreenshots else { return nil }
        let arguments = ProcessInfo.processInfo.arguments
        guard let flag = arguments.firstIndex(of: "-ScreenshotScene"),
              arguments.index(after: flag) < arguments.endIndex else { return nil }
        return arguments[arguments.index(after: flag)]
        #else
        return nil
        #endif
    }()
}

@MainActor
final class WatchAccountsModel: NSObject, ObservableObject {
    static let shared = WatchAccountsModel()

    @Published private(set) var state: WatchAccountCache.State
    /// Background launches waiting for the session to hand over its pending context.
    private var pendingTasks: [WKWatchConnectivityRefreshBackgroundTask] = []

    nonisolated private static let logger = Logger(subsystem: "com.lucferbux.TOTP.watchkitapp", category: "Sync")

    private override init() {
        if WatchEnvironment.isTakingScreenshots {
            // Same path as real data: the payload strips prefixes and drops HOTP.
            state = .ready(WatchPayload(accounts: SampleAccounts.screenshot, isLocked: false).models())
        } else {
            state = WatchAccountCache.load(key: WatchKeyStore.existingKey())
        }
        super.init()
    }

    var accounts: [OtpModel] {
        if case let .ready(accounts) = state { return accounts }
        return []
    }

    func activate() {
        guard !WatchEnvironment.isTakingScreenshots, WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.delegate == nil else { return }
        session.delegate = self
        session.activate()
    }

    fileprivate func apply(_ payload: WatchPayload) {
        if let key = WatchKeyStore.keyForSealing() {
            do {
                try WatchAccountCache.store(payload, key: key)
                state = WatchAccountCache.load(key: key)
            } catch {
                Self.logger.error("Couldn't store the accounts: \(error.localizedDescription, privacy: .public)")
                state = payload.isLocked ? .locked : .ready(payload.models())
            }
        } else {
            // Keychain unreadable right now: show what arrived, but keep nothing on disk.
            state = payload.isLocked ? .locked : .ready(payload.models())
        }
        WidgetCenter.shared.reloadAllTimelines()
        completePendingTasksIfDelivered()
    }

    func completeWhenDelivered(_ task: WKWatchConnectivityRefreshBackgroundTask) {
        pendingTasks.append(task)
        completePendingTasksIfDelivered()
    }

    fileprivate func completePendingTasksIfDelivered() {
        let session = WCSession.default
        guard session.activationState == .activated, !session.hasContentPending else { return }
        pendingTasks.forEach { $0.setTaskCompletedWithSnapshot(false) }
        pendingTasks.removeAll()
    }
}

extension WatchAccountsModel: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error {
            Self.logger.error("Session activation failed: \(error.localizedDescription, privacy: .public)")
        }
        // The latest context may have arrived while the app wasn't running.
        receive(session.receivedApplicationContext)
        Task { @MainActor in self.completePendingTasksIfDelivered() }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        receive(applicationContext)
    }

    nonisolated private func receive(_ context: [String: Any]) {
        guard !context.isEmpty else { return }
        do {
            let payload = try WatchPayload.decode(applicationContext: context)
            Task { @MainActor in self.apply(payload) }
        } catch {
            Self.logger.error("Ignoring an unreadable payload: \(error.localizedDescription, privacy: .public)")
        }
    }
}
