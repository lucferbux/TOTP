import Foundation
import SwiftUI
import CloudKit

@available(iOS 26.0, macOS 26.0, *)
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
                    VStack(spacing: 12) {
                        ProgressView()
                            .scaleEffect(1.3)
                            .tint(.blue)
                        Text("Saving Account...")
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
    private func addAccount() async {
        isSaving = true
        defer { isSaving = false }
        
        do {
            let issuer = self.issuer.trimmingCharacters(in: .whitespacesAndNewlines)
            let name = self.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let prefix = self.prefix.trimmingCharacters(in: .whitespacesAndNewlines)
            let secretKeyString = self.key.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Use Base32 decoding for the key
            // Ensure Data+Base32.swift is added to the target for this to compile
            guard let keyData = Data(base32Encoded: secretKeyString) else {
                errorMessage = "Invalid OTP Key. Please ensure it is a valid Base32 encoded string. It may also be too short or contain invalid characters."
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
            withAnimation(.smooth(duration: 0.3)) {
                self.accounts.append(otpModel)
            }
            
            self.addingAccount = false
            
        } catch {
            errorMessage = "Failed to save account: \(error.localizedDescription)"
            showingError = true
        }
    }
}
