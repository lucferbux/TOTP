//
//  OtpModel.swift
//  Shared (app, widget, AutoFill)
//

import Foundation

public struct OtpModel: Identifiable, Hashable, Sendable {
    public let id: UUID
    public var issuer: String?
    public var name: String?
    /// Fixed text typed before the code (e.g. a login PIN). Never displayed in the UI.
    public var prefix: String?
    public var entry: OtpEntry

    /// Associated domains for AutoFill matching (e.g., ["github.com", "www.github.com"])
    public var associatedDomains: [String]?

    /// When the account was last edited (or its HOTP counter used). Sync keeps the later edit, so
    /// this changes only when the account does — never because it was saved or uploaded again.
    public var modifiedDate: Date

    /// Record identifier for ASCredentialIdentityStore
    public var recordIdentifier: String {
        id.uuidString
    }

    public init(id: UUID = UUID(), issuer: String? = nil, name: String? = nil, prefix: String? = nil, entry: OtpEntry, associatedDomains: [String]? = nil, modifiedDate: Date = .now) {
        self.id = id
        self.issuer = issuer
        self.name = name
        self.prefix = prefix
        self.entry = entry
        self.associatedDomains = associatedDomains
        self.modifiedDate = modifiedDate
    }

    // MARK: Display

    public var hasPrefix: Bool {
        !(prefix ?? "").isEmpty
    }

    /// Issuer, falling back to the account name.
    public var displayTitle: String {
        if let issuer, !issuer.isEmpty { return issuer }
        if let name, !name.isEmpty { return name }
        return String(localized: "Account")
    }

    /// Account name when it adds information beyond the title.
    public var displaySubtitle: String? {
        guard let name, !name.isEmpty, name != displayTitle else { return nil }
        return name
    }

    public func matches(search: String) -> Bool {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        return (issuer?.localizedCaseInsensitiveContains(query) ?? false)
            || (name?.localizedCaseInsensitiveContains(query) ?? false)
    }

    /// Whether this account belongs to one of the AutoFill service identifiers (domains or URLs).
    /// Matches exact hosts and subdomains of the account's associated domains, falling back to
    /// the issuer as a pseudo-domain ("Example Corp" → "examplecorp").
    public func matchesAutoFill(serviceIdentifiers: [String]) -> Bool {
        let hosts = serviceIdentifiers.compactMap(Self.host(from:))
        guard !hosts.isEmpty else { return false }
        let domains = (associatedDomains ?? []).compactMap(Self.host(from:))
        if !domains.isEmpty {
            return hosts.contains { host in
                domains.contains { host == $0 || host.hasSuffix("." + $0) || $0.hasSuffix("." + host) }
            }
        }
        guard let issuer = issuer?.lowercased().filter({ $0.isLetter || $0.isNumber }), !issuer.isEmpty else { return false }
        return hosts.contains { host in
            host.split(separator: ".").contains { $0 == issuer }
        }
    }

    static func host(from identifier: String) -> String? {
        let trimmed = identifier.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return nil }
        if let host = URL(string: trimmed)?.host(), !host.isEmpty {
            return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        }
        let bare = trimmed.split(separator: "/").first.map(String.init) ?? trimmed
        return bare.hasPrefix("www.") ? String(bare.dropFirst(4)) : bare
    }

    // MARK: Sync

    /// Same account data, ignoring when it was last modified.
    public func hasSameContent(as other: OtpModel) -> Bool {
        var other = other
        other.modifiedDate = modifiedDate
        return self == other
    }

    /// The copy to keep when two devices disagree about the same account: the later edit wins
    /// (`self` on a tie), except that an HOTP counter never moves backwards — every code below the
    /// higher counter may already have been used. A re-keyed secret starts its own count.
    public static func resolved(_ mine: OtpModel, _ theirs: OtpModel) -> OtpModel {
        var winner = theirs.modifiedDate > mine.modifiedDate ? theirs : mine
        let loser = winner == theirs ? mine : theirs
        if case let .hotp(key, digits, counter, algorithm) = winner.entry,
           loser.entry.key == key, let other = loser.entry.counter, other > counter {
            winner.entry = .hotp(key: key, digits: digits, counter: other, algorithm: algorithm)
        }
        return winner
    }

    // MARK: Codes

    /// Zero-padded code valid at `date`.
    public func code(at date: Date = .now) -> String {
        entry.code(at: date)
    }

    /// The value to paste or AutoFill: prefix (if any) immediately followed by the zero-padded code.
    public func autoFillValue(at date: Date = .now) -> String {
        (prefix ?? "") + code(at: date)
    }
}
