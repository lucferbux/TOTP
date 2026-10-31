//
//  TipJarTests.swift
//  TOTPTests
//
//  Uses StoreKit's test store with StoreKit/Tips.storekit. A successful purchase needs sandbox from
//  TestFlight: it returns an unknown error in the test store, even when signed.
//

import Foundation
import StoreKit
import StoreKitTest
import Testing
@testable import TOTP

@MainActor
@Suite(.serialized)
struct TipJarTests {
    private func makeSession() throws -> SKTestSession {
        let url = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "StoreKit/Tips.storekit")
        let session = try SKTestSession(contentsOf: url)
        session.disableDialogs = true
        session.clearTransactions()
        return session
    }

    @Test func loadsEveryTipCheapestFirst() async throws {
        let session = try makeSession()
        defer { _ = session }
        let jar = TipJarManager()
        await jar.load()
        #expect(jar.state == .ready)
        #expect(jar.products.map(\.id) == TipJarManager.productIDs)
    }

    @Test func reportsAFailedPurchase() async throws {
        let session = try makeSession()
        defer { _ = session }
        let jar = TipJarManager()
        await jar.load()
        let product = try #require(jar.products.first)
        await jar.buy(product) { _ in throw StoreKitError.networkError(URLError(.notConnectedToInternet)) }
        #expect(jar.failed)
        #expect(!jar.thanked)
    }
}
