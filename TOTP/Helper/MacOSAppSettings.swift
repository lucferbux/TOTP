//
//  MacOSAppSettings.swift
//  TOTP
//
//  macOS-specific settings for background mode, dock icon, and login item management.
//

#if os(macOS)
import SwiftUI
import ServiceManagement
import AppKit
import os

final class MacOSAppSettings: ObservableObject {
    static let shared = MacOSAppSettings()
    
    private let defaults = UserDefaults.standard
    
    private enum Keys {
        static let showDockIcon = "macOS_showDockIcon"
        static let launchAtLogin = "macOS_launchAtLogin"
    }
    
    /// Whether to show the app icon in the Dock. Default: false (hidden).
    @Published var showDockIcon: Bool {
        didSet {
            defaults.set(showDockIcon, forKey: Keys.showDockIcon)
            applyDockIconPolicy()
        }
    }
    
    /// Whether the app should launch at login. Default: false.
    @Published var launchAtLogin: Bool {
        didSet {
            defaults.set(launchAtLogin, forKey: Keys.launchAtLogin)
            applyLoginItemState()
        }
    }
    
    private init() {
        // Register defaults (dock icon hidden by default)
        defaults.register(defaults: [
            Keys.showDockIcon: false,
            Keys.launchAtLogin: false
        ])
        
        self.showDockIcon = defaults.bool(forKey: Keys.showDockIcon)
        self.launchAtLogin = defaults.bool(forKey: Keys.launchAtLogin)
    }
    
    // MARK: - Dock Icon
    
    /// Applies the current dock icon visibility setting.
    /// `.accessory` hides the dock icon; `.regular` shows it.
    func applyDockIconPolicy() {
        if showDockIcon {
            NSApp.setActivationPolicy(.regular)
        } else {
            NSApp.setActivationPolicy(.accessory)
            // Ensure the app stays activatable even without dock icon
            NSApp.activate()
        }
    }
    
    // MARK: - Launch at Login
    
    /// Registers or unregisters the app as a Login Item using SMAppService.
    private func applyLoginItemState() {
        let service = SMAppService.mainApp
        do {
            if launchAtLogin {
                try service.register()
            } else {
                try service.unregister()
            }
        } catch {
            Logger(subsystem: "com.lucferbux.TOTP", category: "Settings")
                .error("Failed to update login item: \(error.localizedDescription, privacy: .public)")
        }
        objectWillChange.send()
    }
    
    /// Reads the current login item status from the system.
    var loginItemStatus: SMAppService.Status {
        return SMAppService.mainApp.status
    }

    /// Whether the main window opens when the app launches. It stays hidden only once the user has
    /// turned on launch at login and so knows the app lives in the menu bar; otherwise opening the
    /// app would show nothing but a menu bar icon, which a notch can even hide.
    var presentsWindowAtLaunch: Bool {
        !(launchAtLogin && SMAppService.mainApp.status == .enabled)
    }
    
    // MARK: - Window Management
    
    /// Shows the main app window (useful from menu bar).
    func showMainWindow(openWindow: OpenWindowAction) {
        NSApp.setActivationPolicy(.regular)
        
        // Check if a main window already exists
        for window in NSApp.windows {
            if window.canBecomeMain && !window.className.contains("MenuBarExtra") && !window.className.contains("Settings") {
                window.makeKeyAndOrderFront(nil)
                NSApp.activate()
                return
            }
        }
        
        // No main window exists — create one via the WindowGroup id
        openWindow(id: "main")
        NSApp.activate()
    }
}
#endif
