//
//  WatchPayload.swift
//  Shared (app, watch app, watch complication)
//
//  What the iPhone sends to the Apple Watch through WatchConnectivity, and how the watch keeps it.
//
//  The payload carries the bare minimum needed to show a TOTP code: no prefix (PIN), no associated
//  domains, no HOTP accounts (their counters must be advanced and saved by the app), and nothing at
//  all while the app lock is on. On the watch it is sealed with the watch's own device-only key
//  before it touches storage (see `WatchKeyStore` in the watch targets).
//

import Foundation
import CryptoKit

public struct WatchPayload: Codable, Equatable, Sendable {
    /// Bump when the format changes incompatibly; a watch ignores payloads newer than it knows.
    public static let currentVersion = 1
    /// Key of the encoded payload in the WatchConnectivity application context.
    public static let contextKey = "watchPayload"

    public struct Account: Codable, Equatable, Sendable {
        public let id: UUID
        public let issuer: String?
        public let name: String?
        public let secret: Data
        public let digits: Int
        public let interval: Double
        public let algorithm: String
        public let order: Int
    }

    public let version: Int
    /// The app lock is on: the watch shows no codes, and `accounts` is always empty.
    public let isLocked: Bool
    public let accounts: [Account]

    public init(version: Int = WatchPayload.currentVersion, isLocked: Bool, accounts: [Account]) {
        self.version = version
        self.isLocked = isLocked
        self.accounts = isLocked ? [] : accounts
    }

    /// Builds the payload for `accounts`: TOTP only, prefix and domains left out, nothing when locked.
    public init(accounts: [OtpModel], isLocked: Bool) {
        let totp = isLocked ? [] : accounts.filter { !$0.entry.isHotp }
        self.init(isLocked: isLocked, accounts: totp.enumerated().compactMap { index, model in
            guard case let .totp(key, digits, interval, algorithm) = model.entry else { return nil }
            return Account(id: model.id, issuer: model.issuer, name: model.name, secret: key,
                           digits: digits, interval: interval, algorithm: algorithm.rawValue, order: index)
        })
    }

    /// The accounts as models, in the iPhone's order. HOTP can't be expressed, so none come back.
    public func models() -> [OtpModel] {
        guard !isLocked else { return [] }
        return accounts.sorted { $0.order < $1.order }.map { account in
            OtpModel(id: account.id, issuer: account.issuer, name: account.name,
                     entry: .totp(key: account.secret,
                                  digits: min(max(account.digits, 6), 10),
                                  interval: account.interval,
                                  algorithm: OtpAlgorithm(lenient: account.algorithm) ?? .sha1))
        }
    }

    // MARK: Transport

    public func encoded() throws -> Data {
        try JSONEncoder().encode(self)
    }

    public static func decode(_ data: Data) throws -> WatchPayload {
        let payload = try JSONDecoder().decode(WatchPayload.self, from: data)
        guard payload.version <= currentVersion else { throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Unsupported watch payload version")) }
        return payload
    }

    /// The WatchConnectivity application context for this payload.
    public func applicationContext() throws -> [String: Any] {
        [Self.contextKey: try encoded()]
    }

    public static func decode(applicationContext: [String: Any]) throws -> WatchPayload {
        guard let data = applicationContext[contextKey] as? Data else {
            throw DecodingError.valueNotFound(Data.self, .init(codingPath: [], debugDescription: "No watch payload"))
        }
        return try decode(data)
    }
}

/// The watch's copy of the accounts: sealed with the watch key in the (watch) App Group defaults,
/// so the complication extension can read it too.
public enum WatchAccountCache {
    public enum State: Equatable, Sendable {
        /// Nothing received from the iPhone yet.
        case neverSynced
        /// The app lock is on on the iPhone.
        case locked
        case ready([OtpModel])
    }

    static let lockedKey = "watch_app_locked"
    static let syncedKey = "watch_has_synced"

    /// Seals and stores `payload`. With the lock on (or no accounts) every sealed secret is removed.
    public static func store(_ payload: WatchPayload, key: SymmetricKey, in defaults: UserDefaults = AppGroup.defaults) throws {
        let models = payload.models()
        if models.isEmpty {
            defaults.removeObject(forKey: AccountStore.accountsKey)
        } else {
            defaults.set(try AccountStore.encode(models, key: key), forKey: AccountStore.accountsKey)
        }
        defaults.set(payload.isLocked, forKey: lockedKey)
        defaults.set(true, forKey: syncedKey)
    }

    /// Whether anything has been received, and whether it said "locked" — no key needed.
    public static func status(in defaults: UserDefaults = AppGroup.defaults) -> State {
        guard defaults.bool(forKey: syncedKey) else { return .neverSynced }
        return defaults.bool(forKey: lockedKey) ? .locked : .ready([])
    }

    /// Opens the stored accounts. HOTP is filtered again in case anything other than a payload wrote here.
    public static func load(key: SymmetricKey?, from defaults: UserDefaults = AppGroup.defaults) -> State {
        let status = status(in: defaults)
        guard case .ready = status else { return status }
        guard let key else { return .ready([]) }
        return .ready(AccountStore.loadAccounts(from: defaults, key: key).filter { !$0.entry.isHotp })
    }
}
