//
//  OTPSelectionView.swift
//  TOTP AutoFill
//
//  Account picker shown by the credential provider.
//

import SwiftUI

struct OTPSelectionView: View {
    let accounts: [OtpModel]
    /// Accounts matching the website being filled; shown first.
    var suggested: [OtpModel] = []
    let onSelect: (OtpModel) -> Void
    let onCancel: () -> Void

    @State private var searchText = ""

    private var others: [OtpModel] {
        let suggestedIDs = Set(suggested.map(\.id))
        return accounts.filter { !suggestedIDs.contains($0.id) && $0.matches(search: searchText) }
    }

    private var filteredSuggested: [OtpModel] {
        suggested.filter { $0.matches(search: searchText) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if accounts.isEmpty {
                    ContentUnavailableView(
                        "No Accounts",
                        systemImage: "lock.shield",
                        description: Text("Add accounts in the TOTP app to use AutoFill.")
                    )
                } else if filteredSuggested.isEmpty && others.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        List {
                            if !filteredSuggested.isEmpty {
                                Section("Suggested") {
                                    rows(filteredSuggested, date: context.date)
                                }
                            }
                            if !others.isEmpty {
                                Section(filteredSuggested.isEmpty ? "Accounts" : "Other Accounts") {
                                    rows(others, date: context.date)
                                }
                            }
                        }
                        #if os(iOS)
                        .listStyle(.insetGrouped)
                        #else
                        .listStyle(.inset)
                        #endif
                    }
                }
            }
            .navigationTitle("Choose Account")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel, action: onCancel)
                }
            }
            .searchable(text: $searchText, prompt: "Search accounts")
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 360)
        #endif
    }

    private func rows(_ accounts: [OtpModel], date: Date) -> some View {
        ForEach(accounts) { account in
            Button {
                onSelect(account)
            } label: {
                AccountRowView(account: account, date: date)
            }
            .buttonStyle(.plain)
        }
    }
}

struct AccountRowView: View {
    let account: OtpModel
    let date: Date

    @ScaledMetric(relativeTo: .headline) private var badgeSize: CGFloat = 40

    var body: some View {
        HStack(spacing: 14) {
            Text(String(account.displayTitle.prefix(1)).uppercased())
                .font(.headline)
                .foregroundStyle(.tint)
                .frame(width: badgeSize, height: badgeSize)
                .background(.tint.opacity(0.15), in: .circle)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(account.displayTitle)
                        .font(.headline)
                    if account.hasPrefix {
                        Image(systemName: "key.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Includes prefix")
                    }
                }
                if let subtitle = account.displaySubtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(account.code(at: date).groupedOTP)
                    .font(.system(.title3, design: .monospaced, weight: .semibold))
                    .contentTransition(.numericText())
                if !account.entry.isHotp {
                    Text("\(account.entry.secondsRemaining(at: date)) s")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    OTPSelectionView(accounts: [], onSelect: { _ in }, onCancel: {})
}
