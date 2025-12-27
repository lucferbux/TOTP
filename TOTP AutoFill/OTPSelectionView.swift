//
//  OTPSelectionView.swift
//  TOTP AutoFill
//
//  SwiftUI view for selecting an OTP account during AutoFill
//  Note: Uses OtpModel defined in CredentialProviderViewController.swift
//

import SwiftUI
import Combine

@available(iOS 26.0, *)
struct OTPSelectionView: View {
    let accounts: [OtpModel]
    let onSelect: (OtpModel) -> Void
    let onCancel: () -> Void
    
    @State private var searchText = ""
    
    var filteredAccounts: [OtpModel] {
        if searchText.isEmpty {
            return accounts
        }
        return accounts.filter { account in
            let issuer = account.issuer?.lowercased() ?? ""
            let name = account.name?.lowercased() ?? ""
            let search = searchText.lowercased()
            return issuer.contains(search) || name.contains(search)
        }
    }
    
    var body: some View {
        NavigationStack {
            Group {
                if accounts.isEmpty {
                    emptyStateView
                } else {
                    accountListView
                }
            }
            .navigationTitle("Select Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search accounts")
        }
    }
    
    private var emptyStateView: some View {
        ContentUnavailableView(
            "No Accounts",
            systemImage: "lock.shield",
            description: Text("Add accounts in the TOTP app to use AutoFill.")
        )
    }
    
    private var accountListView: some View {
        List(filteredAccounts) { account in
            AccountRowView(account: account)
                .contentShape(Rectangle())
                .onTapGesture {
                    onSelect(account)
                }
        }
        .listStyle(.insetGrouped)
    }
}

@available(iOS 26.0, *)
struct AccountRowView: View {
    let account: OtpModel
    
    @State private var currentCode: String = ""
    @State private var timeRemaining: Int = 30
    
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    var body: some View {
        HStack(spacing: 16) {
            // Account icon
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: 44, height: 44)
                
                Text(accountInitial)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.accentColor)
            }
            
            // Account info
            VStack(alignment: .leading, spacing: 4) {
                Text(account.issuer ?? "Unknown")
                    .font(.headline)
                    .foregroundStyle(.primary)
                
                if let name = account.name, !name.isEmpty {
                    Text(name)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            // Code display
            VStack(alignment: .trailing, spacing: 4) {
                Text(formattedCode)
                    .font(.system(.title3, design: .monospaced))
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText())
                
                // Time remaining indicator
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.caption2)
                    Text("\(timeRemaining)s")
                        .font(.caption)
                        .monospacedDigit()
                }
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 8)
        .onAppear {
            updateCode()
            updateTimeRemaining()
        }
        .onReceive(timer) { _ in
            updateCode()
            updateTimeRemaining()
        }
    }
    
    private var accountInitial: String {
        let text = account.issuer ?? account.name ?? "?"
        return String(text.prefix(1)).uppercased()
    }
    
    private var formattedCode: String {
        let code = currentCode
        if code.count == 6 {
            return "\(code.prefix(3)) \(code.suffix(3))"
        } else if code.count == 8 {
            return "\(code.prefix(4)) \(code.suffix(4))"
        }
        return code
    }
    
    private func updateCode() {
        withAnimation(.smooth(duration: 0.3)) {
            currentCode = account.generateCode()
        }
    }
    
    private func updateTimeRemaining() {
        switch account.entry {
        case .totp(_, _, let interval):
            let currentTime = Date().timeIntervalSince1970
            let remaining = Int(interval) - Int(currentTime.truncatingRemainder(dividingBy: interval))
            timeRemaining = remaining
        case .hotp:
            timeRemaining = 0
        }
    }
}

#Preview {
    if #available(iOS 26.0, *) {
        OTPSelectionView(
            accounts: [],
            onSelect: { _ in },
            onCancel: { }
        )
    }
}
