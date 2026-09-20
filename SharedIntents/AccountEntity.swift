//
//  AccountEntity.swift
//  SharedIntents (app + widget)
//
//  App Intents representation of an account. Exposes only non-secret metadata.
//

import AppIntents
import CoreSpotlight
import Foundation

struct AccountEntity: AppEntity, IndexedEntity, Identifiable, Hashable {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Account")
    static let defaultQuery = AccountQuery()

    let id: UUID

    @Property(title: "Issuer")
    var issuer: String

    @Property(title: "Account Name")
    var accountName: String

    /// Whether a fixed prefix (PIN) is prepended to the code.
    let hasPrefix: Bool

    init(model: OtpModel) {
        id = model.id
        hasPrefix = model.hasPrefix
        issuer = model.displayTitle
        accountName = model.displaySubtitle ?? ""
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(issuer)",
            subtitle: accountName.isEmpty ? nil : "\(accountName)",
            image: .init(systemName: "lock.shield")
        )
    }

    static func == (lhs: AccountEntity, rhs: AccountEntity) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct AccountQuery: EntityStringQuery {
    func entities(for identifiers: [AccountEntity.ID]) async throws -> [AccountEntity] {
        let wanted = Set(identifiers)
        return Self.models().filter { wanted.contains($0.id) }.map(AccountEntity.init(model:))
    }

    func entities(matching string: String) async throws -> [AccountEntity] {
        Self.models().filter { $0.matches(search: string) }.map(AccountEntity.init(model:))
    }

    func suggestedEntities() async throws -> [AccountEntity] {
        Self.models().map(AccountEntity.init(model:))
    }

    /// Accounts eligible for intents, widgets and controls.
    /// HOTP accounts are excluded: generating one outside the app would need to persist the counter.
    static func models() -> [OtpModel] {
        AccountStore.loadAccounts().filter { !$0.entry.isHotp }
    }

    static func model(for entity: AccountEntity) -> OtpModel? {
        models().first { $0.id == entity.id }
    }
}

enum AccountIntentError: Error, CustomLocalizedStringResourceConvertible {
    case accountNotFound
    case authenticationFailed
    case authenticationUnavailable

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .accountNotFound: "That account is no longer available. Open TOTP to check your accounts."
        case .authenticationFailed: "TOTP is locked. Authenticate to use your codes."
        case .authenticationUnavailable: "TOTP is locked and this device can't authenticate right now."
        }
    }
}
