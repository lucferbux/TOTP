//
//  OtpAuthURL.swift
//  Shared
//
//  Parser/builder for the de-facto `otpauth://` Key URI format
//  otpauth://TYPE/LABEL?secret=…&issuer=…&algorithm=…&digits=…&period=…&counter=…
//

import Foundation

public struct OtpAuthURL: Equatable, Sendable {
    public enum ParseError: LocalizedError, Equatable {
        case notOtpAuth
        case unsupportedType
        case missingSecret
        case invalidSecret
        case invalidParameter(String)

        public var errorDescription: String? {
            switch self {
            case .notOtpAuth: String(localized: "This isn't an otpauth:// link or QR code.")
            case .unsupportedType: String(localized: "Only TOTP and HOTP codes are supported.")
            case .missingSecret: String(localized: "The link has no secret.")
            case .invalidSecret: String(localized: "The secret isn't valid Base32.")
            case .invalidParameter(let name): String(localized: "The “\(name)” value isn't valid.")
            }
        }
    }

    public var issuer: String?
    public var name: String?
    public var entry: OtpEntry

    public init(issuer: String?, name: String?, entry: OtpEntry) {
        self.issuer = issuer
        self.name = name
        self.entry = entry
    }

    public init(string: String) throws {
        guard let url = URL(string: string.trimmingCharacters(in: .whitespacesAndNewlines)) else { throw ParseError.notOtpAuth }
        try self.init(url: url)
    }

    public init(url: URL) throws {
        guard url.scheme?.lowercased() == "otpauth",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw ParseError.notOtpAuth
        }
        let type = (components.host ?? "").lowercased()
        guard type == "totp" || type == "hotp" else { throw ParseError.unsupportedType }

        var query: [String: String] = [:]
        for item in components.queryItems ?? [] {
            query[item.name.lowercased()] = item.value ?? ""
        }

        guard let secretString = query["secret"], !secretString.isEmpty else { throw ParseError.missingSecret }
        guard let secret = Data(base32Encoded: secretString) else { throw ParseError.invalidSecret }

        // Label: "Issuer:account" or "account" (path is already percent-decoded)
        var label = components.path
        if label.hasPrefix("/") { label.removeFirst() }
        var labelIssuer: String?
        var accountName: String?
        if let colon = label.firstIndex(of: ":") {
            labelIssuer = String(label[..<colon]).trimmingCharacters(in: .whitespaces)
            accountName = String(label[label.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
        } else if !label.isEmpty {
            accountName = label.trimmingCharacters(in: .whitespaces)
        }

        let issuer = (query["issuer"].flatMap { $0.isEmpty ? nil : $0 }) ?? labelIssuer
        self.issuer = issuer?.isEmpty == true ? nil : issuer
        self.name = accountName?.isEmpty == true ? nil : accountName

        var algorithm = OtpAlgorithm.sha1
        if let value = query["algorithm"] {
            guard let parsed = OtpAlgorithm(lenient: value) else { throw ParseError.invalidParameter("algorithm") }
            algorithm = parsed
        }

        var digits = 6
        if let value = query["digits"] {
            guard let parsed = Int(value), (6...10).contains(parsed) else { throw ParseError.invalidParameter("digits") }
            digits = parsed
        }

        if type == "hotp" {
            guard let value = query["counter"], let counter = UInt64(value) else { throw ParseError.invalidParameter("counter") }
            entry = .hotp(key: secret, digits: digits, counter: counter, algorithm: algorithm)
        } else {
            var period = 30.0
            if let value = query["period"] {
                guard let parsed = Double(value), parsed >= 1, parsed <= 300 else { throw ParseError.invalidParameter("period") }
                period = parsed
            }
            entry = .totp(key: secret, digits: digits, interval: period, algorithm: algorithm)
        }
    }

    /// Serialises back to an otpauth:// URL (used for round-trip tests and future export).
    /// `nil` only if the label can't be represented in a URL.
    public var url: URL? {
        var components = URLComponents()
        components.scheme = "otpauth"
        components.host = entry.isHotp ? "hotp" : "totp"
        let label = [issuer, name].compactMap { $0 }.joined(separator: ":")
        components.path = "/" + label
        var items = [URLQueryItem(name: "secret", value: entry.key.base32EncodedString())]
        if let issuer { items.append(URLQueryItem(name: "issuer", value: issuer)) }
        items.append(URLQueryItem(name: "algorithm", value: entry.algorithm.rawValue))
        items.append(URLQueryItem(name: "digits", value: String(entry.digits)))
        switch entry {
        case let .totp(_, _, interval, _):
            items.append(URLQueryItem(name: "period", value: String(Int(interval))))
        case let .hotp(_, _, counter, _):
            items.append(URLQueryItem(name: "counter", value: String(counter)))
        }
        components.queryItems = items
        return components.url
    }

    public func makeModel(prefix: String? = nil, associatedDomains: [String]? = nil) -> OtpModel {
        OtpModel(issuer: issuer, name: name, prefix: prefix, entry: entry, associatedDomains: associatedDomains)
    }
}
