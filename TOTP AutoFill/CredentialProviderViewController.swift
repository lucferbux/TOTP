//
//  CredentialProviderViewController.swift
//  TOTP AutoFill
//
//  Credential Provider extension (iOS, iPadOS and macOS). Fills either a one-time-code field
//  or a password field with prefix + code, which is what PIN + token logins expect.
//

import AuthenticationServices
import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

#if canImport(AppKit)
import AppKit
#endif

class CredentialProviderViewController: ASCredentialProviderViewController {

    /// What the system asked for; decides how a picked account is returned.
    private enum RequestKind {
        case oneTimeCode
        case password
    }

    private var accounts: [OtpModel] = []
    private var hasShownUI = false

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        accounts = AccountStore.loadAccounts()
    }

    #if canImport(UIKit)
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if !hasShownUI {
            showAccountSelectionUI(serviceIdentifiers: [], kind: .oneTimeCode)
        }
    }
    #else
    override func viewDidAppear() {
        super.viewDidAppear()
        if !hasShownUI {
            showAccountSelectionUI(serviceIdentifiers: [], kind: .oneTimeCode)
        }
    }
    #endif

    // MARK: - Lists (user picks an account)

    /// Password fields — the prefix + code is returned as the password.
    override func prepareCredentialList(for serviceIdentifiers: [ASCredentialServiceIdentifier]) {
        showAccountSelectionUI(serviceIdentifiers: serviceIdentifiers, kind: .password)
    }

    /// One-time-code fields.
    override func prepareOneTimeCodeCredentialList(for serviceIdentifiers: [ASCredentialServiceIdentifier]) {
        showAccountSelectionUI(serviceIdentifiers: serviceIdentifiers, kind: .oneTimeCode)
    }

    // MARK: - QuickType bar (identity already chosen)

    override func provideCredentialWithoutUserInteraction(for credentialRequest: any ASCredentialRequest) {
        guard let account = account(for: credentialRequest) else {
            extensionContext.cancelRequest(withError: ASExtensionError(.credentialIdentityNotFound))
            return
        }
        complete(credentialRequest, with: account)
    }

    override func prepareInterfaceToProvideCredential(for credentialRequest: any ASCredentialRequest) {
        hasShownUI = true
        if let account = account(for: credentialRequest) {
            complete(credentialRequest, with: account)
        } else {
            let kind: RequestKind = credentialRequest is ASPasswordCredentialRequest ? .password : .oneTimeCode
            showAccountSelectionUI(serviceIdentifiers: [credentialRequest.credentialIdentity.serviceIdentifier], kind: kind)
        }
    }

    override func prepareInterfaceForExtensionConfiguration() {
        hasShownUI = true
        embedHostingController(rootView: ConfigurationView { [weak self] in
            self?.extensionContext.completeExtensionConfigurationRequest()
        })
    }

    // MARK: - Private

    private func account(for request: any ASCredentialRequest) -> OtpModel? {
        let recordIdentifier = request.credentialIdentity.recordIdentifier ?? ""
        if accounts.isEmpty { accounts = AccountStore.loadAccounts() }
        return accounts.first { $0.recordIdentifier == recordIdentifier }
    }

    private func complete(_ request: any ASCredentialRequest, with account: OtpModel) {
        if request is ASPasswordCredentialRequest {
            complete(.password, with: account)
        } else {
            complete(.oneTimeCode, with: account)
        }
    }

    private func complete(_ kind: RequestKind, with account: OtpModel) {
        let value = account.autoFillValue()
        switch kind {
        case .oneTimeCode:
            extensionContext.completeOneTimeCodeRequest(using: ASOneTimeCodeCredential(code: value))
        case .password:
            let user = account.name ?? account.issuer ?? ""
            extensionContext.completeRequest(withSelectedCredential: ASPasswordCredential(user: user, password: value))
        }
    }

    private func showAccountSelectionUI(serviceIdentifiers: [ASCredentialServiceIdentifier], kind: RequestKind) {
        hasShownUI = true
        accounts = AccountStore.loadAccounts()

        let identifiers = serviceIdentifiers.map(\.identifier)
        let suggested = identifiers.isEmpty ? [] : accounts.filter { $0.matchesAutoFill(serviceIdentifiers: identifiers) }

        let selectionView = OTPSelectionView(
            accounts: accounts,
            suggested: suggested,
            onSelect: { [weak self] account in
                self?.complete(kind, with: account)
            },
            onCancel: { [weak self] in
                self?.extensionContext.cancelRequest(withError: ASExtensionError(.userCanceled))
            }
        )
        embedHostingController(rootView: selectionView)
    }

    /// Embeds a SwiftUI view, replacing any previously embedded one.
    private func embedHostingController<Content: View>(rootView: Content) {
        for child in children {
            child.view.removeFromSuperview()
            child.removeFromParent()
        }
        #if canImport(UIKit)
        let hostingController = UIHostingController(rootView: rootView)
        #else
        let hostingController = NSHostingController(rootView: rootView)
        #endif
        addChild(hostingController)
        view.addSubview(hostingController.view)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        #if canImport(UIKit)
        hostingController.didMove(toParent: self)
        #endif
    }
}

// MARK: - Configuration View

struct ConfigurationView: View {
    let onDone: () -> Void

    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label("TOTP AutoFill Is On", systemImage: "checkmark.shield.fill")
            } description: {
                Text("Codes from the TOTP app, including any fixed prefix, now appear when you sign in. Manage accounts in the TOTP app.")
            } actions: {
                Button("Done", action: onDone)
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
            }
            .navigationTitle("AutoFill")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 320)
        #endif
    }
}
