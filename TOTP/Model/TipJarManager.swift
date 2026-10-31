//
//  TipJarManager.swift
//  TOTP
//
//  "Buy Me a Coffee": consumable in-app purchases that unlock nothing (App Review 3.1.1).
//  Product ids live here, in StoreKit/Tips.storekit and in App Store Connect (`fastlane tips`).
//

import Foundation
import StoreKit
import os

@MainActor
final class TipJarManager: ObservableObject {
    enum State: Equatable {
        case loading
        /// The App Store has no products to offer, so the screen says so instead of showing buttons.
        case unavailable
        case ready
    }

    static let productIDs = [
        "com.lucferbux.TOTP.tip.small",
        "com.lucferbux.TOTP.tip.medium",
        "com.lucferbux.TOTP.tip.large",
    ]

    private static let logger = Logger(subsystem: "com.lucferbux.TOTP", category: "TipJar")

    @Published private(set) var state = State.loading
    @Published private(set) var products: [Product] = []
    @Published private(set) var purchasing: Product.ID?
    @Published var thanked = false
    @Published private(set) var failed = false

    func load() async {
        do {
            let found = try await Product.products(for: Self.productIDs)
            products = found.sorted { $0.price < $1.price }
            state = products.isEmpty ? .unavailable : .ready
        } catch {
            Self.logger.error("Couldn't load the tips: \(error.localizedDescription, privacy: .public)")
            state = .unavailable
        }
    }

    /// `purchase` is SwiftUI's `purchase` environment action, which shows the sheet in this window:
    /// iPad and iPhone Duo can have more than one scene.
    func buy(_ product: Product, using purchase: (Product) async throws -> Product.PurchaseResult) async {
        purchasing = product.id
        failed = false
        defer { purchasing = nil }
        do {
            switch try await purchase(product) {
            case .success(let result):
                await settle(result)
            case .pending, .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            Self.logger.error("Tip purchase failed: \(error.localizedDescription, privacy: .public)")
            failed = true
        }
    }

    /// Finishes purchases that complete away from this screen, such as one awaiting a parent's
    /// approval, or StoreKit keeps redelivering them. Touch it at launch; one listener per process,
    /// however many windows there are.
    static let pendingTransactionListener = Task.detached {
        for await update in Transaction.updates {
            if case .verified(let transaction) = update {
                await transaction.finish()
            }
        }
    }

    private func settle(_ result: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = result else {
            failed = true
            return
        }
        await transaction.finish()
        thanked = true
    }
}
