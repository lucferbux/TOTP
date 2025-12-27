import Foundation
import SwiftUI
import CloudKit

@available(iOS 26.0, macOS 26.0, *)
public struct AddingPageView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var syncManager: SyncManager
    @Binding public var accounts: [OtpModel]
    @Binding public var addingAccount: Bool
    public let dataManager: SharedDataManager
    public var editingAccount: OtpModel?
    
    @State private var issuer: String = ""
    @State private var name: String = ""
    @State private var prefix: String = ""
    @State private var key: String = ""
    @State private var digits = 6
    @State private var interval = 30
    @State private var counter = 0
    @State private var isHotp = false
    @State private var isSaving = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var showKey = false
    @State private var domainsText: String = ""
    @State private var numberFormatter: NumberFormatter = {
        var formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = " "
        return formatter
    }()
    
    private var isEditing: Bool {
        editingAccount != nil
    }
    
    private var navigationTitle: String {
        isEditing ? "Edit Account" : "Add Account"
    }
    
    private var saveButtonTitle: String {
        isEditing ? "Save Changes" : "Add Account"
    }
    
    // Key is always required (pre-filled when editing)
    private var canSave: Bool {
        return !key.isEmpty && interval >= 1 && digits >= 6 && digits <= 10 && !isSaving
    }
    
    public init(accounts: Binding<[OtpModel]>, addingAccount: Binding<Bool>, dataManager: SharedDataManager, editingAccount: OtpModel? = nil) {
        self._accounts = accounts
        self._addingAccount = addingAccount
        self.dataManager = dataManager
        self.editingAccount = editingAccount
        
        // Initialize state from editingAccount if present
        if let account = editingAccount {
            _issuer = State(initialValue: account.issuer ?? "")
            _name = State(initialValue: account.name ?? "")
            _prefix = State(initialValue: account.prefix ?? "")
            
            // Convert stored Data back to String (UTF-8)
            // For accounts created with plain text keys, this will work directly
            // For older accounts with Base32-decoded binary data, show the Base32 encoded version
            let keyData = account.entry.getKey()
            let keyString: String
            if let utf8 = String(data: keyData, encoding: .utf8), 
               !utf8.isEmpty,
               utf8.allSatisfy({ $0.isASCII && !$0.isNewline }) {
                // Valid ASCII string (plain text key)
                keyString = utf8
            } else {
                // Binary data - encode as Base32 for display (fallback for old accounts)
                keyString = keyData.base32EncodedString()
            }
            _key = State(initialValue: keyString)
            
            switch account.entry {
            case .totp(_, let d, let i):
                _isHotp = State(initialValue: false)
                _digits = State(initialValue: d)
                _interval = State(initialValue: Int(i))
                _counter = State(initialValue: 0)
            case .hotp(_, let d, let c):
                _isHotp = State(initialValue: true)
                _digits = State(initialValue: d)
                _counter = State(initialValue: Int(c))
                _interval = State(initialValue: 30)
            }
            
            // Initialize domains text from associated domains
            if let domains = account.associatedDomains, !domains.isEmpty {
                _domainsText = State(initialValue: domains.joined(separator: ", "))
            } else {
                _domainsText = State(initialValue: "")
            }
        } else {
            _issuer = State(initialValue: "")
            _name = State(initialValue: "")
            _prefix = State(initialValue: "")
            _key = State(initialValue: "")
            _digits = State(initialValue: 6)
            _interval = State(initialValue: 30)
            _counter = State(initialValue: 0)
            _isHotp = State(initialValue: false)
            _domainsText = State(initialValue: "")
        }
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Type", selection: $isHotp) {
                        Text("TOTP").tag(false)
                        Text("HOTP").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .disabled(isEditing) // Can't change type when editing

                    HStack {
                        if showKey {
                            TextField("Secret Key", text: $key)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        } else {
                            SecureField("Secret Key", text: $key)
                        }
                        
                        Button(action: {
                            withAnimation(.smooth(duration: 0.2)) {
                                showKey.toggle()
                            }
                        }) {
                            Image(systemName: showKey ? "eye.slash.fill" : "eye.fill")
                                .foregroundStyle(.secondary)
                                .contentTransition(.symbolEffect(.replace))
                        }
                        .buttonStyle(.plain)
                    }

                    if self.isHotp {
                        Stepper("Counter: \(counter)", value: $counter, in: 0...Int.max)
                    } else {
                        Stepper("\(interval) seconds", value: $interval, in: 1...300)
                    }

                    Stepper("\(digits) digits", value: $digits, in: 6...10)
                } header: {
                    Text("OTP Configuration")
                }

                Section {
                    TextField("Issuer", text: $issuer)
                    TextField("Account Name", text: $name)
                    TextField("Prefix (optional)", text: $prefix)
                } header: {
                    Text("Account Information")
                }
                
                Section {
                    TextField("e.g. github.com, example.org", text: $domainsText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("AutoFill Domains")
                } footer: {
                    Text("Enter domains where this code should appear in AutoFill, separated by commas.")
                }
            }
            .navigationTitle(navigationTitle)
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Cancel") {
                            self.addingAccount = false
                            dismiss()
                        }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(saveButtonTitle) {
                            Task {
                                await saveAccount()
                            }
                        }
                        .disabled(!canSave)
                    }
                }
            #elseif os(macOS)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button(saveButtonTitle) {
                            Task {
                                await saveAccount()
                            }
                        }
                        .disabled(!canSave)
                    }
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            self.addingAccount = false
                            dismiss()
                        }
                    }
                }
            #endif
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .alert(isEditing ? "Error Updating Account" : "Error Adding Account", isPresented: $showingError) {
            Button("OK") {}
        } message: {
            Text(errorMessage)
        }
        .overlay {
            if isSaving {
                ZStack {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                    VStack(spacing: 12) {
                        ProgressView()
                            .scaleEffect(1.3)
                            .tint(.blue)
                        Text(isEditing ? "Updating Account..." : "Saving Account...")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                    }
                    .padding(24)
                    .background {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color(.secondarySystemGroupedBackground))
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
        }
        .sensoryFeedback(.success, trigger: accounts.count)
    }
    
    @MainActor
    private func saveAccount() async {
        isSaving = true
        defer { isSaving = false }
        
        do {
            let issuer = self.issuer.trimmingCharacters(in: .whitespacesAndNewlines)
            let name = self.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let prefix = self.prefix.trimmingCharacters(in: .whitespacesAndNewlines)
            let secretKeyString = self.key.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Parse domains from comma-separated text
            let domains: [String]? = {
                let trimmed = domainsText.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty { return nil }
                let parsed = trimmed.split(separator: ",")
                    .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                    .filter { !$0.isEmpty }
                return parsed.isEmpty ? nil : parsed
            }()
            
            // Key is always required (pre-filled when editing)
            guard !secretKeyString.isEmpty else {
                errorMessage = "Secret key cannot be empty."
                showingError = true
                return
            }
            
            // Convert plain text to Data directly (UTF-8 encoding)
            let keyData = Data(secretKeyString.utf8)
            
            let entry: OtpEntry
            if self.isHotp {
                entry = .hotp(
                    key: keyData,
                    digits: self.digits,
                    counter: UInt64(self.counter)
                )
            } else {
                entry = .totp(
                    key: keyData,
                    digits: self.digits,
                    interval: Double(self.interval)
                )
            }
            
            if isEditing, let existingAccount = editingAccount {
                // Create updated model with the same ID
                var updatedModel = existingAccount
                updatedModel.issuer = issuer.isEmpty ? nil : issuer
                updatedModel.name = name.isEmpty ? nil : name
                updatedModel.prefix = prefix.isEmpty ? nil : prefix
                updatedModel.entry = entry
                updatedModel.associatedDomains = domains
                
                print("DEBUG: Updating account with ID: \(existingAccount.id)")
                
                // Update using SyncManager (syncs to both local and cloud)
                try await syncManager.updateAccount(updatedModel)
                
                print("DEBUG: Update completed successfully")
                
                // Update local array for immediate UI feedback
                withAnimation(.smooth(duration: 0.3)) {
                    if let index = self.accounts.firstIndex(where: { $0.id == existingAccount.id }) {
                        self.accounts[index] = updatedModel
                    }
                }
            } else {
                let otpModel = OtpModel(
                    issuer: issuer.isEmpty ? nil : issuer,
                    name: name.isEmpty ? nil : name,
                    prefix: prefix.isEmpty ? nil : prefix,
                    entry: entry,
                    associatedDomains: domains
                )
                
                // Save using SyncManager (syncs to both local and cloud)
                await syncManager.addAccount(otpModel)
                
                // Update local array for immediate UI feedback
                withAnimation(.smooth(duration: 0.3)) {
                    self.accounts.append(otpModel)
                }
            }
            
            // Dismiss the sheet
            self.addingAccount = false
            dismiss()
            
        } catch {
            errorMessage = "Failed to save account: \(error.localizedDescription)"
            showingError = true
        }
    }
}
