//
//  ClipboardManager.swift
//  Shared (app, widget, AutoFill)
//
//  Every copy of a code goes through here so auto-clear applies everywhere.
//

import Foundation

#if canImport(UIKit)
import UIKit
import UniformTypeIdentifiers
#endif

#if canImport(AppKit)
import AppKit
#endif

/// User preferences shared through the App Group so extensions honour them too.
public enum AppPreferences {
    public enum Keys {
        public static let clipboardClearSeconds = "clipboardClearSeconds"
        public static let appLockEnabled = "appLockEnabled"
    }

    public static let clipboardClearOptions: [Int] = [0, 30, 60, 120]
    public static let defaultClipboardClearSeconds = 60

    public static var defaults: UserDefaults { AppGroup.defaults }

    /// Seconds after which a copied code is removed from the clipboard (0 = never).
    public static var clipboardClearSeconds: Int {
        get {
            guard defaults.object(forKey: Keys.clipboardClearSeconds) != nil else { return defaultClipboardClearSeconds }
            return defaults.integer(forKey: Keys.clipboardClearSeconds)
        }
        set { defaults.set(newValue, forKey: Keys.clipboardClearSeconds) }
    }

    public static var appLockEnabled: Bool {
        get { defaults.bool(forKey: Keys.appLockEnabled) }
        set { defaults.set(newValue, forKey: Keys.appLockEnabled) }
    }
}

public enum ClipboardManager {
    /// Copies `value`, scheduling removal after `clearAfter` seconds (defaults to the user preference).
    @MainActor
    public static func copy(_ value: String, clearAfter: Int = AppPreferences.clipboardClearSeconds) {
        #if canImport(UIKit)
        var options: [UIPasteboard.OptionsKey: Any] = [:]
        if let expiry = expirationDate(clearAfter: clearAfter) {
            options[.expirationDate] = expiry
        }
        UIPasteboard.general.setItems([[UTType.plainText.identifier: value]], options: options)
        #elseif canImport(AppKit)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
        // Tell clipboard managers not to record the code
        pasteboard.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
        let changeCount = pasteboard.changeCount
        if clearAfter > 0 {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(clearAfter))
                if shouldClear(currentChangeCount: pasteboard.changeCount, copiedChangeCount: changeCount) {
                    pasteboard.clearContents()
                }
            }
        }
        #endif
    }

    /// Expiry date for a copy made at `now`, or `nil` when auto-clear is off.
    public static func expirationDate(clearAfter: Int, now: Date = .now) -> Date? {
        clearAfter > 0 ? now.addingTimeInterval(TimeInterval(clearAfter)) : nil
    }

    /// Only clear when nothing else has been copied since (don't wipe the user's own clipboard).
    public static func shouldClear(currentChangeCount: Int, copiedChangeCount: Int) -> Bool {
        currentChangeCount == copiedChangeCount
    }
}
