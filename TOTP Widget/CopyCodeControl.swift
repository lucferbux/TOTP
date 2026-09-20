//
//  CopyCodeControl.swift
//  TOTP Widget
//
//  Control Center / Lock Screen / Action button control that copies an account's
//  full value (prefix + code) in one tap.
//

import AppIntents
import SwiftUI
import WidgetKit

// Controls (Control Center / Lock Screen / Action button) don't exist on visionOS.
#if !os(visionOS)

struct CopyCodeControl: ControlWidget {
    static let kind = "com.lucferbux.TOTP.CopyCodeControl"

    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(kind: Self.kind, provider: Provider()) { value in
            ControlWidgetButton(action: CopyControlCodeIntent(accountID: value.accountID)) {
                Label(value.title, systemImage: "key.viewfinder")
            }
        }
        .displayName("Copy Code")
        .description("Copies an account's code, including any fixed prefix.")
        .promptsForUserConfiguration()
    }

    struct Value {
        var accountID: String?
        var title: String
    }

    struct Provider: AppIntentControlValueProvider {
        func previewValue(configuration: CopyCodeControlConfiguration) -> Value {
            Value(accountID: configuration.account?.id.uuidString, title: configuration.account?.issuer ?? String(localized: "Copy Code"))
        }

        func currentValue(configuration: CopyCodeControlConfiguration) async throws -> Value {
            previewValue(configuration: configuration)
        }
    }
}

struct CopyCodeControlConfiguration: ControlConfigurationIntent {
    static let title: LocalizedStringResource = "Copy Code"

    @Parameter(title: "Account")
    var account: AccountEntity?
}

/// Control action. Falls back to the first account when none (or a deleted one) is configured.
struct CopyControlCodeIntent: AppIntent {
    static let title: LocalizedStringResource = "Copy Code"
    static let isDiscoverable = false


    @Parameter(title: "Account ID")
    var accountID: String?

    init() {}

    init(accountID: String?) {
        self.accountID = accountID
    }

    func perform() async throws -> some IntentResult {
        // The Control is reachable from the Lock Screen; honour the app lock there too.
        try await IntentAuthentication.requireIfLocked()
        let models = AccountQuery.models()
        let model = models.first { $0.id.uuidString == accountID } ?? models.first
        guard let model else { throw AccountIntentError.accountNotFound }
        await ClipboardManager.copy(model.autoFillValue())
        return .result()
    }
}
#endif
