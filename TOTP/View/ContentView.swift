import Combine
import CryptoKit
import SwiftUI

#if canImport(UIKit)
    import UIKit
#endif

public struct ContentView: View {
    @Environment(\.colorScheme) var colorScheme
    @State var accounts: [OtpModel] = [
        OtpModel(
            issuer: "Red Hat",
            name: "lferrnan",
            entry: .totp(
                key: Data(base64Encoded: "qo5y1y7LIewn/CFrv7AOPn+UjjQ=")!, digits: 6, interval: 30.0
            )
        )
    ]
    @State var addingAccount = false
    @State var deletingAccount: OtpModel?
    @State var showCopiedToast = false
    @State var search = ""

    public init() {}

    public var body: some View {
        NavigationStack {
            VStack {
                GeometryReader { geometry in
                    ZStack {
                        VStack {
                            ScrollView {
                                let searchField = self.search.trimmingCharacters(
                                    in: .whitespacesAndNewlines)
                                LazyVGrid(
                                    columns: [GridItem(.adaptive(minimum: 250, maximum: 325))],
                                    alignment: .center,
                                    spacing: 7.5
                                ) {
                                    ForEach(
                                        searchField.isEmpty
                                            ? self.accounts
                                            : self.accounts
                                                .filter {
                                                    $0.name?.localizedCaseInsensitiveContains(
                                                        searchField) ?? false
                                                        || $0
                                                            .issuer?
                                                            .localizedCaseInsensitiveContains(
                                                                searchField) ?? false
                                                }
                                    ) { account in
                                        TOtpView(
                                            otp: account,
                                            cutoff: geometry.size.width,
                                            deleting: $deletingAccount,
                                            toast: $showCopiedToast
                                        )
                                        .padding(.horizontal)
                                        .transition(
                                            AnyTransition.asymmetric(
                                                insertion: AnyTransition.move(edge: .leading),
                                                removal: AnyTransition.move(edge: .trailing)
                                            ).combined(with: AnyTransition.opacity)
                                        )
                                    }
                                }
                                .padding(.top)
                                .frame(minWidth: geometry.size.width, maxWidth: geometry.size.width)
                            }
                            VStack(alignment: .center) {
                                Text("Click account to copy the current code to your clipboard.")
                                    .font(.caption)
                                    .fontWeight(.light)
                                    .opacity(0.75)
                                Text("Slide or long press on an account's ball to delete the card.")
                                    .font(.caption)
                                    .fontWeight(.light)
                                    .opacity(0.75)
                            }
                            .multilineTextAlignment(.center)
                        }
                        HStack {
                            Spacer()
                            VStack {
                                Spacer()
                                Text("Code copied to clipboard")
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 12)
                                    .background(
                                        .regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                            }.padding()
                            Spacer()
                        }
                        .opacity(self.showCopiedToast ? 0.9 : 0.0)
                        .allowsHitTesting(false)
                    }
                }
            }
            .navigationTitle("TOTP Passwords")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.large)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(action: {
                            self.addingAccount = true
                        }) {
                            Image(systemName: "plus")
                            .font(.title3)
                        }
                    }
                }
            #elseif os(macOS)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button(action: {
                            self.addingAccount = true
                        }) {
                            Label("Add Account", systemImage: "plus")
                        }
                        .help("Add new TOTP account")
                    }
                }
            #endif
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .alert(item: $deletingAccount) { (item: OtpModel) in
            var alertText: String
            switch (item.issuer, item.name) {
            case let (.some(issuer), .some(name)):
                alertText = "the account \"\(name)\" for \"\(issuer)\""
            case let (.none, .some(name)):
                alertText = "the account \"\(name)\""
            case let (.some(issuer), .none):
                alertText = "the account for \"\(issuer)\""
            case (.none, .none):
                alertText = "this account"
            }
            return Alert(
                title: Text("Confirm Delete"),
                message: Text("Are you sure that you want to DELETE \(alertText)"),
                primaryButton: .destructive(Text("Delete").bold()) {
                    withAnimation(Animation.easeInOut(duration: 1)) {
                        self.accounts.removeAll(where: { $0.id == item.id })
                    }
                },
                secondaryButton: .cancel()
            )
        }
        .sheet(isPresented: $addingAccount) {
            AddingPageView(accounts: $accounts, addingAccount: $addingAccount)
                .preferredColorScheme(self.colorScheme)
        }
    }
}

struct ContentViewPreviewLight: PreviewProvider {
    static var previews: some View {
        ContentView()
            .preferredColorScheme(.light)
    }
}

struct ContentViewPreviewDark: PreviewProvider {
    static var previews: some View {
        ContentView()
            .preferredColorScheme(.dark)
    }
}
