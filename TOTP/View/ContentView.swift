import Combine
import CryptoKit
import SwiftUI
import CloudKit

#if canImport(UIKit)
    import UIKit
#endif

public struct ContentView: View {
    @Environment(\.colorScheme) var colorScheme
    @StateObject private var dataManager = SharedDataManager.shared
    @State private var accounts: [OtpModel] = []
    @State var addingAccount = false
    @State var deletingAccount: OtpModel?
    @State var showCopiedToast = false
    @State var search = ""
    @State private var showingErrorAlert = false

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
                            
                            // Loading indicator
                            if dataManager.isLoading {
                                VStack {
                                    ProgressView()
                                        .scaleEffect(1.2)
                                    Text("Loading accounts...")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .padding(.top, 8)
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                            }
                            
                            VStack(alignment: .center) {
                                if self.accounts.isEmpty && !dataManager.isLoading {
                                    Spacer()
                                    VStack(spacing: 20) {
                                        Image(systemName: "lock.shield")
                                            .font(.system(size: 60))
                                            .foregroundColor(.secondary)
                                        VStack(spacing: 8) {
                                            Text("No TOTP accounts")
                                                .font(.title2)
                                                .fontWeight(.semibold)
                                            Text("Add your first account to get started")
                                                .font(.body)
                                                .foregroundColor(.secondary)
                                        }
                                        Button("Add Account") {
                                            self.addingAccount = true
                                        }
                                        .buttonStyle(.borderedProminent)
                                    }
                                    Spacer()
                                } else if !self.accounts.isEmpty {
                                    VStack(spacing: 5) {
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
                }
            }
            .navigationTitle("TOTP Passwords")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.large)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button(action: {
                            dataManager.loadAccounts()
                        }) {
                            Image(systemName: "arrow.clockwise")
                                .font(.title3)
                        }
                        .disabled(dataManager.isLoading)
                    }
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
                    ToolbarItem(placement: .secondaryAction) {
                        Button(action: {
                            dataManager.loadAccounts()
                        }) {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                        .help("Refresh accounts")
                        .disabled(dataManager.isLoading)
                    }
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
        .onAppear {
            self.accounts = dataManager.accounts
        }
        .onReceive(dataManager.$accounts) { newAccounts in
            withAnimation(.easeInOut(duration: 0.3)) {
                self.accounts = newAccounts
            }
        }
        .onReceive(dataManager.$error) { error in
            if error != nil {
                showingErrorAlert = true
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .alert("Data Error", isPresented: $showingErrorAlert) {
            Button("OK") {
                dataManager.error = nil
            }
        } message: {
            Text(dataManager.error?.localizedDescription ?? "An unknown error occurred")
        }
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
                    dataManager.deleteAccount(item)
                    withAnimation(Animation.easeInOut(duration: 1)) {
                        self.accounts.removeAll(where: { $0.id == item.id })
                    }
                },
                secondaryButton: .cancel()
            )
        }
        .sheet(isPresented: $addingAccount) {
            AddingPageView(accounts: $accounts, addingAccount: $addingAccount, dataManager: dataManager)
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
