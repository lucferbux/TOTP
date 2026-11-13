//
//  TOTPWatchApp.swift
//  TOTP Watch
//
//  Read-only companion: the TOTP codes the iPhone sends, a large code view, and a complication.
//

import SwiftUI
import WatchKit
import WatchConnectivity

@main
struct TOTPWatchApp: App {
    @WKApplicationDelegateAdaptor private var delegate: WatchAppDelegate
    @ObservedObject private var model = WatchAccountsModel.shared

    var body: some Scene {
        WindowGroup {
            AccountListView(model: model)
        }
    }
}

/// Starts the session at launch — including the background launches watchOS makes to deliver a
/// new application context, so the complication is current without opening the app.
final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    func applicationDidFinishLaunching() {
        WatchAccountsModel.shared.activate()
    }

    func handle(_ backgroundTasks: Set<WKRefreshBackgroundTask>) {
        for task in backgroundTasks {
            if let task = task as? WKWatchConnectivityRefreshBackgroundTask {
                WatchAccountsModel.shared.activate()
                WatchAccountsModel.shared.completeWhenDelivered(task)
            } else {
                task.setTaskCompletedWithSnapshot(false)
            }
        }
    }
}
