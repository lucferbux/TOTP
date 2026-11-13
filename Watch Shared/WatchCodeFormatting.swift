//
//  WatchCodeFormatting.swift
//  Watch Shared (watch app + watch complication)
//

import Foundation

extension String {
    /// The code with every digit masked, keeping its grouping: "123456" → "••• •••".
    /// Shown in always-on mode, when anyone glancing at the wrist could read it.
    var maskedOTP: String {
        String(repeating: "•", count: count).groupedOTP
    }

    /// Digits read one by one by VoiceOver: "123456" → "1 2 3 4 5 6".
    var spokenOTP: String {
        map(String.init).joined(separator: " ")
    }
}
