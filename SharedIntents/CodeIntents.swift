//
//  CodeIntents.swift
//  SharedIntents (app + widget)
//
//  Shortcuts / Siri / Spotlight / widget / Control actions.
//

import AppIntents
import Foundation
import WidgetKit

/// Returns the full value (prefix + code) so Shortcuts can paste or type it.
struct GetCodeIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Code"
    static let description = IntentDescription("Returns the current code for an account, including its fixed prefix.")

    @Parameter(title: "Account")
    var account: AccountEntity

    init() {}

    init(account: AccountEntity) {
        self.account = account
    }

    static var parameterSummary: some ParameterSummary {
        Summary("Get code for \(\.$account)")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        guard let model = AccountQuery.model(for: account) else { throw AccountIntentError.accountNotFound }
        return .result(value: model.autoFillValue())
    }
}

/// Copies the full value (prefix + code) to the clipboard. Used by Siri, widgets and the Control.
struct CopyCodeIntent: AppIntent {
    static let title: LocalizedStringResource = "Copy Code"
    static let description = IntentDescription("Copies the current code for an account, including its fixed prefix, to the clipboard.")

    @Parameter(title: "Account")
    var account: AccountEntity

    init() {}

    init(account: AccountEntity) {
        self.account = account
    }

    static var parameterSummary: some ParameterSummary {
        Summary("Copy code for \(\.$account)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let model = AccountQuery.model(for: account) else { throw AccountIntentError.accountNotFound }
        await ClipboardManager.copy(model.autoFillValue())
        return .result(dialog: "Copied the code for \(model.displayTitle).")
    }
}
