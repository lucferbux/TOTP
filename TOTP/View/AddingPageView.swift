import Foundation
import SwiftUI

public struct AddingPageView: View {
    @Binding public var accounts: [OtpModel]
    @Binding public var addingAccount: Bool
    @State private var issuer: String = ""
    @State private var name: String = ""
    @State private var key: String = ""
    @State private var digits = 6
    @State private var interval = 30
    @State private var counter = 0
    @State private var isHotp = false
    @State private var numberFormatter: NumberFormatter = {
        var formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = " "
        return formatter
    }()

    public var body: some View {
        NavigationView {
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
                } header: {
                    Text("Account Information")
                }

                Section {
                    Button("Add Account") {
                        let issuer = self.issuer.trimmingCharacters(in: .whitespacesAndNewlines)
                        let name = self.name.trimmingCharacters(in: .whitespacesAndNewlines)
                        var entry: OtpEntry
                        if self.isHotp {
                            entry = .hotp(
                                key: self.key.trimmingCharacters(in: .whitespacesAndNewlines).data(
                                    using: .utf8)!,
                                digits: self.digits,
                                counter: UInt64(self.counter)
                            )
                        } else {
                            entry = .totp(
                                key: self.key.trimmingCharacters(in: .whitespacesAndNewlines).data(
                                    using: .utf8)!,
                                digits: self.digits,
                                interval: Double(self.interval)
                            )
                        }
                        withAnimation(.easeInOut(duration: 0.3)) {
                            self.accounts.append(
                                OtpModel(
                                    issuer: issuer.isEmpty ? nil : issuer,
                                    name: name.isEmpty ? nil : name,
                                    entry: entry
                                ))
                        }
                        self.addingAccount = false
                    }
                    .disabled(key.isEmpty || interval < 1 || digits < 6 || digits > 10)

                    Button("Cancel", role: .cancel) {
                        self.addingAccount = false
                    }
                }
            }
            .navigationTitle("Add Account")
        }
    }
}
