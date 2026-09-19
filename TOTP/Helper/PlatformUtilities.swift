//
//  PlatformUtilities.swift
//  TOTP
//
//  Cross-platform utilities for iOS and macOS compatibility
//

import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

#if canImport(AppKit)
import AppKit
#endif

// MARK: - Cross-platform Colors
public struct PlatformColors {
    static var systemGroupedBackground: Color {
        #if canImport(UIKit)
        return Color(UIColor.systemGroupedBackground)
        #else
        return Color(NSColor.windowBackgroundColor)
        #endif
    }

    static var secondarySystemGroupedBackground: Color {
        #if canImport(UIKit)
        return Color(UIColor.secondarySystemGroupedBackground)
        #else
        return Color(NSColor.controlBackgroundColor)
        #endif
    }
}

// MARK: - Cross-platform Pasteboard
public struct PlatformPasteboard {
    /// Copies with the user's auto-clear preference applied.
    @MainActor
    static func copyToClipboard(_ text: String) {
        ClipboardManager.copy(text)
    }
}

// MARK: - Settings deep links
enum SystemSettings {
    @MainActor
    static func openAppSettings() {
        #if os(iOS)
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
        #elseif os(macOS)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preferences.AppleIDPrefPane") {
            NSWorkspace.shared.open(url)
        }
        #endif
    }
}
