//
//  TipJarView.swift
//  TOTP
//
//  "Buy Me a Coffee", pushed from Settings.
//

import StoreKit
import SwiftUI

struct TipJarView: View {
    @StateObject private var jar = TipJarManager()
    @Environment(\.purchase) private var purchase

    var body: some View {
        Form {
            Section {
                Text("TOTP Password has no ads, no tracking and no subscription. If it saves you time, a coffee helps keep it that way.")
            } footer: {
                Text("A one-time, voluntary payment handled by Apple. It unlocks nothing.")
            }
            Section {
                content
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Buy Me a Coffee")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { await jar.load() }
        .alert("Thank You!", isPresented: $jar.thanked) {
            Button("You're Welcome", role: .confirm) {}
        } message: {
            Text("Enjoy your codes. This coffee is on you.")
        }
    }

    @ViewBuilder
    private var content: some View {
        #if DEBUG
        // Store products don't load in a screenshot run, which has no StoreKit configuration.
        if UserDefaults.standard.bool(forKey: "ScreenshotTips") {
            TipRow(title: "A Coffee", detail: "A small thank you", price: "0,99 €", isBusy: false) {}
            TipRow(title: "A Large Coffee", detail: "For a long night of fixes", price: "2,99 €", isBusy: false) {}
            TipRow(title: "A Week of Coffee", detail: "For the next big update", price: "4,99 €", isBusy: false) {}
        } else {
            liveContent
        }
        #else
        liveContent
        #endif
    }

    @ViewBuilder
    private var liveContent: some View {
        switch jar.state {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity)
        case .unavailable:
            Label("Coffee isn't available right now.", systemImage: "exclamationmark.circle")
                .foregroundStyle(.secondary)
        case .ready:
            ForEach(jar.products) { product in
                TipRow(title: product.displayName, detail: product.description, price: product.displayPrice, isBusy: jar.purchasing == product.id) {
                    Task { await jar.buy(product) { try await purchase($0) } }
                }
                .disabled(jar.purchasing != nil)
                .accessibilityIdentifier("tip-\(product.id)")
            }
            if jar.failed {
                Label("The payment couldn't be completed.", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
        }
    }
}

private struct TipRow: View {
    var title: String
    var detail: String
    var price: String
    var isBusy: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .foregroundStyle(.primary)
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isBusy {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text(price)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    NavigationStack {
        TipJarView()
    }
}
