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
    static var systemFill: Color {
        #if canImport(UIKit)
        return Color(UIColor.systemFill)
        #else
        return Color(NSColor.controlBackgroundColor)
        #endif
    }
    
    static var tertiarySystemFill: Color {
        #if canImport(UIKit)
        return Color(UIColor.tertiarySystemFill)
        #else
        return Color(NSColor.tertiaryLabelColor).opacity(0.1)
        #endif
    }
    
    static var secondarySystemBackground: Color {
        #if canImport(UIKit)
        return Color(UIColor.secondarySystemBackground)
        #else
        return Color(NSColor.windowBackgroundColor)
        #endif
    }
    
    static var label: Color {
        #if canImport(UIKit)
        return Color(UIColor.label)
        #else
        return Color(NSColor.labelColor)
        #endif
    }
    
    static var placeholderText: Color {
        #if canImport(UIKit)
        return Color(UIColor.placeholderText)
        #else
        return Color(NSColor.placeholderTextColor)
        #endif
    }
    
    static var systemBackground: Color {
        #if canImport(UIKit)
        return Color(UIColor.systemBackground)
        #else
        return Color(NSColor.windowBackgroundColor)
        #endif
    }
}

// MARK: - Cross-platform Pasteboard
public struct PlatformPasteboard {
    static func copyToClipboard(_ text: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = text
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }
}

// MARK: - Platform Detection
public struct PlatformInfo {
    static var isMacOS: Bool {
        #if canImport(AppKit) && !targetEnvironment(macCatalyst)
        return true
        #else
        return false
        #endif
    }
    
    static var isIOS: Bool {
        #if canImport(UIKit) && !canImport(AppKit)
        return true
        #else
        return false
        #endif
    }
}
