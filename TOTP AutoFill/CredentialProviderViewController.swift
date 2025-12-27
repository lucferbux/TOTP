//
//  CredentialProviderViewController.swift
//  TOTP AutoFill
//
//  Credential Provider extension for TOTP AutoFill functionality
//

import AuthenticationServices
import SwiftUI
import CryptoKit
import Combine

// MARK: - Embedded Models (for extension independence)

/// OTP Entry type for the extension
enum OtpEntry: Hashable {
    case hotp(key: Data, digits: Int, counter: UInt64)
    case totp(key: Data, digits: Int, interval: Double)
    
    mutating func code() -> UInt64 {
        switch self {
        case let .hotp(key, digits, counter):
            let code = hotpCode(key: key, digits: digits, counter: counter)
            self = .hotp(key: key, digits: digits, counter: counter + 1)
            return code
        case let .totp(key, digits, interval):
            let counter = UInt64(Date().timeIntervalSince1970 / interval)
            return hotpCode(key: key, digits: digits, counter: counter)
        }
    }
    
    func get_display_value() -> Int {
        switch self {
        case let .hotp(_, _, counter):
            return Int(counter)
        case let .totp(_, _, interval):
            let time = Date().timeIntervalSince1970
            let nextUpdate = Double(ceil(time / interval) * interval)
            return Int((nextUpdate - time).rounded())
        }
    }
}

/// HOTP code generation (RFC 4226)
func hotpCode(key: Data, digits: Int, counter: UInt64) -> UInt64 {
    var counter = counter.bigEndian
    let counterData = Data(bytes: &counter, count: MemoryLayout<UInt64>.size)
    
    let hmacKey = SymmetricKey(data: key)
    var hmac = HMAC<Insecure.SHA1>(key: hmacKey)
    hmac.update(data: counterData)
    let hmacResult = Data(hmac.finalize())
    
    let offset = Int(hmacResult[hmacResult.count - 1] & 0x0f)
    let truncatedHash = hmacResult.withUnsafeBytes { ptr -> UInt32 in
        let bytes = ptr.baseAddress!.advanced(by: offset).assumingMemoryBound(to: UInt8.self)
        return UInt32(bytes[0] & 0x7f) << 24 |
               UInt32(bytes[1]) << 16 |
               UInt32(bytes[2]) << 8 |
               UInt32(bytes[3])
    }
    
    var mod: UInt32 = 1
    for _ in 0..<digits {
        mod *= 10
    }
    
    return UInt64(truncatedHash % mod)
}

/// OTP Model for the extension
struct OtpModel: Identifiable, Hashable {
    static func == (lhs: OtpModel, rhs: OtpModel) -> Bool {
        lhs.id == rhs.id || (lhs.issuer == rhs.issuer && lhs.name == rhs.name && lhs.entry == rhs.entry && lhs.prefix == rhs.prefix)
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(issuer)
        hasher.combine(name)
        hasher.combine(prefix)
        hasher.combine(entry)
    }
    
    let id: UUID
    var issuer: String?
    var name: String?
    var prefix: String?
    var entry: OtpEntry
    var associatedDomains: [String]?
    
    var recordIdentifier: String {
        id.uuidString
    }
    
    init(id: UUID = UUID(), issuer: String? = nil, name: String? = nil, prefix: String? = nil, entry: OtpEntry, associatedDomains: [String]? = nil) {
        self.id = id
        self.issuer = issuer
        self.name = name
        self.prefix = prefix
        self.entry = entry
        self.associatedDomains = associatedDomains
    }
    
    func generateCode() -> String {
        var entryCopy = entry
        let code = entryCopy.code()
        let digits: Int
        switch entry {
        case .hotp(_, let d, _), .totp(_, let d, _):
            digits = d
        }
        return String(format: "%0\(digits)d", Int(code))
    }
    
    func generateAutoFillValue() -> String {
        let code = generateCode()
        if let prefix = prefix, !prefix.isEmpty {
            return prefix + code
        }
        return code
    }
}

// MARK: - Credential Provider View Controller

@available(iOS 26.0, *)
class CredentialProviderViewController: ASCredentialProviderViewController {
    
    // MARK: - Properties
    
    private var accounts: [OtpModel] = []
    private var hasShownUI = false
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        loadAccounts()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // If no specific method was called, show selection UI
        if !hasShownUI {
            showAccountSelectionUI(serviceIdentifiers: [])
        }
    }
    
    // MARK: - ASCredentialProviderViewController Methods
    
    /// Called when user interaction is required - show account selection UI
    override func prepareCredentialList(for serviceIdentifiers: [ASCredentialServiceIdentifier]) {
        hasShownUI = true
        showAccountSelectionUI(serviceIdentifiers: serviceIdentifiers)
    }
    
    /// Called to provide credential without showing UI
    override func provideCredentialWithoutUserInteraction(for credentialRequest: any ASCredentialRequest) {
        // Handle one-time code requests
        if let otpRequest = credentialRequest as? ASOneTimeCodeCredentialRequest,
           let identity = otpRequest.credentialIdentity as? ASOneTimeCodeCredentialIdentity {
            let recordIdentifier = identity.recordIdentifier ?? ""
            
            guard let account = accounts.first(where: { $0.recordIdentifier == recordIdentifier }) else {
                extensionContext.cancelRequest(withError: ASExtensionError(.userInteractionRequired))
                return
            }
            
            let code = account.generateAutoFillValue()
            let credential = ASOneTimeCodeCredential(code: code)
            extensionContext.completeOneTimeCodeRequest(using: credential)
            return
        }
        
        // Handle password requests
        if let passwordRequest = credentialRequest as? ASPasswordCredentialRequest,
           let identity = passwordRequest.credentialIdentity as? ASPasswordCredentialIdentity {
            let recordIdentifier = identity.recordIdentifier ?? ""
            
            guard let account = accounts.first(where: { $0.recordIdentifier == recordIdentifier }) else {
                extensionContext.cancelRequest(withError: ASExtensionError(.userInteractionRequired))
                return
            }
            
            let password = account.generateAutoFillValue()
            let userName = account.name ?? account.issuer ?? "Account"
            let credential = ASPasswordCredential(user: userName, password: password)
            extensionContext.completeRequest(withSelectedCredential: credential, completionHandler: nil)
            return
        }
        
        // Fallback - require user interaction
        extensionContext.cancelRequest(withError: ASExtensionError(.userInteractionRequired))
    }
    
    /// Called to prepare UI for credential selection
    override func prepareInterface(forPasskeyRegistration registrationRequest: any ASCredentialRequest) {
        // Not supporting passkeys, show regular selection
        hasShownUI = true
        showAccountSelectionUI(serviceIdentifiers: [])
    }
    
    /// Called when user selects to configure the extension
    override func prepareInterfaceForExtensionConfiguration() {
        hasShownUI = true
        // Show configuration UI directing users to main app
        let configView = ConfigurationView(
            onDismiss: { [weak self] in
                self?.extensionContext.cancelRequest(withError: ASExtensionError(.userCanceled))
            }
        )
        
        let hostingController = UIHostingController(rootView: configView)
        addChild(hostingController)
        view.addSubview(hostingController.view)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        hostingController.didMove(toParent: self)
    }
    
    // MARK: - Private Methods
    
    private func loadAccounts() {
        accounts = SharedDataLoader.loadAccounts()
    }
    
    private func showAccountSelectionUI(serviceIdentifiers: [ASCredentialServiceIdentifier]) {
        loadAccounts()
        
        // Filter accounts by service identifiers if provided
        var filteredAccounts = accounts
        if !serviceIdentifiers.isEmpty {
            let domains = serviceIdentifiers.map { $0.identifier.lowercased() }
            filteredAccounts = accounts.filter { account in
                guard let accountDomains = account.associatedDomains else { return true }
                return accountDomains.contains { domain in
                    domains.contains { $0.contains(domain.lowercased()) || domain.lowercased().contains($0) }
                }
            }
            // If no matches found, show all accounts
            if filteredAccounts.isEmpty {
                filteredAccounts = accounts
            }
        }
        
        let selectionView = OTPSelectionView(
            accounts: filteredAccounts,
            onSelect: { [weak self] account in
                self?.provideCredential(for: account)
            },
            onCancel: { [weak self] in
                self?.extensionContext.cancelRequest(withError: ASExtensionError(.userCanceled))
            }
        )
        
        let hostingController = UIHostingController(rootView: selectionView)
        addChild(hostingController)
        view.addSubview(hostingController.view)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        hostingController.didMove(toParent: self)
    }
    
    private func provideCredential(for account: OtpModel) {
        let code = account.generateAutoFillValue()
        let credential = ASOneTimeCodeCredential(code: code)
        extensionContext.completeOneTimeCodeRequest(using: credential)
    }
}

// MARK: - Shared Data Loader

/// Loads accounts from App Group shared storage
struct SharedDataLoader {
    private static let suiteName = "group.com.lucferbux.TOTP"
    private static let accountsKey = "stored_totp_accounts"
    private static let keyFileName = ".totp-encryption-key"
    
    static func loadAccounts() -> [OtpModel] {
        guard let userDefaults = UserDefaults(suiteName: suiteName),
              let data = userDefaults.data(forKey: accountsKey),
              let encryptionKey = getEncryptionKey() else {
            return []
        }
        
        do {
            let decoder = JSONDecoder()
            let storedAccounts = try decoder.decode([StoredOtpAccount].self, from: data)
            
            return storedAccounts.compactMap { storedAccount -> OtpModel? in
                do {
                    let decryptedKey = try decryptData(storedAccount.encryptedKey, using: encryptionKey)
                    
                    let entry: OtpEntry
                    if storedAccount.isHotp {
                        entry = .hotp(key: decryptedKey, digits: storedAccount.digits, counter: UInt64(max(0, storedAccount.counter)))
                    } else {
                        entry = .totp(key: decryptedKey, digits: storedAccount.digits, interval: storedAccount.interval)
                    }
                    
                    let accountId = UUID(uuidString: storedAccount.id) ?? UUID()
                    
                    return OtpModel(
                        id: accountId,
                        issuer: storedAccount.issuer,
                        name: storedAccount.name,
                        prefix: storedAccount.prefix,
                        entry: entry,
                        associatedDomains: storedAccount.associatedDomains
                    )
                } catch {
                    return nil
                }
            }
        } catch {
            return []
        }
    }
    
    private static func getEncryptionKey() -> SymmetricKey? {
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: suiteName) else {
            return nil
        }
        
        let keyFileURL = containerURL.appendingPathComponent(keyFileName)
        
        do {
            let keyData = try Data(contentsOf: keyFileURL)
            return SymmetricKey(data: keyData)
        } catch {
            return nil
        }
    }
    
    private static func decryptData(_ encryptedData: Data, using key: SymmetricKey) throws -> Data {
        let sealedBox = try ChaChaPoly.SealedBox(combined: encryptedData)
        return try ChaChaPoly.open(sealedBox, using: key)
    }
}

// MARK: - Storage Model (mirrors SharedDataManager)

private struct StoredOtpAccount: Codable {
    let id: String
    let issuer: String?
    let name: String?
    let prefix: String?
    let encryptedKey: Data
    let isHotp: Bool
    let digits: Int
    let interval: Double
    let counter: Int64
    let createdDate: Date
    let modifiedDate: Date
    let associatedDomains: [String]?
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        issuer = try container.decodeIfPresent(String.self, forKey: .issuer)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        prefix = try container.decodeIfPresent(String.self, forKey: .prefix)
        encryptedKey = try container.decode(Data.self, forKey: .encryptedKey)
        isHotp = try container.decode(Bool.self, forKey: .isHotp)
        digits = try container.decode(Int.self, forKey: .digits)
        interval = try container.decode(Double.self, forKey: .interval)
        counter = try container.decode(Int64.self, forKey: .counter)
        createdDate = try container.decode(Date.self, forKey: .createdDate)
        modifiedDate = try container.decode(Date.self, forKey: .modifiedDate)
        associatedDomains = try container.decodeIfPresent([String].self, forKey: .associatedDomains)
    }
}

// MARK: - Configuration View

@available(iOS 26.0, *)
struct ConfigurationView: View {
    let onDismiss: () -> Void
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()
                
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(Color.accentColor)
                    .symbolEffect(.pulse.byLayer, options: .repeating)
                
                Text("TOTP AutoFill")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("Manage your accounts in the TOTP app. Accounts will automatically appear here for AutoFill.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                
                Spacer()
                
                Button(action: onDismiss) {
                    Text("Done")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
