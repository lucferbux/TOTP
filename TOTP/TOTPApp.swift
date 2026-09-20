//
//  TOTPApp.swift
//  TOTP
//
//  Created by Lucas Fernández Aragón on 4/3/25.
//

import SwiftUI
import WidgetKit
import CloudKit
import os

#if canImport(UIKit)
import UIKit
#endif

#if canImport(AppKit)
import AppKit
#endif

private let logger = Logger(subsystem: "com.lucferbux.TOTP", category: "App")

@main
struct TOTPApp: App {
    #if os(iOS)
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    #elseif os(macOS)
    @NSApplicationDelegateAdaptor(MacAppDelegate.self) var appDelegate
    #endif

    @StateObject private var syncManager = SyncManager.shared
    @StateObject private var lock = AppLockManager.shared

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .environmentObject(syncManager)
                .appLock(lock)
                .onOpenURL { url in
                    handleURL(url)
                }
                .task {
                    syncManager.startIfNeeded()
                }
        }
        #if os(macOS)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 820, height: 600)
        .defaultLaunchBehavior(AppEnvironment.isUITesting ? .presented : .suppressed)
        #endif
        .commands {
            AccountCommands()
        }

        #if os(macOS)
        // Menu bar icon with the list of codes. The icon is static on purpose: macOS 27
        // hosts all status items in one window, and frequently changing items are costly.
        MenuBarExtra("TOTP Password", systemImage: "lock.shield.fill") {
            MenuBarView()
                .environmentObject(syncManager)
        }
        .menuBarExtraStyle(.window)

        // macOS Settings window (Cmd+,)
        Settings {
            SettingsView()
                .environmentObject(syncManager)
        }
        #endif
    }

    private func handleURL(_ url: URL) {
        switch url.scheme?.lowercased() {
        case "otpauth":
            do {
                AppRouter.shared.pendingImport = try OtpAuthURL(url: url)
            } catch {
                AppRouter.shared.importError = error.localizedDescription
            }
        case "totp":
            // The ≤3.x widget used totp://copy?code=… to put text on the clipboard. Any app or web
            // page could call it, so it's gone; widgets copy through CopyCodeIntent now.
            WidgetCenter.shared.reloadAllTimelines()
        default:
            break
        }
    }
}

/// File ▸ Add Account (⌘N) — also shown in the iPadOS menu bar.
struct AccountCommands: Commands {
    @FocusedValue(\.addAccountAction) private var addAccount

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Add Account…") {
                addAccount?()
            }
            .keyboardShortcut("n", modifiers: .command)
            .disabled(addAccount == nil)
        }
    }
}

// MARK: - App Delegate for Remote Notifications

#if os(iOS)
class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Register for remote notifications (CloudKit silent push)
        if !AppEnvironment.isUITesting {
            application.registerForRemoteNotifications()
        }
        Task { @MainActor in SyncManager.shared.startIfNeeded() }
        return true
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        logger.error("Remote notification registration failed: \(error.localizedDescription, privacy: .public)")
    }

    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        Task {
            let handled = await SyncManager.shared.handleRemoteNotification(userInfo: userInfo)
            completionHandler(handled ? .newData : .noData)
        }
    }
}
#endif

// MARK: - macOS App Delegate for Remote Notifications & Lifecycle

#if os(macOS)
class MacAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if !AppEnvironment.isUITesting {
            NSApplication.shared.registerForRemoteNotifications()
        }
        MacOSAppSettings.shared.applyDockIconPolicy()
        // The main window is suppressed at launch, so start syncing here rather than from a view.
        Task { @MainActor in SyncManager.shared.startIfNeeded() }
        #if DEBUG
        positionWindowForScreenshotsIfNeeded()
        #endif
    }

    #if DEBUG
    /// Puts the window at a known place and size so `scripts/export-screenshots.sh` can capture it
    /// without needing Accessibility permission. 1440x900 points captures at 2880x1800 — an
    /// App Store–accepted Mac size.
    private func positionWindowForScreenshotsIfNeeded() {
        guard AppEnvironment.isTakingScreenshots else { return }
        // Always the primary (menu bar) display: its frame origin is (0, 0), which is the space
        // `screencapture -R` works in. `NSScreen.main` is the *focused* screen, so on a machine
        // with a second display it silently puts the window in another coordinate space.
        guard let screen = NSScreen.screens.first else { return }

        let size = CGSize(width: 1440, height: 900)
        let insetFromTop: CGFloat = 100

        // A scene can end up with a second, empty main window on top of the real one. The window
        // we want is the one carrying the toolbar; the rest are ordered out so they can't be shot.
        func mainWindows() -> [NSWindow] {
            let titled = NSApp.windows.filter {
                $0.isVisible && $0.canBecomeMain && $0.styleMask.contains(.titled) && !($0 is NSPanel)
            }
            let withToolbar = titled.filter { $0.toolbar != nil }
            guard !withToolbar.isEmpty else { return titled }
            for extra in titled where extra.toolbar == nil {
                extra.orderOut(nil)
            }
            return withToolbar
        }

        // Applied several times because presenting a sheet or entering select mode rebuilds the
        // toolbar afterwards, and SwiftUI re-lays out the window once that happens.
        for delay in [1.5, 4.0, 7.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                let frame = CGRect(x: screen.frame.minX + 100,
                                   y: screen.frame.maxY - insetFromTop - size.height,
                                   width: size.width, height: size.height)
                for window in mainWindows() {
                    window.setFrame(frame, display: true)
                }
                NSApp.activate(ignoringOtherApps: true)
                mainWindows().last?.makeKeyAndOrderFront(nil)
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 9.5) {
            // AppKit keeps the origin (bottom-left) when SwiftUI makes the window taller than we
            // asked, so it grows upwards. Re-anchor the top edge without touching the size.
            for window in mainWindows() {
                window.setFrameOrigin(CGPoint(
                    x: screen.frame.minX + 100,
                    y: screen.frame.maxY - insetFromTop - window.frame.height
                ))
            }
            // Report where the window actually ended up — AppKit can still clamp it — in
            // screencapture's coordinates: points, origin at the top-left of the primary display.
            guard let window = mainWindows().last,
                  let container = FileManager.default.containerURL(
                      forSecurityApplicationGroupIdentifier: AppGroup.identifier) else { return }
            let frame = window.frame
            let report = "\(Int(frame.minX)),\(Int(screen.frame.maxY - frame.maxY)),\(Int(size.width)),\(Int(size.height))\n"
            try? report.write(to: container.appendingPathComponent("screenshot-window-frame"),
                              atomically: true, encoding: .utf8)
        }
    }
    #endif

    func application(_ application: NSApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        logger.error("Remote notification registration failed: \(error.localizedDescription, privacy: .public)")
    }

    func application(_ application: NSApplication, didReceiveRemoteNotification userInfo: [String: Any]) {
        Task {
            _ = await SyncManager.shared.handleRemoteNotification(userInfo: userInfo)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            for window in sender.windows where window.canBecomeMain {
                window.makeKeyAndOrderFront(self)
                break
            }
        }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Don't quit — keep running in the menu bar
        MacOSAppSettings.shared.applyDockIconPolicy()
        return false
    }
}
#endif
