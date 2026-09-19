//
//  TOTPShortcuts.swift
//  TOTP
//
//  Siri / Shortcuts / Spotlight phrases (app target only).
//

import AppIntents

struct TOTPShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CopyCodeIntent(),
            phrases: [
                "Copy my \(.applicationName) code for \(\.$account)",
                "Copy \(\.$account) code with \(.applicationName)",
                "Copy my \(.applicationName) code"
            ],
            shortTitle: "Copy Code",
            systemImageName: "doc.on.doc"
        )
        AppShortcut(
            intent: GetCodeIntent(),
            phrases: [
                "Get my \(.applicationName) code for \(\.$account)",
                "Get \(\.$account) code from \(.applicationName)"
            ],
            shortTitle: "Get Code",
            systemImageName: "number"
        )
    }

    static let shortcutTileColor: ShortcutTileColor = .blue
}
