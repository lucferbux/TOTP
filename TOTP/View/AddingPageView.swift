import Foundation
import SwiftUI
import CloudKit

public struct AddingPageView: View {
    @Binding public var accounts: [OtpModel]
    @Binding public var addingAccount: Bool
    public let dataManager: SharedDataManager
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
    @State private var numberFormatter: NumberFormatter = {
        var formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = " "
        return formatter
    }()

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Type", selection: $isHotp) {
                        Text("TOTP").tag(false)
                        Text("HOTP").tag(true)
                    }
                    .pickerStyle(.segmented)

                    SecureField("OTP Key", text: $key)

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
            }
            .navigationTitle("Add Account")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Cancel") {
                            self.addingAccount = false
                        }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Add Account") {
                            Task {
                                await addAccount()
                            }
                        }
                        .disabled(key.isEmpty || interval < 1 || digits < 6 || digits > 10 || isSaving)
                    }
                }
            #elseif os(macOS)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Add Account") {
                            Task {
                                await addAccount()
                            }
                        }
                        .disabled(key.isEmpty || interval < 1 || digits < 6 || digits > 10 || isSaving)
                    }
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            self.addingAccount = false
                        }
                    }
                }
            #endif
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .alert("Error Adding Account", isPresented: $showingError) {
            Button("OK") {}
        } message: {
            Text(errorMessage)
        }
        .overlay {
            if isSaving {
                ZStack {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                    VStack {
                        ProgressView()
                            .scaleEffect(1.2)
                        Text("Saving Account...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.top, 8)
                    }
                    .padding()
                    .background(.regularMaterial)
                    .cornerRadius(12)
                }
            }
        }
    }
    
    @MainActor
    private func addAccount() async {
        isSaving = true
        defer { isSaving = false }
        
        do {
            let issuer = self.issuer.trimmingCharacters(in: .whitespacesAndNewlines)
            let name = self.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let prefix = self.prefix.trimmingCharacters(in: .whitespacesAndNewlines)
            
            guard let keyData = self.key.trimmingCharacters(in: .whitespacesAndNewlines).data(using: .utf8) else {
                errorMessage = "Invalid key format"
                showingError = true
                return
            }
            
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
            
            let otpModel = OtpModel(
                issuer: issuer.isEmpty ? nil : issuer,
                name: name.isEmpty ? nil : name,
                prefix: prefix.isEmpty ? nil : prefix,
                entry: entry
            )
            
            // Save using the data manager
            try await dataManager.saveAccount(otpModel)
            
            // Update local array for immediate UI feedback
            withAnimation(.easeInOut(duration: 0.3)) {
                self.accounts.append(otpModel)
            }
            
            self.addingAccount = false
            
        } catch {
            errorMessage = "Failed to save account: \(error.localizedDescription)"
            showingError = true
        }
    }
}
