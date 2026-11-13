//
//  SampleAccounts.swift
//  Shared (app, widget, AutoFill, watch)
//
//  Seed data for UI tests and App Store screenshots, shared by the iPhone/iPad/Mac app and the
//  watch app so every platform's screenshots show the same accounts.
//
//  Fictional names only: real service names and logos belong to their owners and don't belong in
//  our marketing images (App Review 5.2.2). No real people's names or addresses either.
//

import Foundation

public enum SampleAccounts {
    /// Accounts shown in App Store screenshots.
    public static var screenshot: [OtpModel] {
        // A distinct secret per account, so the screenshots don't show five identical codes.
        func account(_ issuer: String, _ name: String, secret: String, prefix: String? = nil, domain: String? = nil) -> OtpModel {
            OtpModel(issuer: issuer, name: name, prefix: prefix,
                     entry: .totp(key: Data(secret.utf8), digits: 6, interval: 30),
                     associatedDomains: domain.map { [$0] })
        }
        return [
            account("Northwind Corp", "you@northwind.example", secret: "12345678901234567890", prefix: "1234", domain: "sso.northwind.example"),
            account("Contoso Cloud", "admin@contoso.example", secret: "abcdefghij1234567890", domain: "login.contoso.example"),
            account("Fabrikam Mail", "you@fabrikam.example", secret: "qrstuvwxyz0987654321"),
            account("Acme Bank", "personal", secret: "0987654321zyxwvutsrq"),
            account("Tailspin Dev", "deploy-bot", secret: "mnopqrstuv5647382910"),
            account("Woodgrove Bank", "you@woodgrove.example", secret: "5647382910mnopqrstuv"),
            account("Proseware VPN", "alex", secret: "vutsrqponm0192837465", prefix: "77"),
            account("Adatum Hosting", "root", secret: "1029384756zyxwvutsrq")
        ]
    }

    /// Deterministic accounts for UI tests (RFC 6238 test secret; no real credentials).
    public static var uiTest: [OtpModel] {
        let rfcSecret = Data("12345678901234567890".utf8)
        return [
            OtpModel(issuer: "Example Corp", name: "user@example.com", prefix: "1234",
                     entry: .totp(key: rfcSecret, digits: 6, interval: 30), associatedDomains: ["sso.example.com"]),
            OtpModel(issuer: "GitHub", name: "octocat", entry: .totp(key: rfcSecret, digits: 6, interval: 30)),
            OtpModel(issuer: "Counter Bank", name: "hotp", entry: .hotp(key: rfcSecret, digits: 6, counter: 0))
        ]
    }
}
